import 'package:flutter/material.dart';
import '../models/card.dart';
import '../models/campaign_state.dart';
import '../data/card_upgrades.dart';

/// Screen shown between acts to allow players to upgrade their cards
class CardUpgradeScreen extends StatefulWidget {
  final CampaignState campaign;
  final int fromAct; // The act we're transitioning FROM (1 or 2)
  final VoidCallback onComplete;

  const CardUpgradeScreen({
    super.key,
    required this.campaign,
    required this.fromAct,
    required this.onComplete,
  });

  @override
  State<CardUpgradeScreen> createState() => _CardUpgradeScreenState();
}

class _CardUpgradeScreenState extends State<CardUpgradeScreen> {
  late CampaignState _campaign;
  final Set<String> _upgradedTypes = {};

  @override
  void initState() {
    super.initState();
    _campaign = widget.campaign;
  }

  /// Get all cards from deck and reserves combined
  List<GameCard> get _allCards {
    return [..._campaign.deck, ..._campaign.inventory];
  }

  /// Get upgradable card types for current act transition
  Map<String, List<GameCard>> get _upgradableTypes {
    return CardUpgrades.getUpgradableTypes(_allCards, widget.fromAct);
  }

  /// Upgrade all cards of a given type
  void _upgradeCardType(String typeName) {
    final cost = _getUpgradeCostForType(typeName);
    if (_campaign.gold < cost) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not enough gold!')));
      return;
    }

    setState(() {
      _campaign.spendGold(cost);

      // Upgrade all cards in deck
      for (int i = 0; i < _campaign.deck.length; i++) {
        final card = _campaign.deck[i];
        if (CardUpgrades.getCardTypeName(card) == typeName &&
            CardUpgrades.canUpgradeAtActTransition(card.tier, widget.fromAct)) {
          _campaign.deck[i] = CardUpgrades.applyUpgrade(card);
        }
      }

      // Upgrade all cards in reserves
      for (int i = 0; i < _campaign.inventory.length; i++) {
        final card = _campaign.inventory[i];
        if (CardUpgrades.getCardTypeName(card) == typeName &&
            CardUpgrades.canUpgradeAtActTransition(card.tier, widget.fromAct)) {
          _campaign.inventory[i] = CardUpgrades.applyUpgrade(card);
        }
      }

      _upgradedTypes.add(typeName);
    });
  }

  /// Get the upgrade cost for a card type (based on first card's tier)
  int _getUpgradeCostForType(String typeName) {
    final cards = _upgradableTypes[typeName];
    if (cards == null || cards.isEmpty) return 0;
    return CardUpgrades.upgradeCost(cards.first.tier);
  }

  @override
  Widget build(BuildContext context) {
    final upgradableTypes = _upgradableTypes;
    final nextAct = widget.fromAct + 1;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text('Upgrade Cards - Act $nextAct'),
        backgroundColor: const Color(0xFF16213E),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF16213E),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entering Act $nextAct',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.fromAct == 1
                          ? 'Upgrade Basic → Advanced (+1 DMG, +2 HP)'
                          : 'Upgrade Advanced → Expert (+1 DMG, +2 HP)',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber[700],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '${_campaign.gold}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Card list
          Expanded(
            child: upgradableTypes.isEmpty
                ? Center(
                    child: Text(
                      'No cards available for upgrade',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: upgradableTypes.length,
                    itemBuilder: (context, index) {
                      final typeName = upgradableTypes.keys.elementAt(index);
                      final cards = upgradableTypes[typeName]!;
                      final sampleCard = cards.first;
                      final upgradedPreview = CardUpgrades.previewUpgrade(
                        sampleCard,
                      );
                      final cost = CardUpgrades.upgradeCost(sampleCard.tier);
                      final canAfford = _campaign.gold >= cost;
                      final alreadyUpgraded = _upgradedTypes.contains(typeName);

                      return Card(
                        color: alreadyUpgraded
                            ? Colors.green[900]
                            : const Color(0xFF2D2D44),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Card name and count
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    typeName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[700],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${cards.length} card${cards.length > 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Stats comparison
                              Row(
                                children: [
                                  // Current stats
                                  Expanded(
                                    child: _buildStatBox(
                                      'Current (${CardUpgrades.tierPrefix(sampleCard.tier)})',
                                      sampleCard,
                                      Colors.grey[700]!,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Icon(
                                      Icons.arrow_forward,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  // Upgraded stats
                                  Expanded(
                                    child: _buildStatBox(
                                      'Upgraded (${CardUpgrades.tierPrefix(upgradedPreview.tier)})',
                                      upgradedPreview,
                                      Colors.green[700]!,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Upgrade button
                              if (alreadyUpgraded)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green[800],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'UPGRADED',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ElevatedButton(
                                  onPressed: canAfford
                                      ? () => _upgradeCardType(typeName)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canAfford
                                        ? Colors.amber[700]
                                        : Colors.grey[700],
                                    minimumSize: const Size(
                                      double.infinity,
                                      48,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.upgrade,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Upgrade All ($cost Gold)',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Continue button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: widget.onComplete,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                minimumSize: const Size(double.infinity, 56),
              ),
              child: Text(
                'Continue to Act $nextAct',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, GameCard card, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatItem(Icons.flash_on, '${card.damage}', Colors.orange),
              const SizedBox(width: 16),
              _buildStatItem(Icons.favorite, '${card.health}', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
