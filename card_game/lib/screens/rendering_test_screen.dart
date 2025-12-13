import 'dart:math';
import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/card.dart';
import '../models/hero.dart';
import '../models/tile.dart';
import '../data/hero_library.dart';
import '../services/match_manager.dart';
import '../services/simple_ai.dart';
import 'main_menu_screen.dart';

/// Rendering Test Screen - Visual asset testing mode
/// Features:
/// - Poker-style fanned card hand
/// - Full drag-and-drop functionality
/// - Rich visual assets (gradients, patterns, effects)
/// - All game interactions working
class RenderingTestScreen extends StatefulWidget {
  final GameHero? selectedHero;

  const RenderingTestScreen({super.key, this.selectedHero});

  @override
  State<RenderingTestScreen> createState() => _RenderingTestScreenState();
}

class _RenderingTestScreenState extends State<RenderingTestScreen> {
  final MatchManager _matchManager = MatchManager();
  final SimpleAI _ai = SimpleAI();

  // Hand card selection
  GameCard? _selectedCard;
  GameCard? _draggedCard;

  // Board card selection (for move/attack)
  GameCard? _selectedBoardCard;
  int? _selectedBoardRow;
  int? _selectedBoardCol;
  List<GameCard> _validTargets = [];

  // Hand UI settings
  final double _handFanAngle = 8.0;
  final double _handCardOverlap = 0.45;

  @override
  void initState() {
    super.initState();
    _initMatch();
  }

  Future<void> _initMatch() async {
    final hero = widget.selectedHero ?? HeroLibrary.napoleon();
    final deck = Deck.starter(playerId: 'render_player');

    _matchManager.startMatch(
      playerId: 'render_player',
      playerName: 'Player',
      playerDeck: deck,
      opponentId: 'render_ai',
      opponentName: 'AI Opponent',
      opponentDeck: Deck.starter(playerId: 'render_ai'),
      playerHero: hero,
      opponentHero: HeroLibrary.saladin(),
    );

    setState(() {});
  }

  void _startNewMatch() {
    _selectedCard = null;
    _draggedCard = null;
    _clearBoardSelection();
    _initMatch();
  }

  void _clearBoardSelection() {
    _selectedBoardCard = null;
    _selectedBoardRow = null;
    _selectedBoardCol = null;
    _validTargets = [];
  }

  void _endTurnTYC3() {
    _matchManager.endTurnTYC3();
    _clearBoardSelection();
    _selectedCard = null;

    // AI turn
    if (!_matchManager.currentMatch!.isGameOver) {
      _ai.executeTurnTYC3(_matchManager);
    }

    setState(() {});
  }

  // ===== CARD PLACEMENT =====

  void _placeCardOnTile(int row, int col) {
    if (_selectedCard == null) return;

    final success = _matchManager.placeCardTYC3(_selectedCard!, row, col);
    if (success) {
      setState(() {
        _selectedCard = null;
      });
    }
  }

  void _onTileTap(
    int row,
    int col,
    bool canPlace,
    bool canMoveTo,
    bool canAttackBase,
  ) {
    if (canPlace && _selectedCard != null) {
      _placeCardOnTile(row, col);
    } else if (canMoveTo && _selectedBoardCard != null) {
      _moveCardTYC3(row, col);
    } else if (canAttackBase && _selectedBoardCard != null) {
      _attackBaseTYC3(col);
    }
  }

  // ===== CARD MOVEMENT =====

  void _moveCardTYC3(int targetRow, int targetCol) {
    if (_selectedBoardCard == null ||
        _selectedBoardRow == null ||
        _selectedBoardCol == null)
      return;

    final success = _matchManager.moveCardTYC3(
      _selectedBoardCard!,
      _selectedBoardRow!,
      _selectedBoardCol!,
      targetRow,
      targetCol,
    );

    if (success) {
      setState(() {
        _selectedBoardRow = targetRow;
        _selectedBoardCol = targetCol;
        _validTargets = _matchManager.getValidTargetsTYC3(
          _selectedBoardCard!,
          targetRow,
          targetCol,
        );
      });
    }
  }

  void _attackBaseTYC3(int col) {
    if (_selectedBoardCard == null) return;

    final damage = _matchManager.attackBaseTYC3(
      _selectedBoardCard!,
      _selectedBoardRow!,
      _selectedBoardCol!,
    );

    if (damage > 0) {
      _clearBoardSelection();
      setState(() {});
    }
  }

