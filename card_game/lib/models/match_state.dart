import 'player.dart';
import 'lane.dart';
import 'game_board.dart';
import 'tile.dart';
import 'relic.dart';
import '../data/hero_library.dart';
import 'turn_snapshot.dart';

/// Serializable combat result for syncing between players in PvP
/// This allows the "resting" player to see combat results from opponent's attacks
class SyncedCombatResult {
  final String id; // Unique ID to detect new results
  final bool isBaseAttack; // true if attacking base, false if attacking card
  final bool isHeal; // true if this result is a heal action
  final String attackerName;
  final String? targetName; // null for base attacks
  final String? targetId; // optional: ID of target card (for UI targeting)
  final int damageDealt;
  final int healAmount;
  final int retaliationDamage;
  final bool targetDied;
  final bool attackerDied;
  final int? targetHpBefore;
  final int? targetHpAfter;
  final int? attackerHpBefore;
  final int? attackerHpAfter;
  final int laneCol; // 0=west, 1=center, 2=east
  final String attackerOwnerId; // To determine if "my" card or opponent's
  final String? attackerId; // ID of the attacking card (for fog of war)

  // Optional board positions for UI animations (arrow)
  final int? attackerRow;
  final int? attackerCol;
  final int? targetRow;
  final int? targetCol;

  SyncedCombatResult({
    required this.id,
    required this.isBaseAttack,
    this.isHeal = false,
    required this.attackerName,
    this.targetName,
    this.targetId,
    required this.damageDealt,
    this.healAmount = 0,
    this.retaliationDamage = 0,
    this.targetDied = false,
    this.attackerDied = false,
    this.targetHpBefore,
    this.targetHpAfter,
    this.attackerHpBefore,
    this.attackerHpAfter,
    required this.laneCol,
    required this.attackerOwnerId,
    this.attackerId,
    this.attackerRow,
    this.attackerCol,
    this.targetRow,
    this.targetCol,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'isBaseAttack': isBaseAttack,
    'isHeal': isHeal,
    'attackerName': attackerName,
    'targetName': targetName,
    'targetId': targetId,
    'damageDealt': damageDealt,
    'healAmount': healAmount,
    'retaliationDamage': retaliationDamage,
    'targetDied': targetDied,
    'attackerDied': attackerDied,
    'targetHpBefore': targetHpBefore,
    'targetHpAfter': targetHpAfter,
    'attackerHpBefore': attackerHpBefore,
    'attackerHpAfter': attackerHpAfter,
    'laneCol': laneCol,
    'attackerOwnerId': attackerOwnerId,
    'attackerId': attackerId,
    'attackerRow': attackerRow,
    'attackerCol': attackerCol,
    'targetRow': targetRow,
    'targetCol': targetCol,
  };

  factory SyncedCombatResult.fromJson(Map<String, dynamic> json) {
    return SyncedCombatResult(
      id: json['id'] as String,
      isBaseAttack: json['isBaseAttack'] as bool,
      isHeal: json['isHeal'] as bool? ?? false,
      attackerName: json['attackerName'] as String,
      targetName: json['targetName'] as String?,
      targetId: json['targetId'] as String?,
      damageDealt: json['damageDealt'] as int,
      healAmount: json['healAmount'] as int? ?? 0,
      retaliationDamage: json['retaliationDamage'] as int? ?? 0,
      targetDied: json['targetDied'] as bool? ?? false,
      attackerDied: json['attackerDied'] as bool? ?? false,
      targetHpBefore: json['targetHpBefore'] as int?,
      targetHpAfter: json['targetHpAfter'] as int?,
      attackerHpBefore: json['attackerHpBefore'] as int?,
      attackerHpAfter: json['attackerHpAfter'] as int?,
      laneCol: json['laneCol'] as int,
      attackerOwnerId: json['attackerOwnerId'] as String,
      attackerId: json['attackerId'] as String?,
      attackerRow: json['attackerRow'] as int?,
      attackerCol: json['attackerCol'] as int?,
      targetRow: json['targetRow'] as int?,
      targetCol: json['targetCol'] as int?,
    );
  }
}

/// Serializable hero ability event for syncing
class SyncedHeroAbility {
  final String id; // Unique ID to detect new events
  final String heroName;
  final String abilityName;
  final String description;
  final String playerId; // Who used it

