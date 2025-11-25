import '../models/card.dart';

/// Central place to define all base card types (archetypes).
///
/// For now we keep mechanics simple but add elements and stat variety
/// so simulations can explore richer matchups.

/// Basic archetype identifiers
// We use simple IDs; decks will refer to these by copying.

GameCard fireQuickStrike(int index) => GameCard(
  id: 'fire_qs_$index',
  name: 'Fire Quick Strike',
  damage: 4,
  health: 4,
  tick: 1,
  element: 'Fire',
  abilities: const [],
  cost: 1,
  rarity: 1,
);

GameCard waterQuickStrike(int index) => GameCard(
  id: 'water_qs_$index',
  name: 'Water Quick Strike',
  damage: 3,
  health: 6,
  tick: 1,
  element: 'Water',
  abilities: const [],
  cost: 1,
  rarity: 1,
);

GameCard natureQuickStrike(int index) => GameCard(
  id: 'nature_qs_$index',
  name: 'Nature Quick Strike',
  damage: 3,
  health: 5,
  tick: 1,
  element: 'Nature',
  abilities: const [],
  cost: 1,
  rarity: 1,
);

GameCard fireWarrior(int index) => GameCard(
  id: 'fire_war_$index',
  name: 'Fire Warrior',
  damage: 6,
  health: 9,
  tick: 3,
  element: 'Fire',
  abilities: const [],
  cost: 2,
  rarity: 1,
);

GameCard waterWarrior(int index) => GameCard(
  id: 'water_war_$index',
  name: 'Water Warrior',
  damage: 5,
  health: 11,
  tick: 3,
  element: 'Water',
  abilities: const [],
  cost: 2,
  rarity: 1,
);

GameCard natureWarrior(int index) => GameCard(
  id: 'nature_war_$index',
  name: 'Nature Warrior',
  damage: 5,
  health: 10,
  tick: 3,
  element: 'Nature',
  abilities: const [],
  cost: 2,
  rarity: 1,
);

GameCard fireTank(int index) => GameCard(
  id: 'fire_tank_$index',
  name: 'Fire Tank',
  damage: 9,
  health: 14,
  tick: 5,
  element: 'Fire',
  abilities: const [],
  cost: 3,
  rarity: 1,
);

GameCard waterTank(int index) => GameCard(
  id: 'water_tank_$index',
  name: 'Water Tank',
  damage: 8,
  health: 16,
  tick: 5,
  element: 'Water',
  abilities: const [],
  cost: 3,
  rarity: 1,
);

GameCard natureTank(int index) => GameCard(
  id: 'nature_tank_$index',
  name: 'Nature Tank',
  damage: 8,
  health: 15,
  tick: 5,
  element: 'Nature',
  abilities: const [],
  cost: 3,
  rarity: 1,
);

/// Support card: 0 damage, 1 HP, provides defensive buffs/debuffs for Water lanes.
GameCard waterShieldTotem(int index) => GameCard(
  id: 'water_shield_$index',
  name: 'Water Shield Totem',
  damage: 0,
  health: 1,
  tick: 3,
  element: 'Water',
  abilities: const ['shield_2', 'stack_debuff_enemy_damage_2'],
  cost: 2,
  rarity: 1,
);

/// Support card: 0 damage, 1 HP, provides offensive buffs for Fire lanes.
GameCard fireWarBanner(int index) => GameCard(
  id: 'fire_banner_$index',
  name: 'Fire War Banner',
  damage: 0,
  health: 1,
  tick: 3,
  element: 'Fire',
  abilities: const ['fury_2', 'stack_buff_damage_2'],
  cost: 2,
  rarity: 1,
);

/// Build a simple 25-card starter deck composition using the archetypes above.
List<GameCard> buildStarterCardPool() {
  final cards = <GameCard>[];

  // 9 Quick Strikes: 3 of each element
  for (int i = 0; i < 3; i++) {
    cards.add(fireQuickStrike(i));
    cards.add(waterQuickStrike(i));
    cards.add(natureQuickStrike(i));
  }

  // 9 Warriors: 3 of each element
  for (int i = 0; i < 3; i++) {
    cards.add(fireWarrior(i));
    cards.add(waterWarrior(i));
    cards.add(natureWarrior(i));
  }

  // 7 Tanks: spread across elements (3 Fire, 2 Water, 2 Nature)
  cards.add(fireTank(0));
  cards.add(fireTank(1));
  cards.add(fireTank(2));
  cards.add(waterTank(0));
  cards.add(waterTank(1));
  cards.add(natureTank(0));
  cards.add(natureTank(1));

  assert(cards.length == 25);
  return cards;
}

/// Element-focused deck: Water Control.
/// Heavier on Water units with some Nature/Fire splash.
List<GameCard> buildWaterControlDeck() {
  final cards = <GameCard>[];

  // Quick Strikes (8): 5 Water, 2 Nature, 1 Fire
  for (int i = 0; i < 6; i++) {
    cards.add(waterQuickStrike(i));
  }
  // Drop one Water QS to make room for support
  cards.removeLast();
  cards.add(natureQuickStrike(0));
  cards.add(natureQuickStrike(1));
  cards.add(fireQuickStrike(0));

  // Warriors (8): 4 Water, 3 Nature, 1 Fire
  for (int i = 0; i < 5; i++) {
    cards.add(waterWarrior(i));
  }
  // Drop one Water Warrior to make room for support
  cards.removeLast();
  cards.add(natureWarrior(0));
  cards.add(natureWarrior(1));
  cards.add(natureWarrior(2));
  cards.add(fireWarrior(0));

  // Tanks (7): 3 Water, 2 Nature, 2 Fire
  cards.add(waterTank(0));
  cards.add(waterTank(1));
  cards.add(waterTank(2));
  cards.add(natureTank(0));
  cards.add(natureTank(1));
  cards.add(fireTank(0));
  cards.add(fireTank(1));

  // Support: 2 Water Shield Totems (0 dmg / 1 HP buff cards)
  cards.add(waterShieldTotem(0));
  cards.add(waterShieldTotem(1));

  assert(cards.length == 25);
  return cards;
}

/// Element-focused deck: Fire Aggro.
/// Heavier on Fire units with some Nature/Water splash.
List<GameCard> buildFireAggroDeck() {
  final cards = <GameCard>[];

  // Quick Strikes (8): 5 Fire, 2 Nature, 1 Water
  for (int i = 0; i < 6; i++) {
    cards.add(fireQuickStrike(i));
  }
  // Drop one Fire QS to make room for support
  cards.removeLast();
  cards.add(natureQuickStrike(0));
  cards.add(natureQuickStrike(1));
  cards.add(waterQuickStrike(0));

  // Warriors (8): 4 Fire, 3 Nature, 1 Water
  for (int i = 0; i < 5; i++) {
    cards.add(fireWarrior(i));
  }
  // Drop one Fire Warrior to make room for support
  cards.removeLast();
  cards.add(natureWarrior(0));
  cards.add(natureWarrior(1));
  cards.add(natureWarrior(2));
  cards.add(waterWarrior(0));

  // Tanks (7): 3 Fire, 2 Nature, 2 Water
  cards.add(fireTank(0));
  cards.add(fireTank(1));
  cards.add(fireTank(2));
  cards.add(natureTank(0));
  cards.add(natureTank(1));
  cards.add(waterTank(0));
  cards.add(waterTank(1));

  // Support: 2 Fire War Banners (0 dmg / 1 HP buff cards)
  cards.add(fireWarBanner(0));
  cards.add(fireWarBanner(1));

  assert(cards.length == 25);
  return cards;
}
