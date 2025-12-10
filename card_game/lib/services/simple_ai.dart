import 'dart:math';
import '../models/card.dart';
import '../models/lane.dart';
import '../models/player.dart';
import '../models/tile.dart';
import '../models/game_board.dart';
import '../services/match_manager.dart';
import '../services/combat_resolver.dart';

/// Simple AI opponent that makes basic decisions
class SimpleAI {
  final Random _random = Random();

  /// Execute a full turn for the current active player (AI)
  /// Can be used by both TestMatchScreen (with delays) and MatchSimulator (instant)
  Future<void> executeTurnTYC3(
    MatchManager matchManager, {
    Function(String description)? onAction,
    Function(GameCard attacker, GameCard target, AttackResult result, int col)?
    onCombatResult,
    Function(GameCard attacker, int damage, int col)? onBaseAttack,
    int delayMs = 0,
  }) async {
    final match = matchManager.currentMatch;
    if (match == null) return;

    // Helper to log and wait
    Future<void> logAndWait(String action) async {
      onAction?.call(action);
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    final activePlayer = match.activePlayerId == match.player.id
        ? match.player
        : match.opponent;
    final enemyPlayer = match.activePlayerId == match.player.id
        ? match.opponent
        : match.player;

    // Determine base rows based on who is playing
    // Player: Base at Row 2, Enemy at Row 0
    // Opponent: Base at Row 0, Enemy at Row 2
    // BUT the board coordinates are absolute.
    // Row 0 is "Enemy Base" from player perspective (top).
    // Row 2 is "Player Base" from player perspective (bottom).
    // If activePlayer is opponent (AI), their base is Row 0.
    final isOpponentAI = activePlayer.id == match.opponent.id;
    final baseRow = isOpponentAI ? 0 : 2;
    final enemyBaseRow = isOpponentAI ? 2 : 0;
    final forwardDirection = isOpponentAI ? 1 : -1; // 0->1->2 or 2->1->0

    if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs * 2));

    // 1. PLACE CARDS
    final hand = activePlayer.hand;
    final maxCards = matchManager.maxCardsThisTurn;
    int cardsPlaced = 0;

    // Shuffle hand for variety
    final shuffledHand = hand.toList()..shuffle(_random);

    for (final card in shuffledHand) {
      if (cardsPlaced >= maxCards) break;

      // Smart lane selection logic
      final laneScores = <int, double>{};
      for (int col = 0; col < 3; col++) {
        double score = _random.nextDouble() * 2; // Base randomness

        // Check enemy presence in this lane (middle row)
        final middleTile = match.board.getTile(1, col);
        final enemyCardsInMiddle = middleTile.cards
            .where((c) => c.ownerId == enemyPlayer.id && c.isAlive)
            .length;

        // Contest lanes with enemies
        score += enemyCardsInMiddle * 1.5;

        // Check own presence
        int ownCardsInLane = 0;
        for (int r = 0; r < 3; r++) {
          final t = match.board.getTile(r, col);
          ownCardsInLane += t.cards
              .where((c) => c.ownerId == activePlayer.id && c.isAlive)
              .length;
        }
        score -= ownCardsInLane * 0.5; // Avoid overcrowding

        // Terrain bonus
        final baseTile = match.board.getTile(baseRow, col);
        if (baseTile.terrain != null && card.element == baseTile.terrain) {
          score += 2.0;
        }

        laneScores[col] = score;
      }

      // Sort lanes
      final sortedLanes = laneScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Try to place
      for (final entry in sortedLanes) {
        if (matchManager.placeCardTYC3(card, baseRow, entry.key)) {
          cardsPlaced++;
          await logAndWait('Placed ${card.name} in lane ${entry.key}');
          break;
        }
      }
    }

    // 2. MOVE CARDS
    // Collect movable cards
    final movableCards = <({GameCard card, int row, int col})>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final card in tile.cards) {
          if (card.isAlive &&
              card.canMove() &&
              card.ownerId == activePlayer.id) {
            movableCards.add((card: card, row: row, col: col));
          }
        }
      }
    }
    movableCards.shuffle(_random);

    for (final entry in movableCards) {
      final card = entry.card;
      final row = entry.row;
      final col = entry.col;

      if (!card.canMove()) continue;

      final targetRow = row + forwardDirection;
      if (targetRow < 0 || targetRow > 2) continue;

      // Check if moving is beneficial (don't move into blocked tile without attacking)
      final targetTile = match.board.getTile(targetRow, col);
      final hasEnemyCards = targetTile.cards.any(
        (c) => c.ownerId == enemyPlayer.id && c.isAlive,
      );

      if (hasEnemyCards) continue;

      // Random chance to stay
      if (_random.nextDouble() < 0.2) continue;

      if (matchManager.moveCardTYC3(card, row, col, targetRow, col)) {
        await logAndWait('Moved ${card.name} to row $targetRow');
      }
    }

    // 3. ATTACK
    final attackers = <({GameCard card, int row, int col})>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final card in tile.cards) {
          if (card.isAlive &&
              card.canAttack() &&
              card.ownerId == activePlayer.id) {
            attackers.add((card: card, row: row, col: col));
          }
        }
      }
    }
    attackers.shuffle(_random);

    for (final entry in attackers) {
      final card = entry.card;
      final row = entry.row;
      final col = entry.col;

      if (!card.canAttack()) continue;

      // Valid targets
      final targets = matchManager.getValidTargetsTYC3(card, row, col);
      if (targets.isNotEmpty) {
        targets.sort((a, b) {
          // Prioritize kills
          final killA = a.currentHealth <= card.damage ? 1 : 0;
          final killB = b.currentHealth <= card.damage ? 1 : 0;
          if (killA != killB) return killB - killA;
          // Prioritize high damage threats
          return b.damage - a.damage;
        });

        final target = targets.first;
        // Find target position
        for (int tr = 0; tr < 3; tr++) {
          for (int tc = 0; tc < 3; tc++) {
            final tTile = match.board.getTile(tr, tc);
            if (tTile.cards.contains(target)) {
              final result = matchManager.attackCardTYC3(
                card,
                target,
                row,
                col,
                tr,
                tc,
              );
              if (result != null) {
                // Notify via callback if provided
                if (onCombatResult != null) {
                  await onCombatResult(card, target, result, tc);
                }
                await logAndWait('Attacked ${target.name} (${result.message})');
              }
              break;
            }
          }
        }
      }

      // Attack Base
      if (card.canAttack()) {
        final distToBase = (enemyBaseRow - row).abs();
        if (distToBase <= card.attackRange) {
          final dmg = matchManager.attackBaseTYC3(card, row, col);
          if (dmg > 0) {
            if (onBaseAttack != null) {
              await onBaseAttack(card, dmg, col);
            }
            await logAndWait('Attacked base for $dmg damage');
          }
        }
      }
    }
  }

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
