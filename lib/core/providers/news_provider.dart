import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/news_model.dart';
import '../services/cache_service.dart';
import 'settings_provider.dart';

class NewsState {
  final NewsDigest? digest;
  final bool isLoading;
  final String? error;

  const NewsState({this.digest, this.isLoading = false, this.error});

  NewsState copyWith({
    NewsDigest? digest,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NewsState(
      digest: digest ?? this.digest,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Lee el digest más reciente de `news_digests`.
///
/// La tabla la escribe una routine (agente programado en la nube) vía la
/// función `publish_news_digest`; la app solo lee. Por eso aquí no hay ninguna
/// ruta de escritura ni cola offline: no hay nada que sincronizar de vuelta.
class NewsNotifier extends Notifier<NewsState> {
  @override
  NewsState build() {
    _load();
    return const NewsState(isLoading: true);
  }

  bool get _hasSupabase {
    final settings = ref.read(settingsProvider);
    return settings.isSupabaseConfigured &&
        Supabase.instance.client.auth.currentUser != null;
  }

  Future<void> _load() async {
    // El digest cacheado se pinta primero para que la sección abra al
    // instante y siga sirviendo sin conexión.
    final cached = await _readCache();
    if (cached != null) {
      state = state.copyWith(digest: cached, isLoading: false, clearError: true);
    }
    await refresh(silent: cached != null);
  }

  Future<NewsDigest?> _readCache() async {
    try {
      final raw = await CacheService.read('news_digest');
      if (raw is Map<String, dynamic>) return NewsDigest.fromJson(raw);
    } catch (_) {}
    return null;
  }

  /// [silent] evita el spinner cuando ya hay un digest en pantalla: un
  /// refresco de fondo no debería vaciar la vista.
  Future<void> refresh({bool silent = false}) async {
    if (!_hasSupabase) {
      state = state.copyWith(
        isLoading: false,
        error: state.digest == null
            ? 'Inicia sesión para ver el digest de noticias.'
            : null,
      );
      return;
    }

    if (!silent) state = state.copyWith(isLoading: true, clearError: true);

    try {
      final rows = await Supabase.instance.client
          .from('news_digests')
          .select('digest_date, editorial, items')
          .order('digest_date', ascending: false)
          .limit(1);

      if (rows.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: state.digest == null
              ? 'Todavía no hay ningún digest publicado.'
              : null,
        );
        return;
      }

      final row = rows.first;
      // `digest_date` es la columna real; el modelo habla de `date`, que es
      // también la clave que usa el payload de la routine.
      final digest = NewsDigest.fromJson({
        'date': row['digest_date'],
        'editorial': row['editorial'],
        'items': row['items'],
      });

      await CacheService.save('news_digest', digest.toJson());
      state = NewsState(digest: digest, isLoading: false);
    } catch (e) {
      // Nunca se traga el error: si no hay nada cacheado el usuario debe ver
      // qué falló, y si lo hay debe saber que está viendo algo viejo.
      state = state.copyWith(
        isLoading: false,
        error: state.digest == null
            ? 'No se pudo cargar el digest: $e'
            : 'Sin conexión — mostrando el último digest guardado.',
      );
    }
  }
}

final newsProvider =
    NotifierProvider<NewsNotifier, NewsState>(NewsNotifier.new);
