import '../models/card.dart';

/// Central place to define all base card types (archetypes).
///
/// Card Rarity System:
/// - Common (1): Unlimited copies - basic troops
/// - Rare (2): Max 3 copies - elite versions with +20% stats
/// - Epic (3): Max 2 copies - specialists with abilities
/// - Legendary (4): Max 1 copy - champions with unique powers
///
/// Power Score formula: (damage * 2 + health) / tick
/// Higher score = more efficient card

// ============================================================================
// COMMON CARDS (Rarity 1) - Unlimited copies available
// ============================================================================

GameCard desertQuickStrike(int index) => GameCard(
  id: 'desert_qs_$index',
  name: 'Desert Quick Strike',
  damage: 4,
  health: 4,
  tick: 1,
  element: 'Desert',
  abilities: const [],
  cost: 1,
  rarity: 1, // Common
);

GameCard lakeQuickStrike(int index) => GameCard(
  id: 'lake_qs_$index',
  name: 'Lake Quick Strike',
  damage: 3,
  health: 6,
  tick: 1,
  element: 'Lake',
  abilities: const [],
  cost: 1,
  rarity: 1, // Common
);

GameCard woodsQuickStrike(int index) => GameCard(
  id: 'woods_qs_$index',
  name: 'Woods Quick Strike',
  damage: 3,
  health: 5,
  tick: 1,
  element: 'Woods',
  abilities: const [],
  cost: 1,
  rarity: 1, // Common
);

GameCard desertWarrior(int index) => GameCard(
  id: 'desert_war_$index',
  name: 'Desert Warrior',
  damage: 6,
  health: 9,
  tick: 3,
  element: 'Desert',
  abilities: const [],
  cost: 2,
  rarity: 1, // Common
);

GameCard lakeWarrior(int index) => GameCard(
  id: 'lake_war_$index',
  name: 'Lake Warrior',
  damage: 5,
  health: 11,
  tick: 3,
  element: 'Lake',
  abilities: const [],
  cost: 2,
  rarity: 1, // Common
);

GameCard woodsWarrior(int index) => GameCard(
  id: 'woods_war_$index',
  name: 'Woods Warrior',
  damage: 5,
  health: 10,
  tick: 3,
  element: 'Woods',
  abilities: const [],
  cost: 2,
  rarity: 1, // Common
);

GameCard desertTank(int index) => GameCard(
  id: 'desert_tank_$index',
  name: 'Desert Tank',
  damage: 9,
  health: 14,
  tick: 5,
  element: 'Desert',
  abilities: const [],
  cost: 3,
  rarity: 1, // Common
);

GameCard lakeTank(int index) => GameCard(
  id: 'lake_tank_$index',
  name: 'Lake Tank',
  damage: 8,
  health: 16,
  tick: 5,
  element: 'Lake',
  abilities: const [],
  cost: 3,
  rarity: 1, // Common
);

GameCard woodsTank(int index) => GameCard(
  id: 'woods_tank_$index',
  name: 'Woods Tank',
  damage: 8,
  health: 15,
  tick: 5,
  element: 'Woods',
  abilities: const [],
  cost: 3,
  rarity: 1, // Common
);

// ============================================================================
// RARE CARDS (Rarity 2) - Max 3 copies each - Elite versions (+25% stats)
// ============================================================================

GameCard desertEliteStriker(int index) => GameCard(
  id: 'desert_elite_qs_$index',
  name: 'Desert Elite Striker',
  damage: 5, // +1 from common
  health: 5, // +1 from common
  tick: 1,
  element: 'Desert',
  abilities: const [],
  cost: 2,
  rarity: 2, // Rare
);

GameCard lakeEliteStriker(int index) => GameCard(
  id: 'lake_elite_qs_$index',
  name: 'Lake Elite Striker',
  damage: 4, // +1 from common
  health: 7, // +1 from common
  tick: 1,
  element: 'Lake',
  abilities: const [],
  cost: 2,
  rarity: 2, // Rare
);

