import 'package:flutter/material.dart';

import '../theme/bento_theme.dart';

/// Cómo se resume una métrica al mirar un periodo entero.
///
/// Sumar horas de sueño de siete noches da un número sin sentido; sumar
/// minutos de foco de siete días es exactamente lo que interesa. La diferencia
/// no es cosmética: decide qué se compara contra la semana anterior.
enum MetricAggregation { sum, average }

/// Las señales que la app ya recoge, puestas en un formato común para poder
/// cruzarlas.
///
/// Cada feature guardaba lo suyo en su silo: sueño en `sleep_provider`, foco en
/// `focus_stats_provider`, gasto en `finance_provider`… y nadie las miraba
/// juntas. Todo esto se deriva de datos que ya existen; no hay tabla nueva.
enum DailyMetric {
  sleepMinutes(
    label: 'Sueño',
    unit: 'h',
    aggregation: MetricAggregation.average,
    higherIsBetter: true,
  ),
  sleepQuality(
    label: 'Calidad del sueño',
    unit: '/5',
    aggregation: MetricAggregation.average,
    higherIsBetter: true,
  ),
  focusMinutes(
    label: 'Foco',
    unit: 'min',
    aggregation: MetricAggregation.sum,
    higherIsBetter: true,
  ),
  pomodoros(
    label: 'Pomodoros',
    unit: '',
    aggregation: MetricAggregation.sum,
    higherIsBetter: true,
  ),
  habitRate(
    label: 'Hábitos',
    unit: '%',
    aggregation: MetricAggregation.average,
    higherIsBetter: true,
  ),
  tasksCompleted(
    label: 'Tareas hechas',
    unit: '',
    aggregation: MetricAggregation.sum,
    higherIsBetter: true,
  ),
  expense(
    label: 'Gasto',
    unit: '\$',
    aggregation: MetricAggregation.sum,
    higherIsBetter: false,
  ),
  readingMinutes(
    label: 'Lectura',
    unit: 'min',
    aggregation: MetricAggregation.sum,
    higherIsBetter: true,
  ),
  exerciseKm(
    label: 'Distancia',
    unit: 'km',
    aggregation: MetricAggregation.sum,
    higherIsBetter: true,
  ),
  exerciseMinutes(
    label: 'Ejercicio',
    unit: 'min',
    aggregation: MetricAggregation.sum,
    higherIsBetter: true,
  );

  const DailyMetric({
    required this.label,
    required this.unit,
    required this.aggregation,
    required this.higherIsBetter,
  });

  final String label;
  final String unit;
  final MetricAggregation aggregation;

  /// Si subir es bueno. El gasto es la excepción y por eso las flechas de
  /// tendencia no pueden pintarse solo por el signo del cambio.
  final bool higherIsBetter;

  /// Como en [AppDestination], el color es un getter y no un campo del enum:
  /// la paleta cambia en vivo con el tema y un `const` la congelaría.
  Color get accent => switch (this) {
        DailyMetric.sleepMinutes => BentoTheme.accentAlarm,
        DailyMetric.sleepQuality => BentoTheme.accentAlarm,
        DailyMetric.focusMinutes => BentoTheme.accentBlue,
        DailyMetric.pomodoros => BentoTheme.accentBlue,
        DailyMetric.habitRate => BentoTheme.accentHabits,
        DailyMetric.tasksCompleted => BentoTheme.accentLime,
        DailyMetric.expense => BentoTheme.accentFinance,
        DailyMetric.readingMinutes => BentoTheme.accentPurple,
        DailyMetric.exerciseKm => BentoTheme.accentOrange,
        DailyMetric.exerciseMinutes => BentoTheme.accentOrange,
      };

  IconData get icon => switch (this) {
        DailyMetric.sleepMinutes => Icons.bedtime_outlined,
        DailyMetric.sleepQuality => Icons.nightlight_outlined,
        DailyMetric.focusMinutes => Icons.timer_outlined,
        DailyMetric.pomodoros => Icons.local_fire_department_outlined,
        DailyMetric.habitRate => Icons.check_circle_outline,
        DailyMetric.tasksCompleted => Icons.task_alt_outlined,
        DailyMetric.expense => Icons.account_balance_wallet_outlined,
        DailyMetric.readingMinutes => Icons.auto_stories_outlined,
        DailyMetric.exerciseKm => Icons.directions_run,
        DailyMetric.exerciseMinutes => Icons.timer_outlined,
      };

