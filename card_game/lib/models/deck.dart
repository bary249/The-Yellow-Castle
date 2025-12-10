import 'dart:math';
import 'card.dart';
import '../data/card_library.dart';

/// Represents a player's deck of 20-25 cards
class Deck {
  static const int minDeckSize = 20;
  static const int maxDeckSize = 25;

  final String id;
  final String name;
  final List<GameCard> _cards;

  Deck({
    required this.id,
    required this.name,
    required List<GameCard> cards,
    bool skipValidation = false,
  }) : _cards = cards.map((c) => c.copy()).toList() {
    if (!skipValidation) {
      assert(
        cards.length >= minDeckSize && cards.length <= maxDeckSize,
        'Deck must have $minDeckSize-$maxDeckSize cards (got ${cards.length})',
      );
    }
  }

  /// Get remaining cards in deck
  List<GameCard> get cards => List.unmodifiable(_cards);

  /// How many cards left in deck
  int get remainingCards => _cards.length;

  /// Check if deck is empty
  bool get isEmpty => _cards.isEmpty;

  /// Shuffle the deck
  void shuffle() {
    _cards.shuffle(Random());
  }

  /// Replace all cards in the deck (for online sync)
  void replaceCards(List<GameCard> newCards) {
    _cards.clear();
    _cards.addAll(newCards.map((c) => c.copy()));
  }

  /// Draw a single card from the top
  GameCard? drawCard() {
    if (_cards.isEmpty) return null;
    return _cards.removeAt(0);
  }

  /// Draw multiple cards
  List<GameCard> drawCards(int count) {
    final drawnCards = <GameCard>[];
    for (int i = 0; i < count && _cards.isNotEmpty; i++) {
      final card = drawCard();
      if (card != null) drawnCards.add(card);
    }
    return drawnCards;
  }

  /// Reset deck to original state (for new match)
  void reset(List<GameCard> originalCards) {
    _cards.clear();
    _cards.addAll(originalCards.map((c) => c.copy()));
  }

  /// Create a basic starter deck for testing
  factory Deck.starter({String? playerId}) {
    final cards = buildStarterCardPool();
    return Deck(
      id: 'starter_${playerId ?? "default"}',
      name: 'Terrain Starter Deck',
      cards: cards,
    );
  }

  /// Create Napoleon's campaign starter deck
  factory Deck.napoleon({String? playerId}) {
    final cards = buildNapoleonStarterDeck();
    return Deck(
      id: 'napoleon_${playerId ?? "default"}',
      name: "Napoleon's Army",
      cards: cards,
    );
  }

  /// Create Saladin's Desert Warriors deck
  factory Deck.saladin({String? playerId}) {
    final cards = buildSaladinStarterDeck();
    return Deck(
      id: 'saladin_${playerId ?? "default"}',
      name: "Saladin's Warriors",
      cards: cards,
    );
  }

  /// Create Admiral Nelson's Royal Navy deck
  factory Deck.nelson({String? playerId}) {
    final cards = buildNelsonStarterDeck();
    return Deck(
      id: 'nelson_${playerId ?? "default"}',
      name: "Nelson's Fleet",
      cards: cards,
    );
  }

  /// Create Act 1 enemy deck (Austrian forces - Italian Campaign)
  /// Now associated with Archduke Charles
  factory Deck.act1Enemy({String? playerId}) {
    return Deck.archduke(playerId: playerId);
  }

  /// Create Archduke Charles's Austrian Army deck
  factory Deck.archduke({String? playerId}) {
    final cards = buildAct1EnemyDeck();
    return Deck(
      id: 'archduke_${playerId ?? "default"}',
      name: 'Austrian Forces',
      cards: cards,
    );
  }

