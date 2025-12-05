import 'package:flutter/material.dart';
import '../models/card.dart';
import '../data/card_library.dart';
import '../services/deck_storage_service.dart';

/// Screen for editing the player's deck
class DeckEditorScreen extends StatefulWidget {
  const DeckEditorScreen({super.key});

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  static const int maxDeckSize = 25;
  static const int minDeckSize = 20;

  final DeckStorageService _storageService = DeckStorageService();

  // Current deck cards
  List<GameCard> _deckCards = [];

  // All available cards (card pool)
  List<GameCard> _availableCards = [];

  // Selected card for details view
  GameCard? _selectedCard;

  // Loading state
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeck();
  }

  Future<void> _loadDeck() async {
    // Load saved deck from storage
    final savedDeck = await _storageService.loadDeck();

    if (mounted) {
      setState(() {
        _deckCards = savedDeck;
        _availableCards = _buildCardPool();
        _isLoading = false;
      });
    }
  }

  List<GameCard> _buildCardPool() {
    // Use the full card pool with all rarities
    return buildFullCardPool();
  }

  /// Count how many copies of a card (by name) are in the deck
  int _countInDeck(String cardName) {
    return _deckCards.where((c) => c.name == cardName).length;
  }

  /// Check if we can add more copies of this card based on rarity limits
  bool _canAddCard(GameCard card) {
    final currentCount = _countInDeck(card.name);
    final maxAllowed = maxCopiesByRarity(card.rarity);
    return currentCount < maxAllowed;
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

    // Check rarity scarcity limit
    if (!_canAddCard(card)) {
      final maxAllowed = maxCopiesByRarity(card.rarity);
      final rarityLabel = rarityName(card.rarity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$rarityLabel cards limited to $maxAllowed copies!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      // Create a copy with unique ID including all TYC3 stats
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
        // TYC3 stats
        maxAP: card.maxAP,
        apPerTurn: card.apPerTurn,
        attackAPCost: card.attackAPCost,
        attackRange: card.attackRange,
        moveSpeed: card.moveSpeed,
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

  Future<void> _saveDeck() async {
    if (_deckCards.length < minDeckSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deck needs at least $minDeckSize cards!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Save to persistent storage
    final success = await _storageService.saveDeck(_deckCards);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deck saved!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(_deckCards);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save deck'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _resetDeck() async {
    // Clear saved deck and reset to default
    await _storageService.clearDeck();

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
      body: _isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.indigo[900]!, Colors.grey[900]!],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 16),
                    Text(
                      'Loading deck...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            )
          : Container(
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
    final rarityColor = _getRarityColor(card.rarity);
    final maxCopies = maxCopiesByRarity(card.rarity);

    return GestureDetector(
      onTap: () => setState(() => _selectedCard = card),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withValues(alpha: 0.3)
              : _getRarityBgColor(card.rarity).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.amber : rarityColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Rarity + Element indicator
            Container(
              width: 8,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    rarityColor,
                    _getElementColor(card.element ?? 'neutral'),
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),

            // Card info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        card.name,
                        style: TextStyle(
                          color: rarityColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Rarity indicator
                      if (card.rarity > 1)
                        Text(
                          card.rarity == 4
                              ? '★'
                              : (card.rarity == 3 ? '◆' : '●'),
                          style: TextStyle(color: rarityColor, fontSize: 10),
                        ),
                    ],
                  ),
                  Text(
                    '⚔️${card.damage} ❤️${card.health} 🎯${card.attackRange} ⚡${card.maxAP}  (max $maxCopies)',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
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
    final maxCopies = maxCopiesByRarity(card.rarity);
    final canAdd = inDeckCount < maxCopies;
    final rarityColor = _getRarityColor(card.rarity);

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
              rarityColor.withAlpha(40),
              _getElementColor(card.element ?? 'neutral').withAlpha(40),
              Colors.black45,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: canAdd ? rarityColor : Colors.grey,
            width: card.rarity > 1 ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rarity indicator row
            Row(
              children: [
                // Rarity badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: rarityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rarityName(card.rarity).substring(0, 1), // C/R/E/L
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // Count in deck / max
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: inDeckCount >= maxCopies ? Colors.red : Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$inDeckCount/$maxCopies',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Header with name
            Expanded(
              child: Text(
                card.name,
                style: TextStyle(
                  color: rarityColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),

            // Stats - TYC3 format
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatBadge('⚔️', card.damage.toString(), Colors.red),
                _buildStatBadge('❤️', card.health.toString(), Colors.pink),
                _buildStatBadge(
                  '🎯',
                  card.attackRange.toString(),
                  Colors.orange,
                ),
                _buildStatBadge('⚡', card.maxAP.toString(), Colors.cyan),
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
          // TYC3 Stats
          Row(
            children: [
              _buildDetailStat('Damage', card.damage, Colors.red),
              const SizedBox(width: 12),
              _buildDetailStat('Health', card.health, Colors.pink),
              const SizedBox(width: 12),
              _buildDetailStat('Range', card.attackRange, Colors.orange),
              const SizedBox(width: 12),
              _buildDetailStat('AP', card.maxAP, Colors.cyan),
            ],
          ),
          const SizedBox(height: 8),
          // Additional TYC3 info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.cyan.withAlpha(50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'AP/Turn: ${card.apPerTurn}',
                  style: const TextStyle(color: Colors.cyan, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Attack Cost: ${card.attackAPCost} AP',
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Move Speed: ${card.moveSpeed}',
                  style: const TextStyle(color: Colors.green, fontSize: 11),
                ),
              ),
            ],
          ),
          if (card.abilities.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'ABILITIES',
              style: TextStyle(
                color: Colors.purple,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            ...card.abilities.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        a,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getAbilityDescription(a),
                        style: TextStyle(color: Colors.grey[300], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
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

  Color _getRarityColor(int rarity) {
    switch (rarity) {
      case 1:
        return Colors.grey; // Common - grey
      case 2:
        return Colors.blue; // Rare - blue
      case 3:
        return Colors.purple; // Epic - purple
      case 4:
        return Colors.amber; // Legendary - gold
      default:
        return Colors.grey;
    }
  }

  Color _getRarityBgColor(int rarity) {
    switch (rarity) {
      case 1:
        return Colors.grey[800]!; // Common
      case 2:
        return Colors.blue[900]!; // Rare
      case 3:
        return Colors.purple[900]!; // Epic
      case 4:
        return Colors.amber[900]!; // Legendary
      default:
        return Colors.grey[800]!;
    }
  }

  /// Get human-readable description for abilities (TYC3)
  String _getAbilityDescription(String ability) {
    // Parse ability format: name_value (e.g., "fury_2", "shield_1")
    final parts = ability.split('_');
    final baseName = parts[0];
    final value = parts.length > 1 ? parts.sublist(1).join('_') : '';

    switch (baseName) {
      // Offensive abilities
      case 'fury':
        return '+$value damage when attacking';
      case 'cleave':
        return 'Attacks hit ALL enemies on the same tile';
      case 'thorns':
        return 'Reflects $value damage back to attackers';
      case 'first':
        if (ability == 'first_strike') {
          return 'Attacks first, enemy cannot retaliate if killed';
        }
        return 'Strikes first in combat';

      // Defensive abilities
      case 'shield':
        return 'Reduces incoming damage by $value';
      case 'regen':
        return 'Heals $value HP at start of each turn';
      case 'regenerate':
        return 'Regenerates health over time';
      case 'guard':
        return 'Must be attacked before other units on same tile';
      case 'tile':
        if (ability.startsWith('tile_shield')) {
          return 'Provides shield to all allies on same tile';
        }
        return 'Tile-wide effect';

      // Support abilities
      case 'heal':
        return 'Heals friendly cards for $value HP';
      case 'inspire':
        return 'Boosts nearby allies by $value damage';
      case 'fortify':
        return 'Grants $value shield to allies on same tile';
      case 'rally':
        return 'Boosts all allies in lane by $value damage';

      // Movement/Tactical abilities
      case 'flanking':
        return 'Can move to adjacent lanes (left/right)';
      case 'scout':
        return 'Reveals enemy cards in adjacent lanes';
      case 'stealth':
        if (ability == 'stealth_pass') {
          return 'Can move through enemies in middle lane';
        }
        return 'Harder to detect';
      case 'paratrooper':
        return 'Can be placed directly on middle row';

      // Attack abilities
      case 'ranged':
        return 'Can attack from distance without retaliation';
      case 'far':
        if (ability == 'far_attack') {
          return 'Attacks enemies at OTHER tiles in same lane';
        }
        return 'Long-range attack';
      case 'cross':
        if (ability == 'cross_attack') {
          return 'Can attack enemies in adjacent lanes';
        }
        return 'Cross-lane ability';
      case 'long':
        if (ability == 'long_range') {
          return 'Can attack enemies 2 tiles away';
        }
        return 'Extended range';

      default:
        // Try to make unknown abilities readable
        return ability.replaceAll('_', ' ');
    }
  }
}
