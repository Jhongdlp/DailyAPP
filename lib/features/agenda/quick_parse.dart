import '../../core/models/task_model.dart';

/// Resultado de interpretar una línea escrita a mano.
class ParsedBlock {
  final String title;

  /// Minuto del día en que empieza. `null` = no dijo hora y hay que elegirla.
  final int? startMinutes;

  /// Duración en minutos. `null` = no la dijo.
  final int? durationMinutes;

  final TaskPriority priority;
  final String? location;
  final BlockType? blockType;

  /// Desplazamiento en días respecto al día en curso ("mañana" ⇒ 1).
  final int dayOffset;

  const ParsedBlock({
    required this.title,
    this.startMinutes,
    this.durationMinutes,
    this.priority = TaskPriority.normal,
    this.location,
    this.blockType,
    this.dayOffset = 0,
  });

  int? get endMinutes =>
      startMinutes == null || durationMinutes == null ? null : startMinutes! + durationMinutes!;

  bool get hasTime => startMinutes != null;
}

// Rango explícito: "9-11", "9:30 - 11", "de 9 a 11", "9 a 11".
final _rangeRe = RegExp(
  r'(?:\bde\s+)?\b(\d{1,2})(?::(\d{2}))?\s*(?:-|–|—|a(?:\s+las)?)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|h)?\b',
  caseSensitive: false,
);

// Hora suelta: "6:30", "6 am", "18h", "a las 7".
final _timeRe = RegExp(
  r'(?:\ba\s+las?\s+)?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|hs?)?\b',
  caseSensitive: false,
);

// Duración: "1h", "30m", "45min", "1h30", "2 horas", "90 minutos".
final _durationRe = RegExp(
  r'\b(\d{1,3})\s*(h|hr|hrs|hora|horas)\s*(\d{1,2})?\b|\b(\d{1,3})\s*(m|min|mins|minuto|minutos)\b',
  caseSensitive: false,
);

final _locationRe = RegExp(r'@([\wáéíóúüñ.\-]+)', caseSensitive: false);
final _tagRe = RegExp(r'#([\wáéíóúüñ\-]+)', caseSensitive: false);

const _tagToBlockType = {
  'foco': BlockType.deep,
  'deep': BlockType.deep,
  'trabajo': BlockType.deep,
  'tramite': BlockType.admin,
  'trámite': BlockType.admin,
  'admin': BlockType.admin,
  'descanso': BlockType.rest,
  'rest': BlockType.rest,
  'pausa': BlockType.rest,
  'personal': BlockType.personal,
  'habito': BlockType.habit,
  'hábito': BlockType.habit,
};

