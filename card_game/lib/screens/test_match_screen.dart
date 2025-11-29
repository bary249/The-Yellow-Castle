import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/lane.dart';
import '../models/card.dart';
import '../models/hero.dart';
import '../models/tile.dart';
import '../data/hero_library.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';
import '../services/auth_service.dart';
import '../services/deck_storage_service.dart';

/// Test screen for playing a match vs AI opponent or online multiplayer
class TestMatchScreen extends StatefulWidget {
  final GameHero? selectedHero;
  final String? onlineMatchId; // If provided, plays online multiplayer

  const TestMatchScreen({super.key, this.selectedHero, this.onlineMatchId});

  @override
  State<TestMatchScreen> createState() => _TestMatchScreenState();
}

class _TestMatchScreenState extends State<TestMatchScreen> {
  final MatchManager _matchManager = MatchManager();
  final SimpleAI _ai = SimpleAI();
  final AuthService _authService = AuthService();
  final DeckStorageService _deckStorage = DeckStorageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _playerId;
  String? _playerName;
  int? _playerElo;
  List<GameCard>? _savedDeck;

  // Staging area: cards placed on tiles before submitting
  // Key is "row,col" string (e.g., "2,0" for player base left)
  final Map<String, List<GameCard>> _stagedCards = {};

  GameCard? _selectedCard;

  // UI state: battle log drawer visibility
  bool _showBattleLog = false;

  // Online multiplayer state
  StreamSubscription? _matchListener;
  bool _isOnlineMode = false;
  bool _amPlayer1 = true;
  String? _opponentId;
  String? _opponentName;
  bool _mySubmitted = false;
  bool _opponentSubmitted = false;
  bool _waitingForOpponent = false;
  int _lastProcessedTurn = 0; // Track which turn we last processed

  /// Get the staging key for a tile.
  String _tileKey(int row, int col) => '$row,$col';

  /// Get staged cards for a specific tile.
  List<GameCard> _getStagedCards(int row, int col) {
    return _stagedCards[_tileKey(row, col)] ?? [];
  }

  @override
  void initState() {
    super.initState();
    _initPlayerAndMatch();
  }

  @override
  void dispose() {
    _matchListener?.cancel();
    super.dispose();
  }

  Future<void> _initPlayerAndMatch() async {
    // Use Firebase user if available
    final user = _authService.currentUser;
    if (user != null) {
      _playerId = user.uid;
      final profile = await _authService.getUserProfile(user.uid);
      _playerName = profile?['displayName'] as String? ?? 'Player';
      _playerElo = profile?['elo'] as int? ?? 1000;
    } else {
      _playerId = 'local_player';
      _playerName = 'Player';
      _playerElo = 1000;
    }

    // Load saved deck from Firebase
    _savedDeck = await _deckStorage.loadDeck();
    debugPrint('Loaded saved deck: ${_savedDeck?.length ?? 0} cards');

    // Check if online mode
    if (widget.onlineMatchId != null && _playerId != null) {
      _isOnlineMode = true;
      await _initOnlineMatch();
    } else {
      // VS AI mode
      if (mounted) {
        _startNewMatch();
      }
    }
  }

  /// Initialize online multiplayer match
  Future<void> _initOnlineMatch() async {
    if (widget.onlineMatchId == null || _playerId == null) return;

    try {
      // Get match data to determine which player we are
      final matchDoc = await _firestore
          .collection('matches')
          .doc(widget.onlineMatchId)
          .get();

      if (!matchDoc.exists) {
        _showError('Match not found');
        return;
      }

      final matchData = matchDoc.data()!;
      _amPlayer1 = matchData['player1']?['userId'] == _playerId;

      // Get opponent info
      final opponentData = _amPlayer1
          ? matchData['player2']
          : matchData['player1'];
      _opponentId = opponentData?['userId'] as String?;
      _opponentName = opponentData?['displayName'] as String? ?? 'Opponent';

      // Start the local match
      _startNewMatch();

      // Listen to Firebase match updates
      _listenToMatchUpdates();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing online match: $e');
      _showError('Failed to join match');
    }
  }

  /// Listen to Firebase match document updates
  void _listenToMatchUpdates() {
    if (widget.onlineMatchId == null) return;

    _matchListener = _firestore
        .collection('matches')
        .doc(widget.onlineMatchId)
        .snapshots()
        .listen((snapshot) {
          if (!mounted || !snapshot.exists) return;

          final data = snapshot.data()!;
          _handleMatchUpdate(data);
        });
  }

