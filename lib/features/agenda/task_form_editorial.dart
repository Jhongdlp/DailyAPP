import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task_model.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import '../alarm/widgets/editorial_time_picker.dart';

/// Formulario de bloque de agenda en el sistema editorial.
///
/// Mismos campos y misma lógica de guardado que `task_form_dialog.dart`. Lo que
/// cambia es dónde cae el peso.
///
/// La versión anterior abría con dos campos de texto —nombre y notas— del mismo
/// tamaño, y el *cuándo* quedaba en tercer lugar detrás de ellos. Pero un
/// bloque de agenda es una hora antes que un título: lo que decides al crearlo
/// es a qué hora va y cuánto dura. Aquí eso sube a una **lámina de horario**
/// justo debajo del nombre, con la hora de inicio y la duración leyéndose como
/// una frase —"08:30, 45m, termina 09:15"— en vez de como tres controles.
///
/// Las notas bajan al final, donde corresponde a un campo que casi nadie
/// rellena.
Future<void> showTaskFormEditorial(
  BuildContext context,
  WidgetRef ref, {
  required DateTime day,
  Task? existing,
}) {
  return showEditorialSheet<void>(
    context: context,
    title: existing == null ? 'Nuevo bloque' : 'Editar bloque',
    maxHeightFactor: 0.92,
    builder: (sheetContext, _) => _TaskFormBody(day: day, existing: existing),
  );
}

class _TaskFormBody extends ConsumerStatefulWidget {
  const _TaskFormBody({required this.day, this.existing});

  final DateTime day;
  final Task? existing;

  @override
  ConsumerState<_TaskFormBody> createState() => _TaskFormBodyState();
}

