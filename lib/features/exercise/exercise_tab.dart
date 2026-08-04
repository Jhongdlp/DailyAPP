import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/habit_model.dart';
import '../../core/providers/exercise_habit_link_provider.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/widgets/streak_flame.dart';
import 'exercise_capture_flow.dart';
import 'exercise_gallery_screen.dart';
import 'exercise_stats.dart';
import 'exercise_stats_screen.dart';
import 'widgets/exercise_log_form.dart';
import 'widgets/exercise_weekly_chart.dart';
import 'widgets/link_habit_sheet.dart';

class ExerciseTab extends ConsumerWidget {
  const ExerciseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final linkedId = ref.watch(exerciseHabitLinkProvider);
    Habit? linkedHabit;
    if (linkedId != null) {
      for (final h in habits) {
        if (h.id == linkedId && !h.archived) {
          linkedHabit = h;
          break;
        }
      }
    }

    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      child: linkedHabit == null ? _GateScreen(habits: habits) : _ExerciseContent(habit: linkedHabit),
    );
  }
}

class _GateScreen extends ConsumerWidget {
  final List<Habit> habits;
  const _GateScreen({required this.habits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = autoDetectExerciseHabits(habits);
    final suggestion = suggestions.length == 1 ? suggestions.first : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: NeuCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, color: BentoTheme.accentOrange, size: 48),
              const SizedBox(height: 16),
              Text(
                'Vincula tu hábito de ejercicio',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Para llevar tu registro de ejercicio primero necesitas el hábito que usas para "hacer ejercicio". Créalo o vincula uno que ya tengas.',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (suggestion != null) ...[
                Text(
                  '¿Es este tu hábito de ejercicio?',
                  style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.7), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => ref.read(exerciseHabitLinkProvider.notifier).setLinkedHabit(suggestion.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BentoTheme.accentOrange,
                      foregroundColor: const Color(0xFF0C0C0D),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Sí, usar "${suggestion.name}"',
                      style: GoogleFonts.montserrat(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => showLinkHabitSheet(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BentoTheme.cream,
                    side: BorderSide(color: BentoTheme.creamAlpha(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    suggestion != null ? 'Elegir otro hábito' : 'Vincular o crear hábito',
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseContent extends ConsumerWidget {
  final Habit habit;
  const _ExerciseContent({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseState = ref.watch(exerciseProvider);
    final now = DateTime.now();
    final stats = computeExerciseStats(exerciseState.logs);
    final photoCount = exerciseState.photos.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ejercicio',
            style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            'Vinculado a "${habit.name}"',
            style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.directions_run,
                  accent: BentoTheme.accentOrange,
                  value: stats.totalKm30.toStringAsFixed(1),
                  unit: 'km',
                  label: 'Últimos 30 días',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.event_available,
                  accent: BentoTheme.accentBlue,
                  value: '${stats.sessions30}',
                  unit: stats.sessions30 == 1 ? 'sesión' : 'sesiones',
                  label: 'Últimos 30 días',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StreakCard(streak: stats.streakDays),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.speed,
                  accent: BentoTheme.accentPurple,
                  value: stats.avgPace30 == null ? '—' : stats.avgPace30!.toStringAsFixed(2),
                  unit: stats.avgPace30 == null ? '' : 'min/km',
                  label: 'Ritmo promedio',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NeuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kilómetros por semana',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ExerciseWeeklyChart(weeks: stats.weeks, color: BentoTheme.accentOrange),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.directions_run,
                  label: 'Registrar carrera',
                  onTap: () => showExerciseLogForm(context, ref, forDate: now, habitId: habit.id),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Foto de progreso',
                  onTap: () => runExerciseCaptureFlow(context, ref, forDate: now, habitId: habit.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NavCard(
                  icon: Icons.bar_chart_rounded,
                  accent: BentoTheme.accentBlue,
                  title: 'Detalles',
                  subtitle: 'Historial y progreso',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ExerciseStatsScreen(habitId: habit.id)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavCard(
                  icon: Icons.photo_library_outlined,
                  accent: BentoTheme.accentPurple,
                  title: 'Galería',
                  subtitle: photoCount == 0 ? 'Sin fotos aún' : '$photoCount ${photoCount == 1 ? 'foto' : 'fotos'}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ExerciseGalleryScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String value;
  final String unit;
  final String label;
  const _StatCard({required this.icon, required this.accent, required this.value, required this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 20, fontWeight: FontWeight.w800)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.45), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streak;
  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          StreakFlame(streak: streak, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$streak ${streak == 1 ? 'día' : 'días'}',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Text('Racha actual', style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.45), fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavCard({required this.icon, required this.accent, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: accent, size: 22),
              Icon(Icons.chevron_right, color: BentoTheme.creamAlpha(0.3), size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.45), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: BentoTheme.accentOrange, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
