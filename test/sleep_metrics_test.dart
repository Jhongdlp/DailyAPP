import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/sleep_model.dart';

/// Construye una noche que empieza el día anterior a [wakeDay] a las
/// [bedHour]:[bedMinute] y termina a las [wakeHour]:[wakeMinute].
SleepSession night(
  DateTime wakeDay, {
  int bedHour = 23,
  int bedMinute = 0,
  int wakeHour = 7,
  int wakeMinute = 0,
  int? quality,
  int? awakenings,
  int? latency,
  int? alarmHour,
  int? alarmMinute,
  bool ignored = false,
  bool woke = true,
}) {
  // Acostarse a partir de las 18:00 pertenece a la noche del día siguiente.
  final bedDay =
      bedHour >= 18 ? wakeDay.subtract(const Duration(days: 1)) : wakeDay;
  final alarm = alarmHour == null
      ? null
      : DateTime(wakeDay.year, wakeDay.month, wakeDay.day, alarmHour,
          alarmMinute ?? 0);
  return SleepSession(
    nightKey: sleepDayKey(wakeDay),
    lightsOutAt:
        DateTime(bedDay.year, bedDay.month, bedDay.day, bedHour, bedMinute),
    alarmScheduledAt: alarm,
    firstRingAt: alarm,
    wokeAt: woke
        ? DateTime(
            wakeDay.year, wakeDay.month, wakeDay.day, wakeHour, wakeMinute)
        : null,
    alarmIgnored: ignored,
    quality: quality,
    awakenings: awakenings,
    latencyMinutes: latency,
  );
}