  SyncedHeroAbility({
    required this.id,
    required this.heroName,
    required this.abilityName,
    required this.description,
    required this.playerId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'heroName': heroName,
    'abilityName': abilityName,
    'description': description,
    'playerId': playerId,
  };

  factory SyncedHeroAbility.fromJson(Map<String, dynamic> json) =>
      SyncedHeroAbility(
        id: json['id'] as String,
        heroName: json['heroName'] as String,
        abilityName: json['abilityName'] as String,
        description: json['description'] as String,
        playerId: json['playerId'] as String,
      );
}

/// Current phase of the match
/// TYC3: Updated for turn-based system
enum MatchPhase {
  setup, // Initial setup, drawing hands
  playerTurn, // TYC3: Player's turn (30 seconds)
  opponentTurn, // TYC3: Opponent's turn (30 seconds)
  gameOver, // Match ended
  // LEGACY phases (kept for backward compatibility during migration)
  @Deprecated('Use playerTurn/opponentTurn instead')
  turnPhase, // Legacy: simultaneous turn
  @Deprecated('Removed in TYC3 - combat is immediate')
  combatPhase, // Legacy: tick-based combat
  @Deprecated('Draw happens at turn start in TYC3')
  drawPhase, // Legacy: drawing cards
}

/// Represents the complete state of an ongoing match
/// TYC3: Turn-based system with AP and manual targeting
class MatchState {
  final Player player;
  final Player opponent;

  /// Match history for replay
  final List<TurnSnapshot> history = [];

  /// Legacy lane system (kept for backward compatibility during migration).
  final List<Lane> lanes;

  /// New 3×3 tile-based board.
  final GameBoard board;

  MatchPhase currentPhase;
  int turnNumber;
  String? winnerId;

  // ===== TYC3: TURN-BASED TRACKING =====

  /// ID of the player whose turn it currently is
  String? activePlayerId;

  /// When the current turn started (for 30-second timer)
  DateTime? turnStartTime;

  /// Whether this is the very first turn of the match
  /// (first player can only place 1 card on first turn)
  bool isFirstTurn = true;

  /// Number of cards placed this turn (max 2, or 1 on first turn)
  int cardsPlayedThisTurn = 0;

  /// Turn duration in seconds
  static const int turnDurationSeconds = 100;

  /// Default chess timer total duration (8 minutes)
  static const int defaultChessTimeSeconds = 480;

  /// Whether match uses chess timer mode (accumulative time)
  bool isChessTimerMode = false;

  /// Total time remaining for player (in seconds)
  int playerTotalTimeRemaining = defaultChessTimeSeconds;

  /// Total time remaining for opponent (in seconds)
  int opponentTotalTimeRemaining = defaultChessTimeSeconds;

  // ===== END TYC3 =====

  // LEGACY: Turn submission tracking (kept for backward compatibility)
  @Deprecated('TYC3 uses activePlayerId instead')
  bool playerSubmitted = false;
  @Deprecated('TYC3 uses activePlayerId instead')
  bool opponentSubmitted = false;

  /// Fog of war: tracks which lanes' enemy base terrains are revealed to player.
  /// A lane is revealed once player captures its middle tile.
  final Set<LanePosition> revealedEnemyBaseLanes = {};

  /// Fog of war: tracks enemy units that attacked this turn (visible next turn).
  /// Map of unit ID -> turn number when they attacked
  final Map<String, int> recentlyAttackedEnemyUnits = {};

  /// Relic manager for handling relics on the battlefield.
  /// Currently places one relic on the center middle tile.
  final RelicManager relicManager = RelicManager();

  /// Last combat result for syncing to opponent in PvP
  /// When an attack happens, store the result here so the other player can see it
  SyncedCombatResult? lastCombatResult;

  /// Last hero ability usage for syncing to opponent in PvP
  SyncedHeroAbility? lastHeroAbility;

  MatchState({
    required this.player,
    required this.opponent,
    required this.board,
    this.currentPhase = MatchPhase.setup,
    this.turnNumber = 0,
  }) : lanes = [
         Lane(position: LanePosition.west),
         Lane(position: LanePosition.center),
         Lane(position: LanePosition.east),
       ];

  /// Get a tile from the board.
  Tile getTile(int row, int col) => board.getTile(row, col);

