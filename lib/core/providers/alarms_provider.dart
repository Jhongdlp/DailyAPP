import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../services/cache_service.dart';
import 'sleep_provider.dart';

/// Almacenamiento 100% local de las alarmas.
///
/// Las alarmas viven solo en el dispositivo (via [CacheService], que ya
/// scopea las claves por usuario). No dependen de Supabase ni de la red, así
/// que la lista carga al instante al abrir la app y no falla por retrasos de
/// red o refresco del JWT en el arranque en frío.
class AlarmsNotifier extends AsyncNotifier<List<AlarmModel>> {
  static const _cacheKey = 'alarms';

  @override
  Future<List<AlarmModel>> build() => _load();

  Future<List<AlarmModel>> _load() async {
    final raw = await CacheService.read(_cacheKey);
    final alarms = <AlarmModel>[];
    if (raw is List) {
      for (final e in raw) {
        try {
          alarms.add(AlarmModel.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          // Ignora entradas corruptas en vez de tumbar toda la lista.
        }
      }
    }
    alarms.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    try {
      await AlarmService.rescheduleAll(alarms);
    } catch (_) {
      // Reprogramar es un efecto secundario local; si el plugin nativo aún no
      // está listo justo tras el arranque, no debe tumbar la carga de la lista.
    }
    return alarms;
  }

  List<AlarmModel> get _current => state.value ?? [];

  Future<void> _persist(List<AlarmModel> alarms) async {
    await CacheService.save(_cacheKey, alarms.map((a) => a.toJson()).toList());
  }

  String _newId() {
    final rnd = Random().nextInt(0x7fffffff);
    return '${DateTime.now().microsecondsSinceEpoch}-$rnd';
  }

  /// Mantiene el horario de sueño alineado con la alarma que lo representa.
  ///
  /// Vive aquí y no en cada pantalla porque la alarma de sueño se toca desde
  /// varios sitios —el interruptor de la tarjeta, el deslizar para borrar, el
  /// formulario— y olvidarlo en uno solo dejaría los avisos de "hora de dormir"
  /// sonando para una alarma ya apagada.
  void _syncSleepSchedule() {
    final current = _current;
    AlarmModel? sleepAlarm;
    for (final alarm in current) {
      if (alarm.isSleepAlarm) {
        sleepAlarm = alarm;
        break;
      }
    }
    unawaited(ref.read(sleepProvider.notifier).syncFromAlarm(sleepAlarm));
  }

  /// Solo puede haber un horario de sueño: degrada a alarma normal cualquier
  /// otra que lo fuera. Dos horarios peleando por la misma noche darían dos
  /// avisos de "hora de dormir" y un registro imposible de interpretar.
  List<AlarmModel> _demoteOtherSleepAlarms(
    List<AlarmModel> list,
    String keepId,
  ) {
    return [
      for (final alarm in list)
        if (alarm.id != keepId && alarm.isSleepAlarm)
          alarm.copyWith(clearBedtime: true)
        else
          alarm,
    ];
  }

  Future<AlarmModel> addAlarm(AlarmModel alarm) async {
    final newAlarm = AlarmModel(
      id: _newId(),
      userId: alarm.userId,
      enabled: alarm.enabled,
      hour: alarm.hour,
      minute: alarm.minute,
      targetObject: alarm.targetObject,
      label: alarm.label,
      daysOfWeek: alarm.daysOfWeek,
      createdAt: DateTime.now(),
      bedtimeHour: alarm.bedtimeHour,
      bedtimeMinute: alarm.bedtimeMinute,
    );

    var list = [..._current, newAlarm];
    if (newAlarm.isSleepAlarm) {
      list = _demoteOtherSleepAlarms(list, newAlarm.id);
    }
    await _persist(list);
    state = AsyncData(list);
    unawaited(AlarmService.scheduleAlarm(newAlarm));
    _syncSleepSchedule();
    return newAlarm;
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    var list = [..._current];
    final idx = list.indexWhere((a) => a.id == alarm.id);
    if (idx != -1) list[idx] = alarm;
    if (alarm.isSleepAlarm) {
      list = _demoteOtherSleepAlarms(list, alarm.id);
    }
    await _persist(list);
    state = AsyncData(list);
    unawaited(AlarmService.scheduleAlarm(alarm));
    _syncSleepSchedule();
  }

  /// Actualiza el switch al instante (optimistic) y persiste en segundo plano;
  /// revierte si falla el guardado local.
  Future<void> toggleAlarm(String id, bool enabled) async {
    final previous = _current;
    final idx = previous.indexWhere((a) => a.id == id);
    if (idx == -1) return;

    final updated = previous[idx].copyWith(enabled: enabled);
    final optimisticList = [...previous]..[idx] = updated;
    state = AsyncData(optimisticList);

    try {
      await _persist(optimisticList);
      unawaited(AlarmService.scheduleAlarm(updated));
      if (updated.isSleepAlarm) _syncSleepSchedule();
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteAlarm(String id) async {
    final previous = _current;
    final next = previous.where((a) => a.id != id).toList();
    state = AsyncData(next);

    try {
      await _persist(next);
      unawaited(AlarmService.cancelAlarm(id));
      _syncSleepSchedule();
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

final alarmsProvider =
    AsyncNotifierProvider<AlarmsNotifier, List<AlarmModel>>(AlarmsNotifier.new);

/// El horario de sueño vigente, si lo hay. Es la alarma que la pestaña de
/// sueño trata como "mi horario", y la que sabe a qué hora toca acostarse.
final sleepAlarmProvider = Provider<AlarmModel?>((ref) {
  final alarms = ref.watch(alarmsProvider).value ?? const <AlarmModel>[];
  for (final alarm in alarms) {
    if (alarm.isSleepAlarm) return alarm;
  }
  return null;
});
