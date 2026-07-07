import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Envuelve el modo "Lock Task" / Screen Pinning de Android.
///
/// En una app normal (sin device owner) esto activa el *fijado de pantalla*:
/// se desactivan los botones Home y Recientes. El usuario todavía puede salir
/// manteniendo pulsado Atrás + Recientes, pero es un candado suficientemente
/// fuerte para una alarma anti-procrastinación.
///
/// En iOS no existe equivalente accesible para apps de la App Store, así que
/// todas las llamadas son no-ops.
class LockTaskService {
  static const _channel = MethodChannel('com.sistemdaily/lock_task');

  /// Fija la pantalla. Devuelve `true` si la llamada nativa tuvo éxito.
  static Future<bool> enable() async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startLockTask');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.enable error: ${e.message}');
      return false;
    }
  }

  /// Libera la pantalla fijada. Seguro de llamar aunque no esté fijada.
  static Future<bool> disable() async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('stopLockTask');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.disable error: ${e.message}');
      return false;
    }
  }

  /// Indica si la pantalla está actualmente fijada.
  static Future<bool> isActive() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isInLockTaskMode') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre la pantalla de ajustes de notificaciones de la app en el sistema.
  static Future<bool> openNotificationSettings() async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openNotificationSettings');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.openNotificationSettings error: ${e.message}');
      return false;
    }
  }

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
}
