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
  moveSpeed: 2, // Fast - reaches enemy quickly
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
  moveSpeed: 2, // Fast - reaches enemy quickly
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
  moveSpeed: 2, // Fast - reaches enemy quickly
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 0, // Stationary - holds position
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
  moveSpeed: 0, // Stationary - holds position
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
  moveSpeed: 0, // Stationary - holds position
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
  moveSpeed: 2, // Fast - like Quick Strike
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
  moveSpeed: 2, // Fast - like Quick Strike
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
  moveSpeed: 2, // Fast - like Quick Strike
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 0, // Stationary support
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
  moveSpeed: 0, // Stationary support
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
  moveSpeed: 0, // Stationary support
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
  moveSpeed: 1, // Normal speed
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
  moveSpeed: 0, // Stationary - elite tank holds position
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
  moveSpeed: 1, // Normal speed
  element: 'Woods',
  abilities: const ['regen_1'], // Heals 1 HP per tick
  cost: 4,
  rarity: 3, // Epic
);

/// Tactical support - Desert Shadow Scout
/// When in front with a back card, hides the back card's identity from enemy
GameCard desertShadowScout(int index) => GameCard(
  id: 'desert_shadow_$index',
  name: 'Desert Shadow Scout',
  damage: 5,
  health: 6,
  tick: 2,
  moveSpeed: 2, // Fast scout
  element: 'Desert',
  abilities: const ['conceal_back'], // Hides back card from enemy view
  cost: 3,
  rarity: 3, // Epic
);

/// Tactical support - Lake Mist Weaver
/// When in front with a back card, hides the back card's identity from enemy
GameCard lakeMistWeaver(int index) => GameCard(
  id: 'lake_mist_$index',
  name: 'Lake Mist Weaver',
  damage: 4,
  health: 8,
  tick: 2,
  moveSpeed: 1, // Normal speed
  element: 'Lake',
  abilities: const ['conceal_back', 'shield_1'], // Conceals and has light armor
  cost: 3,
  rarity: 3, // Epic
);

/// Tactical support - Woods Shroud Walker
/// When in front with a back card, hides the back card's identity from enemy
GameCard woodsShroudWalker(int index) => GameCard(
  id: 'woods_shroud_$index',
  name: 'Woods Shroud Walker',
  damage: 4,
  health: 7,
  tick: 2,
  moveSpeed: 1, // Normal speed
  element: 'Woods',
  abilities: const ['conceal_back', 'regen_1'], // Conceals and regenerates
  cost: 3,
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
  moveSpeed: 1, // Normal speed - powerful but balanced
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
  tick: 5,
  moveSpeed: 0, // Stationary - legendary tank holds the line
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
  moveSpeed: 0, // Stationary - legendary tree holds position
  element: 'Woods',
  abilities: const ['regen_2', 'thorns_3'], // Heals and reflects damage
  cost: 5,
  rarity: 4, // Legendary
);

/// Neutral Champion - Shadow Assassin (stealth)
GameCard shadowAssassin() => GameCard(
  id: 'legendary_neutral_shadow_assassin',
  name: 'Shadow Assassin',
  damage: 11,
  health: 7,
  tick: 2,
  moveSpeed: 2, // Fast, fragile assassin
  element: null, // Neutral
  abilities: const ['stealth_pass'],
  cost: 5,
  rarity: 4, // Legendary
);

// ============================================================================
// NAPOLEON'S CAMPAIGN CARDS
// ============================================================================
// Historical French military units from the Napoleonic era.
// Terrain: Woods (primary), Lake (cavalry)
// Playstyle: Balanced/Tactical with strong artillery and elite infantry

// ------------------ COMMON CARDS (Starter Deck) ------------------

/// Voltigeur - Light infantry skirmishers, fast and agile
/// Historical: Elite light infantry who screened the army's advance
GameCard napoleonVoltigeur(int index) => GameCard(
  id: 'napoleon_voltigeur_$index',
  name: 'Voltigeur',
  damage: 4,
  health: 5,
  tick: 1,
  moveSpeed: 2, // Fast skirmishers
  element: 'Woods',
  abilities: const [],
  cost: 1,
  rarity: 1, // Common
);

