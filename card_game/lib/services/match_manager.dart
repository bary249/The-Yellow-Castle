import '../models/match_state.dart';
import '../models/player.dart';
import '../models/deck.dart';
import '../models/lane.dart';
import '../models/card.dart';
import '../models/hero.dart';
import '../models/game_board.dart';
import '../models/tile.dart';
import 'combat_resolver.dart';

/// Coordinates the entire match flow
class MatchManager {
  MatchState? _currentMatch;
  final CombatResolver _combatResolver = CombatResolver();

  MatchState? get currentMatch => _currentMatch;

  /// Tracks if player has a damage boost active for this turn (from hero ability).
  bool _playerDamageBoostActive = false;

  /// Start a new match
  void startMatch({
    required String playerId,
    required String playerName,
    required Deck playerDeck,
    required String opponentId,
    required String opponentName,
    required Deck opponentDeck,
    bool opponentIsAI = true,
    String? playerAttunedElement,
    String? opponentAttunedElement,
    GameHero? playerHero,
    GameHero? opponentHero,
  }) {
    // Create players with heroes (copy heroes to reset ability state)
    final player = Player(
      id: playerId,
      name: playerName,
      deck: playerDeck,
      isHuman: true,
      attunedElement: playerAttunedElement,
      hero: playerHero?.copy(),
    );

    final opponent = Player(
      id: opponentId,
      name: opponentName,
      deck: opponentDeck,
      isHuman: !opponentIsAI,
      attunedElement: opponentAttunedElement,
      hero: opponentHero?.copy(),
    );

    // Shuffle decks
    player.deck.shuffle();
    opponent.deck.shuffle();

    // Create the 3×3 game board with terrain from hero affinities
    final playerTerrains = playerHero?.terrainAffinities ?? ['Woods'];
    final opponentTerrains = opponentHero?.terrainAffinities ?? ['Desert'];
    final board = GameBoard.create(
      playerTerrains: playerTerrains,
      opponentTerrains: opponentTerrains,
    );

    // Create match state
    _currentMatch = MatchState(
      player: player,
      opponent: opponent,
      board: board,
    );

    // Draw initial hands
    player.drawInitialHand();
    opponent.drawInitialHand();

    // Reset temporary buffs
    _playerDamageBoostActive = false;

    // Start first turn
    _currentMatch!.currentPhase = MatchPhase.turnPhase;
    _currentMatch!.turnNumber = 1;

    _log('Match started!');
    if (playerHero != null) {
      _log(
        'Player hero: ${playerHero.name} (${playerHero.abilityDescription})',
      );
    }
    if (opponentHero != null) {
      _log('Opponent hero: ${opponentHero.name}');
    }
  }

  /// Check if player can use their hero ability.
  bool get canUsePlayerHeroAbility {
    final hero = _currentMatch?.player.hero;
    if (hero == null) return false;
    if (hero.abilityUsed) return false;
    // Can only use during staging phase (before submission)
    if (_currentMatch?.playerSubmitted == true) return false;
    if (_currentMatch?.currentPhase != MatchPhase.turnPhase) return false;
    return true;
  }

  /// Activate the player's hero ability.
  /// Returns true if ability was activated successfully.
  bool activatePlayerHeroAbility() {
    if (!canUsePlayerHeroAbility) return false;

    final hero = _currentMatch!.player.hero!;
    hero.useAbility();

    _log('\n🦸 HERO ABILITY ACTIVATED: ${hero.name}');
    _log('   ${hero.abilityDescription}');

    switch (hero.abilityType) {
      case HeroAbilityType.drawCards:
        // Draw 2 extra cards
        _currentMatch!.player.drawCards(count: 2);
        _log(
          '   Drew 2 extra cards. Hand size: ${_currentMatch!.player.hand.length}',
        );
        break;

      case HeroAbilityType.damageBoost:
        // Flag for +1 damage boost this turn (applied during combat)
        _playerDamageBoostActive = true;
        _log('   All units will deal +1 damage this turn.');
        break;

      case HeroAbilityType.healUnits:
        // Heal all surviving units by 3 HP
        int healed = 0;
        for (final lane in _currentMatch!.lanes) {
          for (final card in lane.playerStack.aliveCards) {
            final before = card.currentHealth;
            card.currentHealth = (card.currentHealth + 3).clamp(0, card.health);
            if (card.currentHealth > before) healed++;
          }
        }
        _log('   Healed $healed surviving units by up to 3 HP.');
        break;
    }

    return true;
  }

