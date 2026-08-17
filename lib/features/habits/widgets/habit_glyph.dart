import 'package:flutter/material.dart';

import '../../../core/models/habit_model.dart';

/// Traduce el emoji de un hábito a un glifo monolineal.
///
/// El emoji a color rompe el presupuesto de tres colores: una sola fila con
/// emoji mete dos tonos que compiten con el texto. Un glifo de línea del mismo
/// peso que la tipografía se integra en la fila en vez de gritar desde ella.
///
/// El emoji NO se pierde: sigue guardado en el modelo y se muestra en la
/// pantalla de detalle, donde no compite con nada.
class HabitGlyph {
  HabitGlyph._();

  /// Un emoji puede venir con selector de variación (U+FE0F) o modificador de
  /// tono de piel; se compara solo por el primer punto de código.
  static int? _firstRune(String emoji) =>
      emoji.runes.isEmpty ? null : emoji.runes.first;

  static const Map<int, IconData> _byRune = {
    // Agua e hidratación
    0x1F4A7: Icons.water_drop_rounded, // 💧
    0x1F6B0: Icons.water_drop_rounded, // 🚰
    0x1F964: Icons.local_drink_rounded, // 🥤

    // Lectura y estudio
    0x1F4D6: Icons.auto_stories_rounded, // 📖
    0x1F4DA: Icons.auto_stories_rounded, // 📚
    0x1F4D5: Icons.auto_stories_rounded, // 📕
    0x1F393: Icons.school_rounded, // 🎓
    0x1F310: Icons.translate_rounded, // 🌐
    0x1F5E3: Icons.translate_rounded, // 🗣

    // Movimiento
    0x1F3C3: Icons.directions_run_rounded, // 🏃
    0x1F6B6: Icons.directions_walk_rounded, // 🚶
    0x1F6B4: Icons.directions_bike_rounded, // 🚴
    0x1F3CA: Icons.pool_rounded, // 🏊
    0x1F4AA: Icons.fitness_center_rounded, // 💪
    0x1F3CB: Icons.fitness_center_rounded, // 🏋
    0x26BD: Icons.sports_soccer_rounded, // ⚽
    0x1F3C0: Icons.sports_basketball_rounded, // 🏀

    // Mente
    0x1F9D8: Icons.self_improvement_rounded, // 🧘
    0x1F9E0: Icons.psychology_rounded, // 🧠
    0x1F64F: Icons.volunteer_activism_rounded, // 🙏

    // Descanso y ritmo del día
    0x1F634: Icons.bedtime_rounded, // 😴
    0x1F6CC: Icons.bedtime_rounded, // 🛌
    0x1F319: Icons.nightlight_rounded, // 🌙
    0x2600: Icons.wb_sunny_rounded, // ☀
    0x1F305: Icons.wb_twilight_rounded, // 🌅
    0x23F0: Icons.schedule_rounded, // ⏰

    // Alimentación
    0x1F957: Icons.restaurant_rounded, // 🥗
    0x1F34E: Icons.apple_rounded, // 🍎
    0x1F37D: Icons.restaurant_rounded, // 🍽
    0x2615: Icons.local_cafe_rounded, // ☕

    // Cuidado personal
    0x1F6BF: Icons.shower_rounded, // 🚿
    0x1F48A: Icons.spa_rounded, // 💊
    0x1F9F9: Icons.cleaning_services_rounded, // 🧹

    // Trabajo y creación
    0x270D: Icons.edit_note_rounded, // ✍
    0x1F4DD: Icons.edit_note_rounded, // 📝
    0x1F4BB: Icons.code_rounded, // 💻
    0x1F3B8: Icons.music_note_rounded, // 🎸
    0x1F3B5: Icons.music_note_rounded, // 🎵
    0x1F3A8: Icons.palette_rounded, // 🎨
    0x1F4F7: Icons.photo_camera_rounded, // 📷

    // Otros
    0x1F331: Icons.yard_rounded, // 🌱
    0x1F4B0: Icons.savings_rounded, // 💰
    0x1F4B5: Icons.savings_rounded, // 💵
    0x1F4F1: Icons.smartphone_rounded, // 📱
    0x1F3AF: Icons.auto_awesome_rounded, // 🎯
  };

  /// Glifo para [habit]. Si el emoji no está mapeado cae al icono de su
  /// categoría, que ya es monolineal — así ningún hábito queda sin icono.
  static IconData of(Habit habit) {
    final rune = _firstRune(habit.icon);
    return _byRune[rune] ?? habit.category.icon;
  }
}
