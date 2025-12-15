import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/campaign_state.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../data/card_library.dart';
import '../data/shop_items.dart';
import 'test_match_screen.dart';
import '../data/hero_library.dart';
import 'campaign_deck_screen.dart';
import 'progression_screen.dart';
import 'card_upgrade_screen.dart';
import '../services/campaign_persistence_service.dart';
import '../data/napoleon_progression.dart';

class RewardEvent {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final String?
  cardId; // If set, this event is a card delivery that can be added to deck

  const RewardEvent({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    this.cardId,
  });
}

/// Campaign screen - Book chapter selection style
class CampaignMapScreen extends StatefulWidget {
  final String leaderId;
  final int act;
  final CampaignState? savedState;

  const CampaignMapScreen({
    super.key,
    required this.leaderId,
    this.act = 1,
    this.savedState,
  });

  @override
  State<CampaignMapScreen> createState() => _CampaignMapScreenState();
}

class _CampaignMapScreenState extends State<CampaignMapScreen>
    with SingleTickerProviderStateMixin {
  late CampaignState _campaign;
  late EncounterGenerator _generator;
  bool _isLoading = true;
  final CampaignPersistenceService _persistence = CampaignPersistenceService();
  final MapController _mapController = MapController();

  bool _isValidConsumableOfferId(String id) {
    return ShopInventory.getAllConsumables().any((e) => e.id == id);
  }

  void _logSupply(String message) {
    if (!kDebugMode) return;
    debugPrint('[SUPPLY] $message');
  }

  int _distanceSupplyModifierEncountersAt({
    required double travelLat,
    required double travelLng,
  }) {
    final townLat = _campaign.homeTownLat;
    final townLng = _campaign.homeTownLng;
    if (townLat == null || townLng == null) {
      return 0;
    }

    final distanceMeters = const Distance()(
      LatLng(travelLat, travelLng),
      LatLng(townLat, townLng),
    );
    final km = distanceMeters / 1000.0;

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

    final reduction = _homeTownReduceDistancePenalty ? 1 : 0;
    final relicReduction = _campaign.isRelicActive('relic_supply_routes')
        ? 1
        : 0;
    final totalReduction = reduction + relicReduction;

    return baseModifier - totalReduction;
  }

  double? _distanceToHomeTownKmAt({
    required double travelLat,
    required double travelLng,
  }) {
    final townLat = _campaign.homeTownLat;
    final townLng = _campaign.homeTownLng;
    if (townLat == null || townLng == null) {
      return null;
    }

    final distanceMeters = const Distance()(
      LatLng(travelLat, travelLng),
      LatLng(townLat, townLng),
    );
    return distanceMeters / 1000.0;
  }

  static List<String> _locationTerrainPoolForAct(int act) {
    switch (act) {
      case 2:
        return const ['Desert', 'Desert', 'Desert', 'Marsh', 'Lake'];
      case 3:
        return const ['Woods', 'Woods', 'Lake', 'Marsh'];
      default:
        return const ['Woods', 'Lake', 'Desert', 'Marsh'];
    }
  }

  int _homeTownBuildDiscountPercent = 0;
  bool _homeTownReduceDistancePenalty = false;

  static const String _campaignMapRelicId = 'campaign_map_relic';
  static const double _mapRelicDiscoverDistanceMeters = 25000;

  static const String _buildingTrainingGroundsId = 'building_training_grounds';
  static const String _buildingSupplyDepotId = 'building_supply_depot';
  static const String _buildingOfficersAcademyId = 'building_officers_academy';
  static const String _buildingWarCollegeId = 'building_war_college';
  static const String _buildingMedicCorpsId = 'building_medic_corps';

  final Random _random = Random();

  int _applyDiscount(int cost, int discountPercent) {
    if (discountPercent <= 0) return cost;
    final discounted = (cost * (100 - discountPercent)) / 100.0;
    return discounted.round().clamp(0, cost);
  }

  /// 1/5 chance to permanently destroy a random card from deck
  /// Returns a RewardEvent if a card was destroyed, null otherwise
  RewardEvent? _tryRandomCardDeath() {
    if (_campaign.deck.isEmpty) return null;

    // 1 in 5 chance (20%)
    if (_random.nextInt(5) != 0) return null;

    final idx = _random.nextInt(_campaign.deck.length);
    final card = _campaign.deck[idx];
    setState(() {
      _campaign.destroyCardPermanently(card.id);
    });
    _saveCampaign();
    return RewardEvent(
      title: 'Casualty',
      message: '${card.name} was lost during the wait.',
      icon: Icons.dangerous,
      iconColor: Colors.red,
    );
  }

  RewardEvent _applyReturnPenalty() {
    final lat = _campaign.lastTravelLat ?? 0;
    final lng = _campaign.lastTravelLng ?? 0;
    final seedLat = (lat.abs() * 1000).round();
    final seedLng = (lng.abs() * 1000).round();
    final seed =
        (seedLat * 1000003) ^ seedLng ^ (_campaign.encounterNumber * 31);
    final rng = Random(seed);

    // Distance-based scaling: penalties are harsher the further from home
    final distanceKm = _distanceToHomeTownKm() ?? 0.0;
    // Scale factor: 1.0 at home, up to 3.0 at 300km+
    final distanceScale = 1.0 + (distanceKm / 150.0).clamp(0.0, 2.0);
    final distanceNote = distanceKm > 50
        ? ' (${distanceKm.toStringAsFixed(0)}km from base)'
        : '';

    if (rng.nextBool() || _campaign.deck.isEmpty) {
      // Gold loss scales with distance: 10-20 base, up to 30-60 at max distance
      final baseGoldLoss = 10 + rng.nextInt(11); // 10-20
      final goldLoss = (baseGoldLoss * distanceScale).round();
      final actualLoss = goldLoss.clamp(0, _campaign.gold);
      setState(() {
        _campaign.spendGold(actualLoss);
      });
      _saveCampaign();
      return RewardEvent(
        title: 'Backtrack Cost',
        message: 'Lost -$actualLoss Gold while retreating$distanceNote',
        icon: Icons.money_off,
        iconColor: Colors.redAccent,
      );
    }

    // Card penalty: at long distances, card is gated for longer
    final gateEncounters = distanceKm > 200 ? 3 : (distanceKm > 100 ? 2 : 1);
    final idx = rng.nextInt(_campaign.deck.length);
    final card = _campaign.deck[idx];
    setState(() {
      _campaign.removeCardWithGate(card.id, gateEncounters: gateEncounters);
    });
    _saveCampaign();
    return RewardEvent(
      title: 'Backtrack Cost',
      message:
          '${card.name} is moved to Reserves during the retreat (available after $gateEncounters encounter${gateEncounters > 1 ? 's' : ''})$distanceNote',
      icon: Icons.sick,
      iconColor: Colors.orangeAccent,
    );
  }

  void _focusMapOnHero() {
    final townLat = _campaign.homeTownLat;
    final townLng = _campaign.homeTownLng;

    LatLng? heroPos;
    if (_campaign.lastTravelLat != null && _campaign.lastTravelLng != null) {
      heroPos = LatLng(_campaign.lastTravelLat!, _campaign.lastTravelLng!);
    } else if (townLat != null && townLng != null) {
      heroPos = LatLng(townLat, townLng);
    }
    if (heroPos == null) return;

    final zoom = _mapController.camera.zoom;
    _mapController.move(heroPos, zoom);
  }

  Future<void> _returnToPreviousNode() async {
    if (_campaign.visitedNodes.length < 2) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Return to Previous Node',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Returning counts as time passing and comes with a setback.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Return'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final prev = _campaign.visitedNodes[_campaign.visitedNodes.length - 2];

    final rewardEvents = <RewardEvent>[];
    rewardEvents.add(
      const RewardEvent(
        title: 'Backtrack',
        message: 'You return to the previous node.',
        icon: Icons.undo,
        iconColor: Colors.orangeAccent,
      ),
    );

    // Apply the penalty before updating the node list so it keys off the current state.
    rewardEvents.add(_applyReturnPenalty());

    setState(() {
      // Move hero back one node.
      _campaign.popVisitedNode();
      _campaign.lastTravelLat = prev.lat;
      _campaign.lastTravelLng = prev.lng;
      // Add a travel step so the route is visible.
      _campaign.addTravelPoint(prev.lat, prev.lng);
      // Counts as an iteration.
      _campaign.completeEncounter();
      _generateNewChoices();
    });

    await _saveCampaign();
    final deliveries = await _autoCollectHomeTownDeliveries(showDialogs: false);
    rewardEvents.addAll(deliveries);
    await _saveCampaign();

    if (!mounted) return;
    await _showCelebrationDialog(
      title: 'After-Action Report',
      events: rewardEvents,
    );
  }

  Future<void> _waitOneEncounter() async {
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Wait', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Waiting counts as time passing and comes with a setback.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Wait'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    _logSupply(
      'Wait: advance 1 encounter in place (encounter=${_campaign.encounterNumber})',
    );

    final rewardEvents = <RewardEvent>[];
    rewardEvents.add(
      const RewardEvent(
        title: 'Wait',
        message: 'You hold position and let time pass.',
        icon: Icons.hourglass_bottom,
        iconColor: Colors.orangeAccent,
      ),
    );

    rewardEvents.add(_applyReturnPenalty());

    // 1/5 chance to lose a card permanently
    final cardDeath = _tryRandomCardDeath();
    if (cardDeath != null) {
      rewardEvents.add(cardDeath);
    }

    setState(() {
      _campaign.completeEncounter();
      _generateNewChoices();
    });

    await _saveCampaign();
    final deliveries = await _autoCollectHomeTownDeliveries(showDialogs: false);
    rewardEvents.addAll(deliveries);
    await _saveCampaign();

    if (!mounted) return;
    await _showCelebrationDialog(
      title: 'After-Action Report',
      events: rewardEvents,
    );
  }

  RewardEvent _goldEvent(int amount) {
    final prefix = amount >= 0 ? '+' : '';
    return RewardEvent(
      title: 'Gold',
      message: '$prefix$amount Gold',
      icon: Icons.monetization_on,
      iconColor: Colors.amber,
    );
  }

  Future<void> _showCelebrationDialog({
    required String title,
    required List<RewardEvent> events,
  }) async {
    if (events.isEmpty) return;
    final navigator = Navigator.of(context);
    if (!mounted) return;

    // Track which cards have been added to deck during this dialog
    final addedToDeck = <String>{};

    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: events.map((e) {
                final canAddToDeck =
                    e.cardId != null &&
                    !addedToDeck.contains(e.cardId) &&
                    _campaign.inventory.any((c) => c.id == e.cardId);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(e.icon, color: e.iconColor, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              e.message,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            if (canAddToDeck) ...[
                              const SizedBox(height: 6),
                              ElevatedButton.icon(
                                onPressed: () {
                                  _campaign.addCardFromInventory(e.cardId!);
                                  _saveCampaign();
                                  addedToDeck.add(e.cardId!);
                                  setDialogState(() {});
                                  setState(() {});
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add to Deck'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[700],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 28),
                                ),
                              ),
                            ],
                            if (e.cardId != null &&
                                addedToDeck.contains(e.cardId))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green[400],
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Added to Deck',
                                      style: TextStyle(
                                        color: Colors.green[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initCampaign();
  }

  Future<void> _refreshHomeTownProgressionPerks() async {
    if (widget.leaderId != 'napoleon') {
      if (!mounted) return;
      setState(() {
        _homeTownBuildDiscountPercent = 0;
        _homeTownReduceDistancePenalty = false;
        _campaign.supplyDistancePenaltyReduction = 0;
      });
      return;
    }

    final data = await _persistence.loadProgression();
    final state = data != null
        ? NapoleonProgressionState.fromJson(data)
        : NapoleonProgressionState();
    final mods = state.modifiers;
    if (!mounted) return;
    setState(() {
      _homeTownBuildDiscountPercent = mods.shopDiscountPercent;
      _homeTownReduceDistancePenalty = state.hasEffect('continental_system');
      _campaign.supplyDistancePenaltyReduction = _homeTownReduceDistancePenalty
          ? 1
          : 0;
    });
  }

  List<ShopItem> _startingRelicOptions({
    required String leaderId,
    NapoleonProgressionState? napoleonProgression,
  }) {
    final all = ShopInventory.getAllRelics();
    final allowedIds = (leaderId == 'napoleon' && napoleonProgression != null)
        ? napoleonProgression.modifiers.startingRelicOptionIds
        : const <String>{'relic_gold_purse'};

    final options = <ShopItem>[];
    for (final r in all) {
      if (allowedIds.contains(r.id)) {
        options.add(r);
      }
    }

    if (options.isEmpty && all.isNotEmpty) {
      options.add(all.first);
    }

    return options;
  }

  Future<void> _runPreCampaignSetupIfNeeded({
    required String leaderId,
    required int act,
    NapoleonProgressionState? napoleonProgression,
  }) async {
    if (!mounted) return;

    if (_campaign.startingRelicId == null) {
      final relicOptions = _startingRelicOptions(
        leaderId: leaderId,
        napoleonProgression: napoleonProgression,
      ).where((r) => !_campaign.hasRelic(r.id)).toList();

      final selectedRelicId = relicOptions.isEmpty
          ? null
          : await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                title: const Text(
                  'What you choose to take on your journey',
                  style: TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in relicOptions)
                      ListTile(
                        leading: const Icon(
                          Icons.auto_awesome,
                          color: Colors.purple,
                        ),
                        title: Text(
                          r.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          r.description,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        onTap: () => Navigator.pop(context, r.id),
                      ),
                  ],
                ),
              ),
            );

      if (selectedRelicId != null) {
        _campaign.startingRelicId = selectedRelicId;
        _campaign.addRelic(selectedRelicId);
      }
    }

    if (!mounted) return;

    // Story mode: remove the pre-first-encounter special card selection.
    // Use an empty sentinel so we don't re-prompt on next app launch.
    _campaign.startingSpecialCardId ??= '';
  }

  Future<void> _initCampaign() async {
    if (widget.savedState != null) {
      _campaign = widget.savedState!;
      _generator = EncounterGenerator(act: _campaign.act);

      _initMapRelicIfNeeded();
      _initHomeTownIfNeeded();
      await _refreshHomeTownProgressionPerks();
    } else {
      _generator = EncounterGenerator(act: widget.act);

      // Get starter deck for leader
      final deck = widget.leaderId == 'napoleon'
          ? buildNapoleonStarterDeck()
          : buildStarterCardPool();

      int startingGold = 50;
      int startingMaxHealth = 50;
      int startingHealth = 50;

      NapoleonProgressionState? napoleonProgression;
      if (widget.leaderId == 'napoleon') {
        final progressionData = await _persistence.loadProgression();
        napoleonProgression = progressionData != null
            ? NapoleonProgressionState.fromJson(progressionData)
            : NapoleonProgressionState();
        final mods = napoleonProgression.modifiers;

        startingGold += mods.startingGoldBonus;
        startingMaxHealth += mods.campaignMaxHpBonus;
        startingHealth += mods.campaignMaxHpBonus;

        debugPrint(
          'CAMPAIGN START BONUSES: leader=${widget.leaderId}, startingGold=$startingGold (base 50), hp=$startingHealth/$startingMaxHealth, points=${napoleonProgression.progressionPoints}, unlocked=[${napoleonProgression.unlockedNodes.join(", ")}]',
        );
        if (napoleonProgression.unimplementedEffects.isNotEmpty) {
          debugPrint(
            'CAMPAIGN START: Unimplemented progression effects: ${napoleonProgression.unimplementedEffects.join(", ")}',
          );
        }
      }

      _campaign = CampaignState(
        id: 'campaign_${DateTime.now().millisecondsSinceEpoch}',
        leaderId: widget.leaderId,
        act: widget.act,
        gold: startingGold,
        health: startingHealth,
        maxHealth: startingMaxHealth,
        deck: deck,
        startedAt: DateTime.now(),
      );

      _initMapRelicIfNeeded();
      _initHomeTownIfNeeded();
      await _refreshHomeTownProgressionPerks();

      await _runPreCampaignSetupIfNeeded(
        leaderId: widget.leaderId,
        act: widget.act,
        napoleonProgression: napoleonProgression,
      );

      // Generate initial choices
      _generateNewChoices();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // Save initial state
    await _saveCampaign();

    // Start initial production for all buildings
    await _autoCollectHomeTownDeliveries(showDialogs: false);
  }

  bool get _isNapoleonRealMapEnabled {
    return widget.leaderId == 'napoleon' &&
        _campaign.act >= 1 &&
        _campaign.act <= 3;
  }

  void _initMapRelicIfNeeded() {
    if (!_isNapoleonRealMapEnabled) return;
    if (_campaign.mapRelicDiscovered) return;
    if (_campaign.mapRelicLat != null && _campaign.mapRelicLng != null) return;

    final pool = _mapRelicCandidateLocationsForAct(_campaign.act);
    if (pool.isEmpty) return;

    final base = pool[_random.nextInt(pool.length)];

    // Small jitter to avoid always matching a city center exactly.
    final jitterLat = (_random.nextDouble() - 0.5) * 0.16;
    final jitterLng = (_random.nextDouble() - 0.5) * 0.16;

    _campaign.mapRelicLat = base.latitude + jitterLat;
    _campaign.mapRelicLng = base.longitude + jitterLng;
  }

  void _initHomeTownIfNeeded() {
    if (!_isNapoleonRealMapEnabled) return;
    if (_campaign.homeTownName != null &&
        _campaign.homeTownLat != null &&
        _campaign.homeTownLng != null) {
      _ensureHomeTownStarterBuildings();

      // Backward compat: older saves may have buildings with lastCollectedEncounter = -1.
      // Keep them as -99 so they're ready to produce immediately.
      final updated = _campaign.homeTownBuildings
          .map(
            (b) => b.lastCollectedEncounter == -1
                ? HomeTownBuilding(
                    id: b.id,
                    level: b.level,
                    lastCollectedEncounter: -99, // Ready to produce immediately
                  )
                : b,
          )
          .toList();
      _campaign.homeTownBuildings = updated;
      return;
    }

    switch (_campaign.act) {
      case 2:
        _campaign.homeTownName = 'Alexandria';
        _campaign.homeTownLat = 31.2001;
        _campaign.homeTownLng = 29.9187;

        _campaign.campaignEndLat = 30.0444; // Cairo
        _campaign.campaignEndLng = 31.2357;
        break;
      case 3:
        _campaign.homeTownName = 'Paris';
        _campaign.homeTownLat = 48.8566;
        _campaign.homeTownLng = 2.3522;

        _campaign.campaignEndLat = 49.1390; // Austerlitz (Slavkov u Brna)
        _campaign.campaignEndLng = 16.7630;
        break;
      default:
        _campaign.homeTownName = 'Nice';
        _campaign.homeTownLat = 43.695;
        _campaign.homeTownLng = 7.264;

        _campaign.campaignEndLat = 45.4642; // Milan
        _campaign.campaignEndLng = 9.1900;
        break;
    }

    _campaign.homeTownLevel = _campaign.homeTownLevel.clamp(1, 99);

    _ensureHomeTownStarterBuildings();
  }

  void _ensureHomeTownStarterBuildings() {
    if (_campaign.homeTownBuildings.any(
      (b) => b.id == _buildingTrainingGroundsId,
    )) {
      return;
    }
    _campaign.homeTownBuildings = [
      ..._campaign.homeTownBuildings,
      HomeTownBuilding(
        id: _buildingTrainingGroundsId,
        lastCollectedEncounter: -99, // Ready to produce immediately
      ),
    ];
  }

  List<LatLng> _mapRelicCandidateLocationsForAct(int act) {
    switch (act) {
      case 2:
        return const [
          LatLng(31.2001, 29.9187), // Alexandria
          LatLng(31.3986, 30.4170), // Rosetta
          LatLng(31.4165, 31.8144), // Damietta
          LatLng(30.0131, 31.2089), // Giza
          LatLng(30.0444, 31.2357), // Cairo
        ];
      case 3:
        return const [
          LatLng(49.1193, 6.1757), // Metz
          LatLng(48.5734, 7.7521), // Strasbourg
          LatLng(48.4011, 9.9876), // Ulm
          LatLng(48.2082, 16.3738), // Vienna
          LatLng(49.1951, 16.6068), // Brno
        ];
      default:
        return const [
          LatLng(44.107, 7.669),
          LatLng(44.384, 7.823),
          LatLng(44.418, 8.869),
          LatLng(44.913, 8.616),
          LatLng(45.041, 7.657),
          LatLng(45.184, 9.159),
          LatLng(45.309, 9.503),
          LatLng(45.263, 10.992),
        ];
    }
  }

  Future<void> _maybeDiscoverMapRelicAfterEncounter(Encounter encounter) async {
    if (!_isNapoleonRealMapEnabled) return;
    if (_campaign.mapRelicDiscovered) return;
    if (_campaign.hasRelic(_campaignMapRelicId)) return;

    final relicLat = _campaign.mapRelicLat;
    final relicLng = _campaign.mapRelicLng;
    final travelLat = _campaign.lastTravelLat;
    final travelLng = _campaign.lastTravelLng;
    if (relicLat == null ||
        relicLng == null ||
        travelLat == null ||
        travelLng == null) {
      return;
    }

    final isEligible =
        encounter.type == EncounterType.event ||
        encounter.type == EncounterType.treasure;
    if (!isEligible) return;

    final distanceMeters = const Distance()(
      LatLng(travelLat, travelLng),
      LatLng(relicLat, relicLng),
    );
    if (distanceMeters > _mapRelicDiscoverDistanceMeters) return;

    if (!mounted) return;

    final rewardPool = ShopInventory.getCardsForAct(_campaign.act);
    GameCard? rewardCard;
    if (rewardPool.isNotEmpty) {
      rewardPool.shuffle(_random);
      rewardCard = rewardPool.first;
    }

    setState(() {
      _campaign.mapRelicDiscovered = true;
      _campaign.addRelic(_campaignMapRelicId);

      if (rewardCard != null) {
        _campaign.addCardToReserves(rewardCard);
      }
    });
    await _saveCampaign();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Map Relic Found!',
          style: TextStyle(color: Colors.purpleAccent),
        ),
        content: const Text(
          'Your scouts uncover a hidden cache while exploring the area.',
          style: TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        actions: [
          if (rewardCard != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recovered: ${rewardCard.name} (sent to Reserves)',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Claim'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCampaign() async {
    await _persistence.saveCampaign(_campaign);
  }

  List<String> _campaignBuffLabelsForBattle({
    required NapoleonProgressionModifiers mods,
    int defenseDamageBonus = 0,
    int defenseHealthBonus = 0,
  }) {
    final labels = <String>[];

    if (_campaign.hasRelic('relic_armor')) {
      labels.add("Relic: Officer's Armor (+10 max HP)");
    }
    if (_campaign.hasRelic('legendary_relic_armor')) {
      labels.add("Relic: Marshal's Armor (+20 max HP)");
    }

    if (_campaign.isRelicActive('relic_morale')) {
      labels.add('Relic: Battle Standard (+1 damage to all units)');
    }
    if (_campaign.isRelicActive('legendary_relic_morale')) {
      labels.add('Relic: Imperial Standard (+2 damage to all units)');
    }

    if (_campaign.isRelicActive('relic_gold_purse')) {
      labels.add('Relic: War Chest (+10 gold after each battle)');
    }
    if (_campaign.isRelicActive('legendary_relic_gold_purse')) {
      labels.add('Relic: Imperial Treasury (+20 gold after each battle)');
    }

    if (_campaign.isRelicActive('relic_supply_routes')) {
      labels.add('Relic: Supply Routes (Home Town distance penalty -1)');
    }

    if (_campaign.isRelicActive('campaign_map_relic')) {
      labels.add('Relic: Map Relic (+1 HP to all Cannons)');
    }

    if (defenseDamageBonus > 0) {
      labels.add('Defense: +$defenseDamageBonus damage this battle');
    }
    if (defenseHealthBonus > 0) {
      labels.add('Defense: +$defenseHealthBonus HP this battle');
    }

    return labels;
  }

  List<String> _campaignBuffLabelsForBuffsDialog({
    required NapoleonProgressionModifiers mods,
    int defenseDamageBonus = 0,
    int defenseHealthBonus = 0,
  }) {
    final labels = _campaignBuffLabelsForBattle(
      mods: mods,
      defenseDamageBonus: defenseDamageBonus,
      defenseHealthBonus: defenseHealthBonus,
    );

    if (mods.extraStartingDraw > 0) {
      labels.add('Bonus: +${mods.extraStartingDraw} starting draw');
    }
    if (mods.artilleryDamageBonus > 0) {
      labels.add('Bonus: Artillery +${mods.artilleryDamageBonus} damage');
    }
    if (mods.heroAbilityDamageBoost > 0) {
      labels.add('Bonus: Hero ability +${mods.heroAbilityDamageBoost} damage');
    }
    return labels;
  }

  String _homeTownBuildingName(String id) {
    switch (id) {
      case _buildingTrainingGroundsId:
        return 'Training Grounds';
      case _buildingSupplyDepotId:
        return 'Supply Depot';
      case _buildingOfficersAcademyId:
        return 'Officers Academy';
      case _buildingWarCollegeId:
        return 'War College';
      case _buildingMedicCorpsId:
        return 'Medic Corps';
      default:
        return id;
    }
  }

  String _homeTownBuildingDescription(String id) {
    switch (id) {
      case _buildingTrainingGroundsId:
        return 'Provides a common unit card once per encounter.';
      case _buildingSupplyDepotId:
        return 'Passive: +15 gold per encounter.';
      case _buildingOfficersAcademyId:
        return 'Provides a rare unit card on a longer supply schedule.';
      case _buildingWarCollegeId:
        return 'Provides an epic unit card on a longer supply schedule.';
      case _buildingMedicCorpsId:
        return 'Provides a Medic card (tier based on current Act).';
      default:
        return '';
    }
  }

  int _homeTownBuildCost(String id) {
    switch (id) {
      case _buildingSupplyDepotId:
        return 60;
      case _buildingOfficersAcademyId:
        return 110;
      case _buildingWarCollegeId:
        return 160;
      case _buildingMedicCorpsId:
        return 80;
      default:
        return 0;
    }
  }

  /// Calculate supply time modifier based on distance from home town.
  /// Returns negative value (bonus) when close, positive (penalty) when far.
  int _distanceSupplyModifierEncounters() {
    final travelLat = _campaign.lastTravelLat;
    final travelLng = _campaign.lastTravelLng;
    if (travelLat == null || travelLng == null) {
      return 0;
    }

    return _distanceSupplyModifierEncountersAt(
      travelLat: travelLat,
      travelLng: travelLng,
    );
  }

  /// Legacy wrapper for UI that expects only penalties (non-negative values)
  int _distanceSupplyPenaltyEncounters() {
    final modifier = _distanceSupplyModifierEncounters();
    return modifier > 0 ? modifier : 0;
  }

  double? _distanceToHomeTownKm() {
    final townLat = _campaign.homeTownLat;
    final townLng = _campaign.homeTownLng;
    final travelLat = _campaign.lastTravelLat;
    final travelLng = _campaign.lastTravelLng;
    if (townLat == null ||
        townLng == null ||
        travelLat == null ||
        travelLng == null) {
      return null;
    }
    final distanceMeters = const Distance()(
      LatLng(travelLat, travelLng),
      LatLng(townLat, townLng),
    );
    return distanceMeters / 1000.0;
  }

  int _buildingBaseSupplyEveryEncounters(HomeTownBuilding building) {
    return switch (building.id) {
      _buildingTrainingGroundsId => 1,
      _buildingSupplyDepotId => 1,
      _buildingOfficersAcademyId => 3,
      _buildingWarCollegeId => 4,
      _buildingMedicCorpsId => 2,
      _ => 1,
    };
  }

  int _buildingSupplyEveryEncounters(HomeTownBuilding building) {
    final modifier = _distanceSupplyModifierEncounters();
    final base = _buildingBaseSupplyEveryEncounters(building);
    // Ensure supply time is at least 1 encounter
    return (base + modifier).clamp(1, 99);
  }

  String _buildingProducingStatusText(HomeTownBuilding building) {
    if (building.id == _buildingSupplyDepotId) {
      return '';
    }
    final producing = _campaign.pendingCardDeliveries
        .where(
          (d) =>
              d.sourceBuildingId == building.id &&
              _campaign.encountersUntilDeliveryProduced(d) > 0,
        )
        .toList();
    if (producing.isEmpty) return '';

    producing.sort(
      (a, b) => _campaign
          .encountersUntilDeliveryProduced(a)
          .compareTo(_campaign.encountersUntilDeliveryProduced(b)),
    );
    final d = producing.first;
    final producingRemaining = _campaign.encountersUntilDeliveryProduced(d);
    return 'Production: ${d.card.name} - $producingRemaining encounter${producingRemaining == 1 ? '' : 's'}';
  }

  String _buildingTravelingStatusText(HomeTownBuilding building) {
    if (building.id == _buildingSupplyDepotId) {
      return '';
    }
    final traveling = _campaign.pendingCardDeliveries
        .where(
          (d) =>
              d.sourceBuildingId == building.id &&
              _campaign.encountersUntilDeliveryProduced(d) <= 0,
        )
        .toList();
    if (traveling.isEmpty) return '';

    traveling.sort(
      (a, b) => _campaign
          .encountersUntilDeliveryArrives(a)
          .compareTo(_campaign.encountersUntilDeliveryArrives(b)),
    );
    final d = traveling.first;
    final remaining = _campaign.encountersUntilDeliveryArrives(d);
    if (remaining <= 0) {
      return 'Traveling: ${d.card.name} - arriving now';
    }
    return 'Traveling: ${d.card.name} - $remaining encounter${remaining == 1 ? '' : 's'}';
  }

  bool _canCollectBuilding(HomeTownBuilding building) {
    final interval = _buildingSupplyEveryEncounters(building);
    return (_campaign.encounterNumber - building.lastCollectedEncounter) >=
        interval;
  }

  Future<void> _hurryHomeTownSupply() async {
    const cost = 100;
    if (_campaign.gold < cost) return;

    setState(() {
      _campaign.spendGold(cost);

      if (_campaign.pendingCardDeliveries.isNotEmpty) {
        _campaign.pendingCardDeliveries = _campaign.pendingCardDeliveries.map((
          d,
        ) {
          final remaining = _campaign.encountersUntilDeliveryArrives(d);
          if (remaining <= 1) return d;
          return PendingCardDelivery(
            id: d.id,
            sourceBuildingId: d.sourceBuildingId,
            card: d.card,
            scheduledAtEncounter: d.scheduledAtEncounter,
            productionDurationEncounters: d.productionDurationEncounters,
            traveledKm: d.traveledKm,
            forcedArrivesAtEncounter: _campaign.encounterNumber + 1,
          );
        }).toList();
      }

      for (final b in _campaign.homeTownBuildings) {
        final interval = _buildingSupplyEveryEncounters(b);
        final sinceLast = _campaign.encounterNumber - b.lastCollectedEncounter;
        final remaining = interval - sinceLast;
        if (remaining <= 1) continue;

        // Make it ready in exactly 1 encounter.
        final desiredSinceLast = interval - 1;
        b.lastCollectedEncounter = _campaign.encounterNumber - desiredSinceLast;
      }
    });

    await _saveCampaign();
  }

  Future<void> _showHomeTownDeliveryDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) async {
    final navigator = Navigator.of(context);
    if (!mounted) return;
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show dialog for multiple deliveries at the same location
  Future<void> _showMultipleDeliveriesDialog({
    required List<
      ({PendingCardDelivery delivery, String phase, int eta, int prodRemaining})
    >
    deliveries,
  }) async {
    final navigator = Navigator.of(context);
    if (!mounted) return;

    final km = _campaign.distanceHomeToHeroKm();
    final distanceText = km != null ? '${km.toStringAsFixed(0)} km' : 'unknown';

    String enc(int n) => n == 1 ? '1 encounter' : '$n encounters';

    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            const Icon(Icons.local_shipping, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Supply Deliveries (${deliveries.length})',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Distance to hero: $distanceText',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...deliveries.map((d) {
                final delivery = d.delivery;
                final phase = d.phase;
                final eta = d.eta;
                final prodRemaining = d.prodRemaining;
                final buildingName = _homeTownBuildingName(
                  delivery.sourceBuildingId,
                );
                final cardName = delivery.card.name;
                final prodDone = prodRemaining <= 0;
                final travelDone = prodDone && eta <= 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            phase == 'Producing'
                                ? Icons.build
                                : Icons.directions,
                            color: phase == 'Producing'
                                ? Colors.orangeAccent
                                : Colors.greenAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              cardName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'From: $buildingName',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        travelDone
                            ? 'Arriving now!'
                            : prodDone
                            ? 'Traveling: ${enc(eta)}'
                            : 'Producing: ${enc(prodRemaining)}',
                        style: TextStyle(
                          color: travelDone
                              ? Colors.greenAccent
                              : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeliveryDetailsDialog({
    required PendingCardDelivery delivery,
    required String phase,
    required int eta,
    required int prodRemaining,
  }) async {
    final navigator = Navigator.of(context);
    if (!mounted) return;

    final buildingName = _homeTownBuildingName(delivery.sourceBuildingId);
    final cardName = delivery.card.name;
    final km = _campaign.distanceHomeToHeroKm();
    final distanceText = km != null ? '${km.toStringAsFixed(0)} km' : 'unknown';

    // Production time (based on rarity)
    final totalProdTime = delivery.productionDurationEncounters;
    final prodDone = prodRemaining <= 0;

    // Travel time (based on distance)
    final travelDuration = _campaign.currentTravelDurationEncounters();
    final travelRemaining = prodDone ? eta : travelDuration;
    final travelDone = prodDone && eta <= 0;

    // Total ETA
    final totalEta = eta;

    String enc(int n) => n == 1 ? '1 encounter' : '$n encounters';

    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(
              Icons.local_shipping,
              color: phase == 'Producing'
                  ? Colors.orangeAccent
                  : Colors.greenAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Supply Delivery',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cargo: $cardName',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'From: $buildingName → To: Hero',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Distance: $distanceText',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Production row
            _buildTimelineRow(
              icon: Icons.build,
              label: 'Production',
              duration: enc(totalProdTime),
              status: prodDone ? 'Complete' : '$prodRemaining left',
              isComplete: prodDone,
              isActive: !prodDone,
            ),
            const SizedBox(height: 8),

            // Travel row
            _buildTimelineRow(
              icon: Icons.directions,
              label: 'Travel',
              duration: enc(travelDuration),
              status: travelDone
                  ? 'Arrived'
                  : prodDone
                  ? '$travelRemaining left'
                  : 'Waiting',
              isComplete: travelDone,
              isActive: prodDone && !travelDone,
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),

            // Total ETA
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Total ETA: ',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  totalEta <= 0 ? 'Arriving now!' : enc(totalEta),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineRow({
    required IconData icon,
    required String label,
    required String duration,
    required String status,
    required bool isComplete,
    required bool isActive,
  }) {
    final Color color = isComplete
        ? Colors.greenAccent
        : isActive
        ? Colors.orangeAccent
        : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.orange.withValues(alpha: 0.15)
            : isComplete
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? Colors.orangeAccent.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  duration,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isComplete
                  ? Colors.green.withValues(alpha: 0.3)
                  : isActive
                  ? Colors.orange.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEncounterRewardDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) async {
    final navigator = Navigator.of(context);
    if (!mounted) return;
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<RewardEvent?> _applyEncounterOffer(
    Encounter encounter, {
    bool showDialog = true,
  }) async {
    final type = encounter.offerType;
    final id = encounter.offerId;
    if (type == null || id == null || id.isEmpty) return null;
    final amount = encounter.offerAmount ?? 1;

    String message = '';
    IconData icon = Icons.card_giftcard;
    Color iconColor = Colors.amber;

    if (type == 'consumable') {
      // Backward compat: ignore legacy/unknown consumables (e.g. remove_card)
      if (!_isValidConsumableOfferId(id)) return null;
      setState(() {
        _campaign.addConsumable(id, count: amount);
      });
      final all = ShopInventory.getAllConsumables();
      final item = all.where((e) => e.id == id).toList();
      final name = item.isNotEmpty ? item.first.name : id;
      message = 'Received: $name ×$amount';
      icon = Icons.local_hospital;
      iconColor = Colors.greenAccent;
    } else if (type == 'relic') {
      // Allow duplicate relics - each copy stacks
      setState(() {
        _campaign.addRelic(id);
      });
      final all = ShopInventory.getAllRelics();
      final item = all.where((e) => e.id == id).toList();
      final name = item.isNotEmpty ? item.first.name : id;
      message = 'Received: $name';
      icon = Icons.auto_awesome;
      iconColor = Colors.purpleAccent;
    } else {
      return null;
    }

    await _saveCampaign();
    final event = RewardEvent(
      title: 'Reward',
      message: message,
      icon: icon,
      iconColor: iconColor,
    );
    if (showDialog) {
      await _showEncounterRewardDialog(
        title: event.title,
        message: event.message,
        icon: event.icon,
        iconColor: event.iconColor,
      );
    }
    return event;
  }

  String _encounterOfferLabel(Encounter encounter) {
    final type = encounter.offerType;
    final id = encounter.offerId;
    if (type == null || id == null || id.isEmpty) return '';
    final amount = encounter.offerAmount ?? 1;

    if (type == 'consumable') {
      final all = ShopInventory.getAllConsumables();
      final item = all.where((e) => e.id == id).toList();
      // Backward compat: hide legacy/unknown consumables (e.g. remove_card)
      if (item.isEmpty) return '';
      final name = item.isNotEmpty ? item.first.name : id;
      final description = item.isNotEmpty ? item.first.description : '';
      final headline = amount > 1 ? 'Offer: $name ×$amount' : 'Offer: $name';
      return description.isNotEmpty ? '$headline\n$description' : headline;
    }
    if (type == 'relic') {
      final all = ShopInventory.getAllRelics();
      final item = all.where((e) => e.id == id).toList();
      final name = item.isNotEmpty ? item.first.name : id;
      final description = item.isNotEmpty ? item.first.description : '';
      final headline = 'Offer: $name';
      return description.isNotEmpty ? '$headline\n$description' : headline;
    }
    return 'Offer: $id';
  }

  IconData _encounterOfferIcon(Encounter encounter) {
    switch (encounter.offerType) {
      case 'consumable':
        return Icons.local_hospital;
      case 'relic':
        return Icons.auto_awesome;
      default:
        return Icons.card_giftcard;
    }
  }

  Color _encounterOfferColor(Encounter encounter) {
    switch (encounter.offerType) {
      case 'consumable':
        return Colors.greenAccent;
      case 'relic':
        return Colors.purpleAccent;
      default:
        return Colors.amber;
    }
  }

  /// Show terrain picker dialog for higher-rarity buildings
  Future<String?> _showTerrainPickerDialog({
    required String buildingName,
    required List<GameCard> availableCards,
  }) async {
    // Get unique terrains from available cards
    final terrains = availableCards
        .map((c) => c.element)
        .where((e) => e != null)
        .cast<String>()
        .toSet()
        .toList();

    if (terrains.isEmpty) return null;
    if (terrains.length == 1) return terrains.first;

    final navigator = Navigator.of(context);
    return showDialog<String>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Text(
          '$buildingName - Choose Terrain',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select terrain specialization for your unit:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ...terrains.map((terrain) {
              final cardsForTerrain = availableCards
                  .where((c) => c.element == terrain)
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, terrain),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _terrainColor(terrain),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_terrainIcon(terrain), color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '$terrain (${cardsForTerrain.length} units)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  IconData _terrainIcon(String? terrain) {
    switch (terrain) {
      case 'Woods':
        return Icons.park;
      case 'Lake':
        return Icons.water;
      case 'Desert':
        return Icons.wb_sunny;
      default:
        return Icons.landscape;
    }
  }

  Color _terrainColor(String? terrain) {
    switch (terrain) {
      case 'Woods':
        return Colors.green[700]!;
      case 'Lake':
        return Colors.blue[700]!;
      case 'Desert':
        return Colors.orange[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  Future<RewardEvent?> _collectBuilding(
    HomeTownBuilding building, {
    bool showDialog = true,
    bool forceStart = false,
  }) async {
    if (!forceStart && !_canCollectBuilding(building)) return null;

    if (building.id == _buildingTrainingGroundsId) {
      // Training Grounds produces only common cards (rarity 1)
      final candidates = ShopInventory.getCardsForAct(
        _campaign.act,
      ).where((c) => c.rarity == 1).toList();
      if (candidates.isNotEmpty) {
        candidates.shuffle(_random);
        final card = candidates.first;
        final productionDuration = _campaign.supplyProductionDurationForCard(
          card,
        );
        final travelDuration = _campaign.currentTravelDurationEncounters();
        _logSupply(
          'Production start: building=${building.id} prod=$productionDuration travel=$travelDuration lastCollected=${building.lastCollectedEncounter} now=${_campaign.encounterNumber} card=${card.id}:${card.name}',
        );
        PendingCardDelivery? created;
        setState(() {
          created = _campaign.enqueueCardDelivery(
            sourceBuildingId: building.id,
            card: card,
          );
          building.lastCollectedEncounter = _campaign.encounterNumber;
        });
        await _saveCampaign();
        final remaining = created == null
            ? 0
            : _campaign.encountersUntilDeliveryArrives(created!);
        final event = RewardEvent(
          title: 'Training Grounds',
          message:
              'Production started: ${card.name} (ETA: $remaining encounters)',
          icon: Icons.military_tech,
          iconColor: Colors.greenAccent,
        );
        if (showDialog) {
          await _showHomeTownDeliveryDialog(
            title: event.title,
            message: event.message,
            icon: event.icon,
            iconColor: event.iconColor,
          );
        }
        return event;
      }
      return null;
    }

    if (building.id == _buildingSupplyDepotId) {
      return null;
    }

    if (building.id == _buildingOfficersAcademyId) {
      final allCandidates = ShopInventory.getCardsForAct(
        _campaign.act,
      ).where((c) => c.rarity == 2).toList();
      if (allCandidates.isEmpty) return null;

      // Use preferred terrain during auto/forced production to avoid going idle.
      // Only prompt when user-initiated.
      final String? selectedTerrain = forceStart
          ? (building.preferredTerrain ??
                await _showTerrainPickerDialog(
                  buildingName: 'Officers Academy',
                  availableCards: allCandidates,
                ))
          : await _showTerrainPickerDialog(
              buildingName: 'Officers Academy',
              availableCards: allCandidates,
            );
      if (selectedTerrain == null) return null; // User cancelled or no terrain

      // Persist selection so future auto-cycles can reuse it.
      building.preferredTerrain = selectedTerrain;

      final candidates = allCandidates
          .where((c) => c.element == selectedTerrain)
          .toList();
      if (candidates.isNotEmpty) {
        candidates.shuffle(_random);
        final card = candidates.first;
        final productionDuration = _campaign.supplyProductionDurationForCard(
          card,
        );
        final travelDuration = _campaign.currentTravelDurationEncounters();
        _logSupply(
          'Production start: building=${building.id} prod=$productionDuration travel=$travelDuration lastCollected=${building.lastCollectedEncounter} now=${_campaign.encounterNumber} card=${card.id}:${card.name}',
        );
        PendingCardDelivery? created;
        setState(() {
          created = _campaign.enqueueCardDelivery(
            sourceBuildingId: building.id,
            card: card,
          );
          building.lastCollectedEncounter = _campaign.encounterNumber;
        });
        await _saveCampaign();
        final remaining = created == null
            ? 0
            : _campaign.encountersUntilDeliveryArrives(created!);
        final event = RewardEvent(
          title: 'Officers Academy',
          message:
              'Production started: ${card.name} (ETA: $remaining encounters)',
          icon: Icons.school,
          iconColor: Colors.lightBlueAccent,
        );
        if (showDialog) {
          await _showHomeTownDeliveryDialog(
            title: event.title,
            message: event.message,
            icon: event.icon,
            iconColor: event.iconColor,
          );
        }
        return event;
      }
      return null;
    }

    if (building.id == _buildingWarCollegeId) {
      final allCandidates = ShopInventory.getCardsForAct(
        _campaign.act,
      ).where((c) => c.rarity == 3).toList();
      if (allCandidates.isEmpty) return null;

      // Use preferred terrain during auto/forced production to avoid going idle.
      // Only prompt when user-initiated.
      final String? selectedTerrain = forceStart
          ? (building.preferredTerrain ??
                await _showTerrainPickerDialog(
                  buildingName: 'War College',
                  availableCards: allCandidates,
                ))
          : await _showTerrainPickerDialog(
              buildingName: 'War College',
              availableCards: allCandidates,
            );
      if (selectedTerrain == null) return null; // User cancelled or no terrain

      // Persist selection so future auto-cycles can reuse it.
      building.preferredTerrain = selectedTerrain;

      final candidates = allCandidates
          .where((c) => c.element == selectedTerrain)
          .toList();
      if (candidates.isNotEmpty) {
        candidates.shuffle(_random);
        final card = candidates.first;
        final productionDuration = _campaign.supplyProductionDurationForCard(
          card,
        );
        final travelDuration = _campaign.currentTravelDurationEncounters();
        _logSupply(
          'Production start: building=${building.id} prod=$productionDuration travel=$travelDuration lastCollected=${building.lastCollectedEncounter} now=${_campaign.encounterNumber} card=${card.id}:${card.name}',
        );
        PendingCardDelivery? created;
        setState(() {
          created = _campaign.enqueueCardDelivery(
            sourceBuildingId: building.id,
            card: card,
          );
          building.lastCollectedEncounter = _campaign.encounterNumber;
        });
        await _saveCampaign();
        final remaining = created == null
            ? 0
            : _campaign.encountersUntilDeliveryArrives(created!);
        final event = RewardEvent(
          title: 'War College',
          message:
              'Production started: ${card.name} (ETA: $remaining encounters)',
          icon: Icons.auto_awesome,
          iconColor: Colors.purpleAccent,
        );
        if (showDialog) {
          await _showHomeTownDeliveryDialog(
            title: event.title,
            message: event.message,
            icon: event.icon,
            iconColor: event.iconColor,
          );
        }
        return event;
      }
      return null;
    }

    if (building.id == _buildingMedicCorpsId) {
      // Produce medic card based on current act
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final GameCard card;
      switch (_campaign.act) {
        case 2:
          card = advancedMedic(timestamp);
          break;
        case 3:
          card = expertMedic(timestamp);
          break;
        default:
          card = basicMedic(timestamp);
      }
      final productionDuration = _campaign.supplyProductionDurationForCard(
        card,
      );
      final travelDuration = _campaign.currentTravelDurationEncounters();
      _logSupply(
        'Production start: building=${building.id} prod=$productionDuration travel=$travelDuration lastCollected=${building.lastCollectedEncounter} now=${_campaign.encounterNumber} card=${card.id}:${card.name}',
      );
      PendingCardDelivery? created;
      setState(() {
        created = _campaign.enqueueCardDelivery(
          sourceBuildingId: building.id,
          card: card,
        );
        building.lastCollectedEncounter = _campaign.encounterNumber;
      });
      await _saveCampaign();
      final remaining = created == null
          ? 0
          : _campaign.encountersUntilDeliveryArrives(created!);
      final event = RewardEvent(
        title: 'Medic Corps',
        message:
            'Production started: ${card.name} (ETA: $remaining encounters)',
        icon: Icons.healing,
        iconColor: Colors.greenAccent,
      );
      if (showDialog) {
        await _showHomeTownDeliveryDialog(
          title: event.title,
          message: event.message,
          icon: event.icon,
          iconColor: event.iconColor,
        );
      }
      return event;
    }

    return null;
  }

  Future<List<RewardEvent>> _autoCollectHomeTownDeliveries({
    bool showDialogs = true,
  }) async {
    if (!mounted) return <RewardEvent>[];

    final buildings = _campaign.homeTownBuildings;
    if (buildings.isEmpty) return <RewardEvent>[];

    _logSupply(
      'AutoCollect start: encounter=${_campaign.encounterNumber} home=(${_campaign.homeTownLat},${_campaign.homeTownLng}) hero=(${_campaign.lastTravelLat},${_campaign.lastTravelLng}) km=${_distanceToHomeTownKm()?.toStringAsFixed(1) ?? "?"} modifier=${_distanceSupplyModifierEncounters()} pendingDeliveries=${_campaign.pendingCardDeliveries.length}',
    );

    final events = <RewardEvent>[];

    // Step 1: Move arrived deliveries into Reserves.
    final arrived = _campaign.collectArrivedDeliveries();
    final arrivedBuildingIds = arrived.map((d) => d.sourceBuildingId).toSet();
    if (arrived.isNotEmpty) {
      _logSupply(
        'Arrived deliveries: count=${arrived.length} (encounter=${_campaign.encounterNumber})',
      );
      for (final d in arrived) {
        _logSupply(
          'Delivery arrived: building=${d.sourceBuildingId} card=${d.card.id}:${d.card.name} scheduledAt=${d.scheduledAtEncounter} prod=${d.productionDurationEncounters} traveledKm=${d.traveledKm.toStringAsFixed(1)} forcedAt=${d.forcedArrivesAtEncounter ?? "-"}',
        );
        final title = 'Delivery Arrived';
        final message =
            '${d.card.name} (from ${_homeTownBuildingName(d.sourceBuildingId)})';
        final event = RewardEvent(
          title: title,
          message: message,
          icon: Icons.local_shipping,
          iconColor: Colors.greenAccent,
          cardId: d.card.id,
        );
        events.add(event);
        if (showDialogs) {
          await _showHomeTownDeliveryDialog(
            title: event.title,
            message: event.message,
            icon: event.icon,
            iconColor: event.iconColor,
          );
        }
      }
      await _saveCampaign();
    }

    for (final b in buildings) {
      if (b.id == _buildingSupplyDepotId) {
        continue;
      }

      // Check if this building currently has a unit in production
      final hasProducingUnit = _campaign.pendingCardDeliveries.any(
        (d) =>
            d.sourceBuildingId == b.id &&
            _campaign.encountersUntilDeliveryProduced(d) > 0,
      );

      // Check if this building has a unit traveling (finished production)
      final hasTravelingUnit = _campaign.pendingCardDeliveries.any(
        (d) =>
            d.sourceBuildingId == b.id &&
            _campaign.encountersUntilDeliveryProduced(d) <= 0,
      );

      // If a delivery just arrived for this building, start the next cycle
      // immediately (no "stale" encounter), even if the distance-based interval
      // increased since the previous cycle started.
      // Also start new production if: no unit producing AND (has traveling unit OR can collect)
      final canStartNow =
          !hasProducingUnit &&
          (arrivedBuildingIds.contains(b.id) ||
              (hasTravelingUnit || _canCollectBuilding(b)));
      if (!canStartNow) continue;

      // If a unit is already traveling for this building, start a new production
      // cycle immediately (no idle).
      final event = await _collectBuilding(
        b,
        showDialog: showDialogs,
        forceStart: hasTravelingUnit || arrivedBuildingIds.contains(b.id),
      );
      if (event != null) events.add(event);
      if (!mounted) return <RewardEvent>[];
    }

    return events;
  }

  RewardEvent? _applyRandomStoryOutcome(Encounter encounter) {
    final lat = _campaign.lastTravelLat ?? 0;
    final lng = _campaign.lastTravelLng ?? 0;
    final seedLat = (lat.abs() * 1000).round();
    final seedLng = (lng.abs() * 1000).round();
    final seed = encounter.id.hashCode ^ (seedLat * 1000003) ^ seedLng ^ 0x26;
    final rng = Random(seed);

    final roll = rng.nextDouble();
    if (roll < 0.40) return null;

    // Positive outcomes
    if (roll < 0.70) {
      if (rng.nextBool()) {
        final gold = 10 + rng.nextInt(11); // 10-20
        setState(() {
          _campaign.addGold(gold);
        });
        _saveCampaign();
        return RewardEvent(
          title: 'Fortune',
          message: 'Found +$gold Gold on the march',
          icon: Icons.attach_money,
          iconColor: Colors.amber,
        );
      }

      final candidates = ShopInventory.getCardsForAct(_campaign.act);
      if (candidates.isEmpty) return null;
      candidates.shuffle(rng);
      final card = candidates.first;
      setState(() {
        _campaign.addCard(card);
      });
      _saveCampaign();
      return RewardEvent(
        title: 'Reinforcements',
        message: 'Mercenaries join you: ${card.name}',
        icon: Icons.group_add,
        iconColor: Colors.greenAccent,
      );
    }

    // Negative outcomes
    if (rng.nextBool()) {
      final goldLoss = 5 + rng.nextInt(11); // 5-15
      setState(() {
        _campaign.spendGold(goldLoss.clamp(0, _campaign.gold));
      });
      _saveCampaign();
      return RewardEvent(
        title: 'Setback',
        message: 'Supplies lost: -$goldLoss Gold',
        icon: Icons.money_off,
        iconColor: Colors.redAccent,
      );
    }

    if (_campaign.deck.isEmpty) return null;
    final idx = rng.nextInt(_campaign.deck.length);
    final card = _campaign.deck[idx];
    setState(() {
      _campaign.removeCardWithGate(card.id);
    });
    _saveCampaign();
    return RewardEvent(
      title: 'Illness',
      message:
          '${card.name} is moved to Reserves (available after 1 encounter)',
      icon: Icons.sick,
      iconColor: Colors.orangeAccent,
    );
  }

  Future<void> _showBuildBuildingDialog() async {
    final alreadyBuilt = _campaign.homeTownBuildings.map((b) => b.id).toSet();

    await showDialog<void>(
      context: context,
      builder: (context) {
        final options = <String>[
          _buildingSupplyDepotId,
          _buildingOfficersAcademyId,
          _buildingWarCollegeId,
          _buildingMedicCorpsId,
        ].where((id) => !alreadyBuilt.contains(id)).toList();

        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text(
            'Build New Building',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: options.isEmpty
                ? const Text(
                    'No buildings available to build right now.',
                    style: TextStyle(color: Colors.white70),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final id = options[index];
                      final cost = _homeTownBuildCost(id);
                      final effectiveCost = _applyDiscount(
                        cost,
                        _homeTownBuildDiscountPercent,
                      );
                      final canAfford = _campaign.gold >= effectiveCost;

                      String producesText = _homeTownBuildingDescription(id);
                      if (id == _buildingSupplyDepotId) {
                        producesText = 'Passive: +15 Gold per encounter';
                      } else if (id == _buildingOfficersAcademyId) {
                        final candidates = ShopInventory.getCardsForAct(
                          _campaign.act,
                        ).where((c) => c.rarity == 2).toList();
                        final examples = candidates
                            .take(3)
                            .map((c) => c.name)
                            .toList();
                        final exampleText = examples.isEmpty
                            ? ''
                            : '\nExamples: ${examples.join(", ")}';
                        producesText = 'Produces: Rare unit card$exampleText';
                      } else if (id == _buildingWarCollegeId) {
                        final candidates = ShopInventory.getCardsForAct(
                          _campaign.act,
                        ).where((c) => c.rarity == 3).toList();
                        final examples = candidates
                            .take(3)
                            .map((c) => c.name)
                            .toList();
                        final exampleText = examples.isEmpty
                            ? ''
                            : '\nExamples: ${examples.join(", ")}';
                        producesText = 'Produces: Epic unit card$exampleText';
                      } else if (id == _buildingMedicCorpsId) {
                        final medicName = switch (_campaign.act) {
                          2 => 'Advanced Medic',
                          3 => 'Expert Medic',
                          _ => 'Field Medic',
                        };
                        producesText = 'Produces: $medicName (healer unit)';
                      }

                      return Card(
                        color: Colors.grey[850],
                        child: ListTile(
                          title: Text(
                            _homeTownBuildingName(id),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            producesText,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: ElevatedButton(
                            onPressed: canAfford
                                ? () async {
                                    setState(() {
                                      _campaign.spendGold(effectiveCost);
                                      // Set lastCollectedEncounter to -99 so building can start producing immediately
                                      _campaign.homeTownBuildings = [
                                        ..._campaign.homeTownBuildings,
                                        HomeTownBuilding(
                                          id: id,
                                          lastCollectedEncounter: -99,
                                        ),
                                      ];
                                    });
                                    await _saveCampaign();
                                    // Trigger production immediately for new building
                                    await _autoCollectHomeTownDeliveries(
                                      showDialogs: true,
                                    );
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canAfford
                                  ? Colors.amber[700]
                                  : Colors.grey,
                              foregroundColor: canAfford
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            child: Text('Build ($effectiveCost)'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openHomeTown() async {
    final navigator = Navigator.of(context);
    await _refreshHomeTownProgressionPerks();
    await _autoCollectHomeTownDeliveries();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final name = _campaign.homeTownName ?? 'Home Town';
          final buildings = _campaign.homeTownBuildings;
          final distanceKm = _distanceToHomeTownKm();
          final supplyPenalty = _distanceSupplyPenaltyEncounters();

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.home, color: Colors.amber, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_campaign.gold}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.place,
                          color: Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            distanceKm == null
                                ? 'Distance: Unknown'
                                : 'Distance: ${distanceKm.toStringAsFixed(0)} km',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        if (supplyPenalty > 0)
                          Text(
                            '+$supplyPenalty supply',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          const Text(
                            'No penalty',
                            style: TextStyle(color: Colors.greenAccent),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _campaign.gold >= 100
                          ? () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF2D2D2D),
                                  title: const Text(
                                    'Hurry Supply?',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: const Text(
                                    'Hurry Supply - Reduce all current supply times to 1 encounter\n\nCost: 100 Gold',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[700],
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Pay 100'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed != true) return;
                              await _hurryHomeTownSupply();
                              setSheetState(() {});
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Supply hurried: all ETAs reduced to 1 encounter.',
                                  ),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.flash_on),
                      label: const Text(
                        'Hurry Supply - Reduce all current supply times to 1 encounter',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.apartment,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Buildings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _showBuildBuildingDialog();
                          setSheetState(() {});
                        },
                        child: const Text('Build New'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (buildings.isEmpty)
                    const Text(
                      'No buildings yet.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else
                    ...buildings.map((b) {
                      final canCollect = _canCollectBuilding(b);
                      final prodTime = _buildingBaseSupplyEveryEncounters(b);
                      final isProductionBuilding =
                          b.id != _buildingSupplyDepotId;

                      // Prefer the currently producing card (if any) for the
                      // click-to-details behavior; otherwise fall back to the
                      // traveling card.
                      final deliveriesForBuilding = _campaign
                          .pendingCardDeliveries
                          .where((d) => d.sourceBuildingId == b.id)
                          .toList();
                      PendingCardDelivery? producing;
                      PendingCardDelivery? traveling;
                      for (final d in deliveriesForBuilding) {
                        if (_campaign.encountersUntilDeliveryProduced(d) > 0) {
                          producing ??= d;
                        } else {
                          traveling ??= d;
                        }
                      }
                      final currentCard = (producing ?? traveling)?.card;

                      return Card(
                        color: Colors.grey[850],
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          onTap: isProductionBuilding && currentCard != null
                              ? () => _showCardDetailsDialog(currentCard)
                              : null,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _homeTownBuildingName(b.id),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              if (isProductionBuilding && currentCard != null)
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.white38,
                                  size: 16,
                                ),
                            ],
                          ),
                          subtitle: Text(
                            [
                              _homeTownBuildingDescription(b.id),
                              _buildingProducingStatusText(b),
                              _buildingTravelingStatusText(b),
                            ].where((s) => s.trim().isNotEmpty).join('\n'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: isProductionBuilding
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      canCollect
                                          ? Icons.local_shipping
                                          : Icons.schedule,
                                      color: canCollect
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${prodTime}e',
                                      style: TextStyle(
                                        color: canCollect
                                            ? Colors.greenAccent
                                            : Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                )
                              : Icon(Icons.attach_money, color: Colors.amber),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _generateNewChoices() {
    final pendingDefense = _campaign.pendingDefenseEncounter;

    if (_campaign.recoveryEncountersRemaining > 0) {
      final choices = _generator.generateRecoveryChoices(
        _campaign.encounterNumber,
      );
      if (pendingDefense != null) {
        final alreadyIncluded = choices.any((e) => e.id == pendingDefense.id);
        if (!alreadyIncluded) {
          if (choices.isEmpty) {
            choices.add(pendingDefense);
          } else {
            choices[choices.length - 1] = pendingDefense;
          }
        }
      }
      _campaign.currentChoices = choices;
      return;
    }

    if (_campaign.isBossTime) {
      // Boss is available, but not forced: keep regular encounters as options.
      final boss = _generator.generateBoss();
      final choices = _generator.generateChoices(_campaign.encounterNumber);

      if (choices.isEmpty) {
        choices.add(boss);
      } else {
        var replaceIndex = choices.indexWhere(
          (e) =>
              e.type == EncounterType.battle || e.type == EncounterType.elite,
        );
        if (replaceIndex == -1) {
          replaceIndex = choices.length - 1;
        }
        choices[replaceIndex] = boss;
      }

      if (pendingDefense != null) {
        final alreadyIncluded = choices.any((e) => e.id == pendingDefense.id);
        if (!alreadyIncluded) {
          if (choices.isEmpty) {
            choices.add(pendingDefense);
          } else {
            // Replace the last choice so we keep the same number of options.
            choices[choices.length - 1] = pendingDefense;
          }
        }
      }

      _campaign.currentChoices = choices;
      return;
    }

    final choices = _generator.generateChoices(_campaign.encounterNumber);
    if (pendingDefense != null) {
      final alreadyIncluded = choices.any((e) => e.id == pendingDefense.id);
      if (!alreadyIncluded) {
        if (choices.isEmpty) {
          choices.add(pendingDefense);
        } else {
          // Replace the last choice so we keep the same number of options.
          choices[choices.length - 1] = pendingDefense;
        }
      }
    }
    _campaign.currentChoices = choices;
  }

  List<List<String>>? _terrainGridForCurrentEncounterLocation({
    required List<String> playerTerrains,
  }) {
    final lat = _campaign.lastTravelLat;
    final lng = _campaign.lastTravelLng;
    if (lat == null || lng == null) return null;

    final seedLat = (lat.abs() * 1000).round();
    final seedLng = (lng.abs() * 1000).round();
    final seed = (seedLat * 1000003) ^ seedLng;
    final rng = Random(seed);

    final pool = _locationTerrainPoolForAct(_campaign.act);

    String pickFrom(List<String> values) {
      if (values.isEmpty) return pool.first;
      return values[rng.nextInt(values.length)];
    }

    // Enemy base and middle terrain are determined from location.
    final enemyBaseTerrain = pickFrom(pool);
    var middleTerrain = pickFrom(pool);
    if (middleTerrain == enemyBaseTerrain && pool.length > 1) {
      middleTerrain = pickFrom(
        pool.where((t) => t != enemyBaseTerrain).toList(),
      );
    }

    // Player base uses hero terrains (so heroes keep identity).
    final normalizedPlayerTerrains = playerTerrains.isNotEmpty
        ? playerTerrains
        : const ['Woods'];

    final grid = List.generate(3, (_) => List.filled(3, 'Woods'));
    for (int col = 0; col < 3; col++) {
      grid[0][col] = enemyBaseTerrain;
      grid[1][col] = middleTerrain;
      grid[2][col] = pickFrom(normalizedPlayerTerrains);
    }
    return grid;
  }

  static const List<({String name, LatLng pos})> _act1NamedLocations = [
    (name: 'Nice', pos: LatLng(43.695, 7.264)),
    (name: 'Savona', pos: LatLng(44.309, 8.477)),
    (name: 'Genoa', pos: LatLng(44.405, 8.946)),
    (name: 'Tende', pos: LatLng(44.107, 7.669)),
    (name: 'Mondovì', pos: LatLng(44.384, 7.823)),
    (name: 'Cuneo', pos: LatLng(44.558, 7.734)),
    (name: 'Alessandria', pos: LatLng(44.915, 8.617)),
    (name: 'Turin', pos: LatLng(45.070, 7.687)),
    (name: 'Pavia', pos: LatLng(45.133, 9.158)),
    (name: 'Milan', pos: LatLng(45.453, 9.183)),
    (name: 'Monza', pos: LatLng(45.542, 9.270)),
    (name: 'Lodi', pos: LatLng(45.309, 9.503)),
    (name: 'Mantua', pos: LatLng(45.263, 10.992)),
  ];

  static const List<({String name, LatLng pos})> _act2NamedLocations = [
    (name: 'Alexandria', pos: LatLng(31.2001, 29.9187)),
    (name: 'Rosetta', pos: LatLng(31.3986, 30.4170)),
    (name: 'Damietta', pos: LatLng(31.4165, 31.8144)),
    (name: 'Giza', pos: LatLng(30.0131, 31.2089)),
    (name: 'Cairo', pos: LatLng(30.0444, 31.2357)),
  ];

  static const List<({String name, LatLng pos})> _act3NamedLocations = [
    (name: 'Paris', pos: LatLng(48.8566, 2.3522)),
    (name: 'Metz', pos: LatLng(49.1193, 6.1757)),
    (name: 'Strasbourg', pos: LatLng(48.5734, 7.7521)),
    (name: 'Ulm', pos: LatLng(48.4011, 9.9876)),
    (name: 'Vienna', pos: LatLng(48.2082, 16.3738)),
    (name: 'Brno', pos: LatLng(49.1951, 16.6068)),
    (name: 'Austerlitz', pos: LatLng(49.1390, 16.7630)),
  ];

  String _nearestPlaceNameFor(double lat, double lng) {
    final pool = switch (_campaign.act) {
      2 => _act2NamedLocations,
      3 => _act3NamedLocations,
      _ => _act1NamedLocations,
    };
    if (pool.isEmpty) return 'Unknown location';
    final target = LatLng(lat, lng);
    final distance = const Distance();
    var bestName = pool.first.name;
    var bestMeters = distance(target, pool.first.pos);

    for (final p in pool.skip(1)) {
      final d = distance(target, p.pos);
      if (d < bestMeters) {
        bestMeters = d;
        bestName = p.name;
      }
    }

    return bestName;
  }

  String _locationLabelForCurrentTravel() {
    final lat = _campaign.lastTravelLat;
    final lng = _campaign.lastTravelLng;
    if (lat == null || lng == null) return 'Unknown location';
    return _nearestPlaceNameFor(lat, lng);
  }

  String _storyTextForEncounter(Encounter encounter) {
    final loc = _locationLabelForCurrentTravel();
    final lat = _campaign.lastTravelLat ?? 0;
    final lng = _campaign.lastTravelLng ?? 0;
    final seedLat = (lat.abs() * 1000).round();
    final seedLng = (lng.abs() * 1000).round();
    final seed = encounter.id.hashCode ^ (seedLat * 1000003) ^ seedLng;
    final rng = Random(seed);

    String pick(List<String> options) => options[rng.nextInt(options.length)];

    if (encounter.isDefense) {
      return pick([
        'At $loc, your newly raised banners draw a swift response. The enemy returns in force, but your troops hold the streets and gates with stubborn resolve.',
        'The city at $loc erupts again as the foe attempts to retake what was lost. You fortify, countercharge, and deny them any foothold.',
      ]);
    }
    if (encounter.isConquerableCity) {
      return pick([
        'You advance on the city at $loc under a hard sky. After brief, violent fighting, the defenders break—your standards rise above the walls.',
        'At $loc, the populace watches in tense silence as your columns enter. The garrison yields after sharp resistance, and the city is yours—for now.',
      ]);
    }

    switch (encounter.type) {
      case EncounterType.battle:
      case EncounterType.elite:
        return pick([
          'Smoke drifts over $loc as the last volleys fade. You regroup, count losses, and press on before the enemy can reorganize.',
          'At $loc, the clash is brief but decisive. Discipline holds; your line does not break, and the road ahead opens.',
        ]);
      case EncounterType.boss:
        return pick([
          'The field at $loc is won—at a cost. The enemy commander’s plan collapses, and the campaign turns in your favor.',
          'At $loc, the decisive encounter ends with your forces in control. The opposition reels; the next chapter awaits.',
        ]);
      case EncounterType.shop:
        return pick([
          'At $loc you barter and resupply. Rumors pass between merchants and officers—useful truths hidden among exaggerations.',
          'The market at $loc offers brief comfort: dry powder, fresh bread, and a moment to plan the march ahead.',
        ]);
      case EncounterType.rest:
        return pick([
          'A quiet camp near $loc steadies the army. Wounds are bound, orders are written, and morale rises with the firelight.',
          'You halt near $loc. The men rest, the horses drink, and the coming miles feel possible again.',
        ]);
      case EncounterType.event:
      case EncounterType.mystery:
        return pick([
          'Near $loc, chance intervenes. A small decision reshapes the day—sometimes fortune favors boldness, sometimes caution.',
          'At $loc, the unexpected becomes policy. You adapt quickly, turning uncertainty into advantage.',
        ]);
      case EncounterType.treasure:
        return pick([
          'At $loc you seize unattended stores—coin, tools, and provisions. The army moves lighter in spirit, heavier in supply.',
          'A hidden cache near $loc changes hands. Your quartermasters smile; your enemies will not.',
        ]);
    }
  }

  Future<void> _showStoryAfterEncounter(Encounter encounter) async {
    if (!_isNapoleonRealMapEnabled) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final story = _storyTextForEncounter(encounter);
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Dispatch', style: TextStyle(color: Colors.white)),
        content: Text(
          story,
          style: const TextStyle(color: Colors.white70, height: 1.25),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
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
      case EncounterType.mystery:
        _openMystery(encounter);
        break;
      case EncounterType.treasure:
        _openTreasure(encounter);
        break;
    }
  }

  void _openMystery(Encounter encounter) {
    // Mystery can be anything - for now let's make it a 50/50 between battle and treasure
    // In a real implementation, this would likely reveal the true type and then delegate
    final isBattle = DateTime.now().millisecondsSinceEpoch % 2 == 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Colors.purple),
            const SizedBox(width: 8),
            Text(encounter.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(encounter.description),
            const SizedBox(height: 16),
            const Text(
              'You approach the unknown location...',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isBattle) {
                // Reveal as battle
                final battleEncounter = Encounter(
                  id: encounter.id,
                  type: EncounterType.battle,
                  title: 'Ambush!',
                  description: 'It was a trap! Prepare for battle.',
                  difficulty: encounter.difficulty ?? BattleDifficulty.normal,
                  goldReward: encounter.goldReward,
                );
                _startBattle(battleEncounter);
              } else {
                // Reveal as treasure
                final treasureEncounter = Encounter(
                  id: encounter.id,
                  type: EncounterType.treasure,
                  title: 'Hidden Supplies',
                  description: 'You found a stash of supplies!',
                  goldReward: 50,
                );
                _openTreasure(treasureEncounter);
              }
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }

  void _openProgressionView() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProgressionScreen(viewOnly: true),
      ),
    );
  }

  void _openTreasure(Encounter encounter) {
    final goldReward = encounter.goldReward ?? 50;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Column(
                children: [
                  const Text('You found:'),
                  const SizedBox(height: 8),
                  Text(
                    '+$goldReward Gold',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final rewardEvents = <RewardEvent>[];
              setState(() {
                _campaign.addGold(goldReward);
                _campaign.completeEncounter();
                _generateNewChoices();
              });
              rewardEvents.add(_goldEvent(goldReward));
              await _saveCampaign();
              final offerEvent = await _applyEncounterOffer(
                encounter,
                showDialog: false,
              );
              if (offerEvent != null) rewardEvents.add(offerEvent);
              await _maybeDiscoverMapRelicAfterEncounter(encounter);
              await _showStoryAfterEncounter(encounter);
              final storyOutcome = _applyRandomStoryOutcome(encounter);
              if (storyOutcome != null) rewardEvents.add(storyOutcome);
              final deliveries = await _autoCollectHomeTownDeliveries(
                showDialogs: false,
              );
              rewardEvents.addAll(deliveries);
              await _saveCampaign();
              await _showCelebrationDialog(
                title: 'Rewards',
                events: rewardEvents,
              );
            },
            child: const Text('Claim'),
          ),
        ],
      ),
    );
  }

  void _startBattle(Encounter encounter) async {
    // Generate randomized enemy deck based on difficulty
    final difficultyLevel = switch (encounter.difficulty) {
      BattleDifficulty.easy => 1,
      BattleDifficulty.normal => 2,
      BattleDifficulty.hard => 3,
      BattleDifficulty.elite => 4,
      BattleDifficulty.boss => 5,
      null => 2, // Default to normal
    };

    final enemyCards = switch (_campaign.act) {
      2 => buildRandomizedAct2Deck(difficultyLevel),
      3 => buildRandomizedAct3Deck(difficultyLevel),
      _ => buildRandomizedAct1Deck(difficultyLevel),
    };

    final enemyDeck = Deck(
      id: 'enemy_${encounter.id}',
      name: encounter.title,
      cards: enemyCards,
    );

    final progressionData = await _persistence.loadProgression();
    final progressionState = progressionData != null
        ? NapoleonProgressionState.fromJson(progressionData)
        : NapoleonProgressionState();

    final mods = progressionState.modifiers;

    debugPrint(
      'CAMPAIGN PROGRESSION: points=${progressionState.progressionPoints}, unlocked=[${progressionState.unlockedNodes.join(", ")}]',
    );

    debugPrint(
      'CAMPAIGN BATTLE: act=${_campaign.act}, encounter=${_campaign.encounterNumber}, hp=${_campaign.health}/${_campaign.maxHealth}, activeRelics=${_campaign.activeRelics}, damageBonus=${_campaign.globalDamageBonus}, goldBonus=${_campaign.goldPerBattleBonus}, extraStartingDraw=${mods.extraStartingDraw}, artilleryDamageBonus=${mods.artilleryDamageBonus}, difficulty=${encounter.difficulty}',
    );

    final predefinedTerrainsOverride = _terrainGridForCurrentEncounterLocation(
      playerTerrains: HeroLibrary.napoleon().terrainAffinities,
    );

    final int defenseDamageBonus = encounter.isDefense ? 1 : 0;
    final int defenseHealthBonus = encounter.isDefense ? 1 : 0;
    final buffLabels = _campaignBuffLabelsForBattle(
      mods: mods,
      defenseDamageBonus: defenseDamageBonus,
      defenseHealthBonus: defenseHealthBonus,
    );
    final buffsDialogLabels = _campaignBuffLabelsForBuffsDialog(
      mods: mods,
      defenseDamageBonus: defenseDamageBonus,
      defenseHealthBonus: defenseHealthBonus,
    );

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final result = await navigator.push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => TestMatchScreen(
          selectedHero: HeroLibrary.napoleon(),
          forceCampaignDeck: true,
          campaignAct: _campaign.act,
          enemyDeck: enemyDeck,
          customDeck: _campaign.deck,
          predefinedTerrainsOverride: predefinedTerrainsOverride,
          playerDamageBonus: _campaign.globalDamageBonus + defenseDamageBonus,
          playerCardHealthBonus: defenseHealthBonus,
          extraStartingDraw: mods.extraStartingDraw,
          artilleryDamageBonus: mods.artilleryDamageBonus,
          cannonHealthBonus: _campaign.isRelicActive('campaign_map_relic')
              ? 1
              : 0,
          heroAbilityDamageBoost: mods.heroAbilityDamageBoost,
          playerCurrentHealth: _campaign.health,
          playerMaxHealth: _campaign.maxHealth,
          campaignBuffLabels: buffLabels,
          campaignBuffLabelsForBuffsDialog: buffsDialogLabels,
        ),
      ),
    );

    // Handle battle result
    if (result != null) {
      final won = result['won'] as bool? ?? false;
      final crystalDamage = result['crystalDamage'] as int? ?? 0;
      final destroyedCardIds =
          (result['destroyedCardIds'] as List?)?.whereType<String>().toList() ??
          <String>[];

      // Apply damage taken during battle regardless of outcome
      setState(() {
        _campaign.takeDamage(crystalDamage);
        for (final id in destroyedCardIds) {
          _campaign.destroyCardPermanently(id);
        }
      });
      _saveCampaign();

      if (won) {
        final rewardEvents = <RewardEvent>[];
        await _awardBattleLegacyPoints(encounter);
        final int reward =
            (encounter.goldReward ?? 15) + _campaign.goldPerBattleBonus;
        setState(() {
          _campaign.addGold(reward);
        });
        rewardEvents.add(_goldEvent(reward));

        final offerEvent = await _applyEncounterOffer(
          encounter,
          showDialog: false,
        );
        if (offerEvent != null) rewardEvents.add(offerEvent);

        Encounter? pendingDefense;
        double? pendingDefenseLat;
        double? pendingDefenseLng;
        if (encounter.isDefense) {
          // Completed defense encounter.
          pendingDefense = null;
        } else if (encounter.isConquerableCity &&
            _campaign.pendingDefenseEncounter == null) {
          pendingDefenseLat = _campaign.lastTravelLat;
          pendingDefenseLng = _campaign.lastTravelLng;
          pendingDefense = Encounter(
            id: 'defense_${encounter.id}',
            type: EncounterType.battle,
            title:
                'Defense: ${encounter.title.replaceFirst("Conquer City: ", "")}',
            description:
                'The enemy attempts to retake the city. Hold your ground.',
            difficulty: BattleDifficulty.easy,
            goldReward: 8,
            isDefense: true,
          );
        }

        setState(() {
          if (encounter.isDefense) {
            _campaign.clearPendingDefenseEncounter();
          } else if (pendingDefense != null) {
            if (pendingDefenseLat != null && pendingDefenseLng != null) {
              _campaign.setPendingDefenseEncounterAtLocation(
                pendingDefense,
                lat: pendingDefenseLat,
                lng: pendingDefenseLng,
              );
            } else {
              _campaign.setPendingDefenseEncounter(pendingDefense);
            }
          }
          _campaign.incrementBattleEncounterCount();
          _campaign.completeEncounter();
          _generateNewChoices();
        });
        await _saveCampaign();
        await _showStoryAfterEncounter(encounter);
        final storyOutcome = _applyRandomStoryOutcome(encounter);
        if (storyOutcome != null) rewardEvents.add(storyOutcome);
        final deliveries = await _autoCollectHomeTownDeliveries(
          showDialogs: false,
        );
        rewardEvents.addAll(deliveries);
        await _saveCampaign();
        await _showCelebrationDialog(
          title: 'After-Action Report',
          events: rewardEvents,
        );
      } else {
        if (_campaign.health <= 0) {
          await _showGameOver();
        } else {
          setState(() {
            _campaign.enterRecoveryMode(encounters: 2);
            _generateNewChoices();
          });
          await _saveCampaign();
          if (!mounted) return;
          await _showEncounterRewardDialog(
            title: 'Defeat',
            message:
                'You survived, but your army is battered. You can regroup and seek supplies.',
            icon: Icons.warning,
            iconColor: Colors.redAccent,
          );
        }
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
        title: const Text('Retreat?'),
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
                      _campaign.enterRecoveryMode(encounters: 1);
                      _generateNewChoices(); // Refresh encounters
                    });
                    _saveCampaign();
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
    final progressionData = await _persistence.loadProgression();
    final progressionState = progressionData != null
        ? NapoleonProgressionState.fromJson(progressionData)
        : NapoleonProgressionState();

    final mods = progressionState.modifiers;

    final buffLabels = _campaignBuffLabelsForBattle(mods: mods);
    final buffsDialogLabels = _campaignBuffLabelsForBuffsDialog(mods: mods);

    // Boss battles use a dedicated boss deck that always includes the act boss card.
    final bossCard = switch (_campaign.act) {
      2 => bossMuradBey(0),
      3 => bossCoalitionForces(0),
      _ => bossGeneralBeaulieu(0),
    };

    final baseEnemyCards = switch (_campaign.act) {
      2 => buildRandomizedAct2Deck(5),
      3 => buildRandomizedAct3Deck(5),
      _ => buildRandomizedAct1Deck(5),
    };

    final enemyCards = <GameCard>[
      bossCard,
      ...baseEnemyCards,
    ].where((c) => c.id != bossCard.id).toList();
    while (enemyCards.length > 25) {
      enemyCards.removeLast();
    }

    final enemyDeck = Deck(
      id: 'boss_${encounter.id}',
      name: encounter.title,
      cards: enemyCards,
    );

    final int bossOpponentBaseHP = 25 + (25 * _campaign.act);

    debugPrint(
      'CAMPAIGN PROGRESSION: points=${progressionState.progressionPoints}, unlocked=[${progressionState.unlockedNodes.join(", ")}]',
    );

    debugPrint(
      'CAMPAIGN BOSS: act=${_campaign.act}, hp=${_campaign.health}/${_campaign.maxHealth}, activeRelics=${_campaign.activeRelics}, damageBonus=${_campaign.globalDamageBonus}, goldBonus=${_campaign.goldPerBattleBonus}, extraStartingDraw=${mods.extraStartingDraw}, artilleryDamageBonus=${mods.artilleryDamageBonus}, bossOpponentBaseHP=$bossOpponentBaseHP',
    );

    final predefinedTerrainsOverride = _terrainGridForCurrentEncounterLocation(
      playerTerrains: HeroLibrary.napoleon().terrainAffinities,
    );

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final result = await navigator.push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => TestMatchScreen(
          selectedHero: HeroLibrary.napoleon(),
          forceCampaignDeck: true,
          campaignAct: _campaign.act,
          enemyDeck: enemyDeck,
          customDeck: _campaign.deck,
          predefinedTerrainsOverride: predefinedTerrainsOverride,
          playerCurrentHealth: _campaign.health,
          playerMaxHealth: _campaign.maxHealth,
          playerDamageBonus: _campaign.globalDamageBonus,
          extraStartingDraw: mods.extraStartingDraw,
          artilleryDamageBonus: mods.artilleryDamageBonus,
          cannonHealthBonus: _campaign.isRelicActive('campaign_map_relic')
              ? 1
              : 0,
          heroAbilityDamageBoost: mods.heroAbilityDamageBoost,
          opponentBaseHP: bossOpponentBaseHP,
          opponentPriorityCardIds: const [
            'boss_',
          ], // Prioritize boss cards in starting hand
          campaignBuffLabels: buffLabels,
          campaignBuffLabelsForBuffsDialog: buffsDialogLabels,
        ),
      ),
    );

    if (result != null) {
      final won = result['won'] as bool? ?? false;

      if (won) {
        await _awardBossLegacyPoints(_campaign.act);
        // Calculate gold reward with relic bonus
        final int reward =
            (encounter.goldReward ?? 50) + _campaign.goldPerBattleBonus;
        setState(() {
          _campaign.incrementBattleEncounterCount();
          _campaign.addGold(reward);
        });

        if (_campaign.act < 3) {
          await _awardActCompleteLegacyPoints(_campaign.act);
          // Act Complete
          if (mounted) {
            await _showActCompleteDialog();
            _startNextAct();
          }
        } else {
          // Campaign Complete
          setState(() {
            _campaign.isVictory = true;
            _campaign.completedAt = DateTime.now();
          });
          _saveCampaign();
          final earned = await _awardCampaignVictoryLegacyPoints();
          _showVictory(earned);
        }
      } else {
        setState(() {
          _campaign.takeDamage(50); // Boss deals massive damage on loss
        });
        _saveCampaign();
        if (_campaign.health <= 0) {
          await _showGameOver();
        } else {
          setState(() {
            _campaign.enterRecoveryMode(encounters: 2);
            _generateNewChoices();
          });
          await _saveCampaign();
          if (!mounted) return;
          await _showEncounterRewardDialog(
            title: 'Setback',
            message:
                'You fell back from the boss fight. Gather strength and supplies before returning.',
            icon: Icons.warning,
            iconColor: Colors.orangeAccent,
          );
        }
      }
    } else {
      _showRetreatDialog(encounter);
    }
  }

  void _startNextAct() {
    final fromAct = _campaign.act;
    // Show upgrade screen before advancing to next act
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CardUpgradeScreen(
          campaign: _campaign,
          fromAct: fromAct,
          onComplete: () {
            Navigator.of(context).pop();
            _completeActTransition();
          },
        ),
      ),
    );
  }

  void _completeActTransition() {
    setState(() {
      _campaign.nextAct();
      // Re-initialize generator for the new act
      _generator = EncounterGenerator(act: _campaign.act);
      _generateNewChoices();
    });
    _initHomeTownIfNeeded();
    _initMapRelicIfNeeded();
    _refreshHomeTownProgressionPerks();
    _saveCampaign();
    _showActIntroDialog();
  }

  Future<void> _showActCompleteDialog() async {
    String rewardText = '';
    switch (_campaign.act) {
      case 1:
        rewardText =
            'Your artillery tactics have proven superior. The Austrians retreat.';
        break;
      case 2:
        rewardText =
            'The mysteries of the desert are yours. Ancient power grows.';
        break;
    }

    // Get a random relic as reward
    final allRelics = ShopInventory.getAllLegendaryRelics();
    // Filter out already owned relics
    final availableRelics = allRelics
        .where((r) => !_campaign.hasRelic(r.id))
        .toList();
    availableRelics.shuffle();
    final relicReward = availableRelics.isNotEmpty
        ? availableRelics.first
        : null;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Text(
          'Act ${_campaign.act} Complete!',
          style: const TextStyle(color: Colors.amber),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Victory in ${_getActTitle(_campaign.act)}!',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              rewardText,
              style: TextStyle(color: Colors.grey[300]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your army rests and recovers full health.',
              style: TextStyle(color: Colors.green),
            ),
            if (relicReward != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Legendary Relic Discovered!',
                style: TextStyle(
                  color: Colors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.purple),
                ),
                title: Text(
                  relicReward.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  relicReward.description,
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (relicReward != null) {
                _campaign.addRelic(relicReward.id);
                // Note: immediate effects handled in addRelic
              }
              Navigator.pop(context);
            },
            child: const Text('Claim & March Onwards'),
          ),
        ],
      ),
    );
  }

  void _showActIntroDialog() {
    final title = _getActTitle(_campaign.act);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Text(
          'Act ${_campaign.act}: $title',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'New enemies and challenges await. Spend your gold wisely and lead your troops to victory.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Begin'),
          ),
        ],
      ),
    );
  }

  void _showVictory(int earnedLegacyPoints) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Center(
          child: Text(
            'CAMPAIGN VICTORY!',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You have conquered Europe!',
              style: TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildStatRow(
              Icons.monetization_on,
              'Final Gold',
              '${_campaign.gold}',
            ),
            _buildStatRow(
              Icons.favorite,
              'Final Health',
              '${_campaign.health}/${_campaign.maxHealth}',
            ),
            _buildStatRow(
              Icons.style,
              'Deck Size',
              '${_campaign.deck.length} cards',
            ),
            const Divider(color: Colors.grey),
            _buildStatRow(
              Icons.stars,
              'Legacy Points Earned',
              '$earnedLegacyPoints',
            ),
            const SizedBox(height: 8),
            const Text(
              'Points added to Napoleon\'s Legacy',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('RETURN TO MENU'),
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _awardLegacyPointsOnce(String milestoneId, int points) async {
    if (_campaign.hasAwardedMilestone(milestoneId)) {
      return 0;
    }

    _campaign.markMilestoneAwarded(milestoneId);
    await _saveCampaign();

    try {
      final progressionData = await _persistence.loadProgression();
      final progressionState = progressionData != null
          ? NapoleonProgressionState.fromJson(progressionData)
          : NapoleonProgressionState();

      progressionState.addPoints(points);
      await _persistence.saveProgression(progressionState.toJson());
      return points;
    } catch (e) {
      debugPrint('Error saving progression: $e');
      return 0;
    }
  }

  Future<int> _awardBattleLegacyPoints(Encounter encounter) async {
    final isElite =
        encounter.type == EncounterType.elite ||
        encounter.difficulty == BattleDifficulty.elite;
    final points = isElite ? 10 : 5;
    return _awardLegacyPointsOnce('battle_win_${encounter.id}', points);
  }

  Future<int> _awardBossLegacyPoints(int act) async {
    return _awardLegacyPointsOnce('boss_defeated_act_$act', 25);
  }

  Future<int> _awardActCompleteLegacyPoints(int act) async {
    final points = switch (act) {
      1 => 50,
      2 => 100,
      _ => 0,
    };
    if (points == 0) return 0;
    return _awardLegacyPointsOnce('act_complete_$act', points);
  }

  Future<int> _awardCampaignVictoryLegacyPoints() async {
    const milestoneId = 'campaign_complete_act_3';
    if (_campaign.hasAwardedMilestone(milestoneId)) {
      return 0;
    }

    _campaign.markMilestoneAwarded(milestoneId);
    await _saveCampaign();

    try {
      final progressionData = await _persistence.loadProgression();
      final progressionState = progressionData != null
          ? NapoleonProgressionState.fromJson(progressionData)
          : NapoleonProgressionState();

      int total = 200;
      if (progressionState.completedCampaigns == 0) {
        total += 100;
      }
      progressionState.addPoints(total);
      progressionState.markCampaignCompleted();
      await _persistence.saveProgression(progressionState.toJson());
      await _persistence.clearCampaign();
      return total;
    } catch (e) {
      debugPrint('Error saving progression: $e');
      return 0;
    }
  }

  Future<int> _awardCampaignLossLegacyPoints() async {
    final points = switch (_campaign.act) {
      1 => 10,
      2 => 20,
      _ => 30,
    };
    return _awardLegacyPointsOnce('campaign_lost_${_campaign.id}', points);
  }

  String _getActTitle(int act) {
    switch (act) {
      case 1:
        return 'Italian Campaign';
      case 2:
        return 'Egyptian Expedition';
      case 3:
        return 'War of the Third Coalition';
      default:
        return 'Campaign';
    }
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey[400], size: 20),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey[400])),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  int _repairCostForCard(GameCard card) {
    final rarityAdj = ((card.rarity - 1).clamp(0, 3)) * 25;
    final statAdj = (card.damage + card.health).clamp(0, 50);
    return 30 + rarityAdj + statAdj;
  }

  void _openShop(Encounter encounter) async {
    final shopItems = ShopInventory.generateForAct(_campaign.act);

    NapoleonProgressionModifiers mods = const NapoleonProgressionModifiers();
    if (widget.leaderId == 'napoleon') {
      final data = await _persistence.loadProgression();
      final state = data != null
          ? NapoleonProgressionState.fromJson(data)
          : NapoleonProgressionState();
      mods = state.modifiers;
    }

    if (!mounted) return;

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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_campaign.destroyedDeckCards.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.build_circle,
                            color: Colors.orangeAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Repair Destroyed Cards',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._campaign.destroyedDeckCards.map((card) {
                        final cost = _repairCostForCard(card);
                        final canAfford = _campaign.gold >= cost;
                        return Card(
                          color: Colors.grey[850],
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.red[800],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.construction,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              card.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${card.element ?? "Neutral"} - DMG:${card.damage} HP:${card.health}',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                            trailing: ElevatedButton(
                              onPressed: canAfford
                                  ? () {
                                      if (!_campaign.spendGold(cost)) return;
                                      final ok = _campaign.repairDestroyedCard(
                                        card.id,
                                      );
                                      if (!ok) return;
                                      setShopState(() {});
                                      setState(() {});
                                      _saveCampaign();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Repaired ${card.name}',
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canAfford
                                    ? Colors.orange
                                    : Colors.grey,
                                foregroundColor: Colors.black,
                              ),
                              child: Text('$cost'),
                            ),
                          ),
                        );
                      }),
                      const Divider(color: Colors.white24, height: 24),
                    ],
                    ...shopItems.map((item) {
                      final effectiveCost = _applyDiscount(
                        item.cost,
                        mods.shopDiscountPercent,
                      );
                      final canAfford = _campaign.gold >= effectiveCost;
                      final isOwned =
                          item.type == ShopItemType.relic &&
                          _campaign.hasRelic(item.id);

                      return Card(
                        color: Colors.grey[850],
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          onTap:
                              item.type == ShopItemType.card &&
                                  item.card != null
                              ? () => _showCardDetailsDialog(item.card!)
                              : null,
                          leading: _getShopItemIcon(item),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (item.type == ShopItemType.card)
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                            ],
                          ),
                          subtitle: Text(
                            item.description,
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                          trailing: isOwned
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : ElevatedButton(
                                  onPressed: canAfford
                                      ? () => _buyItem(
                                          item,
                                          effectiveCost,
                                          setShopState,
                                        )
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canAfford
                                        ? Colors.amber
                                        : Colors.grey,
                                  ),
                                  child: Text(
                                    '$effectiveCost',
                                    style: TextStyle(
                                      color: canAfford
                                          ? Colors.black
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              // Leave button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final rewardEvents = <RewardEvent>[];
                      setState(() {
                        _campaign.completeEncounter();
                        _generateNewChoices();
                      });
                      _saveCampaign();
                      await _showStoryAfterEncounter(encounter);
                      final storyOutcome = _applyRandomStoryOutcome(encounter);
                      if (storyOutcome != null) rewardEvents.add(storyOutcome);
                      final deliveries = await _autoCollectHomeTownDeliveries(
                        showDialogs: false,
                      );
                      rewardEvents.addAll(deliveries);
                      await _saveCampaign();
                      await _showCelebrationDialog(
                        title: 'After-Action Report',
                        events: rewardEvents,
                      );
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

  /// Show detailed card information dialog
  void _showCardDetailsDialog(GameCard card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getElementColor(card.element ?? 'woods'),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.style, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    card.element ?? 'Neutral',
                    style: TextStyle(
                      color: _getElementColor(card.element ?? 'woods'),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      Icons.flash_on,
                      'DMG',
                      '${card.damage}',
                      Colors.redAccent,
                    ),
                    _buildStatColumn(
                      Icons.favorite,
                      'HP',
                      '${card.health}',
                      Colors.greenAccent,
                    ),
                    _buildStatColumn(
                      Icons.speed,
                      'AP',
                      '${card.maxAP}',
                      Colors.blueAccent,
                    ),
                    _buildStatColumn(
                      Icons.gps_fixed,
                      'Range',
                      '${card.attackRange}',
                      Colors.orangeAccent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Rarity
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Rarity: ${_rarityName(card.rarity)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Abilities
              if (card.abilities.isNotEmpty) ...[
                const Text(
                  'Abilities:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ...card.abilities.map(
                  (ability) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _getAbilityIcon(ability),
                          color: _getAbilityColor(ability),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatAbilityName(ability),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _getAbilityDescription(ability),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                const Text(
                  'No special abilities',
                  style: TextStyle(
                    color: Colors.white54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  String _rarityName(int rarity) {
    switch (rarity) {
      case 1:
        return 'Common';
      case 2:
        return 'Rare';
      case 3:
        return 'Epic';
      case 4:
        return 'Legendary';
      default:
        return 'Common';
    }
  }

  String _formatAbilityName(String ability) {
    // Convert snake_case or simple names to Title Case
    if (ability.contains('_')) {
      return ability
          .split('_')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
    }
    return ability.isNotEmpty
        ? '${ability[0].toUpperCase()}${ability.substring(1)}'
        : ability;
  }

  IconData _getAbilityIcon(String ability) {
    if (ability.startsWith('medic')) return Icons.healing;
    if (ability.contains('cannon')) return Icons.gps_fixed;
    if (ability.contains('charge')) return Icons.flash_on;
    if (ability.contains('shield')) return Icons.shield;
    if (ability.contains('range')) return Icons.straighten;
    if (ability.contains('heal')) return Icons.favorite;
    return Icons.auto_awesome;
  }

  Color _getAbilityColor(String ability) {
    if (ability.startsWith('medic')) return Colors.greenAccent;
    if (ability.contains('cannon')) return Colors.orangeAccent;
    if (ability.contains('charge')) return Colors.yellowAccent;
    if (ability.contains('shield')) return Colors.blueAccent;
    return Colors.purpleAccent;
  }

  String _getAbilityDescription(String ability) {
    // Medic abilities
    if (ability == 'medic_5') return 'Can heal friendly units for 5 HP';
    if (ability == 'medic_10') return 'Can heal friendly units for 10 HP';
    if (ability == 'medic_15') return 'Can heal friendly units for 15 HP';
    if (ability.startsWith('medic_')) {
      final amount = ability.replaceFirst('medic_', '');
      return 'Can heal friendly units for $amount HP';
    }

    // Cannon ability
    if (ability == 'cannon') return 'Artillery unit with extended attack range';

    // Range abilities
    if (ability.startsWith('range_')) {
      final range = ability.replaceFirst('range_', '');
      return 'Attack range of $range tiles';
    }

    // Other common abilities
    if (ability == 'charge') return 'Can move and attack in the same turn';
    if (ability == 'shield') return 'Reduces incoming damage';
    if (ability == 'first_strike') return 'Attacks first in combat';
    if (ability == 'counter') return 'Deals damage when attacked';

    return 'Special ability';
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

  void _buyItem(ShopItem item, int effectiveCost, StateSetter setShopState) {
    if (!_campaign.spendGold(effectiveCost)) return;

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
        _campaign.addConsumable(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${item.name} to your inventory!')),
        );
        break;
      case ShopItemType.relic:
        _applyRelic(item);
        break;
    }

    setShopState(() {});
    setState(() {});
    _saveCampaign();
  }

  void _applyRelic(ShopItem item) {
    _campaign.addRelic(item.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Acquired ${item.name}!')));
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
            const Text(
              'Your army is tired. Rest to recover health.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final rewardEvents = <RewardEvent>[];
              setState(() {
                _campaign.heal(healAmount);
                _campaign.completeEncounter();
                _generateNewChoices();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Recovered $healAmount HP!')),
              );
              await _saveCampaign();
              await _showStoryAfterEncounter(encounter);
              final storyOutcome = _applyRandomStoryOutcome(encounter);
              if (storyOutcome != null) rewardEvents.add(storyOutcome);
              final deliveries = await _autoCollectHomeTownDeliveries(
                showDialogs: false,
              );
              rewardEvents.addAll(deliveries);
              await _saveCampaign();
              await _showCelebrationDialog(
                title: 'After-Action Report',
                events: rewardEvents,
              );
            },
            child: Text('Rest (+$healAmount HP)'),
          ),
        ],
      ),
    );
  }

  void _triggerEvent(Encounter encounter) {
    final offerType = encounter.offerType;
    final offerId = encounter.offerId;
    final offerAmount = encounter.offerAmount ?? 1;

    String rewardLine = 'You found supplies.';
    if (offerType == 'consumable' && offerId != null) {
      final all = ShopInventory.getAllConsumables();
      final item = all.where((e) => e.id == offerId).toList();
      final name = item.isNotEmpty ? item.first.name : offerId;
      rewardLine = 'Offer: $name ×$offerAmount';
    } else if (offerType == 'relic' && offerId != null) {
      final all = ShopInventory.getAllRelics();
      final item = all.where((e) => e.id == offerId).toList();
      final name = item.isNotEmpty ? item.first.name : offerId;
      rewardLine = 'Offer: $name';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.event, color: Colors.blue),
            const SizedBox(width: 8),
            Text(encounter.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(encounter.description),
            const SizedBox(height: 16),
            Text(
              rewardLine,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final rewardEvents = <RewardEvent>[];
              setState(() {
                _campaign.completeEncounter();
                _generateNewChoices();
              });
              await _saveCampaign();
              final offerEvent = await _applyEncounterOffer(
                encounter,
                showDialog: false,
              );
              if (offerEvent != null) rewardEvents.add(offerEvent);
              await _maybeDiscoverMapRelicAfterEncounter(encounter);
              await _showStoryAfterEncounter(encounter);
              final storyOutcome = _applyRandomStoryOutcome(encounter);
              if (storyOutcome != null) rewardEvents.add(storyOutcome);
              final deliveries = await _autoCollectHomeTownDeliveries(
                showDialogs: false,
              );
              rewardEvents.addAll(deliveries);
              await _saveCampaign();
              await _showCelebrationDialog(
                title: 'Rewards',
                events: rewardEvents,
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGameOver() async {
    await _awardCampaignLossLegacyPoints();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Defeat!', style: TextStyle(color: Colors.red)),
        content: const Text(
          'Your army has been defeated. The campaign is over.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              // Clear save
              await _persistence.clearCampaign();
              if (!mounted) return;
              navigator.popUntil((route) => route.isFirst);
            },
            child: const Text('Return to Menu'),
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
              Expanded(
                child: Stack(
                  children: [
                    (_isNapoleonRealMapEnabled)
                        ? _buildRealMapSelection()
                        : _buildChapterSelection(),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Builder(
                        builder: (context) {
                          final modifier = _distanceSupplyModifierEncounters();
                          final km = _distanceToHomeTownKm();
                          final travel = _campaign
                              .currentTravelDurationEncounters();

                          final Color bannerColor = modifier > 0
                              ? (Colors.red[300] ?? Colors.red)
                              : modifier < 0
                              ? Colors.greenAccent
                              : Colors.white70;

                          final String modifierText = modifier > 0
                              ? '+$modifier'
                              : modifier.toString();
                          final String kmText = km == null
                              ? ''
                              : ' • ${km.toStringAsFixed(0)}km';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  'Supply modifier: $modifierText (Travel $travel enc)$kmText',
                                  style: TextStyle(
                                    color: bannerColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FloatingActionButton.extended(
                                    onPressed: _waitOneEncounter,
                                    backgroundColor: Colors.blueGrey[700],
                                    icon: const Icon(
                                      Icons.hourglass_bottom,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Wait',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  if (_campaign.visitedNodes.length >= 2) ...[
                                    const SizedBox(width: 12),
                                    FloatingActionButton.extended(
                                      onPressed: _returnToPreviousNode,
                                      backgroundColor: Colors.orange[700],
                                      icon: const Icon(
                                        Icons.undo,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        'Return',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (_isNapoleonRealMapEnabled)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: FloatingActionButton(
                          heroTag: 'focus_hero',
                          onPressed: _focusMapOnHero,
                          backgroundColor: Colors.black.withValues(alpha: 0.75),
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LatLng _mapCenterForAct(int act) {
    switch (act) {
      case 2:
        return const LatLng(30.6, 31.1);
      case 3:
        return const LatLng(49.2, 10.6);
      default:
        return const LatLng(45.2, 8.6);
    }
  }

  LatLng _centerOfLatLngs(List<LatLng> points) {
    if (points.isEmpty) return _mapCenterForAct(_campaign.act);
    double lat = 0;
    double lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  LatLng _shopPositionBetweenHeroAndCluster({
    required Encounter encounter,
    required LatLng defaultPos,
    required LatLng? heroPos,
    required LatLng clusterCenter,
  }) {
    if (heroPos == null) return defaultPos;
    if (encounter.type != EncounterType.shop) return defaultPos;

    // Deterministic jitter so the shop doesn't overlap other markers.
    final seed = encounter.id.hashCode ^ (_campaign.encounterNumber * 1009);
    final rng = Random(seed);

    // Interpolate: closer to hero, but still on the way to the main cluster.
    const t = 0.35;
    var lat =
        heroPos.latitude + (clusterCenter.latitude - heroPos.latitude) * t;
    var lng =
        heroPos.longitude + (clusterCenter.longitude - heroPos.longitude) * t;

    lat += (rng.nextDouble() - 0.5) * 0.25;
    lng += (rng.nextDouble() - 0.5) * 0.25;

    return LatLng(lat, lng);
  }

  // For MVP: map the *currentChoices* (2-3 encounters) to plausible real locations
  // that progress generally toward Milan. We keep it deterministic per chapter.
  List<LatLng> _candidateLocationsForChapter({
    required int act,
    required int chapterIndex,
  }) {
    final stage = chapterIndex.clamp(0, 4);

    if (act == 2) {
      if (stage <= 0) {
        return const [
          LatLng(31.2001, 29.9187),
          LatLng(31.3986, 30.4170),
          LatLng(31.4165, 31.8144),
        ];
      }
      if (stage == 1) {
        return const [
          LatLng(31.3986, 30.4170),
          LatLng(30.0444, 31.2357),
          LatLng(30.0131, 31.2089),
        ];
      }
      if (stage == 2) {
        return const [
          LatLng(30.0444, 31.2357),
          LatLng(30.0131, 31.2089),
          LatLng(29.9850, 31.1320),
        ];
      }
      if (stage == 3) {
        return const [
          LatLng(30.0444, 31.2357),
          LatLng(30.0131, 31.2089),
          LatLng(30.0500, 31.3000),
        ];
      }
      return const [
        LatLng(30.0444, 31.2357),
        LatLng(30.0131, 31.2089),
        LatLng(30.0500, 31.3000),
      ];
    }

    if (act == 3) {
      if (stage <= 0) {
        return const [
          LatLng(48.8566, 2.3522),
          LatLng(49.1193, 6.1757),
          LatLng(48.5734, 7.7521),
        ];
      }
      if (stage == 1) {
        return const [
          LatLng(48.5734, 7.7521),
          LatLng(48.4011, 9.9876),
          LatLng(48.1372, 11.5756),
        ];
      }
      if (stage == 2) {
        return const [
          LatLng(48.4011, 9.9876),
          LatLng(48.2082, 16.3738),
          LatLng(49.1951, 16.6068),
        ];
      }
      if (stage == 3) {
        return const [
          LatLng(48.2082, 16.3738),
          LatLng(49.1951, 16.6068),
          LatLng(49.1390, 16.7630),
        ];
      }
      return const [
        LatLng(49.1390, 16.7630),
        LatLng(49.1951, 16.6068),
        LatLng(48.2082, 16.3738),
      ];
    }

    if (stage <= 0) {
      return const [
        LatLng(43.695, 7.264),
        LatLng(44.309, 8.477),
        LatLng(44.405, 8.946),
      ];
    }
    if (stage == 1) {
      return const [
        LatLng(44.915, 8.617),
        LatLng(45.070, 7.687),
        LatLng(44.558, 7.734),
      ];
    }
    if (stage == 2) {
      return const [
        LatLng(45.133, 9.158),
        LatLng(45.309, 9.503),
        LatLng(45.453, 9.183),
      ];
    }
    if (stage == 3) {
      return const [
        LatLng(45.542, 9.270),
        LatLng(45.309, 9.503),
        LatLng(45.263, 10.992),
      ];
    }
    return const [
      LatLng(45.453, 9.183),
      LatLng(45.309, 9.503),
      LatLng(45.263, 10.992),
    ];
  }

  IconData _iconForEncounterType(EncounterType type) {
    switch (type) {
      case EncounterType.battle:
        return Icons.sports_kabaddi;
      case EncounterType.elite:
        return Icons.local_fire_department;
      case EncounterType.boss:
        return Icons.whatshot;
      case EncounterType.shop:
        return Icons.store;
      case EncounterType.rest:
        return Icons.local_cafe;
      case EncounterType.event:
        return Icons.help_outline;
      case EncounterType.mystery:
        return Icons.question_mark;
      case EncounterType.treasure:
        return Icons.auto_awesome;
    }
  }

  Color _colorForEncounterType(EncounterType type) {
    switch (type) {
      case EncounterType.battle:
        return Colors.red[700]!;
      case EncounterType.elite:
        return Colors.orange[700]!;
      case EncounterType.boss:
        return Colors.purple[700]!;
      case EncounterType.shop:
        return Colors.amber[700]!;
      case EncounterType.rest:
        return Colors.green[700]!;
      case EncounterType.event:
        return Colors.blue[700]!;
      case EncounterType.mystery:
        return Colors.deepPurple[400]!;
      case EncounterType.treasure:
        return Colors.amber[800]!;
    }
  }

  Future<void> _confirmEncounterOnMap(Encounter encounter, LatLng pos) async {
    final offerLabel = _encounterOfferLabel(encounter);
    final distanceKm = _distanceToHomeTownKmAt(
      travelLat: pos.latitude,
      travelLng: pos.longitude,
    );
    final supplyModifierAtDestination = _distanceSupplyModifierEncountersAt(
      travelLat: pos.latitude,
      travelLng: pos.longitude,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(_iconForEncounterType(encounter.type), color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                encounter.title,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              encounter.description,
              style: TextStyle(color: Colors.grey[300]),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.local_shipping,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Supply chain: +1 on completion',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.route, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Distance to Home: ${distanceKm?.toStringAsFixed(0) ?? "?"} km  |  Supply modifier: $supplyModifierAtDestination',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
            if (encounter.goldReward != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.monetization_on,
                    color: Colors.amber,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '+${encounter.goldReward} Gold',
                    style: const TextStyle(color: Colors.amber),
                  ),
                ],
              ),
            ],
            if (offerLabel.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    _encounterOfferIcon(encounter),
                    color: _encounterOfferColor(encounter),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      offerLabel,
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _colorForEncounterType(encounter.type),
              foregroundColor: Colors.white,
            ),
            child: const Text('Travel'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final prevLat = _campaign.lastTravelLat;
      final prevLng = _campaign.lastTravelLng;
      _logSupply(
        'Travel confirm: encounter=${_campaign.encounterNumber} from=($prevLat,$prevLng) to=(${pos.latitude},${pos.longitude}) home=(${_campaign.homeTownLat},${_campaign.homeTownLng}) km=${distanceKm?.toStringAsFixed(1) ?? "?"} modifier=$supplyModifierAtDestination',
      );
      setState(() {
        _campaign.lastTravelLat = pos.latitude;
        _campaign.lastTravelLng = pos.longitude;
        _campaign.addTravelPoint(pos.latitude, pos.longitude);
        _campaign.recordVisitedNode(pos.latitude, pos.longitude);
      });
      await _saveCampaign();
      if (!mounted) return;
      _onEncounterSelected(encounter);
    }
  }

  Widget _buildRealMapSelection() {
    final center = _mapCenterForAct(_campaign.act);
    final choices = _campaign.currentChoices;
    final locations = _candidateLocationsForChapter(
      act: _campaign.act,
      chapterIndex: _campaign.encounterNumber,
    );
    final clusterCenter = _centerOfLatLngs(locations);
    final travelPoints = _campaign.travelHistory
        .map((p) => LatLng(p.lat, p.lng))
        .toList();

    final townLat = _campaign.homeTownLat;
    final townLng = _campaign.homeTownLng;
    final townName = _campaign.homeTownName ?? 'Home Town';

    // Build full route points: Home Town -> travel history.
    final routePoints = <LatLng>[];
    if (townLat != null && townLng != null) {
      routePoints.add(LatLng(townLat, townLng));
    }
    routePoints.addAll(travelPoints);

    // Build per-segment polylines and number labels.
    final routeShadowPolylines = <Polyline>[];
    final routeColorPolylines = <Polyline>[];
    final routeNumberMarkers = <Marker>[];
    if (routePoints.length >= 2) {
      final baseHsl = HSLColor.fromColor(Colors.tealAccent);
      for (int i = 0; i < routePoints.length - 1; i++) {
        final a = routePoints[i];
        final b = routePoints[i + 1];
        final hue = (baseHsl.hue + (i * 18)) % 360;
        final color = baseHsl.withHue(hue).toColor().withValues(alpha: 0.85);

        routeShadowPolylines.add(
          Polyline(
            points: [a, b],
            strokeWidth: 7,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        );
        routeColorPolylines.add(
          Polyline(points: [a, b], strokeWidth: 4, color: color),
        );

        // Number label placed at segment midpoint.
        final mid = LatLng(
          (a.latitude + b.latitude) / 2,
          (a.longitude + b.longitude) / 2,
        );
        routeNumberMarkers.add(
          Marker(
            point: mid,
            width: 26,
            height: 26,
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }
    }

    final markers = <Marker>[];
    if (townLat != null && townLng != null) {
      final pos = LatLng(townLat, townLng);
      markers.add(
        Marker(
          point: pos,
          width: 70,
          height: 70,
          child: GestureDetector(
            onTap: () {
              _openHomeTown();
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.teal[700]!.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.home, color: Colors.white, size: 22),
                  const SizedBox(height: 2),
                  Text(
                    townName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Hero marker: last travel position (fallback to Home Town).
    LatLng? heroPos;
    if (_campaign.lastTravelLat != null && _campaign.lastTravelLng != null) {
      heroPos = LatLng(_campaign.lastTravelLat!, _campaign.lastTravelLng!);
    } else if (townLat != null && townLng != null) {
      heroPos = LatLng(townLat, townLng);
    }
    if (heroPos != null) {
      markers.add(
        Marker(
          point: heroPos,
          width: 62,
          height: 62,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.person_pin_circle,
                  color: Colors.black,
                  size: 34,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (townLat != null && townLng != null) {
      final km = _campaign.distanceHomeToHeroKm();

      // Group deliveries by location to avoid stacking markers
      final deliveriesByLocation =
          <
            String,
            List<
              ({
                PendingCardDelivery delivery,
                String phase,
                int eta,
                int prodRemaining,
                double lat,
                double lng,
              })
            >
          >{};

      for (final d in _campaign.pendingCardDeliveries) {
        if (d.forcedArrivesAtEncounter != null) {
          continue;
        }

        final isProduced = _campaign.isDeliveryProduced(d);
        final eta = _campaign.encountersUntilDeliveryArrives(d);
        final prodRemaining = _campaign.encountersUntilDeliveryProduced(d);

        double lat;
        double lng;
        String phase;

        if (!isProduced) {
          // Still in production: show at Home Town
          lat = townLat;
          lng = townLng;
          phase = 'Producing';
        } else if (heroPos != null && km != null && km > 0) {
          // Traveling: interpolate position
          final frac = (d.traveledKm / km).clamp(0.0, 1.0);
          lat = townLat + ((heroPos.latitude - townLat) * frac);
          lng = townLng + ((heroPos.longitude - townLng) * frac);
          phase = 'Traveling';
        } else {
          continue;
        }

        // Round to 3 decimal places to group nearby markers
        final locationKey =
            '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
        deliveriesByLocation.putIfAbsent(locationKey, () => []);
        deliveriesByLocation[locationKey]!.add((
          delivery: d,
          phase: phase,
          eta: eta,
          prodRemaining: prodRemaining,
          lat: lat,
          lng: lng,
        ));
      }

      // Create one marker per location
      for (final entry in deliveriesByLocation.entries) {
        final deliveryList = entry.value;
        final firstDelivery = deliveryList.first;
        final lat = firstDelivery.lat;
        final lng = firstDelivery.lng;

        // Use orange if any are producing, green if all traveling
        final hasProducing = deliveryList.any((d) => d.phase == 'Producing');
        final markerColor = hasProducing
            ? Colors.orangeAccent
            : Colors.greenAccent;

        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 32,
            height: 32,
            child: GestureDetector(
              onTap: () {
                if (deliveryList.length == 1) {
                  _showDeliveryDetailsDialog(
                    delivery: firstDelivery.delivery,
                    phase: firstDelivery.phase,
                    eta: firstDelivery.eta,
                    prodRemaining: firstDelivery.prodRemaining,
                  );
                } else {
                  _showMultipleDeliveriesDialog(
                    deliveries: deliveryList
                        .map(
                          (d) => (
                            delivery: d.delivery,
                            phase: d.phase,
                            eta: d.eta,
                            prodRemaining: d.prodRemaining,
                          ),
                        )
                        .toList(),
                  );
                }
              },
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: markerColor.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.local_shipping,
                        color: Colors.black,
                        size: 18,
                      ),
                    ),
                  ),
                  // Show count badge if multiple deliveries
                  if (deliveryList.length > 1)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${deliveryList.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
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
    }

    for (int i = 0; i < choices.length; i++) {
      final encounter = choices[i];
      LatLng pos = locations[i % locations.length];

      // Place shop encounters closer to the current hero location / between the
      // hero and the next encounter cluster.
      pos = _shopPositionBetweenHeroAndCluster(
        encounter: encounter,
        defaultPos: pos,
        heroPos: heroPos,
        clusterCenter: clusterCenter,
      );

      if (encounter.isDefense &&
          _campaign.pendingDefenseLat != null &&
          _campaign.pendingDefenseLng != null) {
        pos = LatLng(
          _campaign.pendingDefenseLat!,
          _campaign.pendingDefenseLng!,
        );
      }

      markers.add(
        Marker(
          point: pos,
          width: 56,
          height: 56,
          child: GestureDetector(
            onTap: () => _confirmEncounterOnMap(encounter, pos),
            child: Container(
              decoration: BoxDecoration(
                color: _colorForEncounterType(
                  encounter.type,
                ).withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  _iconForEncounterType(encounter.type),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 6.4,
                minZoom: 4,
                maxZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'card_game',
                ),
                if (routeShadowPolylines.isNotEmpty)
                  PolylineLayer(polylines: routeShadowPolylines),
                if (routeColorPolylines.isNotEmpty)
                  PolylineLayer(polylines: routeColorPolylines),
                if (routeNumberMarkers.isNotEmpty)
                  MarkerLayer(markers: routeNumberMarkers),
                MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _campaign.isBossTime
                            ? 'Boss available: choose where to engage'
                            : 'Choose your next destination',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7)),
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: Colors.white),
            color: const Color(0xFF2D2D2D),
            onSelected: (value) {
              if (value == 'back') {
                Navigator.pop(context);
              } else if (value == 'legacy') {
                _openProgressionView();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'back',
                child: Row(
                  children: [
                    Icon(Icons.arrow_back, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Exit Campaign',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'legacy',
                child: Row(
                  children: [
                    Icon(Icons.account_tree, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Legacy', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Act ${_campaign.act}: ${_getActTitle(_campaign.act)}',
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
                          ? '👑 Boss available'
                          : '${_campaign.battlesUntilBoss} battles until boss',
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
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isNapoleonRealMapEnabled) ...[
                    InkWell(
                      onTap: () {
                        _openHomeTown();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.brown[600],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.brown[400]!),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.home, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Town',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  InkWell(
                    onTap: _openRelicsView,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.brown[600],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.brown[400]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Relics (${_campaign.relics.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _openItemsView,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.brown[600],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.brown[400]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_hospital,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Items (${_totalConsumables()})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showDeckView,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.brown[600],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.brown[400]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.style,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Deck (${_campaign.deck.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _totalConsumables() {
    int total = 0;
    for (final count in _campaign.consumables.values) {
      total += count;
    }
    return total;
  }

  void _openRelicsView() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Relics', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: _campaign.relics.isEmpty
              ? const Text(
                  'No relics collected yet.',
                  style: TextStyle(color: Colors.white70),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _campaign.relics.length,
                  itemBuilder: (context, index) {
                    final relicId = _campaign.relics[index];
                    final all = ShopInventory.getAllRelics();
                    final relic = all.firstWhere(
                      (r) => r.id == relicId,
                      orElse: () => all.first,
                    );
                    final isActive = _campaign.isRelicActive(relicId);
                    return ListTile(
                      leading: Icon(
                        Icons.auto_awesome,
                        color: isActive ? Colors.purpleAccent : Colors.grey,
                      ),
                      title: Text(
                        relic.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        relic.description,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      trailing: isActive
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(
                              Icons.radio_button_unchecked,
                              color: Colors.grey,
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openItemsView() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text('Items', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: _campaign.consumables.isEmpty
                ? const Text(
                    'No items collected yet.',
                    style: TextStyle(color: Colors.white70),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _campaign.consumables.keys.length,
                    itemBuilder: (context, index) {
                      final itemId = _campaign.consumables.keys.elementAt(
                        index,
                      );
                      final count = _campaign.consumables[itemId] ?? 0;
                      if (count <= 0) return const SizedBox.shrink();
                      final all = ShopInventory.getAllConsumables();
                      final item = all.firstWhere(
                        (c) => c.id == itemId,
                        orElse: () => all.first,
                      );

                      // Determine if item is usable
                      bool isUsable = true;
                      if (itemId == 'heal_potion' ||
                          itemId == 'large_heal_potion') {
                        isUsable = _campaign.health < _campaign.maxHealth;
                      }

                      return ListTile(
                        leading: const Icon(
                          Icons.local_hospital,
                          color: Colors.greenAccent,
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          item.description,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: isUsable
                                  ? () {
                                      _useConsumableItem(itemId);
                                      setDialogState(() {});
                                      setState(() {});
                                    }
                                  : null,
                              style: TextButton.styleFrom(
                                foregroundColor: isUsable
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              child: const Text('Use'),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[800],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '×$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _useConsumableItem(String itemId) {
    final count = _campaign.consumables[itemId] ?? 0;
    if (count <= 0) return;

    // Consume the item
    _campaign.consumables[itemId] = count - 1;
    if (_campaign.consumables[itemId] == 0) {
      _campaign.consumables.remove(itemId);
    }

    // Apply the effect
    if (itemId == 'heal_potion') {
      _campaign.heal(15);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Healed 15 HP!')));
    } else if (itemId == 'large_heal_potion') {
      _campaign.heal(30);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Healed 30 HP!')));
    }

    _saveCampaign();
  }

  void _showDeckView() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CampaignDeckScreen(
          campaign: _campaign,
          onRemoveCard: (card) {
            setState(() {
              _campaign.removeCard(card.id);
            });
            _saveCampaign();
          },
          onAddCard: (card) {
            setState(() {
              _campaign.addCardFromInventory(card.id);
            });
            _saveCampaign();
          },
        ),
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
              _campaign.isBossTime ? 'Boss Available' : 'Choose Your Path',
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
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _campaign.currentChoices.asMap().entries.map((entry) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildChapterCard(entry.value, entry.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterCard(Encounter encounter, int index) {
    final colors = _getEncounterColors(encounter.type);
    final offerLabel = _encounterOfferLabel(encounter);

    return GestureDetector(
      onTap: () => _onEncounterSelected(encounter),
      child: Container(
        height: 180, // Further reduced for compact layout
        decoration: BoxDecoration(
          color: Colors.brown[100],
          borderRadius: BorderRadius.circular(12), // Reduced radius
          border: Border.all(color: Colors.brown[800]!, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8, // Reduced blur
              offset: const Offset(2, 4), // Reduced offset
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with type icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(colors.icon, color: colors.iconColor, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      encounter.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colors.textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Description
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      encounter.description,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.brown[900],
                        fontStyle: FontStyle.italic,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.local_shipping,
                          color: Colors.black54,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Supply: +1',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown[800],
                          ),
                        ),
                      ],
                    ),
                    if (encounter.goldReward != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber[700]!.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: Colors.amber,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '+${encounter.goldReward} Gold',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (offerLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.brown[600]!.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _encounterOfferIcon(encounter),
                              color: _encounterOfferColor(encounter),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                offerLabel,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer / Difficulty
            if (encounter.difficulty != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.brown[200],
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Difficulty: ',
                      style: TextStyle(
                        color: Colors.brown[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    ..._buildDifficultyStars(encounter.difficulty!),
                  ],
                ),
              )
            else
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.brown[200],
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10),
                  ),
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
      case EncounterType.mystery:
        return _EncounterColors(
          background: Colors.purple[50]!,
          icon: Icons.question_mark,
          iconColor: Colors.purple[400]!,
          textColor: Colors.purple[900]!,
        );
      case EncounterType.treasure:
        return _EncounterColors(
          background: Colors.amber[50]!,
          icon: Icons.auto_awesome,
          iconColor: Colors.amber[600]!,
          textColor: Colors.amber[900]!,
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
