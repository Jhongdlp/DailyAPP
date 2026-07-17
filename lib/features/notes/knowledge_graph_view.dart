import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/note_model.dart';
import '../../core/models/note_vault_model.dart';
import '../../core/services/knowledge_service.dart';

/// Un nodo del grafo de conocimiento: envuelve una [Note] con su posición
/// física actual dentro de la simulación de fuerzas.
class GraphNode {
  final String id;
  Offset position;
  Offset velocity;
  bool isDragging;
  String title;
  String? vaultId;
  int linkCount;

  GraphNode({
    required this.id,
    required this.position,
    Offset? velocity,
    this.isDragging = false,
    required this.title,
    this.vaultId,
    this.linkCount = 0,
  }) : velocity = velocity ?? Offset.zero;

  double get radius => (22 + 5 * sqrt(linkCount)).clamp(22.0, 48.0);
  bool get isOrphan => linkCount == 0;
}

/// Vista del grafo de conocimiento: layout de fuerzas (repulsión + resortes +
/// gravedad), interactivo (pan/zoom del lienzo, arrastrar nodos, tap para
/// enfocar un nodo con mini-card, long-press para abrir la nota), coloreado
/// por bóveda, con filtro por bóveda, búsqueda por título/significado y
/// **aristas semánticas** descubiertas por embeddings (punteadas) además de
/// los enlaces manuales (sólidas).
///
/// Implementa su propio pan/zoom (en vez de `InteractiveViewer`) porque un
/// `GestureDetector` anidado dentro de `InteractiveViewer` compite de forma
/// poco confiable por el gesto de arrastre de un solo dedo — el
/// reconocedor de escala de `InteractiveViewer` normalmente gana el gesture
/// arena antes de que se pueda desactivar a tiempo. Un único
/// `GestureDetector` de escala que decide él mismo, al iniciar el gesto, si
/// el toque cayó sobre un nodo (y por tanto lo arrastra) o sobre el lienzo
/// (y por tanto hace pan/zoom) evita esa ambigüedad por completo.
class KnowledgeGraphView extends StatefulWidget {
  final List<Note> notes;
  final List<NoteVault> vaults;
  final List<SemanticEdge> semanticEdges;
  final ValueChanged<Note> onOpenNote;
  final void Function(String id1, String id2)? onLinkNotes;
  final Future<List<RelatedNote>> Function(String query)? onSemanticSearch;

  const KnowledgeGraphView({
    super.key,
    required this.notes,
    required this.vaults,
    this.semanticEdges = const [],
    required this.onOpenNote,
    this.onLinkNotes,
    this.onSemanticSearch,
  });

