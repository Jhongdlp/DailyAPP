import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// Abre el modal de creación/edición de hábito. Si [existing] es null crea uno nuevo.
/// Si se pasa [template], prellena nombre/ícono/color/categoría/meta/recordatorio sugeridos.
Future<void> showHabitFormDialog(BuildContext context, WidgetRef ref, {Habit? existing, HabitTemplate? template}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _HabitFormSheet(existing: existing, template: template),
  );
}

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
      borderSide: BorderSide(color: BentoTheme.accentHabits, width: 1.5),
    ),
  );
}

class _HabitFormSheet extends ConsumerStatefulWidget {
  final Habit? existing;
  final HabitTemplate? template;
  const _HabitFormSheet({this.existing, this.template});

  @override
  ConsumerState<_HabitFormSheet> createState() => _HabitFormSheetState();
}

String _formatGoalValue(double? v) {
  if (v == null) return '';
  return v % 1 == 0 ? v.toInt().toString() : v.toString();
}

class _HabitFormSheetState extends ConsumerState<_HabitFormSheet> {
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

    int n = (val / 0.25).round();
    if (n < 2) n = 2;
    if (n > 12) n = 12;

    const startMinutes = 8 * 60; // 08:00
    const endMinutes = 21 * 60; // 21:00
    final totalMinutes = endMinutes - startMinutes;

    final newTimes = <TimeOfDay>[];
    final interval = totalMinutes / (n - 1);
    for (int i = 0; i < n; i++) {
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
        clearGoal: goalValue == null,
        goalUnit: goalUnit,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        clearReminder: !_reminderEnabled,
        reminderTimes: reminderTimesList,
      ));
    }
    Navigator.pop(context);
  }

  Widget _buildTimeChip(int index, TimeOfDay time) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: time);
        if (picked != null) setState(() => _reminderTimes[index] = picked);
      },
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
              time.format(context),
              style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() => _reminderTimes.removeAt(index)),
              child: Icon(Icons.close, size: 16, color: BentoTheme.creamAlpha(0.5)),
            ),
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
        initialChildSize: 0.9,
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
                        isEditing ? 'Editar hábito' : 'Nuevo hábito',
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
                          controller: _nameController,
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                          decoration: _darkFieldDecoration('Ej: Hacer 30 mins de ejercicio'),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Ícono'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
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
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected ? BentoTheme.accentHabits.withValues(alpha: 0.16) : BentoTheme.creamAlpha(0.06),
                                  border: Border.all(color: selected ? BentoTheme.accentHabits : BentoTheme.creamAlpha(0.14), width: selected ? 2 : 1.5),
                                ),
                                child: Text(e, style: const TextStyle(fontSize: 17)),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Color'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _kColorChoices.map((c) {
                            final selected = c == _color;
                            final swatch = Color(int.parse(c.replaceFirst('#', '0xFF')));
                            return GestureDetector(
                              onTap: () => setState(() => _color = c),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: swatch,
                                  border: Border.all(color: selected ? BentoTheme.cream : Colors.transparent, width: 3),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Categoría'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: HabitCategory.values.map((c) {
                            final selected = c == _category;
                            return GestureDetector(
                              onTap: () => setState(() => _category = c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? c.color.withValues(alpha: 0.18) : BentoTheme.creamAlpha(0.06),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: selected ? c.color : BentoTheme.creamAlpha(0.14)),
                                ),
                                child: Text(
                                  c.label,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? c.color : BentoTheme.creamAlpha(0.6),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('Meta (opcional)'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _goalValueController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                                decoration: _darkFieldDecoration('Ej: 2'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _goalUnitController,
                                style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                                decoration: _darkFieldDecoration('Unidad: L, min, páginas...'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionLabel('Recordarme'),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_icon == '💧')
                                  GestureDetector(
                                    onTap: _updateAutomaticWaterReminders,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Icon(Icons.auto_awesome, size: 20, color: BentoTheme.accentHabits),
                                    ),
                                  ),
                                Switch(
                                  value: _reminderEnabled,
                                  onChanged: (v) => setState(() => _reminderEnabled = v),
                                  activeThumbColor: BentoTheme.accentHabits,
                                  activeTrackColor: BentoTheme.accentHabits.withValues(alpha: 0.3),
                                  inactiveThumbColor: BentoTheme.creamAlpha(0.6),
                                  inactiveTrackColor: BentoTheme.creamAlpha(0.12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_reminderEnabled) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ...List.generate(_reminderTimes.length, (index) => _buildTimeChip(index, _reminderTimes[index])),
                              GestureDetector(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: const TimeOfDay(hour: 12, minute: 0),
                                  );
                                  if (picked != null) setState(() => _reminderTimes.add(picked));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(color: BentoTheme.accentHabits.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add, size: 15, color: BentoTheme.accentHabits),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Añadir hora',
                                        style: GoogleFonts.montserrat(color: BentoTheme.accentHabits, fontWeight: FontWeight.w600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        _sectionLabel('Días activos'),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(7, (i) {
                            final day = i + 1;
                            final active = _days.contains(day);
                            const cellSize = 34.0;
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
                                  color: active ? BentoTheme.accentHabits : BentoTheme.creamAlpha(0.08),
                                ),
                                child: Center(
                                  child: Text(
                                    _kDayLabels[i],
                                    style: GoogleFonts.montserrat(
                                      color: active ? const Color(0xFF0C0C0D) : BentoTheme.creamAlpha(0.5),
                                      fontWeight: FontWeight.w800,
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
                            decoration: BoxDecoration(color: BentoTheme.accentHabits, borderRadius: BorderRadius.circular(100)),
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
