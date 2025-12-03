import 'card.dart';
import 'deck.dart';
import 'hero.dart';

/// Represents a player's state during a match
/// TYC3: Base HP system (renamed from crystalHP)
class Player {
  final String id;
  final String name;
  final bool isHuman; // true for human player, false for AI

  // Match state
  final Deck deck;
  final List<GameCard> hand;

  // TYC3: Base HP (renamed from crystalHP for clarity)
  int baseHP;
  int gold;

  /// The hero selected for this match (optional for backward compatibility).
  final GameHero? hero;

  /// Optional elemental attunement for this player's base/crystal.
  /// When set, matching-element cards can receive buffs in that player's base zone.
  /// If a hero is set, this may be derived from the hero's terrain affinities.
  final String? attunedElement;

  // Constants
  static const int maxHandSize = 8;
  static const int maxBaseHP = 100; // TYC3: Increased base HP

  /// LEGACY: Alias for backward compatibility
  @Deprecated('Use baseHP instead')
  int get crystalHP => baseHP;
  @Deprecated('Use baseHP instead')
  set crystalHP(int value) => baseHP = value;
  static const int maxCrystalHP = maxBaseHP; // Legacy alias

  Player({
    required this.id,
    required this.name,
    required this.deck,
    this.isHuman = true,
    int? baseHP,
    this.gold = 0,
    this.attunedElement,
    this.hero,
  }) : hand = [],
       baseHP = baseHP ?? maxBaseHP;

  /// Check if base is destroyed (player loses)
  bool get isDefeated => baseHP <= 0;

  /// Check if hand is full
  bool get isHandFull => hand.length >= maxHandSize;

  /// Draw initial hand (6 cards)
  void drawInitialHand() {
    final cards = deck.drawCards(6);
    hand.addAll(cards);
  }

  /// Draw cards at start of turn (2 cards)
  void drawCards({int count = 2}) {
    if (deck.isEmpty) return;

    final cards = deck.drawCards(count);
    for (final card in cards) {
      if (!isHandFull) {
        hand.add(card);
      }
      // If hand is full, card is discarded
    }
  }

  /// Play a card from hand
  bool playCard(GameCard card) {
    if (!hand.contains(card)) return false;
    hand.remove(card);
    return true;
  }

  /// Take damage to base
  void takeBaseDamage(int amount) {
    baseHP -= amount;
    if (baseHP < 0) baseHP = 0;
  }

  /// LEGACY: Alias for backward compatibility
  @Deprecated('Use takeBaseDamage instead')
  void takeCrystalDamage(int amount) => takeBaseDamage(amount);

  /// Earn gold
  void earnGold(int amount) {
    gold += amount;
  }

  /// Get base HP percentage for UI
  double get baseHPPercent => baseHP / maxBaseHP;

  /// LEGACY: Alias for backward compatibility
  @Deprecated('Use baseHPPercent instead')
  double get crystalHPPercent => baseHPPercent;

  @override
  String toString() =>
      '$name (Base: $baseHP HP, Hand: ${hand.length}, Deck: ${deck.remainingCards})';
}
