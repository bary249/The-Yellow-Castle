import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

/// Handles matchmaking queue and player matching
class MatchmakingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  StreamSubscription? _queueListener;

  MatchmakingService(this._authService);

  /// Add current player to matchmaking queue
  Future<String?> joinQueue() async {
    if (!_authService.isSignedIn) return null;

    final userId = _authService.currentUser!.uid;
    final profile = await _authService.getUserProfile(userId);

    if (profile == null) return null;

    try {
      // Add to queue
      await _firestore.collection('matchmaking_queue').doc(userId).set({
        'userId': userId,
        'displayName': profile['displayName'],
        'elo': profile['elo'],
        'timestamp': FieldValue.serverTimestamp(),
        'searching': true,
      });

      // Start listening for match
      return await _waitForMatch(userId, profile['elo'] as int);
    } catch (e) {
      print('Error joining queue: $e');
      return null;
    }
  }

  /// Wait for a match to be found
  Future<String?> _waitForMatch(String userId, int myElo) async {
    final completer = Completer<String?>();

    // Listen for potential opponents
    _queueListener = _firestore
        .collection('matchmaking_queue')
        .where('searching', isEqualTo: true)
        .where('elo', isGreaterThanOrEqualTo: myElo - 100)
        .where('elo', isLessThanOrEqualTo: myElo + 100)
        .snapshots()
        .listen((snapshot) async {
          // Find opponent (not self)
          final opponents = snapshot.docs
              .where((doc) => doc.id != userId)
              .toList();

          if (opponents.isNotEmpty) {
            // Pick first opponent
            final opponent = opponents.first;
            final opponentId = opponent.id;

            try {
              // Try to create match (race condition handled by Firestore)
              final matchId = await _createMatch(userId, opponentId);

              if (matchId != null) {
                // Remove both from queue
                await _removeFromQueue(userId);
                await _removeFromQueue(opponentId);

                completer.complete(matchId);
              }
            } catch (e) {
              print('Error creating match: $e');
            }
          }
        });

    // Timeout after 60 seconds
    Timer(const Duration(seconds: 60), () {
      if (!completer.isCompleted) {
        _queueListener?.cancel();
        _removeFromQueue(userId);
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Create a new match between two players
  Future<String?> _createMatch(String player1Id, String player2Id) async {
    try {
      // Get both player profiles
      final p1Profile = await _authService.getUserProfile(player1Id);
      final p2Profile = await _authService.getUserProfile(player2Id);

      if (p1Profile == null || p2Profile == null) return null;

      // Create match document
      final matchRef = _firestore.collection('matches').doc();
      await matchRef.set({
        'matchId': matchRef.id,
        'status': 'waiting',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'player1': {
          'userId': player1Id,
          'displayName': p1Profile['displayName'],
          'elo': p1Profile['elo'],
          'ready': false,
          'submitted': false,
          'crystalHP': 100,
          'gold': 0,
        },
        'player2': {
          'userId': player2Id,
          'displayName': p2Profile['displayName'],
          'elo': p2Profile['elo'],
          'ready': false,
          'submitted': false,
          'crystalHP': 100,
          'gold': 0,
        },
        'playerIds': [player1Id, player2Id],
        'turnNumber': 0,
        'currentPhase': 'placement',
        'lanes': {
          'left': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
          'center': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
          'right': {'zone': 'middle', 'player1Cards': [], 'player2Cards': []},
        },
        'winner': null,
        'disconnected': [],
      });

      return matchRef.id;
    } catch (e) {
      print('Error creating match: $e');
      return null;
    }
  }

  /// Remove player from queue
  Future<void> _removeFromQueue(String userId) async {
    try {
      await _firestore.collection('matchmaking_queue').doc(userId).delete();
    } catch (e) {
      print('Error removing from queue: $e');
    }
  }

  /// Cancel matchmaking search
  Future<void> cancelSearch() async {
    if (!_authService.isSignedIn) return;

    _queueListener?.cancel();
    await _removeFromQueue(_authService.currentUser!.uid);
  }

  /// Clean up old queue entries (maintenance)
  Future<void> cleanupOldEntries() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
      final oldEntries = await _firestore
          .collection('matchmaking_queue')
          .where('timestamp', isLessThan: cutoff)
          .get();

      for (final doc in oldEntries.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      print('Error cleaning up queue: $e');
    }
  }

  void dispose() {
    _queueListener?.cancel();
  }
}
