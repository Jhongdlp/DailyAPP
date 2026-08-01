import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/achievement_catalog.dart';
import '../models/alarm_model.dart';
import '../models/sleep_model.dart';
import '../services/cache_service.dart';
import '../services/sleep_service.dart';
import '../services/wake_check_service.dart';
import 'rpg_provider.dart';

/// Ciclo de sueño: horario configurado, registro de noches y métricas.
///
/// Todo vive en local ([CacheService]). No hay tabla en Supabase a propósito:
/// el dato solo tiene sentido junto a las alarmas, que también son locales, y
/// así el registro funciona con el móvil en avión.
class SleepNotifier extends Notifier<SleepData> {
  static const _cacheKey = 'sleep_data';

  /// Tras este tiempo sin validar la foto, se da la mañana por perdida y la
  /// noche se cierra como "alarma ignorada".
  static const _staleAfter = Duration(hours: 6);

  /// Solo se conservan las noches de este último año: el panel nunca mira más
  /// atrás y el JSON en SharedPreferences no debe crecer sin límite.
  static const _retentionDays = 400;

  Future<void>? _loadFuture;

  @override
  SleepData build() {
    _loadFuture = _load();
    return const SleepData();
  }

  Future<void> _ensureLoaded() async {
    if (_loadFuture != null) await _loadFuture;
  }

  Future<void> _load() async {
    try {
      final cached = await CacheService.read(_cacheKey);
      if (cached is Map) {
        state = SleepData.fromJson(Map<String, dynamic>.from(cached));
      }
    } catch (_) {
      // Caché corrupto: se arranca de cero en vez de dejar la pestaña rota.
    }
    _closeStaleNights();
    unawaited(_dropStaleWakeCheck());
    unawaited(SleepService.reschedule(state.schedule));
  }

  Future<void> _persist() => CacheService.save(_cacheKey, state.toJson());

  void _write(SleepData next) {
    state = next;
    unawaited(_persist());
  }

  SleepSession _sessionFor(String key) =>
      state.sessions[key] ?? SleepSession(nightKey: key);

  SleepData _withSession(SleepSession session) {
    final sessions = Map<String, SleepSession>.of(state.sessions);
    sessions[session.nightKey] = session;
    return state.copyWith(sessions: sessions);
  }

  // ── Configuración ──────────────────────────────────────────────────────

  Future<void> saveSchedule(SleepSchedule schedule) async {
    await _ensureLoaded();
    _write(state.copyWith(schedule: schedule));
    await SleepService.reschedule(schedule);
  }

  /// Alinea el horario con la alarma de sueño, que es quien manda sobre la hora
  /// de acostarse y los días.
  ///
  /// La alarma es lo que el usuario ve y edita; el [SleepSchedule] guarda lo
  /// que no cabe en una alarma (meta, avisos, verificación de vigilia). Tener
  /// dos fuentes para la misma hora sería garantía de que se desincronizan.
  Future<void> syncFromAlarm(AlarmModel? alarm) async {
    await _ensureLoaded();
    if (alarm == null || !alarm.isSleepAlarm) {
      if (!state.schedule.enabled) return;
      final off = state.schedule.copyWith(enabled: false);
      _write(state.copyWith(schedule: off));
      await SleepService.reschedule(off);
      return;
    }

    final next = state.schedule.copyWith(
      enabled: alarm.enabled,
      bedtimeHour: alarm.bedtimeHour,
      bedtimeMinute: alarm.bedtimeMinute,
      daysOfWeek: alarm.daysOfWeek,
    );
    _write(state.copyWith(schedule: next));
    await SleepService.reschedule(next);
  }

  // ── Registro del ciclo ─────────────────────────────────────────────────

  /// Marca el inicio del ciclo de sueño. Idempotente: tocar la notificación,
  /// su acción y el aviso repetido acaban aquí, y solo la primera cuenta.
  Future<void> confirmBedtime({DateTime? at}) async {
    await _ensureLoaded();
    final now = at ?? DateTime.now();
    final key = nightKeyFor(now);
    final existing = state.sessions[key];

    if (existing?.lightsOutAt != null) {
      // Ya estaba confirmada: solo hay que asegurarse de que no siga
      // insistiendo si la confirmación llegó por otra vía.
      await SleepService.cancelNags();
      return;
    }

    final session = _sessionFor(key).copyWith(
      lightsOutAt: now,
      bedtimeTarget: state.schedule.enabled
          ? state.schedule.bedtimeTargetFor(now)
          : null,
    );

    _write(_withSession(session).copyWith(openNightKey: key));

    await SleepService.cancelNags();
    // Las insistencias se reprograman ya para la noche siguiente; son
    // notificaciones de un solo uso, no semanales.
    await SleepService.scheduleNags(state.schedule);
  }

