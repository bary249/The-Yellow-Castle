import 'package:card_game/models/card.dart';
import 'package:card_game/models/deck.dart';
import 'package:card_game/models/match_state.dart';
import 'package:card_game/services/match_manager.dart';

Deck buildFillerDeck(String playerId, {int size = 20}) {
  final cards = List.generate(
    size,
    (i) => GameCard(
      id: 'filler_${playerId}_$i',
      name: 'Filler',
      damage: 1,
      health: 1,
    ),
  );
  return Deck(id: 'deck_$playerId', name: 'Deck $playerId', cards: cards);
}

MatchManager startHarnessedMatch({
  required String playerId,
  required String opponentId,
  int playerBaseHP = 100,
  int opponentBaseHP = 100,
  String playerName = 'P1',
  String opponentName = 'P2',
}) {
  final mm = MatchManager();
  mm.maxCardsThisTurnOverride = 10;

  mm.startMatchTYC3(
    playerId: playerId,
    playerName: playerName,
    playerDeck: buildFillerDeck(playerId),
    opponentId: opponentId,
    opponentName: opponentName,
    opponentDeck: buildFillerDeck(opponentId),
    opponentIsAI: false,
    firstPlayerIdOverride: playerId,
    playerBaseHP: playerBaseHP,
    opponentBaseHP: opponentBaseHP,
  );

  final match = mm.currentMatch;
  if (match == null) {
    throw StateError('Failed to create match');
  }

  // Make the harness deterministic and easy to control:
  // - clear hands so tests can inject exact cards
  // - ensure it is playerId's turn
  match.player.hand.clear();
  match.opponent.hand.clear();
  match.activePlayerId = playerId;
  match.currentPhase = MatchPhase.playerTurn;
  match.isFirstTurn = false;
  match.cardsPlayedThisTurn = 0;

  return mm;
}

GameCard findCardOnTile(MatchState match, int row, int col, String cardId) {
  final tile = match.board.getTile(row, col);
  return tile.cards.firstWhere((c) => c.id == cardId);
}
