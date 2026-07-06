class AlarmModel {
  final String id;
  final String userId;
  final bool enabled;
  final int hour;
  final int minute;
  final String targetObject;
  final String label;
  final List<int> daysOfWeek;
  final DateTime createdAt;

  const AlarmModel({
    required this.id,
    required this.userId,
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.targetObject,
    required this.label,
    required this.daysOfWeek,
    required this.createdAt,
  });

  factory AlarmModel.fromJson(Map<String, dynamic> json) {
    return AlarmModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      enabled: json['enabled'] as bool,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      targetObject: json['target_object'] as String,
      label: (json['label'] as String?) ?? 'Alarma',
      daysOfWeek: json['days_of_week'] != null
          ? List<int>.from(json['days_of_week'] as List)
          : [1, 2, 3, 4, 5, 6, 7],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'target_object': targetObject,
        'label': label,
        'days_of_week': daysOfWeek,
      };

  AlarmModel copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    String? targetObject,
    String? label,
    List<int>? daysOfWeek,
  }) {
    return AlarmModel(
      id: id,
      userId: userId,
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      targetObject: targetObject ?? this.targetObject,
      label: label ?? this.label,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      createdAt: createdAt,
    );
  }

  String get formattedTime {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Hora en formato 12h sin el sufijo (ej: "7:30")
  String get time12 {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h12:$m';
  }

  /// Sufijo AM/PM
  String get amPm => hour < 12 ? 'AM' : 'PM';

  /// Próxima fecha/hora en la que sonará esta alarma (null si no hay días)
  DateTime? nextTrigger({DateTime? from}) {
    if (daysOfWeek.isEmpty) return null;
    final now = from ?? DateTime.now();
    for (int i = 0; i < 8; i++) {
      final candidate = DateTime(now.year, now.month, now.day, hour, minute)
          .add(Duration(days: i));
      if (candidate.isAfter(now) && daysOfWeek.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  /// Texto tipo "Suena en 7 h 30 min"
  String? get untilLabel {
    final next = nextTrigger();
    if (next == null) return null;
    final diff = next.difference(DateTime.now());
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) return 'Suena en $days d $hours h';
    if (hours > 0) return 'Suena en $hours h $mins min';
    if (mins > 0) return 'Suena en $mins min';
    return 'Suena en menos de 1 min';
  }

  String get daysLabel {
    if (daysOfWeek.length == 7) return 'Todos los días';
    if (daysOfWeek.isEmpty) return 'Sin días';
    const names = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final sorted = [...daysOfWeek]..sort();
    return sorted.map((d) => names[d]).join(', ');
  }
}
