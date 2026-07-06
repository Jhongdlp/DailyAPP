import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/habit_model.dart';
import '../../core/models/habit_template.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/theme/bento_theme.dart';

const List<String> _kEmojiChoices = [
  '✅', '💧', '🧘', '📚', '🏃', '🍎', '😴', '💪', '✍️', '🎯', '🧠', '🚭', '🎨', '🙏', '💰', '🌱',
];

const List<String> _kColorChoices = [
  '#758BFD', // accentBlue
  '#FF8600', // accentOrange
  '#8A84E2', // accentPurple
  '#38B000', // successGreen
  '#D90429', // errorRed
  '#27187E', // primaryDark
];

const List<String> _kDayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Abre el diálogo de creación/edición de hábito. Si [existing] es null crea uno nuevo.
/// Si se pasa [template], prellena nombre/ícono/color/categoría/meta/recordatorio sugeridos.
Future<void> showHabitFormDialog(BuildContext context, WidgetRef ref, {Habit? existing, HabitTemplate? template}) {
  return showDialog(
    context: context,
    builder: (context) => _HabitFormDialog(existing: existing, template: template),
  );
}

class _HabitFormDialog extends ConsumerStatefulWidget {
  final Habit? existing;
  final HabitTemplate? template;
  const _HabitFormDialog({this.existing, this.template});

  @override
  ConsumerState<_HabitFormDialog> createState() => _HabitFormDialogState();
}

String _formatGoalValue(double? v) {
  if (v == null) return '';
  return v % 1 == 0 ? v.toInt().toString() : v.toString();
}

