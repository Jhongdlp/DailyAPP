import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/habit_model.dart';
import '../services/habit_reminder_service.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class HabitsNotifier extends Notifier<List<Habit>> {
  Future<void>? _loadFuture;

  @override
  List<Habit> build() {
    _loadFuture = _loadHabits();
    return [];
  }

  Future<void> _ensureLoaded() async {
    if (_loadFuture != null) {
      await _loadFuture;
    }
  }

  List<Habit> _getMockHabits() {
    return [];
  }

  Future<void> _loadHabits() async {
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured) {
        state = _getMockHabits();
        return;
      }

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        state = _getMockHabits();
        return;
      }

      final habitsResponse = await client
          .from('habits')
          .select()
          .eq('archived', false)
          .order('created_at', ascending: true);

      List logsResponse;
      bool hasProgressValue = true;
      try {
        logsResponse = await client
            .from('habit_logs')
            .select('habit_id, completed_on, progress_value')
            .eq('user_id', user.id) as List;
      } catch (e) {
        hasProgressValue = false;
        logsResponse = await client
            .from('habit_logs')
            .select('habit_id, completed_on')
            .eq('user_id', user.id) as List;
      }

      final logsByHabit = <String, Set<DateTime>>{};
      final progressByHabit = <String, Map<DateTime, double>>{};

      for (final row in logsResponse) {
        final habitId = row['habit_id'] as String;
        final date = DateTime.parse(row['completed_on'] as String);
        final day = _dateOnly(date);

        logsByHabit.putIfAbsent(habitId, () => <DateTime>{});
        progressByHabit.putIfAbsent(habitId, () => <DateTime, double>{});

        if (hasProgressValue && row['progress_value'] != null) {
          final val = (row['progress_value'] as num).toDouble();
          progressByHabit[habitId]![day] = val;
        }
      }

      state = (habitsResponse as List).map((json) {
        final habitId = json['id'] as String;
        final goalValue = (json['goal_value'] as num?)?.toDouble();
        final hCompletedDates = logsByHabit[habitId] ?? <DateTime>{};
        final hProgress = progressByHabit[habitId] ?? <DateTime, double>{};

        for (final row in logsResponse) {
          if (row['habit_id'] == habitId) {
            final date = DateTime.parse(row['completed_on'] as String);
            final day = _dateOnly(date);
            if (!hProgress.containsKey(day)) {
              hProgress[day] = goalValue ?? 1.0;
            }
          }
        }

        for (final entry in hProgress.entries) {
          final target = goalValue ?? 1.0;
          if (entry.value >= target) {
            hCompletedDates.add(entry.key);
          }
        }

        return Habit.fromJson(
          json as Map<String, dynamic>,
          completedDates: hCompletedDates,
          dailyProgress: hProgress,
        );
      }).toList();
      unawaited(HabitReminderService.rescheduleAll(state));
    } catch (e) {
      state = _getMockHabits();
    }
  }

  Future<void> toggleHabit(String habitId, DateTime date) async {
    await _ensureLoaded();
    final index = state.indexWhere((h) => h.id == habitId);
    if (index == -1) return;

    final habit = state[index];
    final day = _dateOnly(date);
    final completed = Set<DateTime>.from(habit.completedDates);
    final wasCompleted = completed.contains(day);
    
    double newProgress = 0.0;
    if (wasCompleted) {
      completed.remove(day);
      newProgress = 0.0;
    } else {
      completed.add(day);
      newProgress = habit.goalValue ?? 1.0;
    }

    final newProgressMap = Map<DateTime, double>.from(habit.dailyProgress);
    newProgressMap[day] = newProgress;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) habit.copyWith(
          completedDates: completed,
          dailyProgress: newProgressMap,
        ) else state[i]
    ];

    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      if (wasCompleted) {
        await client
            .from('habit_logs')
            .delete()
            .eq('habit_id', habitId)
            .eq('completed_on', _fmt(day));
      } else {
        await client.from('habit_logs').upsert({
          'habit_id': habitId,
          'user_id': user.id,
          'completed_on': _fmt(day),
          'progress_value': newProgress,
        }, onConflict: 'habit_id,completed_on');
      }
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }

  Future<void> updateHabitProgress(String habitId, DateTime date, double increment) async {
    await _ensureLoaded();
    final index = state.indexWhere((h) => h.id == habitId);
    if (index == -1) return;

    final habit = state[index];
    final day = _dateOnly(date);
    final currentProgress = habit.dailyProgress[day] ?? 0.0;
    
    var newProgress = currentProgress + increment;
    if (newProgress < 0.0) newProgress = 0.0;
    
    final goal = habit.goalValue ?? 1.0;
    final completed = Set<DateTime>.from(habit.completedDates);
    final isCompletedNow = newProgress >= goal;
    
    if (isCompletedNow) {
      completed.add(day);
    } else {
      completed.remove(day);
    }

    final newProgressMap = Map<DateTime, double>.from(habit.dailyProgress);
    newProgressMap[day] = newProgress;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) habit.copyWith(
          completedDates: completed,
          dailyProgress: newProgressMap,
        ) else state[i]
    ];

    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      if (newProgress == 0.0) {
        await client
            .from('habit_logs')
            .delete()
            .eq('habit_id', habitId)
            .eq('completed_on', _fmt(day));
      } else {
        await client.from('habit_logs').upsert({
          'habit_id': habitId,
          'user_id': user.id,
          'completed_on': _fmt(day),
          'progress_value': newProgress,
        }, onConflict: 'habit_id,completed_on');
      }
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }

  Future<void> addHabit({
    required String name,
    String icon = '✅',
    String color = '#758BFD',
    HabitCategory category = HabitCategory.general,
    List<int> daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    double? goalValue,
    String? goalUnit,
    int? reminderHour,
    int? reminderMinute,
    List<String>? reminderTimes,
  }) async {
    Habit created;
    try {
      final settings = ref.read(settingsProvider);
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (settings.isSupabaseConfigured && user != null) {
        final draft = Habit(
          id: '',
          name: name,
          icon: icon,
          color: color,
          category: category,
          daysOfWeek: daysOfWeek,
          goalValue: goalValue,
          goalUnit: goalUnit,
          reminderHour: reminderHour,
          reminderMinute: reminderMinute,
          reminderTimes: reminderTimes,
        );
        final response = await client.from('habits').insert(draft.toInsertJson(user.id)).select().single();
        created = Habit.fromJson(response);
        state = [...state, created];
        unawaited(HabitReminderService.scheduleReminder(created));
        return;
      }
    } catch (e) {
      // cae a modo local abajo
    }
    created = Habit(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      icon: icon,
      color: color,
      category: category,
      daysOfWeek: daysOfWeek,
      goalValue: goalValue,
      goalUnit: goalUnit,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
      reminderTimes: reminderTimes,
    );
    state = [...state, created];
    unawaited(HabitReminderService.scheduleReminder(created));
  }

  Future<void> updateHabit(Habit updated) async {
    final index = state.indexWhere((h) => h.id == updated.id);
    if (index == -1) return;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) updated else state[i]
    ];
    unawaited(HabitReminderService.scheduleReminder(updated));

    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(updated.id)) return;
      await Supabase.instance.client.from('habits').update(updated.toUpdateJson()).eq('id', updated.id);
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }

  Future<void> archiveHabit(String habitId) async {
    state = state.where((h) => h.id != habitId).toList();
    unawaited(HabitReminderService.cancelReminder(habitId));
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
      await Supabase.instance.client.from('habits').update({'archived': true}).eq('id', habitId);
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }

  Future<void> deleteHabit(String habitId) async {
    state = state.where((h) => h.id != habitId).toList();
    unawaited(HabitReminderService.cancelReminder(habitId));
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
      await Supabase.instance.client.from('habits').delete().eq('id', habitId);
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }
}

final habitsProvider = NotifierProvider<HabitsNotifier, List<Habit>>(() {
  return HabitsNotifier();
});
