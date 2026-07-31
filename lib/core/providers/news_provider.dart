import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/news_model.dart';
import '../services/cache_service.dart';

/// Base cruda del repo donde la routine publica los digests. Es contenido
/// público y de solo lectura, así que va sin credenciales.
const _newsBaseUrl =
    'https://raw.githubusercontent.com/Jhongdlp/DailyAPP/main/news';

/// Días hacia atrás que se prueban cuando el digest de hoy todavía no existe.
/// La routine corre a las 6am; abrir la app antes de esa hora, o después de un
/// día en que falló, debe mostrar el último digest disponible en vez de vacío.
const _maxLookbackDays = 7;

String _fileNameFor(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d.json';
}

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

class NewsNotifier extends Notifier<NewsState> {
  @override
  NewsState build() {
    _load();
    return const NewsState(isLoading: true);
  }

  Future<void> _load() async {
    // El digest cacheado se pinta primero para que el apartado abra al
    // instante y siga sirviendo sin conexión; la red solo lo reemplaza si
    // trae algo más nuevo.
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

  /// Descarga el digest más reciente disponible.
  ///
  /// [silent] evita el spinner cuando ya hay un digest cacheado en pantalla:
  /// un refresco de fondo no debería vaciar la vista.
  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, clearError: true);

    final client = http.Client();
    try {
      final today = DateTime.now();
      for (var back = 0; back < _maxLookbackDays; back++) {
        final day = today.subtract(Duration(days: back));
        final digest = await _fetchDay(client, day);
        if (digest == null) continue;

        // Un digest más viejo que el cacheado no lo reemplaza: pasa cuando la
        // routine aún no publicó hoy y el lookback encuentra el de ayer, que
        // ya teníamos.
        final current = state.digest;
        if (current != null && digest.date.isBefore(current.date)) {
          state = state.copyWith(isLoading: false, clearError: true);
          return;
        }

        await CacheService.save('news_digest', digest.toJson());
        state = NewsState(digest: digest, isLoading: false);
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: state.digest == null
            ? 'Todavía no hay ningún digest publicado.'
            : 'No se encontró un digest más reciente.',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: state.digest == null
            ? 'No se pudo cargar el digest: $e'
            : 'Sin conexión — mostrando el último digest guardado.',
      );
    } finally {
      client.close();
    }
  }

  Future<NewsDigest?> _fetchDay(http.Client client, DateTime day) async {
    try {
      final response = await client
          .get(Uri.parse('$_newsBaseUrl/${_fileNameFor(day)}'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      // `bodyBytes` + utf8 explícito: raw.githubusercontent no manda charset y
      // `response.body` asumiría latin-1, rompiendo las tildes de los resúmenes.
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;

      final digest = NewsDigest.fromJson(decoded);
      return digest.isEmpty ? null : digest;
    } catch (_) {
      return null;
    }
  }
}

final newsProvider =
    NotifierProvider<NewsNotifier, NewsState>(NewsNotifier.new);
