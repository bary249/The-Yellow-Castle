import '../models/card.dart';

/// Card upgrade system
/// - B -> A costs 25g (+1 dmg, +2 hp) - available Act 1 -> Act 2
/// - A -> E costs 50g (+1 dmg, +2 hp) - available Act 2 -> Act 3

class CardUpgrades {
  /// Get the cost to upgrade a card to the next tier
  static int upgradeCost(CardTier currentTier) {
    switch (currentTier) {
      case CardTier.basic:
        return 25; // B -> A
      case CardTier.advanced:
        return 50; // A -> E
      case CardTier.expert:
        return 0; // Already max tier
    }
  }

  /// Check if a card can be upgraded at the given act transition
  /// Act 1 -> Act 2: Only B -> A allowed
  /// Act 2 -> Act 3: Only A -> E allowed
  static bool canUpgradeAtActTransition(CardTier tier, int fromAct) {
    switch (fromAct) {
      case 1: // Act 1 -> Act 2
        return tier == CardTier.basic;
      case 2: // Act 2 -> Act 3
        return tier == CardTier.advanced;
      default:
        return false;
    }
  }

  /// Get the next tier for a card
  static CardTier? nextTier(CardTier current) {
    switch (current) {
      case CardTier.basic:
        return CardTier.advanced;
      case CardTier.advanced:
        return CardTier.expert;
      case CardTier.expert:
        return null; // Already max tier
    }
  }

  /// Get display name for a tier
  static String tierName(CardTier tier) {
    switch (tier) {
      case CardTier.basic:
        return 'Basic';
      case CardTier.advanced:
        return 'Advanced';
      case CardTier.expert:
        return 'Expert';
    }
  }

  /// Get short tier prefix
  static String tierPrefix(CardTier tier) {
    switch (tier) {
      case CardTier.basic:
        return 'B';
      case CardTier.advanced:
        return 'A';
      case CardTier.expert:
        return 'E';
    }
  }

  /// Calculate upgraded stats for a card
  /// Returns a preview of the upgraded card (without actually upgrading)
  static GameCard previewUpgrade(GameCard card) {
    final nextT = nextTier(card.tier);
    if (nextT == null) return card;

    // Upgrade stats: +1 damage, +2 health per tier
    return card.copyWith(
      tier: nextT,
      damage: card.damage + 1,
      health: card.health + 2,
    );
  }

  /// Apply upgrade to a card (creates a new upgraded card)
  static GameCard applyUpgrade(GameCard card) {
    return previewUpgrade(card);
  }

  /// Get unique card type name (for grouping cards of the same type)
  /// This strips the unique ID suffix and uses just the base name
  static String getCardTypeName(GameCard card) {
    // Use the card name as the type identifier
    return card.name;
  }

  /// Group cards by their type name
  static Map<String, List<GameCard>> groupByType(List<GameCard> cards) {
    final groups = <String, List<GameCard>>{};
    for (final card in cards) {
      final typeName = getCardTypeName(card);
      groups.putIfAbsent(typeName, () => []);
      groups[typeName]!.add(card);
    }
    return groups;
  }

  /// Get upgradable card types at a given act transition
  /// Returns map of type name -> list of cards of that type
  static Map<String, List<GameCard>> getUpgradableTypes(
    List<GameCard> cards,
    int fromAct,
  ) {
    final groups = groupByType(cards);
    final upgradable = <String, List<GameCard>>{};

    for (final entry in groups.entries) {
      // Check if any card of this type can be upgraded
      final upgradableCards = entry.value
          .where((c) => canUpgradeAtActTransition(c.tier, fromAct))
          .toList();
      if (upgradableCards.isNotEmpty) {
        upgradable[entry.key] = upgradableCards;
      }
    }

    return upgradable;
  }
}
