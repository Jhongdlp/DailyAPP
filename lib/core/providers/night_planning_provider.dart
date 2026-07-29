import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/night_planning_service.dart';

/// Ajustes del ritual nocturno.
///
/// Van en SharedPreferences y no en Supabase a propósito: son de este
/// dispositivo (es el que da el aviso), y deben poder leerse antes de que haya
/// sesión iniciada para reprogramar la notificación al arrancar.
class NightPlanningPrefs {
  final bool enabled;
  final int hour;
  final int minute;

  const NightPlanningPrefs({
    this.enabled = true,
    // Suficientemente tarde para que el día ya esté cerrado, suficientemente
    // temprano para no competir con el sueño.
    this.hour = 21,
    this.minute = 30,
  });

  NightPlanningPrefs copyWith({bool? enabled, int? hour, int? minute}) => NightPlanningPrefs(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {'enabled': enabled, 'hour': hour, 'minute': minute};

  factory NightPlanningPrefs.fromJson(Map<String, dynamic> json) => NightPlanningPrefs(
        enabled: json['enabled'] as bool? ?? true,
        hour: (json['hour'] as num?)?.toInt() ?? 21,
        minute: (json['minute'] as num?)?.toInt() ?? 30,
      );
}

class NightPlanningNotifier extends Notifier<NightPlanningPrefs> {
  static const _prefsKey = 'night_planning_prefs';

  @override
  NightPlanningPrefs build() {
    _load();
    return const NightPlanningPrefs();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        state = NightPlanningPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Preferencias corruptas: se conservan las de fábrica.
      }
    }
    // Se reprograma en cada arranque: una notificación diaria puede perderse
    // si el sistema mata la app o el usuario reinicia el teléfono.
    await _applyToScheduler();
  }

  Future<void> _applyToScheduler() async {
    if (state.enabled) {
      await NightPlanningService.schedule(hour: state.hour, minute: state.minute);
    } else {
      await NightPlanningService.cancel();
    }
  }

  Future<void> _update(NightPlanningPrefs next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
    await _applyToScheduler();
  }

  Future<void> setEnabled(bool value) => _update(state.copyWith(enabled: value));

  Future<void> setTime(int hour, int minute) =>
      _update(state.copyWith(hour: hour, minute: minute, enabled: true));
}

final nightPlanningProvider =
    NotifierProvider<NightPlanningNotifier, NightPlanningPrefs>(() => NightPlanningNotifier());
