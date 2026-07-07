import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/note_model.dart';
import '../../core/models/note_vault_model.dart';

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
/// abrir la nota, long-press para vista previa), coloreado por bóveda, con
/// leyenda y búsqueda.
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
  final ValueChanged<Note> onOpenNote;

  const KnowledgeGraphView({
    super.key,
    required this.notes,
    required this.vaults,
    required this.onOpenNote,
  });

  @override
  State<KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<KnowledgeGraphView>
    with SingleTickerProviderStateMixin {
  static const double _kRepel = 11000;
  static const double _kSpring = 0.03;
  static const double _idealLength = 160;
  static const double _kGravity = 0.012;
  static const double _damping = 0.88;
  static const double _worldSize = 2400;
  static const double _minScale = 0.35;
  static const double _maxScale = 3.0;
  static const double _kineticEpsilon = 0.6;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final Map<String, GraphNode> _nodes = {};
  Map<String, Set<String>> _adjacency = {};
  final _random = Random();

  double _scale = 1.0;
  Offset _panOffset = Offset.zero;
  bool _panInitialized = false;

  String? _draggedNodeId;
  Offset _gestureStartLocalFocal = Offset.zero;
  Offset _dragNodeStartPosition = Offset.zero;
  double _scaleAtGestureStart = 1.0;
  double _totalGestureMovement = 0;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _rebuildGraph(widget.notes);
    _ticker = createTicker(_onTick)..start();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void didUpdateWidget(covariant KnowledgeGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notes, widget.notes)) {
      _rebuildGraph(widget.notes);
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

  void _rebuildGraph(List<Note> notes) {
    final incomingIds = notes.map((n) => n.id).toSet();
    _nodes.removeWhere((id, _) => !incomingIds.contains(id));

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

    final center = Offset(_worldSize / 2, _worldSize / 2);

    for (final note in notes) {
      final degree = adjacency[note.id]?.length ?? 0;
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
    final center = Offset(_worldSize / 2, _worldSize / 2);

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
    _totalGestureMovement = 0;
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
    _totalGestureMovement += details.focalPointDelta.distance;

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
    final wasTap = _totalGestureMovement < 6;
    node?.isDragging = false;
    _draggedNodeId = null;
    _reheat();
    if (wasTap && node != null) {
      final note = _noteById(node.id);
      if (note != null) widget.onOpenNote(note);
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final hit = _hitTest(_toWorld(details.localPosition));
    if (hit == null) return;
    final note = _noteById(hit.id);
    if (note != null) _showNotePreviewSheet(note, hit);
  }

  void _showNotePreviewSheet(Note note, GraphNode node) {
    final vault = _vaultById(node.vaultId);
    final color = vault?.flutterColor ?? BentoTheme.accentBrain;
    final snippet = _stripMarkdownSnippet(note.content);

    showModalBottomSheet(
      context: context,
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: BentoTheme.creamAlpha(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
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
                      note.title,
                      style: GoogleFonts.montserrat(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (snippet.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  snippet,
                  style: TextStyle(color: BentoTheme.creamSecondary, fontSize: 13, height: 1.4),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  _previewChip(Icons.link_rounded, '${node.linkCount} ${node.linkCount == 1 ? 'vínculo' : 'vínculos'}', BentoTheme.accentPurple),
                  if (vault != null)
                    _previewChip(vault.iconData ?? Icons.folder_rounded, vault.name, color),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onOpenNote(note);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BentoTheme.accentBrain,
                    foregroundColor: const Color(0xFF0C0C0D),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Abrir nota'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  String _stripMarkdownSnippet(String text) {
    return text
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLegendAndSearch(),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!_panInitialized && constraints.maxWidth > 0) {
                  final viewportCenter =
                      Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
                  _panOffset = viewportCenter -
                      Offset(_worldSize / 2, _worldSize / 2) * _scale;
                  _panInitialized = true;
                }
                return Container(
                  color: BentoTheme.darkCard,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    onLongPressStart: _onLongPressStart,
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translateByDouble(_panOffset.dx, _panOffset.dy, 0, 1)
                        ..scaleByDouble(_scale, _scale, 1, 1),
                      child: SizedBox(
                        width: _worldSize,
                        height: _worldSize,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _EdgePainter(
                                  nodes: _nodes,
                                  adjacency: _adjacency,
                                  highlightedIds: _matchedIds,
                                  hasQuery: _searchQuery.isNotEmpty,
                                ),
                              ),
                            ),
                            for (final node in _nodes.values) _buildNodeWidget(node),
                          ],
                        ),
                      ),
                    ),
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
    return _nodes.values
        .where((n) => n.title.toLowerCase().contains(_searchQuery))
        .map((n) => n.id)
        .toSet();
  }

  Widget _buildNodeWidget(GraphNode node) {
    final vault = _vaultById(node.vaultId);
    final baseColor = node.isOrphan
        ? BentoTheme.creamAlpha(0.35)
        : (vault?.flutterColor ?? BentoTheme.accentBrain);

    final hasQuery = _searchQuery.isNotEmpty;
    final isMatch = !hasQuery || _matchedIds.contains(node.id);
    final opacity = node.isOrphan ? 0.55 : 1.0;
    final finalOpacity = hasQuery ? (isMatch ? opacity : opacity * 0.28) : opacity;

    final d = node.radius * 2;
    return Positioned(
      left: node.position.dx - node.radius,
      top: node.position.dy - node.radius,
      width: d,
      height: d,
      child: Opacity(
        opacity: finalOpacity,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BentoTheme.darkCardAlt,
            border: Border.all(
              color: (hasQuery && isMatch && !node.isOrphan)
                  ? BentoTheme.accentBrain
                  : baseColor,
              width: (hasQuery && isMatch) ? 3 : 2,
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Text(
            node.title.length > 16 ? '${node.title.substring(0, 15)}…' : node.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: node.isOrphan ? BentoTheme.creamAlpha(0.6) : BentoTheme.cream,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendAndSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: BentoTheme.cream, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar en el grafo...',
              hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
              prefixIcon: Icon(Icons.search, size: 18, color: BentoTheme.creamSecondary),
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
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: BentoTheme.accentBrain, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 26,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final vault in widget.vaults) _legendChip(vault.flutterColor, vault.name),
                _legendChip(BentoTheme.accentBrain, 'Sin clasificar'),
                _legendChip(BentoTheme.creamAlpha(0.35), 'Huérfanas'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendChip(Color color, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BentoTheme.darkCardAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BentoTheme.creamAlpha(0.15)),
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
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BentoTheme.creamSecondary)),
        ],
      ),
    );
  }
}

/// Dibuja únicamente las aristas (líneas) entre notas vinculadas — capa
/// barata debajo de los widgets de nodo, sin necesidad de hit-testing.
class _EdgePainter extends CustomPainter {
  final Map<String, GraphNode> nodes;
  final Map<String, Set<String>> adjacency;
  final Set<String> highlightedIds;
  final bool hasQuery;

  _EdgePainter({
    required this.nodes,
    required this.adjacency,
    required this.highlightedIds,
    required this.hasQuery,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()
      ..color = BentoTheme.accentBrain.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fadedPaint = Paint()
      ..color = BentoTheme.accentBrain.withValues(alpha: 0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final entry in adjacency.entries) {
      final a = nodes[entry.key];
      if (a == null) continue;
      for (final targetId in entry.value) {
        if (targetId.compareTo(entry.key) <= 0) continue;
        final b = nodes[targetId];
        if (b == null) continue;

        final dim = hasQuery &&
            !(highlightedIds.contains(entry.key) && highlightedIds.contains(targetId));
        canvas.drawLine(a.position, b.position, dim ? fadedPaint : dimPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => true;
}
