import 'dart:math';
import 'card.dart';

enum EncounterType { battle, elite, shop, rest, event, boss, mystery, treasure }

enum BattleDifficulty { easy, normal, hard, elite, boss }

class Encounter {
  final String id;
  final EncounterType type;
  final String title;
  final String description;
  final BattleDifficulty? difficulty;
  final int? goldReward;
  final String? eventId;

  const Encounter({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.difficulty,
    this.goldReward,
    this.eventId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'difficulty': difficulty?.name,
    'goldReward': goldReward,
    'eventId': eventId,
  };

  factory Encounter.fromJson(Map<String, dynamic> json) => Encounter(
    id: json['id'] as String,
    type: EncounterType.values.byName(json['type'] as String),
    title: json['title'] as String,
    description: json['description'] as String,
    difficulty: json['difficulty'] != null
        ? BattleDifficulty.values.byName(json['difficulty'] as String)
        : null,
    goldReward: json['goldReward'] as int?,
    eventId: json['eventId'] as String?,
  );
}

class CampaignState {
  final String id;
  final String leaderId;
  int act;
  int encounterNumber;
  int gold;
  int health;
  int maxHealth;
  List<GameCard> deck;
  List<GameCard> inventory;
  List<String> relics;
  List<String> activeRelics;
  String? startingRelicId;
  String? startingSpecialCardId;
  Map<String, int> consumables;
  Map<String, int> activeConsumables;
  Set<String> awardedLegacyMilestones;
  final DateTime startedAt;
  DateTime? completedAt;
  bool isVictory;
  List<Encounter> currentChoices;
  DateTime lastUpdated;

  CampaignState({
    required this.id,
    required this.leaderId,
    this.act = 1,
    this.encounterNumber = 0,
    this.gold = 50,
    this.health = 50,
    this.maxHealth = 50,
    required this.deck,
    List<GameCard>? inventory,
    List<String>? relics,
    List<String>? activeRelics,
    this.startingRelicId,
    this.startingSpecialCardId,
    Map<String, int>? consumables,
    Map<String, int>? activeConsumables,
    Set<String>? awardedLegacyMilestones,
    required this.startedAt,
    this.completedAt,
    this.isVictory = false,
    this.currentChoices = const [],
    DateTime? lastUpdated,
  }) : inventory = inventory ?? [],
       relics = relics ?? [],
       activeRelics =
           activeRelics ?? (relics != null ? [...relics] : <String>[]),
       consumables = consumables ?? <String, int>{},
       activeConsumables = activeConsumables ?? <String, int>{},
       awardedLegacyMilestones = awardedLegacyMilestones ?? <String>{},
       lastUpdated = lastUpdated ?? DateTime.now();

  bool hasAwardedMilestone(String milestoneId) {
    return awardedLegacyMilestones.contains(milestoneId);
  }

  void markMilestoneAwarded(String milestoneId) {
    awardedLegacyMilestones.add(milestoneId);
  }

  static const int bossEncounterThreshold = 5;
  bool get isBossTime => encounterNumber >= bossEncounterThreshold;
  bool get isOver => isVictory || health <= 0;
  int get encountersUntilBoss => (bossEncounterThreshold - encounterNumber)
      .clamp(0, bossEncounterThreshold);

  // Relic Effects Helpers
  bool hasRelic(String relicId) => relics.contains(relicId);

  bool isRelicActive(String relicId) => activeRelics.contains(relicId);

  int get goldPerBattleBonus {
    int bonus = 0;
    if (activeRelics.contains('relic_gold_purse')) bonus += 10;
    if (activeRelics.contains('legendary_relic_gold_purse')) bonus += 20;
    return bonus;
  }

  int get globalDamageBonus {
    int bonus = 0;
    if (activeRelics.contains('relic_morale')) bonus += 1;
    if (activeRelics.contains('legendary_relic_morale')) bonus += 2;
    return bonus;
  }

  void nextAct() {
    act++;
    encounterNumber = 0;
    // Reset health between acts
    health = maxHealth;
  }

  void addGold(int amount) {
    gold += amount;
  }

  bool spendGold(int amount) {
    if (gold < amount) return false;
    gold -= amount;
    return true;
  }

  void takeDamage(int amount) {
    health = (health - amount).clamp(0, maxHealth);
  }

  void heal(int amount) {
    health = (health + amount).clamp(0, maxHealth);
  }

  void addRelic(String relicId) {
    if (!relics.contains(relicId)) {
      relics.add(relicId);
      if (!activeRelics.contains(relicId)) {
        activeRelics.add(relicId);
      }

      // Immediate effects
      if (relicId == 'relic_armor') {
        maxHealth += 10;
        health += 10; // Heal the amount increased
      }

      if (relicId == 'legendary_relic_armor') {
        maxHealth += 20;
        health += 20;
      }
    }
  }

