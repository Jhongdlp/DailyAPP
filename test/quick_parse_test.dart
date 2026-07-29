import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/task_model.dart';
import 'package:sistem_daily/features/agenda/quick_parse.dart';

void main() {
  group('hora de inicio', () {
    test('hora con minutos', () {
      final r = parseQuickBlock('correr 6:30')!;
      expect(r.title, 'correr');
      expect(r.startMinutes, 6 * 60 + 30);
    });

    test('am y pm', () {
      expect(parseQuickBlock('gym 6am')!.startMinutes, 6 * 60);
      expect(parseQuickBlock('cena 8 pm')!.startMinutes, 20 * 60);
    });

    test('12am es medianoche y 12pm es mediodía', () {
      expect(parseQuickBlock('algo 12am')!.startMinutes, 0);
      expect(parseQuickBlock('algo 12pm')!.startMinutes, 12 * 60);
    });

    test('"a las" marca la hora aunque no traiga minutos', () {
      final r = parseQuickBlock('llamar al banco a las 9')!;
      expect(r.startMinutes, 9 * 60);
      expect(r.title, 'llamar al banco');
    });

    test('un número suelto sin marcas NO se toma como hora', () {
      // "correr 5 km" no empieza a las 5:00.
      final r = parseQuickBlock('correr 5 km')!;
      expect(r.startMinutes, isNull);
      expect(r.title, 'correr 5 km');
    });
  });

  group('duración', () {
    test('horas y minutos por separado', () {
      expect(parseQuickBlock('foco 9:00 1h')!.durationMinutes, 60);
      expect(parseQuickBlock('pausa 30m')!.durationMinutes, 30);
      expect(parseQuickBlock('leer 45min')!.durationMinutes, 45);
    });

    test('formato compuesto 1h30', () {
      expect(parseQuickBlock('estudiar 8:00 1h30')!.durationMinutes, 90);
    });

    test('en palabras', () {
      expect(parseQuickBlock('taller 10:00 2 horas')!.durationMinutes, 120);
      expect(parseQuickBlock('café 90 minutos')!.durationMinutes, 90);
    });

    test('la duración no se confunde con la hora', () {
      final r = parseQuickBlock('estudiar 1h30')!;
      expect(r.durationMinutes, 90);
      expect(r.startMinutes, isNull);
      expect(r.title, 'estudiar');
    });
  });

  group('rangos', () {
    test('rango con guion', () {
      final r = parseQuickBlock('9-11 informe')!;
      expect(r.startMinutes, 9 * 60);
      expect(r.durationMinutes, 120);
      expect(r.title, 'informe');
    });

    test('rango con "a" y minutos', () {
      final r = parseQuickBlock('reunión de 9:30 a 11:00')!;
      expect(r.startMinutes, 9 * 60 + 30);
      expect(r.durationMinutes, 90);
      expect(r.title, 'reunión');
    });

    test('un rango que cruza medianoche no da duración negativa', () {
      final r = parseQuickBlock('turno 22-2')!;
      expect(r.startMinutes, 22 * 60);
      expect(r.durationMinutes, 4 * 60);
    });

    test('endMinutes combina inicio y duración', () {
      final r = parseQuickBlock('9-11 informe')!;
      expect(r.endMinutes, 11 * 60);
    });
  });

  group('modificadores', () {
    test('! sube la prioridad y no queda en el título', () {
      final r = parseQuickBlock('entregar informe!')!;
      expect(r.priority, TaskPriority.high);
      expect(r.title, 'entregar informe');
    });

    test('@ marca el lugar', () {
      final r = parseQuickBlock('correr 6:30 @parque')!;
      expect(r.location, 'parque');
      expect(r.title, 'correr');
    });

    test('# marca el tipo de bloque', () {
      expect(parseQuickBlock('informe 9:00 #foco')!.blockType, BlockType.deep);
      expect(parseQuickBlock('siesta 15:00 #descanso')!.blockType, BlockType.rest);
    });

    test('una etiqueta desconocida se queda en el título', () {
      final r = parseQuickBlock('informe #loquesea')!;
      expect(r.blockType, isNull);
      expect(r.title, contains('#loquesea'));
    });

    test('"mañana" desplaza el día', () {
      final r = parseQuickBlock('dentista mañana 10:00')!;
      expect(r.dayOffset, 1);
      expect(r.startMinutes, 10 * 60);
      expect(r.title, 'dentista');
    });

    test('"hoy" no desplaza', () {
      expect(parseQuickBlock('algo hoy 10:00')!.dayOffset, 0);
    });
  });

  group('casos límite', () {
    test('cadena vacía o solo espacios devuelve null', () {
      expect(parseQuickBlock(''), isNull);
      expect(parseQuickBlock('   '), isNull);
    });

    test('solo una hora, sin título, devuelve null', () {
      expect(parseQuickBlock('6:30'), isNull);
    });

    test('una hora imposible se queda como texto', () {
      final r = parseQuickBlock('marcar 99:99')!;
      expect(r.startMinutes, isNull);
      expect(r.title, contains('99'));
    });

    test('todo junto', () {
      final r = parseQuickBlock('correr mañana 6:30 45min @parque #habito!')!;
      expect(r.title, 'correr');
      expect(r.dayOffset, 1);
      expect(r.startMinutes, 6 * 60 + 30);
      expect(r.durationMinutes, 45);
      expect(r.location, 'parque');
      expect(r.blockType, BlockType.habit);
      expect(r.priority, TaskPriority.high);
    });
  });
}
