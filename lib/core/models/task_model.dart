import 'package:flutter/material.dart';
import '../theme/bento_theme.dart';

enum TaskPriority {
  low(0, 'Baja'),
  normal(1, 'Normal'),
  high(2, 'Alta');

  final int value;
  final String label;
  const TaskPriority(this.value, this.label);

  /// El color no puede ser un campo del enum: el constructor exige argumentos
  /// const, y los acentos son getters que resuelven contra el modo claro/oscuro.
  Color get color => switch (this) {
        TaskPriority.low => BentoTheme.creamAlpha(0.4),
        TaskPriority.normal => BentoTheme.accentBlue,
        TaskPriority.high => BentoTheme.errorRed,
      };

  static TaskPriority fromValue(int? v) => TaskPriority.values.firstWhere(
        (p) => p.value == v,
        orElse: () => TaskPriority.normal,
      );
}

/// Naturaleza del bloque. No es lo mismo "trabajo profundo" que "descanso":
/// separarlos permite avisar cuando el día está lleno de trabajo sin huecos,
/// y colorear el timeline por tipo de energía y no solo por prioridad.
enum BlockType {
  task('task', 'Tarea', Icons.check_circle_outline),
  habit('habit', 'Hábito', Icons.local_fire_department_outlined),
  deep('deep', 'Foco', Icons.bolt_outlined),
  admin('admin', 'Trámite', Icons.inbox_outlined),
  rest('rest', 'Descanso', Icons.self_improvement),
  personal('personal', 'Personal', Icons.favorite_border);

  final String value;
  final String label;
  final IconData icon;
  const BlockType(this.value, this.label, this.icon);

  Color get color => switch (this) {
        BlockType.task => BentoTheme.accentBlue,
        BlockType.habit => BentoTheme.accentLime,
        BlockType.deep => BentoTheme.accentPurple,
        BlockType.admin => BentoTheme.accentOrange,
        BlockType.rest => BentoTheme.successGreen,
        BlockType.personal => BentoTheme.accentHabits,
      };

