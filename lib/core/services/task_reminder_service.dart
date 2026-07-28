import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/task_model.dart';
import 'alarm_service.dart';

/// Notificaciones one-shot para recordatorios de tareas de la Agenda.
/// Reutiliza el plugin ya inicializado por AlarmService en main.dart.
class TaskReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const channelId = AlarmService.tasksChannelId;
  static const _channelName = 'Recordatorios de Agenda';

  /// Prefijo del payload para distinguir tareas de alarmas/notas/hábitos al tocar la notificación.
  static const payloadPrefix = 'task:';

  // Rango 400000–499999: próximo bloque libre tras AlarmService (0-99999),
  // NoteReminderService (100000-199999, 300000-399999) y HabitReminderService
  // (200000-299999).
  static int _notifId(String taskId) => 400000 + (taskId.hashCode.abs() % 100000);

  static Future<void> scheduleReminder(Task task) async {
    try {
      await cancelReminder(task.id);
      if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
        return;
      }

      final remindAt = task.remindAt;
      if (remindAt == null || !remindAt.isAfter(DateTime.now())) return;

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

      final body = task.notes == null || task.notes!.isEmpty ? 'Toca para ver el bloque de tu agenda' : task.notes!;

      await AlarmService.zonedScheduleWithFallback(
        id: _notifId(task.id),
        title: '🗓️ ${task.title}',
        body: body,
        when: tz.TZDateTime.from(remindAt, tz.local),
        details: details,
        payload: '$payloadPrefix${task.id}',
      );
    } catch (e) {
      debugPrint('Error scheduling task reminder: $e');
    }
  }

  static Future<void> cancelReminder(String taskId) async {
    try {
      if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
        return;
      }
      await _plugin.cancel(_notifId(taskId));
    } catch (e) {
      debugPrint('Error canceling task reminder: $e');
    }
  }

  static Future<void> rescheduleAll(List<Task> tasks) async {
    for (final task in tasks) {
      if (task.hasReminder && !task.completed) {
        await scheduleReminder(task);
      }
    }
  }
}
