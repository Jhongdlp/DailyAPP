import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/habit_model.dart';
import '../../../core/theme/bento_theme.dart';

/// Bandeja con los hábitos que tocan un día y aún no están colocados en el
/// timeline.
///
/// Es la pieza que hace que planear la noche sirva de algo para los hábitos:
/// en vez de recordar cuáles tocan mañana, están ahí delante pidiendo una
/// hora. Colocar un hábito es darle un cuándo, y un hábito con hora concreta
/// se cumple mucho más que uno que "hay que hacer en algún momento".
class HabitTray extends StatelessWidget {
  final List<Habit> pending;

  /// Coloca un hábito concreto, en su hora habitual si la tiene.
  final void Function(Habit habit) onPlace;

  /// Coloca de golpe todos los que tienen hora habitual.
  final VoidCallback? onPlaceAll;

  /// Cuántos de los pendientes tienen hora habitual guardada.
  final int withUsualTime;

  const HabitTray({
    super.key,
    required this.pending,
    required this.onPlace,
    required this.withUsualTime,
    this.onPlaceAll,
  });

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 20, 8),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_outlined, size: 15, color: BentoTheme.creamAlpha(0.5)),
                const SizedBox(width: 6),
                Text(
                  'Sin hora todavía',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.creamAlpha(0.5),
                  ),
                ),
                const Spacer(),
                // Un solo toque coloca la columna vertebral del día. Es el
                // atajo que hace que el ritual dure un minuto y no diez.
                if (onPlaceAll != null && withUsualTime > 1)
                  GestureDetector(
                    onTap: onPlaceAll,
                    child: Text(
                      'usar mis horarios',
                      style: GoogleFonts.montserrat(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.accentLime,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: pending.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final habit = pending[index];
                return _HabitChip(habit: habit, onTap: () => onPlace(habit));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitChip extends StatelessWidget {
  final Habit habit;
  final VoidCallback onTap;

  const _HabitChip({required this.habit, required this.onTap});

  String? get _usualTime => habit.reminderTimes.isNotEmpty
      ? habit.reminderTimes.first
      : (habit.reminderHour != null && habit.reminderMinute != null
          ? '${habit.reminderHour.toString().padLeft(2, '0')}:${habit.reminderMinute.toString().padLeft(2, '0')}'
          : null);

  @override
  Widget build(BuildContext context) {
    final color = habit.colorValue;
    final usual = _usualTime;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(habit.icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              habit.name,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: BentoTheme.cream,
              ),
            ),
            if (usual != null) ...[
              const SizedBox(width: 6),
              Text(
                usual,
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BentoTheme.creamAlpha(0.5),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.add, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
