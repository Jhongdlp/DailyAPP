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

  /// Muestra (o deja de mostrar) la app por encima de la pantalla de bloqueo.
  /// Se activa mientras suena una alarma para poder tomar la foto sin
  /// desbloquear el teléfono, y se desactiva al salir.
  static Future<bool> showOverLockscreen(bool show) async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('showOverLockscreen', {'show': show});
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.showOverLockscreen error: ${e.message}');
      return false;
    }
  }

  static Future<bool> hasCameraPermission() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasCameraPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Pide el permiso de cámara. Debe llamarse ANTES de fijar la pantalla:
  /// en modo lock task Android no muestra los diálogos de permisos.
  static Future<bool> requestCameraPermission() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestCameraPermission') ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.requestCameraPermission error: ${e.message}');
      return false;
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;
    } on PlatformException {
      return true;
    }
  }

  /// Abre el diálogo del sistema para excluir la app del ahorro de batería.
  /// Sin esto, muchas ROMs matan los recordatorios programados.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.requestIgnoreBatteryOptimizations error: ${e.message}');
      return false;
    }
  }

  /// Abre la ficha de la app en los ajustes del sistema (para reactivar
  /// permisos denegados de forma permanente, como la cámara).
  static Future<bool> openAppSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService.openAppSettings error: ${e.message}');
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
