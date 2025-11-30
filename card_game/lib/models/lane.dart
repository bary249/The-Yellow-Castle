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
/// Each position (base, middle, enemyBase) can hold up to 2 cards
class PositionalCards {
  final bool isPlayerOwned;

  // Cards at each position (from this side's perspective)
  final CardStack baseCards; // Own base - staging area
  final CardStack middleCards; // Middle row - neutral zone
  final CardStack enemyBaseCards; // Enemy base - attacking position

  PositionalCards({required this.isPlayerOwned})
    : baseCards = CardStack(isPlayerOwned: isPlayerOwned),
      middleCards = CardStack(isPlayerOwned: isPlayerOwned),
      enemyBaseCards = CardStack(isPlayerOwned: isPlayerOwned);

  /// Get the CardStack at a specific zone
  /// Zone is always from PLAYER's perspective:
  /// - Zone.playerBase = Row 2 = Player's home base
  /// - Zone.middle = Row 1 = Neutral middle zone
  /// - Zone.enemyBase = Row 0 = Opponent's home base
  /// The isPlayer param is ignored - mapping is based on isPlayerOwned
  CardStack getStackAt(Zone zone, bool isPlayer) {
    if (isPlayerOwned) {
      // Player's cards - direct mapping
      switch (zone) {
        case Zone.playerBase:
          return baseCards; // Player cards at player base
        case Zone.middle:
          return middleCards;
        case Zone.enemyBase:
          return enemyBaseCards; // Player cards attacking enemy base
      }
    } else {
      // Opponent's cards - flip the zone mapping
      // Opponent cards at player base = their attack target = enemyBaseCards
      switch (zone) {
        case Zone.playerBase:
          return enemyBaseCards; // Opponent attacking player base
        case Zone.middle:
          return middleCards;
        case Zone.enemyBase:
          return baseCards; // Opponent defending their base
      }
    }
  }

  /// Get active card for combat at the given zone
  GameCard? getActiveCardAt(Zone zone, bool isPlayer) {
    return getStackAt(zone, isPlayer).activeCard;
  }

  /// Get all alive cards at a zone
  List<GameCard> getAliveCardsAt(Zone zone, bool isPlayer) {
    return getStackAt(zone, isPlayer).aliveCards;
  }

  /// Get all alive cards across all positions
  List<GameCard> get allAliveCards {
    return [
      ...baseCards.aliveCards,
      ...middleCards.aliveCards,
      ...enemyBaseCards.aliveCards,
    ];
  }

  /// Check if there are any cards
  bool get hasCards =>
      !baseCards.isEmpty || !middleCards.isEmpty || !enemyBaseCards.isEmpty;

  /// Add card to a specific position
  bool addCardAt(
    Zone zone,
    GameCard card,
    bool isPlayer, {
    bool asTopCard = false,
  }) {
    return getStackAt(zone, isPlayer).addCard(card, asTopCard: asTopCard);
  }

  /// Move a single card forward based on its moveSpeed
  /// Returns the zone the card ended up at, or null if blocked by enemy
  /// The `enemyCards` parameter is used to check for blocking
  Zone? moveCardForward(
    GameCard card,
    Zone currentZone,
    PositionalCards enemyCards,
    bool isPlayer,
  ) {
    final speed = card.moveSpeed;
    if (speed == 0) return currentZone; // Stationary card

    Zone targetZone = currentZone;

    for (int step = 0; step < speed; step++) {
      final nextZone = _getNextZone(targetZone, isPlayer);
      if (nextZone == null) break; // Already at enemy base

      // Move to next zone
      targetZone = nextZone;

      // Check if enemy has cards at this zone - if so, stop here to fight
      final enemyStack = enemyCards.getStackAt(targetZone, !isPlayer);
      if (!enemyStack.isEmpty) {
        // Enemy present - stop here and fight
        break;
      }
    }

    // Move card if it changed zones
    if (targetZone != currentZone) {
      final sourceStack = getStackAt(currentZone, isPlayer);
      final targetStack = getStackAt(targetZone, isPlayer);

      // Remove from source
      if (sourceStack.topCard == card) {
        sourceStack.topCard = sourceStack.bottomCard;
        sourceStack.bottomCard = null;
      } else if (sourceStack.bottomCard == card) {
        sourceStack.bottomCard = null;
      }

      // Add to target
      targetStack.addCard(card, asTopCard: false);
    }

    return targetZone;
  }

