import 'dart:math';
import 'card.dart';
import '../data/card_library.dart';

/// Represents a player's deck of 25 cards
class Deck {
  final String id;
  final String name;
  final List<GameCard> _cards;

  Deck({required this.id, required this.name, required List<GameCard> cards})
    : _cards = cards.map((c) => c.copy()).toList() {
    assert(cards.length == 25, 'Deck must have exactly 25 cards');
  }

  /// Get remaining cards in deck
  List<GameCard> get cards => List.unmodifiable(_cards);

  /// How many cards left in deck
  int get remainingCards => _cards.length;

  /// Check if deck is empty
  bool get isEmpty => _cards.isEmpty;

  /// Shuffle the deck
  void shuffle() {
    _cards.shuffle(Random());
  }

  /// Draw a single card from the top
  GameCard? drawCard() {
    if (_cards.isEmpty) return null;
    return _cards.removeAt(0);
  }

  /// Draw multiple cards
  List<GameCard> drawCards(int count) {
    final drawnCards = <GameCard>[];
    for (int i = 0; i < count && _cards.isNotEmpty; i++) {
      final card = drawCard();
      if (card != null) drawnCards.add(card);
    }
    return drawnCards;
  }

  /// Reset deck to original state (for new match)
  void reset(List<GameCard> originalCards) {
    _cards.clear();
    _cards.addAll(originalCards.map((c) => c.copy()));
  }

  /// Create a basic starter deck for testing
  factory Deck.starter({String? playerId}) {
    final cards = buildStarterCardPool();
    return Deck(
      id: 'starter_${playerId ?? "default"}',
      name: 'Elemental Starter Deck',
      cards: cards,
    );
  }
}
