import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/services/quick_capture_parser.dart';

void main() {
  // Referencia fija para que las fechas relativas sean deterministas:
  // jueves 30 de julio de 2026, 10:00.
  final now = DateTime(2026, 7, 30, 10, 0);

  QuickCaptureDraft parse(String input, {CaptureKind? forced}) =>
      QuickCaptureParser.parse(input, forcedKind: forced, now: now);

  group('gastos', () {
    test('monto y categoría desde texto suelto', () {
      final d = parse('20 almuerzo');
      expect(d.kind, CaptureKind.expense);
      expect(d.amount, 20);
      expect(d.categoryId, 'food');
      expect(d.title, 'Almuerzo');
    });

    test('quita el verbo y la preposición de la descripción', () {
      final d = parse('gasté 15.50 en taxi');
      expect(d.kind, CaptureKind.expense);
      expect(d.amount, 15.5);
      expect(d.categoryId, 'transport');
      expect(d.title, 'Taxi');
    });

    test('símbolo de moneda y miles', () {
      final d = parse('\$1,250.75 arriendo');
      expect(d.amount, 1250.75);
      expect(d.categoryId, 'home');
    });

    test('sufijo k multiplica por mil', () {
      final d = parse('3k mercado');
      expect(d.amount, 3000);
      expect(d.categoryId, 'food');
    });

    test('signo negativo fuerza gasto', () {
      final d = parse('-40 cerveza');
      expect(d.kind, CaptureKind.expense);
      expect(d.amount, 40);
      expect(d.categoryId, 'entertainment');
    });
  });

  group('ingresos', () {
    test('signo + fuerza ingreso', () {
      final d = parse('+500 sueldo');
      expect(d.kind, CaptureKind.income);
      expect(d.amount, 500);
      expect(d.categoryId, 'salary');
    });

    test('palabra clave de ingreso gana sobre el gasto por defecto', () {
      final d = parse('cobré 300 de un cliente');
      expect(d.kind, CaptureKind.income);
      expect(d.amount, 300);
      expect(d.categoryId, 'freelance');
    });
  });

  group('tareas', () {
    test('verbo de acción con hora relativa', () {
      final d = parse('llamar a mamá mañana 3pm');
      expect(d.kind, CaptureKind.task);
      expect(d.hasExplicitTime, isTrue);
      expect(d.scheduledAt, DateTime(2026, 7, 31, 15, 0));
      expect(d.title, contains('llamar'.toUpperCase()[0]));
      expect(d.title.toLowerCase(), contains('mamá'));
    });

    test('día de la semana sin hora', () {
      final d = parse('revisar el contrato el lunes');
      expect(d.kind, CaptureKind.task);
      expect(d.hasExplicitTime, isFalse);
      // El lunes siguiente al jueves 30/07/2026 es el 03/08.
      expect(d.scheduledAt, DateTime(2026, 8, 3));
    });

    test('"en 2 horas" se resuelve sobre el momento actual', () {
      final d = parse('sacar la ropa en 2 horas');
      expect(d.kind, CaptureKind.task);
      expect(d.scheduledAt, DateTime(2026, 7, 30, 12, 0));
      expect(d.hasExplicitTime, isTrue);
    });

    test('una hora ya pasada sin día se entiende como mañana', () {
      final d = parse('enviar el reporte a las 8');
      expect(d.kind, CaptureKind.task);
      expect(d.scheduledAt, DateTime(2026, 7, 31, 8, 0));
    });

    test('la hora no se confunde con un monto', () {
      final d = parse('reunión a las 7 pm');
      expect(d.amount, isNull);
      expect(d.kind, CaptureKind.task);
      expect(d.scheduledAt, DateTime(2026, 7, 30, 19, 0));
    });
  });

  group('notas', () {
    test('texto sin monto ni acción cae en nota', () {
      final d = parse('la app necesita un modo offline de verdad');
      expect(d.kind, CaptureKind.note);
      expect(d.amount, isNull);
      expect(d.scheduledAt, isNull);
    });

    test('prefijo explícito manda sobre la heurística', () {
      final d = parse('nota: comprar leche mañana');
      expect(d.kind, CaptureKind.note);
      expect(d.title, 'Comprar leche mañana');
    });
  });

  group('tipo forzado', () {
    test('el botón del widget gana sobre el detector', () {
      final d = parse('curso de flutter 45', forced: CaptureKind.expense);
      expect(d.kind, CaptureKind.expense);
      expect(d.amount, 45);
      expect(d.categoryId, 'education');
    });

    test('forzar nota descarta monto y fecha', () {
      final d = parse('20 almuerzo mañana', forced: CaptureKind.note);
      expect(d.kind, CaptureKind.note);
      expect(d.amount, isNull);
      expect(d.scheduledAt, isNull);
    });
  });

  test('entrada vacía no revienta', () {
    final d = parse('   ');
    expect(d.title, isEmpty);
    expect(d.kind, CaptureKind.note);
  });
}
