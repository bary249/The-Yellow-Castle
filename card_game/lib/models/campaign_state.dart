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

  final bool isConquerableCity;
  final bool isDefense;

  final String? offerType;
  final String? offerId;
  final int? offerAmount;

  const Encounter({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.difficulty,
    this.goldReward,
    this.eventId,
    this.isConquerableCity = false,
    this.isDefense = false,
    this.offerType,
    this.offerId,
    this.offerAmount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'difficulty': difficulty?.name,
    'goldReward': goldReward,
    'eventId': eventId,
    'isConquerableCity': isConquerableCity,
    'isDefense': isDefense,
    'offerType': offerType,
    'offerId': offerId,
    'offerAmount': offerAmount,
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
    isConquerableCity: json['isConquerableCity'] as bool? ?? false,
    isDefense: json['isDefense'] as bool? ?? false,
    offerType: json['offerType'] as String?,
    offerId: json['offerId'] as String?,
    offerAmount: (json['offerAmount'] as num?)?.toInt(),
  );
}

class PendingCardDelivery {
  final String id;
  final String sourceBuildingId;
  final GameCard card;
  int scheduledAtEncounter;
  final int productionDurationEncounters;

  /// How many kilometers this delivery has traveled so far.
  double traveledKm;

  /// Optional override used for legacy saves and “hurry supply”.
  /// If set, the delivery is considered arrived once encounterNumber >= this.
  int? forcedArrivesAtEncounter;

  PendingCardDelivery({
    required this.id,
    required this.sourceBuildingId,
    required this.card,
    required this.scheduledAtEncounter,
    required this.productionDurationEncounters,
    this.traveledKm = 0,
    this.forcedArrivesAtEncounter,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceBuildingId': sourceBuildingId,
    'card': card.toJson(),
    'scheduledAtEncounter': scheduledAtEncounter,
    'productionDurationEncounters': productionDurationEncounters,
    'traveledKm': traveledKm,
    // Backward compatibility: older saves use arrivesAtEncounter.
    'arrivesAtEncounter': forcedArrivesAtEncounter,
    'forcedArrivesAtEncounter': forcedArrivesAtEncounter,
  };

  factory PendingCardDelivery.fromJson(Map<String, dynamic> json) =>
      PendingCardDelivery(
        id: json['id'] as String,
        sourceBuildingId: json['sourceBuildingId'] as String,
        card: GameCard.fromJson(json['card'] as Map<String, dynamic>),
        scheduledAtEncounter:
            (json['scheduledAtEncounter'] as num?)?.toInt() ?? 0,
        productionDurationEncounters:
            (json['productionDurationEncounters'] as num?)?.toInt() ?? 0,
        traveledKm: (json['traveledKm'] as num?)?.toDouble() ?? 0.0,
        forcedArrivesAtEncounter:
            (json['forcedArrivesAtEncounter'] as num?)?.toInt() ??
            (json['arrivesAtEncounter'] as num?)?.toInt(),
      );
}

class HomeTownBuilding {
  final String id;
  int level;
  int lastCollectedEncounter;

  HomeTownBuilding({
    required this.id,
    this.level = 1,
    this.lastCollectedEncounter = -1,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level,
    'lastCollectedEncounter': lastCollectedEncounter,
  };

  factory HomeTownBuilding.fromJson(Map<String, dynamic> json) =>
      HomeTownBuilding(
        id: json['id'] as String,
        level: (json['level'] as num?)?.toInt() ?? 1,
        lastCollectedEncounter:
            (json['lastCollectedEncounter'] as num?)?.toInt() ?? -1,
      );
}

class TravelPoint {
  final double lat;
  final double lng;

