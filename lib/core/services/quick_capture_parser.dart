/// Parser de la captura rápida: convierte una frase suelta ("20 almuerzo",
/// "llamar a mamá mañana 3pm") en algo que la app sabe guardar.
///
/// Es deliberadamente local y sin red. La captura rápida se abre desde el
/// desplegable o el widget para anotar en dos segundos; si el reconocimiento
/// dependiera de Ollama (que vive en un servidor remoto) cada anotación
/// costaría segundos de espera y el atajo dejaría de usarse. La IA solo entra
/// después, en la app principal, para afinar lo que aquí quedó como `note`.
library;

enum CaptureKind { expense, income, task, note }

extension CaptureKindX on CaptureKind {
  String get label => switch (this) {
        CaptureKind.expense => 'Gasto',
        CaptureKind.income => 'Ingreso',
        CaptureKind.task => 'Tarea',
        CaptureKind.note => 'Nota',
      };

  String get dbValue => name;

  static CaptureKind? fromName(String? value) {
    if (value == null) return null;
    for (final k in CaptureKind.values) {
      if (k.name == value) return k;
    }
    return null;
  }
}

/// Resultado del parseo. Todavía no es un `TransactionModel`/`Task`/`Note`:
/// esos necesitan `user_id` y `account_id`, que la captura rápida no conoce
/// (su engine no arranca Supabase). La conversión ocurre al drenar la cola.
class QuickCaptureDraft {
  final CaptureKind kind;

  /// Lo que el usuario escribió, tal cual. Se conserva para poder reinterpretar
  /// la captura más tarde si el parseo local se equivocó.
  final String rawText;

  /// Texto ya limpio de monto y marcadores temporales: sirve como descripción
  /// de la transacción o título de la tarea/nota.
  final String title;

  final double? amount;

  /// Id de `FinanceCategories`. Siempre presente para gasto/ingreso.
  final String? categoryId;

  /// Momento detectado para las tareas. Null = sin hora explícita.
  final DateTime? scheduledAt;

  /// Distingue "mañana" (día, sin hora) de "mañana a las 3" (día y hora). Sin
  /// esto no se puede decidir si toca programar un recordatorio.
  final bool hasExplicitTime;

  const QuickCaptureDraft({
    required this.kind,
    required this.rawText,
    required this.title,
    this.amount,
    this.categoryId,
    this.scheduledAt,
    this.hasExplicitTime = false,
  });

