import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/sleep_model.dart';
import 'alarm_service.dart';

/// Notificaciones de la rutina de sueño: el aviso de "baja el ritmo", el de
/// "hora de dormir" (cuyo toque marca el inicio del ciclo) y las insistencias
/// si se ignora. Reutiliza el plugin ya inicializado por [AlarmService].
class SleepService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const channelId = AlarmService.sleepChannelId;
  static const _channelName = 'Rutina de Sueño';
  static const _channelDescription =
      'Aviso de hora de dormir y recordatorios de la rutina nocturna';

  /// Prefijo del payload para distinguirlo de alarmas/notas/hábitos/agenda.
  static const payloadPrefix = 'sleep:';
  static const windDownPayload = '${payloadPrefix}winddown';
  static const bedtimePayload = '${payloadPrefix}bedtime';
  static const nagPayload = '${payloadPrefix}nag';

  /// Acción que confirma el inicio del ciclo sin abrir la app.
  static const confirmActionId = 'action_sleep_now';

  // Rango reservado 400000–499999. Los demás servicios cancelan recalculando
  // ids a partir de un hash, así que solaparse con ellos hace que se borren
  // notificaciones entre sí sin ningún error visible.
  static int _windDownId(int weekday) => 400000 + weekday;
  static int _bedtimeId(int weekday) => 400100 + weekday;
  static int _nagId(int index) => 400200 + index;

  /// Minutos tras el bedtime en los que insiste si no se ha confirmado.
  static const nagOffsets = [15, 30, 45];

  static bool get _unsupported =>
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS);

  static NotificationDetails _details({List<AndroidNotificationAction>? actions}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: true,
        enableVibration: true,
        icon: AlarmService.notificationIcon,
        actions: actions,
      ),
    );
  }

  static const _confirmActions = [
    AndroidNotificationAction(
      confirmActionId,
      'Me voy a dormir',
      showsUserInterface: true,
    ),
  ];

  /// Reprograma toda la rutina a partir de [schedule]. Idempotente: cancela lo
  /// anterior antes de programar, así que se puede llamar en cada arranque.
  static Future<void> reschedule(SleepSchedule schedule) async {
    try {
      await cancelAll();
      if (_unsupported) return;
      if (!schedule.enabled || schedule.daysOfWeek.isEmpty) return;

      final futures = <Future<void>>[];

      for (final day in schedule.daysOfWeek) {
        final bedtime =
            _nextOccurrence(day, schedule.bedtimeHour, schedule.bedtimeMinute);

        if (schedule.windDownMinutes > 0) {
          final windDown =
              bedtime.subtract(Duration(minutes: schedule.windDownMinutes));
          futures.add(AlarmService.zonedScheduleWithFallback(
            id: _windDownId(day),
            title: '🌙 Empieza a bajar el ritmo',
            body: 'Te toca dormir en ${schedule.windDownMinutes} min. '
                'Baja luces y suelta las pantallas.',
            when: windDown,
            details: _details(),
            payload: windDownPayload,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          ));
        }

        futures.add(AlarmService.zonedScheduleWithFallback(
          id: _bedtimeId(day),
          title: '😴 Hora de dormir',
          body: 'Toca aquí justo antes de soltar el móvil: '
              'así empieza tu ciclo de sueño.',
          when: bedtime,
          details: _details(actions: _confirmActions),
          payload: bedtimePayload,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        ));
      }

      await Future.wait(futures);
      await scheduleNags(schedule);
    } catch (e) {
      debugPrint('SleepService: reschedule falló: $e');
    }
  }

  /// Programa las insistencias de la **próxima** noche solamente.
  ///
  /// No pueden repetirse semanalmente como el aviso principal: al confirmar el
  /// bedtime hay que borrarlas, y cancelar una notificación semanal la mataría
  /// también para las semanas siguientes. Como one-shot, se cancelan hoy y se
  /// vuelven a programar para la noche siguiente.
  static Future<void> scheduleNags(SleepSchedule schedule) async {
    try {
      if (_unsupported) return;
      if (!schedule.enabled || !schedule.nagEnabled) return;

      final bedtime = schedule.nextBedtime();
      if (bedtime == null) return;

      final futures = <Future<void>>[];
      for (var i = 0; i < nagOffsets.length; i++) {
        final when = tz.TZDateTime.from(
          bedtime.add(Duration(minutes: nagOffsets[i])),
          tz.local,
        );
        if (!when.isAfter(tz.TZDateTime.now(tz.local))) continue;
        futures.add(AlarmService.zonedScheduleWithFallback(
          id: _nagId(i),
          title: '🌙 Sigues despierto',
          body: 'Llevas ${nagOffsets[i]} min de más. '
              'Cada noche corta se paga al día siguiente.',
          when: when,
          details: _details(actions: _confirmActions),
          payload: nagPayload,
        ));
      }
      await Future.wait(futures);
    } catch (e) {
      debugPrint('SleepService: scheduleNags falló: $e');
    }
  }

  /// Borra las insistencias pendientes de esta noche. Se llama al confirmar
  /// el bedtime.
  static Future<void> cancelNags() async {
    try {
      if (_unsupported) return;
      await Future.wait([
        for (var i = 0; i < nagOffsets.length; i++) _plugin.cancel(_nagId(i)),
      ]);
    } catch (e) {
      debugPrint('SleepService: cancelNags falló: $e');
    }
  }

  static Future<void> cancelAll() async {
    try {
      if (_unsupported) return;
      final futures = <Future<void>>[];
      for (var day = 1; day <= 7; day++) {
        futures.add(_plugin.cancel(_windDownId(day)));
        futures.add(_plugin.cancel(_bedtimeId(day)));
      }
      for (var i = 0; i < nagOffsets.length; i++) {
        futures.add(_plugin.cancel(_nagId(i)));
      }
      await Future.wait(futures);
    } catch (e) {
      debugPrint('SleepService: cancelAll falló: $e');
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
