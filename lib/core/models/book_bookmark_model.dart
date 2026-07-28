class BookBookmark {
  final String id;
  final String bookId;
  final String position;
  final String? label;
  final DateTime? createdAt;

  BookBookmark({
    required this.id,
    required this.bookId,
    required this.position,
    this.label,
    this.createdAt,
  });

  factory BookBookmark.fromJson(Map<String, dynamic> json) => BookBookmark(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        position: json['position'] as String,
        label: json['label'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String).toLocal()
            : null,
      );

  Map<String, dynamic> toInsertJson(String userId) => {
        'user_id': userId,
        'book_id': bookId,
        'position': position,
        'label': label,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'book_id': bookId,
        'position': position,
        'label': label,
        'created_at': createdAt?.toIso8601String(),
      };

  factory BookBookmark.fromCacheJson(Map<String, dynamic> json) => BookBookmark.fromJson(json);
}
