import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/metric_model.dart';
import '../../../core/theme/bento_theme.dart';

/// Paso 1: los números de la semana, sin pedir nada todavía.
///
/// Va primero a propósito. Preguntar "¿qué funcionó?" en frío se contesta con
/// lo último que uno recuerda, que casi nunca es lo que de verdad pasó; ver los
/// datos antes cambia la respuesta.
class StepNumbers extends StatelessWidget {
  const StepNumbers({
    super.key,
    required this.summaries,
    required this.onNext,
  });

  final List<MetricSummary> summaries;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final withData = summaries.where((s) => s.hasData).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                'Tu semana',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: BentoTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                withData.isEmpty
                    ? 'No hay nada registrado esta semana. Puedes revisarla '
                        'igual: a veces lo que hay que anotar es justo eso.'
                    : 'Míralos antes de opinar sobre la semana.',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  height: 1.45,
                  color: BentoTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              for (final summary in withData) ...[
                _Row(summary: summary),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        _NextButton(onTap: onNext, label: 'Seguir'),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.summary});

  final MetricSummary summary;

  @override
  Widget build(BuildContext context) {
    final metric = summary.metric;
    final change = summary.change;
    final improved = summary.isImprovement;

    final changeColor = improved == null
        ? BentoTheme.textSecondary
        : improved
            ? BentoTheme.accentLime
            : BentoTheme.accentOrange;

    return NeuCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(metric.icon, size: 18, color: metric.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.textSecondary,
                  ),
                ),
                Text(
                  // Un promedio sobre dos días no es "tu semana": se dice.
                  summary.samples == 1
                      ? '1 día con dato'
                      : '${summary.samples} días con dato',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: BentoTheme.creamAlpha(0.4),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                metric.format(summary.value!),
                style: GoogleFonts.outfit(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: BentoTheme.textPrimary,
                ),
              ),
              if (change != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      change > 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 11,
                      color: changeColor,
                    ),
                    Text(
                      '${(change.abs() * 100).round()}%',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: changeColor,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón de avance del ritual. Vive aquí porque los cuatro pasos lo comparten.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: GestureDetector(
        onTap: onTap,
        child: NeuCard(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: BentoTheme.accentBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reexportado para que los otros pasos usen exactamente el mismo botón.
class RitualButton extends StatelessWidget {
  const RitualButton({super.key, required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) =>
      _NextButton(onTap: onTap, label: label);
}
