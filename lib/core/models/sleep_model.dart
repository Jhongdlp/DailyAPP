import 'dart:math' as math;

/// Clave `yyyy-MM-dd` de un día.
String sleepDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// Hora a partir de la cual acostarse cuenta como la noche del día siguiente.
/// Antes de las 18:00 se asume que sigues en el día que ya empezó (siesta larga
/// o alguien que se acuesta de madrugada y lo confirma a las 03:00).
const _nightRolloverHour = 18;

/// Clave de la noche a la que pertenece un instante: la fecha del **despertar**.
/// Es la convención estándar en registro de sueño — la noche del 3 al 4 se
/// archiva como el día 4 — y hace que "las horas que dormí para el lunes"
/// signifique lo mismo para el usuario y para el código.
String nightKeyFor(DateTime moment) {
  if (moment.hour >= _nightRolloverHour) {
    return sleepDayKey(moment.add(const Duration(days: 1)));
  }
  return sleepDayKey(moment);
}

/// Minutos que se descuentan del tiempo en cama por cada despertar nocturno
/// reportado. No es medible sin sensores, así que se usa una estimación
/// conservadora y constante: lo que importa es que la eficiencia se mueva en
/// la dirección correcta, no clavar el número.
const int minutesPerAwakening = 8;

/// Una noche registrada, identificada por [nightKey] (fecha del despertar).
class SleepSession {
  final String nightKey;

  /// Hora a la que tocaba acostarse según el horario configurado esa noche.
  final DateTime? bedtimeTarget;

  /// Cuándo se confirmó "me voy a dormir" (toque en la notificación).
  final DateTime? lightsOutAt;

  /// Hora a la que debía sonar la alarma de despertar.
  final DateTime? alarmScheduledAt;

  /// Primera vez que la alarma sonó de verdad esa mañana.
  final DateTime? firstRingAt;

  /// Cuándo se validó la foto y la alarma se apagó.
  final DateTime? wokeAt;

  /// La alarma sonó pero nunca se llegó a validar la foto.
  final bool alarmIgnored;

  /// Calidad percibida 1–5 (check-in matutino).
  final int? quality;

  /// Veces que se despertó durante la noche (check-in).
  final int? awakenings;

  /// Minutos que tardó en dormirse (check-in).
  final int? latencyMinutes;

  /// Intentos fallidos de foto antes de acertar.
  final int dismissAttempts;

  const SleepSession({
    required this.nightKey,
    this.bedtimeTarget,
    this.lightsOutAt,
    this.alarmScheduledAt,
    this.firstRingAt,
    this.wokeAt,
    this.alarmIgnored = false,
    this.quality,
    this.awakenings,
    this.latencyMinutes,
    this.dismissAttempts = 0,
  });

  /// Fecha (sin hora) a la que corresponde la noche.
  DateTime get date => _parseDate(nightKey) ?? DateTime.now();

  bool get isComplete => lightsOutAt != null && wokeAt != null;

  /// Tiempo entre apagar la luz y levantarse. `null` si falta algún extremo.
  Duration? get timeInBed {
    final start = lightsOutAt;
    final end = wokeAt;
    if (start == null || end == null) return null;
    final diff = end.difference(start);
    // Una noche de más de 16 h o negativa es un registro corrupto (p.ej. se
    // confirmó el bedtime y no se despertó hasta dos días después): mejor no
    // tener el dato que envenenar todas las medias con él.
    if (diff.isNegative || diff.inHours > 16) return null;
    return diff;
  }

  /// Sueño estimado: tiempo en cama menos lo que costó dormirse y menos los
  /// despertares reportados. Sin sensores esto es lo más honesto que se puede
  /// calcular, y coincide con lo que hace un diario de sueño clínico.
  Duration? get estimatedSleep {
    final inBed = timeInBed;
    if (inBed == null) return null;
    final penalty = Duration(
      minutes: (latencyMinutes ?? 0) + (awakenings ?? 0) * minutesPerAwakening,
    );
    final result = inBed - penalty;
    return result.isNegative ? Duration.zero : result;
  }

  /// Sueño estimado en minutos, o `null` si la noche está incompleta.
  int? get sleepMinutes => estimatedSleep?.inMinutes;

  /// Porcentaje del tiempo en cama que se pasó durmiendo (0–1).
  double? get efficiency {
    final inBed = timeInBed;
    final slept = estimatedSleep;
    if (inBed == null || slept == null || inBed.inMinutes == 0) return null;
    return slept.inMinutes / inBed.inMinutes;
  }

