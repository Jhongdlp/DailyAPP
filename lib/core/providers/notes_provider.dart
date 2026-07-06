import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/note_model.dart';
import '../services/note_reminder_service.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

class NotesNotifier extends Notifier<List<Note>> {
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
      if (!_hasSupabase) {
        state = [];
        return;
      }

      final client = Supabase.instance.client;
      final response = await client
          .from('notes')
          .select()
          .order('created_at', ascending: false);

      final allNotes =
          (response as List).map((json) => Note.fromJson(json)).toList();

      // Autodestrucción: eliminar notas cuyo recordatorio ya pasó
      final expired = allNotes.where((n) => n.isExpired).toList();
      final alive = allNotes.where((n) => !n.isExpired).toList();

      for (final note in expired) {
        await NoteReminderService.cancelReminder(note.id);
        await client.from('notes').delete().eq('id', note.id);
      }

      state = _sorted(alive);

      // Reprogramar recordatorios pendientes (por si el dispositivo se reinició)
      await NoteReminderService.rescheduleAll(alive);
    } catch (e) {
      state = [];
    }
  }

  Future<void> refresh() => _loadNotes();

  /// Retorna notas filtradas por vault
  List<Note> notesForVault(String? vaultId) {
    if (vaultId == null) return state;
    return state.where((n) => n.vaultId == vaultId).toList();
  }

  Future<void> addNote(
    String title,
    String content, {
    List<String>? linkedNoteIds,
    NotePriority priority = NotePriority.normal,
    DateTime? remindAt,
    bool selfDestruct = false,
    String? vaultId,
  }) async {
    final draft = Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      linkedNoteIds: linkedNoteIds ?? [],
      priority: priority,
      remindAt: remindAt,
      selfDestruct: selfDestruct,
      createdAt: DateTime.now(),
      vaultId: vaultId,
    );

    Note saved = draft;
    try {
      if (_hasSupabase) {
        final client = Supabase.instance.client;
        final validUuids =
            draft.linkedNoteIds.where(_uuidRegex.hasMatch).toList();
        final response = await client
            .from('notes')
            .insert(draft.toInsertJson(client.auth.currentUser!.id, validUuids))
            .select()
            .single();
        saved = Note.fromJson(response);
      }
    } catch (e) {
      // Mantener la nota local si falla el guardado remoto
    }

    state = _sorted([saved, ...state]);

    if (saved.isReminderPending) {
      await NoteReminderService.scheduleReminder(saved);
    }
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
    );

    state = _sorted([
      for (final n in state)
        if (n.id == id) updatedNote else n
    ]);

    if (updatedNote.isReminderPending) {
      await NoteReminderService.scheduleReminder(updatedNote);
    } else {
      await NoteReminderService.cancelReminder(id);
    }

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        final validUuids = linkedNoteIds.where(_uuidRegex.hasMatch).toList();
        await Supabase.instance.client.from('notes').update({
          'title': title,
          'content': content,
          'linked_note_ids': validUuids,
          'priority': updatedNote.priority.value,
          'remind_at': updatedNote.remindAt?.toUtc().toIso8601String(),
          'self_destruct': updatedNote.selfDestruct,
          'vault_id': clearVaultId ? null : (vaultId ?? updatedNote.vaultId),
        }).eq('id', id);
      }
    } catch (e) {
      // Ignorar
    }
  }

  Future<void> deleteNote(String id) async {
    await NoteReminderService.cancelReminder(id);
    state = state.where((n) => n.id != id).toList();

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client.from('notes').delete().eq('id', id);
      }
    } catch (e) {
      // Ignorar
    }
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

    try {
      if (_hasSupabase &&
          _uuidRegex.hasMatch(id1) &&
          _uuidRegex.hasMatch(id2)) {
        final client = Supabase.instance.client;
        final n1 = state.firstWhere((n) => n.id == id1);
        final n2 = state.firstWhere((n) => n.id == id2);
        await client
            .from('notes')
            .update({'linked_note_ids': n1.linkedNoteIds}).eq('id', id1);
        await client
            .from('notes')
            .update({'linked_note_ids': n2.linkedNoteIds}).eq('id', id2);
      }
    } catch (e) {
      // Ignorar
    }
  }
}

final notesProvider = NotifierProvider<NotesNotifier, List<Note>>(() {
  return NotesNotifier();
});
