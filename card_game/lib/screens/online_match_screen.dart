import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../models/lane.dart';

/// Online match screen with real-time Firestore sync
class OnlineMatchScreen extends StatefulWidget {
  final String matchId;

  const OnlineMatchScreen({super.key, required this.matchId});

  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _matchListener;
  Map<String, dynamic>? _matchData;
  List<GameCard> _hand = [];
  final Map<LanePosition, List<GameCard>> _stagedCards = {
    LanePosition.left: [],
    LanePosition.center: [],
    LanePosition.right: [],
  };
  GameCard? _selectedCard;
  bool _isSubmitting = false;
  String? _myPlayerId;
  bool _amPlayer1 = true;

  @override
  void initState() {
    super.initState();
    _myPlayerId = _authService.currentUser?.uid;
    _initializeHand();
    _listenToMatch();
  }

  @override
  void dispose() {
    _matchListener?.cancel();
    super.dispose();
  }

  void _initializeHand() {
    // Create a starter deck hand
    final deck = Deck.starter(playerId: _myPlayerId ?? 'player');
    _hand = List.from(deck.cards.take(5)); // Draw 5 cards
  }

  void _listenToMatch() {
    _matchListener = _firestore
        .collection('matches')
        .doc(widget.matchId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            setState(() {
              _matchData = snapshot.data();
              _amPlayer1 = _matchData?['player1']?['userId'] == _myPlayerId;
            });

            // Check if match ended
            if (_matchData?['status'] == 'completed') {
              _showMatchResult();
            }

            // Check if both submitted - resolve combat
            final p1Submitted = _matchData?['player1']?['submitted'] == true;
            final p2Submitted = _matchData?['player2']?['submitted'] == true;
            if (p1Submitted &&
                p2Submitted &&
                _matchData?['currentPhase'] == 'placement') {
              _resolveCombat();
            }
          }
        });
  }

  void _showMatchResult() {
    final winner = _matchData?['winner'];
    final isWinner = winner == _myPlayerId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isWinner ? '🎉 Victory!' : '😢 Defeat'),
        content: Text(
          isWinner
              ? 'Congratulations! You won the match!'
              : 'Better luck next time!',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Return to menu
            },
            child: const Text('Back to Menu'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveCombat() async {
    // Simple combat resolution - just for demo
    // In real implementation, this would be more sophisticated
    final matchRef = _firestore.collection('matches').doc(widget.matchId);

    await matchRef.update({'currentPhase': 'combat'});

    // Simulate combat delay
    await Future.delayed(const Duration(seconds: 2));

    // Get current HP
    final p1HP = _matchData?['player1']?['crystalHP'] as int? ?? 100;
    final p2HP = _matchData?['player2']?['crystalHP'] as int? ?? 100;

    // Simple damage calculation based on cards played
    final p1Cards = _stagedCards.values.expand((c) => c).length;
    final p2Cards = (_matchData?['player2']?['cardsPlayed'] as int?) ?? 0;

    final newP1HP = p1HP - (p2Cards * 5);
    final newP2HP = p2HP - (p1Cards * 5);

    // Check for winner
    String? winner;
    String status = 'active';
    if (newP1HP <= 0 || newP2HP <= 0) {
      status = 'completed';
      if (newP1HP <= 0 && newP2HP <= 0) {
        winner = null; // Draw
      } else if (newP1HP <= 0) {
        winner = _matchData?['player2']?['userId'];
      } else {
        winner = _matchData?['player1']?['userId'];
      }
    }

    // Update match
    await matchRef.update({
      'currentPhase': 'placement',
      'turnNumber': FieldValue.increment(1),
      'player1.crystalHP': newP1HP > 0 ? newP1HP : 0,
      'player2.crystalHP': newP2HP > 0 ? newP2HP : 0,
      'player1.submitted': false,
      'player2.submitted': false,
      'player1.cardsPlayed': 0,
      'player2.cardsPlayed': 0,
      'status': status,
      if (winner != null) 'winner': winner,
    });

    // Clear staging
    if (mounted) {
      setState(() {
        _stagedCards[LanePosition.left]!.clear();
        _stagedCards[LanePosition.center]!.clear();
        _stagedCards[LanePosition.right]!.clear();
        _initializeHand(); // Refresh hand
      });
    }
  }

  void _placeCard(LanePosition lane) {
    if (_selectedCard == null) return;
    if (_stagedCards[lane]!.length >= 2) return;

    setState(() {
      _stagedCards[lane]!.add(_selectedCard!);
      _hand.remove(_selectedCard);
      _selectedCard = null;
    });
  }

  void _removeCard(LanePosition lane, GameCard card) {
    setState(() {
      _stagedCards[lane]!.remove(card);
      _hand.add(card);
    });
  }

  Future<void> _submitTurn() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final playerKey = _amPlayer1 ? 'player1' : 'player2';
      final cardsPlayed = _stagedCards.values.expand((c) => c).length;

      await _firestore.collection('matches').doc(widget.matchId).update({
        '$playerKey.submitted': true,
        '$playerKey.cardsPlayed': cardsPlayed,
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_matchData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final myData = _amPlayer1 ? _matchData!['player1'] : _matchData!['player2'];
    final opponentData = _amPlayer1
        ? _matchData!['player2']
        : _matchData!['player1'];
    final mySubmitted = myData?['submitted'] == true;
    final opponentSubmitted = opponentData?['submitted'] == true;
    final turnNumber = _matchData!['turnNumber'] as int? ?? 1;
    final phase = _matchData!['currentPhase'] as String? ?? 'placement';

    return Scaffold(
      appBar: AppBar(
        title: Text('Turn $turnNumber - Online Match'),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        actions: [
          // Leave button
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () => _showLeaveDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            color: phase == 'combat' ? Colors.red[100] : Colors.blue[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPlayerStatus(
                  'You',
                  myData?['crystalHP'] as int? ?? 100,
                  mySubmitted,
                  true,
                ),
                Column(
                  children: [
                    Text(
                      phase == 'combat' ? '⚔️ COMBAT' : '📋 PLACEMENT',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Turn $turnNumber'),
                  ],
                ),
                _buildPlayerStatus(
                  opponentData?['displayName'] as String? ?? 'Opponent',
                  opponentData?['crystalHP'] as int? ?? 100,
                  opponentSubmitted,
                  false,
                ),
              ],
            ),
          ),

          // Waiting indicator
          if (mySubmitted && !opponentSubmitted)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.amber[100],
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Waiting for opponent...'),
                ],
              ),
            ),

          // Combat indicator
          if (phase == 'combat')
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red[200],
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flash_on, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    '⚔️ COMBAT IN PROGRESS ⚔️',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.flash_on, color: Colors.red),
                ],
              ),
            ),

          // Lanes
          Expanded(
            child: Row(
              children: [
                _buildLane(LanePosition.left, 'LEFT'),
                _buildLane(LanePosition.center, 'CENTER'),
                _buildLane(LanePosition.right, 'RIGHT'),
              ],
            ),
          ),

          // Hand
          _buildHand(),

          // Submit button
          if (!mySubmitted && phase == 'placement')
            Container(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitTurn,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Turn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerStatus(String name, int hp, bool submitted, bool isMe) {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              isMe ? Icons.person : Icons.smart_toy,
              color: isMe ? Colors.blue : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isMe ? Colors.blue[700] : Colors.red[700],
              ),
            ),
          ],
        ),
        Text('❤️ $hp HP'),
        Icon(
          submitted ? Icons.check_circle : Icons.hourglass_empty,
          color: submitted ? Colors.green : Colors.grey,
          size: 16,
        ),
      ],
    );
  }

  Widget _buildLane(LanePosition position, String label) {
    final staged = _stagedCards[position]!;
    final canPlace = _selectedCard != null && staged.length < 2;

    return Expanded(
      child: GestureDetector(
        onTap: canPlace ? () => _placeCard(position) : null,
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
          child: Column(
            children: [
              // Lane label
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[300],
                width: double.infinity,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              // Staged cards
              Expanded(
                child: staged.isEmpty
                    ? Center(
                        child: Icon(
                          canPlace ? Icons.add_circle_outline : Icons.remove,
                          color: canPlace ? Colors.green : Colors.grey,
                          size: 40,
                        ),
                      )
                    : ListView(
                        children: staged.map((card) {
                          return Card(
                            color: Colors.blue[100],
                            child: ListTile(
                              dense: true,
                              title: Text(
                                card.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                'HP:${card.health} DMG:${card.damage}',
                                style: const TextStyle(fontSize: 10),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => _removeCard(position, card),
                              ),
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

  Widget _buildHand() {
    // Get available cards (not staged)
    final stagedSet = _stagedCards.values.expand((c) => c).toSet();
    final available = _hand.where((c) => !stagedSet.contains(c)).toList();

    return Container(
      height: 120,
      padding: const EdgeInsets.all(8),
      color: Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Hand (${available.length} cards)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: available.length,
              itemBuilder: (ctx, i) {
                final card = available[i];
                final isSelected = card == _selectedCard;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCard = isSelected ? null : card;
                    });
                  },
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green[200] : Colors.white,
                      border: Border.all(
                        color: isSelected ? Colors.green : Colors.grey,
                        width: isSelected ? 3 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          card.name,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'HP:${card.health}',
                          style: const TextStyle(fontSize: 9),
                        ),
                        Text(
                          'DMG:${card.damage}',
                          style: const TextStyle(fontSize: 9),
                        ),
                        Text(
                          'T:${card.tick}',
                          style: const TextStyle(fontSize: 9),
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

  void _showLeaveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Match?'),
        content: const Text(
          'Are you sure you want to leave? This will forfeit the match.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Mark as forfeited
              await _firestore
                  .collection('matches')
                  .doc(widget.matchId)
                  .update({
                    'status': 'completed',
                    'winner': _amPlayer1
                        ? _matchData?['player2']?['userId']
                        : _matchData?['player1']?['userId'],
                  });
              if (mounted) Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}