/// Fusilier - Standard line infantry, backbone of the army
/// Historical: Regular infantry forming the bulk of Napoleon's forces
GameCard napoleonFusilier(int index) => GameCard(
  id: 'napoleon_fusilier_$index',
  name: 'Fusilier',
  damage: 5,
  health: 9,
  tick: 3,
  moveSpeed: 1, // Standard march
  element: 'Woods',
  abilities: const [],
  cost: 2,
  rarity: 1, // Common
);

/// Line Infantry - Standard infantry backbone
/// Historical: The main fighting force of Napoleon's army
GameCard napoleonLineInfantry(int index) => GameCard(
  id: 'napoleon_line_infantry_$index',
  name: 'Line Infantry',
  damage: 6,
  health: 12,
  tick: 3, // Faster to be more useful
  moveSpeed: 1,
  element: 'Woods',
  abilities: const [],
  cost: 2,
  rarity: 1, // Common
);

/// Field Cannon - Mobile artillery piece
/// Historical: Napoleon's expertise - "God fights on the side with the best artillery"
GameCard napoleonFieldCannon(int index) => GameCard(
  id: 'napoleon_field_cannon_$index',
  name: 'Field Cannon',
  damage: 6,
  health: 8,
  tick: 2,
  moveSpeed: 0, // Stationary artillery
  element: 'Woods',
  abilities: const ['ranged'], // Can attack from back position
  cost: 2,
  rarity: 1, // Common
);

/// Sapper - Combat engineer providing fortification
/// Historical: Military engineers who built fortifications
GameCard napoleonSapper(int index) => GameCard(
  id: 'napoleon_sapper_$index',
  name: 'Sapper',
  damage: 4,
  health: 8,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['fortify_1'], // +1 shield to all allies in lane
  cost: 2,
  rarity: 1, // Common
);

/// Drummer Boy - Morale booster, inspires troops
/// Historical: Young drummers who kept troops marching in rhythm
GameCard napoleonDrummerBoy(int index) => GameCard(
  id: 'napoleon_drummer_$index',
  name: 'Drummer Boy',
  damage: 0,
  health: 4,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['inspire_1'], // +1 damage to all allies in lane
  cost: 1,
  rarity: 1, // Common
);

// ------------------ RARE CARDS (Starter Deck) ------------------

/// Grenadier - Elite heavy infantry with fury
/// Historical: Tallest, strongest soldiers who threw grenades
GameCard napoleonGrenadier(int index) => GameCard(
  id: 'napoleon_grenadier_$index',
  name: 'Grenadier',
  damage: 8,
  health: 14,
  tick: 3, // Faster to actually use fury
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['fury_1'], // +1 damage when attacking
  cost: 3,
  rarity: 2, // Rare
);

/// Hussar - Light cavalry, fast and deadly
/// Historical: Dashing light cavalry known for bold charges
GameCard napoleonHussar(int index) => GameCard(
  id: 'napoleon_hussar_$index',
  name: 'Hussar',
  damage: 6,
  health: 6,
  tick: 2,
  moveSpeed: 2, // Fast cavalry
  element: 'Lake',
  abilities: const ['first_strike'], // Attacks first in same tick
  cost: 3,
  rarity: 2, // Rare
);

/// Cuirassier - Heavy armored cavalry
/// Historical: Armored cavalry that delivered devastating charges
GameCard napoleonCuirassier(int index) => GameCard(
  id: 'napoleon_cuirassier_$index',
  name: 'Cuirassier',
  damage: 8,
  health: 10,
  tick: 3,
  moveSpeed: 1,
  element: 'Lake',
  abilities: const ['shield_1'], // Armor reduces damage
  cost: 3,
  rarity: 2, // Rare
);

// ------------------ RARE CARDS (Campaign Acquirable) ------------------

/// Young Guard - Junior elite troops with rally ability
/// Historical: Newer recruits to the Imperial Guard
GameCard napoleonYoungGuard(int index) => GameCard(
  id: 'napoleon_young_guard_$index',
  name: 'Young Guard',
  damage: 6,
  health: 10,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['rally_1'], // Adjacent allies gain +1 damage
  cost: 3,
  rarity: 2, // Rare
);

