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

  static const notesChannelId = 'sistdaily_notes_v1';
  static const habitsChannelId = 'sistdaily_habits_v1';
  static const testChannelId = 'sistdaily_test_v1';

  /// Última zona horaria resuelta, para el panel de diagnóstico.
  static String timezoneName = 'desconocida';

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
      timezoneName = tzInfo.identifier;
    } catch (e) {
      // Si esto falla, tz.local queda en UTC y los recordatorios de hábitos
      // (que se construyen con hora de pared) se programarían corridos.
      timezoneName = 'UTC (fallo al detectar)';
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

    await _createChannels();
    await requestPermissions();

    _initialized = true;
  }

  /// Crea los canales por adelantado. Si se dejan crear implícitamente en el
  /// primer `zonedSchedule`, una notificación programada por una versión
  /// anterior con otra importancia deja el canal fijado con esa importancia.
  static Future<void> _createChannels() async {
    final androidImpl = _androidImpl;
    if (androidImpl == null) return;

    const channels = [
      AndroidNotificationChannel(
        notesChannelId,
        'Recordatorios de Notas',
        description: 'Recordatorios programados desde tus notas',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        habitsChannelId,
        'Recordatorios de Hábitos',
        description: 'Recordatorios diarios para cumplir tus hábitos',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        testChannelId,
        'Pruebas',
        description: 'Notificaciones de prueba del diagnóstico',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    ];

    for (final channel in channels) {
      try {
        await androidImpl.createNotificationChannel(channel);
      } catch (e) {
        debugPrint('AlarmService: createNotificationChannel ${channel.id} falló: $e');
      }
    }
  }

  /// Programa una notificación pidiendo alarma exacta y, si el sistema la
  /// deniega, reintenta en modo inexacto en vez de perder el recordatorio.
  ///
  /// Antes esto era un `zonedSchedule` suelto envuelto en un try/catch que
  /// sólo hacía `debugPrint`: cuando Android revocaba el permiso de alarmas
  /// exactas, no se programaba nada y no había forma de notarlo.
  static Future<void> zonedScheduleWithFallback({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    required String payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    Future<void> attempt(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: mode,
          matchDateTimeComponents: matchDateTimeComponents,
          payload: payload,
        );

    try {
      await attempt(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (e) {
      debugPrint('AlarmService: alarma exacta denegada ($e); reintento inexacto');
      try {
        await attempt(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e2) {
        debugPrint('AlarmService: schedule inexacto también falló: $e2');
      }
    }
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

  /// ¿Puede el sistema programar alarmas exactas? Si es `false`, los
  /// recordatorios caen a modo inexacto y pueden llegar con minutos de retraso.
  static Future<bool> canScheduleExactAlarms() async {
    try {
      return await _androidImpl?.canScheduleExactNotifications() ?? true;
    } catch (e) {
      debugPrint('AlarmService: canScheduleExactNotifications falló: $e');
      return false;
    }
  }

  /// Recordatorios que el sistema tiene realmente en cola, agrupados por
  /// origen según el prefijo del payload.
  static Future<NotificationDiagnostics> diagnose() async {
    var notes = 0;
    var habits = 0;
    var other = 0;
    try {
      for (final request in await _plugin.pendingNotificationRequests()) {
        final payload = request.payload ?? '';
        if (payload.startsWith('note:')) {
          notes++;
        } else if (payload.startsWith('habit:')) {
          habits++;
        } else {
          other++;
        }
      }
    } catch (e) {
      debugPrint('AlarmService: pendingNotificationRequests falló: $e');
    }

    return NotificationDiagnostics(
      notificationsEnabled: await areNotificationsEnabled(),
      exactAlarmsAllowed: await canScheduleExactAlarms(),
      timezone: timezoneName,
      pendingNotes: notes,
      pendingHabits: habits,
      pendingOther: other,
      scheduledAlarms: (await Alarm.getAlarms()).length,
    );
  }

  /// Dispara una notificación de prueba dentro de [delay] para comprobar de
  /// punta a punta que el sistema las entrega.
  static Future<void> scheduleTestNotification({
    Duration delay = const Duration(seconds: 15),
  }) async {
    await zonedScheduleWithFallback(
      id: 999999,
      title: '🔔 Notificación de prueba',
      body: 'Si ves esto, las notificaciones programadas funcionan.',
      when: tz.TZDateTime.now(tz.local).add(delay),
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          testChannelId,
          'Pruebas',
          channelDescription: 'Notificaciones de prueba del diagnóstico',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      payload: 'test:ping',
    );
  }
}

class NotificationDiagnostics {
  final bool notificationsEnabled;
  final bool exactAlarmsAllowed;
  final String timezone;
  final int pendingNotes;
  final int pendingHabits;
  final int pendingOther;
  final int scheduledAlarms;

  const NotificationDiagnostics({
    required this.notificationsEnabled,
    required this.exactAlarmsAllowed,
    required this.timezone,
    required this.pendingNotes,
    required this.pendingHabits,
    required this.pendingOther,
    required this.scheduledAlarms,
  });
}