  /// Punto medio del sueño en minutos desde medianoche, **con envoltura**:
  /// 03:30 → 210, 23:50 → −10. Sin esta envoltura, medias y desviaciones se
  /// disparan en cuanto una noche cruza las 00:00 (1430 y 10 promedian 720,
  /// o sea mediodía, que es justo lo contrario de lo que pasó).
  double? get midpointMinutes {
    final start = lightsOutAt;
    final slept = estimatedSleep;
    if (start == null || slept == null) return null;
    final mid = start.add(Duration(minutes: slept.inMinutes ~/ 2));
    final raw = mid.hour * 60 + mid.minute;
    return raw > 720 ? (raw - 1440).toDouble() : raw.toDouble();
  }

  /// Minutos entre que la alarma sonó y que te levantaste de verdad.
  int? get snoozeMinutes {
    final ring = firstRingAt ?? alarmScheduledAt;
    final end = wokeAt;
    if (ring == null || end == null) return null;
    final diff = end.difference(ring).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  /// ¿Se cumplió el horario de acostarse? Se dan 15 min de gracia porque
  /// castigar el minuto exacto convierte la métrica en ruido.
  bool? get metBedtime {
    final target = bedtimeTarget;
    final actual = lightsOutAt;
    if (target == null || actual == null) return null;
    return !actual.isAfter(target.add(const Duration(minutes: 15)));
  }

  SleepSession copyWith({
    DateTime? bedtimeTarget,
    DateTime? lightsOutAt,
    DateTime? alarmScheduledAt,
    DateTime? firstRingAt,
    DateTime? wokeAt,
    bool? alarmIgnored,
    int? quality,
    int? awakenings,
    int? latencyMinutes,
    int? dismissAttempts,
  }) {
    return SleepSession(
      nightKey: nightKey,
      bedtimeTarget: bedtimeTarget ?? this.bedtimeTarget,
      lightsOutAt: lightsOutAt ?? this.lightsOutAt,
      alarmScheduledAt: alarmScheduledAt ?? this.alarmScheduledAt,
      firstRingAt: firstRingAt ?? this.firstRingAt,
      wokeAt: wokeAt ?? this.wokeAt,
      alarmIgnored: alarmIgnored ?? this.alarmIgnored,
      quality: quality ?? this.quality,
      awakenings: awakenings ?? this.awakenings,
      latencyMinutes: latencyMinutes ?? this.latencyMinutes,
      dismissAttempts: dismissAttempts ?? this.dismissAttempts,
    );
  }

  Map<String, dynamic> toJson() => {
        'night_key': nightKey,
        'bedtime_target': bedtimeTarget?.toIso8601String(),
        'lights_out_at': lightsOutAt?.toIso8601String(),
        'alarm_scheduled_at': alarmScheduledAt?.toIso8601String(),
        'first_ring_at': firstRingAt?.toIso8601String(),
        'woke_at': wokeAt?.toIso8601String(),
        'alarm_ignored': alarmIgnored,
        'quality': quality,
        'awakenings': awakenings,
        'latency_minutes': latencyMinutes,
        'dismiss_attempts': dismissAttempts,
      };

  factory SleepSession.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final raw = json[key] as String?;
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    }

