/// OnlineGameManager: Simple state-sync for online TYC3 matches.
///
/// Design principle: Write FULL game state to Firebase after every action.
/// The opponent receives the state via a Firestore stream and replaces their
/// local state entirely. No action replay, no coordinate conversion during sync.
///
/// This is simpler and more robust than action-replay because:
/// - Turn-based game = only one player acts at a time
/// - Full state sync = no desync possible
/// - Stream-based = UI updates automatically

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/match_state.dart';

/// Manages online game state synchronization via Firebase.
///
/// Usage:
/// 1. Create instance with matchId and myPlayerId
/// 2. Call syncState() after every local action (place, move, attack, end turn)
/// 3. Listen to stateStream for opponent's updates
/// 4. When stream emits, replace local MatchState with the received one
class OnlineGameManager {
  final FirebaseFirestore _firestore;
  final String matchId;
  final String myPlayerId;

  /// Stream controller for game state updates
  StreamSubscription<DocumentSnapshot>? _subscription;
  final _stateController = StreamController<MatchState>.broadcast();

  /// Stream of game state updates from Firebase
  /// Emits whenever the opponent updates the game state
  Stream<MatchState> get stateStream => _stateController.stream;

  /// Last known state version to detect changes
  int _lastSyncedVersion = 0;

  OnlineGameManager({
    required this.matchId,
    required this.myPlayerId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Start listening to Firebase for state updates
  void startListening() {
    debugPrint('📡 OnlineGameManager: Starting Firebase listener for $matchId');

    _subscription = _firestore
        .collection('matches')
        .doc(matchId)
        .snapshots()
        .listen(
          _onSnapshot,
          onError: (e) {
            debugPrint('❌ OnlineGameManager: Firebase error: $e');
          },
        );
  }

  /// Stop listening to Firebase
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    debugPrint('� OnlineGameManager: Stopped listening');
  }

  /// Handle incoming Firebase snapshot
  void _onSnapshot(DocumentSnapshot snapshot) {
    if (!snapshot.exists) {
      debugPrint('⚠️ OnlineGameManager: Match document does not exist');
      return;
    }

    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return;

    // Check if there's game state to sync
    final gameState = data['gameState'] as Map<String, dynamic>?;
    if (gameState == null) {
      debugPrint('📡 OnlineGameManager: No gameState in document yet');
      return;
    }

    // Check version to avoid processing our own updates
    final version = gameState['version'] as int? ?? 0;
    final lastUpdatedBy = gameState['lastUpdatedBy'] as String?;

    debugPrint(
      '📡 OnlineGameManager: Received state v$version (last: $_lastSyncedVersion, by: $lastUpdatedBy)',
    );

    // Only process if this is a newer version AND it wasn't us who updated it
    if (version > _lastSyncedVersion && lastUpdatedBy != myPlayerId) {
      _lastSyncedVersion = version;

      try {
        final matchState = MatchState.fromJson(
          gameState,
          myPlayerId: myPlayerId,
        );
        debugPrint(
          '✅ OnlineGameManager: Parsed opponent state, emitting to stream',
        );
        _stateController.add(matchState);
      } catch (e) {
        debugPrint('❌ OnlineGameManager: Failed to parse state: $e');
      }
    } else if (lastUpdatedBy == myPlayerId) {
      // Update our version tracker when we see our own update confirmed
      _lastSyncedVersion = version;
      debugPrint('📡 OnlineGameManager: Confirmed our own update v$version');
    }
  }

  /// Sync the current game state to Firebase
  /// Call this after every action (place, move, attack, end turn)
  Future<void> syncState(MatchState state) async {
    _lastSyncedVersion++;

    final stateJson = state.toJson();
    stateJson['version'] = _lastSyncedVersion;
    stateJson['lastUpdatedBy'] = myPlayerId;
    stateJson['updatedAt'] = FieldValue.serverTimestamp();

    debugPrint('📤 OnlineGameManager: Syncing state v$_lastSyncedVersion');

    try {
      await _firestore.collection('matches').doc(matchId).update({
        'gameState': stateJson,
      });
      debugPrint('✅ OnlineGameManager: State synced successfully');
    } catch (e) {
      debugPrint('❌ OnlineGameManager: Failed to sync state: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    _stateController.close();
  }
}
