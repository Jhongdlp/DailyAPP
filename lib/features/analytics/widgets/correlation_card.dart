import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/metric_model.dart';
import '../../../core/services/metrics_service.dart';
import '../../../core/theme/bento_theme.dart';

/// Una relación encontrada entre dos métricas, contada en una frase.
///
/// Se enseña el contraste entre grupos y no el coeficiente: «los días que
/// dormiste 5.2 h hiciste 2 pomodoros y los que dormiste 7.8 h hiciste 5» se
/// entiende, y «r = 0.62» no. El número de días se pone al lado a propósito,
/// porque una relación sobre nueve días merece menos confianza que sobre
/// noventa.
class CorrelationCard extends StatelessWidget {
  const CorrelationCard({super.key, required this.correlation});

  final MetricCorrelation correlation;

  @override
  Widget build(BuildContext context) {
    final c = correlation;

    return NeuCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetricChip(metric: c.driver),
              const SizedBox(width: 6),
              Icon(
                c.isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 16,
                color: BentoTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              _MetricChip(metric: c.outcome),
              const Spacer(),
              Text(
                '${c.samples} días',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BentoTheme.creamAlpha(0.42),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            MetricsService.describe(c),
            style: GoogleFonts.outfit(
              fontSize: 14,
              height: 1.42,
              fontWeight: FontWeight.w500,
              color: BentoTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _StrengthBar(strength: c.strength, color: c.outcome.accent),
          const SizedBox(height: 6),
          Text(
            // La advertencia va siempre, no solo cuando la relación es débil:
            // es la lectura correcta de cualquier correlación, y esconderla en
            // los casos fuertes es justo cuando más engaña.
            'Es una coincidencia observada, no una causa demostrada.',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: BentoTheme.creamAlpha(0.38),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric});

  final DailyMetric metric;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(metric.icon, size: 13, color: metric.accent),
        const SizedBox(width: 4),
        Text(
          metric.label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BentoTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Fuerza de la relación como una barra, sin enseñar el coeficiente crudo.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength, required this.color});

  final double strength;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: NeuPressed(
            lite: true,
            borderRadius: 999,
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 6,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: strength.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _label(strength),
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: BentoTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  static String _label(double strength) {
    if (strength >= 0.7) return 'muy marcada';
    if (strength >= 0.5) return 'clara';
    return 'leve';
  }
}
