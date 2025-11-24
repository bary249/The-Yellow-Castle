enum Suit { hearts, diamonds, clubs, spades }

enum Rank {
  ace,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
}

class CardModel {
  final Suit suit;
  final Rank rank;
  bool isFaceUp;

  CardModel({required this.suit, required this.rank, this.isFaceUp = false});

  String get imagePath =>
      'assets/images/cards/${rank.name}_of_${suit.name}.svg';

  @override
  String toString() =>
      '${rank.toString().split('.').last} of ${suit.toString().split('.').last}';

  int get value {
    switch (rank) {
      case Rank.ace:
        return 14;
      case Rank.king:
        return 13;
      case Rank.queen:
        return 12;
      case Rank.jack:
        return 11;
      default:
        return rank.index + 1;
    }
  }
}

class Deck {
  final List<CardModel> _cards = [];

  Deck() {
    // Create a standard deck of 52 cards
    for (var suit in Suit.values) {
      for (var rank in Rank.values) {
        _cards.add(CardModel(suit: suit, rank: rank));
      }
    }
  }

  void shuffle() {
    _cards.shuffle();
  }

  List<CardModel> deal(int count) {
    if (count > _cards.length) {
      throw Exception('Not enough cards in the deck');
    }
    return _cards.sublist(0, count);
  }

  List<CardModel> get cards => List.unmodifiable(_cards);
}
