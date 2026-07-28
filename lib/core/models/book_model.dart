enum BookFormat {
  pdf,
  epub;

  static BookFormat fromValue(String v) =>
      BookFormat.values.firstWhere((f) => f.name == v, orElse: () => BookFormat.pdf);
}

class Book {
  final String id;
  final String title;
  final String? author;
  final BookFormat format;
  final String localFilename;
  final int? totalPages;
  final String? lastPosition;
  final double? progressPercent;
  final DateTime? addedAt;
  final DateTime? lastOpenedAt;

  Book({
    required this.id,
    required this.title,
    this.author,
    required this.format,
    required this.localFilename,
    this.totalPages,
    this.lastPosition,
    this.progressPercent,
    this.addedAt,
    this.lastOpenedAt,
  });

  Book copyWith({
    String? title,
    String? author,
    int? totalPages,
    String? lastPosition,
    double? progressPercent,
    DateTime? lastOpenedAt,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format,
      localFilename: localFilename,
      totalPages: totalPages ?? this.totalPages,
      lastPosition: lastPosition ?? this.lastPosition,
      progressPercent: progressPercent ?? this.progressPercent,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String?,
        format: BookFormat.fromValue(json['format'] as String),
        localFilename: json['local_filename'] as String,
        totalPages: json['total_pages'] as int?,
        lastPosition: json['last_position'] as String?,
        progressPercent: (json['progress_percent'] as num?)?.toDouble(),
        addedAt: json['added_at'] != null
            ? DateTime.parse(json['added_at'] as String).toLocal()
            : null,
        lastOpenedAt: json['last_opened_at'] != null
            ? DateTime.parse(json['last_opened_at'] as String).toLocal()
            : null,
      );

  Map<String, dynamic> toInsertJson(String userId) => {
        'user_id': userId,
        'title': title,
        'author': author,
        'format': format.name,
        'local_filename': localFilename,
        'total_pages': totalPages,
        'last_position': lastPosition,
        'progress_percent': progressPercent,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format.name,
        'local_filename': localFilename,
        'total_pages': totalPages,
        'last_position': lastPosition,
        'progress_percent': progressPercent,
        'added_at': addedAt?.toIso8601String(),
        'last_opened_at': lastOpenedAt?.toIso8601String(),
      };

  factory Book.fromCacheJson(Map<String, dynamic> json) => Book.fromJson(json);
}
