import 'package:flutter/material.dart';
import 'package:card_game/models/card_model.dart';

class CardWidget extends StatelessWidget {
  final CardModel card;
  final VoidCallback? onTap;
  final bool isPlayable;
  final double width;
  final double height;

  const CardWidget({
    Key? key,
    required this.card,
    this.onTap,
    this.isPlayable = true,
    this.width = 100,
    this.height = 150,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isPlayable && onTap != null
              ? Colors.blue[50]
              : Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isPlayable && onTap != null
                ? Colors.blue
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: card.isFaceUp ? _buildFront() : _buildBack(),
      ),
    );
  }

  Widget _buildFront() {
    Color color;
    switch (card.suit) {
      case Suit.hearts:
      case Suit.diamonds:
        color = Colors.red;
        break;
      case Suit.clubs:
      case Suit.spades:
        color = Colors.black;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              _getRankSymbol(card.rank),
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Center(
            child: Text(
              _getSuitSymbol(card.suit),
              style: TextStyle(color: color, fontSize: 32),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Transform.rotate(
              angle: 3.14159, // 180 degrees in radians
              child: Text(
                _getRankSymbol(card.rank),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBack() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue, Colors.blueGrey],
        ),
      ),
    );
  }

  String _getRankSymbol(Rank rank) {
    switch (rank) {
      case Rank.ace:
        return 'A';
      case Rank.king:
        return 'K';
      case Rank.queen:
        return 'Q';
      case Rank.jack:
        return 'J';
      default:
        return (rank.index + 1).toString();
    }
  }

  String _getSuitSymbol(Suit suit) {
    switch (suit) {
      case Suit.hearts:
        return '♥';
      case Suit.diamonds:
        return '♦';
      case Suit.clubs:
        return '♣';
      case Suit.spades:
        return '♠';
    }
  }
}
