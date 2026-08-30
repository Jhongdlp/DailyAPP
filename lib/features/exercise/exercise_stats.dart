import '../../core/models/exercise_model.dart';

/// Total de kilómetros corridos dentro de una semana (lunes a domingo).
class WeekBucket {
  final DateTime weekStart;
  final double km;
  const WeekBucket({required this.weekStart, required this.km});
}

/// Métricas derivadas del historial de carreras, calculadas una sola vez y
/// compartidas entre la pestaña y la pantalla de detalles para que ambas
/// cuenten siempre la misma historia.
class ExerciseStats {
  final double totalKm30;
  final double totalKm90;
  final double totalKmAll;
  final int sessions30;
  final int sessionsAll;
  final double totalMinutes30;
  final double? avgPace30;
  final int streakDays;
  final double? bestDistance;
  final List<WeekBucket> weeks;

  const ExerciseStats({
    required this.totalKm30,
    required this.totalKm90,
    required this.totalKmAll,
    required this.sessions30,
    required this.sessionsAll,
    required this.totalMinutes30,
    required this.avgPace30,
    required this.streakDays,
    required this.bestDistance,
    required this.weeks,
  });
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) {
  final day = _dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

ExerciseStats computeExerciseStats(List<ExerciseLog> logs) {
  final now = DateTime.now();
  final logged = logs
      .where((l) => l.distanceKm != null || l.durationMinutes != null)
      .toList();

  bool within(ExerciseLog l, int days) =>
      now.difference(l.loggedDate).inDays <= days;
  final last30 = logged.where((l) => within(l, 30)).toList();
  final last90 = logged.where((l) => within(l, 90)).toList();

  double sumKm(Iterable<ExerciseLog> xs) =>
      xs.fold<double>(0, (s, l) => s + (l.distanceKm ?? 0));

  final paces30 = last30
      .map((l) => l.computedPace)
      .whereType<double>()
      .toList();
  final avgPace30 = paces30.isEmpty
      ? null
      : paces30.reduce((a, b) => a + b) / paces30.length;

  double? bestDistance;
  for (final l in logged) {
    final km = l.distanceKm;
    if (km != null && (bestDistance == null || km > bestDistance)) {
      bestDistance = km;
    }
  }

  // Racha: días consecutivos con registro, contando hacia atrás desde hoy
  // (o desde ayer si hoy todavía no se registró nada).
  final loggedDays = logged.map((l) => _dateOnly(l.loggedDate)).toSet();
  var cursor = _dateOnly(now);
  if (!loggedDays.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (loggedDays.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final currentWeekStart = _mondayOf(now);
  final weeks = <WeekBucket>[
    for (var i = 7; i >= 0; i--)
      WeekBucket(
        weekStart: currentWeekStart.subtract(Duration(days: 7 * i)),
        km: sumKm(
          logged.where((l) {
            final start = currentWeekStart.subtract(Duration(days: 7 * i));
            final d = _dateOnly(l.loggedDate);
            return !d.isBefore(start) &&
                d.isBefore(start.add(const Duration(days: 7)));
          }),
        ),
      ),
  ];

  return ExerciseStats(
    totalKm30: sumKm(last30),
    totalKm90: sumKm(last90),
    totalKmAll: sumKm(logged),
    sessions30: last30.length,
    sessionsAll: logged.length,
    totalMinutes30: last30.fold<double>(
      0,
      (s, l) => s + (l.durationMinutes ?? 0),
    ),
    avgPace30: avgPace30,
    streakDays: streak,
    bestDistance: bestDistance,
    weeks: weeks,
  );
}
