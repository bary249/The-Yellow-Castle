/// Represents a playing card in the game
/// Phase 1: simple version, but already prepared for elements/families/abilities
class GameCard {
  final String id;
  final String name;
  final int damage;
  final int health;

  /// 1-5: determines when the card acts in combat
  final int tick;

  /// 0, 1, or 2: how many tiles this card moves forward each turn
  /// 0 = stationary (doesn't advance)
  /// 1 = normal (moves 1 tile per turn)
  /// 2 = fast (moves 2 tiles per turn - can reach enemy base from own base in 1 turn)
  final int moveSpeed;

  /// Optional element for advantage matrix (e.g. 'Fire', 'Water', 'Nature')
  final String? element;

  /// Optional character family (e.g. 'Monkey', 'Ant')
  final String? family;

  /// Simple ability tags (e.g. 'pierce', 'shield', 'haste')
  final List<String> abilities;

  /// Basic balance knobs (unused by core logic for now)
  final int cost;
  final int rarity; // 1-5

  // Runtime state
  int currentHealth;

  GameCard({
    required this.id,
    required this.name,
    required this.damage,
    required this.health,
    required this.tick,
    this.moveSpeed = 1, // Default: normal speed (1 tile per turn)
    this.element,
    this.family,
    List<String>? abilities,
    this.cost = 0,
    this.rarity = 1,
  }) : abilities = List.unmodifiable(abilities ?? const []),
       currentHealth = health;

  /// Create a copy of this card (for deck shuffling/dealing)
  GameCard copy() {
    return GameCard(
      id: id,
      name: name,
      damage: damage,
      health: health,
      tick: tick,
      moveSpeed: moveSpeed,
      element: element,
      family: family,
      abilities: abilities,
      cost: cost,
      rarity: rarity,
    );
  }

  /// Check if card is still alive
  bool get isAlive => currentHealth > 0;

  /// Take damage and return true if card dies
  bool takeDamage(int amount) {
    currentHealth -= amount;
    if (currentHealth < 0) currentHealth = 0;
    return !isAlive;
  }

  /// Reset health to max (for new matches)
  void reset() {
    currentHealth = health;
  }

  @override
  String toString() =>
      '$name (HP: $currentHealth/$health, DMG: $damage, Tick: $tick, Speed: $moveSpeed)';

  /// Serialize to JSON for saving
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'damage': damage,
    'health': health,
    'tick': tick,
    'moveSpeed': moveSpeed,
    'element': element,
    'family': family,
    'abilities': abilities,
    'cost': cost,
    'rarity': rarity,
    'currentHealth': currentHealth,
  };

  /// Create from JSON
  factory GameCard.fromJson(Map<String, dynamic> json) => GameCard(
    id: json['id'] as String,
    name: json['name'] as String,
    damage: json['damage'] as int,
    health: json['health'] as int,
    tick: json['tick'] as int,
    moveSpeed: json['moveSpeed'] as int? ?? 1,
    element: json['element'] as String?,
    family: json['family'] as String?,
    abilities: List<String>.from(json['abilities'] ?? []),
    cost: json['cost'] as int? ?? 0,
    rarity: json['rarity'] as int? ?? 1,
  )..currentHealth = json['currentHealth'] as int? ?? json['health'] as int;

  /// Factory method for creating test cards
  factory GameCard.test({
    String? id,
    String? name,
    int damage = 5,
    int health = 10,
    int tick = 3,
    int moveSpeed = 1,
    String? element,
    String? family,
    List<String>? abilities,
    int cost = 0,
    int rarity = 1,
  }) {
    return GameCard(
      id: id ?? 'card_${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? 'Test Card',
      damage: damage,
      health: health,
      tick: tick,
      moveSpeed: moveSpeed,
      element: element,
      family: family,
      abilities: abilities,
      cost: cost,
      rarity: rarity,
    );
  }
}
