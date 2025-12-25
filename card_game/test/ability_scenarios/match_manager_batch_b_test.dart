import 'package:flutter_test/flutter_test.dart';

import 'package:card_game/models/card.dart';
import 'package:card_game/models/lane.dart';

import '../helpers/match_manager_harness.dart';

void main() {
  group('MatchManager ability scenarios (Batch B: attack patterns)', () {
    test(
      'Push Back: on attack, target is pushed 1 tile backward (toward its base)',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final attacker = GameCard(
          id: 'push_attacker',
          name: 'Pusher',
          damage: 1,
          health: 10,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['push_back'],
        );
        final target = GameCard(
          id: 'push_target',
          name: 'Target',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(attacker);
        match.opponent.hand.add(target);

        expect(mm.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(mm.placeCardForOpponentTYC3(target, 1, 0), isTrue);

        final res = mm.attackCardTYC3(attacker, target, 2, 0, 1, 0);
        expect(res, isNotNull);

        // Target should be pushed toward opponent base (row 0).
        expect(
          match.board.getTile(0, 0).cards.any((c) => c.id == target.id),
          isTrue,
        );
        expect(
          match.board.getTile(1, 0).cards.any((c) => c.id == target.id),
          isFalse,
        );
      },
    );

    test(
      'Diagonal Attack: attacker with diagonal_attack can attack an adjacent diagonal tile',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final attacker = GameCard(
          id: 'diag_attacker',
          name: 'Diagonal Attacker',
          damage: 4,
          health: 10,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          attackRange: 1,
          abilities: const ['diagonal_attack'],
        );

        final target = GameCard(
          id: 'diag_target',
          name: 'Diagonal Target',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(attacker);
        match.opponent.hand.add(target);

        // Attacker at bottom-left (2,0). Target at center (1,1) is diagonal adjacent.
        expect(mm.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(mm.placeCardForOpponentTYC3(target, 1, 1), isTrue);

        final hpBefore = target.currentHealth;
        final res = mm.attackCardTYC3(attacker, target, 2, 0, 1, 1);
        expect(res, isNotNull);
        expect(target.currentHealth, hpBefore - res!.damageDealt);
      },
    );

    test(
      'One-Side Attacker: from side lane hits center+far side splash on same row',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final attacker = GameCard(
          id: 'osa_attacker',
          name: 'OneSide',
          damage: 2,
          health: 10,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['one_side_attacker'],
        );

        final primary = GameCard(
          id: 'osa_primary',
          name: 'Primary',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );
        final splashCenter = GameCard(
          id: 'osa_center',
          name: 'Center',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );
        final splashFar = GameCard(
          id: 'osa_far',
          name: 'Far',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(attacker);
        match.opponent.hand.addAll([primary, splashCenter, splashFar]);

        // Attacker is in side lane col 0.
        expect(mm.placeCardTYC3(attacker, 2, 0), isTrue);

        // Targets in row 1 across all lanes.
        expect(mm.placeCardForOpponentTYC3(primary, 1, 0), isTrue);
        expect(mm.placeCardForOpponentTYC3(splashCenter, 1, 1), isTrue);
        expect(mm.placeCardForOpponentTYC3(splashFar, 1, 2), isTrue);

        final centerHpBefore = splashCenter.currentHealth;
        final farHpBefore = splashFar.currentHealth;

        final res = mm.attackCardTYC3(attacker, primary, 2, 0, 1, 0);
        expect(res, isNotNull);

        expect(splashCenter.currentHealth, centerHpBefore - res!.damageDealt);
        expect(splashFar.currentHealth, farHpBefore - res.damageDealt);
      },
    );

    test(
      'Two-Side Attacker: from center hits both side lanes splash on same row',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final attacker = GameCard(
          id: 'tsa_attacker',
          name: 'TwoSide',
          damage: 2,
          health: 10,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['two_side_attacker'],
        );

        final primary = GameCard(
          id: 'tsa_primary',
          name: 'Primary',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );
        final splashLeft = GameCard(
          id: 'tsa_left',
          name: 'Left',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );
        final splashRight = GameCard(
          id: 'tsa_right',
          name: 'Right',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(attacker);
        match.opponent.hand.addAll([primary, splashLeft, splashRight]);

        // Attacker is in center lane col 1.
        expect(mm.placeCardTYC3(attacker, 2, 1), isTrue);

        // Targets in row 1 across all lanes.
        expect(mm.placeCardForOpponentTYC3(primary, 1, 1), isTrue);
        expect(mm.placeCardForOpponentTYC3(splashLeft, 1, 0), isTrue);
        expect(mm.placeCardForOpponentTYC3(splashRight, 1, 2), isTrue);

        final leftHpBefore = splashLeft.currentHealth;
        final rightHpBefore = splashRight.currentHealth;

        final res = mm.attackCardTYC3(attacker, primary, 2, 1, 1, 1);
        expect(res, isNotNull);

        expect(splashLeft.currentHealth, leftHpBefore - res!.damageDealt);
        expect(splashRight.currentHealth, rightHpBefore - res.damageDealt);
      },
    );

    test(
      'Lane Sweep: after attacking, hits all other enemies in same lane across all tiles',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final attacker = GameCard(
          id: 'ls_attacker',
          name: 'Lane Sweeper',
          damage: 3,
          health: 10,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['lane_sweep'],
        );

        // Primary target in row 1.
        final primary = GameCard(
          id: 'ls_primary',
          name: 'Primary',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        // Other enemies in the SAME lane (col 0).
        // One shares the target tile (2 cards on the same tile), another is on a different tile.
        final otherEnemyOnSameTile = GameCard(
          id: 'ls_same_tile',
          name: 'SameTile',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );
        final otherEnemyAtEnemyBase = GameCard(
          id: 'ls_enemy_base',
          name: 'EnemyBase',
          damage: 1,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(attacker);
        match.opponent.hand.addAll([
          primary,
          otherEnemyOnSameTile,
          otherEnemyAtEnemyBase,
        ]);

        // Attacker in lane col 0.
        expect(mm.placeCardTYC3(attacker, 2, 0), isTrue);

        // Primary target in middle row.
        expect(mm.placeCardForOpponentTYC3(primary, 1, 0), isTrue);
        // Extra enemy on the same tile (2nd occupant).
        expect(mm.placeCardForOpponentTYC3(otherEnemyOnSameTile, 1, 0), isTrue);
        // Extra enemy in same lane at another tile.
        expect(
          mm.placeCardForOpponentTYC3(otherEnemyAtEnemyBase, 0, 0),
          isTrue,
        );

        final baseHpBefore = otherEnemyAtEnemyBase.currentHealth;
        final sameTileHpBefore = otherEnemyOnSameTile.currentHealth;

        final res = mm.attackCardTYC3(attacker, primary, 2, 0, 1, 0);
        expect(res, isNotNull);

        // Both other enemies in lane should take the same damage as the primary attack.
        expect(
          otherEnemyOnSameTile.currentHealth,
          sameTileHpBefore - res!.damageDealt,
        );
        expect(
          otherEnemyAtEnemyBase.currentHealth,
          baseHpBefore - res.damageDealt,
        );
      },
    );

    test(
      'Ranged: attacker with ranged ability does not take retaliation damage',
      () {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;

        final attacker = GameCard(
          id: 'ranged_attacker',
          name: 'Archer',
          damage: 2,
          health: 10,
          maxAP: 2,
          apPerTurn: 2,
          attackAPCost: 1,
          abilities: const ['ranged'],
        );
        final target = GameCard(
          id: 'ranged_target',
          name: 'Defender',
          damage: 3,
          health: 10,
          maxAP: 1,
          apPerTurn: 1,
          attackAPCost: 1,
          abilities: const [],
        );

        match.player.hand.add(attacker);
        match.opponent.hand.add(target);

        expect(mm.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(mm.placeCardForOpponentTYC3(target, 1, 0), isTrue);

        final hpBefore = attacker.currentHealth;
        final res = mm.attackCardTYC3(attacker, target, 2, 0, 1, 0);
        expect(res, isNotNull);

        expect(attacker.currentHealth, hpBefore);
      },
    );

    test(
      'First strike (combat): first_strike unit can kill before taking damage',
      () async {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;
        mm.fastMode = true;

        final striker = GameCard(
          id: 'fs_attacker',
          name: 'Striker',
          damage: 10,
          health: 10,
          tick: 2,
          moveSpeed: 1,
          abilities: const ['first_strike'],
        );

        final victim = GameCard(
          id: 'fs_victim',
          name: 'Victim',
          damage: 5,
          health: 5,
          tick: 2,
          moveSpeed: 1,
          abilities: const [],
        );

        match.player.hand.add(striker);
        match.opponent.hand.add(victim);

        await mm.submitPlayerMoves({
          LanePosition.west: [striker],
        });
        await mm.submitOpponentMoves({
          LanePosition.west: [victim],
        });

        // After combat resolution, victim should be dead and striker should not have taken damage.
        final lane = match.getLane(LanePosition.west);
        expect(lane.opponentCards.allAliveCards.isEmpty, isTrue);
        expect(lane.playerCards.allAliveCards.single.id, striker.id);
        expect(striker.currentHealth, striker.health);
      },
    );

    test(
      'Far Attack (combat phase): uncontested far_attack unit damages first enemy found in other tiles',
      () async {
        final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
        final match = mm.currentMatch!;
        mm.fastMode = true;

        final cannon = GameCard(
          id: 'far_cannon',
          name: 'Siege Cannon',
          damage: 3,
          health: 10,
          tick: 5,
          moveSpeed: 0,
          abilities: const ['far_attack'],
        );

        final enemyAtOtherTile = GameCard(
          id: 'far_enemy',
          name: 'OtherTileEnemy',
          damage: 1,
          health: 10,
          tick: 2,
          moveSpeed: 0,
          abilities: const [],
        );

        match.player.hand.add(cannon);
        match.opponent.hand.add(enemyAtOtherTile);

        // Put far_attack unit on player base in WEST lane.
        // Put enemy at middle tile (other zone). No enemy at cannon's own tile => uncontested.
        await mm.submitPlayerMoves({
          LanePosition.west: [cannon],
        });
        await mm.submitOpponentMoves({
          LanePosition.west: [enemyAtOtherTile],
        });

        final lane = match.getLane(LanePosition.west);
        final enemyAtBase = lane.opponentCards.baseCards.activeCard;
        expect(enemyAtBase, isNotNull);
        expect(
          enemyAtBase!.currentHealth,
          enemyAtOtherTile.health - cannon.damage,
        );
      },
    );
  });
}
