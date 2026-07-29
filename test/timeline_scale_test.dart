import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/task_model.dart';
import 'package:sistem_daily/features/agenda/timeline_scale.dart';

Task _task(String id, int startHour, int startMin, {int? endHour, int? endMin}) {
  final day = DateTime(2026, 7, 30);
  return Task(
    id: id,
    title: id,
    dueDate: day,
    startAt: DateTime(day.year, day.month, day.day, startHour, startMin),
    endAt: endHour == null ? null : DateTime(day.year, day.month, day.day, endHour, endMin ?? 0),
  );
}

void main() {
  group('TimelineScale sin plegado', () {
    const scale = TimelineScale(hourHeight: 72);

    test('la hora en punto cae exactamente sobre su línea de rejilla', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(scale.yForMinutes(hour * 60), hour * 72.0, reason: 'hora $hour');
      }
    });

    test('los minutos se escalan, no se usan como píxeles', () {
      // El bug original: 23:00 daba 1380 (los minutos crudos) en vez de 1656.
      expect(scale.yForMinutes(23 * 60), 1656.0);
      expect(scale.yForMinutes(30), 36.0);
    });

    test('minutesForY es la inversa de yForMinutes', () {
      for (final m in [0, 15, 90, 375, 720, 1439]) {
        expect(scale.minutesForY(scale.yForMinutes(m)), m);
      }
    });

    test('el alto total cubre el día completo', () {
      expect(scale.totalHeight, 24 * 72.0);
    });
  });

  group('TimelineScale con madrugada plegada', () {
    const scale = TimelineScale(hourHeight: 72, collapseUntilHour: 6, collapsedHeight: 44);

    test('la banda plegada comprime las primeras horas', () {
      expect(scale.yForMinutes(0), 0.0);
      expect(scale.yForMinutes(6 * 60), 44.0);
      expect(scale.yForMinutes(3 * 60), 22.0);
    });

    test('después de la banda la escala vuelve a ser la normal', () {
      expect(scale.yForMinutes(7 * 60), 44.0 + 72.0);
      expect(scale.yForMinutes(12 * 60), 44.0 + 6 * 72.0);
    });

    test('plegar acorta el día en las horas ocultas menos la banda', () {
      expect(scale.totalHeight, 44.0 + 18 * 72.0);
    });

    test('minutesForY sigue siendo la inversa a ambos lados de la banda', () {
      for (final m in [0, 180, 360, 420, 900, 1439]) {
        expect(scale.minutesForY(scale.yForMinutes(m)), closeTo(m, 1));
      }
    });
  });

  group('snap', () {
    test('redondea al cuarto de hora más cercano', () {
      expect(TimelineScale.snap(0), 0);
      expect(TimelineScale.snap(7), 0);
      expect(TimelineScale.snap(8), 15);
      expect(TimelineScale.snap(22), 15);
      expect(TimelineScale.snap(23), 30);
      expect(TimelineScale.snap(1439), 1440);
    });
  });

  group('endMinutesOf', () {
    test('un bloque sin fin ocupa la duración por defecto', () {
      expect(endMinutesOf(_task('a', 9, 0)), 9 * 60 + 40);
    });

    test('un bloque con fin usa su fin real', () {
      expect(endMinutesOf(_task('a', 9, 0, endHour: 10, endMin: 30)), 10 * 60 + 30);
    });

    test('un bloque que cruza medianoche se corta a las 24:00', () {
      final day = DateTime(2026, 7, 30);
      final t = Task(
        id: 'a',
        title: 'a',
        dueDate: day,
        startAt: DateTime(2026, 7, 30, 23, 0),
        endAt: DateTime(2026, 7, 31, 1, 0),
      );
      expect(endMinutesOf(t), TimelineScale.minutesPerDay);
    });
  });

  group('layoutBlocks', () {
    test('bloques que no se tocan ocupan el ancho completo', () {
      final out = layoutBlocks([
        _task('a', 9, 0, endHour: 10),
        _task('b', 11, 0, endHour: 12),
      ]);
      expect(out.every((b) => b.laneCount == 1 && b.lane == 0), isTrue);
    });

    test('dos bloques solapados se reparten en dos carriles', () {
      final out = layoutBlocks([
        _task('a', 9, 0, endHour: 11),
        _task('b', 10, 0, endHour: 12),
      ]);
      expect(out.every((b) => b.laneCount == 2), isTrue);
      expect(out.map((b) => b.lane).toSet(), {0, 1});
    });

    test('una cadena A-B-C comparte reparto aunque A y C no se toquen', () {
      // Sin agrupar por cluster conectado, C volvería a ancho completo y las
      // columnas saltarían de ancho a media pantalla.
      final out = layoutBlocks([
        _task('a', 9, 0, endHour: 10, endMin: 30),
        _task('b', 10, 0, endHour: 11, endMin: 30),
        _task('c', 11, 0, endHour: 12),
      ]);
      expect(out.every((b) => b.laneCount == 2), isTrue);
    });

    test('un bloque reutiliza el carril que quedó libre', () {
      final out = layoutBlocks([
        _task('a', 9, 0, endHour: 11),
        _task('b', 9, 30, endHour: 10),
        _task('c', 10, 15, endHour: 10, endMin: 45),
      ]);
      final byId = {for (final b in out) b.task.id: b};
      expect(byId['b']!.lane, byId['c']!.lane);
      expect(out.every((b) => b.laneCount == 2), isTrue);
    });

    test('lista vacía no revienta', () {
      expect(layoutBlocks(const []), isEmpty);
    });
  });
}