  /// La alarma de despertar empezó a sonar. Es lo que permite distinguir
  /// "me levanté a la hora" de "la dejé sonar 40 minutos" o "la ignoré".
  Future<void> registerRing(AlarmModel alarm, {DateTime? at}) async {
    await _ensureLoaded();
    final now = at ?? DateTime.now();
    final key = nightKeyFor(now);
    final existing = _sessionFor(key);

    // Solo el primer timbrazo de la mañana cuenta: `Alarm.ringing` puede
    // emitir varias veces para la misma alarma (arranque en frío + stream).
    if (existing.firstRingAt != null) return;

    final scheduled =
        DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);

    _write(_withSession(existing.copyWith(
      firstRingAt: now,
      alarmScheduledAt: scheduled,
    )));
  }

  /// Foto validada: la noche se cierra aquí. Devuelve la sesión resultante
  /// para que la pantalla de check-in la muestre.
  Future<SleepSession?> registerWake({
    String? alarmId,
    DateTime? at,
    int dismissAttempts = 0,
  }) async {
    await _ensureLoaded();
    final now = at ?? DateTime.now();
    final key = nightKeyFor(now);
    final existing = _sessionFor(key);
    if (existing.wokeAt != null) return existing;

    final session = existing.copyWith(
      wokeAt: now,
      alarmIgnored: false,
      dismissAttempts: dismissAttempts,
    );
    _write(_withSession(session).copyWith(clearOpenNight: true));

    if (alarmId != null) {
      await _scheduleWakeCheck(
        alarmId: alarmId,
        nightKey: key,
        wokeAt: now,
        round: 1,
      );
    }
    return session;
  }

  // ── Verificación de vigilia ────────────────────────────────────────────

  /// Programa la siguiente comprobación de "¿sigues despierto?", salvo que ya
  /// se haya agotado la ventana de vigilancia.
  Future<void> _scheduleWakeCheck({
    required String alarmId,
    required String nightKey,
    required DateTime wokeAt,
    required int round,
  }) async {
    final schedule = state.schedule;
    if (!schedule.wakeCheckEnabled) return;

    // La ventana se mide desde que se apagó la alarma: pasada, se asume que ya
    // estás en pie y se deja de insistir.
    final elapsed = DateTime.now().difference(wokeAt).inMinutes;
    if (elapsed + schedule.wakeCheckIntervalMinutes >
        schedule.wakeCheckWindowMinutes) {
      _write(state.copyWith(clearWakeCheck: true));
      return;
    }

    final pending = await WakeCheckService.schedule(
      alarmId: alarmId,
      nightKey: nightKey,
      wokeAt: wokeAt,
      round: round,
      interval: Duration(minutes: schedule.wakeCheckIntervalMinutes),
    );

    _write(pending == null
        ? state.copyWith(clearWakeCheck: true)
        : state.copyWith(wakeCheck: pending));
  }

  /// El usuario confirmó que sigue despierto: se apaga esta comprobación y se
  /// encadena la siguiente hasta agotar la ventana.
  Future<void> confirmAwake() async {
    await _ensureLoaded();
    final pending = state.wakeCheck;
    if (pending == null) return;

    await WakeCheckService.cancel(pending.nativeId);

    final session = _sessionFor(pending.nightKey);
    _write(_withSession(
      session.copyWith(wakeChecksPassed: session.wakeChecksPassed + 1),
    ).copyWith(clearWakeCheck: true));

    await _scheduleWakeCheck(
      alarmId: pending.alarmId,
      nightKey: pending.nightKey,
      wokeAt: pending.wokeAt,
      round: pending.round + 1,
    );
  }

  /// Descarta una comprobación que se quedó colgada (el móvil se apagó, la
  /// alarma sonó sola hasta agotarse). Sin esto, al abrir la app horas después
  /// el estado seguiría diciendo que hay una vigilancia activa.
  Future<void> _dropStaleWakeCheck() async {
    final pending = state.wakeCheck;
    if (pending == null) return;
    if (DateTime.now().difference(pending.dueAt) < const Duration(hours: 2)) {
      return;
    }
    await WakeCheckService.cancel(pending.nativeId);
    _write(state.copyWith(clearWakeCheck: true));
  }

  /// Cancela la vigilancia sin más (el usuario la descarta a mano).
  Future<void> cancelWakeCheck() async {
    await _ensureLoaded();
    final pending = state.wakeCheck;
    if (pending == null) return;
    await WakeCheckService.cancel(pending.nativeId);
    _write(state.copyWith(clearWakeCheck: true));
  }

  /// Anota que te volviste a dormir y a qué hora te levantaste de verdad.
  ///
  /// Corrige la duración de la noche hacia arriba: el tramo extra fue sueño,
  /// aunque fragmentado.
  Future<void> registerBackToSleep({
    required DateTime finalWakeAt,
    String? nightKey,
  }) async {
    await _ensureLoaded();
    final key = nightKey ?? nightKeyFor(DateTime.now());
    final session = _sessionFor(key);
    final first = session.wokeAt;
    // Sin un despertar previo no hay "volver a dormirse" que anotar, y una hora
    // anterior a él sería un dato imposible.
    if (first == null || !finalWakeAt.isAfter(first)) return;

    _write(_withSession(session.copyWith(finalWakeAt: finalWakeAt)));
    await cancelWakeCheck();
  }

  /// Corrige a mano las horas de una noche desde el panel.
  Future<void> editNight({
    required String nightKey,
    DateTime? lightsOutAt,
    DateTime? wokeAt,
    DateTime? finalWakeAt,
    bool clearFinalWake = false,
  }) async {
    await _ensureLoaded();
    final session = _sessionFor(nightKey);
    _write(_withSession(session.copyWith(
      lightsOutAt: lightsOutAt,
      wokeAt: wokeAt,
      finalWakeAt: finalWakeAt,
      clearFinalWake: clearFinalWake,
      // Corregir a mano una noche que se había dado por ignorada implica que sí
      // te levantaste; si no, la noche seguiría marcada en rojo con horas.
      alarmIgnored: (wokeAt ?? session.wokeAt) != null ? false : null,
    )));
  }

  /// Guarda las respuestas del check-in matutino y premia la noche.
  /// Devuelve el resultado de [RpgNotifier.gainXpAndGold], o `null` si la
  /// noche ya se había premiado.
  Future<Map<String, dynamic>?> submitCheckIn({
    required int quality,
    required int awakenings,
    required int latencyMinutes,
    String? nightKey,
  }) async {
    await _ensureLoaded();
    final key = nightKey ?? nightKeyFor(DateTime.now());
    final session = _sessionFor(key).copyWith(
      quality: quality,
      awakenings: awakenings,
      latencyMinutes: latencyMinutes,
    );
    _write(_withSession(session));
    // XP deliberadamente pequeño frente a los 50/25 de apagar la alarma: el
    // premio gordo es levantarse, esto solo empuja a responder tres toques.
    return _awardNight(session, xp: 10, gold: 5);
  }

  /// El usuario saltó el check-in. La noche se cuenta igual (la duración es
  /// dato objetivo), pero sin XP extra.
  Future<Map<String, dynamic>?> skipCheckIn({String? nightKey}) async {
    await _ensureLoaded();
    final key = nightKey ?? nightKeyFor(DateTime.now());
    return _awardNight(_sessionFor(key), xp: 0, gold: 0);
  }

  Map<String, dynamic>? _awardNight(
    SleepSession session, {
    required int xp,
    required int gold,
  }) {
    if (state.rewardedNights.contains(session.nightKey)) return null;
    final slept = session.sleepMinutes;
    if (slept == null) return null;

    _write(state.copyWith(
      rewardedNights: [...state.rewardedNights, session.nightKey],
    ));

    final counters = <String>[
      RpgCounters.sleepNights,
      if (slept >= state.schedule.goalMinutes) RpgCounters.sleepGoalNights,
    ];
    return ref.read(rpgProvider.notifier).gainXpAndGold(
          xp,
          gold,
          counterKeys: counters,
        );
  }

  /// Cierra noches que quedaron a medias: bedtime confirmado y despertar que
  /// nunca llegó, o alarma que sonó y jamás se validó. Sin esto, una mañana
  /// ignorada dejaría la noche "en curso" para siempre y la tarjeta mentiría.
  void _closeStaleNights() {
    final now = DateTime.now();
    var changed = false;
    final sessions = Map<String, SleepSession>.of(state.sessions);

    for (final entry in sessions.entries.toList()) {
      final session = entry.value;
      if (session.wokeAt != null) continue;

      final ring = session.firstRingAt;
      final lightsOut = session.lightsOutAt;
      final reference = ring ?? lightsOut;
      if (reference == null) continue;

      if (now.difference(reference) <= _staleAfter) continue;

      if (ring != null && !session.alarmIgnored) {
        sessions[entry.key] = session.copyWith(alarmIgnored: true);
        changed = true;
      }
    }

    // Poda de noches antiguas.
    final cutoff = sleepDayKey(now.subtract(const Duration(days: _retentionDays)));
    final stale = sessions.keys.where((k) => k.compareTo(cutoff) < 0).toList();
    for (final key in stale) {
      sessions.remove(key);
      changed = true;
    }

    final openKey = state.openNightKey;
    final closeOpen = openKey != null &&
        (sessions[openKey]?.wokeAt != null ||
            (sessions[openKey]?.lightsOutAt != null &&
                now.difference(sessions[openKey]!.lightsOutAt!) >
                    const Duration(hours: 20)));

    if (changed || closeOpen) {
      _write(state.copyWith(
        sessions: sessions,
        clearOpenNight: closeOpen,
      ));
    }
  }

  /// Fuerza el cierre de noches colgadas. Se llama al volver a primer plano
  /// desde la pestaña de alarma.
  Future<void> refreshStale() async {
    await _ensureLoaded();
    _closeStaleNights();
  }

  // ── Utilidad de desarrollo ─────────────────────────────────────────────

  /// Rellena [nights] noches sintéticas para poder revisar los gráficos sin
  /// esperar un mes. Solo disponible en debug.
  Future<void> seedDemoNights(int nights) async {
    if (!kDebugMode) return;
    await _ensureLoaded();

    final random = math.Random(7);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessions = Map<String, SleepSession>.of(state.sessions);

    for (var i = nights; i >= 1; i--) {
      final day = today.subtract(Duration(days: i));
      final weekend = day.weekday >= DateTime.saturday;

      // El fin de semana se acuesta ~90 min más tarde: así el jet lag social
      // aparece en los datos de prueba y se puede ver si el gráfico lo pinta.
      final baseBedMinutes = (weekend ? 23 * 60 + 90 : 23 * 60) +
          random.nextInt(70) - 35;
      final lightsOut = day
          .subtract(const Duration(days: 1))
          .add(Duration(minutes: baseBedMinutes));

      final target = day.subtract(const Duration(days: 1)).add(
            Duration(minutes: 23 * 60),
          );

      final alarmAt = day.add(Duration(minutes: (weekend ? 8 : 6) * 60 + 30));
      final ignored = i == 4 || i == 17;
      final snooze = ignored ? 0 : random.nextInt(25);
      final wokeAt = ignored ? null : alarmAt.add(Duration(minutes: snooze));

      final key = sleepDayKey(day);
      sessions[key] = SleepSession(
        nightKey: key,
        bedtimeTarget: target,
        lightsOutAt: lightsOut,
        alarmScheduledAt: alarmAt,
        firstRingAt: alarmAt,
        wokeAt: wokeAt,
        alarmIgnored: ignored,
        quality: ignored ? null : 2 + random.nextInt(4),
        awakenings: ignored ? null : random.nextInt(3),
        latencyMinutes: ignored ? null : 5 + random.nextInt(25),
      );
    }

    _write(state.copyWith(sessions: sessions));
  }

  /// Borra todo el historial de sueño (no toca el horario configurado).
  Future<void> clearHistory() async {
    await _ensureLoaded();
    _write(state.copyWith(
      sessions: const {},
      rewardedNights: const [],
      clearOpenNight: true,
    ));
  }
}

final sleepProvider =
    NotifierProvider<SleepNotifier, SleepData>(SleepNotifier.new);

/// Métricas derivadas. Se recalculan una vez por cambio de estado en vez de en
/// cada `build` de cada gráfico, que es donde se notaría.
final sleepAnalyticsProvider = Provider<SleepAnalytics>((ref) {
  final data = ref.watch(sleepProvider);
  return SleepAnalytics(
    nights: data.sessions.values.toList(),
    goalMinutes: data.schedule.goalMinutes,
  );
});
