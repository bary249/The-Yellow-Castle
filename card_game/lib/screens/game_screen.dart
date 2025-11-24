import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:card_game/widgets/card_widget.dart';
import 'package:card_game/game/game_state.dart';
import 'package:card_game/models/card_model.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final gameNotifier = ref.read(gameProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Game'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => gameNotifier.startNewGame(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Computer's hand (top)
          _buildPlayerHand(
            context,
            'Computer (${gameState.computerHand.length} cards)',
            gameState.computerHand,
            false,
            null,
          ),

          // Table cards
          Expanded(
            child: Center(
              child: gameState.tableCards.isEmpty
                  ? Text(
                      'Play a card to start',
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  : Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: gameState.tableCards.map((card) {
                        return CardWidget(card: card, width: 80, height: 120);
                      }).toList(),
                    ),
            ),
          ),

          // Game message
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              gameState.message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: gameState.isGameOver
                    ? (gameState.winner == 'Player' ? Colors.green : Colors.red)
                    : null,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Player's hand (bottom)
          _buildPlayerHand(
            context,
            'Your Hand (${gameState.playerHand.length} cards)',
            gameState.playerHand,
            gameState.isPlayerTurn && !gameState.isGameOver,
            (card) => gameNotifier.playCard(card),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerHand(
    BuildContext context,
    String title,
    List<CardModel> cards,
    bool isPlayable,
    void Function(CardModel)? onCardTap,
  ) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: cards.isEmpty
                ? Center(
                    child: Text(
                      'No cards left',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: cards.length,
                    itemBuilder: (context, index) {
                      final card = cards[index];
                      return CardWidget(
                        card: card,
                        onTap: isPlayable ? () => onCardTap?.call(card) : null,
                        isPlayable: isPlayable,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