    return SleepSession(
      nightKey: json['night_key'] as String,
      bedtimeTarget: parse('bedtime_target'),
      lightsOutAt: parse('lights_out_at'),
      alarmScheduledAt: parse('alarm_scheduled_at'),
      firstRingAt: parse('first_ring_at'),
      wokeAt: parse('woke_at'),
      alarmIgnored: json['alarm_ignored'] as bool? ?? false,
      quality: (json['quality'] as num?)?.toInt(),
      awakenings: (json['awakenings'] as num?)?.toInt(),
      latencyMinutes: (json['latency_minutes'] as num?)?.toInt(),
      dismissAttempts: (json['dismiss_attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Horario de sueño configurado por el usuario.
class SleepSchedule {
  final bool enabled;
  final int bedtimeHour;
  final int bedtimeMinute;

  /// Minutos antes del bedtime en los que llega el aviso de "baja el ritmo".
  final int windDownMinutes;

  /// Meta de sueño en minutos.
  final int goalMinutes;

  /// 1 = lunes … 7 = domingo, mismo criterio que [AlarmModel].
  final List<int> daysOfWeek;

  /// Repetir el aviso cada 15 min (hasta 3 veces) si no se confirma.
  final bool nagEnabled;

  const SleepSchedule({
    this.enabled = false,
    this.bedtimeHour = 23,
    this.bedtimeMinute = 0,
    this.windDownMinutes = 30,
    this.goalMinutes = 480,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    this.nagEnabled = true,
  });

  String get formattedBedtime =>
      '${bedtimeHour.toString().padLeft(2, '0')}:'
      '${bedtimeMinute.toString().padLeft(2, '0')}';

  String get goalLabel {
    final h = goalMinutes ~/ 60;
    final m = goalMinutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  String get daysLabel {
    if (daysOfWeek.length == 7) return 'Todos los días';
    if (daysOfWeek.isEmpty) return 'Sin días';
    const names = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final sorted = [...daysOfWeek]..sort();
    return sorted.map((d) => names[d]).join(', ');
  }

  /// Próxima hora de acostarse a partir de [from], o `null` si no hay días.
  DateTime? nextBedtime({DateTime? from}) {
    if (!enabled || daysOfWeek.isEmpty) return null;
    final now = from ?? DateTime.now();
    for (var i = 0; i < 8; i++) {
      final candidate =
          DateTime(now.year, now.month, now.day, bedtimeHour, bedtimeMinute)
              .add(Duration(days: i));
      if (candidate.isAfter(now) && daysOfWeek.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  /// Hora objetivo de acostarse de la noche que corresponde a [moment].
  /// Se usa para rellenar `bedtimeTarget` aunque el usuario confirme tarde.
  DateTime bedtimeTargetFor(DateTime moment) {
    final target =
        DateTime(moment.year, moment.month, moment.day, bedtimeHour, bedtimeMinute);
    // Si se confirma de madrugada, el objetivo era el de la noche anterior.
    if (moment.hour < _nightRolloverHour && bedtimeHour >= _nightRolloverHour) {
      return target.subtract(const Duration(days: 1));
    }
    return target;
  }

  SleepSchedule copyWith({
    bool? enabled,
    int? bedtimeHour,
    int? bedtimeMinute,
    int? windDownMinutes,
    int? goalMinutes,
    List<int>? daysOfWeek,
    bool? nagEnabled,
  }) {
    return SleepSchedule(
      enabled: enabled ?? this.enabled,
      bedtimeHour: bedtimeHour ?? this.bedtimeHour,
      bedtimeMinute: bedtimeMinute ?? this.bedtimeMinute,
      windDownMinutes: windDownMinutes ?? this.windDownMinutes,
      goalMinutes: goalMinutes ?? this.goalMinutes,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      nagEnabled: nagEnabled ?? this.nagEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'bedtime_hour': bedtimeHour,
        'bedtime_minute': bedtimeMinute,
        'wind_down_minutes': windDownMinutes,
        'goal_minutes': goalMinutes,
        'days_of_week': daysOfWeek,
        'nag_enabled': nagEnabled,
      };

  factory SleepSchedule.fromJson(Map<String, dynamic> json) => SleepSchedule(
        enabled: json['enabled'] as bool? ?? false,
        bedtimeHour: (json['bedtime_hour'] as num?)?.toInt() ?? 23,
        bedtimeMinute: (json['bedtime_minute'] as num?)?.toInt() ?? 0,
        windDownMinutes: (json['wind_down_minutes'] as num?)?.toInt() ?? 30,
        goalMinutes: (json['goal_minutes'] as num?)?.toInt() ?? 480,
        daysOfWeek: json['days_of_week'] != null
            ? List<int>.from(json['days_of_week'] as List)
            : const [1, 2, 3, 4, 5, 6, 7],
        nagEnabled: json['nag_enabled'] as bool? ?? true,
      );
}

/// Estado raíz persistido del apartado de sueño.
class SleepData {
  final SleepSchedule schedule;

  /// Noches indexadas por `nightKey`.
  final Map<String, SleepSession> sessions;

  /// Noche en curso: bedtime confirmado y aún sin despertar registrado.
  final String? openNightKey;

  /// Noches que ya dieron XP. Evita volver a premiar si se reabre el check-in.
  final List<String> rewardedNights;

  const SleepData({
    this.schedule = const SleepSchedule(),
    this.sessions = const {},
    this.openNightKey,
    this.rewardedNights = const [],
  });

  SleepSession? get openNight =>
      openNightKey == null ? null : sessions[openNightKey];

  /// La noche que ya terminó más reciente.
  SleepSession? get lastCompleteNight {
    final done = sessions.values.where((s) => s.timeInBed != null).toList()
      ..sort((a, b) => b.nightKey.compareTo(a.nightKey));
    return done.isEmpty ? null : done.first;
  }

  /// Noches de los últimos [days] días, de la más antigua a la más reciente,
  /// incluyendo huecos como `null` para que los gráficos mantengan el eje.
  List<({DateTime day, SleepSession? session})> lastNights(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          session: sessions[sleepDayKey(today.subtract(Duration(days: i)))],
        ),
    ];
  }

  SleepData copyWith({
    SleepSchedule? schedule,
    Map<String, SleepSession>? sessions,
    String? openNightKey,
    bool clearOpenNight = false,
    List<String>? rewardedNights,
  }) {
    return SleepData(
      schedule: schedule ?? this.schedule,
      sessions: sessions ?? this.sessions,
      openNightKey: clearOpenNight ? null : (openNightKey ?? this.openNightKey),
      rewardedNights: rewardedNights ?? this.rewardedNights,
    );
  }

  Map<String, dynamic> toJson() => {
        'schedule': schedule.toJson(),
        'sessions': {
          for (final entry in sessions.entries) entry.key: entry.value.toJson(),
        },
        'open_night_key': openNightKey,
        'rewarded_nights': rewardedNights,
      };

  factory SleepData.fromJson(Map<String, dynamic> json) => SleepData(
        schedule: json['schedule'] is Map
            ? SleepSchedule.fromJson(
                Map<String, dynamic>.from(json['schedule'] as Map))
            : const SleepSchedule(),
        sessions: {
          for (final entry in (json['sessions'] as Map? ?? {}).entries)
            entry.key as String: SleepSession.fromJson(
                Map<String, dynamic>.from(entry.value as Map)),
        },
        openNightKey: json['open_night_key'] as String?,
        rewardedNights: [
          for (final key in (json['rewarded_nights'] as List? ?? []))
            key as String,
        ],
      );
}

/// Cómo de bien está una métrica. Alimenta el semáforo de la UI sin que cada
/// widget tenga que reimplementar los umbrales.
enum SleepGrade { good, fair, poor, unknown }

/// Resultado de la métrica "cuánto necesitas dormir tú".
typedef OptimalDuration = ({int minutes, double avgQuality, int nights});

/// Todas las métricas derivadas de las últimas semanas. Se calcula una vez por
/// cambio de estado (ver `sleepAnalyticsProvider`) en vez de en cada `build`.
class SleepAnalytics {
  final List<SleepSession> nights;
  final int goalMinutes;

  const SleepAnalytics({required this.nights, required this.goalMinutes});

  /// Noches con duración calculable, de la más antigua a la más reciente.
  List<SleepSession> get scored {
    final list = nights.where((n) => n.sleepMinutes != null).toList()
      ..sort((a, b) => a.nightKey.compareTo(b.nightKey));
    return list;
  }

  bool get hasData => scored.isNotEmpty;

  int get nightCount => scored.length;

  List<SleepSession> _lastN(int n) {
    final list = scored;
    return list.length <= n ? list : list.sublist(list.length - n);
  }

  double? _avgMinutes(List<SleepSession> list) {
    if (list.isEmpty) return null;
    final total = list.fold<int>(0, (sum, n) => sum + n.sleepMinutes!);
    return total / list.length;
  }

  /// Media de sueño de las últimas 7 noches registradas, en minutos.
  double? get avg7 => _avgMinutes(_lastN(7));

  /// Media de sueño de las últimas 30 noches registradas, en minutos.
  double? get avg30 => _avgMinutes(_lastN(30));

  /// Deuda acumulada en las últimas 14 noches, en minutos. Solo suma los
  /// déficits: dormir de más un día no "devuelve" el sueño perdido otro, que
  /// es como funciona de verdad la recuperación.
  int get sleepDebtMinutes {
    final debt = _lastN(14).fold<int>(
      0,
      (sum, n) => sum + math.max(0, goalMinutes - n.sleepMinutes!),
    );
    // Tope de 20 h: por encima el número deja de significar nada accionable.
    return math.min(debt, 20 * 60);
  }

  /// Desviación típica del punto medio del sueño (minutos) en las últimas 14
  /// noches. Es la versión ligera del Sleep Regularity Index: mide si te
  /// acuestas y levantas siempre a la misma hora, que predice el descanso
  /// incluso mejor que la duración total.
  double? get regularityMinutes {
    final mids = _lastN(14)
        .map((n) => n.midpointMinutes)
        .whereType<double>()
        .toList();
    if (mids.length < 3) return null;
    final mean = mids.reduce((a, b) => a + b) / mids.length;
    final variance =
        mids.fold<double>(0, (sum, m) => sum + math.pow(m - mean, 2)) / mids.length;
    return math.sqrt(variance);
  }

  SleepGrade get regularityGrade {
    final r = regularityMinutes;
    if (r == null) return SleepGrade.unknown;
    if (r < 30) return SleepGrade.good;
    if (r < 60) return SleepGrade.fair;
    return SleepGrade.poor;
  }

  /// Jet lag social: diferencia entre el punto medio del fin de semana y el de
  /// entre semana, en minutos. Más de 60 min es el umbral clásico de riesgo.
  double? get socialJetLagMinutes {
    final recent = _lastN(28);
    final weekend = <double>[];
    final weekday = <double>[];
    for (final night in recent) {
      final mid = night.midpointMinutes;
      if (mid == null) continue;
      // El día de la noche es el del despertar: sábado y domingo son los que
      // llevan el horario relajado del viernes y sábado noche.
      if (night.date.weekday >= DateTime.saturday) {
        weekend.add(mid);
      } else {
        weekday.add(mid);
      }
    }
    if (weekend.length < 2 || weekday.length < 3) return null;
    final wkndAvg = weekend.reduce((a, b) => a + b) / weekend.length;
    final wkdyAvg = weekday.reduce((a, b) => a + b) / weekday.length;
    return wkndAvg - wkdyAvg;
  }

  /// Eficiencia media (0–1) de las últimas 14 noches.
  double? get avgEfficiency {
    final values =
        _lastN(14).map((n) => n.efficiency).whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Porcentaje (0–1) de noches en las que se respetó la hora de acostarse.
  double? get bedtimeAdherence {
    final values = _lastN(14).map((n) => n.metBedtime).whereType<bool>().toList();
    if (values.isEmpty) return null;
    return values.where((v) => v).length / values.length;
  }

  /// Media de minutos entre que suena la alarma y que te levantas.
  double? get avgSnoozeMinutes {
    final values =
        _lastN(14).map((n) => n.snoozeMinutes).whereType<int>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Proporción (0–1) de mañanas en las que la alarma acabó ignorada.
  double? get ignoredRate {
    final recent = nights.where((n) => n.firstRingAt != null).toList();
    if (recent.isEmpty) return null;
    return recent.where((n) => n.alarmIgnored).length / recent.length;
  }

  /// Duración con mejor calidad percibida, en bloques de 30 min. Responde
  /// "¿cuántas horas necesito yo?" con los datos del usuario en vez de con el
  /// tópico de las 8 h. Necesita al menos 3 noches en el bloque para no
  /// declarar ganador a un único día bueno.
  OptimalDuration? get optimalDuration {
    final buckets = <int, List<int>>{};
    for (final night in scored) {
      final quality = night.quality;
      if (quality == null) continue;
      final bucket = (night.sleepMinutes! / 30).round() * 30;
      buckets.putIfAbsent(bucket, () => []).add(quality);
    }

    OptimalDuration? best;
    for (final entry in buckets.entries) {
      if (entry.value.length < 3) continue;
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      if (best == null || avg > best.avgQuality) {
        best = (minutes: entry.key, avgQuality: avg, nights: entry.value.length);
      }
    }
    return best;
  }

  /// Calidad media percibida de las últimas 14 noches (1–5).
  double? get avgQuality {
    final values = _lastN(14).map((n) => n.quality).whereType<int>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Noches consecutivas alcanzando la meta, contando hacia atrás desde la más
  /// reciente registrada. Un hueco sin registro corta la racha.
  int get goalStreak {
    final list = scored;
    var count = 0;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].sleepMinutes! < goalMinutes) break;
      count++;
    }
    return count;
  }

  /// Media móvil de 7 días alineada con [scored], para pintarla sobre las
  /// barras de duración. Cada punto es la media de esa noche y las 6 previas.
  List<double> get rollingAverage7 {
    final list = scored;
    return [
      for (var i = 0; i < list.length; i++)
        () {
          final from = math.max(0, i - 6);
          final window = list.sublist(from, i + 1);
          return window.fold<int>(0, (s, n) => s + n.sleepMinutes!) / window.length;
        }(),
    ];
  }
}

/// Formatea minutos como "7 h 20 m". Usado por toda la UI de sueño.
String formatSleepMinutes(num? minutes) {
  if (minutes == null) return '—';
  final total = minutes.round().abs();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m m';
  if (m == 0) return '$h h';
  return '$h h $m m';
}

/// Formatea minutos desde medianoche con envoltura ("−10" → "23:50").
String formatClockMinutes(num? minutes) {
  if (minutes == null) return '—';
  var value = minutes.round() % 1440;
  if (value < 0) value += 1440;
  final h = value ~/ 60;
  final m = value % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
