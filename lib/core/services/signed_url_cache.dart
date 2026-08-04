import 'package:supabase_flutter/supabase_flutter.dart';

/// Cachea el `Future` de una URL firmada de Storage, por bucket+ruta.
///
/// Sin esto, cada vez que un widget con un `FutureBuilder` inline se
/// reconstruye (p. ej. al escribir en un campo del mismo formulario) se
/// pide una URL firmada nueva -- distinta a la anterior -- y `Image.network`
/// la trata como una imagen nunca vista, así que se repite la descarga
/// completa en vez de usar la que ya estaba en la caché de imágenes de
/// Flutter. Aquí la URL (y su future en vuelo) se piden una sola vez por
/// ruta mientras siga viva la sesión de la app.
class SignedUrlCache {
  SignedUrlCache._();

  static final Map<String, Future<String>> _cache = {};

  static Future<String> get(
    String bucket,
    String path, {
    int expiresIn = 3600,
  }) {
    final key = '$bucket/$path';
    return _cache.putIfAbsent(
      key,
      () => Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(path, expiresIn),
    );
  }

  static void invalidate(String bucket, String path) {
    _cache.remove('$bucket/$path');
  }
}
