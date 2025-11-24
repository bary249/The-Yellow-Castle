import 'player.dart';
import 'lane.dart';

/// Current phase of the match
enum MatchPhase {
  setup, // Initial setup, drawing hands
  turnPhase, // Players selecting cards (8 seconds)
  combatPhase, // Combat resolution
  drawPhase, // Drawing cards for next turn
  gameOver, // Match ended
}

/// Represents the complete state of an ongoing match
class MatchState {
  final Player player;
  final Player opponent;
  final List<Lane> lanes;

  MatchPhase currentPhase;
  int turnNumber;
  String? winnerId;

  // Turn submission tracking
  bool playerSubmitted = false;
  bool opponentSubmitted = false;

  MatchState({
    required this.player,
    required this.opponent,
    this.currentPhase = MatchPhase.setup,
    this.turnNumber = 0,
  }) : lanes = [
         Lane(position: LanePosition.left),
         Lane(position: LanePosition.center),
         Lane(position: LanePosition.right),
       ];

  /// Get a specific lane by position
  Lane getLane(LanePosition position) {
    return lanes.firstWhere((lane) => lane.position == position);
  }

  /// Check if match is over
  bool get isGameOver => currentPhase == MatchPhase.gameOver;

  /// Check if both players have submitted their moves
  bool get bothPlayersSubmitted => playerSubmitted && opponentSubmitted;

  /// Get the winner
  Player? get winner {
    if (winnerId == null) return null;
    return winnerId == player.id ? player : opponent;
  }

  /// Reset turn submissions
  void resetSubmissions() {
    playerSubmitted = false;
    opponentSubmitted = false;
  }

  /// End the match with a winner
  void endMatch(String winnerPlayerId) {
    winnerId = winnerPlayerId;
    currentPhase = MatchPhase.gameOver;
  }

  /// Check for match end conditions
  void checkGameOver() {
    if (player.isDefeated) {
      endMatch(opponent.id);
    } else if (opponent.isDefeated) {
      endMatch(player.id);
    }
  }

  @override
  String toString() {
    return 'Match: Turn $turnNumber, Phase: $currentPhase\n'
        'Player: ${player.name} (${player.crystalHP} HP)\n'
        'Opponent: ${opponent.name} (${opponent.crystalHP} HP)';
  }
}
