import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../core/models/habit_model.dart';
import '../../core/models/habit_template.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';

/// Formulario de hábito en el sistema editorial.
///
/// Mismos campos y misma lógica de guardado que `habit_form_dialog.dart` —la
/// versión neumórfica, que sigue viva para la otra piel—, recompuesto entero en
/// papel sobre lienzo. Ver `DesignLanguage`: quién llama a cuál lo decide la
/// pestaña, no el import.
///
/// La composición cambia más de lo que parece. La versión anterior era una
/// pila de secciones etiquetadas todas iguales, así que el campo del nombre
/// —lo único obligatorio— pesaba lo mismo que la unidad de la meta. Aquí el
/// nombre y el ícono forman una **portadilla**: el ícono grande a la izquierda,
/// el nombre en tipografía de título al lado, y todo lo demás debajo en
/// registro de formulario. Se ve qué hábito estás creando antes de leer nada.
Future<void> showHabitFormEditorial(
  BuildContext context,
  WidgetRef ref, {
  Habit? existing,
  HabitTemplate? template,
}) {
  return showEditorialSheet<void>(
    context: context,
    title: existing == null ? 'Nuevo hábito' : 'Editar hábito',
    maxHeightFactor: 0.92,
    builder: (sheetContext, _) => _HabitFormBody(
      ref: ref,
      existing: existing,
      template: template,
    ),
  );
}

const List<String> _emojis = [
  '✅', '💧', '🧘', '📚', '🏃', '🍎', '😴', '💪', '✍️',
  '🎯', '🧠', '🚭', '🎨', '🙏', '💰', '🌱', '👟', '🤸',
];

const List<String> _colors = [
  '#758BFD',
  '#FF8600',
  '#8A84E2',
  '#38B000',
  '#D90429',
  '#27187E',
];

const List<String> _dayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Emoji que dispara el reparto automático de recordatorios de hidratación.
/// Vive como constante y no suelto en tres condiciones porque es la única
/// pieza de todo el formulario que tiene comportamiento propio.
const String _waterEmoji = '💧';

class _HabitFormBody extends StatefulWidget {
  const _HabitFormBody({required this.ref, this.existing, this.template});

  final WidgetRef ref;
  final Habit? existing;
  final HabitTemplate? template;

  @override
  State<_HabitFormBody> createState() => _HabitFormBodyState();
}

class _HabitFormBodyState extends State<_HabitFormBody> {
  late final TextEditingController _name;
  late final TextEditingController _goalValue;
  late final TextEditingController _goalUnit;
  late String _icon;
  late String _color;
  late HabitCategory _category;
  late Set<int> _days;
  late bool _remind;
  late List<TimeOfDay> _times;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    final t = widget.template;

