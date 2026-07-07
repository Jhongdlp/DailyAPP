import 'package:flutter/material.dart';
import '../theme/bento_theme.dart';

enum NotePriority {
  low(0, 'Baja', BentoTheme.textSecondary, Icons.arrow_downward),
  normal(1, 'Normal', BentoTheme.accentBlue, Icons.remove),
  high(2, 'Alta', BentoTheme.accentOrange, Icons.arrow_upward),
  urgent(3, 'Urgente', BentoTheme.errorRed, Icons.priority_high);

  final int value;
  final String label;
  final Color color;
  final IconData icon;
  const NotePriority(this.value, this.label, this.color, this.icon);

  static NotePriority fromValue(int? v) =>
      NotePriority.values.firstWhere((p) => p.value == v,
          orElse: () => NotePriority.normal);
}

class Note {
  final String id;
  final String title;
  final String content;
  final List<String> linkedNoteIds;
  final NotePriority priority;
  final DateTime? remindAt; // Recordatorio por notificación (null = sin recordatorio)
  final bool selfDestruct; // Se elimina sola después de que el recordatorio pase
  final DateTime? createdAt;
  final String? vaultId;   // ID de la bóveda a la que pertenece (null = Sin clasificar)

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.linkedNoteIds,
    this.priority = NotePriority.normal,
    this.remindAt,
    this.selfDestruct = false,
    this.createdAt,
    this.vaultId,
  });

  bool get isReminderPending =>
      remindAt != null && remindAt!.isAfter(DateTime.now());

  bool get isExpired =>
      selfDestruct && remindAt != null && remindAt!.isBefore(DateTime.now());

  Note copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? linkedNoteIds,
    NotePriority? priority,
    DateTime? remindAt,
    bool clearRemindAt = false,
    bool? selfDestruct,
    DateTime? createdAt,
    String? vaultId,
    bool clearVaultId = false,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      linkedNoteIds: linkedNoteIds ?? this.linkedNoteIds,
      priority: priority ?? this.priority,
      remindAt: clearRemindAt ? null : (remindAt ?? this.remindAt),
      selfDestruct: selfDestruct ?? this.selfDestruct,
      createdAt: createdAt ?? this.createdAt,
      vaultId: clearVaultId ? null : (vaultId ?? this.vaultId),
    );
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      linkedNoteIds: List<String>.from(json['linked_note_ids'] as List? ?? []),
      priority: NotePriority.fromValue(json['priority'] as int?),
      remindAt: json['remind_at'] != null
          ? DateTime.parse(json['remind_at'] as String).toLocal()
          : null,
      selfDestruct: json['self_destruct'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : null,
      vaultId: json['vault_id'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson(String userId, List<String> validLinkIds) => {
        'user_id': userId,
        'title': title,
        'content': content,
        'linked_note_ids': validLinkIds,
        'priority': priority.value,
        'remind_at': remindAt?.toUtc().toIso8601String(),
        'self_destruct': selfDestruct,
        'vault_id': vaultId,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'title': title,
        'content': content,
        'linked_note_ids': linkedNoteIds,
        'priority': priority.value,
        'remind_at': remindAt?.toIso8601String(),
        'self_destruct': selfDestruct,
        'created_at': createdAt?.toIso8601String(),
        'vault_id': vaultId,
      };

  factory Note.fromCacheJson(Map<String, dynamic> json) => Note.fromJson(json);
}
