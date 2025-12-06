import 'dart:math';
import 'package:flutter/material.dart';
import '../models/card.dart';
import '../data/card_library.dart' as cards;

/// UI Test Screen for experimenting with:
/// 1. Stacked/fanned card display on board tiles
/// 2. Drag-and-drop card placement
/// 3. Responsive layouts for different screen sizes
class UITestScreen extends StatefulWidget {
  const UITestScreen({super.key});

  @override
  State<UITestScreen> createState() => _UITestScreenState();
}

class _UITestScreenState extends State<UITestScreen> {
  // Sample cards for testing
  late List<GameCard> _handCards;

  // Board state: 3x3 grid, each tile can hold multiple cards
  late List<List<List<GameCard>>> _boardCards;

  // Currently dragged card (tracked for potential future use)
  // ignore: unused_field
  GameCard? _draggedCard;

  // Selected card (for point-and-click placement)
  GameCard? _selectedCard;

  // Targeted card on board (for attack/action targeting)
  GameCard? _targetedCard;
  int? _targetedRow;
  int? _targetedCol;

  // Selected card on board (for move/attack source)
  GameCard? _selectedBoardCard;
  int? _selectedBoardRow;
  int? _selectedBoardCol;

  // UI settings for board cards
  double _cardOverlapRatio = 0.6; // How much cards overlap (0-1)
  bool _useFanLayout = true; // Fan vs stack layout
  double _fanAngle = 5.0; // Degrees of fan spread
  double _cardSeparation = 0.0; // Extra horizontal separation between cards

  // UI settings for hand
  double _handFanAngle = 8.0; // Degrees of fan spread for hand
  double _handCardOverlap = 0.5; // How much hand cards overlap

  // Settings panel visibility
  bool _showSettings = true;

  @override
  void initState() {
    super.initState();
    _initializeTestData();
  }

  void _initializeTestData() {
    // Create sample cards using the card library factory functions
    final sampleCards = [
      cards.desertQuickStrike(0),
      cards.desertWarrior(0),
      cards.lakeArcher(0),
      cards.woodsArcher(0),
      cards.desertQuickStrike(1),
      cards.desertTank(0),
      cards.lakeWarrior(0),
      cards.woodsWarrior(0),
      cards.scoutUnit(0),
    ];

    // Pick 6 cards for hand
    _handCards = sampleCards.take(6).map((c) {
      final card = c.copy();
      card.ownerId = 'player';
      return card;
    }).toList();

    // Initialize empty 3x3 board
    _boardCards = List.generate(
      3,
      (row) => List.generate(3, (col) => <GameCard>[]),
    );

    // Fill board for testing:
    // - 7 tiles with 2 cards each
    // - 1 tile with 1 card (player base center)
    // - 1 tile with 0 cards (enemy base west)
    // Row 0 = enemy base, Row 1 = middle, Row 2 = player base
    // Col 0 = West, Col 1 = Center, Col 2 = East

    int cardIndex = 20;

    // Helper to create a card pair for a tile
    List<GameCard> createCardPair(String owner) {
      final card1 = cards.desertQuickStrike(cardIndex++).copy();
      card1.ownerId = owner;
      final card2 = cards.lakeArcher(cardIndex++).copy();
      card2.ownerId = owner;
      return [card1, card2];
    }

    // Row 0: Enemy Base
    // [0,0] Enemy West - EMPTY (0 cards)
    _boardCards[0][0] = [];
    // [0,1] Enemy Center - 2 cards
    _boardCards[0][1] = createCardPair('opponent');
    // [0,2] Enemy East - 2 cards
    _boardCards[0][2] = createCardPair('opponent');

    // Row 1: Middle
    // [1,0] Middle West - 2 cards (mixed)
    final midWest1 = cards.desertWarrior(cardIndex++).copy();
    midWest1.ownerId = 'player';
    final midWest2 = cards.woodsArcher(cardIndex++).copy();
    midWest2.ownerId = 'opponent';
    _boardCards[1][0] = [midWest1, midWest2];
    // [1,1] Middle Center - 2 cards
    _boardCards[1][1] = createCardPair('opponent');
    // [1,2] Middle East - 2 cards
    final midEast1 = cards.desertTank(cardIndex++).copy();
    midEast1.ownerId = 'player';
    final midEast2 = cards.lakeWarrior(cardIndex++).copy();
    midEast2.ownerId = 'opponent';
    _boardCards[1][2] = [midEast1, midEast2];

    // Row 2: Player Base
    // [2,0] Base West - 2 cards
    _boardCards[2][0] = createCardPair('player');
    // [2,1] Base Center - 1 card (player)
    final baseCenter = cards.woodsWarrior(cardIndex++).copy();
    baseCenter.ownerId = 'player';
    _boardCards[2][1] = [baseCenter];
    // [2,2] Base East - 2 cards
    _boardCards[2][2] = createCardPair('player');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UI Test - Stacked Cards & Drag/Drop'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showSettings ? Icons.visibility_off : Icons.tune),
            onPressed: () => setState(() => _showSettings = !_showSettings),
            tooltip: _showSettings ? 'Hide Settings' : 'Show Settings',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _initializeTestData()),
            tooltip: 'Reset',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive: use available space
            final isLandscape = constraints.maxWidth > constraints.maxHeight;

