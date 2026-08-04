import 'package:flutter/material.dart';
import 'rpg_model.dart';

/// Sistema de logros: cada logro observa un contador de RpgStats.counters
/// (o un valor derivado como el nivel) y se desbloquea al llegar a [target].
enum BadgeTier { bronce, plata, oro, diamante }

class BadgeTierPalette {
  final Color main;
  final Color shadow;
  final Color highlight;
  const BadgeTierPalette(this.main, this.shadow, this.highlight);
}

const Map<BadgeTier, BadgeTierPalette> badgeTierPalettes = {
  BadgeTier.bronce: BadgeTierPalette(
      Color(0xFFC77B4A), Color(0xFF8F5230), Color(0xFFE8A87C)),
  BadgeTier.plata: BadgeTierPalette(
      Color(0xFFC9D1DC), Color(0xFF8B96A5), Color(0xFFEEF2F7)),
  BadgeTier.oro: BadgeTierPalette(
      Color(0xFFFFD75E), Color(0xFFC9952C), Color(0xFFFFF3C4)),
  BadgeTier.diamante: BadgeTierPalette(
      Color(0xFF7DE8D8), Color(0xFF3BA89A), Color(0xFFD4FBF5)),
};

String badgeTierLabel(BadgeTier tier) {
  switch (tier) {
    case BadgeTier.bronce:
      return 'Bronce';
    case BadgeTier.plata:
      return 'Plata';
    case BadgeTier.oro:
      return 'Oro';
    case BadgeTier.diamante:
      return 'Diamante';
  }
}

// Claves de contador usadas por los eventos de la app
class RpgCounters {
  static const habitsDone = 'habits_done';
  static const wakes = 'wakes';
  static const earlyWakes = 'early_wakes';
  static const transactions = 'transactions';
  static const notes = 'notes';
  static const goldTotal = 'gold_total';
  static const readingMinutes = 'reading_minutes';
  static const booksFinished = 'books_finished';
  static const highlights = 'highlights';
  static const sleepNights = 'sleep_nights';
  static const sleepGoalNights = 'sleep_goal_nights';
  static const focusMinutes = 'focus_minutes';
  static const exerciseSessions = 'exercise_sessions';
  static const exerciseKm = 'exercise_km';
  static const progressPhotos = 'progress_photos';
  // derivados (no viven en counters):
  static const level = 'level';
  static const cosmetics = 'cosmetics';
}

/// Categorías usadas para agrupar el panel de logros en la UI. El orden de
/// este enum define el orden en que se muestran las secciones.
enum AchievementCategory {
  habitos,
  alarma,
  suenio,
  finanzas,
  notas,
  lectura,
  enfoque,
  ejercicio,
  economia,
  nivel,
}

String achievementCategoryLabel(AchievementCategory c) {
  switch (c) {
    case AchievementCategory.habitos:
      return 'Hábitos';
    case AchievementCategory.alarma:
      return 'Alarma';
    case AchievementCategory.suenio:
      return 'Sueño';
    case AchievementCategory.finanzas:
      return 'Finanzas';
    case AchievementCategory.notas:
      return 'Notas';
    case AchievementCategory.lectura:
      return 'Lectura';
    case AchievementCategory.enfoque:
      return 'Enfoque';
    case AchievementCategory.ejercicio:
      return 'Ejercicio';
    case AchievementCategory.economia:
      return 'Economía y colección';
    case AchievementCategory.nivel:
      return 'Nivel';
  }
}

class AchievementDef {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final BadgeTier tier;
  final String counterKey;
  final int target;
  final int xpReward;
  final int goldReward;
  final AchievementCategory category;

  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.tier,
    required this.counterKey,
    required this.target,
    required this.xpReward,
    required this.goldReward,
    required this.category,
  });
}