  /// Get a specific lane by position
  Lane getLane(LanePosition position) {
    return lanes.firstWhere((lane) => lane.position == position);
  }

  /// Check if match is over
  bool get isGameOver => currentPhase == MatchPhase.gameOver;

  // ===== TYC3: TURN HELPERS =====

  /// Check if it's the player's turn
  bool get isPlayerTurn => activePlayerId == player.id;

  /// Check if it's the opponent's turn
  bool get isOpponentTurn => activePlayerId == opponent.id;

  /// Get the active player (whose turn it is)
  Player? get activePlayer {
    if (activePlayerId == player.id) return player;
    if (activePlayerId == opponent.id) return opponent;
    return null;
  }

  /// Get remaining seconds in current turn
  int get remainingTurnSeconds {
    if (turnStartTime == null) return turnDurationSeconds;
    final elapsed = DateTime.now().difference(turnStartTime!).inSeconds;
    return (turnDurationSeconds - elapsed).clamp(0, turnDurationSeconds);
  }

  /// Check if turn timer has expired
  bool get isTurnExpired => remainingTurnSeconds <= 0;

  /// Maximum cards that can be placed this turn
  /// Turn 1 (first turn) = 1 card only (balances first-mover advantage)
  /// All other turns = 2 cards
  int get maxCardsThisTurn => isFirstTurn ? 1 : 2;

  /// Check if more cards can be placed this turn
  bool get canPlaceMoreCards => cardsPlayedThisTurn < maxCardsThisTurn;

  /// Start a new turn for the given player
  void startTurn(String playerId) {
    activePlayerId = playerId;
    turnStartTime = DateTime.now();
    cardsPlayedThisTurn = 0;
    currentPhase = playerId == player.id
        ? MatchPhase.playerTurn
        : MatchPhase.opponentTurn;
  }

  /// End the current turn and switch to the other player
  void endCurrentTurn() {
    if (isFirstTurn) {
      isFirstTurn = false;
    }

    // Switch to other player
    final nextPlayerId = activePlayerId == player.id ? opponent.id : player.id;
    startTurn(nextPlayerId);
    turnNumber++;
  }

  // ===== END TYC3 =====

  /// LEGACY: Check if both players have submitted their moves
  @Deprecated('TYC3 uses turn-based system')
  bool get bothPlayersSubmitted => playerSubmitted && opponentSubmitted;

  /// Get the winner
  Player? get winner {
    if (winnerId == null) return null;
    return winnerId == player.id ? player : opponent;
  }

  /// LEGACY: Reset turn submissions
  @Deprecated('TYC3 uses turn-based system')
  void resetSubmissions() {
    playerSubmitted = false;
    opponentSubmitted = false;
  }

  /// End the match with a winner
  void endMatch(String winnerPlayerId) {
    winnerId = winnerPlayerId;
    currentPhase = MatchPhase.gameOver;
  }

  /// Check for match end conditions
  void checkGameOver() {
    if (player.isDefeated) {
      endMatch(opponent.id);
    } else if (opponent.isDefeated) {
      endMatch(player.id);
    }
  }

  @override
  String toString() {
    return 'Match: Turn $turnNumber, Phase: $currentPhase\n'
        'Player: ${player.name} (${player.crystalHP} HP)\n'
        'Opponent: ${opponent.name} (${opponent.crystalHP} HP)';
  }

  /// Serialize to JSON for Firebase
  /// This captures the FULL game state for online sync
  Map<String, dynamic> toJson() => {
    'player': player.toJson(),
    'opponent': opponent.toJson(),
    'board': board.toJson(),
    'currentPhase': currentPhase.name,
    'turnNumber': turnNumber,
    'winnerId': winnerId,
    'activePlayerId': activePlayerId,
    'isFirstTurn': isFirstTurn,
    'cardsPlayedThisTurn': cardsPlayedThisTurn,
    'revealedEnemyBaseLanes': revealedEnemyBaseLanes
        .map((l) => l.name)
        .toList(),
    'relicColumn': relicManager.relicColumn,
    'relicClaimed': relicManager.isRelicClaimed,
    'relicClaimedBy': relicManager.relicClaimedBy,
    'lastCombatResult': lastCombatResult?.toJson(),
    'lastHeroAbility': lastHeroAbility?.toJson(),
    'isChessTimerMode': isChessTimerMode,
    'playerTotalTimeRemaining': playerTotalTimeRemaining,
    'opponentTotalTimeRemaining': opponentTotalTimeRemaining,
  };

