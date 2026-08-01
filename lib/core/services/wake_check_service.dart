import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

import '../models/sleep_model.dart';

/// Verificación de vigilia: la alarma que vuelve a sonar un rato después de
/// apagar la de despertar, para comprobar que no te has vuelto a dormir.
///
/// Usa el paquete `alarm` y no una notificación a propósito: una notificación
/// silenciada por el modo no molestar, o simplemente no vista, no despierta a
/// nadie. Aquí hace falta sonido en bucle y pantalla completa, igual que la
/// alarma original.
class WakeCheckService {
  /// Id nativo de la comprobación. Se deriva del id de la alarma con un sufijo
  /// para que **nunca** coincida con el de la alarma en sí: si colisionaran,
  /// programar la comprobación mataría la alarma del día siguiente.
  static int nativeIdFor(String alarmId) =>
      '$alarmId:wakecheck'.hashCode.abs() % 100000;

  /// Programa la comprobación número [round] para dentro de [interval].
  ///
  /// Devuelve el descriptor a guardar en el estado, o `null` si no se pudo
  /// programar (en cuyo caso no debe quedar nada pendiente: mejor sin
  /// comprobación que con una fantasma que el usuario no puede parar).
  static Future<PendingWakeCheck?> schedule({
    required String alarmId,
    required String nightKey,
    required DateTime wokeAt,
    required int round,
    required Duration interval,
  }) async {
    final nativeId = nativeIdFor(alarmId);
    final dueAt = DateTime.now().add(interval);

    try {
      await Alarm.stop(nativeId);
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: nativeId,
          dateTime: dueAt,
          assetAudioPath: null,
          loopAudio: true,
          vibrate: true,
          warningNotificationOnKill: false,
          androidStopAlarmOnTermination: false,
          volumeSettings: const VolumeSettings.fixed(
            volume: 1.0,
            volumeEnforced: true,
          ),
          notificationSettings: const NotificationSettings(
            title: '👀 ¿Sigues despierto?',
            body: 'Confirma que no te has vuelto a dormir',
            icon: 'notification_icon',
          ),
          androidFullScreenIntent: true,
        ),
      );
    } catch (e) {
      debugPrint('WakeCheckService: no pude programar la comprobación: $e');
      return null;
    }

    return PendingWakeCheck(
      alarmId: alarmId,
      nativeId: nativeId,
      nightKey: nightKey,
      dueAt: dueAt,
      wokeAt: wokeAt,
      round: round,
    );
  }

  /// Para la comprobación (esté sonando o solo programada).
  static Future<void> cancel(int nativeId) async {
    try {
      await Alarm.stop(nativeId);
    } catch (e) {
      debugPrint('WakeCheckService: no pude cancelar la comprobación: $e');
    }
  }

  /// ¿Está sonando ahora mismo?
  static Future<bool> isRinging(int nativeId) async {
    try {
      return await Alarm.isRinging(nativeId);
    } catch (_) {
      return false;
    }
  }
}
