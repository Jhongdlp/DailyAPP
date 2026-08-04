import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/exercise_model.dart';
import '../services/cache_service.dart';
import '../services/outbox_service.dart';
import '../services/synced_write.dart';
import 'settings_provider.dart';

/// Cuántos días de historial se traen al cargar: suficiente para comparar
/// progreso "en unos meses" (running + fotos) sin arrastrar toda la vida de
/// la cuenta en cada carga.
const _historyDays = 400;

class ExerciseState {
  final List<ExerciseLog> logs;
  final List<ExercisePhoto> photos;
  final bool loading;

  const ExerciseState({
    this.logs = const [],
    this.photos = const [],
    this.loading = false,
  });

  ExerciseState copyWith({
    List<ExerciseLog>? logs,
    List<ExercisePhoto>? photos,
    bool? loading,
  }) {
    return ExerciseState(
      logs: logs ?? this.logs,
      photos: photos ?? this.photos,
      loading: loading ?? this.loading,
    );
  }
}

class ExerciseNotifier extends Notifier<ExerciseState> {
  Future<void>? _loadFuture;
  DateTime? _lastSyncedAt;
  static const _cacheTtl = Duration(seconds: 90);

  @override
  ExerciseState build() {
    _loadFuture = _load();
    return const ExerciseState(loading: true);
  }

  Future<void> _ensureLoaded() async {
    if (_loadFuture != null) await _loadFuture;
  }

  Future<void> refresh({bool force = true}) => _load(force: force);

  Future<void> _load({bool force = false}) async {
    try {
      final cached = await CacheService.read('exercise');
      if (cached is Map) {
        final syncedAtStr = cached['syncedAt'] as String?;
        _lastSyncedAt = syncedAtStr != null ? DateTime.tryParse(syncedAtStr) : null;
        final logsJson = cached['logs'] as List? ?? const [];
        final photosJson = cached['photos'] as List? ?? const [];
        state = state.copyWith(
          logs: logsJson.map((e) => ExerciseLog.fromCacheJson(Map<String, dynamic>.from(e as Map))).toList(),
          photos: photosJson.map((e) => ExercisePhoto.fromCacheJson(Map<String, dynamic>.from(e as Map))).toList(),
        );
      }
    } catch (_) {}

    try {
      if (!force && _lastSyncedAt != null && DateTime.now().difference(_lastSyncedAt!) < _cacheTtl) {
        state = state.copyWith(loading: false);
        return;
      }

      final settings = ref.read(settingsProvider);
      if (!settings.isSupabaseConfigured) {
        state = state.copyWith(loading: false);
        return;
      }

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        state = state.copyWith(loading: false);
        return;
      }

      final cutoff = DateTime.now().subtract(const Duration(days: _historyDays));
      final cutoffStr = _fmtDate(cutoff);

      final logsResponse = await client
          .from('exercise_logs')
          .select()
          .eq('user_id', user.id)
          .gte('logged_date', cutoffStr)
          .order('logged_date', ascending: false);

      final photosResponse = await client
          .from('exercise_photos')
          .select()
          .eq('user_id', user.id)
          .gte('logged_date', cutoffStr)
          .order('logged_date', ascending: false);

      final logRows = OutboxService.reconcileRows(
        [for (final row in logsResponse as List) Map<String, dynamic>.from(row as Map)],
        await OutboxService.pendingFor('exercise_logs'),
      );
      final photoRows = OutboxService.reconcileRows(
        [for (final row in photosResponse as List) Map<String, dynamic>.from(row as Map)],
        await OutboxService.pendingFor('exercise_photos'),
      );

      final freshLogs = logRows.map((json) => ExerciseLog.fromJson(json)).toList();
      final freshPhotos = photoRows.map((json) => ExercisePhoto.fromJson(json)).toList();

      state = ExerciseState(logs: freshLogs, photos: freshPhotos, loading: false);
      _lastSyncedAt = DateTime.now();
      unawaited(_persistCache());
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> _persistCache() => CacheService.save('exercise', {
        'syncedAt': _lastSyncedAt?.toIso8601String(),
        'logs': state.logs.map((l) => l.toCacheJson()).toList(),
        'photos': state.photos.map((p) => p.toCacheJson()).toList(),
      });

  ExerciseLog? logForDate(DateTime day) {
    final target = dateOnly(day);
    for (final log in state.logs) {
      if (dateOnly(log.loggedDate) == target) return log;
    }
    return null;
  }

  List<ExercisePhoto> photosForDate(DateTime day) {
    final target = dateOnly(day);
    return state.photos.where((p) => dateOnly(p.loggedDate) == target).toList();
  }

  /// Agrupa fotos por día, más recientes primero, para el grid de progreso.
  Map<DateTime, List<ExercisePhoto>> photosByDate() {
    final map = <DateTime, List<ExercisePhoto>>{};
    for (final photo in state.photos) {
      final day = dateOnly(photo.loggedDate);
      map.putIfAbsent(day, () => []).add(photo);
    }
    return map;
  }

  Future<ExerciseLog> upsertLog(ExerciseLog log) async {
    await _ensureLoaded();
    final index = state.logs.indexWhere((l) => l.id == log.id);
    final newLogs = [
      if (index == -1) ...state.logs else ...[
        for (int i = 0; i < state.logs.length; i++)
          if (i != index) state.logs[i]
      ],
      log,
    ];
    state = state.copyWith(logs: newLogs);
    unawaited(_persistCache());

    final settings = ref.read(settingsProvider);
    if (settings.isSupabaseConfigured && canWriteToSupabase) {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser!;
      final payload = log.toInsertJson(user.id);
      await syncedWrite(
        write: () => client.from('exercise_logs').upsert(payload, onConflict: 'id'),
        fallback: () => OutboxOp.create(
          table: 'exercise_logs',
          kind: OutboxOpKind.upsert,
          payload: payload,
          match: {'id': log.id},
          onConflict: 'id',
        ),
      );
    }
    return log;
  }

  /// Sube la foto a Storage y la registra en `exercise_photos`. Se llama
  /// **después** de una subida exitosa, nunca antes, para no dejar filas que
  /// apunten a objetos inexistentes en el bucket.
  Future<ExercisePhoto> addPhoto({
    required String id,
    required File file,
    required DateTime loggedDate,
    String? exerciseLogId,
  }) async {
    await _ensureLoaded();
    final settings = ref.read(settingsProvider);
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (!settings.isSupabaseConfigured || user == null) {
      throw Exception('Se requiere conexión para guardar fotos de progreso.');
    }

    final day = dateOnly(loggedDate);
    final storagePath = '${user.id}/${_fmtDate(day)}/$id.jpg';
    await client.storage.from('exercise-photos').upload(storagePath, file);

    final photo = ExercisePhoto(
      id: id,
      userId: user.id,
      exerciseLogId: exerciseLogId,
      loggedDate: day,
      storagePath: storagePath,
      classification: PhotoClassification.pending,
      takenAt: DateTime.now(),
      localFile: file,
    );

    state = state.copyWith(photos: [photo, ...state.photos]);
    unawaited(_persistCache());

    if (canWriteToSupabase) {
      final payload = photo.toInsertJson(user.id);
      await syncedWrite(
        write: () => client.from('exercise_photos').insert(payload),
        fallback: () => OutboxOp.create(
          table: 'exercise_photos',
          kind: OutboxOpKind.insert,
          payload: payload,
          match: {'id': photo.id},
        ),
      );
    }
    return photo;
  }

  /// Sube la captura de ruta (p. ej. pantallazo de Strava) y la liga al log
  /// [logId]. Cada llamada usa un nombre nuevo en vez de sobrescribir: el
  /// bucket no tiene policy de UPDATE en storage.objects, así que un
  /// upsert fallaría por RLS. El archivo viejo (si había) se borra best-effort.
  Future<String> uploadRoutePhoto({required String logId, required File file, String? previousPath}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Se requiere conexión para adjuntar la ruta.');

    final path = '${user.id}/routes/$logId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage.from('exercise-photos').upload(path, file);

    if (previousPath != null && previousPath.isNotEmpty) {
      unawaited(client.storage.from('exercise-photos').remove([previousPath]).catchError((_) => <FileObject>[]));
    }
    return path;
  }

  void setPhotoClassificationLocal(String photoId, PhotoClassification classification) {
    final index = state.photos.indexWhere((p) => p.id == photoId);
    if (index == -1) return;
    final updated = state.photos[index].copyWith(classification: classification);
    state = state.copyWith(photos: [
      for (int i = 0; i < state.photos.length; i++)
        if (i == index) updated else state.photos[i]
    ]);
  }

  Future<void> updatePhotoClassification(String photoId, PhotoClassification classification) async {
    setPhotoClassificationLocal(photoId, classification);
    unawaited(_persistCache());

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !canWriteToSupabase) return;
    final client = Supabase.instance.client;
    final payload = {
      'classification_status': classification.dbStatus,
      'classification': classification.dbClassification,
    };
    await syncedWrite(
      write: () => client.from('exercise_photos').update(payload).eq('id', photoId),
      fallback: () => OutboxOp.create(
        table: 'exercise_photos',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': photoId},
      ),
    );
  }

