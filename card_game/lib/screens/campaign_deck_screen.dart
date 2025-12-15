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

  final Set<String> _selectedAttackTypeFilters = {};
  final Set<int> _selectedRarityFilters = {};
  final Set<String> _selectedAbilityFilters = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  List<GameCard> _applyFilters(List<GameCard> cards) {
    Iterable<GameCard> filtered = cards;

    if (_selectedElementFilter != null) {
      filtered = filtered.where((c) => c.element == _selectedElementFilter);
    }

    if (_selectedAttackTypeFilters.isNotEmpty) {
      filtered = filtered.where(
        (c) => _selectedAttackTypeFilters.contains(_attackTypeFilterKey(c)),
      );
    }

    if (_selectedRarityFilters.isNotEmpty) {
      filtered = filtered.where(
        (c) => _selectedRarityFilters.contains(c.rarity),
      );
    }

    if (_selectedAbilityFilters.isNotEmpty) {
      filtered = filtered.where(
        (c) => _selectedAbilityFilters.every((a) => c.abilities.contains(a)),
      );
    }

    return filtered.toList();
  }

  String _attackTypeFilterKey(GameCard card) {
    if (card.isLongRange ||
        card.attackRange >= 2 ||
        card.abilities.contains('long_range') ||
        card.abilities.contains('far_attack')) {
      return 'far_attack';
    }
    if (card.isRanged) return 'ranged';
    return 'melee';
  }

  List<String> _allAbilitiesForFilters() {
    final allCards = <GameCard>[
      ...widget.campaign.deck,
      ...widget.campaign.inventory,
      ...widget.campaign.destroyedDeckCards,
    ];
    final abilities = <String>{};
    for (final c in allCards) {
      abilities.addAll(c.abilities);
    }
    final list = abilities.toList()..sort();
    return list;
  }

  Future<void> _showAdvancedFiltersSheet() async {
    final allAbilities = _allAbilitiesForFilters();
    final selectedAttackTypes = Set<String>.from(_selectedAttackTypeFilters);
    final selectedRarities = Set<int>.from(_selectedRarityFilters);
    final selectedAbilities = Set<String>.from(_selectedAbilityFilters);

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Widget sectionTitle(String title) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.amber[300],
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          const Text(
                            'Filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                selectedAttackTypes.clear();
                                selectedRarities.clear();
                                selectedAbilities.clear();
                              });
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),

                    sectionTitle('Attack Type'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Melee'),
                            selected: selectedAttackTypes.contains('melee'),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedAttackTypes.add('melee')
                                  : selectedAttackTypes.remove('melee');
                            }),
                          ),
                          FilterChip(
                            label: const Text('Ranged'),
                            selected: selectedAttackTypes.contains('ranged'),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedAttackTypes.add('ranged')
                                  : selectedAttackTypes.remove('ranged');
                            }),
                          ),
                          FilterChip(
                            label: const Text('Far Attack'),
                            selected: selectedAttackTypes.contains(
                              'far_attack',
                            ),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedAttackTypes.add('far_attack')
                                  : selectedAttackTypes.remove('far_attack');
                            }),
                          ),
                        ],
                      ),
                    ),

                    sectionTitle('Rarity'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('R1'),
                            selected: selectedRarities.contains(1),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedRarities.add(1)
                                  : selectedRarities.remove(1);
                            }),
                          ),
                          FilterChip(
                            label: const Text('R2'),
                            selected: selectedRarities.contains(2),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedRarities.add(2)
                                  : selectedRarities.remove(2);
                            }),
                          ),
                          FilterChip(
                            label: const Text('R3'),
                            selected: selectedRarities.contains(3),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedRarities.add(3)
                                  : selectedRarities.remove(3);
                            }),
                          ),
                          FilterChip(
                            label: const Text('R4'),
                            selected: selectedRarities.contains(4),
                            onSelected: (v) => setModalState(() {
                              v
                                  ? selectedRarities.add(4)
                                  : selectedRarities.remove(4);
                            }),
                          ),
                        ],
                      ),
                    ),

                    sectionTitle('Abilities'),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allAbilities.map((a) {
                            return FilterChip(
                              label: Text(a),
                              selected: selectedAbilities.contains(a),
                              onSelected: (v) => setModalState(() {
                                v
                                    ? selectedAbilities.add(a)
                                    : selectedAbilities.remove(a);
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Apply'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (result == true) {
      setState(() {
        _selectedAttackTypeFilters
          ..clear()
          ..addAll(selectedAttackTypes);
        _selectedRarityFilters
          ..clear()
          ..addAll(selectedRarities);
        _selectedAbilityFilters
          ..clear()
          ..addAll(selectedAbilities);
      });
    }
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
              '${widget.campaign.deck.length} Cards | ${widget.campaign.inventory.length} Reserves | ${widget.campaign.destroyedDeckCards.length} Fallen',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        actions: [
          _buildFilterButton('Woods', Colors.green),
          _buildFilterButton('Lake', Colors.blue),
          _buildFilterButton('Desert', Colors.orange),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showAdvancedFiltersSheet,
          ),
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
            Tab(
              icon: const Icon(Icons.sentiment_very_dissatisfied),
              text: 'Fallen (${widget.campaign.destroyedDeckCards.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDeckTab(), _buildInventoryTab(), _buildDeceasedTab()],
      ),
    );
  }

  Widget _buildDeckTab() {
    final filteredCards = _applyFilters(widget.campaign.deck);

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
    final filteredCards = _applyFilters(widget.campaign.inventory);

    final pendingDeliveries = widget.campaign.pendingCardDeliveries;

    filteredCards.sort((a, b) => a.name.compareTo(b.name));

    if (filteredCards.isEmpty && pendingDeliveries.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pendingDeliveries.isNotEmpty) ...[
          Text(
            'Incoming Deliveries',
            style: TextStyle(
              color: Colors.amber[300],
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...pendingDeliveries.map((d) {
            final remaining = widget.campaign.encountersUntilDeliveryArrives(d);
            final etaText = remaining == 0
                ? 'Arriving now'
                : (remaining == 1
                      ? 'Arrives in 1 encounter'
                      : 'Arrives in $remaining encounters');

            return Card(
              color: Colors.grey[850],
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(
                  Icons.local_shipping,
                  color: Colors.greenAccent,
                ),
                title: Text(
                  d.card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  etaText,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        if (filteredCards.isNotEmpty) ...[
          Text(
            'Reserves',
            style: TextStyle(
              color: Colors.amber[300],
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addAllAvailableReservesToDeck,
              icon: const Icon(Icons.playlist_add),
              label: Text(
                'Add all available to deck (${_availableReserveCount()})',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
          ),
        ],
      ],
    );
  }

  int _availableReserveCount() {
    return widget.campaign.inventory
        .where((c) => !widget.campaign.isCardGated(c.id))
        .length;
  }

  void _addAllAvailableReservesToDeck() {
    final toAdd = widget.campaign.inventory
        .where((c) => !widget.campaign.isCardGated(c.id))
        .toList();

    if (toAdd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available reserve cards to add.')),
      );
      return;
    }

    for (final c in toAdd) {
      if (widget.onAddCard != null) {
        widget.onAddCard!(c);
      } else {
        widget.campaign.addCardFromInventory(c.id);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${toAdd.length} reserve cards to deck'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {});
  }

  Widget _buildDeceasedTab() {
    final filteredCards = _applyFilters(widget.campaign.destroyedDeckCards);

    if (filteredCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sentiment_satisfied_alt,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No fallen soldiers',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Units destroyed in battle appear here',
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
        return _buildDeceasedCardItem(filteredCards[index]);
      },
    );
  }

  Widget _buildDeceasedCardItem(GameCard card) {
    return GestureDetector(
      onTap: () => _showDeceasedCardDetails(card),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[900]!, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Opacity(
              opacity: 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red[900]?.withOpacity(0.3),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.bolt, size: 14, color: Colors.grey[600]),
                        Icon(
                          _getElementIcon(card.element),
                          size: 14,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Icon(
                        _getTypeIcon(card),
                        size: 32,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      card.name,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat(
                          Icons.local_fire_department,
                          '${card.damage}',
                          Colors.grey,
                        ),
                        _buildStat(
                          Icons.favorite,
                          '${card.health}',
                          Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red[900],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.sentiment_very_dissatisfied,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeceasedCardDetails(GameCard card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(Icons.sentiment_very_dissatisfied, color: Colors.red[400]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                card.name,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This unit was lost in battle.',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
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
    final isGated = !inDeck && widget.campaign.isCardGated(card.id);

    return GestureDetector(
      onTap: () => _showCardDetails(card, inDeck: inDeck),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isGated ? Colors.orange : _getElementColor(card.element),
                width: 2,
              ),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 4,
                    ),
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
          if (isGated)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.orange[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.lock, color: Colors.white, size: 12),
              ),
            ),
        ],
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
                    : _buildReserveActionButton(card),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const int _gatedCardUnlockCost = 15;

  Widget _buildReserveActionButton(GameCard card) {
    final isGated = widget.campaign.isCardGated(card.id);

    if (!isGated) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add to Deck'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () {
          if (widget.onAddCard != null) {
            widget.onAddCard!(card);
          } else {
            widget.campaign.addCardFromInventory(card.id);
          }
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${card.name} to deck'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        },
      );
    }

    final remaining = widget.campaign.encountersUntilCardUnlocked(card.id);
    final canAfford = widget.campaign.gold >= _gatedCardUnlockCost;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange[900]?.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange[700]!),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remaining == 1
                      ? 'Locked – available in 1 encounter'
                      : 'Locked – available in $remaining encounters',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.monetization_on, size: 16),
                label: Text('Pay $_gatedCardUnlockCost Gold'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford
                      ? Colors.amber[700]
                      : Colors.grey[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: canAfford
                    ? () {
                        widget.campaign.unlockGatedCardWithGold(
                          card.id,
                          _gatedCardUnlockCost,
                        );
                        if (widget.onAddCard != null) {
                          widget.onAddCard!(card);
                        } else {
                          widget.campaign.addCardFromInventory(card.id);
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Paid $_gatedCardUnlockCost Gold – ${card.name} added to deck',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() {});
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
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
    if (card.abilities.contains('archer') || card.isRanged) {
      return Icons.gps_fixed;
    }
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