  /// Texto corto para una tarjeta. Los minutos de sueño se muestran en horas
  /// porque «426 min» no se lee como una noche.
  String format(double value) => switch (this) {
        DailyMetric.sleepMinutes => '${(value / 60).toStringAsFixed(1)} h',
        DailyMetric.sleepQuality => value.toStringAsFixed(1),
        DailyMetric.habitRate => '${(value * 100).round()}%',
        DailyMetric.expense => '\$${value.toStringAsFixed(0)}',
        DailyMetric.focusMinutes ||
        DailyMetric.readingMinutes ||
        DailyMetric.exerciseMinutes =>
          '${value.round()} min',
        DailyMetric.pomodoros || DailyMetric.tasksCompleted => '${value.round()}',
        DailyMetric.exerciseKm => '${value.toStringAsFixed(1)} km',
      };

  /// Cómo se nombra la métrica dentro de una frase ("los días de **más foco**").
  String get inlineName => switch (this) {
        DailyMetric.sleepMinutes => 'sueño',
        DailyMetric.sleepQuality => 'calidad de sueño',
        DailyMetric.focusMinutes => 'foco',
        DailyMetric.pomodoros => 'pomodoros',
        DailyMetric.habitRate => 'cumplimiento de hábitos',
        DailyMetric.tasksCompleted => 'tareas completadas',
        DailyMetric.expense => 'gasto',
        DailyMetric.readingMinutes => 'lectura',
        DailyMetric.exerciseKm => 'distancia recorrida',
        DailyMetric.exerciseMinutes => 'ejercicio',
      };
}

/// Serie diaria de una métrica. La clave es el día a medianoche local.
typedef MetricSeries = Map<DateTime, double>;

/// Todo lo que se sabe de un periodo, ya cruzado.
class MetricsSnapshot {
  final Map<DailyMetric, MetricSeries> series;

  const MetricsSnapshot(this.series);

  static const empty = MetricsSnapshot({});

  MetricSeries operator [](DailyMetric metric) => series[metric] ?? const {};

  bool has(DailyMetric metric) => (series[metric] ?? const {}).isNotEmpty;

  Iterable<DailyMetric> get available =>
      DailyMetric.values.where(has);
}

/// Resumen de una métrica en un periodo, con el mismo cálculo aplicado al
/// periodo anterior para poder comparar.
class MetricSummary {
  final DailyMetric metric;
  final double? value;
  final double? previous;

  /// Días del periodo con dato. Un 100% de hábitos sobre un solo día no dice
  /// lo mismo que sobre siete, y la UI necesita poder avisarlo.
  final int samples;

  const MetricSummary({
    required this.metric,
    required this.value,
    required this.previous,
    required this.samples,
  });

  bool get hasData => value != null;

  /// Cambio relativo respecto al periodo anterior. `null` cuando no hay con qué
  /// comparar o cuando el anterior era cero (un salto desde cero es infinito y
  /// mostrar "+∞%" no ayuda).
  double? get change {
    final v = value;
    final p = previous;
    if (v == null || p == null || p == 0) return null;
    return (v - p) / p.abs();
  }

  /// Si el cambio es una buena noticia, teniendo en cuenta que en el gasto
  /// bajar es mejor.
  bool? get isImprovement {
    final c = change;
    if (c == null || c == 0) return null;
    return metric.higherIsBetter ? c > 0 : c < 0;
  }
}

/// Relación encontrada entre dos métricas diarias.
class MetricCorrelation {
  /// La métrica que se usa para partir los días (la "causa" aparente).
  final DailyMetric driver;

  /// La métrica que se mide en cada grupo.
  final DailyMetric outcome;

  /// Coeficiente de Pearson. Solo se usa para ordenar por fuerza: la frase que
  /// ve el usuario sale del contraste entre grupos, que es mucho más legible.
  final double r;

  final int samples;

  /// Media de [driver] en el tercio de días más bajo y más alto.
  final double lowDriver;
  final double highDriver;

  /// Media de [outcome] en esos mismos dos grupos.
  final double lowOutcome;
  final double highOutcome;

  const MetricCorrelation({
    required this.driver,
    required this.outcome,
    required this.r,
    required this.samples,
    required this.lowDriver,
    required this.highDriver,
    required this.lowOutcome,
    required this.highOutcome,
  });

  bool get isPositive => r > 0;

  double get strength => r.abs();

  /// Diferencia en [outcome] entre el grupo alto y el bajo.
  double get outcomeGap => highOutcome - lowOutcome;
}
