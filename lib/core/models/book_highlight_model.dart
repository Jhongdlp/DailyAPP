import 'package:flutter/material.dart';

/// Colores disponibles para resaltar. Se guarda el nombre, no el valor, para
/// que el resaltado se adapte al modo de lectura (claro, sepia, oscuro).
enum HighlightColor {
  yellow('Amarillo', Color(0xFFFFD54F)),
  green('Verde', Color(0xFF7CD992)),
  blue('Azul', Color(0xFF6FB1FF)),
  pink('Rosa', Color(0xFFFF8FB1)),
  purple('Morado', Color(0xFFB79CFF));

  const HighlightColor(this.label, this.color);

  final String label;
  final Color color;

  static HighlightColor fromName(String? name) => HighlightColor.values.firstWhere(
        (c) => c.name == name,
        orElse: () => HighlightColor.yellow,
      );
}

/// Fragmento resaltado dentro de un libro.
///
/// Se ancla por [paragraphIndex] (índice absoluto del párrafo en el libro)
/// porque el CFI de `epub_view` apunta al párrafo visible, no al rango exacto
/// que seleccionó el usuario; el texto se re-busca dentro de ese párrafo al
/// pintarlo.
///
/// Vive solo en almacenamiento local: los resaltados son muchos y se consultan
/// en cada repintado de párrafo, así que no compensa pagar red por ellos.
class BookHighlight {
  final String id;
  final String bookId;
  final String text;
  final String? note;
  final HighlightColor color;
  final String? position;
  final int? paragraphIndex;
  final String? chapterTitle;

  /// Nota de la Máquina de Conocimiento creada a partir de este resaltado.
  final String? noteId;

  final DateTime? createdAt;

  BookHighlight({
    required this.id,
    required this.bookId,
    required this.text,
    this.note,
    this.color = HighlightColor.yellow,
    this.position,
    this.paragraphIndex,
    this.chapterTitle,
    this.noteId,
    this.createdAt,
  });

  BookHighlight copyWith({
    String? note,
    HighlightColor? color,
    String? noteId,
  }) {
    return BookHighlight(
      id: id,
      bookId: bookId,
      text: text,
      note: note ?? this.note,
      color: color ?? this.color,
      position: position,
      paragraphIndex: paragraphIndex,
      chapterTitle: chapterTitle,
      noteId: noteId ?? this.noteId,
      createdAt: createdAt,
    );
  }

  factory BookHighlight.fromJson(Map<String, dynamic> json) => BookHighlight(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        text: json['text'] as String? ?? '',
        note: json['note'] as String?,
        color: HighlightColor.fromName(json['color'] as String?),
        position: json['position'] as String?,
        paragraphIndex: json['paragraph_index'] as int?,
        chapterTitle: json['chapter_title'] as String?,
        noteId: json['note_id'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String).toLocal()
            : null,
      );

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'book_id': bookId,
        'text': text,
        'note': note,
        'color': color.name,
        'position': position,
        'paragraph_index': paragraphIndex,
        'chapter_title': chapterTitle,
        'note_id': noteId,
        'created_at': createdAt?.toIso8601String(),
      };

  factory BookHighlight.fromCacheJson(Map<String, dynamic> json) =>
      BookHighlight.fromJson(json);
}