  Future<void> linkPhotosToLog(DateTime day, String exerciseLogId) async {
    final target = dateOnly(day);
    final toLink = state.photos.where((p) => dateOnly(p.loggedDate) == target && p.exerciseLogId == null).toList();
    if (toLink.isEmpty) return;

    state = state.copyWith(photos: [
      for (final p in state.photos)
        if (toLink.any((l) => l.id == p.id)) p.copyWith(exerciseLogId: exerciseLogId) else p
    ]);
    unawaited(_persistCache());

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !canWriteToSupabase) return;
    final client = Supabase.instance.client;
    for (final photo in toLink) {
      final payload = {'exercise_log_id': exerciseLogId};
      await syncedWrite(
        write: () => client.from('exercise_photos').update(payload).eq('id', photo.id),
        fallback: () => OutboxOp.create(
          table: 'exercise_photos',
          kind: OutboxOpKind.update,
          payload: payload,
          match: {'id': photo.id},
        ),
      );
    }
  }

  Future<void> deletePhoto(ExercisePhoto photo) async {
    state = state.copyWith(photos: state.photos.where((p) => p.id != photo.id).toList());
    unawaited(_persistCache());

    final settings = ref.read(settingsProvider);
    if (!settings.isSupabaseConfigured || !canWriteToSupabase) return;
    final client = Supabase.instance.client;

    // Borrado del objeto en Storage: best-effort, no bloquea ni se reintenta.
    unawaited(client.storage.from('exercise-photos').remove([photo.storagePath]).catchError((_) => <FileObject>[]));

    await syncedWrite(
      write: () => client.from('exercise_photos').delete().eq('id', photo.id),
      fallback: () => OutboxOp.create(
        table: 'exercise_photos',
        kind: OutboxOpKind.delete,
        match: {'id': photo.id},
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final day = dateOnly(d);
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

final exerciseProvider = NotifierProvider<ExerciseNotifier, ExerciseState>(() {
  return ExerciseNotifier();
});
