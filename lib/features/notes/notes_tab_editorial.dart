import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../core/models/achievement_catalog.dart';
import '../../core/models/note_model.dart';
import '../../core/models/note_vault_model.dart';
import '../../core/providers/notes_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/providers/vaults_provider.dart';
import '../../core/services/knowledge_service.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../vault/screens/vault_home_screen.dart';
import '../vault/screens/vault_lock_screen.dart';
import 'knowledge_graph_view.dart';
import 'notion_editor.dart';
import 'voice_recorder_sheet.dart';
import 'dart:io';
import 'vault_image_widgets.dart';

/// Pestaña de Notas en el sistema editorial.
///
/// Mismo mapa que la versión neumórfica —bóvedas → lista → editor, más el grafo
/// y la carpeta segura por arrastre—, recompuesto entero en papel sobre lienzo.
/// Cuál de las dos se monta lo decide `designLanguageProvider`; ver
/// [DesignLanguage]. Las dos comparten providers, así que se puede alternar sin
/// migrar nada: lo único que cambia es quién pinta.
///
/// Las reglas que sostienen la composición, todas heredadas de la pestaña de
/// Hábitos para que los dos sistemas se lean como uno:
///
///  1. **El lienzo es el fondo y el papel es el contenido.** Una bóveda, una
///     nota y una hoja modal son la misma lámina blanca; lo que las separa es
///     el tamaño y la posición, nunca una sombra ni un borde.
///  2. **El color aparece una sola vez por pieza.** El de la bóveda vive en su
///     glifo (es identidad) y el de la prioridad en el filete izquierdo de la
///     fila (es significado). En cuanto un color se repite en dos sitios de la
///     misma tarjeta deja de señalar y pasa a decorar.
///  3. **Nada se invierte al tocarlo.** Una lista que alterna láminas blancas y
///     negras cambia de peso a cada interacción. El estado se dice con tinta,
///     no con inversión.
///
/// Dos piezas se reutilizan tal cual y no son editoriales: [NotionEditor] y
/// [KnowledgeGraphView]. Son componentes grandes con su propia interacción
/// (bloques arrastrables, física de grafo) y rehacerlos es un trabajo aparte;
/// acá viven dentro del marco editorial, sobre la superficie de [BentoTheme]
/// contra la que fueron diseñados. Ver [_editorBody].
class NotesTabEditorial extends ConsumerStatefulWidget {
  const NotesTabEditorial({super.key});

  @override
  ConsumerState<NotesTabEditorial> createState() => _NotesTabEditorialState();
}

enum _View { vaults, list, editor, graph }

