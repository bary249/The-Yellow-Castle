import '../models/card.dart';
import '../models/lane.dart';

/// TYC3: Result of a single attack
class AttackResult {
  final bool success;
  final int damageDealt;
  final int retaliationDamage;
  final int thornsDamage; // Separate from retaliation for logging
  final bool targetDied;
  final bool attackerDied;
  final String message;
  final List<String> modifiers; // Buffs/Debuffs descriptions
  final List<String> retaliationModifiers; // Retaliation Buffs/Debuffs

  AttackResult({
    required this.success,
    this.damageDealt = 0,
    this.retaliationDamage = 0,
    this.thornsDamage = 0,
    this.targetDied = false,
    this.attackerDied = false,
    this.message = '',
    this.modifiers = const [],
    this.retaliationModifiers = const [],
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

    // 5) Lane-wide shield bonus from fortify/command abilities
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

    // Handle cleave: also damage the second card on the tile
    if (attacker.abilities.contains('cleave')) {
      final secondTarget = targetStack.bottomCard;
      if (secondTarget != null &&
          secondTarget.isAlive &&
          secondTarget != target) {
        // Cleave deals same damage to second target
        final cleaveHpBefore = secondTarget.currentHealth;
        final cleaveDied = secondTarget.takeDamage(damage);
        final cleaveHpAfter = secondTarget.currentHealth;

        combatLog.add(
          BattleLogEntry(
            tick: tick,
            laneDescription: laneName,
            action: '🌀 CLEAVE → ${secondTarget.name}',
            details:
                '$damage cleave damage | HP: $cleaveHpBefore → $cleaveHpAfter | ${cleaveDied ? "💀 DESTROYED" : "✓ Hit"}',
            isImportant: cleaveDied,
            level: LogLevel.important,
            damageDealt: damage,
            attackerName: attacker.name,
            targetName: secondTarget.name,
            targetHpBefore: cleaveHpBefore,
            targetHpAfter: cleaveHpAfter,
            targetDied: cleaveDied,
          ),
        );
      }
    }

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
  /// Handles damage, abilities (fury, shield, ranged), terrain buffs, and retaliation
  /// tileTerrain is the terrain of the tile where combat occurs (target's tile)
  /// playerDamageBoost is the hero ability damage boost (if active)
  AttackResult resolveAttackTYC3(
    GameCard attacker,
    GameCard target, {
    bool isPlayerAttacking = true,
    String? tileTerrain,
    int playerDamageBoost = 0,
    int laneDamageBonus = 0,
    int laneShieldBonus = 0,
  }) {
    // Calculate base damage
    int damage = attacker.damage;
    final List<String> modifiers = [];

    // Apply lane damage bonus if set
    if (isPlayerAttacking) {
      final totalBonus = _playerLaneDamageBonus + laneDamageBonus;
      if (totalBonus > 0) {
        damage += totalBonus;
        modifiers.add('+$totalBonus Lane Buff');
      }
    } else {
      final totalBonus = _opponentLaneDamageBonus + laneDamageBonus;
      if (totalBonus > 0) {
        damage += totalBonus;
        modifiers.add('+$totalBonus Lane Buff');
      }
    }

    // Apply hero ability damage boost (player only)
    if (isPlayerAttacking && playerDamageBoost > 0) {
      damage += playerDamageBoost;
      modifiers.add('+$playerDamageBoost Hero Boost');
    }

    // Apply terrain buff for attacker (+1 if attacker's element matches tile terrain)
    if (tileTerrain != null &&
        attacker.element != null &&
        attacker.element!.toLowerCase() == tileTerrain.toLowerCase()) {
      damage += 1;
      modifiers.add('+1 Terrain');
    }

    // Apply fury bonus
    final furyBonus = _getFuryBonus(attacker);
    if (furyBonus > 0) {
      damage += furyBonus;
      modifiers.add('+$furyBonus Fury');
    }

    // =========================================================================
    // UNIT COUNTERS (Rock-Paper-Scissors)
    // =========================================================================
    final isPikeman = attacker.abilities.contains('pikeman');
  final isCavalry = attacker.abilities.contains('cavalry');
  // final isArcher = attacker.abilities.contains('archer'); // Unused
  final isRanged = attacker.isRanged; // Checks 'ranged' ability

  final targetIsCavalry = target.abilities.contains('cavalry');
  final targetIsArcher = target.abilities.contains('archer');
  final targetIsShieldGuard = target.abilities.contains('shield_guard');

  // 1. Pikeman > Cavalry (+4 DMG)
  if (isPikeman && targetIsCavalry) {
    damage += 4;
    modifiers.add('+4 vs Cavalry');
  }

  // 2. Cavalry > Archer (+4 DMG)
  if (isCavalry && targetIsArcher) {
    damage += 4;
    modifiers.add('+4 vs Archer');
  }

  // 3. Shield Guard vs Ranged (-2 DMG)
  if (isRanged && targetIsShieldGuard) {
    damage -= 2;
    modifiers.add('-2 Shield Guard');
  }
  // =========================================================================

  // Scale damage based on attacker's current HP (soft floor 50%-100%)
  final attackerMaxHp = attacker.health;
  if (attackerMaxHp > 0) {
    final attackerHpRatio = attacker.currentHealth / attackerMaxHp;
    final hpMultiplier = 0.5 + 0.5 * attackerHpRatio;
    damage = (damage * hpMultiplier).ceil();
  }

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

  // Check for retaliation (melee attackers always receive retaliation, even from dying units)
  // This represents simultaneous combat - both units strike at the same time
  int retaliationDamage = 0;
  bool attackerDied = false;

  // Retaliation happens if attacker is melee (not ranged) and target has damage > 0
  // Note: We use target.damage (base stat) not currentHealth since target retaliates before dying
  final List<String> retModifiers = [];
  if (!attacker.isRanged && target.damage > 0) {
    // Target retaliates
    retaliationDamage = target.damage;

    // Apply target's fury
    final furyBonus = _getFuryBonus(target);
    // Apply fury bonus
    final furyBonus = _getFuryBonus(attacker);
    if (furyBonus > 0) {
      damage += furyBonus;
      modifiers.add('+$furyBonus Fury');
    }

    // Apply terrain buff for attacker (+1 if attacker's element matches tile terrain)
    int attackerTerrainBonus = 0;
    if (tileTerrain != null &&
        attacker.element != null &&
        attacker.element!.toLowerCase() == tileTerrain.toLowerCase()) {
      attackerTerrainBonus = 1;
      damage += attackerTerrainBonus;
      modifiers.add('+1 Terrain');
    }

    // Apply hero ability damage boost (player only)
    if (isPlayerAttacking && playerDamageBoost > 0) {
      damage += playerDamageBoost;
      modifiers.add('+$playerDamageBoost Hero Boost');
    }

    // Apply lane damage bonus if set
    if (isPlayerAttacking) {
      final totalBonus = _playerLaneDamageBonus + laneDamageBonus;
      if (totalBonus > 0) {
        damage += totalBonus;
        modifiers.add('+$totalBonus Lane Buff');
      }
    } else {
      final totalBonus = _opponentLaneDamageBonus + laneDamageBonus;
      if (totalBonus > 0) {
        damage += totalBonus;
        modifiers.add('+$totalBonus Lane Buff');
      }
    }

    // =========================================================================
    // UNIT COUNTERS (Rock-Paper-Scissors)
    // =========================================================================
    final isPikeman = attacker.abilities.contains('pikeman');
    final isCavalry = attacker.abilities.contains('cavalry');
    // final isArcher = attacker.abilities.contains('archer'); // Unused
    final isRanged = attacker.isRanged; // Checks 'ranged' ability

    final targetIsCavalry = target.abilities.contains('cavalry');
    final targetIsArcher = target.abilities.contains('archer');
    final targetIsShieldGuard = target.abilities.contains('shield_guard');

    // 1. Pikeman > Cavalry (+4 DMG)
    if (isPikeman && targetIsCavalry) {
      damage += 4;
      modifiers.add('+4 vs Cavalry');
    }

    // 2. Cavalry > Archer (+4 DMG)
    if (isCavalry && targetIsArcher) {
      damage += 4;
      modifiers.add('+4 vs Archer');
    }

    // 3. Shield Guard vs Ranged (-2 DMG)
    if (isRanged && targetIsShieldGuard) {
      damage -= 2;
      modifiers.add('-2 Shield Guard');
    }
    // =========================================================================

    // Scale damage based on attacker's current HP (soft floor 50%-100%)
    final attackerMaxHp = attacker.health;
    if (attackerMaxHp > 0) {
      final attackerHpRatio = attacker.currentHealth / attackerMaxHp;
      final hpMultiplier = 0.5 + 0.5 * attackerHpRatio;
      damage = (damage * hpMultiplier).ceil();
    }

    // Apply shield reduction on target
    final targetShield = _getShieldValue(target);
    final baseShieldBonus = isPlayerAttacking
        ? _opponentLaneShieldBonus
        : _playerLaneShieldBonus;
    final effectiveShieldBonus = baseShieldBonus + laneShieldBonus;
    final totalShield = targetShield + effectiveShieldBonus;
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

    // Check for retaliation (melee attackers always receive retaliation, even from dying units)
    // This represents simultaneous combat - both units strike at the same time
    int retaliationDamage = 0;
    bool attackerDied = false;

    // Retaliation happens if attacker is melee (not ranged) and target has damage > 0
    // Note: We use target.damage (base stat) not currentHealth since target retaliates before dying
    final List<String> retModifiers = [];
    if (!attacker.isRanged && target.damage > 0) {
      // Target retaliates
      retaliationDamage = target.damage;

      // Apply target's fury
      final furyBonus = _getFuryBonus(target);
      if (furyBonus > 0) {
        retaliationDamage += furyBonus;
        retModifiers.add('+$furyBonus Fury');
      }

      // =========================================================================
      // UNIT COUNTERS (Retaliation)
      // =========================================================================
      final targetIsRanged = target.isRanged; // Includes Archer, Cannon, etc.
      final targetIsPikeman = target.abilities.contains('pikeman');
      final attackerIsCavalry = attacker.abilities.contains('cavalry');

      // 1. Ranged vs Melee (-4 Retaliation - Weak in melee)
      if (targetIsRanged) {
        retaliationDamage -= 4;
        retModifiers.add('-4 Ranged Weakness');
      }

      // 2. Pikeman vs Cavalry (+4 Retaliation - Anti-cavalry defense)
      if (targetIsPikeman && attackerIsCavalry) {
        retaliationDamage += 4;
        retModifiers.add('+4 vs Cavalry');
      }
      // =========================================================================

      // Apply terrain buff for defender (+1 if defender's element matches tile terrain)
      if (tileTerrain != null &&
          target.element != null &&
          target.element!.toLowerCase() == tileTerrain.toLowerCase()) {
        retaliationDamage += 1;
        retModifiers.add('+1 Terrain');
      }

      // Scale retaliation based on defender's current HP (soft floor 50%-100%)
      final defenderMaxHp = target.health;
      if (defenderMaxHp > 0) {
        final defenderHpRatio = target.currentHealth / defenderMaxHp;
        final hpMultiplier = 0.5 + 0.5 * defenderHpRatio;
        retaliationDamage = (retaliationDamage * hpMultiplier).ceil();
      }

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
    int actualThornsDamage = 0;
    if (!attackerDied && target.isAlive) {
      actualThornsDamage = _getThornsDamage(target);
      if (actualThornsDamage > 0) {
        final attackerHpBefore = attacker.currentHealth;
        attackerDied = attacker.takeDamage(actualThornsDamage);
        final attackerHpAfter = attacker.currentHealth;

        combatLog.add(
          BattleLogEntry(
            tick: 0,
            laneDescription: 'TYC3',
            action: '🌿 ${target.name} THORNS',
            details:
                '${attacker.name} takes $actualThornsDamage thorns damage | HP: $attackerHpBefore → $attackerHpAfter${attackerDied ? " 💀" : ""}',
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
      thornsDamage: actualThornsDamage,
      targetDied: targetDied,
      attackerDied: attackerDied,
      message:
          '${attacker.name} dealt $damage to ${target.name}${targetDied ? " (killed)" : ""}',
      modifiers: modifiers,
      retaliationModifiers: retModifiers,
    );
  }

  /// TYC3: Preview an attack without applying damage
  /// Returns predicted AttackResult with damage values
  AttackResult previewAttackTYC3(
    GameCard attacker,
    GameCard target, {
    bool isPlayerAttacking = true,
    String? tileTerrain,
    int playerDamageBoost = 0,
    int laneDamageBonus = 0,
    int laneShieldBonus = 0,
  }) {
    // Calculate base damage
    int damage = attacker.damage;
    final List<String> modifiers = [];

    // Apply fury bonus
    final furyBonus = _getFuryBonus(attacker);
    if (furyBonus > 0) {
      damage += furyBonus;
      modifiers.add('+$furyBonus Fury');
    }

    // Apply terrain buff for attacker (+1 if attacker's element matches tile terrain)
    if (tileTerrain != null &&
        attacker.element != null &&
        attacker.element!.toLowerCase() == tileTerrain.toLowerCase()) {
      damage += 1;
      modifiers.add('+1 Terrain');
    }

    // Apply hero ability damage boost (player only)
    if (isPlayerAttacking && playerDamageBoost > 0) {
      damage += playerDamageBoost;
      modifiers.add('+$playerDamageBoost Hero Boost');
    }

    // Apply lane damage bonus if set
    if (isPlayerAttacking) {
      final totalBonus = _playerLaneDamageBonus + laneDamageBonus;
      if (totalBonus > 0) {
        damage += totalBonus;
        modifiers.add('+$totalBonus Lane Buff');
      }
    } else {
      final totalBonus = _opponentLaneDamageBonus + laneDamageBonus;
      if (totalBonus > 0) {
        damage += totalBonus;
        modifiers.add('+$totalBonus Lane Buff');
      }
    }

    // =========================================================================
    // UNIT COUNTERS (Rock-Paper-Scissors)
    // =========================================================================
    final isPikeman = attacker.abilities.contains('pikeman');
    final isCavalry = attacker.abilities.contains('cavalry');
    final isRanged = attacker.isRanged; // Checks 'ranged' ability

    final targetIsCavalry = target.abilities.contains('cavalry');
    final targetIsArcher = target.abilities.contains('archer');
    final targetIsShieldGuard = target.abilities.contains('shield_guard');

    // 1. Pikeman > Cavalry (+4 DMG)
    if (isPikeman && targetIsCavalry) {
      damage += 4;
      modifiers.add('+4 vs Cavalry');
    }

    // 2. Cavalry > Archer (+4 DMG)
    if (isCavalry && targetIsArcher) {
      damage += 4;
      modifiers.add('+4 vs Archer');
    }

    // 3. Shield Guard vs Ranged (-2 DMG)
    if (isRanged && targetIsShieldGuard) {
      damage -= 2;
      modifiers.add('-2 Shield Guard');
    }
    // =========================================================================

    // Scale damage based on attacker's current HP (soft floor 50%-100%)
    final attackerMaxHp = attacker.health;
    if (attackerMaxHp > 0) {
      final attackerHpRatio = attacker.currentHealth / attackerMaxHp;
      final hpMultiplier = 0.5 + 0.5 * attackerHpRatio;
      damage = (damage * hpMultiplier).ceil();
    }

    // Apply shield reduction on target
    final targetShield = _getShieldValue(target);
    final baseShieldBonus = isPlayerAttacking
        ? _opponentLaneShieldBonus
        : _playerLaneShieldBonus;
    final effectiveShieldBonus = baseShieldBonus + laneShieldBonus;
    final totalShield = targetShield + effectiveShieldBonus;
    damage = (damage - totalShield).clamp(0, damage);

    // Predict target death
    final targetHpAfter = (target.currentHealth - damage).clamp(
      0,
      target.health,
    );
    final targetDied = targetHpAfter <= 0;

    // Calculate retaliation (melee attackers always receive retaliation, even from dying units)
    int retaliationDamage = 0;
    bool attackerDied = false;
    int attackerHpAfter = attacker.currentHealth;

    // Retaliation happens if attacker is melee and target has damage > 0
    final List<String> retModifiers = [];
    if (!attacker.isRanged && target.damage > 0) {
      // Target retaliates
      retaliationDamage = target.damage;

      // Apply target's fury
      final furyBonus = _getFuryBonus(target);
      if (furyBonus > 0) {
        retaliationDamage += furyBonus;
        retModifiers.add('+$furyBonus Fury');
      }

      // =========================================================================
      // UNIT COUNTERS (Retaliation)
      // =========================================================================
      final targetIsRanged = target.isRanged; // Includes Archer, Cannon, etc.
      final targetIsPikeman = target.abilities.contains('pikeman');
      final attackerIsCavalry = attacker.abilities.contains('cavalry');

      // 1. Ranged vs Melee (-4 Retaliation - Weak in melee)
      if (targetIsRanged) {
        retaliationDamage -= 4;
        retModifiers.add('-4 Ranged Weakness');
      }

      // 2. Pikeman vs Cavalry (+4 Retaliation - Anti-cavalry defense)
      if (targetIsPikeman && attackerIsCavalry) {
        retaliationDamage += 4;
        retModifiers.add('+4 vs Cavalry');
      }
      // =========================================================================

      // Apply terrain buff for defender (+1 if defender's element matches tile terrain)
      if (tileTerrain != null &&
          target.element != null &&
          target.element!.toLowerCase() == tileTerrain.toLowerCase()) {
        retaliationDamage += 1;
        retModifiers.add('+1 Terrain');
      }

      // Scale retaliation based on defender's current HP (soft floor 50%-100%)
      final defenderMaxHp = target.health;
      if (defenderMaxHp > 0) {
        final defenderHpRatio = target.currentHealth / defenderMaxHp;
        final hpMultiplier = 0.5 + 0.5 * defenderHpRatio;
        retaliationDamage = (retaliationDamage * hpMultiplier).ceil();
      }

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

    // Add thorns damageR
    int thornsDamage = 0;
    if (!attackerDied && !targetDied) {
      thornsDamage = _getThornsDamage(target);
      if (thornsDamage > 0) {
        attackerHpAfter = (attackerHpAfter - thornsDamage).clamp(
          0,
          attacker.health,
        );
        attackerDied = attackerHpAfter <= 0;
        // Don't add thorns to retaliation - keep them separate
      }
    }

    return AttackResult(
      success: true,
      damageDealt: damage,
      retaliationDamage: retaliationDamage,
      thornsDamage: thornsDamage,
      targetDied: targetDied,
      attackerDied: attackerDied,
      message: 'Preview: ${attacker.name} → $damage dmg → ${target.name}',
      modifiers: modifiers,
      retaliationModifiers: retModifiers,
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
  /// Cross-lane attacks follow same rules as movement: only adjacent tiles (same row, different col)
  /// Forward attacks can go up to attackRange tiles ahead in same lane
  /// Returns null if valid, or an error message if invalid
  String? validateAttackTYC3({
    required GameCard attacker,
    required GameCard target,
    required int attackerRow,
    required int attackerCol,
    required int targetRow,
    required int targetCol,
    required List<GameCard> guardsInTargetTile,
    bool allowCrossLane = false,
  }) {
    // Check if attacker has enough AP
    if (!attacker.canAttack()) {
      return 'Not enough AP to attack (need ${attacker.attackAPCost}, have ${attacker.currentAP})';
    }

    // Calculate distance (in tiles)
    final rowDistance = (targetRow - attackerRow).abs();
    final colDistance = (targetCol - attackerCol).abs();

    // Check if this is a valid attack pattern:
    // 1) Forward attack: same column, within range
    // 2) Cross-lane attack: same row, adjacent column (if allowed)
    final hasCrossAttack = attacker.abilities.contains('cross_attack');
    final canAttackCrossLane = allowCrossLane || hasCrossAttack;

    final isForwardAttack =
        colDistance == 0 && rowDistance <= attacker.attackRange;
    final isCrossLaneAttack =
        canAttackCrossLane && rowDistance == 0 && colDistance == 1;

    if (!isForwardAttack && !isCrossLaneAttack) {
      if (colDistance > 0 && rowDistance > 0) {
        return 'Cannot attack diagonally';
      } else if (colDistance > 1) {
        return 'Cross-lane attack only works on adjacent lanes';
      } else if (colDistance > 0 && !canAttackCrossLane) {
        return 'Cannot attack cross-lane (no cross_attack ability)';
      } else {
        return 'Target is out of range (range: ${attacker.attackRange}, distance: $rowDistance)';
      }
    }

    // Check guard rule - must attack guards first
    if (guardsInTargetTile.isNotEmpty && !target.isGuard) {
      final guardNames = guardsInTargetTile.map((g) => g.name).join(', ');
      return 'Must attack guards first: $guardNames';
    }

    return null; // Valid attack
  }

  /// TYC3: Get all valid attack targets for a card
  /// Cross-lane attacks follow same rules as movement: only adjacent tiles (same row, different col)
  /// Forward attacks can go up to attackRange tiles ahead in same lane
  List<GameCard> getValidTargetsTYC3({
    required GameCard attacker,
    required int attackerRow,
    required int attackerCol,
    required List<List<List<GameCard>>> boardCards, // [row][col][cards]
    required bool isPlayerCard,
    bool allowCrossLane = false,
  }) {
    final targets = <GameCard>[];

    // Check if this unit can attack cross-lane
    final hasCrossAttack = attacker.abilities.contains('cross_attack');
    final canAttackCrossLane = allowCrossLane || hasCrossAttack;

    // Forward direction: player attacks toward row 0, opponent toward row 2
    final forwardDir = isPlayerCard ? -1 : 1;

    // 1) Forward attacks in same lane (up to attackRange)
    for (int dist = 1; dist <= attacker.attackRange; dist++) {
      final targetRow = attackerRow + (forwardDir * dist);
      if (targetRow < 0 || targetRow > 2) break;

      _addTargetsFromBoardTile(
        targets,
        attacker,
        boardCards[targetRow][attackerCol],
      );
    }

    // 2) Cross-lane attacks: only adjacent tiles (same row, different col)
    // This is like side movement - can only attack tiles directly to the left/right
    if (canAttackCrossLane) {
      // Left
      if (attackerCol > 0) {
        _addTargetsFromBoardTile(
          targets,
          attacker,
          boardCards[attackerRow][attackerCol - 1],
        );
      }
      // Right
      if (attackerCol < 2) {
        _addTargetsFromBoardTile(
          targets,
          attacker,
          boardCards[attackerRow][attackerCol + 1],
        );
      }
    }

    return targets;
  }

  /// Helper: Add enemy targets from a board tile's card list
  void _addTargetsFromBoardTile(
    List<GameCard> targets,
    GameCard attacker,
    List<GameCard> cardsInTile,
  ) {
    if (cardsInTile.isEmpty) return;

    // Filter to only enemy cards (cards with different owner)
    final enemyCards = cardsInTile
        .where((c) => c.isAlive && c.ownerId != attacker.ownerId)
        .toList();
    if (enemyCards.isEmpty) return;

    // Check for guards among enemy cards
    final guards = enemyCards.where((c) => c.isGuard).toList();

    if (guards.isNotEmpty) {
      // Can only target guards
      targets.addAll(guards);
    } else {
      // Can target any enemy card
      targets.addAll(enemyCards);
    }
  }
}
