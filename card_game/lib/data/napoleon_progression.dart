/// Napoleon's progression tree - unlockable abilities and upgrades
/// Progression is earned through campaign victories and achievements

/// Progression node types
enum ProgressionNodeType {
  heroAbility, // Upgrades Napoleon's hero ability
  deckBonus, // Passive bonuses to deck/cards
  startingBonus, // Bonuses at campaign start
  special, // Unique unlocks
}

/// A single node in the progression tree
class ProgressionNode {
  final String id;
  final String name;
  final String description;
  final ProgressionNodeType type;
  final int cost; // Progression points to unlock
  final List<String> prerequisites; // Node IDs that must be unlocked first
  final String? effect; // Effect identifier for game logic
  final int tier; // Visual tier (0 = start, 1-3 = branches)

  const ProgressionNode({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.cost,
    this.prerequisites = const [],
    this.effect,
    this.tier = 0,
  });
}

/// Napoleon's complete progression tree
class NapoleonProgression {
  /// All available progression nodes
  static const List<ProgressionNode> nodes = [
    // === TIER 0: Starting Node ===
    ProgressionNode(
      id: 'start',
      name: 'Young General',
      description: 'Begin your journey as Napoleon Bonaparte',
      type: ProgressionNodeType.special,
      cost: 0,
      tier: 0,
    ),

    // === TIER 1: First Choices ===
    // Military Branch
    ProgressionNode(
      id: 'tactical_genius_1',
      name: 'Tactical Genius I',
      description: 'Draw 1 extra card at the start of each battle',
      type: ProgressionNodeType.deckBonus,
      cost: 1,
      prerequisites: ['start'],
      effect: 'extra_draw_1',
      tier: 1,
    ),
    // Economic Branch
    ProgressionNode(
      id: 'war_chest_1',
      name: 'War Chest I',
      description: '+10 starting gold in campaigns',
      type: ProgressionNodeType.startingBonus,
      cost: 1,
      prerequisites: ['start'],
      effect: 'starting_gold_10',
      tier: 1,
    ),
    // Leadership Branch
    ProgressionNode(
      id: 'inspiring_presence_1',
      name: 'Inspiring Presence I',
      description: 'Hero ability also grants +1 damage this turn',
      type: ProgressionNodeType.heroAbility,
      cost: 1,
      prerequisites: ['start'],
      effect: 'hero_damage_boost_1',
      tier: 1,
    ),

    // === TIER 2: Specializations ===
    // Military Branch continued
    ProgressionNode(
      id: 'artillery_master',
      name: 'Artillery Master',
      description: 'All Artillery units gain +1 damage',
      type: ProgressionNodeType.deckBonus,
      cost: 2,
      prerequisites: ['tactical_genius_1'],
      effect: 'artillery_damage_1',
      tier: 2,
    ),
    ProgressionNode(
      id: 'tactical_genius_2',
      name: 'Tactical Genius II',
      description: 'Draw 2 extra cards at the start of each battle',
      type: ProgressionNodeType.deckBonus,
      cost: 3,
      prerequisites: ['tactical_genius_1'],
      effect: 'extra_draw_2',
      tier: 2,
    ),

    // Economic Branch continued
    ProgressionNode(
      id: 'war_chest_2',
      name: 'War Chest II',
      description: '+25 starting gold in campaigns',
      type: ProgressionNodeType.startingBonus,
      cost: 2,
      prerequisites: ['war_chest_1'],
      effect: 'starting_gold_25',
      tier: 2,
    ),
    ProgressionNode(
      id: 'merchant_connections',
      name: 'Merchant Connections',
      description: '15% discount at all shops',
      type: ProgressionNodeType.startingBonus,
      cost: 2,
      prerequisites: ['war_chest_1'],
      effect: 'shop_discount_15',
      tier: 2,
    ),

    // Leadership Branch continued
    ProgressionNode(
      id: 'inspiring_presence_2',
      name: 'Inspiring Presence II',
      description: 'Hero ability grants +2 damage this turn',
      type: ProgressionNodeType.heroAbility,
      cost: 2,
      prerequisites: ['inspiring_presence_1'],
      effect: 'hero_damage_boost_2',
      tier: 2,
    ),
    ProgressionNode(
      id: 'old_guard',
      name: 'Old Guard',
      description: 'Start each campaign with a Grenadier in your deck',
      type: ProgressionNodeType.startingBonus,
      cost: 3,
      prerequisites: ['inspiring_presence_1'],
      effect: 'starting_grenadier',
      tier: 2,
    ),

    // === TIER 3: Mastery ===
    ProgressionNode(
      id: 'emperor',
      name: 'Emperor of France',
      description: 'All units gain +1 HP. Unlocks Imperial Guard units.',
      type: ProgressionNodeType.special,
      cost: 5,
      prerequisites: ['tactical_genius_2', 'inspiring_presence_2'],
      effect: 'emperor_unlock',
      tier: 3,
    ),
    ProgressionNode(
      id: 'grand_armee',
      name: 'La Grande Armée',
      description: '+5 max HP. Start with 2 extra cards in hand.',
      type: ProgressionNodeType.startingBonus,
      cost: 4,
      prerequisites: ['artillery_master', 'old_guard'],
      effect: 'grand_armee',
      tier: 3,
    ),
    ProgressionNode(
      id: 'continental_system',
      name: 'Continental System',
      description: '+50 starting gold. Shops have better items.',
      type: ProgressionNodeType.startingBonus,
      cost: 4,
      prerequisites: ['war_chest_2', 'merchant_connections'],
      effect: 'continental_system',
      tier: 3,
    ),
  ];

