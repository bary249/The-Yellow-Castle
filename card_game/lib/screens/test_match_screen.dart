import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/lane.dart';
import '../models/card.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';
import '../services/auth_service.dart';

/// Simple test screen to verify game logic with drag-and-drop card placement
class TestMatchScreen extends StatefulWidget {
  const TestMatchScreen({super.key});

  @override
  State<TestMatchScreen> createState() => _TestMatchScreenState();
}

class _TestMatchScreenState extends State<TestMatchScreen> {
  final MatchManager _matchManager = MatchManager();
  final SimpleAI _ai = SimpleAI();
  final AuthService _authService = AuthService();

  String? _playerId;
  String? _playerName;
  int? _playerElo;

  // Staging area: cards placed in lanes before submitting
  final Map<LanePosition, List<GameCard>> _stagedCards = {
    LanePosition.left: [],
    LanePosition.center: [],
    LanePosition.right: [],
  };

  GameCard? _selectedCard;

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

    if (mounted) {
      _startNewMatch();
    }
  }

  void _startNewMatch() {
    final id = _playerId ?? 'player1';
    final name = _playerName ?? 'You';
    _matchManager.startMatch(
      playerId: id,
      playerName: name,
      playerDeck: Deck.starter(playerId: id),
      opponentId: 'ai',
      opponentName: 'AI Opponent',
      opponentDeck: Deck.starter(playerId: 'ai'),
      opponentIsAI: true,
      playerAttunedElement: 'Lake',
      opponentAttunedElement: 'Desert',
    );
    _clearStaging();
    setState(() {});
  }

  void _clearStaging() {
    _stagedCards[LanePosition.left]!.clear();
    _stagedCards[LanePosition.center]!.clear();
    _stagedCards[LanePosition.right]!.clear();
    _selectedCard = null;
  }

  void _placeCardInLane(LanePosition lane) {
    final match = _matchManager.currentMatch;
    if (match == null || _selectedCard == null) return;

    // Check if lane already has 2 cards
    if (_stagedCards[lane]!.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lane is full (max 2 cards)!')),
      );
      return;
    }

    // Move card from hand to staging
    _stagedCards[lane]!.add(_selectedCard!);
    _selectedCard = null;
    setState(() {});
  }

  void _removeCardFromLane(LanePosition lane, GameCard card) {
    _stagedCards[lane]!.remove(card);
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
    // if (totalPlaced == 0) {
    //   ScaffoldMessenger.of(
    //     context,
    //   ).showSnackBar(const SnackBar(content: Text('Place at least one card!')));
    //   return;
    // }

    // Set up animation callback
    _matchManager.onCombatUpdate = () {
      if (mounted) setState(() {});
    };

    // Submit player moves
    await _matchManager.submitPlayerMoves(Map.from(_stagedCards));

    // AI makes its moves
    final aiMoves = _ai.generateMoves(match.opponent);
    await _matchManager.submitOpponentMoves(aiMoves);

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

                    // Lanes
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildLane(match, LanePosition.left)),
                          Expanded(
                            child: _buildLane(match, LanePosition.center),
                          ),
                          Expanded(
                            child: _buildLane(match, LanePosition.right),
                          ),
                        ],
                      ),
                    ),

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
            ],
          ),
          Row(
            children: [
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

  Widget _buildLane(MatchState match, LanePosition position) {
    final lane = match.getLane(position);
    final stagedCardsInLane = _stagedCards[position]!;

    // Check total cards: survivors + staged cards must not exceed 2
    final survivingCount = lane.playerStack.aliveCards.length;
    final totalCards = survivingCount + stagedCardsInLane.length;
    final canPlace = _selectedCard != null && totalCards < 2;

    return GestureDetector(
      onTap: canPlace ? () => _placeCardInLane(position) : null,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(
            color: canPlace ? Colors.green : Colors.grey,
            width: canPlace ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: canPlace ? Colors.green.withValues(alpha: 0.1) : null,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                position.name.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              // Zone display
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple),
                ),
                child: Text(
                  lane.zoneDisplay,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Opponent cards
              _buildCardStack(lane.opponentStack, Colors.red[200]!),

              const Divider(),

              // Surviving player cards from previous turn
              if (lane.playerStack.aliveCards.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(4),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '💪 Survivors',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _buildCardStack(lane.playerStack, Colors.blue[200]!),
                    ],
                  ),
                ),

              // Staged/Deployed cards (player's cards for this turn)
              if (stagedCardsInLane.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: match.playerSubmitted
                        ? Colors.green[100]
                        : Colors.yellow[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: match.playerSubmitted
                          ? Colors.green
                          : Colors.orange,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        match.playerSubmitted ? '✅ Deployed' : '⏳ Staged',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ...stagedCardsInLane.asMap().entries.map(
                        (entry) => _buildStagedCard(
                          entry.value,
                          position,
                          indexInLane: entry.key,
                          hasSurvivors: lane.playerStack.aliveCards.isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                )
              else if (canPlace)
                Container(
                  height: 60,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.green,
                      style: BorderStyle.solid,
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_circle_outline,
                      color: Colors.green,
                      size: 32,
                    ),
                  ),
                )
              else
                Container(
                  height: 60,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text('Empty', style: TextStyle(color: Colors.grey)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStagedCard(
    GameCard card,
    LanePosition lane, {
    required int indexInLane,
    required bool hasSurvivors,
  }) {
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.yellow[200],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.name,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Builder(
                  builder: (context) {
                    final posLabel = hasSurvivors
                        ? 'BACK'
                        : (indexInLane == 0 ? 'FRONT' : 'BACK');
                    return Text(
                      'Position: $posLabel',
                      style: const TextStyle(fontSize: 8),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                Text(
                  'HP: ${card.health} DMG: ${card.damage} T:${card.tick}',
                  style: const TextStyle(fontSize: 9),
                ),
                if (card.element != null)
                  Text(
                    'Terrain: ${card.element}',
                    style: const TextStyle(fontSize: 8),
                  ),
                if (card.abilities.isNotEmpty)
                  Text(
                    'Abilities: ${card.abilities.join(", ")}',
                    style: const TextStyle(fontSize: 7),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => _removeCardFromLane(lane, card),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
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