  /// Create a deck from saved cards (must have 20-25 cards)
  factory Deck.fromCards({
    required String playerId,
    required List<GameCard> cards,
    String name = 'Custom Deck',
  }) {
    // Ensure we have at least minDeckSize cards
    if (cards.length < minDeckSize) {
      throw ArgumentError(
        'Deck must have at least $minDeckSize cards (got ${cards.length})',
      );
    }

    // Cap at maxDeckSize
    final deckCards = cards.length > maxDeckSize
        ? cards.take(maxDeckSize).toList()
        : List<GameCard>.from(cards);

    return Deck(id: 'custom_$playerId', name: name, cards: deckCards);
  }

  /// Create a deck from card names (for online sync)
  /// Looks up each card name in the card library and creates instances
  factory Deck.fromCardNames({
    required String playerId,
    required List<String> cardNames,
    String name = 'Synced Deck',
  }) {
    final cards = <GameCard>[];
    final cardCounts = <String, int>{};

    for (final cardName in cardNames) {
      // Track how many of each card we've created (for unique IDs)
      cardCounts[cardName] = (cardCounts[cardName] ?? 0) + 1;
      final index = cardCounts[cardName]!;

      final card = createCardByName(cardName, index);
      if (card != null) {
        cards.add(card);
      } else {
        // Fallback: create a generic card if name not found
        cards.add(
          GameCard(
            id: '${cardName.toLowerCase().replaceAll(' ', '_')}_$index',
            name: cardName,
            damage: 5,
            health: 10,
            element: 'Woods',
            rarity: 1,
          ),
        );
      }
    }

    // Ensure minimum deck size
    if (cards.length < minDeckSize) {
      throw ArgumentError(
        'Deck must have at least $minDeckSize cards (got ${cards.length})',
      );
    }

    return Deck(
      id: 'synced_$playerId',
      name: name,
      cards: cards.take(maxDeckSize).toList(),
    );
  }

