import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Punto medio del sueño día a día, con la banda de ±1 desviación.
///
/// Es la vista de la regularidad: la duración puede estar bien y aun así
/// dormir fatal si el punto medio salta dos horas de un día a otro, porque el
/// reloj interno se reajusta mucho más despacio que el despertador.
class ConsistencyChart extends StatelessWidget {
  final SleepAnalytics analytics;

  const ConsistencyChart({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final all = analytics.scored;
    final nights = all.length <= 21 ? all : all.sublist(all.length - 21);
    final points = [
      for (final night in nights)
        (day: night.date, mid: night.midpointMinutes)
    ].where((p) => p.mid != null).toList();

    final jetLag = analytics.socialJetLagMinutes;
    final regularity = analytics.regularityMinutes;

    return SleepChartShell(
      title: 'CONSISTENCIA',
      subtitle: 'El punto medio de tu sueño cada noche. Cuanto más plana sea '
          'la línea, mejor duerme tu reloj interno.',
      available: points.length,
      minimum: 4,
      trailing: Text(
        regularity == null ? '—' : '±${regularity.round()} min',
        style: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: sleepGradeColor(analytics.regularityGrade),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => CustomPaint(
              size: Size(constraints.maxWidth, 130),
              painter: _ConsistencyPainter(
                midpoints: [for (final p in points) p.mid!],
                days: [for (final p in points) p.day],
                deviation: regularity,
              ),
            ),
          ),
          if (jetLag != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${jetLag >= 0 ? '+' : '−'}${jetLag.abs().round()} min',
                  style: GoogleFonts.montserrat(
                    fontSize: 24,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: jetLag.abs() > 60
                        ? BentoTheme.errorRed
                        : jetLag.abs() > 30
                            ? BentoTheme.accentOrange
                            : BentoTheme.successGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    jetLag.abs() > 60
                        ? 'Jet lag social: el fin de semana duermes en otro '
                            'horario. Es como cruzar un huso horario cada '
                            'viernes y volver el lunes.'
                        : 'Jet lag social: tu horario apenas cambia el fin de '
                            'semana. Eso es exactamente lo que quieres.',
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      height: 1.4,
                      color: BentoTheme.creamAlpha(0.55),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsistencyPainter extends CustomPainter {
  /// Minutos desde medianoche con envoltura: 03:30 = 210, 23:50 = −10.
  final List<double> midpoints;
  final List<DateTime> days;
  final double? deviation;

  static const _axisBand = 16.0;

  _ConsistencyPainter({
    required this.midpoints,
    required this.days,
    required this.deviation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (midpoints.length < 2) return;

    final plotHeight = size.height - _axisBand;
    final mean = midpoints.reduce((a, b) => a + b) / midpoints.length;

    // El eje se centra en la media y cubre al menos ±90 min, para que un
    // horario estable no se vea como una montaña rusa por autoescalado.
    final spread = midpoints
        .map((m) => (m - mean).abs())
        .fold<double>(90, (max, v) => v > max ? v : max);
    final range = spread * 1.15;

    double y(double minutes) =>
        plotHeight * (0.5 - (minutes - mean) / (range * 2));

    // Banda de ±1 desviación alrededor de la media.
    if (deviation != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(mean + deviation!), size.width, y(mean - deviation!)),
        Paint()..color = BentoTheme.accentAlarm.withValues(alpha: 0.10),
      );
    }

    // Media, como hairline continua.
    canvas.drawLine(
      Offset(0, y(mean)),
      Offset(size.width, y(mean)),
      Paint()
        ..color = BentoTheme.creamAlpha(0.18)
        ..strokeWidth = 1,
    );

    final slot = size.width / (midpoints.length - 1);
    final path = Path();
    for (var i = 0; i < midpoints.length; i++) {
      final dx = i * slot;
      final dy = y(midpoints[i]);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = BentoTheme.accentAlarm
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Puntos: los de fin de semana en hueco para que se vea de dónde sale el
    // jet lag sin añadir otra serie de color.
    for (var i = 0; i < midpoints.length; i++) {
      final center = Offset(i * slot, y(midpoints[i]));
      final weekend = days[i].weekday >= DateTime.saturday;
      // Anillo de superficie de 2px para que los puntos no se peguen a la línea.
      canvas.drawCircle(
          center, 5, Paint()..color = BentoTheme.darkBg);
      canvas.drawCircle(
        center,
        3.5,
        Paint()
          ..color = BentoTheme.accentAlarm
          ..style = weekend ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 2,
      );
    }

    final labelStyle = GoogleFonts.montserrat(
      fontSize: 9,
      color: BentoTheme.creamAlpha(0.35),
    );

    void label(String text, double centerX) {
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

    label(shortDayLabel(days.first), 0);
    label(shortDayLabel(days.last), size.width);

    // La media en hora de reloj, que es como el usuario piensa en ella.
    final meanLabel = TextPainter(
      text: TextSpan(
        text: 'medio ${formatClockMinutes(mean)}',
        style: GoogleFonts.montserrat(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: BentoTheme.creamAlpha(0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    meanLabel.paint(
      canvas,
      Offset(size.width - meanLabel.width, (y(mean) - meanLabel.height - 3).clamp(0, plotHeight)),
    );
  }

  @override
  bool shouldRepaint(_ConsistencyPainter old) =>
      old.midpoints != midpoints || old.deviation != deviation;
}
