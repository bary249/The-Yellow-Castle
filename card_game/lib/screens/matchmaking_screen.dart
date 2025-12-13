import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/card.dart';
import '../models/deck.dart';
import '../data/hero_library.dart';
import 'deck_selection_screen.dart';
import 'test_match_screen.dart';

/// Screen that handles matchmaking queue
class MatchmakingScreen extends StatefulWidget {
  final bool isChessTimerMode;
  final String? heroId;
  final List<GameCard>? deck;

  const MatchmakingScreen({
    super.key,
    this.isChessTimerMode = false,
    this.heroId,
    this.deck,
  });

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  final AuthService _authService = AuthService();
  FirebaseFirestore? _firestore;

  StreamSubscription? _queueListener;
  StreamSubscription? _matchListener;
  bool _isSearching = false;
  bool _navigated = false;
  String _status = 'Initializing...';
  int _searchSeconds = 0;
  Timer? _searchTimer;
  List<GameCard>? _myDeck; // The actual deck to use (widget.deck or fallback)

  @override
  void initState() {
    super.initState();
    debugPrint('MatchmakingScreen init: heroId=${widget.heroId}');

    // Initialize deck with fallback
    if (widget.deck != null && widget.deck!.isNotEmpty) {
      _myDeck = widget.deck;

      // SANITY CHECK: If we have a specific hero but the deck looks like the generic starter (has Pikeman),
      // force regeneration.
      final hasGenericCards = _myDeck!.any((c) => c.name == 'Pikeman');
      if (hasGenericCards &&
          widget.heroId != null &&
          widget.heroId != 'napoleon') {
        // Napoleon might have generic-ish cards? No, he has Fusiliers.
        debugPrint(
          '⚠️ Detected generic cards (Pikeman) for hero ${widget.heroId}! Forcing regeneration.',
        );
        _myDeck = null; // Trigger fallback below
      } else {
        debugPrint(
          'MatchmakingScreen: Using provided deck (${_myDeck!.length} cards). First: ${_myDeck!.first.name}',
        );
      }
    }

    if (_myDeck == null) {
      if (widget.heroId != null) {
        debugPrint(
          '⚠️ MatchmakingScreen: Deck is missing! Falling back to default for ${widget.heroId}',
        );
        switch (widget.heroId) {
          case 'archduke_charles':
            _myDeck = Deck.archduke().cards;
            break;
          case 'saladin':
            _myDeck = Deck.saladin().cards;
            break;
          case 'admiral_nelson':
            _myDeck = Deck.nelson().cards;
            break;
          case 'napoleon':
            _myDeck = Deck.napoleon().cards;
            break;
          default:
            _myDeck = Deck.starter().cards;
        }
        debugPrint(
          'MatchmakingScreen: Created fallback deck (${_myDeck!.length} cards). First: ${_myDeck!.first.name}',
        );
      } else {
        debugPrint(
          '⚠️ MatchmakingScreen: No deck and no hero ID! Using starter.',
        );
        _myDeck = Deck.starter().cards;
      }
    }

    try {
      _firestore = FirebaseFirestore.instance;
    } catch (e) {
      print('Matchmaking: Firebase not available');
      setState(() => _status = 'Offline Mode: Cannot play online');
      return;
    }
    _startSearching();
  }

  @override
  void dispose() {
    _cancelSearch();
    super.dispose();
  }

