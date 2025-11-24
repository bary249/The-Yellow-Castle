import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/lane.dart';
import '../models/card.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';

/// Simple test screen to verify game logic with drag-and-drop card placement
class TestMatchScreen extends StatefulWidget {
  const TestMatchScreen({super.key});

  @override
  State<TestMatchScreen> createState() => _TestMatchScreenState();
}

class _TestMatchScreenState extends State<TestMatchScreen> {
  final MatchManager _matchManager = MatchManager();
  final SimpleAI _ai = SimpleAI();

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
    _startNewMatch();
  }

  void _startNewMatch() {
    _matchManager.startMatch(
      playerId: 'player1',
      playerName: 'You',
      playerDeck: Deck.starter(playerId: 'player1'),
      opponentId: 'ai',
      opponentName: 'AI Opponent',
      opponentDeck: Deck.starter(playerId: 'ai'),
      opponentIsAI: true,
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

  void _submitTurn() {
    final match = _matchManager.currentMatch;
    if (match == null) return;

    // Check if any cards were placed
    final totalPlaced = _stagedCards.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    if (totalPlaced == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Place at least one card!')));
      return;
    }

    // Submit player moves
    _matchManager.submitPlayerMoves(Map.from(_stagedCards));

    // AI makes its moves
    final aiMoves = _ai.generateMoves(match.opponent);
    _matchManager.submitOpponentMoves(aiMoves);

    // Clear staging
    _clearStaging();
    setState(() {});
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

    return Scaffold(
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
      floatingActionButton: match.isGameOver || match.playerSubmitted
          ? null
          : FloatingActionButton.extended(
              onPressed: _submitTurn,
              label: const Text('Submit Turn'),
              icon: const Icon(Icons.send),
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
    return Row(
      children: [
        // Main game area
        Expanded(
          flex: 2,
          child: Column(
            children: [
              // Opponent info
              _buildPlayerInfo(match.opponent, isOpponent: true),

              const SizedBox(height: 8),

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

              // Lanes
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildLane(match, LanePosition.left)),
                    Expanded(child: _buildLane(match, LanePosition.center)),
                    Expanded(child: _buildLane(match, LanePosition.right)),
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
    );
  }

  Widget _buildBattleLog() {
    final logs = _matchManager.getCombatLog();

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(left: BorderSide(color: Colors.grey[700]!, width: 2)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: const Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Text(
                  'BATTLE LOG',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Log entries
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No combat yet\nPlace cards and submit to see battle results',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[index];
                      return _buildLogEntry(entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(dynamic entry) {
    // Check if it's a BattleLogEntry
    final tick = entry.tick as int;
    final laneDesc = entry.laneDescription as String;
    final action = entry.action as String;
    final details = entry.details as String;
    final isImportant = entry.isImportant as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isImportant
            ? Colors.orange[900]!.withOpacity(0.3)
            : Colors.grey[850],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isImportant ? Colors.orange : Colors.grey[700]!,
          width: isImportant ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lane and tick
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                laneDesc,
                style: const TextStyle(
                  color: Colors.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              if (tick > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple[700],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'T$tick',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),

          // Action
          Text(
            action,
            style: TextStyle(
              color: isImportant ? Colors.amber : Colors.white,
              fontWeight: isImportant ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),

          // Details
          Text(
            details,
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerInfo(player, {required bool isOpponent}) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: isOpponent ? Colors.red[100] : Colors.blue[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            player.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '💎 ${player.crystalHP} HP',
            style: const TextStyle(fontSize: 16),
          ),
          Text('🃏 ${player.hand.length}'),
          Text('📚 ${player.deck.remainingCards}'),
          Text('💰 ${player.gold}'),
        ],
      ),
    );
  }

  Widget _buildLane(MatchState match, LanePosition position) {
    final lane = match.getLane(position);
    final stagedCardsInLane = _stagedCards[position]!;
    final canPlace = _selectedCard != null && stagedCardsInLane.length < 2;

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
          color: canPlace ? Colors.green.withOpacity(0.1) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              position.name.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

            // Staged cards (player's cards for this turn)
            if (stagedCardsInLane.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.yellow[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Column(
                  children: [
                    const Text('⏳ Staged', style: TextStyle(fontSize: 10)),
                    ...stagedCardsInLane.map(
                      (card) => _buildStagedCard(card, position),
                    ),
                  ],
                ),
              )
            else if (canPlace)
              Container(
                height: 60,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
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

            // Player cards (from previous turns)
            _buildCardStack(lane.playerStack, Colors.blue[200]!),
          ],
        ),
      ),
    );
  }

  Widget _buildStagedCard(GameCard card, LanePosition lane) {
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
                Text(
                  'HP: ${card.health} DMG: ${card.damage} T:${card.tick}',
                  style: const TextStyle(fontSize: 9),
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

  Widget _buildCardStack(stack, Color color) {
    if (stack.isEmpty) {
      return const SizedBox(height: 80);
    }

    return Column(
      children: [
        if (stack.topCard != null) _buildCardWidget(stack.topCard!, color),
        if (stack.bottomCard != null)
          _buildCardWidget(stack.bottomCard!, color),
      ],
    );
  }

  Widget _buildCardWidget(GameCard card, Color color) {
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: card.isAlive ? color : Colors.grey,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26),
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
                                      color: Colors.green.withOpacity(0.5),
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
