import '../models/game_board.dart';
import '../models/card.dart';
import '../models/match_state.dart';
import '../models/tile.dart';

/// Represents a snapshot of the game state at the end of a turn
class TurnSnapshot {
  final int turnNumber;
  final String activePlayerId;
  final GameBoard boardState;
  final List<GameCard> playerHand;
  final List<GameCard> opponentHand;
  final int playerCrystal;
  final int opponentCrystal;
  final SyncedCombatResult? combatResult; // Combat that happened this turn

  TurnSnapshot({
    required this.turnNumber,
    required this.activePlayerId,
    required this.boardState,
    required this.playerHand,
    required this.opponentHand,
    required this.playerCrystal,
    required this.opponentCrystal,
    this.combatResult,
  });

  /// Create a deep copy of the current state
  factory TurnSnapshot.fromState({
    required MatchState matchState,
    required List<GameCard> playerHand,
    required List<GameCard> opponentHand,
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
          targetTile.cards.add(card.copy());
        }

        for (final gs in sourceTile.gravestones) {
          targetTile.gravestones.add(
            Gravestone(
              cardName: gs.cardName,
              deathLog: gs.deathLog,
              timestamp: gs.timestamp,
            ),
          );
        }
      }
    }

    return TurnSnapshot(
      turnNumber: matchState.turnNumber,
      activePlayerId: matchState.activePlayerId ?? '',
      boardState: boardCopy,
      playerHand: playerHand.map((c) => c.copy()).toList(),
      opponentHand: opponentHand.map((c) => c.copy()).toList(),
      playerCrystal: matchState.player.crystalHP,
      opponentCrystal: matchState.opponent.crystalHP,
      combatResult: matchState.lastCombatResult,
    );
  }
}
