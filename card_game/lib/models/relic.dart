import 'dart:math';
import 'card.dart';
import '../data/card_library.dart';

/// Types of relics that can be found on the battlefield.
/// Currently only RandomCard, but designed for future expansion.
enum RelicType {
  /// Adds a random card to the player's deck
  randomCard,
  // Future relic types can be added here:
  // goldBonus,
  // healCrystal,
  // extraDraw,
  // etc.
}

/// Represents a relic that can be found on the battlefield.
/// Relics are hidden until a player reaches their tile.
class Relic {
  final String id;
  final RelicType type;
  final String name;
  final String description;

  /// Whether this relic has been claimed by a player
  bool isClaimed = false;

  /// ID of the player who claimed this relic (null if unclaimed)
  String? claimedByPlayerId;

  /// The card that was generated (for RandomCard type)
  GameCard? generatedCard;

  Relic({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
  });

  /// Create a random card relic
  factory Relic.randomCard({String? id}) {
    return Relic(
      id: id ?? 'relic_${DateTime.now().millisecondsSinceEpoch}',
      type: RelicType.randomCard,
      name: 'Ancient Artifact',
      description: 'Grants a random card when claimed.',
    );
  }

  /// Claim this relic for a player.
  /// Returns the reward (e.g., a GameCard for RandomCard type).
  GameCard? claim(String playerId) {
    if (isClaimed) return null;

    isClaimed = true;
    claimedByPlayerId = playerId;

    if (type == RelicType.randomCard) {
      generatedCard = _generateRandomCard();
      return generatedCard;
    }

    return null;
  }

  /// Generate a random card as a reward.
  /// Picks from a pool of useful cards (Rare or Epic).
  GameCard _generateRandomCard() {
    final random = Random();

    // Pool of reward cards (mix of Rare and Epic)
    final rewardPool = <GameCard Function()>[
      // Rare cards
      () => desertEliteStriker(random.nextInt(100)),
      () => lakeEliteStriker(random.nextInt(100)),
      () => woodsEliteStriker(random.nextInt(100)),
      () => desertVeteran(random.nextInt(100)),
      () => lakeVeteran(random.nextInt(100)),
      () => woodsVeteran(random.nextInt(100)),
      // Epic cards (less common but more powerful)
      () => desertBerserker(random.nextInt(100)),
      () => lakeGuardian(random.nextInt(100)),
      () => woodsSentinel(random.nextInt(100)),
      () => desertShadowScout(random.nextInt(100)),
      () => lakeMistWeaver(random.nextInt(100)),
      () => woodsShroudWalker(random.nextInt(100)),
    ];

    final cardFactory = rewardPool[random.nextInt(rewardPool.length)];
    return cardFactory();
  }

  @override
  String toString() => 'Relic($name, type: $type, claimed: $isClaimed)';
}

/// Manages relics on the game board.
/// Places one relic on a random middle tile (west, center, or east).
class RelicManager {
  /// The relic placed on a random middle tile
  Relic? middleRelic;

  /// The column where the relic is placed (0=west, 1=center, 2=east)
  /// This is hidden from players until they reach the tile.
  int? relicColumn;

  /// Initialize relics for a new match.
  /// Places a random card relic on a random middle tile.
  void initializeRelics() {
    final random = Random();
    relicColumn = random.nextInt(3); // 0, 1, or 2
    middleRelic = Relic.randomCard(id: 'middle_relic');
  }

  /// Check if there's an unclaimed relic at the given position.
  /// Returns the relic if found and unclaimed, null otherwise.
  Relic? getRelicAt(int row, int col) {
    // Relic is on middle row (row 1) at the random column
    if (row == 1 &&
        col == relicColumn &&
        middleRelic != null &&
        !middleRelic!.isClaimed) {
      return middleRelic;
    }
    return null;
  }

  /// Attempt to claim a relic at the given position.
  /// Returns the reward card if successful, null otherwise.
  GameCard? claimRelicAt(int row, int col, String playerId) {
    final relic = getRelicAt(row, col);
    if (relic == null) return null;

    return relic.claim(playerId);
  }

  /// Check if the relic has been claimed.
  bool get isRelicClaimed => middleRelic?.isClaimed ?? true;

  /// Get the player ID who claimed the relic.
  String? get relicClaimedBy => middleRelic?.claimedByPlayerId;

  /// Get the lane name where the relic is placed (for logging).
  String get relicLaneName {
    switch (relicColumn) {
      case 0:
        return 'West';
      case 1:
        return 'Center';
      case 2:
        return 'East';
      default:
        return 'Unknown';
    }
  }
}
