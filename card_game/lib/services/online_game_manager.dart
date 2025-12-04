/// OnlineGameManager: Shared action-log based sync for online TYC3 matches.
///
/// This class enables the same MatchManager logic to be used across all modes:
/// - Simulation: offline script feeds actions into MatchManager.
/// - Vs AI: local human + AI, both run through MatchManager.
/// - Online PvP: two humans, each running a local MatchManager, with actions
///   synced via Firebase and replayed deterministically.
///
/// Core principle: "Every mode gets an ordered list of actions, feeds them
/// into MatchManager." Online just adds a network layer to share that list.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'match_manager.dart';
import '../models/card.dart';

// ============================================================================
// OnlineAction: A single game action that can be serialized, sent to Firebase,
// and replayed deterministically on any client.
// ============================================================================

enum OnlineActionType { place, move, attack, attackBase, endTurn }

class OnlineAction {
  final OnlineActionType type;
  final String byPlayerId;
  final int actionIndex; // Position in the action log (for ordering)

  // For place/move/attack actions
  final String? cardInstanceId;
  final String? cardName; // For logging/debugging

  // Positions (canonical coords, Player 1's perspective)
  final int? fromRow;
  final int? fromCol;
  final int? toRow;
  final int? toCol;

  // For attack actions
  final String? targetId;
  final int? targetRow;
  final int? targetCol;

  // For endTurn
  final int? turnNumber;

  OnlineAction({
    required this.type,
    required this.byPlayerId,
    this.actionIndex = 0,
    this.cardInstanceId,
    this.cardName,
    this.fromRow,
    this.fromCol,
    this.toRow,
    this.toCol,
    this.targetId,
    this.targetRow,
    this.targetCol,
    this.turnNumber,
  });

  /// Create from Firebase document data
  factory OnlineAction.fromMap(Map<String, dynamic> map, int index) {
    final typeStr = map['type'] as String? ?? 'endTurn';
    final type = OnlineActionType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => OnlineActionType.endTurn,
    );

    return OnlineAction(
      type: type,
      byPlayerId: map['byPlayerId'] as String? ?? '',
      actionIndex: index,
      cardInstanceId: map['cardInstanceId'] as String?,
      cardName: map['cardName'] as String?,
      fromRow: map['fromRow'] as int?,
      fromCol: map['fromCol'] as int?,
      toRow: map['toRow'] as int?,
      toCol: map['toCol'] as int?,
      targetId: map['targetId'] as String?,
      targetRow: map['targetRow'] as int?,
      targetCol: map['targetCol'] as int?,
      turnNumber: map['turnNumber'] as int?,
    );
  }

  /// Convert to Firebase-compatible map
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'byPlayerId': byPlayerId,
      if (cardInstanceId != null) 'cardInstanceId': cardInstanceId,
      if (cardName != null) 'cardName': cardName,
      if (fromRow != null) 'fromRow': fromRow,
      if (fromCol != null) 'fromCol': fromCol,
      if (toRow != null) 'toRow': toRow,
      if (toCol != null) 'toCol': toCol,
      if (targetId != null) 'targetId': targetId,
      if (targetRow != null) 'targetRow': targetRow,
      if (targetCol != null) 'targetCol': targetCol,
      if (turnNumber != null) 'turnNumber': turnNumber,
    };
  }

  @override
  String toString() {
    switch (type) {
      case OnlineActionType.place:
        return 'Place($cardName @ $toRow,$toCol by $byPlayerId)';
      case OnlineActionType.move:
        return 'Move($cardName $fromRow,$fromCol → $toRow,$toCol by $byPlayerId)';
      case OnlineActionType.attack:
        return 'Attack($cardName → target $targetId by $byPlayerId)';
      case OnlineActionType.attackBase:
        return 'AttackBase($cardName by $byPlayerId)';
      case OnlineActionType.endTurn:
        return 'EndTurn(turn $turnNumber by $byPlayerId)';
    }
  }
}

// ============================================================================
// OnlineGameManager: Manages action sync between Firebase and local MatchManager
// ============================================================================

class OnlineGameManager {
  final FirebaseFirestore _firestore;
  final String matchId;
  final String myPlayerId;
  final bool amPlayer1; // True if this client is Player 1 (for coord mirroring)

  MatchManager? _matchManager;
  int _lastReplayedIndex = 0;

  /// Callback when actions are replayed (for UI refresh)
  VoidCallback? onStateChanged;

