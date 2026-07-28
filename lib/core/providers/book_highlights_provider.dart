import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book_highlight_model.dart';
import '../services/cache_service.dart';

/// Resaltados de todos los libros, persistidos en el caché local.
///
/// A diferencia de libros y bookmarks, esto no se sincroniza con Supabase: el
/// lector consulta los resaltados del párrafo en cada frame que pinta, así que
/// interesa tenerlos en memoria y sin latencia de red. El índice por libro se
/// mantiene precalculado por la misma razón.
class BookHighlightsNotifier extends Notifier<List<BookHighlight>> {
  static const _cacheKey = 'book_highlights';

  Map<String, List<BookHighlight>> _byBook = const {};

  @override
  List<BookHighlight> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    try {
      final cached = await CacheService.read(_cacheKey);
      if (cached is List) {
        _setState(cached
            .map((e) => BookHighlight.fromCacheJson(e as Map<String, dynamic>))
            .toList());
      }
    } catch (_) {
      // Caché corrupto: se arranca sin resaltados
    }
  }

  void _setState(List<BookHighlight> highlights) {
    final sorted = [...highlights]..sort((a, b) {
        final byParagraph =
            (a.paragraphIndex ?? 0).compareTo(b.paragraphIndex ?? 0);
        if (byParagraph != 0) return byParagraph;
        return (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
      });

    final index = <String, List<BookHighlight>>{};
    for (final h in sorted) {
      (index[h.bookId] ??= []).add(h);
    }

    _byBook = index;
    state = sorted;
  }

  Future<void> _persist() =>
      CacheService.save(_cacheKey, state.map((h) => h.toCacheJson()).toList());

  /// Resaltados de un libro, ya ordenados por posición.
  List<BookHighlight> forBook(String bookId) => _byBook[bookId] ?? const [];

  /// Resaltados de un párrafo concreto. Se usa en el pintado del texto, por eso
  /// filtra sobre el índice precalculado y no sobre la lista completa.
  List<BookHighlight> forParagraph(String bookId, int paragraphIndex) {
    final all = _byBook[bookId];
    if (all == null) return const [];
    return all.where((h) => h.paragraphIndex == paragraphIndex).toList();
  }

  Future<BookHighlight> addHighlight({
    required String bookId,
    required String text,
    HighlightColor color = HighlightColor.yellow,
    String? note,
    String? position,
    int? paragraphIndex,
    String? chapterTitle,
    String? noteId,
  }) async {
    final highlight = BookHighlight(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      bookId: bookId,
      text: text,
      note: note,
      color: color,
      position: position,
      paragraphIndex: paragraphIndex,
      chapterTitle: chapterTitle,
      noteId: noteId,
      createdAt: DateTime.now(),
    );

    _setState([...state, highlight]);
    unawaited(_persist());
    return highlight;
  }

  Future<void> updateHighlight(
    String id, {
    String? note,
    HighlightColor? color,
    String? noteId,
  }) async {
    final index = state.indexWhere((h) => h.id == id);
    if (index == -1) return;

    final updated = state[index].copyWith(note: note, color: color, noteId: noteId);
    _setState([
      for (final h in state)
        if (h.id == id) updated else h,
    ]);
    unawaited(_persist());
  }

  Future<void> deleteHighlight(String id) async {
    _setState(state.where((h) => h.id != id).toList());
    unawaited(_persist());
  }

  /// Limpia los resaltados de un libro borrado.
  Future<void> deleteForBook(String bookId) async {
    if (!_byBook.containsKey(bookId)) return;
    _setState(state.where((h) => h.bookId != bookId).toList());
    unawaited(_persist());
  }
}

final bookHighlightsProvider =
    NotifierProvider<BookHighlightsNotifier, List<BookHighlight>>(
        BookHighlightsNotifier.new);