class _TaskFormBodyState extends ConsumerState<_TaskFormBody> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _location;
  late TimeOfDay _startTime;

  /// Duración en minutos. Sustituye al segundo selector de hora: elegir "1h" es
  /// un toque, contra los cuatro que costaba abrir un reloj, mover la aguja y
  /// aceptar.
  late int _durationMinutes;

  late TaskPriority _priority;
  late bool _remind;
  late bool _isMit;
  String? _titleError;

  static const _durationPresets = [15, 30, 45, 60, 90, 120];

  static final Color _destructive =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.52);

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _location = TextEditingController(text: t?.location ?? '');
    _startTime = t != null ? TimeOfDay.fromDateTime(t.startAt) : TimeOfDay.now();
    _durationMinutes = t?.durationMinutes ?? 30;
    if (_durationMinutes <= 0) _durationMinutes = 30;
    _priority = t?.priority ?? TaskPriority.normal;
    _remind = t?.hasReminder ?? true;
    _isMit = t?.isMit ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _location.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay time) => DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
        time.hour,
        time.minute,
      );

  /// Hora de fin implícita, para no obligar a calcularla mentalmente.
  String get _endLabel {
    final total = _startTime.hour * 60 + _startTime.minute + _durationMinutes;
    final h = (total ~/ 60) % 24;
    final m = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h$m';
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      // Un `return` mudo dejaba la hoja quieta sin explicar por qué no pasaba
      // nada; el error va pegado al campo que lo causa.
      setState(() => _titleError = 'Ponle un nombre al bloque');
      return;
    }

    final notifier = ref.read(tasksProvider.notifier);
    // Se captura antes del pop: después, el context de esta hoja ya no sirve.
    final messenger = ScaffoldMessenger.of(context);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final location = _location.text.trim().isEmpty ? null : _location.text.trim();
    final startAt = _combine(_startTime);
    // La duración siempre es positiva, así que el fin nunca cae antes del
    // inicio; si cruza medianoche, `add` ya lo lleva al día siguiente.
    final endAt = startAt.add(Duration(minutes: _durationMinutes));

    // Se cierra de inmediato —el bloque ya está en la lista por el insert
    // optimista— pero se sigue esperando para poder avisar si el sync falló.
    Navigator.of(context).pop();

    if (widget.existing == null) {
      await notifier.addTask(
        title: title,
        notes: notes,
        dueDate: widget.day,
        startAt: startAt,
        endAt: endAt,
        remindAt: _remind ? startAt : null,
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
        remindAt: _remind ? startAt : null,
        clearReminder: !_remind,
        priority: _priority,
        location: location,
        clearLocation: location == null,
        isMit: _isMit,
      ));
    }

    final error = notifier.takeSyncError();
    if (error == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(error, style: EditorialTheme.text(14, color: EditorialTheme.ink)),
        backgroundColor: EditorialTheme.paper,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    var picked = _startTime;

    await showEditorialSheet<void>(
      context: context,
      title: 'Hora de inicio',
      maxHeightFactor: 0.55,
      builder: (pickerContext, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorialTimePicker(
              initialTime: _startTime,
              onChanged: (t) => picked = t,
            ),
            const SizedBox(height: 20),
            EditorialButton(
              label: 'Listo',
              onTap: () => Navigator.of(pickerContext).pop(),
            ),
          ],
        ),
      ),
    );

    if (mounted) setState(() => _startTime = picked);
  }

  Future<void> _confirmDelete() async {
    final task = widget.existing;
    if (task == null) return;

    final navigator = Navigator.of(context);
    final ok = await confirmEditorial(
      context,
      title: 'ELIMINAR BLOQUE',
      body: 'Se borra "${task.title}" del día. No se puede deshacer.',
    );
    if (!ok) return;

    await ref.read(tasksProvider.notifier).deleteTask(task.id);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              EditorialField(
                controller: _title,
                hint: 'Salir a correr',
                autofocus: !editing,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              if (_titleError != null) ...[
                const SizedBox(height: 7),
                Text(
                  _titleError!,
                  style: EditorialTheme.text(
                    12.5,
                    weight: FontWeight.w600,
                    color: _destructive,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _schedulePanel(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Dónde'),
              const SizedBox(height: 10),
              EditorialField(
                controller: _location,
                // Decir dónde convierte un propósito en una intención de
                // implementación, que es lo que de verdad sube la probabilidad
                // de cumplirlo.
                hint: 'En el parque, en casa… (opcional)',
                prefix: Icon(Icons.place_outlined,
                    size: 17, color: EditorialTheme.grayText),
              ),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Prioridad'),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final p in TaskPriority.values) ...[
                    if (p != TaskPriority.values.first) const SizedBox(width: 7),
                    Expanded(
                      child: EditorialChoice(
                        label: p.label,
                        compact: true,
                        selected: p == _priority,
                        onTap: () => setState(() => _priority = p),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              _toggle(
                'Uno de los 3 grandes',
                'Los tres bloques que de verdad mueven el día.',
                _isMit,
                (v) => setState(() => _isMit = v),
              ),
              const SizedBox(height: 16),
              _toggle(
                'Recordarme',
                _remind
                    ? 'Te aviso a las ${_startTime.format(context)}.'
                    : 'Sin aviso: tendrás que acordarte tú.',
                _remind,
                (v) => setState(() => _remind = v),
              ),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Notas'),
              const SizedBox(height: 10),
              EditorialField(
                controller: _notes,
                hint: 'Opcional',
                maxLines: 3,
              ),
            ],
          ),
        ),
        const EditorialRule(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(
            children: [
              if (editing) ...[
                EditorialPressable(
                  onTap: _confirmDelete,
                  scale: 0.9,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: EditorialTheme.gray,
                      borderRadius:
                          BorderRadius.circular(EditorialTheme.radiusChip),
                    ),
                    child: Icon(Icons.delete_outline, size: 20, color: _destructive),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: EditorialButton(
                  label: editing ? 'Guardar cambios' : 'Añadir al día',
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// El horario, en una lámina propia.
  ///
  /// Es lo que de verdad se decide al crear un bloque, y aquí se lee de un
  /// tirón: hora de inicio grande, duración en chips debajo, y la hora de fin
  /// calculada al lado para no tener que sumar de cabeza.
  Widget _schedulePanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: EditorialTheme.gray,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialSectionLabel('Cuándo'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              EditorialPressable(
                onTap: _pickStartTime,
                scale: 0.94,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: EditorialTheme.paper,
                    borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
                  ),
                  child: Text(
                    _startTime.format(context),
                    style: EditorialTheme.caps(
                      26,
                      color: EditorialTheme.ink,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'termina $_endLabel',
                style: EditorialTheme.text(13, color: EditorialTheme.grayText),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const EditorialSectionLabel('Cuánto dura'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              // Si el bloque venía con una duración rara —por haberlo estirado
              // en el timeline— se muestra como un chip más, para no perderla
              // al abrir el formulario.
              for (final minutes in {..._durationPresets, _durationMinutes}.toList()..sort())
                EditorialChoice(
                  label: _fmtDuration(minutes),
                  compact: true,
                  selected: minutes == _durationMinutes,
                  onTap: () => setState(() => _durationMinutes = minutes),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: EditorialTheme.label(11, color: EditorialTheme.grayText),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: EditorialTheme.text(
                  13,
                  color: EditorialTheme.inkAlpha(0.55),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeThumbColor: EditorialTheme.paper,
          activeTrackColor: EditorialTheme.ink,
          inactiveThumbColor: EditorialTheme.paper,
          inactiveTrackColor: EditorialTheme.grayStrong,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
