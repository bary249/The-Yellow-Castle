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

  /// Step-based movement is handled at the Lane level where both sides
  /// are considered together so units can't pass through each other.

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

/// Result of a full step-based movement for a lane.
class LaneMovementResult {
  final Map<GameCard, Zone> playerMoves;
  final Map<GameCard, Zone> opponentMoves;

  LaneMovementResult({required this.playerMoves, required this.opponentMoves});
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

  /// Shared, step-based movement for both sides.
  /// Applies no-crossing and stop-on-shared-tile rules.
  LaneMovementResult moveCardsStepBased() {
    // Snapshot initial positions
    final Map<GameCard, Zone> playerPos = {};
    final Map<GameCard, Zone> opponentPos = {};

    void _collectPositions(
      Map<GameCard, Zone> target,
      PositionalCards source,
      bool isPlayer,
    ) {
      for (final zone in Zone.values) {
        final stack = source.getStackAt(zone, isPlayer);
        for (final card in stack.aliveCards) {
          target[card] = zone;
        }
      }
    }

    _collectPositions(playerPos, playerCards, true);
    _collectPositions(opponentPos, opponentCards, false);

    // Track which cards are locked in combat and cannot move further
    final Set<GameCard> locked = {};

    // PRE-LOCK: Any cards that already share a tile at the start of
    // movement (same Zone for both sides) are immediately locked and
    // will not advance this turn. They must resolve combat where they
    // are instead of walking past each other.
    //
    // Exception: cards with 'stealth_pass' in the middle can slip out
    // and are not movement-locked by sharing the middle tile.
    for (final zone in Zone.values) {
      final playersHere = playerPos.keys
          .where((card) => playerPos[card] == zone)
          .toList();
      final opponentsHere = opponentPos.keys
          .where((card) => opponentPos[card] == zone)
          .toList();
      if (playersHere.isNotEmpty && opponentsHere.isNotEmpty) {
        for (final card in playersHere) {
          final isStealthMiddle =
              zone == Zone.middle && card.abilities.contains('stealth_pass');
          if (!isStealthMiddle) {
            locked.add(card);
          }
        }
        for (final card in opponentsHere) {
          final isStealthMiddle =
              zone == Zone.middle && card.abilities.contains('stealth_pass');
          if (!isStealthMiddle) {
            locked.add(card);
          }
        }
      }
    }

    // Local helper: get the next zone in the forward direction for a side
    Zone? _nextZone(Zone current, bool isPlayer) {
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

    // Helper: run a single movement step
    void _runStep(int stepIndex) {
      // Build occupancy at start of step
      final Map<Zone, List<GameCard>> playerAt = {
        for (final z in Zone.values) z: [],
      };
      final Map<Zone, List<GameCard>> opponentAt = {
        for (final z in Zone.values) z: [],
      };

      playerPos.forEach((card, zone) {
        playerAt[zone]!.add(card);
      });
      opponentPos.forEach((card, zone) {
        opponentAt[zone]!.add(card);
      });

      // Compute intents
      final Map<GameCard, Zone> intended = {};

      void _computeIntentsForSide(
        Map<GameCard, Zone> positions,
        Map<Zone, List<GameCard>> enemyAt,
        bool isPlayer,
      ) {
        positions.forEach((card, zone) {
          if (locked.contains(card)) {
            intended[card] = zone;
            return;
          }

          // Remaining speed: if this step exceeds moveSpeed, stay
          if (stepIndex > card.moveSpeed || card.moveSpeed == 0) {
            intended[card] = zone;
            return;
          }

          final next = _nextZone(zone, isPlayer);
          if (next == null) {
            intended[card] = zone;
            return;
          }

          // Block movement into occupied tiles, EXCEPT bases:
          // - You may move into an occupied enemyBase (to contest it).
          // - Opponent may move into an occupied playerBase.
          final isEnteringEnemyBase = isPlayer && next == Zone.enemyBase;
          final isEnteringPlayerBase = !isPlayer && next == Zone.playerBase;
          final hasStealthPass = card.abilities.contains('stealth_pass');
          final ignoresMiddleBlock = hasStealthPass && next == Zone.middle;
          if (enemyAt[next]!.isNotEmpty &&
              !(isEnteringEnemyBase || isEnteringPlayerBase) &&
              !ignoresMiddleBlock) {
            intended[card] = zone;
            return;
          }

          intended[card] = next;
        });
      }

      _computeIntentsForSide(playerPos, opponentAt, true);
      _computeIntentsForSide(opponentPos, playerAt, false);

      // Handle crossing: playerBase<->middle and middle<->enemyBase
      void _resolveCrossing(Zone a, Zone b) {
        // Players moving a->b, opponents moving b->a
        final crossingPlayers = playerPos.keys.where((card) {
          final from = playerPos[card]!;
          final to = intended[card] ?? from;
          return from == a && to == b;
        }).toList();

        final crossingOpponents = opponentPos.keys.where((card) {
          final from = opponentPos[card]!;
          final to = intended[card] ?? from;
          return from == b && to == a;
        }).toList();

        if (crossingPlayers.isNotEmpty && crossingOpponents.isNotEmpty) {
          // Meeting tile is always the middle between a and b (which is b if a==playerBase)
          final meetZone = Zone.middle;
          for (final card in crossingPlayers) {
            intended[card] = meetZone;
          }
          for (final card in crossingOpponents) {
            intended[card] = meetZone;
          }
        }
      }

      _resolveCrossing(Zone.playerBase, Zone.middle);
      _resolveCrossing(Zone.middle, Zone.enemyBase);

      // Special edge case: both sides start in middle and try to move
      // outward to opposite bases in the same step.
      // They should NOT pass through each other; instead, they both
      // remain in middle and are locked in combat there.
      final middlePlayersOut = playerPos.keys.where((card) {
        final from = playerPos[card]!;
        final to = intended[card] ?? from;
        return from == Zone.middle && to == Zone.enemyBase;
      }).toList();

      final middleOpponentsOut = opponentPos.keys.where((card) {
        final from = opponentPos[card]!;
        final to = intended[card] ?? from;
        return from == Zone.middle && to == Zone.playerBase;
      }).toList();

      if (middlePlayersOut.isNotEmpty && middleOpponentsOut.isNotEmpty) {
        for (final card in middlePlayersOut) {
          intended[card] = Zone.middle;
        }
        for (final card in middleOpponentsOut) {
          intended[card] = Zone.middle;
        }
      }

      // Apply intents and lock any tiles with both sides present
      final Map<Zone, List<GameCard>> newPlayerAt = {
        for (final z in Zone.values) z: [],
      };
      final Map<Zone, List<GameCard>> newOpponentAt = {
        for (final z in Zone.values) z: [],
      };

      playerPos.forEach((card, _) {
        final z = intended[card] ?? playerPos[card]!;
        playerPos[card] = z;
        newPlayerAt[z]!.add(card);
      });
      opponentPos.forEach((card, _) {
        final z = intended[card] ?? opponentPos[card]!;
        opponentPos[card] = z;
        newOpponentAt[z]!.add(card);
      });

      // Lock any cards sharing a tile with enemies
      // Stealth units ('stealth_pass') in the middle are not movement-locked
      // here so they can continue slipping through in later steps, but they
      // are still present for combat resolution once movement is done.
      for (final z in Zone.values) {
        if (newPlayerAt[z]!.isNotEmpty && newOpponentAt[z]!.isNotEmpty) {
          for (final card in newPlayerAt[z]!) {
            final isStealthMiddle =
                z == Zone.middle && card.abilities.contains('stealth_pass');
            if (!isStealthMiddle) {
              locked.add(card);
            }
          }
          for (final card in newOpponentAt[z]!) {
            final isStealthMiddle =
                z == Zone.middle && card.abilities.contains('stealth_pass');
            if (!isStealthMiddle) {
              locked.add(card);
            }
          }
        }
      }
    }

    // Run up to 2 steps (max moveSpeed is 2)
    for (int step = 1; step <= 2; step++) {
      _runStep(step);
    }

    // Build movement result maps (card -> final zone)
    final Map<GameCard, Zone> playerMoves = {};
    final Map<GameCard, Zone> opponentMoves = {};

    // Clear stacks and repopulate from final positions
    playerCards.clear();
    opponentCards.clear();

    playerPos.forEach((card, zone) {
      playerCards.addCardAt(zone, card, true, asTopCard: false);
      playerMoves[card] = zone;
    });
    opponentPos.forEach((card, zone) {
      opponentCards.addCardAt(zone, card, false, asTopCard: false);
      opponentMoves[card] = zone;
    });

    return LaneMovementResult(
      playerMoves: playerMoves,
      opponentMoves: opponentMoves,
    );
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
