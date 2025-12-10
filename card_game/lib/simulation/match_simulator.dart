import '../models/deck.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart'; // Import SimpleAI

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
    final buffer = StringBuffer();
    buffer.writeln('=== Simulation Report ===');
    buffer.writeln('Total Games: $games');
    buffer.writeln(
      'Deck 1 Wins: $deck1Wins (${(deck1Wins / games * 100).toStringAsFixed(1)}%)',
    );
    buffer.writeln(
      'Deck 2 Wins: $deck2Wins (${(deck2Wins / games * 100).toStringAsFixed(1)}%)',
    );
    buffer.writeln(
      'Draws: $draws (${(draws / games * 100).toStringAsFixed(1)}%)',
    );
    buffer.writeln('Average Turns: ${avgTurns.toStringAsFixed(1)}');

    // Calculate average final HP
    int totalP1Hp = 0;
    int totalP2Hp = 0;
    for (final outcome in outcomes) {
      totalP1Hp += outcome.playerCrystalHp;
      totalP2Hp += outcome.opponentCrystalHp;
    }
    final avgP1Hp = games > 0 ? totalP1Hp / games : 0;
    final avgP2Hp = games > 0 ? totalP2Hp / games : 0;

    buffer.writeln('Avg Final HP - P1 (Deck 1): ${avgP1Hp.toStringAsFixed(1)}');
    buffer.writeln('Avg Final HP - P2 (Deck 2): ${avgP2Hp.toStringAsFixed(1)}');

    return buffer.toString();
  }
}

/// Simulate a single headless match between two decks using TYC3 turn-based system.
/// This matches the PvE and PvP modes exactly.
Future<MatchOutcome> simulateSingleMatch({
  required Deck deck1,
  required Deck deck2,
  required int seed,
}) async {
  final matchManager = MatchManager();

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
    // final isPlayer1Turn = matchManager.isPlayerTurn;
    // final currentPlayer = isPlayer1Turn ? match.player : match.opponent;
    // final enemyPlayer = isPlayer1Turn ? match.opponent : match.player;
    // final playerBaseRow = isPlayer1Turn ? 2 : 0;
    // final enemyBaseRow = isPlayer1Turn ? 0 : 2;

    // Execute AI turn for current player
    await SimpleAI().executeTurnTYC3(matchManager, delayMs: 0);

    // End turn
    matchManager.endTurnTYC3();

    // Log state after each turn
    if (match.turnNumber % 10 == 0) {
      matchManager.printGameStateSnapshot();
    }
  }
}

/// Execute a simulated AI turn using TYC3 mechanics

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
