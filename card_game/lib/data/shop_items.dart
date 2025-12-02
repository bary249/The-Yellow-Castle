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
    final availableCards = _getCardsForAct(act);
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
    items.addAll(_getRelics(act));

    return items;
  }

  static List<GameCard> _getCardsForAct(int act) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    switch (act) {
      case 1:
        return [
          napoleonGrenadier(100 + timestamp % 1000),
          napoleonCuirassier(101 + timestamp % 1000),
          napoleonVoltigeur(102 + timestamp % 1000),
          napoleonHussar(103 + timestamp % 1000),
          napoleonFusilier(104 + timestamp % 1000),
          napoleonFieldCannon(105 + timestamp % 1000),
          napoleonLineInfantry(106 + timestamp % 1000),
        ];
      default:
        return [
          napoleonGrenadier(100 + timestamp % 1000),
          napoleonCuirassier(101 + timestamp % 1000),
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
      ShopItem(
        id: 'remove_card',
        name: 'Discharge Papers',
        description: 'Remove a card from your deck',
        cost: 50,
        type: ShopItemType.consumable,
        effect: 'remove_card',
      ),
    ];
  }

  static List<ShopItem> _getRelics(int act) {
    final relics = [
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
    relics.shuffle();
    return [relics.first];
  }
}