  OnlineGameManager({
    required this.matchId,
    required this.myPlayerId,
    required this.amPlayer1,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Attach to a MatchManager instance
  void attachToMatch(MatchManager manager) {
    _matchManager = manager;
    _lastReplayedIndex = 0;
    debugPrint('🎮 OnlineGameManager attached to match');
  }

  /// Send a local action to Firebase
  Future<void> sendAction(OnlineAction action) async {
    debugPrint('📤 Sending action: $action');

    await _firestore.collection('matches').doc(matchId).update({
      'tyc3Actions': FieldValue.arrayUnion([action.toMap()]),
    });

    debugPrint('✅ Action sent to Firebase');
  }

  /// Called when Firebase actions list updates
  /// Replays any new actions into the local MatchManager
  void onActionsUpdate(List<dynamic> actionsData) {
    if (_matchManager == null) {
      debugPrint('⚠️ OnlineGameManager: No MatchManager attached');
      return;
    }

    final actions = actionsData
        .asMap()
        .entries
        .map(
          (e) => OnlineAction.fromMap(e.value as Map<String, dynamic>, e.key),
        )
        .toList();

    // Replay any actions we haven't processed yet
    for (int i = _lastReplayedIndex; i < actions.length; i++) {
      final action = actions[i];

      // CRITICAL: Skip our own actions - we already applied them locally
      if (action.byPlayerId == myPlayerId) {
        debugPrint('⏭️ Skipping own action $i: ${action.type.name}');
        _lastReplayedIndex = i + 1;
        continue;
      }

      debugPrint('🔄 Replaying opponent action $i: $action');
      _replayAction(action);
      _lastReplayedIndex = i + 1;
    }

    // Notify UI to refresh
    onStateChanged?.call();
  }

  /// Replay a single action into the MatchManager
  /// Uses the SAME logic as vs-AI mode
  void _replayAction(OnlineAction action) {
    if (_matchManager == null) return;

    // Convert canonical coords to local coords if needed
    // (Player 2 sees the board mirrored)
    int localRow(int? canonicalRow) {
      if (canonicalRow == null) return 0;
      return amPlayer1 ? canonicalRow : (2 - canonicalRow);
    }

    switch (action.type) {
      case OnlineActionType.place:
        _replayPlace(action, localRow);
        break;
      case OnlineActionType.move:
        _replayMove(action, localRow);
        break;
      case OnlineActionType.attack:
        _replayAttack(action, localRow);
        break;
      case OnlineActionType.attackBase:
        _replayAttackBase(action, localRow);
        break;
      case OnlineActionType.endTurn:
        _replayEndTurn(action);
        break;
    }
  }

  void _replayPlace(OnlineAction action, int Function(int?) localRow) {
    final match = _matchManager!.currentMatch;
    if (match == null) return;

    final toRow = localRow(action.toRow);
    final toCol = action.toCol ?? 0;

    // For opponent's place action, we need to find a card by NAME in their hand
    // (card instance IDs are different per player since each has their own deck)
    final activePlayer = _matchManager!.activePlayer;
    if (activePlayer == null) return;

    // Find card by name (first matching card with that name)
    final cardName = action.cardName;
    GameCard? card;
    for (final c in activePlayer.hand) {
      if (c.name == cardName) {
        card = c;
        break;
      }
    }

    if (card == null) {
      debugPrint(
        '⚠️ Replay place: card "$cardName" not found in opponent hand (${activePlayer.hand.length} cards)',
      );
      // Debug: list cards in hand
      for (final c in activePlayer.hand) {
        debugPrint('   - ${c.name} (${c.id})');
      }
      return;
    }

    final success = _matchManager!.placeCardTYC3(card, toRow, toCol);
    debugPrint(
      '🎯 Replay place: ${action.cardName} @ ($toRow, $toCol) = $success',
    );
  }

  void _replayMove(OnlineAction action, int Function(int?) localRow) {
    final match = _matchManager!.currentMatch;
    if (match == null) return;

    final fromRow = localRow(action.fromRow);
    final fromCol = action.fromCol ?? 0;
    final toRow = localRow(action.toRow);
    final toCol = action.toCol ?? 0;

    // Find the card on the board by instanceId
    final card = _findCardOnBoard(match, action.cardInstanceId);
    if (card == null) {
      debugPrint(
        '⚠️ Replay move: card ${action.cardInstanceId} not found on board',
      );
      return;
    }

    final success = _matchManager!.moveCardTYC3(
      card,
      fromRow,
      fromCol,
      toRow,
      toCol,
    );
    debugPrint(
      '🎯 Replay move: ${action.cardName} ($fromRow,$fromCol) → ($toRow,$toCol) = $success',
    );
  }

  void _replayAttack(OnlineAction action, int Function(int?) localRow) {
    final match = _matchManager!.currentMatch;
    if (match == null) return;

    // Convert coords for local perspective
    final attackerRow = localRow(action.fromRow);
    final attackerCol = action.fromCol ?? 0;
    final targetRow = localRow(action.targetRow);
    final targetCol = action.targetCol ?? 0;

    // Find attacker and target cards
    final attacker = _findCardOnBoard(match, action.cardInstanceId);
    final target = _findCardOnBoard(match, action.targetId);

    if (attacker == null || target == null) {
      debugPrint('⚠️ Replay attack: attacker or target not found');
      return;
    }

    // Call MatchManager's attack method (same as vs-AI)
    final result = _matchManager!.attackCardTYC3(
      attacker,
      target,
      attackerRow,
      attackerCol,
      targetRow,
      targetCol,
    );
    debugPrint(
      '🎯 Replay attack: ${action.cardName} → ${target.name} = ${result != null ? "success" : "failed"}',
    );
  }

  void _replayAttackBase(OnlineAction action, int Function(int?) localRow) {
    final match = _matchManager!.currentMatch;
    if (match == null) return;

    final attackerRow = localRow(action.fromRow);
    final attackerCol = action.fromCol ?? 0;

    final attacker = _findCardOnBoard(match, action.cardInstanceId);
    if (attacker == null) {
      debugPrint('⚠️ Replay attackBase: attacker not found');
      return;
    }

    final damage = _matchManager!.attackBaseTYC3(
      attacker,
      attackerRow,
      attackerCol,
    );
    debugPrint('🎯 Replay attackBase: ${action.cardName} dealt $damage damage');
  }

  void _replayEndTurn(OnlineAction action) {
    _matchManager!.endTurnTYC3();
    debugPrint('🎯 Replay endTurn: turn ${action.turnNumber}');
  }

  // -------------------------------------------------------------------------
  // Helper: Find a card by instanceId
  // -------------------------------------------------------------------------

  GameCard? _findCardInHand(List<GameCard> hand, String? instanceId) {
    if (instanceId == null) return null;
    try {
      return hand.firstWhere((c) => c.id == instanceId);
    } catch (_) {
      return null;
    }
  }

  GameCard? _findCardOnBoard(dynamic match, String? instanceId) {
    if (instanceId == null || match == null) return null;

    // Search all tiles for the card
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final card in tile.cards) {
          if (card.id == instanceId) {
            return card;
          }
        }
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Action factory methods (for TestMatchScreen to use)
  // -------------------------------------------------------------------------

  /// Create a place action
  OnlineAction createPlaceAction({
    required GameCard card,
    required int toRow,
    required int toCol,
  }) {
    // Convert local coords to canonical (Player 1's perspective)
    final canonicalRow = amPlayer1 ? toRow : (2 - toRow);

    return OnlineAction(
      type: OnlineActionType.place,
      byPlayerId: myPlayerId,
      cardInstanceId: card.id,
      cardName: card.name,
      toRow: canonicalRow,
      toCol: toCol,
    );
  }

  /// Create a move action
  OnlineAction createMoveAction({
    required GameCard card,
    required int fromRow,
    required int fromCol,
    required int toRow,
    required int toCol,
  }) {
    final canonicalFromRow = amPlayer1 ? fromRow : (2 - fromRow);
    final canonicalToRow = amPlayer1 ? toRow : (2 - toRow);

    return OnlineAction(
      type: OnlineActionType.move,
      byPlayerId: myPlayerId,
      cardInstanceId: card.id,
      cardName: card.name,
      fromRow: canonicalFromRow,
      fromCol: fromCol,
      toRow: canonicalToRow,
      toCol: toCol,
    );
  }

  /// Create an attack action
  OnlineAction createAttackAction({
    required GameCard attacker,
    required int attackerRow,
    required int attackerCol,
    required GameCard target,
    required int targetRow,
    required int targetCol,
  }) {
    final canonicalAttackerRow = amPlayer1 ? attackerRow : (2 - attackerRow);
    final canonicalTargetRow = amPlayer1 ? targetRow : (2 - targetRow);

    return OnlineAction(
      type: OnlineActionType.attack,
      byPlayerId: myPlayerId,
      cardInstanceId: attacker.id,
      cardName: attacker.name,
      fromRow: canonicalAttackerRow,
      fromCol: attackerCol,
      targetId: target.id,
      targetRow: canonicalTargetRow,
      targetCol: targetCol,
    );
  }

  /// Create an attackBase action
  OnlineAction createAttackBaseAction({
    required GameCard attacker,
    required int attackerRow,
    required int attackerCol,
  }) {
    final canonicalRow = amPlayer1 ? attackerRow : (2 - attackerRow);

    return OnlineAction(
      type: OnlineActionType.attackBase,
      byPlayerId: myPlayerId,
      cardInstanceId: attacker.id,
      cardName: attacker.name,
      fromRow: canonicalRow,
      fromCol: attackerCol,
    );
  }

  /// Create an endTurn action
  OnlineAction createEndTurnAction({required int turnNumber}) {
    return OnlineAction(
      type: OnlineActionType.endTurn,
      byPlayerId: myPlayerId,
      turnNumber: turnNumber,
    );
  }
}
