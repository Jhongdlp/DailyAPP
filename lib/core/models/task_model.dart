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
  });

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
      };

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
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
