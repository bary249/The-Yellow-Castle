import 'package:flutter/material.dart';

import '../data/shop_items.dart';
import '../models/campaign_state.dart';

class CampaignInventoryScreen extends StatefulWidget {
  final CampaignState campaign;
  final VoidCallback onChanged;
  final Future<bool> Function() onRequestRemoveCard;

  const CampaignInventoryScreen({
    super.key,
    required this.campaign,
    required this.onChanged,
    required this.onRequestRemoveCard,
  });

  @override
  State<CampaignInventoryScreen> createState() =>
      _CampaignInventoryScreenState();
}

class _CampaignInventoryScreenState extends State<CampaignInventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  late final Map<String, ShopItem> _relicById;
  late final Map<String, ShopItem> _consumableById;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final allRelics = [
      ...ShopInventory.getAllRelics(),
      ...ShopInventory.getAllLegendaryRelics(),
    ];
    _relicById = {for (final r in allRelics) r.id: r};
    _consumableById = {
      for (final c in ShopInventory.getAllConsumables()) c.id: c,
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _nameForRelic(String id) => _relicById[id]?.name ?? id;
  String _descForRelic(String id) => _relicById[id]?.description ?? '';

  String _nameForConsumable(String id) => _consumableById[id]?.name ?? id;
  String _descForConsumable(String id) =>
      _consumableById[id]?.description ?? '';

  Future<void> _useActiveConsumable(String id) async {
    final activeCount = widget.campaign.activeConsumables[id] ?? 0;
    if (activeCount <= 0) return;

    if (id == 'heal_potion') {
      if (!widget.campaign.consumeActiveConsumable(id)) return;
      widget.campaign.heal(15);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Healed 15 HP!')));
      }
      return;
    }

    if (id == 'large_heal_potion') {
      if (!widget.campaign.consumeActiveConsumable(id)) return;
      widget.campaign.heal(30);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Healed 30 HP!')));
      }
      return;
    }

    if (id == 'remove_card') {
      final removed = await widget.onRequestRemoveCard();
      if (!removed) {
        widget.onChanged();
        return;
      }

      if (!widget.campaign.consumeActiveConsumable(id)) return;
      widget.onChanged();
      return;
    }

    if (!widget.campaign.consumeActiveConsumable(id)) return;
    widget.onChanged();
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber[300]),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTab() {
    final activeRelics = widget.campaign.activeRelics;
    final activeConsumables = widget.campaign.activeConsumables;

    return ListView(
      children: [
        _sectionHeader('Relics', Icons.auto_awesome),
        if (activeRelics.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No active relics.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          ...activeRelics.map((id) {
            final isLocked = id == 'relic_armor';
            return Card(
              color: Colors.grey[850],
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: const Icon(
                  Icons.auto_awesome,
                  color: Colors.purpleAccent,
                ),
                title: Text(
                  _nameForRelic(id),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _descForRelic(id),
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: isLocked
                    ? const Icon(Icons.lock, color: Colors.white54)
                    : TextButton(
                        onPressed: () {
                          setState(() {
                            widget.campaign.deactivateRelic(id);
                          });
                          widget.onChanged();
                        },
                        child: const Text('Deactivate'),
                      ),
              ),
            );
          }),
        _sectionHeader('Consumables', Icons.medical_services),
        if (activeConsumables.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No active consumables.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          ...activeConsumables.entries.map((e) {
            final id = e.key;
            final count = e.value;
            return Card(
              color: Colors.grey[850],
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: const Icon(
                  Icons.medical_services,
                  color: Colors.greenAccent,
                ),
                title: Text(
                  '${_nameForConsumable(id)}  x$count',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _descForConsumable(id),
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _useActiveConsumable(id),
                      child: const Text('Use'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          widget.campaign.unequipConsumable(id);
                        });
                        widget.onChanged();
                      },
                      child: const Text('Unequip'),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInventoryTab() {
    final ownedRelics = widget.campaign.relics;
    final inactiveRelics = ownedRelics
        .where((r) => !widget.campaign.isRelicActive(r))
        .toList();

    final consumables = widget.campaign.consumables;

    return ListView(
      children: [
        _sectionHeader('Relics', Icons.auto_awesome),
        if (ownedRelics.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No relics owned.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else if (inactiveRelics.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'All owned relics are active.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          ...inactiveRelics.map((id) {
            return Card(
              color: Colors.grey[850],
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: const Icon(
                  Icons.auto_awesome,
                  color: Colors.purpleAccent,
                ),
                title: Text(
                  _nameForRelic(id),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _descForRelic(id),
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      widget.campaign.activateRelic(id);
                    });
                    widget.onChanged();
                  },
                  child: const Text('Activate'),
                ),
              ),
            );
          }),
        _sectionHeader('Consumables', Icons.medical_services),
        if (consumables.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No consumables in inventory.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          ...consumables.entries.map((e) {
            final id = e.key;
            final count = e.value;
            return Card(
              color: Colors.grey[850],
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: const Icon(
                  Icons.medical_services,
                  color: Colors.greenAccent,
                ),
                title: Text(
                  '${_nameForConsumable(id)}  x$count',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _descForConsumable(id),
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      widget.campaign.equipConsumable(id);
                    });
                    widget.onChanged();
                  },
                  child: const Text('Equip'),
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Reserves'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Reserves'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildActiveTab(), _buildInventoryTab()],
      ),
    );
  }
}
