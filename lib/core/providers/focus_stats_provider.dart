import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/achievement_catalog.dart';
import '../services/cache_service.dart';
import 'rpg_provider.dart';

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Historial de sesiones de enfoque (Pomodoro), todo en local.
///
/// Mismo contrato que [ReadingStats]: `yyyy-MM-dd` → cantidad, que es lo que
/// hace triviales la racha, el total del día y la barra de los últimos días
/// sin recorrer una lista de sesiones.
class FocusStats {
  /// Segundos de ENFOQUE (los descansos no cuentan) por día.
  final Map<String, int> dailySeconds;

  /// Pomodoros terminados enteros por día. Un enfoque abandonado a medias suma
  /// segundos pero no pomodoro: el número redondo solo se gana llegando al 0.
  final Map<String, int> dailyPomodoros;

  final int totalSeconds;
  final int sessions;

  /// Minutos ya convertidos en XP, para no premiar dos veces los restos.
  final int rewardedMinutes;

  /// `taskId` → pomodoros completados sobre esa tarea. Es lo que permite
  /// mostrar "llevas 3 🍅 en esta tarea" al elegirla.
  final Map<String, int> pomodorosByTask;

  const FocusStats({
    this.dailySeconds = const {},
    this.dailyPomodoros = const {},
    this.totalSeconds = 0,
    this.sessions = 0,
    this.rewardedMinutes = 0,
    this.pomodorosByTask = const {},
  });

  int get totalMinutes => totalSeconds ~/ 60;

  int secondsOn(DateTime date) => dailySeconds[_dayKey(date)] ?? 0;

  int get todaySeconds => secondsOn(DateTime.now());

  int get todayMinutes => todaySeconds ~/ 60;

  int get todayPomodoros => dailyPomodoros[_dayKey(DateTime.now())] ?? 0;

  int pomodorosOnTask(String? taskId) =>
      taskId == null ? 0 : (pomodorosByTask[taskId] ?? 0);

  /// Días consecutivos con enfoque hasta hoy. Si hoy aún no se ha enfocado la
  /// racha sigue viva mientras ayer sí: castigar antes de que acabe el día
  /// haría que la racha parpadeara cada mañana.
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

  /// Minutos enfocados por día en los últimos [days] días, del más antiguo al
  /// más reciente. Pensado para pintar la barra de la semana de un tirón.
  List<({DateTime day, int minutes})> lastDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          minutes:
              (dailySeconds[_dayKey(today.subtract(Duration(days: i)))] ?? 0) ~/ 60,
        ),
    ];
  }

  FocusStats copyWith({
    Map<String, int>? dailySeconds,
    Map<String, int>? dailyPomodoros,
    int? totalSeconds,
    int? sessions,
    int? rewardedMinutes,
    Map<String, int>? pomodorosByTask,
  }) {
    return FocusStats(
      dailySeconds: dailySeconds ?? this.dailySeconds,
      dailyPomodoros: dailyPomodoros ?? this.dailyPomodoros,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      sessions: sessions ?? this.sessions,
      rewardedMinutes: rewardedMinutes ?? this.rewardedMinutes,
      pomodorosByTask: pomodorosByTask ?? this.pomodorosByTask,
    );
  }

  Map<String, dynamic> toJson() => {
        'daily_seconds': dailySeconds,
        'daily_pomodoros': dailyPomodoros,
        'total_seconds': totalSeconds,
        'sessions': sessions,
        'rewarded_minutes': rewardedMinutes,
        'pomodoros_by_task': pomodorosByTask,
      };

  static Map<String, int> _intMap(dynamic raw) => {
        for (final entry in (raw as Map? ?? {}).entries)
          entry.key as String: (entry.value as num).toInt(),
      };

  factory FocusStats.fromJson(Map<String, dynamic> json) => FocusStats(
        dailySeconds: _intMap(json['daily_seconds']),
        dailyPomodoros: _intMap(json['daily_pomodoros']),
        totalSeconds: (json['total_seconds'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        rewardedMinutes: (json['rewarded_minutes'] as num?)?.toInt() ?? 0,
        pomodorosByTask: _intMap(json['pomodoros_by_task']),
      );
}

class FocusStatsNotifier extends Notifier<FocusStats> {
  static const _cacheKey = 'focus_stats';

  /// Por debajo de esto la sesión es ruido (abrir y cerrar la pantalla).
  static const _minSessionSeconds = 60;

  /// Tope de XP por sesión, para que un enfoque larguísimo no desbalancee el
  /// resto del sistema RPG.
  static const _maxRewardedMinutesPerSession = 60;

  /// Cuántas tareas distintas se recuerdan. El mapa se poda por orden de
  /// inserción (Dart lo conserva) para que no crezca sin fin.
  static const _maxTrackedTasks = 120;

  @override
  FocusStats build() {
    _load();
    return const FocusStats();
  }

  Future<void> _load() async {
    try {
      final cached = await CacheService.read(_cacheKey);
      if (cached is Map<String, dynamic>) {
        state = FocusStats.fromJson(cached);
      }
    } catch (_) {
      // Caché corrupto: se arranca de cero
    }
  }

  Future<void> _persist() => CacheService.save(_cacheKey, state.toJson());

  /// Registra un bloque de enfoque terminado (o abandonado) y devuelve el
  /// resultado del premio RPG, o `null` si fue demasiado corto para contar.
  ///
  /// [completed] distingue llegar al 0 de parar antes: solo lo primero suma
  /// pomodoro entero y cuenta para la tarea.
  Map<String, dynamic>? registerFocusSession({
    required DateTime startedAt,
    required int seconds,
    required bool completed,
    String? taskId,
  }) {
    if (seconds < _minSessionSeconds) return null;

    final key = _dayKey(startedAt);

    final daily = Map<String, int>.of(state.dailySeconds);
    daily[key] = (daily[key] ?? 0) + seconds;

    final pomodoros = Map<String, int>.of(state.dailyPomodoros);
    if (completed) {
      pomodoros[key] = (pomodoros[key] ?? 0) + 1;
    }

    var byTask = state.pomodorosByTask;
    if (completed && taskId != null) {
      final updated = Map<String, int>.of(byTask);
      // Reinsertar deja la tarea al final: la poda se come siempre lo más viejo.
      final previous = updated.remove(taskId) ?? 0;
      updated[taskId] = previous + 1;
      if (updated.length > _maxTrackedTasks) {
        final excess = updated.length - _maxTrackedTasks;
        for (final oldKey in updated.keys.take(excess).toList()) {
          updated.remove(oldKey);
        }
      }
      byTask = updated;
    }

    final newTotalSeconds = state.totalSeconds + seconds;
    final newTotalMinutes = newTotalSeconds ~/ 60;

    // Solo se premian los minutos completos aún no premiados, con tope.
    final pendingMinutes = (newTotalMinutes - state.rewardedMinutes)
        .clamp(0, _maxRewardedMinutesPerSession);

    state = state.copyWith(
      dailySeconds: daily,
      dailyPomodoros: pomodoros,
      totalSeconds: newTotalSeconds,
      sessions: state.sessions + 1,
      rewardedMinutes: state.rewardedMinutes + pendingMinutes,
      pomodorosByTask: byTask,
    );
    unawaited(_persist());

    if (pendingMinutes <= 0) return null;

    return ref.read(rpgProvider.notifier).gainXpAndGold(
          pendingMinutes * 2,
          pendingMinutes,
          counterAmounts: {RpgCounters.focusMinutes: pendingMinutes},
        );
  }
}

final focusStatsProvider =
    NotifierProvider<FocusStatsNotifier, FocusStats>(FocusStatsNotifier.new);
