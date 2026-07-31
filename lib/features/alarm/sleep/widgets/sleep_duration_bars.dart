import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Horas dormidas por noche contra la meta, con la media móvil de 7 días.
///
/// La media móvil es lo que evita la trampa de mirar la noche de ayer: una
/// noche mala no significa nada, siete seguidas sí.
class SleepDurationBars extends StatefulWidget {
  final SleepAnalytics analytics;

  const SleepDurationBars({super.key, required this.analytics});

  @override
  State<SleepDurationBars> createState() => _SleepDurationBarsState();
}

class _SleepDurationBarsState extends State<SleepDurationBars> {
  int _days = 14;

  @override
  Widget build(BuildContext context) {
    final all = widget.analytics.scored;
    final rolling = widget.analytics.rollingAverage7;
    final from = all.length <= _days ? 0 : all.length - _days;
    final nights = all.sublist(from);
    final avg = rolling.sublist(from);
    final goal = widget.analytics.goalMinutes;

    return SleepChartShell(
      title: 'HORAS POR NOCHE',
      subtitle: 'La línea clara es tu media de los últimos 7 días; '
          'la de color, tu meta.',
      available: all.length,
      minimum: 2,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [14, 30])
            GestureDetector(
              onTap: () => setState(() => _days = option),
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '${option}d',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _days == option
                        ? BentoTheme.cream
                        : BentoTheme.creamAlpha(0.3),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => CustomPaint(
              size: Size(constraints.maxWidth, 150),
              painter: _DurationPainter(
                nights: nights,
                rollingAverage: avg,
                goalMinutes: goal,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              SleepLegendDot(
                  color: BentoTheme.successGreen, label: 'Meta cumplida'),
              SleepLegendDot(
                  color: BentoTheme.accentOrange, label: 'Hasta 1 h corta'),
              SleepLegendDot(color: BentoTheme.errorRed, label: 'Muy corta'),
              SleepLegendDot(
                  color: BentoTheme.creamAlpha(0.55),
                  label: 'Media 7 días',
                  line: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationPainter extends CustomPainter {
  final List<SleepSession> nights;
  final List<double> rollingAverage;
  final int goalMinutes;

  static const _axisBand = 16.0;

  _DurationPainter({
    required this.nights,
    required this.rollingAverage,
    required this.goalMinutes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nights.isEmpty) return;

    final plotHeight = size.height - _axisBand;
    // El techo del eje es la mayor entre la meta y la mejor noche, con holgura:
    // así la línea de meta nunca queda pegada al borde.
    final peak = nights
        .map((n) => n.sleepMinutes!)
        .fold<int>(goalMinutes, (max, v) => v > max ? v : max);
    final ceiling = (peak * 1.1).ceilToDouble();

    double y(num minutes) => plotHeight * (1 - minutes / ceiling);

    final slot = size.width / nights.length;
    // 2px de hueco de superficie entre barras vecinas.
    final barWidth = (slot - 3).clamp(2.0, 22.0);

    for (var i = 0; i < nights.length; i++) {
      final minutes = nights[i].sleepMinutes!;
      final left = i * slot + (slot - barWidth) / 2;
      final top = y(minutes);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left, top, left + barWidth, plotHeight),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = sleepStatusColor(minutes, goalMinutes),
      );
    }

    // Línea de meta: continua y con su etiqueta, no discontinua.
    final goalY = y(goalMinutes);
    canvas.drawLine(
      Offset(0, goalY),
      Offset(size.width, goalY),
      Paint()
        ..color = BentoTheme.accentAlarm.withValues(alpha: 0.75)
        ..strokeWidth = 1.5,
    );
    final goalLabel = TextPainter(
      text: TextSpan(
        text: 'meta ${formatSleepMinutes(goalMinutes)}',
        style: GoogleFonts.montserrat(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: BentoTheme.accentAlarm,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    goalLabel.paint(
      canvas,
      Offset(size.width - goalLabel.width, (goalY - goalLabel.height - 2).clamp(0, plotHeight)),
    );

    // Media móvil de 7 días, en tinta neutra: es referencia, no una categoría.
    if (rollingAverage.length == nights.length && nights.length > 1) {
      final path = Path();
      for (var i = 0; i < rollingAverage.length; i++) {
        final dx = i * slot + slot / 2;
        final dy = y(rollingAverage[i]);
        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = BentoTheme.creamAlpha(0.55)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Solo se etiquetan los extremos del eje: un número por barra sería ruido.
    final labelStyle = GoogleFonts.montserrat(
      fontSize: 9,
      color: BentoTheme.creamAlpha(0.35),
    );
    void tick(String text, double centerX) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (centerX - painter.width / 2)
          .clamp(0.0, size.width - painter.width);
      painter.paint(canvas, Offset(dx, plotHeight + 4));
    }

    tick(shortDayLabel(nights.first.date), slot / 2);
    if (nights.length > 1) {
      tick(shortDayLabel(nights.last.date), size.width - slot / 2);
    }
  }

  @override
  bool shouldRepaint(_DurationPainter old) =>
      old.nights != nights ||
      old.rollingAverage != rollingAverage ||
      old.goalMinutes != goalMinutes;
}
