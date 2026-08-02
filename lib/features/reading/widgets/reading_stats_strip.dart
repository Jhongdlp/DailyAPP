import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../../core/providers/reading_stats_provider.dart';
import '../../../core/theme/bento_theme.dart';

/// Resumen de lectura en la biblioteca: racha, minutos de hoy, total, y un
/// heatmap corto de las últimas dos semanas.
class ReadingStatsStrip extends ConsumerWidget {
  const ReadingStatsStrip({super.key});

  static const _days = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider);
    if (stats.totalSeconds == 0) return const SizedBox.shrink();

    final days = stats.lastDays(_days);
    final peak = days.fold<int>(0, (max, d) => d.seconds > max ? d.seconds : max);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: BentoTheme.creamAlpha(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BentoTheme.creamAlpha(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _metric('🔥', '${stats.streak}', 'días seguidos'),
                _metric('⏱️', _minutes(stats.todaySeconds), 'hoy'),
                _metric('📚', _hours(stats.totalSeconds), 'en total'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: '${day.day.day}/${day.day.month}: '
                            '${_minutes(day.seconds)}',
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(
                            // La intensidad es relativa al mejor día del
                            // periodo: comparar contra un absoluto dejaría la
                            // tira casi vacía para quien lee poco cada día.
                            color: day.seconds == 0
                                ? BentoTheme.creamAlpha(0.06)
                                : BentoTheme.accentPurple.withValues(
                                    alpha: 0.25 +
                                        0.6 * (peak == 0 ? 0 : day.seconds / peak),
                                  ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String emoji, String value, String label) {
    return Expanded(
      child: Row(
        children: [
          Twemoji(emoji: emoji, height: 15, width: 15),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.montserrat(
                  color: BentoTheme.cream,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.montserrat(
                  color: BentoTheme.creamAlpha(0.45),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _minutes(int seconds) => '${seconds ~/ 60} min';

  String _hours(int seconds) {
    final hours = seconds / 3600;
    return hours < 1 ? '${seconds ~/ 60} min' : '${hours.toStringAsFixed(1)} h';
  }
}