    _name = TextEditingController(text: h?.name ?? t?.name ?? '');
    _goalValue = TextEditingController(text: _fmtGoal(h?.goalValue ?? t?.goalValue));
    _goalUnit = TextEditingController(text: h?.goalUnit ?? t?.goalUnit ?? '');
    _icon = h?.icon ?? t?.icon ?? _emojis.first;
    _color = h?.color ?? t?.color ?? _colors.first;
    _category = h?.category ?? t?.category ?? HabitCategory.general;
    _days = (h?.daysOfWeek ?? const [1, 2, 3, 4, 5, 6, 7]).toSet();
    _remind = h?.hasReminder ?? (t != null);
    _times = _initialTimes(h, t);
  }

  static List<TimeOfDay> _initialTimes(Habit? h, HabitTemplate? t) {
    if (h != null && h.reminderTimes.isNotEmpty) {
      return [
        for (final raw in h.reminderTimes)
          TimeOfDay(
            hour: int.parse(raw.split(':')[0]),
            minute: int.parse(raw.split(':')[1]),
          ),
      ];
    }
    final hour = h?.reminderHour ?? t?.reminderHour;
    final minute = h?.reminderMinute ?? t?.reminderMinute;
    if (hour != null && minute != null) {
      return [TimeOfDay(hour: hour, minute: minute)];
    }
    return [const TimeOfDay(hour: 12, minute: 0)];
  }

  static String _fmtGoal(double? v) {
    if (v == null) return '';
    return v % 1 == 0 ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _goalValue.dispose();
    _goalUnit.dispose();
    super.dispose();
  }

  /// Reparte los recordatorios de agua entre las 08:00 y las 21:00.
  ///
  /// Un vaso son 0.25 L, así que la meta en litros da el número de avisos; se
  /// acota entre 2 y 12 porque por debajo no sirve de recordatorio y por encima
  /// se vuelve una notificación cada media hora, que la gente silencia.
  void _spreadWaterReminders() {
    var goal = double.tryParse(_goalValue.text.trim().replaceAll(',', '.')) ?? 2.0;
    if (goal <= 0) goal = 2.0;

    final count = (goal / 0.25).round().clamp(2, 12);
    const startMinutes = 8 * 60;
    const endMinutes = 21 * 60;
    final step = (endMinutes - startMinutes) / (count - 1);

    setState(() {
      _remind = true;
      _times = [
        for (var i = 0; i < count; i++)
          TimeOfDay(
            hour: (startMinutes + i * step).round() ~/ 60,
            minute: (startMinutes + i * step).round() % 60,
          ),
      ];
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final notifier = widget.ref.read(habitsProvider.notifier);
    final goalValue = double.tryParse(_goalValue.text.trim().replaceAll(',', '.'));
    final goalUnit = _goalUnit.text.trim().isEmpty ? null : _goalUnit.text.trim();
    final sortedDays = _days.toList()..sort();

    final serialized = [
      for (final t in _times)
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    ];
    final first = _remind && _times.isNotEmpty ? _times.first : null;

    if (widget.existing == null) {
      notifier.addHabit(
        name: name,
        icon: _icon,
        color: _color,
        category: _category,
        daysOfWeek: sortedDays,
        goalValue: goalValue,
        goalUnit: goalUnit,
        reminderHour: first?.hour,
        reminderMinute: first?.minute,
        reminderTimes: _remind ? serialized : const [],
      );
    } else {
      notifier.updateHabit(widget.existing!.copyWith(
        name: name,
        icon: _icon,
        color: _color,
        category: _category,
        daysOfWeek: sortedDays,
        goalValue: goalValue,
        clearGoal: goalValue == null,
        goalUnit: goalUnit,
        reminderHour: first?.hour,
        reminderMinute: first?.minute,
        clearReminder: !_remind,
        reminderTimes: _remind ? serialized : const [],
      ));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              _portada(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Ícono'),
              const SizedBox(height: 12),
              _emojiGrid(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Color'),
              const SizedBox(height: 12),
              _colorRow(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Categoría'),
              const SizedBox(height: 12),
              _categoryWrap(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Meta diaria (opcional)'),
              const SizedBox(height: 12),
              _goalRow(),
              const SizedBox(height: 24),
              _reminderSection(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Qué días toca'),
              const SizedBox(height: 12),
              _daysRow(),
            ],
          ),
        ),
        // El botón vive fuera del scroll, apoyado en un filete: en una hoja
        // larga, un guardar que hay que buscar desplazándose es un guardar que
        // no se encuentra.
        const EditorialRule(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: EditorialButton(
            label: widget.existing == null ? 'Crear hábito' : 'Guardar cambios',
            onTap: _submit,
          ),
        ),
      ],
    );
  }

  /// Ícono grande + nombre: se ve el hábito antes de leer el formulario.
  Widget _portada() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EditorialTheme.gray,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Twemoji(emoji: _icon, height: 28, width: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: EditorialField(
            controller: _name,
            hint: 'Nombre del hábito',
            autofocus: widget.existing == null,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _emojiGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final emoji in _emojis)
          EditorialPressable(
            onTap: () => _pickEmoji(emoji),
            scale: 0.88,
            child: AnimatedContainer(
              duration: EditorialTheme.motion,
              curve: EditorialTheme.curve,
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // El emoji no se puede recolorear, así que la selección la
                // marca la superficie: gris apagado o tinta plena debajo.
                color: emoji == _icon ? EditorialTheme.ink : EditorialTheme.gray,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Twemoji(emoji: emoji, height: 21, width: 21),
            ),
          ),
      ],
    );
  }

  /// Elegir la gota prellena el hábito de agua entero: categoría, meta en
  /// litros y avisos repartidos por el día. Es el único hábito de la lista con
  /// una forma tan estándar que adivinarla acierta casi siempre; se prellena
  /// sólo lo que está vacío, para no pisar lo que el usuario ya escribió.
  void _pickEmoji(String emoji) {
    setState(() => _icon = emoji);
    if (emoji != _waterEmoji) return;

    setState(() {
      _category = HabitCategory.health;
      if (_goalUnit.text.trim().isEmpty) _goalUnit.text = 'L';
      if (_goalValue.text.trim().isEmpty) _goalValue.text = '2';
    });
    _spreadWaterReminders();
  }

  Widget _colorRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final hex in _colors)
          EditorialPressable(
            onTap: () => setState(() => _color = hex),
            scale: 0.85,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Normalizado a la lightness del papel, que es donde se va a
                // ver. Con el hex crudo, el usuario elige un tono y luego lo ve
                // distinto en los cuadraditos de la tarjeta.
                color: EditorialTheme.accentAt(_hex(hex), 0.54),
                shape: BoxShape.circle,
              ),
              child: hex == _color
                  ? const Icon(Icons.check, size: 17, color: EditorialTheme.paper)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _categoryWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in HabitCategory.values)
          EditorialChoice(
            label: category.label,
            icon: category.icon,
            compact: true,
            selected: category == _category,
            onTap: () => setState(() => _category = category),
          ),
      ],
    );
  }

  Widget _goalRow() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: EditorialField(
            controller: _goalValue,
            hint: 'Cantidad',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: EditorialField(
            controller: _goalUnit,
            hint: 'L, min, páginas…',
          ),
        ),
      ],
    );
  }

  Widget _reminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorialSectionLabel(
          'Recordatorios',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_icon == _waterEmoji)
                EditorialPressable(
                  onTap: _spreadWaterReminders,
                  scale: 0.85,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: 'Repartir avisos por el día',
                      child: Icon(Icons.auto_awesome,
                          size: 18, color: EditorialTheme.grayText),
                    ),
                  ),
                ),
              Switch.adaptive(
                value: _remind,
                activeThumbColor: EditorialTheme.paper,
                activeTrackColor: EditorialTheme.ink,
                inactiveThumbColor: EditorialTheme.paper,
                inactiveTrackColor: EditorialTheme.grayStrong,
                onChanged: (v) => setState(() => _remind = v),
              ),
            ],
          ),
        ),
        if (_remind) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _times.length; i++) _timeChip(i),
              _addTimeChip(),
            ],
          ),
        ],
      ],
    );
  }

  Widget _timeChip(int index) {
    final time = _times[index];
    return EditorialPressable(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: _pickerTheme,
        );
        if (picked != null && mounted) setState(() => _times[index] = picked);
      },
      scale: 0.93,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 9, 8, 9),
        decoration: BoxDecoration(
          color: EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time.format(context),
              style: EditorialTheme.text(
                13.5,
                weight: FontWeight.w600,
                color: EditorialTheme.ink,
              ),
            ),
            const SizedBox(width: 6),
            // Quitar la última hora dejaría los recordatorios encendidos y sin
            // ninguna: para eso está el interruptor, que además lo dice.
            if (_times.length > 1)
              EditorialPressable(
                onTap: () => setState(() => _times.removeAt(index)),
                scale: 0.8,
                child: Icon(Icons.close, size: 15, color: EditorialTheme.grayText),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addTimeChip() {
    return EditorialPressable(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 12, minute: 0),
          builder: _pickerTheme,
        );
        if (picked != null && mounted) setState(() => _times.add(picked));
      },
      scale: 0.93,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: EditorialTheme.ink,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 15, color: EditorialTheme.paper),
            const SizedBox(width: 5),
            Text(
              'Otra hora',
              style: EditorialTheme.text(
                13.5,
                weight: FontWeight.w600,
                color: EditorialTheme.paper,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Los siete días como una fila de fichas cuadradas.
  ///
  /// Cuadradas y no redondas a propósito: son las mismas siete columnas del
  /// mapa de calor y del selector de la pestaña, y compartir la forma es lo que
  /// hace que el formulario se lea como parte de la misma pieza.
  Widget _daysRow() {
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: EditorialTheme.dayGap),
          Expanded(
            child: EditorialPressable(
              onTap: () => setState(() {
                final day = i + 1;
                if (!_days.remove(day)) _days.add(day);
              }),
              scale: 0.9,
              child: AnimatedContainer(
                duration: EditorialTheme.motion,
                curve: EditorialTheme.curve,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _days.contains(i + 1)
                      ? EditorialTheme.ink
                      : EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  _dayLetters[i],
                  style: EditorialTheme.text(
                    14,
                    weight: FontWeight.w600,
                    color: _days.contains(i + 1)
                        ? EditorialTheme.paper
                        : EditorialTheme.grayText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pickerTheme(BuildContext context, Widget? child) => Theme(
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

  Color _hex(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));
}
