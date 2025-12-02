import 'package:flutter/material.dart';
import '../models/campaign_state.dart';
import '../data/card_library.dart';
import '../data/shop_items.dart';
import 'test_match_screen.dart';
import '../data/hero_library.dart';

/// Campaign screen - Book chapter selection style
class CampaignMapScreen extends StatefulWidget {
  final String leaderId;
  final int act;

  const CampaignMapScreen({super.key, required this.leaderId, this.act = 1});

  @override
  State<CampaignMapScreen> createState() => _CampaignMapScreenState();
}

class _CampaignMapScreenState extends State<CampaignMapScreen> {
  late CampaignState _campaign;
  late EncounterGenerator _generator;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initCampaign();
  }

  void _initCampaign() {
    _generator = EncounterGenerator(act: widget.act);

    // Get starter deck for leader
    final deck = widget.leaderId == 'napoleon'
        ? buildNapoleonStarterDeck()
        : buildStarterCardPool();

    _campaign = CampaignState(
      id: 'campaign_${DateTime.now().millisecondsSinceEpoch}',
      leaderId: widget.leaderId,
      act: widget.act,
      gold: 50,
      health: 50,
      deck: deck,
      startedAt: DateTime.now(),
    );

    // Generate initial choices
    _generateNewChoices();

    setState(() {
      _isLoading = false;
    });
  }

  void _generateNewChoices() {
    if (_campaign.isBossTime) {
      // Time for the boss!
      _campaign.currentChoices = [_generator.generateBoss()];
    } else {
      _campaign.currentChoices = _generator.generateChoices(
        _campaign.encounterNumber,
      );
    }
  }

  void _onEncounterSelected(Encounter encounter) {
    switch (encounter.type) {
      case EncounterType.battle:
      case EncounterType.elite:
        _startBattle(encounter);
        break;
      case EncounterType.boss:
        _startBossBattle(encounter);
        break;
      case EncounterType.shop:
        _openShop(encounter);
        break;
      case EncounterType.rest:
        _openRestSite(encounter);
        break;
      case EncounterType.event:
        _triggerEvent(encounter);
        break;
    }
  }

  void _startBattle(Encounter encounter) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => TestMatchScreen(
          selectedHero: HeroLibrary.napoleon(),
          forceCampaignDeck: true,
          campaignAct: widget.act,
        ),
      ),
    );

    // Handle battle result
    if (result != null) {
      final won = result['won'] as bool? ?? false;
      final crystalDamage = result['crystalDamage'] as int? ?? 0;

      setState(() {
        if (won) {
          _campaign.addGold(encounter.goldReward ?? 15);
          _campaign.completeEncounter();
          _generateNewChoices();
        } else {
          _campaign.takeDamage(crystalDamage);
        }
      });

      if (_campaign.health <= 0) {
        _showGameOver();
      }
    } else {
      // Battle was exited - show retreat dialog
      _showRetreatDialog(encounter);
    }
  }

  void _showRetreatDialog(Encounter encounter) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⚔️ Retreat?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your army is retreating from battle.'),
            const SizedBox(height: 12),
            Text(
              'Cost: 20 gold',
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current gold: ${_campaign.gold}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Return to battle
              _startBattle(encounter);
            },
            child: const Text('Continue Fighting'),
          ),
          TextButton(
            onPressed: _campaign.gold >= 20
                ? () {
                    Navigator.pop(context);
                    setState(() {
                      _campaign.spendGold(20);
                      // Battle NOT completed - same choices remain
                    });
                  }
                : null,
            child: Text(
              'Retreat (-20g)',
              style: TextStyle(
                color: _campaign.gold >= 20 ? Colors.red : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startBossBattle(Encounter encounter) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => TestMatchScreen(
          selectedHero: HeroLibrary.napoleon(),
          forceCampaignDeck: true,
          campaignAct: widget.act,
        ),
      ),
    );

    if (result != null) {
      final won = result['won'] as bool? ?? false;

      if (won) {
        setState(() {
          _campaign.addGold(encounter.goldReward ?? 50);
          _campaign.isVictory = true;
          _campaign.completedAt = DateTime.now();
        });
        _showVictory();
      } else {
        setState(() {
          _campaign.takeDamage(50); // Boss deals massive damage on loss
        });
        if (_campaign.health <= 0) {
          _showGameOver();
        }
      }
    } else {
      _showRetreatDialog(encounter);
    }
  }

  void _openShop(Encounter encounter) {
    final shopItems = ShopInventory.generateForAct(widget.act);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setShopState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFF2D2D2D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store, color: Colors.amber, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            encounter.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            encounter.description,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: Colors.black,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_campaign.gold}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Shop items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: shopItems.length,
                  itemBuilder: (context, index) {
                    final item = shopItems[index];
                    final canAfford = _campaign.gold >= item.cost;

                    return Card(
                      color: Colors.grey[850],
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: _getShopItemIcon(item),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          item.description,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        trailing: ElevatedButton(
                          onPressed: canAfford
                              ? () => _buyItem(item, setShopState)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canAfford
                                ? Colors.amber
                                : Colors.grey,
                          ),
                          child: Text(
                            '${item.cost} 🪙',
                            style: TextStyle(
                              color: canAfford
                                  ? Colors.black
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Leave button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _campaign.completeEncounter();
                        _generateNewChoices();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Leave Shop',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getShopItemIcon(ShopItem item) {
    switch (item.type) {
      case ShopItemType.card:
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getElementColor(item.card?.element ?? 'woods'),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.style, color: Colors.white),
        );
      case ShopItemType.consumable:
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.green[700],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.local_hospital, color: Colors.white),
        );
      case ShopItemType.relic:
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.purple[700],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        );
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
      default:
        return Colors.grey[700]!;
    }
  }

  void _buyItem(ShopItem item, StateSetter setShopState) {
    if (!_campaign.spendGold(item.cost)) return;

    switch (item.type) {
      case ShopItemType.card:
        if (item.card != null) {
          _campaign.addCard(item.card!);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added ${item.name} to your deck!')),
          );
        }
        break;
      case ShopItemType.consumable:
        _applyConsumable(item);
        break;
      case ShopItemType.relic:
        _applyRelic(item);
        break;
    }

    setShopState(() {});
    setState(() {});
  }

  void _applyConsumable(ShopItem item) {
    switch (item.effect) {
      case 'heal_15':
        _campaign.heal(15);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Healed 15 HP!')));
        break;
      case 'heal_30':
        _campaign.heal(30);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Healed 30 HP!')));
        break;
      case 'remove_card':
        _showRemoveCardDialog();
        break;
    }
  }

  void _applyRelic(ShopItem item) {
    // TODO: Implement relic effects (requires campaign state changes)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Acquired ${item.name}! (Effect coming soon)')),
    );
  }

  void _showRemoveCardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove a Card'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _campaign.deck.length,
            itemBuilder: (context, index) {
              final card = _campaign.deck[index];
              return ListTile(
                title: Text(card.name),
                subtitle: Text(
                  '${card.element} - DMG:${card.damage} HP:${card.health}',
                ),
                onTap: () {
                  _campaign.removeCard(card.id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed ${card.name} from deck')),
                  );
                  setState(() {});
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openRestSite(Encounter encounter) {
    final healAmount = (_campaign.maxHealth * 0.3).round();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.local_cafe, color: Colors.green),
            const SizedBox(width: 8),
            Text(encounter.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(encounter.description),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    '${_campaign.health}/${_campaign.maxHealth} HP',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.red),
              title: const Text('Rest'),
              subtitle: Text('Heal $healAmount HP'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _campaign.heal(healAmount);
                  _campaign.completeEncounter();
                  _generateNewChoices();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _triggerEvent(Encounter encounter) {
    // Simple random event
    final goldGain = 15 + (_campaign.encounterNumber * 5);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Text(encounter.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(encounter.description),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Accept their offer'),
              subtitle: Text('Gain $goldGain gold'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _campaign.addGold(goldGain);
                  _campaign.completeEncounter();
                  _generateNewChoices();
                });
              },
            ),
            ListTile(
              title: const Text('Decline politely'),
              subtitle: const Text('Continue on your way'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _campaign.completeEncounter();
                  _generateNewChoices();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showGameOver() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('💀 Campaign Failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your army has been defeated.'),
            const SizedBox(height: 12),
            Text('Encounters completed: ${_campaign.encounterNumber}'),
            Text('Gold earned: ${_campaign.gold}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Return to Menu'),
          ),
        ],
      ),
    );
  }

  void _showVictory() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🏆 Victory!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Act ${widget.act} Complete!'),
            const SizedBox(height: 12),
            Text('Final gold: ${_campaign.gold}'),
            Text('Final health: ${_campaign.health}/${_campaign.maxHealth}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.brown[900]!,
              Colors.brown[800]!,
              Colors.brown[700]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildChapterSelection()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3)),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Act ${widget.act}: Italian Campaign',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Chapter ${_campaign.encounterNumber + 1}',
                  style: TextStyle(color: Colors.amber[300], fontSize: 14),
                ),
                const SizedBox(height: 4),
                // Progress to boss indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _campaign.isBossTime
                          ? '👑 BOSS BATTLE!'
                          : '${_campaign.encountersUntilBoss} encounters until boss',
                      style: TextStyle(
                        color: _campaign.isBossTime
                            ? Colors.red[300]
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: _campaign.isBossTime
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, color: Colors.red, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${_campaign.health}/${_campaign.maxHealth}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monetization_on,
                    color: Colors.amber[400],
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_campaign.gold}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChapterSelection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Title
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              _campaign.isBossTime ? '⚔️ Final Battle ⚔️' : 'Choose Your Path',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'serif',
              ),
            ),
          ),

          // Chapter cards
          Expanded(
            child: ListView.builder(
              itemCount: _campaign.currentChoices.length,
              itemBuilder: (context, index) {
                return _buildChapterCard(
                  _campaign.currentChoices[index],
                  index,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterCard(Encounter encounter, int index) {
    final colors = _getEncounterColors(encounter.type);

    return GestureDetector(
      onTap: () => _onEncounterSelected(encounter),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.brown[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.brown[800]!, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with type icon
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  Icon(colors.icon, color: colors.iconColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      encounter.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textColor,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  if (encounter.goldReward != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: Colors.amber,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '+${encounter.goldReward}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Description
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                encounter.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.brown[800],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            // Difficulty indicator for battles
            if (encounter.difficulty != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.brown[200],
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(6),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Difficulty: ',
                      style: TextStyle(color: Colors.brown[600]),
                    ),
                    ..._buildDifficultyStars(encounter.difficulty!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDifficultyStars(BattleDifficulty difficulty) {
    final stars = switch (difficulty) {
      BattleDifficulty.easy => 1,
      BattleDifficulty.normal => 2,
      BattleDifficulty.hard => 3,
      BattleDifficulty.elite => 4,
      BattleDifficulty.boss => 5,
    };

    return List.generate(5, (i) {
      return Icon(
        i < stars ? Icons.star : Icons.star_border,
        color: i < stars ? Colors.amber : Colors.brown[400],
        size: 18,
      );
    });
  }

  _EncounterColors _getEncounterColors(EncounterType type) {
    switch (type) {
      case EncounterType.battle:
        return _EncounterColors(
          background: Colors.red[100]!,
          icon: Icons.sports_kabaddi,
          iconColor: Colors.red[700]!,
          textColor: Colors.red[900]!,
        );
      case EncounterType.elite:
        return _EncounterColors(
          background: Colors.orange[100]!,
          icon: Icons.local_fire_department,
          iconColor: Colors.orange[700]!,
          textColor: Colors.orange[900]!,
        );
      case EncounterType.boss:
        return _EncounterColors(
          background: Colors.purple[100]!,
          icon: Icons.whatshot,
          iconColor: Colors.purple[700]!,
          textColor: Colors.purple[900]!,
        );
      case EncounterType.shop:
        return _EncounterColors(
          background: Colors.amber[100]!,
          icon: Icons.store,
          iconColor: Colors.amber[700]!,
          textColor: Colors.amber[900]!,
        );
      case EncounterType.rest:
        return _EncounterColors(
          background: Colors.green[100]!,
          icon: Icons.local_cafe,
          iconColor: Colors.green[700]!,
          textColor: Colors.green[900]!,
        );
      case EncounterType.event:
        return _EncounterColors(
          background: Colors.blue[100]!,
          icon: Icons.help_outline,
          iconColor: Colors.blue[700]!,
          textColor: Colors.blue[900]!,
        );
    }
  }
}

class _EncounterColors {
  final Color background;
  final IconData icon;
  final Color iconColor;
  final Color textColor;

  const _EncounterColors({
    required this.background,
    required this.icon,
    required this.iconColor,
    required this.textColor,
  });
}
