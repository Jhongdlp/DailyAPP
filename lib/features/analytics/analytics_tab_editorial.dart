import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/metric_model.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/services/metrics_service.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'weekly_review_screen.dart';
import 'widgets/sparkline.dart';

/// Pestaña de Analíticas en Estilo Editorial:
/// - Rango temporal segmentado (Semana, Mes, Año)
/// - Cuadrícula de métricas clave con sparklines y deltas de cambio
/// - Gráfica de tendencia detallada interactiva para la métrica seleccionada
/// - Tarjetas de correlaciones descubiertas entre hábitos y rendimiento
/// - Acceso a la Revisión Semanal guiada por IA
class AnalyticsTabEditorial extends ConsumerStatefulWidget {
  const AnalyticsTabEditorial({super.key});

  @override
  ConsumerState<AnalyticsTabEditorial> createState() => _AnalyticsTabEditorialState();
}

class _AnalyticsTabEditorialState extends ConsumerState<AnalyticsTabEditorial> {
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

    final focused = summaries.any((s) => s.metric == _focused)
        ? _focused!
        : (summaries.isNotEmpty ? summaries.first.metric : null);

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
          children: [
            _HeaderEditorial(
              onReviewTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WeeklyReviewScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _RangeBarEditorial(selected: range),
            const SizedBox(height: 24),
            if (summaries.isEmpty)
              _EmptyStateEditorial(range: range)
            else ...[
              EditorialSectionLabel(
                'TU ${range.label.toUpperCase()}',
                trailing: Text(
                  '${summaries.where((s) => s.hasData).length} activas',
                  style: EditorialTheme.label(11, color: EditorialTheme.muted),
                ),
              ),
              const SizedBox(height: 10),
              _MetricsGridEditorial(
                summaries: summaries,
                snapshot: snapshot,
                days: days,
                selectedMetric: focused,
                onSelect: (m) {
                  HapticFeedback.selectionClick();
                  setState(() => _focused = m);
                },
              ),
              if (focused != null) ...[
                const SizedBox(height: 28),
                EditorialSectionLabel(
                  'TENDENCIA DETALLADA',
                  trailing: Text(
                    focused.label.toUpperCase(),
                    style: EditorialTheme.label(
                      11,
                      color: EditorialTheme.accent(focused.accent, onDark: true),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _TrendChartCardEditorial(
                  metric: focused,
                  points: [
                    for (final day in days)
                      (day: day, value: snapshot[focused][day]),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              const EditorialSectionLabel(
                'QUÉ VA CON QUÉ',
                trailing: Text('PATRONES DETECTADOS'),
              ),
              const SizedBox(height: 10),
              if (correlations.isEmpty)
                const _NoCorrelationsEditorial()
              else
                for (final c in correlations) ...[
                  _CorrelationCardEditorial(correlation: c),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 20),
              _WeeklyReviewHeroCard(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WeeklyReviewScreen(),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER Y SELECTOR DE RANGO
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderEditorial extends StatelessWidget {
  final VoidCallback onReviewTap;
  const _HeaderEditorial({required this.onReviewTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analíticas',
                style: EditorialTheme.caps(
                  28,
                  color: EditorialTheme.paper,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tendencias, rendimiento y correlaciones cruzadas',
                style: EditorialTheme.text(
                  12,
                  color: EditorialTheme.muted,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        EditorialCircleButton(
          icon: Icons.auto_awesome_rounded,
          tooltip: 'Revisión Semanal',
          onTap: onReviewTap,
          size: 44,
        ),
      ],
    );
  }
}

class _RangeBarEditorial extends ConsumerWidget {
  final AnalyticsRange selected;
  const _RangeBarEditorial({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: EditorialTheme.surface,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        border: Border.all(color: EditorialTheme.surfaceHigh, width: 1),
      ),
      child: Row(
        children: [
          for (final range in AnalyticsRange.values)
            Expanded(
              child: _RangeSegmentEditorial(
                range: range,
                selected: range == selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(analyticsRangeProvider.notifier).select(range);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeSegmentEditorial extends StatelessWidget {
  final AnalyticsRange range;
  final bool selected;
  final VoidCallback onTap;

  const _RangeSegmentEditorial({
    required this.range,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : Colors.transparent,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Text(
          range.label,
          style: EditorialTheme.text(
            13,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? EditorialTheme.ink : EditorialTheme.muted,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRILLA DE MÉTRICAS EDITORIAL
// ─────────────────────────────────────────────────────────────────────────────

class _MetricsGridEditorial extends StatelessWidget {
  final List<MetricSummary> summaries;
  final MetricsSnapshot snapshot;
  final List<DateTime> days;
  final DailyMetric? selectedMetric;
  final ValueChanged<DailyMetric> onSelect;

  const _MetricsGridEditorial({
    required this.summaries,
    required this.snapshot,
    required this.days,
    required this.selectedMetric,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 500 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.18,
          ),
          itemCount: summaries.length,
          itemBuilder: (context, index) {
            final summary = summaries[index];
            final metric = summary.metric;
            final series = [
              for (final d in days) snapshot[metric][d] ?? 0.0,
            ];
            final isSelected = selectedMetric == metric;

            return _MetricTileEditorial(
              summary: summary,
              series: series,
              selected: isSelected,
              onTap: () => onSelect(metric),
            );
          },
        );
      },
    );
  }
}

class _MetricTileEditorial extends StatelessWidget {
  final MetricSummary summary;
  final List<double> series;
  final bool selected;
  final VoidCallback onTap;

  const _MetricTileEditorial({
    required this.summary,
    required this.series,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final metric = summary.metric;
    final accent = EditorialTheme.accent(metric.accent, onDark: selected);

    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          border: Border.all(
            color: selected ? EditorialTheme.paper : EditorialTheme.surfaceHigh,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: selected ? 0.15 : 0.20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    metric.icon,
                    size: 14,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.text(
                      12,
                      weight: FontWeight.w600,
                      color: selected ? EditorialTheme.ink : EditorialTheme.paperAlpha(0.85),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              summary.hasData ? metric.format(summary.value!) : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorialTheme.caps(
                20,
                color: selected ? EditorialTheme.ink : EditorialTheme.paper,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ChangeChipEditorial(summary: summary, onLight: selected),
                SizedBox(
                  width: 44,
                  height: 18,
                  child: Sparkline(
                    values: series,
                    color: accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeChipEditorial extends StatelessWidget {
  final MetricSummary summary;
  final bool onLight;

  const _ChangeChipEditorial({required this.summary, required this.onLight});

  @override
  Widget build(BuildContext context) {
    final change = summary.change;

    if (change == null) {
      return Text(
        summary.hasData ? 'sin comp.' : 'sin datos',
        style: EditorialTheme.text(
          10,
          color: onLight ? EditorialTheme.grayText : EditorialTheme.muted,
        ),
      );
    }

    final improved = summary.isImprovement;
    final color = improved == null
        ? (onLight ? EditorialTheme.grayText : EditorialTheme.muted)
        : improved
            ? const Color(0xFF16A34A)
            : const Color(0xFFEA580C);

    final percent = (change.abs() * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          change > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 1),
        Text(
          '$percent%',
          style: EditorialTheme.text(
            11,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRÁFICA DE TENDENCIA DETALLADA
// ─────────────────────────────────────────────────────────────────────────────

typedef _TrendPoint = ({DateTime day, double? value});

class _TrendChartCardEditorial extends StatelessWidget {
  final DailyMetric metric;
  final List<_TrendPoint> points;

  const _TrendChartCardEditorial({
    required this.metric,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final withData = points.where((p) => p.value != null).toList();
    final accent = EditorialTheme.accent(metric.accent, onDark: false);

    if (withData.length < 2) {
      return Container(
        height: 180,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(metric.icon, size: 28, color: EditorialTheme.grayText),
              const SizedBox(height: 10),
              Text(
                'Aún no hay suficientes registros de ${metric.inlineName}.',
                textAlign: TextAlign.center,
                style: EditorialTheme.text(13, color: EditorialTheme.grayText),
              ),
            ],
          ),
        ),
      );
    }

    var min = withData.first.value!;
    var max = withData.first.value!;
    for (final p in withData) {
      if (p.value! < min) min = p.value!;
      if (p.value! > max) max = p.value!;
    }

    if (min > 0 && min < max * 0.4) min = 0;
    if (min == max) {
      min = min - 1;
      max = max + 1;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(metric.icon, size: 15, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    metric.label,
                    style: EditorialTheme.text(
                      14,
                      weight: FontWeight.w700,
                      color: EditorialTheme.ink,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${withData.length} días con dato',
                  style: EditorialTheme.text(11, weight: FontWeight.w600, color: EditorialTheme.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Máx: ${metric.format(max)}',
                style: EditorialTheme.text(11, weight: FontWeight.w600, color: EditorialTheme.grayText),
              ),
              Text(
                'Mín: ${metric.format(min)}',
                style: EditorialTheme.text(11, weight: FontWeight.w600, color: EditorialTheme.grayText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _EditorialTrendPainter(
                points: points,
                min: min,
                max: max,
                color: accent,
                gridColor: EditorialTheme.grayStrong,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtDate(points.first.day),
                style: EditorialTheme.text(11, color: EditorialTheme.grayText),
              ),
              Text(
                _fmtDate(points.last.day),
                style: EditorialTheme.text(11, color: EditorialTheme.grayText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}';
}

class _EditorialTrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double min;
  final double max;
  final Color color;
  final Color gridColor;

  _EditorialTrendPainter({
    required this.points,
    required this.min,
    required this.max,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final n = points.length;
    if (n < 2) return;

    final dx = size.width / (n - 1);
    final path = Path();
    final fillPath = Path();

    var started = false;
    Offset? lastValid;

    for (var i = 0; i < n; i++) {
      final v = points[i].value;
      if (v == null) {
        started = false;
        continue;
      }

      final normalized = ((v - min) / (max - min)).clamp(0.0, 1.0);
      final x = i * dx;
      final y = size.height - (normalized * size.height);

      if (!started) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        started = true;
      } else {
        final prev = lastValid!;
        final c1 = Offset(prev.dx + (x - prev.dx) / 2, prev.dy);
        final c2 = Offset(prev.dx + (x - prev.dx) / 2, y);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, x, y);
        fillPath.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, x, y);
      }
      lastValid = Offset(x, y);
    }

    if (lastValid != null) {
      fillPath.lineTo(lastValid.dx, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(fillPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    final dotInner = Paint()..color = EditorialTheme.paper;

    for (var i = 0; i < n; i++) {
      final v = points[i].value;
      if (v == null) continue;
      final normalized = ((v - min) / (max - min)).clamp(0.0, 1.0);
      final pt = Offset(i * dx, size.height - (normalized * size.height));
      canvas.drawCircle(pt, 4, dotPaint);
      canvas.drawCircle(pt, 2, dotInner);
    }
  }

  @override
  bool shouldRepaint(_EditorialTrendPainter old) =>
      old.min != min ||
      old.max != max ||
      old.color != color ||
      old.points.length != points.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// CORRELACIONES EDITORIAL
// ─────────────────────────────────────────────────────────────────────────────

class _CorrelationCardEditorial extends StatelessWidget {
  final MetricCorrelation correlation;
  const _CorrelationCardEditorial({required this.correlation});

  @override
  Widget build(BuildContext context) {
    final c = correlation;
    final driverColor = EditorialTheme.accent(c.driver.accent, onDark: false);
    final outcomeColor = EditorialTheme.accent(c.outcome.accent, onDark: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetricPillEditorial(metric: c.driver, color: driverColor),
              const SizedBox(width: 6),
              Icon(
                c.isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 16,
                color: EditorialTheme.grayText,
              ),
              const SizedBox(width: 6),
              _MetricPillEditorial(metric: c.outcome, color: outcomeColor),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${c.samples} días',
                  style: EditorialTheme.text(11, weight: FontWeight.w700, color: EditorialTheme.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            MetricsService.describe(c),
            style: EditorialTheme.text(
              14,
              weight: FontWeight.w600,
              color: EditorialTheme.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _StrengthBarEditorial(strength: c.strength, color: outcomeColor),
          const SizedBox(height: 8),
          Text(
            'Coincidencia observada en tus registros, no una causa demostrada.',
            style: EditorialTheme.text(
              11,
              color: EditorialTheme.grayText,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPillEditorial extends StatelessWidget {
  final DailyMetric metric;
  final Color color;

  const _MetricPillEditorial({required this.metric, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(metric.icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            metric.label,
            style: EditorialTheme.text(
              11,
              weight: FontWeight.w700,
              color: EditorialTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _StrengthBarEditorial extends StatelessWidget {
  final double strength;
  final Color color;

  const _StrengthBarEditorial({required this.strength, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = strength >= 0.7
        ? 'Relación muy marcada'
        : (strength >= 0.5 ? 'Relación clara' : 'Relación leve');

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Container(
              height: 6,
              color: EditorialTheme.grayStrong,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: strength.clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: EditorialTheme.text(
            11,
            weight: FontWeight.w700,
            color: EditorialTheme.ink,
          ),
        ),
      ],
    );
  }
}

class _NoCorrelationsEditorial extends StatelessWidget {
  const _NoCorrelationsEditorial();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialTheme.surface,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        border: Border.all(color: EditorialTheme.surfaceHigh, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_outlined, size: 24, color: EditorialTheme.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscando patrones',
                  style: EditorialTheme.text(
                    13,
                    weight: FontWeight.w700,
                    color: EditorialTheme.paper,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'A medida que registres más días, aparecerán relaciones automáticas.',
                  style: EditorialTheme.text(11, color: EditorialTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO CARD DE REVISIÓN SEMANAL
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyReviewHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _WeeklyReviewHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: EditorialTheme.accent(BentoTheme.accentBrain, onDark: false).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.psychology_rounded,
                size: 24,
                color: EditorialTheme.accent(BentoTheme.accentBrain, onDark: false),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revisión Semanal Guiada',
                    style: EditorialTheme.text(
                      15,
                      weight: FontWeight.w700,
                      color: EditorialTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Analiza victorias, fricciones y síntesis con IA',
                    style: EditorialTheme.text(12, color: EditorialTheme.grayText),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: EditorialTheme.ink,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ESTADO VACÍO
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyStateEditorial extends StatelessWidget {
  final AnalyticsRange range;
  const _EmptyStateEditorial({required this.range});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_rounded,
                size: 48,
                color: EditorialTheme.accent(BentoTheme.accentBrain, onDark: false),
              ),
              const SizedBox(height: 16),
              Text(
                'Sin datos para ${range.label.toLowerCase()}',
                textAlign: TextAlign.center,
                style: EditorialTheme.caps(18, color: EditorialTheme.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'Registra tus hábitos, tareas o sueño para ver analíticas y tendencias completas.',
                textAlign: TextAlign.center,
                style: EditorialTheme.text(13, color: EditorialTheme.grayText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
