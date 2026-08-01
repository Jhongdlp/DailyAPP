import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/metric_model.dart';
import 'package:sistem_daily/core/services/metrics_service.dart';

DateTime _d(int day) => DateTime(2026, 7, day);

/// Construye una serie a partir del día del mes.
MetricSeries _series(Map<int, double> raw) =>
    {for (final e in raw.entries) _d(e.key): e.value};

void main() {
  group('aggregate', () {
    test('suma lo que se suma y promedia lo que se promedia', () {
      final series = _series({1: 10, 2: 20, 3: 30});

      final summed = MetricsService.aggregate(
        DailyMetric.focusMinutes,
        series,
        _d(1),
        _d(4),
      );
      final averaged = MetricsService.aggregate(
        DailyMetric.sleepMinutes,
        series,
        _d(1),
        _d(4),
      );

      expect(summed.value, 60);
      expect(averaged.value, 20);
    });

    test('los días sin dato se ignoran, no cuentan como cero', () {
      // Un hueco es "no registrado", no "durmió cero horas": promediarlo como
      // cero hundiría la media por un fallo de registro.
      final series = _series({1: 400, 3: 500});

      final result = MetricsService.aggregate(
        DailyMetric.sleepMinutes,
        series,
        _d(1),
        _d(4),
      );

      expect(result.value, 450);
      expect(result.samples, 2);
    });

    test('un periodo vacío no inventa un valor', () {
      final result = MetricsService.aggregate(
        DailyMetric.focusMinutes,
        _series({1: 10}),
        _d(5),
        _d(8),
      );

      expect(result.value, isNull);
      expect(result.samples, 0);
    });

    test('el rango excluye el día final', () {
      final result = MetricsService.aggregate(
        DailyMetric.focusMinutes,
        _series({1: 10, 2: 10, 3: 10}),
        _d(1),
        _d(3),
      );

      expect(result.value, 20);
    });
  });

  group('summarize', () {
    test('compara contra el periodo anterior de la misma duración', () {
      final series = _series({
        // semana anterior
        1: 100, 2: 100, 3: 100,
        // semana en curso
        4: 200, 5: 200, 6: 200,
      });

      final summary = MetricsService.summarize(
        DailyMetric.focusMinutes,
        series,
        _d(4),
        _d(7),
      );

      expect(summary.value, 600);
      expect(summary.previous, 300);
      expect(summary.change, 1.0);
      expect(summary.isImprovement, isTrue);
    });

    test('en el gasto, bajar es la buena noticia', () {
      final series = _series({1: 200, 2: 100});

      final summary = MetricsService.summarize(
        DailyMetric.expense,
        series,
        _d(2),
        _d(3),
      );

      expect(summary.change, -0.5);
      expect(summary.isImprovement, isTrue);
    });

    test('sin periodo anterior no hay porcentaje que enseñar', () {
      final summary = MetricsService.summarize(
        DailyMetric.focusMinutes,
        _series({5: 100}),
        _d(5),
        _d(6),
      );

      expect(summary.value, 100);
      expect(summary.change, isNull);
      expect(summary.isImprovement, isNull);
    });

    test('partir de cero no produce un cambio infinito', () {
      final series = _series({1: 0, 2: 50});

      final summary = MetricsService.summarize(
        DailyMetric.focusMinutes,
        series,
        _d(2),
        _d(3),
      );

      expect(summary.previous, 0);
      expect(summary.change, isNull);
    });
  });

  group('pearson', () {
    test('una relación perfecta da 1', () {
      final r = MetricsService.pearson([1, 2, 3, 4], [2, 4, 6, 8]);
      expect(r, closeTo(1.0, 1e-9));
    });

    test('una relación inversa perfecta da -1', () {
      final r = MetricsService.pearson([1, 2, 3, 4], [8, 6, 4, 2]);
      expect(r, closeTo(-1.0, 1e-9));
    });

    test('una serie plana no correlaciona con nada', () {
      expect(MetricsService.pearson([5, 5, 5, 5], [1, 2, 3, 4]), isNull);
    });

    test('listas de distinto tamaño o muy cortas devuelven null', () {
      expect(MetricsService.pearson([1, 2], [1]), isNull);
      expect(MetricsService.pearson([1], [1]), isNull);
    });
  });

  group('pairedValues', () {
    test('solo empareja los días que están en las dos series', () {
      final paired = MetricsService.pairedValues(
        _series({1: 10, 2: 20, 3: 30}),
        _series({2: 5, 3: 6, 9: 7}),
      );

      expect(paired.driver, [20, 30]);
      expect(paired.outcome, [5, 6]);
    });
  });

  group('correlate', () {
    /// Dormir más va con enfocarse más, sobre días suficientes.
    MetricsSnapshot buildSnapshot() {
      final sleep = <DateTime, double>{};
      final focus = <DateTime, double>{};

      for (var i = 1; i <= 12; i++) {
        sleep[_d(i)] = 300 + i * 20; // de 5h a 9h
        focus[_d(i)] = 10 + i * 10;
      }

      return MetricsSnapshot({
        DailyMetric.sleepMinutes: sleep,
        DailyMetric.focusMinutes: focus,
      });
    }

    test('encuentra la relación y la ordena por fuerza', () {
      final found = MetricsService.findCorrelations(buildSnapshot());

      expect(found, hasLength(1));
      expect(found.single.r, closeTo(1.0, 1e-9));
      expect(found.single.samples, 12);
    });

    test('el contraste compara el tercio bajo contra el alto', () {
      final c = MetricsService.findCorrelations(buildSnapshot()).single;

      // Cuatro días abajo (1-4) y cuatro arriba (9-12).
      expect(c.lowDriver, closeTo(350, 0.001));
      expect(c.highDriver, closeTo(510, 0.001));
      expect(c.lowOutcome, closeTo(35, 0.001));
      expect(c.highOutcome, closeTo(115, 0.001));
      expect(c.outcomeGap, greaterThan(0));
    });

    test('con pocos días no se arriesga ninguna conclusión', () {
      final snapshot = MetricsSnapshot({
        DailyMetric.sleepMinutes: _series({1: 300, 2: 400, 3: 500}),
        DailyMetric.focusMinutes: _series({1: 10, 2: 20, 3: 30}),
      });

      expect(MetricsService.findCorrelations(snapshot), isEmpty);
    });

    test('una relación débil se descarta como ruido', () {
      final sleep = <DateTime, double>{};
      final focus = <DateTime, double>{};
      // Sierra deliberada: sin tendencia común entre las dos.
      const noise = <double>[40, 10, 35, 15, 38, 12, 30, 20, 33, 18, 36, 14];
      for (var i = 1; i <= 12; i++) {
        sleep[_d(i)] = 300 + i * 20;
        focus[_d(i)] = noise[i - 1];
      }

      final found = MetricsService.findCorrelations(
        MetricsSnapshot({
          DailyMetric.sleepMinutes: sleep,
          DailyMetric.focusMinutes: focus,
        }),
      );

      expect(found, isEmpty);
    });

    test('una métrica no correlaciona consigo misma', () {
      final series = _series({for (var i = 1; i <= 12; i++) i: i.toDouble()});

      expect(
        MetricsService.correlate(
          DailyMetric.focusMinutes,
          series,
          DailyMetric.focusMinutes,
          series,
        ),
        isNull,
      );
    });
  });

  group('describe', () {
    test('la frase habla de números, no de coeficientes', () {
      final c = MetricCorrelation(
        driver: DailyMetric.sleepMinutes,
        outcome: DailyMetric.pomodoros,
        r: 0.7,
        samples: 20,
        lowDriver: 312,
        highDriver: 468,
        lowOutcome: 2.0,
        highOutcome: 5.0,
      );

      final text = MetricsService.describe(c);

      expect(text, contains('5.2 h'));
      expect(text, contains('7.8 h'));
      expect(text, contains('sube'));
      expect(text, isNot(contains('0.7')));
    });

    test('una relación inversa se cuenta como una bajada', () {
      final c = MetricCorrelation(
        driver: DailyMetric.sleepMinutes,
        outcome: DailyMetric.expense,
        r: -0.6,
        samples: 20,
        lowDriver: 300,
        highDriver: 480,
        lowOutcome: 40,
        highOutcome: 15,
      );

      expect(MetricsService.describe(c), contains('baja'));
    });
  });

  group('startOfWeek', () {
    test('devuelve el lunes de esa semana', () {
      // 2026-07-31 es viernes.
      expect(MetricsService.startOfWeek(DateTime(2026, 7, 31)),
          DateTime(2026, 7, 27));
    });

    test('un lunes es su propio comienzo de semana', () {
      expect(MetricsService.startOfWeek(DateTime(2026, 7, 27)),
          DateTime(2026, 7, 27));
    });

    test('un domingo pertenece a la semana que empezó el lunes anterior', () {
      expect(MetricsService.startOfWeek(DateTime(2026, 8, 2)),
          DateTime(2026, 7, 27));
    });
  });
}