            return Column(
              children: [
                // Settings panel (collapsible)
                if (_showSettings) ...[
                  _buildSettingsPanel(),
                  const Divider(height: 1),
                ],

                // Main game area
                Expanded(
                  child: isLandscape
                      ? _buildLandscapeLayout(constraints)
                      : _buildPortraitLayout(constraints),
                ),
              ],
            );
          },
        ),
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
          // Board card settings
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
              SizedBox(
                width: 35,
                child: Text(
                  '${(_cardOverlapRatio * 100).toInt()}%',
                  style: const TextStyle(fontSize: 11),
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
              SizedBox(
                width: 30,
                child: Text(
                  '${_cardSeparation.toInt()}px',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          // Hand settings
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
              SizedBox(
                width: 30,
                child: Text(
                  '${_handFanAngle.toInt()}°',
                  style: const TextStyle(fontSize: 11),
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
              SizedBox(
                width: 35,
                child: Text(
                  '${(_handCardOverlap * 100).toInt()}%',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(BoxConstraints constraints) {
    return Column(
      children: [
        // Targeting status bar
        _buildTargetingStatusBar(),

        // Board takes most of the space
        Expanded(flex: 5, child: _buildBoard(constraints)),

        const Divider(height: 1),

        // Hand at bottom - poker style fanned
        SizedBox(height: 160, child: _buildHand()),
      ],
    );
  }

  Widget _buildTargetingStatusBar() {
    final hasSelection = _selectedBoardCard != null || _targetedCard != null;
    if (!hasSelection) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey[800],
      child: Row(
        children: [
          // Selected card info
          if (_selectedBoardCard != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.yellow,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, size: 14, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    _selectedBoardCard!.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Arrow if both selected and targeted
          if (_selectedBoardCard != null && _targetedCard != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, color: Colors.white, size: 20),
            ),
          ],

          // Targeted card info
          if (_targetedCard != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_fixed, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _targetedCard!.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Clear button
          TextButton.icon(
            onPressed: () => setState(() => _clearBoardSelection()),
            icon: const Icon(Icons.clear, size: 16, color: Colors.white70),
            label: const Text(
              'Clear',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(BoxConstraints constraints) {
    // In landscape, also use bottom fanned hand for consistency
    return Column(
      children: [
        // Targeting status bar
        _buildTargetingStatusBar(),

        // Board takes most of the space
        Expanded(flex: 4, child: _buildBoard(constraints)),

        const Divider(height: 1),

        // Hand at bottom - poker style fanned (same as portrait)
        SizedBox(height: 140, child: _buildHand()),
      ],
    );
  }

  Widget _buildBoard(BoxConstraints constraints) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: AspectRatio(
        aspectRatio: 1.0, // Square board
        child: Column(
          children: [
            // Row labels
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Enemy Base',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),

            // Board grid
            Expanded(
              child: Column(
                children: List.generate(3, (row) {
                  return Expanded(
                    child: Row(
                      children: List.generate(3, (col) {
                        return Expanded(child: _buildTile(row, col));
                      }),
                    ),
                  );
                }),
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Your Base',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(int row, int col) {
    final cards = _boardCards[row][col];
    final isPlayerBase = row == 2;
    final isEnemyBase = row == 0;

    // Determine if this tile can accept drops
    final canAcceptDrop = isPlayerBase || row == 1;

    return DragTarget<GameCard>(
      onWillAcceptWithDetails: (details) => canAcceptDrop && cards.length < 3,
      onAcceptWithDetails: (details) {
        setState(() {
          final card = details.data;
          // Remove from hand
          _handCards.remove(card);
          // Add to board
          _boardCards[row][col].add(card);
          _selectedCard = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        final isSelected =
            _selectedCard != null && canAcceptDrop && cards.length < 3;

        return GestureDetector(
          onTap: () => _onTileTap(row, col),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? Colors.green[100]
                  : isSelected
                  ? Colors.blue[50]
                  : isPlayerBase
                  ? Colors.blue[50]
                  : isEnemyBase
                  ? Colors.red[50]
                  : Colors.grey[100],
              border: Border.all(
                color: isHighlighted
                    ? Colors.green
                    : isSelected
                    ? Colors.blue
                    : Colors.grey[400]!,
                width: isHighlighted || isSelected ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: cards.isEmpty
                ? Center(
                    child: Text(
                      _getTileLabel(row, col),
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  )
                : _buildStackedCards(cards, row, col),
          ),
        );
      },
    );
  }

  String _getTileLabel(int row, int col) {
    final lanes = ['West', 'Center', 'East'];
    final rows = ['Enemy', 'Middle', 'Base'];
    return '${rows[row]}\n${lanes[col]}';
  }

  /// Build stacked/fanned card display for a tile
  Widget _buildStackedCards(List<GameCard> cards, int row, int col) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth;
        final tileHeight = constraints.maxHeight;

        // Calculate card dimensions based on tile size
        final cardWidth = tileWidth * 0.85;
        final cardHeight = cardWidth * 1.4; // Card aspect ratio

        // Calculate offset for stacking
        final overlapOffset = cardHeight * (1 - _cardOverlapRatio);

        // Total height needed for all cards
        final totalHeight = cardHeight + (cards.length - 1) * overlapOffset;

        // Scale down if needed
        final scale = totalHeight > tileHeight * 0.95
            ? (tileHeight * 0.95) / totalHeight
            : 1.0;

        return Center(
          child: SizedBox(
            width: cardWidth * scale + (_useFanLayout ? cards.length * 4 : 0),
            height: totalHeight * scale,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(cards.length, (index) {
                final card = cards[index];
                final isPlayerCard = card.ownerId == 'player';

                // Calculate position
                double top = index * overlapOffset * scale;
                double left = 0;
                double rotation = 0;

                if (_useFanLayout && cards.length > 1) {
                  // Fan layout: slight rotation and horizontal offset
                  final centerIndex = (cards.length - 1) / 2;
                  final offsetFromCenter = index - centerIndex;
                  rotation = offsetFromCenter * _fanAngle * (pi / 180);
                  left = offsetFromCenter * (4 + _cardSeparation);
                } else if (cards.length > 1) {
                  // Stack layout with separation
                  final centerIndex = (cards.length - 1) / 2;
                  final offsetFromCenter = index - centerIndex;
                  left = offsetFromCenter * _cardSeparation;
                }

                // Check if this card is targeted (for raised effect)
                final isTargeted = _targetedCard == card;

                return Positioned(
                  top: top,
                  left: left,
                  child: Transform.rotate(
                    angle: rotation,
                    child: isPlayerCard
                        ? _buildDraggableBoardCard(
                            card,
                            row,
                            col,
                            cardWidth * scale,
                            cardHeight * scale,
                            index == cards.length - 1,
                          )
                        : _buildTargetableBoardCard(
                            card,
                            row,
                            col,
                            cardWidth * scale,
                            cardHeight * scale,
                            index == cards.length - 1,
                            isTargeted,
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

  /// Build a draggable player card on the board
  Widget _buildDraggableBoardCard(
    GameCard card,
    int row,
    int col,
    double width,
    double height,
    bool isTopCard,
  ) {
    final isSelected = _selectedBoardCard == card;

    return Draggable<GameCard>(
      data: card,
      feedback: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(8),
        child: Transform.scale(
          scale: 1.1,
          child: _buildMiniCard(
            card,
            width,
            height,
            isPlayerCard: true,
            isTopCard: true,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildMiniCard(
          card,
          width,
          height,
          isPlayerCard: true,
          isTopCard: isTopCard,
        ),
      ),
      onDragStarted: () {
        setState(() {
          _selectedBoardCard = card;
          _selectedBoardRow = row;
          _selectedBoardCol = col;
          _targetedCard = null;
        });
      },
      onDragEnd: (details) {
        // Keep selection if not dropped on target
      },
      child: GestureDetector(
        onTap: () => _onBoardCardTap(card, row, col),
        onLongPress: () => _showCardDetails(card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.identity()..scale(isSelected ? 1.05 : 1.0),
          transformAlignment: Alignment.center,
          child: _buildMiniCard(
            card,
            width,
            height,
            isPlayerCard: true,
            isTopCard: isTopCard,
          ),
        ),
      ),
    );
  }

  /// Build a targetable enemy card on the board (can receive drag)
  Widget _buildTargetableBoardCard(
    GameCard card,
    int row,
    int col,
    double width,
    double height,
    bool isTopCard,
    bool isTargeted,
  ) {
    return DragTarget<GameCard>(
      onWillAcceptWithDetails: (details) {
        // Only accept player cards for targeting
        return details.data.ownerId == 'player';
      },
      onAcceptWithDetails: (details) {
        setState(() {
          _targetedCard = card;
          _targetedRow = row;
          _targetedCol = col;
        });
        _showTargetingFeedback(card, row, col, false);
      },
      builder: (context, candidateData, rejectedData) {
        final isBeingDraggedOver = candidateData.isNotEmpty;

        return GestureDetector(
          onTap: () => _onBoardCardTap(card, row, col),
          onLongPress: () => _showCardDetails(card),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()
              ..scale(
                isTargeted
                    ? 1.15
                    : isBeingDraggedOver
                    ? 1.1
                    : 1.0,
              )
              ..translate(
                0.0,
                isTargeted
                    ? -8.0
                    : isBeingDraggedOver
                    ? -4.0
                    : 0.0,
              ),
            transformAlignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  if (isTargeted || isBeingDraggedOver)
                    BoxShadow(
                      color: Colors.orange.withOpacity(isTargeted ? 0.6 : 0.4),
                      blurRadius: isTargeted ? 16 : 12,
                      spreadRadius: isTargeted ? 4 : 2,
                    ),
                ],
              ),
              child: _buildMiniCard(
                card,
                width,
                height,
                isPlayerCard: false,
                isTopCard: isTopCard,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build a mini card widget for board display
  Widget _buildMiniCard(
    GameCard card,
    double width,
    double height, {
    bool isPlayerCard = true,
    bool isTopCard = false,
  }) {
    final baseColor = isPlayerCard ? Colors.blue : Colors.red;
    final rarityColor = _getRarityColor(card.rarity);

    // Check if this card is selected or targeted
    final isSelected = _selectedBoardCard == card;
    final isTargeted = _targetedCard == card;

    // Determine border color and width based on state
    Color borderColor;
    double borderWidth;
    if (isSelected) {
      borderColor = Colors.yellow;
      borderWidth = 3;
    } else if (isTargeted) {
      borderColor = Colors.orange;
      borderWidth = 3;
    } else {
      borderColor = isTopCard ? rarityColor : rarityColor.withOpacity(0.5);
      borderWidth = isTopCard ? 2 : 1;
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSelected
              ? [Colors.yellow[100]!, Colors.yellow[200]!]
              : isTargeted
              ? [Colors.orange[100]!, Colors.orange[200]!]
              : [baseColor[100]!, baseColor[200]!],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? Colors.yellow.withOpacity(0.5)
                : isTargeted
                ? Colors.orange.withOpacity(0.5)
                : Colors.black.withOpacity(0.2),
            blurRadius: isSelected || isTargeted ? 8 : 4,
            spreadRadius: isSelected || isTargeted ? 2 : 0,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card name (truncated)
            Text(
              card.name,
              style: TextStyle(
                fontSize: width * 0.12,
                fontWeight: FontWeight.bold,
                color: baseColor[900],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Attack
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      size: width * 0.15,
                      color: Colors.orange,
                    ),
                    Text(
                      '${card.currentDamage}',
                      style: TextStyle(
                        fontSize: width * 0.12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Health
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: width * 0.15, color: Colors.red),
                    Text(
                      '${card.currentHealth}/${card.health}',
                      style: TextStyle(
                        fontSize: width * 0.12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // AP indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, size: width * 0.12, color: Colors.amber),
                Text(
                  '${card.currentAP}/${card.maxAP}',
                  style: TextStyle(
                    fontSize: width * 0.10,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build the hand area - poker-style fanned cards at bottom
  Widget _buildHand() {
    return Container(
      color: Colors.brown[200],
      child: Column(
        children: [
          // Label
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Your Hand (${_handCards.length}) - Drag or tap to select',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.brown[800],
              ),
            ),
          ),
          // Fanned cards
          Expanded(child: _buildFannedHand()),
        ],
      ),
    );
  }

  /// Build poker-style fanned hand
  Widget _buildFannedHand() {
    if (_handCards.isEmpty) {
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

        // Card dimensions
        final cardHeight = availableHeight * 0.85;
        final cardWidth = cardHeight / 1.4;

        // Calculate total width needed for all cards with overlap
        final overlapWidth = cardWidth * (1 - _handCardOverlap);
        final totalCardsWidth =
            cardWidth + (_handCards.length - 1) * overlapWidth;

        // Fan rotation calculations
        final totalAngle = _handFanAngle * (_handCards.length - 1);
        final startAngle = -totalAngle / 2;

        // Build cards centered using a Row with MainAxisAlignment.center
        return Center(
          child: SizedBox(
            width: totalCardsWidth + 40, // Extra padding for rotated cards
            height: availableHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: List.generate(_handCards.length, (index) {
                final card = _handCards[index];
                final isSelected = _selectedCard == card;

                // Calculate position relative to center
                final centerIndex = (_handCards.length - 1) / 2;
                final offsetFromCenter = index - centerIndex;

                // Horizontal position from center
                final xOffset = offsetFromCenter * overlapWidth;

                // Rotation angle
                final angle = _handCards.length > 1
                    ? (startAngle + index * _handFanAngle) * (pi / 180)
                    : 0.0;

                // Vertical offset based on position (arc effect)
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
                      cardWidth: cardWidth,
                      cardHeight: cardHeight,
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

  /// Build a draggable hand card
  Widget _buildDraggableHandCard(
    GameCard card,
    bool isSelected, {
    bool vertical = false,
    double? cardWidth,
    double? cardHeight,
  }) {
    final width = cardWidth ?? (vertical ? 100.0 : 90.0);
    final height = cardHeight ?? (width * 1.4);

    return Draggable<GameCard>(
      data: card,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: _buildHandCardWidget(card, width, height, isDragging: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildHandCardWidget(card, width, height),
      ),
      onDragStarted: () {
        setState(() {
          _draggedCard = card;
          _selectedCard = null;
        });
      },
      onDragEnd: (_) {
        setState(() => _draggedCard = null);
      },
      child: GestureDetector(
        onTap: () => _onHandCardTap(card),
        onLongPress: () => _showCardDetails(card),
        child: _buildHandCardWidget(
          card,
          width,
          height,
          isSelected: isSelected,
        ),
      ),
    );
  }

  /// Build the visual widget for a hand card
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
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card name
            Text(
              card.name,
              style: TextStyle(
                fontSize: width * 0.11,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            // Element badge
            if (card.element != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _getElementColor(card.element!),
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

            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatChip(
                  Icons.local_fire_department,
                  '${card.damage}',
                  Colors.orange,
                  width * 0.10,
                ),
                _buildStatChip(
                  Icons.favorite,
                  '${card.health}',
                  Colors.red,
                  width * 0.10,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatChip(
                  Icons.bolt,
                  '${card.maxAP}',
                  Colors.amber,
                  width * 0.10,
                ),
                if (card.abilities.isNotEmpty)
                  Icon(Icons.star, size: width * 0.12, color: Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String value,
    Color color,
    double fontSize,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: fontSize * 1.2, color: color),
        Text(
          value,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // === Event Handlers ===

  void _onHandCardTap(GameCard card) {
    setState(() {
      if (_selectedCard == card) {
        _selectedCard = null; // Deselect
      } else {
        _selectedCard = card; // Select
      }
    });
  }

  void _onTileTap(int row, int col) {
    if (_selectedCard != null) {
      // Point-and-click placement
      final canPlace =
          (row == 2 || row == 1) && _boardCards[row][col].length < 3;
      if (canPlace) {
        setState(() {
          _handCards.remove(_selectedCard);
          _boardCards[row][col].add(_selectedCard!);
          _selectedCard = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Card placed at ${_getTileLabel(row, col).replaceAll('\n', ' ')}',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _onBoardCardTap(GameCard card, int row, int col) {
    final isPlayerCard = card.ownerId == 'player';

    setState(() {
      if (isPlayerCard) {
        // Tapping own card - select it as source for action
        if (_selectedBoardCard == card) {
          // Deselect if already selected
          _clearBoardSelection();
        } else {
          _selectedBoardCard = card;
          _selectedBoardRow = row;
          _selectedBoardCol = col;
          _targetedCard = null;
          _targetedRow = null;
          _targetedCol = null;
          _selectedCard = null; // Clear hand selection
        }
      } else {
        // Tapping enemy card - target it
        if (_targetedCard == card) {
          // Deselect if already targeted
          _targetedCard = null;
          _targetedRow = null;
          _targetedCol = null;
        } else {
          _targetedCard = card;
          _targetedRow = row;
          _targetedCol = col;
        }
      }
    });

    // Show feedback
    _showTargetingFeedback(card, row, col, isPlayerCard);
  }

  void _clearBoardSelection() {
    _selectedBoardCard = null;
    _selectedBoardRow = null;
    _selectedBoardCol = null;
    _targetedCard = null;
    _targetedRow = null;
    _targetedCol = null;
  }

  void _showTargetingFeedback(
    GameCard card,
    int row,
    int col,
    bool isPlayerCard,
  ) {
    final action = isPlayerCard ? 'SELECTED' : 'TARGETED';
    final color = isPlayerCard ? Colors.blue : Colors.red;
    final cardIndex = _boardCards[row][col].indexOf(card);
    final totalCards = _boardCards[row][col].length;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isPlayerCard ? Icons.touch_app : Icons.gps_fixed,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$action: ${card.name} (card ${cardIndex + 1}/$totalCards in stack)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Details',
          textColor: Colors.white,
          onPressed: () => _showCardDetails(card),
        ),
      ),
    );
  }

  void _showCardDetails(GameCard card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(card.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Damage: ${card.damage}'),
            Text('Health: ${card.currentHealth}/${card.health}'),
            Text('AP: ${card.currentAP}/${card.maxAP}'),
            if (card.element != null) Text('Element: ${card.element}'),
            if (card.abilities.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Abilities:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...card.abilities.map((a) => Text('• $a')),
            ],
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

  // === Helper Methods ===

  Color _getRarityColor(int rarity) {
    switch (rarity) {
      case 1:
        return Colors.grey;
      case 2:
        return Colors.blue;
      case 3:
        return Colors.purple;
      case 4:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getElementColor(String element) {
    switch (element.toLowerCase()) {
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
}
