import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/day_plan_model.dart';

DateTime _day(int daysFromToday) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.add(Duration(days: daysFromToday));
}

void main() {
  group('DayPlan serialización', () {
    test('el ida y vuelta por caché conserva todos los campos', () {
      final original = DayPlan(
        id: 'abc',
        planDate: DateTime(2026, 7, 30),
        intention: 'tranquilo',
        reflection: 'día duro',
        mood: 4,
        ritualCompleted: true,
        plannedAt: DateTime(2026, 7, 29, 21, 40),
      );

      final restored = DayPlan.fromCacheJson(original.toCacheJson());

      expect(restored.id, original.id);
      expect(restored.planDate, original.planDate);
      expect(restored.intention, original.intention);
      expect(restored.reflection, original.reflection);
      expect(restored.mood, original.mood);
      expect(restored.ritualCompleted, original.ritualCompleted);
      expect(restored.plannedAt, original.plannedAt);
    });

    test('fromJson normaliza plan_date a medianoche', () {
      final plan = DayPlan.fromJson({
        'id': 'x',
        'plan_date': '2026-07-30',
        'ritual_completed': false,
        'planned_at': '2026-07-29T20:00:00Z',
      });
      expect(plan.planDate, DateTime(2026, 7, 30));
      expect(plan.mood, isNull);
    });

    test('toUpsertJson escribe la fecha como YYYY-MM-DD y la hora en UTC', () {
      final json = DayPlan(
        id: 'x',
        planDate: DateTime(2026, 1, 5),
        plannedAt: DateTime.utc(2026, 1, 4, 22, 0),
      ).toUpsertJson('user-1');

      expect(json['plan_date'], '2026-01-05');
      expect(json['user_id'], 'user-1');
      expect(json['planned_at'], '2026-01-04T22:00:00.000Z');
    });

    test('copyWith puede limpiar campos opcionales', () {
      final plan = DayPlan(
        id: 'x',
        planDate: _day(1),
        mood: 3,
        intention: 'algo',
        plannedAt: DateTime.now(),
      );
      final cleared = plan.copyWith(clearMood: true, clearIntention: true);
      expect(cleared.mood, isNull);
      expect(cleared.intention, isNull);
      // Lo no tocado sobrevive.
      expect(cleared.planDate, plan.planDate);
    });
  });
}