  /// Get the damage boost amount for player cards this turn.
  int get playerDamageBoost => _playerDamageBoostActive ? 1 : 0;

  /// Player submits their card placements for the turn (tile-based)
  /// placements is a Map<String, List<GameCard>> where key is "row,col"
  Future<void> submitPlayerTileMoves(
    Map<String, List<GameCard>> tilePlacements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.playerSubmitted) return;

    // Place cards at their tile positions
    for (final entry in tilePlacements.entries) {
      final parts = entry.key.split(',');
      final row = int.parse(parts[0]);
      final col = int.parse(parts[1]);
      final cards = entry.value;

      final lane = _currentMatch!.lanes[col];

      for (final card in cards) {
        if (_currentMatch!.player.playCard(card)) {
          if (row == 2) {
            // Player's base tile - add to baseCards
            lane.playerCards.baseCards.addCard(card, asTopCard: false);
          } else if (row == 1) {
            // Middle tile - add to middleCards
            lane.playerCards.middleCards.addCard(card, asTopCard: false);
          }
        }
      }
    }

    _currentMatch!.playerSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Legacy: Player submits their card placements for the turn (lane-based)
  Future<void> submitPlayerMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.playerSubmitted) return;

    // Place cards in lanes (at base position)
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        if (_currentMatch!.player.playCard(card)) {
          // Place at base position
          lane.playerCards.baseCards.addCard(card, asTopCard: false);
        }
      }
    }

    _currentMatch!.playerSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Opponent (AI) submits their moves (always at their base - row 0)
  Future<void> submitOpponentMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards in lanes at opponent's base position
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        if (_currentMatch!.opponent.playCard(card)) {
          // AI stages at their base
          lane.opponentCards.baseCards.addCard(card, asTopCard: false);
        }
      }
    }

    _currentMatch!.opponentSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Submit opponent moves for online multiplayer (cards not in local hand)
  /// Places cards directly in lanes without checking hand
  Future<void> submitOnlineOpponentMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards directly in lanes at opponent's base
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        // Add directly to opponent base - these are reconstructed from Firebase
        lane.opponentCards.baseCards.addCard(card, asTopCard: false);
      }
    }

    _currentMatch!.opponentSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Opponent (AI or online) submits tile-based moves (supports middle tiles if captured)
  /// placements is a Map<String, List<GameCard>> where key is "row,col"
  /// skipHandCheck: set to true for online mode where cards come from Firebase (not in hand)
  Future<void> submitOpponentTileMoves(
    Map<String, List<GameCard>> tilePlacements, {
    bool skipHandCheck = false,
  }) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards at their tile positions
    for (final entry in tilePlacements.entries) {
      final parts = entry.key.split(',');
      final row = int.parse(parts[0]);
      final col = int.parse(parts[1]);
      final cards = entry.value;

      final lane = _currentMatch!.lanes[col];

      for (final card in cards) {
        // For online mode, skip the hand check since cards come from Firebase
        final canPlay = skipHandCheck || _currentMatch!.opponent.playCard(card);
        if (canPlay) {
          if (row == 0) {
            // Opponent's base tile - add to baseCards
            lane.opponentCards.baseCards.addCard(card, asTopCard: false);
          } else if (row == 1) {
            // Middle tile - add to middleCards
            lane.opponentCards.middleCards.addCard(card, asTopCard: false);
          }
        }
      }
    }

    _currentMatch!.opponentSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Callback for combat animation updates
  Function()? onCombatUpdate;

  /// Current tick information for UI display
  String? currentTickInfo;
  LanePosition? currentCombatLane;
  int? currentCombatTick;

  /// Per-lane tick tracking for UI tick clocks
  /// Maps lane position to current tick (1-5, or 0 if not in combat, 6 if complete)
  Map<LanePosition, int> laneTickProgress = {
    LanePosition.west: 0,
    LanePosition.center: 0,
    LanePosition.east: 0,
  };

  /// Detailed combat info for current tick (for enhanced UI display)
  List<String> currentTickDetails = [];

  /// Optional log sink used by simulations to capture full battle logs.
  /// When set, all combat-related print output is also written here.
  StringBuffer? logSink;

  /// Manual tick progression control
  bool waitingForNextTick = false;
  bool skipAllTicks = false;
  bool autoProgress = true; // Auto-progress with delays (enabled by default)
  bool fastMode = false; // When true, skip delays (for simulations)
  Function()? onWaitingForTick;

  /// Auto-progress tick delays in milliseconds
  int tickDelayWithCombat = 2500; // Longer delay when cards fight (2.5s)
  int tickDelayNoCombat = 800; // Shorter when no action (0.8s)

  /// Advance to next tick (called by user action)
  void advanceToNextTick() {
    waitingForNextTick = false;
    onWaitingForTick?.call();
  }

  /// Skip all remaining ticks (ENTER key)
  void skipToEnd() {
    skipAllTicks = true;
    waitingForNextTick = false;
    onWaitingForTick?.call();
  }

  /// Resolve combat in all lanes with animations
  Future<void> _resolveCombat() async {
    if (_currentMatch == null) return;

    _currentMatch!.currentPhase = MatchPhase.combatPhase;

    // Reset skip flag for new combat
    skipAllTicks = false;

    // Reset lane tick progress
    laneTickProgress = {
      LanePosition.west: 0,
      LanePosition.center: 0,
      LanePosition.east: 0,
    };
    currentTickDetails = [];

    // Clear previous combat log
    _combatResolver.clearLog();

    // Print turn header to terminal
    _log('\n${'=' * 80}');
    _log('TURN ${_currentMatch!.turnNumber} - COMBAT RESOLUTION');
    _log('=' * 80);

    // Log board state BEFORE advancement (shows staging result)
    _log('\n--- BOARD STATE (AFTER STAGING) ---');
    _logBoardState();

    // Move cards forward based on their moveSpeed
    _log('\n--- CARD MOVEMENT ---');
    for (final lane in _currentMatch!.lanes) {
      final laneName = lane.position.name.toUpperCase();

      // Player cards move forward
      final playerMoves = lane.movePlayerCardsForward();
      for (final entry in playerMoves.entries) {
        _log(
          '$laneName: Player ${entry.key.name} moved to ${entry.value.name}',
        );
      }

      // Opponent cards move forward
      final opponentMoves = lane.moveOpponentCardsForward();
      for (final entry in opponentMoves.entries) {
        _log(
          '$laneName: Opponent ${entry.key.name} moved to ${entry.value.name}',
        );
      }
    }
    _log('--- END CARD MOVEMENT ---');

    // Update combat zones for each lane (find where cards meet)
    for (final lane in _currentMatch!.lanes) {
      lane.updateCombatZone();
    }

    // Log board state AFTER movement (shows combat positions)
    _log('\n--- BOARD STATE (BEFORE COMBAT) ---');
    _logBoardState();

    // Resolve each lane with tick-by-tick animation
    for (final lane in _currentMatch!.lanes) {
      if (lane.hasCombat) {
        await _resolveLaneAnimated(lane);
      }
    }

    // Check if any cards damaged crystals (winning a lane means attacking crystal)
    _checkCrystalDamage();

    // Print combat log to terminal
    _log('\n--- BATTLE LOG ---');
    for (final entry in _combatResolver.logEntries) {
      _log(entry.formattedMessage);
    }
    _log('--- END BATTLE LOG ---\n');

    // Wait before showing final results (skip in fast/sim mode)
    if (!fastMode) {
      await Future.delayed(const Duration(milliseconds: 800));
    }
    onCombatUpdate?.call();

    // Print crystal damage
    _log('Player Crystal: ${_currentMatch!.player.crystalHP} HP');
    _log('Opponent Crystal: ${_currentMatch!.opponent.crystalHP} HP');
    _log('=' * 80);

    // Check for game over
    _currentMatch!.checkGameOver();

    if (!_currentMatch!.isGameOver) {
      _startNextTurn();
    }
  }

  /// Resolve a single lane with tick-by-tick animations
  Future<void> _resolveLaneAnimated(Lane lane) async {
    currentCombatLane = lane.position;
    currentTickInfo =
        '⚔️ ${lane.position.name.toUpperCase()} - Combat Starting...';
    laneTickProgress[lane.position] = 0; // Mark lane as starting

    // Provide lane/attunement context to the combat resolver so it can
    // apply base-zone buffs for matching elements and hero damage boosts.
    if (_currentMatch != null) {
      _combatResolver.setLaneContext(
        zone: lane.currentZone,
        playerBaseElement: _currentMatch!.player.attunedElement,
        opponentBaseElement: _currentMatch!.opponent.attunedElement,
        playerDamageBoost: playerDamageBoost,
      );
    }

    // Initial delay to show combat starting (skip in fast/sim mode)
    if (!fastMode) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    onCombatUpdate?.call();

    // Process ticks 1-5 with delays
    for (int tick = 1; tick <= 5; tick++) {
      final playerCard = lane.playerStack.activeCard;
      final opponentCard = lane.opponentStack.activeCard;

      // If both sides are empty, break
      if (playerCard == null && opponentCard == null) break;

      currentCombatTick = tick;
      laneTickProgress[lane.position] = tick; // Update lane tick clock
      currentTickInfo = 'Tick $tick: Processing...';

      // Count log entries before this tick
      final logCountBefore = _combatResolver.logEntries.length;

      // Resolve this tick
      _combatResolver.processTickInLane(tick, lane);

      // Get new log entries from this tick
      final newEntries = _combatResolver.logEntries
          .skip(logCountBefore)
          .toList();

      // Build detailed tick info with combat summaries
      currentTickDetails = newEntries
          .where((e) => e.tick == tick && e.damageDealt != null)
          .map((e) => e.combatSummary)
          .toList();

      final tickActions = newEntries
          .where((e) => e.tick == tick && e.action.contains('→'))
          .map((e) => e.action)
          .join(' | ');

      currentTickInfo = tickActions.isNotEmpty
          ? 'Tick $tick: $tickActions'
          : 'Tick $tick: No actions';

      // Determine if there was combat action this tick
      final hadCombat = currentTickDetails.isNotEmpty || tickActions.isNotEmpty;
      final tickDelay = hadCombat ? tickDelayWithCombat : tickDelayNoCombat;

      // Auto-progress with variable delay based on combat activity
      if (autoProgress && !skipAllTicks) {
        onCombatUpdate?.call();
        if (!fastMode) {
          await Future.delayed(Duration(milliseconds: tickDelay));
        }
      } else if (!skipAllTicks) {
        // Manual progression (waiting for user input)
        waitingForNextTick = true;
        onCombatUpdate?.call();

        // Wait until user presses next or skip
        while (waitingForNextTick && !skipAllTicks) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // Clean up dead cards
      lane.playerStack.cleanup();
      lane.opponentStack.cleanup();

      // Update UI after cleanup
      if (!skipAllTicks) {
        onCombatUpdate?.call();
      }

      // Check if combat is over
      if (lane.playerStack.isEmpty || lane.opponentStack.isEmpty) {
        currentTickInfo = '🏁 Combat Complete!';
        laneTickProgress[lane.position] = 6; // Mark as complete
        break;
      }
    }

    // Mark lane as complete if we finished all 5 ticks
    if (laneTickProgress[lane.position] != 6) {
      laneTickProgress[lane.position] = 6;
    }

    // Final delay after lane completes (skip in fast/sim mode)
    if (!fastMode && !skipAllTicks) {
      await Future.delayed(const Duration(milliseconds: 400));
    }
    currentTickInfo = null;
    currentCombatLane = null;
    currentCombatTick = null;
    currentTickDetails = [];
    onCombatUpdate?.call();
  }

  /// Check crystal damage after combat
  /// Crystal damage occurs when:
  /// 1. Uncontested: Attackers at enemy base with no defenders
  /// 2. Combat victory at enemy base: Surviving attackers deal damage
  /// Attackers STAY at enemy base (no retreat unless special ability)
  void _checkCrystalDamage() {
    if (_currentMatch == null) return;

    _log('\n--- CRYSTAL DAMAGE CHECK ---');

    for (final lane in _currentMatch!.lanes) {
      final laneName = lane.position.name.toUpperCase();
      final colIndex = lane.position.index;

      // Check for player attackers at enemy base
      final playerAttackers = lane.playerCards.enemyBaseCards.aliveCards;
      final opponentDefenders = lane.opponentCards.baseCards.aliveCards;

      if (playerAttackers.isNotEmpty) {
        if (opponentDefenders.isEmpty) {
          // Uncontested - deal full damage
          final totalDamage = playerAttackers.fold<int>(
            0,
            (sum, card) => sum + card.damage,
          );
          _currentMatch!.opponent.takeCrystalDamage(totalDamage);
          _log('$laneName: 💥 $totalDamage UNCONTESTED crystal damage to AI!');
          _log('$laneName: Player attackers hold enemy base');

          // Update tile ownership
          _updateTileOwnership(
            colIndex,
            Zone.enemyBase,
            isPlayerAdvancing: true,
          );
        } else if (lane.currentZone == Zone.enemyBase &&
            lane.playerWon == true) {
          // Won combat at enemy base - survivors deal damage
          final survivors = lane.playerStack.aliveCards;
          if (survivors.isNotEmpty) {
            final totalDamage = survivors.fold<int>(
              0,
              (sum, card) => sum + card.damage,
            );
            _currentMatch!.opponent.takeCrystalDamage(totalDamage);
            _log(
              '$laneName: 💥 $totalDamage crystal damage to AI (combat victory)!',
            );
            _log('$laneName: Player attackers hold enemy base');

            // Update tile ownership
            _updateTileOwnership(
              colIndex,
              Zone.enemyBase,
              isPlayerAdvancing: true,
            );
          }

          // Award gold for combat victory
          _currentMatch!.player.earnGold(400);
        }
      }

      // Check for opponent attackers at player base
      final opponentAttackers = lane.opponentCards.enemyBaseCards.aliveCards;
      final playerDefenders = lane.playerCards.baseCards.aliveCards;

      if (opponentAttackers.isNotEmpty) {
        if (playerDefenders.isEmpty) {
          // Uncontested - deal full damage
          final totalDamage = opponentAttackers.fold<int>(
            0,
            (sum, card) => sum + card.damage,
          );
          _currentMatch!.player.takeCrystalDamage(totalDamage);
          _log(
            '$laneName: 💥 $totalDamage UNCONTESTED crystal damage to Player!',
          );
          _log('$laneName: AI attackers hold player base');

          // Update tile ownership
          _updateTileOwnership(
            colIndex,
            Zone.playerBase,
            isPlayerAdvancing: false,
          );
        } else if (lane.currentZone == Zone.playerBase &&
            lane.playerWon == false) {
          // Won combat at player base - survivors deal damage
          final survivors = lane.opponentStack.aliveCards;
          if (survivors.isNotEmpty) {
            final totalDamage = survivors.fold<int>(
              0,
              (sum, card) => sum + card.damage,
            );
            _currentMatch!.player.takeCrystalDamage(totalDamage);
            _log(
              '$laneName: 💥 $totalDamage crystal damage to Player (combat victory)!',
            );
            _log('$laneName: AI attackers hold player base');

            // Update tile ownership
            _updateTileOwnership(
              colIndex,
              Zone.playerBase,
              isPlayerAdvancing: false,
            );
          }

          // Award gold for combat victory
          _currentMatch!.opponent.earnGold(400);
        }
      }

      // Check for combat victories at other zones (award gold)
      if (lane.hasCombat || lane.playerWon != null) {
        if (lane.playerWon == true && lane.currentZone != Zone.enemyBase) {
          _log('$laneName: Player victory at ${lane.zoneDisplay}');
          _currentMatch!.player.earnGold(400);
        } else if (lane.playerWon == false &&
            lane.currentZone != Zone.playerBase) {
          _log('$laneName: AI victory at ${lane.zoneDisplay}');
          _currentMatch!.opponent.earnGold(400);
        } else if (lane.playerWon == null && lane.hasCombat) {
          _log('$laneName: Draw at ${lane.zoneDisplay}');
        }
      }
    }

    _log('--- END CRYSTAL DAMAGE CHECK ---');

    // Log the board state after combat resolution
    _log('\n--- BOARD STATE (AFTER COMBAT) ---');
    _logBoardState();
  }

  /// Log the current board state showing tiles and cards
  void _logBoardState() {
    if (_currentMatch == null) return;

    final board = _currentMatch!.board;
    final lanes = _currentMatch!.lanes;

    _log('\n╔════════════════════════════════════╗');
    _log('║         BOARD STATE                ║');
    _log('╠════════════════════════════════════╣');

    // Row labels
    final rowLabels = ['Enemy Base', 'Middle    ', 'Your Base '];

    for (int row = 0; row < 3; row++) {
      _log('║ ${rowLabels[row]}:');

      for (int col = 0; col < 3; col++) {
        final tile = board.getTile(row, col);
        final lane = lanes[col];

        // Get owner symbol
        String ownerSymbol;
        switch (tile.owner) {
          case TileOwner.player:
            ownerSymbol = '🔵';
          case TileOwner.opponent:
            ownerSymbol = '🔴';
          case TileOwner.neutral:
            ownerSymbol = '⚪';
        }

        // Get cards at this tile based on position
        List<String> cardNames = [];
        final lanePos = [
          LanePosition.west,
          LanePosition.center,
          LanePosition.east,
        ][col];

        // Row 0 = enemy base, Row 1 = middle, Row 2 = player base
        // Show cards at their ACTUAL positions (not based on combat zone)
        if (row == 0) {
          // Enemy base row - show opponent's base cards + player's attacking cards
          // Player cards that reached enemy base
          for (final card in lane.playerCards.enemyBaseCards.aliveCards) {
            cardNames.add('P:${card.name}(${card.currentHealth}hp)');
          }
          // Opponent's staging cards (with fog of war)
          if (_currentMatch!.revealedEnemyBaseLanes.contains(lanePos)) {
            for (final card in lane.opponentCards.baseCards.aliveCards) {
              cardNames.add('O:${card.name}(${card.currentHealth}hp)');
            }
          } else {
            final hiddenCount = lane.opponentCards.baseCards.aliveCards.length;
            if (hiddenCount > 0) {
              cardNames.add('??? ($hiddenCount hidden)');
            }
          }
        } else if (row == 1) {
          // Middle row - show both sides' middle cards
          for (final card in lane.playerCards.middleCards.aliveCards) {
            cardNames.add('P:${card.name}(${card.currentHealth}hp)');
          }
          for (final card in lane.opponentCards.middleCards.aliveCards) {
            cardNames.add('O:${card.name}(${card.currentHealth}hp)');
          }
        } else if (row == 2) {
          // Player base row - show player's base cards + opponent's attacking cards
          for (final card in lane.playerCards.baseCards.aliveCards) {
            cardNames.add('P:${card.name}(${card.currentHealth}hp)');
          }
          // Opponent cards that reached player base
          for (final card in lane.opponentCards.enemyBaseCards.aliveCards) {
            cardNames.add('O:${card.name}(${card.currentHealth}hp)');
          }
        }

        final colName = ['W', 'C', 'E'][col];

        // Fog of war: hide enemy base terrain unless revealed
        String terrain;
        if (row == 0 &&
            !_currentMatch!.revealedEnemyBaseLanes.contains(lanePos)) {
          terrain = '???'; // Hidden terrain
        } else {
          terrain = tile.terrain ?? '-';
        }

        final cardsStr = cardNames.isEmpty ? 'empty' : cardNames.join(', ');

        _log('║   [$colName] $ownerSymbol $terrain: $cardsStr');
      }
    }

    _log('╚════════════════════════════════════╝');

    // Add compact visual grid
    _log('\n     W   C   E     POSITIONS');
    _log('   ┌───┬───┬───┐');
    for (int row = 0; row < 3; row++) {
      final rowLabel = ['0', '1', '2'][row];
      String rowStr = ' $rowLabel │';
      for (int col = 0; col < 3; col++) {
        final tile = board.getTile(row, col);
        final lane = lanes[col];

        // Zone row: where combat happens for this lane
        final zoneRow = lane.currentZone == Zone.enemyBase
            ? 0
            : (lane.currentZone == Zone.playerBase ? 2 : 1);

        // Fighting cards (middleCards) - shown at zone row
        final hasFightingPlayer =
            lane.playerCards.middleCards.aliveCards.isNotEmpty;
        final hasFightingOpponent =
            lane.opponentCards.middleCards.aliveCards.isNotEmpty;

        // Staging cards (baseCards) - shown at base rows when zone is elsewhere
        final hasStagingPlayer =
            lane.playerCards.baseCards.aliveCards.isNotEmpty;
        final hasStagingOpponent =
            lane.opponentCards.baseCards.aliveCards.isNotEmpty;

        // Cell content based on zone position
        String cell;
        if (row == zoneRow) {
          // This is the combat zone for this lane
          if (hasFightingPlayer && hasFightingOpponent) {
            cell = 'X'; // Combat!
          } else if (hasFightingPlayer) {
            cell = 'P';
          } else if (hasFightingOpponent) {
            cell = 'O';
          } else {
            cell = '·';
          }
        } else if (row == 0) {
          // Enemy base row - show staging cards if zone is not here
          cell = hasStagingOpponent ? 'O' : '·';
        } else if (row == 2) {
          // Player base row - show staging cards if zone is not here
          cell = hasStagingPlayer ? 'P' : '·';
        } else {
          // Middle row but zone is at a base - empty
          cell = '·';
        }

        // Add owner color indicator
        String ownerMark = '';
        if (tile.owner == TileOwner.player) {
          ownerMark = '▪'; // Player owned
        } else if (tile.owner == TileOwner.opponent) {
          ownerMark = '▫'; // Opponent owned
        }

        rowStr += ' $cell$ownerMark│';
      }

      // Add row labels
      final rowName = row == 0 ? 'Enemy' : (row == 1 ? 'Mid' : 'You');
      _log('$rowStr  $rowName');
      if (row < 2) _log('   ├───┼───┼───┤');
    }
    _log('   └───┴───┴───┘');
    _log(
      'Legend: P=Player cards, O=Opponent cards, X=Combat, ▪=PlayerOwned, ▫=OpponentOwned',
    );
  }

  /// Update tile ownership when zone advances.
  /// ONLY middle tiles (row 1) can be captured.
  /// Base tiles (row 0 & row 2) are NEVER captured.
  void _updateTileOwnership(
    int col,
    Zone newZone, {
    required bool isPlayerAdvancing,
  }) {
    if (_currentMatch == null) return;

    final board = _currentMatch!.board;

    // ONLY middle tiles can be captured
    // Base tiles NEVER change ownership
    if (newZone == Zone.middle) {
      final tile = board.getTile(1, col);
      final lanePos = [
        LanePosition.west,
        LanePosition.center,
        LanePosition.east,
      ][col];

      if (isPlayerAdvancing) {
        if (tile.owner != TileOwner.player) {
          tile.owner = TileOwner.player;
          _log('  🏴 Player captured ${tile.displayName}!');

          // Fog of war: reveal enemy base terrain for this lane
          if (!_currentMatch!.revealedEnemyBaseLanes.contains(lanePos)) {
            _currentMatch!.revealedEnemyBaseLanes.add(lanePos);
            final enemyBaseTile = board.getTile(0, col);
            _log(
              '  👁️ Enemy base terrain revealed: ${enemyBaseTile.terrain ?? "none"}',
            );
          }
        }
      } else {
        if (tile.owner != TileOwner.opponent) {
          tile.owner = TileOwner.opponent;
          _log('  🚩 Opponent captured ${tile.displayName}!');
        }
      }
    }
  }

  /// Advance to next turn (used after combat resolves when game not over)
  void _startNextTurn() {
    if (_currentMatch == null) return;

    _currentMatch!.currentPhase = MatchPhase.drawPhase;

    // Draw cards for both players
    _currentMatch!.player.drawCards();
    _currentMatch!.opponent.drawCards();

    // DON'T reset lanes - surviving cards persist across turns!
    // Zones and surviving cards remain in their positions.

    // Reset submissions for next turn
    _currentMatch!.resetSubmissions();

    // Reset temporary buffs from hero abilities
    _playerDamageBoostActive = false;

    // Increment turn
    _currentMatch!.turnNumber++;
    _currentMatch!.currentPhase = MatchPhase.turnPhase;
  }

  /// Get combat log entries for UI display
  List<dynamic> getCombatLog() {
    return _combatResolver.logEntries;
  }

  /// End current match
  void endMatch() {
    _currentMatch = null;
    _combatResolver.clearLog();
  }

  /// Debug helper: print a readable snapshot of the current game state.
  ///
  /// Shows turn, phase, player/opponent crystals and gold, and for each lane
  /// the current zone plus front/back cards on both sides.
  void printGameStateSnapshot() {
    final match = _currentMatch;
    if (match == null) {
      _log('No active match.');
      return;
    }

    _log('\n=== GAME STATE SNAPSHOT ===');
    _log('Turn ${match.turnNumber} | Phase: ${match.currentPhase}');
    _log(
      'Player: ${match.player.name} | Crystal: ${match.player.crystalHP} HP | '
      'Hand: ${match.player.hand.length} | Deck: ${match.player.deck.remainingCards} | '
      'Gold: ${match.player.gold}',
    );
    _log(
      'Opponent: ${match.opponent.name} | Crystal: ${match.opponent.crystalHP} HP | '
      'Hand: ${match.opponent.hand.length} | Deck: ${match.opponent.deck.remainingCards} | '
      'Gold: ${match.opponent.gold}',
    );

    for (final lane in match.lanes) {
      final laneLabel = lane.position.name.toUpperCase();
      _log('\nLane $laneLabel | Zone: ${lane.zoneDisplay}');

      final playerFront = lane.playerStack.topCard;
      final playerBack = lane.playerStack.bottomCard;
      final opponentFront = lane.opponentStack.topCard;
      final opponentBack = lane.opponentStack.bottomCard;

      String describeCard(GameCard? card) {
        if (card == null) return '—';
        return '${card.name} (HP: ${card.currentHealth}/${card.health}, '
            'DMG: ${card.damage}, T: ${card.tick}'
            '${card.element != null ? ', Terrain: ${card.element}' : ''})';
      }

      _log('  Player Front:  ${describeCard(playerFront)}');
      _log('  Player Back:   ${describeCard(playerBack)}');
      _log('  Opp Front:     ${describeCard(opponentFront)}');
      _log('  Opp Back:      ${describeCard(opponentBack)}');
    }

    _log('=== END GAME STATE SNAPSHOT ===\n');
  }

  void _log(String message) {
    // Always print for now (keeps existing debug behavior)
    // Simulations additionally capture logs via logSink.
    // ignore: avoid_print
    print(message);
    logSink?.writeln(message);
  }
}
