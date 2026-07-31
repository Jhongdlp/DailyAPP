import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';

/// Contenedor común de cada bloque del panel: título, explicación de qué se
/// está mirando y estado de "aún no hay suficientes noches".
///
/// Que la explicación viva aquí y no en cada gráfico es deliberado: un panel de
/// sueño sin interpretación son ocho dibujos bonitos que nadie sabe leer.
class SleepChartShell extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Cifra o frase interpretativa que acompaña al título.
  final Widget? trailing;

  /// Noches disponibles y mínimo para que el gráfico signifique algo.
  final int available;
  final int minimum;

  final Widget child;

  const SleepChartShell({
    super.key,
    required this.title,
    required this.available,
    required this.minimum,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final missing = minimum - available;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: BentoTheme.creamAlpha(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BentoTheme.creamAlpha(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: BentoTheme.cream,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                height: 1.35,
                color: BentoTheme.creamAlpha(0.45),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (missing > 0)
            _NotEnoughData(missing: missing)
          else
            child,
        ],
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  final int missing;

  const _NotEnoughData({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty,
              size: 15, color: BentoTheme.creamAlpha(0.3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              missing == 1
                  ? 'Falta 1 noche para poder mostrarlo'
                  : 'Faltan $missing noches para poder mostrarlo',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: BentoTheme.creamAlpha(0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Punto de color + etiqueta. Se usa cuando un gráfico pinta dos series y la
/// identidad no puede quedar solo en el color.
class SleepLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  /// Línea en vez de punto (para la media móvil).
  final bool line;

  const SleepLegendDot({
    super.key,
    required this.color,
    required this.label,
    this.line = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: line ? 14 : 8,
          height: line ? 2 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(line ? 1 : 4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            color: BentoTheme.creamAlpha(0.5),
          ),
        ),
      ],
    );
  }
}

/// Color de estado de una duración frente a la meta. Aquí el color sí significa
/// bien/regular/mal, así que usa los tokens de estado y no la paleta de series.
Color sleepStatusColor(int? minutes, int goal) {
  if (minutes == null) return BentoTheme.creamAlpha(0.12);
  if (minutes >= goal) return BentoTheme.successGreen;
  if (minutes >= goal - 60) return BentoTheme.accentOrange;
  return BentoTheme.errorRed;
}

Color sleepGradeColor(SleepGrade grade) {
  switch (grade) {
    case SleepGrade.good:
      return BentoTheme.successGreen;
    case SleepGrade.fair:
      return BentoTheme.accentOrange;
    case SleepGrade.poor:
      return BentoTheme.errorRed;
    case SleepGrade.unknown:
      return BentoTheme.creamAlpha(0.35);
  }
}

/// Etiqueta corta de día para los ejes ("12/7").
String shortDayLabel(DateTime day) => '${day.day}/${day.month}';
