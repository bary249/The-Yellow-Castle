/// Represents a playing card in the game
/// TYC3: Turn-based AP system with manual targeting
class GameCard {
  final String id;
  final String name;
  final int damage;
  final int health;

  /// LEGACY: 1-5 tick value (kept for migration, will be removed)
  final int tick;

  /// 0, 1, or 2: how many tiles this card moves forward each turn
  /// 0 = stationary (doesn't advance)
  /// 1 = normal (moves 1 tile per turn)
  /// 2 = fast (moves 2 tiles per turn)
  final int moveSpeed;

  // ===== TYC3: ACTION POINT SYSTEM =====

  /// Maximum AP this card can hold (1-3, most cards = 1)
  final int maxAP;

  /// AP gained at the start of owner's turn (usually = maxAP)
  final int apPerTurn;

  /// AP cost to perform an attack (1-2, most cards = 1)
  final int attackAPCost;

  /// Attack range in tiles (1 = adjacent only, 2 = long range for cannons)
  final int attackRange;

  /// Current AP available (runtime state)
  int currentAP;

  /// Owner player ID (set when card is placed on board)
  String? ownerId;

  // ===== END TYC3 =====

  /// Optional element for terrain matching (e.g. 'Woods', 'Lake', 'Desert')
  final String? element;

  /// Optional character family (e.g. 'Monkey', 'Ant')
  final String? family;

  /// Ability tags (e.g. 'guard', 'ranged', 'fury_2', 'shield_1')
  final List<String> abilities;

  /// Basic balance knobs
  final int cost;
  final int rarity; // 1-4 (1=Common, 2=Rare, 3=Epic, 4=Legendary)

  // Runtime state
  int currentHealth;

  GameCard({
    required this.id,
    required this.name,
    required this.damage,
    required this.health,
    this.tick = 3, // Legacy default
    this.moveSpeed = 1, // Default: normal speed (1 tile per turn)
    // TYC3 AP fields - all units have 3 AP for simplicity
    this.maxAP = 3,
    this.apPerTurn = 3,
    this.attackAPCost = 1,
    this.attackRange = 1, // 1 = adjacent, 2 = long range
    this.element,
    this.family,
    List<String>? abilities,
    this.cost = 0,
    this.rarity = 1,
  }) : abilities = List.unmodifiable(abilities ?? const []),
       currentHealth = health,
       currentAP = 0; // Cards start with 0 AP when placed

  /// Create a copy of this card (for deck shuffling/dealing)
  GameCard copy() {
    return GameCard(
      id: id,
      name: name,
      damage: damage,
      health: health,
      tick: tick,
      moveSpeed: moveSpeed,
      maxAP: maxAP,
      apPerTurn: apPerTurn,
      attackAPCost: attackAPCost,
      attackRange: attackRange,
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

  /// Reset health and AP to starting values (for new matches)
  void reset() {
    currentHealth = health;
    currentAP = 0; // Cards start with 0 AP when placed
  }

  // ===== TYC3: AP METHODS =====

  /// Regenerate AP at the start of owner's turn
  void regenerateAP() {
    currentAP = (currentAP + apPerTurn).clamp(0, maxAP);
  }

  /// Check if card has enough AP to attack
  bool canAttack() => currentAP >= attackAPCost;

  /// Check if card has enough AP to move (costs 1 AP)
  bool canMove() => currentAP >= 1 && moveSpeed > 0;

  /// Spend AP for an attack. Returns true if successful.
  bool spendAttackAP() {
    if (!canAttack()) return false;
    currentAP -= attackAPCost;
    return true;
  }

  /// Spend AP for movement. Returns true if successful.
  bool spendMoveAP() {
    if (!canMove()) return false;
    currentAP -= 1;
    return true;
  }

  /// Check if this card has the 'ranged' ability (no retaliation)
  bool get isRanged => abilities.contains('ranged');

  /// Check if this card has the 'guard' ability (must be attacked first)
  bool get isGuard => abilities.contains('guard');

  /// Check if this card has long range attack (2 tiles)
  bool get isLongRange => attackRange >= 2 || abilities.contains('long_range');

  // ===== END TYC3 =====

  @override
  String toString() =>
      '$name (HP: $currentHealth/$health, DMG: $damage, AP: $currentAP/$maxAP, AtkCost: $attackAPCost)';

  /// Serialize to JSON for saving
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'damage': damage,
    'health': health,
    'tick': tick,
    'moveSpeed': moveSpeed,
    'maxAP': maxAP,
    'apPerTurn': apPerTurn,
    'attackAPCost': attackAPCost,
    'attackRange': attackRange,
    'element': element,
    'family': family,
    'abilities': abilities,
    'cost': cost,
    'rarity': rarity,
    'currentHealth': currentHealth,
    'currentAP': currentAP,
  };

  /// Create from JSON
  factory GameCard.fromJson(Map<String, dynamic> json) {
    final card = GameCard(
      id: json['id'] as String,
      name: json['name'] as String,
      damage: json['damage'] as int,
      health: json['health'] as int,
      tick: json['tick'] as int? ?? 3,
      moveSpeed: json['moveSpeed'] as int? ?? 1,
      maxAP: json['maxAP'] as int? ?? 1,
      apPerTurn: json['apPerTurn'] as int? ?? 1,
      attackAPCost: json['attackAPCost'] as int? ?? 1,
      attackRange: json['attackRange'] as int? ?? 1,
      element: json['element'] as String?,
      family: json['family'] as String?,
      abilities: List<String>.from(json['abilities'] ?? []),
      cost: json['cost'] as int? ?? 0,
      rarity: json['rarity'] as int? ?? 1,
    );
    card.currentHealth = json['currentHealth'] as int? ?? json['health'] as int;
    card.currentAP = json['currentAP'] as int? ?? 0;
    return card;
  }

  /// Factory method for creating test cards
  factory GameCard.test({
    String? id,
    String? name,
    int damage = 5,
    int health = 10,
    int tick = 3,
    int moveSpeed = 1,
    int maxAP = 1,
    int apPerTurn = 1,
    int attackAPCost = 1,
    int attackRange = 1,
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
      maxAP: maxAP,
      apPerTurn: apPerTurn,
      attackAPCost: attackAPCost,
      attackRange: attackRange,
      element: element,
      family: family,
      abilities: abilities,
      cost: cost,
      rarity: rarity,
    );
  }
}
