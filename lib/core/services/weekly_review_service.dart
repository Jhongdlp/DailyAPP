import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'alarm_service.dart';

/// Aviso semanal para sentarse a revisar la semana.
///
/// Uno solo y recurrente, como el aviso nocturno: lo que se quiere crear es el
/// hábito de revisar, y para eso basta con un empujón el mismo día a la misma
/// hora. Cae en domingo por la tarde por defecto, cuando la semana ya se puede
/// juzgar entera pero todavía se está a tiempo de decidir la siguiente.
class WeeklyReviewService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const channelId = AlarmService.tasksChannelId;
  static const _channelName = 'Recordatorios de Agenda';

  /// Payload que abre directamente el ritual.
  static const payload = 'review:week';

  /// Bloque 600000–699999. Los servicios de esta app cancelan **recalculando**
  /// IDs a partir de un hash, no leyendo la cola, así que dos servicios en el
  /// mismo rango se borran las notificaciones entre sí. Este es el siguiente
  /// bloque libre tras NightPlanningService (500000–599999).
  static const _notifId = 600000;

  /// Domingo a las 19:00.
  static const defaultWeekday = DateTime.sunday;
  static const defaultHour = 19;
  static const defaultMinute = 0;

  static bool get _unsupportedPlatform =>
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS);

  /// Programa (o reprograma) el aviso semanal.
  static Future<void> schedule({
    int weekday = defaultWeekday,
    int hour = defaultHour,
    int minute = defaultMinute,
  }) async {
    try {
      await cancel();
      if (_unsupportedPlatform) return;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelName,
          channelDescription: 'Recordatorios programados desde tu agenda',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          playSound: true,
          enableVibration: true,
          icon: AlarmService.notificationIcon,
        ),
      );

      await AlarmService.zonedScheduleWithFallback(
        id: _notifId,
        title: '📊 Revisa tu semana',
        body: 'Cinco minutos para ver qué funcionó y decidir la que viene.',
        when: _nextOccurrence(weekday, hour, minute),
        details: details,
        payload: payload,
        // Repite el mismo día de la semana a la misma hora.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      debugPrint('Error scheduling weekly review reminder: $e');
    }
  }

  static Future<void> cancel() async {
    try {
      if (_unsupportedPlatform) return;
      await _plugin.cancel(_notifId);
    } catch (e) {
      debugPrint('Error canceling weekly review reminder: $e');
    }
  }

  static tz.TZDateTime _nextOccurrence(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // Avanza hasta el primer día de la semana que toque; si hoy es ese día pero
    // la hora ya pasó, se va a la semana siguiente.
    while (when.weekday != weekday || !when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    return when;
  }
}
