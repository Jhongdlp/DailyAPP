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
      final remindAt = note.remindAt;
      if (remindAt == null || !remindAt.isAfter(DateTime.now())) return;

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
