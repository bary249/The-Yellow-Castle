import 'package:flutter_test/flutter_test.dart';

import 'package:card_game/models/card.dart';
import 'package:card_game/models/match_state.dart';

import '../helpers/match_manager_harness.dart';

void main() {
  group('MatchManager ability scenarios (Batch A: trap/spy/vision)', () {
    test(
      'Trap: placing a trap and enemy entering triggers damage and clears trap',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        // Ensure terrain matches the trap requirement.
        final trapRow = 1;
        final trapCol = 0;
        match.board.getTile(trapRow, trapCol).terrain = 'Woods';

        final trap = GameCard(
          id: 'trap_test',
          name: 'Woods Mine',
          damage: 3,
          health: 1,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          element: 'Woods',
          abilities: const ['trap_3'],
        );

        match.player.hand.add(trap);
        expect(mm.placeCardTYC3(trap, trapRow, trapCol), isTrue);
        expect(match.board.getTile(trapRow, trapCol).trap, isNotNull);

        final enemy = GameCard(
          id: 'enemy_mover',
          name: 'Enemy',
          damage: 1,
          health: 3,
          maxAP: 3,
          apPerTurn: 3,
          attackAPCost: 1,
          abilities: const [],
        );

        // Place enemy adjacent so it can move onto trapped tile.
        match.opponent.hand.add(enemy);
        expect(mm.placeCardForOpponentTYC3(enemy, 0, 0), isTrue);

        // Switch turn control to opponent for the move.
        match.activePlayerId = match.opponent.id;
        match.currentPhase = MatchPhase.opponentTurn;

        final moved = mm.moveCardTYC3(enemy, 0, 0, trapRow, trapCol);
        expect(moved, isTrue);

        // Trap should have triggered and cleared.
        expect(match.board.getTile(trapRow, trapCol).trap, isNull);
        expect(enemy.isAlive, isFalse);
        expect(
          match.board.getTile(trapRow, trapCol).gravestones.isNotEmpty,
          isTrue,
        );
      },
    );

    test(
      'Spy: entering enemy base assassinates a unit and spy self-destructs',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final spy = GameCard(
          id: 'spy_test',
          name: 'Spy',
          damage: 0,
          health: 1,
          maxAP: 3,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['spy'],
        );

        final baseGuard = GameCard(
          id: 'base_guard',
          name: 'Base Guard',
          damage: 1,
          health: 5,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(spy);
        match.opponent.hand.add(baseGuard);

        // Opponent unit sits on their base.
        expect(mm.placeCardForOpponentTYC3(baseGuard, 0, 0), isTrue);

        // Player spy staged in middle (allowed because maxAP>=2).
        expect(mm.placeCardTYC3(spy, 1, 0), isTrue);

        final beforeEnemyCount = match.board.getTile(0, 0).cards.length;

        // Move spy into enemy base tile (two steps: 1,0 -> 0,0).
        final step1 = mm.moveCardTYC3(spy, 1, 0, 0, 0);
        expect(step1, isTrue);

        // Enemy should be removed.
        final afterEnemyCount = match.board.getTile(0, 0).cards.length;
        expect(afterEnemyCount, beforeEnemyCount - 1);

        // Spy self-destructs and should not remain on tile (including hidden spies).
        final baseTile = match.board.getTile(0, 0);
        expect(baseTile.cards.any((c) => c.id == spy.id), isFalse);
        expect(baseTile.hiddenSpies.any((c) => c.id == spy.id), isFalse);
        expect(spy.isAlive, isFalse);
      },
    );

    test(
      'Watcher: isTileRevealedByWatcher matches same/adjacent/forward pattern',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final watcher = GameCard(
          id: 'watcher_test',
          name: 'Watcher',
          damage: 2,
          health: 4,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const ['watcher'],
        );
        match.player.hand.add(watcher);

        // Put watcher on player base center.
        expect(mm.placeCardTYC3(watcher, 2, 1), isTrue);

        // Revealed: self tile + left/right adjacent + "forward" tile (row-1).
        expect(
          mm.isTileRevealedByWatcher(
            viewerOwnerId: match.player.id,
            row: 2,
            col: 1,
          ),
          isTrue,
        );
        expect(
          mm.isTileRevealedByWatcher(
            viewerOwnerId: match.player.id,
            row: 2,
            col: 0,
          ),
          isTrue,
        );
        expect(
          mm.isTileRevealedByWatcher(
            viewerOwnerId: match.player.id,
            row: 2,
            col: 2,
          ),
          isTrue,
        );
        expect(
          mm.isTileRevealedByWatcher(
            viewerOwnerId: match.player.id,
            row: 1,
            col: 1,
          ),
          isTrue,
        );

        // Not revealed: diagonal / far tiles.
        expect(
          mm.isTileRevealedByWatcher(
            viewerOwnerId: match.player.id,
            row: 0,
            col: 2,
          ),
          isFalse,
        );
        expect(
          mm.isTileRevealedByWatcher(
            viewerOwnerId: match.player.id,
            row: 1,
            col: 0,
          ),
          isFalse,
        );
      },
    );

    test(
      'Scout: placing scout in middle reveals enemy base lanes (lane + adjacent)',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final scout = GameCard(
          id: 'scout_test',
          name: 'Scout',
          damage: 1,
          health: 3,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['scout'],
        );

        match.player.hand.add(scout);
        expect(mm.placeCardTYC3(scout, 1, 1), isTrue);

        // Should reveal col 1 and adjacent cols 0 and 2.
        expect(match.revealedEnemyBaseLanes.length, 3);
      },
    );

    test(
      'Tall: allows attacking into fog of war when no middle card/scout exists',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        // Enemy unit on enemy base.
        final enemy = GameCard(
          id: 'enemy_base_unit',
          name: 'Enemy',
          damage: 1,
          health: 5,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );
        match.opponent.hand.add(enemy);
        expect(mm.placeCardForOpponentTYC3(enemy, 0, 0), isTrue);

        // Attacker on player base in same lane.
        final attacker = GameCard(
          id: 'attacker',
          name: 'Attacker',
          damage: 2,
          health: 5,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          attackRange: 2,
          abilities: const [],
        );
        match.player.hand.add(attacker);
        expect(mm.placeCardTYC3(attacker, 2, 0), isTrue);

        // Without tall/scout/middle card visibility, base attack should be blocked.
        final blocked = mm.attackCardTYC3(attacker, enemy, 2, 0, 0, 0);
        expect(blocked, isNull);

        // Add Tall in manhattan distance 1 from enemy base tile (0,0).
        final tall = GameCard(
          id: 'tall_test',
          name: 'Tall',
          damage: 1,
          health: 5,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['tall'],
        );
        match.player.hand.add(tall);
        expect(mm.placeCardTYC3(tall, 1, 0), isTrue);

        // Attacker needs AP to attack again (attack attempt may have spent none since it failed).
        attacker.currentAP = attacker.maxAP;

        final allowed = mm.attackCardTYC3(attacker, enemy, 2, 0, 0, 0);
        expect(allowed, isNotNull);
      },
    );
  });
}
