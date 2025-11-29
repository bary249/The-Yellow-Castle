import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

/// Simple test screen to verify game logic with drag-and-drop card placement
class TestMatchScreen extends StatefulWidget {
  /// Optional hero selected before the match. If null, uses default (Napoleon).
  final GameHero? selectedHero;

  const TestMatchScreen({super.key, this.selectedHero});

  @override
  State<TestMatchScreen> createState() => _TestMatchScreenState();
}

class _TestMatchScreenState extends State<TestMatchScreen> {
  final MatchManager _matchManager = MatchManager();
  final SimpleAI _ai = SimpleAI();
  final AuthService _authService = AuthService();
  final DeckStorageService _deckStorage = DeckStorageService();

  String? _playerId;
  String? _playerName;
  int? _playerElo;
  List<GameCard>? _savedDeck;

  // Staging area: cards placed on tiles before submitting
  // Key is "row,col" string (e.g., "2,0" for player base left)
  final Map<String, List<GameCard>> _stagedCards = {};

  GameCard? _selectedCard;

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

    if (mounted) {
      _startNewMatch();
    }
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

    _matchManager.startMatch(
      playerId: id,
      playerName: name,
      playerDeck: playerDeck,
      opponentId: 'ai',
      opponentName: 'AI Opponent',
      opponentDeck: Deck.starter(playerId: 'ai'),
      opponentIsAI: true,
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

    // Check if any cards were placed
    final totalPlaced = _stagedCards.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    // Set up animation callback
    _matchManager.onCombatUpdate = () {
      if (mounted) setState(() {});
    };

    // Submit player moves using new tile-based system
    // _stagedCards is already keyed by "row,col"
    await _matchManager.submitPlayerTileMoves(_stagedCards);

    // AI makes its moves (tile-based, can place on captured middle tiles)
    final aiMoves = _ai.generateTileMoves(
      match.opponent,
      match.board,
      match.lanes,
      isOpponent: true,
    );
    await _matchManager.submitOpponentTileMoves(aiMoves);

    // Clear staging AFTER combat completes
    _clearStaging();
    if (mounted) setState(() {});
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
        if (event is KeyDownEvent && _matchManager.waitingForNextTick) {
          // SPACE: Advance one tick at a time
          if (event.logicalKey == LogicalKeyboardKey.space) {
            _matchManager.advanceToNextTick();
            return KeyEventResult.handled;
          }
          // ENTER: Skip all remaining ticks instantly
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            _matchManager.skipToEnd();
            return KeyEventResult.handled;
          }
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
        floatingActionButton: _matchManager.waitingForNextTick
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    onPressed: () => _matchManager.skipToEnd(),
                    label: const Text('Skip All (ENTER)'),
                    icon: const Icon(Icons.fast_forward),
                    backgroundColor: Colors.red,
                    heroTag: 'skip',
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.extended(
                    onPressed: () => _matchManager.advanceToNextTick(),
                    label: const Text('Next Tick (SPACE)'),
                    icon: const Icon(Icons.skip_next),
                    backgroundColor: Colors.orange,
                    heroTag: 'next',
                  ),
                ],
              )
            : (match.isGameOver || match.playerSubmitted
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: _submitTurn,
                      label: const Text('Submit Turn'),
                      icon: const Icon(Icons.send),
                    )),
      ),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Account header (Firebase player info)
        _buildAccountHeader(),
        const SizedBox(height: 8),

        Expanded(
          child: Row(
            children: [
              // Main game area
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // Opponent info
                    _buildPlayerInfo(match.opponent, isOpponent: true),

                    const SizedBox(height: 8),

                    // Combat phase indicator
                    if (match.currentPhase == MatchPhase.combatPhase)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red[700]!, Colors.orange[600]!],
                          ),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.flash_on,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '⚔️ COMBAT IN PROGRESS ⚔️',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.flash_on,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ],
                            ),
                            if (_matchManager.currentTickInfo != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _matchManager.currentTickInfo!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

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
                            Text(
                              'Click a lane to place ${_selectedCard!.name}',
                            ),
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

              // Battle Log sidebar
              _buildBattleLog(),
            ],
          ),
        ),
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

    // Get cards to show: opponent first (top/closer to enemy), then player (bottom/closer to you)
    List<GameCard> cardsToShow = [
      ...opponentCardsAtTile, // Enemy cards at TOP (row 0 direction)
      ...playerCardsAtTile, // Player survivors/cards
      ...stagedCardsOnTile, // Player staged cards at BOTTOM (row 2 direction)
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

                      // Check if this is the opponent's back card and it's concealed
                      final isOpponentBackCard =
                          isOpponent &&
                          opponentCardsAtTile.length >= 2 &&
                          opponentCardsAtTile.indexOf(card) == 1;
                      final isConcealed =
                          isOpponentBackCard && opponentBackCardConcealed;

                      // Determine card color
                      Color cardColor;
                      if (isStaged) {
                        cardColor = Colors.amber[100]!;
                      } else if (isOpponent) {
                        cardColor = isConcealed
                            ? Colors.grey[400]!
                            : Colors.red[200]!;
                      } else if (isPlayerCard) {
                        cardColor = Colors.blue[200]!;
                      } else {
                        cardColor = Colors.grey[200]!;
                      }

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(4),
                          border: isStaged
                              ? Border.all(color: Colors.amber, width: 2)
                              : (isPlayerCard
                                    ? Border.all(color: Colors.blue, width: 1)
                                    : (isConcealed
                                          ? Border.all(
                                              color: Colors.grey[600]!,
                                              width: 1,
                                            )
                                          : null)),
                        ),
                        child: isConcealed
                            // Show hidden card placeholder
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    '🔮 Hidden Card',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '(concealed)',
                                    style: TextStyle(
                                      fontSize: 7,
                                      color: Colors.grey[300],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              )
                            // Show normal card info
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
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

  Widget _buildBattleLog() {
    final log = _matchManager.getCombatLog();

    return Container(
      width: 200,
      color: Colors.grey[100],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[300],
            width: double.infinity,
            child: const Text(
              '📜 Battle Log',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: log.isEmpty
                ? const Center(child: Text('No combat yet'))
                : ListView.builder(
                    itemCount: log.length,
                    itemBuilder: (context, index) {
                      final entry = log[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey[300]!),
                          ),
                          color: entry.isImportant
                              ? Colors.amber[50]
                              : Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${entry.laneDescription}] T${entry.tick}',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              entry.action,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (entry.details.isNotEmpty)
                              Text(
                                entry.details,
                                style: const TextStyle(fontSize: 9),
                              ),
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

  Widget _buildCardStack(stack, Color color) {
    if (stack.isEmpty) {
      return const SizedBox(height: 80);
    }

    final hasMultiple = stack.topCard != null && stack.bottomCard != null;

    return Column(
      children: [
        if (stack.topCard != null)
          _buildCardWidgetWithPosition(
            stack.topCard!,
            color,
            position: hasMultiple ? '🔼 FRONT' : 'FRONT',
          ),
        if (stack.bottomCard != null)
          _buildCardWidgetWithPosition(
            stack.bottomCard!,
            color,
            position: hasMultiple ? '🔽 BACK' : 'BACK',
          ),
      ],
    );
  }

  Widget _buildCardWidgetWithPosition(
    GameCard card,
    Color color, {
    String? position,
    bool isAttacking = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (position != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              position,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        _buildCardWidget(card, color, isAttacking: isAttacking),
      ],
    );
  }

  Widget _buildCardWidget(
    GameCard card,
    Color color, {
    bool isAttacking = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: card.isAlive ? color : Colors.grey,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isAttacking ? Colors.orange : Colors.black26,
          width: isAttacking ? 3 : 1,
        ),
        boxShadow: isAttacking
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            card.name,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'HP:${card.currentHealth}/${card.health}',
            style: const TextStyle(fontSize: 7),
          ),
          Text(
            'DMG:${card.damage} T:${card.tick}',
            style: const TextStyle(fontSize: 7),
          ),
          if (card.element != null)
            Text(
              'Terrain:${card.element}',
              style: const TextStyle(fontSize: 7),
            ),
          if (card.abilities.isNotEmpty)
            Text(
              card.abilities.join(', '),
              style: const TextStyle(fontSize: 6),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'HP: ${card.health}',
                                style: const TextStyle(fontSize: 9),
                              ),
                              Text(
                                'DMG: ${card.damage}',
                                style: const TextStyle(fontSize: 9),
                              ),
                              Text(
                                'Tick: ${card.tick}',
                                style: const TextStyle(fontSize: 9),
                              ),
                              if (card.element != null)
                                Text(
                                  'Elem: ${card.element}',
                                  style: const TextStyle(fontSize: 8),
                                ),
                              if (card.abilities.isNotEmpty)
                                Text(
                                  card.abilities.join(', '),
                                  style: const TextStyle(fontSize: 7),
                                  maxLines: 2,
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
