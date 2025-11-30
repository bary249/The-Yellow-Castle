import 'dart:math';
import 'tile.dart';
import 'card.dart';

/// Manages the 3×3 game board.
///
/// Board layout (from player's perspective):
/// ```
/// Row 0: [0,0] [0,1] [0,2]  <- Opponent's base row
/// Row 1: [1,0] [1,1] [1,2]  <- Middle row (contested)
/// Row 2: [2,0] [2,1] [2,2]  <- Player's base row
/// ```
///
/// Columns: 0=left, 1=center, 2=right
class GameBoard {
  /// The 3×3 grid of tiles. Access as tiles[row][column].
  final List<List<Tile>> tiles;

  GameBoard._({required this.tiles});

  /// All possible terrain types for random assignment
  static const allTerrains = ['woods', 'lake', 'desert', 'marsh'];

  /// Create a new game board with initial ownership and terrain.
  ///
  /// [playerTerrains] - List of 1-2 terrain types for player's base tiles.
  /// [opponentTerrains] - List of 1-2 terrain types for opponent's base tiles.
  factory GameBoard.create({
    required List<String> playerTerrains,
    required List<String> opponentTerrains,
  }) {
    final random = Random();
    final tiles = <List<Tile>>[];

    for (int row = 0; row < 3; row++) {
      final rowTiles = <Tile>[];
      for (int col = 0; col < 3; col++) {
        TileOwner owner;
        String? terrain;

        if (row == 0) {
          // Opponent's base row
          owner = TileOwner.opponent;
          terrain = opponentTerrains[random.nextInt(opponentTerrains.length)];
        } else if (row == 2) {
          // Player's base row
          owner = TileOwner.player;
          terrain = playerTerrains[random.nextInt(playerTerrains.length)];
        } else {
          // Middle row - neutral with random terrain
          owner = TileOwner.neutral;
          terrain = allTerrains[random.nextInt(allTerrains.length)];
        }

        rowTiles.add(
          Tile(row: row, column: col, terrain: terrain, owner: owner),
        );
      }
      tiles.add(rowTiles);
    }

    return GameBoard._(tiles: tiles);
  }

  /// Get a specific tile by row and column.
  Tile getTile(int row, int col) => tiles[row][col];

  /// Get a tile by lane column and row.
  Tile getTileByLane(LaneColumn lane, int row) => tiles[row][lane.index];

  /// Get all tiles in a specific column (lane).
  List<Tile> getLane(LaneColumn lane) {
    return [tiles[0][lane.index], tiles[1][lane.index], tiles[2][lane.index]];
  }

  /// Get all tiles owned by player.
  List<Tile> get playerTiles => tiles
      .expand((row) => row)
      .where((t) => t.owner == TileOwner.player)
      .toList();

  /// Get all tiles owned by opponent.
  List<Tile> get opponentTiles => tiles
      .expand((row) => row)
      .where((t) => t.owner == TileOwner.opponent)
      .toList();

  /// Get all tiles in player's base row.
  List<Tile> get playerBaseTiles => tiles[2];

  /// Get all tiles in opponent's base row.
  List<Tile> get opponentBaseTiles => tiles[0];

  /// Get all tiles in middle row.
  List<Tile> get middleTiles => tiles[1];

  /// Get the frontmost tile with player cards in a lane.
  /// Returns null if no player cards in that lane.
  Tile? getPlayerFrontTile(LaneColumn lane) {
    final laneTiles = getLane(lane);
    // Check from row 0 (enemy base) to row 2 (player base)
    for (int row = 0; row < 3; row++) {
      final tile = laneTiles[row];
      if (tile.aliveCards.any((c) => _isPlayerCard(tile, c))) {
        return tile;
      }
    }
    return null;
  }

  /// Get the frontmost tile with opponent cards in a lane.
  /// Returns null if no opponent cards in that lane.
  Tile? getOpponentFrontTile(LaneColumn lane) {
    final laneTiles = getLane(lane);
    // Check from row 2 (player base) to row 0 (enemy base)
    for (int row = 2; row >= 0; row--) {
      final tile = laneTiles[row];
      if (tile.aliveCards.any((c) => _isOpponentCard(tile, c))) {
        return tile;
      }
    }
    return null;
  }

  /// Check if a card belongs to player (placed on player-owned tile originally).
  /// For now, we track this by tile ownership at placement time.
  bool _isPlayerCard(Tile tile, GameCard card) {
    // TODO: Cards should track their owner explicitly
    // For now, assume cards on player-owned or neutral tiles moving up are player's
    return tile.owner == TileOwner.player || tile.row >= 1;
  }

  bool _isOpponentCard(Tile tile, GameCard card) {
    return tile.owner == TileOwner.opponent || tile.row <= 1;
  }

  /// Transfer ownership of a tile after combat victory.
  void captureTile(Tile tile, TileOwner newOwner) {
    tile.owner = newOwner;
  }

  /// Print a debug view of the board.
  void printBoard() {
    print('\n=== GAME BOARD ===');
    for (int row = 0; row < 3; row++) {
      final rowStr = tiles[row]
          .map((t) {
            final ownerChar = t.owner == TileOwner.player
                ? 'P'
                : t.owner == TileOwner.opponent
                ? 'O'
                : 'N';
            final terrain = t.terrain ?? '-';
            final cards = t.cards.length;
            return '[$ownerChar:$terrain:$cards]';
          })
          .join(' ');
      print('Row $row: $rowStr');
    }
    print('==================\n');
  }
}
