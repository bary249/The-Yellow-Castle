import 'dart:math';
import '../models/card.dart';
import '../models/lane.dart';
import '../models/player.dart';

/// Simple AI opponent that makes basic decisions
class SimpleAI {
  final Random _random = Random();

  /// Generate AI card placements for the turn
  /// Returns a map of lane positions to list of cards to play
  Map<LanePosition, List<GameCard>> generateMoves(Player aiPlayer) {
    final moves = <LanePosition, List<GameCard>>{};

    if (aiPlayer.hand.isEmpty) return moves;

    // Simple strategy: randomly place 1-2 cards per lane
    final lanes = [LanePosition.left, LanePosition.center, LanePosition.right];

    // Shuffle lanes for variety
    lanes.shuffle(_random);

    // Try to place cards in each lane (max 2 per lane)
    for (final lane in lanes) {
      if (aiPlayer.hand.isEmpty) break;

      // Decide how many cards to play in this lane (0-2)
      final cardsToPlay = _random.nextInt(3); // 0, 1, or 2

      if (cardsToPlay == 0) continue;

      final laneCards = <GameCard>[];

      for (int i = 0; i < cardsToPlay && aiPlayer.hand.isNotEmpty; i++) {
        // Simple strategy: pick random card from hand
        final card = _pickRandomCard(aiPlayer.hand);
        if (card != null) {
          laneCards.add(card);
        }
      }

      if (laneCards.isNotEmpty) {
        moves[lane] = laneCards;
      }
    }

    return moves;
  }

  /// Pick a random card from the list
  GameCard? _pickRandomCard(List<GameCard> cards) {
    if (cards.isEmpty) return null;
    return cards[_random.nextInt(cards.length)];
  }

  /// More advanced: pick card based on simple heuristics
  GameCard? _pickBestCard(List<GameCard> cards) {
    if (cards.isEmpty) return null;

    // Prefer cards with good damage-to-tick ratio
    cards.sort((a, b) {
      final aValue = a.damage / a.tick;
      final bValue = b.damage / b.tick;
      return bValue.compareTo(aValue);
    });

    return cards.first;
  }
}
