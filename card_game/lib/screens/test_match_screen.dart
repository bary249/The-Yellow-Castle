import 'dart:async';
import 'dart:math';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main_menu_screen.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/lane.dart';
import '../models/card.dart';
import '../models/hero.dart';
import '../models/turn_snapshot.dart';

import '../models/tile.dart';
import '../models/game_board.dart';
import '../models/player.dart';
import '../data/hero_library.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';
import '../services/auth_service.dart';
import '../services/deck_storage_service.dart';
import '../services/combat_resolver.dart' show AttackResult;
import '../services/online_game_manager.dart';
import 'deck_selection_screen.dart';

/// Test screen for playing a match vs AI opponent or online multiplayer
class TestMatchScreen extends StatefulWidget {
  final GameHero? selectedHero;
  final String? onlineMatchId; // If provided, plays online multiplayer
  final bool
  forceCampaignDeck; // If true, use hero's campaign deck instead of saved deck
  final Deck? enemyDeck; // Custom enemy deck (for campaign battles)
  final int campaignAct; // Current campaign act (1, 2, or 3)
  final List<List<String>>?
  predefinedTerrainsOverride; // Campaign: predefined terrain grid (player perspective)
  final List<GameCard>?
  customDeck; // Custom player deck (overrides default/saved)
  final int? playerCurrentHealth; // Starting HP for campaign mode
  final int? playerMaxHealth; // Max HP for campaign mode
  final int
  playerDamageBonus; // Flat damage bonus applied to all player deck cards
  final int
  playerCardHealthBonus; // Flat HP bonus applied to all player deck cards
  final int extraStartingDraw;
  final int artilleryDamageBonus;
  final int cannonHealthBonus; // HP bonus for cannon/artillery cards
  final int heroAbilityDamageBoost;
  final int? opponentBaseHP;
  final List<String>
  opponentPriorityCardIds; // Card IDs to prioritize in opponent's starting hand (e.g., boss cards)

  final List<String> campaignBuffLabels;
  final List<String> campaignBuffLabelsForBuffsDialog;

  const TestMatchScreen({
    super.key,
    this.selectedHero,
    this.onlineMatchId,
    this.forceCampaignDeck = false,
    this.enemyDeck,
    this.campaignAct = 1,
    this.predefinedTerrainsOverride,
    this.customDeck,
    this.playerCurrentHealth,
    this.playerMaxHealth,
    this.playerDamageBonus = 0,
    this.playerCardHealthBonus = 0,
    this.extraStartingDraw = 0,
    this.artilleryDamageBonus = 0,
    this.cannonHealthBonus = 0,
    this.heroAbilityDamageBoost = 0,
    this.opponentBaseHP,
    this.opponentPriorityCardIds = const [],
    this.campaignBuffLabels = const [],
    this.campaignBuffLabelsForBuffsDialog = const [],
  });

  @override
  State<TestMatchScreen> createState() => _TestMatchScreenState();
}

class _CardFocusSwitchTarget {
  final GameCard card;
  final String? tileTerrain;
  final VoidCallback? onSecondTapAction;
  final VoidCallback? onDismissed;

  const _CardFocusSwitchTarget({
    required this.card,
    this.tileTerrain,
    this.onSecondTapAction,
    this.onDismissed,
  });
}

