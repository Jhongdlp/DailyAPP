import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../services/task_reminder_service.dart';
import '../services/cache_service.dart';
import '../services/outbox_service.dart';
import '../services/synced_write.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

class TasksNotifier extends Notifier<List<Task>> {
  Future<void>? _loadFuture;
  DateTime? _lastSyncedAt;
  Timer? _saveDebounce;
  String? _lastReminderFingerprint;

  /// Último error de sincronización pendiente de mostrar. La UI lo lee tras
  /// una mutación y lo consume con [takeSyncError]; antes estos errores se
  /// tragaban en silencio y la tarea quedaba solo en local sin avisar.
  String? lastSyncError;

  String? takeSyncError() {
    final error = lastSyncError;
    lastSyncError = null;
    return error;
  }

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

      // Se reaplica lo que sigue en el outbox: si no, una tarea marcada como
      // hecha sin conexión volvería a aparecer pendiente en la recarga.
      final rows = OutboxService.reconcileRows(
        [for (final row in response as List) Map<String, dynamic>.from(row as Map)],
        await OutboxService.pendingFor('tasks'),
      );

      final freshTasks = rows.map(Task.fromJson).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));

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
    String? habitId,
    BlockType blockType = BlockType.task,
    String? location,
    bool isMit = false,
    DateTime? plannedAt,
  }) async {
    // Sin esto, guardar mientras la carga inicial sigue en vuelo hace que
    // `_loadTasks` pise el estado optimista y la tarea recién creada
    // desaparezca de la lista aunque sí se haya insertado en Supabase.
    await _ensureLoaded();

    // Id definitivo desde el cliente: la tarea creada sin conexión conserva su
    // identidad, así que sus recordatorios y sus ediciones posteriores siguen
    // apuntando a la misma fila cuando el alta llegue al servidor.
    final localTask = Task(
      id: newRowId(),
      title: title,
      notes: notes,
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      startAt: startAt,
      endAt: endAt,
      remindAt: remindAt,
      priority: priority,
      habitId: habitId,
      blockType: blockType,
      location: location,
      isMit: isMit,
      plannedAt: plannedAt,
    );

    state = [...state, localTask];
    _scheduleCacheSave();
    unawaited(TaskReminderService.scheduleReminder(localTask));
    _lastReminderFingerprint = _reminderFingerprint(state);

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !canWriteToSupabase) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;
    final payload = {'id': localTask.id, ...localTask.toInsertJson(user.id)};

    final confirmed = await syncedWrite(
      write: () => client.from('tasks').insert(payload),
      fallback: () => OutboxOp.create(
        table: 'tasks',
        kind: OutboxOpKind.insert,
        payload: payload,
        match: {'id': localTask.id},
      ),
    );

    if (!confirmed) lastSyncError = _queuedMessage;
  }

  /// Lo que se le dice al usuario cuando la escritura se quedó en el outbox. Ya
  /// no es una advertencia de pérdida: el cambio está a salvo y se subirá solo.
  static const _queuedMessage =
      'Sin conexión: el cambio se guardó y se sincronizará solo.';

  /// Clona en [to] todos los bloques de [from], conservando horas y duración.
  ///
  /// Las rutinas se repiten: rehacer a mano el mismo lunes cada semana es la
  /// clase de trabajo que hace abandonar el sistema. No copia el estado de
  /// completado ni los bloques ligados a un hábito (esos los coloca la propia
  /// bandeja de hábitos, y duplicarlos crearía dos bloques para el mismo día).
  ///
  /// Devuelve cuántos bloques se copiaron.
  Future<int> copyDay({required DateTime from, required DateTime to}) async {
    await _ensureLoaded();

    final source = tasksForDay(from).where((t) => !t.isHabitBlock).toList();
    if (source.isEmpty) return 0;

    final target = DateTime(to.year, to.month, to.day);
    final existing = tasksForDay(target);
    var copied = 0;

    for (final task in source) {
      // No duplicar lo que ya está a la misma hora con el mismo nombre.
      final alreadyThere = existing.any((t) =>
          t.title == task.title &&
          t.startAt.hour == task.startAt.hour &&
          t.startAt.minute == task.startAt.minute);
      if (alreadyThere) continue;

      // Se conserva la hora del reloj, no el instante: copiar el lunes al
      // martes debe dejar el bloque a la misma hora, no 24h después.
      DateTime atTargetDay(DateTime d, {required bool nextDay}) => DateTime(
            target.year,
            target.month,
            target.day + (nextDay ? 1 : 0),
            d.hour,
            d.minute,
          );

      final endCrossesMidnight = task.endAt != null && task.endAt!.isBefore(task.startAt);
      DateTime shift(DateTime d) =>
          atTargetDay(d, nextDay: d == task.endAt && endCrossesMidnight);

      copied++;
      await addTask(
        title: task.title,
        notes: task.notes,
        dueDate: target,
        startAt: shift(task.startAt),
        endAt: task.endAt != null ? shift(task.endAt!) : null,
        remindAt: task.hasReminder ? shift(task.startAt) : null,
        priority: task.priority,
        blockType: task.blockType,
        location: task.location,
        isMit: task.isMit,
        plannedAt: DateTime.now(),
      );
    }

    return copied;
  }

  Future<void> updateTask(Task updated) async {
    await _ensureLoaded();
    final index = state.indexWhere((t) => t.id == updated.id);
    if (index == -1) return;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) updated else state[i]
    ];
    _scheduleCacheSave();
    unawaited(TaskReminderService.scheduleReminder(updated));
    _lastReminderFingerprint = _reminderFingerprint(state);

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(updated.id)) return;
    if (!canWriteToSupabase) return;

    final payload = updated.toUpdateJson();
    final confirmed = await syncedWrite(
      write: () =>
          Supabase.instance.client.from('tasks').update(payload).eq('id', updated.id),
      fallback: () => OutboxOp.create(
        table: 'tasks',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': updated.id},
      ),
    );

    if (!confirmed) lastSyncError = _queuedMessage;
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

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(taskId)) return;
    if (!canWriteToSupabase) return;

    final payload = {
      'completed': updated.completed,
      'completed_at': updated.completedAt?.toUtc().toIso8601String(),
    };
    await syncedWrite(
      write: () =>
          Supabase.instance.client.from('tasks').update(payload).eq('id', taskId),
      fallback: () => OutboxOp.create(
        table: 'tasks',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': taskId},
      ),
    );
  }

  Future<void> deleteTask(String taskId) async {
    await _ensureLoaded();
    state = state.where((t) => t.id != taskId).toList();
    _scheduleCacheSave();
    unawaited(TaskReminderService.cancelReminder(taskId));
    _lastReminderFingerprint = _reminderFingerprint(state);
    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(taskId)) return;
    if (!canWriteToSupabase) return;

    await syncedWrite(
      write: () => Supabase.instance.client.from('tasks').delete().eq('id', taskId),
      fallback: () => OutboxOp.create(
        table: 'tasks',
        kind: OutboxOpKind.delete,
        match: {'id': taskId},
      ),
    );
  }
}

final tasksProvider = NotifierProvider<TasksNotifier, List<Task>>(() {
  return TasksNotifier();
});
