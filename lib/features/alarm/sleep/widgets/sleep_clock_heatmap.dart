import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Con qué frecuencia estás dormido a cada hora, por día de la semana.
///
/// Es tu "firma" de horario: la banda oscura debería ser un bloque compacto y
/// alineado. Donde se deshilacha —casi siempre viernes y sábado— es donde se
/// rompe el ritmo.
class SleepClockHeatmap extends StatelessWidget {
  final List<SleepSession> nights;

  const SleepClockHeatmap({super.key, required this.nights});

  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  /// El eje empieza a las 18:00 para que la noche salga entera y contigua en
  /// vez de partida entre los dos extremos de la fila.
  static const _startHour = 18;

  /// `[weekday-1][columna]` → veces que estabas dormido / veces registradas.
  ({List<List<double>> ratios, int nights}) _grid() {
    final asleep = List.generate(7, (_) => List<double>.filled(24, 0));
    final totals = List<int>.filled(7, 0);
    var counted = 0;

    for (final night in nights) {
      final start = night.lightsOutAt;
      final end = night.wokeAt;
      if (start == null || end == null || night.timeInBed == null) continue;

      counted++;
      // La noche se archiva en el día del despertar, que es también como el
      // usuario la nombra ("la noche del lunes" = amaneciendo el lunes).
      final row = night.date.weekday - 1;
      totals[row]++;

      // Se recorre en pasos de 15 min y se marca la hora en la que cae: más
      // barato que integrar y suficiente para una rejilla de una hora.
      for (var t = start;
          t.isBefore(end);
          t = t.add(const Duration(minutes: 15))) {
        final column = (t.hour - _startHour + 24) % 24;
        asleep[row][column] += 0.25;
      }
    }

    final ratios = [
      for (var row = 0; row < 7; row++)
        [
          for (var col = 0; col < 24; col++)
            totals[row] == 0 ? 0.0 : (asleep[row][col] / totals[row]).clamp(0.0, 1.0),
        ],
    ];
    return (ratios: ratios, nights: counted);
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid();

    return SleepChartShell(
      title: 'TU FIRMA DE HORARIO',
      subtitle: 'Cuánto sueles estar dormido a cada hora, por día de la semana.',
      available: grid.nights,
      minimum: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row < 7; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: Text(
                      _dayLabels[row],
                      style: GoogleFonts.montserrat(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: row >= 5
                            ? BentoTheme.creamAlpha(0.6)
                            : BentoTheme.creamAlpha(0.3),
                      ),
                    ),
                  ),
                  for (var col = 0; col < 24; col++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Tooltip(
                          message: '${_dayLabels[row]} '
                              '${((col + _startHour) % 24).toString().padLeft(2, '0')}h: '
                              '${(grid.ratios[row][col] * 100).round()} %',
                          child: Container(
                            height: 13,
                            decoration: BoxDecoration(
                              // Escala secuencial de un solo tono, claro→oscuro.
                              color: grid.ratios[row][col] == 0
                                  ? BentoTheme.creamAlpha(0.05)
                                  : BentoTheme.accentAlarm.withValues(
                                      alpha: 0.18 + 0.72 * grid.ratios[row][col],
                                    ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final hour in [18, 0, 6, 12])
                  Text(
                    '${hour.toString().padLeft(2, '0')}h',
                    style: GoogleFonts.montserrat(
                      fontSize: 9,
                      color: BentoTheme.creamAlpha(0.35),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'menos',
                style: GoogleFonts.montserrat(
                  fontSize: 9,
                  color: BentoTheme.creamAlpha(0.35),
                ),
              ),
              const SizedBox(width: 6),
              for (final step in [0.1, 0.35, 0.6, 0.85])
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: BentoTheme.accentAlarm
                          .withValues(alpha: 0.18 + 0.72 * step),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const SizedBox(width: 3),
              Text(
                'más',
                style: GoogleFonts.montserrat(
                  fontSize: 9,
                  color: BentoTheme.creamAlpha(0.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