  Future<void> _startSearching() async {
    if (_firestore == null) return;

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
      await _firestore!.collection('matchmaking_queue').doc(user.uid).set({
        'userId': user.uid,
        'displayName': playerName,
        'elo': playerElo,
        'timestamp': FieldValue.serverTimestamp(),
        'searching': true,
        'heroId': widget.heroId, // Store selected hero
        'deck': _myDeck
            ?.map((c) => c.name)
            .toList(), // Store selected deck (use fallback if needed)
      });

      setState(() => _status = 'Searching for opponent...');

      // Listen for other players in queue
      _queueListener = _firestore!
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
              final oppData = opponent.data();

              // Try to create match (only one player should succeed)
              await _tryCreateMatch(
                user.uid,
                opponent.id,
                playerName,
                oppData['displayName'] as String? ?? 'Opponent',
                widget.heroId,
                oppData['heroId'] as String?,
                _myDeck?.map((c) => c.name).toList(), // Use _myDeck here too
                (oppData['deck'] as List<dynamic>?)?.cast<String>(),
              );
            }
          });

      // TESTING: Delete any existing matches for this user before searching
      // This ensures we always get a fresh match for testing
      try {
        final existingMatches = await _firestore!
            .collection('matches')
            .where('playerIds', arrayContains: user.uid)
            .get();
        for (final doc in existingMatches.docs) {
          final status = doc.data()['status'] as String?;
          if (status == 'waiting' || status == 'active') {
            print('🧹 Deleting old match: ${doc.id}');
            await doc.reference.delete();
          }
        }
      } catch (e) {
        print('⚠️ Could not delete old matches (continuing anyway): $e');
      }

      // Also listen for matches where we're a player
      _matchListener = _firestore!
          .collection('matches')
          .where('playerIds', arrayContains: user.uid)
          .snapshots()
          .listen((snapshot) {
            if (!mounted || !_isSearching) return;

            // Find waiting or active match
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final status = data['status'] as String?;
              if (status == 'waiting' || status == 'active') {
                print('Found match: ${doc.id} (status: $status)');
                _navigateToMatch(doc.id);
                return;
              }
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
    String? myHeroId,
    String? opponentHeroId,
    List<String>? myDeck,
    List<String>? opponentDeck,
  ) async {
    // Use a transaction to avoid race conditions
    // The player with the "lower" ID creates the match
    if (myId.compareTo(opponentId) > 0) return; // Let the other player create

    if (_firestore == null) return;

    debugPrint(
      'Creating match: MyDeck=${myDeck?.length}, OppDeck=${opponentDeck?.length}',
    );
    if (myDeck != null && myDeck.isNotEmpty)
      debugPrint('MyDeck[0]=${myDeck.first}');

    try {
      final matchRef = _firestore!.collection('matches').doc();

      // Check if opponent is still searching
      final opponentDoc = await _firestore!
          .collection('matchmaking_queue')
          .doc(opponentId)
          .get();

      if (!opponentDoc.exists || opponentDoc.data()?['searching'] != true) {
        return; // Opponent left queue
      }

      // Create match with ready flags
      await matchRef.set({
        'matchId': matchRef.id,
        'status':
            'waiting', // waiting for both players to be ready (or active if pre-selected)
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isChessTimerMode': widget.isChessTimerMode,
        'player1': {
          'userId': myId,
          'displayName': myName,
          'ready': myDeck != null, // Ready if deck provided
          'submitted': false,
          'crystalHP': 100,
          'heroId': myHeroId,
          'deck': myDeck,
        },
        'player2': {
          'userId': opponentId,
          'displayName': opponentName,
          'ready': opponentDeck != null, // Ready if deck provided
          'submitted': false,
          'crystalHP': 100,
          'heroId': opponentHeroId,
          'deck': opponentDeck,
        },
        'playerIds': [myId, opponentId],
        'turnNumber': 1,
        'currentPhase': 'placement',
        'lanes': {
          'left': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
          'center': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
          'right': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
        },
        'winner': null,
      });

      // Remove both from queue
      await _firestore!.collection('matchmaking_queue').doc(myId).delete();
      await _firestore!
          .collection('matchmaking_queue')
          .doc(opponentId)
          .delete();

      // Don't navigate here - let both players detect via listener
    } catch (e) {
      print('Match creation error (may be normal race): $e');
    }
  }

  void _navigateToMatch(String matchId) {
    if (_navigated) return;
    _navigated = true;
    _cancelSearch();

    if (mounted) {
      if (_myDeck != null) {
        // Resolve hero
        final hero = widget.heroId != null
            ? HeroLibrary.getHeroById(widget.heroId!)
            : null;

        // Deck already selected: Go straight to game
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TestMatchScreen(
              onlineMatchId: matchId,
              selectedHero: hero,
              customDeck: _myDeck,
            ),
          ),
        );
      } else {
        // Legacy/Fallback: Go to Deck Selection Lobby
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DeckSelectionScreen(
              heroId: widget.heroId ?? 'napoleon', // Fallback if null
              onlineMatchId: matchId,
            ),
          ),
        );
      }
    }
  }

  Future<void> _cancelSearch() async {
    _isSearching = false;
    _queueListener?.cancel();
    _matchListener?.cancel();
    _searchTimer?.cancel();

    // Remove from queue
    final user = _authService.currentUser;
    if (user != null && _firestore != null) {
      try {
        await _firestore!
            .collection('matchmaking_queue')
            .doc(user.uid)
            .delete();
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
                    backgroundColor: const Color(0xFF16213E),
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