  /// Get the next zone in the forward direction
  Zone? _getNextZone(Zone current, bool isPlayer) {
    if (isPlayer) {
      switch (current) {
        case Zone.playerBase:
          return Zone.middle;
        case Zone.middle:
          return Zone.enemyBase;
        case Zone.enemyBase:
          return null; // Already at enemy base
      }
    } else {
      switch (current) {
        case Zone.enemyBase:
          return Zone.middle;
        case Zone.middle:
          return Zone.playerBase;
        case Zone.playerBase:
          return null; // Already at player base (enemy's target)
      }
    }
  }

  /// Cleanup dead cards at all positions
  void cleanup() {
    baseCards.cleanup();
    middleCards.cleanup();
    enemyBaseCards.cleanup();
  }

  /// Clear all cards
  void clear() {
    baseCards.clear();
    middleCards.clear();
    enemyBaseCards.clear();
  }
}

/// Represents one of the 3 battle lanes
class Lane {
  final LanePosition position;
  Zone currentZone; // The zone where combat is happening

  // Positional card tracking for each side
  final PositionalCards playerCards;
  final PositionalCards opponentCards;

  // Combat stacks - returns cards at the current combat zone
  CardStack get playerStack => playerCards.getStackAt(currentZone, true);
  CardStack get opponentStack => opponentCards.getStackAt(currentZone, false);

  Lane({required this.position, this.currentZone = Zone.middle})
    : playerCards = PositionalCards(isPlayerOwned: true),
      opponentCards = PositionalCards(isPlayerOwned: false);

  /// Update currentZone to where combat should happen
  /// Call this after movement and before combat resolution
  void updateCombatZone() {
    final combatZone = findCombatZone();
    if (combatZone != null) {
      currentZone = combatZone;
    }
  }

  /// Check if lane has any cards that could engage in combat
  bool get hasActiveCards {
    // Check all zones for any alive cards
    return playerCards.hasCards || opponentCards.hasCards;
  }

  /// Check if there's active combat (both sides have cards at combat zone)
  bool get hasCombat {
    return !playerStack.isEmpty && !opponentStack.isEmpty;
  }

  /// Get the winning side at current combat zone (null if tie or no winner yet)
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

  /// Move all player cards forward based on their moveSpeed
  /// Returns a map of card -> zone they ended up at
  Map<GameCard, Zone> movePlayerCardsForward() {
    final results = <GameCard, Zone>{};

    // Process cards from front to back (enemyBase, middle, base)
    // to avoid conflicts
    for (final zone in [Zone.enemyBase, Zone.middle, Zone.playerBase]) {
      final stack = playerCards.getStackAt(zone, true);
      final cardsToMove = [...stack.aliveCards];

      for (final card in cardsToMove) {
        final endZone = playerCards.moveCardForward(
          card,
          zone,
          opponentCards,
          true,
        );
        if (endZone != null) {
          results[card] = endZone;
        }
      }
    }

    return results;
  }

  /// Move all opponent cards forward based on their moveSpeed
  /// Returns a map of card -> zone they ended up at
  Map<GameCard, Zone> moveOpponentCardsForward() {
    final results = <GameCard, Zone>{};

    // Process cards from front to back (playerBase, middle, enemyBase)
    for (final zone in [Zone.playerBase, Zone.middle, Zone.enemyBase]) {
      final stack = opponentCards.getStackAt(zone, false);
      final cardsToMove = [...stack.aliveCards];

      for (final card in cardsToMove) {
        final endZone = opponentCards.moveCardForward(
          card,
          zone,
          playerCards,
          false,
        );
        if (endZone != null) {
          results[card] = endZone;
        }
      }
    }

    return results;
  }

  /// Find the combat zone where both sides have cards
  /// Returns null if no combat (cards haven't met yet)
  Zone? findCombatZone() {
    // Check each zone for combat
    for (final zone in Zone.values) {
      final playerStack = playerCards.getStackAt(zone, true);
      final opponentStack = opponentCards.getStackAt(zone, false);

      if (!playerStack.isEmpty && !opponentStack.isEmpty) {
        return zone;
      }
    }
    return null;
  }

  /// Get cards at enemy base that can deal crystal damage (uncontested)
  List<GameCard> getUncontestedPlayerAttackers() {
    final attackers = playerCards.enemyBaseCards.aliveCards;
    final defenders = opponentCards.baseCards.aliveCards;

    if (defenders.isEmpty) {
      return attackers;
    }
    return [];
  }

  /// Get opponent cards at player base that can deal crystal damage (uncontested)
  List<GameCard> getUncontestedOpponentAttackers() {
    final attackers = opponentCards.enemyBaseCards.aliveCards;
    final defenders = playerCards.baseCards.aliveCards;

    if (defenders.isEmpty) {
      return attackers;
    }
    return [];
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