  // ===== CARD INTERACTIONS =====

  void _onHandCardTap(GameCard card) {
    setState(() {
      if (_selectedCard == card) {
        _selectedCard = null;
      } else {
        _selectedCard = card;
        _clearBoardSelection();
      }
    });
  }

  void _onBoardCardTap(
    GameCard card,
    int row,
    int col,
    bool isPlayerCard,
    bool isOpponent,
  ) {
    final match = _matchManager.currentMatch;
    if (match == null) return;

    if (isPlayerCard && _matchManager.isPlayerTurn) {
      if (_selectedBoardCard == card) {
        _clearBoardSelection();
      } else {
        _selectedBoardCard = card;
        _selectedBoardRow = row;
        _selectedBoardCol = col;
        _validTargets = _matchManager.getValidTargetsTYC3(card, row, col);
        _selectedCard = null;
      }
      setState(() {});
    } else if (isOpponent && _validTargets.contains(card)) {
      _attackCardTYC3(card, row, col);
    }
  }

  void _attackCardTYC3(GameCard target, int targetRow, int targetCol) {
    if (_selectedBoardCard == null) return;

    final result = _matchManager.attackCardTYC3(
      _selectedBoardCard!,
      target,
      _selectedBoardRow!,
      _selectedBoardCol!,
      targetRow,
      targetCol,
    );

    if (result != null) {
      _showBattleResultDialog(result);
      _clearBoardSelection();
      setState(() {});
    }
  }