GameCard woodsEliteStriker(int index) => GameCard(
  id: 'woods_elite_qs_$index',
  name: 'Woods Elite Striker',
  damage: 4, // +1 from common
  health: 6, // +1 from common
  tick: 1,
  element: 'Woods',
  abilities: const [],
  cost: 2,
  rarity: 2, // Rare
);

GameCard desertVeteran(int index) => GameCard(
  id: 'desert_vet_$index',
  name: 'Desert Veteran',
  damage: 8, // +2 from common warrior
  health: 11, // +2 from common warrior
  tick: 3,
  element: 'Desert',
  abilities: const [],
  cost: 3,
  rarity: 2, // Rare
);

GameCard lakeVeteran(int index) => GameCard(
  id: 'lake_vet_$index',
  name: 'Lake Veteran',
  damage: 7, // +2 from common warrior
  health: 13, // +2 from common warrior
  tick: 3,
  element: 'Lake',
  abilities: const [],
  cost: 3,
  rarity: 2, // Rare
);

GameCard woodsVeteran(int index) => GameCard(
  id: 'woods_vet_$index',
  name: 'Woods Veteran',
  damage: 7, // +2 from common warrior
  health: 12, // +2 from common warrior
  tick: 3,
  element: 'Woods',
  abilities: const [],
  cost: 3,
  rarity: 2, // Rare
);

// ============================================================================
// EPIC CARDS (Rarity 3) - Max 2 copies each - Specialists with abilities
// ============================================================================

/// Support card: defensive buffs/debuffs
GameCard lakeShieldTotem(int index) => GameCard(
  id: 'lake_shield_$index',
  name: 'Lake Shield Totem',
  damage: 0,
  health: 1,
  tick: 3,
  element: 'Lake',
  abilities: const ['shield_2', 'stack_debuff_enemy_damage_2'],
  cost: 2,
  rarity: 3, // Epic - support cards are valuable
);

/// Support card: offensive buffs
GameCard desertWarBanner(int index) => GameCard(
  id: 'desert_banner_$index',
  name: 'Desert War Banner',
  damage: 0,
  health: 1,
  tick: 3,
  element: 'Desert',
  abilities: const ['fury_2', 'stack_buff_damage_2'],
  cost: 2,
  rarity: 3, // Epic - support cards are valuable
);

/// Woods support: healing/regen
GameCard woodsHealingTree(int index) => GameCard(
  id: 'woods_heal_$index',
  name: 'Woods Healing Tree',
  damage: 0,
  health: 3,
  tick: 4,
  element: 'Woods',
  abilities: const ['heal_ally_2', 'regen_1'],
  cost: 2,
  rarity: 3, // Epic
);

/// Elite heavy hitter - Desert Berserker
GameCard desertBerserker(int index) => GameCard(
  id: 'desert_berserker_$index',
  name: 'Desert Berserker',
  damage: 12, // Very high damage
  health: 10, // Lower health - glass cannon
  tick: 4,
  element: 'Desert',
  abilities: const ['fury_1'], // +1 damage when attacking
  cost: 4,
  rarity: 3, // Epic
);

/// Elite tank - Lake Guardian
GameCard lakeGuardian(int index) => GameCard(
  id: 'lake_guardian_$index',
  name: 'Lake Guardian',
  damage: 6,
  health: 20, // Very tanky
  tick: 5,
  element: 'Lake',
  abilities: const ['shield_1'], // Reduces incoming damage
  cost: 4,
  rarity: 3, // Epic
);

/// Balanced elite - Woods Sentinel
GameCard woodsSentinel(int index) => GameCard(
  id: 'woods_sentinel_$index',
  name: 'Woods Sentinel',
  damage: 8,
  health: 14,
  tick: 4,
  element: 'Woods',
  abilities: const ['regen_1'], // Heals 1 HP per tick
  cost: 4,
  rarity: 3, // Epic
);

// ============================================================================
// LEGENDARY CARDS (Rarity 4) - Max 1 copy each - Champions
// ============================================================================

