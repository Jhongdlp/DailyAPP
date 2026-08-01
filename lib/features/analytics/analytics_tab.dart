import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/metric_model.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/services/metrics_service.dart';
import '../../core/theme/bento_theme.dart';
import 'weekly_review_screen.dart';
import 'widgets/correlation_card.dart';
import 'widgets/metric_tile.dart';
import 'widgets/trend_chart.dart';

/// Analíticas: lo que la app ya sabía de ti pero tenía repartido en ocho silos.
///
/// Nada de esto añade una tabla nueva ni pide registrar nada extra. Sueño,
/// foco, hábitos, tareas, gasto y lectura ya se guardaban; aquí simplemente se
/// miran juntos.
class AnalyticsTab extends ConsumerStatefulWidget {
  const AnalyticsTab({super.key});

  @override
  ConsumerState<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends ConsumerState<AnalyticsTab> {
  /// Métrica que se está viendo en la gráfica grande. `null` = todavía no se ha
  /// tocado ninguna tarjeta y se muestra la primera disponible.
  DailyMetric? _focused;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(metricsSnapshotProvider);
    final summaries = ref.watch(metricSummariesProvider);
    final range = ref.watch(analyticsRangeProvider);
    final correlations = ref.watch(correlationsProvider);

    final to = MetricsService.dayOnly(DateTime.now()).add(const Duration(days: 1));
    final from = to.subtract(Duration(days: range.days));
    final days = MetricsService.daysBetween(from, to);

    // Si la métrica enfocada dejó de tener datos (o aún no hay ninguna), se cae
    // a la primera disponible en vez de dejar la gráfica en blanco.
    final focused = summaries.any((s) => s.metric == _focused)
        ? _focused!
        : (summaries.isNotEmpty ? summaries.first.metric : null);

    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      child: summaries.isEmpty
          ? _empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
              children: [
                _header(),
                _rangeBar(range),
                const SizedBox(height: 18),
                _sectionTitle('Tu ${range.label.toLowerCase()}'),
                const SizedBox(height: 10),
                _summaryGrid(summaries, snapshot, days),
                if (focused != null) ...[
                  const SizedBox(height: 22),
                  _sectionTitle(focused.label),
                  const SizedBox(height: 10),
                  NeuCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: TrendChart(
                      metric: focused,
                      points: [
                        for (final day in days)
                          (day: day, value: snapshot[focused][day]),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _sectionTitle('Qué va con qué'),
                const SizedBox(height: 10),
                if (correlations.isEmpty)
                  _noCorrelations()
                else
                  for (final c in correlations) ...[
                    CorrelationCard(correlation: c),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 10),
                _reviewEntry(),
              ],
            ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 14),
      child: Text(
        'Analíticas',
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w800,
          fontSize: 38,
          height: 0.92,
          letterSpacing: -1.2,
          color: BentoTheme.cream,
        ),
      ),
    );
  }

  Widget _rangeBar(AnalyticsRange selected) {
    return Row(
      children: [
        for (final range in AnalyticsRange.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(analyticsRangeProvider.notifier).select(range),
              child: range == selected
                  ? NeuPressed(
                      lite: true,
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _rangeLabel(range, active: true),
                    )
                  : NeuCard(
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _rangeLabel(range, active: false),
                    ),
            ),
          ),
          if (range != AnalyticsRange.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _rangeLabel(AnalyticsRange range, {required bool active}) {
    return Center(
      child: Text(
        range.label,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? BentoTheme.textPrimary : BentoTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: BentoTheme.textPrimary,
      ),
    );
  }

  Widget _summaryGrid(
    List<MetricSummary> summaries,
    MetricsSnapshot snapshot,
    List<DateTime> days,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dos columnas salvo en pantallas muy estrechas, donde una tarjeta a
        // media anchura dejaría el número partido en dos líneas.
        final columns = constraints.maxWidth < 340 ? 1 : 2;
        const gap = 12.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final summary in summaries)
              SizedBox(
                width: width,
                child: MetricTile(
                  summary: summary,
                  selected: summary.metric == _focused,
                  onTap: () => setState(() => _focused = summary.metric),
                  series: [
                    for (final day in days)
                      if (snapshot[summary.metric][day] != null)
                        snapshot[summary.metric][day]!,
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _noCorrelations() {
    return NeuCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Text(
        'Todavía no hay días suficientes para cruzar tus métricas con '
        'confianza. Hacen falta al menos '
        '${MetricsService.minCorrelationSamples} días con dato en dos '
        'métricas a la vez.',
        style: GoogleFonts.outfit(
          fontSize: 13.5,
          height: 1.45,
          color: BentoTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _reviewEntry() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WeeklyReviewScreen()),
      ),
      child: NeuCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 22,
              color: BentoTheme.accentLime,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revisión semanal',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Mira la semana, apunta qué funcionó y cierra el ciclo.',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: BentoTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: BentoTheme.creamAlpha(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 42),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 44,
              color: BentoTheme.creamAlpha(0.28),
            ),
            const SizedBox(height: 16),
            Text(
              'Nada que analizar todavía',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: BentoTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'En cuanto registres sueño, pomodoros, hábitos o gastos, esta '
              'pantalla empieza a cruzarlos sola.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                height: 1.45,
                color: BentoTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