class _TestMatchScreenState extends State<TestMatchScreen>
    with SingleTickerProviderStateMixin {
  final MatchManager _matchManager = MatchManager();
  final SimpleAI _ai = SimpleAI();
  final AuthService _authService = AuthService();
  final DeckStorageService _deckStorage = DeckStorageService();
  FirebaseFirestore? _firestore;

  final Set<String> _campaignDestroyedPlayerCardIds = <String>{};
  final Map<String, int> _fallenPlayerCardCounts = <String, int>{};

  bool _isArtilleryCard(GameCard card) {
    if (card.abilities.contains('cannon')) return true;
    if (card.attackRange >= 2) return true;
    final lowerName = card.name.toLowerCase();
    if (lowerName.contains('cannon') || lowerName.contains('artillery')) {
      return true;
    }
    return false;
  }

  String? _playerId;
  String? _playerName;
  List<GameCard>? _savedDeck;

  // Staging area: cards placed on tiles before submitting
  // Key is "row,col" string (e.g., "2,0" for player base left)
  final Map<String, List<GameCard>> _stagedCards = {};

  GameCard? _selectedCard;

  // UI state: battle log drawer visibility
  bool _showBattleLog = false;

  // Card focus overlay state
  OverlayEntry? _cardFocusOverlay;
  bool _cardFocusExpanded = false;
  VoidCallback? _cardFocusOnDismissed;

  final Map<String, Rect> _handCardRects = {};
  final Map<String, Rect> _boardCardRects = {};
  final Map<String, Rect> _boardTileRects = {};

  final GlobalKey _matchViewStackKey = GlobalKey();
  late final AnimationController _attackArrowController;
  Offset? _attackArrowFrom;
  Offset? _attackArrowTo;
  bool _showAttackArrow = false;

  final Map<String, _CardFocusSwitchTarget> _handCardTargets = {};
  final Map<String, _CardFocusSwitchTarget> _boardCardTargets = {};

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
  List<GameCard>? _selectedOnlineDeck; // Deck selected in online dialog
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
  String? _lastSeenHeroAbilityId;

  // ===== TYC3: Turn-based AP system state =====
  final bool _useTYC3Mode = true; // Enable TYC3 by default for testing
  final bool _useChessTimer = true; // Enable Chess Timer mode by default
  Timer? _turnTimer;
  int _turnSecondsRemaining = 100;

  // ===== UI Mode Toggle =====
  final bool _useStackedCardUI =
      true; // Toggle between old ListView and new stacked card UI
  double _handFanAngle = 5.0; // Degrees of fan spread for hand
  double _handCardOverlap = 0.4; // How much hand cards overlap

  // UI Settings
  bool _showSettings = false;
  double _cardOverlapRatio = 0.6; // How much board cards overlap
  double _cardSeparation = 0.0; // Extra horizontal separation on board

  // TYC3 action state
  GameCard? _selectedCardForAction; // Card selected for move/attack
  int? _selectedCardRow;
  int? _selectedCardCol;
  List<GameCard> _validTargets = [];
  bool _isAttackPreviewOpen = false; // Track if preview dialog is open

  /// Get the staging key for a tile.
  String _tileKey(int row, int col) => '$row,$col';

  /// Get staged cards for a specific tile.
  List<GameCard> _getStagedCards(int row, int col) {
    return _stagedCards[_tileKey(row, col)] ?? [];
  }

  // Replay mode state
  bool _isReplayMode = false;
  int _replayTurnIndex = 0;
  TurnSnapshot? _currentReplaySnapshot;

  // Overlay for turn notification
  OverlayEntry? _turnDialogOverlay;
  Timer? _turnOverlayTimer;

  @override
  void initState() {
    super.initState();
    _attackArrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    try {
      _firestore = FirebaseFirestore.instance;
    } catch (e) {
      debugPrint('TestMatchScreen: Firebase not available ($e)');
    }
    _initPlayerAndMatch();

    // Listen for turn changes to show overlay
    _matchManager.onTurnChanged = (activePlayerId) {
      if (!mounted) return;

      final isMyTurn = activePlayerId == _matchManager.currentMatch?.player.id;
      _showTurnChangeOverlay(isMyTurn);

      // Also handle normal turn change logic
      if (isMyTurn && _isOnlineMode) {
        _startTurnTimer();
      }
    };
  }

  @override
  void dispose() {
    _matchListener?.cancel();
    _turnTimer?.cancel();
    _turnOverlayTimer?.cancel();
    _turnDialogOverlay?.remove();
    _cardFocusOverlay?.remove();
    _onlineStateSubscription?.cancel();
    _onlineGameManager?.dispose();
    _attackArrowController.dispose();
    super.dispose();
  }

  Future<void> _playAttackArrow(
    GameCard attacker,
    int attackerRow,
    int attackerCol,
    GameCard target,
    int targetRow,
    int targetCol,
  ) async {
    if (!mounted) return;

    final fromRect =
        _boardCardRects['${attacker.id}_$attackerRow,$attackerCol'];
    final toRect = _boardCardRects['${target.id}_$targetRow,$targetCol'];
    if (fromRect == null || toRect == null) return;

    final renderObject = _matchViewStackKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final from = renderObject.globalToLocal(fromRect.center);
    final to = renderObject.globalToLocal(toRect.center);

    setState(() {
      _attackArrowFrom = from;
      _attackArrowTo = to;
      _showAttackArrow = true;
    });

    _attackArrowController.reset();
    await _attackArrowController.forward();

    if (!mounted) return;
    setState(() {
      _showAttackArrow = false;
    });
  }

  ({GameCard card, int row, int col})? _findBoardCardById(
    MatchState match,
    String cardId,
  ) {
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final c in tile.cards) {
          if (c.id == cardId) {
            return (card: c, row: row, col: col);
          }
        }
      }
    }
    return null;
  }

  Future<void> _playAttackArrowToTile(
    GameCard attacker,
    int attackerRow,
    int attackerCol,
    int targetRow,
    int targetCol,
  ) async {
    if (!mounted) return;

    final fromRect =
        _boardCardRects['${attacker.id}_$attackerRow,$attackerCol'];
    final toRect = _boardTileRects[_tileKey(targetRow, targetCol)];
    if (fromRect == null || toRect == null) return;

    final renderObject = _matchViewStackKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final from = renderObject.globalToLocal(fromRect.center);
    final to = renderObject.globalToLocal(toRect.center);

    setState(() {
      _attackArrowFrom = from;
      _attackArrowTo = to;
      _showAttackArrow = true;
    });

    _attackArrowController.reset();
    await _attackArrowController.forward();

    if (!mounted) return;
    setState(() {
      _showAttackArrow = false;
    });
  }

  Future<void> _showDeckDialog(MatchState match) async {
    final player = match.player;

    final inPlay = <GameCard>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        inPlay.addAll(
          tile.cards.where((c) => c.isAlive && c.ownerId == player.id),
        );
      }
    }

    final staged = <GameCard>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        staged.addAll(_getStagedCards(row, col));
      }
    }

    final destroyedNames = <String>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        for (final gs in tile.gravestones) {
          if (gs.ownerId == player.id) {
            destroyedNames.add(gs.cardName);
          }
        }
      }
    }

    final remainingDeck = player.deck.cards;
    final drawnNow = <GameCard>[...player.hand, ...inPlay, ...staged];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Deck'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ExpansionTile(
                  title: Text('Drawn (Hand + In Play) (${drawnNow.length})'),
                  children: drawnNow.isEmpty
                      ? [const ListTile(title: Text('None'))]
                      : drawnNow
                            .map(
                              (c) => ListTile(
                                dense: true,
                                title: Text(c.name),
                                onTap: () {
                                  Navigator.pop(context);
                                  _showCardDetails(c);
                                },
                              ),
                            )
                            .toList(),
                ),
                ExpansionTile(
                  title: Text('Remaining in Deck (${remainingDeck.length})'),
                  children: remainingDeck.isEmpty
                      ? [const ListTile(title: Text('Empty'))]
                      : remainingDeck
                            .map(
                              (c) => ListTile(dense: true, title: Text(c.name)),
                            )
                            .toList(),
                ),
                ExpansionTile(
                  title: Text('Destroyed (${destroyedNames.length})'),
                  children: destroyedNames.isEmpty
                      ? [const ListTile(title: Text('None'))]
                      : destroyedNames
                            .map(
                              (name) =>
                                  ListTile(dense: true, title: Text(name)),
                            )
                            .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Rect _globalRectForContext(BuildContext ctx) {
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox) return Rect.zero;
    if (!renderObject.hasSize) return Rect.zero;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  void _dismissCardFocus() {
    if (_cardFocusOverlay == null) return;
    _cardFocusExpanded = false;
    _cardFocusOverlay?.markNeedsBuild();
    final onDismissed = _cardFocusOnDismissed;
    _cardFocusOnDismissed = null;
    Future.delayed(const Duration(milliseconds: 150), () {
      _cardFocusOverlay?.remove();
      _cardFocusOverlay = null;
      if (onDismissed != null && mounted) {
        onDismissed();
      }
    });
  }

  void _showCardFocus(
    GameCard card,
    Rect sourceRect, {
    String? tileTerrain,
    VoidCallback? onSecondTapAction,
    VoidCallback? onDismissed,
    Map<String, Rect>? switchRects,
    Map<String, _CardFocusSwitchTarget>? switchTargets,
  }) {
    _cardFocusOverlay?.remove();
    _cardFocusOverlay = null;
    _cardFocusExpanded = false;
    _cardFocusOnDismissed = onDismissed;

    final overlay = Overlay.of(context, rootOverlay: true);

    _cardFocusOverlay = OverlayEntry(
      builder: (overlayContext) {
        final mediaSize = MediaQuery.of(overlayContext).size;

        // Keep overlay close to ~2x the tapped card, with conservative max
        final minW = max(sourceRect.width * 1.5, 160.0);
        final maxW = min(300.0, mediaSize.width - 24.0);
        final targetW = (sourceRect.width * 2.0).clamp(minW, maxW).toDouble();
        final targetH = (targetW * 1.4)
            .clamp(200.0, mediaSize.height - 24.0)
            .toDouble();

        final center = sourceRect.center;
        final targetLeft = (center.dx - targetW / 2)
            .clamp(12.0, max(12.0, mediaSize.width - targetW - 12.0))
            .toDouble();
        final targetTop = (center.dy - targetH / 2)
            .clamp(12.0, max(12.0, mediaSize.height - targetH - 12.0))
            .toDouble();

        final startLeft = sourceRect.left;
        final startTop = sourceRect.top;
        final startW = sourceRect.width;
        final startH = sourceRect.height;

        final left = _cardFocusExpanded ? targetLeft : startLeft;
        final top = _cardFocusExpanded ? targetTop : startTop;
        final w = _cardFocusExpanded ? targetW : startW;
        final h = _cardFocusExpanded ? targetH : startH;

        final focusedRect = Rect.fromLTWH(left, top, w, h);

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // Tap outside to dismiss
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    if (focusedRect.contains(e.position)) return;

                    if (switchRects != null && switchTargets != null) {
                      for (final entry in switchRects.entries) {
                        final id = entry.key;
                        final rect = entry.value;
                        if (rect.contains(e.position)) {
                          final nextTarget = switchTargets[id];
                          if (nextTarget != null) {
                            _cardFocusOnDismissed = nextTarget.onDismissed;
                            _dismissCardFocus();
                            return;
                          }
                        }
                      }
                    }

                    _dismissCardFocus();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              // Focused card
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                left: left,
                top: top,
                width: w,
                height: h,
                child: Material(
                  elevation: _cardFocusExpanded ? 12 : 0,
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: () {
                      if (!_cardFocusExpanded) return;
                      // Second tap on focused card = action
                      if (onSecondTapAction != null) {
                        onSecondTapAction();
                      }
                      _dismissCardFocus();
                    },
                    child: _buildHandCardVisual(
                      card,
                      w,
                      h,
                      false,
                      showDetails: _cardFocusExpanded,
                      tileTerrain: tileTerrain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_cardFocusOverlay!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cardFocusExpanded = true;
      _cardFocusOverlay?.markNeedsBuild();
    });
  }

  /// Show a non-blocking overlay when turn changes
  void _showTurnChangeOverlay(bool isMyTurn) {
    // Remove existing overlay if any
    _turnOverlayTimer?.cancel();
    _turnDialogOverlay?.remove();
    _turnDialogOverlay = null;

    final overlay = Overlay.of(context);

    _turnDialogOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Full screen touch detector to dismiss on tap outside
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _turnDialogOverlay?.remove();
                _turnDialogOverlay = null;
                _turnOverlayTimer?.cancel();
              },
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Dialog content
          Positioned(
            top: MediaQuery.of(context).size.height * 0.2, // Top 20%
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.8 + (0.2 * value),
                        // Also allow dismissing by tapping the banner itself
                        child: GestureDetector(
                          onTap: () {
                            _turnDialogOverlay?.remove();
                            _turnDialogOverlay = null;
                            _turnOverlayTimer?.cancel();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isMyTurn
                                  ? Colors.blue[900]!.withOpacity(0.9)
                                  : Colors.red[900]!.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isMyTurn ? Icons.person : Icons.warning,
                                  size: 48,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isMyTurn ? "YOUR TURN" : "ENEMY TURN",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_turnDialogOverlay!);

    // Auto-dismiss after 2 seconds
    _turnOverlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _turnDialogOverlay != null) {
        _turnDialogOverlay!.remove();
        _turnDialogOverlay = null;
      }
    });
  }

  // ===== TYC3: Turn timer methods =====

  void _startTurnTimer() {
    // Only use timer in online mode - no timer for vs AI
    if (!_isOnlineMode) return;

    _turnTimer?.cancel();

    // For normal turn timer, reset to 100s
    if (!_useChessTimer) {
      _turnSecondsRemaining = 100;
    }

    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        final match = _matchManager.currentMatch;
        if (match == null || match.isGameOver) {
          timer.cancel();
          return;
        }

        if (_useChessTimer) {
          // CHESS TIMER LOGIC
          if (_matchManager.isPlayerTurn) {
            match.playerTotalTimeRemaining--;
            if (match.playerTotalTimeRemaining <= 0) {
              timer.cancel();
              // Player ran out of time - Defeat
              _handleTimeOutDefeat();
            }

            // Sound effect for low time
            if (match.playerTotalTimeRemaining <= 10 &&
                match.playerTotalTimeRemaining > 0) {
              FlameAudio.play('ticking_clock.mp3');
            }
          } else {
            // Visual decrement for opponent (actual value comes from sync)
            match.opponentTotalTimeRemaining--;

            // Check for opponent timeout (with small grace period for lag)
            if (match.opponentTotalTimeRemaining <= -2) {
              timer.cancel();
              _handleTimeOutVictory();
            }
          }
        } else {
          // STANDARD TURN TIMER LOGIC
          _turnSecondsRemaining--;

          // Play ticking sound in last 10 seconds
          if (_turnSecondsRemaining <= 10 && _turnSecondsRemaining > 0) {
            // SystemSound.play(SystemSoundType.click);
            FlameAudio.play('ticking_clock.mp3');
          }

          if (_turnSecondsRemaining <= 0) {
            timer.cancel();
            // Auto-end turn when timer expires
            if (_matchManager.isPlayerTurn) {
              _endTurnTYC3();
            }
          }
        }
      });
    });
  }

  /// Handle defeat due to time running out
  void _handleTimeOutDefeat() {
    // Show dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⏰ Time Out!'),
        content: const Text('You ran out of time. Defeat.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Surrender/End Match
              _matchManager.currentMatch?.endMatch(_opponentId ?? 'opponent');
              _syncTYC3Action('surrender', {}); // Or endMatch action
              setState(() {});
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Handle victory due to opponent time running out
  void _handleTimeOutVictory() {
    // End match locally immediately
    _matchManager.currentMatch?.endMatch(_playerId ?? 'player');

    // Show dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⏰ Opponent Time Out!'),
        content: const Text('Opponent ran out of time. Victory!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Refresh UI to show Game Over screen
              setState(() {});
            },
            child: const Text('Claim Victory'),
          ),
        ],
      ),
    );
  }

  /// Sync current game state to Firebase (for online mode)
  /// Call this after every action (place, move, attack, end turn)
  /// Only syncs if it's currently our turn (we're the authority)
  void _syncOnlineState() {
    if (_onlineGameManager == null ||
        _matchManager.currentMatch == null ||
        _firestore == null)
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
    if (combatResult != null &&
        combatResult.id != _lastSeenCombatResultId &&
        // Only show results where opponent was the attacker
        combatResult.attackerOwnerId != _matchManager.currentMatch?.player.id) {
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

      // LOCAL FOG OF WAR UPDATE:
      // Since we don't sync 'recentlyAttackedEnemyUnits' via Firebase (to avoid bugs),
      // we must update our local state when we see an incoming combat result.
      final attackerId = combatResult.attackerId;
      if (attackerId != null) {
        debugPrint('👀 FOW: Marking attacker $attackerId as visible');
        // We use the *incoming* turn number from the new state
        _matchManager.currentMatch?.recentlyAttackedEnemyUnits[attackerId] =
            newState.turnNumber;
      }
    }

    // Check for new hero ability usage from opponent
    final heroAbility = newState.lastHeroAbility;
    if (heroAbility != null &&
        heroAbility.id != _lastSeenHeroAbilityId &&
        heroAbility.playerId != _matchManager.currentMatch?.player.id) {
      _lastSeenHeroAbilityId = heroAbility.id;
      debugPrint('🦸 Opponent used hero ability: ${heroAbility.heroName}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showHeroAbilityDialog(heroAbility, isOpponent: true);
        }
      });
    }

    // Preserve local fog of war state before replacing
    final localAttackedUnits = Map<String, int>.from(
      _matchManager.currentMatch?.recentlyAttackedEnemyUnits ?? {},
    );

    // Replace local match state with the received state
    _matchManager.replaceMatchState(newState);

    // Restore local fog of war state into the new state object
    _matchManager.currentMatch?.recentlyAttackedEnemyUnits.addAll(
      localAttackedUnits,
    );

    // Check if turn changed
    final isMyTurnNow = _matchManager.isPlayerTurn;
    debugPrint('📥 Turn state: wasMyTurn=$wasMyTurn, isMyTurnNow=$isMyTurnNow');

    if (isMyTurnNow && !wasMyTurn) {
      // Turn just switched to us - start timer and draw a card
      debugPrint('🔄 Turn switched to us!');
      FlameAudio.play('turn_pass.mp3');
      _showTurnChangeOverlay(true);
      _startTurnTimer();

      // Draw a card at the start of our turn (online mode)
      // Skip on turns 1-2 since players already have their initial 6-card hands
      final currentTurn = _matchManager.currentMatch?.turnNumber ?? 1;
      final player = _matchManager.currentMatch?.player;
      if (player != null && !player.deck.isEmpty && currentTurn > 2) {
        player.drawCards(count: 1);
        debugPrint(
          '📥 Drew 1 card. Hand size: ${player.hand.length}, Turn: $currentTurn',
        );
      } else {
        debugPrint(
          '📥 Skipping card draw (Turn $currentTurn, initial hands already dealt)',
        );
      }

      // Regenerate AP for our units
      _matchManager.regenerateAPForPlayer(_playerId ?? 'player');
    } else if (!isMyTurnNow && wasMyTurn) {
      // Turn just switched away from us - stop timer
      debugPrint('🔄 Turn switched to opponent');
      _showTurnChangeOverlay(false);
      _turnTimer?.cancel();

      // Close any open attack preview dialog
      if (_isAttackPreviewOpen && mounted) {
        Navigator.of(context).pop();
      }
    }

    // Refresh UI
    if (mounted) setState(() {});
  }

  void _endTurnTYC3() {
    _turnTimer?.cancel();

    // Close any open attack preview dialog
    if (_isAttackPreviewOpen && mounted) {
      Navigator.of(context).pop();
    }

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

      // In Chess Mode, keep timer running to tick opponent time
      if (_useChessTimer) {
        _startTurnTimer();
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
    FlameAudio.play('turn_pass.mp3');
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

  /// Check if a card is a medic (has medic_X ability)
  bool _isMedic(GameCard card) {
    return card.abilities.any((a) => a.startsWith('medic_'));
  }

  /// Get the heal amount for a medic card
  int _getMedicHealAmount(GameCard card) {
    for (final a in card.abilities) {
      if (a.startsWith('medic_')) {
        return int.tryParse(a.split('_').last) ?? 0;
      }
    }
    return 0;
  }

  /// TYC3: Select a card on the board for action (move/attack/heal)
  void _selectCardForAction(GameCard card, int row, int col) {
    // Check if it's player's turn
    if (!_matchManager.isPlayerTurn) return;

    // Check if this is a player card (row 1-2)
    if (row == 0) return; // Can't select enemy cards

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

        if (card.currentAP > 0) {
          // Medics get heal targets instead of attack targets
          if (_isMedic(card)) {
            final healTargets = _matchManager.getReachableHealTargets(
              card,
              row,
              col,
            );
            _validTargets = healTargets.map((t) => t.target).toList();
          } else {
            final reachableTargets = _matchManager.getReachableAttackTargets(
              card,
              row,
              col,
            );
            _validTargets = reachableTargets.map((t) => t.target).toList();
          }
        } else {
          _validTargets = [];
        }
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

  /// TYC3: Perform heal on a friendly target
  void _healTargetTYC3(GameCard target, int targetRow, int targetCol) {
    if (_selectedCardForAction == null ||
        _selectedCardRow == null ||
        _selectedCardCol == null)
      return;

    final healer = _selectedCardForAction!;

    // Show heal preview dialog
    _showHealPreviewDialog(
      healer: healer,
      target: target,
      healerRow: _selectedCardRow!,
      healerCol: _selectedCardCol!,
      targetRow: targetRow,
      targetCol: targetCol,
    );
  }

  /// Show heal preview dialog with predicted outcome
  Future<void> _showHealPreviewDialog({
    required GameCard healer,
    required GameCard target,
    required int healerRow,
    required int healerCol,
    required int targetRow,
    required int targetCol,
  }) async {
    final healAmount = _getMedicHealAmount(healer);
    final targetHpAfter = (target.currentHealth + healAmount).clamp(
      0,
      target.health,
    );
    final actualHeal = targetHpAfter - target.currentHealth;
    final laneName = _getLaneName(healerCol);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text('Heal Preview', textAlign: TextAlign.center),
            Text(
              '$laneName Lane',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Healer info
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    healer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.healing, color: Colors.green, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '+$actualHeal HP',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Icon(Icons.arrow_downward, size: 24, color: Colors.green),
            const SizedBox(height: 8),
            // Target info
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    target.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.favorite, color: Colors.red, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${target.currentHealth}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(' → '),
                      Text(
                        '$targetHpAfter',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(' / ${target.health}'),
                    ],
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
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _executeHealTYC3(
                healer,
                target,
                healerRow,
                healerCol,
                targetRow,
                targetCol,
              );
            },
            icon: const Icon(Icons.healing),
            label: const Text('Heal'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  /// Execute heal action
  void _executeHealTYC3(
    GameCard healer,
    GameCard target,
    int healerRow,
    int healerCol,
    int targetRow,
    int targetCol,
  ) {
    final result = _matchManager.healCardTYC3(
      healer,
      target,
      healerRow,
      healerCol,
      targetRow,
      targetCol,
    );

    if (result != null) {
      // Sync state for online mode
      _syncOnlineState();

      // Show brief heal result
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${healer.name} healed ${target.name} for ${result.healAmount} HP!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Heal failed'),
          backgroundColor: Colors.red,
        ),
      );
    }

    _clearTYC3Selection();
    setState(() {});
  }

  /// Get lane name from column index
  String _getLaneName(int col) {
    return ['West', 'Center', 'East'][col];
  }

  /// Show attack preview dialog with predicted outcome
  Future<void> _showAttackPreviewDialog({
    required GameCard attacker,
    required GameCard target,
    required int attackerRow,
    required int attackerCol,
    required int targetRow,
    required int targetCol,
  }) async {
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

    _isAttackPreviewOpen = true;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text('Attack Preview', textAlign: TextAlign.center),
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
                    // Show detailed modifiers (buffs/debuffs)
                    if (preview.modifiers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Column(
                          children: preview.modifiers
                              .map(
                                (m) => Text(
                                  m,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.blueGrey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                              .toList(),
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
                            _getTerrainIcon(tileTerrain),
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
                    // Show retaliation if > 0 OR if there are modifiers explaining why it's 0 (e.g. -4 weakness)
                    if (preview.retaliationDamage > 0 ||
                        preview.retaliationModifiers.isNotEmpty) ...[
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
                              _getTerrainIcon(tileTerrain),
                              size: 12,
                              color: _getTerrainColor(tileTerrain),
                            ),
                          ],
                        ),
                      // Show detailed retaliation modifiers
                      if (preview.retaliationModifiers.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            children: preview.retaliationModifiers
                                .map(
                                  (m) => Text(
                                    m,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                                .toList(),
                          ),
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
            // Result summary
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  if (preview.targetDied)
                    const Text(
                      'Target will be killed!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (preview.attackerDied)
                    const Text(
                      'Attacker will die from retaliation!',
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
                      'Ranged - No retaliation',
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
            onPressed: () async {
              Navigator.pop(context);
              await _executeAttackTYC3(
                attacker,
                target,
                attackerRow,
                attackerCol,
                targetRow,
                targetCol,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ATTACK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    _isAttackPreviewOpen = false;
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
                  Text(
                    '${card.currentDamage}/${card.damage}',
                    style: const TextStyle(fontSize: 12),
                  ),
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
              if (willDie) const Text('DEAD', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  /// Execute the attack after confirmation
  Future<void> _executeAttackTYC3(
    GameCard attacker,
    GameCard target,
    int attackerRow,
    int attackerCol,
    int targetRow,
    int targetCol,
  ) async {
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

    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }

    await _playAttackArrow(
      attacker,
      currentRow,
      currentCol,
      target,
      targetRow,
      targetCol,
    );

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

  /// Start replay mode
  void _startReplay() {
    final match = _matchManager.currentMatch;
    if (match == null || match.history.isEmpty) {
      _showError('No replay history available');
      return;
    }

    setState(() {
      _isReplayMode = true;
      _replayTurnIndex = 0;
      _currentReplaySnapshot = match.history.first;
    });
  }

  /// Go to next replay turn
  void _nextReplayTurn() {
    final match = _matchManager.currentMatch;
    if (match == null || !_isReplayMode) return;

    if (_replayTurnIndex < match.history.length - 1) {
      setState(() {
        _replayTurnIndex++;
        _currentReplaySnapshot = match.history[_replayTurnIndex];
      });
    }
  }

  /// Go to previous replay turn
  void _prevReplayTurn() {
    final match = _matchManager.currentMatch;
    if (match == null || !_isReplayMode) return;

    if (_replayTurnIndex > 0) {
      setState(() {
        _replayTurnIndex--;
        _currentReplaySnapshot = match.history[_replayTurnIndex];
      });
    }
  }

  /// Exit replay mode
  void _exitReplay() {
    setState(() {
      _isReplayMode = false;
      _currentReplaySnapshot = null;
    });
  }

  /// Show battle result dialog with animation
  void _showBattleResultDialog(
    AttackResult result,
    GameCard attacker,
    GameCard target,
    int col,
  ) {
    final laneName = _getLaneName(col);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Column(
            children: [
              const Text('Battle Result'),
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
                    Flexible(
                      child: Text(
                        attacker.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
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
                      const Text(
                        ' (Destroyed)',
                        style: TextStyle(fontSize: 14),
                      ),
                  ],
                ),
              ),

              if (result.modifiers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: result.modifiers
                      .map(
                        (m) => Text(
                          m,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],

              // Retaliation
              if (result.retaliationDamage > 0 ||
                  result.retaliationModifiers.isNotEmpty) ...[
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
                      Flexible(
                        child: Text(
                          target.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
                        const Text(
                          ' (Destroyed)',
                          style: TextStyle(fontSize: 14),
                        ),
                    ],
                  ),
                ),

                if (result.retaliationModifiers.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.retaliationModifiers
                        .map(
                          (m) => Text(
                            m,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],

              // Summary
              const SizedBox(height: 12),
              if (result.targetDied && result.attackerDied)
                const Text(
                  'Both units destroyed!',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (result.targetDied)
                Text(
                  '${target.name} destroyed!',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (result.attackerDied)
                Text(
                  '${attacker.name} destroyed!',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              if (widget.campaignBuffLabels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Active buffs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.campaignBuffLabels.join('\n'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blueGrey[900],
                          height: 1.2,
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
              onPressed: () {
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
            const Text('Enemy Attack!', textAlign: TextAlign.center),
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
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
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
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                  if (result.targetDied)
                    const Text(
                      'DESTROYED!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                ],
              ),
            ),

            if (result.modifiers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.modifiers
                    .map(
                      (m) => Text(
                        m,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    )
                    .toList(),
              ),
            ],

            // Retaliation
            if (result.retaliationDamage > 0 ||
                result.retaliationModifiers.isNotEmpty) ...[
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
                        'ATTACKER DESTROYED!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),

              if (result.retaliationModifiers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: result.retaliationModifiers
                      .map(
                        (m) => Text(
                          m,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],

            if (widget.campaignBuffLabels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueGrey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Active buffs',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.campaignBuffLabels.join('\n'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey[900],
                        height: 1.2,
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
            const Text('BASE UNDER ATTACK!', textAlign: TextAlign.center),
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

  /// Show hero ability usage dialog
  Future<void> _showHeroAbilityDialog(
    SyncedHeroAbility ability, {
    required bool isOpponent,
  }) async {
    final titleText = isOpponent
        ? 'Enemy Hero Ability!'
        : 'Hero Ability Activated!';
    final bgColor = isOpponent ? Colors.red[50] : Colors.amber[50];
    final accentColor = isOpponent ? Colors.red : Colors.amber[800]!;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        // Auto-close after 3 seconds using the DIALOG'S context
        Timer(const Duration(seconds: 3), () {
          if (!dialogContext.mounted && Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }
        });

        return AlertDialog(
          backgroundColor: bgColor,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  titleText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ability.heroName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      ability.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show combat result dialog from synced PvP state
  /// This is called when opponent attacks/heals and we receive the result via Firebase
  Future<void> _showSyncedCombatResultDialog(SyncedCombatResult result) async {
    final laneName = _getLaneName(result.laneCol);
    final isOpponentAction = result.attackerOwnerId != _playerId;

    // Handle heal results differently
    if (result.isHeal) {
      await _showSyncedHealResultDialog(result, laneName, isOpponentAction);
      return;
    }

    // Determine dialog style based on who is attacking
    final titleText = isOpponentAction ? 'Enemy Attack!' : 'Your Attack';
    final bgColor = isOpponentAction ? Colors.red[50] : Colors.blue[50];
    final accentColor = isOpponentAction ? Colors.red : Colors.blue;

    final match = _matchManager.currentMatch;
    if (match != null &&
        result.attackerId != null &&
        result.attackerRow != null &&
        result.attackerCol != null &&
        result.targetRow != null &&
        result.targetCol != null) {
      final attackerInfo = _findBoardCardById(match, result.attackerId!);
      if (attackerInfo != null) {
        if (mounted) {
          setState(() {});
          await WidgetsBinding.instance.endOfFrame;
        }

        if (result.isBaseAttack) {
          await _playAttackArrowToTile(
            attackerInfo.card,
            result.attackerRow!,
            result.attackerCol!,
            result.targetRow!,
            result.targetCol!,
          );
        } else if (result.targetId != null) {
          final targetInfo = _findBoardCardById(match, result.targetId!);
          if (targetInfo != null) {
            await _playAttackArrow(
              attackerInfo.card,
              result.attackerRow!,
              result.attackerCol!,
              targetInfo.card,
              result.targetRow!,
              result.targetCol!,
            );
          }
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            Text(titleText, textAlign: TextAlign.center),
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
                      color: isOpponentAction ? Colors.blue : Colors.red,
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
                      result.isBaseAttack ? 'VICTORY!' : 'DESTROYED!',
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
                        'ATTACKER DESTROYED!',
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

  /// Show heal result dialog from synced PvP state
  Future<void> _showSyncedHealResultDialog(
    SyncedCombatResult result,
    String laneName,
    bool isOpponentAction,
  ) async {
    final titleText = isOpponentAction ? 'Enemy Heal' : 'Your Heal';
    final bgColor = Colors.green[50];
    const accentColor = Colors.green;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            Text(titleText, textAlign: TextAlign.center),
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
                      const Icon(Icons.healing, color: accentColor, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '+${result.healAmount} HP',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.targetName ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (result.targetHpAfter != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'HP: ${result.targetHpBefore} → ${result.targetHpAfter}',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
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

    // Calculate lane buffs (Inspire, Command)
    final laneBuffs = _matchManager.calculateLaneBuffsTYC3(
      col,
      attacker.ownerId!,
    );
    final buffBonus = laneBuffs.damage;

    final enemyHp = match.opponent.baseHP;
    final baseDamage = attacker.currentDamage;
    final totalDamage = baseDamage + terrainBonus + buffBonus;
    final hpAfter = (enemyHp - totalDamage).clamp(0, 999);
    final willWin = hpAfter <= 0;
    final laneName = _getLaneName(col);

    showDialog(
      context: context,
      barrierDismissible: true,
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
                  // Show buff breakdown
                  if (hasTerrainBuff || buffBonus > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '($baseDamage base',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (terrainBonus > 0) ...[
                            Text(
                              ' + $terrainBonus ',
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
                          ],
                          if (buffBonus > 0)
                            Text(
                              ' + $buffBonus buff',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
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
                        'VICTORY!',
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
              'ATTACK BASE',
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

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: Column(
              children: [
                const Text('Base Attacked!'),
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
                            'VICTORY!',
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

    // If we have a card selected and this is a valid target, attack or heal it
    if (_selectedCardForAction != null && _validTargets.contains(card)) {
      if (_isMedic(_selectedCardForAction!)) {
        _healTargetTYC3(card, row, col);
      } else {
        _attackTargetTYC3(card, row, col);
      }
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

  void _selectCardForActionNoToggle(GameCard card, int row, int col) {
    if (!_matchManager.isPlayerTurn) return;
    if (row == 0) return;

    setState(() {
      _selectedCard = null;
      _selectedCardForAction = card;
      _selectedCardRow = row;
      _selectedCardCol = col;

      if (card.currentAP > 0) {
        final reachableTargets = _matchManager.getReachableAttackTargets(
          card,
          row,
          col,
        );
        _validTargets = reachableTargets.map((t) => t.target).toList();
      } else {
        _validTargets = [];
      }
    });
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

    // Use shared SimpleAI logic
    await _ai.executeTurnTYC3(
      _matchManager,
      delayMs: 300,
      onAction: (description) {
        debugPrint('AI Action: $description');
        if (mounted) setState(() {});
      },
      onCombatResult:
          (
            attacker,
            target,
            result,
            attackerRow,
            attackerCol,
            targetRow,
            targetCol,
          ) async {
            if (mounted) {
              setState(() {});
              await WidgetsBinding.instance.endOfFrame;
              await _playAttackArrow(
                attacker,
                attackerRow,
                attackerCol,
                target,
                targetRow,
                targetCol,
              );
              await _showAIBattleResultDialog(
                result,
                attacker,
                target,
                targetCol,
              );
            }
          },
      onBaseAttack:
          (
            attacker,
            damage,
            attackerRow,
            attackerCol,
            targetBaseRow,
            targetBaseCol,
          ) async {
            if (mounted) {
              setState(() {});
              await WidgetsBinding.instance.endOfFrame;
              await _playAttackArrowToTile(
                attacker,
                attackerRow,
                attackerCol,
                targetBaseRow,
                targetBaseCol,
              );
              await _showAIBaseAttackDialog(attacker, damage, targetBaseCol);
            }
          },
    );

    // End AI turn
    _matchManager.endTurnTYC3();
    FlameAudio.play('turn_pass.mp3');
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
    } else {
      _playerId = 'local_player';
      _playerName = 'Player';
    }

    // Load saved deck from Firebase
    _savedDeck = await _deckStorage.loadDeck();
    debugPrint('Loaded saved deck: ${_savedDeck?.length ?? 0} cards');

    debugPrint(
      'Match init flags: onlineMatchId=${widget.onlineMatchId}, forceCampaignDeck=${widget.forceCampaignDeck}, playerId=$_playerId',
    );

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
        await _startNewMatch();
      }
    }
  }

  /// Initialize online multiplayer match
  Future<void> _initOnlineMatch() async {
    if (widget.onlineMatchId == null || _playerId == null || _firestore == null)
      return;

    try {
      // Get match data to determine which player we are
      final matchDoc = await _firestore!
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

      // Check if we already selected hero/deck (from DeckSelectionScreen)
      final myData = _amPlayer1 ? matchData['player1'] : matchData['player2'];
      final myHeroId = myData?['heroId'] as String?;
      final rawDeck = myData?['deck'];
      debugPrint(
        '🔍 Raw deck from Firebase: ${rawDeck?.runtimeType} = $rawDeck',
      );

      List<String>? myDeckNames;
      if (rawDeck is List) {
        // Check if it's a list of strings or a list of maps
        if (rawDeck.isNotEmpty && rawDeck.first is String) {
          myDeckNames = rawDeck.cast<String>();
        } else if (rawDeck.isNotEmpty && rawDeck.first is Map) {
          // Firebase stored GameCard objects as maps - extract names
          myDeckNames = rawDeck
              .map((item) => (item as Map)['name'] as String)
              .toList();
          debugPrint(
            '⚠️ Deck was stored as maps, extracted names: $myDeckNames',
          );
        }
      }

      if (myHeroId != null && myDeckNames != null) {
        _selectedHero = HeroLibrary.getHeroById(myHeroId);

        // PRIORITY: Use widget.customDeck if provided (passed directly from matchmaking)
        if (widget.customDeck != null && widget.customDeck!.isNotEmpty) {
          _selectedOnlineDeck = widget.customDeck;
          debugPrint(
            '✅ Using customDeck from widget (${widget.customDeck!.length} cards). First: ${widget.customDeck!.first.name}',
          );
        } else if (_playerId != null) {
          // Fallback: Build deck from Firebase names
          final deck = Deck.fromCardNames(
            playerId: _playerId!,
            cardNames: myDeckNames,
          );
          _selectedOnlineDeck = deck.cards;
          debugPrint(
            '📦 Built deck from Firebase names (${_selectedOnlineDeck?.length} cards). First: ${_selectedOnlineDeck?.first.name}',
          );
        }
        debugPrint(
          'Loaded pre-selected hero: ${_selectedHero?.name}, deck: ${_selectedOnlineDeck?.length} cards',
        );
      } else if (widget.customDeck != null && widget.customDeck!.isNotEmpty) {
        // We have a custom deck but no Firebase data - use it directly
        _selectedOnlineDeck = widget.customDeck;
        if (widget.selectedHero != null) {
          _selectedHero = widget.selectedHero;
        }
        debugPrint(
          '✅ Using customDeck (no Firebase data). Hero: ${_selectedHero?.name}, Deck: ${widget.customDeck!.length} cards',
        );
      } else {
        // Fallback: Show selection dialog if not selected
        if (mounted) {
          await _showHeroSelectionDialog();
        }
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
      await _firestore!.collection('matches').doc(widget.onlineMatchId).update({
        '$myKey.heroId': selected.id,
      });

      debugPrint('Selected hero: ${selected.name}');
    } else {
      // Default to Napoleon if dialog dismissed somehow
      _selectedHero = HeroLibrary.napoleon();
    }

    // 2. Select Deck (if hero selected)
    if (_selectedHero != null && mounted) {
      final selectedDeck = await Navigator.of(context).push<List<GameCard>>(
        MaterialPageRoute(
          builder: (_) => DeckSelectionScreen(
            heroId: _selectedHero!.id,
            onDeckSelected: (deck) {
              Navigator.of(context).pop(deck);
            },
          ),
        ),
      );

      if (selectedDeck != null) {
        _selectedOnlineDeck = selectedDeck;
        debugPrint('Selected online deck: ${selectedDeck.length} cards');
      } else {
        // Fallback to default deck for hero
        // Logic handled in _startNewMatch via _selectedOnlineDeck being null
        debugPrint('No deck selected - using default');
      }
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
      case HeroAbilityType.directBaseDamage:
        return Icons.local_fire_department;
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

  Widget _buildTimerDisplay(MatchState match) {
    if (_useChessTimer) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Player Clock
            // _buildChessClockItem(
            //   label: 'YOU',
            //   seconds: match.playerTotalTimeRemaining,
            //   isActive: _matchManager.isPlayerTurn,
            //   isCritical: match.playerTotalTimeRemaining <= 30,
            // ),
            // const SizedBox(width: 8),
            // Opponent Clock
            _buildChessClockItem(
              label: 'OPP',
              seconds: match.opponentTotalTimeRemaining,
              isActive: !(_matchManager.isPlayerTurn), // Opponent turn
              isCritical: match.opponentTotalTimeRemaining <= 30,
            ),
          ],
        ),
      );
    }

    // Standard Timer (only show if player turn)
    if (!_matchManager.isPlayerTurn) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: _turnSecondsRemaining <= 10 ? Colors.red : Colors.green,
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
    );
  }

  Widget _buildChessClockItem({
    required String label,
    required int seconds,
    required bool isActive,
    required bool isCritical,
  }) {
    // Format MM:SS
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final timeStr = '$m:${s.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? (isCritical ? Colors.red : Colors.green[700])
            : Colors.grey[700],
        borderRadius: BorderRadius.circular(4),
        border: isActive ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 8, color: Colors.white70),
          ),
          Text(
            timeStr,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
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

  /// Determine attack style from card abilities and properties
  /// Returns: 'melee' (sword), 'ranged' (bow - no retaliation), or 'long_range' (cannon - 2 tile range)
  String _getAttackStyle(GameCard card) {
    // Long range (cannon): attackRange >= 2 or has 'long_range' or 'far_attack' ability
    if (card.isLongRange || card.abilities.contains('far_attack')) {
      return 'long_range';
    }
    // Ranged (archer): has 'ranged' ability - no retaliation but range 1
    if (card.isRanged) return 'ranged';
    // Default: melee
    return 'melee';
  }

  /// Get icon for attack style
  /// - Melee: Sword (gets retaliation, range 1)
  /// - Ranged/Archer: Bow (no retaliation, range 1) 🏹
  /// - Long Range/Cannon: Explosion (no retaliation, range 2) 💥
  IconData _getAttackStyleIcon(String attackStyle) {
    switch (attackStyle) {
      case 'long_range':
        return Icons.gps_fixed; // Target/crosshair for cannon (long range)
      case 'ranged':
        return Icons.arrow_forward; // Arrow for ranged (no retaliation)
      case 'melee':
      default:
        return Icons.sports_martial_arts; // Sword for melee
    }
  }

  /// Get color for attack style icon
  Color _getAttackStyleColor(String attackStyle) {
    switch (attackStyle) {
      case 'long_range':
        return Colors.deepOrange[700]!; // Cannon = deep orange (explosive)
      case 'ranged':
        return Colors.teal[600]!; // Archer = teal (swift, precise)
      case 'melee':
      default:
        return Colors.blueGrey[700]!; // Sword = steel blue-grey
    }
  }

  /// Build attack style icon widget with tooltip
  Widget _buildAttackStyleIcon(GameCard card, {double size = 10}) {
    final style = _getAttackStyle(card);
    final icon = _getAttackStyleIcon(style);
    final color = _getAttackStyleColor(style);

    // Add a small indicator for range
    if (style == 'long_range') {
      // Show "2" badge for long range
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: size, color: color),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Colors.deepOrange[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '2',
                style: TextStyle(
                  fontSize: size * 0.5,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Icon(icon, size: size, color: color);
  }

  /// Get human-readable label for attack style
  String _getAttackStyleLabel(String attackStyle) {
    switch (attackStyle) {
      case 'long_range':
        return 'Cannon (Range 2)'; // Long range - can hit 2 tiles away
      case 'ranged':
        return 'Archer (No Retaliation)'; // Ranged - no retaliation but range 1
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
        if (ability.startsWith('medic_')) {
          final amount = ability.split('_').last;
          return 'Heals a friendly unit on the same tile for $amount HP.';
        }
        return ability;
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
      case 'stealth_pass':
        return 'Stealth';
      case 'paratrooper':
        return 'Paratrooper';
      case 'flanking':
        return 'Flanking';
      default:
        if (ability.startsWith('medic_')) {
          return 'Medic ${ability.split('_').last}';
        }
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

  void _showCombatLogDialog(Gravestone gravestone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.sentiment_very_dissatisfied, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text('R.I.P. ${gravestone.cardName}')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Battle Summary:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[400]!),
              ),
              child: Text(gravestone.deathLog),
            ),
            const SizedBox(height: 12),
            Text(
              'Time: ${gravestone.timestamp.hour}:${gravestone.timestamp.minute.toString().padLeft(2, '0')}:${gravestone.timestamp.second.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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
                    isHumanPlayer ? 'Card Added to Hand!' : 'Enemy Gained:',
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
                      _buildStatBadge(
                        'ATK',
                        '${rewardCard.damage}',
                        Colors.red,
                      ),
                      const SizedBox(width: 12),
                      _buildStatBadge(
                        'HP',
                        '${rewardCard.health}',
                        Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _buildStatBadge('SPD', '${rewardCard.tick}', Colors.blue),
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
    if (widget.onlineMatchId == null || _firestore == null) return;

    debugPrint(
      '📡 Starting Firebase listener for match: ${widget.onlineMatchId}',
    );

    _matchListener = _firestore!
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
        _firestore!.collection('matches').doc(widget.onlineMatchId).update({
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

  /// Show Mulligan dialog to replace initial cards
  Future<void> _showMulliganDialog() async {
    final player = _matchManager.currentMatch?.player;
    if (player == null || player.hand.isEmpty) return;

    if (player.deck.remainingCards <= 0) {
      return;
    }

    // Mulligan is only for the local player
    final hand = player.hand;
    final selectedIndices = <int>{};
    int secondsLeft = 10;
    Timer? timer;

    // Only use timer in online mode - PvE has no time pressure
    final useTimer = _isOnlineMode;

    // Wait for the dialog to close
    final result = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Start timer once (only in online mode)
            if (useTimer) {
              timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
                if (secondsLeft > 0) {
                  if (mounted) {
                    setStateDialog(() {
                      secondsLeft--;
                    });
                  }
                } else {
                  t.cancel();
                  // Auto-confirm with selection if time runs out
                  Navigator.of(context).pop(selectedIndices.toList());
                }
              });
            }

            return AlertDialog(
              backgroundColor: Colors.brown[50],
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Mulligan Phase'),
                  if (useTimer)
                    Text(
                      '$secondsLeft s',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select up to 2 cards to replace:',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardW = 80.0;
                        final cardH = 120.0;
                        final n = hand.length;
                        final maxW = constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : 420.0;

                        final spread = (maxW - cardW) / (n > 1 ? (n - 1) : 1);
                        final spacing = spread.clamp(
                          cardW * 0.32,
                          cardW * 0.85,
                        );
                        final fanWidth =
                            cardW + spacing * (n > 0 ? (n - 1) : 0);
                        final leftPad = ((maxW - fanWidth) / 2).clamp(
                          0.0,
                          maxW,
                        );
                        final center = (n - 1) / 2.0;
                        final maxAngle = (n <= 1)
                            ? 0.0
                            : (0.32 * (1.0 - (n - 2) * 0.03)).clamp(0.18, 0.32);

                        return SizedBox(
                          width: maxW,
                          height: cardH + 26,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: List.generate(n, (index) {
                              final card = hand[index];
                              final isSelected = selectedIndices.contains(
                                index,
                              );
                              final t = n <= 1
                                  ? 0.0
                                  : ((index - center) / center);
                              final angle = t * maxAngle;
                              final lift =
                                  (t.abs() * 6.0) + (isSelected ? 12.0 : 0.0);
                              final x = leftPad + index * spacing;

                              return Positioned(
                                left: x,
                                top: 8 + (t.abs() * 4.0) - lift,
                                child: GestureDetector(
                                  onTap: () {
                                    setStateDialog(() {
                                      if (isSelected) {
                                        selectedIndices.remove(index);
                                      } else if (selectedIndices.length < 2) {
                                        selectedIndices.add(index);
                                      }
                                    });
                                  },
                                  child: Transform.rotate(
                                    angle: angle,
                                    alignment: Alignment.bottomCenter,
                                    child: Transform.scale(
                                      scale: isSelected ? 1.08 : 1.0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.red
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Opacity(
                                          opacity: isSelected ? 0.75 : 1.0,
                                          child: _buildHandCardVisual(
                                            card,
                                            cardW,
                                            cardH,
                                            false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    Navigator.of(context).pop(selectedIndices.toList());
                  },
                  child: Text(
                    selectedIndices.isEmpty
                        ? 'Keep Hand'
                        : 'Confirm Replacement (${selectedIndices.length})',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    timer?.cancel();

    if (result != null && result.isNotEmpty) {
      // Perform replacement
      final cardsToReplace = result.map((i) => hand[i]).toList();

      setState(() {
        player.replaceCards(cardsToReplace);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Replaced ${cardsToReplace.length} cards with new ones from deck',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green[700],
          ),
        );
      }

      // If online, force sync state to update opponent (though hand is private, it's good practice)
      // Actually, opponent doesn't see our hand, so strictly speaking not required,
      // but if we want to ensure deck counts are synced or if we trust client state fully...
      // Current implementation syncs everything.
      if (_isOnlineMode && _onlineGameManager != null) {
        // Only sync if it's our turn, otherwise we might overwrite opponent's move?
        // Wait, online sync is state-based.
        // If it's my turn, I sync. If not, I don't.
        // But Mulligan happens at start.
        // Player 1 syncs first.
        if (_matchManager.isPlayerTurn) {
          _onlineGameManager!.syncState(_matchManager.currentMatch!);
        }
      }
    }
  }

  Future<void> _startNewMatch() async {
    debugPrint('🚀 _startNewMatch called');
    debugPrint(
      '   mode flags: onlineMatchId=${widget.onlineMatchId}, _isOnlineMode=$_isOnlineMode, forceCampaignDeck=${widget.forceCampaignDeck}',
    );
    debugPrint(
      '   _selectedOnlineDeck: ${_selectedOnlineDeck?.length} cards, first: ${_selectedOnlineDeck?.firstOrNull?.name}',
    );
    debugPrint(
      '   widget.customDeck: ${widget.customDeck?.length} cards, first: ${widget.customDeck?.firstOrNull?.name}',
    );
    debugPrint(
      '   _savedDeck: ${_savedDeck?.length} cards, first: ${_savedDeck?.firstOrNull?.name}',
    );

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

      // Select opponent hero based on campaign act
      if (widget.forceCampaignDeck) {
        switch (widget.campaignAct) {
          case 2: // Egypt
            opponentHero = HeroLibrary.saladin();
            break;
          case 3: // Coalition (Austria/Russia)
            opponentHero = HeroLibrary.archdukeCharles();
            break;
          default: // Act 1 (Italy/Austria)
            opponentHero = HeroLibrary.archdukeCharles();
        }
      } else {
        opponentHero = HeroLibrary.saladin();
      }
    }

    // Determine which deck to use
    debugPrint(
      'forceCampaignDeck: ${widget.forceCampaignDeck}, hero: ${playerHero.name}',
    );
    final Deck playerDeck;

    // Check for specific hero decks
    if (widget.forceCampaignDeck) {
      // Campaign mode: prefer the campaign deck passed in from the campaign state.
      if (widget.customDeck != null) {
        playerDeck = Deck(
          id: 'custom_$id',
          name: "${playerHero.name} Campaign Deck",
          cards: widget.customDeck!.map((c) => c.clone()).toList(),
          skipValidation: true,
        );
        // Ensure deck is shuffled for each new battle
        playerDeck.shuffle();
        debugPrint(
          '🎖️ CAMPAIGN MODE: Using provided campaign deck (${widget.customDeck!.length} cards, shuffled)',
        );
      } else if (playerHero.id == 'napoleon') {
        playerDeck = Deck.napoleon(playerId: id);
        playerDeck.shuffle();
        debugPrint(
          '🎖️ CAMPAIGN MODE: Using Napoleon starter deck (25 cards, shuffled)',
        );
      } else {
        // Fallback for other campaign heroes
        playerDeck = Deck.starter(playerId: id);
        playerDeck.shuffle();
        debugPrint(
          '🎖️ CAMPAIGN MODE: Using starter deck for ${playerHero.name} (shuffled)',
        );
      }
    } else if (_isOnlineMode && _selectedOnlineDeck != null) {
      // Use online selected deck
      playerDeck = Deck.fromCards(playerId: id, cards: _selectedOnlineDeck!);
      debugPrint(
        'Using online selected deck (${_selectedOnlineDeck!.length} cards)',
      );
      debugPrint(
        '🃏 Online deck cards: ${_selectedOnlineDeck!.take(5).map((c) => c.name).join(", ")}...',
      );
    } else if (widget.customDeck != null) {
      // Use custom deck passed in constructor
      playerDeck = Deck.fromCards(playerId: id, cards: widget.customDeck!);
      debugPrint(
        'Using custom selected deck (${widget.customDeck!.length} cards)',
      );
    } else if (_savedDeck != null && _savedDeck!.isNotEmpty) {
      // Use saved deck if available (custom deck overrides hero default)
      // Note: This might need changing if we want to force hero decks
      playerDeck = Deck.fromCards(playerId: id, cards: _savedDeck!);
      debugPrint('Using saved deck (${_savedDeck!.length} cards)');
    } else {
      // Default deck based on hero ID
      switch (playerHero.id) {
        case 'napoleon':
          playerDeck = Deck.napoleon(playerId: id);
          debugPrint('Using Napoleon\'s Grand Army deck');
          break;
        case 'saladin':
          playerDeck = Deck.saladin(playerId: id);
          debugPrint('Using Saladin\'s Desert Warriors deck');
          break;
        case 'admiral_nelson':
          playerDeck = Deck.nelson(playerId: id);
          debugPrint('Using Nelson\'s Royal Navy deck');
          break;
        case 'archduke_charles':
          playerDeck = Deck.archduke(playerId: id);
          debugPrint('Using Archduke\'s Austrian Army deck');
          break;
        default:
          playerDeck = Deck.starter(playerId: id);
          debugPrint('Using generic starter deck');
      }
    }

    // Apply campaign bonuses to the selected deck.
    // This is applied only for the current match; it does not mutate saved/campaign deck state.
    final bool hasDeckBonuses =
        widget.playerDamageBonus != 0 ||
        widget.artilleryDamageBonus != 0 ||
        widget.cannonHealthBonus != 0 ||
        widget.playerCardHealthBonus != 0;
    final Deck effectivePlayerDeck = hasDeckBonuses
        ? (widget.forceCampaignDeck
              ? Deck(
                  id: 'custom_$id',
                  name: playerDeck.name,
                  cards: playerDeck.cards.map((c) {
                    final isArtillery = _isArtilleryCard(c);
                    final artilleryDmgBonus = isArtillery
                        ? widget.artilleryDamageBonus
                        : 0;
                    final cannonHpBonus = isArtillery
                        ? widget.cannonHealthBonus
                        : 0;
                    final totalDmgBonus =
                        widget.playerDamageBonus + artilleryDmgBonus;
                    final totalHpBonus =
                        widget.playerCardHealthBonus + cannonHpBonus;
                    final newDamage = c.damage + totalDmgBonus;
                    final newHealth = c.health + totalHpBonus;
                    if (totalDmgBonus == 0 && totalHpBonus == 0) {
                      return c;
                    }
                    return c.copyWith(damage: newDamage, health: newHealth);
                  }).toList(),
                  skipValidation: true,
                )
              : Deck.fromCards(
                  playerId: id,
                  name: playerDeck.name,
                  cards: playerDeck.cards.map((c) {
                    final isArtillery = _isArtilleryCard(c);
                    final artilleryDmgBonus = isArtillery
                        ? widget.artilleryDamageBonus
                        : 0;
                    final cannonHpBonus = isArtillery
                        ? widget.cannonHealthBonus
                        : 0;
                    final totalDmgBonus =
                        widget.playerDamageBonus + artilleryDmgBonus;
                    final totalHpBonus =
                        widget.playerCardHealthBonus + cannonHpBonus;
                    final newDamage = c.damage + totalDmgBonus;
                    final newHealth = c.health + totalHpBonus;
                    if (totalDmgBonus == 0 && totalHpBonus == 0) {
                      return c;
                    }
                    return c.copyWith(damage: newDamage, health: newHealth);
                  }).toList(),
                ))
        : playerDeck;

    _campaignDestroyedPlayerCardIds.clear();
    _fallenPlayerCardCounts.clear();
    _matchManager.onCardDestroyed = (card) {
      final match = _matchManager.currentMatch;
      if (match == null) return;
      if (card.ownerId != match.player.id) return;

      // Always track fallen cards for Victory screen summary.
      _fallenPlayerCardCounts[card.name] =
          (_fallenPlayerCardCounts[card.name] ?? 0) + 1;

      // Campaign needs IDs back to map for permanent destruction.
      if (widget.forceCampaignDeck && !_isOnlineMode) {
        _campaignDestroyedPlayerCardIds.add(card.id);
      }
    };

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
    debugPrint(
      'Battle modifiers: playerBaseHP=${widget.playerCurrentHealth}, opponentBaseHP=${widget.opponentBaseHP}, playerDamageBonus=${widget.playerDamageBonus}, artilleryDamageBonus=${widget.artilleryDamageBonus}, extraStartingDraw=${widget.extraStartingDraw}',
    );
    debugPrint('Deck name: ${effectivePlayerDeck.name}');
    debugPrint('Deck cards (${effectivePlayerDeck.cards.length}):');
    for (final card in effectivePlayerDeck.cards) {
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
      if (!_isOnlineMode &&
          terrainsToUse == null &&
          widget.predefinedTerrainsOverride != null) {
        terrainsToUse = widget.predefinedTerrainsOverride;
        debugPrint('Using predefined terrains override (campaign)');
      }

      // Skip opponent shuffle if we have synced deck (already in correct order)
      final skipOppShuffle = _isOnlineMode && _opponentDeckCardNames != null;

      // Define custom relic for campaign (if applicable)
      String? relicName;
      String? relicDescription;
      if (widget.forceCampaignDeck) {
        switch (widget.campaignAct) {
          case 1:
            relicName = 'Austrian Supply Wagon';
            relicDescription =
                'Supplies captured from the Austrian army. Contains a useful card.';
            break;
          case 2:
            relicName = 'Desert Cache';
            relicDescription =
                'A hidden store found in the sands. Contains a useful card.';
            break;
          case 3:
            relicName = 'Coalition Stockpile';
            relicDescription =
                'Captured enemy supplies. Contains a useful card.';
            break;
        }
      }

      _matchManager.startMatchTYC3(
        playerId: id,
        playerName: name,
        playerDeck: effectivePlayerDeck,
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
        predefinedRelicColumn: _predefinedRelicColumn,
        skipOpponentShuffle: skipOppShuffle,
        relicName: relicName,
        relicDescription: relicDescription,
        isChessTimerMode: _useChessTimer,
        playerBaseHP: widget.playerCurrentHealth,
        opponentBaseHP: widget.opponentBaseHP,
        opponentPriorityCardIds: widget.opponentPriorityCardIds.isEmpty
            ? null
            : widget.opponentPriorityCardIds,
      );

      if (widget.extraStartingDraw > 0) {
        _matchManager.currentMatch?.player.drawCards(
          count: widget.extraStartingDraw,
        );
      }

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
          // In Chess Mode, timer runs constantly to tick opponent clock
          if (_useChessTimer) {
            _startTurnTimer();
          }
        }
      } else {
        // Single player: Start turn timer if it's player's turn
        // Note: AI turn is triggered AFTER mulligan completes (see end of _startNewMatch)
        if (_matchManager.isPlayerTurn) {
          _startTurnTimer();
        }
        // Don't trigger AI here - wait for mulligan to complete first
      }
    } else {
      _matchManager.startMatch(
        playerId: id,
        playerName: name,
        playerDeck: effectivePlayerDeck,
        opponentId: opponentIdFinal,
        opponentName: opponentNameFinal,
        opponentDeck: opponentDeck,
        opponentIsAI: !_isOnlineMode,
        playerAttunedElement: playerHero.terrainAffinities.first,
        opponentAttunedElement: opponentHero.terrainAffinities.first,
        playerHero: playerHero,
        opponentHero: opponentHero,
        opponentBaseHP: widget.opponentBaseHP,
      );

      if (widget.extraStartingDraw > 0) {
        _matchManager.currentMatch?.player.drawCards(
          count: widget.extraStartingDraw,
        );
      }
    }
    _clearStaging();
    _clearTYC3Selection();
    _lastProcessedActionIndex = 0; // Reset action tracking for new match
    setState(() {});

    // Mulligan Phase - MUST happen before AI can play
    if (mounted) {
      final player = _matchManager.currentMatch?.player;
      final canMulligan =
          player != null &&
          player.hand.isNotEmpty &&
          player.deck.remainingCards > 0;
      if (canMulligan) {
        await _showMulliganDialog();
      }
    }

    // After mulligan, trigger AI turn if needed (single-player only, TYC3 mode)
    if (!_isOnlineMode &&
        _useTYC3Mode &&
        _matchManager.isOpponentTurn &&
        mounted) {
      _doAITurnTYC3();
    }
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
      await _firestore!.collection('matches').doc(widget.onlineMatchId).update({
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

      await _firestore!
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
    if (widget.onlineMatchId == null || _firestore == null) return;

    try {
      final docRef = _firestore!
          .collection('matches')
          .doc(widget.onlineMatchId);
      await docRef.update({
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
      await _firestore!.collection('matches').doc(widget.onlineMatchId).update({
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

  /// DEBUG: Instantly win the battle (Campaign testing)
  void _debugWinBattle() {
    final match = _matchManager.currentMatch;
    if (match == null) return;

    setState(() {
      // Deal fatal damage to opponent base
      match.opponent.takeBaseDamage(match.opponent.baseHP);

      // Trigger game over
      match.currentPhase = MatchPhase.gameOver;
      match.winnerId = match.player.id;

      debugPrint('🏆 DEBUG: Forced win for player');
    });
  }

  @override
  Widget build(BuildContext context) {
    // If in replay mode, render from snapshot
    if (_isReplayMode && _currentReplaySnapshot != null) {
      return _buildReplayUI();
    }

    final match = _matchManager.currentMatch;

    // Show waiting screen for online mode while waiting for opponent's hero
    if (match == null) {
      if (_isOnlineMode && _selectedHero != null && !_heroSelectionComplete) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Online Match'),
            backgroundColor: const Color(0xFF16213E),
            foregroundColor: Colors.white,
          ),
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
        appBar: AppBar(
          title: const Text('Test Match'),
          backgroundColor: const Color(0xFF16213E),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('No match in progress')),
      );
    }

    final buffsForDialog = widget.campaignBuffLabelsForBuffsDialog.isNotEmpty
        ? widget.campaignBuffLabelsForBuffsDialog
        : widget.campaignBuffLabels;

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
          backgroundColor: const Color(0xFF16213E),
          foregroundColor: Colors.white,
          actions: [
            if (!match.isGameOver)
              IconButton(
                icon: const Icon(Icons.style),
                tooltip: 'Deck',
                onPressed: () => _showDeckDialog(match),
              ),

            // DEBUG: Win Battle button (Campaign only)
            if ((widget.enemyDeck != null || widget.forceCampaignDeck) &&
                !match.isGameOver)
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.amber),
                tooltip: 'Win Battle (Debug)',
                onPressed: _debugWinBattle,
              ),

            // TYC3: Show turn timer (only in online mode)
            if (_useTYC3Mode && _isOnlineMode && !match.isGameOver)
              _buildTimerDisplay(match),

            if (buffsForDialog.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'Buffs',
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Active buffs'),
                      content: Text(buffsForDialog.join('\n')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
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

            IconButton(
              icon: Icon(_showSettings ? Icons.visibility_off : Icons.tune),
              onPressed: () => setState(() => _showSettings = !_showSettings),
              tooltip: _showSettings ? 'Hide Settings' : 'Show Settings',
            ),
          ],
        ),
        body: Column(
          children: [
            if (_showSettings) _buildSettingsPanel(),
            Expanded(
              child: match.isGameOver
                  ? _buildGameOver(match)
                  : _buildMatchView(match),
            ),
          ],
        ),
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

  Widget _buildReplayUI() {
    final snapshot = _currentReplaySnapshot!;
    final board = snapshot.boardState;

    // Create a temporary MatchState to reuse existing UI builders
    // IMPORTANT: Use the player/opponent states from the snapshot!
    final replayMatch = MatchState(
      player: snapshot.playerState,
      opponent: snapshot.opponentState,
      board: board,
      currentPhase: MatchPhase.gameOver,
      turnNumber: snapshot.turnNumber,
    )..activePlayerId = snapshot.activePlayerId;

    // Use existing board view but with replay controls overlay
    return Scaffold(
      appBar: AppBar(
        title: Text('Replay - Turn ${snapshot.turnNumber}'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exitReplay,
            tooltip: 'Exit Replay',
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMatchView(replayMatch),

          // Replay Control Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.8),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 32),
                    color: Colors.white,
                    onPressed: _replayTurnIndex > 0 ? _prevReplayTurn : null,
                  ),
                  const SizedBox(width: 24),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Turn ${snapshot.turnNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_replayTurnIndex + 1} / ${_matchManager.currentMatch!.history.length}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 32),
                    color: Colors.white,
                    onPressed:
                        _replayTurnIndex <
                            _matchManager.currentMatch!.history.length - 1
                        ? _nextReplayTurn
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
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

    // Show "End Turn" button during player's turn (small icon)
    if (_matchManager.isPlayerTurn) {
      return FloatingActionButton.small(
        onPressed: _endTurnTYC3,
        tooltip: 'End Turn',
        backgroundColor: Colors.blue[700],
        heroTag: 'endTurn',
        child: const Icon(Icons.skip_next, size: 24),
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

    final startPlayerBaseHp = widget.playerCurrentHealth ?? Player.maxBaseHP;
    final maxPlayerBaseHp = widget.playerMaxHealth ?? startPlayerBaseHp;
    final currentPlayerBaseHp = match.player.baseHP;
    final damageTakenThisBattle = (startPlayerBaseHp - currentPlayerBaseHp)
        .clamp(0, startPlayerBaseHp);

    final fallenLines = _fallenPlayerCardCounts.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key} ×${e.value}')
        .toList();

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
          Text('Player Base: ${match.player.baseHP} HP'),
          Text('Opponent Base: ${match.opponent.baseHP} HP'),
          const SizedBox(height: 16),
          Container(
            width: 360,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Battle Summary',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Base damage taken: $damageTakenThisBattle',
                  style: const TextStyle(fontSize: 12, height: 1.25),
                ),
                Text(
                  'Base HP: $currentPlayerBaseHp / $maxPlayerBaseHp',
                  style: const TextStyle(fontSize: 12, height: 1.25),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Fallen cards',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  fallenLines.isEmpty ? 'None' : fallenLines.join('\n'),
                  style: const TextStyle(fontSize: 12, height: 1.25),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Total Turns: ${match.turnNumber}'),
          if (isCampaignMode && widget.campaignBuffLabels.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: 360,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active buffs',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.campaignBuffLabels.join('\n'),
                    style: const TextStyle(fontSize: 12, height: 1.25),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 30),
          // Replay Button
          if (match.history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: _startReplay,
                icon: const Icon(Icons.history),
                label: const Text('WATCH REPLAY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          // Continue button - returns result to campaign
          ElevatedButton.icon(
            onPressed: () {
              if (isCampaignMode) {
                // Calculate actual damage taken based on starting HP
                // Default to 25 if not provided (matches Player.maxBaseHP)
                final startHP = widget.playerCurrentHealth ?? 25;
                final endHP = match.player.baseHP;
                final damageTaken = (startHP - endHP).clamp(0, startHP);

                Navigator.pop(context, {
                  'won': playerWon,
                  'crystalDamage': damageTaken,
                  'turnsPlayed': match.turnNumber,
                  'destroyedCardIds': _campaignDestroyedPlayerCardIds.toList(),
                });
              } else {
                // Return to main menu safely (avoid popping the app)
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainMenuScreen()),
                  (route) => false,
                );
              }
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
      key: _matchViewStackKey,
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

        if (_showAttackArrow &&
            _attackArrowFrom != null &&
            _attackArrowTo != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _attackArrowController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AttackArrowPainter(
                      from: _attackArrowFrom!,
                      to: _attackArrowTo!,
                      t: _attackArrowController.value,
                    ),
                  );
                },
              ),
            ),
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
                        ? '${currentLane.name.toUpperCase()} LANE'
                        : 'COMBAT IN PROGRESS',
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
                    '${activeLane.name.toUpperCase()} LANE',
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
                    'Combat at: ${zone == Zone.playerBase ? 'YOUR BASE' : (zone == Zone.enemyBase ? 'ENEMY BASE' : 'MIDDLE')}',
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
                                'YOUR CARDS',
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
                                'ENEMY CARDS',
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
            if (card.isDecoy && isPlayer)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '⚠️ DECOY UNIT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
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
                _buildZoomStat('ATK', '${card.damage}'),
                _buildZoomStat('TICK', 'T${card.tick}'),
              ],
            ),

            // Terrain
            if (card.element != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${card.element}',
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
                  'DESTROYED',
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
                  if (!_isOnlineMode &&
                      widget.forceCampaignDeck &&
                      hero.abilityType == HeroAbilityType.drawCards &&
                      widget.heroAbilityDamageBoost > 0) {
                    _matchManager.addPlayerDamageBoostThisTurn(
                      widget.heroAbilityDamageBoost,
                      source: 'Inspiring Presence',
                    );
                  }
                  setState(() {});
                  _showHeroAbilityDialog(
                    SyncedHeroAbility(
                      id: 'temp', // ID doesn't matter for local display
                      heroName: hero.name,
                      abilityName: hero.abilityType.name,
                      description: hero.abilityDescription,
                      playerId: _matchManager.currentMatch!.player.id,
                    ),
                    isOpponent: false,
                  );
                  // Sync state immediately so opponent sees it
                  _syncOnlineState();
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

      // Fog of War: Check if player has cards in middle (row 1) OR enemy base (row 0) of this lane
      final middleTile = match.board.getTile(1, col);
      final enemyBaseTile = match.board.getTile(0, col);
      final playerHasMiddleCard = middleTile.cards.any(
        (c) => c.ownerId == playerId && c.isAlive,
      );
      final playerHasEnemyBaseCard = enemyBaseTile.cards.any(
        (c) => c.ownerId == playerId && c.isAlive,
      );

      // Check if a scout in middle can see this lane
      bool scoutCanSee = false;
      for (int scoutCol = 0; scoutCol < 3; scoutCol++) {
        final scoutTile = match.board.getTile(1, scoutCol);
        final hasScout = scoutTile.cards.any(
          (c) =>
              c.ownerId == playerId &&
              c.isAlive &&
              c.abilities.contains('scout'),
        );
        if (hasScout) {
          // Scout can see its own lane and adjacent lanes
          if (scoutCol == col) {
            scoutCanSee = true;
          } else if ((scoutCol - col).abs() == 1) {
            scoutCanSee = true;
          } else if (scoutCol == 1) {
            // Center scout can see all lanes
            scoutCanSee = true;
          }
        }
      }

      // Unit FOW: Dynamic visibility only (no permanent reveal for units)
      final canSeeEnemyBaseUnits =
          playerHasMiddleCard || playerHasEnemyBaseCard || scoutCanSee;

      // Use card.ownerId to determine ownership
      for (final card in tileCards) {
        if (card.ownerId == playerId) {
          playerCardsAtTile.add(card);
        } else {
          // Fog of War: Hide enemy base cards (row 0) unless player can see units
          if (row == 0 && !canSeeEnemyBaseUnits) {
            // Check if this specific unit recently attacked (visible for 1 turn)
            final recentlyAttacked = match.recentlyAttackedEnemyUnits
                .containsKey(card.id);
            if (!recentlyAttacked) {
              // Don't add to opponentCardsAtTile - hidden by fog of war
              continue;
            }
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
        _selectedCardCol != null &&
        _selectedCardForAction!.currentAP > 0 &&
        _matchManager.isPlayerTurn) {
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
            final hasEnemyCards = baseTile.cards.any(
              (c) =>
                  c.isAlive &&
                  c.ownerId != _matchManager.currentMatch!.player.id,
            );

            if (!hasEnemyCards) {
              // FOW Check: Can only attack if we have visibility of the base lane
              final playerId = _matchManager.currentMatch!.player.id;

              // Check presence in middle row or enemy base row
              final middleTile = _matchManager.currentMatch!.board.getTile(
                1,
                col,
              );
              final playerHasMiddleCard = middleTile.cards.any(
                (c) => c.ownerId == playerId && c.isAlive,
              );
              final playerHasEnemyBaseCard = baseTile.cards.any(
                (c) => c.ownerId == playerId && c.isAlive,
              );

              // Check scout visibility
              bool scoutCanSee = false;
              for (int sCol = 0; sCol < 3; sCol++) {
                final sTile = _matchManager.currentMatch!.board.getTile(
                  1,
                  sCol,
                );
                final hasScout = sTile.cards.any(
                  (c) =>
                      c.ownerId == playerId &&
                      c.isAlive &&
                      c.abilities.contains('scout'),
                );

                if (hasScout) {
                  // Scout sees own lane, adjacent lanes, and if in center sees all
                  if (sCol == col || (sCol - col).abs() == 1 || sCol == 1) {
                    scoutCanSee = true;
                    break;
                  }
                }
              }

              if (playerHasMiddleCard ||
                  playerHasEnemyBaseCard ||
                  scoutCanSee) {
                canAttackBase = true;
                break;
              }
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

    // Wrap with DragTarget to accept card drops from hand
    return DragTarget<GameCard>(
      onWillAcceptWithDetails: (details) {
        final card = details.data;
        final isFromHand = match.player.hand.contains(card);

        // Case 1: Placement from hand (existing logic)
        if (isFromHand) {
          final isPlayerBase = row == 2;
          final isMiddleRow = row == 1;
          final cardCanPlaceMiddle = card.maxAP >= 2;
          final hasEnemyOnMiddle =
              isMiddleRow && opponentCardsAtTile.isNotEmpty;

          // Check 1 card per lane limit
          int stagedInLane = 0;
          for (int r = 0; r <= 2; r++) {
            final laneKey = _tileKey(r, col);
            stagedInLane += (_stagedCards[laneKey]?.length ?? 0);
          }

          return isNotEnemyBase &&
              stagedInLane == 0 &&
              (existingPlayerCount + stagedCount) < Tile.maxCards &&
              (isPlayerBase ||
                  (isMiddleRow && cardCanPlaceMiddle && !hasEnemyOnMiddle));
        }

        // Case 2: Moving an on-board player card via drag-and-drop
        final isPlayerCard = card.ownerId == match.player.id;
        final isSelectedForMove = _selectedCardForAction == card;

        // Allow drop only on reachable tiles during player's turn
        return isPlayerCard && isSelectedForMove && canMoveTo;
      },
      onAcceptWithDetails: (details) {
        final card = details.data;
        final isFromHand = match.player.hand.contains(card);

        if (isFromHand) {
          // Place the card on this tile
          setState(() {
            _selectedCard = card;
          });
          _placeCardOnTile(row, col);
        } else {
          // Move an on-board card
          _moveCardTYC3(row, col);
          setState(() {});
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isBeingDraggedOver = candidateData.isNotEmpty;

        return Builder(
          builder: (ctx) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final rect = _globalRectForContext(ctx);
              if (rect == Rect.zero) return;
              _boardTileRects[_tileKey(row, col)] = rect;
            });

            return GestureDetector(
              onTap: () =>
                  _onTileTapTYC3(row, col, canPlace, canMoveTo, canAttackBase),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isBeingDraggedOver
                      ? Colors.green[100]!
                      : (canMoveTo ? Colors.purple[50]! : bgColor),
                  border: Border.all(
                    color: isBeingDraggedOver ? Colors.green : borderColor,
                    width: isBeingDraggedOver ? 3 : borderWidth,
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
                            bool showTerrain = true;

                            if (isEnemyBase) {
                              // Fog of war is DYNAMIC - check current visibility
                              final playerId = match.player.id;

                              // 1. Check if player has cards in middle of THIS lane
                              final middleTileForLane = match.board.getTile(
                                1,
                                col,
                              );
                              final hasPlayerCardInMiddle = middleTileForLane
                                  .cards
                                  .any(
                                    (c) => c.ownerId == playerId && c.isAlive,
                                  );

                              // 2. Check if a scout in middle can see this lane
                              bool scoutCanSee = false;
                              for (int scoutCol = 0; scoutCol < 3; scoutCol++) {
                                final scoutTile = match.board.getTile(
                                  1,
                                  scoutCol,
                                );
                                final hasScout = scoutTile.cards.any(
                                  (c) =>
                                      c.ownerId == playerId &&
                                      c.isAlive &&
                                      c.abilities.contains('scout'),
                                );
                                if (hasScout) {
                                  // Scout can see its own lane and adjacent lanes
                                  if (scoutCol == col) {
                                    scoutCanSee = true;
                                  } else if ((scoutCol - col).abs() == 1) {
                                    // Adjacent lane
                                    scoutCanSee = true;
                                  } else if (scoutCol == 1) {
                                    // Center scout can see all lanes
                                    scoutCanSee = true;
                                  }
                                }
                              }

                              // Check permanent reveal
                              final lanePos = [
                                LanePosition.west,
                                LanePosition.center,
                                LanePosition.east,
                              ][col];
                              final isPermanentlyRevealed = match
                                  .revealedEnemyBaseLanes
                                  .contains(lanePos);

                              // Show terrain if player has visibility via cards, scout, OR permanent reveal
                              showTerrain =
                                  hasPlayerCardInMiddle ||
                                  scoutCanSee ||
                                  isPermanentlyRevealed;
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

                      // Gravestones (destroyed cards)
                      if (tile.gravestones.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Wrap(
                            spacing: 2,
                            runSpacing: 2,
                            alignment: WrapAlignment.center,
                            children: tile.gravestones.map((gs) {
                              final isPlayerCard =
                                  gs.ownerId == match.player.id;
                              final chipColor = isPlayerCard
                                  ? Colors.blue[50]!
                                  : Colors.red[50]!;
                              final borderColor = isPlayerCard
                                  ? Colors.blue[300]!
                                  : Colors.red[300]!;
                              final textColor = isPlayerCard
                                  ? Colors.blue[900]!
                                  : Colors.red[900]!;

                              return GestureDetector(
                                onTap: () => _showCombatLogDialog(gs),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chipColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.sentiment_very_dissatisfied,
                                        size: 10,
                                        color: borderColor,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        gs.cardName,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      // Cards on this tile
                      if (cardsToShow.isEmpty)
                        Text(
                          row == 1 ? 'Middle' : tile.shortName,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        )
                      else if (_useStackedCardUI)
                        // NEW: Stacked card UI
                        Expanded(
                          child: _buildStackedCardsOnTile(
                            cardsToShow,
                            playerCardsAtTile,
                            opponentCardsAtTile,
                            stagedCardsOnTile,
                            row,
                            col,
                            match,
                          ),
                        )
                      else
                        // OLD: ListView UI
                        Expanded(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            children: cardsToShow.map((card) {
                              final isStaged = stagedCardsOnTile.contains(card);
                              final isOpponent = opponentCardsAtTile.contains(
                                card,
                              );
                              final isPlayerCard = playerCardsAtTile.contains(
                                card,
                              );

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
                                    positionLabel = 'TARGET';
                                  }
                                }
                              } else {
                                // Legacy front/back logic
                                if (isOpponent &&
                                    opponentCardsAtTile.isNotEmpty) {
                                  final originalIndex = opponentCardsAtTile
                                      .indexOf(card);
                                  isFrontCard = originalIndex == 0;
                                  if (opponentCardsAtTile.length > 1) {
                                    positionLabel = isFrontCard
                                        ? '▼ FRONT'
                                        : '▲ BACK';
                                  } else {
                                    positionLabel = '▼ FRONT';
                                  }
                                } else if (isPlayerCard &&
                                    playerCardsAtTile.isNotEmpty) {
                                  final idx = playerCardsAtTile.indexOf(card);
                                  isFrontCard = idx == 0;
                                  if (playerCardsAtTile.length > 1) {
                                    positionLabel = isFrontCard
                                        ? '▲ FRONT'
                                        : '▼ BACK';
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
                                  isOpponentBackCard &&
                                  opponentBackCardConcealed;

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
                                  _useTYC3Mode &&
                                  _selectedCardForAction == card;
                              final isValidTarget =
                                  _useTYC3Mode && _validTargets.contains(card);

                              // Visual effect for hero ability damage boost
                              final isDamageBoosted =
                                  isPlayerCard &&
                                  _matchManager.playerDamageBoost > 0;

                              return Builder(
                                builder: (ctx) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!mounted) return;
                                    final rect = _globalRectForContext(ctx);
                                    if (rect == Rect.zero) return;
                                    final key = '${card.id}_$row,$col';
                                    _boardCardRects[key] = rect;
                                  });

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
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 1,
                                          ),
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.yellow[200]!
                                                : isValidTarget
                                                ? Colors.orange[200]!
                                                : cardColor,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            boxShadow: isDamageBoosted
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.red
                                                          .withOpacity(0.6),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                  ]
                                                : null,
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
                                                ? Border.all(
                                                    color: Colors.amber,
                                                    width: 2,
                                                  )
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
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                    const Text(
                                                      '🔮 Hidden',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 3,
                                                              vertical: 1,
                                                            ),
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: labelColor
                                                              .withValues(
                                                                alpha: 0.2,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                3,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          positionLabel,
                                                          style: TextStyle(
                                                            fontSize: 7,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: labelColor,
                                                          ),
                                                        ),
                                                      ),
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        // Show damage as current/max
                                                        _buildStatIconWithMax(
                                                          Icons
                                                              .local_fire_department,
                                                          card.currentDamage +
                                                              (isDamageBoosted
                                                                  ? 1
                                                                  : 0),
                                                          card.damage,
                                                          size: 10,
                                                        ),
                                                        if (isDamageBoosted)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 1,
                                                                ),
                                                            child: Text(
                                                              '(+1)',
                                                              style: const TextStyle(
                                                                fontSize: 8,
                                                                color:
                                                                    Colors.red,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        // Show attack AP cost only if > 1
                                                        if (card.attackAPCost >
                                                            1) ...[
                                                          Text(
                                                            ' (${card.attackAPCost}',
                                                            style: TextStyle(
                                                              fontSize: 8,
                                                              color: Colors
                                                                  .orange[700],
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons.bolt,
                                                            size: 8,
                                                            color: Colors
                                                                .orange[700],
                                                          ),
                                                          Text(
                                                            ')',
                                                            style: TextStyle(
                                                              fontSize: 8,
                                                              color: Colors
                                                                  .orange[700],
                                                            ),
                                                          ),
                                                        ],
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        // Show HP as current/max
                                                        _buildStatIconWithMax(
                                                          Icons.favorite,
                                                          card.currentHealth,
                                                          card.health,
                                                          size: 10,
                                                        ),
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        // TYC3: Show AP (current/max) and attack style icon
                                                        if (_useTYC3Mode) ...[
                                                          _buildStatIconWithMax(
                                                            Icons.bolt,
                                                            card.currentAP,
                                                            card.maxAP,
                                                            size: 10,
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
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
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          _buildStatIcon(
                                                            Icons
                                                                .directions_run,
                                                            card.moveSpeed,
                                                            size: 10,
                                                          ),
                                                        ],
                                                        // Element/Terrain icon
                                                        if (card.element !=
                                                            null) ...[
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  _getTerrainColor(
                                                                    card.element!,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    3,
                                                                  ),
                                                            ),
                                                            child: Icon(
                                                              _getTerrainIcon(
                                                                card.element!,
                                                              ),
                                                              size: 8,
                                                              color:
                                                                  Colors.white,
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
                                            match.currentPhase !=
                                                MatchPhase.combatPhase)
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: GestureDetector(
                                              onTap: () => _removeCardFromTile(
                                                row,
                                                col,
                                                card,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  2,
                                                ),
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
                                },
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===== NEW STACKED CARD UI =====

  /// Build side-by-side card display for a tile (new UI mode)
  Widget _buildStackedCardsOnTile(
    List<GameCard> cardsToShow,
    List<GameCard> playerCardsAtTile,
    List<GameCard> opponentCardsAtTile,
    List<GameCard> stagedCardsOnTile,
    int row,
    int col,
    MatchState match,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth;
        final tileHeight = constraints.maxHeight;

        // Calculate card dimensions - side by side layout (maximize size)
        const scaleFactor = 0.96;
        final cardCount = cardsToShow.length;
        final gap = 4.0;
        final totalGaps = (cardCount > 1) ? (cardCount - 1) * gap : 0;
        final availableWidth = tileWidth - 8; // padding
        final cardWidth = cardCount > 0
            ? (availableWidth - totalGaps) / cardCount
            : availableWidth;
        final cardHeight = min(cardWidth * 1.4, tileHeight - 4) * scaleFactor;
        final actualCardWidth = cardHeight / 1.4;

        return Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(cardsToShow.length, (index) {
              final card = cardsToShow[index];
              final isStaged = stagedCardsOnTile.contains(card);
              final isOpponent = opponentCardsAtTile.contains(card);
              final isPlayerCard = playerCardsAtTile.contains(card);

              // Check states
              final isSelected = _selectedCardForAction == card;
              final isValidTarget = _validTargets.contains(card);

              Widget cardWidget = _buildStackedMiniCard(
                card,
                actualCardWidth,
                cardHeight,
                isPlayerCard: isPlayerCard,
                isOpponent: isOpponent,
                isStaged: isStaged,
                isSelected: isSelected,
                isValidTarget: isValidTarget,
                isTopCard: true,
                row: row,
                col: col,
                match: match,
              );

              // Wrap player cards with Draggable for drag-and-drop targeting
              // If this card is a valid heal target (for medic), also make it targetable
              if (isPlayerCard && !isStaged) {
                if (isValidTarget) {
                  // This is a valid heal target - wrap with both DragTarget and tap handler
                  cardWidget = _buildTargetableCard(
                    card,
                    row,
                    col,
                    cardWidget,
                    isValidTarget,
                  );
                } else {
                  // Normal player card - just draggable
                  cardWidget = _buildDraggableCard(
                    card,
                    row,
                    col,
                    cardWidget,
                    actualCardWidth,
                    cardHeight,
                  );
                }
              }
              // Wrap opponent cards with DragTarget for receiving attacks
              else if (isOpponent) {
                cardWidget = _buildTargetableCard(
                  card,
                  row,
                  col,
                  cardWidget,
                  isValidTarget,
                );
              }
              // Regular gesture detector for staged/other cards
              else {
                cardWidget = GestureDetector(
                  onTap: () =>
                      _onCardTapTYC3(card, row, col, isPlayerCard, isOpponent),
                  onLongPress: () => _showCardDetails(card),
                  child: cardWidget,
                );
              }

              return Padding(
                padding: EdgeInsets.only(
                  right: index < cardsToShow.length - 1 ? gap : 0,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  transform: Matrix4.identity()
                    ..scale(
                      isSelected
                          ? 1.05
                          : isValidTarget
                          ? 1.1
                          : 1.0,
                    )
                    ..translate(
                      0.0,
                      isValidTarget
                          ? -8.0
                          : isSelected
                          ? -4.0
                          : 0.0,
                    ),
                  transformAlignment: Alignment.center,
                  child: cardWidget,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  /// Build a draggable player card for drag-and-drop targeting
  Widget _buildDraggableCard(
    GameCard card,
    int row,
    int col,
    Widget cardWidget,
    double width,
    double height,
  ) {
    return Draggable<GameCard>(
      data: card,
      feedback: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(8),
        child: Transform.scale(
          scale: 1.1,
          child: SizedBox(
            width: width,
            height: height,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue[200],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.yellow, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.yellow.withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  card.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cardWidget),
      onDragStarted: () {
        setState(() {
          _selectedCardForAction = card;
          _selectedCardRow = row;
          _selectedCardCol = col;
          // Calculate valid targets when drag starts
          if (card.currentAP > 0) {
            // Medics get heal targets (friendly units), others get attack targets (enemies)
            if (_isMedic(card)) {
              final healTargets = _matchManager.getReachableHealTargets(
                card,
                row,
                col,
              );
              _validTargets = healTargets.map((t) => t.target).toList();
            } else {
              _validTargets = _matchManager.getValidTargetsTYC3(card, row, col);
            }
          } else {
            _validTargets = [];
          }
        });
      },
      onDragEnd: (details) {
        // Keep selection if dropped on valid target, otherwise clear after delay
        if (!details.wasAccepted) {
          // Don't clear immediately - let tap handle it
        }
      },
      child: Builder(
        builder: (ctx) {
          void selectBoardCard() =>
              _selectCardForActionNoToggle(card, row, col);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final rect = _globalRectForContext(ctx);
            if (rect == Rect.zero) return;
            final terrain = _matchManager.currentMatch?.board
                .getTile(row, col)
                .terrain;
            final key = '${card.id}_$row,$col';
            _boardCardRects[key] = rect;
            _boardCardTargets[key] = _CardFocusSwitchTarget(
              card: card,
              tileTerrain: terrain,
              onSecondTapAction: selectBoardCard,
              onDismissed: selectBoardCard,
            );
          });

          return GestureDetector(
            onTap: () {
              final isSelectedForAction = _selectedCardForAction == card;
              if (!isSelectedForAction) {
                _selectCardForActionNoToggle(card, row, col);
                return;
              }

              final rect = _globalRectForContext(ctx);
              final terrain = _matchManager.currentMatch?.board
                  .getTile(row, col)
                  .terrain;
              _showCardFocus(
                card,
                rect,
                tileTerrain: terrain,
                onSecondTapAction: selectBoardCard,
                onDismissed: selectBoardCard,
                switchRects: _boardCardRects,
                switchTargets: _boardCardTargets,
              );
            },
            child: cardWidget,
          );
        },
      ),
    );
  }

  /// Build a targetable enemy card that can receive drag-and-drop attacks
  Widget _buildTargetableCard(
    GameCard card,
    int row,
    int col,
    Widget cardWidget,
    bool isValidTarget,
  ) {
    return DragTarget<GameCard>(
      onWillAcceptWithDetails: (details) {
        // Only accept if this card is a valid target for the dragged card
        return _validTargets.contains(card);
      },
      onAcceptWithDetails: (details) {
        // Show attack/heal preview dialog when dropped on valid target
        final attackerCard = details.data;
        if (_selectedCardForAction == attackerCard &&
            _validTargets.contains(card)) {
          // Medics heal friendly units, others attack enemies
          if (_isMedic(attackerCard)) {
            _healTargetTYC3(card, row, col);
          } else {
            _attackTargetTYC3(card, row, col);
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isBeingDraggedOver =
            candidateData.isNotEmpty && _validTargets.contains(card);

        return Builder(
          builder: (ctx) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final rect = _globalRectForContext(ctx);
              if (rect == Rect.zero) return;
              final key = '${card.id}_$row,$col';
              _boardCardRects[key] = rect;
            });

            return GestureDetector(
              onTap: () => _onCardTapTYC3(card, row, col, false, true),
              onLongPress: () {
                final rect = _globalRectForContext(ctx);
                final terrain = _matchManager.currentMatch?.board
                    .getTile(row, col)
                    .terrain;
                _showCardFocus(card, rect, tileTerrain: terrain);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                transform: Matrix4.identity()
                  ..scale(isBeingDraggedOver ? 1.15 : 1.0)
                  ..translate(0.0, isBeingDraggedOver ? -10.0 : 0.0),
                transformAlignment: Alignment.center,
                decoration: isBeingDraggedOver
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.7),
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        ],
                      )
                    : null,
                child: cardWidget,
              ),
            );
          },
        );
      },
    );
  }

  /// Build a mini card widget for stacked display (new UI mode)
  Widget _buildStackedMiniCard(
    GameCard card,
    double width,
    double height, {
    required bool isPlayerCard,
    required bool isOpponent,
    required bool isStaged,
    required bool isSelected,
    required bool isValidTarget,
    required bool isTopCard,
    required int row,
    required int col,
    required MatchState match,
  }) {
    // Determine card colors - vibrant gradients
    Color gradientStart;
    Color gradientEnd;
    if (isStaged) {
      gradientStart = Colors.amber[100]!;
      gradientEnd = Colors.amber[300]!;
    } else if (isOpponent) {
      gradientStart = Colors.red[50]!;
      gradientEnd = Colors.red[200]!;
    } else {
      gradientStart = Colors.blue[50]!;
      gradientEnd = Colors.blue[200]!;
    }

    // Border color based on state
    Color borderColor;
    double borderWidth;
    if (isSelected) {
      borderColor = Colors.yellow[600]!;
      borderWidth = 3;
    } else if (isValidTarget) {
      borderColor = Colors.orange[600]!;
      borderWidth = 3;
    } else {
      borderColor = _getRarityBorderColor(card);
      borderWidth = isTopCard ? 2 : 1;
    }

    // Shadow/glow for selected/targeted
    List<BoxShadow> shadows = [];
    if (isSelected) {
      shadows.add(
        BoxShadow(
          color: Colors.yellow.withOpacity(0.6),
          blurRadius: 10,
          spreadRadius: 2,
        ),
      );
    } else if (isValidTarget) {
      shadows.add(
        BoxShadow(
          color: Colors.orange.withOpacity(0.6),
          blurRadius: 12,
          spreadRadius: 3,
        ),
      );
    } else {
      shadows.add(
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 4,
          offset: const Offset(1, 2),
        ),
      );
    }

    // Infer type icon
    final IconData typeIcon = _getAttackStyleIcon(_getAttackStyle(card));

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSelected
              ? [Colors.yellow[100]!, Colors.yellow[300]!]
              : isValidTarget
              ? [Colors.orange[100]!, Colors.orange[300]!]
              : [gradientStart, gradientEnd],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadows,
      ),
      child: Stack(
        children: [
          // 1. Element (Tile Affinity) - Top Right
          if (card.element != null)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getTerrainIcon(card.element!),
                  size: width * 0.15,
                  color: _getTerrainColor(card.element!),
                ),
              ),
            ),

          // 2. Name and Type - Top Left
          Positioned(
            top: 2,
            left: 2,
            right: width * 0.25,
            child: Row(
              children: [
                Icon(typeIcon, size: width * 0.15, color: Colors.black87),
                const SizedBox(width: 1),
                Expanded(
                  child: Text(
                    card.name,
                    style: TextStyle(
                      fontSize: width * 0.10,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                      color: isOpponent ? Colors.red[900] : Colors.blue[900],
                    ),
                    maxLines: 1, // Single line
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // 3. Stats Column - Left Side (Ability Icons -> AP -> Damage -> HP)
          Positioned(
            left: 1,
            bottom: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ability Icons (Moved to left bar)
                if (card.abilities.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: card.abilities
                          .where(
                            (a) => ![
                              'cavalry',
                              'pikeman',
                              'shield_guard',
                            ].contains(a),
                          )
                          .take(2) // Limit to 2 for mini cards
                          .map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 0.5),
                              child: Icon(
                                _abilityIconData(a),
                                size: width * 0.12,
                                color: Colors.black87,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),

                // AP
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt,
                      size: width * 0.12,
                      color: Colors.blue[800],
                    ),
                    Text(
                      '${card.currentAP}', // Show current AP for board units
                      style: TextStyle(
                        fontSize: width * 0.10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Damage
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      size: width * 0.12,
                      color: Colors.deepOrange,
                    ),
                    Text(
                      '${card.currentDamage}', // Show current damage
                      style: TextStyle(
                        fontSize: width * 0.10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // HP
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite,
                      size: width * 0.12,
                      color: Colors.red[700],
                    ),
                    Text(
                      '${card.currentHealth}',
                      style: TextStyle(
                        fontSize: width * 0.10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Decoy Indicator
          if (card.isDecoy && isPlayerCard)
            Positioned(
              top: height * 0.4,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.purple.withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: const Text(
                  'DECOY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBattleLogDrawer() {
    final log = _isReplayMode && _currentReplaySnapshot != null
        ? _currentReplaySnapshot!.logs
        : _matchManager.getCombatLog();

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
    final match = _matchManager.currentMatch;
    final canPlayMoreCardsThisTurn =
        match != null && match.isPlayerTurn && match.canPlaceMoreCards;

    // Calculate available cards (not yet staged)
    final stagedCardSet = _stagedCards.values.expand((list) => list).toSet();
    final availableCards = (player.hand as List<GameCard>)
        .where((card) => !stagedCardSet.contains(card))
        .toList();

    if (_useStackedCardUI) {
      return Container(
        height: 160,
        color: Colors.brown[200],
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    canPlayMoreCardsThisTurn
                        ? 'Your Hand (${availableCards.length}) - Tap to select, drag to place'
                        : 'Your Hand (${availableCards.length}) - No card plays left this turn',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: canPlayMoreCardsThisTurn
                          ? Colors.brown[800]
                          : Colors.grey[700],
                    ),
                  ),
                ),
                Expanded(
                  child: availableCards.isEmpty
                      ? Center(
                          child: Text(
                            'No cards in hand',
                            style: TextStyle(color: Colors.brown[600]),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final availableHeight = constraints.maxHeight;
                            final cardHeight = availableHeight * 0.85;
                            final cardWidth = cardHeight / 1.4;
                            final overlapWidth =
                                cardWidth * (1 - _handCardOverlap);
                            final totalCardsWidth =
                                cardWidth +
                                (availableCards.length - 1) * overlapWidth;
                            final totalAngle =
                                _handFanAngle * (availableCards.length - 1);
                            final startAngle = -totalAngle / 2;

                            final idsInHand = availableCards
                                .map((c) => c.id)
                                .toSet();
                            _handCardRects.removeWhere(
                              (id, _) => !idsInHand.contains(id),
                            );
                            _handCardTargets.removeWhere(
                              (id, _) => !idsInHand.contains(id),
                            );

                            // 1. Generate all card widgets with their positions
                            final cardWidgets = List<Widget>.generate(
                              availableCards.length,
                              (index) {
                                final card = availableCards[index];
                                final isSelected = _selectedCard == card;
                                final centerIndex =
                                    (availableCards.length - 1) / 2;
                                final offsetFromCenter = index - centerIndex;
                                final xOffset = offsetFromCenter * overlapWidth;

                                // Reset angle if selected for better readability
                                final angle =
                                    (availableCards.length > 1 && !isSelected)
                                    ? (startAngle + index * _handFanAngle) *
                                          (pi / 180)
                                    : 0.0;

                                final distanceFromCenter = offsetFromCenter
                                    .abs();
                                final yOffset =
                                    distanceFromCenter * distanceFromCenter * 3;

                                return Positioned(
                                  key: ValueKey(
                                    '${card.id}_$index',
                                  ), // Stable key
                                  left:
                                      (totalCardsWidth + 40) / 2 -
                                      cardWidth / 2 +
                                      xOffset,
                                  top: yOffset + 5,
                                  child: Transform(
                                    transform: Matrix4.identity()
                                      ..rotateZ(angle),
                                    alignment: Alignment.bottomCenter,
                                    child: _buildDraggableHandCard(
                                      card,
                                      cardWidth,
                                      cardHeight,
                                      isSelected,
                                      enabled: canPlayMoreCardsThisTurn,
                                    ),
                                  ),
                                );
                              },
                            );

                            if (_selectedCard != null) {
                              final selectedIndex = availableCards.indexOf(
                                _selectedCard!,
                              );
                              if (selectedIndex != -1 &&
                                  selectedIndex < cardWidgets.length) {
                                final selectedWidget = cardWidgets.removeAt(
                                  selectedIndex,
                                );
                                cardWidgets.add(selectedWidget);
                              }
                            }

                            return Center(
                              child: SizedBox(
                                width: totalCardsWidth + 40,
                                height: availableHeight,
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: cardWidgets,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            if (_useChessTimer && _matchManager.currentMatch != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: _buildChessClockItem(
                  label: 'YOU',
                  seconds: _matchManager.currentMatch!.playerTotalTimeRemaining,
                  isActive: _matchManager.isPlayerTurn,
                  isCritical:
                      _matchManager.currentMatch!.playerTotalTimeRemaining <=
                      30,
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      height: 140,
      padding: const EdgeInsets.all(8),
      color: Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            canPlayMoreCardsThisTurn
                ? 'Your Hand (${availableCards.length} cards)'
                : 'Your Hand (${availableCards.length} cards) - No card plays left this turn',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: canPlayMoreCardsThisTurn ? Colors.black : Colors.grey[700],
            ),
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
                        onTap: canPlayMoreCardsThisTurn
                            ? () {
                                setState(() {
                                  // Clear board card selection when selecting hand card
                                  _clearTYC3Selection();
                                  _selectedCard = isSelected ? null : card;
                                });
                              }
                            : null,
                        onLongPress: () => _showCardDetails(card),
                        child: Opacity(
                          opacity: canPlayMoreCardsThisTurn ? 1.0 : 0.35,
                          child: Container(
                            width: 90,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: baseFill,
                              border: Border.all(
                                color: isSelected ? Colors.green : baseBorder,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
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
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey[100],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Board Cards',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              const Text('Overlap:', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: _cardOverlapRatio,
                  min: 0.2,
                  max: 0.9,
                  onChanged: (v) => setState(() => _cardOverlapRatio = v),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Spread:', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: _cardSeparation,
                  min: 0,
                  max: 30,
                  onChanged: (v) => setState(() => _cardSeparation = v),
                ),
              ),
            ],
          ),
          const Text(
            'Hand Cards',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              const Text('Fan:', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: _handFanAngle,
                  min: 0,
                  max: 20,
                  onChanged: (v) => setState(() => _handFanAngle = v),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Overlap:', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: _handCardOverlap,
                  min: 0.2,
                  max: 0.8,
                  onChanged: (v) => setState(() => _handCardOverlap = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the visual representation of a hand card (no interaction)
  Widget _buildHandCardVisual(
    GameCard card,
    double width,
    double height,
    bool isSelected, {
    bool showDetails = false,
    String? tileTerrain,
  }) {
    final baseFill = _getRarityFillColor(card);
    final baseBorder = _getRarityBorderColor(card);

    // Infer type icon
    final IconData typeIcon = _getAttackStyleIcon(_getAttackStyle(card));

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.green : baseBorder,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          if (isSelected)
            BoxShadow(
              color: Colors.green.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            )
          else
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(1, 2),
            ),
        ],
      ),
      child: Stack(
        children: [
          // 1. Element (Tile Affinity) - Top Right
          if (card.element != null)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getTerrainIcon(card.element!),
                  size: width * 0.15,
                  color: _getTerrainColor(card.element!),
                ),
              ),
            ),

          // 2. Name and Type - Top Left
          Positioned(
            top: 4,
            left: 4,
            right: width * 0.25, // Make room for element
            child: Row(
              children: [
                if (!showDetails)
                  Icon(typeIcon, size: width * 0.15, color: Colors.black87),
                if (!showDetails) const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    card.name,
                    style: TextStyle(
                      fontSize: width * 0.11,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                    maxLines: 1, // Single line
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // 3. Stats Column - Left Side (Ability Icons -> AP -> Damage -> HP)
          if (!showDetails)
            Positioned(
              left: 2,
              bottom: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ability Icons (Moved to left bar)
                  if (card.abilities.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: card.abilities
                            .where(
                              (a) => ![
                                'cavalry',
                                'pikeman',
                                'shield_guard',
                              ].contains(a),
                            )
                            .take(3)
                            .map(
                              (a) => Padding(
                                padding: const EdgeInsets.only(bottom: 1),
                                child: Icon(
                                  _abilityIconData(a),
                                  size: width * 0.14,
                                  color: Colors.black87,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  // AP (Top of stack)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt,
                        size: width * 0.12,
                        color: Colors.blue[800],
                      ),
                      Text(
                        '${card.maxAP}',
                        style: TextStyle(
                          fontSize: width * 0.11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  // Damage
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: width * 0.12,
                        color: Colors.deepOrange,
                      ),
                      Text(
                        '${card.damage}',
                        style: TextStyle(
                          fontSize: width * 0.11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  // HP (Bottom of stack)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite,
                        size: width * 0.12,
                        color: Colors.red[700],
                      ),
                      Text(
                        '${card.health}',
                        style: TextStyle(
                          fontSize: width * 0.11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Decoy Indicator (Overlay)
          if (card.isDecoy)
            Positioned(
              top: height * 0.4,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.purple.withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: const Text(
                  'DECOY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),

          // Full details panel when focused
          if (showDetails)
            Positioned(
              top: height * 0.18,
              left: 4,
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: (width * 0.065).clamp(11.0, 14.0),
                      color: Colors.black87,
                      height: 1.15,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Attack style
                        Row(
                          children: [
                            Icon(typeIcon, size: 14, color: Colors.black87),
                            const SizedBox(width: 4),
                            Text(
                              _getAttackStyle(card).toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Stats row
                        Row(
                          children: [
                            Icon(Icons.bolt, size: 12, color: Colors.blue[800]),
                            Text(' ${card.currentAP}/${card.maxAP}'),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.local_fire_department,
                              size: 12,
                              color: Colors.deepOrange,
                            ),
                            Text(' ${card.currentDamage}/${card.damage}'),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.favorite,
                              size: 12,
                              color: Colors.red[700],
                            ),
                            Text(' ${card.currentHealth}/${card.health}'),
                          ],
                        ),
                        // Terrain affinity
                        if (card.element != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _getTerrainIcon(card.element!),
                                size: 12,
                                color: _getTerrainColor(card.element!),
                              ),
                              const SizedBox(width: 4),
                              Text('Terrain: ${card.element}'),
                            ],
                          ),
                        ],
                        // Tile terrain (if on board)
                        if (tileTerrain != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'On: $tileTerrain',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 10,
                            ),
                          ),
                        ],
                        // Abilities
                        if (card.abilities.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Abilities:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ...card.abilities.map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _abilityIconData(a),
                                    size: 12,
                                    color: Colors.black54,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '$a: ${_abilityDescription(a)}',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build a draggable hand card wrapper
  Widget _buildDraggableHandCard(
    GameCard card,
    double width,
    double height,
    bool isSelected, {
    required bool enabled,
  }) {
    final cardWidget = _buildHandCardVisual(card, width, height, isSelected);

    if (!enabled) {
      return GestureDetector(
        onLongPress: () => _showCardDetails(card),
        child: Opacity(opacity: 0.35, child: cardWidget),
      );
    }

    return Draggable<GameCard>(
      data: card,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Transform.scale(scale: 1.1, child: cardWidget),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cardWidget),
      onDragStarted: () {
        setState(() {
          _clearTYC3Selection();
          _selectedCard = card;
        });
      },
      child: Builder(
        builder: (ctx) {
          void selectCard() {
            setState(() {
              _clearTYC3Selection();
              _selectedCard = card;
            });
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final rect = _globalRectForContext(ctx);
            if (rect == Rect.zero) return;
            _handCardRects[card.id] = rect;
            _handCardTargets[card.id] = _CardFocusSwitchTarget(
              card: card,
              onSecondTapAction: selectCard,
              onDismissed: selectCard,
            );
          });

          return GestureDetector(
            onTap: () {
              final isSelected = _selectedCard == card;
              if (!isSelected) {
                selectCard();
                return;
              }

              final rect = _globalRectForContext(ctx);
              _showCardFocus(
                card,
                rect,
                onSecondTapAction: selectCard,
                onDismissed: selectCard,
                switchRects: _handCardRects,
                switchTargets: _handCardTargets,
              );
            },
            child: cardWidget,
          );
        },
      ),
    );
  }
}

class _AttackArrowPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double t;

  _AttackArrowPainter({required this.from, required this.to, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final clampedT = t.clamp(0.0, 1.0);
    final end = Offset.lerp(from, to, clampedT)!;

    final paint = Paint()
      ..color = Colors.red.withOpacity(0.9)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(from, end, paint);

    final dir = (end - from);
    final len = dir.distance;
    if (len <= 0.01) return;

    final angle = atan2(dir.dy, dir.dx);
    const headLen = 14.0;
    const headAngle = 0.55;

    final p1 =
        end +
        Offset(cos(angle + pi - headAngle), sin(angle + pi - headAngle)) *
            headLen;
    final p2 =
        end +
        Offset(cos(angle + pi + headAngle), sin(angle + pi + headAngle)) *
            headLen;

    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant _AttackArrowPainter oldDelegate) {
    return oldDelegate.from != from ||
        oldDelegate.to != to ||
        oldDelegate.t != t;
  }
}
