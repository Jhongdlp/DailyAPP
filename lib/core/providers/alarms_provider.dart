import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';

class AlarmsNotifier extends AsyncNotifier<List<AlarmModel>> {
  @override
  Future<List<AlarmModel>> build() => _fetch();

  Future<List<AlarmModel>> _fetch() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('alarms')
        .select()
        .order('created_at');

    final alarms = (data as List).map((e) => AlarmModel.fromJson(e)).toList();
    try {
      await AlarmService.rescheduleAll(alarms);
    } catch (_) {
      // Reprogramar alarmas es un efecto secundario local; si el plugin nativo
      // aún no está listo justo tras el arranque en frío, no debe tumbar la
      // carga de la lista (que ya llegó bien desde Supabase).
    }
    return alarms;
  }

  List<AlarmModel> get _current => state.value ?? [];

  Future<void> addAlarm(AlarmModel alarm) async {
    final user = Supabase.instance.client.auth.currentUser!;
    final data = await Supabase.instance.client
        .from('alarms')
        .insert({...alarm.toJson(), 'user_id': user.id})
        .select()
        .single();

    final newAlarm = AlarmModel.fromJson(data);
    state = AsyncData([..._current, newAlarm]);
    unawaited(AlarmService.scheduleAlarm(newAlarm));
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    await Supabase.instance.client
        .from('alarms')
        .update(alarm.toJson())
        .eq('id', alarm.id);

    final list = [..._current];
    final idx = list.indexWhere((a) => a.id == alarm.id);
    if (idx != -1) list[idx] = alarm;
    state = AsyncData(list);
    unawaited(AlarmService.scheduleAlarm(alarm));
  }

  /// Actualiza el switch al instante (optimistic) y sincroniza en segundo
  /// plano; revierte y relanza el error si falla el guardado remoto.
  Future<void> toggleAlarm(String id, bool enabled) async {
    final previous = _current;
    final idx = previous.indexWhere((a) => a.id == id);
    if (idx == -1) return;

    final updated = previous[idx].copyWith(enabled: enabled);
    final optimisticList = [...previous]..[idx] = updated;
    state = AsyncData(optimisticList);

    try {
      await Supabase.instance.client
          .from('alarms')
          .update(updated.toJson())
          .eq('id', id);
      unawaited(AlarmService.scheduleAlarm(updated));
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteAlarm(String id) async {
    final previous = _current;
    state = AsyncData(previous.where((a) => a.id != id).toList());

    try {
      await Supabase.instance.client.from('alarms').delete().eq('id', id);
      unawaited(AlarmService.cancelAlarm(id));
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

final alarmsProvider =
    AsyncNotifierProvider<AlarmsNotifier, List<AlarmModel>>(AlarmsNotifier.new);
