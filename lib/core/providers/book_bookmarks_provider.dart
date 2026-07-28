import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_bookmark_model.dart';
import '../services/cache_service.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

class BookBookmarksNotifier extends Notifier<List<BookBookmark>> {
  @override
  List<BookBookmark> build() {
    _loadBookmarks();
    return [];
  }

  bool get _hasSupabase {
    final settings = ref.read(settingsProvider);
    return settings.isSupabaseConfigured &&
        Supabase.instance.client.auth.currentUser != null;
  }

  List<BookBookmark> _sorted(List<BookBookmark> bookmarks) {
    final sorted = [...bookmarks];
    sorted.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return sorted;
  }

  Future<void> _loadBookmarks() async {
    try {
      final cached = await CacheService.read('book_bookmarks');
      if (cached != null && cached is List) {
        state = _sorted(
            cached.map((e) => BookBookmark.fromCacheJson(e as Map<String, dynamic>)).toList());
      }
    } catch (_) {}

    try {
      if (!_hasSupabase) {
        if (state.isEmpty) state = [];
        return;
      }

      final response = await Supabase.instance.client
          .from('book_bookmarks')
          .select('id, book_id, position, label, created_at')
          .order('created_at', ascending: false);

      final bookmarks = (response as List).map((json) => BookBookmark.fromJson(json)).toList();
      state = _sorted(bookmarks);
      unawaited(CacheService.save('book_bookmarks', bookmarks.map((b) => b.toCacheJson()).toList()));
    } catch (e) {
      if (state.isEmpty) state = [];
    }
  }

  Future<void> refresh() => _loadBookmarks();

  List<BookBookmark> forBook(String bookId) =>
      state.where((b) => b.bookId == bookId).toList();

  Future<void> addBookmark(String bookId, String position, {String? label}) async {
    final draft = BookBookmark(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookId: bookId,
      position: position,
      label: label,
      createdAt: DateTime.now(),
    );

    BookBookmark saved = draft;
    try {
      if (_hasSupabase && _uuidRegex.hasMatch(bookId)) {
        final client = Supabase.instance.client;
        final response = await client
            .from('book_bookmarks')
            .insert(draft.toInsertJson(client.auth.currentUser!.id))
            .select('id, book_id, position, label, created_at')
            .single();
        saved = BookBookmark.fromJson(response);
      }
    } catch (_) {
      // Se conserva local si falla el guardado remoto
    }

    state = _sorted([saved, ...state]);
    unawaited(CacheService.save('book_bookmarks', state.map((b) => b.toCacheJson()).toList()));
  }

  Future<void> deleteBookmark(String id) async {
    state = state.where((b) => b.id != id).toList();
    unawaited(CacheService.save('book_bookmarks', state.map((b) => b.toCacheJson()).toList()));

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client.from('book_bookmarks').delete().eq('id', id);
      }
    } catch (_) {
      // Ignorar
    }
  }
}

final bookBookmarksProvider = NotifierProvider<BookBookmarksNotifier, List<BookBookmark>>(() {
  return BookBookmarksNotifier();
});