  /// Handle match state updates from Firebase
  void _handleMatchUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    final myKey = _amPlayer1 ? 'player1' : 'player2';
    final oppKey = _amPlayer1 ? 'player2' : 'player1';

    final myData = data[myKey] as Map<String, dynamic>?;
    final oppData = data[oppKey] as Map<String, dynamic>?;
    final currentTurn = data['turnNumber'] as int? ?? 1;

    final newMySubmitted = myData?['submitted'] == true;
    final newOppSubmitted = oppData?['submitted'] == true;

    // Only update state if something actually changed
    if (_mySubmitted != newMySubmitted ||
        _opponentSubmitted != newOppSubmitted) {
      setState(() {
        _mySubmitted = newMySubmitted;
        _opponentSubmitted = newOppSubmitted;
      });
    }

    // If both submitted and we haven't processed this turn yet
    if (newMySubmitted &&
        newOppSubmitted &&
        !_waitingForOpponent &&
        currentTurn > _lastProcessedTurn) {
      _lastProcessedTurn = currentTurn;
      _loadOpponentCardsAndResolveCombat(data);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _startNewMatch() {
    final id = _playerId ?? 'player1';
    final name = _playerName ?? 'You';

    // Use selected hero or default to Napoleon
    final playerHero = widget.selectedHero ?? HeroLibrary.napoleon();
    final aiHero = HeroLibrary.saladin(); // AI uses Saladin

    // Use saved deck if available, otherwise use starter deck
    final playerDeck = _savedDeck != null && _savedDeck!.isNotEmpty
        ? Deck.fromCards(playerId: id, cards: _savedDeck!)
        : Deck.starter(playerId: id);

    // Determine opponent name and deck
    final opponentNameFinal = _isOnlineMode
        ? (_opponentName ?? 'Opponent')
        : 'AI Opponent';
    final opponentIdFinal = _isOnlineMode ? (_opponentId ?? 'opponent') : 'ai';

    _matchManager.startMatch(
      playerId: id,
      playerName: name,
      playerDeck: playerDeck,
      opponentId: opponentIdFinal,
      opponentName: opponentNameFinal,
      opponentDeck: Deck.starter(playerId: opponentIdFinal),
      opponentIsAI: !_isOnlineMode,
      playerAttunedElement: playerHero.terrainAffinities.first,
      opponentAttunedElement: aiHero.terrainAffinities.first,
      playerHero: playerHero,
      opponentHero: aiHero,
    );
    _clearStaging();
    setState(() {});
  }

  void _clearStaging() {
    _stagedCards.clear();
    _selectedCard = null;
  }

  /// Place a card on a specific tile.
  /// Players can only stage on their base (row 2) or middle (row 1) tiles.
  void _placeCardOnTile(int row, int col) {
    final match = _matchManager.currentMatch;
    if (match == null || _selectedCard == null) return;

    final tile = match.getTile(row, col);
    final key = _tileKey(row, col);

    // Initialize list if needed
    _stagedCards[key] ??= [];

    // Cannot stage on enemy base row (row 0) even if captured
    if (row == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot stage cards on enemy base!')),
      );
      return;
    }

    // Check tile ownership - must be player-owned
    if (tile.owner != TileOwner.player) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You don\'t own this tile!')),
      );
      return;
    }

    // Get survivor count from lane (survivors are in lane stacks, not tile)
    final lanePos = [
      LanePosition.west,
      LanePosition.center,
      LanePosition.east,
    ][col];
    final lane = match.getLane(lanePos);

    // Map zone to row to check if survivors are on this tile
    int zoneToRow(Zone z) {
      switch (z) {
        case Zone.playerBase:
          return 2;
        case Zone.middle:
          return 1;
        case Zone.enemyBase:
          return 0;
      }
    }

    final currentZoneRow = zoneToRow(lane.currentZone);
    int survivorCount = 0;
    if (row == currentZoneRow) {
      // Survivors are on this tile - count player's cards only (can't place on opponent's)
      survivorCount = lane.playerStack.aliveCards.length;
    }

    // Check if tile already has 2 cards (survivors + staged)
    final stagedCount = _stagedCards[key]!.length;
    if (survivorCount + stagedCount >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tile is full (max 2 cards)!')),
      );
      return;
    }

    // Move card from hand to staging
    _stagedCards[key]!.add(_selectedCard!);
    _selectedCard = null;
    setState(() {});
  }

  /// Remove a card from a tile's staging area.
  void _removeCardFromTile(int row, int col, GameCard card) {
    final key = _tileKey(row, col);
    _stagedCards[key]?.remove(card);
    setState(() {});
  }

  Future<void> _submitTurn() async {
    final match = _matchManager.currentMatch;
    if (match == null) return;

    // Set up animation callback
    _matchManager.onCombatUpdate = () {
      if (mounted) setState(() {});
    };

    if (_isOnlineMode) {
      // Online mode: sync to Firebase
      await _submitOnlineTurn();
      // Don't clear staging yet - wait for combat to complete
    } else {
      // VS AI mode: resolve immediately
      await _submitVsAITurn();
      // Clear staging AFTER combat completes
      _clearStaging();
      if (mounted) setState(() {});
    }
  }

  /// Submit turn in online multiplayer mode
  Future<void> _submitOnlineTurn() async {
    if (widget.onlineMatchId == null || _playerId == null) return;

    try {
      // Convert staged cards to serializable format
      final stagedCardsData = <String, List<Map<String, dynamic>>>{};
      for (final entry in _stagedCards.entries) {
        stagedCardsData[entry.key] = entry.value.map((card) {
          return {
            'id': card.id,
            'name': card.name,
            'damage': card.damage,
            'health': card.health,
            'tick': card.tick,
            'element': card.element,
            'abilities': card.abilities,
            'cost': card.cost,
            'rarity': card.rarity,
          };
        }).toList();
      }

      // Upload my placements to Firebase
      final myKey = _amPlayer1 ? 'player1' : 'player2';
      await _firestore.collection('matches').doc(widget.onlineMatchId).update({
        '$myKey.submitted': true,
        '$myKey.stagedCards': stagedCardsData,
      });

      setState(() {
        _mySubmitted = true;
        _waitingForOpponent = true;
      });

      debugPrint('Submitted turn to Firebase');
    } catch (e) {
      debugPrint('Error submitting online turn: $e');
      _showError('Failed to submit turn');
    }
  }

  /// Submit turn in vs AI mode
  Future<void> _submitVsAITurn() async {
    final match = _matchManager.currentMatch;
    if (match == null) return;

    // Submit player moves using new tile-based system
    await _matchManager.submitPlayerTileMoves(_stagedCards);

    // AI makes its moves (tile-based, can place on captured middle tiles)
    final aiMoves = _ai.generateTileMoves(
      match.opponent,
      match.board,
      match.lanes,
      isOpponent: true,
    );
    await _matchManager.submitOpponentTileMoves(aiMoves);
  }

  /// Load opponent cards from Firebase and resolve combat
  Future<void> _loadOpponentCardsAndResolveCombat(
    Map<String, dynamic> matchData,
  ) async {
    if (!mounted) return;

    // Prevent re-entry
    if (_waitingForOpponent) {
      debugPrint('Already processing combat, skipping');
      return;
    }

    setState(() {
      _waitingForOpponent = true;
    });

    try {
      debugPrint('Processing combat for turn ${matchData['turnNumber']}');

      // Get opponent's staged cards
      final oppKey = _amPlayer1 ? 'player2' : 'player1';
      final oppData = matchData[oppKey] as Map<String, dynamic>?;
      final oppStagedData = oppData?['stagedCards'] as Map<String, dynamic>?;

      if (oppStagedData == null || oppStagedData.isEmpty) {
        debugPrint('No opponent staged cards found');
        setState(() {
          _waitingForOpponent = false;
        });
        return;
      }

      // Convert opponent's cards from Firebase format
      final opponentMoves = <String, List<GameCard>>{};
      for (final entry in oppStagedData.entries) {
        final cardsList = entry.value as List<dynamic>;
        opponentMoves[entry.key] = cardsList.map((cardData) {
          final data = cardData as Map<String, dynamic>;
          return GameCard(
            id: data['id'] as String,
            name: data['name'] as String,
            damage: data['damage'] as int,
            health: data['health'] as int,
            tick: data['tick'] as int,
            element: data['element'] as String?,
            abilities: (data['abilities'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList(),
            cost: data['cost'] as int? ?? 0,
            rarity: data['rarity'] as int? ?? 1,
          );
        }).toList();
      }

      // Submit player's staged cards
      await _matchManager.submitPlayerTileMoves(_stagedCards);

      // Submit opponent's cards
      await _matchManager.submitOpponentTileMoves(opponentMoves);

      // Only player1 updates Firebase to avoid conflicts
      if (_amPlayer1) {
        final myKey = 'player1';
        final newTurnNumber = (matchData['turnNumber'] as int? ?? 1) + 1;

        await _firestore
            .collection('matches')
            .doc(widget.onlineMatchId)
            .update({
              'turnNumber': newTurnNumber,
              '$myKey.submitted': false,
              '$oppKey.submitted': false,
              '$myKey.stagedCards': {},
              '$oppKey.stagedCards': {},
            });
      }

      // Clear local staging
      _clearStaging();

      if (mounted) {
        setState(() {
          _mySubmitted = false;
          _opponentSubmitted = false;
          _waitingForOpponent = false;
        });
      }

      debugPrint('Combat resolved for online match');
    } catch (e) {
      debugPrint('Error loading opponent cards: $e');
      _showError('Failed to load opponent moves');
      if (mounted) {
        setState(() {
          _waitingForOpponent = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = _matchManager.currentMatch;

    if (match == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Test Match')),
        body: const Center(child: Text('No match in progress')),
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // ENTER: Skip all remaining ticks instantly (combat auto-advances otherwise)
        if (event is KeyDownEvent &&
            match.currentPhase == MatchPhase.combatPhase &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          _matchManager.skipToEnd();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Turn ${match.turnNumber} - ${match.currentPhase.name}'),
          actions: [
            if (match.isGameOver)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _startNewMatch,
              ),
            if (!match.isGameOver && !match.playerSubmitted)
              IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: () {
                  _clearStaging();
                  setState(() {});
                },
                tooltip: 'Clear all placements',
              ),
          ],
        ),
        body: match.isGameOver ? _buildGameOver(match) : _buildMatchView(match),
        floatingActionButton: match.currentPhase == MatchPhase.combatPhase
            // During combat: show skip button (combat auto-advances, but ENTER skips all)
            ? FloatingActionButton.extended(
                onPressed: () => _matchManager.skipToEnd(),
                label: const Text('Skip Combat (ENTER)'),
                icon: const Icon(Icons.fast_forward),
                backgroundColor: Colors.red[700],
                heroTag: 'skip',
              )
            : _buildSubmitButton(match),
      ),
    );
  }

  Widget? _buildSubmitButton(MatchState match) {
    if (match.isGameOver) return null;

    // Online mode: show waiting state
    if (_isOnlineMode) {
      if (_waitingForOpponent) {
        return FloatingActionButton.extended(
          onPressed: null,
          label: const Text('Waiting for opponent...'),
          icon: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          backgroundColor: Colors.grey,
        );
      } else if (_mySubmitted) {
        return FloatingActionButton.extended(
          onPressed: null,
          label: const Text('Turn Submitted'),
          icon: const Icon(Icons.check),
          backgroundColor: Colors.green[700],
        );
      }
    }

    // Show submit button if not yet submitted
    if (!match.playerSubmitted) {
      return FloatingActionButton.extended(
        onPressed: _submitTurn,
        label: Text(_isOnlineMode ? 'Submit Turn' : 'Submit Turn'),
        icon: const Icon(Icons.send),
      );
    }

    return null;
  }

  Widget _buildGameOver(MatchState match) {
    final winner = match.winner;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            winner?.id == match.player.id ? Icons.emoji_events : Icons.close,
            size: 100,
            color: winner?.id == match.player.id ? Colors.amber : Colors.red,
          ),
          const SizedBox(height: 20),
          Text(
            winner?.id == match.player.id ? 'Victory!' : 'Defeat',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          Text('${winner?.name} wins!'),
          const SizedBox(height: 20),
          Text('Player Crystal: ${match.player.crystalHP} HP'),
          Text('Opponent Crystal: ${match.opponent.crystalHP} HP'),
          const SizedBox(height: 20),
          Text('Total Turns: ${match.turnNumber}'),
        ],
      ),
    );
  }

  Widget _buildMatchView(MatchState match) {
    return Stack(
      children: [
        // Main content
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Account header (Firebase player info)
            _buildAccountHeader(),
            const SizedBox(height: 8),

            Expanded(
              child: Column(
                children: [
                  // Opponent info
                  _buildPlayerInfo(match.opponent, isOpponent: true),

                  const SizedBox(height: 4),

                  // Combat phase indicator with enhanced details
                  if (match.currentPhase == MatchPhase.combatPhase)
                    _buildCombatBanner(),

                  // Lane tick clocks (show during combat)
                  if (match.currentPhase == MatchPhase.combatPhase)
                    _buildLaneTickClocks(),

                  // Instructions
                  if (_selectedCard != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.amber[100],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.touch_app, size: 16),
                          const SizedBox(width: 8),
                          Text('Click a lane to place ${_selectedCard!.name}'),
                        ],
                      ),
                    ),

                  // 3×3 Board Grid
                  Expanded(child: _buildBoard(match)),

                  // Player info
                  _buildPlayerInfo(match.player, isOpponent: false),

                  // Hand
                  _buildHand(match.player),
                ],
              ),
            ),
          ],
        ),

        // Battle log toggle button
        Positioned(
          right: 0,
          top: 100,
          child: GestureDetector(
            onTap: () => setState(() => _showBattleLog = !_showBattleLog),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showBattleLog ? Icons.chevron_right : Icons.chevron_left,
                    color: Colors.white,
                    size: 20,
                  ),
                  const RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'Battle Log',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Sliding battle log drawer
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          right: _showBattleLog ? 0 : -250,
          top: 0,
          bottom: 0,
          child: _buildBattleLogDrawer(),
        ),
      ],
    );
  }

  /// Build the combat banner with detailed tick info
  Widget _buildCombatBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red[700]!, Colors.orange[600]!],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Combat header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.flash_on, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                _matchManager.currentCombatLane != null
                    ? '⚔️ ${_matchManager.currentCombatLane!.name.toUpperCase()} LANE ⚔️'
                    : '⚔️ COMBAT IN PROGRESS ⚔️',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.flash_on, color: Colors.white, size: 20),
            ],
          ),

          // Tick info
          if (_matchManager.currentTickInfo != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _matchManager.currentTickInfo!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // Detailed combat results
          if (_matchManager.currentTickDetails.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: _matchManager.currentTickDetails.map((detail) {
                final isDestroyed = detail.contains('DESTROYED');
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDestroyed ? Colors.red[900] : Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                    border: isDestroyed
                        ? Border.all(color: Colors.red[300]!, width: 1)
                        : null,
                  ),
                  child: Text(
                    detail,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: isDestroyed
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Build the lane tick clocks showing 1-5 ticks per lane
  Widget _buildLaneTickClocks() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSingleLaneTickClock('WEST', LanePosition.west),
          _buildSingleLaneTickClock('CENTER', LanePosition.center),
          _buildSingleLaneTickClock('EAST', LanePosition.east),
        ],
      ),
    );
  }

  Widget _buildSingleLaneTickClock(String label, LanePosition lane) {
    final currentTick = _matchManager.laneTickProgress[lane] ?? 0;
    final isActive = _matchManager.currentCombatLane == lane;
    final isComplete = currentTick >= 6;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.orange : Colors.grey[400],
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final tickNum = index + 1;
            final isPast = tickNum < currentTick;
            final isCurrent = tickNum == currentTick;

            Color tickColor;
            if (isComplete) {
              tickColor = Colors.green;
            } else if (isCurrent && isActive) {
              tickColor = Colors.orange;
            } else if (isPast) {
              tickColor = Colors.green[700]!;
            } else {
              tickColor = Colors.grey[600]!;
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: isCurrent && isActive ? 20 : 14,
              height: isCurrent && isActive ? 20 : 14,
              decoration: BoxDecoration(
                color: tickColor,
                shape: BoxShape.circle,
                border: isCurrent && isActive
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: isCurrent && isActive
                    ? [
                        BoxShadow(
                          color: Colors.orange.withAlpha(153),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '$tickNum',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isCurrent && isActive ? 10 : 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        ),
        if (isComplete)
          const Text('✓', style: TextStyle(color: Colors.green, fontSize: 12)),
      ],
    );
  }

  Widget _buildAccountHeader() {
    final name = _playerName ?? 'Player';
    final elo = _playerElo ?? 1000;
    final id = _playerId ?? 'local';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey[900],
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'ELO $elo',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          Flexible(
            child: Text(
              'UID: ${id.length > 8 ? id.substring(0, 8) : id}',
              style: const TextStyle(color: Colors.white60, fontSize: 10),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerInfo(player, {required bool isOpponent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isOpponent ? Colors.red[50] : Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isOpponent ? Icons.smart_toy : Icons.person,
                color: isOpponent ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                player.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isOpponent ? Colors.red[700] : Colors.blue[700],
                ),
              ),
              // Show hero info
              if (player.hero != null) ...[
                const SizedBox(width: 8),
                Text(
                  '(${player.hero!.name})',
                  style: TextStyle(
                    fontSize: 11,
                    color: isOpponent ? Colors.red[400] : Colors.blue[400],
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              // Hero ability button (player only)
              if (!isOpponent && player.hero != null) ...[
                _buildHeroAbilityButton(player.hero!),
                const SizedBox(width: 12),
              ],
              const Icon(Icons.favorite, color: Colors.pink, size: 18),
              const SizedBox(width: 4),
              Text(
                '${player.crystalHP} HP',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text('${player.gold}'),
              const SizedBox(width: 16),
              if (player.attunedElement != null) ...[
                const Icon(Icons.terrain, size: 16, color: Colors.brown),
                const SizedBox(width: 4),
                Text(
                  'Base: ${player.attunedElement}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroAbilityButton(GameHero hero) {
    final canUse = _matchManager.canUsePlayerHeroAbility;

    return Tooltip(
      message: hero.abilityDescription,
      child: ElevatedButton.icon(
        onPressed: canUse
            ? () {
                final success = _matchManager.activatePlayerHeroAbility();
                if (success) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '🦸 ${hero.name}: ${hero.abilityDescription}',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            : null,
        icon: Icon(
          hero.abilityUsed ? Icons.check_circle : Icons.flash_on,
          size: 16,
        ),
        label: Text(
          hero.abilityUsed ? 'USED' : 'ABILITY',
          style: const TextStyle(fontSize: 10),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: hero.abilityUsed
              ? Colors.grey
              : (canUse ? Colors.amber : Colors.grey[400]),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 28),
        ),
      ),
    );
  }

  /// Build the 3×3 board grid.
  Widget _buildBoard(MatchState match) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          // Row 0: Opponent base
          Expanded(
            child: Row(
              children: [
                for (int col = 0; col < 3; col++)
                  Expanded(child: _buildTile(match, 0, col)),
              ],
            ),
          ),
          // Row 1: Middle
          Expanded(
            child: Row(
              children: [
                for (int col = 0; col < 3; col++)
                  Expanded(child: _buildTile(match, 1, col)),
              ],
            ),
          ),
          // Row 2: Player base
          Expanded(
            child: Row(
              children: [
                for (int col = 0; col < 3; col++)
                  Expanded(child: _buildTile(match, 2, col)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single tile widget.
  Widget _buildTile(MatchState match, int row, int col) {
    final tile = match.getTile(row, col);
    final stagedCardsOnTile = _getStagedCards(row, col);

    // Get lane for this column to check zone and get survivor cards
    final lanePos = [
      LanePosition.west,
      LanePosition.center,
      LanePosition.east,
    ][col];
    final lane = match.getLane(lanePos);

    // Get cards at this tile based on position (using new positional system)
    List<GameCard> playerCardsAtTile = [];
    List<GameCard> opponentCardsAtTile = [];

    // Fog of war: check if this lane's enemy base is revealed
    final isEnemyBaseRevealed = match.revealedEnemyBaseLanes.contains(lanePos);

    // Track if cards are hidden by fog of war
    int hiddenCardCount = 0;

    if (row == 0) {
      // Enemy base - fog of war: only show cards if lane is revealed
      if (isEnemyBaseRevealed) {
        opponentCardsAtTile = lane.opponentCards.baseCards.aliveCards;
      } else {
        // Cards hidden by fog of war
        hiddenCardCount = lane.opponentCards.baseCards.aliveCards.length;
      }
    } else if (row == 1) {
      // Middle - show both sides' middle cards
      playerCardsAtTile = lane.playerCards.middleCards.aliveCards;
      opponentCardsAtTile = lane.opponentCards.middleCards.aliveCards;
    } else if (row == 2) {
      // Player base - show player's base cards
      playerCardsAtTile = lane.playerCards.baseCards.aliveCards;
    }

    // Count existing cards for placement check (only player cards count for placement)
    final existingPlayerCount = playerCardsAtTile.length;

    // Can place on player-owned tiles with room, but NOT enemy base (row 0)
    final isPlayerOwned = tile.owner == TileOwner.player;
    final isNotEnemyBase =
        row != 0; // Cannot stage on enemy base even if captured
    final stagedCount = stagedCardsOnTile.length;
    final canPlace =
        isPlayerOwned &&
        isNotEnemyBase &&
        _selectedCard != null &&
        (existingPlayerCount + stagedCount) < 2;

    // Determine tile color based on owner and terrain
    Color bgColor;
    if (tile.owner == TileOwner.player) {
      bgColor = Colors.blue[50]!;
    } else if (tile.owner == TileOwner.opponent) {
      bgColor = Colors.red[50]!;
    } else {
      bgColor = Colors.grey[100]!;
    }

    // Check if opponent's front card has conceal_back ability
    // If so, we'll hide the back card's identity from the player
    bool opponentBackCardConcealed = false;
    if (opponentCardsAtTile.length >= 2) {
      final frontCard = opponentCardsAtTile[0]; // First card is front (topCard)
      if (frontCard.abilities.contains('conceal_back')) {
        opponentBackCardConcealed = true;
      }
    }

    // Build card display list with position labels
    // Visual order (top to bottom on screen):
    // - Opponent BACK (if exists) - furthest from player
    // - Opponent FRONT - advancing toward player
    // - Player FRONT - advancing toward enemy
    // - Player BACK (if exists) - behind player front
    // - Staged cards - new placements

    // Reverse opponent cards so FRONT is closer to player (bottom of opponent section)
    final opponentCardsReversed = opponentCardsAtTile.reversed.toList();

    List<GameCard> cardsToShow = [
      ...opponentCardsReversed, // Enemy BACK first (top), then FRONT (toward player)
      ...playerCardsAtTile, // Player FRONT first, then BACK
      ...stagedCardsOnTile, // Player staged cards at BOTTOM
    ];

    return GestureDetector(
      onTap: canPlace ? () => _placeCardOnTile(row, col) : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: canPlace ? Colors.green : Colors.grey[400]!,
            width: canPlace ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Terrain tag (with fog of war for enemy base)
              if (tile.terrain != null)
                Builder(
                  builder: (context) {
                    // Fog of war: check if enemy base terrain is revealed
                    final isEnemyBase = row == 0;
                    final lanePos = [
                      LanePosition.west,
                      LanePosition.center,
                      LanePosition.east,
                    ][col];
                    final isRevealed = match.revealedEnemyBaseLanes.contains(
                      lanePos,
                    );
                    final showTerrain = !isEnemyBase || isRevealed;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: showTerrain
                            ? _getTerrainColor(tile.terrain!)
                            : Colors.grey[600],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        showTerrain ? tile.terrain! : '???',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 2),

              // Cards on this tile
              if (cardsToShow.isEmpty)
                Text(
                  row == 1 ? 'Middle' : tile.shortName,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                )
              else
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    children: cardsToShow.map((card) {
                      final isStaged = stagedCardsOnTile.contains(card);
                      final isOpponent = opponentCardsAtTile.contains(card);
                      final isPlayerCard = playerCardsAtTile.contains(card);

                      // Determine position label (FRONT/BACK)
                      String? positionLabel;
                      bool isFrontCard = false;

                      if (isOpponent && opponentCardsAtTile.isNotEmpty) {
                        // For opponent: index 0 in original list is FRONT
                        final originalIndex = opponentCardsAtTile.indexOf(card);
                        isFrontCard = originalIndex == 0;
                        if (opponentCardsAtTile.length > 1) {
                          positionLabel = isFrontCard ? '▼ FRONT' : '▲ BACK';
                        } else {
                          positionLabel = '▼ FRONT';
                        }
                      } else if (isPlayerCard && playerCardsAtTile.isNotEmpty) {
                        // For player: index 0 in list is FRONT
                        final idx = playerCardsAtTile.indexOf(card);
                        isFrontCard = idx == 0;
                        if (playerCardsAtTile.length > 1) {
                          positionLabel = isFrontCard ? '▲ FRONT' : '▼ BACK';
                        } else {
                          positionLabel = '▲ FRONT';
                        }
                      } else if (isStaged) {
                        positionLabel = '📦 STAGED';
                      }

                      // Check if this is the opponent's back card and it's concealed
                      final isOpponentBackCard =
                          isOpponent &&
                          opponentCardsAtTile.length >= 2 &&
                          opponentCardsAtTile.indexOf(card) == 1;
                      final isConcealed =
                          isOpponentBackCard && opponentBackCardConcealed;

                      // Determine card color
                      Color cardColor;
                      Color labelColor;
                      if (isStaged) {
                        cardColor = Colors.amber[100]!;
                        labelColor = Colors.orange[800]!;
                      } else if (isOpponent) {
                        cardColor = isConcealed
                            ? Colors.grey[400]!
                            : Colors.red[200]!;
                        labelColor = Colors.red[800]!;
                      } else if (isPlayerCard) {
                        cardColor = Colors.blue[200]!;
                        labelColor = Colors.blue[800]!;
                      } else {
                        cardColor = Colors.grey[200]!;
                        labelColor = Colors.grey[600]!;
                      }

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(4),
                          border: isStaged
                              ? Border.all(color: Colors.amber, width: 2)
                              : (isFrontCard
                                    ? Border.all(
                                        color: isOpponent
                                            ? Colors.red
                                            : Colors.blue,
                                        width: 2,
                                      )
                                    : (isConcealed
                                          ? Border.all(
                                              color: Colors.grey[600]!,
                                              width: 1,
                                            )
                                          : Border.all(
                                              color: isOpponent
                                                  ? Colors.red[300]!
                                                  : Colors.blue[300]!,
                                              width: 1,
                                            ))),
                        ),
                        child: isConcealed
                            // Show hidden card placeholder
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    positionLabel ?? '',
                                    style: TextStyle(
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const Text(
                                    '🔮 Hidden',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              )
                            // Show normal card info with position label
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Position label row
                                  if (positionLabel != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 1,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 2),
                                      decoration: BoxDecoration(
                                        color: labelColor.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        positionLabel,
                                        style: TextStyle(
                                          fontSize: 7,
                                          fontWeight: FontWeight.bold,
                                          color: labelColor,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    card.name,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '⚔${card.damage}',
                                        style: const TextStyle(fontSize: 8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '❤${card.currentHealth}/${card.health}',
                                        style: const TextStyle(fontSize: 8),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTerrainColor(String terrain) {
    switch (terrain.toLowerCase()) {
      case 'woods':
        return Colors.green[700]!;
      case 'lake':
        return Colors.blue[700]!;
      case 'desert':
        return Colors.orange[700]!;
      case 'marsh':
        return Colors.teal[700]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Widget _buildBattleLogDrawer() {
    final log = _matchManager.getCombatLog();

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(-3, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: Colors.grey[800],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📜 Battle Log',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showBattleLog = false),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // Log entries
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Text(
                      'No combat yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: log.length,
                    reverse: false,
                    itemBuilder: (context, index) {
                      final entry = log[index];
                      final hasDetails = entry.damageDealt != null;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey[800]!,
                              width: 0.5,
                            ),
                          ),
                          color: entry.isImportant
                              ? Colors.red[900]!.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row: lane + tick
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[700],
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    entry.laneDescription,
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'T${entry.tick}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.orange[300],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),

                            // Action (shortened version)
                            Text(
                              entry.action,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: entry.isImportant
                                    ? Colors.red[300]
                                    : Colors.white,
                              ),
                            ),

                            // Combat details if available
                            if (hasDetails) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${entry.damageDealt} dmg',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange[200],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${entry.targetHpBefore} → ${entry.targetHpAfter} HP',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: entry.targetDied == true
                                          ? Colors.red[300]
                                          : Colors.green[300],
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (entry.details.isNotEmpty) ...[
                              Text(
                                entry.details,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[400],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHand(player) {
    // Calculate available cards (not yet staged)
    final stagedCardSet = _stagedCards.values.expand((list) => list).toSet();
    final availableCards = player.hand
        .where((card) => !stagedCardSet.contains(card))
        .toList();

    return Container(
      height: 140,
      padding: const EdgeInsets.all(8),
      color: Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Hand (${availableCards.length} cards)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: availableCards.isEmpty
                ? const Center(
                    child: Text('No cards available (check staged cards)'),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: availableCards.length,
                    itemBuilder: (context, index) {
                      final card = availableCards[index];
                      final isSelected = _selectedCard == card;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCard = isSelected ? null : card;
                          });
                        },
                        child: Container(
                          width: 90,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.green[200]
                                : Colors.white,
                            border: Border.all(
                              color: isSelected ? Colors.green : Colors.grey,
                              width: isSelected ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.green.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                card.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'HP: ${card.health}',
                                style: const TextStyle(fontSize: 8),
                              ),
                              Text(
                                'DMG: ${card.damage}',
                                style: const TextStyle(fontSize: 8),
                              ),
                              Text(
                                'Tick: ${card.tick}',
                                style: const TextStyle(fontSize: 8),
                              ),
                              if (card.element != null)
                                Text(
                                  'Elem: ${card.element}',
                                  style: const TextStyle(fontSize: 7),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (card.abilities.isNotEmpty)
                                Text(
                                  card.abilities.join(', '),
                                  style: const TextStyle(fontSize: 6),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (isSelected)
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.touch_app,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
