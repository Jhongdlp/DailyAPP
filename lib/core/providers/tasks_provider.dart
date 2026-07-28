import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../services/task_reminder_service.dart';
import '../services/cache_service.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

class TasksNotifier extends Notifier<List<Task>> {
  Future<void>? _loadFuture;
  DateTime? _lastSyncedAt;
  Timer? _saveDebounce;
  String? _lastReminderFingerprint;

  static const _cacheTtl = Duration(seconds: 90);
  static const _saveDebounceDuration = Duration(milliseconds: 400);

  @override
  List<Task> build() {
    ref.onDispose(() {
      _saveDebounce?.cancel();
    });
    _loadFuture = _loadTasks();
    return [];
  }

  Future<void> _ensureLoaded() async {
    if (_loadFuture != null) {
      await _loadFuture;
    }
  }

  /// Fuerza una recarga completa desde Supabase, ignorando el TTL de caché.
  Future<void> refresh({bool force = true}) => _loadTasks(force: force);

  String _reminderFingerprint(List<Task> tasks) {
    final parts = tasks
        .where((t) => t.hasReminder && !t.completed)
        .map((t) => [t.id, t.title, t.remindAt?.toIso8601String() ?? ''].join(''))
        .toList()
      ..sort();
    return parts.join('');
  }

  void _scheduleCacheSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, () {
      unawaited(CacheService.save('tasks', {
        'syncedAt': _lastSyncedAt?.toIso8601String(),
        'tasks': state.map((t) => t.toCacheJson()).toList(),
      }));
    });
  }

  Future<void> _loadTasks({bool force = false}) async {
    try {
      final cached = await CacheService.read('tasks');
      List? cachedTasksJson;
      if (cached is Map) {
        final syncedAtStr = cached['syncedAt'] as String?;
        _lastSyncedAt = syncedAtStr != null ? DateTime.tryParse(syncedAtStr) : null;
        cachedTasksJson = cached['tasks'] as List?;
      }
      if (cachedTasksJson != null) {
        state = cachedTasksJson.map((e) => Task.fromCacheJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    try {
      if (!force &&
          _lastSyncedAt != null &&
          DateTime.now().difference(_lastSyncedAt!) < _cacheTtl) {
        return;
      }

      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured) return;

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final response = await client
          .from('tasks')
          .select()
          .order('start_at', ascending: true);

      final freshTasks = (response as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      state = freshTasks;
      _lastSyncedAt = DateTime.now();
      unawaited(CacheService.save('tasks', {
        'syncedAt': _lastSyncedAt!.toIso8601String(),
        'tasks': freshTasks.map((t) => t.toCacheJson()).toList(),
      }));

      final fingerprint = _reminderFingerprint(freshTasks);
      if (fingerprint != _lastReminderFingerprint) {
        _lastReminderFingerprint = fingerprint;
        unawaited(TaskReminderService.rescheduleAll(state));
      }
    } catch (e) {
      // Nos quedamos con lo que ya haya en caché/local.
    }
  }

  List<Task> tasksForDay(DateTime day) {
    final dayOnly = DateTime(day.year, day.month, day.day);
    return state.where((t) => t.dueDate == dayOnly).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Future<void> addTask({
    required String title,
    String? notes,
    required DateTime dueDate,
    required DateTime startAt,
    DateTime? endAt,
    DateTime? remindAt,
    TaskPriority priority = TaskPriority.normal,
  }) async {
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final localTask = Task(
      id: tempId,
      title: title,
      notes: notes,
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      startAt: startAt,
      endAt: endAt,
      remindAt: remindAt,
      priority: priority,
    );

    state = [...state, localTask];
    _scheduleCacheSave();
    unawaited(TaskReminderService.scheduleReminder(localTask));
    _lastReminderFingerprint = _reminderFingerprint(state);

    try {
      final settings = ref.read(settingsProvider);
      if (settings.isSupabaseConfigured) {
        final client = Supabase.instance.client;
        final user = client.auth.currentUser;
        if (user != null) {
          final response = await client.from('tasks').insert(localTask.toInsertJson(user.id)).select().single();
          final serverTask = Task.fromJson(response);

          state = [
            for (final t in state)
              if (t.id == tempId) serverTask else t
          ];
          _scheduleCacheSave();

          unawaited(TaskReminderService.cancelReminder(tempId));
          unawaited(TaskReminderService.scheduleReminder(serverTask));
          _lastReminderFingerprint = _reminderFingerprint(state);
        }
      }
    } catch (e) {
      // Si falla, se queda como tarea local.
    }
  }

  Future<void> updateTask(Task updated) async {
    final index = state.indexWhere((t) => t.id == updated.id);
    if (index == -1) return;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) updated else state[i]
    ];
    _scheduleCacheSave();
    unawaited(TaskReminderService.scheduleReminder(updated));
    _lastReminderFingerprint = _reminderFingerprint(state);

    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(updated.id)) return;
      await Supabase.instance.client.from('tasks').update(updated.toUpdateJson()).eq('id', updated.id);
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }

  Future<void> toggleComplete(String taskId) async {
    await _ensureLoaded();
    final index = state.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = state[index];
    final nowCompleted = !task.completed;
    final updated = task.copyWith(
      completed: nowCompleted,
      completedAt: nowCompleted ? DateTime.now() : null,
      clearCompletedAt: !nowCompleted,
    );

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) updated else state[i]
    ];
    _scheduleCacheSave();
    if (nowCompleted) {
      unawaited(TaskReminderService.cancelReminder(taskId));
    } else {
      unawaited(TaskReminderService.scheduleReminder(updated));
    }
    _lastReminderFingerprint = _reminderFingerprint(state);

    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(taskId)) return;
      await Supabase.instance.client.from('tasks').update({
        'completed': updated.completed,
        'completed_at': updated.completedAt?.toUtc().toIso8601String(),
      }).eq('id', taskId);
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }

  Future<void> deleteTask(String taskId) async {
    state = state.where((t) => t.id != taskId).toList();
    _scheduleCacheSave();
    unawaited(TaskReminderService.cancelReminder(taskId));
    _lastReminderFingerprint = _reminderFingerprint(state);
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(taskId)) return;
      await Supabase.instance.client.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      // Ignoramos error de red/actualización en UI
    }
  }
}

final tasksProvider = NotifierProvider<TasksNotifier, List<Task>>(() {
  return TasksNotifier();
});
