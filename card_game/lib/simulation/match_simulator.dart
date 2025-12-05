import 'dart:math';
import '../models/deck.dart';
import '../models/card.dart';
import '../services/match_manager.dart';

class MatchOutcome {
  final String winner; // 'deck1', 'deck2', or 'draw'
  final int turns;
  final int playerCrystalHp;
  final int opponentCrystalHp;
  final String fullLog;

  MatchOutcome({
    required this.winner,
    required this.turns,
    required this.playerCrystalHp,
    required this.opponentCrystalHp,
    required this.fullLog,
  });
}

/// Simulate a single headless match between two decks using TYC3 turn-based system.
/// This matches the PvE and PvP modes exactly.
Future<MatchOutcome> simulateSingleMatch({
  required Deck deck1,
  required Deck deck2,
  required int seed,
}) async {
  final matchManager = MatchManager();
  final random = Random(seed);

  // Fast mode for simulation (no delays)
  matchManager.fastMode = true;

  // Capture full logs for this simulated match
  final buffer = StringBuffer();
  matchManager.logSink = buffer;

  // Use fresh copies of decks for safety
  final p1Deck = Deck(id: deck1.id, name: deck1.name, cards: deck1.cards);
  final p2Deck = Deck(id: deck2.id, name: deck2.name, cards: deck2.cards);

  // Start match with TYC3 turn-based system
  matchManager.startMatchTYC3(
    playerId: 'P1',
    playerName: 'Deck1',
    playerDeck: p1Deck,
    opponentId: 'P2',
    opponentName: 'Deck2',
    opponentDeck: p2Deck,
    opponentIsAI: true,
    playerAttunedElement: 'Lake',
    opponentAttunedElement: 'Desert',
  );

  // Log initial game state
  matchManager.printGameStateSnapshot();

  // Limit maximum turns to avoid infinite games
  const maxTurns = 80; // Higher limit for turn-based (each player gets a turn)

  while (true) {
    final match = matchManager.currentMatch;
    if (match == null) {
      return MatchOutcome(
        winner: 'draw',
        turns: 0,
        playerCrystalHp: 0,
        opponentCrystalHp: 0,
        fullLog: buffer.toString(),
      );
    }

    if (match.isGameOver || match.turnNumber > maxTurns) {
      // Final snapshot at end of match (or max turn cap)
      matchManager.printGameStateSnapshot();
      final winner = match.winner;
      String winnerLabel = 'draw';
      if (winner != null) {
        if (winner.id == match.player.id) {
          winnerLabel = 'deck1';
        } else if (winner.id == match.opponent.id) {
          winnerLabel = 'deck2';
        }
      }

      return MatchOutcome(
        winner: winnerLabel,
        turns: match.turnNumber,
        playerCrystalHp: match.player.baseHP,
        opponentCrystalHp: match.opponent.baseHP,
        fullLog: buffer.toString(),
      );
    }

    // Determine whose turn it is
    final isPlayer1Turn = matchManager.isPlayerTurn;
    final currentPlayer = isPlayer1Turn ? match.player : match.opponent;
    final enemyPlayer = isPlayer1Turn ? match.opponent : match.player;
    final playerBaseRow = isPlayer1Turn ? 2 : 0;
    final enemyBaseRow = isPlayer1Turn ? 0 : 2;

    // Execute AI turn for current player
    await _executeSimulatedTurn(
      matchManager: matchManager,
      match: match,
      currentPlayer: currentPlayer,
      enemyPlayer: enemyPlayer,
      playerBaseRow: playerBaseRow,
      enemyBaseRow: enemyBaseRow,
      random: random,
    );

    // End turn
    matchManager.endTurnTYC3();

    // Log state after each turn
    if (match.turnNumber % 10 == 0) {
      matchManager.printGameStateSnapshot();
    }
  }
}

