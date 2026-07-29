import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/task_model.dart';
import 'package:sistem_daily/core/services/agenda_ai_service.dart';

Task _busy(int startHour, int endHour) {
  final day = DateTime(2026, 7, 30);
  return Task(
    id: '$startHour',
    title: 'ocupado',
    dueDate: day,
    startAt: DateTime(2026, 7, 30, startHour),
    endAt: DateTime(2026, 7, 30, endHour),
  );
}

void main() {
  group('parseSuggestions', () {
    test('lee un array JSON limpio', () {
      final out = AgendaAIService.parseSuggestions('''
[{"title":"Escribir informe","start":"09:00","end":"10:30","type":"deep"}]
''');
      expect(out, hasLength(1));
      expect(out.first.title, 'Escribir informe');
      expect(out.first.startMinutes, 9 * 60);
      expect(out.first.endMinutes, 10 * 60 + 30);
      expect(out.first.blockType, BlockType.deep);
      expect(out.first.durationMinutes, 90);
    });

    test('sobrevive al markdown y al parloteo alrededor', () {
      final out = AgendaAIService.parseSuggestions('''
Claro, aquí tienes tu plan:
```json
[{"title":"Correr","start":"07:00","end":"07:45","type":"personal"}]
```
Espero que te sirva.
''');
      expect(out, hasLength(1));
      expect(out.first.title, 'Correr');
    });

    test('ordena los bloques por hora de inicio', () {
      final out = AgendaAIService.parseSuggestions('''
[{"title":"Tarde","start":"16:00","end":"17:00"},
 {"title":"Mañana","start":"08:00","end":"09:00"}]
''');
      expect(out.map((b) => b.title), ['Mañana', 'Tarde']);
    });

    test('descarta bloques que pisan lo ya ocupado', () {
      final out = AgendaAIService.parseSuggestions(
        '[{"title":"Choca","start":"09:30","end":"10:30"},'
        ' {"title":"Libre","start":"14:00","end":"15:00"}]',
        occupied: [_busy(9, 11)],
      );
      expect(out.map((b) => b.title), ['Libre']);
    });

    test('descarta bloques que se pisan entre ellos', () {
      final out = AgendaAIService.parseSuggestions(
        '[{"title":"Uno","start":"09:00","end":"11:00"},'
        ' {"title":"Dos","start":"10:00","end":"12:00"}]',
      );
      expect(out.map((b) => b.title), ['Uno']);
    });

    test('un bloque pegado a otro no cuenta como solape', () {
      final out = AgendaAIService.parseSuggestions(
        '[{"title":"Justo después","start":"11:00","end":"12:00"}]',
        occupied: [_busy(9, 11)],
      );
      expect(out, hasLength(1));
    });

    test('ignora elementos con horas inválidas o campos faltantes', () {
      final out = AgendaAIService.parseSuggestions('''
[{"title":"Sin fin","start":"09:00"},
 {"title":"Hora imposible","start":"99:99","end":"10:00"},
 {"start":"09:00","end":"10:00"},
 {"title":"Fin antes del inicio","start":"11:00","end":"10:00"},
 {"title":"Válido","start":"13:00","end":"14:00"}]
''');
      expect(out.map((b) => b.title), ['Válido']);
    });

    test('un tipo desconocido cae a "task" en vez de reventar', () {
      final out = AgendaAIService.parseSuggestions(
        '[{"title":"X","start":"09:00","end":"10:00","type":"inventado"}]',
      );
      expect(out.first.blockType, BlockType.task);
    });

    test('corta a 8 bloques', () {
      final items = List.generate(
        12,
        (i) => '{"title":"B$i","start":"${(8 + i).toString().padLeft(2, '0')}:00",'
            '"end":"${(8 + i).toString().padLeft(2, '0')}:30"}',
      ).join(',');
      expect(AgendaAIService.parseSuggestions('[$items]'), hasLength(8));
    });

    test('texto sin JSON, JSON roto o un objeto suelto devuelven lista vacía', () {
      expect(AgendaAIService.parseSuggestions('No puedo ayudarte con eso.'), isEmpty);
      expect(AgendaAIService.parseSuggestions('[{"title":"roto",'), isEmpty);
      expect(AgendaAIService.parseSuggestions('{"title":"objeto","start":"09:00"}'), isEmpty);
      expect(AgendaAIService.parseSuggestions(''), isEmpty);
    });
  });
}
