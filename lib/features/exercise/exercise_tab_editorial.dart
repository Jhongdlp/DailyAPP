import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/habit_model.dart';
import '../../core/providers/exercise_habit_link_provider.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import '../../core/widgets/streak_flame.dart';
import 'exercise_capture_flow.dart';
import 'exercise_gallery_screen.dart';
import 'exercise_stats.dart';
import 'exercise_stats_screen.dart';
import 'widgets/exercise_log_form.dart';
import 'widgets/link_habit_sheet.dart';

/// Pestaña de Ejercicio en Estilo Editorial:
/// - Cabecera con hábito vinculado y botón circular de foto rápida
/// - Cuadrícula de 4 tarjetas de alto impacto (Kilómetros 30d, Sesiones, Racha, Ritmo)
/// - Gráfica de barras de las últimas 8 semanas de actividad
/// - Acciones directas (Registrar carrera, Capturar foto)
/// - Accesos a Historial & Estadísticas y Galería fotográfica
/// - Feed de actividades recientes
class ExerciseTabEditorial extends ConsumerWidget {
  const ExerciseTabEditorial({super.key});

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

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: linkedHabit == null
            ? _GateScreenEditorial(habits: habits)
            : _ExerciseContentEditorial(habit: linkedHabit),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA DE VINCULACIÓN (GATE)
// ─────────────────────────────────────────────────────────────────────────────

class _GateScreenEditorial extends ConsumerWidget {
  final List<Habit> habits;
  const _GateScreenEditorial({required this.habits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = autoDetectExerciseHabits(habits);
    final suggestion = suggestions.length == 1 ? suggestions.first : null;
    final orangeAccent = EditorialTheme.accent(BentoTheme.accentOrange, onDark: false);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: orangeAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_run_rounded,
                  color: orangeAccent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Vincula tu hábito de ejercicio',
                textAlign: TextAlign.center,
                style: EditorialTheme.caps(
                  20,
                  color: EditorialTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Para registrar tus carreras, ritmos y fotos de progreso, conecta esta pestaña con tu hábito de entrenamiento.',
                textAlign: TextAlign.center,
                style: EditorialTheme.text(
                  13,
                  color: EditorialTheme.grayText,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (suggestion != null) ...[
                Text(
                  'Hábito detectado:',
                  style: EditorialTheme.label(11, color: EditorialTheme.grayText),
                ),
                const SizedBox(height: 8),
                EditorialButton(
                  label: 'Vincular "${suggestion.name}"',
                  icon: Icons.link_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(exerciseHabitLinkProvider.notifier)
                        .setLinkedHabit(suggestion.id);
                  },
                ),
                const SizedBox(height: 10),
              ],
              EditorialButton(
                label: suggestion != null
                    ? 'Elegir otro hábito'
                    : 'Vincular o crear hábito',
                ghost: true,
                onTap: () {
                  HapticFeedback.lightImpact();
                  showLinkHabitSheet(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENIDO PRINCIPAL DE EJERCICIO
// ─────────────────────────────────────────────────────────────────────────────

class _ExerciseContentEditorial extends ConsumerWidget {
  final Habit habit;
  const _ExerciseContentEditorial({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseState = ref.watch(exerciseProvider);
    final now = DateTime.now();
    final stats = computeExerciseStats(exerciseState.logs);
    final photoCount = exerciseState.photos.length;
    final recentLogs = exerciseState.logs
        .where((l) => l.distanceKm != null || l.durationMinutes != null)
        .toList()
      ..sort((a, b) => b.loggedDate.compareTo(a.loggedDate));

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
      children: [
        _HeaderEditorial(
          habit: habit,
          onPhotoTap: () {
            HapticFeedback.lightImpact();
            runExerciseCaptureFlow(
              context,
              ref,
              forDate: now,
              habitId: habit.id,
            );
          },
        ),
        const SizedBox(height: 20),

        // Grid 2x2 de métricas destacadas
        _StatsGridEditorial(stats: stats),
        const SizedBox(height: 24),

        // Gráfica de 8 semanas
        EditorialSectionLabel(
          'ACTIVIDAD SEMANAL',
          trailing: Text(
            'ÚLTIMAS 8 SEMANAS',
            style: EditorialTheme.label(10, color: EditorialTheme.muted),
          ),
        ),
        const SizedBox(height: 10),
        _WeeklyChartCardEditorial(weeks: stats.weeks),
        const SizedBox(height: 24),

        // Acciones rápidas (Registrar carrera / Foto de progreso)
        const EditorialSectionLabel('ACCIONES RÁPIDAS'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionCardEditorial(
                icon: Icons.directions_run_rounded,
                accent: EditorialTheme.accent(BentoTheme.accentOrange, onDark: false),
                title: 'Registrar carrera',
                subtitle: 'Distancia y tiempo',
                onTap: () {
                  HapticFeedback.lightImpact();
                  showExerciseLogForm(
                    context,
                    ref,
                    forDate: now,
                    habitId: habit.id,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionCardEditorial(
                icon: Icons.camera_alt_rounded,
                accent: EditorialTheme.accent(BentoTheme.accentBrain, onDark: false),
                title: 'Foto progreso',
                subtitle: 'Evolución diaria',
                onTap: () {
                  HapticFeedback.lightImpact();
                  runExerciseCaptureFlow(
                    context,
                    ref,
                    forDate: now,
                    habitId: habit.id,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Navegación (Detalles / Galería)
        Row(
          children: [
            Expanded(
              child: _NavCardEditorial(
                icon: Icons.show_chart_rounded,
                accent: EditorialTheme.accent(BentoTheme.accentBlue, onDark: false),
                title: 'Historial & Récords',
                subtitle: '${stats.sessionsAll} sesiones registradas',
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExerciseStatsScreen(habitId: habit.id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NavCardEditorial(
                icon: Icons.photo_library_outlined,
                accent: EditorialTheme.accent(BentoTheme.accentPurple, onDark: false),
                title: 'Galería',
                subtitle: photoCount == 0 ? 'Sin fotos aún' : '$photoCount fotos',
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ExerciseGalleryScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // Feed de sesiones recientes
        if (recentLogs.isNotEmpty) ...[
          const SizedBox(height: 28),
          EditorialSectionLabel(
            'SESIONES RECIENTES',
            trailing: Text(
              '${recentLogs.length} en total',
              style: EditorialTheme.label(10, color: EditorialTheme.muted),
            ),
          ),
          const SizedBox(height: 10),
          for (final log in recentLogs.take(4)) ...[
            _RecentLogTileEditorial(log: log),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER EDITORIAL
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderEditorial extends StatelessWidget {
  final Habit habit;
  final VoidCallback onPhotoTap;

  const _HeaderEditorial({required this.habit, required this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ejercicio',
                style: EditorialTheme.caps(
                  28,
                  color: EditorialTheme.paper,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: EditorialTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: EditorialTheme.surfaceHigh, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 13,
                          color: EditorialTheme.accent(BentoTheme.accentOrange, onDark: true),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          habit.name,
                          style: EditorialTheme.text(
                            11,
                            weight: FontWeight.w600,
                            color: EditorialTheme.paper,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        EditorialCircleButton(
          icon: Icons.camera_alt_rounded,
          tooltip: 'Tomar foto rápida',
          onTap: onPhotoTap,
          size: 44,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUADRÍCULA DE MÉTRICAS (4 CARDS)
// ─────────────────────────────────────────────────────────────────────────────

class _StatsGridEditorial extends StatelessWidget {
  final ExerciseStats stats;
  const _StatsGridEditorial({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCardEditorial(
                icon: Icons.directions_run_rounded,
                accent: EditorialTheme.accent(BentoTheme.accentOrange, onDark: false),
                value: stats.totalKm30.toStringAsFixed(1),
                unit: 'km',
                label: 'Últimos 30 días',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCardEditorial(
                icon: Icons.event_available_rounded,
                accent: EditorialTheme.accent(BentoTheme.accentBlue, onDark: false),
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
              child: _StreakStatCardEditorial(streak: stats.streakDays),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCardEditorial(
                icon: Icons.speed_rounded,
                accent: EditorialTheme.accent(BentoTheme.accentPurple, onDark: false),
                value: stats.avgPace30 == null ? '—' : stats.avgPace30!.toStringAsFixed(2),
                unit: stats.avgPace30 == null ? '' : 'min/km',
                label: 'Ritmo promedio',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCardEditorial extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String value;
  final String unit;
  final String label;

  const _StatCardEditorial({
    required this.icon,
    required this.accent,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: EditorialTheme.caps(
                  22,
                  color: EditorialTheme.ink,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: EditorialTheme.text(
                    12,
                    weight: FontWeight.w700,
                    color: EditorialTheme.grayText,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: EditorialTheme.text(
              11,
              color: EditorialTheme.grayText,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakStatCardEditorial extends StatelessWidget {
  final int streak;
  const _StreakStatCardEditorial({required this.streak});

  @override
  Widget build(BuildContext context) {
    final orangeAccent = EditorialTheme.accent(BentoTheme.accentOrange, onDark: false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StreakFlame(streak: streak, size: 24),
              const Spacer(),
              if (streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: orangeAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'FUEGO',
                    style: EditorialTheme.label(9, color: orangeAccent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$streak',
                style: EditorialTheme.caps(
                  22,
                  color: EditorialTheme.ink,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                streak == 1 ? 'día' : 'días',
                style: EditorialTheme.text(
                  12,
                  weight: FontWeight.w700,
                  color: EditorialTheme.grayText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Racha constante',
            style: EditorialTheme.text(
              11,
              color: EditorialTheme.grayText,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRÁFICA SEMANAL EDITORIAL
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyChartCardEditorial extends StatelessWidget {
  final List<WeekBucket> weeks;
  const _WeeklyChartCardEditorial({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final orangeAccent = EditorialTheme.accent(BentoTheme.accentOrange, onDark: false);
    final hasData = weeks.any((w) => w.km > 0);

    if (!hasData) {
      return Container(
        height: 150,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_rounded, size: 28, color: EditorialTheme.grayText),
              const SizedBox(height: 8),
              Text(
                'Aún no hay carreras registradas en este periodo.',
                textAlign: TextAlign.center,
                style: EditorialTheme.text(12, color: EditorialTheme.grayText),
              ),
            ],
          ),
        ),
      );
    }

    final maxKm = weeks.map((w) => w.km).reduce((a, b) => a > b ? a : b);
    final axisMax = maxKm <= 0 ? 1.0 : maxKm;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Máx semanal: ${axisMax.toStringAsFixed(axisMax < 10 ? 1 : 0)} km',
                style: EditorialTheme.text(11, weight: FontWeight.w600, color: EditorialTheme.grayText),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Última semana: ${weeks.last.km.toStringAsFixed(1)} km',
                  style: EditorialTheme.text(11, weight: FontWeight.w700, color: EditorialTheme.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: CustomPaint(
              painter: _EditorialWeeklyBarPainter(
                weeks: weeks,
                max: axisMax,
                color: orangeAccent,
                gridColor: EditorialTheme.grayStrong,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${weeks.first.weekStart.day}/${weeks.first.weekStart.month}',
                style: EditorialTheme.text(11, color: EditorialTheme.grayText),
              ),
              Text(
                '${weeks.last.weekStart.day}/${weeks.last.weekStart.month}',
                style: EditorialTheme.text(11, color: EditorialTheme.grayText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorialWeeklyBarPainter extends CustomPainter {
  final List<WeekBucket> weeks;
  final double max;
  final Color color;
  final Color gridColor;

  _EditorialWeeklyBarPainter({
    required this.weeks,
    required this.max,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final n = weeks.length;
    const gap = 8.0;
    final barWidth = (size.width - gap * (n - 1)) / n;

    for (var i = 0; i < n; i++) {
      final km = weeks[i].km;
      final isCurrent = i == n - 1;

      // Base bar background
      final bgRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * (barWidth + gap), 0, barWidth, size.height),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(bgRect, Paint()..color = EditorialTheme.gray);

      if (km <= 0) continue;
      final h = (km / max) * size.height;
      final left = i * (barWidth + gap);
      final top = size.height - h;

      final paint = Paint()
        ..color = isCurrent ? color : color.withValues(alpha: 0.38);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, h),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_EditorialWeeklyBarPainter old) =>
      old.max != max ||
      old.color != color ||
      old.weeks.length != weeks.length ||
      old.weeks.last.km != weeks.last.km;
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTONES Y TARJETAS DE ACCIÓN
// ─────────────────────────────────────────────────────────────────────────────

class _ActionCardEditorial extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCardEditorial({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: EditorialTheme.text(
                14,
                weight: FontWeight.w700,
                color: EditorialTheme.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: EditorialTheme.text(11, color: EditorialTheme.grayText),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCardEditorial extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCardEditorial({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
          border: Border.all(color: EditorialTheme.surfaceHigh, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 17, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.text(
                      13,
                      weight: FontWeight.w700,
                      color: EditorialTheme.paper,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.text(11, color: EditorialTheme.muted),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: EditorialTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentLogTileEditorial extends StatelessWidget {
  final dynamic log;
  const _RecentLogTileEditorial({required this.log});

  @override
  Widget build(BuildContext context) {
    final orangeAccent = EditorialTheme.accent(BentoTheme.accentOrange, onDark: false);
    final distance = log.distanceKm as double?;
    final duration = log.durationMinutes as int?;
    final pace = log.paceMinPerKm as double?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: orangeAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.directions_run_rounded, size: 18, color: orangeAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distance != null ? '${distance.toStringAsFixed(2)} km' : 'Sesión de ejercicio',
                  style: EditorialTheme.text(
                    13,
                    weight: FontWeight.w700,
                    color: EditorialTheme.ink,
                  ),
                ),
                Text(
                  _dateLabel(log.loggedDate as DateTime),
                  style: EditorialTheme.text(11, color: EditorialTheme.grayText),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (duration != null)
                Text(
                  '${duration}m',
                  style: EditorialTheme.text(12, weight: FontWeight.w700, color: EditorialTheme.ink),
                ),
              if (pace != null)
                Text(
                  '${pace.toStringAsFixed(2)} min/km',
                  style: EditorialTheme.text(10, color: EditorialTheme.grayText),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return '${d.day}/${d.month}/${d.year}';
  }
}