  @override
  State<KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<KnowledgeGraphView>
    with SingleTickerProviderStateMixin {
  static const double _kRepel = 11000;
  static const double _kSpring = 0.03;
  static const double _idealLength = 160;
  // Las aristas semánticas atraen más débil y a mayor distancia: agrupan
  // temas sin colapsar el layout de los enlaces manuales.
  static const double _kSpringSemantic = _kSpring * 0.35;
  static const double _idealLengthSemantic = 230;
  static const double _kGravity = 0.012;
  static const double _damping = 0.88;
  static const double _worldSize = 2400;
  static const double _minScale = 0.35;
  static const double _maxScale = 3.0;
  static const double _kineticEpsilon = 0.6;

  // Valores sentinela del filtro por bóveda
  static const String _kFilterAll = '__all__';
  static const String _kFilterNone = '__none__';

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final Map<String, GraphNode> _nodes = {};
  Map<String, Set<String>> _adjacency = {};
  Map<String, Map<String, double>> _semanticAdjacency = {};
  final _random = Random();

  final Map<String, Widget> _nodeContentCache = {};
  bool _needsCacheRebuild = true;
  String _lastQuery = '';
  String? _lastFocusedNodeId;
  int _lastNodesCount = 0;

  double _scale = 1.0;
  Offset _panOffset = Offset.zero;
  bool _panInitialized = false;

  String? _draggedNodeId;
  Offset _gestureStartLocalFocal = Offset.zero;
  Offset _dragNodeStartPosition = Offset.zero;
  double _scaleAtGestureStart = 1.0;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, double> _semanticMatches = {};
  bool _searchingSemantic = false;

  String _vaultFilter = _kFilterAll;
  String? _focusedNodeId;

  @override
  void initState() {
    super.initState();
    _rebuildGraph();
    _ticker = createTicker(_onTick)..start();
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
          if (q.isEmpty) _semanticMatches = {};
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant KnowledgeGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notes, widget.notes) ||
        !identical(oldWidget.semanticEdges, widget.semanticEdges)) {
      _rebuildGraph();
      _reheat();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Note? _noteById(String id) {
    for (final n in widget.notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  NoteVault? _vaultById(String? id) {
    if (id == null) return null;
    for (final v in widget.vaults) {
      if (v.id == id) return v;
    }
    return null;
  }

  // ─── Construcción / diff del grafo ─────────────────────────

  List<Note> get _filteredNotes {
    if (_vaultFilter == _kFilterAll) return widget.notes;
    if (_vaultFilter == _kFilterNone) {
      return widget.notes.where((n) => n.vaultId == null).toList();
    }
    return widget.notes.where((n) => n.vaultId == _vaultFilter).toList();
  }

  void _rebuildGraph() {
    _needsCacheRebuild = true;
    final notes = _filteredNotes;
    final incomingIds = notes.map((n) => n.id).toSet();
    _nodes.removeWhere((id, _) => !incomingIds.contains(id));
    if (_focusedNodeId != null && !incomingIds.contains(_focusedNodeId)) {
      _focusedNodeId = null;
    }

    final adjacency = <String, Set<String>>{};
    for (final n in notes) {
      adjacency.putIfAbsent(n.id, () => {});
      for (final targetId in n.linkedNoteIds) {
        if (!incomingIds.contains(targetId)) continue;
        adjacency.putIfAbsent(n.id, () => {}).add(targetId);
        adjacency.putIfAbsent(targetId, () => {}).add(n.id);
      }
    }
    _adjacency = adjacency;

    // Aristas semánticas: solo pares visibles y no enlazados manualmente
    final semantic = <String, Map<String, double>>{};
    for (final e in widget.semanticEdges) {
      if (!incomingIds.contains(e.sourceId) ||
          !incomingIds.contains(e.targetId)) {
        continue;
      }
      if (adjacency[e.sourceId]?.contains(e.targetId) ?? false) continue;
      semantic.putIfAbsent(e.sourceId, () => {})[e.targetId] = e.similarity;
      semantic.putIfAbsent(e.targetId, () => {})[e.sourceId] = e.similarity;
    }
    _semanticAdjacency = semantic;

    final center = const Offset(_worldSize / 2, _worldSize / 2);

    for (final note in notes) {
      final manualDegree = adjacency[note.id]?.length ?? 0;
      final semanticDegree = semantic[note.id]?.length ?? 0;
      final degree = manualDegree + semanticDegree;
      final existing = _nodes[note.id];
      if (existing != null) {
        existing.title = note.title;
        existing.vaultId = note.vaultId;
        existing.linkCount = degree;
        continue;
      }

      GraphNode? neighborWithPos;
      for (final nId in adjacency[note.id] ?? const <String>{}) {
        final n = _nodes[nId];
        if (n != null) {
          neighborWithPos = n;
          break;
        }
      }

      final Offset spawn;
      if (neighborWithPos != null) {
        final angle = _random.nextDouble() * 2 * pi;
        spawn = neighborWithPos.position + Offset(cos(angle), sin(angle)) * 80;
      } else {
        final angle = _random.nextDouble() * 2 * pi;
        final dist = _random.nextDouble() * 60;
        spawn = center + Offset(cos(angle), sin(angle)) * dist;
      }

      _nodes[note.id] = GraphNode(
        id: note.id,
        position: spawn,
        title: note.title,
        vaultId: note.vaultId,
        linkCount: degree,
      );
    }
  }

  void _rebuildNodeContentCache() {
    _nodeContentCache.clear();
    final hasQuery = _searchQuery.isNotEmpty;
    final matched = _matchedIds;
    final focusedId = _focusedNodeId;

    for (final node in _nodes.values) {
      final vault = _vaultById(node.vaultId);
      final baseColor = node.isOrphan
          ? BentoTheme.creamAlpha(0.35)
          : (vault?.flutterColor ?? BentoTheme.accentBrain);

      final isMatch = !hasQuery || matched.contains(node.id);

      var opacity = node.isOrphan ? 0.55 : 1.0;
      if (hasQuery && !isMatch) opacity *= 0.28;

      final inFocusSet = focusedId == null ||
          _focusNeighborhood(focusedId).contains(node.id);
      if (!inFocusSet) opacity *= 0.15;

      final isFocused = node.id == focusedId;
      final borderColor = isFocused
          ? BentoTheme.accentBrain
          : (hasQuery && isMatch && !node.isOrphan)
              ? BentoTheme.accentBrain
              : baseColor;

      _nodeContentCache[node.id] = Opacity(
        key: ValueKey('node-opacity-${node.id}'),
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BentoTheme.darkCardAlt,
            border: Border.all(
              color: borderColor,
              width: isFocused ? 3.5 : (hasQuery && isMatch) ? 3 : 2,
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Text(
            node.title.length > 16
                ? '${node.title.substring(0, 15)}…'
                : node.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: node.isOrphan
                  ? BentoTheme.creamAlpha(0.6)
                  : BentoTheme.cream,
            ),
          ),
        ),
      );
    }
  }

  void _reheat() {
    _lastElapsed = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  // ─── Simulación de fuerzas ──────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) _lastElapsed = elapsed;
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    final ids = _nodes.keys.toList();
    if (ids.isEmpty) {
      _ticker.stop();
      return;
    }

    final forces = <String, Offset>{for (final id in ids) id: Offset.zero};
    final center = const Offset(_worldSize / 2, _worldSize / 2);

    // Repulsión entre todo par de nodos.
    for (int i = 0; i < ids.length; i++) {
      final a = _nodes[ids[i]]!;
      for (int j = i + 1; j < ids.length; j++) {
        final b = _nodes[ids[j]]!;
        var delta = a.position - b.position;
        var dist = delta.distance;
        if (dist < 1) {
          delta = Offset(_random.nextDouble() - 0.5, _random.nextDouble() - 0.5);
          dist = delta.distance.clamp(0.01, double.infinity);
        }
        final minDist = a.radius + b.radius;
        final d = max(dist, minDist);
        final force = _kRepel / (d * d);
        final dir = delta / dist;
        forces[a.id] = forces[a.id]! + dir * force;
        forces[b.id] = forces[b.id]! - dir * force;
      }
    }

    // Resortes solo entre nodos adyacentes (cada arista una sola vez).
    for (final id in ids) {
      final neighbors = _adjacency[id];
      if (neighbors == null) continue;
      final a = _nodes[id]!;
      for (final nId in neighbors) {
        if (nId.compareTo(id) <= 0) continue;
        final b = _nodes[nId];
        if (b == null) continue;
        final delta = b.position - a.position;
        final dist = max(delta.distance, 0.01);
        final force = _kSpring * (dist - _idealLength);
        final dir = delta / dist;
        forces[a.id] = forces[a.id]! + dir * force;
        forces[nId] = forces[nId]! - dir * force;
      }
    }

    // Resortes semánticos (más débiles y largos), ponderados por similitud.
    for (final entry in _semanticAdjacency.entries) {
      final a = _nodes[entry.key];
      if (a == null) continue;
      for (final semEntry in entry.value.entries) {
        if (semEntry.key.compareTo(entry.key) <= 0) continue;
        final b = _nodes[semEntry.key];
        if (b == null) continue;
        final delta = b.position - a.position;
        final dist = max(delta.distance, 0.01);
        final force =
            _kSpringSemantic * semEntry.value * (dist - _idealLengthSemantic);
        final dir = delta / dist;
        forces[a.id] = forces[a.id]! + dir * force;
        forces[semEntry.key] = forces[semEntry.key]! - dir * force;
      }
    }

    // Gravedad débil hacia el centro del "mundo".
    for (final id in ids) {
      final node = _nodes[id]!;
      forces[id] = forces[id]! + (center - node.position) * _kGravity;
    }

    double kinetic = 0;
    for (final id in ids) {
      final node = _nodes[id]!;
      if (node.isDragging) continue;
      node.velocity = (node.velocity + forces[id]! * dt) * _damping;
      node.position += node.velocity * dt;
      kinetic += node.velocity.distanceSquared;
    }

    setState(() {});

    if (kinetic < _kineticEpsilon && _draggedNodeId == null) {
      _ticker.stop();
    }
  }

  // ─── Gestos unificados: pan/zoom del lienzo o arrastre de nodo ───

  GraphNode? _hitTest(Offset worldPoint) {
    for (final node in _nodes.values.toList().reversed) {
      if ((node.position - worldPoint).distance <= node.radius) return node;
    }
    return null;
  }

  Offset _toWorld(Offset local) => (local - _panOffset) / _scale;

  void _onScaleStart(ScaleStartDetails details) {
    _scaleAtGestureStart = _scale;
    _gestureStartLocalFocal = details.localFocalPoint;

    if (details.pointerCount == 1) {
      final hit = _hitTest(_toWorld(details.localFocalPoint));
      if (hit != null) {
        _draggedNodeId = hit.id;
        _dragNodeStartPosition = hit.position;
        hit.isDragging = true;
        hit.velocity = Offset.zero;
        return;
      }
    }
    _draggedNodeId = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_draggedNodeId != null) {
      final node = _nodes[_draggedNodeId];
      if (node == null) return;
      final worldDelta =
          (details.localFocalPoint - _gestureStartLocalFocal) / _scale;
      setState(() {
        node.position = _dragNodeStartPosition + worldDelta;
      });
      return;
    }

    setState(() {
      _scale = (_scaleAtGestureStart * details.scale).clamp(_minScale, _maxScale);
      _panOffset += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_draggedNodeId == null) return;
    final node = _nodes[_draggedNodeId];
    node?.isDragging = false;
    _draggedNodeId = null;
    _reheat();
  }

  /// Tap (sin movimiento): enfocar/desenfocar nodo, o salir del focus si se
  /// toca el lienzo vacío. Se usa un TapGestureRecognizer explícito porque el
  /// ScaleGestureRecognizer no dispara start/end para taps estacionarios.
  void _onTapUp(TapUpDetails details) {
    final hit = _hitTest(_toWorld(details.localPosition));
    setState(() {
      if (hit == null) {
        _focusedNodeId = null;
      } else {
        // Tap sobre el nodo ya enfocado → desenfocar; si no → enfocar
        _focusedNodeId = _focusedNodeId == hit.id ? null : hit.id;
      }
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final hit = _hitTest(_toWorld(details.localPosition));
    if (hit == null) return;
    final note = _noteById(hit.id);
    if (note != null) widget.onOpenNote(note);
  }

  // ─── Búsqueda semántica ─────────────────────────────────────

  Future<void> _runSemanticSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || widget.onSemanticSearch == null) return;
    setState(() => _searchingSemantic = true);
    try {
      final results = await widget.onSemanticSearch!(query);
      if (!mounted) return;
      setState(() {
        _semanticMatches = {for (final r in results) r.id: r.similarity};
      });
    } finally {
      if (mounted) setState(() => _searchingSemantic = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_needsCacheRebuild ||
        _lastQuery != _searchQuery ||
        _lastFocusedNodeId != _focusedNodeId ||
        _lastNodesCount != _nodes.length) {
      _needsCacheRebuild = false;
      _lastQuery = _searchQuery;
      _lastFocusedNodeId = _focusedNodeId;
      _lastNodesCount = _nodes.length;
      _rebuildNodeContentCache();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterAndSearch(),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!_panInitialized && constraints.maxWidth > 0) {
                  final viewportCenter =
                      Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
                  _panOffset = viewportCenter -
                      const Offset(_worldSize / 2, _worldSize / 2) * _scale;
                  _panInitialized = true;
                }
                return Container(
                  color: BentoTheme.darkCard,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: _onTapUp,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          onLongPressStart: _onLongPressStart,
                          child: Transform(
                            transform: Matrix4.identity()
                              ..translateByDouble(_panOffset.dx, _panOffset.dy, 0, 1)
                              ..scaleByDouble(_scale, _scale, 1, 1),
                            // OverflowBox: sin esto, las restricciones ajustadas
                            // del viewport fuerzan al "mundo" al tamaño de la
                            // pantalla y el Stack recorta todos los nodos
                            // (posicionados alrededor de worldSize/2) → grafo
                            // vacío. alignment topLeft alinea el origen del
                            // mundo con el origen del Transform.
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: _worldSize,
                              maxWidth: _worldSize,
                              minHeight: _worldSize,
                              maxHeight: _worldSize,
                              child: RepaintBoundary(
                                child: SizedBox(
                                  key: const ValueKey('graph-world'),
                                  width: _worldSize,
                                  height: _worldSize,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _EdgePainter(
                                            nodes: _nodes,
                                            adjacency: _adjacency,
                                            semanticAdjacency: _semanticAdjacency,
                                            highlightedIds: _matchedIds,
                                            hasQuery: _searchQuery.isNotEmpty,
                                            focusedId: _focusedNodeId,
                                          ),
                                        ),
                                      ),
                                      for (final node in _nodes.values)
                                        _buildNodeWidget(node),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_nodes.isEmpty)
                        Center(
                          child: Text(
                            'No hay notas en este filtro',
                            style: TextStyle(
                              color: BentoTheme.creamSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (_focusedNodeId != null) _buildFocusCard(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Set<String> get _matchedIds {
    if (_searchQuery.isEmpty) return {};
    final byTitle = _nodes.values
        .where((n) => n.title.toLowerCase().contains(_searchQuery))
        .map((n) => n.id)
        .toSet();
    return {...byTitle, ..._semanticMatches.keys.where(_nodes.containsKey)};
  }

  Set<String> _focusNeighborhood(String id) {
    return {
      id,
      ...?_adjacency[id],
      ...?_semanticAdjacency[id]?.keys,
    };
  }

  Widget _buildNodeWidget(GraphNode node) {
    final d = node.radius * 2;
    var cached = _nodeContentCache[node.id];
    if (cached == null) {
      _rebuildNodeContentCache();
      cached = _nodeContentCache[node.id] ?? const SizedBox.shrink();
    }

    return Positioned(
      key: ValueKey('node-pos-${node.id}'),
      left: node.position.dx - node.radius,
      top: node.position.dy - node.radius,
      width: d,
      height: d,
      child: cached,
    );
  }

  // ─── Mini-card del nodo enfocado ─────────────────────────────

  Widget _buildFocusCard() {
    final note = _noteById(_focusedNodeId!);
    if (note == null) return const SizedBox.shrink();
    final node = _nodes[note.id];
    final vault = _vaultById(note.vaultId);
    final color = vault?.flutterColor ?? BentoTheme.accentBrain;
    final manualCount = _adjacency[note.id]?.length ?? 0;

    // Sugerencias semánticas del nodo enfocado, más similares primero
    final suggestions = (_semanticAdjacency[note.id]?.entries.toList() ?? [])
      ..sort((a, b) => b.value.compareTo(a.value));

    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BentoTheme.darkCardAlt.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Sin título' : note.title,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _focusedNodeId = null),
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: BentoTheme.creamSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _infoChip(Icons.link_rounded,
                    '$manualCount ${manualCount == 1 ? 'vínculo' : 'vínculos'}',
                    BentoTheme.accentPurple),
                if (vault != null)
                  _infoChip(vault.iconData ?? Icons.folder_rounded, vault.name, color),
                if (node != null && suggestions.isNotEmpty)
                  _infoChip(Icons.auto_awesome_outlined,
                      '${suggestions.length} sugeridas', BentoTheme.accentBrain),
              ],
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in suggestions.take(6))
                      _suggestionChip(note.id, s.key, s.value),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () => widget.onOpenNote(note),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BentoTheme.accentBrain,
                  foregroundColor: const Color(0xFF0C0C0D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Abrir nota',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chip de sugerencia semántica con acción "vincular": convierte la arista
  /// punteada (descubierta por IA) en un enlace manual sólido.
  Widget _suggestionChip(String focusedId, String targetId, double similarity) {
    final target = _noteById(targetId);
    if (target == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: widget.onLinkNotes == null
          ? null
          : () {
              widget.onLinkNotes!(focusedId, targetId);
              // El provider actualizará widget.notes y la arista pasará a manual
            },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: BentoTheme.accentBrain.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BentoTheme.accentBrain.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_link_rounded,
                size: 14, color: BentoTheme.accentBrain),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                target.title.isEmpty ? 'Sin título' : target.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: BentoTheme.cream,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${(similarity * 100).round()}%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: BentoTheme.accentBrain.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // ─── Filtros y búsqueda ─────────────────────────────────────

  Widget _buildFilterAndSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _runSemanticSearch(),
            textInputAction: TextInputAction.search,
            style: TextStyle(color: BentoTheme.cream, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar... (Enter = por significado)',
              hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
              prefixIcon: Icon(Icons.search, size: 18, color: BentoTheme.creamSecondary),
              suffixIcon: _searchingSemantic
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BentoTheme.accentBrain,
                        ),
                      ),
                    )
                  : (_semanticMatches.isNotEmpty
                      ? Icon(Icons.auto_awesome,
                          size: 16, color: BentoTheme.accentBrain)
                      : null),
              filled: true,
              fillColor: BentoTheme.darkCardAlt,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: BentoTheme.creamAlpha(0.20)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: BentoTheme.creamAlpha(0.20)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: BentoTheme.accentBrain, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(_kFilterAll, BentoTheme.accentBrain, 'Todas'),
                for (final vault in widget.vaults)
                  _filterChip(vault.id, vault.flutterColor, vault.name),
                _filterChip(_kFilterNone, BentoTheme.creamAlpha(0.5), 'Sin clasificar'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String filterId, Color color, String label) {
    final selected = _vaultFilter == filterId;
    return GestureDetector(
      onTap: () {
        if (_vaultFilter == filterId) return;
        setState(() {
          _vaultFilter = filterId;
          _focusedNodeId = null;
          _rebuildGraph();
        });
        _reheat();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.16)
              : BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : BentoTheme.creamAlpha(0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? BentoTheme.cream : BentoTheme.creamSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dibuja las aristas entre notas: sólidas para enlaces manuales, punteadas
/// (con alpha proporcional a la similitud) para las conexiones semánticas
/// descubiertas por embeddings — capa barata debajo de los widgets de nodo.
class _EdgePainter extends CustomPainter {
  final Map<String, GraphNode> nodes;
  final Map<String, Set<String>> adjacency;
  final Map<String, Map<String, double>> semanticAdjacency;
  final Set<String> highlightedIds;
  final bool hasQuery;
  final String? focusedId;

  _EdgePainter({
    required this.nodes,
    required this.adjacency,
    required this.semanticAdjacency,
    required this.highlightedIds,
    required this.hasQuery,
    this.focusedId,
  });

  bool _isDim(String a, String b) {
    if (focusedId != null && a != focusedId && b != focusedId) return true;
    if (hasQuery && !(highlightedIds.contains(a) && highlightedIds.contains(b))) {
      return true;
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final manualPaint = Paint()
      ..color = BentoTheme.accentBrain.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final manualFadedPaint = Paint()
      ..color = BentoTheme.accentBrain.withValues(alpha: 0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Aristas manuales: línea sólida
    for (final entry in adjacency.entries) {
      final a = nodes[entry.key];
      if (a == null) continue;
      for (final targetId in entry.value) {
        if (targetId.compareTo(entry.key) <= 0) continue;
        final b = nodes[targetId];
        if (b == null) continue;
        final dim = _isDim(entry.key, targetId);
        canvas.drawLine(
            a.position, b.position, dim ? manualFadedPaint : manualPaint);
      }
    }

    // Aristas semánticas: línea punteada púrpura, alpha según similitud
    for (final entry in semanticAdjacency.entries) {
      final a = nodes[entry.key];
      if (a == null) continue;
      for (final semEntry in entry.value.entries) {
        if (semEntry.key.compareTo(entry.key) <= 0) continue;
        final b = nodes[semEntry.key];
        if (b == null) continue;

        final dim = _isDim(entry.key, semEntry.key);
        // Similitud 0.55 → alpha ~0.25; similitud 0.9 → alpha ~0.65
        final alpha = dim ? 0.06 : (0.25 + (semEntry.value - 0.55) * 1.15)
            .clamp(0.15, 0.65)
            .toDouble();
        final paint = Paint()
          ..color = BentoTheme.accentPurple.withValues(alpha: alpha)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke;
        _drawDashedLine(canvas, a.position, b.position, paint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashLength = 7.0;
    const gapLength = 6.0;
    final delta = to - from;
    final distance = delta.distance;
    if (distance < 1) return;
    final dir = delta / distance;
    var covered = 0.0;
    while (covered < distance) {
      final segEnd = min(covered + dashLength, distance);
      canvas.drawLine(from + dir * covered, from + dir * segEnd, paint);
      covered = segEnd + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) {
    if (oldDelegate.hasQuery != hasQuery ||
        oldDelegate.focusedId != focusedId ||
        oldDelegate.highlightedIds.length != highlightedIds.length ||
        oldDelegate.nodes.length != nodes.length) {
      return true;
    }
    for (final id in highlightedIds) {
      if (!oldDelegate.highlightedIds.contains(id)) return true;
    }
    for (final entry in nodes.entries) {
      final oldNode = oldDelegate.nodes[entry.key];
      if (oldNode == null || oldNode.position != entry.value.position) {
        return true;
      }
    }
    return false;
  }
}
