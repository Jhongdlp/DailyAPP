import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/habit_model.dart';
import '../../../../core/models/task_model.dart';
import '../../../../core/providers/habits_provider.dart';
import '../../../../core/providers/tasks_provider.dart';
import '../../../../core/theme/bento_theme.dart';
import '../../timeline_scale.dart';
import '../night_planning_screen.dart';

/// Paso 3 — dar hora a los hábitos que tocan mañana.
///
/// Un hábito sin hora concreta es un deseo. Este paso existe para convertir
/// "quiero leer más" en "leo a las 21:00", que es la diferencia real entre
/// cumplirlo y no.
class StepHabits extends ConsumerStatefulWidget {
  final DateTime planDay;
  final VoidCallback onNext;

  const StepHabits({super.key, required this.planDay, required this.onNext});

  @override
  ConsumerState<StepHabits> createState() => _StepHabitsState();
}

class _StepHabitsState extends ConsumerState<StepHabits> {
  bool _working = false;

  int? _usualMinutesOf(Habit habit) {
    if (habit.reminderTimes.isNotEmpty) {
      final parts = habit.reminderTimes.first.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) return h * 60 + m;
      }
    }
    if (habit.reminderHour != null && habit.reminderMinute != null) {
      return habit.reminderHour! * 60 + habit.reminderMinute!;
    }
    return null;
  }

  List<Habit> get _dueHabits => ref
      .read(habitsProvider)
      .where((h) => !h.archived && h.isActiveOn(widget.planDay))
      .toList();

  List<Task> get _planned => ref.read(tasksProvider.notifier).tasksForDay(widget.planDay);

  Task? _blockFor(Habit habit) {
    for (final t in _planned) {
      if (t.habitId == habit.id) return t;
    }
    return null;
  }

  /// Ancla el hábito al final de lo último ya planeado. Encadenarlo a algo que
  /// ya ocurre sostiene el hábito mucho mejor que dejarlo suelto en un hueco.
  int _anchorMinutes() {
    final planned = _planned;
    if (planned.isEmpty) return 8 * 60;
    final lastEnd = planned.map(endMinutesOf).reduce((a, b) => a > b ? a : b);
    if (lastEnd >= TimelineScale.minutesPerDay - 30) return 8 * 60;
    return TimelineScale.snap(lastEnd);
  }

  Future<void> _place(Habit habit) async {
    final usual = _usualMinutesOf(habit);
    final minutes = usual ?? _anchorMinutes();
    final start = widget.planDay.add(Duration(minutes: minutes));

    // Si cae en su hora de siempre, el recordatorio del propio hábito ya
    // suena entonces: poner otro haría sonar dos avisos en el mismo minuto.
    await ref.read(tasksProvider.notifier).addTask(
          title: habit.name,
          dueDate: widget.planDay,
          startAt: start,
          endAt: start.add(const Duration(minutes: 30)),
          remindAt: usual == null ? start : null,
          habitId: habit.id,
          blockType: BlockType.habit,
          plannedAt: DateTime.now(),
        );
  }

  Future<void> _placeAll() async {
    if (_working) return;
    setState(() => _working = true);
    for (final habit in _dueHabits) {
      if (_blockFor(habit) == null) await _place(habit);
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _remove(Task block) =>
      ref.read(tasksProvider.notifier).deleteTask(block.id);

  String _fmt(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    ref.watch(habitsProvider);

    final due = _dueHabits;
    final unplaced = due.where((h) => _blockFor(h) == null).length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NightStepHeading(
                  title: 'Tus hábitos',
                  subtitle: 'Dales una hora concreta. Un hábito con hora se cumple; uno "en algún momento", no.',
                ),
                const SizedBox(height: 22),
                if (due.isEmpty)
                  Text(
                    'Mañana no toca ningún hábito.',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: BentoTheme.creamAlpha(0.45),
                    ),
                  )
                else ...[
                  if (unplaced > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: GestureDetector(
                        onTap: _placeAll,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: BentoTheme.accentLime.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: BentoTheme.accentLime.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            _working ? 'Colocando…' : 'Colocar los $unplaced en su hora de siempre',
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: BentoTheme.accentLime,
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (final habit in due) _buildRow(habit),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: NightStepButton(label: 'Siguiente', onTap: widget.onNext),
        ),
      ],
    );
  }

  Widget _buildRow(Habit habit) {
    final block = _blockFor(habit);
    final placed = block != null;
    final color = habit.colorValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => placed ? _remove(block) : _place(habit),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: placed ? color.withValues(alpha: 0.12) : BentoTheme.creamAlpha(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: placed ? color.withValues(alpha: 0.5) : BentoTheme.creamAlpha(0.1),
            ),
          ),
          child: Row(
            children: [
              Text(habit.icon, style: const TextStyle(fontSize: 17)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  habit.name,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: placed ? BentoTheme.cream : BentoTheme.creamAlpha(0.65),
                  ),
                ),
              ),
              if (placed)
                Text(
                  _fmt(minutesOfDay(block.startAt)),
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                placed ? Icons.check_circle : Icons.add_circle_outline,
                size: 20,
                color: placed ? color : BentoTheme.creamAlpha(0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
