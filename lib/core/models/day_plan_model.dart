DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Una noche de planeación: el registro de haber pensado un día por adelantado.
///
/// Existe aparte de los bloques porque lo que queremos medir no es cuántas
/// tareas hiciste, sino cuántas noches te sentaste a planear. Esa es la
/// conducta que sostiene el sistema; los bloques son su consecuencia.
class DayPlan {
  final String id;

  /// El día que se planea (normalmente mañana), no la noche en que se planeó.
  final DateTime planDate;

  /// Cómo quiero que sea mañana. Formulada por mí, no por la app.
  final String? intention;

  /// Cierre del día que termina.
  final String? reflection;

  /// Ánimo al cerrar el día, 1..5.
  final int? mood;

  final bool ritualCompleted;
  final DateTime plannedAt;

  const DayPlan({
    required this.id,
    required this.planDate,
    this.intention,
    this.reflection,
    this.mood,
    this.ritualCompleted = false,
    required this.plannedAt,
  });

  DayPlan copyWith({
    String? id,
    DateTime? planDate,
    String? intention,
    bool clearIntention = false,
    String? reflection,
    bool clearReflection = false,
    int? mood,
    bool clearMood = false,
    bool? ritualCompleted,
    DateTime? plannedAt,
  }) {
    return DayPlan(
      id: id ?? this.id,
      planDate: planDate ?? this.planDate,
      intention: clearIntention ? null : (intention ?? this.intention),
      reflection: clearReflection ? null : (reflection ?? this.reflection),
      mood: clearMood ? null : (mood ?? this.mood),
      ritualCompleted: ritualCompleted ?? this.ritualCompleted,
      plannedAt: plannedAt ?? this.plannedAt,
    );
  }

  factory DayPlan.fromJson(Map<String, dynamic> json) => DayPlan(
        id: json['id'] as String,
        planDate: _dateOnly(DateTime.parse(json['plan_date'] as String)),
        intention: json['intention'] as String?,
        reflection: json['reflection'] as String?,
        mood: (json['mood'] as num?)?.toInt(),
        ritualCompleted: json['ritual_completed'] as bool? ?? false,
        plannedAt: DateTime.parse(json['planned_at'] as String).toLocal(),
      );

  Map<String, dynamic> toUpsertJson(String userId) => {
        'user_id': userId,
        'plan_date': _fmtDate(planDate),
        'intention': intention,
        'reflection': reflection,
        'mood': mood,
        'ritual_completed': ritualCompleted,
        'planned_at': plannedAt.toUtc().toIso8601String(),
      };

  // Como en Task: la caché guarda horas locales sin offset.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'plan_date': _fmtDate(planDate),
        'intention': intention,
        'reflection': reflection,
        'mood': mood,
        'ritual_completed': ritualCompleted,
        'planned_at': plannedAt.toIso8601String(),
      };

  factory DayPlan.fromCacheJson(Map<String, dynamic> json) => DayPlan(
        id: json['id'] as String,
        planDate: _dateOnly(DateTime.parse(json['plan_date'] as String)),
        intention: json['intention'] as String?,
        reflection: json['reflection'] as String?,
        mood: (json['mood'] as num?)?.toInt(),
        ritualCompleted: json['ritual_completed'] as bool? ?? false,
        plannedAt: DateTime.parse(json['planned_at'] as String),
      );
}
