import 'package:flutter/material.dart';
import '../theme/bento_theme.dart';

/// Cada pantalla principal de la app.
///
/// El orden de los valores ES el orden de los hijos del stack del dashboard:
/// no se reordena ni se intercala nada aquí sin tocar `DashboardScreen._tabs`.
/// El dock, en cambio, puede llevar cualquier subconjunto y en cualquier orden.
enum AppDestination {
  habits('Hábitos', Icons.check_circle_outline),
  notes('Notas', Icons.psychology_outlined),
  alarm('Alarma', Icons.alarm_outlined),
  finance('Finanzas', Icons.account_balance_wallet_outlined),
  chat('Copiloto', Icons.chat_bubble_outline),
  agenda('Agenda', Icons.view_timeline_outlined),
  reading('Biblioteca', Icons.auto_stories_outlined);

  const AppDestination(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Índice en el stack del dashboard.
  int get tabIndex => index;

  /// El acento es un getter y no un campo del enum porque los colores del tema
  /// cambian en vivo (paleta / modo claro-oscuro) y un `const` los congelaría.
  Color get accent => switch (this) {
        AppDestination.habits => BentoTheme.accentHabits,
        AppDestination.notes => BentoTheme.accentBrain,
        AppDestination.alarm => BentoTheme.accentAlarm,
        AppDestination.finance => BentoTheme.accentFinance,
        AppDestination.chat => BentoTheme.accentChat,
        AppDestination.agenda => BentoTheme.accentLime,
        AppDestination.reading => BentoTheme.accentPurple,
      };

  static AppDestination? byName(String name) {
    for (final d in values) {
      if (d.name == name) return d;
    }
    return null;
  }
}
