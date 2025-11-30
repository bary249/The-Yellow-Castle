import 'dart:math';
import '../models/card.dart';
import '../models/lane.dart';
import '../models/player.dart';
import '../models/tile.dart';
import '../models/game_board.dart';

/// Simple AI opponent that makes basic decisions
class SimpleAI {
  final Random _random = Random();

  /// Generate tile-based AI placements
  /// NEW RULES:
  /// - Cards can only be staged at base (row 0 for opponent, row 2 for player)
  /// - Only 1 card per lane per turn
  /// - Exception: cards with 'paratrooper' ability can stage at middle
  /// Returns a map of "row,col" to list of cards to play
  Map<String, List<GameCard>> generateTileMoves(
    Player aiPlayer,
    GameBoard board,
    List<Lane> lanes, {
    bool isOpponent = true,
  }) {
    final moves = <String, List<GameCard>>{};
    if (aiPlayer.hand.isEmpty) return moves;

    // Track which lanes already have a card staged this turn
    final lanesUsed = <int>{};

    // Shuffle hand for variety
    final handCopy = [...aiPlayer.hand]..shuffle(_random);

    for (final card in handCopy) {
      // Find an available lane (0, 1, or 2)
      final availableLanes = [
        0,
        1,
        2,
      ].where((col) => !lanesUsed.contains(col)).toList();
      if (availableLanes.isEmpty) break;

      // Occasionally skip a card (~20% chance), but generally be aggressive
      if (_random.nextInt(100) < 20) continue;

      // Pick a random available lane
      final col = availableLanes[_random.nextInt(availableLanes.length)];
      final lane = lanes[col];

      // Determine placement row
      int row;
      if (isOpponent) {
        // Opponent's base is row 0
        row = 0;
        // Check if paratrooper can go to middle
        if (card.abilities.contains('paratrooper')) {
          final middleTile = board.getTile(1, col);
          if (middleTile.owner == TileOwner.opponent) {
            row = 1; // Use middle if owned and has paratrooper
          }
        }
      } else {
        // Player's base is row 2
        row = 2;
        // Check if paratrooper can go to middle
        if (card.abilities.contains('paratrooper')) {
          final middleTile = board.getTile(1, col);
          if (middleTile.owner == TileOwner.player) {
            row = 1; // Use middle if owned and has paratrooper
          }
        }
      }

      // Check if there's room at the target tile
      final tileKey = '$row,$col';
      final existingCards = isOpponent
          ? (row == 0
                ? lane.opponentCards.baseCards.count
                : lane.opponentCards.middleCards.count)
          : (row == 2
                ? lane.playerCards.baseCards.count
                : lane.playerCards.middleCards.count);

      if (existingCards >= 2) continue; // Tile full

      // Add card to moves
      moves[tileKey] = [card];
      lanesUsed.add(col);

      // Remove from hand copy (actual removal happens in match_manager)
      // Just mark this lane as used
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
