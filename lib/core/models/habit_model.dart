import 'package:flutter/material.dart';
import '../theme/bento_theme.dart';

enum HabitCategory {
  health('health', 'Salud', BentoTheme.successGreen, Icons.favorite_border),
  mind('mind', 'Mente', BentoTheme.accentBlue, Icons.self_improvement),
  productivity('productivity', 'Productividad', BentoTheme.accentOrange, Icons.bolt_outlined),
  learning('learning', 'Aprendizaje', BentoTheme.accentPurple, Icons.school_outlined),
  social('social', 'Social', BentoTheme.errorRed, Icons.groups_outlined),
  general('general', 'General', BentoTheme.primaryDark, Icons.circle_outlined);

  final String value;
  final String label;
  final Color color;
  final IconData icon;
  const HabitCategory(this.value, this.label, this.color, this.icon);

  static HabitCategory fromValue(String? v) => HabitCategory.values.firstWhere(
        (c) => c.value == v,
        orElse: () => HabitCategory.general,
      );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Habit {
  final String id;
  final String name;
  final String icon; // emoji
  final String color; // hex, ej. '#758BFD'
  final HabitCategory category;
  final List<int> daysOfWeek; // 1=Lunes..7=Domingo (DateTime.weekday)
  final bool archived;
  final DateTime? createdAt;
  final Set<DateTime> completedDates; // normalizadas a medianoche local
  final double? goalValue; // ej. 2.0 (litros), 30 (minutos), 10000 (pasos)
  final String? goalUnit; // ej. 'L', 'min', 'pasos', 'páginas'
  final int? reminderHour; // hora local del recordatorio diario (0-23), null = sin recordatorio
  final int? reminderMinute;
  final List<String> reminderTimes; // ej. ['08:00', '10:00']
  final Map<DateTime, double> dailyProgress; // mapas de progreso por fecha

  Habit({
    required this.id,
    required this.name,
    this.icon = '✅',
    this.color = '#758BFD',
    this.category = HabitCategory.general,
    List<int>? daysOfWeek,
    this.archived = false,
    this.createdAt,
    Set<DateTime>? completedDates,
    this.goalValue,
    this.goalUnit,
    this.reminderHour,
    this.reminderMinute,
    List<String>? reminderTimes,
    Map<DateTime, double>? dailyProgress,
  })  : daysOfWeek = daysOfWeek ?? const [1, 2, 3, 4, 5, 6, 7],
        completedDates = completedDates ?? <DateTime>{},
        reminderTimes = reminderTimes ?? const [],
        dailyProgress = dailyProgress ?? const <DateTime, double>{};

  Color get colorValue => Color(int.parse(color.replaceFirst('#', '0xFF')));

  bool get hasReminder => reminderTimes.isNotEmpty || (reminderHour != null && reminderMinute != null);

  String? get goalLabel {
    if (goalValue == null) return null;
    final formatted = goalValue! % 1 == 0 ? goalValue!.toInt().toString() : goalValue!.toString();
    return goalUnit == null || goalUnit!.isEmpty ? formatted : '$formatted ${goalUnit!}';
  }

  bool isActiveOn(DateTime day) => daysOfWeek.contains(day.weekday);

  bool isCompletedOn(DateTime day) {
    final dayOnly = _dateOnly(day);
    if (goalValue != null) {
      final progress = dailyProgress[dayOnly] ?? 0.0;
      return progress >= goalValue!;
    }
    return completedDates.contains(dayOnly);
  }

  /// Racha actual: cuenta hacia atrás desde hoy, saltando días no activos,
  /// y sin romper la racha si el día de hoy (activo) aún no se completó.
  int currentStreak({DateTime? now}) {
    var cursor = _dateOnly(now ?? DateTime.now());
    if (isActiveOn(cursor) && !isCompletedOn(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (true) {
      if (isActiveOn(cursor)) {
        if (isCompletedOn(cursor)) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        } else {
          break;
        }
      } else {
        cursor = cursor.subtract(const Duration(days: 1));
      }
      // Salvaguarda: nunca miramos más de ~2 años atrás.
      if (now == null && streak > 730) break;
    }
    return streak;
  }

  /// Mejor racha histórica registrada, con la misma lógica de saltar días no activos.
  int bestStreak({DateTime? now}) {
    if (completedDates.isEmpty) return 0;
    final today = _dateOnly(now ?? DateTime.now());
    var start = completedDates.reduce((a, b) => a.isBefore(b) ? a : b);
    if (createdAt != null && _dateOnly(createdAt!).isBefore(start)) {
      start = _dateOnly(createdAt!);
    }

    int best = 0;
    int run = 0;
    var cursor = start;
    while (!cursor.isAfter(today)) {
      if (isActiveOn(cursor)) {
        if (isCompletedOn(cursor)) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return best;
  }

  /// % de cumplimiento sobre los días activos de la ventana [days] terminando hoy.
  double completionRate({int days = 30, DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    int expected = 0;
    int done = 0;
    for (int i = 0; i < days; i++) {
      final day = today.subtract(Duration(days: i));
      if (isActiveOn(day)) {
        expected++;
        if (isCompletedOn(day)) done++;
      }
    }
    if (expected == 0) return 0;
    return done / expected;
  }

  Habit copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    HabitCategory? category,
    List<int>? daysOfWeek,
    bool? archived,
    DateTime? createdAt,
    Set<DateTime>? completedDates,
    double? goalValue,
    bool clearGoal = false,
    String? goalUnit,
    int? reminderHour,
    int? reminderMinute,
    bool clearReminder = false,
    List<String>? reminderTimes,
    Map<DateTime, double>? dailyProgress,
  }) {
    return Habit(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      category: category ?? this.category,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      completedDates: completedDates ?? this.completedDates,
      goalValue: clearGoal ? null : (goalValue ?? this.goalValue),
      goalUnit: clearGoal ? null : (goalUnit ?? this.goalUnit),
      reminderHour: clearReminder ? null : (reminderHour ?? this.reminderHour),
      reminderMinute: clearReminder ? null : (reminderMinute ?? this.reminderMinute),
      reminderTimes: clearReminder ? const [] : (reminderTimes ?? this.reminderTimes),
      dailyProgress: dailyProgress ?? this.dailyProgress,
    );
  }

  factory Habit.fromJson(Map<String, dynamic> json, {Set<DateTime>? completedDates, Map<DateTime, double>? dailyProgress}) {
    return Habit(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '✅',
      color: json['color'] as String? ?? '#758BFD',
      category: HabitCategory.fromValue(json['category'] as String?),
      daysOfWeek: List<int>.from(json['days_of_week'] as List? ?? const [1, 2, 3, 4, 5, 6, 7]),
      archived: json['archived'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String).toLocal() : null,
      completedDates: completedDates ?? <DateTime>{},
      goalValue: (json['goal_value'] as num?)?.toDouble(),
      goalUnit: json['goal_unit'] as String?,
      reminderHour: json['reminder_hour'] as int?,
      reminderMinute: json['reminder_minute'] as int?,
      reminderTimes: json['reminder_times'] != null
          ? List<String>.from(json['reminder_times'] as List)
          : const [],
      dailyProgress: dailyProgress,
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
        'user_id': userId,
        'name': name,
        'icon': icon,
        'color': color,
        'category': category.value,
        'days_of_week': daysOfWeek,
        'goal_value': goalValue,
        'goal_unit': goalUnit,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
        'reminder_times': reminderTimes,
      };

  Map<String, dynamic> toUpdateJson() => {
        'name': name,
        'icon': icon,
        'color': color,
        'category': category.value,
        'days_of_week': daysOfWeek,
        'archived': archived,
        'goal_value': goalValue,
        'goal_unit': goalUnit,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
        'reminder_times': reminderTimes,
      };
}
