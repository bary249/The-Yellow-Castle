import '../models/card.dart';
import 'card_library.dart';

/// Shop item types
enum ShopItemType { card, consumable, relic }

/// A purchasable item in the shop
class ShopItem {
  final String id;
  final String name;
  final String description;
  final int cost;
  final ShopItemType type;
  final GameCard? card; // For card items
  final String? effect; // For consumables/relics

  const ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.type,
    this.card,
    this.effect,
  });
}

/// Shop inventory generator
class ShopInventory {
  /// Generate random shop items for the given act
  static List<ShopItem> generateForAct(int act) {
    final items = <ShopItem>[];

    // Add 3 random cards
    final availableCards = getCardsForAct(act);
    availableCards.shuffle();
    for (int i = 0; i < 3 && i < availableCards.length; i++) {
      final card = availableCards[i];
      items.add(
        ShopItem(
          id: 'card_${card.id}',
          name: card.name,
          description:
              '${card.element} unit - DMG:${card.damage} HP:${card.health}',
          cost: _getCardCost(card),
          type: ShopItemType.card,
          card: card,
        ),
      );
    }

    // Add consumables
    items.addAll(_getConsumables(act));

    // Add a relic
    final relics = getAllRelics()
        .where((r) => !r.id.startsWith('campaign_'))
        .toList();
    relics.shuffle();
    if (relics.isNotEmpty) {
      items.add(relics.first);
    }

    return items;
  }

  static List<ShopItem> getAllConsumables() {
    return [
      ShopItem(
        id: 'heal_potion',
        name: 'Field Medic',
        description: 'Restore 15 HP',
        cost: 20,
        type: ShopItemType.consumable,
        effect: 'heal_15',
      ),
      ShopItem(
        id: 'large_heal_potion',
        name: 'Military Hospital',
        description: 'Restore 30 HP',
        cost: 35,
        type: ShopItemType.consumable,
        effect: 'heal_30',
      ),
    ];
  }

  static List<ShopItem> getAllRelics() {
    return [
      const ShopItem(
        id: 'campaign_map_relic',
        name: 'Map Relic',
        description: '+1 max HP to all Cannons',
        cost: 0,
        type: ShopItemType.relic,
        effect: 'cannon_hp_1',
      ),
      const ShopItem(
        id: 'relic_supply_routes',
        name: 'Supply Routes',
        description: 'Reduce Home Town supply distance penalty by 1 encounter',
        cost: 90,
        type: ShopItemType.relic,
        effect: 'supply_distance_penalty_minus_1',
      ),
      const ShopItem(
        id: 'relic_gold_purse',
        name: 'War Chest',
        description: '+10 gold after each battle',
        cost: 75,
        type: ShopItemType.relic,
        effect: 'battle_gold_10',
      ),
      const ShopItem(
        id: 'relic_armor',
        name: 'Officer\'s Armor',
        description: '+10 max HP',
        cost: 60,
        type: ShopItemType.relic,
        effect: 'max_hp_10',
      ),
      const ShopItem(
        id: 'relic_morale',
        name: 'Battle Standard',
        description: '+1 damage to all units',
        cost: 100,
        type: ShopItemType.relic,
        effect: 'damage_boost_1',
      ),
    ];
  }

  static List<ShopItem> getAllLegendaryRelics() {
    return [
      const ShopItem(
        id: 'legendary_relic_gold_purse',
        name: 'Imperial Treasury',
        description: '+20 gold after each battle',
        cost: 0,
        type: ShopItemType.relic,
        effect: 'battle_gold_20',
      ),
      const ShopItem(
        id: 'legendary_relic_armor',
        name: 'Marshal\'s Armor',
        description: '+20 max HP',
        cost: 0,
        type: ShopItemType.relic,
        effect: 'max_hp_20',
      ),
      const ShopItem(
        id: 'legendary_relic_morale',
        name: 'Imperial Standard',
        description: '+2 damage to all units',
        cost: 0,
        type: ShopItemType.relic,
        effect: 'damage_boost_2',
      ),
    ];
  }

  static List<GameCard> getCardsForAct(int act) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    switch (act) {
      case 1:
        return [
          // Common (rarity 1)
          napoleonVoltigeur(100 + timestamp % 1000),
          napoleonFusilier(101 + timestamp % 1000),
          napoleonFieldCannon(102 + timestamp % 1000),
          napoleonLineInfantry(103 + timestamp % 1000),
          napoleonSapper(104 + timestamp % 1000),
          napoleonDrummerBoy(105 + timestamp % 1000),
          // Rare (rarity 2)
          napoleonGrenadier(110 + timestamp % 1000),
          napoleonCuirassier(111 + timestamp % 1000),
          napoleonHussar(112 + timestamp % 1000),
          napoleonYoungGuard(113 + timestamp % 1000),
          napoleonChasseur(114 + timestamp % 1000),
          napoleonHorseArtillery(115 + timestamp % 1000),
          // Epic (rarity 3)
          napoleonOldGuard(120 + timestamp % 1000),
          napoleonMarshalNey(121 + timestamp % 1000),
          napoleonPolishLancer(122 + timestamp % 1000),
        ];
      case 2:
        return [
          // Common (rarity 1)
          napoleonVoltigeur(100 + timestamp % 1000),
          napoleonFusilier(101 + timestamp % 1000),
          napoleonFieldCannon(102 + timestamp % 1000),
          napoleonSapper(103 + timestamp % 1000),
          // Rare (rarity 2)
          napoleonGrenadier(110 + timestamp % 1000),
          napoleonCuirassier(111 + timestamp % 1000),
          napoleonHussar(112 + timestamp % 1000),
          napoleonHorseArtillery(113 + timestamp % 1000),
          // Epic (rarity 3)
          napoleonOldGuard(120 + timestamp % 1000),
          napoleonGrandBattery(121 + timestamp % 1000),
        ];
      default:
        return [
          // Common (rarity 1)
          napoleonVoltigeur(100 + timestamp % 1000),
          napoleonFusilier(101 + timestamp % 1000),
          napoleonFieldCannon(102 + timestamp % 1000),
          // Rare (rarity 2)
          napoleonGrenadier(110 + timestamp % 1000),
          napoleonCuirassier(111 + timestamp % 1000),
          napoleonHussar(112 + timestamp % 1000),
          // Epic (rarity 3)
          napoleonOldGuard(120 + timestamp % 1000),
          napoleonMarshalNey(121 + timestamp % 1000),
        ];
    }
  }

  static int _getCardCost(GameCard card) {
    // Base cost on card stats
    int cost = 15;
    cost += card.damage * 2;
    cost += card.health;
    if (card.abilities.isNotEmpty) {
      cost += card.abilities.length * 5;
    }
    return cost;
  }

  static List<ShopItem> _getConsumables(int act) {
    return getAllConsumables();
  }
}
