import '../services/metrics_service.dart';

/// Una revisión semanal cerrada.
///
/// Vive solo en el dispositivo, como las estadísticas del pomodoro y las
/// alarmas: es material de diario personal y no lo lee ninguna otra pantalla ni
/// se comparte entre dispositivos, así que no justifica una tabla en Supabase
/// ni una migración.
class WeeklyReview {
  /// Lunes de la semana revisada. Es la identidad: hay como mucho una revisión
  /// por semana, y reabrir el ritual la edita en vez de crear otra.
  final DateTime weekStart;

  /// Lo que el usuario escribió que funcionó.
  final String wins;

  /// Lo que estorbó.
  final String frictions;

  /// Resumen narrativo generado en local por Ollama. Puede estar vacío: el
  /// ritual se puede terminar con el servidor de IA apagado.
  final String aiSummary;

  /// La única cosa en la que enfocarse la semana que viene.
  final String nextFocus;

  final DateTime completedAt;

  const WeeklyReview({
    required this.weekStart,
    this.wins = '',
    this.frictions = '',
    this.aiSummary = '',
    this.nextFocus = '',
    required this.completedAt,
  });

  String get weekKey => _fmt(weekStart);

  WeeklyReview copyWith({
    String? wins,
    String? frictions,
    String? aiSummary,
    String? nextFocus,
    DateTime? completedAt,
  }) =>
      WeeklyReview(
        weekStart: weekStart,
        wins: wins ?? this.wins,
        frictions: frictions ?? this.frictions,
        aiSummary: aiSummary ?? this.aiSummary,
        nextFocus: nextFocus ?? this.nextFocus,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => {
        'week_start': _fmt(weekStart),
        'wins': wins,
        'frictions': frictions,
        'ai_summary': aiSummary,
        'next_focus': nextFocus,
        'completed_at': completedAt.toIso8601String(),
      };

  factory WeeklyReview.fromJson(Map<String, dynamic> json) => WeeklyReview(
        weekStart: MetricsService.dayOnly(
          DateTime.parse(json['week_start'] as String),
        ),
        wins: json['wins'] as String? ?? '',
        frictions: json['frictions'] as String? ?? '',
        aiSummary: json['ai_summary'] as String? ?? '',
        nextFocus: json['next_focus'] as String? ?? '',
        completedAt: DateTime.parse(json['completed_at'] as String),
      );

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
