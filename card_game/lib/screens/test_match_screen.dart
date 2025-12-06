import 'dart:async';
import 'dart:math';
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
import '../models/game_board.dart';
import '../data/hero_library.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';
import '../services/auth_service.dart';
import '../services/deck_storage_service.dart';
import '../services/combat_resolver.dart' show AttackResult;
import '../services/online_game_manager.dart';

/// Test screen for playing a match vs AI opponent or online multiplayer
class TestMatchScreen extends StatefulWidget {
  final GameHero? selectedHero;
  final String? onlineMatchId; // If provided, plays online multiplayer
  final bool
  forceCampaignDeck; // If true, use hero's campaign deck instead of saved deck
  final Deck? enemyDeck; // Custom enemy deck (for campaign battles)
  final int campaignAct; // Current campaign act (1, 2, or 3)

  const TestMatchScreen({
    super.key,
    this.selectedHero,
    this.onlineMatchId,
    this.forceCampaignDeck = false,
    this.enemyDeck,
    this.campaignAct = 1,
  });

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

  // Hero selection for online mode
  GameHero? _selectedHero;
  GameHero? _opponentHero;
  bool _heroSelectionComplete = false;
  String?
  _firstPlayerId; // Who goes first in online mode (determined by player1)

  // Board setup for online mode (determined by Player 1)
  List<List<String>>? _predefinedTerrains; // Terrain grid from host
  int? _predefinedRelicColumn; // Relic column from host

  // Opponent's deck card names (synced from Firebase for online mode)
  List<String>? _opponentDeckCardNames;

  // OnlineGameManager for state-based sync (TYC3 online mode)
  OnlineGameManager? _onlineGameManager;
  StreamSubscription<MatchState>? _onlineStateSubscription;

  // Track last seen combat result ID to avoid showing duplicates
  String? _lastSeenCombatResultId;

  // ===== TYC3: Turn-based AP system state =====
  bool _useTYC3Mode = true; // Enable TYC3 by default for testing
  Timer? _turnTimer;
  int _turnSecondsRemaining = 100;

