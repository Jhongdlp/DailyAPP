import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cache_service.dart';

/// Total de palabras por libro, medido por el lector la primera vez que
/// construye su índice de texto.
///
/// Vive aparte del propio libro porque solo se conoce después de abrirlo, y la
/// biblioteca lo necesita para estimar el tiempo restante sin tener que parsear
/// el EPUB entero para pintar una tarjeta.
class BookMetricsNotifier extends Notifier<Map<String, int>> {
  static const _cacheKey = 'book_word_counts';

  @override
  Map<String, int> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final cached = await CacheService.read(_cacheKey);
      if (cached is Map) {
        state = {
          for (final entry in cached.entries)
            entry.key as String: (entry.value as num).toInt(),
        };
      }
    } catch (_) {
      // Caché corrupto: se vuelve a medir al abrir cada libro
    }
  }

  int? wordsOf(String bookId) => state[bookId];

  void setWords(String bookId, int words) {
    if (words <= 0 || state[bookId] == words) return;
    state = {...state, bookId: words};
    unawaited(CacheService.save(_cacheKey, state));
  }

  /// Minutos estimados para terminar el libro al ritmo [wordsPerMinute].
  /// Devuelve `null` mientras no se haya medido el libro.
  int? minutesLeft(String bookId, double progress, double wordsPerMinute) {
    final words = state[bookId];
    if (words == null || wordsPerMinute <= 0) return null;
    final remaining = words * (1 - progress.clamp(0.0, 1.0));
    return (remaining / wordsPerMinute).ceil();
  }
}

final bookMetricsProvider =
    NotifierProvider<BookMetricsNotifier, Map<String, int>>(
        BookMetricsNotifier.new);
