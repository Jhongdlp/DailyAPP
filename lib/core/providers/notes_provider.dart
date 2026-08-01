import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/note_model.dart';
import '../network/local_ai_client.dart';
import '../services/note_reminder_service.dart';
import '../services/cache_service.dart';
import '../services/outbox_service.dart';
import '../services/synced_write.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Columnas explícitas: NUNCA traer `embedding` (1024 floats por nota).
const _noteColumns =
    'id, user_id, vault_id, title, content, linked_note_ids, priority, '
    'remind_at, self_destruct, created_at';

class NotesNotifier extends Notifier<List<Note>> {
  bool _backfilling = false;
  @override
  List<Note> build() {
    _loadNotes();
    return [];
  }

  bool get _hasSupabase {
    final settings = ref.read(settingsProvider);
    return settings.isSupabaseConfigured &&
        Supabase.instance.client.auth.currentUser != null;
  }

  /// Ordena: recordatorios pendientes más próximos primero,
  /// luego por prioridad, luego por fecha de creación.
  List<Note> _sorted(List<Note> notes) {
    final sorted = [...notes];
    sorted.sort((a, b) {
      final aPending = a.isReminderPending;
      final bPending = b.isReminderPending;
      if (aPending != bPending) return aPending ? -1 : 1;
      if (aPending && bPending) return a.remindAt!.compareTo(b.remindAt!);
      final byPriority = b.priority.value.compareTo(a.priority.value);
      if (byPriority != 0) return byPriority;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });
    return sorted;
  }

  Future<void> _loadNotes() async {
    try {
      // Intentar cargar desde caché local primero para velocidad instantánea
      final cached = await CacheService.read('notes');
      if (cached != null && cached is List) {
        state = _sorted(cached.map((e) => Note.fromCacheJson(e as Map<String, dynamic>)).toList());
      }
    } catch (_) {}

    try {
      if (!_hasSupabase) {
        if (state.isEmpty) state = [];
        return;
      }

      final client = Supabase.instance.client;
      final response = await client
          .from('notes')
          .select(_noteColumns)
          .order('created_at', ascending: false);

      // Las notas escritas sin conexión siguen en el outbox: se reaplican
      // encima para que no desaparezcan al recargar.
      final rows = OutboxService.reconcileRows(
        [for (final row in response as List) Map<String, dynamic>.from(row as Map)],
        await OutboxService.pendingFor('notes'),
      );

      final allNotes = rows.map(Note.fromJson).toList();

      // Autodestrucción: eliminar notas cuyo recordatorio ya pasó
      final expired = allNotes.where((n) => n.isExpired).toList();
      final alive = allNotes.where((n) => !n.isExpired).toList();

      for (final note in expired) {
        await NoteReminderService.cancelReminder(note.id);
        await client.from('notes').delete().eq('id', note.id);
      }

      state = _sorted(alive);
      unawaited(CacheService.save('notes', alive.map((n) => n.toCacheJson()).toList()));

      // Reprogramar recordatorios pendientes (por si el dispositivo se reinició)
      await NoteReminderService.rescheduleAll(alive);

      // Generar embeddings para notas que aún no los tienen (en segundo plano)
      unawaited(_backfillEmbeddings());
    } catch (e) {
      if (state.isEmpty) state = [];
    }
  }

  Future<void> refresh() => _loadNotes();

  // ─── Embeddings (Máquina de Conocimiento) ─────────────────────

  LocalAIClient get _aiClient {
    final settings = ref.read(settingsProvider);
    return LocalAIClient(
      baseUrl: settings.localAiUrl,
      embeddingModelName: settings.embeddingModel,
    );
  }

  /// Genera y guarda el embedding de una nota. Degrada en silencio si el
  /// servidor de IA está caído: la nota queda guardada sin embedding y el
  /// backfill la recogerá más adelante.
  Future<void> _embedNote(String id, String title, String content) async {
    if (!_hasSupabase || !_uuidRegex.hasMatch(id)) return;
    try {
      final vector = await _aiClient.embed('$title\n\n$content');
      await Supabase.instance.client
          .from('notes')
          .update({'embedding': vector}).eq('id', id);
    } catch (_) {
      // Sin conexión con el servidor de embeddings: se reintenta en backfill
    }
  }