/// Execute a simulated AI turn using TYC3 mechanics
Future<void> _executeSimulatedTurn({
  required MatchManager matchManager,
  required dynamic match,
  required dynamic currentPlayer,
  required dynamic enemyPlayer,
  required int playerBaseRow,
  required int enemyBaseRow,
  required Random random,
}) async {
  // Phase 1: Place cards from hand
  final maxCards = match.maxCardsThisTurn;
  var cardsPlaced = 0;

  final hand = List<GameCard>.from(currentPlayer.hand);
  hand.shuffle(random);

  for (final card in hand) {
    if (cardsPlaced >= maxCards) break;

    // Try to place on base row first
    for (int col = 0; col < 3; col++) {
      final tile = match.board.getTile(playerBaseRow, col);
      if (tile.cards.length < 2) {
        if (matchManager.placeCardTYC3(card, playerBaseRow, col)) {
          cardsPlaced++;
          break;
        }
      }
    }
  }

  // Phase 2: Move cards forward
  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 3; col++) {
      final tile = match.board.getTile(row, col);
      final cards = tile.cards
          .where((c) => c.isAlive && c.ownerId == currentPlayer.id)
          .toList();

      for (final card in cards) {
        if (!card.canMove()) continue;

        // Determine target row (move toward enemy)
        final targetRow = playerBaseRow == 2 ? row - 1 : row + 1;
        if (targetRow < 0 || targetRow > 2) continue;

        // Check if target tile has enemy cards (don't move into enemy)
        final targetTile = match.board.getTile(targetRow, col);
        final hasEnemyCards = targetTile.cards.any(
          (c) => c.isAlive && c.ownerId == enemyPlayer.id,
        );
        if (hasEnemyCards) continue;

        // Random chance to not move
        if (random.nextDouble() < 0.3) continue;

        matchManager.moveCardTYC3(card, row, col, targetRow, col);
      }
    }
  }

  // Phase 3: Attack with cards
  final attackers = <({GameCard card, int row, int col})>[];
  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 3; col++) {
      final tile = match.board.getTile(row, col);
      for (final card in tile.cards) {
        if (card.isAlive &&
            card.canAttack() &&
            card.ownerId == currentPlayer.id) {
          attackers.add((card: card, row: row, col: col));
        }
      }
    }
  }

  attackers.shuffle(random);

  for (final entry in attackers) {
    final card = entry.card;
    final row = entry.row;
    final col = entry.col;

    if (!card.canAttack()) continue;

    // Try to attack enemy cards
    final targets = matchManager.getValidTargetsTYC3(card, row, col);
    if (targets.isNotEmpty) {
      // Prioritize targets we can kill, then high damage targets
      targets.sort((a, b) {
        final canKillA = a.currentHealth <= card.damage ? 1 : 0;
        final canKillB = b.currentHealth <= card.damage ? 1 : 0;
        if (canKillA != canKillB) return canKillB - canKillA;
        return b.damage - a.damage;
      });

      final target = targets.first;
      // Find target position
      for (int tr = 0; tr < 3; tr++) {
        for (int tc = 0; tc < 3; tc++) {
          final targetTile = match.board.getTile(tr, tc);
          if (targetTile.cards.contains(target)) {
            matchManager.attackCardTYC3(card, target, row, col, tr, tc);
            break;
          }
        }
      }
    }

    // Try to attack enemy base if in range
    if (card.canAttack()) {
      final distanceToBase = (enemyBaseRow - row).abs();
      if (distanceToBase <= card.attackRange) {
        matchManager.attackBaseTYC3(card, row, col);
      }
    }
  }
}

class BatchSimulationReport {
  final int games;
  final int deck1Wins;
  final int deck2Wins;
  final int draws;
  final double avgTurns;
  final List<MatchOutcome> outcomes;

  BatchSimulationReport({
    required this.games,
    required this.deck1Wins,
    required this.deck2Wins,
    required this.draws,
    required this.avgTurns,
    required this.outcomes,
  });

  String toConsoleString() {
    String pct(int value) => games == 0
        ? '0.0%'
        : ((value * 1000 / games).round() / 10).toStringAsFixed(1) + '%';

    return [
      'Simulated $games games (Deck1 vs Deck2)',
      'Deck1 wins: $deck1Wins (${pct(deck1Wins)})',
      'Deck2 wins: $deck2Wins (${pct(deck2Wins)})',
      'Draws: $draws (${pct(draws)})',
      'Average turns: ${avgTurns.toStringAsFixed(2)}',
    ].join('\n');
  }
}

Future<BatchSimulationReport> simulateManyGames({
  required int count,
  required Deck deck1,
  required Deck deck2,
  int baseSeed = 42,
}) async {
  int deck1Wins = 0;
  int deck2Wins = 0;
  int draws = 0;
  int totalTurns = 0;
  final outcomes = <MatchOutcome>[];

  for (int i = 0; i < count; i++) {
    final outcome = await simulateSingleMatch(
      deck1: deck1,
      deck2: deck2,
      seed: baseSeed + i,
    );

    totalTurns += outcome.turns;
    outcomes.add(outcome);

    switch (outcome.winner) {
      case 'deck1':
        deck1Wins++;
        break;
      case 'deck2':
        deck2Wins++;
        break;
      default:
        draws++;
        break;
    }
  }

  final avgTurns = count == 0 ? 0.0 : totalTurns / count;

  return BatchSimulationReport(
    games: count,
    deck1Wins: deck1Wins,
    deck2Wins: deck2Wins,
    draws: draws,
    avgTurns: avgTurns,
    outcomes: outcomes,
  );
}