/// Desert Champion - The Sunfire Warlord
GameCard sunfireWarlord() => GameCard(
  id: 'legendary_desert_warlord',
  name: 'Sunfire Warlord',
  damage: 15,
  health: 18,
  tick: 5,
  element: 'Desert',
  abilities: const ['fury_2', 'cleave'], // +2 damage, hits multiple
  cost: 5,
  rarity: 4, // Legendary
);

/// Lake Champion - The Tidal Leviathan
GameCard tidalLeviathan() => GameCard(
  id: 'legendary_lake_leviathan',
  name: 'Tidal Leviathan',
  damage: 10,
  health: 28,
  tick: 6,
  element: 'Lake',
  abilities: const ['shield_3', 'regenerate'], // Massive tank
  cost: 5,
  rarity: 4, // Legendary
);

/// Woods Champion - The Ancient Treant
GameCard ancientTreant() => GameCard(
  id: 'legendary_woods_treant',
  name: 'Ancient Treant',
  damage: 12,
  health: 22,
  tick: 5,
  element: 'Woods',
  abilities: const ['regen_2', 'thorns_3'], // Heals and reflects damage
  cost: 5,
  rarity: 4, // Legendary
);

// ============================================================================
// RARITY HELPERS
// ============================================================================

/// Get max copies allowed in deck by rarity
int maxCopiesByRarity(int rarity) {
  switch (rarity) {
    case 1:
      return 99; // Common - unlimited
    case 2:
      return 3; // Rare - max 3
    case 3:
      return 2; // Epic - max 2
    case 4:
      return 1; // Legendary - max 1
    default:
      return 99;
  }
}

/// Get rarity name for display
String rarityName(int rarity) {
  switch (rarity) {
    case 1:
      return 'Common';
    case 2:
      return 'Rare';
    case 3:
      return 'Epic';
    case 4:
      return 'Legendary';
    default:
      return 'Unknown';
  }
}

// ============================================================================
// DECK BUILDERS
// ============================================================================

/// Build a simple 25-card starter deck - mostly common with 1 rare per element
List<GameCard> buildStarterCardPool() {
  final cards = <GameCard>[];

  // 6 Common Quick Strikes: 2 of each element
  for (int i = 0; i < 2; i++) {
    cards.add(desertQuickStrike(i));
    cards.add(lakeQuickStrike(i));
    cards.add(woodsQuickStrike(i));
  }

  // 3 Rare Elite Strikers: 1 of each element
  cards.add(desertEliteStriker(0));
  cards.add(lakeEliteStriker(0));
  cards.add(woodsEliteStriker(0));

  // 6 Common Warriors: 2 of each element
  for (int i = 0; i < 2; i++) {
    cards.add(desertWarrior(i));
    cards.add(lakeWarrior(i));
    cards.add(woodsWarrior(i));
  }

  // 3 Rare Veterans: 1 of each element
  cards.add(desertVeteran(0));
  cards.add(lakeVeteran(0));
  cards.add(woodsVeteran(0));

  // 6 Common Tanks: 2 of each element
  cards.add(desertTank(0));
  cards.add(desertTank(1));
  cards.add(lakeTank(0));
  cards.add(lakeTank(1));
  cards.add(woodsTank(0));
  cards.add(woodsTank(1));

  // 1 Epic card (random element based on player preference later)
  cards.add(lakeShieldTotem(0));

  assert(cards.length == 25);
  return cards;
}

