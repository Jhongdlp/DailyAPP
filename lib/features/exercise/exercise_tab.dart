import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/habit_model.dart';
import '../../core/providers/exercise_habit_link_provider.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'exercise_capture_flow.dart';
import 'widgets/exercise_log_form.dart';
import 'widgets/exercise_photo_grid.dart';
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

    final last30 = exerciseState.logs.where((l) => now.difference(l.loggedDate).inDays <= 30);
    final totalKm = last30.fold<double>(0, (sum, l) => sum + (l.distanceKm ?? 0));
    final paceValues = last30.map((l) => l.computedPace).whereType<double>().toList();
    final avgPace = paceValues.isEmpty ? null : paceValues.reduce((a, b) => a + b) / paceValues.length;

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
          const SizedBox(height: 16),
          NeuCard(
            child: Row(
              children: [
                Expanded(
                  child: _StatBlock(label: 'Últimos 30 días', value: '${totalKm.toStringAsFixed(1)} km'),
                ),
                Container(width: 1, height: 40, color: BentoTheme.creamAlpha(0.1)),
                Expanded(
                  child: _StatBlock(
                    label: 'Ritmo promedio',
                    value: avgPace == null ? '—' : '${avgPace.toStringAsFixed(2)} min/km',
                  ),
                ),
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
          const SizedBox(height: 8),
          Text(
            'Progreso',
            style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const ExercisePhotoGrid(),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  const _StatBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontSize: 11, fontWeight: FontWeight.w600)),
      ],
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
