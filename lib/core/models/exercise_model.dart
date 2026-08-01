import 'dart:io';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Estado de clasificación de una foto. Colapsa las dos columnas de
/// `exercise_photos` (`classification` + `classification_status`) en un solo
/// valor para que la UI ramifique sobre una sola cosa.
enum PhotoClassification {
  pending,
  classifying,
  cara,
  cuerpo,
  unknown,
  failed;

  static PhotoClassification fromDb(String status, String? classification) {
    switch (status) {
      case 'classifying':
        return PhotoClassification.classifying;
      case 'failed':
        return PhotoClassification.failed;
      case 'done':
        switch (classification) {
          case 'cara':
            return PhotoClassification.cara;
          case 'cuerpo':
            return PhotoClassification.cuerpo;
          default:
            return PhotoClassification.unknown;
        }
      case 'pending':
      default:
        return PhotoClassification.pending;
    }
  }

  String get dbStatus => switch (this) {
        PhotoClassification.pending => 'pending',
        PhotoClassification.classifying => 'classifying',
        PhotoClassification.failed => 'failed',
        PhotoClassification.cara ||
        PhotoClassification.cuerpo ||
        PhotoClassification.unknown =>
          'done',
      };

  String? get dbClassification => switch (this) {
        PhotoClassification.cara => 'cara',
        PhotoClassification.cuerpo => 'cuerpo',
        PhotoClassification.unknown => 'unknown',
        _ => null,
      };

  bool get isSettled => this == cara || this == cuerpo || this == unknown || this == failed;

  String get label => switch (this) {
        PhotoClassification.cara => 'Cara',
        PhotoClassification.cuerpo => 'Cuerpo',
        PhotoClassification.unknown => 'Sin clasificar',
        PhotoClassification.failed => 'Error IA',
        PhotoClassification.classifying || PhotoClassification.pending => 'Clasificando…',
      };
}

class ExerciseLog {
  final String id;
  final String userId;
  final String? habitId;
  final String activityType;
  final DateTime loggedDate;
  final double? distanceKm;
  final double? durationMinutes;
  final double? paceMinPerKm;
  final String? notes;
  final Map<String, dynamic> extra;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExerciseLog({
    required this.id,
    required this.userId,
    this.habitId,
    this.activityType = 'running',
    required this.loggedDate,
    this.distanceKm,
    this.durationMinutes,
    this.paceMinPerKm,
    this.notes,
    this.extra = const {},
    this.createdAt,
    this.updatedAt,
  });

  /// Ritmo en minutos por kilómetro, calculado en vivo si no viene guardado.
  double? get computedPace {
    if (paceMinPerKm != null) return paceMinPerKm;
    if (distanceKm == null || distanceKm! <= 0 || durationMinutes == null) return null;
    return durationMinutes! / distanceKm!;
  }

  ExerciseLog copyWith({
    String? id,
    String? userId,
    String? habitId,
    bool clearHabit = false,
    String? activityType,
    DateTime? loggedDate,
    double? distanceKm,
    double? durationMinutes,
    double? paceMinPerKm,
    String? notes,
    Map<String, dynamic>? extra,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExerciseLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      habitId: clearHabit ? null : (habitId ?? this.habitId),
      activityType: activityType ?? this.activityType,
      loggedDate: loggedDate ?? this.loggedDate,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      paceMinPerKm: paceMinPerKm ?? this.paceMinPerKm,
      notes: notes ?? this.notes,
      extra: extra ?? this.extra,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ExerciseLog.fromJson(Map<String, dynamic> json) => ExerciseLog(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        habitId: json['habit_id'] as String?,
        activityType: json['activity_type'] as String? ?? 'running',
        loggedDate: DateTime.parse(json['logged_date'] as String),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        durationMinutes: (json['duration_minutes'] as num?)?.toDouble(),
        paceMinPerKm: (json['pace_min_per_km'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
        extra: Map<String, dynamic>.from(json['extra'] as Map? ?? {}),
        createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String).toLocal() : null,
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String).toLocal() : null,
      );

  Map<String, dynamic> toInsertJson(String userId) => {
        'id': id,
        'user_id': userId,
        'habit_id': habitId,
        'activity_type': activityType,
        'logged_date': _fmtDate(loggedDate),
        'distance_km': distanceKm,
        'duration_minutes': durationMinutes,
        'pace_min_per_km': computedPace,
        'notes': notes,
        'extra': extra,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'user_id': userId,
        'habit_id': habitId,
        'activity_type': activityType,
        'logged_date': _fmtDate(loggedDate),
        'distance_km': distanceKm,
        'duration_minutes': durationMinutes,
        'pace_min_per_km': computedPace,
        'notes': notes,
        'extra': extra,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory ExerciseLog.fromCacheJson(Map<String, dynamic> json) => ExerciseLog.fromJson(json);
}

class ExercisePhoto {
  final String id;
  final String userId;
  final String? exerciseLogId;
  final DateTime loggedDate;
  final String storagePath;
  final PhotoClassification classification;
  final DateTime takenAt;

  /// Solo en memoria, nunca se serializa: el archivo local recién capturado,
  /// para pintar la miniatura al instante mientras sube en background.
  final File? localFile;

  const ExercisePhoto({
    required this.id,
    required this.userId,
    this.exerciseLogId,
    required this.loggedDate,
    required this.storagePath,
    this.classification = PhotoClassification.pending,
    required this.takenAt,
    this.localFile,
  });

  ExercisePhoto copyWith({
    String? exerciseLogId,
    PhotoClassification? classification,
    File? localFile,
  }) {
    return ExercisePhoto(
      id: id,
      userId: userId,
      exerciseLogId: exerciseLogId ?? this.exerciseLogId,
      loggedDate: loggedDate,
      storagePath: storagePath,
      classification: classification ?? this.classification,
      takenAt: takenAt,
      localFile: localFile ?? this.localFile,
    );
  }

  factory ExercisePhoto.fromJson(Map<String, dynamic> json) => ExercisePhoto(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        exerciseLogId: json['exercise_log_id'] as String?,
        loggedDate: DateTime.parse(json['logged_date'] as String),
        storagePath: json['storage_path'] as String,
        classification: PhotoClassification.fromDb(
          json['classification_status'] as String? ?? 'pending',
          json['classification'] as String?,
        ),
        takenAt: DateTime.parse(json['taken_at'] as String).toLocal(),
      );

  Map<String, dynamic> toInsertJson(String userId) => {
        'id': id,
        'user_id': userId,
        'exercise_log_id': exerciseLogId,
        'logged_date': _fmtDate(loggedDate),
        'storage_path': storagePath,
        'classification_status': classification.dbStatus,
        'classification': classification.dbClassification,
        'taken_at': takenAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toCacheJson() => toInsertJson(userId);

  factory ExercisePhoto.fromCacheJson(Map<String, dynamic> json) => ExercisePhoto.fromJson(json);
}

String _fmtDate(DateTime d) {
  final day = dateOnly(d);
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
