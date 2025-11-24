import '../models/card.dart';
import '../models/lane.dart';

/// Detailed battle log entry
class BattleLogEntry {
  final int tick;
  final String laneDescription;
  final String action;
  final String details;
  final bool isImportant;

  BattleLogEntry({
    required this.tick,
    required this.laneDescription,
    required this.action,
    required this.details,
    this.isImportant = false,
  });

  String get formattedMessage {
    return '[$laneDescription] Tick $tick: $action - $details';
  }
}

/// Handles combat resolution using the tick system with detailed logging
class CombatResolver {
  final List<BattleLogEntry> combatLog = [];

  /// Resolve combat in a single lane
  /// Returns true if player won the lane
  bool? resolveLane(Lane lane, {String? customLaneName}) {
    final laneName = customLaneName ?? _getLaneName(lane.position);

    // Log lane start
    combatLog.add(
      BattleLogEntry(
        tick: 0,
        laneDescription: laneName,
        action: '⚔️ BATTLE START',
        details: 'Combat begins in $laneName',
        isImportant: true,
      ),
    );

    // Process ticks 1-5
    for (int tick = 1; tick <= 5; tick++) {
      _processTick(tick, lane, laneName);

      // Clean up dead cards after each tick
      lane.playerStack.cleanup();
      lane.opponentStack.cleanup();

      // Check if combat is over (one side eliminated)
      if (lane.playerStack.isEmpty || lane.opponentStack.isEmpty) {
        _logBattleEnd(tick, lane, laneName);
        break;
      }
    }

    // Determine winner
    return lane.playerWon;
  }

  String _getLaneName(LanePosition position) {
    switch (position) {
      case LanePosition.left:
        return 'LEFT LANE';
      case LanePosition.center:
        return 'CENTER LANE';
      case LanePosition.right:
        return 'RIGHT LANE';
    }
  }

  /// Process a single tick
  void _processTick(int tick, Lane lane, String laneName) {
    final playerCard = lane.playerStack.activeCard;
    final opponentCard = lane.opponentStack.activeCard;

    // Log tick start
    if (playerCard != null || opponentCard != null) {
      combatLog.add(
        BattleLogEntry(
          tick: tick,
          laneDescription: laneName,
          action: '⏱️ Tick $tick',
          details: _getTickStatus(playerCard, opponentCard),
        ),
      );
    }

    // Check if cards act on this tick
    final playerActs =
        playerCard != null && _shouldActOnTick(playerCard.tick, tick);
    final opponentActs =
        opponentCard != null && _shouldActOnTick(opponentCard.tick, tick);

    if (!playerActs && !opponentActs) {
      combatLog.add(
        BattleLogEntry(
          tick: tick,
          laneDescription: laneName,
          action: '⏸️ No Actions',
          details: 'No cards act this tick',
        ),
      );
      return;
    }

    // Simultaneous attacks
    if (playerActs && opponentCard != null) {
      _performAttack(
        playerCard,
        opponentCard,
        tick,
        lane.opponentStack,
        laneName,
        true,
      );
    }

    if (opponentActs && playerCard != null) {
      _performAttack(
        opponentCard,
        playerCard,
        tick,
        lane.playerStack,
        laneName,
        false,
      );
    }
  }

  String _getTickStatus(GameCard? playerCard, GameCard? opponentCard) {
    final playerStatus = playerCard != null
        ? 'You: ${playerCard.name} (${playerCard.currentHealth} HP)'
        : 'You: None';
    final opponentStatus = opponentCard != null
        ? 'AI: ${opponentCard.name} (${opponentCard.currentHealth} HP)'
        : 'AI: None';
    return '$playerStatus | $opponentStatus';
  }

  /// Determine if a card acts on a given tick
  bool _shouldActOnTick(int cardTick, int currentTick) {
    if (cardTick == 1) return true; // Acts every tick
    if (cardTick == 2) return currentTick % 2 == 0; // Acts on even ticks
    return cardTick == currentTick; // Acts once at their specific tick
  }

  /// Perform an attack from attacker to target
  void _performAttack(
    GameCard attacker,
    GameCard target,
    int tick,
    CardStack targetStack,
    String laneName,
    bool isPlayerAttacking,
  ) {
    if (!attacker.isAlive || !target.isAlive) return;

    final attackerSide = isPlayerAttacking ? '🛡️ YOU' : '⚔️ AI';
    final damage = attacker.damage;
    final hpBefore = target.currentHealth;

    // Apply damage
    final targetDied = target.takeDamage(damage);
    final hpAfter = target.currentHealth;

    // Log the attack
    final result = targetDied ? '💀 DESTROYED' : '✓ Hit';
    combatLog.add(
      BattleLogEntry(
        tick: tick,
        laneDescription: laneName,
        action: '$attackerSide ${attacker.name} → ${target.name}',
        details: '$damage damage dealt | HP: $hpBefore → $hpAfter | $result',
        isImportant: targetDied,
      ),
    );

    // Handle overflow damage
    if (targetDied) {
      final overflowDamage =
          -target.currentHealth; // Excess damage (negative HP)
      if (overflowDamage > 0 &&
          targetStack.bottomCard != null &&
          targetStack.bottomCard!.isAlive) {
        _applyOverflowDamage(overflowDamage, targetStack, tick, laneName);
      }
    }
  }

  /// Apply overflow damage to the next card in stack
  void _applyOverflowDamage(
    int damage,
    CardStack stack,
    int tick,
    String laneName,
  ) {
    if (stack.bottomCard == null || !stack.bottomCard!.isAlive) return;

    final target = stack.bottomCard!;
    final hpBefore = target.currentHealth;
    final died = target.takeDamage(damage);
    final hpAfter = target.currentHealth;

    combatLog.add(
      BattleLogEntry(
        tick: tick,
        laneDescription: laneName,
        action: '💥 OVERFLOW → ${target.name}',
        details:
            '$damage overflow damage | HP: $hpBefore → $hpAfter | ${died ? "💀 DESTROYED" : "✓ Survived"}',
        isImportant: died,
      ),
    );
  }

  void _logBattleEnd(int tick, Lane lane, String laneName) {
    final playerWon = lane.playerWon;
    String result;

    if (playerWon == true) {
      result = '🏆 VICTORY - You won this lane!';
    } else if (playerWon == false) {
      result = '💔 DEFEAT - AI won this lane';
    } else {
      result = '🤝 DRAW - Both sides eliminated';
    }

    combatLog.add(
      BattleLogEntry(
        tick: tick,
        laneDescription: laneName,
        action: '🏁 BATTLE END',
        details: result,
        isImportant: true,
      ),
    );
  }

  /// Get combat log entries
  List<BattleLogEntry> get logEntries => List.unmodifiable(combatLog);

  /// Clear combat log
  void clearLog() {
    combatLog.clear();
  }
}
