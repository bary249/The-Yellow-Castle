import 'card.dart';

/// Represents the owner of a tile on the 3×3 board.
enum TileOwner {
  player,
  opponent,
  neutral, // Middle row starts neutral
}

/// Represents a destroyed card's remains on the battlefield.
class Gravestone {
  final String cardName;
  final String deathLog; // Summary of how it died
  final DateTime timestamp;
  final String? ownerId; // Owner of the destroyed card
  final int turnCreated; // Turn number when this gravestone was created

  Gravestone({
    required this.cardName,
    required this.deathLog,
    DateTime? timestamp,
    this.ownerId,
    required this.turnCreated,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'cardName': cardName,
    'deathLog': deathLog,
    'timestamp': timestamp.toIso8601String(),
    'ownerId': ownerId,
    'turnCreated': turnCreated,
  };

  factory Gravestone.fromJson(Map<String, dynamic> json) {
    return Gravestone(
      cardName: json['cardName'] as String,
      deathLog: json['deathLog'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      ownerId: json['ownerId'] as String?,
      turnCreated: json['turnCreated'] as int? ?? 0,
    );
  }
}

/// Represents a single tile on the 3×3 game board.
/// TYC3: Updated for 4-card capacity (2×2 grid per tile)
///
/// The board layout (from player's perspective):
/// ```
/// Row 0: [Opp Base L] [Opp Base C] [Opp Base R]  <- Opponent's base
/// Row 1: [Middle L]   [Middle C]   [Middle R]    <- Contested middle
/// Row 2: [My Base L]  [My Base C]  [My Base R]   <- Player's base
/// ```
///
/// Columns represent lanes: 0=left, 1=center, 2=right
///
/// TYC3: Each tile can hold up to 4 cards in a 2×2 grid:
/// ```
/// [Front-Left]  [Front-Right]   <- Front row (closer to enemy)
/// [Back-Left]   [Back-Right]    <- Back row
/// ```
class Tile {
  final int row;
  final int column;

  /// Terrain type of this tile (e.g., 'Woods', 'Lake', 'Desert').
  /// Base tiles get terrain from hero affinities.
  /// Middle tiles are typically neutral (null terrain).
  String? terrain;

  /// Current owner of this tile.
  TileOwner owner;

  /// TYC3: Maximum cards per tile
  /// Set to 2 for simpler gameplay, can be increased to 4 for 2×2 grid
  static const int maxCards = 2;

  /// Cards placed on this tile (up to 4 in TYC3).
  /// Layout: [0]=front-left, [1]=front-right, [2]=back-left, [3]=back-right
  final List<GameCard> cards;

  /// Gravestones of cards destroyed on this tile.
  final List<Gravestone> gravestones;

  Tile({
    required this.row,
    required this.column,
    this.terrain,
    required this.owner,
  }) : cards = [],
       gravestones = [];

  /// Check if this tile is in the player's base row.
  bool get isPlayerBase => row == 2;

  /// Check if this tile is in the opponent's base row.
  bool get isOpponentBase => row == 0;

  /// Check if this tile is in the middle row.
  bool get isMiddle => row == 1;

  /// Get lane position (column) as enum for compatibility.
  LaneColumn get laneColumn => LaneColumn.values[column];

  /// Get the front (active) card, if any.
  /// TYC3: Returns first card in front row (index 0 or 1)
  GameCard? get frontCard => cards.isNotEmpty ? cards.first : null;

  /// Get the back (backup) card, if any.
  /// LEGACY: For backward compatibility, returns second card
  GameCard? get backCard => cards.length > 1 ? cards[1] : null;

  // ===== TYC3: 2×2 GRID ACCESS =====

  /// Get cards in the front row (indices 0-1)
  List<GameCard> get frontRowCards {
    final result = <GameCard>[];
    if (cards.isNotEmpty) result.add(cards[0]);
    if (cards.length > 1) result.add(cards[1]);
    return result;
  }

  /// Get cards in the back row (indices 2-3)
  List<GameCard> get backRowCards {
    final result = <GameCard>[];
    if (cards.length > 2) result.add(cards[2]);
    if (cards.length > 3) result.add(cards[3]);
    return result;
  }

  /// Get card at specific grid position (0-3)
  GameCard? getCardAt(int index) {
    if (index < 0 || index >= cards.length) return null;
    return cards[index];
  }

  // ===== END TYC3 =====

  /// Get all alive cards on this tile.
  List<GameCard> get aliveCards => cards.where((c) => c.isAlive).toList();

  /// Check if tile has any cards.
  bool get hasCards => cards.isNotEmpty;

  /// Check if tile has room for more cards (max 4 in TYC3).
  bool get canAddCard => cards.length < maxCards;

  /// TYC3: Get number of empty slots
  int get emptySlots => maxCards - cards.length;

  /// Add a card to this tile.
  /// Returns true if card was added successfully.
  /// TYC3: Cards fill front row first, then back row
  bool addCard(GameCard card, {bool asFront = false}) {
    if (!canAddCard) return false;

    if (asFront && cards.isNotEmpty) {
      // Insert at front
      cards.insert(0, card);
    } else {
      // Add to next available slot
      cards.add(card);
    }
    return true;
  }

  /// TYC3: Add a card at a specific grid position (0-3)
  /// Returns true if successful
  bool addCardAt(GameCard card, int index) {
    if (index < 0 || index > maxCards) return false;
    if (cards.length >= maxCards) return false;

    // If index is beyond current length, just add to end
    if (index >= cards.length) {
      cards.add(card);
    } else {
      cards.insert(index, card);
    }
    return true;
  }

  /// Add a gravestone to this tile.
  void addGravestone(Gravestone gravestone) {
    gravestones.add(gravestone);
  }

  /// Remove a specific card from this tile.
  bool removeCard(GameCard card) {
    return cards.remove(card);
  }

  /// Clean up dead cards and promote if needed.
  void cleanup() {
    cards.removeWhere((c) => !c.isAlive);
  }

  /// Clear all cards from this tile.
  void clearCards() {
    cards.clear();
  }

  /// Get a display name for this tile.
  String get displayName {
    final colName = ['West', 'Center', 'East'][column];
    final rowName = isPlayerBase
        ? 'Your Base'
        : isOpponentBase
        ? 'Enemy Base'
        : 'Middle';
    return '$colName $rowName';
  }

  /// Short display name (e.g., WEB=West Enemy Base, WPB=West Player Base, WM=West Middle)
  String get shortName {
    final col = ['W', 'C', 'E'][column];
    // Row 0 = Enemy Base, Row 1 = Middle, Row 2 = Player Base
    final rowSuffix = row == 0 ? 'EB' : (row == 1 ? 'M' : 'PB');
    return '$col$rowSuffix';
  }

  @override
  String toString() =>
      'Tile($shortName, owner: $owner, cards: ${cards.length})';

  /// Serialize to JSON for Firebase
  Map<String, dynamic> toJson() => {
    'row': row,
    'column': column,
    'terrain': terrain,
    'owner': owner.name,
    'cards': cards.map((c) => c.toJson()).toList(),
    'gravestones': gravestones.map((g) => g.toJson()).toList(),
  };

  /// Create from JSON
  factory Tile.fromJson(Map<String, dynamic> json) {
    final tile = Tile(
      row: json['row'] as int,
      column: json['column'] as int,
      terrain: json['terrain'] as String?,
      owner: TileOwner.values.firstWhere(
        (o) => o.name == json['owner'],
        orElse: () => TileOwner.neutral,
      ),
    );
    final cardsData = json['cards'] as List<dynamic>? ?? [];
    for (final cardJson in cardsData) {
      tile.cards.add(GameCard.fromJson(cardJson as Map<String, dynamic>));
    }
    final gravestonesData = json['gravestones'] as List<dynamic>? ?? [];
    for (final gsJson in gravestonesData) {
      tile.gravestones.add(Gravestone.fromJson(gsJson as Map<String, dynamic>));
    }
    return tile;
  }
}

/// Column positions (lanes).
enum LaneColumn { west, center, east }

/// Extension to convert LaneColumn to index.
extension LaneColumnExtension on LaneColumn {
  int get index {
    switch (this) {
      case LaneColumn.west:
        return 0;
      case LaneColumn.center:
        return 1;
      case LaneColumn.east:
        return 2;
    }
  }
}