const List<AchievementDef> achievementCatalog = [
  // ── Hábitos ──
  AchievementDef(
    id: 'primer-paso',
    title: 'Primer Paso',
    description: 'Completa tu primer hábito',
    emoji: '🌱',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.habitsDone,
    target: 1,
    xpReward: 20,
    goldReward: 10,
    category: AchievementCategory.habitos,
  ),
  AchievementDef(
    id: 'en-racha',
    title: 'En Racha',
    description: 'Completa 25 hábitos',
    emoji: '🔥',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.habitsDone,
    target: 25,
    xpReward: 50,
    goldReward: 25,
    category: AchievementCategory.habitos,
  ),
  AchievementDef(
    id: 'imparable',
    title: 'Imparable',
    description: 'Completa 100 hábitos',
    emoji: '⚡',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.habitsDone,
    target: 100,
    xpReward: 120,
    goldReward: 80,
    category: AchievementCategory.habitos,
  ),
  AchievementDef(
    id: 'leyenda-viva',
    title: 'Leyenda Viva',
    description: 'Completa 365 hábitos',
    emoji: '👑',
    tier: BadgeTier.diamante,
    counterKey: RpgCounters.habitsDone,
    target: 365,
    xpReward: 300,
    goldReward: 200,
    category: AchievementCategory.habitos,
  ),
  // ── Alarma / despertar ──
  AchievementDef(
    id: 'buenos-dias',
    title: 'Buenos Días',
    description: 'Valida 5 despertares con foto',
    emoji: '⏰',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.wakes,
    target: 5,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.alarma,
  ),
  AchievementDef(
    id: 'madrugador',
    title: 'Madrugador',
    description: 'Valida 20 despertares con foto',
    emoji: '🌅',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.wakes,
    target: 20,
    xpReward: 60,
    goldReward: 40,
    category: AchievementCategory.alarma,
  ),
  AchievementDef(
    id: 'alondra',
    title: 'Alondra',
    description: 'Despierta 15 veces antes de las 8am',
    emoji: '🐦',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.earlyWakes,
    target: 15,
    xpReward: 120,
    goldReward: 80,
    category: AchievementCategory.alarma,
  ),
  // ── Sueño ──
  AchievementDef(
    id: 'diario-de-suenio',
    title: 'Diario de Sueño',
    description: 'Registra 7 noches completas',
    emoji: '🌙',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.sleepNights,
    target: 7,
    xpReward: 40,
    goldReward: 20,
    category: AchievementCategory.suenio,
  ),
  AchievementDef(
    id: 'descanso-real',
    title: 'Descanso Real',
    description: 'Alcanza tu meta de sueño 14 noches',
    emoji: '😴',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.sleepGoalNights,
    target: 14,
    xpReward: 90,
    goldReward: 50,
    category: AchievementCategory.suenio,
  ),
  AchievementDef(
    id: 'reloj-suizo',
    title: 'Reloj Suizo',
    description: 'Alcanza tu meta de sueño 60 noches',
    emoji: '⏳',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.sleepGoalNights,
    target: 60,
    xpReward: 200,
    goldReward: 130,
    category: AchievementCategory.suenio,
  ),
  // ── Finanzas ──
  AchievementDef(
    id: 'contable',
    title: 'Contable',
    description: 'Registra 10 transacciones',
    emoji: '🧾',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.transactions,
    target: 10,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.finanzas,
  ),
  AchievementDef(
    id: 'financiero',
    title: 'Financiero',
    description: 'Registra 50 transacciones',
    emoji: '💼',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.transactions,
    target: 50,
    xpReward: 80,
    goldReward: 50,
    category: AchievementCategory.finanzas,
  ),
  // ── Notas ──
  AchievementDef(
    id: 'escriba',
    title: 'Escriba',
    description: 'Crea 10 notas',
    emoji: '✍️',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.notes,
    target: 10,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.notas,
  ),
  AchievementDef(
    id: 'cronista',
    title: 'Cronista',
    description: 'Crea 50 notas',
    emoji: '📚',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.notes,
    target: 50,
    xpReward: 80,
    goldReward: 50,
    category: AchievementCategory.notas,
  ),
  // ── Lectura ──
  AchievementDef(
    id: 'lector-novato',
    title: 'Lector Novato',
    description: 'Lee durante 60 minutos',
    emoji: '📖',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.readingMinutes,
    target: 60,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.lectura,
  ),
  AchievementDef(
    id: 'raton-de-biblioteca',
    title: 'Ratón de Biblioteca',
    description: 'Lee durante 10 horas',
    emoji: '🐁',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.readingMinutes,
    target: 600,
    xpReward: 90,
    goldReward: 60,
    category: AchievementCategory.lectura,
  ),
  AchievementDef(
    id: 'devorador-de-libros',
    title: 'Devorador de Libros',
    description: 'Lee durante 50 horas',
    emoji: '🐉',
    tier: BadgeTier.diamante,
    counterKey: RpgCounters.readingMinutes,
    target: 3000,
    xpReward: 300,
    goldReward: 200,
    category: AchievementCategory.lectura,
  ),
  AchievementDef(
    id: 'subrayador',
    title: 'Subrayador',
    description: 'Guarda 25 resaltados',
    emoji: '🖍️',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.highlights,
    target: 25,
    xpReward: 60,
    goldReward: 40,
    category: AchievementCategory.lectura,
  ),
  AchievementDef(
    id: 'punto-final',
    title: 'Punto Final',
    description: 'Termina 3 libros',
    emoji: '🏁',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.booksFinished,
    target: 3,
    xpReward: 150,
    goldReward: 100,
    category: AchievementCategory.lectura,
  ),
  // ── Enfoque ──
  AchievementDef(
    id: 'primer-pomodoro',
    title: 'Primer Pomodoro',
    description: 'Acumula 25 minutos de enfoque',
    emoji: '🍅',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.focusMinutes,
    target: 25,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.enfoque,
  ),
  AchievementDef(
    id: 'estado-de-flujo',
    title: 'Estado de Flujo',
    description: 'Acumula 10 horas de enfoque',
    emoji: '🌊',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.focusMinutes,
    target: 600,
    xpReward: 90,
    goldReward: 60,
    category: AchievementCategory.enfoque,
  ),
  AchievementDef(
    id: 'mente-de-acero',
    title: 'Mente de Acero',
    description: 'Acumula 50 horas de enfoque',
    emoji: '🧠',
    tier: BadgeTier.diamante,
    counterKey: RpgCounters.focusMinutes,
    target: 3000,
    xpReward: 250,
    goldReward: 180,
    category: AchievementCategory.enfoque,
  ),
  // ── Ejercicio ──
  AchievementDef(
    id: 'primeros-pasos',
    title: 'Primeros Pasos',
    description: 'Registra tu primera sesión de ejercicio',
    emoji: '🏃',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.exerciseSessions,
    target: 1,
    xpReward: 20,
    goldReward: 10,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: 'ritmo-constante',
    title: 'Ritmo Constante',
    description: 'Registra 20 sesiones de ejercicio',
    emoji: '👟',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.exerciseSessions,
    target: 20,
    xpReward: 60,
    goldReward: 40,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: 'maquina-de-correr',
    title: 'Máquina de Correr',
    description: 'Registra 100 sesiones de ejercicio',
    emoji: '🏅',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.exerciseSessions,
    target: 100,
    xpReward: 150,
    goldReward: 100,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: '10k-recorridos',
    title: '10K Recorridos',
    description: 'Acumula 10 km recorridos',
    emoji: '🗺️',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.exerciseKm,
    target: 10,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: 'medio-centenar',
    title: 'Medio Centenar',
    description: 'Acumula 50 km recorridos',
    emoji: '🛣️',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.exerciseKm,
    target: 50,
    xpReward: 80,
    goldReward: 50,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: 'ultra-distancia',
    title: 'Ultra Distancia',
    description: 'Acumula 200 km recorridos',
    emoji: '🏔️',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.exerciseKm,
    target: 200,
    xpReward: 180,
    goldReward: 120,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: 'diario-visual',
    title: 'Diario Visual',
    description: 'Guarda 10 fotos de progreso',
    emoji: '📸',
    tier: BadgeTier.bronce,
    counterKey: RpgCounters.progressPhotos,
    target: 10,
    xpReward: 30,
    goldReward: 15,
    category: AchievementCategory.ejercicio,
  ),
  AchievementDef(
    id: 'archivo-de-progreso',
    title: 'Archivo de Progreso',
    description: 'Guarda 50 fotos de progreso',
    emoji: '🎞️',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.progressPhotos,
    target: 50,
    xpReward: 80,
    goldReward: 50,
    category: AchievementCategory.ejercicio,
  ),
  // ── Economía y colección ──
  AchievementDef(
    id: 'tesorero',
    title: 'Tesorero',
    description: 'Acumula 1000 de oro ganado',
    emoji: '💰',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.goldTotal,
    target: 1000,
    xpReward: 100,
    goldReward: 50,
    category: AchievementCategory.economia,
  ),
  AchievementDef(
    id: 'fashionista',
    title: 'Fashionista',
    description: 'Compra 3 cosméticos en el bazar',
    emoji: '🛍️',
    tier: BadgeTier.plata,
    counterKey: RpgCounters.cosmetics,
    target: 3,
    xpReward: 60,
    goldReward: 40,
    category: AchievementCategory.economia,
  ),
  // ── Nivel ──
  AchievementDef(
    id: 'heroe-eterno',
    title: 'Héroe Eterno',
    description: 'Alcanza el nivel 10',
    emoji: '🏆',
    tier: BadgeTier.oro,
    counterKey: RpgCounters.level,
    target: 10,
    xpReward: 150,
    goldReward: 100,
    category: AchievementCategory.nivel,
  ),
];

AchievementDef? achievementById(String id) {
  for (final a in achievementCatalog) {
    if (a.id == id) return a;
  }
  return null;
}

/// Progreso actual de un logro según los stats
int achievementProgress(RpgStats stats, AchievementDef a) {
  switch (a.counterKey) {
    case RpgCounters.level:
      return stats.level;
    case RpgCounters.cosmetics:
      return stats.purchasedCosmetics.length;
    default:
      return stats.counters[a.counterKey] ?? 0;
  }
}
