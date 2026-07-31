import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Deuda de sueño acumulada en las últimas 14 noches.
///
/// Es la métrica que más mueve la aguja porque hace visible algo que se siente
/// difuso: recortar 40 min cada noche no es "dormir un poco menos", son casi
/// diez horas perdidas en dos semanas.
class SleepDebtRing extends StatelessWidget {
  final SleepAnalytics analytics;

  const SleepDebtRing({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final debt = analytics.sleepDebtMinutes;
    final goal = analytics.goalMinutes;

    // Referencia: una noche entera de meta perdida por cada 7 noches sería ya
    // una deuda seria. Se usa como tope del arco para que el anillo signifique
    // algo en vez de escalar con el peor caso posible.
    final reference = goal * 2;
    final ratio = (debt / reference).clamp(0.0, 1.0);

    final recoveryNights = debt == 0 ? 0 : (debt / 60).ceil();
    final color = debt == 0
        ? BentoTheme.successGreen
        : debt < goal / 2
            ? BentoTheme.accentOrange
            : BentoTheme.errorRed;

    return SleepChartShell(
      title: 'DEUDA DE SUEÑO',
      subtitle: 'Suma de todo lo que te faltó para tu meta en las últimas '
          '14 noches. Dormir de más otro día no la borra.',
      available: analytics.nightCount,
      minimum: 3,
      child: Row(
        children: [
          SizedBox(
            width: 108,
            height: 108,
            child: CustomPaint(
              painter: _DebtRingPainter(ratio: ratio, color: color),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      debt == 0 ? '0' : '−${formatSleepMinutes(debt)}',
                      style: GoogleFonts.montserrat(
                        fontSize: 20,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '14 noches',
                      style: GoogleFonts.montserrat(
                        fontSize: 9,
                        color: BentoTheme.creamAlpha(0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              debt == 0
                  ? 'Sin deuda: vas cumpliendo tu meta. Mantener esto es más '
                      'valioso que una noche larga de vez en cuando.'
                  : 'Para recuperarla necesitarías unas $recoveryNights noches '
                      'durmiendo una hora extra. La recuperación es lenta a '
                      'propósito: el cuerpo no devuelve el sueño de golpe.',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                height: 1.45,
                color: BentoTheme.creamAlpha(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtRingPainter extends CustomPainter {
  final double ratio;
  final Color color;

  _DebtRingPainter({required this.ratio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 2);

    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = BentoTheme.creamAlpha(0.08)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (ratio <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * ratio,
      false,
      Paint()
        ..color = color
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DebtRingPainter old) =>
      old.ratio != ratio || old.color != color;
}