  QuickCaptureDraft copyWith({
    CaptureKind? kind,
    String? title,
    double? amount,
    String? categoryId,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    bool? hasExplicitTime,
  }) {
    return QuickCaptureDraft(
      kind: kind ?? this.kind,
      rawText: rawText,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
      hasExplicitTime: clearScheduledAt ? false : (hasExplicitTime ?? this.hasExplicitTime),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'raw_text': rawText,
        'title': title,
        'amount': amount,
        'category_id': categoryId,
        'scheduled_at': scheduledAt?.toIso8601String(),
        'has_explicit_time': hasExplicitTime,
      };

  factory QuickCaptureDraft.fromJson(Map<String, dynamic> json) {
    final scheduled = json['scheduled_at'] as String?;
    return QuickCaptureDraft(
      kind: CaptureKindX.fromName(json['kind'] as String?) ?? CaptureKind.note,
      rawText: json['raw_text'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      categoryId: json['category_id'] as String?,
      scheduledAt: scheduled != null ? DateTime.tryParse(scheduled) : null,
      hasExplicitTime: json['has_explicit_time'] as bool? ?? false,
    );
  }
}

class QuickCaptureParser {
  /// Interpreta [input]. Si [forcedKind] viene dado (el usuario tocó el botón
  /// "Gasto" del widget o un chip del modal) se respeta esa intención y solo se
  /// extraen los detalles; el detector automático no la puede contradecir.
  static QuickCaptureDraft parse(String input, {CaptureKind? forcedKind, DateTime? now}) {
    final reference = now ?? DateTime.now();
    final raw = input.trim();
    if (raw.isEmpty) {
      return QuickCaptureDraft(
        kind: forcedKind ?? CaptureKind.note,
        rawText: '',
        title: '',
      );
    }

    // El prefijo explícito ("nota: ...") gana sobre las heurísticas, pero no
    // sobre el botón que el usuario acaba de pulsar.
    final prefixed = _stripPrefix(raw);
    final source = prefixed.text;
    final signHint = _signHint(source);

    // La hora se busca primero y se tapa antes de buscar el monto: si no, el
    // "2" de "en 2 horas" se lee como un importe y la tarea acaba siendo gasto.
    final time = _findDateTime(source, reference);
    final maskedForAmount =
        time == null ? source : _maskRange(source, time.start, time.end);
    final amountMatch = _findAmount(maskedForAmount);
    final amount = amountMatch?.value;

    final kind = forcedKind ??
        prefixed.kind ??
        _detectKind(
          text: source,
          hasAmount: amount != null,
          hasTime: time != null,
          signHint: signHint,
        );

    // Solo se recorta del título lo que el tipo elegido de verdad se lleva a un
    // campo propio. Una nota conserva su texto entero ("comprar leche mañana"
    // no pierde el "mañana" porque nadie va a guardar esa fecha).
    final cuts = <({int start, int end})>[
      if (amountMatch != null && (kind == CaptureKind.expense || kind == CaptureKind.income))
        (start: amountMatch.start, end: amountMatch.end),
      if (time != null && kind == CaptureKind.task)
        (start: time.start, end: time.end),
    ]..sort((a, b) => b.start.compareTo(a.start));

    var working = source;
    for (final cut in cuts) {
      working = _removeRange(working, cut.start, cut.end);
    }

    final cleanTitle = _cleanUp(working);

    // Un gasto sin descripción es ilegible en el histórico; mejor que caiga en
    // "Sin descripción" que dejar la fila vacía.
    final title = cleanTitle.isEmpty && (kind == CaptureKind.expense || kind == CaptureKind.income)
        ? 'Sin descripción'
        : cleanTitle;

    return QuickCaptureDraft(
      kind: kind,
      rawText: raw,
      title: title,
      amount: kind == CaptureKind.expense || kind == CaptureKind.income ? amount : null,
      categoryId: kind == CaptureKind.expense || kind == CaptureKind.income
          ? _detectCategory(prefixed.text, kind)
          : null,
      scheduledAt: kind == CaptureKind.task ? time?.value : null,
      hasExplicitTime: kind == CaptureKind.task && (time?.hasTime ?? false),
    );
  }

  // ---------------------------------------------------------------------------
  // Detección del tipo
  // ---------------------------------------------------------------------------

  static CaptureKind _detectKind({
    required String text,
    required bool hasAmount,
    required bool hasTime,
    required int signHint,
  }) {
    final n = _normalize(text);

    if (signHint > 0) return CaptureKind.income;
    if (signHint < 0 && hasAmount) return CaptureKind.expense;

    final isIncome = _containsAny(n, _incomeWords);
    final isExpense = _containsAny(n, _expenseWords);

    if (hasAmount) {
      if (isIncome) return CaptureKind.income;
      // Con monto, lo abrumadoramente más frecuente es un gasto: se toma como
      // el caso por defecto en vez de exigir la palabra "gasté".
      return CaptureKind.expense;
    }

    if (isIncome) return CaptureKind.income;
    if (isExpense) return CaptureKind.expense;

    if (_containsAny(n, _taskWords) || hasTime) return CaptureKind.task;

    return CaptureKind.note;
  }

  /// `+500 sueldo` / `-20 taxi`. Devuelve 1, -1 o 0.
  static int _signHint(String text) {
    final t = text.trimLeft();
    if (t.startsWith('+')) return 1;
    if (t.startsWith('-')) return -1;
    return 0;
  }

  static const _incomeWords = [
    'ingreso', 'cobre', 'cobrar', 'me pagaron', 'sueldo', 'salario', 'gane',
    'ganancia', 'recibi', 'deposito', 'depositaron', 'entro', 'freelance',
    'venta', 'vendi', 'reembolso',
  ];

  static const _expenseWords = [
    'gaste', 'gasto', 'pague', 'pago', 'compre', 'compra', 'salio',
    'me costo', 'costo',
  ];

  static const _taskWords = [
    'llamar', 'llamada', 'comprar', 'enviar', 'mandar', 'terminar', 'acabar',
    'revisar', 'recordar', 'recordarme', 'agendar', 'cita', 'reunion',
    'entregar', 'pagar', 'ir a', 'hacer', 'estudiar', 'preparar', 'escribir',
    'responder', 'contestar', 'buscar', 'pedir', 'reservar', 'confirmar',
    'sacar', 'renovar', 'devolver', 'empezar', 'continuar', 'practicar',
  ];

  // ---------------------------------------------------------------------------
  // Prefijos explícitos
  // ---------------------------------------------------------------------------

  static const _prefixes = <String, CaptureKind>{
    'gasto': CaptureKind.expense,
    'gaste': CaptureKind.expense,
    'g': CaptureKind.expense,
    'ingreso': CaptureKind.income,
    'i': CaptureKind.income,
    'tarea': CaptureKind.task,
    't': CaptureKind.task,
    'todo': CaptureKind.task,
    'nota': CaptureKind.note,
    'n': CaptureKind.note,
    'idea': CaptureKind.note,
    'apunte': CaptureKind.note,
  };

  static ({CaptureKind? kind, String text}) _stripPrefix(String raw) {
    final match = RegExp(r'^\s*([a-zA-ZáéíóúÁÉÍÓÚñÑ]+)\s*:\s*').firstMatch(raw);
    if (match == null) return (kind: null, text: raw);

    final kind = _prefixes[_normalize(match.group(1)!)];
    if (kind == null) return (kind: null, text: raw);

    return (kind: kind, text: raw.substring(match.end));
  }

  // ---------------------------------------------------------------------------
  // Monto
  // ---------------------------------------------------------------------------

  /// Reconoce `20`, `$20`, `20.50`, `1,250.75`, `20 usd`, `20k`.
  static final _amountRegExp = RegExp(
    r'(?:^|[\s+\-$])\$?\s*(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*(k|mil|usd|dolares|dólares|pesos)?',
    caseSensitive: false,
  );

  static ({double value, int start, int end})? _findAmount(String text) {
    for (final m in _amountRegExp.allMatches(text)) {
      // La hora no es un monto: "a las 7", "3pm" y "19:30" deben quedar fuera.
      if (_looksLikeTime(text, m)) continue;

      final value = _parseNumber(m.group(1)!, m.group(2));
      if (value == null || value <= 0) continue;

      // El grupo 0 puede haberse comido el espacio previo; recortarlo evita
      // pegar palabras al eliminar el rango del título.
      var start = m.start;
      if (start < text.length && RegExp(r'[\s+\-]').hasMatch(text[start])) start += 1;

      return (value: value, start: start, end: m.end);
    }
    return null;
  }

  static double? _parseNumber(String digits, String? suffix) {
    var normalized = digits;

    // "1,250.75" y "1.250,75" son el mismo número escrito en dos convenciones.
    // El último separador manda: si va seguido de 1-2 dígitos es el decimal.
    final lastDot = normalized.lastIndexOf('.');
    final lastComma = normalized.lastIndexOf(',');
    final decimalPos = lastDot > lastComma ? lastDot : lastComma;

    if (decimalPos >= 0 && normalized.length - decimalPos - 1 <= 2) {
      final intPart = normalized.substring(0, decimalPos).replaceAll(RegExp(r'[.,]'), '');
      final decPart = normalized.substring(decimalPos + 1);
      normalized = '$intPart.$decPart';
    } else {
      normalized = normalized.replaceAll(RegExp(r'[.,]'), '');
    }

    final value = double.tryParse(normalized);
    if (value == null) return null;

    final s = suffix?.toLowerCase();
    if (s == 'k' || s == 'mil') return value * 1000;
    return value;
  }

  /// Un número es hora, no monto, si lo precede "a las"/"las" o lo sigue
  /// ":", "am"/"pm" o "h".
  static bool _looksLikeTime(String text, RegExpMatch m) {
    final before = _normalize(text.substring(0, m.start));
    if (RegExp(r'(a\s+las|a\s+la|las|desde|hasta)\s*$').hasMatch(before)) return true;

    final after = text.substring(m.end);
    if (RegExp(r'^\s*(am|pm|hs?\b|:\d)', caseSensitive: false).hasMatch(after)) return true;

    // "19:30": el ":" inmediatamente antes del número.
    if (m.start > 0 && text[m.start] == ':') return true;
    if (before.endsWith(':')) return true;

    return false;
  }

  // ---------------------------------------------------------------------------
  // Fecha y hora
  // ---------------------------------------------------------------------------

  static const _weekdays = <String, int>{
    'lunes': DateTime.monday,
    'martes': DateTime.tuesday,
    'miercoles': DateTime.wednesday,
    'jueves': DateTime.thursday,
    'viernes': DateTime.friday,
    'sabado': DateTime.saturday,
    'domingo': DateTime.sunday,
  };

  /// Busca una expresión temporal y devuelve el momento resuelto junto al rango
  /// de texto que ocupa, para poder quitarlo del título.
  static ({DateTime value, bool hasTime, int start, int end})? _findDateTime(
    String text,
    DateTime now,
  ) {
    final n = _normalize(text);

    DateTime? day;
    var start = -1;
    var end = -1;

    void take(RegExpMatch m, DateTime resolved) {
      day = resolved;
      start = m.start;
      end = m.end;
    }

    final pasado = RegExp(r'\bpasado\s+manana\b').firstMatch(n);
    final manana = RegExp(r'\bmanana\b').firstMatch(n);
    final hoy = RegExp(r'\bhoy\b').firstMatch(n);
    final estaNoche = RegExp(r'\besta\s+noche\b').firstMatch(n);

    if (pasado != null) {
      take(pasado, _dateOnly(now).add(const Duration(days: 2)));
    } else if (manana != null) {
      take(manana, _dateOnly(now).add(const Duration(days: 1)));
    } else if (estaNoche != null) {
      take(estaNoche, _dateOnly(now));
    } else if (hoy != null) {
      take(hoy, _dateOnly(now));
    } else {
      for (final entry in _weekdays.entries) {
        final m = RegExp('\\b(el\\s+|este\\s+|proximo\\s+)?${entry.key}\\b').firstMatch(n);
        if (m == null) continue;
        take(m, _nextWeekday(now, entry.value));
        break;
      }
    }

    // "en 2 horas" / "en 30 minutos": fija día y hora de una vez.
    final relative = RegExp(r'\ben\s+(\d+)\s*(minutos?|mins?|horas?|hs?|dias?)\b').firstMatch(n);
    if (relative != null && day == null) {
      final qty = int.tryParse(relative.group(1)!) ?? 0;
      final unit = relative.group(2)!;
      final delta = unit.startsWith('min')
          ? Duration(minutes: qty)
          : unit.startsWith('d')
              ? Duration(days: qty)
              : Duration(hours: qty);
      return (
        value: now.add(delta),
        hasTime: !unit.startsWith('d'),
        start: relative.start,
        end: relative.end,
      );
    }

    final time = _findTimeOfDay(n);

    if (day == null && time == null) return null;

    final base = day ?? _dateOnly(now);

    if (time == null) {
      return (value: base, hasTime: false, start: start, end: end);
    }

    var resolved = DateTime(base.year, base.month, base.day, time.hour, time.minute);

    // Sin día explícito, una hora ya pasada se entiende como la de mañana.
    if (day == null && resolved.isBefore(now)) {
      resolved = resolved.add(const Duration(days: 1));
    }

    // "esta noche" sin hora concreta se ancla a las 21:00; con hora, manda la hora.
    final spanStart = start == -1 ? time.start : (start < time.start ? start : time.start);
    final spanEnd = end == -1 ? time.end : (end > time.end ? end : time.end);

    return (value: resolved, hasTime: true, start: spanStart, end: spanEnd);
  }

  /// `3pm`, `15:30`, `a las 7`, `7 y media`.
  static ({int hour, int minute, int start, int end})? _findTimeOfDay(String n) {
    final withMeridiem = RegExp(r'\b(?:a\s+las\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\b').firstMatch(n);
    if (withMeridiem != null) {
      var hour = int.parse(withMeridiem.group(1)!);
      final minute = int.tryParse(withMeridiem.group(2) ?? '0') ?? 0;
      final meridiem = withMeridiem.group(3);
      if (meridiem == 'pm' && hour < 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;
      if (hour > 23 || minute > 59) return null;
      return (hour: hour, minute: minute, start: withMeridiem.start, end: withMeridiem.end);
    }

    final colon = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(n);
    if (colon != null) {
      final hour = int.parse(colon.group(1)!);
      final minute = int.parse(colon.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return (hour: hour, minute: minute, start: colon.start, end: colon.end);
    }

    final spelled = RegExp(r'\ba\s+las?\s+(\d{1,2})(?:\s*(?:y\s+media|:(\d{2})|h))?\b').firstMatch(n);
    if (spelled != null) {
      var hour = int.parse(spelled.group(1)!);
      final minute = spelled.group(0)!.contains('media') ? 30 : int.tryParse(spelled.group(2) ?? '0') ?? 0;
      if (hour > 23 || minute > 59) return null;
      // "a las 8" en un contexto cotidiano casi nunca son las 08:00 si ya es
      // de tarde; se deja que _findDateTime lo empuje a mañana si toca.
      return (hour: hour, minute: minute, start: spelled.start, end: spelled.end);
    }

    return null;
  }

  static DateTime _nextWeekday(DateTime now, int weekday) {
    final today = _dateOnly(now);
    var delta = (weekday - today.weekday) % 7;
    if (delta <= 0) delta += 7; // "el lunes" dicho un lunes es el siguiente
    return today.add(Duration(days: delta));
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---------------------------------------------------------------------------
  // Categoría
  // ---------------------------------------------------------------------------

  static const _categoryWords = <String, List<String>>{
    'food': [
      'comida', 'almuerzo', 'desayuno', 'cena', 'restaurante', 'cafe', 'mercado',
      'super', 'supermercado', 'pizza', 'hamburguesa', 'domicilio', 'snack',
      'panaderia', 'verduras', 'carne', 'pollo', 'arepa', 'jugo', 'gaseosa',
    ],
    'transport': [
      'taxi', 'uber', 'bus', 'metro', 'gasolina', 'combustible', 'pasaje',
      'transporte', 'peaje', 'parqueadero', 'didi', 'cabify', 'moto', 'tren',
      'vuelo', 'avion',
    ],
    'home': [
      'casa', 'hogar', 'arriendo', 'alquiler', 'renta', 'muebles', 'aseo',
      'limpieza', 'reparacion', 'ferreteria',
    ],
    'services': [
      'luz', 'agua', 'gas', 'internet', 'telefono', 'celular', 'recarga',
      'factura', 'servicios', 'electricidad', 'wifi',
    ],
    'health': [
      'medico', 'doctor', 'farmacia', 'medicina', 'medicamento', 'dentista',
      'gimnasio', 'gym', 'consulta', 'examen', 'salud', 'terapia',
    ],
    'entertainment': [
      'cine', 'juego', 'videojuego', 'concierto', 'bar', 'cerveza', 'fiesta',
      'salida', 'ocio', 'streaming', 'netflix', 'spotify', 'disney',
    ],
    'shopping': [
      'ropa', 'zapatos', 'compras', 'tienda', 'amazon', 'regalo', 'accesorio',
      'camisa', 'pantalon', 'tenis',
    ],
    'education': [
      'curso', 'libro', 'universidad', 'colegio', 'matricula', 'clase',
      'estudio', 'certificacion', 'taller',
    ],
    'subscriptions': [
      'suscripcion', 'membresia', 'plan', 'mensualidad', 'renovacion',
      'chatgpt', 'claude', 'github', 'dominio', 'hosting',
    ],
    'salary': ['sueldo', 'salario', 'nomina', 'quincena', 'pago mensual'],
    'freelance': ['freelance', 'proyecto', 'cliente', 'trabajo extra'],
    'investment': ['inversion', 'dividendo', 'interes', 'cripto', 'acciones', 'rendimiento'],
  };

  static String _detectCategory(String text, CaptureKind kind) {
    final n = _normalize(text);
    final isIncome = kind == CaptureKind.income;

    for (final entry in _categoryWords.entries) {
      final incomeCategory = entry.key == 'salary' ||
          entry.key == 'freelance' ||
          entry.key == 'investment';
      if (incomeCategory != isIncome) continue;

      if (_containsAny(n, entry.value)) return entry.key;
    }

    return 'other';
  }

  // ---------------------------------------------------------------------------
  // Utilidades de texto
  // ---------------------------------------------------------------------------

  static const _accents = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
    'Á': 'a', 'É': 'e', 'Í': 'i', 'Ó': 'o', 'Ú': 'u', 'Ü': 'u',
    'ñ': 'n', 'Ñ': 'n',
  };

  /// Minúsculas sin acentos, conservando la longitud para que los índices de
  /// las coincidencias sigan siendo válidos sobre el texto original.
  static String _normalize(String s) {
    final buffer = StringBuffer();
    for (final char in s.split('')) {
      buffer.write(_accents[char] ?? char.toLowerCase());
    }
    return buffer.toString();
  }

  static bool _containsAny(String normalized, List<String> words) {
    for (final w in words) {
      if (RegExp('\\b${RegExp.escape(w)}').hasMatch(normalized)) return true;
    }
    return false;
  }

  static String _removeRange(String text, int start, int end) {
    if (start < 0 || end > text.length || start >= end) return text;
    return '${text.substring(0, start)} ${text.substring(end)}';
  }

  /// Sustituye un tramo por espacios en vez de borrarlo: el texto se vuelve
  /// invisible para el siguiente detector sin que los índices se desplacen.
  static String _maskRange(String text, int start, int end) {
    if (start < 0 || end > text.length || start >= end) return text;
    return text.substring(0, start) + ' ' * (end - start) + text.substring(end);
  }

  /// Recorta el prefijo que [pattern] encuentra en la versión normalizada.
  static String _cutLeading(String text, RegExp pattern) {
    final match = pattern.firstMatch(_normalize(text));
    if (match == null) return text;
    return text.substring(match.end);
  }

  /// Quita conectores huérfanos que quedan al arrancar el monto o la fecha
  /// ("gasté en almuerzo" → "almuerzo").
  static String _cleanUp(String text) {
    var out = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'^[\s,;:.\-+$]+'), '');
    out = out.replaceAll(RegExp(r'[\s,;:.\-+$]+$'), '');

    // Verbos de gasto/ingreso al inicio: aportan al tipo, no a la descripción.
    // El patrón se prueba contra la versión normalizada (para que "gasté"
    // encaje con "gaste"), pero el recorte se aplica sobre el texto original;
    // por eso _normalize conserva la longitud carácter a carácter.
    out = _cutLeading(
      out,
      RegExp(r'^(gaste|gasto|pague|pago|compre|compra|cobre|recibi|gane|me pagaron|ingreso)\s+(en\s+|de\s+|por\s+|para\s+)?'),
    );
    out = _cutLeading(out, RegExp(r'^(en|de|por|para|a|el|la|los|las)\s+'));

    if (out.isEmpty) return out;
    return out[0].toUpperCase() + out.substring(1);
  }
}