/// Interpreta una línea escrita a mano y saca de ella la hora, la duración y
/// el título.
///
/// Existe para que planear no exija abrir un formulario: escribir
/// "correr 6:30 1h" y pulsar enter es un orden de magnitud menos de fricción
/// que elegir hora en un reloj, elegir fin en otro y confirmar. Es un parser
/// local a propósito — instantáneo y sin depender del servidor de IA.
///
/// Devuelve `null` si no queda ningún título después de quitar los
/// modificadores: un bloque sin nombre no sirve de nada.
ParsedBlock? parseQuickBlock(String input) {
  var text = ' ${input.trim()} ';
  if (text.trim().isEmpty) return null;

  var priority = TaskPriority.normal;
  String? location;
  BlockType? blockType;
  var dayOffset = 0;

  // --- prioridad: un "!" al final o suelto
  if (RegExp(r'(^|\s)!+(\s|$)').hasMatch(text) || text.trimRight().endsWith('!')) {
    priority = TaskPriority.high;
    text = text.replaceAll(RegExp(r'!+'), ' ');
  }

  // --- lugar
  final locMatch = _locationRe.firstMatch(text);
  if (locMatch != null) {
    location = locMatch.group(1);
    text = text.replaceRange(locMatch.start, locMatch.end, ' ');
  }

  // --- tipo de bloque
  final tagMatch = _tagRe.firstMatch(text);
  if (tagMatch != null) {
    blockType = _tagToBlockType[tagMatch.group(1)!.toLowerCase()];
    if (blockType != null) {
      text = text.replaceRange(tagMatch.start, tagMatch.end, ' ');
    }
  }

  // --- día
  for (final entry in const {'pasado mañana': 2, 'mañana': 1, 'hoy': 0}.entries) {
    final re = RegExp(r'\b' + entry.key + r'\b', caseSensitive: false);
    final m = re.firstMatch(text);
    if (m != null) {
      dayOffset = entry.value;
      text = text.replaceRange(m.start, m.end, ' ');
      break;
    }
  }

  // --- duración (antes que la hora: "1h30" no debe leerse como la hora 1:30)
  int? duration;
  final durMatch = _durationRe.firstMatch(text);
  if (durMatch != null) {
    if (durMatch.group(1) != null) {
      duration = int.parse(durMatch.group(1)!) * 60 + int.parse(durMatch.group(3) ?? '0');
    } else {
      duration = int.parse(durMatch.group(4)!);
    }
    text = text.replaceRange(durMatch.start, durMatch.end, ' ');
  }

  // --- rango, y si no hay rango, hora suelta
  int? start;
  final rangeMatch = _rangeRe.firstMatch(text);
  if (rangeMatch != null) {
    final meridiem = rangeMatch.group(5)?.toLowerCase();
    final startRaw = int.parse(rangeMatch.group(1)!);
    final endRaw = int.parse(rangeMatch.group(3)!);
    final startMin = int.parse(rangeMatch.group(2) ?? '0');
    final endMin = int.parse(rangeMatch.group(4) ?? '0');

    if (startRaw <= 24 && endRaw <= 24 && startMin < 60 && endMin < 60) {
      final s = _applyMeridiem(startRaw, meridiem) * 60 + startMin;
      var e = _applyMeridiem(endRaw, meridiem) * 60 + endMin;
      // "22-2" es de noche a madrugada, no un rango negativo.
      if (e <= s) e += 24 * 60;
      start = s;
      duration = e - s;
      text = text.replaceRange(rangeMatch.start, rangeMatch.end, ' ');
    }
  } else {
    final timeMatch = _timeRe.firstMatch(text);
    if (timeMatch != null) {
      final hourRaw = int.parse(timeMatch.group(1)!);
      final minute = int.parse(timeMatch.group(2) ?? '0');
      final meridiem = timeMatch.group(3)?.toLowerCase();
      // Un número suelto sin ":" ni "am/pm" ni "a las" es ambiguo ("correr 5
      // km"), así que solo cuenta como hora si trae alguna de esas marcas.
      // El "a las" se busca dentro de la propia coincidencia, que ya lo
      // captura, no en el texto que la precede.
      final looksLikeTime = timeMatch.group(2) != null ||
          meridiem != null ||
          RegExp(r'^\s*a\s+las?\s+', caseSensitive: false).hasMatch(timeMatch.group(0)!);
      if (looksLikeTime && hourRaw <= 24 && minute < 60) {
        start = _applyMeridiem(hourRaw, meridiem) * 60 + minute;
        text = text.replaceRange(timeMatch.start, timeMatch.end, ' ');
      }
    }
  }

  // Limpia conectores que quedaron colgando al quitar la hora ("correr a las"
  // ⇒ "correr").
  final title = text
      .replaceAll(RegExp(r'\b(a\s+las?|de|desde|hasta)\s*$', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (title.isEmpty) return null;

  return ParsedBlock(
    title: title,
    startMinutes: start == null ? null : start % (24 * 60),
    durationMinutes: duration,
    priority: priority,
    location: location,
    blockType: blockType,
    dayOffset: dayOffset,
  );
}

int _applyMeridiem(int hour, String? meridiem) {
  if (meridiem == 'pm') return hour == 12 ? 12 : (hour + 12) % 24;
  if (meridiem == 'am') return hour == 12 ? 0 : hour;
  return hour % 24;
}
