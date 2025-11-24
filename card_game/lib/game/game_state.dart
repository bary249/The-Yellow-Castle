import 'package:card_game/models/card_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GameState {
  final List<CardModel> playerHand;
  final List<CardModel> computerHand;
  final List<CardModel> tableCards;
  final bool isPlayerTurn;
  final String? winner;
  final String message;

  const GameState({
    this.playerHand = const [],
    this.computerHand = const [],
    this.tableCards = const [],
    this.isPlayerTurn = true,
    this.winner,
    this.message = 'Tap a card to play',
  });

  GameState copyWith({
    List<CardModel>? playerHand,
    List<CardModel>? computerHand,
    List<CardModel>? tableCards,
    bool? isPlayerTurn,
    String? winner,
    String? message,
  }) {
    return GameState(
      playerHand: playerHand ?? this.playerHand,
      computerHand: computerHand ?? this.computerHand,
      tableCards: tableCards ?? this.tableCards,
      isPlayerTurn: isPlayerTurn ?? this.isPlayerTurn,
      winner: winner ?? this.winner,
      message: message ?? this.message,
    );
  }

  bool get isGameOver => winner != null;
}

class GameNotifier extends StateNotifier<GameState> {
  GameNotifier() : super(GameState()) {
    startNewGame();
  }

  void startNewGame() {
    final deck = Deck()..shuffle();
    final cards = deck.cards;

    // Deal 5 cards to each player
    state = state.copyWith(
      playerHand: cards
          .sublist(0, 5)
          .map((card) => card..isFaceUp = true)
          .toList(),
      computerHand: cards
          .sublist(5, 10)
          .map((card) => card..isFaceUp = false)
          .toList(),
      tableCards: [],
      isPlayerTurn: true,
      winner: null,
      message: 'Your turn. Tap a card to play',
    );
  }

  void playCard(CardModel card) {
    if (!state.isPlayerTurn || state.isGameOver) return;

    final updatedPlayerHand = List<CardModel>.from(state.playerHand);
    updatedPlayerHand.removeWhere((c) => c == card);

    final updatedTableCards = List<CardModel>.from(state.tableCards);
    updatedTableCards.add(card);

    state = state.copyWith(
      playerHand: updatedPlayerHand,
      tableCards: updatedTableCards,
      isPlayerTurn: false,
      message: 'Computer is thinking...',
    );

    // Computer's turn
    Future.delayed(const Duration(seconds: 1), () {
      _computerTurn();
    });
  }

  void _computerTurn() {
    if (state.isPlayerTurn || state.isGameOver) return;

    if (state.computerHand.isEmpty) {
      state = state.copyWith(winner: 'Computer', message: 'Computer wins!');
      return;
    }

    // Simple AI: Play a random card
    final randomCard = state.computerHand.first..isFaceUp = true;
    final updatedComputerHand = List<CardModel>.from(state.computerHand)
      ..remove(randomCard);

    final updatedTableCards = List<CardModel>.from(state.tableCards)
      ..add(randomCard);

    state = state.copyWith(
      computerHand: updatedComputerHand,
      tableCards: updatedTableCards,
      isPlayerTurn: true,
      message: 'Your turn. Tap a card to play',
    );

    _checkGameOver();
  }

  void _checkGameOver() {
    if (state.playerHand.isEmpty) {
      state = state.copyWith(winner: 'Player', message: 'You win!');
    } else if (state.computerHand.isEmpty) {
      state = state.copyWith(winner: 'Computer', message: 'Computer wins!');
    }
  }
}

final gameProvider = StateNotifierProvider<GameNotifier, GameState>((ref) {
  return GameNotifier();
});
