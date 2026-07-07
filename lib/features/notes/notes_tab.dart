import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/note_model.dart';
import '../../core/models/note_vault_model.dart';
import '../../core/providers/notes_provider.dart';
import '../../core/providers/vaults_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/utils/error_snackbar.dart';
import 'notion_editor.dart';
import '../vault/screens/vault_lock_screen.dart';
import '../habits/widgets/habit_blob_header.dart';


export '../../core/models/note_model.dart';
export '../../core/models/note_vault_model.dart';
export '../../core/providers/notes_provider.dart';
export '../../core/providers/vaults_provider.dart';

// ─────────────────────────────────────────────────────
//  PANTALLA PRINCIPAL DE NOTAS
// ─────────────────────────────────────────────────────

enum _NotesView { vaults, notesList, editor, graph }

class NotesTab extends ConsumerStatefulWidget {
  const NotesTab({super.key});

  @override
  ConsumerState<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<NotesTab>
    with SingleTickerProviderStateMixin {
  _NotesView _view = _NotesView.vaults;
  NoteVault? _currentVault;
  Note? _editingNote;
  bool _triggeringBiometrics = false;

  // Editor
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _editorPreviewMode = false;
  List<String> _selectedLinks = [];
  NotePriority _editPriority = NotePriority.normal;
  DateTime? _editRemindAt;
  bool _editSelfDestruct = false;
  bool _suggesting = false;
  String? _aiSuggestions;

  // Búsqueda
  final _searchController = TextEditingController();
  bool _showSearch = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _searchController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─── Navigation ───────────────────────────────────

  void _openSecureVaultFromGesture() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VaultLockScreen()),
    ).then((_) {
      setState(() {
        _triggeringBiometrics = false;
      });
    });
  }

  void _goToVaults() {
    _fadeCtrl.forward(from: 0);
    setState(() {
      _view = _NotesView.vaults;
      _currentVault = null;
      _editingNote = null;
      _showSearch = false;
    });
  }

  void _openVault(NoteVault vault) {
    _fadeCtrl.forward(from: 0);
    setState(() {
      _currentVault = vault;
      _view = _NotesView.notesList;
      _showSearch = false;
    });
  }

  void _openEditor(Note note) {
    _fadeCtrl.forward(from: 0);
    setState(() {
      _editingNote = note;
      _view = _NotesView.editor;
      _titleController.text = note.title;
      _contentController.text = note.content;
      _selectedLinks = List<String>.from(note.linkedNoteIds);
      _editPriority = note.priority;
      _editRemindAt = note.remindAt;
      _editSelfDestruct = note.selfDestruct;
      _aiSuggestions = null;
      _editorPreviewMode = false;
    });
  }

  void _createNewNote() {
    _showCreateNoteSheet();
  }

  void _showCreateNoteSheet() {
    final titleCtrl = TextEditingController();
    NoteVault? selectedVault = _currentVault;
    NotePriority selectedPriority = NotePriority.normal;
    final vaults = ref.read(vaultsProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx2).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: BentoTheme.creamAlpha(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 20, color: BentoTheme.cream),
                      const SizedBox(width: 8),
                      Text(
                        'Nueva nota',
                        style: GoogleFonts.montserrat(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: BentoTheme.cream,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Title Input
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Título de la nota',
                      hintText: 'ej: Ideas de negocio, Lista de compras...',
                      labelStyle: TextStyle(color: BentoTheme.creamSecondary),
                      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
                      filled: true,
                      fillColor: BentoTheme.darkCardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.20)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.20)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: BentoTheme.accentLime, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Vault Selection
                  Text(
                    'Guardar en Bóveda',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.creamSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Unclassified option
                        GestureDetector(
                          onTap: () {
                            setModalState(() => selectedVault = null);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedVault == null
                                  ? BentoTheme.accentLime.withValues(alpha: 0.14)
                                  : BentoTheme.darkCardAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selectedVault == null
                                    ? BentoTheme.accentLime
                                    : BentoTheme.creamAlpha(0.20),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                _vaultIconGlyph(null, size: 16, color: BentoTheme.cream),
                                const SizedBox(width: 8),
                                Text(
                                  'Sin clasificar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: BentoTheme.cream,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Vaults list
                        ...vaults.map((vault) {
                          final selected = selectedVault?.id == vault.id;
                          final color = vault.flutterColor;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() => selectedVault = vault);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color.withValues(alpha: 0.16)
                                    : BentoTheme.darkCardAlt,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected ? color : BentoTheme.creamAlpha(0.20),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  _vaultIconGlyph(vault, size: 16, color: selected ? color : BentoTheme.cream),
                                  const SizedBox(width: 8),
                                  Text(
                                    vault.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: selected ? color : BentoTheme.cream,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Priority selection
                  Text(
                    'Prioridad',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.creamSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: NotePriority.values.map((p) {
                      final selected = selectedPriority == p;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setModalState(() => selectedPriority = p);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? p.color.withValues(alpha: 0.16)
                                  : BentoTheme.darkCardAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? p.color : BentoTheme.creamAlpha(0.20),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(p.icon,
                                    size: 16,
                                    color: selected ? p.color : BentoTheme.creamSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  p.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? p.color : BentoTheme.creamSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Create Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BentoTheme.accentLime,
                      foregroundColor: const Color(0xFF0C0C0D),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
                    ),
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      final actualTitle = title.isEmpty ? 'Nota sin título' : title;
                      Navigator.pop(ctx);

                      final vaultId = selectedVault?.id;
                      await ref.read(notesProvider.notifier).addNote(
                            actualTitle,
                            '',
                            vaultId: vaultId,
                            priority: selectedPriority,
                          );

                      // Get the newly created note and open editor
                      final notes = ref.read(notesProvider);
                      if (notes.isNotEmpty) {
                        final note = notes.reduce((curr, next) {
                          final currTime = curr.createdAt ?? DateTime(0);
                          final nextTime = next.createdAt ?? DateTime(0);
                          return currTime.isAfter(nextTime) ? curr : next;
                        });
                        _openEditor(note);
                      }
                    },
                    child: const Text('Crear Nota'),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _saveEditor() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || _editingNote == null) return;

    ref.read(notesProvider.notifier).updateNote(
          _editingNote!.id,
          title,
          content,
          _selectedLinks,
          priority: _editPriority,
          remindAt: _editRemindAt,
          clearRemindAt: _editRemindAt == null,
          selfDestruct: _editSelfDestruct && _editRemindAt != null,
          vaultId: _editingNote!.vaultId,
        );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Nota guardada', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        duration: const Duration(milliseconds: 800),
        backgroundColor: BentoTheme.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Reminder ─────────────────────────────────────

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

  Future<DateTime?> _pickReminder(DateTime? current) async {
    final now = DateTime.now();
    DateTime? result;

    await showModalBottomSheet(
      context: context,
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        Widget preset(String label, IconData icon, DateTime when, Color color) {
          return ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BentoTheme.cream,
                    fontSize: 14)),
            trailing: Text(
              _formatReminder(when),
              style:
                  TextStyle(fontSize: 12, color: BentoTheme.creamSecondary),
            ),
            onTap: () {
              result = when;
              Navigator.pop(ctx);
            },
          );
        }

        final tonight = DateTime(now.year, now.month, now.day, 20, 0);
        final tomorrow =
            DateTime(now.year, now.month, now.day, 8, 0).add(const Duration(days: 1));

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BentoTheme.creamAlpha(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, size: 18, color: BentoTheme.cream),
                    const SizedBox(width: 8),
                    Text('¿Cuándo te lo recuerdo?',
                        style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: BentoTheme.cream)),
                  ],
                ),
              ),
              preset('En 1 hora', Icons.hourglass_bottom,
                  now.add(const Duration(hours: 1)), BentoTheme.accentBlue),
              preset('En 3 horas', Icons.hourglass_top,
                  now.add(const Duration(hours: 3)), BentoTheme.accentPurple),
              if (tonight.isAfter(now))
                preset('Esta noche (8pm)', Icons.nights_stay, tonight,
                    BentoTheme.accentLime),
              preset('Mañana (8am)', Icons.wb_sunny_outlined, tomorrow,
                  BentoTheme.accentOrange),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: BentoTheme.accentPurple.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_calendar,
                      color: BentoTheme.accentPurple, size: 18),
                ),
                title: Text('Elegir fecha y hora...',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.cream,
                        fontSize: 14)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final date = await showDatePicker(
                    context: context,
                    initialDate: current ?? now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (date == null || !mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(current ?? now),
                  );
                  if (time == null) return;
                  result = DateTime(
                      date.year, date.month, date.day, time.hour, time.minute);
                },
              ),
              if (current != null)
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: BentoTheme.errorRed.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_off,
                        color: BentoTheme.errorRed, size: 18),
                  ),
                  title: const Text('Quitar recordatorio',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.errorRed,
                          fontSize: 14)),
                  onTap: () {
                    result = null;
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    return result;
  }

  // ─── AI suggestions ───────────────────────────────

  Future<void> _suggestConnectionsWithAI() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _suggesting = true;
      _aiSuggestions = null;
    });

    final notes =
        ref.read(notesProvider).where((n) => n.id != _editingNote?.id).toList();
    final settings = ref.read(settingsProvider);

    final buffer = StringBuffer();
    buffer.writeln(
        'Nota Actual:\nTítulo: "$title"\nContenido: "$content"\n\nOtras Notas Existentes:');
    for (var n in notes) {
      buffer.writeln(
          '- ID: ${n.id}, Título: "${n.title}", Resumen: "${n.content.take(60)}..."');
    }
    buffer.writeln(
        '\nAnaliza semánticamente si la Nota Actual se relaciona con alguna de las Notas Existentes. Responde listando los Títulos relacionados y explica brevemente por qué.');

    try {
      final client = LocalAIClient(
        baseUrl: settings.localAiUrl,
        textModelName: settings.textModel,
      );

      final response = await client.askText(
        buffer.toString(),
        systemPrompt:
            'Eres un analista de conocimiento y tu tarea es encontrar conexiones lógicas en un Segundo Cerebro. Sé conciso y responde en español.',
      );

      if (mounted) setState(() => _aiSuggestions = response);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Error al conectar con IA Local: $e');
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  // ─── BUILD ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showFab = _view == _NotesView.vaults || _view == _NotesView.notesList;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BentoTheme.darkBgTop, BentoTheme.darkBg],
          stops: [0.0, 0.6],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: switch (_view) {
                _NotesView.vaults => _buildVaultsScreen(),
                _NotesView.notesList => _buildNotesListScreen(),
                _NotesView.editor => _buildEditorScreen(),
                _NotesView.graph => _buildGraphScreen(),
              },
            ),
          ),
          if (showFab)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                heroTag: 'notes_fab',
                onPressed: _showCreateNoteSheet,
                backgroundColor: BentoTheme.accentLime,
                foregroundColor: const Color(0xFF0C0C0D),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  //  PANTALLA 1: BÓVEDAS
  // ─────────────────────────────────────────────────────

  Widget _buildVaultsScreen() {
    final vaults = ref.watch(vaultsProvider);
    final notes = ref.watch(notesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildVaultsHeader(),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification is ScrollUpdateNotification) {
                final metrics = notification.metrics;
                if (metrics.pixels > metrics.maxScrollExtent) {
                  final overscroll = metrics.pixels - metrics.maxScrollExtent;
                  if (overscroll > 100 && !_triggeringBiometrics) {
                    _triggeringBiometrics = true;
                    _openSecureVaultFromGesture();
                  }
                }
              }
              return false;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 100),
              children: [
                if (vaults.isEmpty) ...[
                  _buildUnvaultedCard(notes),
                  const SizedBox(height: 60),
                  // Contenido de vacío
                  Center(
                    child: Icon(Icons.inventory_2_outlined,
                        size: 48, color: BentoTheme.creamTertiary),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Sin bóvedas todavía',
                      style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: BentoTheme.cream),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Crea una bóveda para organizar\ntus notas por tema',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: BentoTheme.creamSecondary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _showCreateVaultDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BentoTheme.accentLime,
                        foregroundColor: const Color(0xFF0C0C0D),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear bóveda'),
                    ),
                  ),
                ] else ...[
                  // "Sin bóveda" — notas sueltas
                  _buildUnvaultedCard(notes),
                  const SizedBox(height: 10),
                  // Grid de bóvedas
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: vaults.length,
                    itemBuilder: (_, i) =>
                        _buildVaultCard(vaults[i], notes),
                  ),
                ],
                const SizedBox(height: 80),
                // Indicador visual de la bóveda oculta al arrastrar
                Opacity(
                  opacity: 0.4,
                  child: Column(
                    children: [
                      Icon(Icons.lock_outline, color: BentoTheme.creamAlpha(0.5), size: 22),
                      const SizedBox(height: 6),
                      Text(
                        'Arrastra hacia arriba para abrir la Carpeta Segura',
                        style: TextStyle(
                          fontSize: 11,
                          color: BentoTheme.creamAlpha(0.5),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActionPill({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BentoTheme.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BentoTheme.creamAlpha(0.20), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: BentoTheme.cream),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: BentoTheme.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Insignia de ícono estilo Notion: ícono Material sobre fondo tintado,
  /// con fallback a emoji para bóvedas creadas antes del rediseño.
  Widget _vaultIconBadge(NoteVault? vault, {double size = 40, Color? color}) {
    final badgeColor = color ?? vault?.flutterColor ?? BentoTheme.accentBlue;
    final iconData = vault?.iconData ?? (vault == null ? Icons.description_outlined : null);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: iconData != null
          ? Icon(iconData, size: size * 0.5, color: badgeColor)
          : Text(vault?.icon ?? '📁', style: TextStyle(fontSize: size * 0.46)),
    );
  }

  /// Igual que [_vaultIconBadge] pero sin fondo/borde, para usar en chips
  /// compactos y filas de texto (tamaño de ícono en vez de insignia).
  Widget _vaultIconGlyph(NoteVault? vault, {double size = 16, Color? color}) {
    final glyphColor = color ?? vault?.flutterColor ?? BentoTheme.cream;
    final iconData = vault?.iconData ?? (vault == null ? Icons.description_outlined : null);
    return iconData != null
        ? Icon(iconData, size: size, color: glyphColor)
        : Text(vault?.icon ?? '📁', style: TextStyle(fontSize: size));
  }

  Widget _buildVaultsHeader() {
    return SizedBox(
      height: 126,
      child: Stack(
        children: [
          const Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.accentBlue)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildHeaderActionPill(
                      icon: Icons.hub_outlined,
                      label: 'Grafo',
                      onPressed: () => setState(() => _view = _NotesView.graph),
                    ),
                    const SizedBox(width: 10),
                    _buildHeaderActionPill(
                      icon: Icons.create_new_folder_outlined,
                      label: 'Nueva',
                      onPressed: _showCreateVaultDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Segundo Cerebro',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    height: 0.98,
                    letterSpacing: -0.8,
                    color: BentoTheme.cream,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnvaultedCard(List<Note> allNotes) {
    final count = allNotes.where((n) => n.vaultId == null).length;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentVault = null;
          _view = _NotesView.notesList;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BentoTheme.creamAlpha(0.1), width: 1.5),
        ),
        child: Row(
          children: [
            _vaultIconBadge(null, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin clasificar',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                        fontSize: 14),
                  ),
                  Text(
                    '$count ${count == 1 ? 'nota' : 'notas'}',
                    style: TextStyle(
                        fontSize: 12, color: BentoTheme.creamSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BentoTheme.creamAlpha(0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultCard(NoteVault vault, List<Note> allNotes) {
    final count = allNotes.where((n) => n.vaultId == vault.id).length;
    final color = vault.flutterColor;

    return GestureDetector(
      onTap: () => _openVault(vault),
      onLongPress: () => _showVaultOptionsSheet(vault),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _vaultIconBadge(vault, size: 40),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: color),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              vault.name,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: BentoTheme.cream,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (vault.description != null) ...[
              const SizedBox(height: 2),
              Text(
                vault.description!,
                style: TextStyle(
                    fontSize: 11, color: BentoTheme.creamAlpha(0.5)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '$count ${count == 1 ? 'nota' : 'notas'}',
              style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  //  PANTALLA 2: LISTA DE NOTAS EN UNA BÓVEDA
  // ─────────────────────────────────────────────────────

  Widget _buildNotesListScreen() {
    final allNotes = ref.watch(notesProvider);
    final vaultNotes = _currentVault == null
        ? allNotes.where((n) => n.vaultId == null).toList()
        : allNotes.where((n) => n.vaultId == _currentVault!.id).toList();

    final searchQuery = _searchController.text.toLowerCase();
    final filtered = searchQuery.isEmpty
        ? vaultNotes
        : vaultNotes
            .where((n) =>
                n.title.toLowerCase().contains(searchQuery) ||
                n.content.toLowerCase().contains(searchQuery))
            .toList();

    final vaultColor = _currentVault?.flutterColor ?? BentoTheme.creamSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          decoration: BoxDecoration(
            color: vaultColor.withValues(alpha: 0.08),
            border: Border(
              bottom: BorderSide(
                  color: vaultColor.withValues(alpha: 0.2), width: 1),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _goToVaults,
                      icon: Icon(Icons.arrow_back_ios_new,
                          size: 18, color: BentoTheme.cream),
                    ),
                    _vaultIconGlyph(_currentVault, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentVault?.name ?? 'Sin clasificar',
                        style: GoogleFonts.montserrat(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: BentoTheme.cream,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _showSearch = !_showSearch),
                      icon: Icon(
                          _showSearch ? Icons.search_off : Icons.search,
                          color: BentoTheme.creamSecondary),
                    ),
                    IconButton(
                      onPressed: _createNewNote,
                      icon: Icon(Icons.add_circle,
                          color: vaultColor, size: 28),
                      tooltip: 'Nueva nota',
                    ),
                  ],
                ),
              ),
              if (_showSearch)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: BentoTheme.cream),
                    decoration: InputDecoration(
                      hintText: 'Buscar en notas...',
                      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
                      prefixIcon: Icon(Icons.search,
                          color: BentoTheme.creamSecondary),
                      filled: true,
                      fillColor: BentoTheme.darkCardAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: vaultColor.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: vaultColor.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: vaultColor, width: 2),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),

        // Lista de notas
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyNotesList(vaultColor)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _buildNoteListTile(filtered[i], allNotes, vaultColor),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyNotesList(Color vaultColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note_outlined, size: 44, color: BentoTheme.creamTertiary),
          const SizedBox(height: 12),
          Text(
            'Esta bóveda está vacía',
            style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: BentoTheme.cream),
          ),
          const SizedBox(height: 6),
          Text(
            'Presiona + para crear tu primera nota',
            style: TextStyle(color: BentoTheme.creamSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _createNewNote,
            style: ElevatedButton.styleFrom(
              backgroundColor: BentoTheme.accentLime,
              foregroundColor: const Color(0xFF0C0C0D),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Crear nota'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteListTile(Note note, List<Note> allNotes, Color vaultColor) {
    final isUrgent = note.priority == NotePriority.urgent;
    final hasReminder = note.remindAt != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('note_${note.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: BentoTheme.errorRed,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.delete_forever, color: Colors.white),
        ),
        onDismissed: (_) {
          ref.read(notesProvider.notifier).deleteNote(note.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Nota eliminada'),
              duration: const Duration(milliseconds: 900),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
        child: GestureDetector(
          onTap: () => _openEditor(note),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BentoTheme.darkCardAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isUrgent
                    ? BentoTheme.errorRed.withValues(alpha: 0.5)
                    : vaultColor.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Indicador de prioridad
                Container(
                  width: 4,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: note.priority == NotePriority.normal
                        ? vaultColor.withValues(alpha: 0.4)
                        : note.priority.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: BentoTheme.cream,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (note.content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _stripMarkdown(note.content),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: BentoTheme.creamSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (hasReminder || note.linkedNoteIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (hasReminder)
                              _miniChip(
                                note.selfDestruct
                                    ? Icons.local_fire_department_outlined
                                    : Icons.notifications_active_outlined,
                                _formatReminder(note.remindAt!),
                                note.isReminderPending
                                    ? (note.selfDestruct
                                        ? BentoTheme.accentOrange
                                        : BentoTheme.accentBlue)
                                    : BentoTheme.creamSecondary,
                              ),
                            if (note.linkedNoteIds.isNotEmpty)
                              _miniChip(
                                  Icons.link_rounded,
                                  '${note.linkedNoteIds.length}',
                                  BentoTheme.accentPurple),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: BentoTheme.creamAlpha(0.4), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  //  PANTALLA 3: EDITOR ESTILO NOTION
  // ─────────────────────────────────────────────────────

  Widget _buildEditorScreen() {
    return Column(
      children: [
        // Toolbar del editor
        _buildEditorToolbar(),
        // Cuerpo del editor
        Expanded(
          child: _editorPreviewMode
              ? _buildMarkdownPreview()
              : _buildMarkdownEditor(),
        ),
      ],
    );
  }

  Widget _buildEditorToolbar() {
    final vaultColor =
        _currentVault?.flutterColor ?? BentoTheme.accentBlue;

    return Container(
      decoration: BoxDecoration(
        color: BentoTheme.darkCard,
        border: Border(
          bottom: BorderSide(color: BentoTheme.creamAlpha(0.18), width: 1.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                _saveEditor();
                setState(() => _view = _NotesView.notesList);
              },
              icon: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: BentoTheme.cream),
            ),
            const SizedBox(width: 8),
            if (_editingNote != null) ...[
              _vaultIconGlyph(_currentVault, size: 15, color: BentoTheme.creamSecondary),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                _editingNote == null
                    ? 'Nueva nota'
                    : (_currentVault?.name ?? 'Sin clasificar'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: BentoTheme.creamSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Preview toggle
            _toolbarBtn(
              _editorPreviewMode ? Icons.edit_note : Icons.visibility_outlined,
              _editorPreviewMode ? 'Editar' : 'Vista previa',
              vaultColor,
              () => setState(
                  () => _editorPreviewMode = !_editorPreviewMode),
            ),
            const SizedBox(width: 4),
            // Guardar
            _toolbarBtn(
              Icons.check_circle_outline,
              'Guardar',
              BentoTheme.successGreen,
              _saveEditor,
            ),
            const SizedBox(width: 4),
            // Panel de opciones
            _toolbarBtn(
              Icons.tune,
              'Opciones',
              BentoTheme.accentLime,
              () {
                final allNotes = ref.read(notesProvider);
                _showEditorOptionsSheet(context, allNotes);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarBtn(
      IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 20),
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }

  Widget _mdBtn(String label, String insert,
      {bool bold = false, bool italic = false}) {
    return GestureDetector(
      onTap: () => _insertMarkdown(insert),
      child: Container(
        margin: const EdgeInsets.only(right: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BentoTheme.creamAlpha(0.18), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: BentoTheme.cream,
          ),
        ),
      ),
    );
  }

  void _insertMarkdown(String text) {
    final ctrl = _contentController;
    final sel = ctrl.selection;
    final before = ctrl.text.substring(0, sel.start < 0 ? 0 : sel.start);
    final after = ctrl.text.substring(sel.end < 0 ? 0 : sel.end);
    final inserted = '$before$text$after';
    ctrl.value = TextEditingValue(
      text: inserted,
      selection: TextSelection.collapsed(offset: before.length + text.length),
    );
  }

  Widget _buildMarkdownEditor() {
    return NotionEditor(
      key: ValueKey(_editingNote?.id ?? 'new_note'),
      titleController: _titleController,
      contentController: _contentController,
      accentColor: _currentVault?.flutterColor ?? BentoTheme.accentBlue,
    );
  }

  Widget _buildMarkdownPreview() {
    final title = _titleController.text.isEmpty
        ? 'Sin título'
        : _titleController.text;
    final content = _contentController.text.isEmpty
        ? '_Sin contenido aún. Empieza a escribir..._'
        : _contentController.text;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: BentoTheme.cream,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 1.5,
          color: BentoTheme.creamAlpha(0.18),
        ),
        const SizedBox(height: 16),
        MarkdownBody(
          data: content,
          styleSheet: MarkdownStyleSheet(
            h1: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: BentoTheme.cream),
            h2: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: BentoTheme.cream),
            h3: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: BentoTheme.cream),
            p: TextStyle(
                fontSize: 15,
                color: BentoTheme.cream,
                height: 1.6),
            code: TextStyle(
              fontSize: 13.5,
              fontFamily: 'monospace',
              color: BentoTheme.accentPurple,
              backgroundColor: BentoTheme.darkCardAlt,
            ),
            blockquote: TextStyle(
                fontSize: 14,
                color: BentoTheme.creamSecondary,
                fontStyle: FontStyle.italic),
            blockquoteDecoration: BoxDecoration(
              border: const Border(
                  left: BorderSide(
                      color: BentoTheme.accentBlue, width: 4)),
              color: BentoTheme.accentBlue.withValues(alpha: 0.08),
            ),
            tableBody: TextStyle(
                fontSize: 14, color: BentoTheme.cream),
            listBullet: const TextStyle(
                fontSize: 15, color: BentoTheme.accentBlue),
          ),
        ),
      ],
    );
  }

  void _showEditorOptionsSheet(BuildContext context, List<Note> allNotes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: BentoTheme.creamAlpha(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tune_rounded, size: 20, color: BentoTheme.cream),
                      const SizedBox(width: 8),
                      Text(
                        'Propiedades de la nota',
                        style: GoogleFonts.montserrat(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: BentoTheme.cream,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Prioridad
                        Text(
                          'Prioridad',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: BentoTheme.creamSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: NotePriority.values.map((p) {
                            final selected = _editPriority == p;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _editPriority = p);
                                  setModalState(() => _editPriority = p);
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? p.color.withValues(alpha: 0.16)
                                        : BentoTheme.darkCardAlt,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected ? p.color : BentoTheme.creamAlpha(0.20),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(p.icon,
                                          size: 16,
                                          color: selected ? p.color : BentoTheme.creamSecondary),
                                      const SizedBox(height: 4),
                                      Text(
                                        p.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: selected ? p.color : BentoTheme.creamSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),

                        // Recordatorio
                        Text(
                          'Recordatorio',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: BentoTheme.creamSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final picked = await _pickReminder(_editRemindAt);
                            setState(() {
                              _editRemindAt = picked;
                              if (picked == null) _editSelfDestruct = false;
                            });
                            setModalState(() {
                              _editRemindAt = picked;
                              if (picked == null) _editSelfDestruct = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _editRemindAt != null
                                  ? BentoTheme.accentBlue.withValues(alpha: 0.14)
                                  : BentoTheme.darkCardAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _editRemindAt != null
                                    ? BentoTheme.accentBlue
                                    : BentoTheme.creamAlpha(0.20),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.notifications_active_outlined,
                                    color: _editRemindAt != null
                                        ? BentoTheme.accentBlue
                                        : BentoTheme.creamSecondary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _editRemindAt == null
                                        ? 'Agregar recordatorio'
                                        : _formatReminder(_editRemindAt!),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: _editRemindAt != null
                                          ? BentoTheme.accentBlue
                                          : BentoTheme.cream,
                                    ),
                                  ),
                                ),
                                if (_editRemindAt != null)
                                  const Icon(Icons.edit_calendar,
                                      size: 16, color: BentoTheme.accentBlue)
                                else
                                  Icon(Icons.chevron_right,
                                      size: 16, color: BentoTheme.creamSecondary),
                              ],
                            ),
                          ),
                        ),

                        if (_editRemindAt != null) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () {
                              setState(() => _editSelfDestruct = !_editSelfDestruct);
                              setModalState(() => _editSelfDestruct = !_editSelfDestruct);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _editSelfDestruct
                                    ? BentoTheme.accentOrange.withValues(alpha: 0.14)
                                    : BentoTheme.darkCardAlt,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _editSelfDestruct
                                      ? BentoTheme.accentOrange
                                      : BentoTheme.creamAlpha(0.20),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.local_fire_department_outlined,
                                      color: _editSelfDestruct
                                          ? BentoTheme.accentOrange
                                          : BentoTheme.creamSecondary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _editSelfDestruct
                                          ? 'Se autodestruye al vencer'
                                          : 'Autodestruirse al vencer',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: _editSelfDestruct
                                            ? BentoTheme.accentOrange
                                            : BentoTheme.cream,
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: _editSelfDestruct,
                                    activeThumbColor: Colors.white,
                                    activeTrackColor: BentoTheme.accentOrange,
                                    onChanged: (val) {
                                      setState(() => _editSelfDestruct = val);
                                      setModalState(() => _editSelfDestruct = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Conexiones manuales
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Conectar con otras notas',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: BentoTheme.creamSecondary,
                              ),
                            ),
                            Text(
                              '${_selectedLinks.length} conectadas',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: BentoTheme.accentPurple,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (allNotes.where((n) => n.id != _editingNote?.id).isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: BentoTheme.darkCardAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: BentoTheme.creamAlpha(0.18)),
                            ),
                            child: Text(
                              'No hay otras notas para conectar.',
                              style: TextStyle(fontSize: 12, color: BentoTheme.creamSecondary),
                            ),
                          )
                        else
                          SizedBox(
                            height: 120,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: allNotes
                                  .where((n) => n.id != _editingNote?.id)
                                  .map((note) {
                                final linked = _selectedLinks.contains(note.id);
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (linked) {
                                        _selectedLinks.remove(note.id);
                                      } else {
                                        _selectedLinks.add(note.id);
                                      }
                                    });
                                    setModalState(() {});
                                  },
                                  child: Container(
                                    width: 130,
                                    margin: const EdgeInsets.only(right: 8, bottom: 4, top: 4),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: linked
                                          ? BentoTheme.accentPurple.withValues(alpha: 0.14)
                                          : BentoTheme.darkCardAlt,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: linked
                                            ? BentoTheme.accentPurple
                                            : BentoTheme.creamAlpha(0.20),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(linked ? Icons.link : Icons.link_off,
                                            size: 18,
                                            color: linked ? BentoTheme.accentPurple : BentoTheme.creamSecondary),
                                        Text(
                                          note.title.isEmpty ? 'Sin título' : note.title,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: linked ? BentoTheme.accentPurple : BentoTheme.cream,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 24),

                        // IA Suggestions
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: BentoTheme.accentPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: BentoTheme.accentPurple.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome_outlined,
                                      color: BentoTheme.accentPurple, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Copiloto de Conexiones IA',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: BentoTheme.accentPurple,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_suggesting)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: BentoTheme.accentPurple,
                                      ),
                                    )
                                  else
                                    TextButton(
                                      onPressed: () async {
                                        setModalState(() => _suggesting = true);
                                        await _suggestConnectionsWithAI();
                                        setModalState(() {
                                          _suggesting = false;
                                        });
                                      },
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Analizar',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                              if (_aiSuggestions != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: BentoTheme.darkCard,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: BentoTheme.creamAlpha(0.18)),
                                  ),
                                  child: Text(
                                    _aiSuggestions!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BentoTheme.cream,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Eliminar Nota
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_editingNote == null) return;
                            final id = _editingNote!.id;
                            Navigator.pop(ctx);
                            setState(() => _view = _NotesView.notesList);
                            ref.read(notesProvider.notifier).deleteNote(id);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BentoTheme.errorRed.withValues(alpha: 0.1),
                            foregroundColor: BentoTheme.errorRed,
                            elevation: 0,
                            side: const BorderSide(color: BentoTheme.errorRed, width: 1.5),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Eliminar Nota'),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────
  //  PANTALLA 4: GRAFO
  // ─────────────────────────────────────────────────────

  Widget _buildGraphScreen() {
    final notes = ref.watch(notesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _goToVaults,
                    icon: Icon(Icons.arrow_back_ios_new,
                        size: 18, color: BentoTheme.cream),
                  ),
                  Icon(Icons.hub_outlined, size: 18, color: BentoTheme.cream),
                  const SizedBox(width: 8),
                  Text(
                    'Grafo de conocimiento',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: BentoTheme.darkCard,
              border:
                  Border.all(color: BentoTheme.creamAlpha(0.20), width: 1.5),
            ),
            child: InteractiveViewer(
              boundaryMargin: const EdgeInsets.all(100),
              minScale: 0.3,
              maxScale: 3.0,
              child: CustomPaint(
                size: const Size(double.infinity, double.infinity),
                painter: GraphPainter(notes: notes),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────
  //  DIALOGS — CREAR / EDITAR BÓVEDA
  // ─────────────────────────────────────────────────────

  void _showCreateVaultDialog() {
    _showVaultDialog();
  }

  void _showVaultOptionsSheet(NoteVault vault) {
    showModalBottomSheet(
      context: context,
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _vaultIconBadge(vault, size: 32),
                  const SizedBox(width: 10),
                  Text(
                    vault.name,
                    style: GoogleFonts.montserrat(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: BentoTheme.accentBlue),
              title: Text('Editar bóveda',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.cream)),
              onTap: () {
                Navigator.pop(ctx);
                _showVaultDialog(vault: vault);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: BentoTheme.errorRed),
              title: const Text('Eliminar bóveda',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.errorRed)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteVault(vault);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showVaultDialog({NoteVault? vault}) {
    final nameCtrl =
        TextEditingController(text: vault?.name ?? '');
    final descCtrl =
        TextEditingController(text: vault?.description ?? '');
    String selectedIconKey = vault?.icon ?? 'folder';
    String selectedColor = vault?.color ?? '#758BFD';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setModal) {
          InputDecoration darkInputDecoration({required String label, required String hint}) {
            return InputDecoration(
              labelText: label,
              hintText: hint,
              labelStyle: TextStyle(color: BentoTheme.creamSecondary),
              hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
              filled: true,
              fillColor: BentoTheme.darkCardAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: BentoTheme.creamAlpha(0.20)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: BentoTheme.creamAlpha(0.20)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide(color: BentoTheme.accentLime, width: 2),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx2).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        vault == null ? Icons.create_new_folder_outlined : Icons.edit_outlined,
                        size: 20,
                        color: BentoTheme.cream,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        vault == null ? 'Nueva bóveda' : 'Editar bóveda',
                        style: GoogleFonts.montserrat(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: BentoTheme.cream),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: TextStyle(color: BentoTheme.cream),
                    decoration: darkInputDecoration(
                        label: 'Nombre de la bóveda',
                        hint: 'ej: Personal, Ideas, Trabajo...'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: TextStyle(color: BentoTheme.cream),
                    decoration: darkInputDecoration(
                        label: 'Descripción (opcional)',
                        hint: 'Breve descripción...'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ícono',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.creamSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: vaultIconKeyOptions.map((key) {
                      final sel = selectedIconKey == key;
                      Color previewColor;
                      try {
                        previewColor = Color(int.parse(
                            'FF${selectedColor.replaceAll('#', '')}',
                            radix: 16));
                      } catch (_) {
                        previewColor = BentoTheme.accentBlue;
                      }
                      return GestureDetector(
                        onTap: () =>
                            setModal(() => selectedIconKey = key),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: sel
                                ? previewColor.withValues(alpha: 0.18)
                                : BentoTheme.darkCardAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: sel
                                    ? previewColor
                                    : BentoTheme.creamAlpha(0.20),
                                width: sel ? 2 : 1),
                          ),
                          child: Center(
                              child: Icon(vaultIconMap[key],
                                  size: 20,
                                  color: sel ? previewColor : BentoTheme.creamSecondary)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Color',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.creamSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: vaultColorOptions.map((hexColor) {
                      final sel = selectedColor == hexColor;
                      Color c;
                      try {
                        c = Color(int.parse(
                            'FF${hexColor.replaceAll('#', '')}',
                            radix: 16));
                      } catch (_) {
                        c = BentoTheme.accentBlue;
                      }
                      return GestureDetector(
                        onTap: () =>
                            setModal(() => selectedColor = hexColor),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: sel
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2),
                            boxShadow: sel
                                ? [
                                    BoxShadow(
                                        color: c.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1)
                                  ]
                                : null,
                          ),
                          child: sel
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 16)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BentoTheme.accentLime,
                        foregroundColor: const Color(0xFF0C0C0D),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(ctx);
                        if (vault == null) {
                          await ref
                              .read(vaultsProvider.notifier)
                              .createVault(
                                name,
                                icon: selectedIconKey,
                                color: selectedColor,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                              );
                        } else {
                          await ref
                              .read(vaultsProvider.notifier)
                              .updateVault(
                                vault.id,
                                name: name,
                                icon: selectedIconKey,
                                color: selectedColor,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                              );
                        }
                        setState(() {});
                      },
                      child: Text(
                          vault == null ? 'Crear Bóveda' : 'Guardar Cambios'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _confirmDeleteVault(NoteVault vault) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BentoTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Eliminar "${vault.name}"?',
            style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w800, color: BentoTheme.cream)),
        content: Text(
          'Las notas dentro permanecerán como "Sin clasificar". Esta acción no se puede deshacer.',
          style: TextStyle(color: BentoTheme.creamSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: BentoTheme.creamAlpha(0.7)),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(vaultsProvider.notifier).deleteVault(vault.id);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: BentoTheme.errorRed),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────

  Widget _miniChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _stripMarkdown(String text) {
    // Quitar sintaxis markdown para la vista previa del título
    return text
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'_(.+?)_'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'^>\s+', multiLine: true), '')
        .replaceAll(RegExp(r'- \[[ x]\] '), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }
}

// ─────────────────────────────────────────────────────
//  GRAPH PAINTER
// ─────────────────────────────────────────────────────

class GraphPainter extends CustomPainter {
  final List<Note> notes;

  GraphPainter({required this.notes});

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) return;

    final random = Random(42);
    final Map<String, Offset> positions = {};
    const nodeRadius = 34.0;

    final center = Offset(
        size.width == 0 ? 200 : size.width / 2,
        size.height == 0 ? 300 : size.height / 2);

    for (int i = 0; i < notes.length; i++) {
      if (i == 0) {
        positions[notes[i].id] = center;
      } else {
        final angle = (2 * pi / (notes.length - 1)) * (i - 1);
        final distance = 120.0 + random.nextDouble() * 40;
        positions[notes[i].id] = Offset(
          center.dx + cos(angle) * distance,
          center.dy + sin(angle) * distance,
        );
      }
    }

    // Líneas de conexión
    final linePaint = Paint()
      ..color = BentoTheme.accentBlue.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var note in notes) {
      final startPos = positions[note.id];
      if (startPos == null) continue;

      for (var targetId in note.linkedNoteIds) {
        final endPos = positions[targetId];
        if (endPos != null && note.id.hashCode < targetId.hashCode) {
          canvas.drawLine(startPos, endPos, linePaint);
        }
      }
    }

    // Nodos
    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final pos = positions[note.id]!;
      final isCenter = i == 0;
      final priorityColor = note.priority == NotePriority.normal
          ? BentoTheme.accentBlue
          : note.priority.color;

      final fillPaint = Paint()
        ..color = isCenter ? BentoTheme.accentLime : BentoTheme.darkCardAlt
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, nodeRadius, fillPaint);

      final borderPaint = Paint()
        ..color = isCenter ? BentoTheme.accentLime : priorityColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pos, nodeRadius, borderPaint);

      final textSpan = TextSpan(
        text: note.title.length > 8
            ? '${note.title.substring(0, 7)}..'
            : note.title,
        style: TextStyle(
          color: isCenter ? const Color(0xFF0C0C0D) : BentoTheme.cream,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(minWidth: 0, maxWidth: nodeRadius * 2 - 8);
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2,
            pos.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

extension StringTake on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