  /// Helper to create a card by name (public for use by other services)
  static GameCard? createCardByName(String name, int index) {
    switch (name) {
      // Scout
      case 'Scout':
        return scoutUnit(index);
      // Common cards
      case 'Desert Quick Strike':
        return desertQuickStrike(index);
      case 'Lake Quick Strike':
        return lakeQuickStrike(index);
      case 'Woods Quick Strike':
        return woodsQuickStrike(index);
      case 'Desert Warrior':
        return desertWarrior(index);
      case 'Lake Warrior':
        return lakeWarrior(index);
      case 'Woods Warrior':
        return woodsWarrior(index);
      case 'Desert Tank':
        return desertTank(index);
      case 'Lake Tank':
        return lakeTank(index);
      case 'Woods Tank':
        return woodsTank(index);
      // Archers (ranged)
      case 'Desert Archer':
        return desertArcher(index);
      case 'Lake Archer':
        return lakeArcher(index);
      case 'Woods Archer':
        return woodsArcher(index);
      // Cannons (long range)
      case 'Desert Cannon':
        return desertCannon(index);
      case 'Lake Cannon':
        return lakeCannon(index);
      case 'Woods Cannon':
        return woodsCannon(index);
      // Rare cards
      case 'Desert Elite Striker':
        return desertEliteStriker(index);
      case 'Lake Elite Striker':
        return lakeEliteStriker(index);
      case 'Woods Elite Striker':
        return woodsEliteStriker(index);
      case 'Desert Veteran':
        return desertVeteran(index);
      case 'Lake Veteran':
        return lakeVeteran(index);
      case 'Woods Veteran':
        return woodsVeteran(index);
      // Support cards
      case 'Lake Shield Totem':
        return lakeShieldTotem(index);
      case 'Desert War Banner':
        return desertWarBanner(index);
      case 'Woods Healing Tree':
        return woodsHealingTree(index);
      // Epic cards
      case 'Desert Berserker':
        return desertBerserker(index);
      case 'Lake Guardian':
        return lakeGuardian(index);
      case 'Woods Sentinel':
        return woodsSentinel(index);
      case 'Desert Shadow Scout':
        return desertShadowScout(index);
      case 'Lake Mist Weaver':
        return lakeMistWeaver(index);
      case 'Woods Shroud Walker':
        return woodsShroudWalker(index);
      // Nelson cards
      case 'Boarding Party':
        return lakeQuickStrike(index).copyWith(name: 'Boarding Party');
      case 'Royal Marine':
        return lakeWarrior(index).copyWith(name: 'Royal Marine');
      case 'Ironclad Hull':
        return lakeTank(index).copyWith(name: 'Ironclad Hull');
      case 'Naval Gunner':
        return lakeArcher(index).copyWith(name: 'Naval Gunner');
      case 'First Mate':
        return lakeEliteStriker(index).copyWith(name: 'First Mate');
      case 'Veteran Sailor':
        return lakeVeteran(index).copyWith(name: 'Veteran Sailor');
      case 'Ship Cannon':
        return lakeCannon(index).copyWith(name: 'Ship Cannon');
      case 'Line Marine':
        return lakeWarrior(index).copyWith(name: 'Line Marine');
      case 'Elite Guard':
        return lakeVeteran(index).copyWith(name: 'Elite Guard');
      case 'Supply Ship':
        return lakeShieldTotem(index).copyWith(name: 'Supply Ship');
      case 'Deck Gunner':
        return lakeArcher(index).copyWith(name: 'Deck Gunner');
      case 'Musketeer':
        return lakeArcher(index).copyWith(name: 'Musketeer');
      case 'Naval Cannon':
        return lakeCannon(index).copyWith(name: 'Naval Cannon');

      // Saladin cards
      case 'Desert Raider':
        return desertQuickStrike(index).copyWith(name: 'Desert Raider');
      case 'Light Infantry':
        return desertWarrior(index).copyWith(name: 'Light Infantry');
      case 'Skirmisher':
        return desertArcher(index).copyWith(name: 'Skirmisher');
      case 'Swift Lancer':
        return desertEliteStriker(index).copyWith(name: 'Swift Lancer');
      case 'Siege Catapult':
        return desertCannon(index).copyWith(name: 'Siege Catapult');

      // Archduke cards
      case 'Alpine Guard':
        return woodsTank(index).copyWith(name: 'Alpine Guard');
      case 'Forest Ranger':
        return woodsWarrior(index).copyWith(name: 'Forest Ranger');
      case 'Mountain Hunter':
        return woodsVeteran(index).copyWith(name: 'Mountain Hunter');
      case 'Field Hospital':
        return woodsHealingTree(index).copyWith(name: 'Field Hospital');
      case 'Mountain Gun':
        return woodsCannon(index).copyWith(name: 'Mountain Gun');

      // Napoleon cards
      case 'Voltigeur':
        return napoleonVoltigeur(index);
      case 'Fusilier':
        return napoleonFusilier(index);
      case 'Line Infantry':
        return napoleonLineInfantry(index);
      case 'Field Cannon':
        return napoleonFieldCannon(index);
      case 'Sapper':
        return napoleonSapper(index);
      case 'Drummer Boy':
        return napoleonDrummerBoy(index);
      case 'Grenadier':
        return napoleonGrenadier(index);
      case 'Hussar':
        return napoleonHussar(index);
      case 'Cuirassier':
        return napoleonCuirassier(index);
      // Austrian cards
      case 'Austrian Grenadier':
        return austrianGrenadier(index);
      case 'Austrian Cannon':
        return austrianArtillery(index);
      case 'Austrian Hussar':
        return austrianHussar(index);
      case 'Austrian Infantry':
        return austrianLineInfantry(index);
      case 'Austrian Jäger':
        return austrianJager(index);
      case 'Austrian Cuirassier':
        return austrianCuirassier(index);
      case 'Austrian Officer':
        return austrianOfficer(index);
      // Legendary cards
      case 'Sunfire Warlord':
        return sunfireWarlord();
      case 'Tidal Leviathan':
        return tidalLeviathan();
      case 'Ancient Treant':
        return ancientTreant();
      case 'Shadow Assassin':
        return shadowAssassin();
      // Napoleon legendary/epic cards
      case 'Siege Cannon':
        return napoleonSiegeCannon(index);
      case "Napoleon's Guard":
        return napoleonsGuard();
      default:
        return null;
    }
  }
}
