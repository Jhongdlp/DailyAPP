import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/alarm_model.dart';

AlarmModel alarm({
  int wakeHour = 7,
  int wakeMinute = 0,
  int? bedHour,
  int? bedMinute = 0,
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
}) {
  return AlarmModel(
    id: 'a1',
    userId: '',
    enabled: true,
    hour: wakeHour,
    minute: wakeMinute,
    targetObject: 'Taza de café',
    label: 'Horario de sueño',
    daysOfWeek: days,
    createdAt: DateTime(2026, 1, 1),
    bedtimeHour: bedHour,
    bedtimeMinute: bedHour == null ? null : bedMinute,
  );
}

void main() {
  group('isSleepAlarm', () {
    test('sin hora de dormir es una alarma normal', () {
      final a = alarm();
      expect(a.isSleepAlarm, isFalse);
      expect(a.sleepWindowMinutes, isNull);
      expect(a.nextBedtime(), isNull);
    });

    test('con hora de dormir es horario de sueño', () {
      final a = alarm(bedHour: 23);
      expect(a.isSleepAlarm, isTrue);
      expect(a.formattedBedtime, '23:00');
      expect(a.bedtime12, '11:00');
      expect(a.bedtimeAmPm, 'PM');
    });

    test('clearBedtime lo degrada a alarma normal', () {
      expect(alarm(bedHour: 23).copyWith(clearBedtime: true).isSleepAlarm,
          isFalse);
    });
  });

  group('ventana de sueño', () {
    test('cruzando medianoche', () {
      expect(alarm(bedHour: 23, wakeHour: 7).sleepWindowMinutes, 8 * 60);
      expect(alarm(bedHour: 23, wakeHour: 7).sleepWindowLabel, '8 h');
    });

    test('con minutos sueltos', () {
      final a = alarm(bedHour: 23, bedMinute: 30, wakeHour: 7);
      expect(a.sleepWindowMinutes, 7 * 60 + 30);
      expect(a.sleepWindowLabel, '7 h 30 min');
    });

    test('acostándose después de medianoche', () {
      expect(alarm(bedHour: 1, wakeHour: 9).sleepWindowMinutes, 8 * 60);
    });

    test('horas iguales cuentan como 24 h, no como 0', () {
      // Es un dato absurdo, pero devolver 0 haría que la UI dijera "0 h en la
      // cama" en vez de delatar que el horario está mal puesto.
      expect(alarm(bedHour: 7, wakeHour: 7).sleepWindowMinutes, 1440);
    });
  });

  group('nextBedtime', () {
    // 2026-07-20 es lunes.
    test('los días marcados son los del despertar', () {
      // Horario que solo despierta el martes: hay que acostarse el lunes.
      final a = alarm(bedHour: 23, wakeHour: 7, days: [2]);
      expect(
        a.nextBedtime(from: DateTime(2026, 7, 20, 20)),
        DateTime(2026, 7, 20, 23),
      );
    });

    test('sin cruzar medianoche el día de acostarse es el del despertar', () {
      // Acostarse a la 01:00 y despertar a las 09:00 del sábado.
      final a = alarm(bedHour: 1, wakeHour: 9, days: [6]);
      expect(
        a.nextBedtime(from: DateTime(2026, 7, 24, 22)), // viernes noche
        DateTime(2026, 7, 25, 1), // sábado de madrugada
      );
    });

    test('pasada la hora de hoy salta a la siguiente ocurrencia', () {
      final a = alarm(bedHour: 23, wakeHour: 7, days: [2]);
      // Ya son las 23:30 del lunes: la próxima es la del martes al miércoles,
      // que no toca, así que el siguiente martes.
      expect(
        a.nextBedtime(from: DateTime(2026, 7, 20, 23, 30)),
        DateTime(2026, 7, 27, 23),
      );
    });

    test('sin días no hay próxima hora', () {
      expect(alarm(bedHour: 23, days: const []).nextBedtime(), isNull);
    });
  });

  group('persistencia', () {
    test('round-trip conserva la hora de dormir', () {
      final original = alarm(bedHour: 23, bedMinute: 45, wakeHour: 6);
      final copy = AlarmModel.fromJson(original.toJson());
      expect(copy.isSleepAlarm, isTrue);
      expect(copy.bedtimeHour, 23);
      expect(copy.bedtimeMinute, 45);
      expect(copy.sleepWindowMinutes, original.sleepWindowMinutes);
    });

    test('una alarma vieja sin los campos nuevos sigue leyéndose', () {
      final json = alarm().toJson()
        ..remove('bedtime_hour')
        ..remove('bedtime_minute');
      final copy = AlarmModel.fromJson(json);
      expect(copy.isSleepAlarm, isFalse);
      expect(copy.hour, 7);
    });
  });
}