  /// Create from JSON (for online sync)
  /// [myPlayerId] is used to determine which player data maps to 'player' vs 'opponent'
  factory MatchState.fromJson(
    Map<String, dynamic> json, {
    required String myPlayerId,
  }) {
    final playerData = json['player'] as Map<String, dynamic>;
    final opponentData = json['opponent'] as Map<String, dynamic>;

    // Determine which is "me" and which is "opponent" based on player IDs
    final bool iAmPlayer = playerData['id'] == myPlayerId;

    final myData = iAmPlayer ? playerData : opponentData;
    final theirData = iAmPlayer ? opponentData : playerData;

    // Get heroes from library
    final myHeroId = myData['heroId'] as String?;
    final theirHeroId = theirData['heroId'] as String?;
    final myHero = myHeroId != null ? HeroLibrary.getHeroById(myHeroId) : null;
    final theirHero = theirHeroId != null
        ? HeroLibrary.getHeroById(theirHeroId)
        : null;

    final player = Player.fromJson(myData, hero: myHero);
    final opponent = Player.fromJson(theirData, hero: theirHero);

    // Parse board - if we're not the original "player", we need to mirror it
    // so our base is always at row 2 (bottom)
    var board = GameBoard.fromJson(json['board'] as Map<String, dynamic>);
    if (!iAmPlayer) {
      // Mirror the board for Player 2's perspective
      board = board.mirrored();
    }

    final match = MatchState(
      player: player,
      opponent: opponent,
      board: board,
      currentPhase: MatchPhase.values.firstWhere(
        (p) => p.name == json['currentPhase'],
        orElse: () => MatchPhase.playerTurn,
      ),
      turnNumber: json['turnNumber'] as int? ?? 0,
    );

    match.winnerId = json['winnerId'] as String?;
    match.activePlayerId = json['activePlayerId'] as String?;
    match.isFirstTurn = json['isFirstTurn'] as bool? ?? false;
    match.cardsPlayedThisTurn = json['cardsPlayedThisTurn'] as int? ?? 0;

    // Restore revealed lanes
    final revealedLanes =
        json['revealedEnemyBaseLanes'] as List<dynamic>? ?? [];
    for (final laneName in revealedLanes) {
      match.revealedEnemyBaseLanes.add(
        LanePosition.values.firstWhere((l) => l.name == laneName),
      );
    }

    // Restore relic state
    final relicColumn = json['relicColumn'] as int?;
    if (relicColumn != null) {
      match.relicManager.setRelicColumn(relicColumn);
    }
    // If relic was claimed, mark it as claimed
    final claimedBy = json['relicClaimedBy'] as String?;
    if (claimedBy != null && match.relicManager.middleRelic != null) {
      match.relicManager.middleRelic!.isClaimed = true;
      match.relicManager.middleRelic!.claimedByPlayerId = claimedBy;
    }

    // Restore last combat result (for PvP sync)
    final combatResultJson = json['lastCombatResult'] as Map<String, dynamic>?;
    if (combatResultJson != null) {
      match.lastCombatResult = SyncedCombatResult.fromJson(combatResultJson);
    }

    // Restore last hero ability (for PvP sync)
    final heroAbilityJson = json['lastHeroAbility'] as Map<String, dynamic>?;
    if (heroAbilityJson != null) {
      match.lastHeroAbility = SyncedHeroAbility.fromJson(heroAbilityJson);
    }

    // Restore chess timer state
    match.isChessTimerMode = json['isChessTimerMode'] as bool? ?? false;
    final pTime =
        json['playerTotalTimeRemaining'] as int? ?? defaultChessTimeSeconds;
    final oTime =
        json['opponentTotalTimeRemaining'] as int? ?? defaultChessTimeSeconds;

    if (iAmPlayer) {
      match.playerTotalTimeRemaining = pTime;
      match.opponentTotalTimeRemaining = oTime;
    } else {
      // Swap times if viewing from opponent's perspective
      match.playerTotalTimeRemaining = oTime;
      match.opponentTotalTimeRemaining = pTime;
    }

    return match;
  }
}
