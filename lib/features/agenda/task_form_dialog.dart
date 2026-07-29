import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/task_model.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../alarm/widgets/bento_time_picker.dart';

Widget _sectionLabel(String text) {
  return Text(
    text.toUpperCase(),
    style: GoogleFonts.montserrat(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: BentoTheme.creamAlpha(0.5)),
  );
}

InputDecoration _darkFieldDecoration(String hint, {String? errorText}) {
  return InputDecoration(
    hintText: hint,
    errorText: errorText,
    errorStyle: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w600, fontSize: 12),
    hintStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.35), fontWeight: FontWeight.w500),
    filled: true,
    fillColor: BentoTheme.creamAlpha(0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: BentoTheme.accentLime, width: 1.5),
    ),
  );
}

/// Abre el modal de creación/edición de un bloque de agenda para [day].
/// Si [existing] es null crea uno nuevo.
Future<void> showTaskFormDialog(BuildContext context, WidgetRef ref, {required DateTime day, Task? existing}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _TaskFormSheet(day: day, existing: existing),
  );
}

class _TaskFormSheet extends ConsumerStatefulWidget {
  final DateTime day;
  final Task? existing;
  const _TaskFormSheet({required this.day, this.existing});

  @override
  ConsumerState<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<_TaskFormSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _locationController;
  late TimeOfDay _startTime;

  /// Duración en minutos. Sustituye al segundo selector de hora: elegir "1h"
  /// es un toque, contra los cuatro que costaba abrir un reloj, mover la
  /// aguja y aceptar.
  late int _durationMinutes;

  late TaskPriority _priority;
  late bool _reminderEnabled;
  late bool _isMit;
  String? _titleError;

