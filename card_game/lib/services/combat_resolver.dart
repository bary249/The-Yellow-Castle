import '../models/card.dart';
import '../models/lane.dart';

/// TYC3: Result of a single attack
class AttackResult {
  final bool success;
  final int damageDealt;
  final int retaliationDamage;
  final bool targetDied;
  final bool attackerDied;
  final String message;

  AttackResult({
    required this.success,
    this.damageDealt = 0,
    this.retaliationDamage = 0,
    this.targetDied = false,
    this.attackerDied = false,
    this.message = '',
  });
}

/// Log importance levels
enum LogLevel { verbose, normal, important }

/// Detailed battle log entry
class BattleLogEntry {
  final int tick;
  final String laneDescription;
  final String action;
  final String details;
  final bool isImportant;
  final LogLevel level;

  // Combat details for enhanced UI display
  final int? damageDealt;
  final String? attackerName;
  final String? targetName;
  final int? targetHpBefore;
  final int? targetHpAfter;
  final bool? targetDied;

  BattleLogEntry({
    required this.tick,
    required this.laneDescription,
    required this.action,
    required this.details,
    this.isImportant = false,
    this.level = LogLevel.normal,
    this.damageDealt,
    this.attackerName,
    this.targetName,
    this.targetHpBefore,
    this.targetHpAfter,
    this.targetDied,
  });

  String get formattedMessage {
    return '[$laneDescription] Tick $tick: $action - $details';
  }

  /// Get a detailed combat summary for UI display
  String get combatSummary {
    if (damageDealt != null && attackerName != null && targetName != null) {
      final hpInfo = targetHpAfter != null ? ' (${targetHpAfter} HP left)' : '';
      final deathInfo = targetDied == true ? ' ☠️ DESTROYED!' : '';
      return '$attackerName → $targetName: $damageDealt dmg$hpInfo$deathInfo';
    }
    return action;
  }
}

/// Handles combat resolution using the tick system with detailed logging
class CombatResolver {
  final List<BattleLogEntry> combatLog = [];

  /// Get filtered logs based on minimum level
  List<BattleLogEntry> getFilteredLogs({LogLevel minLevel = LogLevel.normal}) {
    return combatLog.where((log) => log.level.index >= minLevel.index).toList();
  }

  /// Get only important logs (kills, abilities, crystal damage)
  List<BattleLogEntry> get importantLogs =>
      getFilteredLogs(minLevel: LogLevel.important);

  // Per-lane context for combat
  Zone _currentZone = Zone.middle;
  int _playerDamageBoost =
      0; // Bonus damage for player cards (from hero ability)

  // Lane-wide buffs applied at combat start (from inspire, fortify, command, rally)
  int _playerLaneDamageBonus = 0;
  int _playerLaneShieldBonus = 0;
  int _opponentLaneDamageBonus = 0;
  int _opponentLaneShieldBonus = 0;

  // Current tile terrain for terrain attunement buffs
  String? _currentTileTerrain;

  /// Set contextual data for the current lane before processing ticks.
  /// This allows us to apply terrain buffs when card element matches tile terrain.
  void setLaneContext({
    required Zone zone,
    String? tileTerrain,
    int playerDamageBoost = 0,
  }) {
    _currentZone = zone;
    _currentTileTerrain = tileTerrain;
    _playerDamageBoost = playerDamageBoost;
  }

  /// Get current tile terrain for display
  String? get currentTileTerrain => _currentTileTerrain;

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

    // Calculate lane-wide buffs from abilities at combat start
    _calculateLaneBuffs(lane, laneName);

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

    // Reset lane buffs for next lane
    _resetLaneBuffs();

