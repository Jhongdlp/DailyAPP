import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rpg_model.dart';
import '../models/achievement_catalog.dart';

class RpgNotifier extends Notifier<RpgStats> {
  static const _prefsKey = 'rpg_stats';

  @override
  RpgStats build() {
    _load();
    return RpgStats(
      level: 1,
      xp: 0,
      gold: 0,
      hp: 100,
      customRewards: _defaultRewards(),
      equippedWeapon: 'wood_sword',
      equippedArmor: 'cloth_armor',
      equippedShield: 'wood_shield',
      purchasedGear: const ['wood_sword', 'cloth_armor', 'wood_shield'],
      unlockedAchievements: const [],
    );
  }

  List<RpgReward> _defaultRewards() {
    return [
      RpgReward(id: 'r1', title: 'Ver 1 capítulo de serie', cost: 50, icon: '📺'),
      RpgReward(id: 'r2', title: 'Comer un postre / antojo', cost: 150, icon: '🍰'),
      RpgReward(id: 'r3', title: '1 hora de videojuegos', cost: 100, icon: '🎮'),
      RpgReward(id: 'r4', title: 'Comprar algo de capricho', cost: 500, icon: '🛍️'),
    ];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    
    RpgStats localStats;
    if (raw != null) {
      try {
        localStats = RpgStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        localStats = RpgStats(customRewards: _defaultRewards());
      }
    } else {
      localStats = RpgStats(customRewards: _defaultRewards());
    }

    state = localStats;

    // Sincronización Supabase
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        final data = await client
            .from('profiles')
            .select('rpg_level, rpg_xp, rpg_gold, rpg_hp, rpg_rewards')
            .eq('id', user.id)
            .maybeSingle();

        if (data != null && data['rpg_level'] != null) {
          final dbRewards = data['rpg_rewards'] as List?;
          final parsedRewards = dbRewards != null
              ? dbRewards.map((r) => RpgReward.fromJson(Map<String, dynamic>.from(r))).toList()
              : localStats.customRewards;

          state = state.copyWith(
            level: data['rpg_level'] as int,
            xp: data['rpg_xp'] as int,
            gold: data['rpg_gold'] as int,
            hp: data['rpg_hp'] as int,
            customRewards: parsedRewards.isNotEmpty ? parsedRewards : _defaultRewards(),
          );
          await _persistLocal();
        }
      }
    } catch (_) {}
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  Future<void> _syncToSupabase() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        await client.from('profiles').update({
          'rpg_level': state.level,
          'rpg_xp': state.xp,
          'rpg_gold': state.gold,
          'rpg_hp': state.hp,
          'rpg_rewards': state.customRewards.map((r) => r.toJson()).toList(),
        }).eq('id', user.id);
      }
    } catch (_) {}
  }

  /// Selecciona el héroe pixel art (el chequeo de nivel se hace en la UI)
  void selectHero(String heroId) {
    if (state.selectedHero == heroId) return;
    HapticFeedback.lightImpact();
    state = state.copyWith(selectedHero: heroId);
    _persistLocal();
  }

  /// Equipa un item de una categoría ('weapon', 'armor', 'shield') si está comprado
  void equipGear(String category, String itemId) {
    if (!state.purchasedGear.contains(itemId)) return;

    HapticFeedback.lightImpact();

    if (category == 'weapon') {
      state = state.copyWith(equippedWeapon: itemId);
    } else if (category == 'armor') {
      state = state.copyWith(equippedArmor: itemId);
    } else if (category == 'shield') {
      state = state.copyWith(equippedShield: itemId);
    }

    _persistLocal();
  }

  /// Compra una pieza de equipamiento usando oro
  bool buyGear(String itemId, int cost) {
    if (state.gold < cost || state.purchasedGear.contains(itemId)) return false;

    HapticFeedback.heavyImpact();

    state = state.copyWith(
      gold: state.gold - cost,
      purchasedGear: [...state.purchasedGear, itemId],
    );

    _persistLocal();
    _syncToSupabase();
    return true;
  }

  /// Desbloquea un logro y otorga recompensas
  bool unlockAchievement(String id, int xpReward, int goldReward) {
    if (state.unlockedAchievements.contains(id)) return false;

    HapticFeedback.heavyImpact();

    // Sumar XP y Oro
    int newXp = state.xp + xpReward;
    int newLevel = state.level;
    bool levelUp = false;

    while (newXp >= (newLevel * 100)) {
      newXp -= (newLevel * 100);
      newLevel++;
      levelUp = true;
    }

    final newCounters = Map<String, int>.of(state.counters);
    newCounters[RpgCounters.goldTotal] =
        (newCounters[RpgCounters.goldTotal] ?? 0) + goldReward;

    state = state.copyWith(
      level: newLevel,
      xp: newXp,
      gold: state.gold + goldReward,
      unlockedAchievements: [...state.unlockedAchievements, id],
      counters: newCounters,
    );

    _persistLocal();
    _syncToSupabase();
    return true;
  }

  /// Revisa el catálogo y desbloquea los logros cuyo objetivo se alcanzó.
  /// Devuelve los logros recién desbloqueados (para celebrarlos en la UI).
  List<AchievementDef> checkAchievements() {
    final unlocked = <AchievementDef>[];
    bool found = true;
    while (found) {
      found = false;
      for (final a in achievementCatalog) {
        if (state.unlockedAchievements.contains(a.id)) continue;
        if (achievementProgress(state, a) >= a.target) {
          if (unlockAchievement(a.id, a.xpReward, a.goldReward)) {
            unlocked.add(a);
            found = true;
          }
        }
      }
    }
    return unlocked;
  }

  /// Otorga XP y oro por un evento de la app.
  /// [counterKeys] incrementa contadores de logros (ver RpgCounters).
  Map<String, dynamic> gainXpAndGold(
    int xpAmount,
    int goldAmount, {
    List<String> counterKeys = const [],
  }) {
    int newXp = state.xp + xpAmount;
    int newLevel = state.level;
    bool levelUp = false;

    HapticFeedback.mediumImpact();

    while (newXp >= (newLevel * 100)) {
      newXp -= (newLevel * 100);
      newLevel++;
      levelUp = true;
    }

    if (levelUp) {
      Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.mediumImpact());
      Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
    }

    final newCounters = Map<String, int>.of(state.counters);
    for (final key in counterKeys) {
      newCounters[key] = (newCounters[key] ?? 0) + 1;
    }
    newCounters[RpgCounters.goldTotal] =
        (newCounters[RpgCounters.goldTotal] ?? 0) + goldAmount;

    state = state.copyWith(
      level: newLevel,
      xp: newXp,
      gold: state.gold + goldAmount,
      counters: newCounters,
    );

    final unlocked = checkAchievements();

    _persistLocal();
    _syncToSupabase();

    return {
      'levelUp': levelUp,
      'newLevel': newLevel,
      'xpGained': xpAmount,
      'goldGained': goldAmount,
      'unlocked': unlocked,
    };
  }

  void revertReward(
    int xpAmount,
    int goldAmount, {
    List<String> counterKeys = const [],
  }) {
    int newXp = state.xp - xpAmount;
    int newLevel = state.level;

    while (newXp < 0 && newLevel > 1) {
      newLevel--;
      newXp += (newLevel * 100);
    }

    if (newXp < 0) {
      newXp = 0;
      newLevel = 1;
    }

    int newGold = state.gold - goldAmount;
    if (newGold < 0) newGold = 0;

    final newCounters = Map<String, int>.of(state.counters);
    for (final key in counterKeys) {
      final v = (newCounters[key] ?? 0) - 1;
      newCounters[key] = v < 0 ? 0 : v;
    }
    final gt = (newCounters[RpgCounters.goldTotal] ?? 0) - goldAmount;
    newCounters[RpgCounters.goldTotal] = gt < 0 ? 0 : gt;

    state = state.copyWith(
      level: newLevel,
      xp: newXp,
      gold: newGold,
      counters: newCounters,
    );

    _persistLocal();
    _syncToSupabase();
  }

  /// Compra un cosmético del bazar y lo equipa automáticamente.
  /// Devuelve los logros desbloqueados por la compra (lista vacía si falló).
  List<AchievementDef>? buyCosmetic(String id, int price, String slot) {
    if (state.gold < price || state.purchasedCosmetics.contains(id)) {
      return null;
    }

    HapticFeedback.heavyImpact();

    state = state.copyWith(
      gold: state.gold - price,
      purchasedCosmetics: [...state.purchasedCosmetics, id],
      equippedCosmetics: {...state.equippedCosmetics, slot: id},
    );

    final unlocked = checkAchievements();

    _persistLocal();
    _syncToSupabase();
    return unlocked;
  }

  /// Equipa/desequipa un cosmético ya comprado
  void toggleCosmetic(String id, String slot) {
    if (!state.purchasedCosmetics.contains(id)) return;

    HapticFeedback.lightImpact();

    final equipped = Map<String, String>.of(state.equippedCosmetics);
    if (equipped[slot] == id) {
      equipped.remove(slot);
    } else {
      equipped[slot] = id;
    }

    state = state.copyWith(equippedCosmetics: equipped);
    _persistLocal();
    _syncToSupabase();
  }

  /// Pone/quita un badge de logro en la carta del héroe (máx 3)
  void toggleBadge(String achievementId) {
    if (!state.unlockedAchievements.contains(achievementId)) return;

    HapticFeedback.lightImpact();

    List<String> badges;
    if (state.equippedBadges.contains(achievementId)) {
      badges = state.equippedBadges.where((b) => b != achievementId).toList();
    } else {
      if (state.equippedBadges.length >= 3) return;
      badges = [...state.equippedBadges, achievementId];
    }

    state = state.copyWith(equippedBadges: badges);
    _persistLocal();
    _syncToSupabase();
  }

  bool purchaseReward(String rewardId) {
    final index = state.customRewards.indexWhere((r) => r.id == rewardId);
    if (index == -1) return false;

    final reward = state.customRewards[index];
    if (state.gold < reward.cost) return false;

    HapticFeedback.heavyImpact();

    final updatedRewards = [
      for (int i = 0; i < state.customRewards.length; i++)
        if (i == index)
          reward.copyWith(timesRedeemed: reward.timesRedeemed + 1)
        else
          state.customRewards[i]
    ];

    state = state.copyWith(
      gold: state.gold - reward.cost,
      customRewards: updatedRewards,
    );

    _persistLocal();
    _syncToSupabase();
    return true;
  }

  void addCustomReward(String title, int cost, String icon) {
    final newReward = RpgReward(
      id: 'reward-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      cost: cost,
      icon: icon,
    );

    state = state.copyWith(
      customRewards: [...state.customRewards, newReward],
    );

    _persistLocal();
    _syncToSupabase();
  }

  void deleteCustomReward(String id) {
    state = state.copyWith(
      customRewards: state.customRewards.where((r) => r.id != id).toList(),
    );

    _persistLocal();
    _syncToSupabase();
  }

  void updateHp(int change) {
    int newHp = state.hp + change;
    if (newHp > 100) newHp = 100;
    if (newHp < 0) newHp = 0;

    if (change < 0) {
      HapticFeedback.vibrate();
    }

    state = state.copyWith(hp: newHp);
    _persistLocal();
    _syncToSupabase();
  }
}

final rpgProvider = NotifierProvider<RpgNotifier, RpgStats>(RpgNotifier.new);
