/// Represents a playing card in the game
/// Phase 1: Simple version without elements or character families
class GameCard {
  final String id;
  final String name;
  final int damage;
  final int health;
  final int tick; // 1-5: determines when the card acts in combat

  // Runtime state
  int currentHealth;

  GameCard({
    required this.id,
    required this.name,
    required this.damage,
    required this.health,
    required this.tick,
  }) : currentHealth = health;

  /// Create a copy of this card (for deck shuffling/dealing)
  GameCard copy() {
    return GameCard(
      id: id,
      name: name,
      damage: damage,
      health: health,
      tick: tick,
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
      '$name (HP: $currentHealth/$health, DMG: $damage, Tick: $tick)';

  /// Factory method for creating test cards
  factory GameCard.test({
    String? id,
    String? name,
    int damage = 5,
    int health = 10,
    int tick = 3,
  }) {
    return GameCard(
      id: id ?? 'card_${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? 'Test Card',
      damage: damage,
      health: health,
      tick: tick,
    );
  }
}
