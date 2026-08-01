import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weekly_review_model.dart';
import '../services/cache_service.dart';
import '../services/metrics_service.dart';

/// Historial de revisiones semanales, indexado por el lunes de cada semana.
class WeeklyReviewNotifier extends Notifier<Map<String, WeeklyReview>> {
  static const _cacheKey = 'weekly_reviews';

  Future<void>? _loadFuture;

  @override
  Map<String, WeeklyReview> build() {
    _loadFuture = _load();
    return const {};
  }

  Future<void> _ensureLoaded() async {
    if (_loadFuture != null) await _loadFuture;
  }

  Future<void> _load() async {
    try {
      final cached = await CacheService.read(_cacheKey);
      if (cached is! List) return;

      final out = <String, WeeklyReview>{};
      for (final raw in cached) {
        try {
          final review = WeeklyReview.fromJson(Map<String, dynamic>.from(raw as Map));
          out[review.weekKey] = review;
        } catch (_) {
          // Una entrada corrupta no puede tumbar el resto del historial.
          continue;
        }
      }
      state = out;
    } catch (_) {}
  }

  void _persist() => unawaited(
        CacheService.save(_cacheKey, state.values.map((r) => r.toJson()).toList()),
      );

  /// La semana que toca revisar: la que acaba de terminar.
  ///
  /// El ritual se hace mirando atrás, así que el domingo por la noche todavía
  /// se revisa la semana en curso; a partir del lunes, la anterior.
  static DateTime currentWeekStart() =>
      MetricsService.startOfWeek(DateTime.now());

  WeeklyReview? forWeek(DateTime weekStart) =>
      state[WeeklyReview(weekStart: weekStart, completedAt: weekStart).weekKey];

  bool hasReviewFor(DateTime weekStart) => forWeek(weekStart) != null;

  /// Revisiones de la más reciente a la más antigua.
  List<WeeklyReview> get history {
    final list = state.values.toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return list;
  }

  /// Semanas seguidas cerrando la revisión, contando hacia atrás desde la
  /// semana en curso. Como en `planningStreak`, no romper la racha por no haber
  /// hecho todavía la de esta semana: aún estás a tiempo.
  int get streak {
    var cursor = currentWeekStart();
    if (!hasReviewFor(cursor)) {
      cursor = cursor.subtract(const Duration(days: 7));
      if (!hasReviewFor(cursor)) return 0;
    }

    var count = 0;
    while (hasReviewFor(cursor)) {
      count++;
      cursor = cursor.subtract(const Duration(days: 7));
      if (count > 520) break; // diez años: red de seguridad, no un límite real
    }
    return count;
  }

  Future<WeeklyReview> save({
    required DateTime weekStart,
    String? wins,
    String? frictions,
    String? aiSummary,
    String? nextFocus,
  }) async {
    await _ensureLoaded();

    final day = MetricsService.dayOnly(weekStart);
    final existing = forWeek(day);

    final merged = (existing ??
            WeeklyReview(weekStart: day, completedAt: DateTime.now()))
        .copyWith(
      wins: wins,
      frictions: frictions,
      aiSummary: aiSummary,
      nextFocus: nextFocus,
      completedAt: DateTime.now(),
    );

    state = {...state, merged.weekKey: merged};
    _persist();
    return merged;
  }
}

final weeklyReviewProvider =
    NotifierProvider<WeeklyReviewNotifier, Map<String, WeeklyReview>>(
        WeeklyReviewNotifier.new);