  void _showBattleResultDialog(dynamic result) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.orange, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.flash_on, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Battle!', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Attack dealt damage!\nTarget ${result.targetDied == true ? "was destroyed!" : "survived"}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _showCardDetails(GameCard card) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _getRarityColor(card.rarity), width: 2),
        ),
        title: Text(
          card.name,
          style: TextStyle(color: _getRarityColor(card.rarity)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              'Damage',
              '${card.currentDamage}/${card.damage}',
              Icons.local_fire_department,
              Colors.orange,
            ),
            _buildDetailRow(
              'Health',
              '${card.currentHealth}/${card.health}',
              Icons.favorite,
              Colors.red,
            ),
            _buildDetailRow(
              'AP',
              '${card.currentAP}/${card.maxAP}',
              Icons.bolt,
              Colors.yellow,
            ),
            if (card.element != null)
              _buildDetailRow(
                'Terrain',
                card.element!,
                _getTerrainIcon(card.element!),
                _getTerrainColor(card.element!),
              ),
            if (card.abilities.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Abilities:',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...card.abilities.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '• $a',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===== BUILD METHODS =====

  @override
  Widget build(BuildContext context) {
    final match = _matchManager.currentMatch;

    if (match == null) {
      return Scaffold(
        body: Container(
          decoration: _buildBackgroundDecoration(),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.amber),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: _buildBackgroundDecoration(),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(match),
              Expanded(
                child: match.isGameOver
                    ? _buildGameOver(match)
                    : _buildMatchView(match),
              ),
              if (!match.isGameOver) _buildPokerHand(match.player),
            ],
          ),
        ),
      ),
      floatingActionButton: match.isGameOver ? null : _buildActionButton(match),
    );
  }

  BoxDecoration _buildBackgroundDecoration() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1a1a2e),
          Color(0xFF16213e),
          Color(0xFF0f3460),
          Color(0xFF1a1a2e),
        ],
        stops: [0.0, 0.3, 0.7, 1.0],
      ),
    );
  }

  Widget _buildTopBar(MatchState match) {
    final isMyTurn = _matchManager.isPlayerTurn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.brown[900]!.withOpacity(0.9),
            Colors.brown[800]!.withOpacity(0.9),
          ],
        ),
        border: Border(bottom: BorderSide(color: Colors.amber[700]!, width: 2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainMenuScreen()),
              (route) => false,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isMyTurn
                    ? [Colors.green[700]!, Colors.green[500]!]
                    : [Colors.red[700]!, Colors.red[500]!],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber, width: 1),
            ),
            child: Text(
              isMyTurn ? 'YOUR TURN' : 'ENEMY TURN',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber[700]!, width: 1),
            ),
            child: Text(
              'Turn ${match.turnNumber}',
              style: const TextStyle(color: Colors.amber, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchView(MatchState match) {
    return Column(
      children: [
        _buildPlayerInfoBar(match.opponent, isOpponent: true),
        Expanded(child: _buildBoard(match)),
        _buildPlayerInfoBar(match.player, isOpponent: false),
      ],
    );
  }

  Widget _buildPlayerInfoBar(player, {required bool isOpponent}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOpponent
              ? [
                  Colors.red[900]!.withOpacity(0.8),
                  Colors.red[800]!.withOpacity(0.8),
                ]
              : [
                  Colors.blue[900]!.withOpacity(0.8),
                  Colors.blue[800]!.withOpacity(0.8),
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOpponent ? Colors.red[400]! : Colors.blue[400]!,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOpponent ? Colors.red : Colors.blue).withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          _buildAvatarFrame(isOpponent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (player.hero != null)
                  Text(
                    player.hero!.name,
                    style: TextStyle(color: Colors.amber[300], fontSize: 12),
                  ),
              ],
            ),
          ),
          _buildCrystalHP(player.crystalHP, isOpponent),
        ],
      ),
    );
  }

  Widget _buildAvatarFrame(bool isOpponent) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: isOpponent
              ? [Colors.red[400]!, Colors.red[900]!]
              : [Colors.blue[400]!, Colors.blue[900]!],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.amber, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 8),
        ],
      ),
      child: Icon(
        isOpponent ? Icons.smart_toy : Icons.person,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildCrystalHP(int hp, bool isOpponent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[900]!, Colors.purple[700]!],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple[300]!, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Colors.cyan[300]!, Colors.purple[700]!],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.diamond, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 6),
          Text(
            '$hp',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(MatchState match) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[800]!, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Map background image
            Positioned.fill(
              child: Image.asset(
                'assets/image/mapBoard.webp',
                fit: BoxFit.cover,
              ),
            ),
            // Semi-transparent overlay for better tile visibility
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
            // Board content
            Column(
              children: [
                _buildRowLabel('ENEMY BASE', Colors.red),
                Expanded(child: _buildBoardRow(match, 0)),
                _buildRowLabel('BATTLEFIELD', Colors.grey),
                Expanded(child: _buildBoardRow(match, 1)),
                _buildRowLabel('YOUR BASE', Colors.blue),
                Expanded(child: _buildBoardRow(match, 2)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowLabel(String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.0),
            color.withOpacity(0.3),
            color.withOpacity(0.0),
          ],
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildBoardRow(MatchState match, int row) {
    return Row(
      children: [
        for (int col = 0; col < 3; col++)
          Expanded(child: _buildTile(match, row, col)),
      ],
    );
  }

  Widget _buildTile(MatchState match, int row, int col) {
    final tile = match.getTile(row, col);
    final playerId = match.player.id;

    final tileCards = tile.cards.where((c) => c.isAlive).toList();
    final playerCards = tileCards.where((c) => c.ownerId == playerId).toList();
    final opponentCards = tileCards
        .where((c) => c.ownerId != playerId)
        .toList();

    final isPlayerBase = row == 2;
    final isMiddleRow = row == 1;
    final selectedCardCanPlaceMiddle =
        _selectedCard != null && _selectedCard!.maxAP >= 2;
    final hasEnemyOnMiddle = isMiddleRow && opponentCards.isNotEmpty;

    final canPlace =
        _selectedCard != null &&
        row != 0 &&
        playerCards.length < Tile.maxCards &&
        (isPlayerBase ||
            (isMiddleRow && selectedCardCanPlaceMiddle && !hasEnemyOnMiddle));

    bool canMoveTo = false;
    bool canAttackBase = false;
    if (_selectedBoardCard != null &&
        _selectedBoardRow != null &&
        _selectedBoardCol != null) {
      final reachableTiles = _matchManager.getReachableTiles(
        _selectedBoardCard!,
        _selectedBoardRow!,
        _selectedBoardCol!,
      );
      canMoveTo = reachableTiles.any((t) => t.row == row && t.col == col);

      if (row == 0 && col == _selectedBoardCol) {
        final baseTile = match.board.getTile(0, col);
        final hasEnemyCards = baseTile.cards.any(
          (c) => c.isAlive && c.ownerId != playerId,
        );
        if (!hasEnemyCards) canAttackBase = true;
      }
    }

    return DragTarget<GameCard>(
      onWillAcceptWithDetails: (details) {
        final card = details.data;
        final isFromHand = match.player.hand.contains(card);
        if (isFromHand) {
          return canPlace || (row != 0 && playerCards.length < Tile.maxCards);
        }
        return card.ownerId == playerId && canMoveTo;
      },
      onAcceptWithDetails: (details) {
        final card = details.data;
        final isFromHand = match.player.hand.contains(card);
        if (isFromHand) {
          setState(() => _selectedCard = card);
          _placeCardOnTile(row, col);
        } else {
          _moveCardTYC3(row, col);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;

        return GestureDetector(
          onTap: () => _onTileTap(row, col, canPlace, canMoveTo, canAttackBase),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: _buildTileDecoration(
              tile,
              row,
              canPlace,
              canMoveTo,
              canAttackBase,
              isHighlighted,
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _buildTerrainBackground(tile.terrain)),
                Column(
                  children: [
                    if (tile.terrain != null) _buildTerrainBadge(tile.terrain!),
                    Expanded(
                      child: _buildCardsOnTile(
                        playerCards,
                        opponentCards,
                        row,
                        col,
                        match,
                      ),
                    ),
                  ],
                ),
                if (canPlace) _buildHighlightOverlay(Colors.green, 'PLACE'),
                if (canMoveTo) _buildHighlightOverlay(Colors.purple, 'MOVE'),
                if (canAttackBase)
                  _buildHighlightOverlay(Colors.orange, 'ATTACK BASE'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHighlightOverlay(Color color, String label) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildTileDecoration(
    Tile tile,
    int row,
    bool canPlace,
    bool canMoveTo,
    bool canAttackBase,
    bool isHighlighted,
  ) {
    Color borderColor;
    double borderWidth = 1;

    if (isHighlighted) {
      borderColor = Colors.green;
      borderWidth = 3;
    } else if (canAttackBase) {
      borderColor = Colors.orange;
      borderWidth = 3;
    } else if (canMoveTo) {
      borderColor = Colors.purple;
      borderWidth = 2;
    } else if (canPlace) {
      borderColor = Colors.green;
      borderWidth = 2;
    } else if (row == 0) {
      borderColor = Colors.red[700]!;
    } else if (row == 2) {
      borderColor = Colors.blue[700]!;
    } else {
      borderColor = Colors.grey[600]!;
    }

    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 4,
          offset: const Offset(2, 2),
        ),
      ],
    );
  }

  Widget _buildTerrainBackground(String? terrain) {
    // Use stone tile image for all tiles
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/image/stone tile.webp', fit: BoxFit.cover),
            // Add terrain color overlay if terrain exists
            if (terrain != null)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _getTerrainGradientColors(terrain),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Color> _getTerrainGradientColors(String terrain) {
    switch (terrain.toLowerCase()) {
      case 'woods':
        return [
          Colors.green[900]!.withOpacity(0.7),
          Colors.green[700]!.withOpacity(0.5),
        ];
      case 'lake':
        return [
          Colors.blue[900]!.withOpacity(0.7),
          Colors.blue[600]!.withOpacity(0.5),
        ];
      case 'desert':
        return [
          Colors.orange[900]!.withOpacity(0.7),
          Colors.yellow[700]!.withOpacity(0.5),
        ];
      case 'marsh':
        return [
          Colors.teal[900]!.withOpacity(0.7),
          Colors.teal[600]!.withOpacity(0.5),
        ];
      default:
        return [
          Colors.grey[800]!.withOpacity(0.5),
          Colors.grey[600]!.withOpacity(0.5),
        ];
    }
  }

  Widget _buildTerrainBadge(String terrain) {
    final icon = _getTerrainIcon(terrain);
    final color = _getTerrainColor(terrain);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            terrain.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
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

  Widget _buildCardsOnTile(
    List<GameCard> playerCards,
    List<GameCard> opponentCards,
    int row,
    int col,
    MatchState match,
  ) {
    final allCards = [...opponentCards.reversed, ...playerCards];

    if (allCards.isEmpty) {
      return Center(
        child: Text(
          row == 1 ? 'Middle' : (row == 0 ? 'Enemy' : 'Base'),
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 8) / max(allCards.length, 1);
        final cardHeight = min(cardWidth * 1.4, constraints.maxHeight - 20);

        return Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: allCards.map((card) {
              final isPlayer = card.ownerId == match.player.id;
              final isSelected = _selectedBoardCard == card;
              final isValidTarget = _validTargets.contains(card);

              Widget cardWidget = _buildRenderedCard(
                card,
                cardWidth.clamp(40.0, 80.0),
                cardHeight.clamp(56.0, 112.0),
                isPlayer: isPlayer,
                isSelected: isSelected,
                isValidTarget: isValidTarget,
              );

              if (isPlayer) {
                cardWidget = Draggable<GameCard>(
                  data: card,
                  feedback: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(8),
                    child: Transform.scale(
                      scale: 1.1,
                      child: _buildRenderedCard(
                        card,
                        cardWidth.clamp(40.0, 80.0),
                        cardHeight.clamp(56.0, 112.0),
                        isPlayer: true,
                        isSelected: true,
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.3, child: cardWidget),
                  onDragStarted: () {
                    setState(() {
                      _selectedBoardCard = card;
                      _selectedBoardRow = row;
                      _selectedBoardCol = col;
                      _validTargets = _matchManager.getValidTargetsTYC3(
                        card,
                        row,
                        col,
                      );
                    });
                  },
                  child: cardWidget,
                );
              } else if (isValidTarget) {
                cardWidget = DragTarget<GameCard>(
                  onWillAcceptWithDetails: (details) =>
                      details.data.ownerId == match.player.id,
                  onAcceptWithDetails: (details) =>
                      _attackCardTYC3(card, row, col),
                  builder: (context, candidateData, rejectedData) {
                    final isBeingTargeted = candidateData.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      transform: Matrix4.identity()
                        ..scale(isBeingTargeted ? 1.1 : 1.0),
                      transformAlignment: Alignment.center,
                      child: _buildRenderedCard(
                        card,
                        cardWidth.clamp(40.0, 80.0),
                        cardHeight.clamp(56.0, 112.0),
                        isPlayer: false,
                        isValidTarget: true,
                        isBeingTargeted: isBeingTargeted,
                      ),
                    );
                  },
                );
              }

              return GestureDetector(
                onTap: () =>
                    _onBoardCardTap(card, row, col, isPlayer, !isPlayer),
                onLongPress: () => _showCardDetails(card),
                child: cardWidget,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildRenderedCard(
    GameCard card,
    double width,
    double height, {
    bool isPlayer = true,
    bool isSelected = false,
    bool isValidTarget = false,
    bool isBeingTargeted = false,
    bool isInHand = false,
  }) {
    final rarityColor = _getRarityColor(card.rarity);
    final rarityGlow = _getRarityGlow(card.rarity);

    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? Colors.yellow
              : isValidTarget
              ? Colors.orange
              : isBeingTargeted
              ? Colors.red
              : rarityColor,
          width: isSelected || isValidTarget || isBeingTargeted ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? Colors.yellow.withOpacity(0.6)
                : isValidTarget || isBeingTargeted
                ? Colors.orange.withOpacity(0.6)
                : rarityGlow.withOpacity(0.4),
            blurRadius: isSelected || isValidTarget || isBeingTargeted ? 12 : 6,
            spreadRadius: isSelected || isValidTarget || isBeingTargeted
                ? 2
                : 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Positioned.fill(child: _buildCardArtPlaceholder(card, isPlayer)),
            Positioned.fill(child: _buildCardFrameOverlay(card.rarity)),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildCardStatsOverlay(card, width),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildCardNameBanner(card, width),
            ),
            if (!isInHand)
              Positioned(
                bottom: height * 0.25,
                left: 2,
                right: 2,
                child: _buildCardHPBar(card),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardArtPlaceholder(GameCard card, bool isPlayer) {
    // Use card1.png as background for all cards
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/image/card1.png', fit: BoxFit.cover),
        // Add player/opponent color tint overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isPlayer
                  ? [Colors.blue.withOpacity(0.3), Colors.blue.withOpacity(0.1)]
                  : [Colors.red.withOpacity(0.3), Colors.red.withOpacity(0.1)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardFrameOverlay(int rarity) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _getRarityColor(rarity).withOpacity(0.5),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.transparent,
            Colors.black.withOpacity(0.3),
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
    );
  }

  Widget _buildCardNameBanner(GameCard card, double width) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.black.withOpacity(0.6),
          ],
        ),
      ),
      child: Text(
        card.name,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _getRarityColor(card.rarity),
          fontSize: width > 60 ? 8 : 6,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCardStatsOverlay(GameCard card, double width) {
    final fontSize = width > 60 ? 8.0 : 6.0;
    final iconSize = width > 60 ? 10.0 : 8.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department,
                size: iconSize,
                color: Colors.orange,
              ),
              Text(
                '${card.currentDamage}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: iconSize, color: Colors.yellow),
              Text(
                '${card.currentAP}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardHPBar(GameCard card) {
    final hpPercent = card.currentHealth / card.health;

    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black, width: 0.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: hpPercent.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hpPercent > 0.5
                  ? [Colors.green[600]!, Colors.green[400]!]
                  : hpPercent > 0.25
                  ? [Colors.orange[600]!, Colors.orange[400]!]
                  : [Colors.red[600]!, Colors.red[400]!],
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Color _getRarityColor(int rarity) {
    switch (rarity) {
      case 1:
        return Colors.grey[400]!;
      case 2:
        return Colors.blue[400]!;
      case 3:
        return Colors.purple[400]!;
      case 4:
        return Colors.amber[400]!;
      default:
        return Colors.grey[400]!;
    }
  }

  Color _getRarityGlow(int rarity) {
    switch (rarity) {
      case 1:
        return Colors.grey;
      case 2:
        return Colors.blue;
      case 3:
        return Colors.purple;
      case 4:
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  // ===== POKER-STYLE FANNED HAND =====

  Widget _buildPokerHand(player) {
    final hand = player.hand as List<GameCard>;

    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.brown[900]!.withOpacity(0.8),
            Colors.brown[800]!.withOpacity(0.9),
          ],
        ),
        border: Border(top: BorderSide(color: Colors.amber[700]!, width: 2)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'YOUR HAND (${hand.length}) - Drag or tap to select',
              style: TextStyle(
                color: Colors.amber[300],
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(child: _buildFannedHand(hand)),
        ],
      ),
    );
  }

  Widget _buildFannedHand(List<GameCard> hand) {
    if (hand.isEmpty) {
      return Center(
        child: Text(
          'No cards in hand',
          style: TextStyle(color: Colors.brown[600]),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final cardHeight = availableHeight * 0.85;
        final cardWidth = cardHeight / 1.4;

        final overlapWidth = cardWidth * (1 - _handCardOverlap);
        final totalCardsWidth = cardWidth + (hand.length - 1) * overlapWidth;

        final totalAngle = _handFanAngle * (hand.length - 1);
        final startAngle = -totalAngle / 2;

        return Center(
          child: SizedBox(
            width: totalCardsWidth + 40,
            height: availableHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: List.generate(hand.length, (index) {
                final card = hand[index];
                final isSelected = _selectedCard == card;

                final centerIndex = (hand.length - 1) / 2;
                final offsetFromCenter = index - centerIndex;
                final xOffset = offsetFromCenter * overlapWidth;
                final angle = hand.length > 1
                    ? (startAngle + index * _handFanAngle) * (pi / 180)
                    : 0.0;
                final distanceFromCenter = offsetFromCenter.abs();
                final yOffset = distanceFromCenter * distanceFromCenter * 3;

                return Positioned(
                  left: (totalCardsWidth + 40) / 2 - cardWidth / 2 + xOffset,
                  top: yOffset + (isSelected ? -15 : 5),
                  child: Transform.rotate(
                    angle: angle,
                    alignment: Alignment.bottomCenter,
                    child: _buildDraggableHandCard(
                      card,
                      isSelected,
                      cardWidth,
                      cardHeight,
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraggableHandCard(
    GameCard card,
    bool isSelected,
    double cardWidth,
    double cardHeight,
  ) {
    return Draggable<GameCard>(
      data: card,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: _buildHandCardWidget(
          card,
          cardWidth,
          cardHeight,
          isDragging: true,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildHandCardWidget(card, cardWidth, cardHeight),
      ),
      onDragStarted: () {
        setState(() {
          _draggedCard = card;
          _selectedCard = null;
          _clearBoardSelection();
        });
      },
      onDragEnd: (_) => setState(() => _draggedCard = null),
      child: GestureDetector(
        onTap: () => _onHandCardTap(card),
        onLongPress: () => _showCardDetails(card),
        child: _buildHandCardWidget(
          card,
          cardWidth,
          cardHeight,
          isSelected: isSelected,
        ),
      ),
    );
  }

  Widget _buildHandCardWidget(
    GameCard card,
    double width,
    double height, {
    bool isSelected = false,
    bool isDragging = false,
  }) {
    final rarityColor = _getRarityColor(card.rarity);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.amber[50]!, Colors.amber[100]!],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.green : rarityColor,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          if (isDragging || isSelected)
            BoxShadow(
              color: (isSelected ? Colors.green : Colors.black).withOpacity(
                0.3,
              ),
              blurRadius: 8,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            // Card art background - use card1.png
            Positioned.fill(
              child: Image.asset('assets/image/card1.png', fit: BoxFit.cover),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: TextStyle(
                      fontSize: width * 0.11,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown[900],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  if (card.element != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getTerrainColor(card.element!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        card.element!,
                        style: TextStyle(
                          fontSize: width * 0.09,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: width * 0.12,
                            color: Colors.orange,
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite,
                            size: width * 0.12,
                            color: Colors.red,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: width * 0.10, color: Colors.amber),
                      Text(
                        '${card.maxAP} AP',
                        style: TextStyle(
                          fontSize: width * 0.09,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildActionButton(MatchState match) {
    if (!_matchManager.isPlayerTurn) {
      return FloatingActionButton.extended(
        onPressed: null,
        backgroundColor: Colors.grey,
        label: const Text("Enemy's Turn"),
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    return FloatingActionButton.extended(
      onPressed: _endTurnTYC3,
      backgroundColor: Colors.amber[700],
      icon: const Icon(Icons.skip_next),
      label: const Text('END TURN'),
    );
  }

  Widget _buildGameOver(MatchState match) {
    final playerWon = match.winner?.id == match.player.id;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: playerWon
                ? [Colors.amber[900]!, Colors.amber[700]!]
                : [Colors.grey[900]!, Colors.grey[700]!],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: playerWon ? Colors.amber : Colors.grey,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: (playerWon ? Colors.amber : Colors.grey).withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              playerWon ? Icons.emoji_events : Icons.close,
              size: 80,
              color: playerWon ? Colors.amber[300] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              playerWon ? 'VICTORY!' : 'DEFEAT',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startNewMatch,
              icon: const Icon(Icons.refresh),
              label: const Text('PLAY AGAIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[700],
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainMenuScreen()),
                (route) => false,
              ),
              icon: const Icon(Icons.home, color: Colors.white70),
              label: const Text(
                'MAIN MENU',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for terrain patterns
class TerrainPatternPainter extends CustomPainter {
  final String terrain;

  TerrainPatternPainter(this.terrain);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    switch (terrain.toLowerCase()) {
      case 'woods':
        for (int i = 0; i < 5; i++) {
          final x = (size.width / 5) * i + 10;
          final y = size.height * 0.6;
          canvas.drawLine(Offset(x, y), Offset(x, y - 15), paint);
          canvas.drawLine(Offset(x - 5, y - 10), Offset(x + 5, y - 10), paint);
        }
        break;
      case 'lake':
        for (int i = 0; i < 3; i++) {
          final y = size.height * (0.3 + i * 0.2);
          final path = Path();
          path.moveTo(0, y);
          for (double x = 0; x < size.width; x += 20) {
            path.quadraticBezierTo(x + 5, y - 5, x + 10, y);
            path.quadraticBezierTo(x + 15, y + 5, x + 20, y);
          }
          canvas.drawPath(path, paint);
        }
        break;
      case 'desert':
        for (int i = 0; i < 3; i++) {
          final y = size.height * (0.4 + i * 0.15);
          final path = Path();
          path.moveTo(0, y);
          path.quadraticBezierTo(
            size.width * 0.25,
            y - 10,
            size.width * 0.5,
            y,
          );
          path.quadraticBezierTo(size.width * 0.75, y + 10, size.width, y);
          canvas.drawPath(path, paint);
        }
        break;
      case 'marsh':
        for (int i = 0; i < 8; i++) {
          final x = (size.width / 8) * i + 5;
          final y = size.height * 0.7;
          canvas.drawLine(Offset(x, y), Offset(x - 2, y - 12), paint);
          canvas.drawLine(Offset(x, y), Offset(x + 2, y - 10), paint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
