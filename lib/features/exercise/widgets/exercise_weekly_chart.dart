import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import '../exercise_stats.dart';

/// Barras de kilómetros por semana, últimas 8 semanas. La semana en curso se
/// resalta a color completo; las anteriores quedan atenuadas para que el ojo
/// vaya directo a "cómo voy esta semana" antes que a comparar el histórico.
class ExerciseWeeklyChart extends StatelessWidget {
  final List<WeekBucket> weeks;
  final Color color;
  final double height;

  const ExerciseWeeklyChart({
    super.key,
    required this.weeks,
    required this.color,
    this.height = 130,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = weeks.any((w) => w.km > 0);
    if (!hasData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Aún no hay carreras registradas.',
            style: GoogleFonts.montserrat(
              color: BentoTheme.creamAlpha(0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final maxKm = weeks.map((w) => w.km).reduce((a, b) => a > b ? a : b);
    final axisMax = maxKm <= 0 ? 1.0 : maxKm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${axisMax.toStringAsFixed(axisMax < 10 ? 1 : 0)} km',
              style: _axisStyle,
            ),
            Text('esta semana', style: _axisStyle),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _WeeklyBarPainter(
              weeks: weeks,
              max: axisMax,
              color: color,
              gridColor: BentoTheme.creamAlpha(0.10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_weekLabel(weeks.first.weekStart), style: _axisStyle),
            Text(_weekLabel(weeks.last.weekStart), style: _axisStyle),
          ],
        ),
      ],
    );
  }

  static TextStyle get _axisStyle => GoogleFonts.montserrat(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: BentoTheme.creamAlpha(0.45),
  );

  static String _weekLabel(DateTime d) => '${d.day}/${d.month}';
}

class _WeeklyBarPainter extends CustomPainter {
  final List<WeekBucket> weeks;
  final double max;
  final Color color;
  final Color gridColor;

  _WeeklyBarPainter({
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
    const gap = 6.0;
    final barWidth = (size.width - gap * (n - 1)) / n;

    for (var i = 0; i < n; i++) {
      final km = weeks[i].km;
      if (km <= 0) continue;
      final h = (km / max) * size.height;
      final left = i * (barWidth + gap);
      final top = size.height - h;
      final isCurrent = i == n - 1;
      final paint = Paint()
        ..color = isCurrent ? color : color.withValues(alpha: 0.32);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WeeklyBarPainter old) =>
      old.max != max ||
      old.color != color ||
      old.weeks.length != weeks.length ||
      old.weeks.last.km != weeks.last.km;
}
