import 'card.dart';

/// Represents one of the 3 battle lanes (west, center, east)
enum LanePosition { west, center, east }

/// Current zone in the lane (player base, middle, enemy base)
enum Zone { playerBase, middle, enemyBase }

/// A stack of cards at a specific position (max 2: top and bottom)
class CardStack {
  GameCard? topCard;
  GameCard? bottomCard;
  final bool isPlayerOwned;

  CardStack({this.topCard, this.bottomCard, required this.isPlayerOwned});

  /// Check if stack has any cards
  bool get isEmpty => topCard == null && bottomCard == null;

  /// Check if stack is full (2 cards)
  bool get isFull => topCard != null && bottomCard != null;

  /// Get card count
  int get count {
    int c = 0;
    if (topCard != null) c++;
    if (bottomCard != null) c++;
    return c;
  }

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
    // First, clear any dead bottom card
    if (bottomCard != null && !bottomCard!.isAlive) {
      bottomCard = null;
    }

    // If top is dead, promote bottom to top
    if (topCard != null && !topCard!.isAlive) {
      topCard = bottomCard;
      bottomCard = null;
    }

    // Check again if new top is dead
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

  /// Clear all cards
  void clear() {
    topCard = null;
    bottomCard = null;
  }

  /// Transfer all cards to another stack (for advancement)
  void transferTo(CardStack target) {
    if (topCard != null) {
      target.addCard(topCard!, asTopCard: true);
      topCard = null;
    }
    if (bottomCard != null) {
      target.addCard(bottomCard!, asTopCard: false);
      bottomCard = null;
    }
  }
}

/// Tracks cards at different positions for one side (player or opponent)
/// Each position (base, middle) can hold up to 2 cards
class PositionalCards {
  final bool isPlayerOwned;

  // Cards at each position
  final CardStack baseCards; // Player's base (row 2) or Opponent's base (row 0)
  final CardStack middleCards; // Middle row (row 1)

  PositionalCards({required this.isPlayerOwned})
    : baseCards = CardStack(isPlayerOwned: isPlayerOwned),
      middleCards = CardStack(isPlayerOwned: isPlayerOwned);

  /// Get active card for combat at the given zone
  GameCard? getActiveCardAt(Zone zone, bool isPlayer) {
    if (isPlayer) {
      // Player's perspective: playerBase = their base
      switch (zone) {
        case Zone.playerBase:
          return baseCards.activeCard;
        case Zone.middle:
          return middleCards.activeCard;
        case Zone.enemyBase:
          return middleCards.activeCard; // Player attacks from middle
      }
    } else {
      // Opponent's perspective: enemyBase = their base
      switch (zone) {
        case Zone.enemyBase:
          return baseCards.activeCard;
        case Zone.middle:
          return middleCards.activeCard;
        case Zone.playerBase:
          return middleCards.activeCard; // Opponent attacks from middle
      }
    }
  }

  /// Get all alive cards at a zone
  List<GameCard> getAliveCardsAt(Zone zone, bool isPlayer) {
    if (isPlayer) {
      switch (zone) {
        case Zone.playerBase:
          return baseCards.aliveCards;
        case Zone.middle:
        case Zone.enemyBase:
          return middleCards.aliveCards;
      }
    } else {
      switch (zone) {
        case Zone.enemyBase:
          return baseCards.aliveCards;
        case Zone.middle:
        case Zone.playerBase:
          return middleCards.aliveCards;
      }
    }
  }

  /// Get all alive cards across all positions
  List<GameCard> get allAliveCards {
    return [...baseCards.aliveCards, ...middleCards.aliveCards];
  }

  /// Check if there are any cards
  bool get hasCards => !baseCards.isEmpty || !middleCards.isEmpty;

  /// Add card to a specific position
  bool addCardAt(
    Zone zone,
    GameCard card,
    bool isPlayer, {
    bool asTopCard = false,
  }) {
    if (isPlayer) {
      switch (zone) {
        case Zone.playerBase:
          return baseCards.addCard(card, asTopCard: asTopCard);
        case Zone.middle:
        case Zone.enemyBase:
          return middleCards.addCard(card, asTopCard: asTopCard);
      }
    } else {
      switch (zone) {
        case Zone.enemyBase:
          return baseCards.addCard(card, asTopCard: asTopCard);
        case Zone.middle:
        case Zone.playerBase:
          return middleCards.addCard(card, asTopCard: asTopCard);
      }
    }
  }

  /// Advance cards from base to middle (if middle has room)
  /// Returns number of cards advanced
  int advanceFromBase() {
    int advanced = 0;

    // Move top card first (survivor priority)
    if (baseCards.topCard != null && !middleCards.isFull) {
      middleCards.addCard(baseCards.topCard!, asTopCard: false);
      baseCards.topCard = null;
      advanced++;
    }

    // Move bottom card if room
    if (baseCards.bottomCard != null && !middleCards.isFull) {
      middleCards.addCard(baseCards.bottomCard!, asTopCard: false);
      baseCards.bottomCard = null;
      advanced++;
    }

    return advanced;
  }

  /// Cleanup dead cards at all positions
  void cleanup() {
    baseCards.cleanup();
    middleCards.cleanup();
  }

  /// Clear all cards
  void clear() {
    baseCards.clear();
    middleCards.clear();
  }
}

/// Represents one of the 3 battle lanes
class Lane {
  final LanePosition position;
  Zone currentZone;

  // Positional card tracking for each side
  final PositionalCards playerCards;
  final PositionalCards opponentCards;

  // Legacy CardStack references for combat compatibility
  // These are now aliases to middleCards for combat system
  CardStack get playerStack => playerCards.middleCards;
  CardStack get opponentStack => opponentCards.middleCards;

  Lane({required this.position, this.currentZone = Zone.middle})
    : playerCards = PositionalCards(isPlayerOwned: true),
      opponentCards = PositionalCards(isPlayerOwned: false);

  /// Check if lane has any active cards at current zone
  bool get hasActiveCards {
    final playerActive =
        playerCards.getActiveCardAt(currentZone, true) != null ||
        playerCards.baseCards.activeCard != null;
    final opponentActive =
        opponentCards.getActiveCardAt(currentZone, false) != null ||
        opponentCards.baseCards.activeCard != null;
    return playerActive || opponentActive;
  }

  /// Get the winning side (null if tie or no winner yet)
  bool? get playerWon {
    // Check middle cards (where combat happens)
    final playerAlive = playerCards.middleCards.activeCard != null;
    final opponentAlive = opponentCards.middleCards.activeCard != null;

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

  /// Retreat zone (for uncontested attacks - hit and return)
  /// Used when attackers reach enemy base with no defenders
  void retreatZone(bool playerAttacking) {
    if (playerAttacking) {
      // Player's survivors return from enemy base to middle
      if (currentZone == Zone.enemyBase) {
        currentZone = Zone.middle;
      }
    } else {
      // Opponent's survivors return from player base to middle
      if (currentZone == Zone.playerBase) {
        currentZone = Zone.middle;
      }
    }
  }

  /// Advance cards from base to middle for the winning side
  /// Call this after combat to move reinforcements forward
  int advancePlayerCards() {
    return playerCards.advanceFromBase();
  }

  int advanceOpponentCards() {
    return opponentCards.advanceFromBase();
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

  /// Reset lane for new turn (clears dead cards but preserves zone and survivors)
  void cleanup() {
    playerCards.cleanup();
    opponentCards.cleanup();
  }

  /// Full reset (for new match)
  void reset() {
    playerCards.clear();
    opponentCards.clear();
    currentZone = Zone.middle;
  }
}
