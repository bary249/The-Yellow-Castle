import '../models/card.dart';

/// Central place to define all base card types (archetypes).
///
/// For now we keep mechanics simple but add elements and stat variety
/// so simulations can explore richer matchups.

/// Basic archetype identifiers
// We use simple IDs; decks will refer to these by copying.

GameCard desertQuickStrike(int index) => GameCard(
  id: 'desert_qs_$index',
  name: 'Desert Quick Strike',
  damage: 4,
  health: 4,
  tick: 1,
  element: 'Desert',
  abilities: const [],
  cost: 1,
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
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
  rarity: 1,
);

/// Support card: 0 damage, 1 HP, provides defensive buffs/debuffs for Lake-aligned lanes.
GameCard lakeShieldTotem(int index) => GameCard(
  id: 'lake_shield_$index',
  name: 'Lake Shield Totem',
  damage: 0,
  health: 1,
  tick: 3,
  element: 'Lake',
  abilities: const ['shield_2', 'stack_debuff_enemy_damage_2'],
  cost: 2,
  rarity: 1,
);

/// Support card: 0 damage, 1 HP, provides offensive buffs for Desert-aligned lanes.
GameCard desertWarBanner(int index) => GameCard(
  id: 'desert_banner_$index',
  name: 'Desert War Banner',
  damage: 0,
  health: 1,
  tick: 3,
  element: 'Desert',
  abilities: const ['fury_2', 'stack_buff_damage_2'],
  cost: 2,
  rarity: 1,
);

/// Build a simple 25-card starter deck composition using the archetypes above.
List<GameCard> buildStarterCardPool() {
  final cards = <GameCard>[];

  // 9 Quick Strikes: 3 of each element
  for (int i = 0; i < 3; i++) {
    cards.add(desertQuickStrike(i));
    cards.add(lakeQuickStrike(i));
    cards.add(woodsQuickStrike(i));
  }

  // 9 Warriors: 3 of each element
  for (int i = 0; i < 3; i++) {
    cards.add(desertWarrior(i));
    cards.add(lakeWarrior(i));
    cards.add(woodsWarrior(i));
  }

  // 7 Tanks: spread across elements (3 Fire, 2 Water, 2 Nature)
  cards.add(desertTank(0));
  cards.add(desertTank(1));
  cards.add(desertTank(2));
  cards.add(lakeTank(0));
  cards.add(lakeTank(1));
  cards.add(woodsTank(0));
  cards.add(woodsTank(1));

  assert(cards.length == 25);
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