  // TYC3 action state
  GameCard? _selectedCardForAction; // Card selected for move/attack
  int? _selectedCardRow;
  int? _selectedCardCol;
  String? _currentAction; // 'move', 'attack', or null
  List<GameCard> _validTargets = [];

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
    _turnTimer?.cancel();
    _onlineStateSubscription?.cancel();
    _onlineGameManager?.dispose();
    super.dispose();
  }

  // ===== TYC3: Turn timer methods =====

  void _startTurnTimer() {
    // Only use timer in online mode - no timer for vs AI
    if (!_isOnlineMode) return;

    _turnTimer?.cancel();
    _turnSecondsRemaining = 100;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _turnSecondsRemaining--;
        if (_turnSecondsRemaining <= 0) {
          timer.cancel();
          // Auto-end turn when timer expires
          if (_matchManager.isPlayerTurn) {
            _endTurnTYC3();
          }
        }
      });
    });
  }

  /// Sync current game state to Firebase (for online mode)
  /// Call this after every action (place, move, attack, end turn)
  /// Only syncs if it's currently our turn (we're the authority)
  void _syncOnlineState() {
    if (_onlineGameManager == null || _matchManager.currentMatch == null)
      return;

    // Only sync if it's our turn - we're the authority during our turn
    if (!_matchManager.isPlayerTurn) {
      debugPrint('⚠️ Not syncing - not our turn');
      return;
    }

    _onlineGameManager!.syncState(_matchManager.currentMatch!);
  }

  /// Handle incoming state update from opponent (via Firebase stream)
  void _onOpponentStateUpdate(MatchState newState) {
    debugPrint('📥 Received opponent state update');
    debugPrint(
      '📥 New state: turnNumber=${newState.turnNumber}, activePlayerId=${newState.activePlayerId}, player.id=${newState.player.id}, opponent.id=${newState.opponent.id}',
    );

    // Check if it's currently our turn locally
    final wasMyTurn = _matchManager.isPlayerTurn;

    // Check for new combat result to show dialog (before replacing state)
    final combatResult = newState.lastCombatResult;
    if (combatResult != null && combatResult.id != _lastSeenCombatResultId) {
      // New combat result from opponent - show dialog
      _lastSeenCombatResultId = combatResult.id;
      debugPrint(
        '📥 New combat result: ${combatResult.attackerName} -> ${combatResult.targetName}',
      );

      // Show dialog after state update
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSyncedCombatResultDialog(combatResult);
        }
      });
    }

    // Replace local match state with the received state
    _matchManager.replaceMatchState(newState);

    // Check if turn changed
    final isMyTurnNow = _matchManager.isPlayerTurn;
    debugPrint('📥 Turn state: wasMyTurn=$wasMyTurn, isMyTurnNow=$isMyTurnNow');

    if (isMyTurnNow && !wasMyTurn) {
      // Turn just switched to us - start timer
      debugPrint('🔄 Turn switched to us!');
      _startTurnTimer();
    } else if (!isMyTurnNow && wasMyTurn) {
      // Turn just switched away from us - stop timer
      debugPrint('🔄 Turn switched to opponent');
      _turnTimer?.cancel();
    }

    // Refresh UI
    if (mounted) setState(() {});
  }

  void _endTurnTYC3() {
    _turnTimer?.cancel();

    // NEW: Use OnlineGameManager for online mode if available
    if (_onlineGameManager != null) {
      // Apply locally first (same logic as vs-AI)
      _matchManager.endTurnTYC3();
      _clearTYC3Selection();
      _selectedCard = null;

      // FORCE sync the end turn state - this is critical because after endTurnTYC3(),
      // isPlayerTurn becomes false, but we MUST sync to notify opponent it's their turn
      if (_matchManager.currentMatch != null) {
        debugPrint('🔄 Force syncing end turn state');
        _onlineGameManager!.syncState(_matchManager.currentMatch!);
      }

      // Timer will be managed by stream listener when turn changes
      setState(() {});
      return;
    }

    // LEGACY: Old online mode path
    // ONLINE, non-host player: do NOT mutate MatchManager turn state.
    // Just send endTurn action; host will call endTurnTYC3 and sync.
    if (_isOnlineMode && !_amPlayer1) {
      _clearTYC3Selection();
      _selectedCard = null; // Also clear hand card selection

      _syncTYC3Action('endTurn', {
        'turnNumber': _matchManager.currentMatch?.turnNumber ?? 0,
      });

      setState(() {});
      return;
    }

    _matchManager.endTurnTYC3();
    _clearTYC3Selection();
    _selectedCard = null; // Also clear hand card selection

    // Sync to Firebase if online
    if (_isOnlineMode) {
      _syncTYC3Action('endTurn', {
        'turnNumber': _matchManager.currentMatch?.turnNumber ?? 0,
      });
      // Don't start timer - wait for opponent's turn to complete via Firebase
    } else if (_matchManager.isOpponentTurn) {
      // Single player: AI's turn
      _doAITurnTYC3();
    } else {
      // Start timer for player's next turn
      _startTurnTimer();
    }
    setState(() {});
  }

  void _clearTYC3Selection() {
    _selectedCardForAction = null;
    _selectedCardRow = null;
    _selectedCardCol = null;
    _currentAction = null;
    _validTargets = [];
  }

  /// TYC3: Place a card from hand onto a tile
  void _placeCardTYC3(int row, int col) {
    if (_selectedCard == null) return;

    // Check if it's player's turn.
    // For online non-host, host is authoritative; we still gate by isPlayerTurn
    // (which comes from Firebase), but avoid additional local restrictions.
    if (!_matchManager.isPlayerTurn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("It's not your turn!")));
      return;
    }

    // Check if can play more cards for local-authoritative modes (offline/host).
    // For online non-host, host enforces limits when applying the action.
    final shouldCheckCardLimit = !_isOnlineMode || _amPlayer1;
    if (shouldCheckCardLimit && !_matchManager.canPlayMoreCards) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Card limit reached (${_matchManager.maxCardsThisTurn} per turn)',
          ),
        ),
      );
      return;
    }

    // Check tile capacity before trying to place
    final match = _matchManager.currentMatch;
    if (match != null) {
      final tile = match.board.getTile(row, col);
      if (tile.cards.length >= Tile.maxCards) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tile is full (max ${Tile.maxCards} cards per tile)'),
          ),
        );
        return;
      }
    }

    // Try to place the card
    final card = _selectedCard!;

    // NEW: Use OnlineGameManager for online mode if available
    if (_onlineGameManager != null) {
      // Apply locally first (same logic as vs-AI)
      final success = _matchManager.placeCardTYC3(card, row, col);
      if (success) {
        // Sync state to Firebase so opponent sees the action
        _syncOnlineState();
        _selectedCard = null;
        setState(() {});
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cannot place card here')));
      }
      return;
    }

    // LEGACY: Old online mode path (will be removed once OnlineGameManager is stable)
    bool success = false;
    final cardName = card.name;

    if (_isOnlineMode && !_amPlayer1) {
      // ONLINE, non-host player: do NOT mutate local MatchManager.
      // Just send the action to Firebase; host will apply it and sync state.
      _syncTYC3Action('place', {'cardName': cardName, 'row': row, 'col': col});
      success = true; // allow local UI to clear selection
    } else {
      // Offline or host: apply to local MatchManager
      success = _matchManager.placeCardTYC3(card, row, col);

      if (success && _isOnlineMode) {
        // Host also logs the action
        _syncTYC3Action('place', {
          'cardName': cardName,
          'row': row,
          'col': col,
        });
      }
    }

    if (success) {
      _selectedCard = null;
      setState(() {});
    } else {
      // Generic fallback - shouldn't normally reach here
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot place card here')));
    }
  }

  /// TYC3: Select a card on the board for action (move/attack)
  void _selectCardForAction(GameCard card, int row, int col) {
    // Check if it's player's turn
    if (!_matchManager.isPlayerTurn) return;

    // Check if this is a player card (row 1-2)
    if (row == 0) return; // Can't select enemy cards

    // Check if card has any AP to do anything
    if (card.currentAP <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${card.name} has no AP left this turn'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      if (_selectedCardForAction == card) {
        // Deselect if already selected
        _clearTYC3Selection();
      } else {
        // Clear any hand card selection first
        _selectedCard = null;

        _selectedCardForAction = card;
        _selectedCardRow = row;
        _selectedCardCol = col;
        _currentAction = null;

        // Get all reachable attack targets (including move+attack combinations)
        // This shows all enemies the card can attack using its full AP
        final reachableTargets = _matchManager.getReachableAttackTargets(
          card,
          row,
          col,
        );
        _validTargets = reachableTargets.map((t) => t.target).toList();
      }
    });
  }

  /// TYC3: Perform attack on a target
  void _attackTargetTYC3(GameCard target, int targetRow, int targetCol) {
    if (_selectedCardForAction == null ||
        _selectedCardRow == null ||
        _selectedCardCol == null)
      return;

    final attacker = _selectedCardForAction!;

    // Show attack preview dialog
    _showAttackPreviewDialog(
      attacker: attacker,
      target: target,
      attackerRow: _selectedCardRow!,
      attackerCol: _selectedCardCol!,
      targetRow: targetRow,
      targetCol: targetCol,
    );
  }

  /// Get lane name from column index
  String _getLaneName(int col) {
    return ['West', 'Center', 'East'][col];
  }

  /// Get row name
  String _getRowName(int row) {
    return ['Enemy Base', 'Middle', 'Your Base'][row];
  }

  /// Show attack preview dialog with predicted outcome
  void _showAttackPreviewDialog({
    required GameCard attacker,
    required GameCard target,
    required int attackerRow,
    required int attackerCol,
    required int targetRow,
    required int targetCol,
  }) {
    // Get preview from combat resolver (includes terrain buff)
    final preview = _matchManager.previewAttackTYC3(
      attacker,
      target,
      targetRow,
      targetCol,
    );

    // Calculate terrain buffs for display
    final match = _matchManager.currentMatch;
    final targetTile = match?.board.getTile(targetRow, targetCol);
    final tileTerrain = targetTile?.terrain;
    final attackerHasTerrainBuff =
        tileTerrain != null && attacker.element == tileTerrain;
    final defenderHasTerrainBuff =
        tileTerrain != null && target.element == tileTerrain;

    final attackerHpAfter = (attacker.currentHealth - preview.retaliationDamage)
        .clamp(0, attacker.health);
    final targetHpAfter = (target.currentHealth - preview.damageDealt).clamp(
      0,
      target.health,
    );

    final laneName = _getLaneName(attackerCol);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text('⚔️ Attack Preview', textAlign: TextAlign.center),
            Text(
              '$laneName Lane',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attacker and Target side by side
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Attacker
                _buildCombatCardPreview(
                  card: attacker,
                  label: 'ATTACKER',
                  hpAfter: attackerHpAfter,
                  willDie: preview.attackerDied,
                  color: Colors.blue,
                ),
                // Arrow with damage info
                Column(
                  children: [
                    Text(
                      '${preview.damageDealt}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    if (attackerHasTerrainBuff)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '+1 ',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            _getTerrainIcon(tileTerrain!),
                            size: 12,
                            color: _getTerrainColor(tileTerrain),
                          ),
                        ],
                      ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 32,
                      color: Colors.red,
                    ),
                    if (preview.retaliationDamage > 0) ...[
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.arrow_back,
                        size: 24,
                        color: Colors.orange,
                      ),
                      Text(
                        '${preview.retaliationDamage}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      if (defenderHasTerrainBuff)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '+1 ',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              _getTerrainIcon(tileTerrain!),
                              size: 12,
                              color: _getTerrainColor(tileTerrain),
                            ),
                          ],
                        ),
                      const Text(
                        'retaliation',
                        style: TextStyle(fontSize: 10, color: Colors.orange),
                      ),
                    ],
                  ],
                ),
                // Target
                _buildCombatCardPreview(
                  card: target,
                  label: 'TARGET',
                  hpAfter: targetHpAfter,
                  willDie: preview.targetDied,
                  color: Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Outcome summary
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  if (preview.targetDied)
                    const Text(
                      '💀 Target will be KILLED!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (preview.attackerDied)
                    const Text(
                      '⚠️ Attacker will DIE from retaliation!',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (!preview.targetDied && !preview.attackerDied)
                    const Text(
                      'Both units survive',
                      style: TextStyle(color: Colors.green),
                    ),
                  if (attacker.isRanged && !preview.targetDied)
                    const Text(
                      '🏹 Ranged - No retaliation',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeAttackTYC3(
                attacker,
                target,
                attackerRow,
                attackerCol,
                targetRow,
                targetCol,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              '⚔️ ATTACK',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a card preview for combat dialog
  Widget _buildCombatCardPreview({
    required GameCard card,
    required String label,
    required int hpAfter,
    required bool willDie,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 80,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: willDie ? Colors.red[100] : color.withOpacity(0.1),
            border: Border.all(color: willDie ? Colors.red : color, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                card.name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    size: 12,
                    color: Colors.orange,
                  ),
                  Text('${card.damage}', style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, size: 12, color: Colors.red),
                  Text(
                    '${card.currentHealth} → $hpAfter',
                    style: TextStyle(
                      fontSize: 12,
                      color: willDie ? Colors.red : Colors.black,
                      fontWeight: willDie ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (willDie) const Text('💀', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }

  /// Execute the attack after confirmation
  void _executeAttackTYC3(
    GameCard attacker,
    GameCard target,
    int attackerRow,
    int attackerCol,
    int targetRow,
    int targetCol,
  ) {
    // Check if we need to move first to reach the target
    // Find the best position to attack from (may require moving)
    final reachableTargets = _matchManager.getReachableAttackTargets(
      attacker,
      attackerRow,
      attackerCol,
    );

    final targetInfo = reachableTargets
        .where((t) => t.target == target)
        .firstOrNull;
    if (targetInfo == null) {
      debugPrint('❌ Target not reachable');
      _clearTYC3Selection();
      setState(() {});
      return;
    }

    // Move to attack position if needed
    int currentRow = attackerRow;
    int currentCol = attackerCol;
    if (targetInfo.moveCost > 0) {
      // Need to move first - find path to attack position
      final destRow = targetInfo.row;
      final destCol = targetInfo.col;

      // Move step by step (simplified - just move directly if adjacent)
      while (currentRow != destRow || currentCol != destCol) {
        int nextRow = currentRow;
        int nextCol = currentCol;

        if (currentRow > destRow)
          nextRow--;
        else if (currentRow < destRow)
          nextRow++;
        else if (currentCol > destCol)
          nextCol--;
        else if (currentCol < destCol)
          nextCol++;

        final moved = _matchManager.moveCardTYC3(
          attacker,
          currentRow,
          currentCol,
          nextRow,
          nextCol,
        );

        if (!moved) {
          debugPrint('❌ Move failed during attack approach');
          break;
        }

        currentRow = nextRow;
        currentCol = nextCol;
      }
    }

    // NEW: Use OnlineGameManager for online mode if available
    if (_onlineGameManager != null) {
      // Apply locally first (same logic as vs-AI)
      final result = _matchManager.attackCardTYC3(
        attacker,
        target,
        currentRow,
        currentCol,
        targetRow,
        targetCol,
      );

      if (result != null) {
        // Sync state to Firebase so opponent sees the action
        _syncOnlineState();

        // Show battle result dialog (same as vs-AI)
        _showBattleResultDialog(result, attacker, target, currentCol);
      }

      _clearTYC3Selection();
      setState(() {});
      return;
    }

    // LEGACY: Old online mode path
    final attackerName = attacker.name;
    final targetName = target.name;

    final result = _matchManager.attackCardTYC3(
      attacker,
      target,
      currentRow,
      currentCol,
      targetRow,
      targetCol,
    );

    // Sync to Firebase if online
    if (_isOnlineMode && result != null) {
      _syncTYC3Action('attack', {
        'attackerName': attackerName,
        'targetName': targetName,
        'attackerRow': attackerRow,
        'attackerCol': attackerCol,
        'targetRow': targetRow,
        'targetCol': targetCol,
        'damageDealt': result.damageDealt,
        'retaliationDamage': result.retaliationDamage,
        'targetDied': result.targetDied,
        'attackerDied': result.attackerDied,
      });
    }

    // Clear selection first to avoid stale references
    _clearTYC3Selection();

    if (result != null && mounted) {
      // Show battle result dialog
      _showBattleResultDialog(result, attacker, target, attackerCol);
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Show battle result dialog with animation
  void _showBattleResultDialog(
    AttackResult result,
    GameCard attacker,
    GameCard target,
    int col,
  ) {
    final laneName = _getLaneName(col);
    bool dialogDismissed = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        // Auto-dismiss after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (!dialogDismissed && mounted && Navigator.canPop(dialogContext)) {
            dialogDismissed = true;
            Navigator.pop(dialogContext);
          }
        });

        return AlertDialog(
          title: Column(
            children: [
              const Text('⚔️ Battle Result'),
              Text(
                '$laneName Lane',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Attack damage
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      attacker.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(' dealt '),
                    Text(
                      '${result.damageDealt}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const Text(' damage'),
                    if (result.targetDied)
                      const Text(' 💀', style: TextStyle(fontSize: 20)),
                  ],
                ),
              ),

              // Retaliation
              if (result.retaliationDamage > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        target.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(' retaliated for '),
                      Text(
                        '${result.retaliationDamage}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      if (result.attackerDied)
                        const Text(' 💀', style: TextStyle(fontSize: 20)),
                    ],
                  ),
                ),
              ],

              // Summary
              const SizedBox(height: 12),
              if (result.targetDied && result.attackerDied)
                const Text(
                  '💀 Both units destroyed!',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (result.targetDied)
                Text(
                  '💀 ${target.name} destroyed!',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (result.attackerDied)
                Text(
                  '💀 ${attacker.name} destroyed!',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                dialogDismissed = true;
                Navigator.pop(dialogContext);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show battle result dialog for AI attacks (async, waits for dismiss)
  Future<void> _showAIBattleResultDialog(
    AttackResult result,
    GameCard attacker,
    GameCard target,
    int col,
  ) async {
    final laneName = _getLaneName(col);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text('🤖 Enemy Attack!', textAlign: TextAlign.center),
            Text(
              '$laneName Lane',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attack damage
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    attacker.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('dealt '),
                      Text(
                        '${result.damageDealt}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const Text(' damage to'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    target.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                  if (result.targetDied)
                    const Text(
                      '💀 DESTROYED!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                ],
              ),
            ),

            // Retaliation
            if (result.retaliationDamage > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      result.targetDied
                          ? '↩️ Retaliation (before dying)'
                          : '↩️ Retaliation',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          target.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(' dealt '),
                        Text(
                          '${result.retaliationDamage}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const Text(' to '),
                        Text(
                          attacker.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (result.attackerDied)
                      const Text(
                        '💀 ATTACKER DESTROYED!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Brief pause after dialog closes
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Show dialog when AI attacks player's base
  Future<void> _showAIBaseAttackDialog(
    GameCard attacker,
    int damage,
    int col,
  ) async {
    final match = _matchManager.currentMatch;
    final playerHp = match?.player.baseHP ?? 0;
    final laneName = _getLaneName(col);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text('⚠️ BASE UNDER ATTACK!', textAlign: TextAlign.center),
            Text(
              '$laneName Lane',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        backgroundColor: Colors.red[50],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red, width: 3),
              ),
              child: Column(
                children: [
                  Text(
                    attacker.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('attacked your base for'),
                  const SizedBox(height: 4),
                  Text(
                    '$damage',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const Text(
                    'DAMAGE!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.favorite, color: Colors.red, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Base HP: $playerHp',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    // Brief pause after dialog closes
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Show combat result dialog from synced PvP state
  /// This is called when opponent attacks and we receive the result via Firebase
  Future<void> _showSyncedCombatResultDialog(SyncedCombatResult result) async {
    final laneName = _getLaneName(result.laneCol);
    final isOpponentAttacking = result.attackerOwnerId != _playerId;

    // Determine dialog style based on who is attacking
    final titleEmoji = isOpponentAttacking ? '🤖' : '⚔️';
    final titleText = isOpponentAttacking ? 'Enemy Attack!' : 'Your Attack';
    final bgColor = isOpponentAttacking ? Colors.red[50] : Colors.blue[50];
    final accentColor = isOpponentAttacking ? Colors.red : Colors.blue;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            Text('$titleEmoji $titleText', textAlign: TextAlign.center),
            Text(
              '$laneName Lane',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        backgroundColor: bgColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attack damage
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    result.attackerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('dealt '),
                      Text(
                        '${result.damageDealt}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                      const Text(' damage to'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.targetName ?? 'Base',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isOpponentAttacking ? Colors.blue : Colors.red,
                    ),
                  ),
                  if (result.isBaseAttack && result.targetHpAfter != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, color: Colors.red, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          'Base HP: ${result.targetHpAfter}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                  if (result.targetDied)
                    Text(
                      result.isBaseAttack ? '🏆 VICTORY!' : '💀 DESTROYED!',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                ],
              ),
            ),

            // Retaliation (only for card attacks)
            if (!result.isBaseAttack && result.retaliationDamage > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      result.targetDied
                          ? '↩️ Retaliation (before dying)'
                          : '↩️ Retaliation',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          result.targetName ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(' dealt '),
                        Text(
                          '${result.retaliationDamage}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const Text(' to '),
                        Text(
                          result.attackerName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (result.attackerDied)
                      const Text(
                        '💀 ATTACKER DESTROYED!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    // Brief pause after dialog closes
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// TYC3: Move card to a tile (supports multi-step moves if card has enough AP)
  void _moveCardTYC3(int toRow, int toCol) {
    if (_selectedCardForAction == null ||
        _selectedCardRow == null ||
        _selectedCardCol == null)
      return;

    final card = _selectedCardForAction!;
    final fromRow = _selectedCardRow!;
    final fromCol = _selectedCardCol!;

    // Check if this is a valid destination using reachable tiles
    final reachableTiles = _matchManager.getReachableTiles(
      card,
      fromRow,
      fromCol,
    );
    final targetTile = reachableTiles
        .where((t) => t.row == toRow && t.col == toCol)
        .firstOrNull;

    if (targetTile == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot reach that tile')));
      return;
    }

    // Move step by step to reach the destination
    int currentRow = fromRow;
    int currentCol = fromCol;

    while (currentRow != toRow || currentCol != toCol) {
      // Determine next step (prioritize row movement, then column)
      int nextRow = currentRow;
      int nextCol = currentCol;

      // Simple pathfinding: move toward target one step at a time
      if (currentRow < toRow)
        nextRow++;
      else if (currentRow > toRow)
        nextRow--;
      else if (currentCol < toCol)
        nextCol++;
      else if (currentCol > toCol)
        nextCol--;

      final moved = _matchManager.moveCardTYC3(
        card,
        currentRow,
        currentCol,
        nextRow,
        nextCol,
      );
      if (!moved) {
        // Path blocked, try alternative direction
        if (currentCol != toCol && currentRow == nextRow) {
          // Was trying horizontal, try vertical first
          nextRow = currentRow;
          nextCol = currentCol;
          if (currentRow < toRow)
            nextRow++;
          else if (currentRow > toRow)
            nextRow--;
          else
            break; // No valid move

          final altMoved = _matchManager.moveCardTYC3(
            card,
            currentRow,
            currentCol,
            nextRow,
            nextCol,
          );
          if (!altMoved) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Path blocked')));
            break;
          }
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Path blocked')));
          break;
        }
      }

      currentRow = nextRow;
      currentCol = nextCol;
    }

    // Sync state for online mode
    if (_onlineGameManager != null) {
      _syncOnlineState();
    } else if (_isOnlineMode) {
      // LEGACY: Old online mode path
      _syncTYC3Action('move', {
        'cardName': card.name,
        'fromRow': fromRow,
        'fromCol': fromCol,
        'toRow': toRow,
        'toCol': toCol,
      });
    }

    // Clear selection after move
    _clearTYC3Selection();
    setState(() {});
  }

  /// TYC3: Handle tap on a tile (place card or move to)
  void _onTileTapTYC3(
    int row,
    int col,
    bool canPlace,
    bool canMoveTo,
    bool canAttackBase,
  ) {
    // If we can attack the enemy base, show preview
    if (canAttackBase && _selectedCardForAction != null) {
      _showBaseAttackPreviewDialog(row, col);
      return;
    }

    // If we can move to this tile, do it
    if (canMoveTo && _selectedCardForAction != null) {
      _moveCardTYC3(row, col);
      return;
    }

    // If we can place a card here, do it
    if (canPlace && _selectedCard != null) {
      _placeCardOnTile(row, col);
      return;
    }

    // Otherwise, clear selection if we have one
    if (_selectedCardForAction != null) {
      _clearTYC3Selection();
      setState(() {});
    }
  }

  /// Show preview dialog for attacking enemy base
  void _showBaseAttackPreviewDialog(int row, int col) {
    if (_selectedCardForAction == null ||
        _selectedCardRow == null ||
        _selectedCardCol == null)
      return;

    final attacker = _selectedCardForAction!;
    final match = _matchManager.currentMatch;
    if (match == null) return;

    // Calculate terrain buff
    final baseTile = match.board.getTile(row, col);
    final tileTerrain = baseTile.terrain;
    final hasTerrainBuff =
        tileTerrain != null && attacker.element == tileTerrain;
    final terrainBonus = hasTerrainBuff ? 1 : 0;

    final enemyHp = match.opponent.baseHP;
    final baseDamage = attacker.damage;
    final totalDamage = baseDamage + terrainBonus;
    final hpAfter = (enemyHp - totalDamage).clamp(0, 999);
    final willWin = hpAfter <= 0;
    final laneName = _getLaneName(col);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text('🏰 Attack Enemy Base?', textAlign: TextAlign.center),
            Text(
              '$laneName Lane',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    attacker.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('will deal '),
                      Text(
                        '$totalDamage',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const Text(' damage'),
                    ],
                  ),
                  // Show terrain buff breakdown
                  if (hasTerrainBuff)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '($baseDamage base + $terrainBonus ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            _getTerrainIcon(tileTerrain!),
                            size: 14,
                            color: _getTerrainColor(tileTerrain),
                          ),
                          Text(
                            ')',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.favorite, color: Colors.red, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        'Enemy Base: $enemyHp → $hpAfter',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  if (willWin)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '🏆 VICTORY!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeBaseAttackTYC3(col);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              '🏰 ATTACK BASE',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Execute attack on enemy base
  void _executeBaseAttackTYC3(int col) {
    if (_selectedCardForAction == null ||
        _selectedCardRow == null ||
        _selectedCardCol == null)
      return;

    final attacker = _selectedCardForAction!;
    final attackerRow = _selectedCardRow!;
    final attackerCol = _selectedCardCol!;

    // NEW: Use OnlineGameManager for online mode if available
    if (_onlineGameManager != null) {
      // Apply locally first (same logic as vs-AI)
      final damage = _matchManager.attackBaseTYC3(
        attacker,
        attackerRow,
        attackerCol,
      );
      if (damage > 0) {
        // Sync state to Firebase so opponent sees the action
        _syncOnlineState();
      }
      _clearTYC3Selection();
      setState(() {});
      return;
    }

    // LEGACY: Old online mode path
    final attackerName = attacker.name;

    if (_isOnlineMode && !_amPlayer1) {
      // ONLINE, non-host player: send intent only; host computes damage.
      _syncTYC3Action('attackBase', {
        'attackerName': attackerName,
        'attackerRow': attackerRow,
        'attackerCol': attackerCol,
      });
      // For now, skip local damage dialog – host will update HP via state sync.
      _clearTYC3Selection();
      return;
    }

    final damage = _matchManager.attackBaseTYC3(
      attacker,
      attackerRow,
      attackerCol,
    );

    if (damage > 0) {
      // Sync to Firebase if online (host only)
      if (_isOnlineMode) {
        _syncTYC3Action('attackBase', {
          'attackerName': attackerName,
          'attackerRow': attackerRow,
          'attackerCol': attackerCol,
          'damage': damage,
        });
      }
      final match = _matchManager.currentMatch;
      final enemyHp = match?.opponent.baseHP ?? 0;
      final laneName = _getLaneName(col);
      bool dialogDismissed = false;

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          // Auto-dismiss after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (!dialogDismissed &&
                mounted &&
                Navigator.canPop(dialogContext)) {
              dialogDismissed = true;
              Navigator.pop(dialogContext);
            }
          });

          return AlertDialog(
            title: Column(
              children: [
                const Text('🏰 Base Attacked!'),
                Text(
                  '$laneName Lane',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${attacker.name} dealt $damage damage!',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.favorite,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Enemy Base HP: $enemyHp',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      if (enemyHp <= 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '🏆 VICTORY!',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  dialogDismissed = true;
                  Navigator.pop(dialogContext);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }

    _clearTYC3Selection();
    setState(() {});
  }

  /// TYC3: Handle tap on a card (select for action or attack target)
  void _onCardTapTYC3(
    GameCard card,
    int row,
    int col,
    bool isPlayerCard,
    bool isOpponent,
  ) {
    if (!_useTYC3Mode) return;

    // Not player's turn - do nothing
    if (!_matchManager.isPlayerTurn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("It's not your turn!")));
      return;
    }

    // If we have a card selected and this is a valid target, attack it
    if (_selectedCardForAction != null && _validTargets.contains(card)) {
      _attackTargetTYC3(card, row, col);
      return;
    }

    // If tapping a player card, select it for action
    if (isPlayerCard && row >= 1) {
      // Player cards are in row 1-2
      _selectCardForAction(card, row, col);
      return;
    }

    // If tapping an opponent card without selection, show details
    if (isOpponent) {
      _showCardDetails(card);
    }
  }

  /// Count AI cards in a specific lane (all rows)
  int _countAICardsInLane(MatchState match, int col) {
    int count = 0;
    for (int row = 0; row < 3; row++) {
      final tile = match.board.getTile(row, col);
      count += tile.cards
          .where((c) => c.ownerId == match.opponent.id && c.isAlive)
          .length;
    }
    return count;
  }

  Future<void> _doAITurnTYC3() async {
    // Guard: Only run if it's actually the AI's turn
    if (!_matchManager.isOpponentTurn) {
      debugPrint('ERROR: _doAITurnTYC3 called but it is NOT opponent turn!');
      return;
    }

    final match = _matchManager.currentMatch;
    if (match == null) return;

    debugPrint(
      'AI TURN START - isOpponentTurn: ${_matchManager.isOpponentTurn}',
    );

    // Wait a bit for visual feedback
    await Future.delayed(const Duration(milliseconds: 500));

    // AI places cards with smart lane selection
    final hand = match.opponent.hand;
    final maxCards = _matchManager.maxCardsThisTurn;
    int cardsPlaced = 0;
    final random = Random();

    // Shuffle hand for variety
    final shuffledHand = hand.toList()..shuffle(random);

    for (final card in shuffledHand) {
      if (cardsPlaced >= maxCards) break;

      // Smart lane selection: prefer lanes with fewer enemy cards or matching terrain
      final laneScores = <int, double>{};
      for (int col = 0; col < 3; col++) {
        double score = random.nextDouble() * 2; // Base randomness (0-2)

        // Check player presence in this lane (middle row)
        final middleTile = match.board.getTile(1, col);
        final playerCardsInMiddle = middleTile.cards
            .where((c) => c.ownerId == match.player.id && c.isAlive)
            .length;

        // Prefer lanes where player has cards (to contest)
        score += playerCardsInMiddle * 1.5;

        // Check AI presence in this lane
        final aiCardsInLane = _countAICardsInLane(match, col);
        // Spread cards across lanes (penalty for overcrowding)
        score -= aiCardsInLane * 0.5;

        // Terrain bonus: prefer placing cards on matching terrain
        final baseTile = match.board.getTile(0, col);
        if (baseTile.terrain != null && card.element == baseTile.terrain) {
          score += 2.0;
        }

        laneScores[col] = score;
      }

      // Sort lanes by score (highest first)
      final sortedLanes = laneScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Try to place in best lane
      for (final entry in sortedLanes) {
        if (_matchManager.placeCardTYC3(card, 0, entry.key)) {
          cardsPlaced++;
          debugPrint(
            'AI placed ${card.name} in lane ${entry.key} (score: ${entry.value.toStringAsFixed(1)})',
          );
          if (mounted) setState(() {});
          await Future.delayed(const Duration(milliseconds: 200));
          break;
        }
      }
    }

    // AI moves cards forward with smart decisions
    // Collect all AI cards that can move
    final movableCards = <({GameCard card, int row, int col})>[];
    for (int row = 0; row <= 1; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final card in tile.cards) {
          if (card.isAlive &&
              card.canMove() &&
              card.ownerId == match.opponent.id) {
            movableCards.add((card: card, row: row, col: col));
          }
        }
      }
    }

    // Shuffle for variety
    movableCards.shuffle(random);

    for (final entry in movableCards) {
      final card = entry.card;
      final row = entry.row;
      final col = entry.col;

      if (!card.canMove()) continue; // May have used AP

      final targetRow = row + 1;
      if (targetRow > 2) continue;

      // Check if moving is beneficial
      final targetTile = match.board.getTile(targetRow, col);
      final hasEnemyCards = targetTile.cards.any(
        (c) => c.ownerId == match.player.id && c.isAlive,
      );

      // Don't move if enemies block (need to attack first)
      if (hasEnemyCards) continue;

      // Random chance to not move (adds unpredictability)
      if (random.nextDouble() < 0.2) continue;

      if (_matchManager.moveCardTYC3(card, row, col, targetRow, col)) {
        debugPrint('AI moved ${card.name} from row $row to row $targetRow');
        if (mounted) setState(() {});
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    // AI attacks with cards that have AP
    // Collect all AI cards that can attack
    final attackers = <({GameCard card, int row, int col})>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final card in tile.cards) {
          if (card.isAlive &&
              card.canAttack() &&
              card.ownerId == match.opponent.id) {
            attackers.add((card: card, row: row, col: col));
          }
        }
      }
    }

    // Shuffle attackers for variety
    attackers.shuffle(random);

    for (final entry in attackers) {
      final card = entry.card;
      final row = entry.row;
      final col = entry.col;

      if (!card.canAttack()) continue; // May have used AP

      // Try to attack enemy cards
      final targets = _matchManager.getValidTargetsTYC3(card, row, col);
      if (targets.isNotEmpty) {
        // Smart target selection: prefer low HP targets or high damage targets
        targets.sort((a, b) {
          // Prioritize targets we can kill
          final canKillA = a.currentHealth <= card.damage ? 1 : 0;
          final canKillB = b.currentHealth <= card.damage ? 1 : 0;
          if (canKillA != canKillB) return canKillB - canKillA;

          // Then prioritize high damage targets
          return b.damage - a.damage;
        });

        final target = targets.first;
        // Find target position
        for (int tr = 0; tr < 3; tr++) {
          for (int tc = 0; tc < 3; tc++) {
            final targetTile = match.board.getTile(tr, tc);
            if (targetTile.cards.contains(target)) {
              final result = _matchManager.attackCardTYC3(
                card,
                target,
                row,
                col,
                tr,
                tc,
              );
              if (result != null) {
                debugPrint('AI: ${result.message}');
                if (mounted) {
                  setState(() {});
                  await _showAIBattleResultDialog(result, card, target, col);
                }
              }
              break;
            }
          }
        }
      }

      // Try to attack player base if in range (row 1 or 2 for AI attacking player base at row 2)
      // AI cards attack player base (row 2), so they need to be within attack range
      final distanceToPlayerBase = (2 - row).abs();
      if (distanceToPlayerBase <= card.attackRange && card.canAttack()) {
        final damage = _matchManager.attackBaseTYC3(card, row, col);
        if (damage > 0) {
          debugPrint('AI attacked player base for $damage damage!');
          if (mounted) {
            setState(() {});
            await _showAIBaseAttackDialog(card, damage, col);
          }
        }
      }
    }

    // End AI turn
    await Future.delayed(const Duration(milliseconds: 300));
    _matchManager.endTurnTYC3();
    _startTurnTimer();
    if (mounted) setState(() {});
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
      _mySubmitted = false;
      _opponentSubmitted = false;
      _waitingForOpponent = false;
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
      debugPrint('Online init: playerId=$_playerId, amPlayer1=$_amPlayer1');

      // Get opponent info
      final opponentData = _amPlayer1
          ? matchData['player2']
          : matchData['player1'];
      _opponentId = opponentData?['userId'] as String?;
      _opponentName = opponentData?['displayName'] as String? ?? 'Opponent';

      // Check if opponent already selected hero (before we start listening)
      final oppHeroId = opponentData?['heroId'] as String?;
      if (oppHeroId != null) {
        _opponentHero = HeroLibrary.getHeroById(oppHeroId);
        debugPrint('Opponent already selected hero: ${_opponentHero?.name}');
      }

      // Start listening to Firebase BEFORE showing hero selection dialog
      // This ensures we don't miss opponent's hero selection
      _listenToMatchUpdates();

      // Show hero selection dialog
      if (mounted) {
        await _showHeroSelectionDialog();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      debugPrint('Error initializing online match: $e');
      debugPrint('Stack trace: $stackTrace');
      _showError('Failed to join match: $e');
    }
  }

  /// Show hero selection dialog for online mode
  Future<void> _showHeroSelectionDialog() async {
    final heroes = HeroLibrary.allHeroes;

    final selected = await showDialog<GameHero>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Select Your Hero'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: heroes
                .map(
                  (hero) => Card(
                    child: ListTile(
                      leading: Icon(
                        _getHeroIcon(hero.abilityType),
                        color: _getHeroColor(hero.terrainAffinities.first),
                        size: 32,
                      ),
                      title: Text(
                        hero.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hero.abilityDescription,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Terrain: ${hero.terrainAffinities.join(", ")}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(hero),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );

    if (selected != null) {
      _selectedHero = selected;

      // Store hero selection in Firebase (deck will be synced after match starts)
      final myKey = _amPlayer1 ? 'player1' : 'player2';
      await _firestore.collection('matches').doc(widget.onlineMatchId).update({
        '$myKey.heroId': selected.id,
      });

      debugPrint('Selected hero: ${selected.name}');
    } else {
      // Default to Napoleon if dialog dismissed somehow
      _selectedHero = HeroLibrary.napoleon();
    }
  }

  IconData _getHeroIcon(HeroAbilityType type) {
    switch (type) {
      case HeroAbilityType.drawCards:
        return Icons.style;
      case HeroAbilityType.damageBoost:
        return Icons.flash_on;
      case HeroAbilityType.healUnits:
        return Icons.healing;
    }
  }

  Color _getHeroColor(String terrain) {
    switch (terrain) {
      case 'Woods':
        return Colors.green;
      case 'Desert':
        return Colors.orange;
      case 'Lake':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Color _getRarityFillColor(GameCard card) {
    switch (card.rarity) {
      case 1:
        return Colors.grey[200]!; // Common
      case 2:
        return Colors.lightBlue[100]!; // Rare
      case 3:
        return Colors.deepPurple[100]!; // Epic
      case 4:
        return Colors.orange[100]!; // Legendary
      default:
        return Colors.grey[200]!;
    }
  }

  Color _getRarityBorderColor(GameCard card) {
    switch (card.rarity) {
      case 1:
        return Colors.grey[500]!;
      case 2:
        return Colors.lightBlue[400]!;
      case 3:
        return Colors.deepPurple[400]!;
      case 4:
        return Colors.orange[400]!;
      default:
        return Colors.grey[500]!;
    }
  }

  String _rarityLabel(int rarity) {
    switch (rarity) {
      case 1:
        return 'Common';
      case 2:
        return 'Rare';
      case 3:
        return 'Epic';
      case 4:
        return 'Legendary';
      default:
        return 'Unknown';
    }
  }

  Widget _buildStatIcon(IconData icon, int value, {double size = 10}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: Colors.grey[800]),
        const SizedBox(width: 1),
        Text('$value', style: TextStyle(fontSize: size - 2)),
      ],
    );
  }

  /// Build stat icon with current/max format (e.g., "2/3")
  Widget _buildStatIconWithMax(
    IconData icon,
    int current,
    int max, {
    double size = 10,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: Colors.grey[800]),
        const SizedBox(width: 1),
        Text('$current/$max', style: TextStyle(fontSize: size - 2)),
      ],
    );
  }

  IconData _abilityIconData(String ability) {
    if (ability == 'guard') return Icons.security; // Shield/tank icon
    if (ability == 'scout') return Icons.visibility; // Eye icon for scouting
    if (ability == 'long_range') return Icons.gps_fixed; // Target icon
    if (ability == 'flanking') return Icons.swap_horiz; // Side movement
    if (ability.startsWith('tile_shield'))
      return Icons.shield_outlined; // Tile-wide shield aura
    if (ability.startsWith('shield')) return Icons.shield;
    if (ability.startsWith('fury')) return Icons.whatshot;
    if (ability.startsWith('regen') || ability.startsWith('regenerate')) {
      return Icons.autorenew;
    }
    if (ability.startsWith('heal')) return Icons.healing;
    if (ability == 'cleave') return Icons.all_inclusive;
    if (ability.startsWith('thorns')) return Icons.grass;
    // conceal_back removed - not valid in TYC3
    if (ability == 'stealth_pass') return Icons.nightlight_round;
    if (ability == 'paratrooper') return Icons.flight_takeoff;
    // New Napoleon abilities
    if (ability == 'first_strike') return Icons.bolt;
    if (ability == 'ranged') return Icons.arrow_forward; // Bow-like
    if (ability == 'far_attack') return Icons.adjust; // Cannonball-like
    if (ability == 'cross_attack') return Icons.swap_horiz;
    if (ability.startsWith('inspire')) return Icons.music_note;
    if (ability.startsWith('fortify')) return Icons.security;
    if (ability.startsWith('rally')) return Icons.campaign;
    if (ability.startsWith('command')) return Icons.military_tech;
    return Icons.star;
  }

  /// Determine attack style from card abilities
  /// Returns: 'melee' (sword), 'ranged' (bow), or 'far_attack' (cannon)
  String _getAttackStyle(GameCard card) {
    if (card.abilities.contains('far_attack')) return 'far_attack';
    if (card.abilities.contains('ranged')) return 'ranged';
    return 'melee';
  }

  /// Get icon for attack style
  /// - Melee: Sword (gets retaliation)
  /// - Ranged: Bow (no retaliation)
  /// - Far Attack: Cannonball (attacks from distance, no retaliation)
  IconData _getAttackStyleIcon(String attackStyle) {
    switch (attackStyle) {
      case 'far_attack':
        return Icons.adjust; // Cannonball
      case 'ranged':
        return Icons.arrow_forward; // Bow
      case 'melee':
      default:
        return Icons
            .content_cut; // Sword (rotated scissors look like crossed swords)
    }
  }

  /// Get color for attack style icon
  Color _getAttackStyleColor(String attackStyle) {
    switch (attackStyle) {
      case 'far_attack':
        return Colors.orange[700]!; // Cannon = orange
      case 'ranged':
        return Colors.green[700]!; // Bow = green
      case 'melee':
      default:
        return Colors.grey[700]!; // Sword = grey/steel
    }
  }

  /// Build attack style icon widget
  Widget _buildAttackStyleIcon(GameCard card, {double size = 10}) {
    final style = _getAttackStyle(card);
    final icon = _getAttackStyleIcon(style);
    final color = _getAttackStyleColor(style);

    return Icon(icon, size: size, color: color);
  }

  /// Get human-readable label for attack style
  String _getAttackStyleLabel(String attackStyle) {
    switch (attackStyle) {
      case 'far_attack':
        return 'Cannon'; // Far attack - no retaliation
      case 'ranged':
        return 'Ranged'; // Ranged - no retaliation
      case 'melee':
      default:
        return 'Melee'; // Melee - gets retaliation
    }
  }

  /// Get a human-readable description for an ability
  String _abilityDescription(String ability) {
    // Handle parameterized abilities (e.g., fury_1, shield_2, inspire_1)
    if (ability.startsWith('tile_shield_')) {
      final value = ability.split('_').last;
      return 'Defends ALL units on this tile by adding $value defense to attacks against them.';
    }
    if (ability.startsWith('shield_')) {
      final value = ability.split('_').last;
      return 'Takes $value less damage from each hit.';
    }
    if (ability.startsWith('fury_')) {
      final value = ability.split('_').last;
      return '+$value damage when attacking.';
    }
    if (ability.startsWith('inspire_')) {
      final value = ability.split('_').last;
      return '+$value damage to ALL allies in this lane.';
    }
    if (ability.startsWith('fortify_')) {
      final value = ability.split('_').last;
      return '+$value shield to ALL allies in this lane.';
    }
    if (ability.startsWith('rally_')) {
      final value = ability.split('_').last;
      return '+$value damage to adjacent ally in stack.';
    }
    if (ability.startsWith('command_')) {
      final value = ability.split('_').last;
      return '+$value damage AND +$value shield to all allies in lane.';
    }
    if (ability.startsWith('regen_')) {
      final value = ability.split('_').last;
      return 'Regenerates $value HP each turn.';
    }
    if (ability.startsWith('thorns_')) {
      final value = ability.split('_').last;
      return 'Reflects $value damage back when hit.';
    }

    switch (ability) {
      case 'guard':
        return 'This unit will direct all tile damage to itself, protecting allies.';
      case 'first_strike':
        return 'Attacks FIRST in the same tick. Can kill before enemy counterattacks.';
      case 'ranged':
        return 'Attacks without receiving retaliation damage.';
      case 'far_attack':
        return 'Attacks enemies at OTHER tiles in same lane. Disabled if contested.';
      case 'cross_attack':
        return 'Can attack enemies in adjacent lanes (left/right).';
      case 'heal_ally_2':
        return 'Heals an ally in lane for 2 HP each tick.';
      case 'regenerate':
        return 'Powerful regeneration over time.';
      case 'cleave':
        return 'Hits BOTH enemies on the same tile with full damage.';
      // conceal_back removed - not valid in TYC3
      case 'stealth_pass':
        return 'Can move through enemies in the middle lane.';
      case 'paratrooper':
        return 'Can be staged directly onto the middle row.';
      case 'scout':
        return 'Reveals enemy cards in adjacent lanes.';
      case 'long_range':
        return 'Can attack enemies 2 tiles away.';
      case 'flanking':
        return 'Can move to adjacent lanes (left/right).';
      default:
        return ability; // Return raw ability name if unknown
    }
  }

  /// Build a row showing ability name and description
  Widget _buildAbilityRow(String ability) {
    final icon = _abilityIconData(ability);
    final description = _abilityDescription(ability);
    final displayName = _abilityDisplayName(ability);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Get a display-friendly name for an ability
  String _abilityDisplayName(String ability) {
    // Convert ability code to readable name
    if (ability.startsWith('tile_shield_'))
      return 'Tile Shield ${ability.split('_').last}';
    if (ability.startsWith('shield_'))
      return 'Shield ${ability.split('_').last}';
    if (ability.startsWith('fury_')) return 'Fury ${ability.split('_').last}';
    if (ability.startsWith('inspire_'))
      return 'Inspire ${ability.split('_').last}';
    if (ability.startsWith('fortify_'))
      return 'Fortify ${ability.split('_').last}';
    if (ability.startsWith('rally_')) return 'Rally ${ability.split('_').last}';
    if (ability.startsWith('command_'))
      return 'Command ${ability.split('_').last}';
    if (ability.startsWith('regen_')) return 'Regen ${ability.split('_').last}';
    if (ability.startsWith('thorns_'))
      return 'Thorns ${ability.split('_').last}';

    switch (ability) {
      case 'first_strike':
        return 'First Strike';
      case 'ranged':
        return 'Ranged';
      case 'far_attack':
        return 'Far Attack';
      case 'cross_attack':
        return 'Cross Attack';
      case 'heal_ally_2':
        return 'Heal Ally';
      case 'regenerate':
        return 'Regenerate';
      case 'cleave':
        return 'Cleave';
      // conceal_back removed - not valid in TYC3
      case 'stealth_pass':
        return 'Stealth';
      case 'paratrooper':
        return 'Paratrooper';
      case 'flanking':
        return 'Flanking';
      default:
        // Convert snake_case to Title Case
        return ability
            .split('_')
            .map(
              (w) =>
                  w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
            )
            .join(' ');
    }
  }

  void _showCardDetails(GameCard card) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(12),
          content: Container(
            width: 260,
            decoration: BoxDecoration(
              color: _getRarityFillColor(card),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _getRarityBorderColor(card), width: 2),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        card.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      iconSize: 18,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (card.element != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          card.element!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Neutral',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      'Rarity: ${_rarityLabel(card.rarity)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show damage as current/max
                        _buildStatIconWithMax(
                          Icons.local_fire_department,
                          card.currentDamage,
                          card.damage,
                          size: 14,
                        ),
                        // Show attack AP cost only if > 1
                        if (card.attackAPCost > 1) ...[
                          Text(
                            ' (${card.attackAPCost}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[700],
                            ),
                          ),
                          Icon(Icons.bolt, size: 11, color: Colors.orange[700]),
                          Text(
                            ')',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Show HP as current/max
                    _buildStatIconWithMax(
                      Icons.favorite,
                      card.currentHealth,
                      card.health,
                      size: 14,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // TYC3: Show AP (current/max) and attack style
                    if (_useTYC3Mode) ...[
                      _buildStatIconWithMax(
                        Icons.bolt,
                        card.currentAP,
                        card.maxAP,
                        size: 14,
                      ),
                      // Attack style with label
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAttackStyleIcon(card, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            _getAttackStyleLabel(_getAttackStyle(card)),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getAttackStyleColor(
                                _getAttackStyle(card),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _buildStatIcon(Icons.timer, card.tick, size: 14),
                      _buildStatIcon(
                        Icons.directions_run,
                        card.moveSpeed,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (card.abilities.isNotEmpty) ...[
                  const Text(
                    'Abilities',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...card.abilities.map((a) => _buildAbilityRow(a)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show celebratory dialog when a relic is discovered
  void _showRelicDiscoveredDialog(
    String playerName,
    bool isHumanPlayer,
    GameCard rewardCard,
  ) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.amber[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.amber, width: 3),
        ),
        title: Column(
          children: [
            const Text('🏺', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              isHumanPlayer
                  ? 'Ancient Artifact Found!'
                  : 'Opponent Found Relic!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isHumanPlayer ? Colors.amber[800] : Colors.red[800],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$playerName discovered a hidden relic!',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getRarityFillColor(rewardCard),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getRarityBorderColor(rewardCard),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    isHumanPlayer
                        ? '✨ Card Added to Hand! ✨'
                        : '⚠️ Enemy Gained:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isHumanPlayer
                          ? Colors.green[700]
                          : Colors.red[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rewardCard.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatBadge('⚔️', '${rewardCard.damage}', Colors.red),
                      const SizedBox(width: 12),
                      _buildStatBadge(
                        '❤️',
                        '${rewardCard.health}',
                        Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _buildStatBadge('⏱️', '${rewardCard.tick}', Colors.blue),
                    ],
                  ),
                  if (rewardCard.element != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        rewardCard.element!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (rewardCard.abilities.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      children: rewardCard.abilities
                          .map(
                            (a) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                a,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple[800],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              isHumanPlayer ? 'Awesome!' : 'Continue',
              style: TextStyle(
                color: isHumanPlayer ? Colors.amber[800] : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    // Refresh UI to show new card in hand
    if (mounted) setState(() {});
  }

  /// Build a stat badge for the relic dialog
  Widget _buildStatBadge(String icon, String value, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color[700],
            ),
          ),
        ],
      ),
    );
  }

  /// Listen to Firebase match document updates
  void _listenToMatchUpdates() {
    if (widget.onlineMatchId == null) return;

    debugPrint(
      '📡 Starting Firebase listener for match: ${widget.onlineMatchId}',
    );

    _matchListener = _firestore
        .collection('matches')
        .doc(widget.onlineMatchId)
        .snapshots()
        .listen((snapshot) {
          debugPrint(
            '📡 Firebase snapshot received, exists=${snapshot.exists}',
          );
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

    debugPrint('🔍 Firebase data keys: ${data.keys.toList()}');
    debugPrint('🔍 oppData ($oppKey): $oppData');

    // Check for hero selection (for starting match)
    final oppHeroId = oppData?['heroId'] as String?;
    debugPrint(
      '🔍 Hero check: oppHeroId=$oppHeroId, _opponentHero=${_opponentHero?.name}, _selectedHero=${_selectedHero?.name}',
    );
    if (oppHeroId != null && _opponentHero == null) {
      _opponentHero = HeroLibrary.getHeroById(oppHeroId);
      debugPrint('✅ Opponent selected hero: ${_opponentHero?.name}');
    }

    // Read opponent's deck card names from Firebase
    final oppDeckNames = oppData?['deckCardNames'] as List<dynamic>?;
    if (oppDeckNames != null && _opponentDeckCardNames == null) {
      _opponentDeckCardNames = oppDeckNames.cast<String>();
      debugPrint(
        '✅ Received opponent deck: ${_opponentDeckCardNames!.length} cards',
      );
    }

    // Check for board setup (from Player 1 / host)
    final boardSetup = data['boardSetup'] as Map<String, dynamic>?;
    if (boardSetup != null) {
      _firstPlayerId = boardSetup['firstPlayerId'] as String?;
      _predefinedRelicColumn = boardSetup['relicColumn'] as int?;

      // Parse terrain grid stored as a flat map: {"row_col": "terrain"}
      final terrainsData = boardSetup['terrains'] as Map<String, dynamic>?;
      if (terrainsData != null) {
        _predefinedTerrains = List.generate(3, (row) {
          return List.generate(3, (col) {
            final key = '${row}_${col}';
            return (terrainsData[key] as String?) ?? 'woods';
          });
        });
      }
    }

    // Start match when both players have selected heroes
    debugPrint(
      '🔍 Match start check: selectedHero=${_selectedHero?.name}, opponentHero=${_opponentHero?.name}, heroSelectionComplete=$_heroSelectionComplete, amPlayer1=$_amPlayer1',
    );
    debugPrint(
      '🔍 Board setup: predefinedTerrains=${_predefinedTerrains != null}, firstPlayerId=$_firstPlayerId',
    );
    if (_selectedHero != null &&
        _opponentHero != null &&
        !_heroSelectionComplete) {
      // Player1 (host) sets up the board and stores in Firebase
      if (_amPlayer1) {
        // Player1: Create temporary board to get terrains, then store in Firebase
        final playerTerrains = _selectedHero?.terrainAffinities ?? ['Woods'];
        final opponentTerrains = _opponentHero?.terrainAffinities ?? ['Desert'];
        final tempBoard = GameBoard.create(
          playerTerrains: playerTerrains,
          opponentTerrains: opponentTerrains,
        );

        // Get terrain grid from the board (3x3 list)
        _predefinedTerrains = tempBoard.toTerrainGrid();

        // Randomly determine relic column and first player
        final random = Random();
        _predefinedRelicColumn = random.nextInt(3);
        _firstPlayerId = random.nextBool() ? _playerId : _opponentId;

        // Flatten terrain grid to a map: {"row_col": "terrain"} to avoid nested arrays
        final terrainsMap = <String, String>{};
        if (_predefinedTerrains != null) {
          for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 3; col++) {
              terrainsMap['${row}_${col}'] = _predefinedTerrains![row][col];
            }
          }
        }

        // Store all board setup in Firebase
        _firestore.collection('matches').doc(widget.onlineMatchId).update({
          'boardSetup': {
            'firstPlayerId': _firstPlayerId,
            'relicColumn': _predefinedRelicColumn,
            'terrains': terrainsMap,
          },
        });
        debugPrint(
          'Player1 stored board setup: firstPlayer=$_firstPlayerId, relic=$_predefinedRelicColumn',
        );
        _heroSelectionComplete = true;
        _startNewMatch();
      } else if (_predefinedTerrains != null && _firstPlayerId != null) {
        // Player2: Use the board setup from Firebase
        debugPrint(
          'Player2 using board from Firebase: firstPlayer=$_firstPlayerId, relic=$_predefinedRelicColumn',
        );
        _heroSelectionComplete = true;
        _startNewMatch();
      } else {
        // Player2: Wait for player1 to set up the board
        debugPrint('Player2 waiting for boardSetup from Firebase...');
      }
    }

    // TYC3 Mode: Handle real-time state updates
    if (_useTYC3Mode) {
      _handleTYC3StateUpdate(data);
      return;
    }

    // Legacy mode: Handle submit-based turns
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

    // If both submitted, trigger combat resolution.
    // Re-entry is guarded inside _loadOpponentCardsAndResolveCombat.
    if (newMySubmitted && newOppSubmitted) {
      _loadOpponentCardsAndResolveCombat(data);
    }
  }

  /// Handle TYC3 state updates from Firebase
  int _lastProcessedActionIndex = 0; // Track which actions we've processed

  void _handleTYC3StateUpdate(Map<String, dynamic> data) {
    // NEW: OnlineGameManager now uses stream-based sync, so this method
    // is only used for legacy state sync. The stream listener handles
    // state updates from the opponent automatically.
    if (_onlineGameManager != null) {
      // Stream-based sync handles updates - nothing to do here
      return;
    }

    // LEGACY: Fall back to old state-sync approach if OnlineGameManager not initialized
    final tyc3State = data['tyc3State'] as Map<String, dynamic>?;
    if (tyc3State == null) return;

    final lastActionBy = tyc3State['lastActionBy'] as String?;

    // Ignore our own actions
    if (lastActionBy == _playerId) return;

    // Opponent made an action - update local state from Firebase
    debugPrint('📥 TYC3 state update from opponent');

    // Sync state first
    _syncLocalStateFromFirebase(tyc3State);

    // Process any new actions from the action log
    final actions = data['tyc3Actions'] as List<dynamic>?;
    if (actions != null && actions.length > _lastProcessedActionIndex) {
      // Process new actions
      for (int i = _lastProcessedActionIndex; i < actions.length; i++) {
        final action = actions[i] as Map<String, dynamic>;
        final actionPlayerId = action['playerId'] as String?;

        // Only process opponent's actions
        if (actionPlayerId != _playerId) {
          _handleOpponentTYC3Action(action);
        }
      }
      _lastProcessedActionIndex = actions.length;
    }

    setState(() {});
  }

  /// Sync local game state from Firebase TYC3 state
  void _syncLocalStateFromFirebase(Map<String, dynamic> tyc3State) {
    final match = _matchManager.currentMatch;
    if (match == null) return;

    // Update base HP
    final player1HP = tyc3State['player1BaseHP'] as int?;
    final player2HP = tyc3State['player2BaseHP'] as int?;

    if (_amPlayer1) {
      if (player1HP != null) match.player.baseHP = player1HP;
      if (player2HP != null) match.opponent.baseHP = player2HP;
    } else {
      if (player2HP != null) match.player.baseHP = player2HP;
      if (player1HP != null) match.opponent.baseHP = player1HP;
    }

    // Update turn info
    final turnNumber = tyc3State['turnNumber'] as int?;
    final isFirstTurn = tyc3State['isFirstTurn'] as bool?;
    final activePlayerId = tyc3State['activePlayerId'] as String?;

    if (turnNumber != null) match.turnNumber = turnNumber;
    if (isFirstTurn != null) match.isFirstTurn = isFirstTurn;
    if (activePlayerId != null) match.activePlayerId = activePlayerId;

    // Sync board state (cards on tiles)
    final boardData = tyc3State['board'] as Map<String, dynamic>?;
    if (boardData != null) {
      _syncBoardFromFirebase(boardData, match);
    }

    debugPrint('🔄 Synced local state from Firebase');
  }

  /// Sync board cards from Firebase data
  void _syncBoardFromFirebase(
    Map<String, dynamic> boardData,
    MatchState match,
  ) {
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final key = '${row}_$col';
        final tileData = boardData[key] as Map<String, dynamic>?;
        if (tileData == null) continue;

        final cardsData = tileData['cards'] as List<dynamic>?;
        if (cardsData == null) continue;

        // For opponent's perspective, we need to mirror the board
        // Row 0 (their base) = Row 2 (our enemy base view)
        // Row 2 (their enemy base) = Row 0 (our base view)
        final localRow = _amPlayer1 ? row : (2 - row);
        final localTile = match.board.getTile(localRow, col);

        // Clear existing cards and rebuild from Firebase
        // Only update opponent's cards to avoid overwriting our own state
        final existingPlayerCards = localTile.cards
            .where((c) => c.ownerId == _playerId)
            .toList();

        // Rebuild opponent cards from Firebase
        final opponentCards = <GameCard>[];
        for (final cardData in cardsData) {
          final data = cardData as Map<String, dynamic>;
          final ownerId = data['ownerId'] as String?;

          // Skip our own cards (we have the authoritative state)
          if (ownerId == _playerId) continue;

          final card = GameCard(
            id: data['id'] as String,
            name: data['name'] as String,
            damage: data['damage'] as int,
            health: data['health'] as int,
            tick: 1, // Default tick
            element: data['element'] as String?,
            abilities: (data['abilities'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList(),
          );
          card.currentHealth = data['currentHealth'] as int? ?? card.health;
          card.currentAP = data['currentAP'] as int? ?? card.maxAP;
          card.ownerId = ownerId;
          opponentCards.add(card);
        }

        // Update tile with combined cards
        localTile.cards.clear();
        localTile.cards.addAll(existingPlayerCards);
        localTile.cards.addAll(opponentCards);
      }
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

    // Use selected hero based on mode
    final GameHero playerHero;
    final GameHero opponentHero;

    if (_isOnlineMode) {
      // Online mode: use heroes selected via dialog
      playerHero = _selectedHero ?? HeroLibrary.napoleon();
      opponentHero = _opponentHero ?? HeroLibrary.saladin();
    } else {
      // AI mode: use widget hero or default
      playerHero = widget.selectedHero ?? HeroLibrary.napoleon();
      opponentHero = HeroLibrary.saladin();
    }

    // Determine which deck to use
    debugPrint(
      'forceCampaignDeck: ${widget.forceCampaignDeck}, hero: ${playerHero.name}',
    );
    final Deck playerDeck;
    final isNapoleon = playerHero.name.toLowerCase().contains('napoleon');
    if (widget.forceCampaignDeck) {
      // Campaign mode: always use hero's campaign deck
      if (isNapoleon) {
        playerDeck = Deck.napoleon(playerId: id);
        debugPrint('🎖️ CAMPAIGN MODE: Using Napoleon starter deck (25 cards)');
      } else {
        playerDeck = Deck.starter(playerId: id);
        debugPrint(
          '🎖️ CAMPAIGN MODE: Using starter deck for ${playerHero.name}',
        );
      }
    } else if (_savedDeck != null && _savedDeck!.isNotEmpty) {
      // Use saved deck if available
      playerDeck = Deck.fromCards(playerId: id, cards: _savedDeck!);
      debugPrint('Using saved deck (${_savedDeck!.length} cards)');
    } else if (isNapoleon) {
      // Default to Napoleon's deck for Napoleon hero
      playerDeck = Deck.napoleon(playerId: id);
      debugPrint('Using Napoleon starter deck (25 cards)');
    } else {
      playerDeck = Deck.starter(playerId: id);
      debugPrint('Using generic starter deck');
    }

    // Determine opponent name and deck
    final opponentNameFinal = _isOnlineMode
        ? (_opponentName ?? 'Opponent')
        : 'AI Opponent';
    final opponentIdFinal = _isOnlineMode ? (_opponentId ?? 'opponent') : 'ai';

    debugPrint('========== MATCH STARTING ==========');
    debugPrint(
      'Player hero: ${playerHero.name} (${playerHero.abilityDescription})',
    );
    debugPrint('Opponent hero: ${opponentHero.name}');
    debugPrint('Deck name: ${playerDeck.name}');
    debugPrint('Deck cards (${playerDeck.cards.length}):');
    for (final card in playerDeck.cards) {
      debugPrint(
        '  - ${card.name} (${card.element}, DMG:${card.damage}, HP:${card.health})',
      );
    }
    debugPrint('====================================');

    // Determine enemy deck - use provided deck, synced deck for online, or act-specific deck for campaign
    final Deck opponentDeck;
    if (widget.enemyDeck != null) {
      opponentDeck = widget.enemyDeck!;
      debugPrint(
        '🎖️ CAMPAIGN: Using provided enemy deck: ${opponentDeck.name}',
      );
    } else if (_isOnlineMode && _opponentDeckCardNames != null) {
      // Online mode: use synced deck from Firebase
      opponentDeck = Deck.fromCardNames(
        playerId: opponentIdFinal,
        cardNames: _opponentDeckCardNames!,
        name: 'Opponent Deck',
      );
      debugPrint(
        '🌐 ONLINE: Using synced opponent deck (${_opponentDeckCardNames!.length} cards)',
      );
    } else if (widget.forceCampaignDeck) {
      // Campaign mode without specific deck - use act-based deck
      switch (widget.campaignAct) {
        case 1:
          opponentDeck = Deck.act1Enemy(playerId: opponentIdFinal);
          debugPrint('🎖️ CAMPAIGN ACT 1: Using Austrian Forces deck');
          break;
        case 2:
          // TODO: Add Act 2 deck (Egyptian Campaign)
          opponentDeck = Deck.act1Enemy(playerId: opponentIdFinal);
          debugPrint('🎖️ CAMPAIGN ACT 2: Using placeholder deck');
          break;
        default:
          opponentDeck = Deck.starter(playerId: opponentIdFinal);
      }
    } else {
      opponentDeck = Deck.starter(playerId: opponentIdFinal);
    }

    debugPrint(
      'Enemy deck: ${opponentDeck.name} (${opponentDeck.cards.length} cards)',
    );

    // Use TYC3 mode if enabled (both single player and online)
    if (_useTYC3Mode) {
      debugPrint(
        '🎮 Starting TYC3 turn-based match${_isOnlineMode ? " (ONLINE)" : ""}',
      );

      // For online mode, use the coordinated settings from host
      // For AI mode, let the match manager randomly decide
      final String? firstPlayerOverride = _isOnlineMode ? _firstPlayerId : null;
      debugPrint('First player override: $firstPlayerOverride');

      // For online mode, use predefined board setup from host
      // Player 2 needs to mirror the terrain grid (swap rows 0 and 2)
      List<List<String>>? terrainsToUse;
      if (_isOnlineMode && _predefinedTerrains != null) {
        if (_amPlayer1) {
          // Player 1: use terrains as-is
          terrainsToUse = _predefinedTerrains;
        } else {
          // Player 2: mirror the terrain grid (row 0 <-> row 2)
          terrainsToUse = [
            _predefinedTerrains![2], // P1's base -> P2's enemy base (row 0)
            _predefinedTerrains![1], // Middle stays same
            _predefinedTerrains![0], // P1's enemy base -> P2's base (row 2)
          ];
        }
        debugPrint('Using predefined terrains (mirrored: ${!_amPlayer1})');
      }

      // Skip opponent shuffle if we have synced deck (already in correct order)
      final skipOppShuffle = _isOnlineMode && _opponentDeckCardNames != null;

      _matchManager.startMatchTYC3(
        playerId: id,
        playerName: name,
        playerDeck: playerDeck,
        opponentId: opponentIdFinal,
        opponentName: opponentNameFinal,
        opponentDeck: opponentDeck,
        opponentIsAI: !_isOnlineMode,
        playerAttunedElement: playerHero.terrainAffinities.first,
        opponentAttunedElement: opponentHero.terrainAffinities.first,
        playerHero: playerHero,
        opponentHero: opponentHero,
        firstPlayerIdOverride: firstPlayerOverride,
        predefinedTerrains: terrainsToUse,
        predefinedRelicColumn: _isOnlineMode ? _predefinedRelicColumn : null,
        skipOpponentShuffle: skipOppShuffle,
      );

      // Set up relic discovery callback
      _matchManager.onRelicDiscovered =
          (playerName, isHumanPlayer, rewardCard) {
            _showRelicDiscoveredDialog(playerName, isHumanPlayer, rewardCard);
          };

      if (_isOnlineMode) {
        // Online TYC3: Initialize OnlineGameManager for state-based sync
        _onlineGameManager = OnlineGameManager(
          matchId: widget.onlineMatchId!,
          myPlayerId: _playerId!,
        );

        // Subscribe to opponent state updates
        _onlineStateSubscription = _onlineGameManager!.stateStream.listen(
          _onOpponentStateUpdate,
          onError: (e) => debugPrint('❌ State stream error: $e'),
        );

        // Start listening to Firebase
        _onlineGameManager!.startListening();
        debugPrint('🎮 OnlineGameManager initialized with stream listener');

        // Debug turn state
        final match = _matchManager.currentMatch!;
        debugPrint(
          '🎮 Turn debug: activePlayerId=${match.activePlayerId}, player.id=${match.player.id}, opponent.id=${match.opponent.id}',
        );
        debugPrint(
          '🎮 Turn debug: isPlayerTurn=${_matchManager.isPlayerTurn}, firstPlayerId=$_firstPlayerId',
        );

        // Sync initial state to Firebase (force sync regardless of turn)
        // This ensures the first player's state is written
        if (_matchManager.isPlayerTurn) {
          debugPrint('🎮 It is our turn - syncing initial state');
          _onlineGameManager!.syncState(_matchManager.currentMatch!);
          _startTurnTimer();
        } else {
          debugPrint('🎮 It is opponent turn - waiting for their state');
        }
      } else {
        // Single player: Start turn timer if it's player's turn
        if (_matchManager.isPlayerTurn) {
          _startTurnTimer();
        } else {
          // AI goes first
          _doAITurnTYC3();
        }
      }
    } else {
      _matchManager.startMatch(
        playerId: id,
        playerName: name,
        playerDeck: playerDeck,
        opponentId: opponentIdFinal,
        opponentName: opponentNameFinal,
        opponentDeck: opponentDeck,
        opponentIsAI: !_isOnlineMode,
        playerAttunedElement: playerHero.terrainAffinities.first,
        opponentAttunedElement: opponentHero.terrainAffinities.first,
        playerHero: playerHero,
        opponentHero: opponentHero,
      );
    }
    _clearStaging();
    _clearTYC3Selection();
    _lastProcessedActionIndex = 0; // Reset action tracking for new match
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

    // TYC3 Mode: Use direct placement
    if (_useTYC3Mode) {
      _placeCardTYC3(row, col);
      return;
    }

    // In online mode, once you've submitted, you can't place more cards this turn
    if (_isOnlineMode && _mySubmitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already submitted this turn. Wait for combat.'),
        ),
      );
      return;
    }

    final tile = match.getTile(row, col);
    final key = _tileKey(row, col);

    // Initialize list if needed
    _stagedCards[key] ??= [];

    // Cards can only be staged at player base (row 2)
    // Exception: cards with 'paratrooper' ability can stage at middle (row 1)
    final hasParatrooper = _selectedCard!.abilities.contains('paratrooper');

    if (row == 0) {
      // Cannot stage on enemy base
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot stage cards on enemy base!')),
      );
      return;
    }

    if (row == 1 && !hasParatrooper) {
      // Cannot stage on middle unless paratrooper
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cards can only be staged at your base! (Paratrooper ability allows middle)',
          ),
        ),
      );
      return;
    }

    // Check tile ownership - must be player-owned (only relevant for middle with paratrooper)
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

    // Check 1 card per lane per turn limit
    // Count all staged cards in this lane (any row in same column)
    int stagedInLane = 0;
    for (int r = 0; r <= 2; r++) {
      final laneKey = _tileKey(r, col);
      stagedInLane += (_stagedCards[laneKey]?.length ?? 0);
    }

    if (stagedInLane >= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only 1 card per lane per turn!')),
      );
      return;
    }

    // Check if tile is full (survivors + staged = max 2)
    final currentZoneRow = zoneToRow(lane.currentZone);
    int survivorCount = 0;
    if (row == currentZoneRow) {
      survivorCount = lane.playerStack.aliveCards.length;
    }

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
    // In online mode, don't allow changing staging after submit
    if (_isOnlineMode && _mySubmitted) {
      return;
    }
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
            'moveSpeed': card.moveSpeed,
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

      // Mark that we submitted locally.
      // Do NOT touch _waitingForOpponent here – that flag is only for
      // "currently resolving combat" inside _loadOpponentCardsAndResolveCombat.
      setState(() {
        _mySubmitted = true;
      });

      debugPrint('Submitted turn to Firebase');
    } catch (e) {
      debugPrint('Error submitting online turn: $e');
      _showError('Failed to submit turn');
    }
  }

  // ===========================================================================
  // TYC3 ONLINE SYNC METHODS
  // ===========================================================================

  /// Sync TYC3 game state to Firebase
  bool _deckSyncedToFirebase = false; // Track if we've synced our deck order

  Future<void> _syncTYC3StateToFirebase() async {
    if (!_isOnlineMode || widget.onlineMatchId == null) return;

    try {
      final match = _matchManager.currentMatch;
      if (match == null) return;

      // Serialize board state
      final boardState = _serializeBoardState(match);

      // Store HP in canonical format (Player 1's perspective)
      // For Player 1: player = player1, opponent = player2
      // For Player 2: player = player2, opponent = player1
      final player1HP = _amPlayer1
          ? match.player.baseHP
          : match.opponent.baseHP;
      final player2HP = _amPlayer1
          ? match.opponent.baseHP
          : match.player.baseHP;

      final updateData = <String, dynamic>{
        'tyc3State': {
          'activePlayerId': match.activePlayerId,
          'turnNumber': match.turnNumber,
          'isFirstTurn': match.isFirstTurn,
          'board': boardState,
          'player1BaseHP': player1HP,
          'player2BaseHP': player2HP,
          'lastActionBy': _playerId,
          'lastActionTime': FieldValue.serverTimestamp(),
        },
      };

      // On first sync, also store our shuffled deck order (deck + hand)
      // This allows opponent to recreate our deck in the exact same order
      if (!_deckSyncedToFirebase) {
        final myKey = _amPlayer1 ? 'player1' : 'player2';
        // Get all cards: hand + remaining deck (in order)
        final allCardNames = <String>[];
        // First add hand cards
        for (final card in match.player.hand) {
          allCardNames.add(card.name);
        }
        // Then add remaining deck cards
        for (final card in match.player.deck.cards) {
          allCardNames.add(card.name);
        }
        updateData['$myKey.deckCardNames'] = allCardNames;
        _deckSyncedToFirebase = true;
        debugPrint(
          '📦 Synced shuffled deck order (${allCardNames.length} cards)',
        );
      }

      await _firestore
          .collection('matches')
          .doc(widget.onlineMatchId)
          .update(updateData);

      debugPrint('🔄 Synced TYC3 state to Firebase');
    } catch (e) {
      debugPrint('Error syncing TYC3 state: $e');
    }
  }

  /// Serialize board state for Firebase
  /// IMPORTANT: Always store in Player 1's perspective (canonical format)
  /// Player 2 must mirror rows when serializing
  Map<String, dynamic> _serializeBoardState(MatchState match) {
    final board = <String, dynamic>{};

    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);

        // Convert to Player 1's perspective for storage
        // Player 1: row stays the same
        // Player 2: row 0 (their enemy base) -> row 2, row 2 (their base) -> row 0
        final canonicalRow = _amPlayer1 ? row : (2 - row);
        final key = '${canonicalRow}_$col';

        board[key] = {
          'terrain': tile.terrain,
          'owner': tile.owner.toString(),
          'cards': tile.cards.map((card) => _serializeCard(card)).toList(),
        };
      }
    }

    return board;
  }

  /// Serialize a card for Firebase
  Map<String, dynamic> _serializeCard(GameCard card) {
    return {
      'id': card.id,
      'name': card.name,
      'damage': card.damage,
      'health': card.health,
      'currentHealth': card.currentHealth,
      'maxAP': card.maxAP,
      'currentAP': card.currentAP,
      'apPerTurn': card.apPerTurn,
      'attackAPCost': card.attackAPCost,
      'attackRange': card.attackRange,
      'element': card.element,
      'abilities': card.abilities,
      'ownerId': card.ownerId,
      'isRanged': card.isRanged,
    };
  }

  /// Sync a TYC3 action to Firebase (place, move, attack, end turn)
  Future<void> _syncTYC3Action(
    String actionType,
    Map<String, dynamic> actionData,
  ) async {
    if (!_isOnlineMode || widget.onlineMatchId == null) return;

    try {
      // Add action to action log
      await _firestore.collection('matches').doc(widget.onlineMatchId).update({
        'tyc3Actions': FieldValue.arrayUnion([
          {
            'type': actionType,
            'playerId': _playerId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            ...actionData,
          },
        ]),
      });

      // Host: also sync full state snapshot for opponent
      if (_amPlayer1) {
        await _syncTYC3StateToFirebase();
      }
    } catch (e) {
      debugPrint('Error syncing TYC3 action: $e');
    }
  }

  /// Handle opponent's TYC3 action from Firebase
  void _handleOpponentTYC3Action(Map<String, dynamic> action) {
    if (!mounted) return;

    final actionType = action['type'] as String?;
    if (actionType == null) return;

    debugPrint('📥 Received opponent action: $actionType');

    switch (actionType) {
      case 'place':
        _handleOpponentPlace(action);
        break;
      case 'move':
        _handleOpponentMove(action);
        break;
      case 'attack':
        _handleOpponentAttack(action);
        break;
      case 'attackBase':
        _handleOpponentAttackBase(action);
        break;
      case 'endTurn':
        _handleOpponentEndTurn(action);
        break;
    }

    setState(() {});
  }

  void _handleOpponentPlace(Map<String, dynamic> action) {
    // Opponent placed a card - update local state from synced board
    debugPrint('Opponent placed card: ${action['cardName']}');
  }

  void _handleOpponentMove(Map<String, dynamic> action) {
    debugPrint('Opponent moved card: ${action['cardName']}');
  }

  void _handleOpponentAttack(Map<String, dynamic> action) {
    debugPrint(
      'Opponent attacked: ${action['attackerName']} -> ${action['targetName']}',
    );
  }

  void _handleOpponentAttackBase(Map<String, dynamic> action) {
    debugPrint('Opponent attacked base for ${action['damage']} damage');
  }

  void _handleOpponentEndTurn(Map<String, dynamic> action) {
    debugPrint('Opponent ended turn (action from Firebase)');
    final match = _matchManager.currentMatch;
    if (match == null) return;

    // IMPORTANT (online mode):
    // - Turn switching, turnNumber, isFirstTurn, AP regen and card draw
    //   are all handled by MatchManager.endTurnTYC3() on the ACTIVE client
    //   (the one who actually ended their turn) and then synced via Firebase.
    // - On the listening client we ONLY react to the new state and update UI.

    // If after processing this action Firebase says it's now OUR turn,
    // just (re)start our local turn timer.
    if (match.activePlayerId == _playerId) {
      debugPrint('🎯 It is now MY turn (after opponent ended)');

      // Ensure any old timer is cleared and start a fresh one
      _turnTimer?.cancel();
      _startTurnTimer();
    }
  }

  // ===========================================================================
  // END TYC3 ONLINE SYNC METHODS
  // ===========================================================================

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

      // Convert opponent's cards from Firebase format (may be empty)
      // IMPORTANT: Mirror the row coordinate! Opponent's row 2 (their base) = our row 0 (enemy base)
      final opponentMoves = <String, List<GameCard>>{};
      if (oppStagedData != null && oppStagedData.isNotEmpty) {
        for (final entry in oppStagedData.entries) {
          // Mirror the tile key: "2,0" -> "0,0", "2,1" -> "0,1", etc.
          final parts = entry.key.split(',');
          final row = int.parse(parts[0]);
          final col = int.parse(parts[1]);
          final mirroredRow = 2 - row; // 2->0, 1->1, 0->2
          final mirroredKey = '$mirroredRow,$col';

          final cardsList = entry.value as List<dynamic>;
          opponentMoves[mirroredKey] = cardsList.map((cardData) {
            final data = cardData as Map<String, dynamic>;
            return GameCard(
              id: data['id'] as String,
              name: data['name'] as String,
              damage: data['damage'] as int,
              health: data['health'] as int,
              tick: data['tick'] as int,
              moveSpeed: data['moveSpeed'] as int? ?? 1,
              element: data['element'] as String?,
              abilities: (data['abilities'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList(),
              cost: data['cost'] as int? ?? 0,
              rarity: data['rarity'] as int? ?? 1,
            );
          }).toList();
        }
      }

      // Submit player's staged cards
      await _matchManager.submitPlayerTileMoves(_stagedCards);

      // Submit opponent's cards (skip hand check since cards come from Firebase)
      await _matchManager.submitOpponentTileMoves(
        opponentMoves,
        skipHandCheck: true,
      );

      // Reset submitted flags and staged cards for next turn
      await _firestore.collection('matches').doc(widget.onlineMatchId).update({
        'player1.submitted': false,
        'player2.submitted': false,
        'player1.stagedCards': {},
        'player2.stagedCards': {},
      });

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

    // Show waiting screen for online mode while waiting for opponent's hero
    if (match == null) {
      if (_isOnlineMode && _selectedHero != null && !_heroSelectionComplete) {
        return Scaffold(
          appBar: AppBar(title: const Text('Online Match')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'You selected: ${_selectedHero!.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Waiting for opponent to select their hero...',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }
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
          title: _useTYC3Mode
              ? _buildTYC3Title(match)
              : Text('Turn ${match.turnNumber} - ${match.currentPhase.name}'),
          actions: [
            // TYC3: Show turn timer (only in online mode)
            if (_useTYC3Mode &&
                _isOnlineMode &&
                !match.isGameOver &&
                _matchManager.isPlayerTurn)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _turnSecondsRemaining <= 10
                      ? Colors.red
                      : Colors.green,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '$_turnSecondsRemaining s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (match.isGameOver)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _startNewMatch,
              ),
            if (!match.isGameOver && !_useTYC3Mode && !match.playerSubmitted)
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
        floatingActionButton: _useTYC3Mode
            ? _buildTYC3ActionButton(match)
            : match.currentPhase == MatchPhase.combatPhase
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

  // ===== TYC3 UI Builders =====

  Widget _buildTYC3Title(MatchState match) {
    final isMyTurn = _matchManager.isPlayerTurn;
    final turnText = isMyTurn ? 'Your Turn' : "Opponent's Turn";
    final cardsPlayed = match.cardsPlayedThisTurn;
    final maxCards = _matchManager.maxCardsThisTurn;
    final cardsRemaining = maxCards - cardsPlayed;
    final isFirstTurn = match.isFirstTurn && isMyTurn;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Turn ${match.turnNumber} - $turnText',
              style: const TextStyle(fontSize: 16),
            ),
            if (isFirstTurn)
              Text(
                '(First turn - 1 card limit)',
                style: TextStyle(fontSize: 11, color: Colors.yellow[300]),
              ),
          ],
        ),
        if (isMyTurn) ...[
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cardsRemaining > 0 ? Colors.green[700] : Colors.grey[600],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cardsRemaining > 0
                    ? Colors.green[300]!
                    : Colors.grey[400]!,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.style, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  '$cardsRemaining/$maxCards',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildTYC3ActionButton(MatchState match) {
    if (match.isGameOver) return null;

    // Show "End Turn" button during player's turn
    if (_matchManager.isPlayerTurn) {
      return FloatingActionButton.extended(
        onPressed: _endTurnTYC3,
        label: const Text('End Turn'),
        icon: const Icon(Icons.skip_next),
        backgroundColor: Colors.blue[700],
        heroTag: 'endTurn',
      );
    }

    // Show waiting indicator during opponent's turn
    return FloatingActionButton.extended(
      onPressed: null,
      label: const Text("Opponent's Turn"),
      icon: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
      backgroundColor: Colors.grey,
      heroTag: 'waiting',
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
    final playerWon = winner?.id == match.player.id;
    final isCampaignMode = widget.forceCampaignDeck;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            playerWon ? Icons.emoji_events : Icons.close,
            size: 100,
            color: playerWon ? Colors.amber : Colors.red,
          ),
          const SizedBox(height: 20),
          Text(
            playerWon ? 'Victory!' : 'Defeat',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          Text('${winner?.name} wins!'),
          const SizedBox(height: 20),
          Text('Player Crystal: ${match.player.crystalHP} HP'),
          Text('Opponent Crystal: ${match.opponent.crystalHP} HP'),
          const SizedBox(height: 20),
          Text('Total Turns: ${match.turnNumber}'),
          const SizedBox(height: 30),
          // Continue button - returns result to campaign
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context, {
                'won': playerWon,
                'crystalDamage': 50 - match.player.crystalHP,
                'turnsPlayed': match.turnNumber,
              });
            },
            icon: Icon(
              isCampaignMode
                  ? (playerWon ? Icons.arrow_forward : Icons.replay)
                  : Icons.home,
            ),
            label: Text(
              isCampaignMode
                  ? (playerWon ? 'Continue Campaign' : 'Return to Map')
                  : 'Return to Menu',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: playerWon ? Colors.amber : Colors.grey,
            ),
          ),
          if (!isCampaignMode) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _startNewMatch,
              icon: const Icon(Icons.refresh),
              label: const Text('Play Again'),
            ),
          ],
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

        // Combat zoom overlay - shown when a lane is actively in combat
        if (match.currentPhase == MatchPhase.combatPhase &&
            _matchManager.currentCombatLane != null)
          Positioned.fill(child: _buildCombatZoomOverlay()),
      ],
    );
  }

  /// Build the combat banner with detailed tick info
  Widget _buildCombatBanner() {
    final match = _matchManager.currentMatch;
    final currentLane = _matchManager.currentCombatLane;

    // Get terrain for current combat tile
    String? terrain;
    if (match != null && currentLane != null) {
      final col = currentLane.index;
      final lane = match.lanes[col];
      final row = lane.currentZone == Zone.playerBase
          ? 2
          : lane.currentZone == Zone.enemyBase
          ? 0
          : 1;
      terrain = match.board.getTile(row, col).terrain;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red[700]!, Colors.orange[600]!],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Combat header with terrain
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.flash_on, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Column(
                children: [
                  Text(
                    currentLane != null
                        ? '⚔️ ${currentLane.name.toUpperCase()} LANE ⚔️'
                        : '⚔️ COMBAT IN PROGRESS ⚔️',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  if (terrain != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getTerrainColor(terrain).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getTerrainIcon(terrain),
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            terrain.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.flash_on, color: Colors.white, size: 20),
            ],
          ),

          // Tick info with better formatting
          if (_matchManager.currentTickInfo != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _matchManager.currentTickInfo!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // Detailed combat results with better styling
          if (_matchManager.currentTickDetails.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...(_matchManager.currentTickDetails.map((detail) {
              final isDestroyed = detail.contains('DESTROYED');
              final isAbility =
                  detail.contains('FIRST STRIKE') ||
                  detail.contains('INSPIRE') ||
                  detail.contains('FORTIFY') ||
                  detail.contains('COMMAND') ||
                  detail.contains('RALLY');
              final isTerrain = detail.contains('terrain');

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDestroyed
                      ? Colors.red[900]
                      : isAbility
                      ? Colors.purple[800]
                      : isTerrain
                      ? Colors.green[800]
                      : Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: isDestroyed
                      ? Border.all(color: Colors.red[300]!, width: 2)
                      : isAbility
                      ? Border.all(color: Colors.purple[300]!, width: 1)
                      : null,
                ),
                child: Text(
                  detail,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: isDestroyed || isAbility
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            })),
          ],
        ],
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
        return Colors.grey[700]!;
    }
  }

  IconData _getTerrainIcon(String terrain) {
    switch (terrain.toLowerCase()) {
      case 'woods':
        return Icons.park;
      case 'lake':
        return Icons.water;
      case 'desert':
        return Icons.wb_sunny;
      case 'marsh':
        return Icons.grass;
      default:
        return Icons.landscape;
    }
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

  /// Build the combat zoom overlay showing the active lane in detail
  Widget _buildCombatZoomOverlay() {
    final match = _matchManager.currentMatch;
    if (match == null) return const SizedBox.shrink();

    final activeLane = _matchManager.currentCombatLane;
    if (activeLane == null) return const SizedBox.shrink();

    final lane = match.getLane(activeLane);
    final currentTick = _matchManager.currentCombatTick ?? 0;
    final zone = lane.currentZone;

    // Get fighting cards (middleCards)
    final playerFront = lane.playerStack.topCard;
    final playerBack = lane.playerStack.bottomCard;
    final opponentFront = lane.opponentStack.topCard;
    final opponentBack = lane.opponentStack.bottomCard;

    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            // Header with lane info
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red[800]!, Colors.orange[700]!],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flash_on, color: Colors.yellow, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    '⚔️ ${activeLane.name.toUpperCase()} LANE ⚔️',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.flash_on, color: Colors.yellow, size: 28),
                ],
              ),
            ),

            // Zone indicator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: zone == Zone.playerBase
                  ? Colors.blue[700]
                  : (zone == Zone.enemyBase
                        ? Colors.red[700]
                        : Colors.grey[700]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    zone == Zone.middle ? Icons.swap_horiz : Icons.castle,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Combat at: ${zone == Zone.playerBase ? '🛡️ YOUR BASE' : (zone == Zone.enemyBase ? '🏰 ENEMY BASE' : '⚔️ MIDDLE')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Tick progress bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              color: Colors.grey[900],
              child: Column(
                children: [
                  Text(
                    'TICK $currentTick / 5',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final tickNum = index + 1;
                      final isPast = tickNum < currentTick;
                      final isCurrent = tickNum == currentTick;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: isCurrent ? 36 : 28,
                        height: isCurrent ? 36 : 28,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.orange
                              : (isPast ? Colors.green : Colors.grey[700]),
                          shape: BoxShape.circle,
                          border: isCurrent
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: Colors.orange.withAlpha(150),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$tickNum',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isCurrent ? 16 : 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),

            // Main combat area
            Expanded(
              child: Row(
                children: [
                  // Player side (left)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[900]!.withAlpha(150),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[400]!, width: 2),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[700],
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '🛡️ YOUR CARDS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildZoomCard(playerFront, 'FRONT', true),
                                const SizedBox(height: 12),
                                _buildZoomCard(playerBack, 'BACK', true),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // VS separator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 8,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[700],
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withAlpha(150),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Text(
                            'VS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Opponent side (right)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red[900]!.withAlpha(150),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[400]!, width: 2),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red[700],
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '⚔️ ENEMY CARDS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildZoomCard(opponentFront, 'FRONT', false),
                                const SizedBox(height: 12),
                                _buildZoomCard(opponentBack, 'BACK', false),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Combat details
            if (_matchManager.currentTickDetails.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey[850],
                child: Column(
                  children: [
                    const Text(
                      'COMBAT LOG',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: _matchManager.currentTickDetails.map((detail) {
                        final isDestroyed = detail.contains('DESTROYED');
                        final isHit = detail.contains('Hit');
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDestroyed
                                ? Colors.red[800]
                                : (isHit
                                      ? Colors.orange[800]
                                      : Colors.grey[700]),
                            borderRadius: BorderRadius.circular(8),
                            border: isDestroyed
                                ? Border.all(color: Colors.red[300]!, width: 1)
                                : null,
                          ),
                          child: Text(
                            detail,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: isDestroyed
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

            // Skip button
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black,
              child: ElevatedButton.icon(
                onPressed: () => _matchManager.skipToEnd(),
                icon: const Icon(Icons.fast_forward),
                label: const Text('SKIP COMBAT (ENTER)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a single card display for the combat zoom overlay
  Widget _buildZoomCard(GameCard? card, String position, bool isPlayer) {
    if (card == null) {
      return Container(
        width: 120,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.grey[800]!.withAlpha(100),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.grey[600]!,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, color: Colors.grey[500], size: 32),
              const SizedBox(height: 4),
              Text(
                position,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              Text(
                'Empty',
                style: TextStyle(color: Colors.grey[600], fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    final isAlive = card.isAlive;
    final healthPercent = card.currentHealth / card.health;
    final cardColor = isPlayer ? Colors.blue : Colors.red;

    return Opacity(
      opacity: isAlive ? 1.0 : 0.4,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cardColor[800]!, cardColor[900]!],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isAlive ? cardColor[400]! : Colors.grey[600]!,
            width: 2,
          ),
          boxShadow: isAlive
              ? [
                  BoxShadow(
                    color: cardColor.withAlpha(100),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Position label
            Text(
              position,
              style: TextStyle(
                color: Colors.white.withAlpha(180),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),

            // Card name
            Text(
              card.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 6),

            // Health bar
            Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: healthPercent.clamp(0.0, 1.0),
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: healthPercent > 0.5
                            ? [Colors.green[600]!, Colors.green[400]!]
                            : (healthPercent > 0.25
                                  ? [Colors.orange[600]!, Colors.orange[400]!]
                                  : [Colors.red[600]!, Colors.red[400]!]),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                SizedBox(
                  height: 16,
                  child: Center(
                    child: Text(
                      '${card.currentHealth}/${card.health}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildZoomStat('⚔️', '${card.damage}'),
                _buildZoomStat('⏱️', 'T${card.tick}'),
              ],
            ),

            // Terrain
            if (card.element != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '🏔️ ${card.element}',
                  style: TextStyle(
                    color: Colors.white.withAlpha(180),
                    fontSize: 9,
                  ),
                ),
              ),

            // Dead indicator
            if (!isAlive)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '💀 DESTROYED',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomStat(String icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerInfo(player, {required bool isOpponent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isOpponent ? Colors.red[50] : Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOpponent ? Icons.smart_toy : Icons.person,
                  color: isOpponent ? Colors.red : Colors.blue,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    player.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOpponent ? Colors.red[700] : Colors.blue[700],
                    ),
                  ),
                ),
                // Show hero info
                if (player.hero != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '(${player.hero!.name})',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isOpponent ? Colors.red[400] : Colors.blue[400],
                      ),
                    ),
                  ),
                ],
              ],
            ),
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

    // Get cards at this tile based on position
    List<GameCard> playerCardsAtTile = [];
    List<GameCard> opponentCardsAtTile = [];

    // Fog of war: check if this lane's enemy base is revealed
    final isEnemyBaseRevealed = match.revealedEnemyBaseLanes.contains(lanePos);

    // TYC3 Mode: Read cards directly from tile.cards
    if (_useTYC3Mode) {
      final tileCards = tile.cards.where((c) => c.isAlive).toList();
      final playerId = match.player.id;

      // Fog of War: Check if player has cards in middle (row 1) of this lane
      final middleTile = match.board.getTile(1, col);
      final playerHasMiddleCard = middleTile.cards.any(
        (c) => c.ownerId == playerId && c.isAlive,
      );

      // Use card.ownerId to determine ownership
      for (final card in tileCards) {
        if (card.ownerId == playerId) {
          playerCardsAtTile.add(card);
        } else {
          // Fog of War: Hide enemy base cards (row 0) unless player has cards in middle
          if (row == 0 && !playerHasMiddleCard) {
            // Don't add to opponentCardsAtTile - hidden by fog of war
            continue;
          }
          opponentCardsAtTile.add(card);
        }
      }
    } else {
      // Legacy mode: use lane system
      if (row == 0) {
        // Enemy base row - show player's attacking cards + opponent's staging cards
        playerCardsAtTile = lane.playerCards.enemyBaseCards.aliveCards;
        if (isEnemyBaseRevealed) {
          opponentCardsAtTile = lane.opponentCards.baseCards.aliveCards;
        }
      } else if (row == 1) {
        // Middle - show both sides' middle cards
        playerCardsAtTile = lane.playerCards.middleCards.aliveCards;
        opponentCardsAtTile = lane.opponentCards.middleCards.aliveCards;
      } else if (row == 2) {
        // Player base row - show player's staging cards + opponent's attacking cards
        playerCardsAtTile = lane.playerCards.baseCards.aliveCards;
        opponentCardsAtTile = lane.opponentCards.enemyBaseCards.aliveCards;
      }
    }

    // Count existing cards for placement check
    final existingPlayerCount = playerCardsAtTile.length;

    // Can place on player base (row 2), or middle row (row 1) if card has 2+ AP
    final isPlayerBase = row == 2;
    final isMiddleRow = row == 1;
    final isNotEnemyBase = row != 0; // Cannot stage on enemy base
    final stagedCount = stagedCardsOnTile.length;

    // Check if selected card can be placed on middle row (needs 2+ AP)
    final selectedCardCanPlaceMiddle =
        _selectedCard != null && _selectedCard!.maxAP >= 2;

    // Check if there are enemy cards on the middle tile (can't place there)
    final hasEnemyOnMiddle = isMiddleRow && opponentCardsAtTile.isNotEmpty;

    // Check 1 card per lane limit - count staged cards in this lane (all rows)
    int stagedInLane = 0;
    for (int r = 0; r <= 2; r++) {
      final laneKey = _tileKey(r, col);
      stagedInLane += (_stagedCards[laneKey]?.length ?? 0);
    }

    // Can place on:
    // 1. Player base (row 2) - always valid
    // 2. Middle row (row 1) - only if card has 2+ AP and no enemies there
    final canPlace =
        _selectedCard != null &&
        isNotEnemyBase &&
        stagedInLane == 0 && // No card already staged in this lane
        (existingPlayerCount + stagedCount) < Tile.maxCards &&
        (isPlayerBase ||
            (isMiddleRow && selectedCardCanPlaceMiddle && !hasEnemyOnMiddle));

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

    // Only show staged cards during placement phase, not during combat
    final showStaged = match.currentPhase != MatchPhase.combatPhase;

    List<GameCard> cardsToShow = [
      ...opponentCardsReversed, // Enemy BACK first (top), then FRONT (toward player)
      ...playerCardsAtTile, // Player FRONT first, then BACK
      if (showStaged)
        ...stagedCardsOnTile, // Player staged cards at BOTTOM (only during placement)
    ];

    // TYC3: Check if this tile is a valid move destination (including multi-AP moves)
    bool canMoveTo = false;
    bool canAttackBase = false;
    if (_useTYC3Mode &&
        _selectedCardForAction != null &&
        _selectedCardRow != null &&
        _selectedCardCol != null) {
      // Get all reachable tiles with their AP costs
      final reachableTiles = _matchManager.getReachableTiles(
        _selectedCardForAction!,
        _selectedCardRow!,
        _selectedCardCol!,
      );

      // Check if this tile is reachable
      final reachable = reachableTiles.where(
        (t) => t.row == row && t.col == col,
      );
      if (reachable.isNotEmpty && _matchManager.isPlayerTurn) {
        canMoveTo = true;
      }

      // Check if can attack enemy base (row 0) - considering multi-move
      if (row == 0 && _matchManager.isPlayerTurn) {
        // Check from current position and all reachable positions
        final positions = [
          (row: _selectedCardRow!, col: _selectedCardCol!, apCost: 0),
          ...reachableTiles,
        ];

        for (final pos in positions) {
          if (pos.col != col) continue; // Must be same lane for base attack
          final apAfterMove = _selectedCardForAction!.currentAP - pos.apCost;
          if (apAfterMove < _selectedCardForAction!.attackAPCost) continue;

          // Check range from this position
          final distance = (pos.row - 0).abs();
          if (distance <= _selectedCardForAction!.attackRange) {
            // Check no enemy cards blocking in base tile
            final baseTile = _matchManager.currentMatch!.board.getTile(0, col);
            final hasEnemyCards = baseTile.cards.any((c) => c.isAlive);
            if (!hasEnemyCards) {
              canAttackBase = true;
              break;
            }
          }
        }
      }
    }

    // Determine border color
    Color borderColor;
    double borderWidth;
    if (canAttackBase) {
      borderColor = Colors.orange;
      borderWidth = 3;
    } else if (canMoveTo) {
      borderColor = Colors.purple;
      borderWidth = 3;
    } else if (canPlace) {
      borderColor = Colors.green;
      borderWidth = 3;
    } else {
      borderColor = Colors.grey[400]!;
      borderWidth = 1;
    }

    return GestureDetector(
      onTap: () => _onTileTapTYC3(row, col, canPlace, canMoveTo, canAttackBase),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: canMoveTo ? Colors.purple[50]! : bgColor,
          border: Border.all(color: borderColor, width: borderWidth),
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
                    bool showTerrain = true;

                    if (isEnemyBase) {
                      final lanePos = [
                        LanePosition.west,
                        LanePosition.center,
                        LanePosition.east,
                      ][col];

                      // Check if revealed via revealedEnemyBaseLanes (scout ability or capture)
                      final isRevealedByScout = match.revealedEnemyBaseLanes
                          .contains(lanePos);

                      if (_useTYC3Mode) {
                        // TYC3: Revealed if player has cards in middle of this lane OR scout revealed it
                        final middleTile = match.board.getTile(1, col);
                        final playerId = match.player.id;
                        final hasCardInMiddle = middleTile.cards.any(
                          (c) => c.ownerId == playerId && c.isAlive,
                        );
                        showTerrain = hasCardInMiddle || isRevealedByScout;
                      } else {
                        // Legacy: Use revealedEnemyBaseLanes
                        showTerrain = isRevealedByScout;
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: showTerrain
                            ? _getTerrainColor(tile.terrain!)
                            : Colors.grey[600],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: showTerrain
                          ? Icon(
                              _getTerrainIcon(tile.terrain!),
                              size: 14,
                              color: Colors.white,
                            )
                          : const Text(
                              '?',
                              style: TextStyle(
                                fontSize: 12,
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

                      // TYC3: No front/back - just show card index for reference
                      String? positionLabel;
                      bool isFrontCard = false;

                      if (_useTYC3Mode) {
                        // TYC3: Show if card is selected for action
                        if (_selectedCardForAction == card) {
                          positionLabel = '✓ SELECTED';
                        } else if (isOpponent) {
                          // Show if this is a valid target
                          if (_validTargets.contains(card)) {
                            positionLabel = '🎯 TARGET';
                          }
                        }
                      } else {
                        // Legacy front/back logic
                        if (isOpponent && opponentCardsAtTile.isNotEmpty) {
                          final originalIndex = opponentCardsAtTile.indexOf(
                            card,
                          );
                          isFrontCard = originalIndex == 0;
                          if (opponentCardsAtTile.length > 1) {
                            positionLabel = isFrontCard ? '▼ FRONT' : '▲ BACK';
                          } else {
                            positionLabel = '▼ FRONT';
                          }
                        } else if (isPlayerCard &&
                            playerCardsAtTile.isNotEmpty) {
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
                      }

                      // Check if this is the opponent's back card and it's concealed (legacy only)
                      final isOpponentBackCard =
                          !_useTYC3Mode &&
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

                      final rarityBorder = _getRarityBorderColor(card);

                      // TYC3: Highlight selected card and valid targets
                      final isSelected =
                          _useTYC3Mode && _selectedCardForAction == card;
                      final isValidTarget =
                          _useTYC3Mode && _validTargets.contains(card);

                      return GestureDetector(
                        onTap: () => _onCardTapTYC3(
                          card,
                          row,
                          col,
                          isPlayerCard,
                          isOpponent,
                        ),
                        onLongPress: () => _showCardDetails(card),
                        child: Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.yellow[200]!
                                    : isValidTarget
                                    ? Colors.orange[200]!
                                    : cardColor,
                                borderRadius: BorderRadius.circular(4),
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.yellow[700]!,
                                        width: 3,
                                      )
                                    : isValidTarget
                                    ? Border.all(
                                        color: Colors.orange[700]!,
                                        width: 2,
                                      )
                                    : isStaged
                                    ? Border.all(color: Colors.amber, width: 2)
                                    : Border.all(
                                        color: rarityBorder,
                                        width: _useTYC3Mode
                                            ? 1
                                            : (isFrontCard ? 2 : 1),
                                      ),
                              ),
                              child: isConcealed
                                  // Show hidden card placeholder
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Position label row
                                        if (positionLabel != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                              vertical: 1,
                                            ),
                                            margin: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: labelColor.withValues(
                                                alpha: 0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(3),
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
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Show damage as current/max
                                            _buildStatIconWithMax(
                                              Icons.local_fire_department,
                                              card.currentDamage,
                                              card.damage,
                                              size: 10,
                                            ),
                                            // Show attack AP cost only if > 1
                                            if (card.attackAPCost > 1) ...[
                                              Text(
                                                ' (${card.attackAPCost}',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.orange[700],
                                                ),
                                              ),
                                              Icon(
                                                Icons.bolt,
                                                size: 8,
                                                color: Colors.orange[700],
                                              ),
                                              Text(
                                                ')',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.orange[700],
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 2),
                                            // Show HP as current/max
                                            _buildStatIconWithMax(
                                              Icons.favorite,
                                              card.currentHealth,
                                              card.health,
                                              size: 10,
                                            ),
                                            const SizedBox(width: 2),
                                            // TYC3: Show AP (current/max) and attack style icon
                                            if (_useTYC3Mode) ...[
                                              _buildStatIconWithMax(
                                                Icons.bolt,
                                                card.currentAP,
                                                card.maxAP,
                                                size: 10,
                                              ),
                                              const SizedBox(width: 2),
                                              // Attack style: melee (sword), ranged (bow), far_attack (cannon)
                                              _buildAttackStyleIcon(
                                                card,
                                                size: 10,
                                              ),
                                            ] else ...[
                                              _buildStatIcon(
                                                Icons.timer,
                                                card.tick,
                                                size: 10,
                                              ),
                                              const SizedBox(width: 2),
                                              _buildStatIcon(
                                                Icons.directions_run,
                                                card.moveSpeed,
                                                size: 10,
                                              ),
                                            ],
                                            // Element/Terrain icon
                                            if (card.element != null) ...[
                                              const SizedBox(width: 2),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getTerrainColor(
                                                    card.element!,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: Icon(
                                                  _getTerrainIcon(
                                                    card.element!,
                                                  ),
                                                  size: 8,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                            ),
                            // X button to remove staged cards
                            if (isStaged &&
                                match.currentPhase != MatchPhase.combatPhase)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () =>
                                      _removeCardFromTile(row, col, card),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
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

                      final baseFill = _getRarityFillColor(card);
                      final baseBorder = _getRarityBorderColor(card);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            // Clear board card selection when selecting hand card
                            _clearTYC3Selection();
                            _selectedCard = isSelected ? null : card;
                          });
                        },
                        onLongPress: () => _showCardDetails(card),
                        child: Container(
                          width: 90,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: baseFill,
                            border: Border.all(
                              color: isSelected ? Colors.green : baseBorder,
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
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
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
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Show damage as current/max
                                    _buildStatIconWithMax(
                                      Icons.local_fire_department,
                                      card.currentDamage,
                                      card.damage,
                                      size: 10,
                                    ),
                                    // Show attack AP cost only if > 1
                                    if (card.attackAPCost > 1) ...[
                                      Text(
                                        ' (${card.attackAPCost}',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                      Icon(
                                        Icons.bolt,
                                        size: 8,
                                        color: Colors.orange[700],
                                      ),
                                      Text(
                                        ')',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 2),
                                    // Show HP as current/max for hand cards
                                    _buildStatIconWithMax(
                                      Icons.favorite,
                                      card.currentHealth,
                                      card.health,
                                      size: 10,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 1),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // TYC3: Show AP (current/max) and attack style icon
                                    if (_useTYC3Mode) ...[
                                      _buildStatIconWithMax(
                                        Icons.bolt,
                                        card.currentAP,
                                        card.maxAP,
                                        size: 10,
                                      ),
                                      const SizedBox(width: 2),
                                      // Attack style: melee (sword), ranged (bow), far_attack (cannon)
                                      _buildAttackStyleIcon(card, size: 10),
                                    ] else ...[
                                      _buildStatIcon(
                                        Icons.timer,
                                        card.tick,
                                        size: 10,
                                      ),
                                      const SizedBox(width: 2),
                                      _buildStatIcon(
                                        Icons.directions_run,
                                        card.moveSpeed,
                                        size: 10,
                                      ),
                                    ],
                                  ],
                                ),
                                // Element/Terrain icon
                                if (card.element != null) ...[
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getTerrainColor(card.element!),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      _getTerrainIcon(card.element!),
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                                if (card.abilities.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: card.abilities
                                        .map<Widget>(
                                          (a) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 1,
                                            ),
                                            child: Icon(
                                              _abilityIconData(a),
                                              size: 9,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
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
