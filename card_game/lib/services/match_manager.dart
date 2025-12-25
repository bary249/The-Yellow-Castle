import '../models/match_state.dart';
import '../models/player.dart';
import '../models/tile.dart';
import '../models/turn_snapshot.dart';
import '../models/deck.dart';
import '../models/lane.dart';
import '../models/card.dart';
import '../models/hero.dart';
import '../models/game_board.dart';
import 'combat_resolver.dart';

/// Coordinates the entire match flow
class MatchManager {
  MatchState? _currentMatch;
  final CombatResolver _combatResolver = CombatResolver();

  // ============================================================================
  // MOVEMENT & ATTACK CONFIGURATION
  // ============================================================================

  /// If true, units can move to adjacent lanes (left/right).
  /// If false, units can only move forward/backward in the same lane.
  /// Can be enabled globally or per-unit via 'flanking' ability.
  static bool allowCrossLaneMovement = true;

  /// If true, units can attack enemies in adjacent lanes.
  /// If false, units can only attack enemies in the same lane.
  /// Can be enabled globally or per-unit via 'cross_attack' ability.
  static bool allowCrossLaneAttack = true;

  MatchState? get currentMatch => _currentMatch;

  // When legacy lane-based staging APIs are used (submitPlayerMoves/submitOpponentMoves),
  // lane stacks become the source of truth for unit positions. Online sync serializes
  // the GameBoard, so we must mirror lane stacks into board tiles for correct PvP sync.
  bool _legacyLanesDirtyForBoardSync = false;

  int? maxCardsThisTurnOverride;

  /// Replace the current match state (for online sync)
  /// This completely replaces the local state with the received state
  /// IMPORTANT: Preserves local player's deck and hand since opponent doesn't know them
  void replaceMatchState(MatchState newState) {
    // Preserve local player's deck and hand - opponent doesn't know our correct deck
    if (_currentMatch != null) {
      // Keep our local deck cards (the opponent's view of our deck is wrong/empty)
      newState.player.deck.replaceCards(_currentMatch!.player.deck.cards);

      // Keep our local starting deck snapshot (used by Tester hero)
      newState.player.startingDeck = _currentMatch!.player.startingDeck
          ?.map((c) => c.clone())
          .toList();

      // Keep our local hand (opponent doesn't see our hand)
      newState.player.hand.clear();
      newState.player.hand.addAll(_currentMatch!.player.hand);

      _log(
        '🔒 Preserved local deck (${newState.player.deck.cards.length} cards) and hand (${newState.player.hand.length} cards)',
      );
    }

    // Preserve local history if available
    if (_currentMatch != null && _currentMatch!.history.isNotEmpty) {
      newState.history.addAll(_currentMatch!.history);
    }

    // Check if a turn has passed OR game over state reached (to capture final frame)
    if (_currentMatch != null &&
        (newState.turnNumber > _currentMatch!.turnNumber ||
            (newState.isGameOver && !_currentMatch!.isGameOver))) {
      // Capture snapshot of the NEW state (which is the state at the start of this new turn)
      // This effectively captures the result of the opponent's turn that just finished
      newState.history.add(TurnSnapshot.fromState(matchState: newState));
    } else if (_currentMatch == null) {
      // First sync (start of match)
      newState.history.add(TurnSnapshot.fromState(matchState: newState));
    }

    _currentMatch = newState;
    _log('🔄 Match state replaced from online sync');
  }

  /// Tracks if player has a damage boost active for this turn (from hero ability).
  bool _playerDamageBoostActive = false;

  int _playerDamageBoostExtra = 0;

  void addPlayerDamageBoostThisTurn(int amount, {String? source}) {
    if (_currentMatch == null) return;
    if (amount <= 0) return;

    if (_playerDamageBoostExtra >= amount) return;
    _playerDamageBoostExtra = amount;
    _log(
      '   Bonus damage this turn: +$amount${source != null ? " ($source)" : ""}',
    );
  }

  bool _isTrapCard(GameCard card) =>
      card.abilities.any((a) => a.startsWith('trap_'));

  bool _isSpyCard(GameCard card) => card.abilities.contains('spy');

  bool _tileHasEnemyCardsForOwner(Tile tile, String ownerId) {
    return tile.cards.any((c) => c.isAlive && c.ownerId != ownerId);
  }

  int _friendlyOccupantCount(Tile tile, String ownerId) {
    final friendlyCards = tile.cards.where(
      (c) => c.isAlive && c.ownerId == ownerId,
    );
    final friendlySpies = tile.hiddenSpies.where(
      (c) => c.isAlive && c.ownerId == ownerId,
    );
    return friendlyCards.length + friendlySpies.length;
  }

  bool _canAddFriendlyOccupant(Tile tile, String ownerId) {
    return _friendlyOccupantCount(tile, ownerId) < Tile.maxCards;
  }

  void _removeCardFromTile(Tile tile, GameCard card) {
    tile.cards.removeWhere((c) => c.id == card.id);
    tile.hiddenSpies.removeWhere((c) => c.id == card.id);
  }

  void _addCardToTile(Tile tile, GameCard card) {
    if (_isSpyCard(card)) {
      tile.hiddenSpies.add(card);
    } else {
      tile.addCard(card);
    }
  }

  bool _isIgniterCard(GameCard card) =>
      card.abilities.any((a) => a.startsWith('ignite_'));

  bool _isConverter(GameCard card) => card.abilities.contains('converter');

  bool _isPoisoner(GameCard card) => card.abilities.contains('poisoner');

  String? _getIgniteAbilityKey(GameCard card) {
    for (final a in card.abilities) {
      if (a.startsWith('ignite_')) return a;
    }
    return null;
  }

  int _getIgniteTurns(GameCard card) {
    for (final a in card.abilities) {
      if (a.startsWith('ignite_')) {
        return int.tryParse(a.split('_').last) ?? 0;
      }
    }
    return 0;
  }

  int _getTrapDamage(GameCard card) {
    for (final a in card.abilities) {
      if (a.startsWith('trap_')) {
        return int.tryParse(a.split('_').last) ?? card.damage;
      }
    }
    return card.damage;
  }

  String? _getTrapTerrainRequirement(GameCard card) => card.element;

  bool _placeTrapOnTile(Player active, GameCard card, int row, int col) {
    if (_currentMatch == null) return false;

    final tile = _currentMatch!.board.getTile(row, col);
    if (tile.trap != null) {
      _log('❌ This tile already has a trap');
      return false;
    }
    final requiredTerrain = _getTrapTerrainRequirement(card);
    if (requiredTerrain != null && requiredTerrain.isNotEmpty) {
      final tileTerrain = tile.terrain;
      if (tileTerrain == null ||
          tileTerrain.toLowerCase() != requiredTerrain.toLowerCase()) {
        _log('❌ Trap must be placed on $requiredTerrain terrain');
        return false;
      }
    }

    final damage = _getTrapDamage(card);
    tile.trap = TileTrap(
      ownerId: active.id,
      damage: damage,
      terrain: tile.terrain,
    );
    _currentMatch!.cardsPlayedThisTurn++;

    final owner = active.id == _currentMatch!.player.id ? 'Player' : 'Opponent';
    _log('✅ [$owner] Placed Trap (${damage} DMG) at ($row, $col)');
    return true;
  }

  void _triggerTrapIfPresent(GameCard enteringCard, int row, int col) {
    if (_currentMatch == null) return;
    final tile = _currentMatch!.board.getTile(row, col);
    final trap = tile.trap;
    if (trap == null) return;
    if (enteringCard.ownerId == null) return;
    if (trap.ownerId == enteringCard.ownerId) return;

    final damage = trap.damage;
    tile.trap = null;

    _log(
      '💥 Trap triggered at ($row,$col)! ${enteringCard.name} takes $damage',
    );
    final died = enteringCard.takeDamage(damage);
    if (died) {
      tile.addGravestone(
        Gravestone(
          cardName: enteringCard.name,
          deathLog: 'Destroyed by trap',
          ownerId: enteringCard.ownerId,
          turnCreated: _currentMatch!.turnNumber,
        ),
      );
      onCardDestroyed?.call(enteringCard);
      _removeCardFromTile(tile, enteringCard);
      _log('   💀 ${enteringCard.name} destroyed by trap!');
    } else {
      _log(
        '   ${enteringCard.name} now ${enteringCard.currentHealth}/${enteringCard.health} HP',
      );
    }
  }

  bool _isMarshTerrain(String? terrain) {
    final t = terrain?.toLowerCase();
    return t == 'marsh';
  }

  int _forwardDirForOwnerId(String ownerId) {
    if (_currentMatch == null) return -1;
    return ownerId == _currentMatch!.player.id ? -1 : 1;
  }

  String? _enemyOwnerId(String ownerId) {
    if (_currentMatch == null) return null;
    if (ownerId == _currentMatch!.player.id) return _currentMatch!.opponent.id;
    if (ownerId == _currentMatch!.opponent.id) return _currentMatch!.player.id;
    return null;
  }