/// Chasseur à Cheval - Light cavalry hunters
/// Historical: Light cavalry of the Imperial Guard
GameCard napoleonChasseur(int index) => GameCard(
  id: 'napoleon_chasseur_$index',
  name: 'Chasseur à Cheval',
  damage: 5,
  health: 7,
  tick: 2,
  moveSpeed: 2, // Fast light cavalry
  element: 'Lake',
  abilities: const ['first_strike'],
  cost: 2,
  rarity: 2, // Rare
);

/// Horse Artillery - Mobile artillery that can reposition
/// Historical: Fast-moving artillery supporting cavalry
GameCard napoleonHorseArtillery(int index) => GameCard(
  id: 'napoleon_horse_artillery_$index',
  name: 'Horse Artillery',
  damage: 7,
  health: 6,
  tick: 2,
  moveSpeed: 1, // Can move unlike field cannon
  element: 'Woods',
  abilities: const ['ranged'],
  cost: 3,
  rarity: 2, // Rare
);

// ------------------ EPIC CARDS (Campaign Acquirable) ------------------

/// Old Guard - The elite of the elite, never retreated
/// Historical: "The Guard dies, it does not surrender!"
GameCard napoleonOldGuard(int index) => GameCard(
  id: 'napoleon_old_guard_$index',
  name: 'Old Guard',
  damage: 9,
  health: 14,
  tick: 4,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['fury_2', 'shield_1'], // Elite stats
  cost: 4,
  rarity: 3, // Epic
);

/// Marshal Ney - "The Bravest of the Brave"
/// Historical: One of Napoleon's most famous marshals
GameCard napoleonMarshalNey(int index) => GameCard(
  id: 'napoleon_marshal_ney_$index',
  name: 'Marshal Ney',
  damage: 8,
  health: 11,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['command_1', 'fury_1'], // Leadership + aggression
  cost: 4,
  rarity: 3, // Epic
);

/// Grand Battery - Massed artillery formation
/// Historical: Napoleon's tactic of concentrating artillery fire
GameCard napoleonGrandBattery(int index) => GameCard(
  id: 'napoleon_grand_battery_$index',
  name: 'Grand Battery',
  damage: 10,
  health: 10,
  tick: 3,
  moveSpeed: 0, // Stationary
  element: 'Woods',
  abilities: const ['ranged', 'cleave'], // Hits all enemies in lane
  cost: 4,
  rarity: 3, // Epic
);

/// Polish Lancer - Elite foreign cavalry
/// Historical: Loyal Polish lancers in Napoleon's service
GameCard napoleonPolishLancer(int index) => GameCard(
  id: 'napoleon_polish_lancer_$index',
  name: 'Polish Lancer',
  damage: 7,
  health: 8,
  tick: 2,
  moveSpeed: 2, // Fast cavalry
  element: 'Lake',
  abilities: const ['first_strike', 'fury_1'],
  cost: 4,
  rarity: 3, // Epic
);

/// Imperial Eagle - The sacred standard of the regiment
/// Historical: Losing an Eagle was the ultimate disgrace
GameCard napoleonImperialEagle(int index) => GameCard(
  id: 'napoleon_imperial_eagle_$index',
  name: 'Imperial Eagle',
  damage: 0,
  health: 6,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['inspire_2', 'rally_1'], // Major morale boost
  cost: 3,
  rarity: 3, // Epic
);

/// Siege Cannon - Massive artillery that fires at distant tiles in the same lane
/// Historical: Heavy siege artillery used to bombard fortifications from afar
/// Special: Attacks enemies in OTHER TILES of the same lane (e.g., base → middle)
/// Cannot attack if contested on its own tile (enemies present at same position)
GameCard napoleonSiegeCannon(int index) => GameCard(
  id: 'napoleon_siege_cannon_$index',
  name: 'Siege Cannon',
  damage: 12, // High damage
  health: 8,
  tick: 5, // Slow
  moveSpeed: 0, // Stationary
  element: 'Woods',
  abilities: const [
    'far_attack',
  ], // Attacks different lane, disabled if contested
  cost: 4,
  rarity: 3, // Epic
);