  static BlockType fromValue(String? v) => BlockType.values.firstWhere(
        (b) => b.value == v,
        orElse: () => BlockType.task,
      );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Task {
  final String id;
  final String title;
  final String? notes;
  final DateTime dueDate; // día al que pertenece el bloque (normalizado a medianoche local)
  final DateTime startAt;
  final DateTime? endAt;
  final DateTime? remindAt;
  final TaskPriority priority;
  final bool completed;
  final DateTime? completedAt;
  final DateTime? createdAt;

  /// Hábito al que representa este bloque, si lo hay. Para estos bloques la
  /// verdad sobre "está hecho" vive en el `Habit` (habit_logs), no en
  /// [completed]: así no hay dos estados que sincronizar.
  final String? habitId;
  final BlockType blockType;

  /// Dónde ocurre. Completa la intención de implementación
  /// ("a las 6:30 voy a correr EN EL PARQUE"), que es lo que de verdad
  /// levanta la tasa de cumplimiento.
  final String? location;

  /// Uno de los 3 grandes del día.
  final bool isMit;

  /// Cuándo se planeó (no cuándo ocurre). Distingue lo planeado la noche
  /// anterior de lo improvisado sobre la marcha.
  final DateTime? plannedAt;

  Task({
    required this.id,
    required this.title,
    this.notes,
    required this.dueDate,
    required this.startAt,
    this.endAt,
    this.remindAt,
    this.priority = TaskPriority.normal,
    this.completed = false,
    this.completedAt,
    this.createdAt,
    this.habitId,
    this.blockType = BlockType.task,
    this.location,
    this.isMit = false,
    this.plannedAt,
  });

  bool get isHabitBlock => habitId != null;

  /// Se planeó por adelantado, no sobre la marcha del propio día.
  bool get wasPlannedAhead => plannedAt != null && _dateOnly(plannedAt!).isBefore(dueDate);

  bool get hasReminder => remindAt != null;

  bool get isOverdue => !completed && dueDate.isBefore(_dateOnly(DateTime.now()));

  bool get isToday => dueDate == _dateOnly(DateTime.now());

  int? get durationMinutes => endAt?.difference(startAt).inMinutes;

  Task copyWith({
    String? id,
    String? title,
    String? notes,
    bool clearNotes = false,
    DateTime? dueDate,
    DateTime? startAt,
    DateTime? endAt,
    bool clearEndAt = false,
    DateTime? remindAt,
    bool clearReminder = false,
    TaskPriority? priority,
    bool? completed,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    String? habitId,
    bool clearHabitId = false,
    BlockType? blockType,
    String? location,
    bool clearLocation = false,
    bool? isMit,
    DateTime? plannedAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: clearNotes ? null : (notes ?? this.notes),
      dueDate: dueDate ?? this.dueDate,
      startAt: startAt ?? this.startAt,
      endAt: clearEndAt ? null : (endAt ?? this.endAt),
      remindAt: clearReminder ? null : (remindAt ?? this.remindAt),
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt ?? this.createdAt,
      habitId: clearHabitId ? null : (habitId ?? this.habitId),
      blockType: blockType ?? this.blockType,
      location: clearLocation ? null : (location ?? this.location),
      isMit: isMit ?? this.isMit,
      plannedAt: plannedAt ?? this.plannedAt,
    );
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      notes: json['notes'] as String?,
      dueDate: DateTime.parse(json['due_date'] as String),
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: json['end_at'] != null ? DateTime.parse(json['end_at'] as String).toLocal() : null,
      remindAt: json['remind_at'] != null ? DateTime.parse(json['remind_at'] as String).toLocal() : null,
      priority: TaskPriority.fromValue(json['priority'] as int?),
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String).toLocal() : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String).toLocal() : null,
      habitId: json['habit_id'] as String?,
      blockType: BlockType.fromValue(json['block_type'] as String?),
      location: json['location'] as String?,
      isMit: json['is_mit'] as bool? ?? false,
      plannedAt: json['planned_at'] != null ? DateTime.parse(json['planned_at'] as String).toLocal() : null,
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
        'user_id': userId,
        'title': title,
        'notes': notes,
        'due_date': _fmtDate(dueDate),
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': endAt?.toUtc().toIso8601String(),
        'remind_at': remindAt?.toUtc().toIso8601String(),
        'priority': priority.value,
        'completed': completed,
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'habit_id': habitId,
        'block_type': blockType.value,
        'location': location,
        'is_mit': isMit,
        'planned_at': plannedAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'notes': notes,
        'due_date': _fmtDate(dueDate),
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': endAt?.toUtc().toIso8601String(),
        'remind_at': remindAt?.toUtc().toIso8601String(),
        'priority': priority.value,
        'completed': completed,
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'habit_id': habitId,
        'block_type': blockType.value,
        'location': location,
        'is_mit': isMit,
        'planned_at': plannedAt?.toUtc().toIso8601String(),
      };

  // Ojo: la caché guarda horas LOCALES sin offset, a diferencia de los JSON de
  // Supabase que van en UTC. Es la convención que ya seguía este modelo.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'due_date': _fmtDate(dueDate),
        'start_at': startAt.toIso8601String(),
        'end_at': endAt?.toIso8601String(),
        'remind_at': remindAt?.toIso8601String(),
        'priority': priority.value,
        'completed': completed,
        'completed_at': completedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'habit_id': habitId,
        'block_type': blockType.value,
        'location': location,
        'is_mit': isMit,
        'planned_at': plannedAt?.toIso8601String(),
      };

  factory Task.fromCacheJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      notes: json['notes'] as String?,
      dueDate: DateTime.parse(json['due_date'] as String),
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: json['end_at'] != null ? DateTime.parse(json['end_at'] as String) : null,
      remindAt: json['remind_at'] != null ? DateTime.parse(json['remind_at'] as String) : null,
      priority: TaskPriority.fromValue(json['priority'] as int?),
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      habitId: json['habit_id'] as String?,
      blockType: BlockType.fromValue(json['block_type'] as String?),
      location: json['location'] as String?,
      isMit: json['is_mit'] as bool? ?? false,
      plannedAt: json['planned_at'] != null ? DateTime.parse(json['planned_at'] as String) : null,
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
