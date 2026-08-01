import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/habit_model.dart';

/// Qué hábito representa "hacer ejercicio". La pestaña Ejercicio no muestra
/// contenido sin este vínculo, y es lo que decide si marcar el hábito en
/// Hábitos dispara el flujo de captura de progreso.
class ExerciseHabitLinkNotifier extends Notifier<String?> {
  static const _keyPrefix = 'exercise_linked_habit_id';

  static String get _userId => Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  static String get _key => '${_keyPrefix}_$_userId';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getString(_key);
    } catch (_) {}
  }

  Future<void> setLinkedHabit(String? habitId) async {
    state = habitId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (habitId == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, habitId);
      }
    } catch (_) {}
  }
}

final exerciseHabitLinkProvider = NotifierProvider<ExerciseHabitLinkNotifier, String?>(() {
  return ExerciseHabitLinkNotifier();
});

final _autoDetectPattern = RegExp(r'ejercicio|correr|running|gym|deporte', caseSensitive: false);

/// Hábitos no archivados cuyo nombre sugiere que son "el" hábito de ejercicio.
/// Solo sirve para *sugerir* un vínculo, nunca para enlazarlo solo: una mala
/// suposición aquí ata fotos del físico al hábito equivocado.
List<Habit> autoDetectExerciseHabits(List<Habit> habits) {
  return habits.where((h) => !h.archived && _autoDetectPattern.hasMatch(h.name)).toList();
}
