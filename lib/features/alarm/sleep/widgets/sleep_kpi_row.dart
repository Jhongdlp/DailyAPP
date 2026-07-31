import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import 'sleep_chart_shell.dart';

/// Las cinco cifras que resumen cómo duermes, cada una con su lectura.
///
/// Van juntas y arriba del todo porque son la respuesta rápida: los gráficos de
/// abajo explican el porqué, pero si el usuario solo mira una cosa, mira esto.
class SleepKpiRow extends StatelessWidget {
  final SleepAnalytics analytics;

  const SleepKpiRow({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final avg7 = analytics.avg7;
    final goal = analytics.goalMinutes;
    final regularity = analytics.regularityMinutes;
    final efficiency = analytics.avgEfficiency;
    final adherence = analytics.bedtimeAdherence;

    final tiles = <Widget>[
      _KpiTile(
        label: 'Media 7 noches',
        value: formatSleepMinutes(avg7),
        reading: avg7 == null
            ? 'Sin datos'
            : avg7 >= goal
                ? 'Por encima de tu meta'
                : 'Te faltan ${formatSleepMinutes(goal - avg7)}',
        color: avg7 == null
            ? BentoTheme.creamAlpha(0.35)
            : sleepStatusColor(avg7.round(), goal),
      ),
      _KpiTile(
        label: 'Regularidad',
        value: regularity == null ? '—' : '±${regularity.round()} min',
        reading: switch (analytics.regularityGrade) {
          SleepGrade.good => 'Horario muy estable',
          SleepGrade.fair => 'Aceptable, se puede afinar',
          SleepGrade.poor => 'Tu horario baila demasiado',
          SleepGrade.unknown => 'Sin datos',
        },
        color: sleepGradeColor(analytics.regularityGrade),
      ),
      _KpiTile(
        label: 'Eficiencia',
        value: efficiency == null ? '—' : '${(efficiency * 100).round()} %',
        reading: efficiency == null
            ? 'Sin datos'
            : efficiency >= 0.85
                ? 'Aprovechas bien la cama'
                : 'Pasas mucho rato en cama sin dormir',
        color: efficiency == null
            ? BentoTheme.creamAlpha(0.35)
            : efficiency >= 0.85
                ? BentoTheme.successGreen
                : BentoTheme.accentOrange,
      ),
      _KpiTile(
        label: 'Cumples la hora',
        value: adherence == null ? '—' : '${(adherence * 100).round()} %',
        reading: adherence == null
            ? 'Sin datos'
            : adherence >= 0.7
                ? 'Te acuestas cuando toca'
                : 'Casi siempre te acuestas tarde',
        color: adherence == null
            ? BentoTheme.creamAlpha(0.35)
            : adherence >= 0.7
                ? BentoTheme.successGreen
                : BentoTheme.accentOrange,
      ),
      _KpiTile(
        label: 'Racha en meta',
        value: '${analytics.goalStreak}',
        reading: analytics.goalStreak == 0
            ? 'Empieza hoy'
            : analytics.goalStreak == 1
                ? 'noche seguida'
                : 'noches seguidas',
        color: analytics.goalStreak > 0
            ? BentoTheme.accentAlarm
            : BentoTheme.creamAlpha(0.35),
      ),
    ];

    return SleepChartShell(
      title: 'RESUMEN',
      subtitle: 'Las últimas 7–14 noches registradas.',
      available: analytics.nightCount,
      minimum: 1,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final tile in tiles)
            // Dos por fila; el ancho se calcula contra el padding del shell.
            SizedBox(
              width: (MediaQuery.of(context).size.width - 40 - 32 - 10) / 2,
              child: tile,
            ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String reading;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.reading,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: BentoTheme.creamAlpha(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // El punto de color lleva el estado; el texto se queda en tinta
              // neutra para que siga leyéndose sin distinguir colores.
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    letterSpacing: 0.4,
                    color: BentoTheme.creamAlpha(0.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: BentoTheme.cream,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reading,
            maxLines: 2,
            style: GoogleFonts.montserrat(
              fontSize: 10,
              height: 1.3,
              color: BentoTheme.creamAlpha(0.45),
            ),
          ),
        ],
      ),
    );
  }
}
