import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/day_plan_model.dart';
import '../services/cache_service.dart';
import 'settings_provider.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Historial de noches de planeación. Sigue el mismo patrón caché + TTL que
/// `TasksNotifier`, pero con `_ensureLoaded()` en los mutadores desde el
/// principio: sin eso, guardar mientras la carga inicial sigue en vuelo hace
/// que la recarga pise el estado optimista.
class DayPlansNotifier extends Notifier<List<DayPlan>> {
  Future<void>? _loadFuture;
  DateTime? _lastSyncedAt;
  Timer? _saveDebounce;

  static const _cacheTtl = Duration(seconds: 90);
  static const _saveDebounceDuration = Duration(milliseconds: 400);

  String? lastSyncError;

  String? takeSyncError() {
    final error = lastSyncError;
    lastSyncError = null;
    return error;
  }

  @override
  List<DayPlan> build() {
    ref.onDispose(() => _saveDebounce?.cancel());
    _loadFuture = _load();
    return [];
  }

  Future<void> _ensureLoaded() async {
    if (_loadFuture != null) await _loadFuture;
  }

  Future<void> refresh({bool force = true}) => _load(force: force);

  void _scheduleCacheSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, () {
      unawaited(CacheService.save('day_plans', {
        'syncedAt': _lastSyncedAt?.toIso8601String(),
        'plans': state.map((p) => p.toCacheJson()).toList(),
      }));
    });
  }

  Future<void> _load({bool force = false}) async {
    try {
      final cached = await CacheService.read('day_plans');
      if (cached is Map) {
        final syncedAtStr = cached['syncedAt'] as String?;
        _lastSyncedAt = syncedAtStr != null ? DateTime.tryParse(syncedAtStr) : null;
        final plans = cached['plans'] as List?;
        if (plans != null) {
          state = plans.map((e) => DayPlan.fromCacheJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}

    try {
      if (!force && _lastSyncedAt != null && DateTime.now().difference(_lastSyncedAt!) < _cacheTtl) {
        return;
      }

      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured) return;

      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;

      // Solo el último año: el historial completo no aporta y la racha nunca
      // necesita mirar más atrás.
      final since = _dateOnly(DateTime.now().subtract(const Duration(days: 365)));
      final response = await client
          .from('day_plans')
          .select()
          .gte('plan_date', _fmtDate(since))
          .order('plan_date', ascending: false);

      final fresh = (response as List)
          .map((json) => DayPlan.fromJson(json as Map<String, dynamic>))
          .toList();

      state = fresh;
      _lastSyncedAt = DateTime.now();
      unawaited(CacheService.save('day_plans', {
        'syncedAt': _lastSyncedAt!.toIso8601String(),
        'plans': fresh.map((p) => p.toCacheJson()).toList(),
      }));
    } catch (e) {
      // Nos quedamos con la caché.
    }
  }

  DayPlan? planFor(DateTime day) {
    final dayOnly = _dateOnly(day);
    for (final p in state) {
      if (p.planDate == dayOnly) return p;
    }
    return null;
  }

  bool hasPlanFor(DateTime day) => planFor(day)?.ritualCompleted ?? false;

  /// Noches consecutivas planeando. Cuenta hacia atrás desde mañana; si mañana
  /// aún no está planeado no rompe la racha (todavía estás a tiempo), igual que
  /// hace `Habit.currentStreak` con el día en curso.
  int get planningStreak {
    final tomorrow = _dateOnly(DateTime.now().add(const Duration(days: 1)));
    var cursor = hasPlanFor(tomorrow) ? tomorrow : _dateOnly(DateTime.now());
    var streak = 0;
    while (hasPlanFor(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
      if (streak > 730) break;
    }
    return streak;
  }

  /// Crea o actualiza el plan de [day]. Es un upsert sobre (user_id, plan_date),
  /// así que reabrir el ritual la misma noche no duplica filas.
  Future<DayPlan> savePlan({
    required DateTime day,
    String? intention,
    String? reflection,
    int? mood,
    bool? ritualCompleted,
  }) async {
    await _ensureLoaded();

    final dayOnly = _dateOnly(day);
    final existing = planFor(dayOnly);
    final merged = (existing ??
            DayPlan(
              id: 'local-${DateTime.now().millisecondsSinceEpoch}',
              planDate: dayOnly,
              plannedAt: DateTime.now(),
            ))
        .copyWith(
      intention: intention,
      reflection: reflection,
      mood: mood,
      ritualCompleted: ritualCompleted,
      plannedAt: DateTime.now(),
    );

    state = [
      merged,
      ...state.where((p) => p.planDate != dayOnly),
    ];
    _scheduleCacheSave();

    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured) return merged;

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return merged;

      final response = await client
          .from('day_plans')
          .upsert(merged.toUpsertJson(user.id), onConflict: 'user_id,plan_date')
          .select()
          .single();

      final saved = DayPlan.fromJson(response);
      state = [
        saved,
        ...state.where((p) => p.planDate != dayOnly),
      ];
      _scheduleCacheSave();
      return saved;
    } catch (e) {
      lastSyncError = 'No se pudo guardar el plan en el servidor. Quedó en este dispositivo.';
      return merged;
    }
  }
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final dayPlansProvider = NotifierProvider<DayPlansNotifier, List<DayPlan>>(() {
  return DayPlansNotifier();
});
