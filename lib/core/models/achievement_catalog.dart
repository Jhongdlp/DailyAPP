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
  // derivados (no viven en counters):
  static const level = 'level';
  static const cosmetics = 'cosmetics';
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