  /// Embebe en serie (throttled) todas las notas que aún no tienen embedding.
  Future<void> _backfillEmbeddings() async {
    if (_backfilling || !_hasSupabase) return;
    _backfilling = true;
    try {
      final client = Supabase.instance.client;
      final pending = await client
          .from('notes')
          .select('id, title, content')
          .isFilter('embedding', null);

      for (final row in (pending as List)) {
        final id = row['id'] as String;
        final title = row['title'] as String? ?? '';
        final content = row['content'] as String? ?? '';
        try {
          final vector = await _aiClient.embed('$title\n\n$content');
          await client.from('notes').update({'embedding': vector}).eq('id', id);
        } catch (_) {
          // Servidor de IA caído: abortar el backfill, se reintentará luego
          break;
        }
        // Throttle para no saturar el servidor de embeddings
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (_) {
      // Ignorar: el backfill es best-effort
    } finally {
      _backfilling = false;
    }
  }

  /// Retorna notas filtradas por vault
  List<Note> notesForVault(String? vaultId) {
    if (vaultId == null) return state;
    return state.where((n) => n.vaultId == vaultId).toList();
  }

  /// Crea una nota y devuelve la versión guardada, para que quien la crea
  /// pueda enlazarla (por ejemplo, un resaltado de un libro).
  Future<Note> addNote(
    String title,
    String content, {
    List<String>? linkedNoteIds,
    NotePriority priority = NotePriority.normal,
    DateTime? remindAt,
    bool selfDestruct = false,
    String? vaultId,
    DateTime? reminderStartDate,
    DateTime? reminderEndDate,
    int? reminderHour,
    int? reminderMinute,
  }) async {
    final draft = Note(
      // Id definitivo desde el cliente: la nota creada sin conexión ya es una
      // fila válida y sus enlaces apuntan a algo que existirá al sincronizar.
      id: newRowId(),
      title: title,
      content: content,
      linkedNoteIds: linkedNoteIds ?? [],
      priority: priority,
      remindAt: remindAt,
      selfDestruct: selfDestruct,
      createdAt: DateTime.now(),
      vaultId: vaultId,
      reminderStartDate: reminderStartDate,
      reminderEndDate: reminderEndDate,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
    );

    final saved = draft;
    if (_hasSupabase && canWriteToSupabase) {
      final client = Supabase.instance.client;
      final validUuids = draft.linkedNoteIds.where(_uuidRegex.hasMatch).toList();
      final payload = {
        'id': draft.id,
        ...draft.toInsertJson(client.auth.currentUser!.id, validUuids),
      };

      final outcome = await syncedWrite(
        write: () => client.from('notes').insert(payload),
        fallback: () => OutboxOp.create(
          table: 'notes',
          kind: OutboxOpKind.insert,
          payload: payload,
          match: {'id': draft.id},
        ),
      );

      // El embedding necesita Ollama, así que sin red se queda pendiente. No
      // hace falta encolarlo: `_backfillEmbeddings` recorre en cada carga las
      // notas que aún no tienen vector y las rellena.
      if (outcome.isConfirmed) unawaited(_embedNote(saved.id, title, content));
    }

    state = _sorted([saved, ...state]);
    unawaited(CacheService.save('notes', state.map((n) => n.toCacheJson()).toList()));

    if (saved.isReminderPending) {
      await NoteReminderService.scheduleReminder(saved);
    }

    return saved;
  }

  Future<void> updateNote(
    String id,
    String title,
    String content,
    List<String> linkedNoteIds, {
    NotePriority? priority,
    DateTime? remindAt,
    bool clearRemindAt = false,
    bool? selfDestruct,
    String? vaultId,
    bool clearVaultId = false,
    DateTime? reminderStartDate,
    DateTime? reminderEndDate,
    int? reminderHour,
    int? reminderMinute,
    bool clearRangeReminder = false,
  }) async {
    final noteIndex = state.indexWhere((n) => n.id == id);
    if (noteIndex == -1) return;

    final updatedNote = state[noteIndex].copyWith(
      title: title,
      content: content,
      linkedNoteIds: linkedNoteIds,
      priority: priority,
      remindAt: remindAt,
      clearRemindAt: clearRemindAt,
      selfDestruct: selfDestruct,
      vaultId: vaultId,
      clearVaultId: clearVaultId,
      reminderStartDate: reminderStartDate,
      reminderEndDate: reminderEndDate,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
      clearRangeReminder: clearRangeReminder,
    );

    state = _sorted([
      for (final n in state)
        if (n.id == id) updatedNote else n
    ]);
    unawaited(CacheService.save('notes', state.map((n) => n.toCacheJson()).toList()));

    if (updatedNote.isReminderPending) {
      await NoteReminderService.scheduleReminder(updatedNote);
    } else {
      await NoteReminderService.cancelReminder(id);
    }

    if (!_hasSupabase || !_uuidRegex.hasMatch(id) || !canWriteToSupabase) return;

    final validUuids = linkedNoteIds.where(_uuidRegex.hasMatch).toList();
    final payload = {
      'title': title,
      'content': updatedNote.serializedContent,
      'linked_note_ids': validUuids,
      'priority': updatedNote.priority.value,
      'remind_at': updatedNote.remindAt?.toUtc().toIso8601String(),
      'self_destruct': updatedNote.selfDestruct,
      'vault_id': clearVaultId ? null : (vaultId ?? updatedNote.vaultId),
    };

    final outcome = await syncedWrite(
      write: () => Supabase.instance.client.from('notes').update(payload).eq('id', id),
      fallback: () => OutboxOp.create(
        table: 'notes',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': id},
      ),
    );

    // Reembeber: el contenido pudo haber cambiado.
    if (outcome.isConfirmed) unawaited(_embedNote(id, title, content));
  }

  Future<void> deleteNote(String id) async {
    await NoteReminderService.cancelReminder(id);
    state = state.where((n) => n.id != id).toList();
    unawaited(CacheService.save('notes', state.map((n) => n.toCacheJson()).toList()));

    if (!_hasSupabase || !_uuidRegex.hasMatch(id) || !canWriteToSupabase) return;

    await syncedWrite(
      write: () => Supabase.instance.client.from('notes').delete().eq('id', id),
      fallback: () => OutboxOp.create(
        table: 'notes',
        kind: OutboxOpKind.delete,
        match: {'id': id},
      ),
    );
  }

  Future<void> linkNotes(String id1, String id2) async {
    state = state.map((note) {
      if (note.id == id1 && !note.linkedNoteIds.contains(id2)) {
        return note.copyWith(linkedNoteIds: [...note.linkedNoteIds, id2]);
      }
      if (note.id == id2 && !note.linkedNoteIds.contains(id1)) {
        return note.copyWith(linkedNoteIds: [...note.linkedNoteIds, id1]);
      }
      return note;
    }).toList();
    unawaited(CacheService.save('notes', state.map((n) => n.toCacheJson()).toList()));

    if (!_hasSupabase ||
        !_uuidRegex.hasMatch(id1) ||
        !_uuidRegex.hasMatch(id2) ||
        !canWriteToSupabase) {
      return;
    }

    // El enlace es recíproco: son dos filas y hacen falta dos escrituras, cada
    // una encolable por su cuenta.
    final client = Supabase.instance.client;
    for (final id in [id1, id2]) {
      final note = state.firstWhere((n) => n.id == id);
      final payload = {'linked_note_ids': note.linkedNoteIds};

      await syncedWrite(
        write: () => client.from('notes').update(payload).eq('id', id),
        fallback: () => OutboxOp.create(
          table: 'notes',
          kind: OutboxOpKind.update,
          payload: payload,
          match: {'id': id},
        ),
      );
    }
  }
}

final notesProvider = NotifierProvider<NotesNotifier, List<Note>>(() {
  return NotesNotifier();
});