class _NotesTabEditorialState extends ConsumerState<NotesTabEditorial>
    with TickerProviderStateMixin {
  _View _view = _View.vaults;
  NoteVault? _vault;
  Note? _editing;

  // ─── Carpeta segura: arrastre desde arriba ───
  //
  // Se conserva el gesto oculto de la versión anterior. La pieza que asoma
  // detrás cambia de material (un escalón de luminosidad sobre el lienzo en vez
  // de una tarjeta con borde), pero los números del gesto son los mismos: si se
  // tocan, la memoria muscular de quien ya lo usa deja de funcionar.

  /// A partir de acá el candado empieza a revelarse.
  static const double _pullReveal = 70;

  /// Y acá se dispara el desbloqueo.
  static const double _pullTrigger = 135;

  /// Tope del arrastre. La lámina no sigue al dedo más allá.
  static const double _pullMax = 160;

  late final AnimationController _pullCtrl;
  double _pull = 0;
  double _dragStartY = 0;
  bool _dragging = false;
  bool _unlocking = false;
  bool _biometricsRunning = false;
  final ScrollController _vaultsScroll = ScrollController();

  // ─── Editor ───
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _preview = false;
  List<String> _links = [];
  NotePriority _priority = NotePriority.normal;
  DateTime? _remindAt;
  bool _selfDestruct = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  int? _rangeHour;
  int? _rangeMinute;
  bool _suggesting = false;
  List<RelatedNote> _suggestions = const [];

  // ─── Búsqueda y grafo ───
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<SemanticEdge> _edges = const [];

  @override
  void initState() {
    super.initState();
    _pullCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() => setState(() => _pull = _pullCtrl.value * _pullMax));
  }

  @override
  void dispose() {
    _pullCtrl.dispose();
    _vaultsScroll.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────── navegación ───────────────────────────

  void _goToVaults() => setState(() {
        _view = _View.vaults;
        _vault = null;
        _editing = null;
        _searching = false;
        _searchCtrl.clear();
      });

  void _openVault(NoteVault? vault) => setState(() {
        _vault = vault;
        _view = _View.list;
        _searching = false;
        _searchCtrl.clear();
      });

  void _openEditor(Note note) => setState(() {
        _editing = note;
        _view = _View.editor;
        _titleCtrl.text = note.title;
        _contentCtrl.text = note.content;
        _links = List<String>.from(note.linkedNoteIds);
        _priority = note.priority;
        _remindAt = note.remindAt;
        _selfDestruct = note.selfDestruct;
        _rangeStart = note.reminderStartDate;
        _rangeEnd = note.reminderEndDate;
        _rangeHour = note.reminderHour;
        _rangeMinute = note.reminderMinute;
        _suggestions = const [];
        _preview = false;
      });

  /// Abre el grafo con el caché primero y el servidor después: así se pinta al
  /// instante y se refresca solo cuando llegan datos frescos.
  void _openGraph() {
    setState(() => _view = _View.graph);
    final service = ref.read(knowledgeServiceProvider);
    service.cachedEdges().then((cached) {
      if (mounted && cached.isNotEmpty && _edges.isEmpty) {
        setState(() => _edges = cached);
      }
    });
    service.fetchEdges().then((fresh) {
      if (mounted) setState(() => _edges = fresh);
    }).catchError((_) {
      // Sin red el grafo sigue sirviendo: caché + enlaces manuales.
    });
  }

  // ─────────────────────────── carpeta segura ───────────────────────────

  void _resetPull() {
    if (!mounted) return;
    setState(() {
      _biometricsRunning = false;
      _unlocking = false;
      _pullCtrl.value = 0;
    });
  }

  void _pushSecureScreen(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _resetPull());
  }

  Future<void> _triggerSecureVault() async {
    if (_biometricsRunning || _unlocking) return;
    setState(() {
      _unlocking = true;
      _biometricsRunning = true;
    });

    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}

    // El candado gira mientras tanto: sin esta pausa el salto a la pantalla de
    // bloqueo es tan seco que no se entiende qué disparó el gesto.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    try {
      if (!ref.read(vaultProvider).isSetup) {
        _pushSecureScreen(const VaultLockScreen());
        return;
      }
      final ok = await ref.read(vaultProvider.notifier).unlockWithBiometrics();
      if (!mounted) return;
      _pushSecureScreen(ok ? const VaultHomeScreen() : const VaultLockScreen());
    } catch (_) {
      // Cualquier fallo cae en la pantalla de bloqueo, que siempre sabe
      // pedir la contraseña de respaldo.
      if (mounted) _pushSecureScreen(const VaultLockScreen());
    }
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EditorialTheme.canvas,
      child: Stack(
        children: [
          Positioned.fill(
            child: switch (_view) {
              _View.vaults => _vaultsScreen(),
              _View.list => _listScreen(),
              _View.editor => _editorScreen(),
              _View.graph => _graphScreen(),
            },
          ),
          if (_view == _View.vaults || _view == _View.list)
            Positioned(
              right: EditorialTheme.margin,
              bottom: 104,
              child: EditorialCircleButton(
                icon: Icons.add,
                tooltip: 'Nueva nota',
                size: 54,
                onTap: _showNewNoteSheet,
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────── pantalla 1: bóvedas ───────────────────────────

  Widget _vaultsScreen() {
    final vaults = ref.watch(vaultsProvider);
    final notes = ref.watch(notesProvider);

    final translation = _pull.clamp(0.0, _pullMax);
    // El radio y el filete de la lámina crecen con los primeros 40px del
    // arrastre. Sin esa interpolación, la esquina aparece de golpe y el gesto
    // se lee como un corte en vez de como algo que se despega.
    final lift = (translation / 40).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _vaultsHeader(notes.length),
        Expanded(
          child: Stack(
            children: [
              if (translation > 0)
                Positioned(top: 0, left: 0, right: 0, child: _securePortal()),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, translation),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: EditorialTheme.canvas,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(lift * EditorialTheme.radiusPanel),
                      ),
                    ),
                    child: Listener(
                      onPointerDown: (e) {
                        _dragStartY = e.position.dy;
                        _dragging = false;
                      },
                      onPointerMove: (e) {
                        final delta = e.position.dy - _dragStartY;
                        final offset =
                            _vaultsScroll.hasClients ? _vaultsScroll.offset : 0.0;
                        if (offset > 0 || delta <= 0) return;
                        _dragging = true;
                        _pullCtrl.value = (delta / _pullMax).clamp(0.0, 1.0);
                        if (_pull >= _pullTrigger) _triggerSecureVault();
                      },
                      onPointerUp: (_) => _releasePull(),
                      onPointerCancel: (_) => _releasePull(),
                      child: ListView(
                        controller: _vaultsScroll,
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(
                          EditorialTheme.margin,
                          6,
                          EditorialTheme.margin,
                          140,
                        ),
                        children: [
                          _unvaultedRow(notes),
                          const SizedBox(height: 26),
                          if (vaults.isEmpty)
                            _emptyVaults()
                          else ...[
                            const EditorialSectionLabel('Bóvedas'),
                            const SizedBox(height: 12),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: EditorialTheme.gutter,
                                crossAxisSpacing: EditorialTheme.gutter,
                                childAspectRatio: 1.02,
                              ),
                              itemCount: vaults.length,
                              itemBuilder: (_, i) => _vaultCard(vaults[i], notes),
                            ),
                          ],
                          const SizedBox(height: 34),
                          _pullHint(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _releasePull() {
    if (_dragging && !_unlocking) {
      _pullCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuad,
      );
    }
    _dragging = false;
  }

  /// Lo que asoma detrás de la lámina al tirar hacia abajo.
  ///
  /// Es una superficie, no una tarjeta: [EditorialTheme.surface] es un escalón
  /// de luminosidad sobre el lienzo, así que se separa sola sin necesitar el
  /// borde que llevaba la versión anterior.
  Widget _securePortal() {
    final progress =
        ((_pull - _pullReveal) / (_pullTrigger - _pullReveal)).clamp(0.0, 1.0);
    final ready = progress >= 1;

    return Container(
      height: 150,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 26),
      decoration: const BoxDecoration(
        color: EditorialTheme.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EditorialTheme.radiusPanel),
        ),
      ),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _unlocking ? null : progress,
              strokeWidth: 1.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                EditorialTheme.paperAlpha(_unlocking ? 0.85 : 0.15 + progress * 0.6),
              ),
            ),
            AnimatedRotation(
              turns: _unlocking ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Icon(
                _unlocking
                    ? Icons.hourglass_empty_rounded
                    : (ready ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                size: 20,
                color: EditorialTheme.paperAlpha(
                  _unlocking ? 0.9 : 0.3 + progress * 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vaultsHeader(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        10,
        EditorialTheme.margin,
        18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SEGUNDO\nCEREBRO',
                  style: EditorialTheme.caps(
                    34,
                    color: EditorialTheme.paper,
                    letterSpacing: -1.0,
                    height: 0.94,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  total == 1 ? '1 NOTA GUARDADA' : '$total NOTAS GUARDADAS',
                  style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              EditorialCircleButton(
                icon: Icons.hub_outlined,
                tooltip: 'Grafo de conocimiento',
                onTap: _openGraph,
              ),
              const SizedBox(height: 8),
              EditorialCircleButton(
                icon: Icons.create_new_folder_outlined,
                tooltip: 'Nueva bóveda',
                onTap: () => _showVaultSheet(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Sin clasificar" va como fila ancha y no como una celda más de la
  /// cuadrícula: no es una bóveda que el usuario creó, es el resto. Darle la
  /// misma forma que a las demás la convertiría en una carpeta que no se puede
  /// borrar ni renombrar.
  Widget _unvaultedRow(List<Note> notes) {
    final count = notes.where((n) => n.vaultId == null).length;

    return EditorialPressable(
      onTap: () => _openVault(null),
      scale: 0.985,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: Row(
          children: [
            _vaultGlyph(null, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin clasificar',
                    style: EditorialTheme.text(
                      16,
                      weight: FontWeight.w600,
                      color: EditorialTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _noteCount(count),
                    style: EditorialTheme.text(13, color: EditorialTheme.grayText),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 18, color: EditorialTheme.inkAlpha(0.35)),
          ],
        ),
      ),
    );
  }

  Widget _vaultCard(NoteVault vault, List<Note> notes) {
    final count = notes.where((n) => n.vaultId == vault.id).length;
    final hasImage = vault.imagePath != null && vault.imagePath!.isNotEmpty;

    return EditorialPressable(
      onTap: () => _openVault(vault),
      onLongPress: () => _showVaultOptions(vault),
      scale: 0.96,
      child: Container(
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          child: Stack(
            children: [
              // Background Image
              if (hasImage)
                Positioned.fill(
                  child: VaultImageWidget(vault: vault, fit: BoxFit.contain),
                ),

              // Top Protection Gradient for maximum text readability & contrast
              if (hasImage)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.72),
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.48, 0.95],
                      ),
                    ),
                  ),
                ),

              // Content Overlay
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (vault.showIcon) ...[
                          Container(
                            padding: hasImage ? const EdgeInsets.all(3) : EdgeInsets.zero,
                            decoration: hasImage
                                ? BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.40),
                                    borderRadius: BorderRadius.circular(6),
                                  )
                                : null,
                            child: _vaultGlyph(vault, size: 16),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            vault.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: EditorialTheme.text(
                              16,
                              weight: FontWeight.w600,
                              color: hasImage ? Colors.white : EditorialTheme.ink,
                            ).copyWith(
                              shadows: hasImage
                                  ? const [
                                      Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1.5)),
                                      Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 2)),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (vault.description != null && vault.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        vault.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EditorialTheme.text(
                          12.5,
                          color: hasImage
                              ? Colors.white.withValues(alpha: 0.88)
                              : EditorialTheme.grayText,
                        ).copyWith(
                          shadows: hasImage
                              ? const [
                                  Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1.5)),
                                  Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 2)),
                                ]
                              : null,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _noteCount(count).toUpperCase(),
                      style: EditorialTheme.label(
                        10,
                        color: hasImage
                            ? Colors.white.withValues(alpha: 0.80)
                            : EditorialTheme.grayText,
                      ).copyWith(
                        shadows: hasImage
                            ? const [
                                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1.5)),
                                Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 2)),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyVaults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'Todavía no hay bóvedas',
          style: EditorialTheme.text(
            20,
            weight: FontWeight.w600,
            color: EditorialTheme.paper,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Una bóveda agrupa notas por tema. Sin ellas todo cae en "Sin clasificar", que también sirve.',
          style: EditorialTheme.text(15, color: EditorialTheme.muted, height: 1.35),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: EditorialPressable(
            onTap: () => _showVaultSheet(),
            scale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: EditorialTheme.paper,
                borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
              ),
              child: Text(
                'Crear la primera',
                style: EditorialTheme.text(
                  14,
                  weight: FontWeight.w600,
                  color: EditorialTheme.ink,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pullHint() {
    return Opacity(
      opacity: 0.45,
      child: Column(
        children: [
          Icon(Icons.keyboard_arrow_up_rounded,
              size: 22, color: EditorialTheme.muted),
          const SizedBox(height: 2),
          Text(
            'ARRASTRA DESDE ARRIBA PARA LA CARPETA SEGURA',
            textAlign: TextAlign.center,
            style: EditorialTheme.label(9.5, color: EditorialTheme.muted),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── pantalla 2: lista ───────────────────────────

  Widget _listScreen() {
    final all = ref.watch(notesProvider);
    final mine = _vault == null
        ? all.where((n) => n.vaultId == null).toList()
        : all.where((n) => n.vaultId == _vault!.id).toList();

    final query = _searchCtrl.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? mine
        : mine
            .where((n) =>
                n.title.toLowerCase().contains(query) ||
                n.content.toLowerCase().contains(query))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _listHeader(mine.length),
        Expanded(
          child: shown.isEmpty
              ? _emptyList(query.isNotEmpty)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    EditorialTheme.margin,
                    4,
                    EditorialTheme.margin,
                    140,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _noteRow(shown[i]),
                  ),
                ),
        ),
      ],
    );
  }

  /// Cabecera de la lista. El nombre de la bóveda ocupa el lugar del título de
  /// la portada: es la misma jerarquía un nivel más adentro, y por eso va en
  /// caps grandes y no en una barra de navegación con el nombre en 17px.
  Widget _listHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        6,
        EditorialTheme.margin,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EditorialPressable(
                onTap: _goToVaults,
                scale: 0.88,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                  child: Icon(Icons.arrow_back,
                      size: 20, color: EditorialTheme.paperAlpha(0.7)),
                ),
              ),
              _vaultGlyph(_vault, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  (_vault?.name ?? 'Sin clasificar').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTheme.label(11, color: EditorialTheme.muted),
                ),
              ),
              EditorialCircleButton(
                icon: _searching ? Icons.close : Icons.search,
                tooltip: _searching ? 'Cerrar búsqueda' : 'Buscar',
                size: 36,
                onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _searchCtrl.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _noteCount(count).toUpperCase(),
            style: EditorialTheme.caps(
              30,
              color: EditorialTheme.paper,
              letterSpacing: -0.9,
              height: 1.0,
            ),
          ),
          if (_searching) ...[
            const SizedBox(height: 14),
            // El buscador es de papel aunque viva sobre el lienzo: es donde se
            // escribe, y en este sistema todo lo que recibe texto es papel.
            EditorialField(
              controller: _searchCtrl,
              hint: 'Buscar en estas notas…',
              autofocus: true,
              onChanged: (_) => setState(() {}),
              prefix: Icon(Icons.search, size: 18, color: EditorialTheme.grayText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyList(bool filtered) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 20, EditorialTheme.margin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filtered ? 'Nada coincide' : 'Bóveda vacía',
            style: EditorialTheme.text(
              20,
              weight: FontWeight.w600,
              color: EditorialTheme.paper,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Ninguna nota de aquí contiene eso.'
                : 'Toca el botón de abajo para escribir la primera.',
            style: EditorialTheme.text(15, color: EditorialTheme.muted, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// Fila de nota: lámina de papel con un filete de prioridad a la izquierda.
  ///
  /// El filete es el único sitio con color de toda la fila, y sólo aparece
  /// cuando la prioridad no es "normal": pintar las cuatro convierte la lista en
  /// un semáforo donde lo urgente deja de destacar. Ver [_priorityTone].
  Widget _noteRow(Note note) {
    final tone = _priorityTone(note.priority);
    final reminder = note.remindAt;

    return Dismissible(
      key: ValueKey('editorial_note_${note.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: _destructive,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: Icon(Icons.delete_outline, color: EditorialTheme.paper, size: 22),
      ),
      onDismissed: (_) {
        ref.read(notesProvider.notifier).deleteNote(note.id);
        showEditorialSnack(context, 'Nota eliminada');
      },
      child: EditorialPressable(
        onTap: () => _openEditor(note),
        scale: 0.985,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tone != null) SizedBox(width: 4, child: ColoredBox(color: tone)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(tone != null ? 13 : 16, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title.isEmpty ? 'Sin título' : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EditorialTheme.text(
                            16,
                            weight: FontWeight.w600,
                            color: EditorialTheme.ink,
                          ),
                        ),
                        if (note.content.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _stripMarkdown(note.content),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: EditorialTheme.text(
                              13.5,
                              color: EditorialTheme.grayText,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (reminder != null ||
                            note.hasRangeReminder ||
                            note.linkedNoteIds.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (reminder != null)
                                _tag(
                                  note.selfDestruct
                                      ? Icons.local_fire_department_outlined
                                      : Icons.notifications_none_rounded,
                                  _formatReminder(reminder),
                                  strong: note.isReminderPending,
                                ),
                              if (note.hasRangeReminder)
                                _tag(Icons.date_range_outlined, 'Rango',
                                    strong: note.isReminderPending),
                              if (note.linkedNoteIds.isNotEmpty)
                                _tag(Icons.link_rounded,
                                    '${note.linkedNoteIds.length}'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Etiqueta de dato dentro de una lámina. Gris apagada por defecto; en tinta
  /// cuando el dato está vivo (un recordatorio que todavía va a sonar).
  Widget _tag(IconData icon, String text, {bool strong = false}) {
    final color = strong ? EditorialTheme.ink : EditorialTheme.grayText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EditorialTheme.gray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: EditorialTheme.text(11.5, weight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── pantalla 3: editor ───────────────────────────

  Widget _editorScreen() {
    return Column(
      children: [
        _editorChrome(),
        Expanded(child: _preview ? _previewPage() : _editorBody()),
      ],
    );
  }

  Widget _editorChrome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 6, 14, 12),
      child: Row(
        children: [
          EditorialPressable(
            onTap: () {
              _saveEditor(silent: true);
              setState(() => _view = _View.list);
            },
            scale: 0.88,
            child: Padding(
              padding: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
              child: Icon(Icons.arrow_back,
                  size: 20, color: EditorialTheme.paperAlpha(0.7)),
            ),
          ),
          Expanded(
            child: Text(
              (_vault?.name ?? 'Sin clasificar').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorialTheme.label(11, color: EditorialTheme.muted),
            ),
          ),
          EditorialCircleButton(
            icon: _preview ? Icons.edit_outlined : Icons.visibility_outlined,
            tooltip: _preview ? 'Volver a editar' : 'Vista previa',
            size: 36,
            onTap: () => setState(() => _preview = !_preview),
          ),
          const SizedBox(width: 8),
          EditorialCircleButton(
            icon: Icons.tune_rounded,
            tooltip: 'Propiedades de la nota',
            size: 36,
            onTap: _showPropertiesSheet,
          ),
          const SizedBox(width: 8),
          EditorialCircleButton(
            icon: Icons.check,
            tooltip: 'Guardar',
            size: 36,
            onTap: _saveEditor,
          ),
        ],
      ),
    );
  }

  /// El editor de bloques, tal cual.
  ///
  /// Se apoya sobre [BentoTheme.darkBg] —el fondo del modo activo— y no sobre
  /// el lienzo editorial. No es una concesión estética sino de contraste:
  /// [NotionEditor] escribe con los colores de BentoTheme, que se invierten con
  /// el modo claro/oscuro, mientras que el lienzo editorial es oscuro siempre.
  /// Sobre el lienzo, un usuario en modo claro vería tinta oscura sobre fondo
  /// oscuro. Dándole su propia superficie, el bloque de escritura queda
  /// coherente consigo mismo y se lee como la hoja donde se escribe.
  Widget _editorBody() {
    return ColoredBox(
      color: BentoTheme.darkBg,
      child: NotionEditor(
        key: ValueKey(_editing?.id ?? 'new'),
        titleController: _titleCtrl,
        contentController: _contentCtrl,
        accentColor: _vault?.flutterColor ?? BentoTheme.accentBrain,
        allNotes: ref.watch(notesProvider),
        currentNoteId: _editing?.id,
        onLinkNote: _onWikilinkSelected,
      ),
    );
  }

  void _onWikilinkSelected(String targetId) {
    if (_editing == null) return;
    setState(() {
      if (!_links.contains(targetId)) _links.add(targetId);
    });
    ref.read(notesProvider.notifier).linkNotes(_editing!.id, targetId);
  }

  /// Vista previa: la nota como página impresa.
  ///
  /// Acá sí manda el sistema editorial, porque leer es lo que el sistema sabe
  /// hacer. La página es una lámina de papel con márgenes anchos y la tinta
  /// cálida de [EditorialTheme]; el título va en caps grandes y un filete lo
  /// separa del cuerpo, como una portadilla.
  Widget _previewPage() {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        0,
        EditorialTheme.margin,
        140,
      ),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
          decoration: BoxDecoration(
            color: EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (title.isEmpty ? 'Sin título' : title).toUpperCase(),
                style: EditorialTheme.caps(
                  28,
                  color: EditorialTheme.ink,
                  letterSpacing: -0.8,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 16),
              const EditorialRule(),
              const SizedBox(height: 18),
              MarkdownBody(
                data: content.isEmpty
                    ? '_Sin contenido todavía._'
                    : content,
                styleSheet: _previewStyles(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  MarkdownStyleSheet _previewStyles() => MarkdownStyleSheet(
        h1: EditorialTheme.caps(24, color: EditorialTheme.ink, height: 1.2),
        h2: EditorialTheme.caps(20, color: EditorialTheme.ink, height: 1.25),
        h3: EditorialTheme.text(17,
            weight: FontWeight.w700, color: EditorialTheme.ink, height: 1.3),
        p: EditorialTheme.text(15.5,
            color: EditorialTheme.inkAlpha(0.88), height: 1.6),
        strong: EditorialTheme.text(15.5,
            weight: FontWeight.w700, color: EditorialTheme.ink, height: 1.6),
        em: EditorialTheme.text(15.5,
            color: EditorialTheme.inkAlpha(0.88), height: 1.6)
            .copyWith(fontStyle: FontStyle.italic),
        listBullet: EditorialTheme.text(15.5, color: EditorialTheme.grayText),
        code: EditorialTheme.text(13.5, color: EditorialTheme.ink).copyWith(
          fontFamily: 'monospace',
          backgroundColor: EditorialTheme.gray,
        ),
        codeblockDecoration: BoxDecoration(
          color: EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        blockquote: EditorialTheme.text(15,
            color: EditorialTheme.grayText, height: 1.55),
        blockquoteDecoration: BoxDecoration(
          color: EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: EditorialTheme.grayStrong)),
        ),
        tableHead: EditorialTheme.text(14,
            weight: FontWeight.w700, color: EditorialTheme.ink),
        tableBody: EditorialTheme.text(14, color: EditorialTheme.inkAlpha(0.85)),
        tableBorder: TableBorder.all(color: EditorialTheme.grayStrong, width: 1),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );

  // ─────────────────────────── pantalla 4: grafo ───────────────────────────

  Widget _graphScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 6, 14, 14),
          child: Row(
            children: [
              EditorialPressable(
                onTap: _goToVaults,
                scale: 0.88,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                  child: Icon(Icons.arrow_back,
                      size: 20, color: EditorialTheme.paperAlpha(0.7)),
                ),
              ),
              Expanded(
                child: Text(
                  'GRAFO',
                  style: EditorialTheme.caps(
                    30,
                    color: EditorialTheme.paper,
                    letterSpacing: -0.9,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              EditorialTheme.margin,
              0,
              EditorialTheme.margin,
              100,
            ),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Superficie y no papel: el grafo dibuja nodos claros y aristas
              // finas, y sobre blanco desaparecerían.
              color: EditorialTheme.surface,
              borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
            ),
            child: KnowledgeGraphView(
              notes: ref.watch(notesProvider),
              vaults: ref.watch(vaultsProvider),
              semanticEdges: _edges,
              onOpenNote: _openEditor,
              onLinkNotes: (a, b) =>
                  ref.read(notesProvider.notifier).linkNotes(a, b),
              onSemanticSearch: (query) =>
                  ref.read(knowledgeServiceProvider).semanticSearch(query),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── hoja: nueva nota ───────────────────────────

  void _showNewNoteSheet() {
    final titleCtrl = TextEditingController();
    var vault = _vault;
    var priority = NotePriority.normal;
    final vaults = ref.read(vaultsProvider);

    showEditorialSheet<void>(
      context: context,
      title: 'Nueva nota',
      builder: (sheetContext, setSheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            EditorialField(
              controller: titleCtrl,
              hint: 'Título de la nota',
              autofocus: true,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 22),
            const EditorialSectionLabel('Dónde va'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                EditorialChoice(
                  label: 'Sin clasificar',
                  icon: Icons.description_outlined,
                  selected: vault == null,
                  compact: true,
                  onTap: () => setSheet(() => vault = null),
                ),
                for (final v in vaults)
                  EditorialChoice(
                    label: v.name,
                    icon: v.iconData ?? Icons.folder_rounded,
                    selected: vault?.id == v.id,
                    compact: true,
                    onTap: () => setSheet(() => vault = v),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const EditorialSectionLabel('Prioridad'),
            const SizedBox(height: 10),
            _priorityPicker(priority, (p) => setSheet(() => priority = p)),
            const SizedBox(height: 26),
            EditorialButton(
              label: 'Crear nota',
              icon: Icons.add,
              onTap: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.of(sheetContext).pop();
                final note = await ref.read(notesProvider.notifier).addNote(
                      title,
                      '',
                      vaultId: vault?.id,
                      priority: priority,
                    );
                if (!mounted) return;
                setState(() => _vault = vault);
                _openEditor(note);
              },
            ),
            const SizedBox(height: 8),
            EditorialButton(
              label: 'Grabar voz',
              icon: Icons.mic_none_rounded,
              ghost: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showVoiceSheet(vault, priority);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityPicker(NotePriority current, ValueChanged<NotePriority> onPick) {
    return Row(
      children: [
        for (final p in NotePriority.values) ...[
          Expanded(
            child: EditorialChoice(
              label: p.label,
              icon: p.icon,
              compact: true,
              selected: current == p,
              accent: _priorityTone(p),
              onTap: () => onPick(p),
            ),
          ),
          if (p != NotePriority.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  void _showVoiceSheet(NoteVault? vault, NotePriority priority) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceRecorderSheet(
        onTranscribed: (text, tags) async {
          final now = DateTime.now();
          final stamp =
              '${now.day}/${now.month} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          final content = tags.isEmpty ? text : '$text\n\n${tags.join(' ')}';

          final note = await ref.read(notesProvider.notifier).addNote(
                'Nota de voz — $stamp',
                content,
                vaultId: vault?.id,
                priority: priority,
              );

          final reward = ref.read(rpgProvider.notifier).gainXpAndGold(
                5,
                2,
                counterKeys: const [RpgCounters.notes],
              );
          if (!mounted) return;
          AchievementToast.show(context, reward['unlocked']);
          setState(() => _vault = vault);
          _openEditor(note);
        },
      ),
    );
  }

  // ─────────────────────── hoja: propiedades de la nota ───────────────────────

  void _showPropertiesSheet() {
    StateSetter? refreshSheet;
    _suggesting = true;
    _suggestions = const [];
    _loadSuggestions().whenComplete(() {
      _suggesting = false;
      if (!mounted) return;
      setState(() {});
      try {
        refreshSheet?.call(() {});
      } catch (_) {
        // La hoja ya se cerró.
      }
    });

    final others =
        ref.read(notesProvider).where((n) => n.id != _editing?.id).toList();

    showEditorialSheet<void>(
      context: context,
      title: 'Propiedades',
      builder: (sheetContext, setSheet) {
        refreshSheet = setSheet;

        /// Los campos del editor viven en el State de la pestaña, no en la
        /// hoja: al guardar, `_saveEditor` los lee de ahí. Por eso cada cambio
        /// se aplica en los dos sitios — sin el `setState` externo, cerrar la
        /// hoja perdería la elección.
        void apply(VoidCallback change) {
          setState(change);
          setSheet(() {});
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const EditorialSectionLabel('Prioridad'),
              const SizedBox(height: 10),
              _priorityPicker(_priority, (p) => apply(() => _priority = p)),
              const SizedBox(height: 22),

              const EditorialSectionLabel('Recordatorio'),
              const SizedBox(height: 10),
              EditorialRow(
                icon: Icons.notifications_none_rounded,
                label: _remindAt == null
                    ? 'Sin recordatorio'
                    : _formatReminder(_remindAt!),
                active: _remindAt != null,
                trailing: Icon(
                  _remindAt == null ? Icons.chevron_right : Icons.edit_calendar_outlined,
                  size: 16,
                  color: EditorialTheme.grayText,
                ),
                onTap: () async {
                  final picked = await _pickReminder(_remindAt);
                  apply(() {
                    _remindAt = picked;
                    if (picked == null) _selfDestruct = false;
                  });
                },
              ),
              if (_remindAt != null) ...[
                const SizedBox(height: 8),
                EditorialRow(
                  icon: Icons.local_fire_department_outlined,
                  label: _selfDestruct
                      ? 'Se borra sola al vencer'
                      : 'Borrarse sola al vencer',
                  active: _selfDestruct,
                  accent: _priorityHigh,
                  trailing: Switch.adaptive(
                    value: _selfDestruct,
                    activeThumbColor: EditorialTheme.paper,
                    activeTrackColor: _priorityHigh,
                    onChanged: (v) => apply(() => _selfDestruct = v),
                  ),
                  onTap: () => apply(() => _selfDestruct = !_selfDestruct),
                ),
              ],
              const SizedBox(height: 22),

              const EditorialSectionLabel('Repetir en un rango'),
              const SizedBox(height: 10),
              EditorialRow(
                icon: Icons.date_range_outlined,
                label: _formatRange(),
                active: _rangeStart != null,
                trailing: _rangeStart == null
                    ? Icon(Icons.chevron_right, size: 16, color: EditorialTheme.grayText)
                    : EditorialPressable(
                        onTap: () => apply(() {
                          _rangeStart = null;
                          _rangeEnd = null;
                          _rangeHour = null;
                          _rangeMinute = null;
                        }),
                        scale: 0.85,
                        child: Icon(Icons.close, size: 16, color: _destructive),
                      ),
                onTap: () => _pickRange(apply),
              ),
              const SizedBox(height: 22),

              EditorialSectionLabel(
                'Conectar con otras notas',
                trailing: Text(
                  '${_links.length}',
                  style: EditorialTheme.text(
                    12,
                    weight: FontWeight.w600,
                    color: EditorialTheme.grayText,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (others.isEmpty)
                Text(
                  'Todavía no hay otras notas con las que conectar.',
                  style: EditorialTheme.text(13, color: EditorialTheme.grayText),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final other in others)
                      EditorialChoice(
                        label: other.title.isEmpty ? 'Sin título' : other.title,
                        icon: _links.contains(other.id)
                            ? Icons.link_rounded
                            : Icons.add_link_rounded,
                        compact: true,
                        selected: _links.contains(other.id),
                        onTap: () => apply(() {
                          if (!_links.remove(other.id)) _links.add(other.id);
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 22),

              EditorialSectionLabel(
                'Sugeridas por parecido',
                trailing: _suggesting
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: EditorialTheme.grayText,
                        ),
                      )
                    : EditorialPressable(
                        onTap: () async {
                          setSheet(() => _suggesting = true);
                          await _loadSuggestions();
                          if (mounted) setSheet(() => _suggesting = false);
                        },
                        scale: 0.85,
                        child: Icon(Icons.refresh,
                            size: 16, color: EditorialTheme.grayText),
                      ),
              ),
              const SizedBox(height: 10),
              if (!_suggesting && _suggestions.isEmpty)
                Text(
                  'Nada parecido por ahora. Las conexiones aparecen solas a medida '
                  'que guardas notas con contenido.',
                  style: EditorialTheme.text(
                    13,
                    color: EditorialTheme.grayText,
                    height: 1.45,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _suggestions)
                      EditorialChoice(
                        label:
                            '${s.title.isEmpty ? 'Sin título' : s.title}  ·  ${(s.similarity * 100).round()}%',
                        icon: _links.contains(s.id)
                            ? Icons.link_rounded
                            : Icons.add_link_rounded,
                        compact: true,
                        selected: _links.contains(s.id),
                        onTap: () => apply(() {
                          if (!_links.remove(s.id)) _links.add(s.id);
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 28),

              EditorialButton(
                label: 'Eliminar nota',
                icon: Icons.delete_outline,
                tone: _destructive,
                onTap: () async {
                  final note = _editing;
                  if (note == null) return;
                  Navigator.of(sheetContext).pop();
                  final ok = await confirmEditorial(
                    context,
                    title: 'ELIMINAR NOTA',
                    body: 'Se borra "${note.title}" y sus enlaces. No se puede deshacer.',
                  );
                  if (!ok || !mounted) return;
                  setState(() => _view = _View.list);
                  ref.read(notesProvider.notifier).deleteNote(note.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────── hojas: bóveda ───────────────────────────

  void _showVaultOptions(NoteVault vault) {
    showEditorialSheet<void>(
      context: context,
      title: vault.name,
      builder: (sheetContext, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorialRow(
              icon: Icons.edit_outlined,
              label: 'Editar bóveda',
              active: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showVaultSheet(vault: vault);
              },
            ),
            const SizedBox(height: 8),
            EditorialRow(
              icon: Icons.delete_outline,
              label: 'Eliminar bóveda',
              active: true,
              accent: _destructive,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await confirmEditorial(
                  context,
                  title: 'ELIMINAR BÓVEDA',
                  body: 'Las notas de dentro pasan a "Sin clasificar". '
                      'La bóveda no se puede recuperar.',
                );
                if (!ok || !mounted) return;
                ref.read(vaultsProvider.notifier).deleteVault(vault.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVaultSheet({NoteVault? vault}) {
    final nameCtrl = TextEditingController(text: vault?.name ?? '');
    final descCtrl = TextEditingController(text: vault?.description ?? '');
    var iconKey = vault?.icon ?? 'folder';
    var colorHex = vault?.color ?? vaultColorOptions.first;

    var showIcon = vault?.showIcon ?? true;
    String? currentImagePath = vault?.imagePath;
    var imageOffsetX = vault?.imageOffsetX ?? 0.0;
    var imageOffsetY = vault?.imageOffsetY ?? 0.0;
    var imageScale = vault?.imageScale ?? 1.0;
    File? newImageFile;
    var clearImage = false;

    showEditorialSheet<void>(
      context: context,
      title: vault == null ? 'Nueva bóveda' : 'Editar bóveda',
      builder: (sheetContext, setSheet) {
        final tone = EditorialTheme.accentAt(_hexColor(colorHex), 0.54);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              EditorialField(
                controller: nameCtrl,
                hint: 'Nombre — Personal, Ideas, Trabajo…',
                autofocus: vault == null,
              ),
              const SizedBox(height: 8),
              EditorialField(
                controller: descCtrl,
                hint: 'Descripción (opcional)',
              ),
              const SizedBox(height: 22),
              const EditorialSectionLabel('Ícono'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in vaultIconKeyOptions)
                    EditorialPressable(
                      onTap: () => setSheet(() => iconKey = key),
                      scale: 0.9,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: iconKey == key
                              ? EditorialTheme.ink
                              : EditorialTheme.gray,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          vaultIconMap[key],
                          size: 20,
                          color: iconKey == key
                              ? EditorialTheme.paper
                              : EditorialTheme.grayText,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const EditorialSectionLabel('Color'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final hex in vaultColorOptions)
                    EditorialPressable(
                      onTap: () => setSheet(() => colorHex = hex),
                      scale: 0.85,
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: EditorialTheme.accentAt(_hexColor(hex), 0.54),
                          shape: BoxShape.circle,
                        ),
                        child: colorHex == hex
                            ? Icon(Icons.check,
                                size: 16, color: EditorialTheme.paper)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              EditorialRow(
                icon: Icons.visibility_outlined,
                label: 'Mostrar Ícono en Tarjeta',
                active: showIcon,
                accent: tone,
                trailing: Switch.adaptive(
                  value: showIcon,
                  activeThumbColor: EditorialTheme.paper,
                  activeTrackColor: tone,
                  onChanged: (v) => setSheet(() => showIcon = v),
                ),
                onTap: () => setSheet(() => showIcon = !showIcon),
              ),
              const SizedBox(height: 22),
              if (currentImagePath != null && !clearImage) ...[
                const EditorialSectionLabel('Foto de Portada'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EditorialTheme.gray,
                    borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: EditorialTheme.inkAlpha(0.12)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: VaultRawImage(path: currentImagePath!, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Portada activa',
                              style: EditorialTheme.text(13, weight: FontWeight.w600, color: EditorialTheme.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Zoom: ${imageScale.toStringAsFixed(1)}x',
                              style: EditorialTheme.text(11, color: EditorialTheme.grayText),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final res = await showVaultCoverPickerDialog(
                            context: sheetContext,
                            currentImagePath: currentImagePath,
                            initialOffsetX: imageOffsetX,
                            initialOffsetY: imageOffsetY,
                            initialScale: imageScale,
                            initialFile: newImageFile,
                            vaultName: nameCtrl.text,
                            vaultDescription: descCtrl.text,
                            vaultIcon: iconKey,
                            vaultColor: colorHex,
                            showIcon: showIcon,
                            noteCount: vault?.noteCount ?? 0,
                            isEditorial: true,
                          );
                          if (res != null) {
                            setSheet(() {
                              if (res.clearImage) {
                                clearImage = true;
                                newImageFile = null;
                                currentImagePath = null;
                              } else {
                                clearImage = false;
                                currentImagePath = res.imagePath;
                                newImageFile = res.newFile;
                                imageOffsetX = res.offsetX;
                                imageOffsetY = res.offsetY;
                                imageScale = res.scale;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.tune_rounded, size: 14),
                        label: const Text('Ajustar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tone,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: BentoTheme.errorRed, size: 20),
                        tooltip: 'Quitar imagen',
                        onPressed: () {
                          setSheet(() {
                            clearImage = true;
                            newImageFile = null;
                            currentImagePath = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final res = await showVaultCoverPickerDialog(
                      context: sheetContext,
                      currentImagePath: currentImagePath,
                      initialOffsetX: imageOffsetX,
                      initialOffsetY: imageOffsetY,
                      initialScale: imageScale,
                      initialFile: newImageFile,
                      vaultName: nameCtrl.text,
                      vaultDescription: descCtrl.text,
                      vaultIcon: iconKey,
                      vaultColor: colorHex,
                      showIcon: showIcon,
                      noteCount: vault?.noteCount ?? 0,
                      isEditorial: true,
                    );
                    if (res != null) {
                      setSheet(() {
                        if (res.clearImage) {
                          clearImage = true;
                          newImageFile = null;
                          currentImagePath = null;
                        } else {
                          clearImage = false;
                          currentImagePath = res.imagePath;
                          newImageFile = res.newFile;
                          imageOffsetX = res.offsetX;
                          imageOffsetY = res.offsetY;
                          imageScale = res.scale;
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.image_outlined, size: 16, color: EditorialTheme.ink),
                  label: Text('Subir foto de portada', style: TextStyle(color: EditorialTheme.ink)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: EditorialTheme.gray),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              // Vista previa: la misma tarjeta que va a aparecer en la portada.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
                ),
                child: Row(
                  children: [
                    if (showIcon) ...[
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: EditorialTheme.paper,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(vaultIconMap[iconKey], size: 19, color: tone),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        nameCtrl.text.trim().isEmpty
                            ? 'Sin nombre'
                            : nameCtrl.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EditorialTheme.text(
                          16,
                          weight: FontWeight.w600,
                          color: EditorialTheme.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              EditorialButton(
                label: vault == null ? 'Crear bóveda' : 'Guardar cambios',
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final description =
                      descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();
                  Navigator.of(sheetContext).pop();

                  final notifier = ref.read(vaultsProvider.notifier);
                  if (vault == null) {
                    await notifier.createVault(
                      name,
                      icon: iconKey,
                      color: colorHex,
                      description: description,
                      showIcon: showIcon,
                      imagePath: currentImagePath,
                      imageOffsetX: imageOffsetX,
                      imageOffsetY: imageOffsetY,
                      imageScale: imageScale,
                      uploadFile: newImageFile,
                    );
                  } else {
                    final updated = await notifier.updateVault(
                      vault.id,
                      name: name,
                      icon: iconKey,
                      color: colorHex,
                      description: description,
                      showIcon: showIcon,
                      imagePath: currentImagePath,
                      imageOffsetX: imageOffsetX,
                      imageOffsetY: imageOffsetY,
                      imageScale: imageScale,
                      uploadFile: newImageFile,
                      clearImage: clearImage,
                    );
                    if (mounted && _vault?.id == vault.id && updated != null) {
                      _vault = updated;
                    }
                  }
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────── guardar y recordatorios ───────────────────────────

  /// [silent] para el guardado automático al salir con la flecha: ahí el aviso
  /// sobra, porque salir ya es la confirmación de que terminaste.
  void _saveEditor({bool silent = false}) {
    final note = _editing;
    final title = _titleCtrl.text.trim();
    if (note == null || title.isEmpty) return;

    ref.read(notesProvider.notifier).updateNote(
          note.id,
          title,
          _contentCtrl.text.trim(),
          _links,
          priority: _priority,
          remindAt: _remindAt,
          clearRemindAt: _remindAt == null,
          selfDestruct: _selfDestruct && _remindAt != null,
          vaultId: note.vaultId,
          reminderStartDate: _rangeStart,
          reminderEndDate: _rangeEnd,
          reminderHour: _rangeHour,
          reminderMinute: _rangeMinute,
          clearRangeReminder: _rangeStart == null,
        );

    if (!silent) showEditorialSnack(context, 'Nota guardada');
  }

  /// Notas parecidas por embeddings. Si la nota todavía no tiene el suyo
  /// (recién creada, o el servidor de IA estaba caído al guardarla), se embebe
  /// el texto actual como consulta.
  Future<void> _loadSuggestions() async {
    final service = ref.read(knowledgeServiceProvider);
    final id = _editing?.id;

    var results = <RelatedNote>[];
    if (id != null) results = await service.relatedTo(id);

    if (results.isEmpty) {
      final text =
          '${_titleCtrl.text.trim()}\n\n${_contentCtrl.text.trim()}'.trim();
      if (text.isNotEmpty) {
        results = await service.semanticSearch(
          text,
          threshold: KnowledgeService.relatedThreshold,
          count: 8,
          excludeId: id,
        );
      }
    }
    _suggestions = results.where((r) => r.id != id).toList();
  }

  /// Selector de recordatorio: atajos primero, calendario al final.
  ///
  /// El orden no es casual. Casi todos los recordatorios de una nota son "en un
  /// rato" o "mañana"; obligar a pasar por un calendario para eso es el camino
  /// largo al caso frecuente.
  Future<DateTime?> _pickReminder(DateTime? current) async {
    final now = DateTime.now();
    DateTime? result;

    final tonight = DateTime(now.year, now.month, now.day, 20);
    final tomorrow =
        DateTime(now.year, now.month, now.day, 8).add(const Duration(days: 1));

    await showEditorialSheet<void>(
      context: context,
      title: '¿Cuándo te aviso?',
      maxHeightFactor: 0.7,
      builder: (sheetContext, _) {
        Widget preset(String label, IconData icon, DateTime when) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EditorialRow(
                icon: icon,
                label: label,
                active: true,
                trailing: Text(
                  _formatReminder(when),
                  style: EditorialTheme.text(12.5, color: EditorialTheme.grayText),
                ),
                onTap: () {
                  result = when;
                  Navigator.of(sheetContext).pop();
                },
              ),
            );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              preset('En 1 hora', Icons.hourglass_bottom,
                  now.add(const Duration(hours: 1))),
              preset('En 3 horas', Icons.hourglass_top,
                  now.add(const Duration(hours: 3))),
              if (tonight.isAfter(now))
                preset('Esta noche', Icons.nights_stay_outlined, tonight),
              preset('Mañana temprano', Icons.wb_sunny_outlined, tomorrow),
              EditorialRow(
                icon: Icons.edit_calendar_outlined,
                label: 'Elegir fecha y hora',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: current ?? now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    builder: _editorialPickerTheme,
                  );
                  if (date == null || !mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(current ?? now),
                    builder: _editorialPickerTheme,
                  );
                  if (time == null) return;
                  result = DateTime(
                      date.year, date.month, date.day, time.hour, time.minute);
                },
              ),
              if (current != null) ...[
                const SizedBox(height: 16),
                EditorialButton(
                  label: 'Quitar recordatorio',
                  icon: Icons.notifications_off_outlined,
                  ghost: true,
                  tone: _destructive,
                  onTap: () {
                    result = null;
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );

    return result;
  }

  /// [apply] escribe en el State de la pestaña y refresca la hoja abierta a la
  /// vez; ver la nota en [_showPropertiesSheet].
  Future<void> _pickRange(void Function(VoidCallback) apply) async {
    final now = DateTime.now();

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _rangeStart != null && _rangeEnd != null
          ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
          : null,
      builder: _editorialPickerTheme,
    );
    if (range == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _rangeHour != null && _rangeMinute != null
          ? TimeOfDay(hour: _rangeHour!, minute: _rangeMinute!)
          : TimeOfDay.fromDateTime(now),
      builder: _editorialPickerTheme,
    );
    if (time == null) return;

    apply(() {
      _rangeStart = range.start;
      _rangeEnd = range.end;
      _rangeHour = time.hour;
      _rangeMinute = time.minute;
      // Un rango y un recordatorio único a la vez programarían dos avisos que
      // se pisan; el rango gana porque es el que se acaba de elegir.
      _remindAt = null;
    });
  }

  /// Los pickers de Material no se pueden recomponer, así que al menos se les
  /// pasa la paleta editorial: papel, tinta y el gris de relleno.
  Widget _editorialPickerTheme(BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: EditorialTheme.ink,
            onPrimary: EditorialTheme.paper,
            surface: EditorialTheme.paper,
            onSurface: EditorialTheme.ink,
          ),
        ),
        child: child!,
      );

  // ─────────────────────────── helpers ───────────────────────────

  /// Color del acento de una prioridad, o null si no lleva.
  ///
  /// "Normal" no tiene color a propósito: es el valor por defecto de casi todas
  /// las notas, y pintarlo convertiría el filete en una raya decorativa que
  /// aparece siempre. Sin él, ver una raya significa algo.
  Color? _priorityTone(NotePriority priority) => switch (priority) {
        NotePriority.low => EditorialTheme.grayStrong,
        NotePriority.normal => null,
        NotePriority.high => _priorityHigh,
        NotePriority.urgent => _destructive,
      };

  /// Ámbar y rojo fijos, no los acentos del tema.
  ///
  /// La paleta personalizable existe para las pestañas; estos dos son
  /// significado, no estilo — "esto quema" y "esto destruye" tienen que decir lo
  /// mismo con cualquier paleta elegida. Salen de la misma máquina OKLCh que el
  /// resto del sistema editorial, a la lightness del papel.
  static final Color _priorityHigh =
      EditorialTheme.accentAt(const Color(0xFFF4A261), 0.60);
  static final Color _destructive =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.52);

  Color _hexColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF758BFD);
    }
  }

  /// Glifo de bóveda, normalizado al sistema.
  ///
  /// El color crudo que eligió el usuario pasa por [EditorialTheme.accentAt]:
  /// esa paleta se armó para el diseño anterior y a plena viveza arrasa con un
  /// sistema de tres tonos. Se conserva el hue —que es lo que identifica a la
  /// bóveda— y se reescriben lightness y croma.
  ///
  /// El emoji es el respaldo para bóvedas creadas antes de que los íconos
  /// fueran Material; no se puede recolorear, y por eso se deja tal cual.
  Widget _vaultGlyph(NoteVault? vault, {double size = 18}) {
    final icon = vault?.iconData ?? (vault == null ? Icons.description_outlined : null);
    if (icon == null) {
      return Twemoji(emoji: vault?.icon ?? '📁', height: size, width: size);
    }
    final color = vault == null
        ? EditorialTheme.grayText
        : EditorialTheme.accentAt(vault.flutterColor, 0.54);
    return Icon(icon, size: size, color: color);
  }

  String _noteCount(int count) => count == 1 ? '1 nota' : '$count notas';

  static String _formatReminder(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (day == today) return 'Hoy $hh:$mm';
    if (day == today.add(const Duration(days: 1))) return 'Mañana $hh:$mm';
    return '${dt.day}/${dt.month} $hh:$mm';
  }

  String _formatRange() {
    if (_rangeStart == null ||
        _rangeEnd == null ||
        _rangeHour == null ||
        _rangeMinute == null) {
      return 'Sin repetición';
    }
    final hh = _rangeHour!.toString().padLeft(2, '0');
    final mm = _rangeMinute!.toString().padLeft(2, '0');
    return '${_rangeStart!.day}/${_rangeStart!.month} — '
        '${_rangeEnd!.day}/${_rangeEnd!.month}, $hh:$mm';
  }

  /// Deja el texto en prosa para el resumen de dos líneas de la fila. No es un
  /// parser: sólo quita la sintaxis que se vería como ruido.
  String _stripMarkdown(String text) => text
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
      .replaceAll(RegExp(r'_(.+?)_'), r'$1')
      .replaceAll(RegExp(r'`(.+?)`'), r'$1')
      .replaceAll(RegExp(r'^>\s+', multiLine: true), '')
      .replaceAll(RegExp(r'- \[[ x]\] '), '')
      .replaceAll(RegExp(r'\n+'), ' ')
      .trim();
}
