/// Represents a hero that a player can select for a match.
/// Each hero has terrain affinities and a single-use ability.
class GameHero {
  final String id;
  final String name;
  final String description;
  final List<String>
  terrainAffinities; // 1-2 terrain types (e.g., ['Woods', 'Lake'])
  final HeroAbilityType abilityType;
  final String abilityDescription;

  /// Tracks whether the ability has been used this match.
  bool abilityUsed = false;

  GameHero({
    required this.id,
    required this.name,
    required this.description,
    required this.terrainAffinities,
    required this.abilityType,
    required this.abilityDescription,
  });

  /// Create a fresh copy for a new match (resets abilityUsed).
  GameHero copy() {
    return GameHero(
      id: id,
      name: name,
      description: description,
      terrainAffinities: List.from(terrainAffinities),
      abilityType: abilityType,
      abilityDescription: abilityDescription,
    );
  }

  /// Check if hero can use their ability (not yet used).
  bool get canUseAbility => !abilityUsed;

  /// Mark ability as used.
  void useAbility() {
    abilityUsed = true;
  }

  @override
  String toString() =>
      'Hero($name, terrains: $terrainAffinities, ability: $abilityType)';
}

/// Types of hero abilities available.
enum HeroAbilityType {
  /// Draw 2 extra cards this turn.
  drawCards,

  /// Give all your units +1 damage this turn.
  damageBoost,

  /// Heal all surviving units by 3 HP.
  healUnits,

  /// Deal direct damage to enemy base (e.g. 2 damage).
  directBaseDamage,

  /// Refill hand with starting deck cards.
  refillHand,
}