    // Determine winner
    return lane.playerWon;
  }

  /// Public method to calculate lane buffs (for use by MatchManager)
  void calculateLaneBuffsPublic(Lane lane, String laneName) {
    _calculateLaneBuffs(lane, laneName);
  }

  /// Public method to reset lane buffs after combat (for use by MatchManager)
  void resetLaneBuffsPublic() {
    _resetLaneBuffs();
  }

  /// Calculate lane-wide buffs from inspire, fortify, command, rally abilities
  void _calculateLaneBuffs(Lane lane, String laneName) {
    _playerLaneDamageBonus = 0;
    _playerLaneShieldBonus = 0;
    _opponentLaneDamageBonus = 0;
    _opponentLaneShieldBonus = 0;

    // Check player stack for buff abilities
    _applyStackBuffs(lane.playerStack, true, laneName);
    // Check opponent stack for buff abilities
    _applyStackBuffs(lane.opponentStack, false, laneName);
  }

  /// Apply buffs from a stack's cards
  void _applyStackBuffs(CardStack stack, bool isPlayer, String laneName) {
    final cards = [stack.topCard, stack.bottomCard].whereType<GameCard>();

    for (final card in cards) {
      for (final ability in card.abilities) {
        // inspire_X: +X damage to all allies in lane
        if (ability.startsWith('inspire_')) {
          final value = int.tryParse(ability.split('_').last) ?? 0;
          if (isPlayer) {
            _playerLaneDamageBonus += value;
          } else {
            _opponentLaneDamageBonus += value;
          }
          combatLog.add(
            BattleLogEntry(
              tick: 0,
              laneDescription: laneName,
              action: '🎺 ${card.name} INSPIRE',
              details:
                  '+$value damage to all ${isPlayer ? "player" : "AI"} units in lane',
              level: LogLevel.important,
              isImportant: true,
            ),
          );
        }

        // fortify_X: +X shield to all allies in lane
        if (ability.startsWith('fortify_')) {
          final value = int.tryParse(ability.split('_').last) ?? 0;
          if (isPlayer) {
            _playerLaneShieldBonus += value;
          } else {
            _opponentLaneShieldBonus += value;
          }
          combatLog.add(
            BattleLogEntry(
              tick: 0,
              laneDescription: laneName,
              action: '🛡️ ${card.name} FORTIFY',
              details:
                  '+$value shield to all ${isPlayer ? "player" : "AI"} units in lane',
              level: LogLevel.important,
              isImportant: true,
            ),
          );
        }

        // command_X: +X damage AND +X shield to all allies in lane
        if (ability.startsWith('command_')) {
          final value = int.tryParse(ability.split('_').last) ?? 0;
          if (isPlayer) {
            _playerLaneDamageBonus += value;
            _playerLaneShieldBonus += value;
          } else {
            _opponentLaneDamageBonus += value;
            _opponentLaneShieldBonus += value;
          }
          combatLog.add(
            BattleLogEntry(
              tick: 0,
              laneDescription: laneName,
              action: '⭐ ${card.name} COMMAND',
              details:
                  '+$value damage and +$value shield to all ${isPlayer ? "player" : "AI"} units in lane',
              level: LogLevel.important,
              isImportant: true,
            ),
          );
        }

        // rally_X: +X damage to adjacent ally (the other card in stack)
        if (ability.startsWith('rally_')) {
          final value = int.tryParse(ability.split('_').last) ?? 0;
          // Rally only affects the other card in the same stack
          final otherCard = stack.topCard == card
              ? stack.bottomCard
              : stack.topCard;
          if (otherCard != null) {
            if (isPlayer) {
              _playerLaneDamageBonus += value;
            } else {
              _opponentLaneDamageBonus += value;
            }
            combatLog.add(
              BattleLogEntry(
                tick: 0,
                laneDescription: laneName,
                action: '📣 ${card.name} RALLY',
                details: '+$value damage to ${otherCard.name}',
                level: LogLevel.important,
                isImportant: true,
              ),
            );
          }
        }
      }
    }
  }

  /// Reset lane buffs after combat
  void _resetLaneBuffs() {
    _playerLaneDamageBonus = 0;
    _playerLaneShieldBonus = 0;
    _opponentLaneDamageBonus = 0;
    _opponentLaneShieldBonus = 0;
  }

  String _getLaneName(LanePosition position) {
    switch (position) {
      case LanePosition.west:
        return 'WEST LANE';
      case LanePosition.center:
        return 'CENTER LANE';
      case LanePosition.east:
        return 'EAST LANE';
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

    // Also check for ranged attackers in back position
    final playerRangedBack = _getRangedBackCard(lane.playerStack);
    final opponentRangedBack = _getRangedBackCard(lane.opponentStack);

    // Log tick start (verbose - only shown in detailed mode)
    if (playerCard != null || opponentCard != null) {
      combatLog.add(
        BattleLogEntry(
          tick: tick,
          laneDescription: laneName,
          action: '⏱️ Tick $tick',
          details: _getTickStatus(playerCard, opponentCard),
          level: LogLevel.verbose,
        ),
      );
    }

    // Check if cards act on this tick
    final playerActs =
        playerCard != null && _shouldActOnTick(playerCard.tick, tick);
    final opponentActs =
        opponentCard != null && _shouldActOnTick(opponentCard.tick, tick);
    final playerRangedActs =
        playerRangedBack != null &&
        _shouldActOnTick(playerRangedBack.tick, tick);
    final opponentRangedActs =
        opponentRangedBack != null &&
        _shouldActOnTick(opponentRangedBack.tick, tick);

    if (!playerActs &&
        !opponentActs &&
        !playerRangedActs &&
        !opponentRangedActs) {
      combatLog.add(
        BattleLogEntry(
          tick: tick,
          laneDescription: laneName,
          action: '⏸️ No Actions',
          details: 'No cards act this tick',
          level: LogLevel.verbose,
        ),
      );
      return;
    }

    // Snapshot alive state BEFORE any attacks (for simultaneous combat)
    final playerAliveBeforeTick = playerCard?.isAlive ?? false;
    final opponentAliveBeforeTick = opponentCard?.isAlive ?? false;

    // Check for first_strike - these units attack FIRST and can prevent counter-attack
    final playerHasFirstStrike =
        playerCard?.abilities.contains('first_strike') ?? false;
    final opponentHasFirstStrike =
        opponentCard?.abilities.contains('first_strike') ?? false;

    // FIRST STRIKE PHASE: Units with first_strike attack before others
    if (playerActs &&
        playerHasFirstStrike &&
        opponentCard != null &&
        playerAliveBeforeTick &&
        opponentAliveBeforeTick) {
      // Log first strike BEFORE the attack
      combatLog.add(
        BattleLogEntry(
          tick: tick,
          laneDescription: laneName,
          action: '⚡ FIRST STRIKE',
          details: '${playerCard.name} strikes first!',
          level: LogLevel.important,
          isImportant: true,
        ),
      );
      _performAttack(
        playerCard,
        opponentCard,
        tick,
        lane.playerStack,
        lane.opponentStack,
        laneName,
        true,
        checkAliveBeforeAttack: false,
      );
    }

    if (opponentActs &&
        opponentHasFirstStrike &&
        playerCard != null &&
        playerAliveBeforeTick &&
        opponentAliveBeforeTick) {
      // Log first strike BEFORE the attack
      combatLog.add(
        BattleLogEntry(
          tick: tick,
          laneDescription: laneName,
          action: '⚡ FIRST STRIKE',
          details: '${opponentCard.name} strikes first!',
          level: LogLevel.important,
          isImportant: true,
        ),
      );
      _performAttack(
        opponentCard,
        playerCard,
        tick,
        lane.opponentStack,
        lane.playerStack,
        laneName,
        false,
        checkAliveBeforeAttack: false,
      );
    }

    // Re-check alive status after first strike phase
    final playerStillAlive = playerCard?.isAlive ?? false;
    final opponentStillAlive = opponentCard?.isAlive ?? false;

    // NORMAL ATTACK PHASE: Non-first-strike units attack (only if still alive)
    if (playerActs &&
        !playerHasFirstStrike &&
        opponentCard != null &&
        playerStillAlive &&
        opponentStillAlive) {
      _performAttack(
        playerCard,
        opponentCard,
        tick,
        lane.playerStack,
        lane.opponentStack,
        laneName,
        true,
        checkAliveBeforeAttack: false,
      );
    }

    if (opponentActs &&
        !opponentHasFirstStrike &&
        playerCard != null &&
        playerStillAlive &&
        opponentStillAlive) {
      _performAttack(
        opponentCard,
        playerCard,
        tick,
        lane.opponentStack,
        lane.playerStack,
        laneName,
        false,
        checkAliveBeforeAttack: false,
      );
    }

    // RANGED ATTACK PHASE: Back cards with 'ranged' ability also attack
    if (playerRangedActs && opponentCard != null && opponentCard.isAlive) {
      _performAttack(
        playerRangedBack,
        opponentCard,
        tick,
        lane.playerStack,
        lane.opponentStack,
        laneName,
        true,
        checkAliveBeforeAttack: true,
        isRangedAttack: true,
      );
    }

    if (opponentRangedActs && playerCard != null && playerCard.isAlive) {
      _performAttack(
        opponentRangedBack,
        playerCard,
        tick,
        lane.opponentStack,
        lane.playerStack,
        laneName,
        false,
        checkAliveBeforeAttack: true,
        isRangedAttack: true,
      );
    }
  }

  /// Get a back card that has 'ranged' ability and is not the active card
  GameCard? _getRangedBackCard(CardStack stack) {
    final bottom = stack.bottomCard;
    if (bottom != null &&
        bottom.isAlive &&
        bottom.abilities.contains('ranged') &&
        stack.topCard != null &&
        stack.topCard!.isAlive) {
      // Only return if there's a front card (ranged fires from behind)
      return bottom;
    }
    return null;
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
    bool isRangedAttack = false,
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

    // 1) Terrain attunement buff: +1 damage when card element matches tile terrain
    // This applies to ANY tile (base or middle), not just bases
    final tileTerrain = _currentTileTerrain;
    final attackerElement = attacker.element;
    if (tileTerrain != null &&
        attackerElement != null &&
        attackerElement.toLowerCase() == tileTerrain.toLowerCase()) {
      damage += 1;
      _append(' (+1 $tileTerrain terrain)');
    }

    // 2) Hero ability damage boost (player only).
    if (isPlayerAttacking && _playerDamageBoost > 0) {
      damage += _playerDamageBoost;
      _append(' (+$_playerDamageBoost hero boost)');
    }

    // 3) Lane-wide damage bonus from inspire/command/rally abilities
    final laneDamageBonus = isPlayerAttacking
        ? _playerLaneDamageBonus
        : _opponentLaneDamageBonus;
    if (laneDamageBonus > 0) {
      damage += laneDamageBonus;
      _append(' (+$laneDamageBonus lane buff)');
    }

    // 4) Fury abilities: fury_1 = +1, fury_2 = +2
    for (final ability in attacker.abilities) {
      if (ability.startsWith('fury_')) {
        final furyValue = int.tryParse(ability.split('_').last) ?? 0;
        if (furyValue > 0) {
          damage += furyValue;
          _append(' (+$furyValue fury)');
        }
      }
    }

    // 5) Stack buff: if a DIFFERENT card in the same stack has stack_buff_damage_X.
    int _getStackBuffDamage(CardStack stack) {
      int buff = 0;
      final top = stack.topCard;
      final bottom = stack.bottomCard;
      for (final card in [top, bottom].whereType<GameCard>()) {
        if (card != attacker) {
          for (final ability in card.abilities) {
            if (ability.startsWith('stack_buff_damage_')) {
              buff += int.tryParse(ability.split('_').last) ?? 0;
            }
          }
        }
      }
      return buff;
    }

    final stackBuff = _getStackBuffDamage(attackerStack);
    if (stackBuff > 0) {
      damage += stackBuff;
      _append(' (+$stackBuff stack buff)');
    }

    // 6) Debuff from defending stack: stack_debuff_enemy_damage_X
    int _getStackDebuff(CardStack stack) {
      int debuff = 0;
      final top = stack.topCard;
      final bottom = stack.bottomCard;
      for (final card in [top, bottom].whereType<GameCard>()) {
        for (final ability in card.abilities) {
          if (ability.startsWith('stack_debuff_enemy_damage_')) {
            debuff += int.tryParse(ability.split('_').last) ?? 0;
          }
        }
      }
      return debuff;
    }

    final stackDebuff = _getStackDebuff(targetStack);
    if (stackDebuff > 0) {
      final reduced = (damage - stackDebuff).clamp(1, 9999);
      if (reduced != damage) {
        damage = reduced;
        _append(' (-$stackDebuff stack debuff)');
      }
    }

    // 7) Lane-wide shield bonus from fortify/command abilities
    final laneShieldBonus = isPlayerAttacking
        ? _opponentLaneShieldBonus
        : _playerLaneShieldBonus;
    if (laneShieldBonus > 0) {
      final reduced = (damage - laneShieldBonus).clamp(1, 9999);
      if (reduced != damage) {
        damage = reduced;
        _append(' (-$laneShieldBonus lane shield)');
      }
    }

    // 8) Shield abilities on target: shield_1 = -1, shield_2 = -2, shield_3 = -3
    for (final ability in target.abilities) {
      if (ability.startsWith('shield_')) {
        final shieldValue = int.tryParse(ability.split('_').last) ?? 0;
        if (shieldValue > 0) {
          final reduced = (damage - shieldValue).clamp(1, 9999);
          if (reduced != damage) {
            damage = reduced;
            _append(' (-$shieldValue shield)');
          }
        }
      }
    }

    final hpBefore = target.currentHealth;

    // Apply damage
    final targetDied = target.takeDamage(damage);
    final hpAfter = target.currentHealth;

    // Log the attack with detailed combat info
    final result = targetDied ? '💀 DESTROYED' : '✓ Hit';
    final rangedLabel = isRangedAttack ? '🏹 RANGED ' : '';
    // Kills and ability triggers are important, regular hits are normal
    final hasAbilityNote = note.isNotEmpty;
    combatLog.add(
      BattleLogEntry(
        tick: tick,
        laneDescription: laneName,
        action: '$rangedLabel$attackerSide ${attacker.name} → ${target.name}',
        details:
            '$damage damage dealt | HP: $hpBefore → $hpAfter | $result$note',
        isImportant: targetDied || hasAbilityNote,
        level: targetDied
            ? LogLevel.important
            : (hasAbilityNote ? LogLevel.normal : LogLevel.verbose),
        // Enhanced combat details for UI
        damageDealt: damage,
        attackerName: attacker.name,
        targetName: target.name,
        targetHpBefore: hpBefore,
        targetHpAfter: hpAfter,
        targetDied: targetDied,
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

  // ===========================================================================
  // TYC3: SINGLE-ATTACK RESOLUTION SYSTEM
  // ===========================================================================

  /// TYC3: Resolve a single attack from attacker to target
  /// Handles damage, abilities (fury, shield, ranged), and retaliation
  AttackResult resolveAttackTYC3(
    GameCard attacker,
    GameCard target, {
    bool isPlayerAttacking = true,
  }) {
    // Calculate base damage
    int damage = attacker.damage;

    // Apply fury bonus
    final furyBonus = _getFuryBonus(attacker);
    damage += furyBonus;

    // Apply lane damage bonus if set
    if (isPlayerAttacking) {
      damage += _playerLaneDamageBonus;
    } else {
      damage += _opponentLaneDamageBonus;
    }

    // Apply shield reduction on target
    final targetShield = _getShieldValue(target);
    final shieldBonus = isPlayerAttacking
        ? _opponentLaneShieldBonus
        : _playerLaneShieldBonus;
    final totalShield = targetShield + shieldBonus;
    damage = (damage - totalShield).clamp(0, damage);

    // Deal damage to target
    final targetHpBefore = target.currentHealth;
    final targetDied = target.takeDamage(damage);
    final targetHpAfter = target.currentHealth;

    // Log the attack
    combatLog.add(
      BattleLogEntry(
        tick: 0, // TYC3 doesn't use ticks
        laneDescription: 'TYC3',
        action: '⚔️ ${attacker.name} ATTACKS',
        details:
            '${target.name} takes $damage damage | HP: $targetHpBefore → $targetHpAfter${targetDied ? " 💀" : ""}',
        isImportant: targetDied,
        level: targetDied ? LogLevel.important : LogLevel.normal,
        damageDealt: damage,
        attackerName: attacker.name,
        targetName: target.name,
        targetHpBefore: targetHpBefore,
        targetHpAfter: targetHpAfter,
        targetDied: targetDied,
      ),
    );

    // Check for retaliation (if target survived and attacker is not ranged)
    int retaliationDamage = 0;
    bool attackerDied = false;

    if (!targetDied && !attacker.isRanged && target.isAlive) {
      // Target retaliates
      retaliationDamage = target.damage;

      // Apply target's fury
      retaliationDamage += _getFuryBonus(target);

      // Apply attacker's shield
      final attackerShield = _getShieldValue(attacker);
      final attackerShieldBonus = isPlayerAttacking
          ? _playerLaneShieldBonus
          : _opponentLaneShieldBonus;
      retaliationDamage =
          (retaliationDamage - attackerShield - attackerShieldBonus).clamp(
            0,
            retaliationDamage,
          );

      // Deal retaliation damage
      final attackerHpBefore = attacker.currentHealth;
      attackerDied = attacker.takeDamage(retaliationDamage);
      final attackerHpAfter = attacker.currentHealth;

      // Log retaliation
      combatLog.add(
        BattleLogEntry(
          tick: 0,
          laneDescription: 'TYC3',
          action: '↩️ ${target.name} RETALIATES',
          details:
              '${attacker.name} takes $retaliationDamage damage | HP: $attackerHpBefore → $attackerHpAfter${attackerDied ? " 💀" : ""}',
          isImportant: attackerDied,
          level: attackerDied ? LogLevel.important : LogLevel.normal,
          damageDealt: retaliationDamage,
          attackerName: target.name,
          targetName: attacker.name,
          targetHpBefore: attackerHpBefore,
          targetHpAfter: attackerHpAfter,
          targetDied: attackerDied,
        ),
      );
    } else if (!targetDied && attacker.isRanged) {
      // Log that ranged attack avoided retaliation
      combatLog.add(
        BattleLogEntry(
          tick: 0,
          laneDescription: 'TYC3',
          action: '🏹 RANGED - No retaliation',
          details:
              '${attacker.name} is ranged, ${target.name} cannot retaliate',
          level: LogLevel.verbose,
        ),
      );
    }

    // Apply thorns damage if target has thorns ability
    if (!attackerDied && target.isAlive) {
      final thornsDamage = _getThornsDamage(target);
      if (thornsDamage > 0) {
        final attackerHpBefore = attacker.currentHealth;
        attackerDied = attacker.takeDamage(thornsDamage);
        final attackerHpAfter = attacker.currentHealth;

        combatLog.add(
          BattleLogEntry(
            tick: 0,
            laneDescription: 'TYC3',
            action: '🌿 ${target.name} THORNS',
            details:
                '${attacker.name} takes $thornsDamage thorns damage | HP: $attackerHpBefore → $attackerHpAfter${attackerDied ? " 💀" : ""}',
            isImportant: attackerDied,
            level: attackerDied ? LogLevel.important : LogLevel.normal,
          ),
        );
      }
    }

    return AttackResult(
      success: true,
      damageDealt: damage,
      retaliationDamage: retaliationDamage,
      targetDied: targetDied,
      attackerDied: attackerDied,
      message:
          '${attacker.name} dealt $damage to ${target.name}${targetDied ? " (killed)" : ""}',
    );
  }

  /// TYC3: Preview an attack without applying damage
  /// Returns predicted AttackResult with damage values
  AttackResult previewAttackTYC3(
    GameCard attacker,
    GameCard target, {
    bool isPlayerAttacking = true,
  }) {
    // Calculate base damage
    int damage = attacker.damage;

    // Apply fury bonus
    final furyBonus = _getFuryBonus(attacker);
    damage += furyBonus;

    // Apply lane damage bonus if set
    if (isPlayerAttacking) {
      damage += _playerLaneDamageBonus;
    } else {
      damage += _opponentLaneDamageBonus;
    }

    // Apply shield reduction on target
    final targetShield = _getShieldValue(target);
    final shieldBonus = isPlayerAttacking
        ? _opponentLaneShieldBonus
        : _playerLaneShieldBonus;
    final totalShield = targetShield + shieldBonus;
    damage = (damage - totalShield).clamp(0, damage);

    // Predict target death
    final targetHpAfter = (target.currentHealth - damage).clamp(
      0,
      target.health,
    );
    final targetDied = targetHpAfter <= 0;

    // Calculate retaliation (if target survives and attacker is not ranged)
    int retaliationDamage = 0;
    bool attackerDied = false;
    int attackerHpAfter = attacker.currentHealth;

    if (!targetDied && !attacker.isRanged) {
      // Target retaliates
      retaliationDamage = target.damage;

      // Apply target's fury
      retaliationDamage += _getFuryBonus(target);

      // Apply attacker's shield
      final attackerShield = _getShieldValue(attacker);
      final attackerShieldBonus = isPlayerAttacking
          ? _playerLaneShieldBonus
          : _opponentLaneShieldBonus;
      retaliationDamage =
          (retaliationDamage - attackerShield - attackerShieldBonus).clamp(
            0,
            retaliationDamage,
          );

      attackerHpAfter = (attacker.currentHealth - retaliationDamage).clamp(
        0,
        attacker.health,
      );
      attackerDied = attackerHpAfter <= 0;
    }

    // Add thorns damage
    int thornsDamage = 0;
    if (!attackerDied && !targetDied) {
      thornsDamage = _getThornsDamage(target);
      if (thornsDamage > 0) {
        attackerHpAfter = (attackerHpAfter - thornsDamage).clamp(
          0,
          attacker.health,
        );
        attackerDied = attackerHpAfter <= 0;
        retaliationDamage += thornsDamage;
      }
    }

    return AttackResult(
      success: true,
      damageDealt: damage,
      retaliationDamage: retaliationDamage,
      targetDied: targetDied,
      attackerDied: attackerDied,
      message: 'Preview: ${attacker.name} → $damage dmg → ${target.name}',
    );
  }

  /// TYC3: Get fury bonus from card abilities
  int _getFuryBonus(GameCard card) {
    for (final ability in card.abilities) {
      if (ability.startsWith('fury_')) {
        return int.tryParse(ability.split('_').last) ?? 0;
      }
    }
    return 0;
  }

  /// TYC3: Get shield value from card abilities
  int _getShieldValue(GameCard card) {
    for (final ability in card.abilities) {
      if (ability.startsWith('shield_')) {
        return int.tryParse(ability.split('_').last) ?? 0;
      }
    }
    return 0;
  }

  /// TYC3: Get thorns damage from card abilities
  int _getThornsDamage(GameCard card) {
    for (final ability in card.abilities) {
      if (ability.startsWith('thorns_')) {
        return int.tryParse(ability.split('_').last) ?? 0;
      }
    }
    return 0;
  }

  /// TYC3: Check if attacker can attack target based on range and position
  /// Returns null if valid, or an error message if invalid
  String? validateAttackTYC3({
    required GameCard attacker,
    required GameCard target,
    required int attackerRow,
    required int attackerCol,
    required int targetRow,
    required int targetCol,
    required List<GameCard> guardsInTargetTile,
  }) {
    // Check if attacker has enough AP
    if (!attacker.canAttack()) {
      return 'Not enough AP to attack (need ${attacker.attackAPCost}, have ${attacker.currentAP})';
    }

    // Calculate distance (in tiles)
    final rowDistance = (targetRow - attackerRow).abs();
    final colDistance = (targetCol - attackerCol).abs();

    // Must be in same column (lane) for now
    if (colDistance != 0) {
      return 'Can only attack in the same lane';
    }

    // Check range
    if (rowDistance > attacker.attackRange) {
      return 'Target is out of range (range: ${attacker.attackRange}, distance: $rowDistance)';
    }

    // Check guard rule - must attack guards first
    if (guardsInTargetTile.isNotEmpty && !target.isGuard) {
      final guardNames = guardsInTargetTile.map((g) => g.name).join(', ');
      return 'Must attack guards first: $guardNames';
    }

    return null; // Valid attack
  }

  /// TYC3: Get all valid attack targets for a card
  List<GameCard> getValidTargetsTYC3({
    required GameCard attacker,
    required int attackerRow,
    required int attackerCol,
    required List<List<List<GameCard>>> boardCards, // [row][col][cards]
    required bool isPlayerCard,
  }) {
    final targets = <GameCard>[];

    // Determine which rows to check based on range
    final minRow = (attackerRow - attacker.attackRange).clamp(0, 2);
    final maxRow = (attackerRow + attacker.attackRange).clamp(0, 2);

    // Only check same column (lane)
    final col = attackerCol;

    for (int row = minRow; row <= maxRow; row++) {
      if (row == attackerRow) continue; // Can't attack own tile

      // Check if this is an enemy tile
      final isEnemyTile = isPlayerCard
          ? (row < attackerRow)
          : (row > attackerRow);
      if (!isEnemyTile) continue;

      final cardsInTile = boardCards[row][col];
      if (cardsInTile.isEmpty) continue;

      // Check for guards
      final guards = cardsInTile.where((c) => c.isGuard && c.isAlive).toList();

      if (guards.isNotEmpty) {
        // Can only target guards
        targets.addAll(guards);
      } else {
        // Can target any card
        targets.addAll(cardsInTile.where((c) => c.isAlive));
      }
    }

    return targets;
  }
}
