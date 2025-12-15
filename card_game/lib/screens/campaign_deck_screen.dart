import 'package:flutter/material.dart';
import '../models/card.dart';
import '../models/campaign_state.dart';
import '../models/deck.dart';

class CampaignDeckScreen extends StatefulWidget {
  final CampaignState campaign;
  final Function(GameCard) onRemoveCard;
  final Function(GameCard)? onAddCard;

  const CampaignDeckScreen({
    super.key,
    required this.campaign,
    required this.onRemoveCard,
    this.onAddCard,
  });

  @override
  State<CampaignDeckScreen> createState() => _CampaignDeckScreenState();
}

class _CampaignDeckScreenState extends State<CampaignDeckScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedElementFilter;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D2D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Campaign Deck',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${widget.campaign.deck.length} Cards | ${widget.campaign.inventory.length} in Reserves',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        actions: [
          _buildFilterButton('Woods', Colors.green),
          _buildFilterButton('Lake', Colors.blue),
          _buildFilterButton('Desert', Colors.orange),
          if (_selectedElementFilter != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() => _selectedElementFilter = null),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(
              icon: const Icon(Icons.style),
              text: 'Deck (${widget.campaign.deck.length})',
            ),
            Tab(
              icon: const Icon(Icons.inventory_2),
              text: 'Reserves (${widget.campaign.inventory.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDeckTab(), _buildInventoryTab()],
      ),
    );
  }

  Widget _buildDeckTab() {
    final filteredCards = _selectedElementFilter == null
        ? widget.campaign.deck
        : widget.campaign.deck
              .where((c) => c.element == _selectedElementFilter)
              .toList();

    filteredCards.sort((a, b) => a.name.compareTo(b.name));

    if (filteredCards.isEmpty) {
      return Center(
        child: Text(
          'No cards found',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filteredCards.length,
      itemBuilder: (context, index) {
        return _buildCardItem(filteredCards[index], inDeck: true);
      },
    );
  }

  Widget _buildInventoryTab() {
    final filteredCards = _selectedElementFilter == null
        ? widget.campaign.inventory
        : widget.campaign.inventory
              .where((c) => c.element == _selectedElementFilter)
              .toList();

    filteredCards.sort((a, b) => a.name.compareTo(b.name));

    if (filteredCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'Reserves are empty',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Cards removed from deck will appear here',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filteredCards.length,
      itemBuilder: (context, index) {
        return _buildCardItem(filteredCards[index], inDeck: false);
      },
    );
  }

  Widget _buildFilterButton(String element, MaterialColor color) {
    final isSelected = _selectedElementFilter == element;
    return IconButton(
      icon: Icon(
        Icons.circle,
        color: isSelected ? color[400] : color[800],
        size: isSelected ? 24 : 16,
      ),
      onPressed: () => setState(() {
        _selectedElementFilter = isSelected ? null : element;
      }),
      tooltip: 'Filter by $element',
    );
  }

  Widget _buildCardItem(GameCard card, {bool inDeck = true}) {
    return GestureDetector(
      onTap: () => _showCardDetails(card, inDeck: inDeck),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _getElementColor(card.element), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar (Cost + Element)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _getElementColor(card.element).withOpacity(0.2),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.bolt, size: 14, color: Colors.amber[300]),
                  Icon(
                    _getElementIcon(card.element),
                    size: 14,
                    color: _getElementColor(card.element),
                  ),
                ],
              ),
            ),

            // Image / Icon placeholder
            Expanded(
              child: Center(
                child: Icon(
                  _getTypeIcon(card),
                  size: 32,
                  color: Colors.white70,
                ),
              ),
            ),

            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                card.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Abilities (Icons)
            if (card.abilities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  runSpacing: 2,
                  children: card.abilities.take(3).map((a) {
                    return Icon(
                      _getAbilityIcon(a),
                      size: 10,
                      color: Colors.amber[300],
                    );
                  }).toList(),
                ),
              ),

            // Stats
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(
                    Icons.local_fire_department,
                    '${card.damage}',
                    Colors.orange,
                  ),
                  _buildStat(Icons.favorite, '${card.health}', Colors.red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showCardDetails(GameCard card, {bool inDeck = true}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 300,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              const SizedBox(height: 16),

              // Stats Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDetailStat(
                    'ATK',
                    '${card.damage}',
                    Icons.local_fire_department,
                    Colors.orange,
                  ),
                  _buildDetailStat(
                    'HP',
                    '${card.health}',
                    Icons.favorite,
                    Colors.red,
                  ),
                  _buildDetailStat(
                    'AP',
                    '${card.maxAP}',
                    Icons.bolt,
                    Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Attack Type (Melee/Ranged/Long Range)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getAttackTypeColor(card),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getAttackTypeIcon(card),
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getAttackTypeLabel(card),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Abilities
              if (card.abilities.isNotEmpty) ...[
                const Text(
                  'Abilities',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: card.abilities
                      .map(
                        (a) => Tooltip(
                          message: _getAbilityDescription(a),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber[800],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              a.replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                // Ability descriptions
                ...card.abilities.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _getAbilityIcon(a),
                          color: Colors.amber[300],
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _getAbilityDescription(a),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Element Info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getElementColor(card.element).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getElementColor(card.element).withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getElementIcon(card.element),
                      color: _getElementColor(card.element),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${card.element ?? "Neutral"} Unit',
                      style: TextStyle(
                        color: _getElementColor(card.element),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Button (Remove or Add)
              SizedBox(
                width: double.infinity,
                child: inDeck
                    ? ElevatedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove from Deck'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[900],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          if (widget.campaign.deck.length <= Deck.minDeckSize) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Deck must have at least ${Deck.minDeckSize} cards!',
                                ),
                              ),
                            );
                            return;
                          }
                          widget.onRemoveCard(card);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Removed ${card.name} from deck'),
                            ),
                          );
                          setState(() {});
                        },
                      )
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add to Deck'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          widget.campaign.addCardFromInventory(card.id);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added ${card.name} to deck'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          setState(() {});
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
      ],
    );
  }

  Color _getElementColor(String? element) {
    switch (element?.toLowerCase()) {
      case 'woods':
        return Colors.green;
      case 'lake':
        return Colors.blue;
      case 'desert':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getElementIcon(String? element) {
    switch (element?.toLowerCase()) {
      case 'woods':
        return Icons.forest;
      case 'lake':
        return Icons.water_drop;
      case 'desert':
        return Icons.wb_sunny;
      default:
        return Icons.help_outline;
    }
  }

  IconData _getTypeIcon(GameCard card) {
    if (card.abilities.contains('cavalry')) return Icons.directions_run;
    if (card.abilities.contains('archer') || card.isRanged)
      return Icons.gps_fixed;
    if (card.abilities.contains('cannon')) return Icons.circle;
    if (card.abilities.contains('shield_guard')) return Icons.shield;
    return Icons.person;
  }

  // Attack type helpers - distinguishes Melee, Ranged (no retaliation), Long Range (2 tiles)
  String _getAttackType(GameCard card) {
    // Long range (cannon): attackRange >= 2 or has 'long_range' or 'far_attack' ability
    if (card.isLongRange || card.abilities.contains('far_attack')) {
      return 'long_range';
    }
    // Ranged (archer/hussar): has 'ranged' ability - no retaliation but range 1
    if (card.isRanged) return 'ranged';
    // Default: melee
    return 'melee';
  }

  Color _getAttackTypeColor(GameCard card) {
    switch (_getAttackType(card)) {
      case 'long_range':
        return Colors.deepOrange[700]!; // Cannon = deep orange (explosive)
      case 'ranged':
        return Colors.teal[600]!; // Archer = teal (swift, precise)
      default:
        return Colors.red[700]!; // Melee = red (close combat)
    }
  }

  IconData _getAttackTypeIcon(GameCard card) {
    switch (_getAttackType(card)) {
      case 'long_range':
        return Icons.gps_fixed; // Target/crosshair for cannon
      case 'ranged':
        return Icons.arrow_forward; // Arrow for ranged
      default:
        return Icons.sports_martial_arts; // Sword for melee
    }
  }

  String _getAttackTypeLabel(GameCard card) {
    switch (_getAttackType(card)) {
      case 'long_range':
        return 'LONG RANGE (2 tiles)';
      case 'ranged':
        return 'RANGED (No Retaliation)';
      default:
        return 'MELEE';
    }
  }

  IconData _getAbilityIcon(String ability) {
    switch (ability) {
      case 'guard':
        return Icons.security;
      case 'scout':
        return Icons.visibility;
      case 'long_range':
        return Icons.gps_fixed;
      case 'ranged':
        return Icons.arrow_forward;
      case 'flanking':
        return Icons.swap_horiz;
      case 'cavalry':
        return Icons.directions_run;
      case 'pikeman':
        return Icons.vertical_align_top;
      case 'archer':
        return Icons.arrow_forward;
      default:
        if (ability.startsWith('inspire')) return Icons.music_note;
        if (ability.startsWith('fury')) return Icons.local_fire_department;
        if (ability.startsWith('shield')) return Icons.shield;
        if (ability.startsWith('thorns')) return Icons.grass;
        if (ability.startsWith('regen')) return Icons.healing;
        return Icons.star;
    }
  }

  String _getAbilityDescription(String ability) {
    switch (ability) {
      case 'guard':
        return 'Must be defeated before other units can be targeted.';
      case 'scout':
        return 'Reveals enemy cards in adjacent lanes.';
      case 'long_range':
        return 'Can attack enemies 2 tiles away.';
      case 'ranged':
        return 'Attacks without triggering retaliation from melee units.';
      case 'flanking':
        return 'Can move to adjacent lanes (left/right).';
      case 'cavalry':
        return '+4 damage vs Archers. Weak to Pikemen.';
      case 'pikeman':
        return '+4 damage and retaliation vs Cavalry.';
      case 'archer':
        return 'Ranged unit. -4 retaliation when attacked by melee.';
      default:
        if (ability.startsWith('inspire')) {
          final value = ability.replaceAll(RegExp(r'[^0-9]'), '');
          return '+$value damage to all friendly units in this lane.';
        }
        if (ability.startsWith('fury')) {
          final value = ability.replaceAll(RegExp(r'[^0-9]'), '');
          return '+$value damage on attack and retaliation.';
        }
        if (ability.startsWith('shield')) {
          final value = ability.replaceAll(RegExp(r'[^0-9]'), '');
          return 'Reduces incoming damage by $value.';
        }
        if (ability.startsWith('thorns')) {
          final value = ability.replaceAll(RegExp(r'[^0-9]'), '');
          return 'Deals $value damage to attackers after combat.';
        }
        if (ability.startsWith('regen')) {
          final value = ability.replaceAll(RegExp(r'[^0-9]'), '');
          return 'Regenerates $value HP at the start of each turn.';
        }
        return ability.replaceAll('_', ' ');
    }
  }
}
