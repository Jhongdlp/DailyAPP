import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../services/cache_service.dart';

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

  Future<void> addAlarm(AlarmModel alarm) async {
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
    );

    final list = [..._current, newAlarm];
    await _persist(list);
    state = AsyncData(list);
    unawaited(AlarmService.scheduleAlarm(newAlarm));
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    final list = [..._current];
    final idx = list.indexWhere((a) => a.id == alarm.id);
    if (idx != -1) list[idx] = alarm;
    await _persist(list);
    state = AsyncData(list);
    unawaited(AlarmService.scheduleAlarm(alarm));
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
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

final alarmsProvider =
    AsyncNotifierProvider<AlarmsNotifier, List<AlarmModel>>(AlarmsNotifier.new);
