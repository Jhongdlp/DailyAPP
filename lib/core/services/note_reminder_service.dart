import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/note_model.dart';

/// Notificaciones one-shot para recordatorios de notas.
/// Reutiliza el plugin ya inicializado por AlarmService en main.dart.
class NoteReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'sistdaily_notes_v1';
  static const _channelName = 'Recordatorios de Notas';

  /// Prefijo del payload para distinguir notas de alarmas al tocar la notificación.
  static const payloadPrefix = 'note:';

  // Rango 100000–199999 para no chocar con los IDs de AlarmService (0–99999)
  static int _notifId(String noteId) =>
      100000 + (noteId.hashCode.abs() % 100000);

  static Future<void> scheduleReminder(Note note) async {
    try {
      await cancelReminder(note.id);
      if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
        return;
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Recordatorios programados desde tus notas',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(note.content),
        ),
      );

      final body = note.content.isEmpty ? 'Toca para ver la nota' : note.content;
      final prefix = note.selfDestruct ? '💣' : '📌';

      // 1. Recordatorio único (One-shot)
      final remindAt = note.remindAt;
      if (remindAt != null && remindAt.isAfter(DateTime.now())) {
        await _plugin.zonedSchedule(
          _notifId(note.id),
          '$prefix ${note.title}',
          body,
          tz.TZDateTime.from(remindAt, tz.local),
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: '$payloadPrefix${note.id}',
        );
      }

      // 2. Recordatorio por rango de días
      if (note.hasRangeReminder) {
        final start = note.reminderStartDate!;
        final end = note.reminderEndDate!;
        final hour = note.reminderHour!;
        final minute = note.reminderMinute!;

        final daysCount = end.difference(start).inDays + 1;
        final maxDays = daysCount.clamp(1, 31); // Máximo 31 días seguidos

        for (int i = 0; i < maxDays; i++) {
          final day = start.add(Duration(days: i));
          final scheduledTime = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minute,
          );

          if (scheduledTime.isAfter(DateTime.now()) && !scheduledTime.isAfter(end.add(const Duration(days: 1)))) {
            await _plugin.zonedSchedule(
              200000 + ((note.id.hashCode.abs() + i) % 100000),
              '$prefix ${note.title}',
              body,
              tz.TZDateTime.from(scheduledTime, tz.local),
              details,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              payload: '$payloadPrefix${note.id}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error scheduling note reminder: $e');
    }
  }

  static Future<void> cancelReminder(String noteId) async {
    try {
      if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
        return;
      }
      await _plugin.cancel(_notifId(noteId));
      for (int i = 0; i < 31; i++) {
        await _plugin.cancel(200000 + ((noteId.hashCode.abs() + i) % 100000));
      }
    } catch (e) {
      debugPrint('Error canceling note reminder: $e');
    }
  }

  static Future<void> rescheduleAll(List<Note> notes) async {
    for (final note in notes) {
      if (note.isReminderPending) {
        await scheduleReminder(note);
      }
    }
  }
}
