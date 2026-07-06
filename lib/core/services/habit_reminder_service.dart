import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/habit_model.dart';

/// Notificaciones diarias repetidas para recordar hábitos con meta (ej. "Tomar 2L de agua a mediodía").
/// Reutiliza el plugin ya inicializado por AlarmService en main.dart.
class HabitReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'sistdaily_habits_v1';
  static const _channelName = 'Recordatorios de Hábitos';

  /// Prefijo del payload para distinguir hábitos de alarmas/notas al tocar la notificación.
  static const payloadPrefix = 'habit:';

  // Rango 200000–299999 para no chocar con AlarmService (0–99999) ni NoteReminderService (100000–199999)
  static int _legacyNotifId(String habitId, int day) =>
      200000 + ('${habitId}_$day'.hashCode.abs() % 100000);

  static int _notifId(String habitId, int day, int timeIndex) =>
      200000 + ('${habitId}_${day}_$timeIndex'.hashCode.abs() % 100000);

  static Future<void> scheduleReminder(Habit habit) async {
    await cancelReminder(habit.id);
    if (!habit.hasReminder || habit.archived || habit.daysOfWeek.isEmpty) return;

    final goal = habit.goalLabel;
    final body = goal == null ? 'Toca para marcarlo como completado hoy' : 'Meta de hoy: $goal';

    List<AndroidNotificationAction>? actions;
    if (habit.goalValue != null) {
      String actionLabel = 'Registrar';
      final unit = habit.goalUnit?.toLowerCase() ?? '';
      if (unit == 'l') {
        actionLabel = '+0.25 L';
      } else if (unit == 'ml') {
        actionLabel = '+250 ml';
      } else if (unit == 'pasos' || unit == 'steps') {
        actionLabel = '+1000';
      } else if (unit == 'min' || unit == 'minutos') {
        actionLabel = '+5 min';
      }
      actions = [
        AndroidNotificationAction(
          'action_increment_progress',
          actionLabel,
          showsUserInterface: true,
        ),
      ];
    } else {
      actions = [
        const AndroidNotificationAction(
          'action_complete_habit',
          'Completar',
          showsUserInterface: true,
        ),
      ];
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Recordatorios diarios para cumplir tus hábitos',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: true,
        enableVibration: true,
        actions: actions,
      ),
    );

    final futures = <Future<void>>[];

    if (habit.reminderTimes.isNotEmpty) {
      for (int timeIdx = 0; timeIdx < habit.reminderTimes.length; timeIdx++) {
        final timeStr = habit.reminderTimes[timeIdx];
        final parts = timeStr.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);

        for (final day in habit.daysOfWeek) {
          futures.add(_plugin.zonedSchedule(
            _notifId(habit.id, day, timeIdx),
            '${habit.icon} ${habit.name}',
            body,
            _nextOccurrence(day, hour, minute),
            details,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: '$payloadPrefix${habit.id}',
          ));
        }
      }
    } else if (habit.reminderHour != null && habit.reminderMinute != null) {
      for (final day in habit.daysOfWeek) {
        futures.add(_plugin.zonedSchedule(
          _legacyNotifId(habit.id, day),
          '${habit.icon} ${habit.name}',
          body,
          _nextOccurrence(day, habit.reminderHour!, habit.reminderMinute!),
          details,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: '$payloadPrefix${habit.id}',
        ));
      }
    }

    await Future.wait(futures);
  }

  static Future<void> cancelReminder(String habitId) async {
    final futures = <Future<void>>[];
    for (int day = 1; day <= 7; day++) {
      for (int timeIdx = 0; timeIdx < 15; timeIdx++) {
        futures.add(_plugin.cancel(_notifId(habitId, day, timeIdx)));
      }
      futures.add(_plugin.cancel(_legacyNotifId(habitId, day)));
    }
    await Future.wait(futures);
  }

  static Future<void> rescheduleAll(List<Habit> habits) async {
    for (final habit in habits) {
      await scheduleReminder(habit);
    }
  }

  static tz.TZDateTime _nextOccurrence(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
