import 'dart:math';
import '../models/card.dart';
import '../models/lane.dart';
import '../models/player.dart';
import '../models/tile.dart';
import '../models/game_board.dart';

/// Simple AI opponent that makes basic decisions
class SimpleAI {
  final Random _random = Random();

  /// Generate tile-based AI placements (supports middle tiles if captured)
  /// Returns a map of "row,col" to list of cards to play
  /// For opponent AI: row 0 = their base, row 1 = middle (if captured)
  Map<String, List<GameCard>> generateTileMoves(
    Player aiPlayer,
    GameBoard board,
    List<Lane> lanes, {
    bool isOpponent = true,
  }) {
    final moves = <String, List<GameCard>>{};
    if (aiPlayer.hand.isEmpty) return moves;

    // Collect all tiles the AI can place on
    final availableTiles = <String, int>{}; // "row,col" -> available slots

    for (int col = 0; col < 3; col++) {
      final lane = lanes[col];

      if (isOpponent) {
        // Opponent's base is row 0 (always available)
        final baseCards = lane.opponentCards.baseCards;
        final baseSlots = 2 - baseCards.count;
        if (baseSlots > 0) {
          availableTiles['0,$col'] = baseSlots;
        }

        // Check if opponent owns middle tile (row 1)
        final middleTile = board.getTile(1, col);
        if (middleTile.owner == TileOwner.opponent) {
          final middleCards = lane.opponentCards.middleCards;
          final middleSlots = 2 - middleCards.count;
          if (middleSlots > 0) {
            availableTiles['1,$col'] = middleSlots;
          }
        }
      } else {
        // Player's base is row 2 (always available)
        final baseCards = lane.playerCards.baseCards;
        final baseSlots = 2 - baseCards.count;
        if (baseSlots > 0) {
          availableTiles['2,$col'] = baseSlots;
        }

        // Check if player owns middle tile (row 1)
        final middleTile = board.getTile(1, col);
        if (middleTile.owner == TileOwner.player) {
          final middleCards = lane.playerCards.middleCards;
          final middleSlots = 2 - middleCards.count;
          if (middleSlots > 0) {
            availableTiles['1,$col'] = middleSlots;
          }
        }
      }
    }

    if (availableTiles.isEmpty) return moves;

    // Shuffle tile keys for variety
    final tileKeys = availableTiles.keys.toList()..shuffle(_random);

    // Distribute cards across available tiles
    for (final tileKey in tileKeys) {
      if (aiPlayer.hand.isEmpty) break;

      final slots = availableTiles[tileKey]!;
      final cardsToPlay = _random.nextInt(slots + 1); // 0 to slots

      if (cardsToPlay == 0) continue;

      final tileCards = <GameCard>[];
      for (int i = 0; i < cardsToPlay && aiPlayer.hand.isNotEmpty; i++) {
        final card = _pickRandomCard(aiPlayer.hand);
        if (card != null) {
          tileCards.add(card);
        }
      }

      if (tileCards.isNotEmpty) {
        moves[tileKey] = tileCards;
      }
    }

    return moves;
  }

  /// Legacy: Generate AI card placements for the turn (lane-based, base only)
  /// Returns a map of lane positions to list of cards to play
  Map<LanePosition, List<GameCard>> generateMoves(Player aiPlayer) {
    final moves = <LanePosition, List<GameCard>>{};

    if (aiPlayer.hand.isEmpty) return moves;

    // Simple strategy: randomly place 1-2 cards per lane
    final lanes = [LanePosition.west, LanePosition.center, LanePosition.east];

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
