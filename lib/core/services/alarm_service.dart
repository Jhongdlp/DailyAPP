import 'package:alarm/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/alarm_model.dart';

class AlarmService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize({
    required void Function(NotificationResponse) onNotificationTap,
  }) async {
    if (_initialized) return;

    // Inicializar el paquete de alarmas genuinas
    await Alarm.init();

    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
  }

  static Future<NotificationAppLaunchDetails?> getLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  static Future<void> scheduleAlarm(AlarmModel alarm, {DateTime? from}) async {
    await cancelAlarm(alarm.id);
    if (!alarm.enabled || alarm.daysOfWeek.isEmpty) return;

    final next = alarm.nextTrigger(from: from);
    if (next == null) return;

    final alarmSettings = AlarmSettings(
      id: alarm.id.hashCode.abs() % 100000,
      dateTime: next,
      assetAudioPath: null, // usa sonido por defecto del sistema
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: true,
      volumeSettings: VolumeSettings.fixed(
        volume: 1.0,
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: '⏰ ${alarm.label}',
        body: 'Fotografía "${alarm.targetObject}" para desactivar',
        icon: 'notification_icon',
      ),
      androidFullScreenIntent: true,
    );

    await Alarm.set(alarmSettings: alarmSettings);
  }

  static Future<void> cancelAlarm(String alarmId) async {
    final idInt = alarmId.hashCode.abs() % 100000;
    await Alarm.stop(idInt);
  }

  static Future<void> rescheduleAll(List<AlarmModel> alarms) async {
    final activeAlarms = await Alarm.getAlarms();
    for (final settings in activeAlarms) {
      await Alarm.stop(settings.id);
    }
    await Future.wait(alarms.map((alarm) => scheduleAlarm(alarm)));
  }
}

