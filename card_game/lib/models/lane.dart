import 'card.dart';

/// Represents one of the 3 battle lanes (left, center, right)
enum LanePosition { left, center, right }

/// Current zone in the lane (player base, middle, enemy base)
enum Zone { playerBase, middle, enemyBase }

/// A stack of cards in a lane (max 2: top and bottom)
class CardStack {
  GameCard? topCard;
  GameCard? bottomCard;
  final bool isPlayerOwned;

  CardStack({this.topCard, this.bottomCard, required this.isPlayerOwned});

  /// Check if stack has any cards
  bool get isEmpty => topCard == null && bottomCard == null;

  /// Check if stack is full (2 cards)
  bool get isFull => topCard != null && bottomCard != null;

  /// Get the active card (top card, or bottom if top is dead)
  GameCard? get activeCard {
    if (topCard != null && topCard!.isAlive) return topCard;
    if (bottomCard != null && bottomCard!.isAlive) return bottomCard;
    return null;
  }

  /// Add a card to the stack
  bool addCard(GameCard card, {bool asTopCard = true}) {
    if (isFull) return false;

    if (topCard == null) {
      topCard = card;
    } else if (bottomCard == null) {
      if (asTopCard) {
        // Move current top to bottom, new card becomes top
        bottomCard = topCard;
        topCard = card;
      } else {
        bottomCard = card;
      }
    } else {
      return false; // Stack full
    }
    return true;
  }

  /// Remove dead cards and promote bottom card if needed
  void cleanup() {
    if (topCard != null && !topCard!.isAlive) {
      topCard = bottomCard;
      bottomCard = null;
    }
    if (topCard != null && !topCard!.isAlive) {
      topCard = null;
    }
  }

  /// Get all alive cards in the stack
  List<GameCard> get aliveCards {
    final cards = <GameCard>[];
    if (topCard != null && topCard!.isAlive) cards.add(topCard!);
    if (bottomCard != null && bottomCard!.isAlive) cards.add(bottomCard!);
    return cards;
  }
}

/// Represents one of the 3 battle lanes
class Lane {
  final LanePosition position;
  Zone currentZone;

  // Card stacks for each side
  final CardStack playerStack;
  final CardStack opponentStack;

  Lane({required this.position, this.currentZone = Zone.middle})
    : playerStack = CardStack(isPlayerOwned: true),
      opponentStack = CardStack(isPlayerOwned: false);

  /// Check if lane has any active cards
  bool get hasActiveCards =>
      playerStack.activeCard != null || opponentStack.activeCard != null;

  /// Get the winning side (null if tie or no winner yet)
  bool? get playerWon {
    final playerAlive = playerStack.activeCard != null;
    final opponentAlive = opponentStack.activeCard != null;

    if (playerAlive && !opponentAlive) return true;
    if (!playerAlive && opponentAlive) return false;
    return null; // Tie or both have cards
  }

  /// Advance zone after combat victory
  /// Returns true if the winner reached enemy base
  bool advanceZone(bool playerWon) {
    if (playerWon) {
      // Player won - advance toward enemy base
      switch (currentZone) {
        case Zone.playerBase:
          currentZone = Zone.middle;
          return false;
        case Zone.middle:
          currentZone = Zone.enemyBase;
          return false;
        case Zone.enemyBase:
          return true; // Reached enemy base - deal crystal damage
      }
    } else {
      // Opponent won - advance toward player base
      switch (currentZone) {
        case Zone.enemyBase:
          currentZone = Zone.middle;
          return false;
        case Zone.middle:
          currentZone = Zone.playerBase;
          return false;
        case Zone.playerBase:
          return true; // Reached player base - deal crystal damage
      }
    }
  }

  /// Get zone display string
  String get zoneDisplay {
    switch (currentZone) {
      case Zone.playerBase:
        return '🛡️ Your Base';
      case Zone.middle:
        return '⚔️ Middle';
      case Zone.enemyBase:
        return '🏰 Enemy Base';
    }
  }

  /// Reset lane for new turn
  void reset() {
    playerStack.topCard = null;
    playerStack.bottomCard = null;
    opponentStack.topCard = null;
    opponentStack.bottomCard = null;
    currentZone = Zone.middle; // Reset to middle
  }
}
