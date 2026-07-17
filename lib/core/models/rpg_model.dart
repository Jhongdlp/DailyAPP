class RpgReward {
  final String id;
  final String title;
  final int cost;
  final String icon;
  final int timesRedeemed;

  RpgReward({
    required this.id,
    required this.title,
    required this.cost,
    this.icon = '🎁',
    this.timesRedeemed = 0,
  });

  RpgReward copyWith({
    String? id,
    String? title,
    int? cost,
    String? icon,
    int? timesRedeemed,
  }) {
    return RpgReward(
      id: id ?? this.id,
      title: title ?? this.title,
      cost: cost ?? this.cost,
      icon: icon ?? this.icon,
      timesRedeemed: timesRedeemed ?? this.timesRedeemed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cost': cost,
      'icon': icon,
      'times_redeemed': timesRedeemed,
    };
  }

  factory RpgReward.fromJson(Map<String, dynamic> json) {
    return RpgReward(
      id: json['id'] as String,
      title: json['title'] as String,
      cost: json['cost'] as int,
      icon: (json['icon'] as String?) ?? '🎁',
      timesRedeemed: (json['times_redeemed'] as int?) ?? 0,
    );
  }
}

class RpgStats {
  final int level;
  final int xp;
  final int gold;
  final int hp;
  final List<RpgReward> customRewards;
  
  // Nuevos campos del sistema de equipamiento RPG
  final String equippedWeapon;
  final String equippedArmor;
  final String equippedShield;
  final List<String> purchasedGear;
  final List<String> unlockedAchievements;

  /// Héroe pixel art seleccionado (ver heroCatalog)
  final String selectedHero;

  /// Contadores de eventos para el sistema de logros
  /// (habits_done, wakes, early_wakes, transactions, notes, gold_total)
  final Map<String, int> counters;

  /// Cosméticos comprados en el bazar (ver cosmeticCatalog)
  final List<String> purchasedCosmetics;

  /// Cosméticos equipados por slot: {'halo': id, 'back': id, 'pet': id, 'aura': id}
  final Map<String, String> equippedCosmetics;

  /// Badges de logros mostrados en la carta del héroe (máx 3)
  final List<String> equippedBadges;

  RpgStats({
    this.level = 1,
    this.xp = 0,
    this.gold = 0,
    this.hp = 100,
    this.customRewards = const [],
    this.equippedWeapon = 'wood_sword',
    this.equippedArmor = 'cloth_armor',
    this.equippedShield = 'wood_shield',
    this.purchasedGear = const ['wood_sword', 'cloth_armor', 'wood_shield'],
    this.unlockedAchievements = const [],
    this.selectedHero = 'warrior',
    this.counters = const {},
    this.purchasedCosmetics = const [],
    this.equippedCosmetics = const {},
    this.equippedBadges = const [],
  });

  int get xpNeeded => level * 100;

  RpgStats copyWith({
    int? level,
    int? xp,
    int? gold,
    int? hp,
    List<RpgReward>? customRewards,
    String? equippedWeapon,
    String? equippedArmor,
    String? equippedShield,
    List<String>? purchasedGear,
    List<String>? unlockedAchievements,
    String? selectedHero,
    Map<String, int>? counters,
    List<String>? purchasedCosmetics,
    Map<String, String>? equippedCosmetics,
    List<String>? equippedBadges,
  }) {
    return RpgStats(
      level: level ?? this.level,
      xp: xp ?? this.xp,
      gold: gold ?? this.gold,
      hp: hp ?? this.hp,
      customRewards: customRewards ?? this.customRewards,
      equippedWeapon: equippedWeapon ?? this.equippedWeapon,
      equippedArmor: equippedArmor ?? this.equippedArmor,
      equippedShield: equippedShield ?? this.equippedShield,
      purchasedGear: purchasedGear ?? this.purchasedGear,
      unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
      selectedHero: selectedHero ?? this.selectedHero,
      counters: counters ?? this.counters,
      purchasedCosmetics: purchasedCosmetics ?? this.purchasedCosmetics,
      equippedCosmetics: equippedCosmetics ?? this.equippedCosmetics,
      equippedBadges: equippedBadges ?? this.equippedBadges,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'level': level,
      'xp': xp,
      'gold': gold,
      'hp': hp,
      'custom_rewards': customRewards.map((r) => r.toJson()).toList(),
      'equipped_weapon': equippedWeapon,
      'equipped_armor': equippedArmor,
      'equipped_shield': equippedShield,
      'purchased_gear': purchasedGear,
      'unlocked_achievements': unlockedAchievements,
      'selected_hero': selectedHero,
      'counters': counters,
      'purchased_cosmetics': purchasedCosmetics,
      'equipped_cosmetics': equippedCosmetics,
      'equipped_badges': equippedBadges,
    };
  }

  factory RpgStats.fromJson(Map<String, dynamic> json) {
    var rewardsList = const <RpgReward>[];
    if (json['custom_rewards'] != null) {
      rewardsList = (json['custom_rewards'] as List)
          .map((r) => RpgReward.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }
    
    return RpgStats(
      level: (json['level'] as int?) ?? 1,
      xp: (json['xp'] as int?) ?? 0,
      gold: (json['gold'] as int?) ?? 0,
      hp: (json['hp'] as int?) ?? 100,
      customRewards: rewardsList,
      equippedWeapon: (json['equipped_weapon'] as String?) ?? 'wood_sword',
      equippedArmor: (json['equipped_armor'] as String?) ?? 'cloth_armor',
      equippedShield: (json['equipped_shield'] as String?) ?? 'wood_shield',
      purchasedGear: json['purchased_gear'] != null
          ? List<String>.from(json['purchased_gear'] as List)
          : const ['wood_sword', 'cloth_armor', 'wood_shield'],
      unlockedAchievements: json['unlocked_achievements'] != null
          ? List<String>.from(json['unlocked_achievements'] as List)
          : const [],
      selectedHero: (json['selected_hero'] as String?) ?? 'warrior',
      counters: json['counters'] != null
          ? Map<String, dynamic>.from(json['counters'] as Map)
              .map((k, v) => MapEntry(k, (v as num).toInt()))
          : const {},
      purchasedCosmetics: json['purchased_cosmetics'] != null
          ? List<String>.from(json['purchased_cosmetics'] as List)
          : const [],
      equippedCosmetics: json['equipped_cosmetics'] != null
          ? Map<String, String>.from(json['equipped_cosmetics'] as Map)
          : const {},
      equippedBadges: json['equipped_badges'] != null
          ? List<String>.from(json['equipped_badges'] as List)
          : const [],
    );
  }
}
