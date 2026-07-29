import 'dart:convert';

import '../models/habit_model.dart';
import '../models/task_model.dart';
import '../network/local_ai_client.dart';

/// Un bloque propuesto por la IA, todavía sin guardar.
class SuggestedBlock {
  final String title;
  final int startMinutes;
  final int endMinutes;
  final BlockType blockType;

  const SuggestedBlock({
    required this.title,
    required this.startMinutes,
    required this.endMinutes,
    required this.blockType,
  });

  int get durationMinutes => endMinutes - startMinutes;
}

/// Propone un horario para un día a partir de los hábitos, los tres grandes y
/// lo que ya está fijado.
///
/// La IA **sugiere y nunca decide**: la respuesta se pinta como bloques
/// fantasma que se aceptan uno a uno o de golpe, y cualquier fallo (servidor
/// caído, JSON inválido, tiempo agotado) se traga en silencio y deja la
/// planeación manual exactamente igual de utilizable. Un ritual nocturno que
/// dependa de que responda un servidor remoto es un ritual que se rompe.
class AgendaAIService {
  final LocalAIClient client;

  const AgendaAIService(this.client);

  static const _systemPrompt = '''
Eres un asistente de planificación diaria. Respondes SIEMPRE con un array JSON válido y nada más: sin explicaciones, sin markdown, sin ```.

Cada elemento: {"title": string, "start": "HH:MM", "end": "HH:MM", "type": "task"|"deep"|"admin"|"rest"|"personal"}

Reglas:
- No solapes bloques nuevos con los ya ocupados que te den.
- Pon el trabajo que exige concentración por la mañana; los trámites, por la tarde.
- Deja huecos: nunca llenes más del 70% del día despierto.
- Incluye al menos una pausa real.
- Máximo 8 bloques. Títulos cortos, en español, en infinitivo.
''';

  Future<List<SuggestedBlock>> suggestPlan({
    required DateTime day,
    required List<Habit> habits,
    required List<Task> alreadyPlanned,
    List<String> mits = const [],
  }) async {
    final prompt = _buildPrompt(day: day, habits: habits, alreadyPlanned: alreadyPlanned, mits: mits);

    try {
      final raw = await client.askText(prompt, systemPrompt: _systemPrompt);
      return parseSuggestions(raw, occupied: alreadyPlanned);
    } catch (_) {
      return const [];
    }
  }

  String _buildPrompt({
    required DateTime day,
    required List<Habit> habits,
    required List<Task> alreadyPlanned,
    required List<String> mits,
  }) {
    const weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final buffer = StringBuffer()
      ..writeln('Planifica el ${weekdays[day.weekday - 1]}.')
      ..writeln();

    if (mits.isNotEmpty) {
      buffer.writeln('Lo más importante del día (ya está agendado, NO lo repitas):');
      for (final m in mits) {
        buffer.writeln('- $m');
      }
      buffer.writeln();
    }

    if (alreadyPlanned.isNotEmpty) {
      buffer.writeln('Horas YA OCUPADAS, no las pises:');
      for (final t in alreadyPlanned) {
        buffer.writeln('- ${_fmt(_minutes(t.startAt))}–${_fmt(_endMinutes(t))} ${t.title}');
      }
      buffer.writeln();
    }

    final active = habits.where((h) => !h.archived && h.isActiveOn(day)).toList();
    if (active.isNotEmpty) {
      buffer.writeln('Hábitos que quiere sostener (solo como contexto, ya están colocados):');
      for (final h in active) {
        buffer.writeln('- ${h.name}');
      }
      buffer.writeln();
    }

    buffer.writeln('Propón bloques para los huecos libres entre las 07:00 y las 22:00.');
    return buffer.toString();
  }

  /// Extrae los bloques del texto del modelo.
  ///
  /// Pública y sin dependencias de red para poder probarla: es la parte frágil
  /// (un modelo local devuelve JSON envuelto en markdown o con campos de más
  /// con mucha facilidad) y la que no puede reventar el ritual.
  static List<SuggestedBlock> parseSuggestions(
    String raw, {
    List<Task> occupied = const [],
  }) {
    final jsonText = _extractJsonArray(raw);
    if (jsonText == null) return const [];

    late final List<dynamic> decoded;
    try {
      final parsed = jsonDecode(jsonText);
      if (parsed is! List) return const [];
      decoded = parsed;
    } catch (_) {
      return const [];
    }

    final busy = occupied
        .map((t) => (start: _minutes(t.startAt), end: _endMinutes(t)))
        .toList();

    final result = <SuggestedBlock>[];
    for (final item in decoded) {
      if (item is! Map) continue;

      final title = (item['title'] as Object?)?.toString().trim();
      final start = _parseHHmm(item['start']);
      final end = _parseHHmm(item['end']);
      if (title == null || title.isEmpty || start == null || end == null) continue;
      if (end <= start) continue;

      // Aunque el prompt lo prohíbe, un modelo local se salta las reglas: se
      // descartan aquí los solapes en vez de confiar en que obedezca.
      final overlapsBusy = busy.any((b) => start < b.end && end > b.start);
      final overlapsAccepted = result.any((b) => start < b.endMinutes && end > b.startMinutes);
      if (overlapsBusy || overlapsAccepted) continue;

      result.add(SuggestedBlock(
        title: title,
        startMinutes: start,
        endMinutes: end,
        blockType: BlockType.fromValue(item['type'] as String?),
      ));

      if (result.length >= 8) break;
    }

    result.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return result;
  }

  /// Recorta al primer array JSON del texto. Los modelos locales envuelven la
  /// respuesta en ```json, la preceden de "Claro, aquí tienes:" o añaden una
  /// coda; nada de eso debería tirar la sugerencia entera.
  static String? _extractJsonArray(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) return null;
    return raw.substring(start, end + 1);
  }

  static int? _parseHHmm(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    if (h > 24 || m > 59) return null;
    final total = h * 60 + m;
    return total > 24 * 60 ? null : total;
  }

  static int _minutes(DateTime d) => d.hour * 60 + d.minute;

  static int _endMinutes(Task t) {
    if (t.endAt == null) return _minutes(t.startAt) + 40;
    final end = _minutes(t.endAt!);
    return end <= _minutes(t.startAt) ? 24 * 60 : end;
  }

  static String _fmt(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