class _HabitFormDialogState extends ConsumerState<_HabitFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _goalValueController;
  late final TextEditingController _goalUnitController;
  late String _icon;
  late String _color;
  late HabitCategory _category;
  late Set<int> _days;
  late bool _reminderEnabled;
  late List<TimeOfDay> _reminderTimes;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    final t = widget.template;
    _nameController = TextEditingController(text: h?.name ?? t?.name ?? '');
    _goalValueController = TextEditingController(text: _formatGoalValue(h?.goalValue ?? t?.goalValue));
    _goalUnitController = TextEditingController(text: h?.goalUnit ?? t?.goalUnit ?? '');
    _icon = h?.icon ?? t?.icon ?? _kEmojiChoices.first;
    _color = h?.color ?? t?.color ?? _kColorChoices.first;
    _category = h?.category ?? t?.category ?? HabitCategory.general;
    _days = (h?.daysOfWeek ?? const [1, 2, 3, 4, 5, 6, 7]).toSet();
    _reminderEnabled = h?.hasReminder ?? (t != null);

    _reminderTimes = [];
    if (h != null && h.reminderTimes.isNotEmpty) {
      for (final tStr in h.reminderTimes) {
        final parts = tStr.split(':');
        _reminderTimes.add(TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        ));
      }
    } else {
      final initialHour = h?.reminderHour ?? t?.reminderHour;
      final initialMinute = h?.reminderMinute ?? t?.reminderMinute;
      if (initialHour != null && initialMinute != null) {
        _reminderTimes.add(TimeOfDay(hour: initialHour, minute: initialMinute));
      } else if (t != null) {
        _reminderTimes.add(TimeOfDay(hour: t.reminderHour, minute: t.reminderMinute));
      } else {
        _reminderTimes.add(const TimeOfDay(hour: 12, minute: 0));
      }
    }
  }

  void _updateAutomaticWaterReminders() {
    final valText = _goalValueController.text.trim().replaceAll(',', '.');
    double val = double.tryParse(valText) ?? 2.0;
    if (val <= 0) val = 2.0;

    int N = (val / 0.25).round();
    if (N < 2) N = 2;
    if (N > 12) N = 12;

    const startMinutes = 8 * 60; // 08:00
    const endMinutes = 21 * 60; // 21:00
    final totalMinutes = endMinutes - startMinutes;

    final newTimes = <TimeOfDay>[];
    final interval = totalMinutes / (N - 1);
    for (int i = 0; i < N; i++) {
      final currentMinutes = (startMinutes + i * interval).round();
      final hour = currentMinutes ~/ 60;
      final minute = currentMinutes % 60;
      newTimes.add(TimeOfDay(hour: hour, minute: minute));
    }

    setState(() {
      _reminderEnabled = true;
      _reminderTimes = newTimes;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalValueController.dispose();
    _goalUnitController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final sortedDays = _days.toList()..sort();
    final notifier = ref.read(habitsProvider.notifier);
    final goalValue = double.tryParse(_goalValueController.text.trim().replaceAll(',', '.'));
    final goalUnit = _goalUnitController.text.trim().isEmpty ? null : _goalUnitController.text.trim();

    final stringList = _reminderTimes.map((t) {
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }).toList();

    final reminderHour = _reminderEnabled && _reminderTimes.isNotEmpty ? _reminderTimes.first.hour : null;
    final reminderMinute = _reminderEnabled && _reminderTimes.isNotEmpty ? _reminderTimes.first.minute : null;
    final reminderTimesList = _reminderEnabled ? stringList : <String>[];

    if (widget.existing == null) {
      notifier.addHabit(
        name: name,
        icon: _icon,
        color: _color,
        category: _category,
        daysOfWeek: sortedDays,
        goalValue: goalValue,
        goalUnit: goalUnit,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        reminderTimes: reminderTimesList,
      );
    } else {
      notifier.updateHabit(widget.existing!.copyWith(
        name: name,
        icon: _icon,
        color: _color,
        category: _category,
        daysOfWeek: sortedDays,
        goalValue: goalValue,
        goalUnit: goalUnit,
        clearGoal: goalValue == null,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        clearReminder: !_reminderEnabled,
        reminderTimes: reminderTimesList,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      backgroundColor: BentoTheme.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: BentoTheme.primaryDark, width: 2),
      ),
      title: Text(
        isEditing ? 'Editar Hábito' : 'Crear Nuevo Hábito',
        style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(hintText: 'Ej: Hacer 30 mins de Ejercicio'),
            ),
            const SizedBox(height: 16),
            const Text('Ícono', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kEmojiChoices.map((e) {
                final selected = e == _icon;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _icon = e;
                      if (e == '💧') {
                        _category = HabitCategory.health;
                        if (_goalUnitController.text.trim().isEmpty) {
                          _goalUnitController.text = 'L';
                        }
                        if (_goalValueController.text.trim().isEmpty) {
                          _goalValueController.text = '2';
                        }
                        _updateAutomaticWaterReminders();
                      }
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? BentoTheme.borderMuted : Colors.transparent,
                      border: Border.all(color: selected ? BentoTheme.primaryDark : BentoTheme.borderMuted, width: 2),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 16)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Color', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kColorChoices.map((c) {
                final selected = c == _color;
                final swatch = Color(int.parse(c.replaceFirst('#', '0xFF')));
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: swatch,
                      border: Border.all(color: selected ? BentoTheme.textPrimary : Colors.transparent, width: 3),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Categoría', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HabitCategory.values.map((c) {
                final selected = c == _category;
                return ChoiceChip(
                  label: Text(c.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = c),
                  selectedColor: c.color.withOpacity(0.18),
                  labelStyle: TextStyle(
                    color: selected ? c.color : BentoTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  side: BorderSide(color: selected ? c.color : BentoTheme.borderMuted, width: 2),
                  backgroundColor: Colors.transparent,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Meta (opcional)', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _goalValueController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(hintText: 'Ej: 2'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _goalUnitController,
                    style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(hintText: 'Unidad: L, min, páginas...'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recordarme', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_icon == '💧')
                      IconButton(
                        tooltip: 'Generar recordatorios automáticos de agua',
                        icon: const Icon(Icons.auto_awesome, color: BentoTheme.primaryDark),
                        onPressed: _updateAutomaticWaterReminders,
                      ),
                    Switch(
                      value: _reminderEnabled,
                      onChanged: (v) => setState(() => _reminderEnabled = v),
                      activeThumbColor: BentoTheme.primaryDark,
                    ),
                  ],
                ),
              ],
            ),
            if (_reminderEnabled) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...List.generate(_reminderTimes.length, (index) {
                    final time = _reminderTimes[index];
                    return InputChip(
                      label: Text(
                        time.format(context),
                        style: const TextStyle(
                          color: BentoTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      backgroundColor: BentoTheme.borderMuted,
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: time,
                        );
                        if (picked != null) {
                          setState(() {
                            _reminderTimes[index] = picked;
                          });
                        }
                      },
                      onDeleted: () {
                        setState(() {
                          _reminderTimes.removeAt(index);
                        });
                      },
                      deleteIconColor: BentoTheme.errorRed,
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16, color: BentoTheme.primaryDark),
                    label: const Text(
                      'Añadir hora',
                      style: TextStyle(
                        color: BentoTheme.primaryDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 12, minute: 0),
                      );
                      if (picked != null) {
                        setState(() {
                          _reminderTimes.add(picked);
                        });
                      }
                    },
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(color: BentoTheme.primaryDark, width: 1.5),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text('Días activos', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final day = i + 1;
                final active = _days.contains(day);
                const cellSize = 32.0;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (active) {
                      _days.remove(day);
                    } else {
                      _days.add(day);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: cellSize,
                    height: cellSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? BentoTheme.primaryDark : BentoTheme.borderMuted,
                    ),
                    child: Center(
                      child: Text(
                        _kDayLabels[i],
                        style: TextStyle(
                          color: active ? Colors.white : BentoTheme.textSecondary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Guardar' : 'Agregar'),
        ),
      ],
    );
  }
}
