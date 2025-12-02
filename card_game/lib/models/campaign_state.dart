import 'dart:math';
import 'card.dart';

enum EncounterType { battle, elite, shop, rest, event, boss }

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
  final int act;
  int encounterNumber;
  int gold;
  int health;
  final int maxHealth;
  List<GameCard> deck;
  final DateTime startedAt;
  DateTime? completedAt;
  bool isVictory;
  List<Encounter> currentChoices;

  CampaignState({
    required this.id,
    required this.leaderId,
    this.act = 1,
    this.encounterNumber = 0,
    this.gold = 50,
    this.health = 50,
    this.maxHealth = 50,
    required this.deck,
    required this.startedAt,
    this.completedAt,
    this.isVictory = false,
    this.currentChoices = const [],
  });

  static const int bossEncounterThreshold = 7;
  bool get isBossTime => encounterNumber >= bossEncounterThreshold;
  bool get isOver => isVictory || health <= 0;
  int get encountersUntilBoss => (bossEncounterThreshold - encounterNumber)
      .clamp(0, bossEncounterThreshold);

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

  void addCard(GameCard card) {
    deck = [...deck, card];
  }

  void removeCard(String cardId) {
    deck = deck.where((c) => c.id != cardId).toList();
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
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'isVictory': isVictory,
    'currentChoices': currentChoices.map((e) => e.toJson()).toList(),
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

      // Add 1-2 non-battle options
      final numNonBattle = _random.nextBool() ? 1 : 2;
      for (int i = 0; i < numNonBattle && i < otherTypes.length; i++) {
        choices.add(_generateEncounter(otherTypes[i], encounterNumber, i));
      }
    }

    choices.shuffle(_random);
    return choices;
  }

  Encounter _generateElite(int encounterNumber) {
    final eliteTitles = [
      ('Austrian Grenadiers', 'Elite heavy infantry guards the pass.'),
      ('Cavalry Ambush', 'Enemy hussars have set a trap.'),
      ('Fortified Position', 'A well-defended enemy stronghold.'),
    ];
    final elite = eliteTitles[_random.nextInt(eliteTitles.length)];
    return Encounter(
      id: 'elite_$encounterNumber',
      type: EncounterType.elite,
      title: elite.$1,
      description: elite.$2,
      difficulty: BattleDifficulty.hard,
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
    if (encounterNumber >= 1) types.add(EncounterType.shop);
    if (encounterNumber >= 2) types.add(EncounterType.rest);
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
    final battleTitles = [
      ('Skirmish at the Bridge', 'Austrian scouts block the river crossing.'),
      ('Village Defense', 'Enemy forces occupy a strategic village.'),
      ('Supply Convoy', 'Capture the enemy supply train.'),
      ('Hill Assault', 'Take the high ground from entrenched defenders.'),
    ];
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
      default:
        return _generateBattle(encounterNumber, index);
    }
  }

  Encounter _generateElite(int encounterNumber, int index) {
    final eliteTitles = [
      ('Austrian Grenadiers', 'Elite heavy infantry guards the pass.'),
    ];
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
}
