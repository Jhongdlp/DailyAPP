import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';
import 'sleep_dashboard_screen.dart';
import 'sleep_schedule_form.dart';
import 'widgets/sleep_chart_shell.dart';

/// Resumen de sueño dentro de la pestaña Alarma: en qué punto del ciclo estás
/// ahora mismo, las dos últimas semanas de duración y la deuda acumulada.
///
/// Alto fijo a propósito: la lista de alarmas de debajo conserva su espacio.
class SleepSummaryCard extends ConsumerWidget {
  const SleepSummaryCard({super.key});

  static const _days = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sleepProvider);
    final analytics = ref.watch(sleepAnalyticsProvider);

    if (!data.schedule.enabled && !analytics.hasData) {
      return const _SetupPrompt();
    }

    final days = data.lastNights(_days);
    final goal = data.schedule.goalMinutes;
    final debt = analytics.sleepDebtMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepDashboardScreen()),
        ),
        // Atajo de desarrollo para poder ver los gráficos con datos.
        onLongPress: kDebugMode
            ? () => ref.read(sleepProvider.notifier).seedDemoNights(30)
            : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
          decoration: BoxDecoration(
            color: BentoTheme.creamAlpha(0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BentoTheme.creamAlpha(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bedtime_outlined,
                      size: 15, color: BentoTheme.accentAlarm),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusText(data, analytics),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.cream,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: BentoTheme.creamAlpha(0.35)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final entry in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Tooltip(
                          message: '${shortDayLabel(entry.day)}: '
                              '${formatSleepMinutes(entry.session?.sleepMinutes)}',
                          child: Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: sleepStatusColor(
                                entry.session?.sleepMinutes,
                                goal,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _metric(
                    formatSleepMinutes(analytics.avg7),
                    'media 7 noches',
                  ),
                  _metric(
                    debt == 0 ? '0' : '−${formatSleepMinutes(debt)}',
                    'deuda 14 noches',
                  ),
                  _metric(
                    '${analytics.goalStreak}',
                    'racha en meta',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(SleepData data, SleepAnalytics analytics) {
    final open = data.openNight;
    if (open?.lightsOutAt != null) {
      final at = open!.lightsOutAt!;
      return 'Durmiendo desde las '
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
    }

    final last = data.lastCompleteNight;
    final todayKey = nightKeyFor(DateTime.now());
    if (last != null && last.nightKey == todayKey) {
      final quality = last.quality;
      return 'Anoche: ${formatSleepMinutes(last.sleepMinutes)}'
          '${quality == null ? '' : ' · calidad $quality/5'}';
    }

    final next = data.schedule.nextBedtime();
    if (next != null) {
      final diff = next.difference(DateTime.now());
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      return 'Te toca dormir en '
          '${hours > 0 ? '$hours h $mins min' : '$mins min'}';
    }

    return 'Calidad de sueño';
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: BentoTheme.cream,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 9,
              color: BentoTheme.creamAlpha(0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupPrompt extends StatelessWidget {
  const _SetupPrompt();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepScheduleForm()),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: BentoTheme.accentAlarm.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined,
                  size: 20, color: BentoTheme.accentAlarm),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calidad de sueño',
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pon tu hora de dormir y empieza a medir cuánto y cómo '
                      'descansas.',
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        height: 1.35,
                        color: BentoTheme.creamAlpha(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: BentoTheme.creamAlpha(0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
