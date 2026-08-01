import 'dart:math' as math;

import '../models/metric_model.dart';

/// Matemática de las analíticas. Todo estático y puro: recibe series ya
/// construidas y no sabe nada de Riverpod ni de Supabase, así que se puede
/// probar entero sin levantar la app.
class MetricsService {
  const MetricsService._();

  /// Días con dato en ambas series que hacen falta para arriesgar una
  /// conclusión. Con menos, cualquier par de números parece una relación.
  static const minCorrelationSamples = 8;

  /// Por debajo de esto la relación es ruido y no se enseña. No es un umbral
  /// estadístico formal: es el punto donde la frase deja de ser útil.
  static const minCorrelationStrength = 0.35;

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Los días de `[from, to)`, en orden.
  static List<DateTime> daysBetween(DateTime from, DateTime to) {
    final out = <DateTime>[];
    var cursor = dayOnly(from);
    final end = dayOnly(to);
    while (cursor.isBefore(end)) {
      out.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  /// Comienzo de la semana (lunes) que contiene [day].
  static DateTime startOfWeek(DateTime day) {
    final d = dayOnly(day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// Resume una serie dentro de `[from, to)` según la agregación de la métrica.
  ///
  /// Los días sin dato se ignoran en vez de contarse como cero: no dormir no es
  /// lo mismo que no haber registrado el sueño, y promediar el hueco como cero
  /// hundiría la media por un fallo de registro.
  static ({double? value, int samples}) aggregate(
    DailyMetric metric,
    MetricSeries series,
    DateTime from,
    DateTime to,
  ) {
    final values = <double>[];
    for (final day in daysBetween(from, to)) {
      final v = series[day];
      if (v != null) values.add(v);
    }

    if (values.isEmpty) return (value: null, samples: 0);

    final total = values.fold<double>(0, (a, b) => a + b);
    final value = switch (metric.aggregation) {
      MetricAggregation.sum => total,
      MetricAggregation.average => total / values.length,
    };

    return (value: value, samples: values.length);
  }

  /// Resumen de [metric] en `[from, to)` comparado con el periodo inmediato
  /// anterior de la misma duración.
  static MetricSummary summarize(
    DailyMetric metric,
    MetricSeries series,
    DateTime from,
    DateTime to,
  ) {
    final span = dayOnly(to).difference(dayOnly(from));
    final current = aggregate(metric, series, from, to);
    final previous = aggregate(metric, series, from.subtract(span), from);

    return MetricSummary(
      metric: metric,
      value: current.value,
      previous: previous.value,
      samples: current.samples,
    );
  }

  /// Coeficiente de correlación de Pearson entre dos listas emparejadas.
  ///
  /// Devuelve `null` si no hay varianza en alguna de las dos: una serie plana
  /// no correlaciona con nada, y la fórmula dividiría por cero.
  static double? pearson(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.length < 2) return null;

    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;

    var covariance = 0.0;
    var varX = 0.0;
    var varY = 0.0;

    for (var i = 0; i < n; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      covariance += dx * dy;
      varX += dx * dx;
      varY += dy * dy;
    }

    if (varX == 0 || varY == 0) return null;

    return covariance / math.sqrt(varX * varY);
  }

  /// Días en que ambas métricas tienen dato, emparejados.
  static ({List<double> driver, List<double> outcome}) pairedValues(
    MetricSeries driver,
    MetricSeries outcome,
  ) {
    final xs = <double>[];
    final ys = <double>[];

    final days = driver.keys.toList()..sort();
    for (final day in days) {
      final y = outcome[day];
      if (y == null) continue;
      xs.add(driver[day]!);
      ys.add(y);
    }

    return (driver: xs, outcome: ys);
  }

  /// Busca una relación entre dos métricas, o `null` si no la hay o no hay
  /// datos suficientes.
  ///
  /// Además del coeficiente se calcula el contraste entre el tercio de días con
  /// menos [driver] y el tercio con más, porque «los días que dormiste 5.2h
  /// hiciste 2 pomodoros y los que dormiste 7.8h hiciste 5» se entiende, y
  /// «r = 0.62» no.
  static MetricCorrelation? correlate(
    DailyMetric driverMetric,
    MetricSeries driver,
    DailyMetric outcomeMetric,
    MetricSeries outcome,
  ) {
    if (driverMetric == outcomeMetric) return null;

    final paired = pairedValues(driver, outcome);
    if (paired.driver.length < minCorrelationSamples) return null;

    final r = pearson(paired.driver, paired.outcome);
    if (r == null || r.abs() < minCorrelationStrength) return null;

    // Se ordenan los días por el valor del driver y se parten en tercios; el
    // del medio se descarta a propósito, que es lo que hace visible el
    // contraste.
    final indices = List.generate(paired.driver.length, (i) => i)
      ..sort((a, b) => paired.driver[a].compareTo(paired.driver[b]));

    final third = math.max(1, indices.length ~/ 3);
    final lowIdx = indices.take(third);
    final highIdx = indices.skip(indices.length - third);

    double meanOf(Iterable<int> idx, List<double> values) =>
        idx.map((i) => values[i]).reduce((a, b) => a + b) / idx.length;

    return MetricCorrelation(
      driver: driverMetric,
      outcome: outcomeMetric,
      r: r,
      samples: paired.driver.length,
      lowDriver: meanOf(lowIdx, paired.driver),
      highDriver: meanOf(highIdx, paired.driver),
      lowOutcome: meanOf(lowIdx, paired.outcome),
      highOutcome: meanOf(highIdx, paired.outcome),
    );
  }

  /// Todas las relaciones que aguantan los umbrales, de más fuerte a más débil.
  ///
  /// Se prueban los pares en un solo sentido (A→B, no B→A): la correlación es
  /// simétrica, así que enseñar los dos sentidos sería repetir la misma frase
  /// dada la vuelta.
  static List<MetricCorrelation> findCorrelations(
    MetricsSnapshot snapshot, {
    int limit = 5,
  }) {
    final metrics = snapshot.available.toList();
    final out = <MetricCorrelation>[];

    for (var i = 0; i < metrics.length; i++) {
      for (var j = i + 1; j < metrics.length; j++) {
        final found = correlate(
          metrics[i],
          snapshot[metrics[i]],
          metrics[j],
          snapshot[metrics[j]],
        );
        if (found != null) out.add(found);
      }
    }

    out.sort((a, b) => b.strength.compareTo(a.strength));
    return out.take(limit).toList();
  }

  /// La relación puesta en una frase.
  static String describe(MetricCorrelation c) {
    final driver = c.driver;
    final outcome = c.outcome;

    final verb = c.isPositive ? 'sube' : 'baja';
    final low = driver.format(c.lowDriver);
    final high = driver.format(c.highDriver);

    return 'Los días de más ${driver.inlineName} ($high frente a $low), '
        'tu ${outcome.inlineName} $verb '
        'de ${outcome.format(c.lowOutcome)} a ${outcome.format(c.highOutcome)}.';
  }
}
