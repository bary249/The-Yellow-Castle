import 'package:flutter/material.dart';
import '../models/card.dart';
import '../data/card_library.dart';

/// Screen for editing the player's deck
class DeckEditorScreen extends StatefulWidget {
  const DeckEditorScreen({super.key});

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  static const int maxDeckSize = 25;
  static const int minDeckSize = 15;

  // Current deck cards
  late List<GameCard> _deckCards;

  // All available cards (card pool)
  late List<GameCard> _availableCards;

  // Selected card for details view
  GameCard? _selectedCard;

  @override
  void initState() {
    super.initState();
    _initializeCards();
  }

  void _initializeCards() {
    // Start with default deck
    _deckCards = List.from(buildStarterCardPool());

    // Available cards pool (all card types, multiple copies)
    _availableCards = _buildCardPool();
  }

  List<GameCard> _buildCardPool() {
    final pool = <GameCard>[];

    // Add multiple copies of each card type
    for (int i = 0; i < 5; i++) {
      pool.add(desertQuickStrike(100 + i));
      pool.add(lakeQuickStrike(100 + i));
      pool.add(woodsQuickStrike(100 + i));
      pool.add(desertWarrior(100 + i));
      pool.add(lakeWarrior(100 + i));
      pool.add(woodsWarrior(100 + i));
      pool.add(desertTank(100 + i));
      pool.add(lakeTank(100 + i));
      pool.add(woodsTank(100 + i));
    }

    // Add support cards
    for (int i = 0; i < 3; i++) {
      pool.add(lakeShieldTotem(100 + i));
      pool.add(desertWarBanner(100 + i));
    }

    return pool;
  }

  void _addCardToDeck(GameCard card) {
    if (_deckCards.length >= maxDeckSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deck is full! Max $maxDeckSize cards.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      // Create a copy with unique ID
      final newCard = GameCard(
        id: '${card.id}_deck_${DateTime.now().millisecondsSinceEpoch}',
        name: card.name,
        damage: card.damage,
        health: card.health,
        tick: card.tick,
        element: card.element,
        abilities: card.abilities,
        cost: card.cost,
        rarity: card.rarity,
      );
      _deckCards.add(newCard);
    });
  }

  void _removeCardFromDeck(GameCard card) {
    if (_deckCards.length <= minDeckSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deck needs at least $minDeckSize cards!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _deckCards.remove(card);
      if (_selectedCard == card) {
        _selectedCard = null;
      }
    });
  }

  void _saveDeck() {
    if (_deckCards.length < minDeckSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deck needs at least $minDeckSize cards!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // TODO: Save to persistent storage
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deck saved!'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pop(_deckCards);
  }

  void _resetDeck() {
    setState(() {
      _deckCards = List.from(buildStarterCardPool());
      _selectedCard = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deck reset to default')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deck Editor'),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _resetDeck,
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text('Reset', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saveDeck,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.indigo[900]!, Colors.grey[900]!],
          ),
        ),
        child: Row(
          children: [
            // Left: Current Deck
            Expanded(flex: 1, child: _buildDeckPanel()),

            // Divider
            Container(width: 2, color: Colors.white24),

            // Right: Available Cards
            Expanded(flex: 1, child: _buildCardPoolPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildDeckPanel() {
    // Group cards by name for display
    final cardCounts = <String, List<GameCard>>{};
    for (final card in _deckCards) {
      cardCounts.putIfAbsent(card.name, () => []).add(card);
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black26,
          child: Row(
            children: [
              const Icon(Icons.style, color: Colors.amber),
              const SizedBox(width: 8),
              const Text(
                'YOUR DECK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _deckCards.length >= minDeckSize
                      ? Colors.green
                      : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_deckCards.length}/$maxDeckSize',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Deck cards list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: cardCounts.length,
            itemBuilder: (context, index) {
              final cardName = cardCounts.keys.elementAt(index);
              final cards = cardCounts[cardName]!;
              final card = cards.first;

              return _buildDeckCardTile(card, cards.length);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeckCardTile(GameCard card, int count) {
    final isSelected = _selectedCard?.name == card.name;

    return GestureDetector(
      onTap: () => setState(() => _selectedCard = card),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withValues(alpha: 0.3)
              : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.amber
                : _getElementColor(card.element ?? 'neutral'),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Element indicator
            Container(
              width: 8,
              height: 40,
              decoration: BoxDecoration(
                color: _getElementColor(card.element ?? 'neutral'),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),

            // Card info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '⚔️${card.damage} ❤️${card.health} ⏱️${card.tick}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),

            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'x$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Remove button
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              onPressed: () {
                final cardsOfType = _deckCards
                    .where((c) => c.name == card.name)
                    .toList();
                if (cardsOfType.isNotEmpty) {
                  _removeCardFromDeck(cardsOfType.last);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPoolPanel() {
    // Group available cards by name
    final cardTypes = <String, GameCard>{};
    for (final card in _availableCards) {
      cardTypes.putIfAbsent(card.name, () => card);
    }

    // Sort by element then name
    final sortedCards = cardTypes.values.toList()
      ..sort((a, b) {
        final elementCompare = (a.element ?? '').compareTo(b.element ?? '');
        if (elementCompare != 0) return elementCompare;
        return a.name.compareTo(b.name);
      });

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black26,
          child: const Row(
            children: [
              Icon(Icons.library_books, color: Colors.cyan),
              SizedBox(width: 8),
              Text(
                'CARD POOL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              Text('Tap to add →', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),

        // Card pool grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: sortedCards.length,
            itemBuilder: (context, index) {
              final card = sortedCards[index];
              return _buildPoolCardTile(card);
            },
          ),
        ),

        // Selected card details
        if (_selectedCard != null) _buildCardDetails(_selectedCard!),
      ],
    );
  }

  Widget _buildPoolCardTile(GameCard card) {
    final inDeckCount = _deckCards.where((c) => c.name == card.name).length;

    return GestureDetector(
      onTap: () => _addCardToDeck(card),
      onLongPress: () => setState(() => _selectedCard = card),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _getElementColor(card.element ?? 'neutral').withAlpha(60),
              Colors.black45,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _getElementColor(card.element ?? 'neutral'),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name and count in deck
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (inDeckCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$inDeckCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const Spacer(),

            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatBadge('⚔️', card.damage.toString(), Colors.red),
                _buildStatBadge('❤️', card.health.toString(), Colors.pink),
                _buildStatBadge('⏱️', card.tick.toString(), Colors.blue),
              ],
            ),

            const SizedBox(height: 4),

            // Element tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getElementColor(card.element ?? 'neutral'),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                card.element ?? 'Neutral',
                style: const TextStyle(
                  color: Colors.white,
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

  Widget _buildStatBadge(String icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$icon$value',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _buildCardDetails(GameCard card) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black45,
        border: Border(
          top: BorderSide(
            color: _getElementColor(card.element ?? 'neutral'),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                card.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getElementColor(card.element ?? 'neutral'),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  card.element ?? 'Neutral',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDetailStat('Damage', card.damage, Colors.red),
              const SizedBox(width: 16),
              _buildDetailStat('Health', card.health, Colors.pink),
              const SizedBox(width: 16),
              _buildDetailStat('Tick', card.tick, Colors.blue),
            ],
          ),
          if (card.abilities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: card.abilities
                  .map(
                    (a) => Chip(
                      label: Text(a, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.purple[800],
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        Text(
          value.toString(),
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getElementColor(String element) {
    switch (element.toLowerCase()) {
      case 'desert':
        return Colors.orange;
      case 'lake':
        return Colors.blue;
      case 'woods':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
