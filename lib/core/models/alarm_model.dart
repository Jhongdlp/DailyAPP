class AlarmModel {
  final String id;
  final String userId;
  final bool enabled;
  final int hour;
  final int minute;
  final String targetObject;
  final String label;
  final List<int> daysOfWeek;
  final DateTime createdAt;

  /// Hora de acostarse. Si está puesta, esta alarma no es un despertador
  /// suelto sino un **horario de sueño completo**: cubre de la hora de dormir
  /// a la de despertar, y solo suena en el extremo del despertar.
  ///
  /// Va aquí y no en una entidad aparte porque para el usuario es una sola
  /// cosa ("mi alarma, de 23:00 a 7:00") y tiene que poder crearla, verla y
  /// apagarla desde la misma lista que las demás.
  final int? bedtimeHour;
  final int? bedtimeMinute;

  const AlarmModel({
    required this.id,
    required this.userId,
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.targetObject,
    required this.label,
    required this.daysOfWeek,
    required this.createdAt,
    this.bedtimeHour,
    this.bedtimeMinute,
  });

  /// ¿Es el horario de sueño (dormir → despertar) y no una alarma suelta?
  bool get isSleepAlarm => bedtimeHour != null && bedtimeMinute != null;

  /// "23:00" — hora de acostarse, o `null` si no es alarma de sueño.
  String? get formattedBedtime => isSleepAlarm
      ? '${bedtimeHour!.toString().padLeft(2, '0')}:'
          '${bedtimeMinute!.toString().padLeft(2, '0')}'
      : null;

  String? get bedtime12 {
    if (!isSleepAlarm) return null;
    final h12 = bedtimeHour! % 12 == 0 ? 12 : bedtimeHour! % 12;
    return '$h12:${bedtimeMinute!.toString().padLeft(2, '0')}';
  }

  String? get bedtimeAmPm => isSleepAlarm ? (bedtimeHour! < 12 ? 'AM' : 'PM') : null;

  /// Minutos entre acostarse y que suene, cruzando medianoche si hace falta.
  int? get sleepWindowMinutes {
    if (!isSleepAlarm) return null;
    final start = bedtimeHour! * 60 + bedtimeMinute!;
    final end = hour * 60 + minute;
    final diff = end - start;
    return diff <= 0 ? diff + 1440 : diff;
  }

  /// "8 h" / "7 h 30 min" — cuánto dormirías cumpliendo el horario.
  String? get sleepWindowLabel {
    final minutes = sleepWindowMinutes;
    if (minutes == null) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  factory AlarmModel.fromJson(Map<String, dynamic> json) {
    return AlarmModel(
      id: json['id'] as String,
      userId: (json['user_id'] as String?) ?? '',
      enabled: json['enabled'] as bool,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      targetObject: json['target_object'] as String,
      label: (json['label'] as String?) ?? 'Alarma',
      daysOfWeek: json['days_of_week'] != null
          ? List<int>.from(json['days_of_week'] as List)
          : [1, 2, 3, 4, 5, 6, 7],
      createdAt: DateTime.parse(json['created_at'] as String),
      bedtimeHour: (json['bedtime_hour'] as num?)?.toInt(),
      bedtimeMinute: (json['bedtime_minute'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'target_object': targetObject,
        'label': label,
        'days_of_week': daysOfWeek,
        'created_at': createdAt.toIso8601String(),
        'bedtime_hour': bedtimeHour,
        'bedtime_minute': bedtimeMinute,
      };

  AlarmModel copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    String? targetObject,
    String? label,
    List<int>? daysOfWeek,
    int? bedtimeHour,
    int? bedtimeMinute,

    /// Degrada la alarma de sueño a alarma normal. Hace falta explícito porque
    /// `copyWith` no puede distinguir "no lo toques" de "ponlo a null".
    bool clearBedtime = false,
  }) {
    return AlarmModel(
      id: id,
      userId: userId,
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      targetObject: targetObject ?? this.targetObject,
      label: label ?? this.label,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      createdAt: createdAt,
      bedtimeHour: clearBedtime ? null : (bedtimeHour ?? this.bedtimeHour),
      bedtimeMinute:
          clearBedtime ? null : (bedtimeMinute ?? this.bedtimeMinute),
    );
  }

  String get formattedTime {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Hora en formato 12h sin el sufijo (ej: "7:30")
  String get time12 {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h12:$m';
  }

  /// Sufijo AM/PM
  String get amPm => hour < 12 ? 'AM' : 'PM';

  /// Próxima fecha/hora en la que sonará esta alarma (null si no hay días)
  DateTime? nextTrigger({DateTime? from}) {
    if (daysOfWeek.isEmpty) return null;
    final now = from ?? DateTime.now();
    for (int i = 0; i < 8; i++) {
      final candidate = DateTime(now.year, now.month, now.day, hour, minute)
          .add(Duration(days: i));
      if (candidate.isAfter(now) && daysOfWeek.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  /// Próxima hora de acostarse según este horario, o `null` si no es alarma de
  /// sueño. Los días marcados son los del **despertar**, así que la noche del
  /// lunes al martes cuenta como martes: hay que retroceder un día cuando la
  /// hora de dormir cae antes de medianoche.
  DateTime? nextBedtime({DateTime? from}) {
    if (!isSleepAlarm || daysOfWeek.isEmpty) return null;
    final now = from ?? DateTime.now();
    // Acostarse por la noche pertenece al despertar del día siguiente.
    final crossesMidnight = bedtimeHour! > hour ||
        (bedtimeHour! == hour && bedtimeMinute! > minute);

    for (var i = 0; i < 8; i++) {
      final candidate =
          DateTime(now.year, now.month, now.day, bedtimeHour!, bedtimeMinute!)
              .add(Duration(days: i));
      final wakeDay = crossesMidnight
          ? candidate.add(const Duration(days: 1))
          : candidate;
      if (candidate.isAfter(now) && daysOfWeek.contains(wakeDay.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  /// Texto tipo "Suena en 7 h 30 min"
  String? get untilLabel {
    final next = nextTrigger();
    if (next == null) return null;
    final diff = next.difference(DateTime.now());
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) return 'Suena en $days d $hours h';
    if (hours > 0) return 'Suena en $hours h $mins min';
    if (mins > 0) return 'Suena en $mins min';
    return 'Suena en menos de 1 min';
  }

  String get daysLabel {
    if (daysOfWeek.length == 7) return 'Todos los días';
    if (daysOfWeek.isEmpty) return 'Sin días';
    const names = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final sorted = [...daysOfWeek]..sort();
    return sorted.map((d) => names[d]).join(', ');
  }
}
