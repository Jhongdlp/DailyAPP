import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/task_model.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/theme/bento_theme.dart';

Widget _sectionLabel(String text) {
  return Text(
    text.toUpperCase(),
    style: GoogleFonts.montserrat(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: BentoTheme.creamAlpha(0.5)),
  );
}

InputDecoration _darkFieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
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
  late TimeOfDay _startTime;
  TimeOfDay? _endTime;
  late TaskPriority _priority;
  late bool _reminderEnabled;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _titleController = TextEditingController(text: t?.title ?? '');
    _notesController = TextEditingController(text: t?.notes ?? '');
    _startTime = t != null ? TimeOfDay.fromDateTime(t.startAt) : TimeOfDay.now();
    _endTime = t?.endAt != null ? TimeOfDay.fromDateTime(t!.endAt!) : null;
    _priority = t?.priority ?? TaskPriority.normal;
    _reminderEnabled = t?.hasReminder ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay time) =>
      DateTime(widget.day.year, widget.day.month, widget.day.day, time.hour, time.minute);

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final notifier = ref.read(tasksProvider.notifier);
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    final startAt = _combine(_startTime);
    var endAt = _endTime != null ? _combine(_endTime!) : null;
    if (endAt != null && !endAt.isAfter(startAt)) {
      endAt = endAt.add(const Duration(days: 1));
    }
    final remindAt = _reminderEnabled ? startAt : null;

    if (widget.existing == null) {
      notifier.addTask(
        title: title,
        notes: notes,
        dueDate: widget.day,
        startAt: startAt,
        endAt: endAt,
        remindAt: remindAt,
        priority: _priority,
      );
    } else {
      notifier.updateTask(widget.existing!.copyWith(
        title: title,
        notes: notes,
        clearNotes: notes == null,
        startAt: startAt,
        endAt: endAt,
        clearEndAt: endAt == null,
        remindAt: remindAt,
        clearReminder: !_reminderEnabled,
        priority: _priority,
      ));
    }
    Navigator.pop(context);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime ?? _startTime);
    if (picked != null) setState(() => _endTime = picked);
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
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                          decoration: _darkFieldDecoration('Ej: Salir a correr'),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w500, fontSize: 13),
                          decoration: _darkFieldDecoration('Notas (opcional)'),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Horario'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _timeChip(label: _startTime.format(context), onTap: _pickStartTime),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                              child: Text('–', style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.4))),
                            ),
                            _endTime != null
                                ? _timeChip(
                                    label: _endTime!.format(context),
                                    onTap: _pickEndTime,
                                    onClear: () => setState(() => _endTime = null),
                                  )
                                : GestureDetector(
                                    onTap: _pickEndTime,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(100),
                                        border: Border.all(color: BentoTheme.accentLime.withValues(alpha: 0.5)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add, size: 15, color: BentoTheme.accentLime),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Hora de fin',
                                            style: GoogleFonts.montserrat(color: BentoTheme.accentLime, fontWeight: FontWeight.w600, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Prioridad'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: TaskPriority.values.map((p) {
                            final selected = p == _priority;
                            return GestureDetector(
                              onTap: () => setState(() => _priority = p),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? p.color.withValues(alpha: 0.18) : BentoTheme.creamAlpha(0.06),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: selected ? p.color : BentoTheme.creamAlpha(0.14)),
                                ),
                                child: Text(
                                  p.label,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? p.color : BentoTheme.creamAlpha(0.6),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
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
