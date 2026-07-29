import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'alarm_service.dart';

/// Aviso diario para sentarse a planear el día siguiente.
///
/// Es una sola notificación recurrente, no una por bloque: lo que queremos
/// crear es el hábito de planear, y para eso basta con un empujón a la misma
/// hora cada noche.
class NightPlanningService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const channelId = AlarmService.tasksChannelId;
  static const _channelName = 'Recordatorios de Agenda';

  /// Payload que abre directamente el ritual, sin pasar por la Agenda.
  static const payload = 'plan:tomorrow';

  /// Bloque 500000–599999. Los servicios de esta app cancelan **recalculando**
  /// IDs a partir de un hash, no leyendo la cola, así que dos servicios en el
  /// mismo rango se borran las notificaciones entre sí. Este es el siguiente
  /// bloque libre tras TaskReminderService (400000–499999).
  static const _notifId = 500000;

  static bool get _unsupportedPlatform =>
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS);

  /// Programa (o reprograma) el aviso nocturno diario a [hour]:[minute].
  static Future<void> schedule({required int hour, required int minute}) async {
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
        title: '🌙 Planea mañana',
        body: 'Dos minutos ahora te ahorran el día entero de improvisar.',
        when: _nextOccurrence(hour, minute),
        details: details,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Error scheduling night planning reminder: $e');
    }
  }

  static Future<void> cancel() async {
    try {
      if (_unsupportedPlatform) return;
      await _plugin.cancel(_notifId);
    } catch (e) {
      debugPrint('Error canceling night planning reminder: $e');
    }
  }

  static tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }
}
