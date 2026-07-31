import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Cuánto tardas en levantarte desde que suena la alarma, y las mañanas en las
/// que directamente la ignoraste.
///
/// El snooze no es una anécdota: cada tramo corto de sueño después de la alarma
/// entra en una fase de la que cuesta más salir, así que media hora "extra"
/// suele dejarte peor que levantarte al primer aviso.
class SnoozeStrip extends StatelessWidget {
  final SleepAnalytics analytics;

  /// Noches a considerar, ya ordenadas de la más antigua a la más reciente.
  final List<SleepSession> nights;

  const SnoozeStrip({super.key, required this.analytics, required this.nights});

  @override
  Widget build(BuildContext context) {
    final rang = nights.where((n) => n.firstRingAt != null).toList()
      ..sort((a, b) => a.nightKey.compareTo(b.nightKey));
    final recent = rang.length <= 14 ? rang : rang.sublist(rang.length - 14);

    final avg = analytics.avgSnoozeMinutes;
    final ignored = analytics.ignoredRate;
    final peak = recent.fold<int>(
      1,
      (max, n) => (n.snoozeMinutes ?? 0) > max ? n.snoozeMinutes! : max,
    );

    return SleepChartShell(
      title: 'CUÁNTO TARDAS EN LEVANTARTE',
      subtitle: 'Minutos entre que suena la alarma y que validas la foto.',
      available: recent.length,
      minimum: 2,
      trailing: Text(
        avg == null ? '—' : '${avg.round()} min de media',
        style: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: BentoTheme.creamAlpha(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final night in recent)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: _SnoozeBar(night: night, peak: peak),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  recent.isEmpty
                      ? ''
                      : '${shortDayLabel(recent.first.date)} → '
                          '${shortDayLabel(recent.last.date)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 9,
                    color: BentoTheme.creamAlpha(0.35),
                  ),
                ),
              ),
              if (ignored != null && ignored > 0)
                Text(
                  'Ignoraste ${(ignored * 100).round()} % de las alarmas',
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: BentoTheme.errorRed,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnoozeBar extends StatelessWidget {
  final SleepSession night;
  final int peak;

  const _SnoozeBar({required this.night, required this.peak});

  @override
  Widget build(BuildContext context) {
    final minutes = night.snoozeMinutes;
    final ignored = night.alarmIgnored;

    // Las ignoradas se pintan a altura completa: no hay un "cuánto tardaste",
    // el dato es que no llegaste a levantarte.
    final ratio = ignored ? 1.0 : (minutes ?? 0) / peak;
    final height = (6 + 44 * ratio).clamp(6.0, 50.0);

    final color = ignored
        ? BentoTheme.errorRed
        : (minutes ?? 0) <= 5
            ? BentoTheme.successGreen
            : (minutes ?? 0) <= 20
                ? BentoTheme.accentOrange
                : BentoTheme.errorRed.withValues(alpha: 0.7);

    return Tooltip(
      message: ignored
          ? '${shortDayLabel(night.date)}: alarma ignorada'
          : '${shortDayLabel(night.date)}: ${minutes ?? 0} min',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (ignored)
            Icon(Icons.close, size: 10, color: BentoTheme.errorRed),
          const SizedBox(height: 2),
          Container(
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
