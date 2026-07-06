import 'package:flutter/material.dart';

/// Representa una "bóveda" (vault) de notas al estilo Obsidian.
/// Cada bóveda agrupa notas por tipo/tema (ej: Personal, Trabajo, Ideas, etc.)
class NoteVault {
  final String id;
  final String name;
  final String icon;      // Emoji o nombre de icono
  final String color;     // Hex color string
  final String? description;
  final int noteCount;    // Calculado en el cliente
  final DateTime? createdAt;

  const NoteVault({
    required this.id,
    required this.name,
    this.icon = '📁',
    this.color = '#758BFD',
    this.description,
    this.noteCount = 0,
    this.createdAt,
  });

  Color get flutterColor {
    try {
      final hex = color.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF758BFD);
    }
  }

  NoteVault copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    String? description,
    int? noteCount,
    DateTime? createdAt,
  }) {
    return NoteVault(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      description: description ?? this.description,
      noteCount: noteCount ?? this.noteCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory NoteVault.fromJson(Map<String, dynamic> json) {
    return NoteVault(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '📁',
      color: json['color'] as String? ?? '#758BFD',
      description: json['description'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
        'user_id': userId,
        'name': name,
        'icon': icon,
        'color': color,
        'description': description,
      };
}

/// Opciones predefinidas de emojis para bóvedas
const vaultEmojiOptions = [
  '📁', '📚', '💡', '🧠', '💼', '🏠', '🎯', '🔬', '🎨', '📝',
  '🌱', '💰', '🏋️', '🎵', '📷', '🌍', '🔧', '📊', '🚀', '❤️',
  '⚡', '🌟', '🎮', '🔮', '📰', '🧪', '🌈', '🦋', '🏆', '🎓',
];

/// Opciones predefinidas de colores para bóvedas
const vaultColorOptions = [
  '#758BFD', '#27187E', '#FF8600', '#8A84E2', '#38B000',
  '#D90429', '#06D6A0', '#FFB703', '#FB8500', '#023E8A',
  '#6A0572', '#0077B6', '#F72585', '#4CC9F0', '#7B2D8B',
];
