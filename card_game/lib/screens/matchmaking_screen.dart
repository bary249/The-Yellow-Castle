import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import 'online_match_screen.dart';

/// Screen that handles matchmaking queue
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _queueListener;
  StreamSubscription? _matchListener;
  bool _isSearching = false;
  String _status = 'Initializing...';
  int _searchSeconds = 0;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _startSearching();
  }

  @override
  void dispose() {
    _cancelSearch();
    super.dispose();
  }

  Future<void> _startSearching() async {
    final user = _authService.currentUser;
    if (user == null) {
      setState(() => _status = 'Not signed in!');
      return;
    }

    setState(() {
      _isSearching = true;
      _status = 'Joining queue...';
    });

    // Start search timer
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _searchSeconds++);
    });

    try {
      // Get player profile
      final profile = await _authService.getUserProfile(user.uid);
      final playerName = profile?['displayName'] as String? ?? 'Player';
      final playerElo = profile?['elo'] as int? ?? 1000;

      // Add to queue
      await _firestore.collection('matchmaking_queue').doc(user.uid).set({
        'userId': user.uid,
        'displayName': playerName,
        'elo': playerElo,
        'timestamp': FieldValue.serverTimestamp(),
        'searching': true,
      });

      setState(() => _status = 'Searching for opponent...');

      // Listen for other players in queue
      _queueListener = _firestore
          .collection('matchmaking_queue')
          .where('searching', isEqualTo: true)
          .snapshots()
          .listen((snapshot) async {
            // Find opponent (not self)
            final opponents = snapshot.docs
                .where((doc) => doc.id != user.uid)
                .toList();

            if (opponents.isNotEmpty && _isSearching) {
              final opponent = opponents.first;

              // Try to create match (only one player should succeed)
              await _tryCreateMatch(
                user.uid,
                opponent.id,
                playerName,
                opponent.data()['displayName'] as String? ?? 'Opponent',
              );
            }
          });

      // Also listen for matches where we're a player
      _matchListener = _firestore
          .collection('matches')
          .where('playerIds', arrayContains: user.uid)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen((snapshot) {
            if (snapshot.docs.isNotEmpty && mounted) {
              final matchDoc = snapshot.docs.first;
              _navigateToMatch(matchDoc.id);
            }
          });
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error: $e');
      }
    }
  }

  Future<void> _tryCreateMatch(
    String myId,
    String opponentId,
    String myName,
    String opponentName,
  ) async {
    // Use a transaction to avoid race conditions
    // The player with the "lower" ID creates the match
    if (myId.compareTo(opponentId) > 0) return; // Let the other player create

    try {
      final matchRef = _firestore.collection('matches').doc();

      await _firestore.runTransaction((transaction) async {
        // Check if opponent is still searching
        final opponentDoc = await transaction.get(
          _firestore.collection('matchmaking_queue').doc(opponentId),
        );

        if (!opponentDoc.exists || opponentDoc.data()?['searching'] != true) {
          return; // Opponent left queue
        }

        // Create match
        transaction.set(matchRef, {
          'matchId': matchRef.id,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'player1': {
            'userId': myId,
            'displayName': myName,
            'submitted': false,
            'crystalHP': 100,
          },
          'player2': {
            'userId': opponentId,
            'displayName': opponentName,
            'submitted': false,
            'crystalHP': 100,
          },
          'playerIds': [myId, opponentId],
          'turnNumber': 1,
          'currentPhase': 'placement',
          'lanes': {
            'left': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
            'center': {
              'zone': 'middle',
              'player1Cards': [],
              'player2Cards': [],
            },
            'right': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
          },
          'winner': null,
        });

        // Remove both from queue
        transaction.delete(
          _firestore.collection('matchmaking_queue').doc(myId),
        );
        transaction.delete(
          _firestore.collection('matchmaking_queue').doc(opponentId),
        );
      });
    } catch (e) {
      print('Match creation error (may be normal race): $e');
    }
  }

  void _navigateToMatch(String matchId) {
    _cancelSearch();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OnlineMatchScreen(matchId: matchId)),
      );
    }
  }

  Future<void> _cancelSearch() async {
    _isSearching = false;
    _queueListener?.cancel();
    _matchListener?.cancel();
    _searchTimer?.cancel();

    // Remove from queue
    final user = _authService.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('matchmaking_queue').doc(user.uid).delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.indigo[900]!, Colors.purple[900]!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated searching indicator
                const SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
                const SizedBox(height: 40),

                // Status text
                Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Search time
                Text(
                  'Time: ${_searchSeconds}s',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),

                // Hint
                Text(
                  'Open another browser tab to test!',
                  style: TextStyle(
                    color: Colors.amber.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 60),

                // Cancel button
                ElevatedButton.icon(
                  onPressed: () {
                    _cancelSearch();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