void main() {
  final day = DateTime(2026, 7, 20); // lunes

  group('nightKeyFor', () {
    test('acostarse por la noche cuenta para el día siguiente', () {
      expect(nightKeyFor(DateTime(2026, 7, 20, 23, 40)), '2026-07-21');
    });

    test('acostarse de madrugada cuenta para el mismo día', () {
      expect(nightKeyFor(DateTime(2026, 7, 21, 1, 30)), '2026-07-21');
    });

    test('despertarse por la mañana cuenta para el mismo día', () {
      expect(nightKeyFor(DateTime(2026, 7, 21, 7, 0)), '2026-07-21');
    });
  });

  group('SleepSession', () {
    test('tiempo en cama y sueño estimado descuentan latencia y despertares', () {
      final s = night(day, awakenings: 2, latency: 20);
      expect(s.timeInBed, const Duration(hours: 8));
      // 480 - 20 de latencia - 2*8 por despertares
      expect(s.sleepMinutes, 480 - 20 - 16);
      expect(s.efficiency, closeTo((480 - 36) / 480, 0.0001));
    });

    test('sin check-in el sueño estimado es todo el tiempo en cama', () {
      expect(night(day).sleepMinutes, 480);
    });

    test('una noche imposible se descarta en vez de contaminar las medias', () {
      final corrupt = SleepSession(
        nightKey: sleepDayKey(day),
        lightsOutAt: DateTime(2026, 7, 19, 23),
        wokeAt: DateTime(2026, 7, 21, 7), // 32 h
      );
      expect(corrupt.timeInBed, isNull);
      expect(corrupt.sleepMinutes, isNull);
    });

    test('el punto medio se envuelve al cruzar medianoche', () {
      // 23:00 → 07:00, mitad a las 03:00
      expect(night(day).midpointMinutes, 180);
      // El dominio es (−720, 720], centrado en medianoche: todo lo posterior a
      // mediodía se expresa como negativo. 14:00 → −600.
      final nap = night(day, bedHour: 13, wakeHour: 15);
      expect(nap.midpointMinutes, 14 * 60 - 1440);
      // 22:00 → 00:20, mitad a las 23:10 → negativo
      final early = night(day, bedHour: 22, wakeHour: 0, wakeMinute: 20);
      expect(early.midpointMinutes, 23 * 60 + 10 - 1440);
    });

    test('snooze mide desde que sonó hasta que se validó la foto', () {
      final s = night(day, alarmHour: 6, alarmMinute: 30, wakeHour: 7);
      expect(s.snoozeMinutes, 30);
    });

    test('metBedtime da 15 minutos de gracia', () {
      final target = DateTime(2026, 7, 19, 23);
      SleepSession withLightsOut(DateTime at) => SleepSession(
            nightKey: sleepDayKey(day),
            bedtimeTarget: target,
            lightsOutAt: at,
          );
      expect(withLightsOut(DateTime(2026, 7, 19, 23, 10)).metBedtime, isTrue);
      expect(withLightsOut(DateTime(2026, 7, 19, 23, 15)).metBedtime, isTrue);
      expect(withLightsOut(DateTime(2026, 7, 19, 23, 40)).metBedtime, isFalse);
    });

    test('round-trip de JSON', () {
      final original = night(day, quality: 4, awakenings: 1, latency: 12);
      final copy = SleepSession.fromJson(original.toJson());
      expect(copy.nightKey, original.nightKey);
      expect(copy.lightsOutAt, original.lightsOutAt);
      expect(copy.wokeAt, original.wokeAt);
      expect(copy.quality, 4);
      expect(copy.sleepMinutes, original.sleepMinutes);
    });
  });

  group('SleepAnalytics', () {
    SleepAnalytics analytics(List<SleepSession> nights, {int goal = 480}) =>
        SleepAnalytics(nights: nights, goalMinutes: goal);

    test('la deuda solo suma déficits, dormir de más no compensa', () {
      final nights = [
        night(day, wakeHour: 5), // 6 h → −120
        night(day.add(const Duration(days: 1)), wakeHour: 10), // 11 h → +180
        night(day.add(const Duration(days: 2)), wakeHour: 6), // 7 h → −60
      ];
      expect(analytics(nights).sleepDebtMinutes, 180);
    });

    test('la deuda se topa en 20 h', () {
      final nights = [
        for (var i = 0; i < 14; i++)
          night(day.add(Duration(days: i)), wakeHour: 1), // 2 h cada noche
      ];
      expect(analytics(nights).sleepDebtMinutes, 20 * 60);
    });

    test('un horario constante da regularidad ~0 y grado bueno', () {
      final nights = [
        for (var i = 0; i < 7; i++) night(day.add(Duration(days: i))),
      ];
      final a = analytics(nights);
      expect(a.regularityMinutes, closeTo(0, 0.001));
      expect(a.regularityGrade, SleepGrade.good);
    });

    test('un horario que cruza medianoche no infla la regularidad', () {
      // Puntos medios a las 23:30 y a las 00:30: una hora de diferencia real.
      final nights = [
        night(day, bedHour: 21, wakeHour: 2), // medio ≈ 23:30
        night(day.add(const Duration(days: 1)), bedHour: 22, wakeHour: 3),
        night(day.add(const Duration(days: 2)), bedHour: 21, wakeHour: 2),
        night(day.add(const Duration(days: 3)), bedHour: 22, wakeHour: 3),
      ];
      // Sin envoltura esto daría cientos de minutos.
      expect(analytics(nights).regularityMinutes, lessThan(45));
    });

    test('regularidad necesita al menos 3 noches', () {
      expect(analytics([night(day), night(day.add(const Duration(days: 1)))])
          .regularityMinutes, isNull);
    });

    test('el jet lag social compara fin de semana contra entre semana', () {
      // Lun–vie a las 23:00; sáb y dom a la 01:00 (dos horas más tarde).
      final nights = <SleepSession>[
        for (var i = 0; i < 5; i++)
          night(day.add(Duration(days: i))), // mar..sáb? -> ver abajo
      ];
      // day = lunes 20 → las noches "de lunes a viernes" son 20..24 (lun–vie).
      final weekend = [
        night(DateTime(2026, 7, 25), bedHour: 1, wakeHour: 9), // sábado
        night(DateTime(2026, 7, 26), bedHour: 1, wakeHour: 9), // domingo
      ];
      final a = analytics([...nights, ...weekend]);
      expect(a.socialJetLagMinutes, closeTo(120, 1));
    });

    test('la duración óptima ignora bloques con menos de 3 noches', () {
      final nights = <SleepSession>[
        // 3 noches de 7 h con calidad 3
        for (var i = 0; i < 3; i++)
          night(day.add(Duration(days: i)), wakeHour: 6, quality: 3),
        // 3 noches de 8 h con calidad 5 → ganador
        for (var i = 3; i < 6; i++)
          night(day.add(Duration(days: i)), wakeHour: 7, quality: 5),
        // 1 noche de 10 h con calidad 5 → no llega al mínimo
        night(day.add(const Duration(days: 6)), wakeHour: 9, quality: 5),
      ];
      final best = analytics(nights).optimalDuration;
      expect(best, isNotNull);
      expect(best!.minutes, 480);
      expect(best.avgQuality, 5);
      expect(best.nights, 3);
    });

    test('la racha se corta con la primera noche por debajo de la meta', () {
      final nights = [
        night(day, wakeHour: 7), // 8 h ✓
        night(day.add(const Duration(days: 1)), wakeHour: 5), // 6 h ✗
        night(day.add(const Duration(days: 2)), wakeHour: 7), // 8 h ✓
        night(day.add(const Duration(days: 3)), wakeHour: 8), // 9 h ✓
      ];
      expect(analytics(nights).goalStreak, 2);
    });

    test('la tasa de ignoradas solo cuenta mañanas en las que sonó', () {
      final nights = [
        night(day, alarmHour: 6), // sonó y se apagó
        night(day.add(const Duration(days: 1)),
            alarmHour: 6, ignored: true, woke: false), // sonó e ignorada
        night(day.add(const Duration(days: 2))), // sin alarma
      ];
      expect(analytics(nights).ignoredRate, closeTo(0.5, 0.0001));
    });

    test('la media móvil de 7 días se alinea con las noches puntuables', () {
      final nights = [
        for (var i = 0; i < 3; i++)
          night(day.add(Duration(days: i)), wakeHour: 7),
      ];
      final avg = analytics(nights).rollingAverage7;
      expect(avg.length, 3);
      expect(avg.every((v) => (v - 480).abs() < 0.001), isTrue);
    });

    test('sin datos las métricas devuelven null en vez de reventar', () {
      final a = analytics(const []);
      expect(a.hasData, isFalse);
      expect(a.avg7, isNull);
      expect(a.regularityMinutes, isNull);
      expect(a.socialJetLagMinutes, isNull);
      expect(a.optimalDuration, isNull);
      expect(a.sleepDebtMinutes, 0);
      expect(a.goalStreak, 0);
    });
  });

  group('SleepSchedule', () {
    test('nextBedtime respeta los días activos', () {
      const schedule = SleepSchedule(
        enabled: true,
        bedtimeHour: 23,
        daysOfWeek: [6, 7], // solo fines de semana
      );
      final next = schedule.nextBedtime(from: DateTime(2026, 7, 20, 12)); // lunes
      expect(next, DateTime(2026, 7, 25, 23)); // sábado
    });

    test('deshabilitado no devuelve próxima hora', () {
      expect(const SleepSchedule().nextBedtime(), isNull);
    });

    test('confirmar de madrugada apunta al objetivo de la noche anterior', () {
      const schedule = SleepSchedule(enabled: true, bedtimeHour: 23);
      final target = schedule.bedtimeTargetFor(DateTime(2026, 7, 21, 1, 30));
      expect(target, DateTime(2026, 7, 20, 23));
    });
  });

  group('SleepData', () {
    test('lastNights mantiene los huecos para no descuadrar el eje', () {
      final today = DateTime.now();
      final key = sleepDayKey(today);
      final data = SleepData(sessions: {key: SleepSession(nightKey: key)});
      final days = data.lastNights(7);
      expect(days.length, 7);
      expect(days.last.session, isNotNull);
      expect(days.first.session, isNull);
    });

    test('round-trip de JSON conserva sesiones y noche abierta', () {
      final original = SleepData(
        schedule: const SleepSchedule(enabled: true, goalMinutes: 450),
        sessions: {sleepDayKey(day): night(day, quality: 5)},
        openNightKey: sleepDayKey(day),
        rewardedNights: [sleepDayKey(day)],
      );
      final copy = SleepData.fromJson(original.toJson());
      expect(copy.schedule.goalMinutes, 450);
      expect(copy.schedule.enabled, isTrue);
      expect(copy.sessions.length, 1);
      expect(copy.openNightKey, sleepDayKey(day));
      expect(copy.rewardedNights, [sleepDayKey(day)]);
    });
  });

  group('formatters', () {
    test('formatSleepMinutes', () {
      expect(formatSleepMinutes(null), '—');
      expect(formatSleepMinutes(45), '45 m');
      expect(formatSleepMinutes(480), '8 h');
      expect(formatSleepMinutes(440), '7 h 20 m');
    });

    test('formatClockMinutes desenvuelve los negativos', () {
      expect(formatClockMinutes(210), '03:30');
      expect(formatClockMinutes(-10), '23:50');
      expect(formatClockMinutes(null), '—');
    });
  });
}
