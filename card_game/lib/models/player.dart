import 'card.dart';
import 'deck.dart';

/// Represents a player's state during a match
class Player {
  final String id;
  final String name;
  final bool isHuman; // true for human player, false for AI

  // Match state
  final Deck deck;
  final List<GameCard> hand;
  int crystalHP;
  int gold;

  // Constants
  static const int maxHandSize = 8;
  static const int maxCrystalHP = 100;

  Player({
    required this.id,
    required this.name,
    required this.deck,
    this.isHuman = true,
    this.crystalHP = maxCrystalHP,
    this.gold = 0,
  }) : hand = [];

  /// Check if crystal is destroyed
  bool get isDefeated => crystalHP <= 0;

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

  /// Take damage to crystal
  void takeCrystalDamage(int amount) {
    crystalHP -= amount;
    if (crystalHP < 0) crystalHP = 0;
  }

  /// Earn gold
  void earnGold(int amount) {
    gold += amount;
  }

  /// Get crystal HP percentage for UI
  double get crystalHPPercent => crystalHP / maxCrystalHP;

  @override
  String toString() =>
      '$name (Crystal: $crystalHP HP, Hand: ${hand.length}, Deck: ${deck.remainingCards})';
}
