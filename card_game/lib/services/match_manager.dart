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
  }) {
    // Create players
    final player = Player(
      id: playerId,
      name: playerName,
      deck: playerDeck,
      isHuman: true,
    );

    final opponent = Player(
      id: opponentId,
      name: opponentName,
      deck: opponentDeck,
      isHuman: !opponentIsAI,
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
      for (final card in cards) {
        if (_currentMatch!.player.playCard(card)) {
          lane.playerStack.addCard(card);
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

  /// Callback for combat animation updates
  Function()? onCombatUpdate;

  /// Current tick information for UI display
  String? currentTickInfo;
  LanePosition? currentCombatLane;
  int? currentCombatTick;

  /// Resolve combat in all lanes with animations
  Future<void> _resolveCombat() async {
    if (_currentMatch == null) return;

    _currentMatch!.currentPhase = MatchPhase.combatPhase;

    // Clear previous combat log
    _combatResolver.clearLog();

    // Print turn header to terminal
    print('\n${'=' * 80}');
    print('TURN ${_currentMatch!.turnNumber} - COMBAT RESOLUTION');
    print('=' * 80);

    // Resolve each lane with tick-by-tick animation
    for (final lane in _currentMatch!.lanes) {
      if (lane.hasActiveCards) {
        await _resolveLaneAnimated(lane);
      }
    }

    // Print combat log to terminal
    print('\n--- BATTLE LOG ---');
    for (final entry in _combatResolver.logEntries) {
      print(entry.formattedMessage);
    }
    print('--- END BATTLE LOG ---\n');

    // Check if any cards damaged crystals (winning a lane means attacking crystal)
    _checkCrystalDamage();

    // Wait before showing final results
    await Future.delayed(const Duration(milliseconds: 800));
    onCombatUpdate?.call();

    // Print crystal damage
    print('Player Crystal: ${_currentMatch!.player.crystalHP} HP');
    print('Opponent Crystal: ${_currentMatch!.opponent.crystalHP} HP');
    print('=' * 80);

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

    // Initial delay to show combat starting
    await Future.delayed(const Duration(milliseconds: 300));
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

      // Show tick result before cleanup
      await Future.delayed(const Duration(milliseconds: 400));
      onCombatUpdate?.call();

      // Clean up dead cards
      lane.playerStack.cleanup();
      lane.opponentStack.cleanup();

      // Update UI after cleanup
      await Future.delayed(const Duration(milliseconds: 400));
      onCombatUpdate?.call();

      // Check if combat is over
      if (lane.playerStack.isEmpty || lane.opponentStack.isEmpty) {
        currentTickInfo = '🏁 Combat Complete!';
        break;
      }
    }

    // Final delay after lane completes
    await Future.delayed(const Duration(milliseconds: 500));
    currentTickInfo = null;
    currentCombatLane = null;
    currentCombatTick = null;
    onCombatUpdate?.call();
  }

  /// Check zone advancement and crystal damage
  void _checkCrystalDamage() {
    if (_currentMatch == null) return;

    print('\n--- ZONE ADVANCEMENT ---');

    for (final lane in _currentMatch!.lanes) {
      final playerWon = lane.playerWon;
      final laneName = lane.position.name.toUpperCase();

      if (playerWon == true) {
        // Player won lane - advance toward enemy base
        print('$laneName: Player victory! ${lane.zoneDisplay}');
        final reachedBase = lane.advanceZone(true);
        print('$laneName: Advanced to ${lane.zoneDisplay}');

        if (reachedBase) {
          // Reached enemy base - deal crystal damage
          final totalDamage = lane.playerStack.aliveCards.fold<int>(
            0,
            (sum, card) => sum + card.damage,
          );
          _currentMatch!.opponent.takeCrystalDamage(totalDamage);
          print('$laneName: 💥 $totalDamage crystal damage to AI!');
        }

        // Award gold for winning lane
        _currentMatch!.player.earnGold(400); // Tier capture gold
      } else if (playerWon == false) {
        // Opponent won lane - advance toward player base
        print('$laneName: AI victory! ${lane.zoneDisplay}');
        final reachedBase = lane.advanceZone(false);
        print('$laneName: Advanced to ${lane.zoneDisplay}');

        if (reachedBase) {
          // Reached player base - deal crystal damage
          final totalDamage = lane.opponentStack.aliveCards.fold<int>(
            0,
            (sum, card) => sum + card.damage,
          );
          _currentMatch!.player.takeCrystalDamage(totalDamage);
          print('$laneName: 💥 $totalDamage crystal damage to Player!');
        }

        _currentMatch!.opponent.earnGold(400);
      } else {
        print('$laneName: Draw - no advancement. ${lane.zoneDisplay}');
      }
    }
    print('--- END ZONE ADVANCEMENT ---\n');
  }

  /// Start the next turn
  void _startNextTurn() {
    if (_currentMatch == null) return;

    _currentMatch!.currentPhase = MatchPhase.drawPhase;

    // Draw cards
    _currentMatch!.player.drawCards();
    _currentMatch!.opponent.drawCards();

    // DON'T reset lanes - surviving cards persist across turns!
    // Zones and surviving cards remain in their positions
    // Players can add NEW cards (0-2 per lane, max 2 total stack)

    // Reset submissions
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
}
