import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/habit_model.dart';
import '../services/habit_reminder_service.dart';
import '../services/cache_service.dart';
import '../services/outbox_service.dart';
import '../services/synced_write.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class HabitsNotifier extends Notifier<List<Habit>> {
  Future<void>? _loadFuture;
  DateTime? _lastSyncedAt;
  Timer? _saveDebounce;
  String? _lastReminderFingerprint;

  static const _cacheTtl = Duration(seconds: 90);
  static const _saveDebounceDuration = Duration(milliseconds: 400);

  @override
  List<Habit> build() {
    ref.onDispose(() {
      _saveDebounce?.cancel();
    });
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

  /// Fuerza una recarga completa desde Supabase, ignorando el TTL de caché.
  /// Pensado para un futuro pull-to-refresh explícito del usuario.
  Future<void> refresh({bool force = true}) => _loadHabits(force: force);

  /// Huella de los campos que afectan a las notificaciones programadas de cada
  /// hábito. Solo se incluyen hábitos que efectivamente tendrían un recordatorio
  /// activo (mismo criterio que HabitReminderService.scheduleReminder), para que
  /// quitar/archivar un recordatorio también cambie la huella y dispare la
  /// limpieza de notificaciones huérfanas.
  String _reminderFingerprint(List<Habit> habits) {
    final parts = habits
        .where((h) => h.hasReminder && !h.archived && h.daysOfWeek.isNotEmpty)
        .map((h) => [
              h.id,
              h.icon,
              h.name,
              h.goalValue?.toString() ?? '',
              h.goalUnit ?? '',
              h.reminderHour?.toString() ?? '',
              h.reminderMinute?.toString() ?? '',
              h.reminderTimes.join(','),
              h.daysOfWeek.join(','),
            ].join(''))
        .toList()
      ..sort();
    return parts.join('');
  }

  /// Agrupa escrituras de caché de mutaciones rápidas (ej. taps repetidos en un
  /// stepper) en una sola escritura, en vez de re-encriptar y persistir la lista
  /// completa en cada toque.
  void _scheduleCacheSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, () {
      unawaited(CacheService.save('habits', {
        'syncedAt': _lastSyncedAt?.toIso8601String(),
        'habits': state.map((h) => h.toCacheJson()).toList(),
      }));
    });
  }

  Future<void> _loadHabits({bool force = false}) async {
    try {
      // Intentar cargar desde caché local primero para velocidad instantánea
      final cached = await CacheService.read('habits');
      List? cachedHabitsJson;
      if (cached is Map) {
        final syncedAtStr = cached['syncedAt'] as String?;
        _lastSyncedAt = syncedAtStr != null ? DateTime.tryParse(syncedAtStr) : null;
        cachedHabitsJson = cached['habits'] as List?;
      } else if (cached is List) {
        // Formato antiguo (lista plana, sin timestamp): se trata como caché sin
        // fecha conocida, así siempre se refresca contra Supabase debajo.
        cachedHabitsJson = cached;
        _lastSyncedAt = null;
      }
      if (cachedHabitsJson != null) {
        state = cachedHabitsJson.map((e) => Habit.fromCacheJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    try {
      if (!force &&
          _lastSyncedAt != null &&
          DateTime.now().difference(_lastSyncedAt!) < _cacheTtl) {
        // Caché todavía fresco: evitamos volver a pegarle a Supabase en cada
        // rebuild/cambio de tab dentro de la ventana de sincronía reciente.
        return;
      }

      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured) {
        if (state.isEmpty) state = _getMockHabits();
        return;
      }

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (state.isEmpty) state = _getMockHabits();
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

      // Lo que el servidor acaba de devolver no incluye las escrituras que
      // siguen en el outbox. Sin este paso, recargar con una marca sin
      // sincronizar haría desaparecer el check delante del usuario.
      final habitRows = OutboxService.reconcileRows(
        [for (final row in habitsResponse as List) Map<String, dynamic>.from(row as Map)],
        await OutboxService.pendingFor('habits'),
      )
          // El archivado pendiente llega como un `archived: true` encima de una
          // fila que el servidor todavía da por activa; el filtro de la consulta
          // no puede saberlo, así que se aplica aquí.
          .where((row) => row['archived'] != true)
          .toList();

      final logRows = OutboxService.reconcileRows(
        [for (final row in logsResponse) Map<String, dynamic>.from(row as Map)],
        await OutboxService.pendingFor('habit_logs'),
      );

      final logsByHabit = <String, Set<DateTime>>{};
      final progressByHabit = <String, Map<DateTime, double>>{};

      for (final row in logRows) {
        final habitId = row['habit_id'] as String;
        final date = DateTime.parse(row['completed_on'] as String);
        final day = _dateOnly(date);

        logsByHabit.putIfAbsent(habitId, () => <DateTime>{}).add(day);
        progressByHabit.putIfAbsent(habitId, () => <DateTime, double>{});

        if (hasProgressValue && row['progress_value'] != null) {
          final val = (row['progress_value'] as num).toDouble();
          progressByHabit[habitId]![day] = val;
        }
      }

      final freshHabits = habitRows.map((json) {
        final habitId = json['id'] as String;
        final goalValue = (json['goal_value'] as num?)?.toDouble();
        final hCompletedDates = <DateTime>{};
        final hProgress = progressByHabit[habitId] ?? <DateTime, double>{};

        // Días con log registrado pero sin progress_value explícito: se
        // completan con el valor por defecto (usando el set de días ya
        // agrupado por hábito arriba, en vez de re-escanear todos los logs).
        for (final day in logsByHabit[habitId] ?? const <DateTime>{}) {
          if (!hProgress.containsKey(day)) {
            hProgress[day] = goalValue ?? 1.0;
          }
        }

        for (final entry in hProgress.entries) {
          final target = goalValue ?? 1.0;
          if (entry.value >= target) {
            hCompletedDates.add(entry.key);
          }
        }

        return Habit.fromJson(
          json,
          completedDates: hCompletedDates,
          dailyProgress: hProgress,
        );
      }).toList();

      state = freshHabits;
      _lastSyncedAt = DateTime.now();
      unawaited(CacheService.save('habits', {
        'syncedAt': _lastSyncedAt!.toIso8601String(),
        'habits': freshHabits.map((h) => h.toCacheJson()).toList(),
      }));

      final fingerprint = _reminderFingerprint(freshHabits);
      if (fingerprint != _lastReminderFingerprint) {
        _lastReminderFingerprint = fingerprint;
        unawaited(HabitReminderService.rescheduleAll(state));
      }
    } catch (e) {
      if (state.isEmpty) state = _getMockHabits();
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
    _scheduleCacheSave();

    await _persistLog(habitId: habitId, day: day, progress: newProgress, remove: wasCompleted);
  }

  /// Guarda el log de un día, o lo borra si el progreso volvió a cero.
  ///
  /// Sin conexión la escritura acaba en el outbox en vez de perderse: marcar un
  /// hábito en el metro y que el check se esfume al llegar a casa era
  /// exactamente el fallo que esto arregla.
  ///
  /// Si el servidor la **rechaza** no hay reintento detrás, así que el estado
  /// optimista que ya se pintó es mentira. En vez de dejarlo hasta la siguiente
  /// recarga (donde el check desaparecía sin explicación), se recarga en el
  /// acto: es feo ver el check saltar hacia atrás, pero mucho menos que creer
  /// durante horas que el día quedó marcado.
  Future<void> _persistLog({
    required String habitId,
    required DateTime day,
    required double progress,
    required bool remove,
  }) async {
    final settings = ref.read(settingsProvider);
    // Los hábitos que solo existen en local (id no-UUID de versiones antiguas)
    // no tienen fila en el servidor a la que colgar el log.
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
    if (!canWriteToSupabase) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;
    final match = {'habit_id': habitId, 'completed_on': _fmt(day)};

    final WriteOutcome outcome;
    if (remove) {
      outcome = await syncedWrite(
        write: () => client
            .from('habit_logs')
            .delete()
            .eq('habit_id', habitId)
            .eq('completed_on', _fmt(day)),
        fallback: () => OutboxOp.create(
          table: 'habit_logs',
          kind: OutboxOpKind.delete,
          match: match,
        ),
      );
    } else {
      final payload = {...match, 'user_id': user.id, 'progress_value': progress};
      outcome = await syncedWrite(
        write: () => client
            .from('habit_logs')
            .upsert(payload, onConflict: 'habit_id,completed_on'),
        fallback: () => OutboxOp.create(
          table: 'habit_logs',
          kind: OutboxOpKind.upsert,
          payload: payload,
          match: match,
          onConflict: 'habit_id,completed_on',
        ),
      );
    }

    if (outcome.isRejected) {
      // `force` es imprescindible: el TTL de caché se acaba de refrescar y sin
      // él la recarga no llegaría a tocar el servidor.
      await refresh(force: true);
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
    _scheduleCacheSave();

    await _persistLog(
      habitId: habitId,
      day: day,
      progress: newProgress,
      remove: newProgress == 0.0,
    );
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
    // El id se genera aquí y ya es el definitivo: no hay baile de id temporal
    // a id de servidor, así que el hábito creado sin conexión conserva su
    // identidad y sus logs cuadran cuando el alta llegue a Supabase.
    final localHabit = Habit(
      id: newRowId(),
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

    // Actualizar estado en UI de inmediato (optimista)
    state = [...state, localHabit];
    _scheduleCacheSave();
    unawaited(HabitReminderService.scheduleReminder(localHabit));
    _lastReminderFingerprint = _reminderFingerprint(state);

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !canWriteToSupabase) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;
    final payload = {'id': localHabit.id, ...localHabit.toInsertJson(user.id)};

    await syncedWrite(
      write: () => client.from('habits').insert(payload),
      fallback: () => OutboxOp.create(
        table: 'habits',
        kind: OutboxOpKind.insert,
        payload: payload,
        match: {'id': localHabit.id},
      ),
    );
  }

  Future<void> updateHabit(Habit updated) async {
    final index = state.indexWhere((h) => h.id == updated.id);
    if (index == -1) return;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) updated else state[i]
    ];
    _scheduleCacheSave();
    unawaited(HabitReminderService.scheduleReminder(updated));
    _lastReminderFingerprint = _reminderFingerprint(state);

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(updated.id)) return;
    if (!canWriteToSupabase) return;

    final payload = updated.toUpdateJson();
    await syncedWrite(
      write: () =>
          Supabase.instance.client.from('habits').update(payload).eq('id', updated.id),
      fallback: () => OutboxOp.create(
        table: 'habits',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': updated.id},
      ),
    );
  }

  Future<void> archiveHabit(String habitId) async {
    state = state.where((h) => h.id != habitId).toList();
    _scheduleCacheSave();
    unawaited(HabitReminderService.cancelReminder(habitId));
    _lastReminderFingerprint = _reminderFingerprint(state);
    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
    if (!canWriteToSupabase) return;

    await syncedWrite(
      write: () => Supabase.instance.client
          .from('habits')
          .update({'archived': true}).eq('id', habitId),
      fallback: () => OutboxOp.create(
        table: 'habits',
        kind: OutboxOpKind.update,
        payload: {'archived': true},
        match: {'id': habitId},
      ),
    );
  }

  Future<void> deleteHabit(String habitId) async {
    state = state.where((h) => h.id != habitId).toList();
    _scheduleCacheSave();
    unawaited(HabitReminderService.cancelReminder(habitId));
    _lastReminderFingerprint = _reminderFingerprint(state);
    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !_uuidRegex.hasMatch(habitId)) return;
    if (!canWriteToSupabase) return;

    await syncedWrite(
      write: () => Supabase.instance.client.from('habits').delete().eq('id', habitId),
      fallback: () => OutboxOp.create(
        table: 'habits',
        kind: OutboxOpKind.delete,
        match: {'id': habitId},
      ),
    );
  }
}

final habitsProvider = NotifierProvider<HabitsNotifier, List<Habit>>(() {
  return HabitsNotifier();
});