  void activateRelic(String relicId) {
    if (relics.contains(relicId) && !activeRelics.contains(relicId)) {
      activeRelics.add(relicId);
    }
  }

  void deactivateRelic(String relicId) {
    if (relicId == 'relic_armor' || relicId == 'legendary_relic_armor') return;
    activeRelics.remove(relicId);
  }

  void addConsumable(String consumableId, {int count = 1}) {
    consumables[consumableId] = (consumables[consumableId] ?? 0) + count;
  }

  bool equipConsumable(String consumableId, {int count = 1}) {
    final available = consumables[consumableId] ?? 0;
    if (available < count) return false;
    consumables[consumableId] = available - count;
    if (consumables[consumableId] == 0) {
      consumables.remove(consumableId);
    }
    activeConsumables[consumableId] =
        (activeConsumables[consumableId] ?? 0) + count;
    return true;
  }

  bool unequipConsumable(String consumableId, {int count = 1}) {
    final active = activeConsumables[consumableId] ?? 0;
    if (active < count) return false;
    activeConsumables[consumableId] = active - count;
    if (activeConsumables[consumableId] == 0) {
      activeConsumables.remove(consumableId);
    }
    consumables[consumableId] = (consumables[consumableId] ?? 0) + count;
    return true;
  }

  bool consumeActiveConsumable(String consumableId, {int count = 1}) {
    final active = activeConsumables[consumableId] ?? 0;
    if (active < count) return false;
    activeConsumables[consumableId] = active - count;
    if (activeConsumables[consumableId] == 0) {
      activeConsumables.remove(consumableId);
    }
    return true;
  }

  void addCard(GameCard card) {
    deck = [...deck, card];
  }

  void removeCard(String cardId) {
    final card = deck.firstWhere(
      (c) => c.id == cardId,
      orElse: () => deck.first,
    );
    deck = deck.where((c) => c.id != cardId).toList();
    // Add to inventory so it can be added back later
    inventory = [...inventory, card];
  }

  void addCardFromInventory(String cardId) {
    final card = inventory.firstWhere(
      (c) => c.id == cardId,
      orElse: () => inventory.first,
    );
    inventory = inventory.where((c) => c.id != cardId).toList();
    deck = [...deck, card];
  }