  Iterable<GameCard> _enemyCardsBehindTileForOwner({
    required String ownerId,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return const [];

    final enemyId = _enemyOwnerId(ownerId);
    if (enemyId == null) return const [];

    final behindRow = row - _forwardDirForOwnerId(enemyId);
    if (behindRow < 0 || behindRow > 2) return const [];

    final behindTile = _currentMatch!.board.getTile(behindRow, col);
    return <GameCard>[
      ...behindTile.cards,
      ...behindTile.hiddenSpies,
    ].where((c) => c.isAlive && c.ownerId == enemyId);
  }

  String _ownerLabel(String? ownerId) {
    if (_currentMatch == null) return 'Unknown';
    if (ownerId == _currentMatch!.player.id) return 'Player';
    if (ownerId == _currentMatch!.opponent.id) return 'Opponent';
    return 'Unknown';
  }

  ({int row, int col})? _findCardPositionById(String cardId) {
    if (_currentMatch == null) return null;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final tile = _currentMatch!.board.getTile(r, c);
        if (tile.cards.any((x) => x.id == cardId) ||
            tile.hiddenSpies.any((x) => x.id == cardId)) {
          return (row: r, col: c);
        }
      }
    }
    return null;
  }

  String _formatCardRef(GameCard card) {
    final pos = _findCardPositionById(card.id);
    if (pos == null) return card.name;
    return '${card.name}(${pos.row},${pos.col})';
  }

  String _formatSources(List<GameCard> sources) {
    if (sources.isEmpty) return '';
    return sources.map(_formatCardRef).join(', ');
  }

  int _abilityChargesRemaining(
    GameCard card,
    String ability, {
    int defaultCharges = 1,
  }) {
    if (!card.abilities.contains(ability)) return 0;
    if (card.abilityCharges.containsKey(ability)) {
      return card.abilityCharges[ability] ?? 0;
    }
    if (ability == 'barrier') {
      return card.barrierUsed ? 0 : defaultCharges;
    }
    return defaultCharges;
  }

  bool _consumeAbilityCharge(
    GameCard card,
    String ability, {
    int defaultCharges = 1,
  }) {
    final current = _abilityChargesRemaining(
      card,
      ability,
      defaultCharges: defaultCharges,
    );
    if (current <= 0) {
      card.abilityCharges[ability] = 0;
      return false;
    }
    card.abilityCharges[ability] = current - 1;
    if (ability == 'barrier') {
      card.barrierUsed = (card.abilityCharges[ability] ?? 0) <= 0;
    }
    return true;
  }

  void _grantAbilityCharge(
    GameCard card,
    String ability, {
    int amount = 1,
    int defaultCharges = 1,
  }) {
    final current = _abilityChargesRemaining(
      card,
      ability,
      defaultCharges: defaultCharges,
    );
    card.abilityCharges[ability] = current + amount;
    if (ability == 'barrier') {
      card.barrierUsed = false;
    }
  }

  /// Initialize ability charges for consumable abilities when card is placed or drawn
  void initializeAbilityCharges(GameCard card) {
    const consumableAbilities = <String>{
      'fear',
      'paralyze',
      'glue',
      'silence',
      'shaco',
      'barrier',
      'poisoner',
    };

    for (final ability in consumableAbilities) {
      if (card.abilities.contains(ability)) {
        // Only initialize if not already set
        if (!card.abilityCharges.containsKey(ability)) {
          card.abilityCharges[ability] = 1;
        }
      }
    }

    for (final a in card.abilities) {
      if (!a.startsWith('ignite_')) continue;
      if (!card.abilityCharges.containsKey(a)) {
        card.abilityCharges[a] = 1;
      }
    }

    // Handle legacy barrier flag
    if (card.abilities.contains('barrier') && !card.barrierUsed) {
      card.abilityCharges['barrier'] = 1;
    }
  }

  void _applyPoisonTurnStartForPlayer(String playerId) {
    if (_currentMatch == null) return;

    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = _currentMatch!.board.getTile(row, col);
        final allCards = <GameCard>[...tile.cards, ...tile.hiddenSpies];

        for (final card in allCards) {
          if (!card.isAlive) continue;
          if (card.ownerId != playerId) continue;
          if (card.poisonTicksRemaining <= 0) continue;

          final hpBefore = card.currentHealth;
          final died = card.takeDamage(1);
          final hpAfter = card.currentHealth;
          card.poisonTicksRemaining = (card.poisonTicksRemaining - 1).clamp(
            0,
            999,
          );

          _log(
            '☠️ Poison ticks on ${card.name}: 1 dmg (${hpBefore}→$hpAfter), remaining=${card.poisonTicksRemaining}',
          );

          if (died) {
            tile.addGravestone(
              Gravestone(
                cardName: card.name,
                deathLog: 'Destroyed by poison',
                ownerId: card.ownerId,
                turnCreated: _currentMatch!.turnNumber,
              ),
            );
            onCardDestroyed?.call(card);
            _removeCardFromTile(tile, card);
            _log('   💀 ${card.name} destroyed by poison!');
          }
        }
      }
    }
  }

  void _applyIgniteTurnStartForPlayer(String playerId) {
    if (_currentMatch == null) return;

    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = _currentMatch!.board.getTile(row, col);
        if (!_isTileIgnited(tile)) continue;

        final allCards = <GameCard>[...tile.cards, ...tile.hiddenSpies];

        for (final card in allCards) {
          if (!card.isAlive) continue;
          if (card.ownerId != playerId) continue;

          final hpBefore = card.currentHealth;
          final died = card.takeDamage(1);
          final hpAfter = card.currentHealth;

          _log(
            '🔥 Ignite burn on ${card.name} at ($row,$col): 1 dmg (${hpBefore}→$hpAfter)',
          );

          if (died) {
            tile.addGravestone(
              Gravestone(
                cardName: card.name,
                deathLog: 'Burned by ignited tile',
                ownerId: card.ownerId,
                turnCreated: _currentMatch!.turnNumber,
              ),
            );
            onCardDestroyed?.call(card);
            _removeCardFromTile(tile, card);
            _log('   💀 ${card.name} burned to death!');
          }
        }
      }
    }
  }

  GameCard? _consumeChargeFromFirstSource(
    List<GameCard> sources,
    String ability,
  ) {
    if (sources.isEmpty) return null;
    sources.sort((a, b) => a.id.compareTo(b.id));
    for (final source in sources) {
      if (_consumeAbilityCharge(source, ability)) return source;
    }
    return null;
  }

  String? getMoveLockReasonTYC3(GameCard card, int row, int col) {
    return _getMoveLockReason(card, row, col);
  }

  String? getAttackLockReasonTYC3(GameCard card, int row, int col) {
    return _getAttackLockReason(card, row, col);
  }

  String? getMoveLockDebugTYC3(GameCard card, int row, int col) {
    final details = _getMoveLockDetails(card, row, col);
    if (details == null) return null;
    final sources = _formatSources(details.sources);
    return '${details.reason}${sources.isNotEmpty ? " (blocked by: $sources)" : ""}';
  }

  String? getAttackLockDebugTYC3(GameCard card, int row, int col) {
    final details = _getAttackLockDetails(card, row, col);
    if (details == null) return null;
    final sources = _formatSources(details.sources);
    return '${details.reason}${sources.isNotEmpty ? " (blocked by: $sources)" : ""}';
  }

  ({String reason, List<GameCard> sources, String ability})?
  _getMoveLockDetails(GameCard card, int row, int col) {
    if (_currentMatch == null) return null;
    if (card.ownerId == null) return null;

    final sources = _enemyCardsBehindTileForOwner(
      ownerId: card.ownerId!,
      row: row,
      col: col,
    ).toList();

    final paralyzers = sources
        .where(
          (c) =>
              c.abilities.contains('paralyze') &&
              _abilityChargesRemaining(c, 'paralyze') > 0,
        )
        .toList();
    if (paralyzers.isNotEmpty) {
      return (
        reason: 'Paralyzed - cannot move',
        sources: paralyzers,
        ability: 'paralyze',
      );
    }

    final gluers = sources
        .where(
          (c) =>
              c.abilities.contains('glue') &&
              _abilityChargesRemaining(c, 'glue') > 0,
        )
        .toList();
    if (gluers.isNotEmpty) {
      return (reason: 'Glued - cannot move', sources: gluers, ability: 'glue');
    }

    return null;
  }

  ({String reason, List<GameCard> sources, String ability})?
  _getAttackLockDetails(GameCard card, int row, int col) {
    if (_currentMatch == null) return null;
    if (card.ownerId == null) return null;

    final sources = _enemyCardsBehindTileForOwner(
      ownerId: card.ownerId!,
      row: row,
      col: col,
    ).toList();

    final paralyzers = sources
        .where(
          (c) =>
              c.abilities.contains('paralyze') &&
              _abilityChargesRemaining(c, 'paralyze') > 0,
        )
        .toList();
    if (paralyzers.isNotEmpty) {
      return (
        reason: 'Paralyzed - cannot attack',
        sources: paralyzers,
        ability: 'paralyze',
      );
    }

    final silencers = sources
        .where(
          (c) =>
              c.abilities.contains('silence') &&
              _abilityChargesRemaining(c, 'silence') > 0,
        )
        .toList();
    if (silencers.isNotEmpty) {
      return (
        reason: 'Silenced - cannot attack',
        sources: silencers,
        ability: 'silence',
      );
    }

    return null;
  }

  String? _getMoveLockReason(GameCard card, int row, int col) {
    return _getMoveLockDetails(card, row, col)?.reason;
  }

  String? _getAttackLockReason(GameCard card, int row, int col) {
    return _getAttackLockDetails(card, row, col)?.reason;
  }

  void _applyFearOnEntry({
    required GameCard enteringCard,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return;
    if (!enteringCard.isAlive) return;
    if (enteringCard.ownerId == null) return;

    final enemyId = _enemyOwnerId(enteringCard.ownerId!);
    if (enemyId == null) return;

    final behindRow = row - _forwardDirForOwnerId(enemyId);
    if (behindRow < 0 || behindRow > 2) return;

    final behindTile = _currentMatch!.board.getTile(behindRow, col);
    final fearSources =
        <GameCard>[...behindTile.cards, ...behindTile.hiddenSpies]
            .where(
              (c) =>
                  c.isAlive &&
                  c.ownerId == enemyId &&
                  c.abilities.contains('fear') &&
                  _abilityChargesRemaining(c, 'fear') > 0,
            )
            .toList();

    if (fearSources.isEmpty) return;

    fearSources.sort((a, b) => a.id.compareTo(b.id));
    final fearCard = fearSources.firstWhere(
      (c) => !c.fearSeenEnemyIds.contains(enteringCard.id),
      orElse: () => fearSources.first,
    );

    if (fearCard.fearSeenEnemyIds.contains(enteringCard.id)) return;
    if (!_consumeAbilityCharge(fearCard, 'fear')) return;

    fearCard.fearSeenEnemyIds.add(enteringCard.id);
    enteringCard.currentAP = 0;
    final owner = _ownerLabel(enteringCard.ownerId);
    _log(
      '😱 [$owner] Fear drains AP: ${enteringCard.name} is reduced to 0 AP (triggered by: ${fearCard.name})',
    );
  }

  void _applyPushBackAfterAttack({
    required GameCard attacker,
    required GameCard target,
    required int targetRow,
    required int targetCol,
  }) {
    if (_currentMatch == null) return;
    if (!attacker.isAlive) return;
    if (attacker.ownerId == null) return;
    if (!attacker.abilities.contains('push_back')) return;

    if (!target.isAlive) return;
    if (target.ownerId == null) return;
    if (target.ownerId == attacker.ownerId) return;

    final targetTile = _currentMatch!.board.getTile(targetRow, targetCol);
    // Only push the primary attacked target (not other units sharing the tile).
    final targetStillOnTile =
        targetTile.cards.any((c) => c.id == target.id) ||
        targetTile.hiddenSpies.any((c) => c.id == target.id);
    if (!targetStillOnTile) return;

    final pushRow = targetRow - _forwardDirForOwnerId(target.ownerId!);
    final pushCol = targetCol;
    if (pushRow < 0 || pushRow > 2) return;

    final destTile = _currentMatch!.board.getTile(pushRow, pushCol);

    final canPush = _isSpyCard(target)
        ? (_tileHasEnemyCardsForOwner(destTile, target.ownerId!) ||
              _canAddFriendlyOccupant(destTile, target.ownerId!))
        : (destTile.canAddCard &&
              !_tileHasEnemyCardsForOwner(destTile, target.ownerId!));

    if (!canPush) return;

    _applyTerrainAffinityOnExit(card: target, fromTerrain: targetTile.terrain);

    _removeCardFromTile(targetTile, target);
    _addCardToTile(destTile, target);
    _log(
      '↩️ Push Back: ${target.name} pushed ($targetRow,$targetCol) → ($pushRow,$pushCol)',
    );

    _triggerTrapIfPresent(target, pushRow, pushCol);
    if (!target.isAlive) return;

    _triggerSpyOnEnemyBaseEntry(
      enteringCard: target,
      fromRow: targetRow,
      fromCol: targetCol,
      toRow: pushRow,
      toCol: pushCol,
    );
    if (!target.isAlive) return;

    final finalPos = _applyBurningOnEntry(
      enteringCard: target,
      fromRow: targetRow,
      fromCol: targetCol,
      toRow: pushRow,
      toCol: pushCol,
    );
    if (!target.isAlive) return;

    _applyFearOnEntry(
      enteringCard: target,
      row: finalPos.row,
      col: finalPos.col,
    );

    _applyMarshDrainOnEntry(
      enteringCard: target,
      row: finalPos.row,
      col: finalPos.col,
    );

    _applyTerrainAffinityOnEntry(
      card: target,
      row: finalPos.row,
      col: finalPos.col,
    );

    _checkRelicPickup(finalPos.row, finalPos.col, target.ownerId!);
    _updatePermanentVisibility(finalPos.row, finalPos.col, target.ownerId!);
  }

  bool _isWatcherCard(GameCard card) => card.abilities.contains('watcher');

  bool _isTileRevealedByWatcherForOwner({
    required String viewerOwnerId,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return false;

    final forwardDir = viewerOwnerId == _currentMatch!.player.id ? -1 : 1;

    final watcherPositions = <({int r, int c})>[
      (r: row, c: col),
      (r: row, c: col - 1),
      (r: row, c: col + 1),
      // "Forward" from watcher perspective means the watcher is 1 tile behind this tile.
      (r: row - forwardDir, c: col),
    ];

    for (final pos in watcherPositions) {
      if (pos.r < 0 || pos.r > 2 || pos.c < 0 || pos.c > 2) continue;
      final tile = _currentMatch!.board.getTile(pos.r, pos.c);
      final hasWatcher = tile.cards.any(
        (c) => c.isAlive && c.ownerId == viewerOwnerId && _isWatcherCard(c),
      );
      if (hasWatcher) return true;
    }

    return false;
  }

  /// Whether a tile's hidden information (spies / concealed cards) is revealed
  /// for the given viewer due to Watcher proximity.
  bool isTileRevealedByWatcher({
    required String viewerOwnerId,
    required int row,
    required int col,
  }) {
    return _isTileRevealedByWatcherForOwner(
      viewerOwnerId: viewerOwnerId,
      row: row,
      col: col,
    );
  }

  void _applyMarshDrainOnEntry({
    required GameCard enteringCard,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return;
    if (!enteringCard.isAlive) return;

    final tile = _currentMatch!.board.getTile(row, col);
    if (!_isMarshTerrain(tile.terrain)) return;

    enteringCard.currentAP = 0;
    _log('🟩 Marsh drains AP: ${enteringCard.name} is reduced to 0 AP');
  }

  bool _hasTerrainAffinity(GameCard card) {
    return card.abilities.contains('terrain_affinity');
  }

  bool _isShacoCard(GameCard card) {
    return card.abilities.contains('shaco');
  }

  void _spawnShacoDecoys({
    required GameCard shaco,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return;
    if (!shaco.isAlive) return;
    if (shaco.ownerId == null) return;
    if (shaco.isDecoy) return;

    if (!_consumeAbilityCharge(shaco, 'shaco')) return;

    final sideCols = <int>[];
    if (col == 0) {
      sideCols.addAll([1, 2]);
    } else if (col == 1) {
      sideCols.addAll([0, 2]);
    } else {
      sideCols.addAll([0, 1]);
    }

    int decoyIndex = 0;
    for (final sideCol in sideCols) {
      final tile = _currentMatch!.board.getTile(row, sideCol);
      if (!tile.canAddCard) continue;

      final decoy = shaco.copyWith(
        id: '${shaco.id}_decoy_$decoyIndex',
        isDecoy: true,
      );
      decoy.ownerId = shaco.ownerId;
      decoy.currentAP = shaco.currentAP;
      decoy.currentHealth = shaco.currentHealth;
      decoy.abilityCharges['shaco'] = 0;

      _addCardToTile(tile, decoy);
      _log('🃏 Shaco spawns decoy at ($row,$sideCol)');

      _triggerTrapIfPresent(decoy, row, sideCol);
      if (decoy.isAlive) {
        _applyTerrainAffinityOnEntry(card: decoy, row: row, col: sideCol);
      }

      decoyIndex++;
    }
  }

  void _applySideAttackerSplash({
    required GameCard attacker,
    required int attackerCol,
    required int targetRow,
    required String primaryTargetId,
    required int damage,
    required bool isOneSide,
  }) {
    if (_currentMatch == null) return;
    if (!attacker.isAlive) return;

    final splashCols = <int>[];

    if (isOneSide) {
      // One-Side Attacker: from side lanes (0 or 2) hits center + far side
      if (attackerCol == 0) {
        splashCols.addAll([1, 2]);
      } else if (attackerCol == 2) {
        splashCols.addAll([1, 0]);
      }
      // From center lane, one-side does nothing extra
    } else {
      // Two-Side Attacker: from center hits both sides; from side hits center
      if (attackerCol == 1) {
        splashCols.addAll([0, 2]);
      } else {
        splashCols.add(1);
      }
    }

    for (final col in splashCols) {
      final tile = _currentMatch!.board.getTile(targetRow, col);
      final enemies = <GameCard>[
        ...tile.cards.where(
          (c) =>
              c.isAlive &&
              c.ownerId != attacker.ownerId &&
              c.id != primaryTargetId,
        ),
        ...tile.hiddenSpies.where(
          (c) =>
              c.isAlive &&
              c.ownerId != attacker.ownerId &&
              c.id != primaryTargetId,
        ),
      ];

      for (final enemy in enemies) {
        final hpBefore = enemy.currentHealth;
        final died = enemy.takeDamage(damage);
        final hpAfter = enemy.currentHealth;

        final label = isOneSide ? 'One-Side' : 'Two-Side';
        _log(
          '   🎯 $label splash hits ${enemy.name} at ($targetRow,$col) for $damage ($hpBefore→$hpAfter)',
        );

        if (died) {
          tile.addGravestone(
            Gravestone(
              cardName: enemy.name,
              deathLog: '$label Attacker splash',
              ownerId: enemy.ownerId,
              turnCreated: _currentMatch!.turnNumber,
            ),
          );
          onCardDestroyed?.call(enemy);
          _removeCardFromTile(tile, enemy);
          _log('   💀 ${enemy.name} destroyed by $label splash!');
        }
      }
    }
  }

  bool _tallCanSeeTile({
    required String viewerOwnerId,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return false;

    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        if ((r - row).abs() + (c - col).abs() > 1) continue;
        final tile = _currentMatch!.board.getTile(r, c);
        final hasTall = <GameCard>[...tile.cards, ...tile.hiddenSpies].any(
          (card) =>
              card.isAlive &&
              card.ownerId == viewerOwnerId &&
              card.abilities.contains('tall'),
        );
        if (hasTall) return true;
      }
    }
    return false;
  }

  ({GameCard card, int row, int col})? _selectMegaTauntInterceptor({
    required String defenderOwnerId,
    required int baseRow,
    required int baseCol,
    required GameCard attacker,
  }) {
    if (_currentMatch == null) return null;

    final candidates = <({GameCard card, int row, int col})>[];
    for (final dc in const [-1, 1]) {
      final c = baseCol + dc;
      if (c < 0 || c > 2) continue;
      final tile = _currentMatch!.board.getTile(baseRow, c);
      final units = tile.cards.where(
        (u) =>
            u.isAlive &&
            u.ownerId == defenderOwnerId &&
            u.abilities.contains('mega_taunt'),
      );
      for (final u in units) {
        candidates.add((card: u, row: baseRow, col: c));
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final hp = b.card.currentHealth.compareTo(a.card.currentHealth);
      if (hp != 0) return hp;
      return a.card.id.compareTo(b.card.id);
    });

    final topHp = candidates.first.card.currentHealth;
    final tied = candidates
        .where((e) => e.card.currentHealth == topHp)
        .toList(growable: false);
    if (tied.length == 1) return tied.first;

    int seed = 0;
    final str =
        '${_currentMatch!.turnNumber}:${attacker.id}:${baseRow},${baseCol}';
    for (final codeUnit in str.codeUnits) {
      seed = (seed * 31 + codeUnit) & 0x7fffffff;
    }
    final idx = seed % tied.length;
    return tied[idx];
  }

  void _applyTerrainAffinityOnExit({
    required GameCard card,
    required String? fromTerrain,
  }) {
    if (_currentMatch == null) return;
    if (!card.isAlive) return;
    if (!_hasTerrainAffinity(card)) return;

    final t = fromTerrain?.toLowerCase();

    if (t == 'desert') {
      card.terrainAffinityRanged = false;
    }
    if (t == 'woods' || t == 'forest') {
      card.terrainAffinityDamageBonus = 0;
    }
    if (t == 'marsh' && card.terrainAffinityMarshBonusApplied) {
      card.health -= 5;
      if (card.currentHealth > card.health) {
        card.currentHealth = card.health;
      }
      card.terrainAffinityMarshBonusApplied = false;
    }
  }

  void _applyTerrainAffinityOnEntry({
    required GameCard card,
    required int row,
    required int col,
  }) {
    if (_currentMatch == null) return;
    if (!card.isAlive) return;
    if (!_hasTerrainAffinity(card)) return;

    final tile = _currentMatch!.board.getTile(row, col);
    final t = tile.terrain?.toLowerCase();

    card.terrainAffinityRanged = t == 'desert';
    card.terrainAffinityDamageBonus = (t == 'woods' || t == 'forest') ? 3 : 0;

    if (t == 'marsh' && !card.terrainAffinityMarshBonusApplied) {
      card.health += 5;
      card.currentHealth += 5;
      card.terrainAffinityMarshBonusApplied = true;
    }

    if (t == 'lake') {
      if (card.terrainAffinityLakeTurn != _currentMatch!.turnNumber) {
        card.terrainAffinityLakeTurn = _currentMatch!.turnNumber;
        card.terrainAffinityLakeTilesThisTurn.clear();
      }

      final tileKey = '$row,$col';
      if (!card.terrainAffinityLakeTilesThisTurn.contains(tileKey)) {
        card.terrainAffinityLakeTilesThisTurn.add(tileKey);
        card.currentAP = card.currentAP + 1;
      }
    }
  }

  bool _isTileIgnited(Tile tile) {
    if (_currentMatch == null) return false;
    final until = tile.ignitedUntilTurn;
    if (until == null) return false;
    return until >= _currentMatch!.turnNumber;
  }

  ({int row, int col}) _applyBurningOnEntry({
    required GameCard enteringCard,
    required int fromRow,
    required int fromCol,
    required int toRow,
    required int toCol,
  }) {
    if (_currentMatch == null) return (row: toRow, col: toCol);
    if (!enteringCard.isAlive) return (row: toRow, col: toCol);

    final toTile = _currentMatch!.board.getTile(toRow, toCol);
    if (!_isTileIgnited(toTile)) {
      return (row: toRow, col: toCol);
    }

    const damage = 1;
    _log(
      '🔥 Burning terrain at ($toRow,$toCol)! ${enteringCard.name} takes $damage',
    );
    final died = enteringCard.takeDamage(damage);
    if (died) {
      toTile.addGravestone(
        Gravestone(
          cardName: enteringCard.name,
          deathLog: 'Burned on terrain',
          ownerId: enteringCard.ownerId,
          turnCreated: _currentMatch!.turnNumber,
        ),
      );
      onCardDestroyed?.call(enteringCard);
      _removeCardFromTile(toTile, enteringCard);
      _log('   💀 ${enteringCard.name} burned to death!');
      return (row: toRow, col: toCol);
    }

    // Knockback: try to push back to the tile it came from
    if (fromRow < 0 || fromRow >= 3 || fromCol < 0 || fromCol >= 3) {
      return (row: toRow, col: toCol);
    }
    final fromTile = _currentMatch!.board.getTile(fromRow, fromCol);
    if (enteringCard.ownerId == null) {
      return (row: toRow, col: toCol);
    }

    final canKnockBack = _isSpyCard(enteringCard)
        ? (_tileHasEnemyCardsForOwner(fromTile, enteringCard.ownerId!) ||
              _canAddFriendlyOccupant(fromTile, enteringCard.ownerId!))
        : fromTile.canAddCard;
    if (!canKnockBack) {
      return (row: toRow, col: toCol);
    }

    _removeCardFromTile(toTile, enteringCard);
    _addCardToTile(fromTile, enteringCard);
    _log(
      '   ↩️ ${enteringCard.name} is knocked back to ($fromRow,$fromCol) from burning terrain',
    );

    _triggerTrapIfPresent(enteringCard, fromRow, fromCol);
    if (enteringCard.isAlive) {
      _applyFearOnEntry(enteringCard: enteringCard, row: fromRow, col: fromCol);
    }
    return (row: fromRow, col: fromCol);
  }

  ({int row, int col}) _triggerSpyOnEnemyBaseEntry({
    required GameCard enteringCard,
    required int fromRow,
    required int fromCol,
    required int toRow,
    required int toCol,
  }) {
    if (_currentMatch == null) return (row: toRow, col: toCol);
    if (!enteringCard.isAlive) return (row: toRow, col: toCol);
    if (!_isSpyCard(enteringCard)) return (row: toRow, col: toCol);
    if (enteringCard.ownerId == null) return (row: toRow, col: toCol);

    final isPlayerCard = enteringCard.ownerId == _currentMatch!.player.id;
    final isEnemyBase =
        (isPlayerCard && toRow == 0) || (!isPlayerCard && toRow == 2);
    if (!isEnemyBase) return (row: toRow, col: toCol);

    final tile = _currentMatch!.board.getTile(toRow, toCol);
    final enemyCards = tile.cards.where(
      (c) => c.isAlive && c.ownerId != enteringCard.ownerId,
    );

    final target = enemyCards.isNotEmpty ? enemyCards.first : null;
    final owner = isPlayerCard ? 'Player' : 'Opponent';
    int baseDamageDealt = 0;

    if (target != null) {
      _log(
        '🕵️ [$owner] ${enteringCard.name} infiltrates enemy base and assassinates ${target.name}!',
      );
      tile.addGravestone(
        Gravestone(
          cardName: target.name,
          deathLog: 'Assassinated by Spy',
          ownerId: target.ownerId,
          turnCreated: _currentMatch!.turnNumber,
        ),
      );
      onCardDestroyed?.call(target);
      tile.cards.remove(target);
    } else {
      final targetPlayer = isPlayerCard
          ? _currentMatch!.opponent
          : _currentMatch!.player;
      targetPlayer.takeBaseDamage(1);
      baseDamageDealt = 1;
      _log(
        '🕵️ [$owner] ${enteringCard.name} infiltrates enemy base and hits the base for 1 damage!',
      );
      _log('   Base HP: ${targetPlayer.baseHP}/${Player.maxBaseHP}');

      if (targetPlayer.isDefeated) {
        _currentMatch!.currentPhase = MatchPhase.gameOver;
        _currentMatch!.winnerId = isPlayerCard
            ? _currentMatch!.player.id
            : _currentMatch!.opponent.id;
        _log('🏆 GAME OVER! ${isPlayerCard ? "Player" : "Opponent"} wins!');

        _currentMatch!.history.add(
          TurnSnapshot.fromState(matchState: _currentMatch!),
        );
      }
    }

    // Trigger assassination callback for UI dialog
    onSpyAssassination?.call(enteringCard, target, baseDamageDealt);

    // Spy is always destroyed after activation
    tile.addGravestone(
      Gravestone(
        cardName: enteringCard.name,
        deathLog: 'Spy self-destruct',
        ownerId: enteringCard.ownerId,
        turnCreated: _currentMatch!.turnNumber,
      ),
    );
    onCardDestroyed?.call(enteringCard);
    _removeCardFromTile(tile, enteringCard);
    enteringCard.currentHealth = 0;

    // Returns previous tile position (Spy no longer occupies enemy base)
    return (row: fromRow, col: fromCol);
  }

  /// TYC3: Get tiles that can be converted (adjacent tiles within range 1)
  List<({int row, int col})> getConvertTargets(
    GameCard card,
    int fromRow,
    int fromCol,
  ) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];
    if (!_isConverter(card)) return [];
    if (card.currentAP < card.attackAPCost) return [];

    final targets = <({int row, int col})>[];

    // Can convert tiles within distance 1 (orthogonal only)
    final positions = [
      (row: fromRow, col: fromCol), // Same tile
      (row: fromRow - 1, col: fromCol), // Up
      (row: fromRow + 1, col: fromCol), // Down
      (row: fromRow, col: fromCol - 1), // Left
      (row: fromRow, col: fromCol + 1), // Right
    ];

    for (final pos in positions) {
      if (pos.row >= 0 && pos.row <= 2 && pos.col >= 0 && pos.col <= 2) {
        targets.add((row: pos.row, col: pos.col));
      }
    }

    return targets;
  }

  /// TYC3: Convert a tile's terrain to a different type
  SyncedCombatResult? convertTileTYC3(
    GameCard converter,
    int converterRow,
    int converterCol,
    int targetRow,
    int targetCol,
    String newTerrain,
  ) {
    if (_currentMatch == null) return null;
    if (!useTurnBasedSystem) return null;
    if (!_isConverter(converter)) return null;
    if (!converter.isAlive) return null;
    if (converter.currentAP < converter.attackAPCost) return null;

    final tile = _currentMatch!.board.getTile(targetRow, targetCol);
    final oldTerrain = tile.terrain ?? 'Neutral';

    // Change the terrain
    tile.terrain = newTerrain;

    // Consume AP
    converter.currentAP -= converter.attackAPCost;

    _log(
      '🔄 ${converter.name} converts tile ($targetRow, $targetCol) from $oldTerrain to $newTerrain',
    );

    final result = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${converter.id}_convert',
      isBaseAttack: false,
      isHeal: false,
      attackerName: converter.name,
      targetName: 'Tile ($targetRow, $targetCol)',
      targetId: 'tile_${targetRow}_$targetCol',
      damageDealt: 0,
      healAmount: 0,
      retaliationDamage: 0,
      targetDied: false,
      attackerDied: false,
      targetHpBefore: 0,
      targetHpAfter: 0,
      attackerHpBefore: converter.currentHealth,
      attackerHpAfter: converter.currentHealth,
      laneCol: targetCol,
      attackerOwnerId: converter.ownerId ?? '',
      attackerId: converter.id,
      attackerRow: converterRow,
      attackerCol: converterCol,
      targetRow: targetRow,
      targetCol: targetCol,
    );

    _currentMatch!.lastCombatResult = result;
    return result;
  }

  List<({int row, int col})> getIgniteTargets(
    GameCard card,
    int fromRow,
    int fromCol,
  ) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];
    if (!_isIgniterCard(card)) return [];

    final igniteKey = _getIgniteAbilityKey(card);
    if (igniteKey == null) return [];
    if (_abilityChargesRemaining(card, igniteKey, defaultCharges: 1) <= 0) {
      return [];
    }

    final turns = _getIgniteTurns(card);
    if (turns <= 0) return [];

    if (card.ownerId != _currentMatch!.activePlayerId) return [];
    if (card.currentAP < card.attackAPCost) return [];

    final targets = <({int row, int col})>[];
    final dirs = <({int dr, int dc})>[
      (dr: -1, dc: 0),
      (dr: 1, dc: 0),
      (dr: 0, dc: -1),
      (dr: 0, dc: 1),
    ];

    for (final d in dirs) {
      final r = fromRow + d.dr;
      final c = fromCol + d.dc;
      if (r < 0 || r > 2 || c < 0 || c > 2) continue;
      targets.add((row: r, col: c));
    }

    return targets;
  }

  /// TYC3: Get all reset targets reachable (friendly units on same tile).
  List<({GameCard target, int row, int col, int moveCost})>
  getReachableResetTargets(GameCard card, int fromRow, int fromCol) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];
    if (!_isResetter(card)) return [];

    if (card.currentAP < card.attackAPCost) return [];

    final targets = <({GameCard target, int row, int col, int moveCost})>[];
    final tile = _currentMatch!.board.getTile(fromRow, fromCol);

    for (final friendly in tile.cards) {
      if (!friendly.isAlive) continue;
      if (friendly.ownerId != card.ownerId) continue;
      if (friendly.id == card.id) continue;

      targets.add((target: friendly, row: fromRow, col: fromCol, moveCost: 0));
    }

    return targets;
  }

  bool igniteTileTYC3(
    GameCard igniter,
    int igniterRow,
    int igniterCol,
    int targetRow,
    int targetCol,
  ) {
    if (_currentMatch == null) return false;
    if (!useTurnBasedSystem) return false;

    if (!_isIgniterCard(igniter)) return false;
    if (igniter.ownerId != _currentMatch!.activePlayerId) return false;
    if (!igniter.isAlive) return false;

    final turns = _getIgniteTurns(igniter);
    if (turns <= 0) return false;

    final rowDist = (targetRow - igniterRow).abs();
    final colDist = (targetCol - igniterCol).abs();
    if (rowDist + colDist != 1) return false;

    final igniteKey = _getIgniteAbilityKey(igniter);
    if (igniteKey == null) return false;
    if (!_consumeAbilityCharge(igniter, igniteKey, defaultCharges: 1)) {
      return false;
    }

    if (!igniter.spendAttackAP()) {
      _grantAbilityCharge(igniter, igniteKey, amount: 1, defaultCharges: 1);
      return false;
    }

    final tile = _currentMatch!.board.getTile(targetRow, targetCol);
    final currentTurn = _currentMatch!.turnNumber;
    final newUntil = currentTurn + (turns - 1);
    final prevUntil = tile.ignitedUntilTurn;
    tile.ignitedUntilTurn = prevUntil == null
        ? newUntil
        : (prevUntil > newUntil ? prevUntil : newUntil);

    final owner = igniter.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '🔥 [$owner] ${igniter.name} ignites tile ($targetRow,$targetCol) until turn ${tile.ignitedUntilTurn} (AP ${igniter.currentAP}/${igniter.maxAP})',
    );
    return true;
  }

  /// Start a new match
  /// For online mode, pass [predefinedTerrains] and [predefinedRelicColumn] to use
  /// the board setup from the host (Player 1).
  void startMatch({
    required String playerId,
    required String playerName,
    required Deck playerDeck,
    required String opponentId,
    required String opponentName,
    required Deck opponentDeck,
    bool opponentIsAI = true,
    String? playerAttunedElement,
    String? opponentAttunedElement,
    GameHero? playerHero,
    GameHero? opponentHero,
    List<List<String>>?
    predefinedTerrains, // For online: terrain grid from host
    int? predefinedRelicColumn, // For online: relic column from host
    bool skipOpponentShuffle =
        false, // For online: opponent deck already in synced order
    String? relicName, // Custom relic name (e.g. for campaign)
    String? relicDescription, // Custom relic description
    bool isChessTimerMode = false, // Whether to use chess timer
    int? playerBaseHP, // Optional starting HP for player
    int? opponentBaseHP, // Optional starting HP for opponent
    List<String>?
    opponentPriorityCardIds, // Card IDs to prioritize in opponent's starting hand (e.g., boss cards)
  }) {
    // Debug: Log the deck being used
    _log(
      '🎴 Creating player with deck: ${playerDeck.name} (${playerDeck.cards.length} cards)',
    );
    _log(
      '🎴 First 5 cards: ${playerDeck.cards.take(5).map((c) => c.name).join(", ")}',
    );

    // Create players with heroes (copy heroes to reset ability state)
    final player = Player(
      id: playerId,
      name: playerName,
      deck: playerDeck,
      isHuman: true,
      attunedElement: playerAttunedElement,
      hero: playerHero?.copy(),
      baseHP: playerBaseHP,
    );

    final opponent = Player(
      id: opponentId,
      name: opponentName,
      deck: opponentDeck,
      isHuman: !opponentIsAI,
      attunedElement: opponentAttunedElement,
      hero: opponentHero?.copy(),
      baseHP: opponentBaseHP,
    );

    // Shuffle decks (skip opponent shuffle if deck is pre-ordered from online sync)
    player.deck.shuffle();
    _log(
      '🔀 After shuffle, first 6 cards (will be hand): ${player.deck.cards.take(6).map((c) => c.name).join(", ")}',
    );
    if (!skipOpponentShuffle) {
      opponent.deck.shuffle();

      // Move priority cards (e.g., boss cards) to front of deck for starting hand
      if (opponentPriorityCardIds != null &&
          opponentPriorityCardIds.isNotEmpty) {
        final priorityCards = <GameCard>[];
        final otherCards = <GameCard>[];
        for (final card in opponent.deck.cards) {
          if (opponentPriorityCardIds.any((id) => card.id.startsWith(id))) {
            priorityCards.add(card);
          } else {
            otherCards.add(card);
          }
        }
        if (priorityCards.isNotEmpty) {
          opponent.deck.replaceCards([...priorityCards, ...otherCards]);
          _log(
            '👑 Prioritized ${priorityCards.length} boss card(s) in opponent starting hand: ${priorityCards.map((c) => c.name).join(", ")}',
          );
        }
      }
    } else {
      _log('⏭️ Skipping opponent deck shuffle (using synced order)');
    }

    // Create the 3×3 game board
    final GameBoard board;
    if (predefinedTerrains != null) {
      // Online mode: use predefined terrains from host (Player 1)
      board = GameBoard.fromTerrains(predefinedTerrains);
      _log('📋 Using predefined board from host');
    } else {
      // Local mode: generate random terrains
      final playerTerrains = playerHero?.terrainAffinities ?? ['Woods'];
      final opponentTerrains = opponentHero?.terrainAffinities ?? ['Desert'];
      board = GameBoard.create(
        playerTerrains: playerTerrains,
        opponentTerrains: opponentTerrains,
      );
    }

    // Create match state
    _currentMatch = MatchState(
      player: player,
      opponent: opponent,
      board: board,
    );
    _currentMatch!.isChessTimerMode = isChessTimerMode;

    // Initialize relics on the battlefield
    if (predefinedRelicColumn != null) {
      // Online mode: use predefined relic column from host
      _currentMatch!.relicManager.setRelicColumn(predefinedRelicColumn);
      _log('🏺 Relic placed at column $predefinedRelicColumn (from host)');
    } else {
      // Local mode: random relic placement
      _currentMatch!.relicManager.initializeRelics(
        name: relicName,
        description: relicDescription,
      );
      _log('🏺 Relic hidden on a middle tile (location unknown)');
    }

    // Capture starting deck snapshots for refill abilities (e.g., Tester hero)
    // Do this AFTER shuffle/re-order so it matches the current deck's identity.
    player.startingDeck = player.deck.cards.map((c) => c.copy()).toList();
    opponent.startingDeck = opponent.deck.cards.map((c) => c.copy()).toList();

    // Draw initial hands
    player.drawInitialHand();
    opponent.drawInitialHand();

    // Initialize ability charges for all cards in hand
    for (final card in player.hand) {
      initializeAbilityCharges(card);
    }
    for (final card in opponent.hand) {
      initializeAbilityCharges(card);
    }

    // Reset temporary buffs
    _playerDamageBoostActive = false;
    _playerDamageBoostExtra = 0;

    // Start first turn
    _currentMatch!.currentPhase = MatchPhase.turnPhase;
    _currentMatch!.turnNumber = 1;

    _log('Match started!');
    if (playerHero != null) {
      _log(
        'Player hero: ${playerHero.name} (${playerHero.abilityDescription})',
      );
    }
    if (opponentHero != null) {
      _log('Opponent hero: ${opponentHero.name}');
    }
  }

  /// Permanently reveal enemy base lanes once seen.
  /// Called on placement, movement, and post-attack moves.
  void _updatePermanentVisibility(int row, int col, String playerId) {
    if (_currentMatch == null) return;

    // Only local player revelation matters for their fog
    if (playerId != _currentMatch!.player.id) return;

    final lanesToReveal = <int>{};

    // Owning the middle tile reveals that lane's base permanently
    if (row == 1) {
      lanesToReveal.add(col);
    }

    // Scouts in middle row also reveal adjacent lanes permanently
    final hasScout = _currentMatch!.board
        .getTile(row, col)
        .cards
        .any(
          (c) =>
              c.isAlive &&
              c.abilities.contains('scout') &&
              c.ownerId == playerId,
        );
    if (hasScout && row == 1) {
      lanesToReveal.add(col);
      if (col > 0) lanesToReveal.add(col - 1);
      if (col < 2) lanesToReveal.add(col + 1);
    }

    for (final laneCol in lanesToReveal) {
      final lanePos = LanePosition.values[laneCol];
      _currentMatch!.revealedEnemyBaseLanes.add(lanePos);
    }
  }

  /// Check if player can use their hero ability.
  bool get canUsePlayerHeroAbility {
    final hero = _currentMatch?.player.hero;
    if (hero == null) return false;
    if (hero.abilityUsed) return false;
    // TYC3: Can use during player's turn
    if (!isPlayerTurn) return false;
    return true;
  }

  /// Activate the player's hero ability.
  /// Returns true if ability was activated successfully.
  bool activatePlayerHeroAbility() {
    if (!canUsePlayerHeroAbility) return false;

    final hero = _currentMatch!.player.hero!;
    hero.useAbility();

    _log('\n🦸 HERO ABILITY ACTIVATED: ${hero.name}');
    _log('   ${hero.abilityDescription}');

    // Set last hero ability for sync
    _currentMatch!.lastHeroAbility = SyncedHeroAbility(
      id: '${DateTime.now().millisecondsSinceEpoch}_${hero.id}',
      heroName: hero.name,
      abilityName: hero.abilityType.name,
      description: hero.abilityDescription,
      playerId: _currentMatch!.player.id,
    );

    switch (hero.abilityType) {
      case HeroAbilityType.drawCards:
        // Draw 2 extra cards
        _currentMatch!.player.drawCards(count: 2);
        _log(
          '   Drew 2 extra cards. Hand size: ${_currentMatch!.player.hand.length}',
        );
        break;

      case HeroAbilityType.damageBoost:
        // Flag for +1 damage boost this turn (applied during combat)
        _playerDamageBoostActive = true;
        _log('   All units will deal +1 damage this turn.');
        break;

      case HeroAbilityType.healUnits:
        // Heal all surviving units by 3 HP
        int healed = 0;
        // TYC3: Iterate over all tiles to find player cards
        for (int row = 0; row < 3; row++) {
          for (int col = 0; col < 3; col++) {
            final tile = _currentMatch!.board.getTile(row, col);
            for (final card in tile.cards) {
              // Only heal player's cards
              if (card.ownerId == _currentMatch!.player.id && card.isAlive) {
                final before = card.currentHealth;
                card.currentHealth = (card.currentHealth + 3).clamp(
                  0,
                  card.health,
                );
                if (card.currentHealth > before) healed++;
              }
            }
          }
        }
        _log('   Healed $healed surviving units by up to 3 HP.');
        break;

      case HeroAbilityType.directBaseDamage:
        // Deal 2 damage to enemy base
        _currentMatch!.opponent.crystalHP -= 2;
        if (_currentMatch!.opponent.crystalHP < 0) {
          _currentMatch!.opponent.crystalHP = 0;
        }
        _log(
          '   Dealt 2 direct damage to enemy base! Opponent HP: ${_currentMatch!.opponent.crystalHP}',
        );

        // Check for immediate win
        if (_currentMatch!.opponent.crystalHP <= 0) {
          _currentMatch!.currentPhase = MatchPhase.gameOver;
          _currentMatch!.winnerId = _currentMatch!.player.id;
          _log('🏆 GAME OVER! Player wins via Hero Ability!');

          // Capture final snapshot for replay
          _currentMatch!.history.add(
            TurnSnapshot.fromState(matchState: _currentMatch!),
          );
        }
        break;

      case HeroAbilityType.refillHand:
        // Refill hand with starting deck cards (for Tester hero)
        final startingDeck = _currentMatch!.player.startingDeck;
        if (startingDeck != null && startingDeck.isNotEmpty) {
          _currentMatch!.player.hand.clear();
          final now = DateTime.now().millisecondsSinceEpoch;
          final takeCount = startingDeck.length < Player.maxHandSize
              ? startingDeck.length
              : Player.maxHandSize;
          for (int i = 0; i < takeCount; i++) {
            final base = startingDeck[i];
            final refilled = base.copyWith(id: '${base.id}_refill_${now}_$i');
            _currentMatch!.player.hand.add(refilled);
          }
          _log(
            '   Refilled hand with ${_currentMatch!.player.hand.length} starting deck cards.',
          );
        } else {
          _log('   No starting deck to refill from.');
        }
        break;
    }

    return true;
  }

  /// Get the damage boost amount for player cards this turn.
  int get playerDamageBoost =>
      (_playerDamageBoostActive ? 1 : 0) + _playerDamageBoostExtra;

  /// Player submits their card placements for the turn (tile-based)
  /// placements is a Map<String, List<GameCard>> where key is "row,col"
  Future<void> submitPlayerTileMoves(
    Map<String, List<GameCard>> tilePlacements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.playerSubmitted) return;

    // Place cards at their tile positions
    for (final entry in tilePlacements.entries) {
      final parts = entry.key.split(',');
      final row = int.parse(parts[0]);
      final col = int.parse(parts[1]);
      final cards = entry.value;

      final lane = _currentMatch!.lanes[col];

      for (final card in cards) {
        if (_currentMatch!.player.playCard(card)) {
          if (row == 2) {
            // Player's base tile - add to baseCards
            lane.playerCards.baseCards.addCard(card, asTopCard: false);
          } else if (row == 1) {
            // Middle tile - add to middleCards
            lane.playerCards.middleCards.addCard(card, asTopCard: false);
          }
        }
      }
    }

    _legacyLanesDirtyForBoardSync = true;
    _syncBoardCardsFromLanesIfNeeded();

    _currentMatch!.playerSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Legacy: Player submits their card placements for the turn (lane-based)
  Future<void> submitPlayerMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.playerSubmitted) return;

    // Place cards in lanes (at base position)
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        if (_currentMatch!.player.playCard(card)) {
          // Place at base position
          lane.playerCards.baseCards.addCard(card, asTopCard: false);
        }
      }
    }

    _legacyLanesDirtyForBoardSync = true;
    _syncBoardCardsFromLanesIfNeeded();

    _currentMatch!.playerSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Opponent (AI) submits their moves (always at their base - row 0)
  Future<void> submitOpponentMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards in lanes at opponent's base position
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        if (_currentMatch!.opponent.playCard(card)) {
          // AI stages at their base
          lane.opponentCards.baseCards.addCard(card, asTopCard: false);
        }
      }
    }

    _legacyLanesDirtyForBoardSync = true;
    _syncBoardCardsFromLanesIfNeeded();

    _currentMatch!.opponentSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Submit opponent moves for online multiplayer (cards not in local hand)
  /// Places cards directly in lanes without checking hand
  Future<void> submitOnlineOpponentMoves(
    Map<LanePosition, List<GameCard>> placements,
  ) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards directly in lanes at opponent's base
    for (final entry in placements.entries) {
      final lane = _currentMatch!.getLane(entry.key);
      final cards = entry.value;

      for (final card in cards) {
        // Add directly to opponent base - these are reconstructed from Firebase
        lane.opponentCards.baseCards.addCard(card, asTopCard: false);
      }
    }

    _legacyLanesDirtyForBoardSync = true;
    _syncBoardCardsFromLanesIfNeeded();

    _currentMatch!.opponentSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Opponent (AI or online) submits tile-based moves (supports middle tiles if captured)
  /// placements is a Map<String, List<GameCard>> where key is "row,col"
  /// skipHandCheck: set to true for online mode where cards come from Firebase (not in hand)
  Future<void> submitOpponentTileMoves(
    Map<String, List<GameCard>> tilePlacements, {
    bool skipHandCheck = false,
  }) async {
    if (_currentMatch == null) return;
    if (_currentMatch!.opponentSubmitted) return;

    // Place cards at their tile positions
    for (final entry in tilePlacements.entries) {
      final parts = entry.key.split(',');
      final row = int.parse(parts[0]);
      final col = int.parse(parts[1]);
      final cards = entry.value;

      final lane = _currentMatch!.lanes[col];

      for (final card in cards) {
        // For online mode, skip the hand check since cards come from Firebase
        final canPlay = skipHandCheck || _currentMatch!.opponent.playCard(card);
        if (canPlay) {
          if (row == 0) {
            // Opponent's base tile - add to baseCards
            lane.opponentCards.baseCards.addCard(card, asTopCard: false);
          } else if (row == 1) {
            // Middle tile - add to middleCards
            lane.opponentCards.middleCards.addCard(card, asTopCard: false);
          }
        }
      }
    }

    _currentMatch!.opponentSubmitted = true;

    // Check if both players submitted
    if (_currentMatch!.bothPlayersSubmitted) {
      await _resolveCombat();
    }
  }

  /// Callback for combat animation updates
  Function()? onCombatUpdate;
  Function(GameCard card)? onCardDestroyed;

  /// Callback for spy assassination (spy, target or null if base hit, baseDamage)
  Function(GameCard spy, GameCard? target, int baseDamage)? onSpyAssassination;

  /// Current tick information for UI display
  String? currentTickInfo;
  LanePosition? currentCombatLane;
  int? currentCombatTick;

  /// Per-lane tick tracking for UI tick clocks
  /// Maps lane position to current tick (1-5, or 0 if not in combat, 6 if complete)
  Map<LanePosition, int> laneTickProgress = {
    LanePosition.west: 0,
    LanePosition.center: 0,
    LanePosition.east: 0,
  };

  /// Detailed combat info for current tick (for enhanced UI display)
  List<String> currentTickDetails = [];

  /// Optional log sink used by simulations to capture full battle logs.
  /// When set, all combat-related print output is also written here.
  StringBuffer? logSink;

  /// Manual tick progression control
  bool waitingForNextTick = false;
  bool skipAllTicks = false;
  bool autoProgress = true; // Auto-progress with delays (enabled by default)
  bool fastMode = false; // When true, skip delays (for simulations)
  Function()? onWaitingForTick;

  /// Auto-progress tick delays in milliseconds
  int tickDelayWithCombat = 3500; // Longer delay when cards fight (3.5s)
  int tickDelayNoCombat = 1200; // Shorter when no action (1.2s)

  /// Advance to next tick (called by user action)
  void advanceToNextTick() {
    waitingForNextTick = false;
    onWaitingForTick?.call();
  }

  /// Skip all remaining ticks (ENTER key)
  void skipToEnd() {
    skipAllTicks = true;
    waitingForNextTick = false;
    onWaitingForTick?.call();
  }

  /// Resolve combat in all lanes with animations
  Future<void> _resolveCombat() async {
    if (_currentMatch == null) return;

    _currentMatch!.currentPhase = MatchPhase.combatPhase;

    // Reset skip flag for new combat
    skipAllTicks = false;

    // Reset lane tick progress
    laneTickProgress = {
      LanePosition.west: 0,
      LanePosition.center: 0,
      LanePosition.east: 0,
    };
    currentTickDetails = [];

    // Clear previous combat log
    _combatResolver.clearLog();

    // Print turn header to terminal
    _log('\n${'=' * 80}');
    _log('TURN ${_currentMatch!.turnNumber} - COMBAT RESOLUTION');
    _log('=' * 80);

    // Log board state BEFORE advancement (shows staging result)
    _log('\n--- BOARD STATE (AFTER STAGING) ---');
    _logBoardState();

    // Move cards forward based on their moveSpeed (step-based, shared plan)
    _log('\n--- CARD MOVEMENT ---');
    for (final lane in _currentMatch!.lanes) {
      final laneName = lane.position.name.toUpperCase();

      final movement = lane.moveCardsStepBased();

      for (final entry in movement.playerMoves.entries) {
        _log(
          '$laneName: Player ${entry.key.name} moved to ${entry.value.name}',
        );
      }

      for (final entry in movement.opponentMoves.entries) {
        _log(
          '$laneName: Opponent ${entry.key.name} moved to ${entry.value.name}',
        );
      }
    }
    _log('--- END CARD MOVEMENT ---');

    // Update combat zones for each lane (find where cards meet)
    for (final lane in _currentMatch!.lanes) {
      lane.updateCombatZone();
    }

    // Log board state AFTER movement (shows combat positions)
    _log('\n--- BOARD STATE (BEFORE COMBAT) ---');
    _logBoardState();

    // Resolve each lane with tick-by-tick animation
    for (final lane in _currentMatch!.lanes) {
      if (lane.hasCombat) {
        await _resolveLaneAnimated(lane);
      }
    }

    // Process far_attack cards (siege cannons that attack other lanes)
    await _processFarAttackCards();

    // If legacy lane APIs were used, ensure the serialized board reflects any
    // movement/combat damage done to lane stacks.
    _syncBoardCardsFromLanesIfNeeded();

    // Check if any cards damaged crystals (winning a lane means attacking crystal)
    _checkCrystalDamage();

    // Print combat log to terminal
    _log('\n--- BATTLE LOG ---');
    for (final entry in _combatResolver.logEntries) {
      _log(entry.formattedMessage);
    }
    _log('--- END BATTLE LOG ---\n');

    // Wait before showing final results (skip in fast/sim mode)
    if (!fastMode) {
      await Future.delayed(const Duration(milliseconds: 800));
    }
    onCombatUpdate?.call();

    // Print crystal damage
    _log('Player Crystal: ${_currentMatch!.player.crystalHP} HP');
    _log('Opponent Crystal: ${_currentMatch!.opponent.crystalHP} HP');
    _log('=' * 80);

    // Check for game over
    _currentMatch!.checkGameOver();

    // Capture snapshot of the turn result (after combat, before next turn starts)
    if (_currentMatch != null) {
      _currentMatch!.history.add(
        TurnSnapshot.fromState(
          matchState: _currentMatch!,
          currentLogs: _combatResolver.logEntries,
        ),
      );
    }

    if (!_currentMatch!.isGameOver) {
      _startNextTurn();
    }
  }

  void _syncBoardCardsFromLanesIfNeeded() {
    if (_currentMatch == null) return;
    if (!_legacyLanesDirtyForBoardSync) return;

    final match = _currentMatch!;

    // Clear only card lists; keep terrain/owner/traps/ignite/gravestones intact.
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = match.board.getTile(row, col);
        tile.cards.clear();
        tile.hiddenSpies.clear();
      }
    }

    for (final lane in match.lanes) {
      final col = lane.position.index;

      // Row 2: player's base cards + opponent attackers that reached player base.
      match.board
          .getTile(2, col)
          .cards
          .addAll(lane.playerCards.baseCards.aliveCards);
      match.board
          .getTile(2, col)
          .cards
          .addAll(lane.opponentCards.enemyBaseCards.aliveCards);

      // Row 1: middle cards from both sides.
      match.board
          .getTile(1, col)
          .cards
          .addAll(lane.playerCards.middleCards.aliveCards);
      match.board
          .getTile(1, col)
          .cards
          .addAll(lane.opponentCards.middleCards.aliveCards);

      // Row 0: opponent base cards + player attackers that reached enemy base.
      match.board
          .getTile(0, col)
          .cards
          .addAll(lane.opponentCards.baseCards.aliveCards);
      match.board
          .getTile(0, col)
          .cards
          .addAll(lane.playerCards.enemyBaseCards.aliveCards);
    }
  }

  /// Resolve a single lane with tick-by-tick animations
  Future<void> _resolveLaneAnimated(Lane lane) async {
    currentCombatLane = lane.position;
    currentTickInfo =
        '⚔️ ${lane.position.name.toUpperCase()} - Combat Starting...';
    laneTickProgress[lane.position] = 0; // Mark lane as starting

    // Provide lane/attunement context to the combat resolver so it can
    // apply terrain buffs when card element matches tile terrain.
    if (_currentMatch != null) {
      // Get the tile terrain based on current zone
      final col = lane.position.index;
      final row = lane.currentZone == Zone.playerBase
          ? 2
          : lane.currentZone == Zone.enemyBase
          ? 0
          : 1;
      final tile = _currentMatch!.board.getTile(row, col);

      _combatResolver.setLaneContext(
        zone: lane.currentZone,
        tileTerrain: tile.terrain,
        playerDamageBoost: playerDamageBoost,
      );
    }

    // Calculate lane-wide buffs from inspire, fortify, command, rally abilities
    // This must be called before processing ticks to apply buffs correctly
    _combatResolver.calculateLaneBuffsPublic(
      lane,
      lane.position.name.toUpperCase(),
    );

    // Initial delay to show combat starting (skip in fast/sim mode)
    if (!fastMode) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    onCombatUpdate?.call();

    // Process ticks 1-5 with delays
    for (int tick = 1; tick <= 5; tick++) {
      final playerCard = lane.playerStack.activeCard;
      final opponentCard = lane.opponentStack.activeCard;

      // If both sides are empty, break
      if (playerCard == null && opponentCard == null) break;

      currentCombatTick = tick;
      laneTickProgress[lane.position] = tick; // Update lane tick clock
      currentTickInfo = 'Tick $tick: Processing...';

      // Count log entries before this tick
      final logCountBefore = _combatResolver.logEntries.length;

      // Resolve this tick
      _combatResolver.processTickInLane(tick, lane);

      // Get new log entries from this tick
      final newEntries = _combatResolver.logEntries
          .skip(logCountBefore)
          .toList();

      // Build detailed tick info with combat summaries
      // Include all important events, not just damage
      currentTickDetails = newEntries
          .where(
            (e) => e.tick == tick && (e.damageDealt != null || e.isImportant),
          )
          .map((e) {
            if (e.damageDealt != null) {
              return e.combatSummary;
            }
            // Format ability/event messages nicely
            return '${e.action}: ${e.details}';
          })
          .toList();

      // Build a human-readable tick summary
      final attacks = newEntries
          .where((e) => e.tick == tick && e.damageDealt != null)
          .toList();
      final kills = attacks.where((e) => e.targetDied == true).toList();

      String tickSummary;
      if (attacks.isEmpty) {
        tickSummary = '⏸️ Tick $tick: No attacks this tick';
      } else if (kills.isNotEmpty) {
        final killNames = kills.map((e) => e.targetName).join(', ');
        tickSummary = '💀 Tick $tick: ${killNames} destroyed!';
      } else {
        final totalDamage = attacks.fold<int>(
          0,
          (sum, e) => sum + (e.damageDealt ?? 0),
        );
        tickSummary =
            '⚔️ Tick $tick: ${attacks.length} attack${attacks.length > 1 ? 's' : ''}, $totalDamage total damage';
      }

      currentTickInfo = tickSummary;

      // Determine if there was combat action this tick
      final hadCombat = currentTickDetails.isNotEmpty || attacks.isNotEmpty;
      final tickDelay = hadCombat ? tickDelayWithCombat : tickDelayNoCombat;

      // Auto-progress with variable delay based on combat activity
      if (autoProgress && !skipAllTicks) {
        onCombatUpdate?.call();
        if (!fastMode) {
          await Future.delayed(Duration(milliseconds: tickDelay));
        }
      } else if (!skipAllTicks) {
        // Manual progression (waiting for user input)
        waitingForNextTick = true;
        onCombatUpdate?.call();

        // Wait until user presses next or skip
        while (waitingForNextTick && !skipAllTicks) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // Clean up dead cards
      lane.playerStack.cleanup();
      lane.opponentStack.cleanup();

      // Update UI after cleanup
      if (!skipAllTicks) {
        onCombatUpdate?.call();
      }

      // Check if combat is over
      if (lane.playerStack.isEmpty || lane.opponentStack.isEmpty) {
        currentTickInfo = '🏁 Combat Complete!';
        laneTickProgress[lane.position] = 6; // Mark as complete
        break;
      }
    }

    // Mark lane as complete if we finished all 5 ticks
    if (laneTickProgress[lane.position] != 6) {
      laneTickProgress[lane.position] = 6;
    }

    // Reset lane buffs after combat completes
    _combatResolver.resetLaneBuffsPublic();

    // Final delay after lane completes (skip in fast/sim mode)
    if (!fastMode && !skipAllTicks) {
      await Future.delayed(const Duration(milliseconds: 400));
    }
    currentTickInfo = null;
    currentCombatLane = null;
    currentCombatTick = null;
    currentTickDetails = [];
    onCombatUpdate?.call();
  }

  /// Process far_attack cards (siege cannons that attack other tiles in same lane)
  /// These cards attack enemies at different tiles in their lane, but only if:
  /// 1. They are NOT contested (no enemy at their own tile)
  /// 2. There ARE enemies at other tiles in the same lane
  /// 3. Their tick fires (tick 5 for siege cannon)
  Future<void> _processFarAttackCards() async {
    if (_currentMatch == null) return;

    _log('\n--- FAR ATTACK PHASE ---');

    for (final lane in _currentMatch!.lanes) {
      // Check player's far_attack cards
      await _processFarAttackInLane(lane, isPlayer: true);
      // Check opponent's far_attack cards
      await _processFarAttackInLane(lane, isPlayer: false);
    }

    _log('--- END FAR ATTACK PHASE ---');
  }

  /// Process far_attack cards for one side in a lane
  Future<void> _processFarAttackInLane(
    Lane lane, {
    required bool isPlayer,
  }) async {
    final laneName = lane.position.name.toUpperCase();
    final cards = isPlayer ? lane.playerCards : lane.opponentCards;
    final enemyCards = isPlayer ? lane.opponentCards : lane.playerCards;

    // Check all tiles for far_attack cards
    for (final zone in Zone.values) {
      final stack = cards.getStackAt(zone, isPlayer);
      final allCardsInStack = [
        stack.topCard,
        stack.bottomCard,
      ].whereType<GameCard>();

      for (final card in allCardsInStack) {
        if (!card.isAlive) continue;
        if (!card.abilities.contains('far_attack')) continue;

        // Check if contested at own tile (enemy present at same zone)
        final enemyAtSameTile = enemyCards.getStackAt(zone, !isPlayer);
        if (!enemyAtSameTile.isEmpty) {
          _log(
            '$laneName: ${card.name} cannot fire - contested at ${zone.name}',
          );
          continue;
        }

        // Find enemies at OTHER tiles in this lane
        GameCard? target;
        Zone? targetZone;
        for (final otherZone in Zone.values) {
          if (otherZone == zone) continue; // Skip own tile
          final enemyStack = enemyCards.getStackAt(otherZone, !isPlayer);
          final enemyActive = enemyStack.activeCard;
          if (enemyActive != null && enemyActive.isAlive) {
            target = enemyActive;
            targetZone = otherZone;
            break; // Attack first enemy found
          }
        }

        if (target == null) {
          _log('$laneName: ${card.name} has no targets in other tiles');
          continue;
        }

        // Check if tick 5 fires (far_attack cards are tick 5)
        // Since this runs after combat, we simulate a single tick 5 attack
        if (card.tick == 5) {
          final damage = card.damage;
          final hpBefore = target.currentHealth;
          final died = target.takeDamage(damage);
          final hpAfter = target.currentHealth;

          final side = isPlayer ? '🛡️ YOU' : '⚔️ AI';
          final result = died ? '💀 DESTROYED' : '✓ Hit';

          _log(
            '$laneName: 🎯 FAR ATTACK $side ${card.name} → ${target.name} at ${targetZone!.name}',
          );
          _log('  $damage damage | HP: $hpBefore → $hpAfter | $result');

          // Add to combat log
          _combatResolver.combatLog.add(
            BattleLogEntry(
              tick: 5,
              laneDescription: laneName,
              action: '🎯 FAR ATTACK $side ${card.name} → ${target.name}',
              details:
                  '$damage damage dealt | HP: $hpBefore → $hpAfter | $result',
              isImportant: died,
              damageDealt: damage,
              attackerName: card.name,
              targetName: target.name,
              targetHpBefore: hpBefore,
              targetHpAfter: hpAfter,
              targetDied: died,
            ),
          );

          // Cleanup dead cards
          if (died) {
            onCardDestroyed?.call(target);
          }
          enemyCards.cleanup();
        }
      }
    }
  }

  /// Check crystal damage after combat
  /// Crystal damage occurs when:
  /// 1. Uncontested: Attackers at enemy base with no defenders
  /// 2. Combat victory at enemy base: Surviving attackers deal damage
  /// Attackers STAY at enemy base (no retreat unless special ability)
  void _checkCrystalDamage() {
    if (_currentMatch == null) return;

    _log('\n--- CRYSTAL DAMAGE CHECK ---');

    int laneDamageBonusForCards(Iterable<GameCard> cards) {
      int damage = 0;
      for (final card in cards) {
        for (final ability in card.abilities) {
          if (ability.startsWith('inspire_')) {
            damage += int.tryParse(ability.split('_').last) ?? 0;
          }
          if (ability.startsWith('command_')) {
            damage += int.tryParse(ability.split('_').last) ?? 0;
          }
          if (ability.startsWith('rally_')) {
            damage += int.tryParse(ability.split('_').last) ?? 0;
          }
        }
      }
      return damage;
    }

    for (final lane in _currentMatch!.lanes) {
      final laneName = lane.position.name.toUpperCase();
      final colIndex = lane.position.index;

      // Check for player attackers at enemy base
      final playerAttackers = lane.playerCards.enemyBaseCards.aliveCards;
      final opponentDefenders = lane.opponentCards.baseCards.aliveCards;

      if (playerAttackers.isNotEmpty) {
        // Fog of war is now DYNAMIC - no permanent reveal needed
        if (opponentDefenders.isEmpty) {
          // Uncontested - deal full damage
          final laneBonus = laneDamageBonusForCards(
            lane.playerCards.allAliveCards,
          );
          final totalDamage = playerAttackers.fold<int>(
            0,
            (sum, card) =>
                sum +
                card.damage +
                laneBonus +
                (playerDamageBoost > 0 ? playerDamageBoost : 0),
          );
          _currentMatch!.opponent.takeCrystalDamage(totalDamage);
          _log('$laneName: 💥 $totalDamage UNCONTESTED crystal damage to AI!');
          _log('$laneName: Player attackers hold enemy base');

          // Update tile ownership
          _updateTileOwnership(
            colIndex,
            Zone.enemyBase,
            isPlayerAdvancing: true,
          );
        } else if (lane.currentZone == Zone.enemyBase &&
            lane.playerWon == true) {
          // Won combat at enemy base - survivors deal damage
          final survivors = lane.playerStack.aliveCards;
          if (survivors.isNotEmpty) {
            final laneBonus = laneDamageBonusForCards(
              lane.playerCards.allAliveCards,
            );
            final totalDamage = survivors.fold<int>(
              0,
              (sum, card) =>
                  sum +
                  card.damage +
                  laneBonus +
                  (playerDamageBoost > 0 ? playerDamageBoost : 0),
            );
            _currentMatch!.opponent.takeCrystalDamage(totalDamage);
            _log(
              '$laneName: 💥 $totalDamage crystal damage to AI (combat victory)!',
            );
            _log('$laneName: Player attackers hold enemy base');

            // Update tile ownership
            _updateTileOwnership(
              colIndex,
              Zone.enemyBase,
              isPlayerAdvancing: true,
            );
          }

          // Award gold for combat victory
          _currentMatch!.player.earnGold(400);
        }
      }

      // Check for opponent attackers at player base
      final opponentAttackers = lane.opponentCards.enemyBaseCards.aliveCards;
      final playerDefenders = lane.playerCards.baseCards.aliveCards;

      if (opponentAttackers.isNotEmpty) {
        if (playerDefenders.isEmpty) {
          // Uncontested - deal full damage
          final laneBonus = laneDamageBonusForCards(
            lane.opponentCards.allAliveCards,
          );
          final totalDamage = opponentAttackers.fold<int>(
            0,
            (sum, card) => sum + card.damage + laneBonus,
          );
          _currentMatch!.player.takeCrystalDamage(totalDamage);
          _log(
            '$laneName: 💥 $totalDamage UNCONTESTED crystal damage to Player!',
          );
          _log('$laneName: AI attackers hold player base');

          // Update tile ownership
          _updateTileOwnership(
            colIndex,
            Zone.playerBase,
            isPlayerAdvancing: false,
          );
        } else if (lane.currentZone == Zone.playerBase &&
            lane.playerWon == false) {
          // Won combat at player base - survivors deal damage
          final survivors = lane.opponentStack.aliveCards;
          if (survivors.isNotEmpty) {
            final laneBonus = laneDamageBonusForCards(
              lane.opponentCards.allAliveCards,
            );
            final totalDamage = survivors.fold<int>(
              0,
              (sum, card) => sum + card.damage + laneBonus,
            );
            _currentMatch!.player.takeCrystalDamage(totalDamage);
            _log(
              '$laneName: 💥 $totalDamage crystal damage to Player (combat victory)!',
            );
            _log('$laneName: AI attackers hold player base');

            // Update tile ownership
            _updateTileOwnership(
              colIndex,
              Zone.playerBase,
              isPlayerAdvancing: false,
            );
          }

          // Award gold for combat victory
          _currentMatch!.opponent.earnGold(400);
        }
      }

      // Check for combat victories at other zones (award gold)
      if (lane.hasCombat || lane.playerWon != null) {
        if (lane.playerWon == true && lane.currentZone != Zone.enemyBase) {
          _log('$laneName: Player victory at ${lane.zoneDisplay}');
          _currentMatch!.player.earnGold(400);
        } else if (lane.playerWon == false &&
            lane.currentZone != Zone.playerBase) {
          _log('$laneName: AI victory at ${lane.zoneDisplay}');
          _currentMatch!.opponent.earnGold(400);
        } else if (lane.playerWon == null && lane.hasCombat) {
          _log('$laneName: Draw at ${lane.zoneDisplay}');
        }
      }
    }

    _log('--- END CRYSTAL DAMAGE CHECK ---');

    // Log the board state after combat resolution
    _log('\n--- BOARD STATE (AFTER COMBAT) ---');
    _logBoardState();
  }

  /// Log the current board state showing tiles and cards
  void _logBoardState() {
    if (_currentMatch == null) return;

    final board = _currentMatch!.board;
    final lanes = _currentMatch!.lanes;

    _log('\n╔════════════════════════════════════╗');
    _log('║         BOARD STATE                ║');
    _log('╠════════════════════════════════════╣');

    // Row labels
    final rowLabels = ['Enemy Base', 'Middle    ', 'Your Base '];

    for (int row = 0; row < 3; row++) {
      _log('║ ${rowLabels[row]}:');

      for (int col = 0; col < 3; col++) {
        final tile = board.getTile(row, col);
        final lane = lanes[col];

        // Get owner symbol
        String ownerSymbol;
        switch (tile.owner) {
          case TileOwner.player:
            ownerSymbol = '🔵';
          case TileOwner.opponent:
            ownerSymbol = '🔴';
          case TileOwner.neutral:
            ownerSymbol = '⚪';
        }

        // Get cards at this tile based on position
        List<String> cardNames = [];
        final lanePos = [
          LanePosition.west,
          LanePosition.center,
          LanePosition.east,
        ][col];

        // Row 0 = enemy base, Row 1 = middle, Row 2 = player base
        // Show cards at their ACTUAL positions (not based on combat zone)
        if (row == 0) {
          // Enemy base row - show opponent's base cards + player's attacking cards
          // Player cards that reached enemy base
          for (final card in lane.playerCards.enemyBaseCards.aliveCards) {
            cardNames.add('P:${card.name}(${card.currentHealth}hp)');
          }
          // Opponent's staging cards (with fog of war)
          if (_currentMatch!.revealedEnemyBaseLanes.contains(lanePos)) {
            for (final card in lane.opponentCards.baseCards.aliveCards) {
              cardNames.add('O:${card.name}(${card.currentHealth}hp)');
            }
          } else {
            final hiddenCount = lane.opponentCards.baseCards.aliveCards.length;
            if (hiddenCount > 0) {
              cardNames.add('??? ($hiddenCount hidden)');
            }
          }
        } else if (row == 1) {
          // Middle row - show both sides' middle cards
          for (final card in lane.playerCards.middleCards.aliveCards) {
            cardNames.add('P:${card.name}(${card.currentHealth}hp)');
          }
          for (final card in lane.opponentCards.middleCards.aliveCards) {
            cardNames.add('O:${card.name}(${card.currentHealth}hp)');
          }
        } else if (row == 2) {
          // Player base row - show player's base cards + opponent's attacking cards
          for (final card in lane.playerCards.baseCards.aliveCards) {
            cardNames.add('P:${card.name}(${card.currentHealth}hp)');
          }
          // Opponent cards that reached player base
          for (final card in lane.opponentCards.enemyBaseCards.aliveCards) {
            cardNames.add('O:${card.name}(${card.currentHealth}hp)');
          }
        }

        final colName = ['W', 'C', 'E'][col];

        // Fog of war: hide enemy base terrain unless revealed
        String terrain;
        if (row == 0 &&
            !_currentMatch!.revealedEnemyBaseLanes.contains(lanePos)) {
          terrain = '???'; // Hidden terrain
        } else {
          terrain = tile.terrain ?? '-';
        }

        final cardsStr = cardNames.isEmpty ? 'empty' : cardNames.join(', ');

        _log('║   [$colName] $ownerSymbol $terrain: $cardsStr');
      }
    }

    _log('╚════════════════════════════════════╝');

    // Add compact visual grid based on ACTUAL positions (same as UI)
    _log('\n     W   C   E     POSITIONS');
    _log('   ┌───┬───┬───┐');
    for (int row = 0; row < 3; row++) {
      final rowLabel = ['0', '1', '2'][row];
      String rowStr = ' $rowLabel │';
      for (int col = 0; col < 3; col++) {
        final tile = board.getTile(row, col);
        final lane = lanes[col];

        bool hasPlayer;
        bool hasOpponent;

        // Row 0 = enemy base, Row 1 = middle, Row 2 = player base
        if (row == 0) {
          // Enemy base: player attackers + opponent base stack
          hasPlayer = lane.playerCards.enemyBaseCards.aliveCards.isNotEmpty;
          hasOpponent = lane.opponentCards.baseCards.aliveCards.isNotEmpty;
        } else if (row == 1) {
          // Middle: both sides' middle stacks
          hasPlayer = lane.playerCards.middleCards.aliveCards.isNotEmpty;
          hasOpponent = lane.opponentCards.middleCards.aliveCards.isNotEmpty;
        } else {
          // Player base: player base stack + opponent attackers at your base
          hasPlayer = lane.playerCards.baseCards.aliveCards.isNotEmpty;
          hasOpponent = lane.opponentCards.enemyBaseCards.aliveCards.isNotEmpty;
        }

        String cell;
        if (hasPlayer && hasOpponent) {
          cell = 'X';
        } else if (hasPlayer) {
          cell = 'P';
        } else if (hasOpponent) {
          cell = 'O';
        } else {
          cell = '·';
        }

        // Add owner color indicator
        String ownerMark = '';
        if (tile.owner == TileOwner.player) {
          ownerMark = '▪'; // Player owned
        } else if (tile.owner == TileOwner.opponent) {
          ownerMark = '▫'; // Opponent owned
        }

        rowStr += ' $cell$ownerMark│';
      }

      final rowName = row == 0 ? 'Enemy' : (row == 1 ? 'Mid' : 'You');
      _log('$rowStr  $rowName');
      if (row < 2) _log('   ├───┼───┼───┤');
    }
    _log('   └───┴───┴───┘');
    _log(
      'Legend: P=Player cards, O=Opponent cards, X=Combat, ▪=PlayerOwned, ▫=OpponentOwned',
    );
  }

  /// Update tile ownership when zone advances.
  /// ONLY middle tiles (row 1) can be captured.
  /// Base tiles (row 0 & row 2) are NEVER captured.
  void _updateTileOwnership(
    int col,
    Zone newZone, {
    required bool isPlayerAdvancing,
  }) {
    if (_currentMatch == null) return;

    final board = _currentMatch!.board;

    // ONLY middle tiles can be captured
    // Base tiles NEVER change ownership
    if (newZone == Zone.middle) {
      final tile = board.getTile(1, col);

      if (isPlayerAdvancing) {
        if (tile.owner != TileOwner.player) {
          tile.owner = TileOwner.player;
          _log('  🏴 Player captured ${tile.displayName}!');
          // Fog of war is now DYNAMIC - visibility based on current card positions
        }
      } else {
        if (tile.owner != TileOwner.opponent) {
          tile.owner = TileOwner.opponent;
          _log('  🚩 Opponent captured ${tile.displayName}!');
        }
      }
    }
  }

  /// Advance to next turn (used after combat resolves when game not over)
  void _startNextTurn() {
    if (_currentMatch == null) return;

    _currentMatch!.currentPhase = MatchPhase.drawPhase;

    // Draw cards for both players
    _currentMatch!.player.drawCards();
    _currentMatch!.opponent.drawCards();

    // DON'T reset lanes - surviving cards persist across turns!
    // Zones and surviving cards remain in their positions.

    // Reset submissions for next turn
    _currentMatch!.resetSubmissions();

    // Reset temporary buffs from hero abilities
    _playerDamageBoostActive = false;

    // Increment turn
    _currentMatch!.turnNumber++;
    _currentMatch!.currentPhase = MatchPhase.turnPhase;
  }

  /// Get combat log entries for UI display
  List<dynamic> getCombatLog() {
    return _combatResolver.logEntries;
  }

  /// End current match
  void endMatch() {
    _currentMatch = null;
    _combatResolver.clearLog();
  }

  /// Debug helper: print a readable snapshot of the current game state.
  ///
  /// Shows turn, phase, player/opponent crystals and gold, and for each lane
  /// the current zone plus front/back cards on both sides.
  void printGameStateSnapshot() {
    final match = _currentMatch;
    if (match == null) {
      _log('No active match.');
      return;
    }

    _log('\n=== GAME STATE SNAPSHOT ===');
    _log('Turn ${match.turnNumber} | Phase: ${match.currentPhase}');
    _log(
      'Player: ${match.player.name} | Crystal: ${match.player.crystalHP} HP | '
      'Hand: ${match.player.hand.length} | Deck: ${match.player.deck.remainingCards} | '
      'Gold: ${match.player.gold}',
    );
    _log(
      'Opponent: ${match.opponent.name} | Crystal: ${match.opponent.crystalHP} HP | '
      'Hand: ${match.opponent.hand.length} | Deck: ${match.opponent.deck.remainingCards} | '
      'Gold: ${match.opponent.gold}',
    );

    for (final lane in match.lanes) {
      final laneLabel = lane.position.name.toUpperCase();
      _log('\nLane $laneLabel | Zone: ${lane.zoneDisplay}');

      final playerFront = lane.playerStack.topCard;
      final playerBack = lane.playerStack.bottomCard;
      final opponentFront = lane.opponentStack.topCard;
      final opponentBack = lane.opponentStack.bottomCard;

      String describeCard(GameCard? card) {
        if (card == null) return '—';
        return '${card.name} (HP: ${card.currentHealth}/${card.health}, '
            'DMG: ${card.damage}, T: ${card.tick}'
            '${card.element != null ? ', Terrain: ${card.element}' : ''})';
      }

      _log('  Player Front:  ${describeCard(playerFront)}');
      _log('  Player Back:   ${describeCard(playerBack)}');
      _log('  Opp Front:     ${describeCard(opponentFront)}');
      _log('  Opp Back:      ${describeCard(opponentBack)}');
    }

    _log('=== END GAME STATE SNAPSHOT ===\n');
  }

  // ===========================================================================
  // TYC3: TURN-BASED AP SYSTEM
  // ===========================================================================

  /// Whether to use the new TYC3 turn-based system (vs legacy simultaneous)
  bool useTurnBasedSystem = false;

  /// Callback when turn changes (for UI updates)
  Function(String activePlayerId)? onTurnChanged;

  /// Callback when turn timer updates (for UI countdown)
  Function(int secondsRemaining)? onTurnTimerUpdate;

  /// Callback when a relic is discovered (for celebratory UI)
  /// Parameters: (playerName, isHumanPlayer, rewardCard)
  Function(String playerName, bool isHumanPlayer, GameCard rewardCard)?
  onRelicDiscovered;

  /// Start a new match with TYC3 turn-based system
  /// If [firstPlayerId] is provided (for online mode), use it instead of random selection
  /// For online mode, pass [predefinedTerrains] and [predefinedRelicColumn] from host
  void startMatchTYC3({
    required String playerId,
    required String playerName,
    required Deck playerDeck,
    required String opponentId,
    required String opponentName,
    required Deck opponentDeck,
    bool opponentIsAI = true,
    String? playerAttunedElement,
    String? opponentAttunedElement,
    GameHero? playerHero,
    GameHero? opponentHero,
    String? firstPlayerIdOverride, // For online mode: who goes first
    List<List<String>>?
    predefinedTerrains, // For online: terrain grid from host
    int? predefinedRelicColumn, // For online: relic column from host
    bool skipOpponentShuffle =
        false, // For online: opponent deck already in synced order
    String? relicName, // Custom relic name (e.g. for campaign)
    String? relicDescription, // Custom relic description
    bool isChessTimerMode = false, // Whether to use chess timer
    int? playerBaseHP, // Optional starting HP for player
    int? opponentBaseHP, // Optional starting HP for opponent
    List<String>?
    opponentPriorityCardIds, // Card IDs to prioritize in opponent's starting hand (e.g., boss cards)
  }) {
    // Use the existing startMatch logic
    startMatch(
      playerId: playerId,
      playerName: playerName,
      playerDeck: playerDeck,
      opponentId: opponentId,
      opponentName: opponentName,
      opponentDeck: opponentDeck,
      opponentIsAI: opponentIsAI,
      playerAttunedElement: playerAttunedElement,
      opponentAttunedElement: opponentAttunedElement,
      playerHero: playerHero,
      opponentHero: opponentHero,
      predefinedTerrains: predefinedTerrains,
      predefinedRelicColumn: predefinedRelicColumn,
      skipOpponentShuffle: skipOpponentShuffle,
      relicName: relicName,
      relicDescription: relicDescription,
      isChessTimerMode: isChessTimerMode,
      playerBaseHP: playerBaseHP,
      opponentBaseHP: opponentBaseHP,
      opponentPriorityCardIds: opponentPriorityCardIds,
    );

    if (_currentMatch == null) return;

    // Enable TYC3 mode
    useTurnBasedSystem = true;

    // Use provided first player ID (online mode) or random selection (AI mode)
    final String firstPlayerId;
    if (firstPlayerIdOverride != null) {
      firstPlayerId = firstPlayerIdOverride;
    } else {
      final random = DateTime.now().millisecondsSinceEpoch % 2 == 0;
      firstPlayerId = random ? playerId : opponentId;
    }

    // Initialize TYC3 turn state
    _currentMatch!.activePlayerId = firstPlayerId;
    _currentMatch!.isFirstTurn = true;
    _currentMatch!.cardsPlayedThisTurn = 0;
    _currentMatch!.turnStartTime = DateTime.now();

    // Set phase based on who goes first
    if (firstPlayerId == playerId) {
      _currentMatch!.currentPhase = MatchPhase.playerTurn;
    } else {
      _currentMatch!.currentPhase = MatchPhase.opponentTurn;
    }

    // Regenerate AP for all cards of the active player
    _regenerateAPForActivePlayer();

    _log(
      '\n🎲 TYC3: ${firstPlayerId == playerId ? "Player" : "Opponent"} goes first!',
    );
    _log(
      '📍 Turn 1 - ${_currentMatch!.isFirstTurn ? "First turn (1 card limit)" : ""}',
    );

    // Capture initial state for replay (Turn 1 start)
    _currentMatch!.history.add(
      TurnSnapshot.fromState(matchState: _currentMatch!),
    );

    onTurnChanged?.call(firstPlayerId);
  }

  /// Check if it's currently the player's turn
  bool get isPlayerTurn {
    if (_currentMatch == null) return false;
    if (!useTurnBasedSystem) return true; // Legacy mode always allows player
    return _currentMatch!.activePlayerId == _currentMatch!.player.id;
  }

  /// Check if it's currently the opponent's turn
  bool get isOpponentTurn {
    if (_currentMatch == null) return false;
    if (!useTurnBasedSystem) return true; // Legacy mode always allows opponent
    return _currentMatch!.activePlayerId == _currentMatch!.opponent.id;
  }

  /// Get the active player
  Player? get activePlayer {
    if (_currentMatch == null) return null;
    if (_currentMatch!.activePlayerId == _currentMatch!.player.id) {
      return _currentMatch!.player;
    }
    return _currentMatch!.opponent;
  }

  /// Get max cards that can be played this turn
  /// Turn 1 = 1 card only (balances first-mover advantage)
  /// All other turns = 2 cards
  int get maxCardsThisTurn {
    if (_currentMatch == null) return 0;
    if (maxCardsThisTurnOverride != null) return maxCardsThisTurnOverride!;
    return _currentMatch!.isFirstTurn ? 1 : 2;
  }

  /// Check if active player can play more cards this turn
  bool get canPlayMoreCards {
    if (_currentMatch == null) return false;
    return _currentMatch!.cardsPlayedThisTurn < maxCardsThisTurn;
  }

  /// Get seconds remaining in current turn
  int get turnSecondsRemaining {
    if (_currentMatch?.turnStartTime == null) return 0;
    final elapsed = DateTime.now().difference(_currentMatch!.turnStartTime!);
    final remaining = MatchState.turnDurationSeconds - elapsed.inSeconds;
    return remaining.clamp(0, MatchState.turnDurationSeconds);
  }

  /// TYC3: Place a card from hand onto a base tile
  /// Returns true if successful
  bool placeCardTYC3(GameCard card, int row, int col) {
    if (_currentMatch == null) return false;
    if (!useTurnBasedSystem) return false;

    final active = activePlayer;
    if (active == null) return false;

    // Check if it's this player's turn
    final isPlayer = active.id == _currentMatch!.player.id;
    if (isPlayer && !isPlayerTurn) return false;
    if (!isPlayer && !isOpponentTurn) return false;

    // Check card limit
    if (!canPlayMoreCards) {
      _log('❌ Cannot play more cards this turn (limit: $maxCardsThisTurn)');
      return false;
    }

    // Validate placement - must be on own base row, or middle row if card has 2+ AP
    final baseRow = isPlayer ? 2 : 0;
    final middleRow = 1;

    // Cards with 2+ maxAP can be placed on middle row (costs 1 extra AP)
    final canPlaceOnMiddle = card.maxAP >= 2;

    if (row == baseRow) {
      // Base row is always valid
    } else if (row == middleRow && canPlaceOnMiddle) {
      // Middle row valid for 2+ AP cards
    } else {
      _log(
        '❌ Can only place cards on your base row ($baseRow)${canPlaceOnMiddle ? " or middle row" : ""}',
      );
      return false;
    }

    // Get the tile (board.getTile returns non-null for valid 0-2 range)
    final tile = _currentMatch!.board.getTile(row, col);

    // Check tile capacity
    if (!_isTrapCard(card)) {
      if (_isSpyCard(card)) {
        if (_canAddFriendlyOccupant(tile, active.id) == false) {
          _log('❌ Tile is full (max ${Tile.maxCards} cards)');
          return false;
        }
        if (tile.hiddenSpies.any((s) => s.isAlive && s.ownerId == active.id)) {
          _log('❌ A spy is already on this tile');
          return false;
        }
      } else if (!tile.canAddCard) {
        _log('❌ Tile is full (max ${Tile.maxCards} cards)');
        return false;
      }
    }

    // Special case: Playing a medic from hand onto your base tile can
    // immediately heal an injured friendly unit on that tile, without paying
    // the placement AP cost (only the heal AP is spent).
    final isBasePlacement = row == baseRow;
    final isMedic = _isMedic(card);
    final injuredFriendlyOnTile = tile.cards
        .where(
          (c) =>
              c.isAlive && c.ownerId == active.id && c.currentHealth < c.health,
        )
        .toList();

    // Remove card from hand
    if (!active.playCard(card)) {
      _log('❌ Card not in hand');
      return false;
    }

    if (_isTrapCard(card)) {
      card.ownerId = active.id;
      final placed = _placeTrapOnTile(active, card, row, col);
      if (!placed) {
        active.hand.add(card);
      }
      return placed;
    }

    // Place card on tile
    _addCardToTile(tile, card);
    _currentMatch!.cardsPlayedThisTurn++;

    // Initialize card's AP and set owner
    // Default: Card starts with maxAP - 1 (placing costs 1 AP)
    // If placed on middle row, costs 2 AP (place + move)
    final shouldInstantHeal =
        isBasePlacement &&
        isMedic &&
        injuredFriendlyOnTile.isNotEmpty &&
        card.maxAP >= card.attackAPCost;
    final apCost = shouldInstantHeal ? 0 : (row == middleRow ? 2 : 1);
    card.currentAP = (card.maxAP - apCost).clamp(0, card.maxAP);
    card.ownerId = active.id;

    // Initialize ability charges for consumable abilities
    initializeAbilityCharges(card);

    final owner = isPlayer ? 'Player' : 'Opponent';
    final placementNote = (row == middleRow)
        ? ' (direct to middle, -2 AP)'
        : '';
    _log(
      '✅ [$owner] Placed ${card.name} (${card.damage}/${card.health}) at ($row, $col)$placementNote',
    );

    _triggerTrapIfPresent(card, row, col);

    if (_isSpyCard(card) && card.isAlive) {
      _triggerSpyOnEnemyBaseEntry(
        enteringCard: card,
        fromRow: row,
        fromCol: col,
        toRow: row,
        toCol: col,
      );
    }
    if (!card.isAlive) return true;

    final finalPos = _applyBurningOnEntry(
      enteringCard: card,
      fromRow: -1,
      fromCol: -1,
      toRow: row,
      toCol: col,
    );
    if (!card.isAlive) return true;

    _applyTerrainAffinityOnEntry(
      card: card,
      row: finalPos.row,
      col: finalPos.col,
    );

    if (shouldInstantHeal) {
      // Heal the most-injured friendly unit on this tile.
      injuredFriendlyOnTile.sort((a, b) {
        final missingA = a.health - a.currentHealth;
        final missingB = b.health - b.currentHealth;
        return missingB - missingA;
      });
      final target = injuredFriendlyOnTile.first;
      healCardTYC3(
        card,
        target,
        finalPos.row,
        finalPos.col,
        finalPos.row,
        finalPos.col,
      );
    }

    // Check for relic pickup at placement tile (in case placed on middle)
    _checkRelicPickup(finalPos.row, finalPos.col, card.ownerId!);

    // Update visibility (permanent lane reveal + scout)
    _updatePermanentVisibility(finalPos.row, finalPos.col, card.ownerId!);

    // Shaco: spawn decoys in side lanes
    if (_isShacoCard(card) && card.isAlive) {
      _spawnShacoDecoys(shaco: card, row: finalPos.row, col: finalPos.col);
    }

    return true;
  }

  /// TYC3: Place a card for the OPPONENT (used when replaying opponent's actions)
  /// This bypasses turn validation since we're replaying a past action
  bool placeCardForOpponentTYC3(GameCard card, int row, int col) {
    if (_currentMatch == null) return false;
    if (!useTurnBasedSystem) return false;

    final opponent = _currentMatch!.opponent;

    // Get the tile
    final tile = _currentMatch!.board.getTile(row, col);

    // Check tile capacity
    if (!_isTrapCard(card)) {
      if (_isSpyCard(card)) {
        if (_canAddFriendlyOccupant(tile, opponent.id) == false) {
          _log('❌ Replay: Tile is full (max ${Tile.maxCards} cards)');
          return false;
        }
        if (tile.hiddenSpies.any(
          (s) => s.isAlive && s.ownerId == opponent.id,
        )) {
          _log('❌ Replay: A spy is already on this tile');
          return false;
        }
      } else if (!tile.canAddCard) {
        _log('❌ Replay: Tile is full (max ${Tile.maxCards} cards)');
        return false;
      }
    }

    // Remove card from opponent's hand
    if (!opponent.playCard(card)) {
      _log('❌ Replay: Card not in opponent hand');
      return false;
    }

    if (_isTrapCard(card)) {
      card.ownerId = opponent.id;
      final placed = _placeTrapOnTile(opponent, card, row, col);
      if (!placed) {
        opponent.hand.add(card);
      }
      return placed;
    }

    // Place card on tile
    _addCardToTile(tile, card);

    // Initialize card's AP and set owner
    card.currentAP = card.maxAP - 1;
    card.ownerId = opponent.id;

    // Initialize ability charges for consumable abilities
    initializeAbilityCharges(card);

    _log(
      '✅ [Opponent Replay] Placed ${card.name} (${card.damage}/${card.health}) at ($row, $col)',
    );

    // Check for relic pickup
    _checkRelicPickup(row, col, card.ownerId!);

    _triggerTrapIfPresent(card, row, col);

    if (card.isAlive) {
      _applyBurningOnEntry(
        enteringCard: card,
        fromRow: -1,
        fromCol: -1,
        toRow: row,
        toCol: col,
      );
    }

    if (!card.isAlive) return true;

    // Update scout visibility
    if (card.abilities.contains('scout')) {
      _updateScoutVisibility(row, col, card.ownerId!);
    }

    return true;
  }

  /// TYC3: End the current player's turn
  void endTurnTYC3() {
    if (_currentMatch == null) return;
    if (!useTurnBasedSystem) return;
    if (_currentMatch!.isGameOver)
      return; // Prevent turn change if game is over

    final wasFirstTurn = _currentMatch!.isFirstTurn;

    // First turn ends after whoever goes first ends their turn
    // This balances first-mover advantage (they only get 1 card)
    if (wasFirstTurn) {
      _currentMatch!.isFirstTurn = false;
      _log('📍 First turn phase complete');
    }

    // Capture state for replay before switching turns
    if (_currentMatch != null) {
      _currentMatch!.history.add(
        TurnSnapshot.fromState(matchState: _currentMatch!),
      );
    }

    // Switch active player
    if (_currentMatch!.activePlayerId == _currentMatch!.player.id) {
      _currentMatch!.activePlayerId = _currentMatch!.opponent.id;
      _currentMatch!.currentPhase = MatchPhase.opponentTurn;
    } else {
      _currentMatch!.activePlayerId = _currentMatch!.player.id;
      _currentMatch!.currentPhase = MatchPhase.playerTurn;
    }

    // Increment turn number every time a turn ends (not just when it comes back to player)
    // This ensures both players see the same turn count
    _currentMatch!.turnNumber++;

    // Cleanup expired ignited tiles
    final currentTurn = _currentMatch!.turnNumber;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final tile = _currentMatch!.board.getTile(r, c);
        final until = tile.ignitedUntilTurn;
        if (until != null && until < currentTurn) {
          tile.ignitedUntilTurn = null;
        }
      }
    }

    // Cleanup old gravestones (remove after 1 turn)
    _cleanupGravestones();

    // Clean up enemy units that attacked more than 1 turn ago (fog of war)
    _currentMatch!.recentlyAttackedEnemyUnits.removeWhere(
      (unitId, attackTurn) => currentTurn - attackTurn >= 1,
    );

    // Reset turn state
    _currentMatch!.cardsPlayedThisTurn = 0;
    _currentMatch!.turnStartTime = DateTime.now();

    // Reset temporary buffs (Saladin hero ability, etc.)
    // Always reset this at the end of a turn cycle to ensure it doesn't carry over
    _playerDamageBoostActive = false;
    _playerDamageBoostExtra = 0;

    // Draw a card for the new active player
    final newActive = activePlayer;
    if (newActive != null) {
      final handSizeBefore = newActive.hand.length;
      newActive.drawCards(count: 1);
      _log('📥 ${newActive.name} draws 1 card');

      // Initialize charges for newly drawn cards
      if (newActive.hand.length > handSizeBefore) {
        final newCard = newActive.hand.last;
        initializeAbilityCharges(newCard);
      }
    }

    // Regenerate AP for all cards of the new active player
    _regenerateAPForActivePlayer();

    _log(
      '\n🔄 Turn ended. Now: ${isPlayerTurn ? "Player" : "Opponent"}\'s turn',
    );
    _log(
      '📍 Turn ${_currentMatch!.turnNumber}${_currentMatch!.isFirstTurn ? " (First turn)" : ""}',
    );

    // Log board state summary at end of each turn
    _logBoardStateSummary();

    onTurnChanged?.call(_currentMatch!.activePlayerId!);
  }

  /// Clean up gravestones that are older than 1 turn
  void _cleanupGravestones() {
    if (_currentMatch == null) return;
    final currentTurn = _currentMatch!.turnNumber;

    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final tile = _currentMatch!.board.getTile(r, c);
        tile.gravestones.removeWhere((gs) {
          // Remove if created before the previous turn (older than 1 turn cycle)
          // Since turns increment by 1 for each player's turn, 2 turns = 1 full round
          // Actually, "remove after 1 turn" usually means it stays for the opponent's turn and then disappears
          // So if created at turn X, it should be removed at turn X+2 (next time it's this player's turn?)
          // Or just strictly > 1 turn difference.
          // Let's keep it for 2 "half-turns" (1 full round) so both players see it.
          return currentTurn - gs.turnCreated > 1;
        });
      }
    }
  }

  /// Regenerate AP for all cards belonging to the active player
  void _regenerateAPForActivePlayer() {
    if (_currentMatch == null) return;
    final activeId = _currentMatch!.activePlayerId;
    if (activeId == null) return;
    regenerateAPForPlayer(activeId);
  }

  /// Regenerate AP and apply regen abilities for all cards belonging to a specific player
  /// Public method for online mode to call when turn switches
  void regenerateAPForPlayer(String playerId) {
    if (_currentMatch == null) return;

    int cardsRegen = 0;

    _applyPoisonTurnStartForPlayer(playerId);
    _applyIgniteTurnStartForPlayer(playerId);

    // Iterate through all tiles on the board
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tile = _currentMatch!.board.getTile(row, col);

        for (final card in tile.cards) {
          // Use ownerId to determine if card belongs to the player
          if (card.ownerId == playerId && card.isAlive) {
            card.regenerateAP();
            cardsRegen++;

            // Apply HP regen abilities
            _applyRegenAbilities(card);
          }
        }

        for (final card in tile.hiddenSpies) {
          if (card.ownerId == playerId && card.isAlive) {
            card.regenerateAP();
            cardsRegen++;
            _applyRegenAbilities(card);
          }
        }
      }
    }

    if (cardsRegen > 0) {
      _log('⚡ $cardsRegen cards regenerated AP');
    }
  }

  /// Apply HP regeneration abilities to a card at turn start
  void _applyRegenAbilities(GameCard card) {
    if (!card.isAlive) return;

    // Check for regen_X ability (e.g., regen_1, regen_2)
    for (final ability in card.abilities) {
      if (ability.startsWith('regen_')) {
        final regenAmount = int.tryParse(ability.split('_').last) ?? 0;
        if (regenAmount > 0 && card.currentHealth < card.health) {
          final oldHp = card.currentHealth;
          card.currentHealth = (card.currentHealth + regenAmount).clamp(
            0,
            card.health,
          );
          final healed = card.currentHealth - oldHp;
          if (healed > 0) {
            _log(
              '💚 ${card.name} regenerates $healed HP (${card.currentHealth}/${card.health})',
            );
          }
        }
      }
      // Also check for 'regenerate' ability (fixed amount)
      else if (ability == 'regenerate') {
        if (card.currentHealth < card.health) {
          final oldHp = card.currentHealth;
          card.currentHealth = (card.currentHealth + 2).clamp(
            0,
            card.health,
          ); // Default 2 HP
          final healed = card.currentHealth - oldHp;
          if (healed > 0) {
            _log(
              '💚 ${card.name} regenerates $healed HP (${card.currentHealth}/${card.health})',
            );
          }
        }
      }
    }
  }

  /// TYC3: Check if a card can move to an adjacent tile
  bool canMoveCard(
    GameCard card,
    int fromRow,
    int fromCol,
    int toRow,
    int toCol,
  ) {
    return getMoveError(card, fromRow, fromCol, toRow, toCol) == null;
  }

  /// TYC3: Get the reason why a card can't move (null if can move)
  String? getMoveError(
    GameCard card,
    int fromRow,
    int fromCol,
    int toRow,
    int toCol,
  ) {
    if (_currentMatch == null) return 'No active match';

    // Check if card belongs to active player using ownerId
    final activeId = _currentMatch!.activePlayerId;
    if (card.ownerId != activeId) {
      return "Cannot move opponent's cards";
    }

    if (card.currentAP < 1) {
      return 'Not enough AP to move (need 1, have ${card.currentAP})';
    }

    final lockReason = _getMoveLockReason(card, fromRow, fromCol);
    if (lockReason != null) {
      return lockReason;
    }

    // Calculate distance
    final rowDist = (toRow - fromRow).abs();
    final colDist = (toCol - fromCol).abs();

    // Must be adjacent (Manhattan distance of 1)
    if (rowDist + colDist != 1) {
      return 'Can only move to adjacent tile';
    }

    // Check cross-lane movement (column change)
    if (colDist > 0) {
      // Check if cross-lane movement is allowed globally or via ability
      final hasFlanking = card.abilities.contains('flanking');
      if (!allowCrossLaneMovement && !hasFlanking) {
        return 'Cannot move to other lanes (no flanking ability)';
      }
    }

    // Cannot move to enemy base (row 0 for player, row 2 for opponent)
    final isPlayerCard = card.ownerId == _currentMatch!.player.id;
    final isMovingIntoEnemyBase =
        (isPlayerCard && toRow == 0) || (!isPlayerCard && toRow == 2);
    if (isMovingIntoEnemyBase && !_isSpyCard(card)) {
      return 'Cannot move into enemy base';
    }

    // Check destination tile for enemy cards (alive ones only)
    final destTile = _currentMatch!.board.getTile(toRow, toCol);
    final hasEnemyCards =
        card.ownerId != null &&
        _tileHasEnemyCardsForOwner(destTile, card.ownerId!);
    if (hasEnemyCards && !_isSpyCard(card)) {
      return 'Tile occupied by enemy - attack to clear it first';
    }

    // Only one friendly spy per tile
    if (_isSpyCard(card) &&
        card.ownerId != null &&
        destTile.hiddenSpies.any(
          (s) => s.isAlive && s.ownerId == card.ownerId,
        )) {
      return 'A spy is already on this tile';
    }

    // Check destination tile capacity for friendly occupancy
    if (!_isSpyCard(card) && !destTile.canAddCard) {
      return 'Destination tile is full (max ${Tile.maxCards} cards)';
    }

    if (_isSpyCard(card) && card.ownerId != null && !hasEnemyCards) {
      if (!_canAddFriendlyOccupant(destTile, card.ownerId!)) {
        return 'Destination tile is full (max ${Tile.maxCards} cards)';
      }
    }

    return null; // Can move
  }

  /// TYC3: Get all tiles reachable with current AP (for multi-move display)
  /// Returns list of (row, col, apCost) tuples
  List<({int row, int col, int apCost})> getReachableTiles(
    GameCard card,
    int fromRow,
    int fromCol,
  ) {
    if (_currentMatch == null) return [];

    final reachable = <({int row, int col, int apCost})>[];
    final visited = <String>{};
    final queue = <({int row, int col, int apCost})>[
      (row: fromRow, col: fromCol, apCost: 0),
    ];

    final isPlayerCard = card.ownerId == _currentMatch!.player.id;
    final hasFlanking = card.abilities.contains('flanking');
    final canCrossLane = allowCrossLaneMovement || hasFlanking;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final key = '${current.row},${current.col}';

      if (visited.contains(key)) continue;
      visited.add(key);

      // Add to reachable if not starting position
      if (current.row != fromRow || current.col != fromCol) {
        reachable.add(current);
      }

      // Don't explore further if we've used all AP
      if (current.apCost >= card.currentAP) continue;

      // Check adjacent tiles
      final directions = <({int dr, int dc})>[
        (dr: -1, dc: 0), // Forward (toward enemy)
        (dr: 1, dc: 0), // Backward
        if (canCrossLane) (dr: 0, dc: -1), // Left
        if (canCrossLane) (dr: 0, dc: 1), // Right
      ];

      for (final dir in directions) {
        final newRow = current.row + dir.dr;
        final newCol = current.col + dir.dc;

        // Bounds check
        if (newRow < 0 || newRow > 2 || newCol < 0 || newCol > 2) continue;

        // Can't move into enemy base (except spies)
        if (!_isSpyCard(card)) {
          if (isPlayerCard && newRow == 0) continue;
          if (!isPlayerCard && newRow == 2) continue;
        }

        // Check destination tile
        final destTile = _currentMatch!.board.getTile(newRow, newCol);

        final hasEnemyCards =
            card.ownerId != null &&
            _tileHasEnemyCardsForOwner(destTile, card.ownerId!);
        if (hasEnemyCards && !_isSpyCard(card)) continue;

        if (_isSpyCard(card) &&
            card.ownerId != null &&
            destTile.hiddenSpies.any(
              (s) => s.isAlive && s.ownerId == card.ownerId,
            )) {
          continue;
        }

        // Check capacity for friendly occupancy
        if (!_isSpyCard(card) && !destTile.canAddCard) continue;
        if (_isSpyCard(card) && card.ownerId != null && !hasEnemyCards) {
          if (!_canAddFriendlyOccupant(destTile, card.ownerId!)) continue;
        }

        queue.add((row: newRow, col: newCol, apCost: current.apCost + 1));
      }
    }

    return reachable;
  }

  /// TYC3: Get all attack targets reachable with current AP (move + attack)
  /// Returns list of (target, row, col, moveCost) where moveCost is AP spent moving
  List<({GameCard target, int row, int col, int moveCost})>
  getReachableAttackTargets(GameCard card, int fromRow, int fromCol) {
    if (_currentMatch == null) return [];

    // Spies cannot attack - they only assassinate on enemy base entry
    if (_isSpyCard(card)) return [];

    final lockReason = _getAttackLockReason(card, fromRow, fromCol);
    if (lockReason != null) return [];

    final targets = <({GameCard target, int row, int col, int moveCost})>[];
    final isPlayerCard = card.ownerId == _currentMatch!.player.id;

    // Get all positions we can reach (including current position with 0 move cost)
    final positions = [
      (row: fromRow, col: fromCol, apCost: 0),
      ...getReachableTiles(card, fromRow, fromCol),
    ];

    for (final pos in positions) {
      // Check if we have enough AP left to attack from this position
      final apAfterMove = card.currentAP - pos.apCost;
      if (apAfterMove < card.attackAPCost) continue;

      // Get valid targets from this position
      final targetsFromPos = _getAttackTargetsFromPosition(
        card,
        pos.row,
        pos.col,
        isPlayerCard,
      );

      for (final target in targetsFromPos) {
        // Avoid duplicates (same target might be reachable from multiple positions)
        if (!targets.any((t) => t.target == target)) {
          targets.add((
            target: target,
            row: pos.row,
            col: pos.col,
            moveCost: pos.apCost,
          ));
        }
      }
    }

    return targets;
  }

  /// Helper: Get attack targets from a specific position
  /// Cross-lane attacks follow same rules as movement: only adjacent tiles (Manhattan distance 1)
  /// Forward attacks can go up to attackRange tiles ahead in same lane
  List<GameCard> _getAttackTargetsFromPosition(
    GameCard attacker,
    int row,
    int col,
    bool isPlayerCard,
  ) {
    final targets = <GameCard>[];
    final hasCrossAttack = attacker.abilities.contains('cross_attack');
    final canAttackCrossLane = allowCrossLaneAttack || hasCrossAttack;
    final hasDiagonalAttack = attacker.abilities.contains('diagonal_attack');

    // Forward direction: player attacks toward row 0, opponent toward row 2
    final forwardDir = isPlayerCard ? -1 : 1;

    // 1) Forward attacks in same lane (up to attackRange)
    for (int dist = 1; dist <= attacker.attackRange; dist++) {
      final targetRow = row + (forwardDir * dist);
      if (targetRow < 0 || targetRow > 2) break;

      _addTargetsFromTile(targets, attacker, targetRow, col);
    }

    // 2) Cross-lane attacks: only adjacent tiles (same row, different col)
    // This is like side movement - can only attack tiles directly to the left/right
    if (canAttackCrossLane) {
      // Left
      if (col > 0) {
        _addTargetsFromTile(targets, attacker, row, col - 1);
      }
      // Right
      if (col < 2) {
        _addTargetsFromTile(targets, attacker, row, col + 1);
      }
    }

    // 3) Diagonal attacks: only distance 1 diagonal tiles
    if (hasDiagonalAttack) {
      final diagonalPositions = [
        (row: row - 1, col: col - 1), // Top-left
        (row: row - 1, col: col + 1), // Top-right
        (row: row + 1, col: col - 1), // Bottom-left
        (row: row + 1, col: col + 1), // Bottom-right
      ];

      for (final pos in diagonalPositions) {
        if (pos.row >= 0 && pos.row <= 2 && pos.col >= 0 && pos.col <= 2) {
          _addTargetsFromTile(targets, attacker, pos.row, pos.col);
        }
      }
    }

    return targets;
  }

  /// Helper: Add enemy targets from a specific tile
  void _addTargetsFromTile(
    List<GameCard> targets,
    GameCard attacker,
    int row,
    int col,
  ) {
    final tile = _currentMatch!.board.getTile(row, col);
    final enemyCards = <GameCard>[
      ...tile.cards.where(
        (card) => card.isAlive && card.ownerId != attacker.ownerId,
      ),
      if (attacker.ownerId != null &&
          _isTileRevealedByWatcherForOwner(
            viewerOwnerId: attacker.ownerId!,
            row: row,
            col: col,
          ))
        ...tile.hiddenSpies.where(
          (card) => card.isAlive && card.ownerId != attacker.ownerId,
        ),
    ];

    if (enemyCards.isEmpty) return;

    // Check for guards
    final guards = enemyCards.where((c) => c.isGuard).toList();
    if (guards.isNotEmpty) {
      targets.addAll(guards);
    } else {
      targets.addAll(enemyCards);
    }
  }

  /// TYC3: Move a card to an adjacent tile (costs 1 AP)
  bool moveCardTYC3(
    GameCard card,
    int fromRow,
    int fromCol,
    int toRow,
    int toCol,
  ) {
    if (_currentMatch == null) return false;
    if (!useTurnBasedSystem) return false;

    final err = getMoveError(card, fromRow, fromCol, toRow, toCol);
    if (err != null) {
      final owner = _ownerLabel(card.ownerId);
      final lockDetails = _getMoveLockDetails(card, fromRow, fromCol);
      final consumedSource = lockDetails != null
          ? _consumeChargeFromFirstSource(
              lockDetails.sources,
              lockDetails.ability,
            )
          : null;
      if (consumedSource != null) {
        _log(
          '🔋 ${consumedSource.name} consumes its ${lockDetails!.ability} charge (remaining: ${_abilityChargesRemaining(consumedSource, lockDetails.ability, defaultCharges: 0)})',
        );
      }
      if (lockDetails != null) {
        final sources = _formatSources(lockDetails.sources);
        _log(
          '⛔ [$owner] ${card.name} cannot move ($fromRow,$fromCol) → ($toRow,$toCol): ${lockDetails.reason}${sources.isNotEmpty ? " (blocked by: $sources)" : ""}',
        );
      } else {
        _log(
          '⛔ [$owner] ${card.name} cannot move ($fromRow,$fromCol) → ($toRow,$toCol): $err',
        );
      }
      return false;
    }

    final fromTile = _currentMatch!.board.getTile(fromRow, fromCol);
    final toTile = _currentMatch!.board.getTile(toRow, toCol);

    // Spend AP
    if (!card.spendMoveAP()) {
      final owner = _ownerLabel(card.ownerId);
      _log(
        '⛔ [$owner] ${card.name} cannot move: not enough AP (AP ${card.currentAP}/${card.maxAP})',
      );
      return false;
    }

    _applyTerrainAffinityOnExit(card: card, fromTerrain: fromTile.terrain);

    // Remove from source tile
    _removeCardFromTile(fromTile, card);

    // Add to destination tile
    _addCardToTile(toTile, card);

    _triggerTrapIfPresent(card, toRow, toCol);
    if (!card.isAlive) return true;

    _triggerSpyOnEnemyBaseEntry(
      enteringCard: card,
      fromRow: fromRow,
      fromCol: fromCol,
      toRow: toRow,
      toCol: toCol,
    );
    if (!card.isAlive) return true;

    final finalPos = _applyBurningOnEntry(
      enteringCard: card,
      fromRow: fromRow,
      fromCol: fromCol,
      toRow: toRow,
      toCol: toCol,
    );
    if (!card.isAlive) return true;

    _applyFearOnEntry(enteringCard: card, row: finalPos.row, col: finalPos.col);

    _applyMarshDrainOnEntry(
      enteringCard: card,
      row: finalPos.row,
      col: finalPos.col,
    );

    _applyTerrainAffinityOnEntry(
      card: card,
      row: finalPos.row,
      col: finalPos.col,
    );

    final owner = card.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '🚶 [$owner] ${card.name} moved ($fromRow,$fromCol) → (${finalPos.row},${finalPos.col})',
    );

    // Check for relic pickup at destination tile
    _checkRelicPickup(finalPos.row, finalPos.col, card.ownerId!);

    // Update visibility (permanent lane reveal + scout)
    _updatePermanentVisibility(finalPos.row, finalPos.col, card.ownerId!);

    return true;
  }

  /// Check if a player picks up a relic at the given tile.
  /// If a relic is found, claim it and add the reward card to the player's hand.
  void _checkRelicPickup(int row, int col, String playerId) {
    if (_currentMatch == null) return;

    final relic = _currentMatch!.relicManager.getRelicAt(row, col);
    if (relic == null) return;

    // Claim the relic
    final rewardCard = _currentMatch!.relicManager.claimRelicAt(
      row,
      col,
      playerId,
    );
    if (rewardCard == null) return;

    // Determine which player claimed it
    final isPlayer = playerId == _currentMatch!.player.id;
    final claimingPlayer = isPlayer
        ? _currentMatch!.player
        : _currentMatch!.opponent;

    // Add the reward card to the player's hand
    claimingPlayer.hand.add(rewardCard);
    rewardCard.ownerId = playerId;

    _log('');
    _log('🏺 ═══════════════════════════════════════════════════════');
    _log('🏺 ${claimingPlayer.name} discovered the Ancient Artifact!');
    _log(
      '🏺 Reward: ${rewardCard.name} (${rewardCard.damage} DMG, ${rewardCard.health} HP)',
    );
    _log('🏺 ═══════════════════════════════════════════════════════');
    _log('');

    // Notify UI to show celebratory dialog
    onRelicDiscovered?.call(claimingPlayer.name, isPlayer, rewardCard);
  }

  /// Update fog of war visibility based on scout ability.
  /// Scout visibility is now DYNAMIC - based on current card positions.
  /// No permanent reveal. This method is kept for future permanent reveal abilities.
  void _updateScoutVisibility(int row, int col, String playerId) {
    if (_currentMatch == null) return;

    // If this is the local player, permanently reveal enemy base lane(s)
    if (playerId == _currentMatch!.player.id) {
      final lanesToReveal = <int>{};

      // Owning the middle tile reveals that lane's base permanently
      if (row == 1) {
        lanesToReveal.add(col);
      }

      // Scouts in middle row also reveal adjacent lanes once
      final hasScout = _currentMatch!.board
          .getTile(row, col)
          .cards
          .any(
            (c) =>
                c.isAlive &&
                c.abilities.contains('scout') &&
                c.ownerId == playerId,
          );
      if (hasScout && row == 1) {
        lanesToReveal.add(col);
        if (col > 0) lanesToReveal.add(col - 1);
        if (col < 2) lanesToReveal.add(col + 1);
      }

      for (final laneCol in lanesToReveal) {
        final lanePos = LanePosition.values[laneCol];
        _currentMatch!.revealedEnemyBaseLanes.add(lanePos);
      }
    }
  }

  /// Log a summary of the current board state for debugging
  void _logBoardStateSummary() {
    if (_currentMatch == null) return;

    final match = _currentMatch!;
    final laneNames = ['West', 'Center', 'East'];

    _log('\n📊 ═══ BOARD STATE ═══');
    _log(
      '💎 Crystals: Player ${match.player.crystalHP} HP | Opponent ${match.opponent.crystalHP} HP',
    );
    _log(
      '🃏 Hands: Player ${match.player.hand.length} cards | Opponent ${match.opponent.hand.length} cards',
    );

    for (int col = 0; col < 3; col++) {
      final laneName = laneNames[col];
      final buffer = StringBuffer();
      buffer.write('  $laneName: ');

      // Enemy base (row 0)
      final enemyBase = match.board.getTile(0, col);
      final enemyCards = enemyBase.cards.where((c) => c.isAlive).toList();
      if (enemyCards.isNotEmpty) {
        buffer.write(
          'EB[${enemyCards.map((c) => '${c.name}:${c.currentHealth}/${c.health}').join(', ')}] ',
        );
      }

      // Middle (row 1)
      final middle = match.board.getTile(1, col);
      final middleCards = middle.cards.where((c) => c.isAlive).toList();
      if (middleCards.isNotEmpty) {
        buffer.write(
          'M[${middleCards.map((c) => '${c.name}:${c.currentHealth}/${c.health}').join(', ')}] ',
        );
      }

      // Player base (row 2)
      final playerBase = match.board.getTile(2, col);
      final playerCards = playerBase.cards.where((c) => c.isAlive).toList();
      if (playerCards.isNotEmpty) {
        buffer.write(
          'PB[${playerCards.map((c) => '${c.name}:${c.currentHealth}/${c.health}').join(', ')}]',
        );
      }

      if (enemyCards.isNotEmpty ||
          middleCards.isNotEmpty ||
          playerCards.isNotEmpty) {
        _log(buffer.toString());
      }
    }

    // Relic status
    if (!match.relicManager.isRelicClaimed) {
      _log('🏺 Relic: Unclaimed (hidden)');
    } else {
      _log(
        '🏺 Relic: Claimed by ${match.relicManager.relicClaimedBy == match.player.id ? "Player" : "Opponent"}',
      );
    }

    // Fog of war status
    final revealed = match.revealedEnemyBaseLanes.map((l) => l.name).join(', ');
    _log('👁️ Revealed enemy bases: ${revealed.isEmpty ? "None" : revealed}');
    _log('═══════════════════════\n');
  }

  /// TYC3: Calculate lane buffs (damage/shield) from Inspire/Command/Fortify
  /// For TYC3, 'lane' means column.
  ({int damage, int shield}) calculateLaneBuffsTYC3(int col, String playerId) {
    if (_currentMatch == null) return (damage: 0, shield: 0);

    int damage = 0;
    int shield = 0;

    // Iterate all 3 rows in this column
    for (int r = 0; r < 3; r++) {
      final tile = _currentMatch!.board.getTile(r, col);
      // Get player's cards on this tile
      final myCards = tile.cards.where(
        (c) => c.isAlive && c.ownerId == playerId,
      );

      for (final card in myCards) {
        for (final ability in card.abilities) {
          if (ability.startsWith('inspire_')) {
            damage += int.tryParse(ability.split('_').last) ?? 0;
          }
          if (ability.startsWith('fortify_')) {
            shield += int.tryParse(ability.split('_').last) ?? 0;
          }
          // command_ is now tile-local (handled by calculateTileCommandBonus)
        }
      }
    }
    return (damage: damage, shield: shield);
  }

  /// TYC3: Calculate command bonus for a unit from adjacent friendly units on the same tile
  /// command_1 = +2 damage bonus to other units on the same tile
  int calculateTileCommandBonus(GameCard attacker, int row, int col) {
    if (_currentMatch == null) return 0;

    final tile = _currentMatch!.board.getTile(row, col);
    int bonus = 0;

    // Get other friendly cards on this tile (not the attacker itself)
    final friendlyCards = tile.cards.where(
      (c) => c.isAlive && c.ownerId == attacker.ownerId && c != attacker,
    );

    for (final card in friendlyCards) {
      for (final ability in card.abilities) {
        if (ability.startsWith('command_')) {
          // command_1 = +2, command_2 = +4, etc.
          final level = int.tryParse(ability.split('_').last) ?? 0;
          bonus += level * 2;
        }
      }
    }

    return bonus;
  }

  /// TYC3: Calculate motivate bonus for a unit from Commander cards on same tile and adjacent tiles
  /// motivate_1 = +1 damage and +1 health to same-type allies on same tile and adjacent tiles
  ({int damage, int health}) calculateMotivateBonus(
    GameCard card,
    int row,
    int col,
  ) {
    if (_currentMatch == null) return (damage: 0, health: 0);

    int damageBonus = 0;
    int healthBonus = 0;

    // Check same tile first
    final sameTile = _currentMatch!.board.getTile(row, col);
    final sameTileCards = sameTile.cards.where(
      (c) => c.isAlive && c.ownerId == card.ownerId && c.id != card.id,
    );

    for (final adjacentCard in sameTileCards) {
      for (final ability in adjacentCard.abilities) {
        if (ability.startsWith('motivate_')) {
          final level = int.tryParse(ability.split('_').last) ?? 0;

          // Commander motivates units of the same family as the Commander
          if (adjacentCard.family != null &&
              card.family != null &&
              adjacentCard.family == card.family) {
            damageBonus += level;
            healthBonus += level;
          }
        }
      }
    }

    // Check adjacent tiles (left, right, above, below)
    final adjacentPositions = [
      (row: row, col: col - 1), // Left
      (row: row, col: col + 1), // Right
      (row: row - 1, col: col), // Above
      (row: row + 1, col: col), // Below
    ];

    for (final pos in adjacentPositions) {
      // Check if position is within board bounds (3x3 grid)
      if (pos.row < 0 || pos.row >= 3 || pos.col < 0 || pos.col >= 3) {
        continue;
      }

      final tile = _currentMatch!.board.getTile(pos.row, pos.col);

      // Get friendly cards on this adjacent tile
      final friendlyCards = tile.cards.where(
        (c) => c.isAlive && c.ownerId == card.ownerId,
      );

      for (final adjacentCard in friendlyCards) {
        for (final ability in adjacentCard.abilities) {
          if (ability.startsWith('motivate_')) {
            final level = int.tryParse(ability.split('_').last) ?? 0;

            // Commander motivates units of the same family as the Commander
            if (adjacentCard.family != null &&
                card.family != null &&
                adjacentCard.family == card.family) {
              damageBonus += level;
              healthBonus += level;
            }
          }
        }
      }
    }

    return (damage: damageBonus, health: healthBonus);
  }

  /// TYC3: Attack a target card
  /// Returns the AttackResult, or null if attack is invalid
  AttackResult? attackCardTYC3(
    GameCard attacker,
    GameCard target,
    int attackerRow,
    int attackerCol,
    int targetRow,
    int targetCol,
  ) {
    if (_currentMatch == null) return null;
    if (!useTurnBasedSystem) return null;

    // Spies cannot perform normal attacks - they only assassinate on enemy base entry
    if (_isSpyCard(attacker)) {
      _log(
        '❌ Spies cannot attack directly - move to enemy base to assassinate',
      );
      return null;
    }

    final lockDetails = _getAttackLockDetails(
      attacker,
      attackerRow,
      attackerCol,
    );
    if (lockDetails != null) {
      final owner = _ownerLabel(attacker.ownerId);
      final sources = _formatSources(lockDetails.sources);
      final consumedSource = _consumeChargeFromFirstSource(
        lockDetails.sources,
        lockDetails.ability,
      );
      if (consumedSource != null) {
        _log(
          '🔋 ${consumedSource.name} consumes its ${lockDetails.ability} charge (remaining: ${_abilityChargesRemaining(consumedSource, lockDetails.ability, defaultCharges: 0)})',
        );
      }
      _log(
        '⛔ [$owner] ${attacker.name} cannot attack: ${lockDetails.reason}${sources.isNotEmpty ? " (blocked by: $sources)" : ""}',
      );
      return null;
    }

    // Fog of war check: Player cannot attack into unrevealed enemy base (row 0)
    final isPlayerAttacker = attacker.ownerId == _currentMatch!.player.id;
    if (isPlayerAttacker && targetRow == 0) {
      // Dynamic fog of war: check if player has visibility
      // Include hiddenSpies - spies have regular vision like any other unit
      final playerId = _currentMatch!.player.id;
      final middleTile = _currentMatch!.board.getTile(1, targetCol);
      final playerHasMiddleCard =
          middleTile.cards.any((c) => c.ownerId == playerId && c.isAlive) ||
          middleTile.hiddenSpies.any((c) => c.ownerId == playerId && c.isAlive);

      // Check if a scout can see this lane
      bool scoutCanSee = false;
      for (int scoutCol = 0; scoutCol < 3; scoutCol++) {
        final scoutTile = _currentMatch!.board.getTile(1, scoutCol);
        final hasScout = scoutTile.cards.any(
          (c) =>
              c.ownerId == playerId &&
              c.isAlive &&
              c.abilities.contains('scout'),
        );
        if (hasScout) {
          if (scoutCol == targetCol ||
              (scoutCol - targetCol).abs() == 1 ||
              scoutCol == 1) {
            scoutCanSee = true;
            break;
          }
        }
      }

      final tallCanSee = _tallCanSeeTile(
        viewerOwnerId: playerId,
        row: 0,
        col: targetCol,
      );

      if (!playerHasMiddleCard && !scoutCanSee && !tallCanSee) {
        _log('❌ Cannot attack into fog of war - no visibility in this lane');
        return null;
      }
    }

    // Get guards in target tile
    final targetTile = _currentMatch!.board.getTile(targetRow, targetCol);
    final guardsInTile = targetTile.cards
        .where((c) => c.isGuard && c.isAlive && c != target)
        .toList();

    // Validate the attack
    final error = _combatResolver.validateAttackTYC3(
      attacker: attacker,
      target: target,
      attackerRow: attackerRow,
      attackerCol: attackerCol,
      targetRow: targetRow,
      targetCol: targetCol,
      guardsInTargetTile: guardsInTile,
      allowCrossLane: allowCrossLaneAttack,
    );

    if (error != null) {
      _log('❌ Attack failed: $error');
      return null;
    }

    // Spend AP
    if (!attacker.spendAttackAP()) {
      _log('❌ Not enough AP to attack');
      return null;
    }

    final willApplyPoison =
        _isPoisoner(attacker) &&
        _abilityChargesRemaining(attacker, 'poisoner', defaultCharges: 1) > 0;
    if (willApplyPoison) {
      if (!_consumeAbilityCharge(attacker, 'poisoner', defaultCharges: 1)) {
        _log('❌ Poisoner has no poison charges');
      }
    }

    // Determine if player is attacking
    final isPlayerAttacking = isPlayerTurn;

    // Get terrain of target tile for terrain buff
    final tileTerrain = targetTile.terrain;

    // Log attack details
    final attackerOwner = attacker.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '⚔️ [$attackerOwner] ${attacker.name} (${attacker.currentHealth}/${attacker.health} HP) attacks ${target.name} (${target.currentHealth}/${target.health} HP)',
    );
    _log(
      '   Position: ($attackerRow,$attackerCol) → ($targetRow,$targetCol) | Terrain: ${tileTerrain ?? "none"}',
    );

    // Calculate lane buffs (Inspire, Fortify)
    final laneBuffs = calculateLaneBuffsTYC3(attackerCol, attacker.ownerId!);

    // Calculate tile command bonus (from adjacent units with command ability)
    final tileCommandBonus = calculateTileCommandBonus(
      attacker,
      attackerRow,
      attackerCol,
    );

    // Calculate motivate bonus (from Commander cards on same tile and adjacent tiles)
    final motivateBonus = calculateMotivateBonus(
      attacker,
      attackerRow,
      attackerCol,
    );

    // Resolve the attack (pass hero damage boost if player is attacking)
    final result = _combatResolver.resolveAttackTYC3(
      attacker,
      target,
      isPlayerAttacking: isPlayerAttacking,
      tileTerrain: tileTerrain,
      playerDamageBoost: isPlayerAttacking ? playerDamageBoost : 0,
      laneDamageBonus: laneBuffs.damage + tileCommandBonus,
      laneShieldBonus: laneBuffs.shield,
      commanderDamageBonus: motivateBonus.damage,
    );

    if (willApplyPoison && target.isAlive) {
      target.poisonTicksRemaining = 2;
      _log('☠️ ${attacker.name} poisons ${target.name} (2 turns)');
    }

    _log(
      '   Damage: ${result.damageDealt} → ${target.name} now ${target.currentHealth}/${target.health} HP',
    );

    if (result.modifiers.isNotEmpty) {
      for (final m in result.modifiers) {
        _log('     $m');
      }
    }

    final attackerTile = _currentMatch!.board.getTile(attackerRow, attackerCol);

    // Cleave is AOE and can hit hidden spies that share the tile.
    if (attacker.abilities.contains('cleave') && attacker.isAlive) {
      final cleaveTargets =
          <GameCard>[...targetTile.cards, ...targetTile.hiddenSpies].where(
            (c) =>
                c.isAlive && c.ownerId != attacker.ownerId && c.id != target.id,
          );

      final secondTarget = cleaveTargets.isNotEmpty
          ? cleaveTargets.first
          : null;
      if (secondTarget != null) {
        final damage = result.damageDealt;
        final hpBefore = secondTarget.currentHealth;
        final died = secondTarget.takeDamage(damage);
        final hpAfter = secondTarget.currentHealth;

        _log(
          '   🌀 Cleave hits ${secondTarget.name} for $damage damage (${hpBefore}→$hpAfter)',
        );

        if (died) {
          targetTile.addGravestone(
            Gravestone(
              cardName: secondTarget.name,
              deathLog: 'Cleave damage',
              ownerId: secondTarget.ownerId,
              turnCreated: _currentMatch!.turnNumber,
            ),
          );
          onCardDestroyed?.call(secondTarget);
          _removeCardFromTile(targetTile, secondTarget);
          _log('   💀 ${secondTarget.name} destroyed by cleave!');
        }
      }
    }

    // Lane Sweep: after attacking, hit all other enemies in the same lane (same column)
    // across all tiles for the same damage. Consumes only the normal attack AP.
    if (attacker.abilities.contains('lane_sweep') && attacker.isAlive) {
      for (int row = 0; row < 3; row++) {
        final tile = _currentMatch!.board.getTile(row, attackerCol);
        final enemies = <GameCard>[...tile.cards, ...tile.hiddenSpies].where(
          (c) =>
              c.isAlive && c.ownerId != attacker.ownerId && c.id != target.id,
        );

        for (final enemy in enemies.toList()) {
          final hpBefore = enemy.currentHealth;
          final died = enemy.takeDamage(result.damageDealt);
          final hpAfter = enemy.currentHealth;

          _log(
            '   🧹 Lane Sweep hits ${enemy.name} at ($row,$attackerCol) for ${result.damageDealt} ($hpBefore→$hpAfter)',
          );

          if (died) {
            tile.addGravestone(
              Gravestone(
                cardName: enemy.name,
                deathLog: 'Lane Sweep',
                ownerId: enemy.ownerId,
                turnCreated: _currentMatch!.turnNumber,
              ),
            );
            onCardDestroyed?.call(enemy);
            _removeCardFromTile(tile, enemy);
            _log('   💀 ${enemy.name} destroyed by Lane Sweep!');
          }
        }
      }
    }

    _applyPushBackAfterAttack(
      attacker: attacker,
      target: target,
      targetRow: targetRow,
      targetCol: targetCol,
    );

    // One-Side Attacker: from side lanes hits center + far side
    if (attacker.abilities.contains('one_side_attacker') && attacker.isAlive) {
      _applySideAttackerSplash(
        attacker: attacker,
        attackerCol: attackerCol,
        targetRow: targetRow,
        primaryTargetId: target.id,
        damage: result.damageDealt,
        isOneSide: true,
      );
    }

    // Two-Side Attacker: from center hits both sides; from side hits center
    if (attacker.abilities.contains('two_side_attacker') && attacker.isAlive) {
      _applySideAttackerSplash(
        attacker: attacker,
        attackerCol: attackerCol,
        targetRow: targetRow,
        primaryTargetId: target.id,
        damage: result.damageDealt,
        isOneSide: false,
      );
    }

    if (result.targetDied) {
      _log('   💀 ${target.name} destroyed!');

      // Create gravestone with battle summary
      final deathLog = result.getDetailedSummary(attacker.name, target.name);
      targetTile.addGravestone(
        Gravestone(
          cardName: target.name,
          deathLog: deathLog,
          ownerId: target.ownerId,
          turnCreated: _currentMatch!.turnNumber,
        ),
      );

      // Remove dead card from tile
      onCardDestroyed?.call(target);
      _removeCardFromTile(targetTile, target);

      // Melee attacker advances to target's tile after kill (if not ranged and attacker survived)
      // Only advance if no other enemy cards remain on the target tile
      // NEVER advance into enemy base (row 0 for player, row 2 for AI)
      if (!attacker.isRanged && !result.attackerDied && attacker.isAlive) {
        final isPlayerCard = attacker.ownerId == _currentMatch!.player.id;
        final isEnemyBase =
            (isPlayerCard && targetRow == 0) ||
            (!isPlayerCard && targetRow == 2);

        if (isEnemyBase) {
          if (_isSpyCard(attacker)) {
            _log('   🕵️ ${attacker.name} advances into enemy base');
            final fromTile = attackerTile;
            _removeCardFromTile(fromTile, attacker);
            _addCardToTile(targetTile, attacker);
            _triggerTrapIfPresent(attacker, targetRow, targetCol);
            if (!attacker.isAlive) return result;

            _triggerSpyOnEnemyBaseEntry(
              enteringCard: attacker,
              fromRow: attackerRow,
              fromCol: attackerCol,
              toRow: targetRow,
              toCol: targetCol,
            );
            return result;
          } else {
            _log('   ⚠️ ${attacker.name} cannot advance into enemy base');
            return result;
          }
        } else {
          final hasOtherEnemies = targetTile.cards.any(
            (c) => c.ownerId != attacker.ownerId && c.isAlive,
          );
          if (!hasOtherEnemies) {
            // Move attacker to target tile (free move after kill)
            _removeCardFromTile(attackerTile, attacker);
            _addCardToTile(targetTile, attacker);
            _log(
              '   🚶 ${attacker.name} advances to (${targetRow},${targetCol}) after kill',
            );

            _triggerTrapIfPresent(attacker, targetRow, targetCol);

            if (attacker.isAlive) {
              _triggerSpyOnEnemyBaseEntry(
                enteringCard: attacker,
                fromRow: attackerRow,
                fromCol: attackerCol,
                toRow: targetRow,
                toCol: targetCol,
              );
              if (!attacker.isAlive) return result;

              final finalPos = _applyBurningOnEntry(
                enteringCard: attacker,
                fromRow: attackerRow,
                fromCol: attackerCol,
                toRow: targetRow,
                toCol: targetCol,
              );
              if (!attacker.isAlive) {
                return result;
              }

              _applyFearOnEntry(
                enteringCard: attacker,
                row: finalPos.row,
                col: finalPos.col,
              );

              _applyMarshDrainOnEntry(
                enteringCard: attacker,
                row: finalPos.row,
                col: finalPos.col,
              );

              // Check for relic pickup at new tile
              _checkRelicPickup(finalPos.row, finalPos.col, attacker.ownerId!);

              // Update visibility (permanent lane reveal + scout)
              _updatePermanentVisibility(
                finalPos.row,
                finalPos.col,
                attacker.ownerId!,
              );
            }
          } else {
            _log(
              '   ⚠️ ${attacker.name} cannot advance - other enemies remain on tile',
            );
          }
        }
      }
    }
    if (result.retaliationDamage > 0 ||
        result.retaliationModifiers.isNotEmpty) {
      final retaliationNote = result.targetDied ? ' (before dying)' : '';
      _log(
        '   ↩️ Retaliation$retaliationNote: ${target.name} deals ${result.retaliationDamage} to ${attacker.name}',
      );
      if (result.retaliationModifiers.isNotEmpty) {
        for (final m in result.retaliationModifiers) {
          _log('     $m');
        }
      }
    }
    if (result.thornsDamage > 0) {
      _log(
        '   🌿 Thorns: ${target.name} reflects ${result.thornsDamage} damage to ${attacker.name}',
      );
    }
    if (result.retaliationDamage > 0 || result.thornsDamage > 0) {
      _log(
        '   ${attacker.name} now ${attacker.currentHealth}/${attacker.health} HP',
      );
      if (result.attackerDied) {
        _log('   💀 ${attacker.name} destroyed!');

        // Create gravestone with battle summary
        final deathLog = result.getDetailedSummary(attacker.name, target.name);
        attackerTile.addGravestone(
          Gravestone(
            cardName: attacker.name,
            deathLog: deathLog,
            ownerId: attacker.ownerId,
            turnCreated: _currentMatch!.turnNumber,
          ),
        );

        // Remove dead attacker from tile
        onCardDestroyed?.call(attacker);
        _removeCardFromTile(attackerTile, attacker);
      }
    }
    _log('   AP remaining: ${attacker.currentAP}/${attacker.maxAP}');

    // Store combat result for PvP sync (so opponent can see the result dialog)
    _currentMatch!.lastCombatResult = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${attacker.id}_${target.id}',
      isBaseAttack: false,
      isHeal: false,
      attackerName: attacker.name,
      targetName: target.name,
      targetId: target.id,
      damageDealt: result.damageDealt,
      healAmount: 0,
      retaliationDamage: result.retaliationDamage,
      targetDied: result.targetDied,
      attackerDied: result.attackerDied,
      targetHpBefore:
          target.currentHealth + result.damageDealt, // Reconstruct before HP
      targetHpAfter: target.currentHealth,
      attackerHpBefore:
          attacker.currentHealth +
          result.retaliationDamage +
          result.thornsDamage,
      attackerHpAfter: attacker.currentHealth,
      laneCol: targetCol,
      attackerOwnerId: attacker.ownerId ?? '',
      attackerId: attacker.id,
      attackerRow: attackerRow,
      attackerCol: attackerCol,
      targetRow: targetRow,
      targetCol: targetCol,
    );

    // Track enemy units that attacked player for fog of war (visible next turn)
    if (!isPlayerAttacking && target.ownerId == _currentMatch!.player.id) {
      _currentMatch!.recentlyAttackedEnemyUnits[attacker.id] =
          _currentMatch!.turnNumber;
    }

    return result;
  }

  /// TYC3: Preview an attack without executing it
  /// Returns predicted AttackResult with damage values
  AttackResult previewAttackTYC3(
    GameCard attacker,
    GameCard target,
    int targetRow,
    int targetCol,
  ) {
    // Get terrain of target tile for terrain buff preview
    final targetTile = _currentMatch!.board.getTile(targetRow, targetCol);
    final tileTerrain = targetTile.terrain;

    // Find attacker column (it might be different from targetCol if moving or ranged)
    int attackerCol = targetCol;
    // Try to find attacker on board to get correct column
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        if (_currentMatch!.board
            .getTile(r, c)
            .cards
            .any((card) => card.id == attacker.id)) {
          attackerCol = c;
          break;
        }
      }
    }

    // Calculate lane buffs
    final laneBuffs = calculateLaneBuffsTYC3(attackerCol, attacker.ownerId!);

    // Find attacker row for tile command bonus
    int attackerRow = 1; // Default to middle
    for (int r = 0; r < 3; r++) {
      if (_currentMatch!.board
          .getTile(r, attackerCol)
          .cards
          .any((card) => card.id == attacker.id)) {
        attackerRow = r;
        break;
      }
    }

    // Calculate tile command bonus (from adjacent units with command ability)
    final tileCommandBonus = calculateTileCommandBonus(
      attacker,
      attackerRow,
      attackerCol,
    );

    // Calculate motivate bonus (from Commander cards on same tile and adjacent tiles)
    final motivateBonus = calculateMotivateBonus(
      attacker,
      attackerRow,
      attackerCol,
    );

    return _combatResolver.previewAttackTYC3(
      attacker,
      target,
      isPlayerAttacking: isPlayerTurn,
      tileTerrain: tileTerrain,
      playerDamageBoost: isPlayerTurn ? playerDamageBoost : 0,
      laneDamageBonus: laneBuffs.damage + tileCommandBonus,
      laneShieldBonus: laneBuffs.shield,
      commanderDamageBonus: motivateBonus.damage,
    );
  }

  /// TYC3: Get valid attack targets for a card
  List<GameCard> getValidTargetsTYC3(GameCard attacker, int row, int col) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];

    // Spies cannot attack - they only assassinate on enemy base entry
    if (_isSpyCard(attacker)) return [];

    final lockReason = _getAttackLockReason(attacker, row, col);
    if (lockReason != null) return [];

    // Check if attacker has AP to attack
    if (attacker.currentAP < attacker.attackAPCost) return [];

    // Determine if attacker is a player card based on ownerId
    final isPlayerCard = attacker.ownerId == _currentMatch!.player.id;

    // Build board cards array
    final boardCards = <List<List<GameCard>>>[];
    for (int r = 0; r < 3; r++) {
      final rowCards = <List<GameCard>>[];
      for (int c = 0; c < 3; c++) {
        final tile = _currentMatch!.board.getTile(r, c);
        final visible = tile.cards.where((card) => card.isAlive).toList();
        if (attacker.ownerId != null &&
            _isTileRevealedByWatcherForOwner(
              viewerOwnerId: attacker.ownerId!,
              row: r,
              col: c,
            )) {
          visible.addAll(
            tile.hiddenSpies.where(
              (s) => s.isAlive && s.ownerId != attacker.ownerId,
            ),
          );
        }
        rowCards.add(visible);
      }
      boardCards.add(rowCards);
    }

    return _combatResolver.getValidTargetsTYC3(
      attacker: attacker,
      attackerRow: row,
      attackerCol: col,
      boardCards: boardCards,
      isPlayerCard: isPlayerCard,
      allowCrossLane: allowCrossLaneAttack,
    );
  }

  /// TYC3: Attack the enemy base directly (if no guards blocking)
  /// Returns damage dealt, or 0 if attack failed
  int attackBaseTYC3(GameCard attacker, int attackerRow, int attackerCol) {
    if (_currentMatch == null) return 0;
    if (!useTurnBasedSystem) return 0;

    // Check if attacker can attack
    if (!attacker.canAttack()) {
      _log('❌ Not enough AP to attack base');
      return 0;
    }

    final lockDetails = _getAttackLockDetails(
      attacker,
      attackerRow,
      attackerCol,
    );
    if (lockDetails != null) {
      final owner = _ownerLabel(attacker.ownerId);
      final sources = _formatSources(lockDetails.sources);
      _log(
        '⛔ [$owner] ${attacker.name} cannot attack base: ${lockDetails.reason}${sources.isNotEmpty ? " (blocked by: $sources)" : ""}',
      );
      return 0;
    }

    // Determine target base row based on attacker's owner
    final isPlayerAttacking = attacker.ownerId == _currentMatch!.player.id;
    final targetBaseRow = isPlayerAttacking ? 0 : 2;

    // Fog of war check: Player cannot attack enemy base if lane not revealed
    if (isPlayerAttacking) {
      // Dynamic fog of war: check if player has visibility
      // Include hiddenSpies - spies have regular vision like any other unit
      final playerId = _currentMatch!.player.id;
      final middleTile = _currentMatch!.board.getTile(1, attackerCol);
      final playerHasMiddleCard =
          middleTile.cards.any((c) => c.ownerId == playerId && c.isAlive) ||
          middleTile.hiddenSpies.any((c) => c.ownerId == playerId && c.isAlive);

      // Check if a scout can see this lane
      bool scoutCanSee = false;
      for (int scoutCol = 0; scoutCol < 3; scoutCol++) {
        final scoutTile = _currentMatch!.board.getTile(1, scoutCol);
        final hasScout = scoutTile.cards.any(
          (c) =>
              c.ownerId == playerId &&
              c.isAlive &&
              c.abilities.contains('scout'),
        );
        if (hasScout) {
          if (scoutCol == attackerCol ||
              (scoutCol - attackerCol).abs() == 1 ||
              scoutCol == 1) {
            scoutCanSee = true;
            break;
          }
        }
      }

      final tallCanSee = _tallCanSeeTile(
        viewerOwnerId: playerId,
        row: 0,
        col: attackerCol,
      );

      if (!playerHasMiddleCard && !scoutCanSee && !tallCanSee) {
        _log(
          '❌ Cannot attack base through fog of war - no visibility in this lane',
        );
        return 0;
      }
    }

    // Check range to base
    final distance = (targetBaseRow - attackerRow).abs();
    if (distance > attacker.attackRange) {
      _log(
        '❌ Base is out of range (range: ${attacker.attackRange}, distance: $distance)',
      );
      return 0;
    }

    // Check for guards in the path (enemy base tile in same column)
    final baseTile = _currentMatch!.board.getTile(targetBaseRow, attackerCol);
    final guards = baseTile.cards.where((c) => c.isGuard && c.isAlive).toList();
    if (guards.isNotEmpty) {
      _log(
        '❌ Must destroy guards first: ${guards.map((g) => g.name).join(", ")}',
      );
      return 0;
    }

    // Check for any enemy cards in base tile
    if (baseTile.cards.any((c) => c.isAlive)) {
      _log('❌ Must destroy all enemy cards in base tile first');
      return 0;
    }

    // Spend AP
    if (!attacker.spendAttackAP()) {
      _log('❌ Not enough AP to attack base');
      return 0;
    }

    // Calculate damage with terrain buff
    int damage = attacker.currentDamage;
    final tileTerrain = baseTile.terrain;
    int terrainBonus = 0;
    if (tileTerrain != null && attacker.element == tileTerrain) {
      terrainBonus = 1;
      damage += terrainBonus;
    }

    // Apply lane buffs (Inspire, Command)
    final laneBuffs = calculateLaneBuffsTYC3(attackerCol, attacker.ownerId!);
    damage += laneBuffs.damage;

    if (isPlayerAttacking && playerDamageBoost > 0) {
      damage += playerDamageBoost;
    }

    final targetPlayer = isPlayerAttacking
        ? _currentMatch!.opponent
        : _currentMatch!.player;

    final defenderOwnerId = targetPlayer.id;
    final interceptor = _selectMegaTauntInterceptor(
      defenderOwnerId: defenderOwnerId,
      baseRow: targetBaseRow,
      baseCol: attackerCol,
      attacker: attacker,
    );

    if (interceptor != null) {
      final tile = _currentMatch!.board.getTile(
        interceptor.row,
        interceptor.col,
      );
      final hpBefore = interceptor.card.currentHealth;
      final died = interceptor.card.takeDamage(damage);
      final hpAfter = interceptor.card.currentHealth;

      _log(
        '🛡️ Mega Taunt: ${interceptor.card.name} intercepts base attack for ${targetPlayer.name} ($damage damage)',
      );

      if (died) {
        tile.addGravestone(
          Gravestone(
            cardName: interceptor.card.name,
            deathLog: 'Intercepted base attack',
            ownerId: interceptor.card.ownerId,
            turnCreated: _currentMatch!.turnNumber,
          ),
        );
        onCardDestroyed?.call(interceptor.card);
        _removeCardFromTile(tile, interceptor.card);
      }

      _currentMatch!.lastCombatResult = SyncedCombatResult(
        id: '${DateTime.now().millisecondsSinceEpoch}_${attacker.id}_mega_taunt',
        isBaseAttack: true,
        isHeal: false,
        attackerName: attacker.name,
        targetName: interceptor.card.name,
        targetId: interceptor.card.id,
        damageDealt: damage,
        healAmount: 0,
        retaliationDamage: 0,
        targetDied: died,
        attackerDied: false,
        targetHpBefore: hpBefore,
        targetHpAfter: hpAfter,
        attackerHpBefore: attacker.currentHealth,
        attackerHpAfter: attacker.currentHealth,
        laneCol: attackerCol,
        attackerOwnerId: attacker.ownerId ?? '',
        attackerId: attacker.id,
        attackerRow: attackerRow,
        attackerCol: attackerCol,
        targetRow: interceptor.row,
        targetCol: interceptor.col,
      );

      if (!isPlayerAttacking) {
        _currentMatch!.recentlyAttackedEnemyUnits[attacker.id] =
            _currentMatch!.turnNumber;
      }

      return damage;
    }

    targetPlayer.takeBaseDamage(damage);

    _log(
      '💥 ${attacker.name} attacks ${targetPlayer.name}\'s base for $damage damage!${terrainBonus > 0 ? " (+$terrainBonus terrain)" : ""}',
    );
    _log('   Base HP: ${targetPlayer.baseHP}/${Player.maxBaseHP}');
    _log('   AP remaining: ${attacker.currentAP}/${attacker.maxAP}');

    // Check for game over
    if (targetPlayer.isDefeated) {
      _currentMatch!.currentPhase = MatchPhase.gameOver;
      _currentMatch!.winnerId = isPlayerAttacking
          ? _currentMatch!.player.id
          : _currentMatch!.opponent.id;
      _log('🏆 GAME OVER! ${isPlayerAttacking ? "Player" : "Opponent"} wins!');

      // Capture final snapshot for replay
      _currentMatch!.history.add(
        TurnSnapshot.fromState(matchState: _currentMatch!),
      );
    }

    // Store combat result for PvP sync (so opponent can see the base attack result)
    _currentMatch!.lastCombatResult = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${attacker.id}_base',
      isBaseAttack: true,
      isHeal: false,
      attackerName: attacker.name,
      targetName: '${targetPlayer.name}\'s Base',
      damageDealt: damage,
      healAmount: 0,
      retaliationDamage: 0,
      targetDied: targetPlayer.isDefeated,
      attackerDied: false,
      targetHpBefore: targetPlayer.baseHP + damage,
      targetHpAfter: targetPlayer.baseHP,
      attackerHpBefore: attacker.currentHealth,
      attackerHpAfter: attacker.currentHealth,
      laneCol: attackerCol,
      attackerOwnerId: attacker.ownerId ?? '',
      attackerId: attacker.id,
      attackerRow: attackerRow,
      attackerCol: attackerCol,
      targetRow: targetBaseRow,
      targetCol: attackerCol,
    );

    // Track enemy units that attacked player base for fog of war (visible next turn)
    if (!isPlayerAttacking) {
      _currentMatch!.recentlyAttackedEnemyUnits[attacker.id] =
          _currentMatch!.turnNumber;
    }

    return damage;
  }

  int _getMedicHealAmount(GameCard card) {
    for (final a in card.abilities) {
      if (a.startsWith('medic_')) {
        return int.tryParse(a.split('_').last) ?? 0;
      }
    }
    return 0;
  }

  bool _isMedic(GameCard card) => _getMedicHealAmount(card) > 0;

  bool _isEnhancer(GameCard card) => card.abilities.contains('enhancer');

  bool _isSwitcher(GameCard card) => card.abilities.contains('switcher');

  bool _isResetter(GameCard card) => card.abilities.contains('resetter');

  /// TYC3: Get all heal targets reachable with current AP (move + heal).
  /// For now, medics can only heal friendly units on the SAME TILE.
  List<({GameCard target, int row, int col, int moveCost})>
  getReachableHealTargets(GameCard card, int fromRow, int fromCol) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];
    if (!_isMedic(card)) return [];

    if (card.currentAP < card.attackAPCost) return [];

    final targets = <({GameCard target, int row, int col, int moveCost})>[];

    // For now healing is only allowed on the SAME TILE (see healCardTYC3).
    final positions = [(row: fromRow, col: fromCol, apCost: 0)];

    _log(
      '🏥 Medic ${card.name} at ($fromRow,$fromCol) AP=${card.currentAP}, checking ${positions.length} positions',
    );

    for (final pos in positions) {
      final apAfterMove = card.currentAP - pos.apCost;
      if (apAfterMove < card.attackAPCost) {
        _log(
          '   Skip (${pos.row},${pos.col}): not enough AP after move ($apAfterMove < ${card.attackAPCost})',
        );
        continue;
      }

      final tile = _currentMatch!.board.getTile(pos.row, pos.col);
      _log('   Tile (${pos.row},${pos.col}): ${tile.cards.length} cards');

      for (final c in tile.cards) {
        final isAlive = c.isAlive;
        final isFriendly = c.ownerId == card.ownerId;
        final isNotSelf = c.id != card.id;
        final isInjured = c.currentHealth < c.health;
        _log(
          '      ${c.name}: alive=$isAlive, friendly=$isFriendly, notSelf=$isNotSelf, injured=$isInjured (${c.currentHealth}/${c.health})',
        );
      }

      final friendlyAliveNotSelf = tile.cards
          .where(
            (c) => c.isAlive && c.ownerId == card.ownerId && c.id != card.id,
          )
          .toList();

      for (final t in friendlyAliveNotSelf) {
        if (!targets.any((e) => e.target.id == t.id)) {
          targets.add((
            target: t,
            row: pos.row,
            col: pos.col,
            moveCost: pos.apCost,
          ));
          _log('   ✓ Found heal target: ${t.name}');
        }
      }
    }

    _log('🏥 Total heal targets: ${targets.length}');
    return targets;
  }

  /// TYC3: Heal a friendly unit with a medic card.
  /// Returns the synced result (for UI + online sync), or null if invalid.
  SyncedCombatResult? healCardTYC3(
    GameCard healer,
    GameCard target,
    int healerRow,
    int healerCol,
    int targetRow,
    int targetCol,
  ) {
    if (_currentMatch == null) return null;
    if (!useTurnBasedSystem) return null;

    final healAmount = _getMedicHealAmount(healer);
    if (healAmount <= 0) {
      _log('❌ Heal failed: ${healer.name} is not a medic');
      return null;
    }
    if (!healer.canAttack()) {
      _log('❌ Heal failed: Not enough AP');
      return null;
    }
    if (!target.isAlive) {
      _log('❌ Heal failed: Target is dead');
      return null;
    }
    if (target.ownerId != healer.ownerId) {
      _log('❌ Heal failed: Cannot heal enemy units');
      return null;
    }

    // Must be on the same tile.
    if (healerRow != targetRow || healerCol != targetCol) {
      _log('❌ Heal failed: Medic must be on the same tile as target');
      return null;
    }

    // Spend AP (reuse attack AP for heal action).
    if (!healer.spendAttackAP()) {
      _log('❌ Heal failed: Not enough AP');
      return null;
    }

    final before = target.currentHealth;
    target.currentHealth = (target.currentHealth + healAmount).clamp(
      0,
      target.health,
    );
    final after = target.currentHealth;
    final actualHeal = after - before;

    final healerOwner = healer.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '🩺 [$healerOwner] ${healer.name} heals ${target.name} for $actualHeal (HP: $before → $after)',
    );
    _log('   AP remaining: ${healer.currentAP}/${healer.maxAP}');

    final result = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${healer.id}_${target.id}_heal',
      isBaseAttack: false,
      isHeal: true,
      attackerName: healer.name,
      targetName: target.name,
      targetId: target.id,
      damageDealt: 0,
      healAmount: actualHeal,
      retaliationDamage: 0,
      targetDied: false,
      attackerDied: false,
      targetHpBefore: before,
      targetHpAfter: after,
      attackerHpBefore: healer.currentHealth,
      attackerHpAfter: healer.currentHealth,
      laneCol: targetCol,
      attackerOwnerId: healer.ownerId ?? '',
      attackerId: healer.id,
      attackerRow: healerRow,
      attackerCol: healerCol,
      targetRow: targetRow,
      targetCol: targetCol,
    );

    _currentMatch!.lastCombatResult = result;
    return result;
  }

  /// TYC3: Refresh consumable ability charges on a friendly unit, then self-destruct.
  SyncedCombatResult? resetCardTYC3(
    GameCard resetter,
    GameCard target,
    int resetterRow,
    int resetterCol,
    int targetRow,
    int targetCol,
  ) {
    if (_currentMatch == null) return null;
    if (!useTurnBasedSystem) return null;

    if (!_isResetter(resetter)) {
      _log('❌ Reset failed: ${resetter.name} is not a resetter');
      return null;
    }
    if (!resetter.canAttack()) {
      _log('❌ Reset failed: Not enough AP');
      return null;
    }
    if (!target.isAlive) {
      _log('❌ Reset failed: Target is dead');
      return null;
    }
    if (target.ownerId != resetter.ownerId) {
      _log('❌ Reset failed: Cannot reset enemy units');
      return null;
    }
    if (resetter.id == target.id) {
      _log('❌ Reset failed: Cannot reset self');
      return null;
    }

    if (resetterRow != targetRow || resetterCol != targetCol) {
      _log('❌ Reset failed: Resetter must be on the same tile as target');
      return null;
    }

    if (!resetter.spendAttackAP()) {
      _log('❌ Reset failed: Not enough AP');
      return null;
    }

    const consumableAbilities = <String>{
      'fear',
      'paralyze',
      'glue',
      'silence',
      'shaco',
      'barrier',
    };

    final refreshed = <String>[];
    for (final ability in consumableAbilities) {
      if (!target.abilities.contains(ability)) continue;
      final before = _abilityChargesRemaining(target, ability);
      _grantAbilityCharge(target, ability, amount: 1);
      final after = _abilityChargesRemaining(target, ability);
      refreshed.add('$ability ($before→$after)');
    }

    final resetterOwner = resetter.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '♻️ [$resetterOwner] ${resetter.name} refreshes ${target.name}${refreshed.isNotEmpty ? " (+1 charge: ${refreshed.join(", ")})" : " (no consumable abilities found)"}',
    );

    // Self-destruct (RIP chip)
    final tile = _currentMatch!.board.getTile(resetterRow, resetterCol);
    tile.addGravestone(
      Gravestone(
        cardName: resetter.name,
        deathLog: 'RIP chip: self-destructed after resetting ${target.name}',
        ownerId: resetter.ownerId,
        turnCreated: _currentMatch!.turnNumber,
      ),
    );
    onCardDestroyed?.call(resetter);
    _removeCardFromTile(tile, resetter);
    resetter.currentHealth = 0;
    _log('   💀 ${resetter.name} self-destructs!');

    final result = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${resetter.id}_${target.id}_reset',
      isBaseAttack: false,
      isHeal: false,
      attackerName: resetter.name,
      targetName: target.name,
      targetId: target.id,
      damageDealt: 0,
      healAmount: 0,
      retaliationDamage: 0,
      targetDied: false,
      attackerDied: true,
      targetHpBefore: target.currentHealth,
      targetHpAfter: target.currentHealth,
      attackerHpBefore: resetter.health,
      attackerHpAfter: 0,
      laneCol: targetCol,
      attackerOwnerId: resetter.ownerId ?? '',
      attackerId: resetter.id,
      attackerRow: resetterRow,
      attackerCol: resetterCol,
      targetRow: targetRow,
      targetCol: targetCol,
    );

    _currentMatch!.lastCombatResult = result;
    return result;
  }

  /// TYC3: Get all enhance targets reachable (friendly units on same tile).
  List<({GameCard target, int row, int col, int moveCost})>
  getReachableEnhanceTargets(GameCard card, int fromRow, int fromCol) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];
    if (!_isEnhancer(card)) return [];

    if (card.currentAP < card.attackAPCost) return [];

    final targets = <({GameCard target, int row, int col, int moveCost})>[];
    final tile = _currentMatch!.board.getTile(fromRow, fromCol);

    for (final friendly in tile.cards) {
      if (!friendly.isAlive) continue;
      if (friendly.ownerId != card.ownerId) continue;
      if (friendly.id == card.id) continue;

      targets.add((target: friendly, row: fromRow, col: fromCol, moveCost: 0));
    }

    return targets;
  }

  /// TYC3: Enhance a friendly unit (double damage), then self-destruct.
  SyncedCombatResult? enhanceCardTYC3(
    GameCard enhancer,
    GameCard target,
    int enhancerRow,
    int enhancerCol,
    int targetRow,
    int targetCol,
  ) {
    if (_currentMatch == null) return null;
    if (!useTurnBasedSystem) return null;

    if (!_isEnhancer(enhancer)) {
      _log('❌ Enhance failed: ${enhancer.name} is not an enhancer');
      return null;
    }
    if (!enhancer.canAttack()) {
      _log('❌ Enhance failed: Not enough AP');
      return null;
    }
    if (!target.isAlive) {
      _log('❌ Enhance failed: Target is dead');
      return null;
    }
    if (target.ownerId != enhancer.ownerId) {
      _log('❌ Enhance failed: Cannot enhance enemy units');
      return null;
    }
    if (enhancer.id == target.id) {
      _log('❌ Enhance failed: Cannot enhance self');
      return null;
    }

    if (enhancerRow != targetRow || enhancerCol != targetCol) {
      _log('❌ Enhance failed: Enhancer must be on the same tile as target');
      return null;
    }

    if (!enhancer.spendAttackAP()) {
      _log('❌ Enhance failed: Not enough AP');
      return null;
    }

    final damageBefore = target.damage;
    target.health = target.health; // Keep health unchanged
    // Double the base damage by modifying the terrainAffinityDamageBonus
    // (since damage is final, we use the bonus field which stacks)
    target.terrainAffinityDamageBonus += damageBefore;
    final damageAfter = target.damage + target.terrainAffinityDamageBonus;

    final enhancerOwner = enhancer.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '⚡ [$enhancerOwner] ${enhancer.name} enhances ${target.name} (DMG: $damageBefore → $damageAfter)',
    );

    // Self-destruct
    final tile = _currentMatch!.board.getTile(enhancerRow, enhancerCol);
    tile.addGravestone(
      Gravestone(
        cardName: enhancer.name,
        deathLog: 'Self-destructed after enhancing ${target.name}',
        ownerId: enhancer.ownerId,
        turnCreated: _currentMatch!.turnNumber,
      ),
    );
    onCardDestroyed?.call(enhancer);
    _removeCardFromTile(tile, enhancer);
    enhancer.currentHealth = 0;
    _log('   💀 ${enhancer.name} self-destructs!');

    final result = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${enhancer.id}_${target.id}_enhance',
      isBaseAttack: false,
      isHeal: false,
      attackerName: enhancer.name,
      targetName: target.name,
      targetId: target.id,
      damageDealt: 0,
      healAmount: 0,
      retaliationDamage: 0,
      targetDied: false,
      attackerDied: true,
      targetHpBefore: target.currentHealth,
      targetHpAfter: target.currentHealth,
      attackerHpBefore: enhancer.health,
      attackerHpAfter: 0,
      laneCol: targetCol,
      attackerOwnerId: enhancer.ownerId ?? '',
      attackerId: enhancer.id,
      attackerRow: enhancerRow,
      attackerCol: enhancerCol,
      targetRow: targetRow,
      targetCol: targetCol,
    );

    _currentMatch!.lastCombatResult = result;
    return result;
  }

  /// TYC3: Get all switch target pairs within 1 tile distance (same tile, adjacent tiles).
  List<({GameCard target1, GameCard target2, int row, int col})>
  getReachableSwitchTargets(GameCard card, int fromRow, int fromCol) {
    if (_currentMatch == null) return [];
    if (!useTurnBasedSystem) return [];
    if (!_isSwitcher(card)) return [];

    if (card.currentAP < card.attackAPCost) return [];

    // Collect all friendly units within 1 tile distance (same tile + adjacent tiles)
    final allFriendlies = <({GameCard card, int row, int col})>[];

    // Check tiles within 1 distance (orthogonal only: same, left, right, up, down)
    final tilesToCheck = [
      (row: fromRow, col: fromCol), // Same tile
      (row: fromRow, col: fromCol - 1), // Left
      (row: fromRow, col: fromCol + 1), // Right
      (row: fromRow - 1, col: fromCol), // Up/Back
      (row: fromRow + 1, col: fromCol), // Down/Forward
    ];

    for (final pos in tilesToCheck) {
      if (pos.row < 0 || pos.row >= 3 || pos.col < 0 || pos.col >= 3) continue;
      final tile = _currentMatch!.board.getTile(pos.row, pos.col);
      for (final c in tile.cards) {
        if (c.isAlive && c.ownerId == card.ownerId && c.id != card.id) {
          allFriendlies.add((card: c, row: pos.row, col: pos.col));
        }
      }
    }

    // If only 1 friendly found, allow swapping with the Switcher itself
    if (allFriendlies.length == 1) {
      final target = allFriendlies.first;
      return [
        (target1: card, target2: target.card, row: target.row, col: target.col),
      ];
    }

    // If 2+ friendlies, generate all pairs
    if (allFriendlies.length < 2) return [];

    final pairs = <({GameCard target1, GameCard target2, int row, int col})>[];
    for (int i = 0; i < allFriendlies.length; i++) {
      for (int j = i + 1; j < allFriendlies.length; j++) {
        // Use the row/col of the first target in the pair
        pairs.add((
          target1: allFriendlies[i].card,
          target2: allFriendlies[j].card,
          row: allFriendlies[i].row,
          col: allFriendlies[i].col,
        ));
      }
    }

    return pairs;
  }

  /// TYC3: Switch abilities between two friendly units, then self-destruct.
  SyncedCombatResult? switchCardsTYC3(
    GameCard switcher,
    GameCard target1,
    GameCard target2,
    int switcherRow,
    int switcherCol,
  ) {
    if (_currentMatch == null) return null;
    if (!useTurnBasedSystem) return null;

    if (!_isSwitcher(switcher)) {
      _log('❌ Switch failed: ${switcher.name} is not a switcher');
      return null;
    }
    if (!switcher.canAttack()) {
      _log('❌ Switch failed: Not enough AP');
      return null;
    }
    if (!target1.isAlive || !target2.isAlive) {
      _log('❌ Switch failed: One or both targets are dead');
      return null;
    }
    if (target1.ownerId != switcher.ownerId ||
        target2.ownerId != switcher.ownerId) {
      _log('❌ Switch failed: Can only switch abilities between friendly units');
      return null;
    }
    if (target1.id == target2.id) {
      _log('❌ Switch failed: Must select two different targets');
      return null;
    }

    if (!switcher.spendAttackAP()) {
      _log('❌ Switch failed: Not enough AP');
      return null;
    }

    // Swap abilities
    final abilities1 = List<String>.from(target1.abilities);
    final abilities2 = List<String>.from(target2.abilities);
    target1.swappedAbilities = abilities2;
    target2.swappedAbilities = abilities1;

    final switcherOwner = switcher.ownerId == _currentMatch!.player.id
        ? 'Player'
        : 'Opponent';
    _log(
      '🔀 [$switcherOwner] ${switcher.name} swaps abilities between ${target1.name} and ${target2.name}',
    );
    _log(
      '   ${target1.name}: ${abilities1.join(", ")} → ${abilities2.join(", ")}',
    );
    _log(
      '   ${target2.name}: ${abilities2.join(", ")} → ${abilities1.join(", ")}',
    );

    // Self-destruct
    final tile = _currentMatch!.board.getTile(switcherRow, switcherCol);
    tile.addGravestone(
      Gravestone(
        cardName: switcher.name,
        deathLog:
            'Self-destructed after switching ${target1.name} and ${target2.name}',
        ownerId: switcher.ownerId,
        turnCreated: _currentMatch!.turnNumber,
      ),
    );
    onCardDestroyed?.call(switcher);
    _removeCardFromTile(tile, switcher);
    switcher.currentHealth = 0;
    _log('   💀 ${switcher.name} self-destructs!');

    final result = SyncedCombatResult(
      id: '${DateTime.now().millisecondsSinceEpoch}_${switcher.id}_switch',
      isBaseAttack: false,
      isHeal: false,
      attackerName: switcher.name,
      targetName: '${target1.name} & ${target2.name}',
      targetId: target1.id,
      damageDealt: 0,
      healAmount: 0,
      retaliationDamage: 0,
      targetDied: false,
      attackerDied: true,
      targetHpBefore: target1.currentHealth,
      targetHpAfter: target1.currentHealth,
      attackerHpBefore: switcher.health,
      attackerHpAfter: 0,
      laneCol: switcherCol,
      attackerOwnerId: switcher.ownerId ?? '',
      attackerId: switcher.id,
      attackerRow: switcherRow,
      attackerCol: switcherCol,
      targetRow: switcherRow,
      targetCol: switcherCol,
    );

    _currentMatch!.lastCombatResult = result;
    return result;
  }

  void _log(String message) {
    // Always print for now (keeps existing debug behavior)
    // Simulations additionally capture logs via logSink.
    // ignore: avoid_print
    print(message);
    logSink?.writeln(message);
  }
}