// ------------------ LEGENDARY CARDS (Campaign Acquirable) ------------------

/// Napoleon's Guard - The Emperor's personal bodyguard
/// Historical: The most elite soldiers, personally led by Napoleon
GameCard napoleonsGuard() => GameCard(
  id: 'napoleon_legendary_guard',
  name: "Napoleon's Guard",
  damage: 12,
  health: 18,
  tick: 5,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['fury_2', 'shield_2', 'inspire_1'],
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
    // Conceal cards - hide back card from enemy
    cards.add(desertShadowScout(i));
    cards.add(lakeMistWeaver(i));
    cards.add(woodsShroudWalker(i));
  }

  // ===== LEGENDARY CARDS (max 1 copy each) =====
  cards.add(sunfireWarlord());
  cards.add(tidalLeviathan());
  cards.add(ancientTreant());
  cards.add(shadowAssassin());

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

// ============================================================================
// NAPOLEON'S CAMPAIGN DECK BUILDERS
// ============================================================================

/// Napoleon's 25-card starter deck for campaign mode.
/// Composition:
/// - 16 Common cards (6 types)
/// - 9 Rare cards (3 types × 3 copies)
List<GameCard> buildNapoleonStarterDeck() {
  final cards = <GameCard>[];

  // === COMMON CARDS (16 total) ===

  // Voltigeur ×3 - Fast skirmishers (tick 1, move 2)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonVoltigeur(i));
  }

  // Fusilier ×3 - Standard infantry (tick 3, move 1)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonFusilier(i));
  }

  // Line Infantry ×3 - Veteran soldiers (tick 4, move 1)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonLineInfantry(i));
  }

  // Field Cannon ×2 - Artillery with ranged (tick 2, move 0)
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonFieldCannon(i));
  }

  // Sapper ×2 - Engineers with fortify_1 (tick 3, move 1)
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonSapper(i));
  }

  // Drummer Boy ×3 - Support with inspire_1 (tick 3, move 1)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonDrummerBoy(i));
  }

  // === RARE CARDS (9 total) ===

  // Grenadier ×3 - Elite infantry with fury_1 (tick 4, move 1)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonGrenadier(i));
  }

  // Hussar ×3 - Light cavalry with first_strike (tick 2, move 2)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonHussar(i));
  }

  // Cuirassier ×3 - Heavy cavalry with shield_1 (tick 3, move 1)
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonCuirassier(i));
  }

  assert(cards.length == 25, 'Napoleon starter deck must have 25 cards');
  return cards;
}

/// All cards available for Napoleon to acquire during campaign.
/// Does NOT include starter deck cards.
List<GameCard> buildNapoleonCampaignCardPool() {
  final cards = <GameCard>[];

  // === RARE CARDS (Campaign Acquirable) ===

  // Young Guard ×3 - rally_1
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonYoungGuard(i));
  }

  // Chasseur à Cheval ×3 - first_strike
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonChasseur(i));
  }

  // Horse Artillery ×3 - ranged
  for (int i = 0; i < 3; i++) {
    cards.add(napoleonHorseArtillery(i));
  }

  // === EPIC CARDS (Campaign Acquirable) ===

  // Old Guard ×2 - fury_2, shield_1
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonOldGuard(i));
  }

  // Marshal Ney ×2 - command_1, fury_1
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonMarshalNey(i));
  }

  // Grand Battery ×2 - ranged, cleave
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonGrandBattery(i));
  }

  // Polish Lancer ×2 - first_strike, fury_1
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonPolishLancer(i));
  }

  // Imperial Eagle ×2 - inspire_2, rally_1
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonImperialEagle(i));
  }

  // Siege Cannon ×2 - far_attack (attacks other lanes)
  for (int i = 0; i < 2; i++) {
    cards.add(napoleonSiegeCannon(i));
  }

  // === LEGENDARY CARDS (Campaign Acquirable) ===

  // Napoleon's Guard ×1 - fury_2, shield_2, inspire_1
  cards.add(napoleonsGuard());

  return cards;
}