  /// Get a node by ID
  static ProgressionNode? getNode(String id) {
    try {
      return nodes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get all nodes at a specific tier
  static List<ProgressionNode> getNodesAtTier(int tier) {
    return nodes.where((n) => n.tier == tier).toList();
  }

  /// Check if a node can be unlocked given current unlocks
  static bool canUnlock(String nodeId, Set<String> unlockedNodes) {
    final node = getNode(nodeId);
    if (node == null) return false;
    if (unlockedNodes.contains(nodeId)) return false;

    // Check all prerequisites are met
    for (final prereq in node.prerequisites) {
      if (!unlockedNodes.contains(prereq)) return false;
    }
    return true;
  }

  /// Get total progression points needed to unlock everything
  static int get totalCost => nodes.fold(0, (sum, n) => sum + n.cost);
}

/// Player's Napoleon progression state
class NapoleonProgressionState {
  Set<String> unlockedNodes;
  int progressionPoints;

  NapoleonProgressionState({
    Set<String>? unlockedNodes,
    this.progressionPoints = 0,
  }) : unlockedNodes = unlockedNodes ?? {'start'};

  /// Unlock a node if possible
  bool unlock(String nodeId) {
    final node = NapoleonProgression.getNode(nodeId);
    if (node == null) return false;
    if (!NapoleonProgression.canUnlock(nodeId, unlockedNodes)) return false;
    if (progressionPoints < node.cost) return false;

    progressionPoints -= node.cost;
    unlockedNodes.add(nodeId);
    return true;
  }

  /// Add progression points (earned from victories)
  void addPoints(int points) {
    progressionPoints += points;
  }

  /// Check if a specific effect is active
  bool hasEffect(String effect) {
    for (final nodeId in unlockedNodes) {
      final node = NapoleonProgression.getNode(nodeId);
      if (node?.effect == effect) return true;
    }
    return false;
  }

  /// Get the value of a numeric effect (e.g., extra_draw_2 returns 2)
  int getEffectValue(String effectPrefix) {
    int maxValue = 0;
    for (final nodeId in unlockedNodes) {
      final node = NapoleonProgression.getNode(nodeId);
      if (node?.effect?.startsWith(effectPrefix) ?? false) {
        final parts = node!.effect!.split('_');
        final value = int.tryParse(parts.last) ?? 0;
        if (value > maxValue) maxValue = value;
      }
    }
    return maxValue;
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'unlockedNodes': unlockedNodes.toList(),
    'progressionPoints': progressionPoints,
  };

  /// Deserialize from JSON
  factory NapoleonProgressionState.fromJson(Map<String, dynamic> json) {
    return NapoleonProgressionState(
      unlockedNodes: Set<String>.from(json['unlockedNodes'] ?? ['start']),
      progressionPoints: json['progressionPoints'] ?? 0,
    );
  }
}
