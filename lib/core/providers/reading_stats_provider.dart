import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/achievement_catalog.dart';
import '../services/cache_service.dart';
import 'rpg_provider.dart';

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Estadísticas de lectura acumuladas, todo en local.
///
/// [dailySeconds] mapea `yyyy-MM-dd` → segundos leídos ese día, que es el
/// formato que necesita el heatmap y el que hace triviales racha y totales.
class ReadingStats {
  final Map<String, int> dailySeconds;
  final int totalSeconds;
  final int sessions;

  /// Minutos ya convertidos en XP. Se guarda aparte para no volver a premiar
  /// los mismos minutos si el redondeo deja restos entre sesiones.
  final int rewardedMinutes;

  /// Libros ya contados como terminados, para no premiar dos veces al volver
  /// a abrir un libro que ya estaba al final.
  final List<String> finishedBookIds;

  const ReadingStats({
    this.dailySeconds = const {},
    this.totalSeconds = 0,
    this.sessions = 0,
    this.rewardedMinutes = 0,
    this.finishedBookIds = const [],
  });

  int get totalMinutes => totalSeconds ~/ 60;

  int secondsOn(DateTime date) => dailySeconds[_dayKey(date)] ?? 0;

  int get todaySeconds => secondsOn(DateTime.now());

  /// Días consecutivos leyendo hasta hoy. Si hoy aún no se ha leído, la racha
  /// sigue viva mientras ayer sí se haya leído: castigar antes de que acabe el
  /// día haría que la racha parpadeara cada mañana.
  int get streak {
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if ((dailySeconds[_dayKey(cursor)] ?? 0) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
      if ((dailySeconds[_dayKey(cursor)] ?? 0) == 0) return 0;
    }

    var count = 0;
    while ((dailySeconds[_dayKey(cursor)] ?? 0) > 0) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// Segundos leídos por día en los últimos [days] días, del más antiguo al
  /// más reciente. Pensado para pintar el heatmap sin recorrer todo el mapa.
  List<({DateTime day, int seconds})> lastDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          seconds: dailySeconds[_dayKey(today.subtract(Duration(days: i)))] ?? 0,
        ),
    ];
  }

  ReadingStats copyWith({
    Map<String, int>? dailySeconds,
    int? totalSeconds,
    int? sessions,
    int? rewardedMinutes,
    List<String>? finishedBookIds,
  }) {
    return ReadingStats(
      dailySeconds: dailySeconds ?? this.dailySeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      sessions: sessions ?? this.sessions,
      rewardedMinutes: rewardedMinutes ?? this.rewardedMinutes,
      finishedBookIds: finishedBookIds ?? this.finishedBookIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'daily_seconds': dailySeconds,
        'total_seconds': totalSeconds,
        'sessions': sessions,
        'rewarded_minutes': rewardedMinutes,
        'finished_book_ids': finishedBookIds,
      };

  factory ReadingStats.fromJson(Map<String, dynamic> json) => ReadingStats(
        dailySeconds: {
          for (final entry in (json['daily_seconds'] as Map? ?? {}).entries)
            entry.key as String: (entry.value as num).toInt(),
        },
        totalSeconds: (json['total_seconds'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        rewardedMinutes: (json['rewarded_minutes'] as num?)?.toInt() ?? 0,
        finishedBookIds: [
          for (final id in (json['finished_book_ids'] as List? ?? [])) id as String,
        ],
      );
}

class ReadingStatsNotifier extends Notifier<ReadingStats> {
  static const _cacheKey = 'reading_stats';

  /// Sesiones por debajo de esto son ruido (abrir el libro y cerrarlo).
  static const _minSessionSeconds = 30;

  /// Tope de XP por sesión: leer tres horas seguidas no debería desbalancear
  /// el resto del sistema RPG.
  static const _maxRewardedMinutesPerSession = 60;

  @override
  ReadingStats build() {
    _load();
    return const ReadingStats();
  }

  Future<void> _load() async {
    try {
      final cached = await CacheService.read(_cacheKey);
      if (cached is Map<String, dynamic>) {
        state = ReadingStats.fromJson(cached);
      }
    } catch (_) {
      // Caché corrupto: se arranca de cero
    }
  }

  Future<void> _persist() => CacheService.save(_cacheKey, state.toJson());

  /// Registra una sesión terminada y devuelve el resultado del premio RPG
  /// (`null` si la sesión fue demasiado corta para contar).
  Map<String, dynamic>? registerSession({
    required DateTime startedAt,
    required int seconds,
  }) {
    if (seconds < _minSessionSeconds) return null;

    final key = _dayKey(startedAt);
    final daily = Map<String, int>.of(state.dailySeconds);
    daily[key] = (daily[key] ?? 0) + seconds;

    final newTotalSeconds = state.totalSeconds + seconds;
    final newTotalMinutes = newTotalSeconds ~/ 60;

    // Solo se premian los minutos completos que aún no se habían premiado, con
    // tope por sesión.
    final pendingMinutes =
        (newTotalMinutes - state.rewardedMinutes).clamp(0, _maxRewardedMinutesPerSession);

    state = state.copyWith(
      dailySeconds: daily,
      totalSeconds: newTotalSeconds,
      sessions: state.sessions + 1,
      rewardedMinutes: state.rewardedMinutes + pendingMinutes,
    );
    unawaited(_persist());

    if (pendingMinutes <= 0) return null;

    return ref.read(rpgProvider.notifier).gainXpAndGold(
      pendingMinutes * 2,
      pendingMinutes,
      counterAmounts: {RpgCounters.readingMinutes: pendingMinutes},
    );
  }

  /// Premia un resaltado guardado. Es barato a propósito: el valor está en
  /// acumular el logro, no en farmear XP subrayando.
  void registerHighlight() {
    ref.read(rpgProvider.notifier).gainXpAndGold(
      2,
      1,
      counterKeys: [RpgCounters.highlights],
    );
  }

  /// Premia terminar un libro la primera vez que se llega al final.
  /// Devuelve `null` si ese libro ya estaba contado.
  Map<String, dynamic>? registerBookFinished(String bookId) {
    if (state.finishedBookIds.contains(bookId)) return null;

    state = state.copyWith(finishedBookIds: [...state.finishedBookIds, bookId]);
    unawaited(_persist());

    return ref.read(rpgProvider.notifier).gainXpAndGold(
      80,
      50,
      counterKeys: [RpgCounters.booksFinished],
    );
  }
}

final readingStatsProvider =
    NotifierProvider<ReadingStatsNotifier, ReadingStats>(ReadingStatsNotifier.new);
