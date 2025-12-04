import 'player.dart';
import 'lane.dart';
import 'game_board.dart';
import 'tile.dart';
import 'relic.dart';

/// Current phase of the match
/// TYC3: Updated for turn-based system
enum MatchPhase {
  setup, // Initial setup, drawing hands
  playerTurn, // TYC3: Player's turn (30 seconds)
  opponentTurn, // TYC3: Opponent's turn (30 seconds)
  gameOver, // Match ended
  // LEGACY phases (kept for backward compatibility during migration)
  @Deprecated('Use playerTurn/opponentTurn instead')
  turnPhase, // Legacy: simultaneous turn
  @Deprecated('Removed in TYC3 - combat is immediate')
  combatPhase, // Legacy: tick-based combat
  @Deprecated('Draw happens at turn start in TYC3')
  drawPhase, // Legacy: drawing cards
}

/// Represents the complete state of an ongoing match
/// TYC3: Turn-based system with AP and manual targeting
class MatchState {
  final Player player;
  final Player opponent;

  /// Legacy lane system (kept for backward compatibility during migration).
  final List<Lane> lanes;

  /// New 3×3 tile-based board.
  final GameBoard board;

  MatchPhase currentPhase;
  int turnNumber;
  String? winnerId;

  // ===== TYC3: TURN-BASED TRACKING =====

  /// ID of the player whose turn it currently is
  String? activePlayerId;

  /// When the current turn started (for 30-second timer)
  DateTime? turnStartTime;

  /// Whether this is the very first turn of the match
  /// (first player can only place 1 card on first turn)
  bool isFirstTurn = true;

  /// Number of cards placed this turn (max 2, or 1 on first turn)
  int cardsPlayedThisTurn = 0;

  /// Turn duration in seconds
  static const int turnDurationSeconds = 100;

  // ===== END TYC3 =====

  // LEGACY: Turn submission tracking (kept for backward compatibility)
  @Deprecated('TYC3 uses activePlayerId instead')
  bool playerSubmitted = false;
  @Deprecated('TYC3 uses activePlayerId instead')
  bool opponentSubmitted = false;

  /// Fog of war: tracks which lanes' enemy base terrains are revealed to player.
  /// A lane is revealed once player captures its middle tile.
  final Set<LanePosition> revealedEnemyBaseLanes = {};

  /// Relic manager for handling relics on the battlefield.
  /// Currently places one relic on the center middle tile.
  final RelicManager relicManager = RelicManager();

  MatchState({
    required this.player,
    required this.opponent,
    required this.board,
    this.currentPhase = MatchPhase.setup,
    this.turnNumber = 0,
  }) : lanes = [
         Lane(position: LanePosition.west),
         Lane(position: LanePosition.center),
         Lane(position: LanePosition.east),
       ];

  /// Get a tile from the board.
  Tile getTile(int row, int col) => board.getTile(row, col);

  /// Get a specific lane by position
  Lane getLane(LanePosition position) {
    return lanes.firstWhere((lane) => lane.position == position);
  }

  /// Check if match is over
  bool get isGameOver => currentPhase == MatchPhase.gameOver;

  // ===== TYC3: TURN HELPERS =====

  /// Check if it's the player's turn
  bool get isPlayerTurn => activePlayerId == player.id;

  /// Check if it's the opponent's turn
  bool get isOpponentTurn => activePlayerId == opponent.id;

  /// Get the active player (whose turn it is)
  Player? get activePlayer {
    if (activePlayerId == player.id) return player;
    if (activePlayerId == opponent.id) return opponent;
    return null;
  }

  /// Get remaining seconds in current turn
  int get remainingTurnSeconds {
    if (turnStartTime == null) return turnDurationSeconds;
    final elapsed = DateTime.now().difference(turnStartTime!).inSeconds;
    return (turnDurationSeconds - elapsed).clamp(0, turnDurationSeconds);
  }

  /// Check if turn timer has expired
  bool get isTurnExpired => remainingTurnSeconds <= 0;

  /// Maximum cards that can be placed this turn
  int get maxCardsThisTurn =>
      isFirstTurn && activePlayerId == player.id ? 1 : 2;

  /// Check if more cards can be placed this turn
  bool get canPlaceMoreCards => cardsPlayedThisTurn < maxCardsThisTurn;

  /// Start a new turn for the given player
  void startTurn(String playerId) {
    activePlayerId = playerId;
    turnStartTime = DateTime.now();
    cardsPlayedThisTurn = 0;
    currentPhase = playerId == player.id
        ? MatchPhase.playerTurn
        : MatchPhase.opponentTurn;
  }

  /// End the current turn and switch to the other player
  void endCurrentTurn() {
    if (isFirstTurn) {
      isFirstTurn = false;
    }

    // Switch to other player
    final nextPlayerId = activePlayerId == player.id ? opponent.id : player.id;
    startTurn(nextPlayerId);
    turnNumber++;
  }

  // ===== END TYC3 =====

  /// LEGACY: Check if both players have submitted their moves
  @Deprecated('TYC3 uses turn-based system')
  bool get bothPlayersSubmitted => playerSubmitted && opponentSubmitted;

  /// Get the winner
  Player? get winner {
    if (winnerId == null) return null;
    return winnerId == player.id ? player : opponent;
  }

  /// LEGACY: Reset turn submissions
  @Deprecated('TYC3 uses turn-based system')
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
