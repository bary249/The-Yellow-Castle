import 'dart:math';

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
import 'campaign_inventory_screen.dart';
import 'progression_screen.dart';
import '../services/campaign_persistence_service.dart';
import '../data/napoleon_progression.dart';

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

class _CampaignMapScreenState extends State<CampaignMapScreen> {
  late CampaignState _campaign;
  late EncounterGenerator _generator;
  bool _isLoading = true;
  final CampaignPersistenceService _persistence = CampaignPersistenceService();
  final MapController _mapController = MapController();

  static const List<String> _locationTerrainPool = [
    'Woods',
    'Lake',
    'Desert',
    'Marsh',
  ];
  int _homeTownBuildDiscountPercent = 0;
  bool _homeTownReduceDistancePenalty = false;

  static const String _campaignMapRelicId = 'campaign_map_relic';
  static const double _mapRelicDiscoverDistanceMeters = 25000;

  static const String _buildingTrainingGroundsId = 'building_training_grounds';
  static const String _buildingSupplyDepotId = 'building_supply_depot';
  static const String _buildingOfficersAcademyId = 'building_officers_academy';
  static const String _buildingWarCollegeId = 'building_war_college';

  final Random _random = Random();

  int _applyDiscount(int cost, int discountPercent) {
    if (discountPercent <= 0) return cost;
    final discounted = (cost * (100 - discountPercent)) / 100.0;
    return discounted.round().clamp(0, cost);
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
    });
  }

  String _cardTypeKey(GameCard card) {
    final id = card.id;
    final parts = id.split('_');
    if (parts.isNotEmpty && int.tryParse(parts.last) != null) {
      return parts.sublist(0, parts.length - 1).join('_');
    }
    return id;
  }

  List<GameCard> _campaignCardPoolForLeader(String leaderId) {
    if (leaderId == 'napoleon') {
      return buildNapoleonCampaignCardPool();
    }
    return buildStarterCardPool()
        .where((c) => !c.id.startsWith('scout_'))
        .toList();
  }

  List<GameCard> _startingSpecialCardOptions({
    required String leaderId,
    required int act,
    NapoleonProgressionState? napoleonProgression,
  }) {
    final pool = _campaignCardPoolForLeader(leaderId);
    final seen = <String>{};
    final unique = <GameCard>[];
    for (final c in pool) {
      final key = _cardTypeKey(c);
      if (seen.contains(key)) continue;
      seen.add(key);
      unique.add(c);
    }

    int desired = 2;
    if (leaderId == 'napoleon' && napoleonProgression != null) {
      desired = napoleonProgression.modifiers.startingSpecialCardOptionCount;
    }

    if (unique.length <= desired) return unique;
    return unique.take(desired).toList();
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
                  'Choose Starting Relic',
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

    if (_campaign.startingSpecialCardId == null) {
      final options = _startingSpecialCardOptions(
        leaderId: leaderId,
        act: act,
        napoleonProgression: napoleonProgression,
      );

      final chosen = options.isEmpty
          ? null
          : await _pickStartingSpecialCardWithDetails(options);

      if (chosen != null) {
        final selectedTypeKey = _cardTypeKey(chosen);
        _campaign.startingSpecialCardId = selectedTypeKey;
        _campaign.addCard(chosen.copy());
      }
    }
  }

  Future<GameCard?> _pickStartingSpecialCardWithDetails(
    List<GameCard> options,
  ) async {
    return showDialog<GameCard>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Choose Starting Special Card',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in options)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getElementColor(c.element ?? 'woods'),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.style, color: Colors.white),
                  ),
                  title: Text(
                    c.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${c.element ?? ""}  ATK:${c.damage}  HP:${c.health}  AP:${c.maxAP}',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () async {
                    final confirmed = await _showCardDetailsForPick(c);
                    if (!context.mounted) return;
                    if (confirmed == true) {
                      Navigator.pop(context, c);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showCardDetailsForPick(GameCard card) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      card.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDetailStat(
                    'ATK',
                    '${card.damage}',
                    Icons.local_fire_department,
                    Colors.orange,
                  ),
                  _buildDetailStat(
                    'HP',
                    '${card.health}',
                    Icons.favorite,
                    Colors.red,
                  ),
                  _buildDetailStat(
                    'AP',
                    '${card.maxAP}',
                    Icons.bolt,
                    Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getAttackTypeColor(card),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getAttackTypeIcon(card),
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getAttackTypeLabel(card),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (card.abilities.isNotEmpty) ...[
                const Text(
                  'Abilities',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: card.abilities
                      .map(
                        (a) => Tooltip(
                          message: _getAbilityDescription(a),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber[800],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              a.replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                ...card.abilities.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _getAbilityIcon(a),
                          color: Colors.amber[300],
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _getAbilityDescription(a),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getElementColor(
                    card.element ?? 'woods',
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getElementColor(
                      card.element ?? 'woods',
                    ).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getElementIcon(card.element ?? 'woods'),
                      color: _getElementColor(card.element ?? 'woods'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${card.element ?? "Neutral"} Unit',
                      style: TextStyle(
                        color: _getElementColor(card.element ?? 'woods'),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Choose This Card'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  }

  bool get _isNapoleonAct1MapEnabled {
    return widget.leaderId == 'napoleon' && _campaign.act == 1;
  }

  void _initMapRelicIfNeeded() {
    if (!_isNapoleonAct1MapEnabled) return;
    if (_campaign.mapRelicDiscovered) return;
    if (_campaign.mapRelicLat != null && _campaign.mapRelicLng != null) return;

    final pool = _act1MapRelicCandidateLocations();
    if (pool.isEmpty) return;

    final base = pool[_random.nextInt(pool.length)];

    // Small jitter to avoid always matching a city center exactly.
    final jitterLat = (_random.nextDouble() - 0.5) * 0.16;
    final jitterLng = (_random.nextDouble() - 0.5) * 0.16;

    _campaign.mapRelicLat = base.latitude + jitterLat;
    _campaign.mapRelicLng = base.longitude + jitterLng;
  }

  void _initHomeTownIfNeeded() {
    if (!_isNapoleonAct1MapEnabled) return;
    if (_campaign.homeTownName != null &&
        _campaign.homeTownLat != null &&
        _campaign.homeTownLng != null) {
      _ensureHomeTownStarterBuildings();
      return;
    }

    // Napoleon Act 1 home base: Nice.
    _campaign.homeTownName = 'Nice';
    _campaign.homeTownLat = 43.695;
    _campaign.homeTownLng = 7.264;
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
      HomeTownBuilding(id: _buildingTrainingGroundsId),
    ];
  }

  List<LatLng> _act1MapRelicCandidateLocations() {
    // A handful of plausible Act 1 (Italy 1796) locations.
    // The exact route is not enforced; this just keeps the relic in-theater.
    return const [
      LatLng(44.107, 7.669), // Tende / Alps pass area
      LatLng(44.384, 7.823), // Mondovì
      LatLng(44.418, 8.869), // Genoa outskirts
      LatLng(44.913, 8.616), // Alessandria
      LatLng(45.041, 7.657), // Turin outskirts
      LatLng(45.184, 9.159), // Pavia area
      LatLng(45.309, 9.503), // Lodi
      LatLng(45.263, 10.992), // Mantua
    ];
  }

  Future<void> _maybeDiscoverMapRelicAfterEncounter(Encounter encounter) async {
    if (!_isNapoleonAct1MapEnabled) return;
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
    setState(() {
      _campaign.mapRelicDiscovered = true;
      _campaign.addRelic(_campaignMapRelicId);
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
        actions: [
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

  int _homeTownUpgradeCost(int currentLevel) {
    return 50 + (currentLevel - 1) * 50;
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
      default:
        return id;
    }
  }

  String _homeTownBuildingDescription(String id) {
    switch (id) {
      case _buildingTrainingGroundsId:
        return 'Provides a common unit card once per encounter.';
      case _buildingSupplyDepotId:
        return 'Provides gold once per encounter.';
      case _buildingOfficersAcademyId:
        return 'Provides a rare unit card on a longer supply schedule.';
      case _buildingWarCollegeId:
        return 'Provides an epic unit card on a longer supply schedule.';
      default:
        return '';
    }
  }

  int _homeTownBuildCost(String id) {
    switch (id) {
      case _buildingSupplyDepotId:
        return 120;
      case _buildingOfficersAcademyId:
        return 220;
      case _buildingWarCollegeId:
        return 320;
      default:
        return 0;
    }
  }

  int _distanceSupplyPenaltyEncounters() {
    final townLat = _campaign.homeTownLat;
    final townLng = _campaign.homeTownLng;
    final travelLat = _campaign.lastTravelLat;
    final travelLng = _campaign.lastTravelLng;
    if (townLat == null ||
        townLng == null ||
        travelLat == null ||
        travelLng == null) {
      return 0;
    }

    final distanceMeters = const Distance()(
      LatLng(travelLat, travelLng),
      LatLng(townLat, townLng),
    );
    final km = distanceMeters / 1000.0;
    final basePenalty = (km < 80)
        ? 0
        : (km < 180)
        ? 1
        : (km < 320)
        ? 2
        : (km < 500)
        ? 3
        : 4;
    final reduction = _homeTownReduceDistancePenalty ? 1 : 0;
    return (basePenalty - reduction).clamp(0, basePenalty).toInt();
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
      _ => 1,
    };
  }

  int _buildingSupplyEveryEncounters(HomeTownBuilding building) {
    final penalty = _distanceSupplyPenaltyEncounters();
    final base = _buildingBaseSupplyEveryEncounters(building);
    return base + penalty;
  }

  String _buildingSupplyBreakdownText(HomeTownBuilding building) {
    final base = _buildingBaseSupplyEveryEncounters(building);
    final penalty = _distanceSupplyPenaltyEncounters();
    final total = base + penalty;
    if (penalty <= 0) {
      return 'Supply: every $base encounter${base == 1 ? "" : "s"}';
    }
    return 'Supply: $base + $penalty = $total encounters';
  }

  String _buildingSupplyStatusText(HomeTownBuilding building) {
    final interval = _buildingSupplyEveryEncounters(building);
    final sinceLast =
        _campaign.encounterNumber - building.lastCollectedEncounter;
    final remaining = interval - sinceLast;
    if (remaining <= 0) return 'Ready';
    if (remaining == 1) return 'Ready in 1 encounter';
    return 'Ready in $remaining encounters';
  }

  bool _canCollectBuilding(HomeTownBuilding building) {
    final interval = _buildingSupplyEveryEncounters(building);
    return (_campaign.encounterNumber - building.lastCollectedEncounter) >=
        interval;
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

  Future<void> _applyEncounterOffer(Encounter encounter) async {
    final type = encounter.offerType;
    final id = encounter.offerId;
    if (type == null || id == null || id.isEmpty) return;
    final amount = encounter.offerAmount ?? 1;

    String message = '';
    IconData icon = Icons.card_giftcard;
    Color iconColor = Colors.amber;

    if (type == 'consumable') {
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
      if (!_campaign.hasRelic(id)) {
        setState(() {
          _campaign.addRelic(id);
        });
      }
      final all = ShopInventory.getAllRelics();
      final item = all.where((e) => e.id == id).toList();
      final name = item.isNotEmpty ? item.first.name : id;
      message = 'Received: $name';
      icon = Icons.auto_awesome;
      iconColor = Colors.purpleAccent;
    } else if (type == 'building') {
      final alreadyBuilt = _campaign.homeTownBuildings.any((b) => b.id == id);
      if (!alreadyBuilt) {
        setState(() {
          _campaign.homeTownBuildings = [
            ..._campaign.homeTownBuildings,
            HomeTownBuilding(id: id),
          ];
        });
      }
      message = 'Offered: ${_homeTownBuildingName(id)}';
      icon = Icons.apartment;
      iconColor = Colors.tealAccent;
    } else {
      return;
    }

    await _saveCampaign();
    await _showEncounterRewardDialog(
      title: 'Reward',
      message: message,
      icon: icon,
      iconColor: iconColor,
    );
  }

  String _encounterOfferLabel(Encounter encounter) {
    final type = encounter.offerType;
    final id = encounter.offerId;
    if (type == null || id == null || id.isEmpty) return '';
    final amount = encounter.offerAmount ?? 1;

    if (type == 'consumable') {
      final all = ShopInventory.getAllConsumables();
      final item = all.where((e) => e.id == id).toList();
      final name = item.isNotEmpty ? item.first.name : id;
      return amount > 1 ? 'Offer: $name ×$amount' : 'Offer: $name';
    }
    if (type == 'relic') {
      final all = ShopInventory.getAllRelics();
      final item = all.where((e) => e.id == id).toList();
      final name = item.isNotEmpty ? item.first.name : id;
      return 'Offer: $name';
    }
    if (type == 'building') {
      return 'Offer: ${_homeTownBuildingName(id)}';
    }
    return 'Offer: $id';
  }

  IconData _encounterOfferIcon(Encounter encounter) {
    switch (encounter.offerType) {
      case 'consumable':
        return Icons.local_hospital;
      case 'relic':
        return Icons.auto_awesome;
      case 'building':
        return Icons.apartment;
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
      case 'building':
        return Colors.tealAccent;
      default:
        return Colors.amber;
    }
  }

  Future<void> _collectBuilding(HomeTownBuilding building) async {
    if (!_canCollectBuilding(building)) return;

    if (building.id == _buildingTrainingGroundsId) {
      final candidates = ShopInventory.getCardsForAct(_campaign.act);
      if (candidates.isNotEmpty) {
        candidates.shuffle(_random);
        final card = candidates.first;
        setState(() {
          _campaign.addCard(card);
          building.lastCollectedEncounter = _campaign.encounterNumber;
        });
        await _saveCampaign();
        await _showHomeTownDeliveryDialog(
          title: 'Training Grounds',
          message: 'Delivered: ${card.name}',
          icon: Icons.military_tech,
          iconColor: Colors.greenAccent,
        );
      }
      return;
    }

    if (building.id == _buildingSupplyDepotId) {
      const goldReward = 15;
      setState(() {
        _campaign.addGold(goldReward);
        building.lastCollectedEncounter = _campaign.encounterNumber;
      });
      await _saveCampaign();
      await _showHomeTownDeliveryDialog(
        title: 'Supply Depot',
        message: 'Delivered: +15 Gold',
        icon: Icons.monetization_on,
        iconColor: Colors.amber,
      );
      return;
    }

    if (building.id == _buildingOfficersAcademyId) {
      final candidates = ShopInventory.getCardsForAct(
        _campaign.act,
      ).where((c) => c.rarity == 2).toList();
      if (candidates.isNotEmpty) {
        candidates.shuffle(_random);
        final card = candidates.first;
        setState(() {
          _campaign.addCard(card);
          building.lastCollectedEncounter = _campaign.encounterNumber;
        });
        await _saveCampaign();
        await _showHomeTownDeliveryDialog(
          title: 'Officers Academy',
          message: 'Delivered: ${card.name}',
          icon: Icons.school,
          iconColor: Colors.lightBlueAccent,
        );
      }
      return;
    }

    if (building.id == _buildingWarCollegeId) {
      final candidates = ShopInventory.getCardsForAct(
        _campaign.act,
      ).where((c) => c.rarity == 3).toList();
      if (candidates.isNotEmpty) {
        candidates.shuffle(_random);
        final card = candidates.first;
        setState(() {
          _campaign.addCard(card);
          building.lastCollectedEncounter = _campaign.encounterNumber;
        });
        await _saveCampaign();
        await _showHomeTownDeliveryDialog(
          title: 'War College',
          message: 'Delivered: ${card.name}',
          icon: Icons.auto_awesome,
          iconColor: Colors.purpleAccent,
        );
      }
      return;
    }
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

                      return Card(
                        color: Colors.grey[850],
                        child: ListTile(
                          title: Text(
                            _homeTownBuildingName(id),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _homeTownBuildingDescription(id),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: ElevatedButton(
                            onPressed: canAfford
                                ? () async {
                                    setState(() {
                                      _campaign.spendGold(effectiveCost);
                                      _campaign.homeTownBuildings = [
                                        ..._campaign.homeTownBuildings,
                                        HomeTownBuilding(id: id),
                                      ];
                                    });
                                    await _saveCampaign();
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber[700],
                              foregroundColor: Colors.black,
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
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final name = _campaign.homeTownName ?? 'Home Town';
          final level = _campaign.homeTownLevel;
          final cost = _homeTownUpgradeCost(level);
          final canUpgrade = _campaign.gold >= cost;
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
                        Expanded(
                          child: Text(
                            'Town Level: $level',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canUpgrade
                          ? () async {
                              setState(() {
                                _campaign.spendGold(cost);
                                _campaign.homeTownLevel += 1;
                              });
                              setSheetState(() {});
                              await _saveCampaign();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Upgrade (Cost: $cost)'),
                    ),
                  ),
                  const SizedBox(height: 18),
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
                      final label = canCollect ? 'Collect' : 'Waiting';

                      return Card(
                        color: Colors.grey[850],
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(
                            _homeTownBuildingName(b.id),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '${_homeTownBuildingDescription(b.id)}\n${_buildingSupplyBreakdownText(b)}\n${_buildingSupplyStatusText(b)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: ElevatedButton(
                            onPressed: canCollect
                                ? () async {
                                    await _collectBuilding(b);
                                    setSheetState(() {});
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                            ),
                            child: Text(label),
                          ),
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

    if (_campaign.isBossTime) {
      // Time for the boss!
      final boss = _generator.generateBoss();
      final choices = <Encounter>[boss];
      if (pendingDefense != null) {
        choices.add(pendingDefense);
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

    String pickFrom(List<String> values) {
      if (values.isEmpty) return _locationTerrainPool.first;
      return values[rng.nextInt(values.length)];
    }

    // Enemy base and middle terrain are determined from location.
    final enemyBaseTerrain = pickFrom(_locationTerrainPool);
    var middleTerrain = pickFrom(_locationTerrainPool);
    if (middleTerrain == enemyBaseTerrain && _locationTerrainPool.length > 1) {
      middleTerrain = pickFrom(
        _locationTerrainPool.where((t) => t != enemyBaseTerrain).toList(),
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

  Future<void> _maybeOfferVisitHomeTownAfterEncounter() async {
    if (!_isNapoleonAct1MapEnabled) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final goHomeTown = await showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'After-Action',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Do you want to visit your Home Town before choosing your next destination?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Home Town'),
          ),
        ],
      ),
    );

    if (goHomeTown == true) {
      await _openHomeTown();
    }
  }

  String _locationLabelForCurrentTravel() {
    final lat = _campaign.lastTravelLat;
    final lng = _campaign.lastTravelLng;
    if (lat == null || lng == null) return 'Unknown location';
    return '${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)}';
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
    if (!_isNapoleonAct1MapEnabled) return;
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
              setState(() {
                _campaign.addGold(goldReward);
                _campaign.completeEncounter();
                _generateNewChoices();
              });
              await _saveCampaign();
              await _applyEncounterOffer(encounter);
              await _maybeDiscoverMapRelicAfterEncounter(encounter);
              await _showStoryAfterEncounter(encounter);
              await _maybeOfferVisitHomeTownAfterEncounter();
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
          heroAbilityDamageBoost: mods.heroAbilityDamageBoost,
          playerCurrentHealth: _campaign.health,
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
        await _awardBattleLegacyPoints(encounter);
        final int reward =
            (encounter.goldReward ?? 15) + _campaign.goldPerBattleBonus;
        setState(() {
          _campaign.addGold(reward);
        });

        await _applyEncounterOffer(encounter);

        // Show card reward selection
        if (mounted) {
          await _showCardRewardDialog();
        }

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
          _campaign.completeEncounter();
          _generateNewChoices();
        });
        await _saveCampaign();
        await _showStoryAfterEncounter(encounter);
        await _maybeOfferVisitHomeTownAfterEncounter();
      } else {
        if (_campaign.health <= 0) {
          await _showGameOver();
        }
      }
    } else {
      // Battle was exited - show retreat dialog
      _showRetreatDialog(encounter);
    }
  }

  Future<void> _showCardRewardDialog() async {
    final availableCards = ShopInventory.getCardsForAct(_campaign.act);
    availableCards.shuffle();
    final rewards = availableCards.take(3).toList();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Victory! Choose a Reward',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
          child: ListView.builder(
            itemCount: rewards.length,
            itemBuilder: (context, index) {
              final card = rewards[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getElementColor(card.element ?? 'woods'),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.style, color: Colors.white),
                  ),
                  title: Text(
                    card.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${card.element ?? "Neutral"} - ${card.damage} ATK / ${card.health} HP\n${card.abilities.isEmpty ? "No abilities" : card.abilities.join(", ")}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      _campaign.addCard(card);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added ${card.name} to your deck!'),
                        ),
                      );
                      _saveCampaign();
                    },
                    child: const Text('Pick'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
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
          customDeck: _campaign.deck,
          predefinedTerrainsOverride: predefinedTerrainsOverride,
          playerCurrentHealth: _campaign.health,
          playerDamageBonus: _campaign.globalDamageBonus,
          extraStartingDraw: mods.extraStartingDraw,
          artilleryDamageBonus: mods.artilleryDamageBonus,
          heroAbilityDamageBoost: mods.heroAbilityDamageBoost,
          opponentBaseHP: bossOpponentBaseHP,
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
        }
      }
    } else {
      _showRetreatDialog(encounter);
    }
  }

  void _startNextAct() {
    setState(() {
      _campaign.nextAct();
      // Re-initialize generator for the new act
      _generator = EncounterGenerator(act: _campaign.act);
      _generateNewChoices();
    });
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
                      setState(() {
                        _campaign.completeEncounter();
                        _generateNewChoices();
                      });
                      _saveCampaign();
                      await _showStoryAfterEncounter(encounter);
                      await _maybeOfferVisitHomeTownAfterEncounter();
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

  Widget _buildDetailStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
      ],
    );
  }

  String _getAttackType(GameCard card) {
    if (card.isLongRange || card.abilities.contains('far_attack')) {
      return 'long_range';
    }
    if (card.isRanged) return 'ranged';
    return 'melee';
  }

  Color _getAttackTypeColor(GameCard card) {
    switch (_getAttackType(card)) {
      case 'long_range':
        return Colors.deepOrange[700]!;
      case 'ranged':
        return Colors.teal[600]!;
      default:
        return Colors.red[700]!;
    }
  }

  IconData _getAttackTypeIcon(GameCard card) {
    switch (_getAttackType(card)) {
      case 'long_range':
        return Icons.gps_fixed;
      case 'ranged':
        return Icons.arrow_forward;
      default:
        return Icons.sports_martial_arts;
    }
  }

  String _getAttackTypeLabel(GameCard card) {
    switch (_getAttackType(card)) {
      case 'long_range':
        return 'LONG RANGE (2 tiles)';
      case 'ranged':
        return 'RANGED (No Retaliation)';
      default:
        return 'MELEE';
    }
  }

  IconData _getAbilityIcon(String ability) {
    switch (ability) {
      case 'guard':
        return Icons.security;
      case 'scout':
        return Icons.visibility;
      case 'long_range':
        return Icons.gps_fixed;
      case 'ranged':
        return Icons.arrow_forward;
      case 'flanking':
        return Icons.swap_horiz;
      case 'cavalry':
        return Icons.directions_run;
      case 'pikeman':
        return Icons.vertical_align_top;
      case 'archer':
        return Icons.arrow_forward;
      default:
        if (ability.startsWith('inspire')) return Icons.music_note;
        if (ability.startsWith('fury')) return Icons.local_fire_department;
        if (ability.startsWith('shield')) return Icons.shield;
        if (ability.startsWith('thorns')) return Icons.grass;
        if (ability.startsWith('regen') || ability.startsWith('regenerate')) {
          return Icons.healing;
        }
        if (ability.startsWith('rally')) return Icons.campaign;
        if (ability.startsWith('command')) return Icons.military_tech;
        if (ability == 'first_strike') return Icons.bolt;
        if (ability == 'far_attack') return Icons.adjust;
        if (ability == 'cleave') return Icons.all_inclusive;
        return Icons.star;
    }
  }

  String _getAbilityDescription(String ability) {
    if (ability.startsWith('shield_')) {
      final value = ability.split('_').last;
      return 'Reduces incoming damage by $value.';
    }
    if (ability.startsWith('fury_')) {
      final value = ability.split('_').last;
      return '+$value damage on attack and retaliation.';
    }
    if (ability.startsWith('inspire_')) {
      final value = ability.split('_').last;
      return '+$value damage to all friendly units in this lane.';
    }
    if (ability.startsWith('rally_')) {
      final value = ability.split('_').last;
      return '+$value damage to adjacent ally in stack.';
    }
    if (ability.startsWith('command_')) {
      final value = ability.split('_').last;
      return '+$value damage AND +$value shield to all allies in lane.';
    }
    if (ability.startsWith('thorns_')) {
      final value = ability.split('_').last;
      return 'Deals $value damage to attackers after combat.';
    }
    if (ability.startsWith('regen_')) {
      final value = ability.split('_').last;
      return 'Regenerates $value HP at the start of each turn.';
    }

    switch (ability) {
      case 'guard':
        return 'Must be defeated before other units can be targeted.';
      case 'scout':
        return 'Reveals enemy cards in adjacent lanes.';
      case 'long_range':
        return 'Can attack enemies 2 tiles away.';
      case 'ranged':
        return 'Attacks without triggering retaliation from melee units.';
      case 'flanking':
        return 'Can move to adjacent lanes (left/right).';
      case 'first_strike':
        return 'Attacks FIRST in the same tick. Can kill before counterattacks.';
      case 'far_attack':
        return 'Attacks enemies at OTHER tiles in same lane. Disabled if contested.';
      case 'cleave':
        return 'Hits BOTH enemies on the same tile with full damage.';
      default:
        return ability.replaceAll('_', ' ');
    }
  }

  IconData _getElementIcon(String element) {
    switch (element.toLowerCase()) {
      case 'woods':
        return Icons.forest;
      case 'lake':
        return Icons.water_drop;
      case 'desert':
        return Icons.wb_sunny;
      default:
        return Icons.help_outline;
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

  Future<bool> _showRemoveCardDialog() async {
    final result = await showDialog<bool>(
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
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed ${card.name} from deck')),
                  );
                  setState(() {});
                  _saveCampaign();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _openInventory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CampaignInventoryScreen(
          campaign: _campaign,
          onChanged: () {
            setState(() {});
            _saveCampaign();
          },
          onRequestRemoveCard: _showRemoveCardDialog,
        ),
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
              await _maybeOfferVisitHomeTownAfterEncounter();
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
    } else if (offerType == 'building' && offerId != null) {
      rewardLine = 'Offer: ${_homeTownBuildingName(offerId)}';
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
              setState(() {
                _campaign.completeEncounter();
                _generateNewChoices();
              });
              await _saveCampaign();
              await _applyEncounterOffer(encounter);
              await _maybeDiscoverMapRelicAfterEncounter(encounter);
              await _showStoryAfterEncounter(encounter);
              await _maybeOfferVisitHomeTownAfterEncounter();
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
                child: (widget.leaderId == 'napoleon' && _campaign.act == 1)
                    ? _buildRealMapSelection()
                    : _buildChapterSelection(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LatLng _act1ItalyCenter() {
    // Northern Italy / Alps theater (1796 campaign).
    return const LatLng(45.2, 8.6);
  }

  // For MVP: map the *currentChoices* (2-3 encounters) to plausible real locations
  // that progress generally toward Milan. We keep it deterministic per chapter.
  List<LatLng> _act1CandidateLocationsForChapter(int chapterIndex) {
    // The closer we are to boss, the closer we get to Milan.
    // Approximate key areas: Nice, Savona, Genoa, Alessandria, Pavia/Milan.
    final stage = _campaign.encounterNumber.clamp(0, 4);
    final pool = <List<LatLng>>[
      // Chapter 1-2: Ligurian coast / entry into Italy.
      const [
        LatLng(43.695, 7.264), // Nice
        LatLng(44.309, 8.477), // Savona
        LatLng(44.405, 8.946), // Genoa
      ],
      // Chapter 2-3: inland / Piedmont.
      const [
        LatLng(44.558, 7.734), // Cuneo
        LatLng(44.915, 8.617), // Alessandria
        LatLng(45.070, 7.687), // Turin
      ],
      // Chapter 3-4: Lombardy approach.
      const [
        LatLng(45.133, 9.158), // Pavia
        LatLng(45.453, 9.183), // Milan
        LatLng(45.464, 9.190), // Milan (alt point for spacing)
      ],
      // Chapter 4-5: near boss.
      const [
        LatLng(45.470, 9.190), // Milan
        LatLng(45.542, 9.270), // Monza
        LatLng(45.500, 9.090), // West of Milan
      ],
      // Boss focus.
      const [
        LatLng(45.464, 9.190), // Milan (boss)
        LatLng(45.453, 9.183),
        LatLng(45.470, 9.200),
      ],
    ];

    final chosenPool = pool[stage];
    // Rotate based on chapterIndex so the same encounterNumber doesn’t always map to same spot.
    final rotated = <LatLng>[];
    for (int i = 0; i < chosenPool.length; i++) {
      rotated.add(chosenPool[(i + chapterIndex) % chosenPool.length]);
    }
    return rotated;
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
      setState(() {
        _campaign.lastTravelLat = pos.latitude;
        _campaign.lastTravelLng = pos.longitude;
        _campaign.addTravelPoint(pos.latitude, pos.longitude);
      });
      await _saveCampaign();
      if (!mounted) return;
      _onEncounterSelected(encounter);
    }
  }

  Widget _buildRealMapSelection() {
    final center = _act1ItalyCenter();
    final choices = _campaign.currentChoices;
    final locations = _act1CandidateLocationsForChapter(
      _campaign.encounterNumber,
    );
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

    for (int i = 0; i < choices.length; i++) {
      final encounter = choices[i];
      LatLng pos = locations[i % locations.length];
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
                            ? 'Final Battle: choose where to engage'
                            : 'Choose your next destination',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
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
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isNapoleonAct1MapEnabled) ...[
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
                    onTap: _openProgressionView,
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_tree,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Legacy',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _openInventory,
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Inventory',
                            style: TextStyle(color: Colors.white, fontSize: 12),
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
              _campaign.isBossTime ? 'Final Battle' : 'Choose Your Path',
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
                                maxLines: 1,
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
