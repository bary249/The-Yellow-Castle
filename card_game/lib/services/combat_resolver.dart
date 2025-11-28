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

  // Per-lane context for zone-based terrain attunement buffs.
  Zone _currentZone = Zone.middle;
  String? _playerBaseElement; // Treated as terrain tag for the player's base
  String?
  _opponentBaseElement; // Treated as terrain tag for the opponent's base
  int _playerDamageBoost =
      0; // Bonus damage for player cards (from hero ability)

  /// Set contextual data for the current lane before processing ticks.
  /// This allows us to apply small buffs when fighting in an attuned base zone.
  void setLaneContext({
    required Zone zone,
    String? playerBaseElement,
    String? opponentBaseElement,
    int playerDamageBoost = 0,
  }) {
    _currentZone = zone;
    _playerBaseElement = playerBaseElement;
    _opponentBaseElement = opponentBaseElement;
    _playerDamageBoost = playerDamageBoost;
  }

  /// Base damage calculator.
  /// Card-vs-card element/terrain matchups are disabled; we start from
  /// the attacker's raw damage and then apply zone-attunement + abilities.
  int _calculateElementalDamage(GameCard attacker, GameCard target) {
    return attacker.damage;
  }

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

  /// Process a single tick in a lane (public for animations)
  void processTickInLane(int tick, Lane lane, {String? customLaneName}) {
    final laneName = customLaneName ?? _getLaneName(lane.position);
    _processTick(tick, lane, laneName);
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

    // Snapshot alive state BEFORE any attacks (for simultaneous combat)
    final playerAliveBeforeTick = playerCard?.isAlive ?? false;
    final opponentAliveBeforeTick = opponentCard?.isAlive ?? false;

    // Simultaneous attacks - both happen even if one dies
    if (playerActs &&
        opponentCard != null &&
        playerAliveBeforeTick &&
        opponentAliveBeforeTick) {
      _performAttack(
        playerCard,
        opponentCard,
        tick,
        lane.playerStack,
        lane.opponentStack,
        laneName,
        true,
        checkAliveBeforeAttack: false, // Skip alive check for simultaneous
      );
    }

    if (opponentActs &&
        playerCard != null &&
        playerAliveBeforeTick &&
        opponentAliveBeforeTick) {
      _performAttack(
        opponentCard,
        playerCard,
        tick,
        lane.opponentStack,
        lane.playerStack,
        laneName,
        false,
        checkAliveBeforeAttack: false, // Skip alive check for simultaneous
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
    CardStack attackerStack,
    CardStack targetStack,
    String laneName,
    bool isPlayerAttacking, {
    bool checkAliveBeforeAttack = true,
  }) {
    // Check alive status only if requested (skip for simultaneous attacks)
    if (checkAliveBeforeAttack && (!attacker.isAlive || !target.isAlive))
      return;

    final attackerSide = isPlayerAttacking ? '🛡️ YOU' : '⚔️ AI';
    int damage = _calculateElementalDamage(attacker, target);
    String note = '';

    void _append(String text) {
      if (note.isEmpty) {
        note = text;
      } else {
        note = '$note$text';
      }
    }

    // 1) Zone attunement buff when fighting in a base zone whose terrain
    // matches the attacker. Either base can grant this if its terrain matches.
    final isInPlayerBase = _currentZone == Zone.playerBase;
    final isInOpponentBase = _currentZone == Zone.enemyBase;

    // Attacker gets +1 if they are in the player base and match its terrain.
    if (isInPlayerBase &&
        _playerBaseElement != null &&
        attacker.element == _playerBaseElement) {
      damage += 1;
      _append(' (+1 terrain buff @ player base)');
    }

    // Attacker also gets +1 if they are in the opponent base and match its terrain.
    if (isInOpponentBase &&
        _opponentBaseElement != null &&
        attacker.element == _opponentBaseElement) {
      damage += 1;
      _append(' (+1 terrain buff @ enemy base)');
    }

    // 2) Hero ability damage boost (player only).
    if (isPlayerAttacking && _playerDamageBoost > 0) {
      damage += _playerDamageBoost;
      _append(' (+$_playerDamageBoost hero boost)');
    }

    // 3) Fury: flat +2 damage for this attacker.
    if (attacker.abilities.contains('fury_2')) {
      damage += 2;
      _append(' (+2 fury)');
    }

    // 3) Stack buff: if a DIFFERENT card in the same stack has stack_buff_damage_2.
    bool _stackHasBuff(CardStack stack) {
      final top = stack.topCard;
      final bottom = stack.bottomCard;
      if (top != null &&
          top != attacker &&
          top.abilities.contains('stack_buff_damage_2')) {
        return true;
      }
      if (bottom != null &&
          bottom != attacker &&
          bottom.abilities.contains('stack_buff_damage_2')) {
        return true;
      }
      return false;
    }

    if (_stackHasBuff(attackerStack)) {
      damage += 2;
      _append(' (+2 stack buff)');
    }

    // 4) Debuff from defending stack: reduce incoming damage by 2 (min 1).
    bool _stackHasDebuff(CardStack stack) {
      final top = stack.topCard;
      final bottom = stack.bottomCard;
      if (top != null &&
          top.abilities.contains('stack_debuff_enemy_damage_2')) {
        return true;
      }
      if (bottom != null &&
          bottom.abilities.contains('stack_debuff_enemy_damage_2')) {
        return true;
      }
      return false;
    }

    if (_stackHasDebuff(targetStack)) {
      final reduced = (damage - 2).clamp(1, 9999);
      if (reduced != damage) {
        damage = reduced;
        _append(' (-2 stack debuff)');
      }
    }

    // 5) Shield on the target: reduce damage by 2 (min 1).
    if (target.abilities.contains('shield_2')) {
      final reduced = (damage - 2).clamp(1, 9999);
      if (reduced != damage) {
        damage = reduced;
        _append(' (-2 shield)');
      }
    }

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
        details:
            '$damage damage dealt | HP: $hpBefore → $hpAfter | $result$note',
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
