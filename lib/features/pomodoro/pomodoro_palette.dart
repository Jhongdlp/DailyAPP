import 'package:flutter/material.dart';

import '../../core/theme/bento_theme.dart';
import 'providers/pomodoro_provider.dart';

/// Color de cada fase. El enfoque es un celeste sereno (no el azul de alarma,
/// que el cuerpo asocia a urgencia), el descanso corto verde y el largo morado:
/// tres señales que se distinguen de reojo sin leer una palabra.
class PomodoroPalette {
  static const Color focus = Color(0xFF4EA8DE);

  static Color of(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.focus => focus,
        PomodoroPhase.shortBreak => BentoTheme.successGreen,
        PomodoroPhase.longBreak => BentoTheme.accentPurple,
      };
}

/// `1 h 25 min`, `25 min`, `40 s`. Formato corto para tiras de estadísticas.
String formatFocusDuration(int minutes) {
  if (minutes < 1) return '0 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// `15:42` en 24 h, que es como se lee una hora de fin de bloque.
String formatClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