// ============================================================================
// CAMPAIGN ENEMY DECKS
// ============================================================================

// ------------------ ACT 1: ITALIAN CAMPAIGN (Austrian Forces) ------------------

/// Austrian Jäger - Light infantry skirmisher
GameCard austrianJager(int index) => GameCard(
  id: 'austrian_jager_$index',
  name: 'Austrian Jäger',
  damage: 4,
  health: 5,
  tick: 1,
  moveSpeed: 2,
  element: 'Woods',
  abilities: const [],
  cost: 1,
  rarity: 1,
);

/// Austrian Line Infantry - Standard Habsburg soldiers
GameCard austrianLineInfantry(int index) => GameCard(
  id: 'austrian_line_$index',
  name: 'Austrian Infantry',
  damage: 5,
  health: 9,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const [],
  cost: 2,
  rarity: 1,
);

/// Austrian Grenadier - Elite heavy infantry
GameCard austrianGrenadier(int index) => GameCard(
  id: 'austrian_grenadier_$index',
  name: 'Austrian Grenadier',
  damage: 6,
  health: 11,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['shield_1'],
  cost: 2,
  rarity: 2,
);

/// Austrian Hussar - Light cavalry
GameCard austrianHussar(int index) => GameCard(
  id: 'austrian_hussar_$index',
  name: 'Austrian Hussar',
  damage: 5,
  health: 6,
  tick: 2,
  moveSpeed: 2,
  element: 'Lake',
  abilities: const [],
  cost: 2,
  rarity: 2,
);

/// Austrian Cuirassier - Heavy cavalry
GameCard austrianCuirassier(int index) => GameCard(
  id: 'austrian_cuirassier_$index',
  name: 'Austrian Cuirassier',
  damage: 7,
  health: 10,
  tick: 3,
  moveSpeed: 1,
  element: 'Lake',
  abilities: const ['shield_1'],
  cost: 3,
  rarity: 2,
);

/// Austrian Artillery - Field cannon
GameCard austrianArtillery(int index) => GameCard(
  id: 'austrian_artillery_$index',
  name: 'Austrian Cannon',
  damage: 5,
  health: 6,
  tick: 3,
  moveSpeed: 0,
  element: 'Woods',
  abilities: const ['ranged'],
  cost: 2,
  rarity: 1,
);

/// Austrian Officer - Provides command buff
GameCard austrianOfficer(int index) => GameCard(
  id: 'austrian_officer_$index',
  name: 'Austrian Officer',
  damage: 3,
  health: 7,
  tick: 3,
  moveSpeed: 1,
  element: 'Woods',
  abilities: const ['inspire_1'],
  cost: 2,
  rarity: 2,
);

/// Build Act 1 enemy deck - Austrian forces in Italy
/// Balanced deck for early campaign, slightly weaker than Napoleon's starter
List<GameCard> buildAct1EnemyDeck() {
  final cards = <GameCard>[];

  // Fast skirmishers ×4
  for (int i = 0; i < 4; i++) {
    cards.add(austrianJager(i));
  }

  // Line Infantry ×5
  for (int i = 0; i < 5; i++) {
    cards.add(austrianLineInfantry(i));
  }

  // Grenadiers ×3
  for (int i = 0; i < 3; i++) {
    cards.add(austrianGrenadier(i));
  }

  // Hussars ×3
  for (int i = 0; i < 3; i++) {
    cards.add(austrianHussar(i));
  }

  // Cuirassiers ×2
  for (int i = 0; i < 2; i++) {
    cards.add(austrianCuirassier(i));
  }

  // Artillery ×3
  for (int i = 0; i < 3; i++) {
    cards.add(austrianArtillery(i));
  }

  // Officers ×2
  for (int i = 0; i < 2; i++) {
    cards.add(austrianOfficer(i));
  }

  // Pad to 25 if needed
  while (cards.length < 25) {
    cards.add(austrianLineInfantry(cards.length));
  }

  assert(cards.length == 25, 'Act 1 enemy deck must have 25 cards');
  return cards;
}
