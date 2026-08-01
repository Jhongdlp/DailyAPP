import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/metric_model.dart';
import '../models/transaction_model.dart';
import '../services/metrics_service.dart';
import 'finance_provider.dart';
import 'focus_stats_provider.dart';
import 'habits_provider.dart';
import 'reading_stats_provider.dart';
import 'sleep_provider.dart';
import 'tasks_provider.dart';

DateTime _day(DateTime d) => MetricsService.dayOnly(d);

/// Clave `yyyy-MM-dd` a día local. Las estadísticas de foco y lectura guardan
/// los días así.
DateTime? _fromDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;

  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;

  return DateTime(y, m, d);
}

MetricSeries _fromDayKeyMap(Map<String, int> raw, {double scale = 1}) {
  final out = <DateTime, double>{};
  for (final entry in raw.entries) {
    final day = _fromDayKey(entry.key);
    if (day == null) continue;
    out[day] = entry.value * scale;
  }
  return out;
}

/// Todas las señales de la app en un formato común.
///
/// Es un `Provider` derivado y no un servicio con estado propio: se recalcula
/// cuando cambia cualquiera de las fuentes, y ninguna de ellas necesita
/// enterarse de que las analíticas existen.
final metricsSnapshotProvider = Provider<MetricsSnapshot>((ref) {
  final series = <DailyMetric, MetricSeries>{};

  // --- Sueño -------------------------------------------------------------
  // `nightKey` es la fecha del despertar, que es la atribución que queremos:
  // lo que importa es cómo dormiste *para* ese día, no en cuál te acostaste.
  final sleep = ref.watch(sleepProvider);
  final sleepMinutes = <DateTime, double>{};
  final sleepQuality = <DateTime, double>{};

  for (final night in sleep.sessions.values) {
    final day = _day(night.date);
    final minutes = night.sleepMinutes;
    if (minutes != null) sleepMinutes[day] = minutes.toDouble();

    final quality = night.quality;
    if (quality != null) sleepQuality[day] = quality.toDouble();
  }

  if (sleepMinutes.isNotEmpty) series[DailyMetric.sleepMinutes] = sleepMinutes;
  if (sleepQuality.isNotEmpty) series[DailyMetric.sleepQuality] = sleepQuality;

  // --- Foco --------------------------------------------------------------
  final focus = ref.watch(focusStatsProvider);
  final focusMinutes = _fromDayKeyMap(focus.dailySeconds, scale: 1 / 60);
  final pomodoros = _fromDayKeyMap(focus.dailyPomodoros);

  if (focusMinutes.isNotEmpty) series[DailyMetric.focusMinutes] = focusMinutes;
  if (pomodoros.isNotEmpty) series[DailyMetric.pomodoros] = pomodoros;

  // --- Lectura -----------------------------------------------------------
  final reading = ref.watch(readingStatsProvider);
  final readingMinutes = _fromDayKeyMap(reading.dailySeconds, scale: 1 / 60);
  if (readingMinutes.isNotEmpty) {
    series[DailyMetric.readingMinutes] = readingMinutes;
  }

  // --- Hábitos -----------------------------------------------------------
  final habits = ref.watch(habitsProvider);
  if (habits.isNotEmpty) {
    final rate = <DateTime, double>{};
    final today = _day(DateTime.now());

    // Solo se mira hacia atrás hasta el hábito más antiguo: antes de eso no
    // había nada que cumplir y un 0% falso arrastraría todas las medias.
    DateTime? earliest;
    for (final h in habits) {
      final created = h.createdAt;
      if (created == null) continue;
      final day = _day(created);
      if (earliest == null || day.isBefore(earliest)) earliest = day;
    }
    earliest ??= today.subtract(const Duration(days: 90));

    for (final day in MetricsService.daysBetween(
      earliest,
      today.add(const Duration(days: 1)),
    )) {
      var scheduled = 0;
      var done = 0;

      for (final habit in habits) {
        // Un hábito no cuenta en los días en que no tocaba, ni antes de
        // existir: si no, crear un hábito hoy hundiría el histórico entero.
        if (!habit.daysOfWeek.contains(day.weekday)) continue;
        final created = habit.createdAt;
        if (created != null && _day(created).isAfter(day)) continue;

        scheduled++;
        if (habit.completedDates.contains(day)) done++;
      }

      if (scheduled > 0) rate[day] = done / scheduled;
    }

    if (rate.isNotEmpty) series[DailyMetric.habitRate] = rate;
  }

  // --- Tareas ------------------------------------------------------------
  final tasks = ref.watch(tasksProvider);
  final tasksDone = <DateTime, double>{};
  for (final task in tasks) {
    // Cuenta el día en que se completó, no el día para el que estaba puesta:
    // lo que se mide es la actividad real.
    final completedAt = task.completedAt;
    if (!task.completed || completedAt == null) continue;

    final day = _day(completedAt);
    tasksDone[day] = (tasksDone[day] ?? 0) + 1;
  }
  if (tasksDone.isNotEmpty) series[DailyMetric.tasksCompleted] = tasksDone;

  // --- Gasto -------------------------------------------------------------
  final txs = ref.watch(transactionsProvider).value ?? const [];
  final expense = <DateTime, double>{};
  for (final tx in txs) {
    // Las transferencias mueven dinero entre cuentas propias: no son gasto.
    if (tx.type != TransactionType.expense) continue;

    final day = _day(tx.occurredAt);
    expense[day] = (expense[day] ?? 0) + tx.amount;
  }
  if (expense.isNotEmpty) series[DailyMetric.expense] = expense;

  return MetricsSnapshot(series);
});

/// Ventana de tiempo que se está mirando en la pantalla de analíticas.
enum AnalyticsRange {
  week('7 días', 7),
  month('30 días', 30),
  quarter('90 días', 90);

  const AnalyticsRange(this.label, this.days);

  final String label;
  final int days;
}

class AnalyticsRangeNotifier extends Notifier<AnalyticsRange> {
  @override
  AnalyticsRange build() => AnalyticsRange.week;

  void select(AnalyticsRange range) => state = range;
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, AnalyticsRange>(
        AnalyticsRangeNotifier.new);

/// Resúmenes de todas las métricas con dato, comparados con el periodo
/// anterior de la misma duración.
final metricSummariesProvider = Provider<List<MetricSummary>>((ref) {
  final snapshot = ref.watch(metricsSnapshotProvider);
  final range = ref.watch(analyticsRangeProvider);

  // El periodo termina mañana a las 00:00 para que hoy entre completo.
  final to = MetricsService.dayOnly(DateTime.now()).add(const Duration(days: 1));
  final from = to.subtract(Duration(days: range.days));

  return [
    for (final metric in snapshot.available)
      MetricsService.summarize(metric, snapshot[metric], from, to),
  ];
});

/// Relaciones entre métricas. Se calculan sobre **todo** el histórico y no
/// sobre la ventana elegida: una correlación necesita muchos días para
/// significar algo, y siete nunca bastarían.
final correlationsProvider = Provider<List<MetricCorrelation>>((ref) {
  final snapshot = ref.watch(metricsSnapshotProvider);
  return MetricsService.findCorrelations(snapshot);
});
