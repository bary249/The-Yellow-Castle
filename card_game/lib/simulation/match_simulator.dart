import '../models/deck.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';

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

/// Simulate a single headless match between two decks using SimpleAI on both sides.
Future<MatchOutcome> simulateSingleMatch({
  required Deck deck1,
  required Deck deck2,
  required int seed,
}) async {
  final matchManager = MatchManager();

  // Ensure combat runs automatically without manual tick input
  matchManager.autoProgress = true;
  matchManager.fastMode = true; // No delays in simulation

  // Capture full logs for this simulated match
  final buffer = StringBuffer();
  matchManager.logSink = buffer;

  // Use fresh copies of decks for safety
  final p1Deck = Deck(id: deck1.id, name: deck1.name, cards: deck1.cards);
  final p2Deck = Deck(id: deck2.id, name: deck2.name, cards: deck2.cards);

  matchManager.startMatch(
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

  // Log initial game state before any turns are played
  matchManager.printGameStateSnapshot();

  final ai1 = SimpleAI();
  final ai2 = SimpleAI();

  // Limit maximum turns to avoid infinite games
  const maxTurns = 40;

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
        playerCrystalHp: match.player.crystalHP,
        opponentCrystalHp: match.opponent.crystalHP,
        fullLog: buffer.toString(),
      );
    }

    // SimpleAI for both sides - use tile-based moves to support captured middle tiles
    final p1Moves = ai1.generateTileMoves(
      match.player,
      match.board,
      match.lanes,
      isOpponent: false,
    );
    final p2Moves = ai2.generateTileMoves(
      match.opponent,
      match.board,
      match.lanes,
      isOpponent: true,
    );

    await matchManager.submitPlayerTileMoves(p1Moves);
    await matchManager.submitOpponentTileMoves(p2Moves);

    // After both sides submit, MatchManager resolves combat and advances turn.
    // Capture a snapshot at the end of each full round (post-combat, pre-next turn).
    matchManager.printGameStateSnapshot();
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