/// Build the full card pool available for deck building (with scarcity limits)
/// This is what players can pick from in the deck editor
List<GameCard> buildFullCardPool() {
  final cards = <GameCard>[];

  // ===== COMMON CARDS (unlimited in pool, show 5 of each) =====
  for (int i = 0; i < 5; i++) {
    cards.add(desertQuickStrike(i));
    cards.add(lakeQuickStrike(i));
    cards.add(woodsQuickStrike(i));
    cards.add(desertWarrior(i));
    cards.add(lakeWarrior(i));
    cards.add(woodsWarrior(i));
  }
  for (int i = 0; i < 4; i++) {
    cards.add(desertTank(i));
    cards.add(lakeTank(i));
    cards.add(woodsTank(i));
  }

  // ===== RARE CARDS (max 3 copies each) =====
  for (int i = 0; i < 3; i++) {
    cards.add(desertEliteStriker(i));
    cards.add(lakeEliteStriker(i));
    cards.add(woodsEliteStriker(i));
    cards.add(desertVeteran(i));
    cards.add(lakeVeteran(i));
    cards.add(woodsVeteran(i));
  }

  // ===== EPIC CARDS (max 2 copies each) =====
  for (int i = 0; i < 2; i++) {
    cards.add(lakeShieldTotem(i));
    cards.add(desertWarBanner(i));
    cards.add(woodsHealingTree(i));
    cards.add(desertBerserker(i));
    cards.add(lakeGuardian(i));
    cards.add(woodsSentinel(i));
  }

  // ===== LEGENDARY CARDS (max 1 copy each) =====
  cards.add(sunfireWarlord());
  cards.add(tidalLeviathan());
  cards.add(ancientTreant());

  return cards;
}

/// Terrain-focused deck: Lake Control.
/// Heavier on Lake units with some Woods/Desert splash.
List<GameCard> buildWaterControlDeck() {
  final cards = <GameCard>[];

  // Quick Strikes (8): 5 Water, 2 Nature, 1 Fire
  for (int i = 0; i < 6; i++) {
    cards.add(lakeQuickStrike(i));
  }
  // Drop one Water QS to make room for support
  cards.removeLast();
  cards.add(woodsQuickStrike(0));
  cards.add(woodsQuickStrike(1));
  cards.add(desertQuickStrike(0));

  // Warriors (8): 4 Water, 3 Nature, 1 Fire
  for (int i = 0; i < 5; i++) {
    cards.add(lakeWarrior(i));
  }
  // Drop one Water Warrior to make room for support
  cards.removeLast();
  cards.add(woodsWarrior(0));
  cards.add(woodsWarrior(1));
  cards.add(woodsWarrior(2));
  cards.add(desertWarrior(0));

  // Tanks (7): 3 Water, 2 Nature, 2 Fire
  cards.add(lakeTank(0));
  cards.add(lakeTank(1));
  cards.add(lakeTank(2));
  cards.add(woodsTank(0));
  cards.add(woodsTank(1));
  cards.add(desertTank(0));
  cards.add(desertTank(1));

  // Support: 2 Water Shield Totems (0 dmg / 1 HP buff cards)
  cards.add(lakeShieldTotem(0));
  cards.add(lakeShieldTotem(1));

  assert(cards.length == 25);
  return cards;
}

/// Terrain-focused deck: Desert Aggro.
/// Heavier on Desert units with some Woods/Lake splash.
List<GameCard> buildFireAggroDeck() {
  final cards = <GameCard>[];

  // Quick Strikes (8): 5 Fire, 2 Nature, 1 Water
  for (int i = 0; i < 6; i++) {
    cards.add(desertQuickStrike(i));
  }
  // Drop one Fire QS to make room for support
  cards.removeLast();
  cards.add(woodsQuickStrike(0));
  cards.add(woodsQuickStrike(1));
  cards.add(lakeQuickStrike(0));

  // Warriors (8): 4 Fire, 3 Nature, 1 Water
  for (int i = 0; i < 5; i++) {
    cards.add(desertWarrior(i));
  }
  // Drop one Fire Warrior to make room for support
  cards.removeLast();
  cards.add(woodsWarrior(0));
  cards.add(woodsWarrior(1));
  cards.add(woodsWarrior(2));
  cards.add(lakeWarrior(0));

  // Tanks (7): 3 Fire, 2 Nature, 2 Water
  cards.add(desertTank(0));
  cards.add(desertTank(1));
  cards.add(desertTank(2));
  cards.add(woodsTank(0));
  cards.add(woodsTank(1));
  cards.add(lakeTank(0));
  cards.add(lakeTank(1));

  // Support: 2 Fire War Banners (0 dmg / 1 HP buff cards)
  cards.add(desertWarBanner(0));
  cards.add(desertWarBanner(1));

  assert(cards.length == 25);
  return cards;
}
