import 'card.dart';

/// Represents the owner of a tile on the 3×3 board.
enum TileOwner {
  player,
  opponent,
  neutral, // Middle row starts neutral
}

/// Represents a single tile on the 3×3 game board.
///
/// The board layout (from player's perspective):
/// ```
/// Row 0: [Opp Base L] [Opp Base C] [Opp Base R]  <- Opponent's base
/// Row 1: [Middle L]   [Middle C]   [Middle R]    <- Contested middle
/// Row 2: [My Base L]  [My Base C]  [My Base R]   <- Player's base
/// ```
///
/// Columns represent lanes: 0=left, 1=center, 2=right
class Tile {
  final int row;
  final int column;

  /// Terrain type of this tile (e.g., 'Woods', 'Lake', 'Desert').
  /// Base tiles get terrain from hero affinities.
  /// Middle tiles are typically neutral (null terrain).
  String? terrain;

  /// Current owner of this tile.
  TileOwner owner;

  /// Cards placed on this tile (up to 2).
  /// Index 0 = front card (active), Index 1 = back card (backup).
  final List<GameCard> cards;

  Tile({
    required this.row,
    required this.column,
    this.terrain,
    required this.owner,
  }) : cards = [];

  /// Check if this tile is in the player's base row.
  bool get isPlayerBase => row == 2;

  /// Check if this tile is in the opponent's base row.
  bool get isOpponentBase => row == 0;

  /// Check if this tile is in the middle row.
  bool get isMiddle => row == 1;

  /// Get lane position (column) as enum for compatibility.
  LaneColumn get laneColumn => LaneColumn.values[column];

  /// Get the front (active) card, if any.
  GameCard? get frontCard => cards.isNotEmpty ? cards.first : null;

  /// Get the back (backup) card, if any.
  GameCard? get backCard => cards.length > 1 ? cards[1] : null;

  /// Get all alive cards on this tile.
  List<GameCard> get aliveCards => cards.where((c) => c.isAlive).toList();

  /// Check if tile has any cards.
  bool get hasCards => cards.isNotEmpty;

  /// Check if tile has room for more cards (max 2).
  bool get canAddCard => cards.length < 2;

  /// Add a card to this tile.
  /// Returns true if card was added successfully.
  bool addCard(GameCard card, {bool asFront = false}) {
    if (!canAddCard) return false;

    if (asFront && cards.isNotEmpty) {
      // Insert at front
      cards.insert(0, card);
    } else {
      // Add to back
      cards.add(card);
    }
    return true;
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
    final colName = ['Left', 'Center', 'Right'][column];
    final rowName = isPlayerBase
        ? 'Your Base'
        : isOpponentBase
        ? 'Enemy Base'
        : 'Middle';
    return '$colName $rowName';
  }

  /// Short display name.
  String get shortName {
    final col = ['L', 'C', 'R'][column];
    final row = ['E', 'M', 'Y'][2 - this.row]; // E=enemy, M=middle, Y=yours
    return '$col$row';
  }

  @override
  String toString() =>
      'Tile($shortName, owner: $owner, cards: ${cards.length})';
}

/// Column positions (lanes).
enum LaneColumn { left, center, right }

/// Extension to convert LaneColumn to index.
extension LaneColumnExtension on LaneColumn {
  int get index {
    switch (this) {
      case LaneColumn.left:
        return 0;
      case LaneColumn.center:
        return 1;
      case LaneColumn.right:
        return 2;
    }
  }
}
