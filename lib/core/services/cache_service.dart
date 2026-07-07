import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Caché local de datos no sensibles (hábitos, notas, alarmas) usada para
/// mostrar el último estado conocido al instante mientras se refresca contra
/// Supabase. Usa shared_preferences (plano) en vez de flutter_secure_storage
/// (cifrado): el contenido es siempre reconstruible desde Supabase, así que no
/// necesita el costo extra de cifrado en cada lectura/escritura. Las
/// credenciales/vault siguen usando flutter_secure_storage aparte.
class CacheService {
  static SharedPreferences? _prefs;

  static const _knownKeys = ['habits', 'notes', 'alarms', 'semantic_edges'];

  static Future<SharedPreferences> _instance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static String get _userId => Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  static String _scopedKey(String key) => '${key}_$_userId';

  static Future<void> save(String key, dynamic data) async {
    try {
      final prefs = await _instance();
      final jsonStr = jsonEncode(data);
      await prefs.setString(_scopedKey(key), jsonStr);
    } catch (_) {}
  }

  static Future<dynamic> read(String key) async {
    try {
      final prefs = await _instance();
      final jsonStr = prefs.getString(_scopedKey(key));
      if (jsonStr != null) {
        return jsonDecode(jsonStr);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> delete(String key) async {
    try {
      final prefs = await _instance();
      await prefs.remove(_scopedKey(key));
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await _instance();
      for (final key in _knownKeys) {
        await prefs.remove(_scopedKey(key));
      }
    } catch (_) {}
  }
}
