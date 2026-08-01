import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/metric_model.dart';
import '../../../core/theme/bento_theme.dart';
import 'sparkline.dart';

/// Tarjeta de una métrica: el número grande, cuánto ha cambiado y la forma del
/// periodo.
///
/// El valor y las etiquetas van en tinta normal, nunca en el color de la
/// métrica: el acento lo lleva el icono y la línea, que es lo que da identidad
/// sin sacrificar contraste del texto.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.summary,
    required this.series,
    this.onTap,
    this.selected = false,
  });

  final MetricSummary summary;

  /// Valores del periodo en orden cronológico, para la sparkline.
  final List<double> series;

  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final metric = summary.metric;
    final accent = metric.accent;

    return GestureDetector(
      onTap: onTap,
      child: NeuCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        borderColor: selected ? accent : null,
        borderWidth: selected ? 1.5 : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(metric.icon, size: 15, color: accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary.hasData ? metric.format(summary.value!) : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: -0.6,
                color: BentoTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            _ChangeChip(summary: summary),
            const SizedBox(height: 4),
            Sparkline(values: series, color: accent),
          ],
        ),
      ),
    );
  }
}

/// Cuánto ha cambiado respecto al periodo anterior.
///
/// La flecha apunta al movimiento del número y el color dice si es buena
/// noticia; en el gasto las dos cosas van al revés, y por eso no se puede
/// pintar solo por el signo.
class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.summary});

  final MetricSummary summary;

  @override
  Widget build(BuildContext context) {
    final change = summary.change;

    if (change == null) {
      return Text(
        summary.hasData ? 'sin comparación' : 'sin datos',
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: BentoTheme.creamAlpha(0.42),
        ),
      );
    }

    final improved = summary.isImprovement;
    final color = improved == null
        ? BentoTheme.textSecondary
        : improved
            ? BentoTheme.accentLime
            : BentoTheme.accentOrange;

    final percent = (change.abs() * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          change > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '$percent%',
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'vs. antes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: BentoTheme.creamAlpha(0.42),
            ),
          ),
        ),
      ],
    );
  }
}
