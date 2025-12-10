import '../models/game_board.dart';
import '../models/match_state.dart';
import '../models/tile.dart';
import '../models/player.dart';
import '../services/combat_resolver.dart';

/// Represents a snapshot of the game state at the end of a turn
class TurnSnapshot {
  final int turnNumber;
  final String activePlayerId;
  final GameBoard boardState;
  final Player playerState;
  final Player opponentState;
  final SyncedCombatResult? combatResult; // Combat that happened this turn
  final List<BattleLogEntry> logs;

  TurnSnapshot({
    required this.turnNumber,
    required this.activePlayerId,
    required this.boardState,
    required this.playerState,
    required this.opponentState,
    this.combatResult,
    this.logs = const [],
  });

  /// Create a deep copy of the current state
  factory TurnSnapshot.fromState({
    required MatchState matchState,
    List<BattleLogEntry>? currentLogs,
  }) {
    // Deep copy the board
    final boardCopy = GameBoard.fromTerrains(matchState.board.toTerrainGrid());

    // Copy cards and gravestones to the new board
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final sourceTile = matchState.board.getTile(r, c);
        final targetTile = boardCopy.getTile(r, c);

        targetTile.owner = sourceTile.owner;

        for (final card in sourceTile.cards) {
          targetTile.cards.add(card.clone());
        }

        for (final gs in sourceTile.gravestones) {
          targetTile.gravestones.add(
            Gravestone(
              cardName: gs.cardName,
              deathLog: gs.deathLog,
              timestamp: gs.timestamp,
              ownerId: gs.ownerId,
              turnCreated: gs.turnCreated,
            ),
          );
        }
      }
    }

    return TurnSnapshot(
      turnNumber: matchState.turnNumber,
      activePlayerId: matchState.activePlayerId ?? '',
      boardState: boardCopy,
      playerState: matchState.player.copy(),
      opponentState: matchState.opponent.copy(),
      combatResult: matchState.lastCombatResult,
      logs: currentLogs != null ? List.from(currentLogs) : [],
    );
  }
}