  void completeEncounter() {
    encounterNumber++;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'leaderId': leaderId,
    'act': act,
    'encounterNumber': encounterNumber,
    'gold': gold,
    'health': health,
    'maxHealth': maxHealth,
    'deck': deck.map((c) => c.toJson()).toList(),
    'inventory': inventory.map((c) => c.toJson()).toList(),
    'relics': relics,
    'activeRelics': activeRelics,
    'startingRelicId': startingRelicId,
    'startingSpecialCardId': startingSpecialCardId,
    'consumables': consumables,
    'activeConsumables': activeConsumables,
    'awardedLegacyMilestones': awardedLegacyMilestones.toList(),
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'isVictory': isVictory,
    'currentChoices': currentChoices.map((e) => e.toJson()).toList(),
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory CampaignState.fromJson(Map<String, dynamic> json) => CampaignState(
    id: json['id'] as String,
    leaderId: json['leaderId'] as String,
    act: json['act'] as int? ?? 1,
    encounterNumber: json['encounterNumber'] as int? ?? 0,
    gold: json['gold'] as int? ?? 50,
    health: json['health'] as int? ?? 50,
    maxHealth: json['maxHealth'] as int? ?? 50,
    deck: (json['deck'] as List)
        .map((c) => GameCard.fromJson(c as Map<String, dynamic>))
        .toList(),
    inventory: (json['inventory'] as List?)
        ?.map((c) => GameCard.fromJson(c as Map<String, dynamic>))
        .toList(),
    relics: (json['relics'] as List?)?.map((e) => e as String).toList(),
    activeRelics: (json['activeRelics'] as List?)
        ?.map((e) => e as String)
        .toList(),
    startingRelicId: json['startingRelicId'] as String?,
    startingSpecialCardId: json['startingSpecialCardId'] as String?,
    consumables: (json['consumables'] as Map?)?.map(
      (key, value) => MapEntry(key as String, (value as num).toInt()),
    ),
    activeConsumables: (json['activeConsumables'] as Map?)?.map(
      (key, value) => MapEntry(key as String, (value as num).toInt()),
    ),
    awardedLegacyMilestones: Set<String>.from(
      json['awardedLegacyMilestones'] as List? ?? const [],
    ),
    startedAt: DateTime.parse(json['startedAt'] as String),
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
    isVictory: json['isVictory'] as bool? ?? false,
    currentChoices:
        (json['currentChoices'] as List?)
            ?.map((e) => Encounter.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    lastUpdated: json['lastUpdated'] != null
        ? DateTime.parse(json['lastUpdated'] as String)
        : null,
  );
}

class EncounterGenerator {
  final Random _random;
  final int act;

  EncounterGenerator({required this.act, int? seed})
    : _random = seed != null ? Random(seed) : Random();

  List<Encounter> generateChoices(int encounterNumber) {
    final choices = <Encounter>[];

    // Determine if this encounter should have non-battle options
    // Non-battle options appear every 2-3 encounters (not every turn)
    final shouldHaveNonBattle =
        (encounterNumber % 3 == 0) ||
        (encounterNumber % 3 == 2 && _random.nextBool());

    // Always have at least 2 battle options
    final numBattles = shouldHaveNonBattle ? 2 : 3;

    for (int i = 0; i < numBattles; i++) {
      // Mix in elite battles as encounter progresses
      if (encounterNumber >= 3 && i == 0 && _random.nextDouble() < 0.3) {
        choices.add(_generateElite(encounterNumber));
      } else {
        choices.add(_generateBattle(encounterNumber, i));
      }
    }

    // Add non-battle options only on designated encounters
    if (shouldHaveNonBattle) {
      final otherTypes = _getAvailableTypes(encounterNumber);
      otherTypes.shuffle(_random);

      // FORCE SHOP if it's a multiple of 3 and shop is available
      // ALSO force Shop on the first encounter of Acts 2 and 3.
      if ((encounterNumber == 0 && (act == 2 || act == 3)) ||
          (encounterNumber > 0 && encounterNumber % 3 == 0)) {
        if (otherTypes.contains(EncounterType.shop)) {
          // Move shop to front to ensure it's picked
          otherTypes.remove(EncounterType.shop);
          otherTypes.insert(0, EncounterType.shop);
        }
      }

      // Add 1 non-battle option (Total 3 choices: 2 battles + 1 non-battle)
      final numNonBattle = 1;
      for (int i = 0; i < numNonBattle && i < otherTypes.length; i++) {
        choices.add(_generateEncounter(otherTypes[i], encounterNumber, i));
      }
    }

    choices.shuffle(_random);
    return choices;
  }

  Encounter _generateElite(int encounterNumber, [int index = 0]) {
    final List<(String, String)> eliteTitles;

    switch (act) {
      case 2: // Egypt
        eliteTitles = [
          ('Mamluk Heavy Cavalry', 'Elite Mamluk warriors charge your lines.'),
          ('Janissary Guard', 'The Sultan\'s elite infantry blocks the way.'),
          ('Desert Ambush', 'Bedouin raiders strike from the dunes.'),
        ];
        break;
      case 3: // Coalition
        eliteTitles = [
          ('Russian Imperial Guard', ' The Tzar\'s finest troops stand firm.'),
          ('Combined Elite Force', 'Austrian and Russian elites join forces.'),
          ('Cossack Raiders', 'Fearless horsemen harass your flanks.'),
        ];
        break;
      default: // Act 1 (Italy)
        eliteTitles = [
          ('Austrian Grenadiers', 'Elite heavy infantry guards the pass.'),
          ('Cavalry Ambush', 'Enemy hussars have set a trap.'),
          ('Fortified Position', 'A well-defended enemy stronghold.'),
        ];
    }

    final elite = eliteTitles[_random.nextInt(eliteTitles.length)];
    return Encounter(
      id: 'elite_${encounterNumber}_$index',
      type: EncounterType.elite,
      title: elite.$1,
      description: elite.$2,
      difficulty: BattleDifficulty.elite,
      goldReward: 25 + (act * 10),
    );
  }

  Encounter generateBoss() {
    final bossNames = <int, (String, String)>{
      1: (
        'General Beaulieu',
        'The Austrian commander blocks your path to Milan.',
      ),
      2: ('Murad Bey', 'The Mamluk warlord awaits at the Pyramids.'),
      3: (
        'Coalition Forces',
        'The combined armies of Europe stand against you.',
      ),
    };
    final boss =
        bossNames[act] ??
        ('Enemy Commander', 'A powerful foe blocks your path.');
    return Encounter(
      id: 'boss_act_$act',
      type: EncounterType.boss,
      title: boss.$1,
      description: boss.$2,
      difficulty: BattleDifficulty.boss,
      goldReward: 50 + (act * 25),
    );
  }

  List<EncounterType> _getAvailableTypes(int encounterNumber) {
    final types = <EncounterType>[EncounterType.event, EncounterType.event];
    if (encounterNumber >= 1 ||
        ((act == 2 || act == 3) && encounterNumber == 0)) {
      types.add(EncounterType.shop);
    }
    if (encounterNumber >= 2) types.add(EncounterType.rest);
    if (encounterNumber >= 3) types.add(EncounterType.mystery);
    if (encounterNumber >= 4 && _random.nextDouble() < 0.15) {
      types.add(EncounterType.treasure);
    }
    if (encounterNumber >= 3 && encounterNumber < 6) {
      types.add(EncounterType.elite);
    }
    return types;
  }

  Encounter _generateBattle(int encounterNumber, int index) {
    final difficulty = encounterNumber < 2
        ? BattleDifficulty.easy
        : (encounterNumber < 5
              ? BattleDifficulty.normal
              : BattleDifficulty.hard);

    final List<(String, String)> battleTitles;

    switch (act) {
      case 2: // Egypt
        battleTitles = [
          ('Skirmish at the Nile', 'Mamluk scouts block the river bank.'),
          ('Village Raid', 'Local militia defends a supply cache.'),
          ('Desert Crossing', 'Enemy forces ambush the weary column.'),
          (
            'Battle of the Pyramids (Outskirts)',
            'Advanced guard action near the monuments.',
          ),
        ];
        break;
      case 3: // Coalition
        battleTitles = [
          ('Snowy Plains', 'Russian infantry digs in for defense.'),
          ('Bridge Defense', 'Hold the bridge against Austrian advance.'),
          ('Forest Skirmish', 'Enemy jägers hide in the dense woods.'),
          ('Rearguard Action', 'Protect the baggage train from Cossacks.'),
        ];
        break;
      default: // Act 1 (Italy)
        battleTitles = [
          (
            'Skirmish at the Bridge',
            'Austrian scouts block the river crossing.',
          ),
          ('Village Defense', 'Enemy forces occupy a strategic village.'),
          ('Supply Convoy', 'Capture the enemy supply train.'),
          ('Hill Assault', 'Take the high ground from entrenched defenders.'),
        ];
    }

    final battle = battleTitles[_random.nextInt(battleTitles.length)];
    return Encounter(
      id: 'battle_${encounterNumber}_$index',
      type: EncounterType.battle,
      title: battle.$1,
      description: battle.$2,
      difficulty: difficulty,
      goldReward: 10 + (act * 5) + (encounterNumber * 2),
    );
  }

  Encounter _generateEncounter(
    EncounterType type,
    int encounterNumber,
    int index,
  ) {
    switch (type) {
      case EncounterType.elite:
        return _generateElite(encounterNumber, index);
      case EncounterType.shop:
        return _generateShop(index);
      case EncounterType.rest:
        return _generateRest(index);
      case EncounterType.event:
        return _generateEvent(index);
      case EncounterType.mystery:
        return _generateMystery(index);
      case EncounterType.treasure:
        return _generateTreasure(index);
      default:
        return _generateBattle(encounterNumber, index);
    }
  }

  Encounter _generateShop(int index) {
    final shopTitles = [
      ('Military Outfitter', 'A merchant offers weapons and supplies.'),
    ];
    final shop = shopTitles[_random.nextInt(shopTitles.length)];
    return Encounter(
      id: 'shop_$index',
      type: EncounterType.shop,
      title: shop.$1,
      description: shop.$2,
    );
  }

  Encounter _generateRest(int index) {
    final restTitles = [('Field Camp', 'Rest and tend to the wounded.')];
    final rest = restTitles[_random.nextInt(restTitles.length)];
    return Encounter(
      id: 'rest_$index',
      type: EncounterType.rest,
      title: rest.$1,
      description: rest.$2,
    );
  }

  Encounter _generateEvent(int index) {
    final eventTitles = [
      ('Mysterious Traveler', 'A cloaked figure offers a deal.'),
    ];
    final event = eventTitles[_random.nextInt(eventTitles.length)];
    return Encounter(
      id: 'event_$index',
      type: EncounterType.event,
      title: event.$1,
      description: event.$2,
    );
  }

  Encounter _generateMystery(int index) {
    return Encounter(
      id: 'mystery_$index',
      type: EncounterType.mystery,
      title: 'Unknown Location',
      description: 'A strange aura surrounds this place. Proceed with caution.',
      difficulty:
          BattleDifficulty.values[_random.nextInt(
            BattleDifficulty.values.length,
          )], // Hidden difficulty
    );
  }

  Encounter _generateTreasure(int index) {
    return Encounter(
      id: 'treasure_$index',
      type: EncounterType.treasure,
      title: 'Hidden Cache',
      description: 'A hidden stash of supplies left by a previous army.',
      goldReward: 50 + (act * 20),
    );
  }
}