  static const _durationPresets = [15, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _titleController = TextEditingController(text: t?.title ?? '');
    _notesController = TextEditingController(text: t?.notes ?? '');
    _locationController = TextEditingController(text: t?.location ?? '');
    _startTime = t != null ? TimeOfDay.fromDateTime(t.startAt) : TimeOfDay.now();
    _durationMinutes = t?.durationMinutes ?? 30;
    if (_durationMinutes <= 0) _durationMinutes = 30;
    _priority = t?.priority ?? TaskPriority.normal;
    _reminderEnabled = t?.hasReminder ?? true;
    _isMit = t?.isMit ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay time) =>
      DateTime(widget.day.year, widget.day.month, widget.day.day, time.hour, time.minute);

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      // Antes esto era un `return` mudo: el sheet se quedaba quieto sin
      // explicar por qué no pasaba nada.
      setState(() => _titleError = 'Ponle un nombre al bloque');
      return;
    }

    final notifier = ref.read(tasksProvider.notifier);
    // Se captura antes del pop: después el context de este sheet ya no sirve.
    final messenger = ScaffoldMessenger.of(context);
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    final location = _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
    final startAt = _combine(_startTime);
    // La duración siempre es positiva, así que el fin nunca cae antes del
    // inicio; si cruza medianoche, `add` ya lo lleva al día siguiente.
    final endAt = startAt.add(Duration(minutes: _durationMinutes));
    final remindAt = _reminderEnabled ? startAt : null;

    // Cerramos el sheet de inmediato — el bloque ya está en la lista por el
    // insert optimista — pero seguimos esperando para poder avisar si la
    // sincronización falló.
    Navigator.pop(context);

    if (widget.existing == null) {
      await notifier.addTask(
        title: title,
        notes: notes,
        dueDate: widget.day,
        startAt: startAt,
        endAt: endAt,
        remindAt: remindAt,
        priority: _priority,
        location: location,
        isMit: _isMit,
        plannedAt: DateTime.now(),
      );
    } else {
      await notifier.updateTask(widget.existing!.copyWith(
        title: title,
        notes: notes,
        clearNotes: notes == null,
        startAt: startAt,
        endAt: endAt,
        remindAt: remindAt,
        clearReminder: !_reminderEnabled,
        priority: _priority,
        location: location,
        clearLocation: location == null,
        isMit: _isMit,
      ));
    }

    final error = notifier.takeSyncError();
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
          backgroundColor: BentoTheme.darkCardAlt,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Abre la rueda neumórfica que ya usa la pestaña Alarma, en vez del
  /// `showTimePicker` de Material: la Agenda era el único sitio de la app que
  /// se salía del tema.
  Future<void> _pickStartTime() async {
    var picked = _startTime;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: BentoTheme.darkCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionLabel('Hora de inicio'),
            const SizedBox(height: 12),
            BentoTimePicker(
              initialTime: _startTime,
              onChanged: (t) => picked = t,
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BentoTheme.accentLime,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Listo',
                  style: GoogleFonts.montserrat(
                    color: const Color(0xFF0C0C0D),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _startTime = picked);
  }

  String _fmtDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h$m';
  }

  /// Hora de fin implícita, para no obligar a calcularla mentalmente.
  String get _endLabel {
    final total = _startTime.hour * 60 + _startTime.minute + _durationMinutes;
    final h = (total ~/ 60) % 24;
    final m = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : BentoTheme.creamAlpha(0.06),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? color : BentoTheme.creamAlpha(0.14)),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? color : BentoTheme.creamAlpha(0.6),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final task = widget.existing;
    if (task == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BentoTheme.darkCard,
        title: Text('¿Eliminar bloque?',
            style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700)),
        content: Text(task.title,
            style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context);
    await ref.read(tasksProvider.notifier).deleteTask(task.id);
  }

  Widget _timeChip({required String label, required VoidCallback onTap, VoidCallback? onClear}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: BentoTheme.creamAlpha(0.08),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: BentoTheme.creamAlpha(0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: BentoTheme.darkCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: BentoTheme.creamAlpha(0.2), borderRadius: BorderRadius.circular(100)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEditing ? 'Editar bloque' : 'Nuevo bloque',
                        style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w800, color: BentoTheme.cream),
                      ),
                      const Spacer(),
                      if (isEditing)
                        GestureDetector(
                          onTap: _confirmDelete,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.delete_outline, size: 21, color: BentoTheme.creamAlpha(0.55)),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: BentoTheme.creamAlpha(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: BentoTheme.creamAlpha(0.14)),
                          ),
                          child: Icon(Icons.close, size: 18, color: BentoTheme.creamAlpha(0.8)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          autofocus: widget.existing == null,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          onChanged: (_) {
                            if (_titleError != null) setState(() => _titleError = null);
                          },
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                          decoration: _darkFieldDecoration('Ej: Salir a correr', errorText: _titleError),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w500, fontSize: 13),
                          decoration: _darkFieldDecoration('Notas (opcional)'),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Empieza a las'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _timeChip(label: _startTime.format(context), onTap: _pickStartTime),
                            const SizedBox(width: 10),
                            Text(
                              'termina $_endLabel',
                              style: GoogleFonts.montserrat(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: BentoTheme.creamAlpha(0.45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Cuánto dura'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Si el bloque venía con una duración rara (por
                            // haberlo estirado en el timeline), se muestra como
                            // un chip más para no perderla al abrir el formulario.
                            for (final minutes in {..._durationPresets, _durationMinutes}.toList()..sort())
                              _choiceChip(
                                label: _fmtDuration(minutes),
                                selected: minutes == _durationMinutes,
                                color: BentoTheme.accentLime,
                                onTap: () => setState(() => _durationMinutes = minutes),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Dónde'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _locationController,
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w500, fontSize: 13),
                          // Decir dónde convierte un propósito en una intención
                          // de implementación, que es lo que de verdad sube la
                          // probabilidad de cumplirlo.
                          decoration: _darkFieldDecoration('En el parque, en casa… (opcional)'),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Prioridad'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: TaskPriority.values
                              .map((p) => _choiceChip(
                                    label: p.label,
                                    selected: p == _priority,
                                    color: p.color,
                                    onTap: () => setState(() => _priority = p),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: _sectionLabel('Uno de los 3 grandes')),
                            Switch(
                              value: _isMit,
                              onChanged: (v) => setState(() => _isMit = v),
                              activeThumbColor: BentoTheme.accentOrange,
                              activeTrackColor: BentoTheme.accentOrange.withValues(alpha: 0.3),
                              inactiveThumbColor: BentoTheme.creamAlpha(0.6),
                              inactiveTrackColor: BentoTheme.creamAlpha(0.12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionLabel('Recordarme'),
                            Switch(
                              value: _reminderEnabled,
                              onChanged: (v) => setState(() => _reminderEnabled = v),
                              activeThumbColor: BentoTheme.accentLime,
                              activeTrackColor: BentoTheme.accentLime.withValues(alpha: 0.3),
                              inactiveThumbColor: BentoTheme.creamAlpha(0.6),
                              inactiveTrackColor: BentoTheme.creamAlpha(0.12),
                            ),
                          ],
                        ),
                        if (_reminderEnabled)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Te avisaremos a las ${_startTime.format(context)}',
                              style: GoogleFonts.montserrat(fontSize: 12, color: BentoTheme.creamAlpha(0.5)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: BentoTheme.creamAlpha(0.08))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _submit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: BentoTheme.accentLime, borderRadius: BorderRadius.circular(100)),
                            child: Text(
                              isEditing ? 'Guardar' : 'Agregar',
                              style: GoogleFonts.montserrat(color: const Color(0xFF0C0C0D), fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