  const TravelPoint({required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory TravelPoint.fromJson(Map<String, dynamic> json) => TravelPoint(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
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
  List<GameCard> destroyedDeckCards;
  List<GameCard> inventory;
  List<PendingCardDelivery> pendingCardDeliveries;
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
  Encounter? pendingDefenseEncounter;
  double? pendingDefenseLat;
  double? pendingDefenseLng;
  DateTime lastUpdated;

  String? homeTownName;
  double? homeTownLat;
  double? homeTownLng;
  int homeTownLevel;
  List<HomeTownBuilding> homeTownBuildings;

  double? mapRelicLat;
  double? mapRelicLng;
  bool mapRelicDiscovered;
  double? lastTravelLat;
  double? lastTravelLng;

  List<TravelPoint> travelHistory;
  List<TravelPoint> visitedNodes;

  /// Maps card ID to the encounter number when it becomes freely available.
  /// Cards gated by random events can be restored immediately for gold or
  /// for free once encounterNumber >= the gated value.
  Map<String, int> gatedReserveCards;

  int recoveryEncountersRemaining;

  /// Campaign upgrade: reduces distance-based supply penalty.
  /// Currently 0 or 1.
  int supplyDistancePenaltyReduction;

  /// Count of battle encounters completed (battle, elite, boss only).
  /// Used for boss availability threshold.
  int battleEncounterCount;

  /// Campaign end node location (for boss distance check).
  double? campaignEndLat;
  double? campaignEndLng;

  CampaignState({
    required this.id,
    required this.leaderId,
    this.act = 1,
    this.encounterNumber = 0,
    this.gold = 50,
    this.health = 50,
    this.maxHealth = 50,
    required this.deck,
    List<GameCard>? destroyedDeckCards,
    List<GameCard>? inventory,
    List<PendingCardDelivery>? pendingCardDeliveries,
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
    this.pendingDefenseEncounter,
    this.pendingDefenseLat,
    this.pendingDefenseLng,
    this.homeTownName,
    this.homeTownLat,
    this.homeTownLng,
    this.homeTownLevel = 1,
    List<HomeTownBuilding>? homeTownBuildings,
    this.mapRelicLat,
    this.mapRelicLng,
    this.mapRelicDiscovered = false,
    this.lastTravelLat,
    this.lastTravelLng,
    List<TravelPoint>? travelHistory,
    List<TravelPoint>? visitedNodes,
    Map<String, int>? gatedReserveCards,
    this.recoveryEncountersRemaining = 0,
    this.supplyDistancePenaltyReduction = 0,
    this.battleEncounterCount = 0,
    this.campaignEndLat,
    this.campaignEndLng,
    DateTime? lastUpdated,
  }) : inventory = inventory ?? [],
       gatedReserveCards = gatedReserveCards ?? <String, int>{},
       pendingCardDeliveries = pendingCardDeliveries ?? <PendingCardDelivery>[],
       destroyedDeckCards = destroyedDeckCards ?? [],
       relics = relics ?? [],
       activeRelics =
           activeRelics ?? (relics != null ? [...relics] : <String>[]),
       homeTownBuildings = homeTownBuildings ?? <HomeTownBuilding>[],
       consumables = consumables ?? <String, int>{},
       activeConsumables = activeConsumables ?? <String, int>{},
       awardedLegacyMilestones = awardedLegacyMilestones ?? <String>{},
       travelHistory = travelHistory ?? <TravelPoint>[],
       visitedNodes = visitedNodes ?? <TravelPoint>[],
       lastUpdated = lastUpdated ?? DateTime.now();

  int supplyProductionDurationForCard(GameCard card) {
    return switch (card.rarity) {
      1 => 1,
      2 => 2,
      3 => 3,
      4 => 4,
      _ => 1,
    };
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);

  static double _haversineKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double? distanceHomeToHeroKm() {
    final townLat = homeTownLat;
    final townLng = homeTownLng;
    final heroLat = lastTravelLat;
    final heroLng = lastTravelLng;
    if (townLat == null ||
        townLng == null ||
        heroLat == null ||
        heroLng == null) {
      return null;
    }
    return _haversineKm(
      lat1: townLat,
      lng1: townLng,
      lat2: heroLat,
      lng2: heroLng,
    );
  }

  int distanceSupplyModifierEncountersFromKm(double km) {
    final baseModifier = (km < 40)
        ? -1
        : (km < 80)
        ? 0
        : (km < 180)
        ? 1
        : (km < 320)
        ? 2
        : (km < 500)
        ? 3
        : 4;

    final relicReduction = isRelicActive('relic_supply_routes') ? 1 : 0;
    final totalReduction = supplyDistancePenaltyReduction + relicReduction;
    return baseModifier - totalReduction;
  }

  int currentTravelDurationEncounters() {
    final km = distanceHomeToHeroKm();
    if (km == null) return 1;
    // Base travel time is 1; distance modifies it.
    final modifier = distanceSupplyModifierEncountersFromKm(km);
    return (1 + modifier).clamp(1, 99);
  }

  bool isDeliveryProduced(PendingCardDelivery d) {
    return (encounterNumber - d.scheduledAtEncounter) >=
        d.productionDurationEncounters;
  }

  int encountersUntilDeliveryProduced(PendingCardDelivery d) {
    final producedAt = d.scheduledAtEncounter + d.productionDurationEncounters;
    return (producedAt - encounterNumber).clamp(0, 999999);
  }

  void addTravelPoint(double lat, double lng) {
    travelHistory = [...travelHistory, TravelPoint(lat: lat, lng: lng)];
  }

  void recordVisitedNode(double lat, double lng) {
    visitedNodes = [...visitedNodes, TravelPoint(lat: lat, lng: lng)];
  }

  bool get canReturnToPreviousNode => visitedNodes.isNotEmpty;

  void popVisitedNode() {
    if (visitedNodes.isEmpty) return;
    visitedNodes = visitedNodes.sublist(0, visitedNodes.length - 1);
  }

  bool hasAwardedMilestone(String milestoneId) {
    return awardedLegacyMilestones.contains(milestoneId);
  }

  void markMilestoneAwarded(String milestoneId) {
    awardedLegacyMilestones.add(milestoneId);
  }

  static const int bossEncounterThreshold = 7;
  static const double bossDistanceThresholdKm = 100.0;

  /// Boss is available when enough BATTLE encounters completed AND hero is close to end node.
  bool get isBossTime {
    if (battleEncounterCount < bossEncounterThreshold) return false;
    // Also check distance to campaign end node
    final distKm = distanceToEndNodeKm();
    if (distKm == null) return true; // No end node set, allow boss
    return distKm <= bossDistanceThresholdKm;
  }

  bool get isOver => isVictory || health <= 0;

  int get battlesUntilBoss => (bossEncounterThreshold - battleEncounterCount)
      .clamp(0, bossEncounterThreshold);

  double? distanceToEndNodeKm() {
    final heroLat = lastTravelLat;
    final heroLng = lastTravelLng;
    final endLat = campaignEndLat;
    final endLng = campaignEndLng;
    if (heroLat == null ||
        heroLng == null ||
        endLat == null ||
        endLng == null) {
      return null;
    }
    return _haversineKm(
      lat1: heroLat,
      lng1: heroLng,
      lat2: endLat,
      lng2: endLng,
    );
  }

  void incrementBattleEncounterCount() {
    battleEncounterCount++;
  }

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

  void addCardToReserves(GameCard card) {
    inventory = [...inventory, card];
  }

  PendingCardDelivery enqueueCardDelivery({
    required String sourceBuildingId,
    required GameCard card,
  }) {
    final delivery = PendingCardDelivery(
      id: 'delivery_${DateTime.now().millisecondsSinceEpoch}_${pendingCardDeliveries.length}',
      sourceBuildingId: sourceBuildingId,
      card: card,
      scheduledAtEncounter: encounterNumber,
      productionDurationEncounters: supplyProductionDurationForCard(card),
    );
    pendingCardDeliveries = [...pendingCardDeliveries, delivery];
    return delivery;
  }

  void advanceSupplyChainOneEncounter() {
    if (pendingCardDeliveries.isEmpty) return;

    final km = distanceHomeToHeroKm();
    if (km == null) {
      // Without coordinates we only support forced arrivals.
      return;
    }

    final travelDuration = currentTravelDurationEncounters();
    final speedKmPerEncounter = km <= 0 ? 999999.0 : (km / travelDuration);

    for (final d in pendingCardDeliveries) {
      if (d.forcedArrivesAtEncounter != null) continue;
      if (!isDeliveryProduced(d)) continue;
      d.traveledKm += speedKmPerEncounter;
    }
  }

  List<PendingCardDelivery> collectArrivedDeliveries() {
    if (pendingCardDeliveries.isEmpty) return <PendingCardDelivery>[];

    final km = distanceHomeToHeroKm();
    final arrived = pendingCardDeliveries.where((d) {
      final forced = d.forcedArrivesAtEncounter;
      if (forced != null) {
        return encounterNumber >= forced;
      }
      if (km == null) return false;
      if (!isDeliveryProduced(d)) return false;
      return d.traveledKm >= km;
    }).toList();
    if (arrived.isEmpty) return <PendingCardDelivery>[];
    pendingCardDeliveries = pendingCardDeliveries
        .where((d) => !arrived.any((a) => a.id == d.id))
        .toList();
    for (final d in arrived) {
      addCardToReserves(d.card);
    }
    return arrived;
  }

  int encountersUntilDeliveryArrives(PendingCardDelivery d) {
    final forced = d.forcedArrivesAtEncounter;
    if (forced != null) {
      return (forced - encounterNumber).clamp(0, 999999);
    }

    final km = distanceHomeToHeroKm();
    if (km == null) return 0;

    final productionRemaining = encountersUntilDeliveryProduced(d);
    if (productionRemaining > 0) {
      final travelDuration = currentTravelDurationEncounters();
      return (productionRemaining + travelDuration).clamp(0, 999999);
    }

    final travelDuration = currentTravelDurationEncounters();
    final speedKmPerEncounter = km <= 0 ? 999999.0 : (km / travelDuration);
    final remainingKm = (km - d.traveledKm).clamp(0.0, 999999999.0);
    if (remainingKm <= 0) return 0;
    return (remainingKm / speedKmPerEncounter).ceil().clamp(0, 999999);
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

  /// Move card from deck to reserves with a gate (requires gold or wait).
  /// [gateEncounters] defaults to 1 but can be higher for harsher penalties.
  void removeCardWithGate(String cardId, {int gateEncounters = 1}) {
    final card = deck.firstWhere(
      (c) => c.id == cardId,
      orElse: () => deck.first,
    );
    deck = deck.where((c) => c.id != cardId).toList();
    inventory = [...inventory, card];
    // Gate unlocks after N encounters.
    gatedReserveCards[cardId] = encounterNumber + gateEncounters;
  }

  bool isCardGated(String cardId) {
    final gate = gatedReserveCards[cardId];
    if (gate == null) return false;
    return encounterNumber < gate;
  }

  int encountersUntilCardUnlocked(String cardId) {
    final gate = gatedReserveCards[cardId];
    if (gate == null) return 0;
    return (gate - encounterNumber).clamp(0, 999999);
  }

  /// Pay gold to unlock a gated card immediately.
  bool unlockGatedCardWithGold(String cardId, int cost) {
    if (gold < cost) return false;
    gold -= cost;
    gatedReserveCards.remove(cardId);
    return true;
  }

  /// Remove gate if encounter threshold passed.
  void clearExpiredGates() {
    gatedReserveCards.removeWhere((_, gate) => encounterNumber >= gate);
  }

  void destroyCardPermanently(String cardId) {
    GameCard? removed;
    for (final c in deck) {
      if (c.id == cardId) {
        removed = c;
        break;
      }
    }
    deck = deck.where((c) => c.id != cardId).toList();
    if (removed != null) {
      if (!destroyedDeckCards.any((c) => c.id == cardId)) {
        destroyedDeckCards = [...destroyedDeckCards, removed];
      }
    }
  }

  bool repairDestroyedCard(String cardId) {
    final matches = destroyedDeckCards.where((c) => c.id == cardId).toList();
    if (matches.isEmpty) return false;
    final card = matches.first;
    destroyedDeckCards = destroyedDeckCards
        .where((c) => c.id != cardId)
        .toList();
    deck = [...deck, card];
    return true;
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
    if (recoveryEncountersRemaining > 0) {
      recoveryEncountersRemaining--;
    }

    // Home Town passive effects
    // Supply Depot: +15 gold per encounter (passive, not a delivery).
    if (homeTownBuildings.any((b) => b.id == 'building_supply_depot')) {
      addGold(15);
    }

    // Advance supply chain once per encounter (production + travel).
    advanceSupplyChainOneEncounter();

    clearExpiredGates();
  }

  void enterRecoveryMode({int encounters = 2}) {
    if (encounters <= 0) return;
    if (recoveryEncountersRemaining < encounters) {
      recoveryEncountersRemaining = encounters;
    }
  }

  void setPendingDefenseEncounter(Encounter encounter) {
    pendingDefenseEncounter = encounter;
  }

  void setPendingDefenseEncounterAtLocation(
    Encounter encounter, {
    required double lat,
    required double lng,
  }) {
    pendingDefenseEncounter = encounter;
    pendingDefenseLat = lat;
    pendingDefenseLng = lng;
  }

  void clearPendingDefenseEncounter() {
    pendingDefenseEncounter = null;
    pendingDefenseLat = null;
    pendingDefenseLng = null;
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
    'destroyedDeckCards': destroyedDeckCards.map((c) => c.toJson()).toList(),
    'inventory': inventory.map((c) => c.toJson()).toList(),
    'pendingCardDeliveries': pendingCardDeliveries
        .map((d) => d.toJson())
        .toList(),
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
    'pendingDefenseEncounter': pendingDefenseEncounter?.toJson(),
    'pendingDefenseLat': pendingDefenseLat,
    'pendingDefenseLng': pendingDefenseLng,
    'homeTownName': homeTownName,
    'homeTownLat': homeTownLat,
    'homeTownLng': homeTownLng,
    'homeTownLevel': homeTownLevel,
    'homeTownBuildings': homeTownBuildings.map((b) => b.toJson()).toList(),
    'mapRelicLat': mapRelicLat,
    'mapRelicLng': mapRelicLng,
    'mapRelicDiscovered': mapRelicDiscovered,
    'lastTravelLat': lastTravelLat,
    'lastTravelLng': lastTravelLng,
    'travelHistory': travelHistory.map((p) => p.toJson()).toList(),
    'visitedNodes': visitedNodes.map((p) => p.toJson()).toList(),
    'gatedReserveCards': gatedReserveCards,
    'recoveryEncountersRemaining': recoveryEncountersRemaining,
    'supplyDistancePenaltyReduction': supplyDistancePenaltyReduction,
    'battleEncounterCount': battleEncounterCount,
    'campaignEndLat': campaignEndLat,
    'campaignEndLng': campaignEndLng,
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
    destroyedDeckCards:
        (json['destroyedDeckCards'] as List?)
            ?.map((e) => GameCard.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    inventory:
        (json['inventory'] as List?)
            ?.map((e) => GameCard.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    pendingCardDeliveries:
        (json['pendingCardDeliveries'] as List?)
            ?.map(
              (e) => PendingCardDelivery.fromJson(e as Map<String, dynamic>),
            )
            .toList() ??
        <PendingCardDelivery>[],
    relics: (json['relics'] as List?)?.whereType<String>().toList() ?? [],
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
    pendingDefenseEncounter: json['pendingDefenseEncounter'] != null
        ? Encounter.fromJson(
            json['pendingDefenseEncounter'] as Map<String, dynamic>,
          )
        : null,
    pendingDefenseLat: (json['pendingDefenseLat'] as num?)?.toDouble(),
    pendingDefenseLng: (json['pendingDefenseLng'] as num?)?.toDouble(),
    homeTownName: json['homeTownName'] as String?,
    homeTownLat: (json['homeTownLat'] as num?)?.toDouble(),
    homeTownLng: (json['homeTownLng'] as num?)?.toDouble(),
    homeTownLevel: (json['homeTownLevel'] as num?)?.toInt() ?? 1,
    homeTownBuildings:
        (json['homeTownBuildings'] as List?)
            ?.map((e) => HomeTownBuilding.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <HomeTownBuilding>[],
    mapRelicLat: (json['mapRelicLat'] as num?)?.toDouble(),
    mapRelicLng: (json['mapRelicLng'] as num?)?.toDouble(),
    mapRelicDiscovered: json['mapRelicDiscovered'] as bool? ?? false,
    lastTravelLat: (json['lastTravelLat'] as num?)?.toDouble(),
    lastTravelLng: (json['lastTravelLng'] as num?)?.toDouble(),
    travelHistory:
        (json['travelHistory'] as List?)
            ?.map((e) => TravelPoint.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <TravelPoint>[],
    visitedNodes:
        (json['visitedNodes'] as List?)
            ?.map((e) => TravelPoint.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <TravelPoint>[],
    gatedReserveCards: (json['gatedReserveCards'] as Map?)?.map(
      (key, value) => MapEntry(key as String, (value as num).toInt()),
    ),
    recoveryEncountersRemaining:
        (json['recoveryEncountersRemaining'] as num?)?.toInt() ?? 0,
    supplyDistancePenaltyReduction:
        (json['supplyDistancePenaltyReduction'] as num?)?.toInt() ?? 0,
    battleEncounterCount: (json['battleEncounterCount'] as num?)?.toInt() ?? 0,
    campaignEndLat: (json['campaignEndLat'] as num?)?.toDouble(),
    campaignEndLng: (json['campaignEndLng'] as num?)?.toDouble(),
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

  String _randomConsumableOfferId({String? exclude}) {
    const ids = <String>['heal_potion', 'large_heal_potion'];
    if (exclude != null && ids.length > 1) {
      final filtered = ids.where((e) => e != exclude).toList();
      return filtered[_random.nextInt(filtered.length)];
    }
    return ids[_random.nextInt(ids.length)];
  }

  String _randomRelicOfferId({String? exclude}) {
    const ids = <String>['relic_gold_purse', 'relic_armor', 'relic_morale'];
    if (exclude != null && ids.length > 1) {
      final filtered = ids.where((e) => e != exclude).toList();
      return filtered[_random.nextInt(filtered.length)];
    }
    return ids[_random.nextInt(ids.length)];
  }

  Encounter _withOffer(
    Encounter encounter, {
    required String? offerType,
    required String? offerId,
    required int? offerAmount,
  }) {
    return Encounter(
      id: encounter.id,
      type: encounter.type,
      title: encounter.title,
      description: encounter.description,
      difficulty: encounter.difficulty,
      goldReward: encounter.goldReward,
      eventId: encounter.eventId,
      isConquerableCity: encounter.isConquerableCity,
      isDefense: encounter.isDefense,
      offerType: offerType,
      offerId: offerId,
      offerAmount: offerAmount,
    );
  }

  void _ensureOfferDiversity(List<Encounter> choices) {
    final offered = <int>[];
    for (int i = 0; i < choices.length; i++) {
      if (choices[i].offerType != null && choices[i].offerId != null) {
        offered.add(i);
      }
    }
    if (offered.length < 2) return;

    final keys = offered
        .map((i) => '${choices[i].offerType}:${choices[i].offerId}')
        .toSet();
    if (keys.length > 1) return;

    // All offers are identical - reroll one offer to guarantee variety.
    final idx = offered.last;
    final e = choices[idx];
    if (e.offerType == 'consumable') {
      final newId = _randomConsumableOfferId(exclude: e.offerId);
      choices[idx] = _withOffer(
        e,
        offerType: e.offerType,
        offerId: newId,
        offerAmount: e.offerAmount,
      );
    } else if (e.offerType == 'relic') {
      final newId = _randomRelicOfferId(exclude: e.offerId);
      choices[idx] = _withOffer(
        e,
        offerType: e.offerType,
        offerId: newId,
        offerAmount: e.offerAmount,
      );
    }
  }

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

    _ensureOfferDiversity(choices);
    choices.shuffle(_random);
    return choices;
  }

  List<Encounter> generateRecoveryChoices(int encounterNumber) {
    final choices = <Encounter>[];

    choices.add(
      Encounter(
        id: 'recovery_battle_${encounterNumber}_0',
        type: EncounterType.battle,
        title: 'Skirmish (Recovery)',
        description: 'A smaller enemy force you can defeat to regain momentum.',
        difficulty: BattleDifficulty.easy,
        goldReward: 8 + (act * 5),
        offerType: 'consumable',
        offerId: _randomConsumableOfferId(),
        offerAmount: 1,
      ),
    );
    choices.add(_generateEncounter(EncounterType.shop, encounterNumber, 0));
    choices.add(_generateEncounter(EncounterType.rest, encounterNumber, 0));
    choices.add(_generateEncounter(EncounterType.event, encounterNumber, 1));
    choices.add(_generateEncounter(EncounterType.treasure, encounterNumber, 0));

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
      offerType: 'relic',
      offerId: _randomRelicOfferId(),
      offerAmount: 1,
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

    final bool isCityBattle =
        encounterNumber >= 1 && _random.nextDouble() < 0.18;

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

    final title = isCityBattle ? 'Conquer City: ${battle.$1}' : battle.$1;
    final description = isCityBattle
        ? '${battle.$2} This city can be conquered.'
        : battle.$2;
    return Encounter(
      id: 'battle_${encounterNumber}_$index',
      type: EncounterType.battle,
      title: title,
      description: description,
      difficulty: difficulty,
      goldReward: 10 + (act * 5) + (encounterNumber * 2),
      isConquerableCity: isCityBattle,
      offerType: 'consumable',
      offerId: _randomConsumableOfferId(),
      offerAmount: 1,
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
    final bool isRelic = _random.nextBool();
    return Encounter(
      id: 'event_$index',
      type: EncounterType.event,
      title: event.$1,
      description: event.$2,
      offerType: isRelic ? 'relic' : 'consumable',
      offerId: isRelic ? _randomRelicOfferId() : _randomConsumableOfferId(),
      offerAmount: 1,
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
      offerType: 'consumable',
      offerId: 'large_heal_potion',
      offerAmount: 1,
    );
  }
}
