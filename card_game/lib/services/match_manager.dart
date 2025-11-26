import '../models/match_state.dart';
import '../models/player.dart';
import '../models/deck.dart';
import '../models/lane.dart';
import '../models/card.dart';
import 'combat_resolver.dart';

/// Coordinates the entire match flow
class MatchManager {
  MatchState? _currentMatch;
  final CombatResolver _combatResolver = CombatResolver();

  MatchState? get currentMatch => _currentMatch;

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
  }) {
    // Create players
    final player = Player(
      id: playerId,
      name: playerName,
      deck: playerDeck,
      isHuman: true,
      attunedElement: playerAttunedElement,
    );

    final opponent = Player(
      id: opponentId,
      name: opponentName,
      deck: opponentDeck,
      isHuman: !opponentIsAI,
      attunedElement: opponentAttunedElement,
    );

    // Shuffle decks
    player.deck.shuffle();
    opponent.deck.shuffle();

    // Create match state
    _currentMatch = MatchState(player: player, opponent: opponent);

    // Draw initial hands
    player.drawInitialHand();
    opponent.drawInitialHand();

    // Start first turn
    _currentMatch!.currentPhase = MatchPhase.turnPhase;
    _currentMatch!.turnNumber = 1;
  }

  /// Player submits their card placements for the turn
  Future<void> submitPlayerMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.playerSubmitted) return;

    // Place cards in lanes
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      // Remove cards from hand and place in lane
      // Fresh cards ALWAYS go to bottom if there are survivors
      for (final card in cards) {
        if (_currentMatch!.player.playCard(card)) {
          // If lane has survivors, place new card at bottom
          final hasSurvivors = lane.playerStack.topCard != null;
          lane.playerStack.addCard(card, asTopCard: !hasSurvivors);
        }
      }
    }

    _currentMatch!.playerSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Opponent (AI) submits their moves
  Future<void> submitOpponentMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards in lanes
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        if (_currentMatch!.opponent.playCard(card)) {
          lane.opponentStack.addCard(card);
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

    // Place cards directly in lanes (no hand check for online opponent)
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        // Add directly to opponent stack - these are reconstructed from Firebase
        lane.opponentStack.addCard(card);
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

  /// Optional log sink used by simulations to capture full battle logs.
  /// When set, all combat-related print output is also written here.
  StringBuffer? logSink;

  /// Manual tick progression control
  bool waitingForNextTick = false;
  bool skipAllTicks = false;
  bool autoProgress = false; // Auto-progress with delays (for online mode)
  bool fastMode = false; // When true, skip delays (for simulations)
  Function()? onWaitingForTick;

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

    // Clear previous combat log
    _combatResolver.clearLog();

    // Print turn header to terminal
    _log('\n${'=' * 80}');
    _log('TURN ${_currentMatch!.turnNumber} - COMBAT RESOLUTION');
    _log('=' * 80);

    // Resolve each lane with tick-by-tick animation
    for (final lane in _currentMatch!.lanes) {
      if (lane.hasActiveCards) {
        await _resolveLaneAnimated(lane);
      }
    }

    // Print combat log to terminal
    _log('\n--- BATTLE LOG ---');
    for (final entry in _combatResolver.logEntries) {
      _log(entry.formattedMessage);
    }
    _log('--- END BATTLE LOG ---\n');

    // Check if any cards damaged crystals (winning a lane means attacking crystal)
    _checkCrystalDamage();

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

    // Provide lane/attunement context to the combat resolver so it can
    // apply base-zone buffs for matching elements.
    if (_currentMatch != null) {
      _combatResolver.setLaneContext(
        zone: lane.currentZone,
        playerBaseElement: _currentMatch!.player.attunedElement,
        opponentBaseElement: _currentMatch!.opponent.attunedElement,
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
      currentTickInfo = 'Tick $tick: Processing...';

      // Count log entries before this tick
      final logCountBefore = _combatResolver.logEntries.length;

      // Resolve this tick
      _combatResolver.processTickInLane(tick, lane);

      // Get new log entries from this tick
      final newEntries = _combatResolver.logEntries
          .skip(logCountBefore)
          .toList();
      final tickActions = newEntries
          .where((e) => e.tick == tick && e.action.contains('→'))
          .map((e) => e.action)
          .join(' | ');

      currentTickInfo = tickActions.isNotEmpty
          ? 'Tick $tick: $tickActions'
          : 'Tick $tick: No actions';

      // Wait for user to advance tick (unless skipping all or auto-progressing)
      if (autoProgress) {
        // Auto-progress: show tick, then continue (optionally with delay)
        onCombatUpdate?.call();
        if (!fastMode) {
          await Future.delayed(const Duration(seconds: 2));
        }
      } else if (!skipAllTicks) {
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
      if (autoProgress || !skipAllTicks) {
        onCombatUpdate?.call();
      }

      // Check if combat is over
      if (lane.playerStack.isEmpty || lane.opponentStack.isEmpty) {
        currentTickInfo = '🏁 Combat Complete!';
        break;
      }
    }

    // Final delay after lane completes (skip in fast/sim mode)
    if (!fastMode) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    currentTickInfo = null;
    currentCombatLane = null;
    currentCombatTick = null;
    onCombatUpdate?.call();
  }

  /// Check zone advancement and crystal damage
  void _checkCrystalDamage() {
    if (_currentMatch == null) return;

    _log('\n--- ZONE ADVANCEMENT ---');

    for (final lane in _currentMatch!.lanes) {
      final playerWon = lane.playerWon;
      final laneName = lane.position.name.toUpperCase();

      if (playerWon == true) {
        // Player won lane - advance toward enemy base
        _log('$laneName: Player victory! ${lane.zoneDisplay}');
        final reachedBase = lane.advanceZone(true);
        _log('$laneName: Advanced to ${lane.zoneDisplay}');

        if (reachedBase) {
          // Reached enemy base - deal crystal damage
          final totalDamage = lane.playerStack.aliveCards.fold<int>(
            0,
            (sum, card) => sum + card.damage,
          );
          _currentMatch!.opponent.takeCrystalDamage(totalDamage);
          _log(
            '$laneName: 💥 ${totalDamage.toStringAsFixed(0)} crystal damage to AI!',
          );
        }

        // Award gold for winning lane
        _currentMatch!.player.earnGold(400); // Tier capture gold
      } else if (playerWon == false) {
        // Opponent won lane - advance toward player base
        _log('$laneName: AI victory! ${lane.zoneDisplay}');
        final reachedBase = lane.advanceZone(false);
        _log('$laneName: Advanced to ${lane.zoneDisplay}');

        if (reachedBase) {
          // Reached player base - deal crystal damage
          final totalDamage = lane.opponentStack.aliveCards.fold<int>(
            0,
            (sum, card) => sum + card.damage,
          );
          _currentMatch!.player.takeCrystalDamage(totalDamage);
          _log(
            '$laneName: 💥 ${totalDamage.toStringAsFixed(0)} crystal damage to Player!',
          );
        }

        // Award gold for winning lane
        _currentMatch!.opponent.earnGold(400);
      } else {
        // Draw - no advancement
        _log('$laneName: Draw - no advancement. ${lane.zoneDisplay}');
      }
    }

    _log('--- END ZONE ADVANCEMENT ---');
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
            '${card.element != null ? ', ${card.element}' : ''})';
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
