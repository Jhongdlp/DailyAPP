import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Cuánto dormiste frente a cómo te sentiste, una noche por punto.
///
/// Es el gráfico que responde "¿cuántas horas necesito yo?" con tus datos en
/// vez de con el tópico de las ocho horas: para mucha gente la curva se aplana
/// antes, y para otra no llega hasta las nueve.
class DurationQualityScatter extends StatelessWidget {
  final SleepAnalytics analytics;

  const DurationQualityScatter({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final points = analytics.scored
        .where((n) => n.quality != null)
        .map((n) => (minutes: n.sleepMinutes!, quality: n.quality!))
        .toList();

    final best = analytics.optimalDuration;

    return SleepChartShell(
      title: 'CUÁNTO NECESITAS TÚ',
      subtitle: 'Cada punto es una noche: horas dormidas frente a cómo te '
          'sentiste al despertar.',
      available: points.length,
      minimum: 6,
      trailing: best == null
          ? null
          : Text(
              formatSleepMinutes(best.minutes),
              style: GoogleFonts.montserrat(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: BentoTheme.accentAlarm,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => CustomPaint(
              size: Size(constraints.maxWidth, 150),
              painter: _ScatterPainter(
                points: points,
                optimalMinutes: best?.minutes,
                goalMinutes: analytics.goalMinutes,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            best == null
                ? 'Con unas cuantas noches más podré decirte con qué duración '
                    'te despiertas mejor.'
                : 'Tus mejores mañanas llegan durmiendo '
                    '${formatSleepMinutes(best.minutes)} '
                    '(${best.nights} noches, calidad media '
                    '${best.avgQuality.toStringAsFixed(1)}/5). '
                    '${best.minutes == analytics.goalMinutes ? 'Tu meta ya está donde toca.' : 'Puede que te convenga mover tu meta ahí.'}',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              height: 1.45,
              color: BentoTheme.creamAlpha(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  final List<({int minutes, int quality})> points;
  final int? optimalMinutes;
  final int goalMinutes;

  static const _axisBand = 16.0;
  static const _gutter = 18.0;

  _ScatterPainter({
    required this.points,
    required this.optimalMinutes,
    required this.goalMinutes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final plotHeight = size.height - _axisBand;
    final plotWidth = size.width - _gutter;

    final minMinutes = points
        .map((p) => p.minutes)
        .fold<int>(goalMinutes, (min, v) => v < min ? v : min);
    final maxMinutes = points
        .map((p) => p.minutes)
        .fold<int>(goalMinutes, (max, v) => v > max ? v : max);
    // Margen de media hora a cada lado para que ningún punto toque el borde.
    final low = (minMinutes - 30).toDouble();
    final high = (maxMinutes + 30).toDouble();
    final span = (high - low).clamp(60.0, 1440.0);

    double x(num minutes) => _gutter + plotWidth * ((minutes - low) / span);
    // Calidad 1 abajo, 5 arriba.
    double y(int quality) => plotHeight * (1 - (quality - 1) / 4);

    // Rejilla horizontal por nivel de calidad, con su etiqueta.
    final gridPaint = Paint()
      ..color = BentoTheme.creamAlpha(0.08)
      ..strokeWidth = 1;
    final labelStyle = GoogleFonts.montserrat(
      fontSize: 9,
      color: BentoTheme.creamAlpha(0.35),
    );

    for (var quality = 1; quality <= 5; quality++) {
      final dy = y(quality);
      canvas.drawLine(Offset(_gutter, dy), Offset(size.width, dy), gridPaint);
      final painter = TextPainter(
        text: TextSpan(text: '$quality', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, dy - painter.height / 2));
    }

    // Banda de la duración óptima: el mensaje del gráfico, resaltado.
    if (optimalMinutes != null) {
      canvas.drawRect(
        Rect.fromLTRB(
          x(optimalMinutes! - 15),
          0,
          x(optimalMinutes! + 15),
          plotHeight,
        ),
        Paint()..color = BentoTheme.accentAlarm.withValues(alpha: 0.14),
      );
    }

    for (final point in points) {
      final center = Offset(x(point.minutes), y(point.quality));
      // Anillo de superficie para que los puntos solapados no se fundan.
      canvas.drawCircle(center, 6, Paint()..color = BentoTheme.darkBg);
      canvas.drawCircle(
        center,
        4.5,
        Paint()..color = BentoTheme.accentAlarm.withValues(alpha: 0.85),
      );
    }

    void tick(String text, double centerX) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset((centerX - painter.width / 2).clamp(0.0, size.width - painter.width),
            plotHeight + 4),
      );
    }

    tick(formatSleepMinutes(minMinutes), x(minMinutes));
    if (maxMinutes != minMinutes) {
      tick(formatSleepMinutes(maxMinutes), x(maxMinutes));
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter old) =>
      old.points != points || old.optimalMinutes != optimalMinutes;
}
