import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/alarm_model.dart';

class AlarmService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static AndroidFlutterLocalNotificationsPlugin? get _androidImpl => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> initialize({
    required void Function(NotificationResponse) onNotificationTap,
  }) async {
    if (_initialized) return;

    // Cada paso se protege por separado: un fallo en uno (p.ej. timezone)
    // no debe impedir que se soliciten los permisos de notificación.
    try {
      // Inicializar el paquete de alarmas genuinas
      await Alarm.init();
    } catch (e) {
      debugPrint('AlarmService: Alarm.init falló: $e');
    }

    try {
      tz_data.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (e) {
      debugPrint('AlarmService: timezone falló: $e');
    }

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onNotificationTap,
      );
    } catch (e) {
      debugPrint('AlarmService: plugin.initialize falló: $e');
    }

    await requestPermissions();

    _initialized = true;
  }

  /// Solicita todos los permisos necesarios para que las alarmas funcionen.
  /// Devuelve `true` si las notificaciones están habilitadas al terminar.
  static Future<bool> requestPermissions() async {
    final androidImpl = _androidImpl;
    if (androidImpl == null) return true;

    try {
      await androidImpl.requestNotificationsPermission();
    } catch (e) {
      debugPrint('AlarmService: requestNotificationsPermission falló: $e');
    }
    try {
      await androidImpl.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('AlarmService: requestExactAlarmsPermission falló: $e');
    }
    try {
      // Android 14+ restringe USE_FULL_SCREEN_INTENT; sin él, la pantalla
      // de la alarma no se abre con la app cerrada/bloqueada.
      await androidImpl.requestFullScreenIntentPermission();
    } catch (e) {
      debugPrint('AlarmService: requestFullScreenIntentPermission falló: $e');
    }

    return areNotificationsEnabled();
  }

  /// Comprueba si el usuario tiene las notificaciones habilitadas.
  static Future<bool> areNotificationsEnabled() async {
    try {
      return await _androidImpl?.areNotificationsEnabled() ?? true;
    } catch (e) {
      debugPrint('AlarmService: areNotificationsEnabled falló: $e');
      return true;
    }
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
      // El usuario puede intentar apagar la alarma cerrando la app desde
      // "recientes" mientras suena. Sin esto, el servicio nativo la detiene
      // en onTaskRemoved (comportamiento por defecto del paquete `alarm`).
      androidStopAlarmOnTermination: false,
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

