import 'card.dart';
import 'deck.dart';
import 'hero.dart';

/// Represents a player's state during a match
/// TYC3: Base HP system (renamed from crystalHP)
class Player {
  final String id;
  final String name;
  final bool isHuman; // true for human player, false for AI

  // Match state
  final Deck deck;
  final List<GameCard> hand;
  List<GameCard>? startingDeck;

  // TYC3: Base HP (renamed from crystalHP for clarity)
  int baseHP;
  int gold;

  /// The hero selected for this match (optional for backward compatibility).
  final GameHero? hero;

  /// Optional elemental attunement for this player's base/crystal.
  /// When set, matching-element cards can receive buffs in that player's base zone.
  /// If a hero is set, this may be derived from the hero's terrain affinities.
  final String? attunedElement;

  // Constants
  static const int maxHandSize = 8;
  static const int maxBaseHP = 25; // TYC3: Increased base HP

  /// LEGACY: Alias for backward compatibility
  @Deprecated('Use baseHP instead')
  int get crystalHP => baseHP;
  @Deprecated('Use baseHP instead')
  set crystalHP(int value) => baseHP = value;
  static const int maxCrystalHP = maxBaseHP; // Legacy alias

  Player({
    required this.id,
    required this.name,
    required this.deck,
    this.isHuman = true,
    int? baseHP,
    this.gold = 0,
    this.attunedElement,
    this.hero,
  }) : hand = [],
       baseHP = baseHP ?? maxBaseHP;

  /// Check if base is destroyed (player loses)
  bool get isDefeated => baseHP <= 0;

  /// Check if hand is full
  bool get isHandFull => hand.length >= maxHandSize;

  /// Draw initial hand (6 cards)
  void drawInitialHand() {
    final cards = deck.drawCards(6);
    hand.addAll(cards);
  }

  /// Draw cards at start of turn (2 cards)
  void drawCards({int count = 2}) {
    if (deck.isEmpty) return;

    final cards = deck.drawCards(count);
    for (final card in cards) {
      if (!isHandFull) {
        hand.add(card);
      }
      // If hand is full, card is discarded
    }
  }

  /// Replace specific cards in hand with new ones from deck (Mulligan)
  void replaceCards(List<GameCard> cardsToReplace) {
    int count = 0;
    for (final card in cardsToReplace) {
      if (hand.contains(card)) {
        hand.remove(card);
        deck.returnCard(card);
        count++;
      }
    }
    deck.shuffle();

    final newCards = deck.drawCards(count);
    hand.addAll(newCards);
  }

  /// Play a card from hand
  bool playCard(GameCard card) {
    if (!hand.contains(card)) return false;
    hand.remove(card);
    return true;
  }

  /// Take damage to base
  void takeBaseDamage(int amount) {
    baseHP -= amount;
    if (baseHP < 0) baseHP = 0;
  }

  /// LEGACY: Alias for backward compatibility
  @Deprecated('Use takeBaseDamage instead')
  void takeCrystalDamage(int amount) => takeBaseDamage(amount);

  /// Earn gold
  void earnGold(int amount) {
    gold += amount;
  }

  /// Get base HP percentage for UI
  double get baseHPPercent => (baseHP / maxBaseHP).clamp(0.0, 1.0);

  /// LEGACY: Alias for backward compatibility
  @Deprecated('Use baseHPPercent instead')
  double get crystalHPPercent => baseHPPercent;

  @override
  String toString() =>
      '$name (Base: $baseHP HP, Hand: ${hand.length}, Deck: ${deck.remainingCards})';

  /// Serialize to JSON for Firebase (runtime state only, not full deck)
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isHuman': isHuman,
    'baseHP': baseHP,
    'gold': gold,
    'attunedElement': attunedElement,
    'heroId': hero?.id,
    'heroAbilityUsed': hero?.abilityUsed ?? false,
    'hand': hand.map((c) => c.toJson()).toList(),
    'deckCards': deck.cards.map((c) => c.toJson()).toList(),
  };

  /// Create from JSON (for syncing online state)
  factory Player.fromJson(Map<String, dynamic> json, {GameHero? hero}) {
    final playerId = json['id'] as String;
    final playerName = json['name'] as String;
    final deckCards = (json['deckCards'] as List<dynamic>? ?? [])
        .map((c) => GameCard.fromJson(c as Map<String, dynamic>))
        .toList();

    // Ensure deck has 25 cards (pad if needed)
    while (deckCards.length < 25) {
      deckCards.add(
        GameCard(
          id: 'filler_${deckCards.length}',
          name: 'Filler',
          damage: 1,
          health: 1,
        ),
      );
    }

    // Restore hero ability used state
    if (hero != null && json['heroAbilityUsed'] == true) {
      hero.abilityUsed = true;
    }

    final player = Player(
      id: playerId,
      name: playerName,
      deck: Deck(
        id: 'deck_$playerId',
        name: '$playerName Deck',
        cards: deckCards,
      ),
      isHuman: json['isHuman'] as bool? ?? true,
      baseHP: json['baseHP'] as int? ?? maxBaseHP,
      gold: json['gold'] as int? ?? 0,
      attunedElement: json['attunedElement'] as String?,
      hero: hero,
    );
    final handData = json['hand'] as List<dynamic>? ?? [];
    for (final cardJson in handData) {
      player.hand.add(GameCard.fromJson(cardJson as Map<String, dynamic>));
    }

    // Snapshot the starting deck for refill-style hero abilities.
    player.startingDeck = player.deck.cards.map((c) => c.copy()).toList();
    return player;
  }

  /// Create a deep copy of the player state
  Player copy() {
    final newPlayer = Player(
      id: id,
      name: name,
      deck: Deck(
        id: deck.id,
        name: deck.name,
        cards: deck.cards,
        skipValidation: true,
      ),
      isHuman: isHuman,
      baseHP: baseHP,
      gold: gold,
      attunedElement: attunedElement,
      hero: hero?.copy(),
    );

    // Copy hand
    for (final card in hand) {
      newPlayer.hand.add(card.clone());
    }

    newPlayer.startingDeck = startingDeck?.map((c) => c.clone()).toList();

    return newPlayer;
  }
}
