import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:card_game/models/card.dart';
import 'package:card_game/models/lane.dart';
import 'package:card_game/services/match_manager.dart';
import 'package:card_game/services/online_game_manager.dart';

import '../helpers/match_manager_harness.dart';

void main() {
  group('PvE vs PvP parity (Batch B)', () {
    test(
      'Push Back outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_b_push_back';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        final hostMatch = hostMM.currentMatch!;

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

        hostMatch.player.hand.add(attacker);
        hostMatch.opponent.hand.add(target);

        expect(hostMM.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(hostMM.placeCardForOpponentTYC3(target, 1, 0), isTrue);

        expect(hostMM.attackCardTYC3(attacker, target, 2, 0, 1, 0), isNotNull);

        // Host: target pushed to row 0.
        expect(
          hostMatch.board.getTile(0, 0).cards.any((c) => c.id == target.id),
          isTrue,
        );

        final hostOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: hostId,
          firestore: firestore,
        );
        final clientOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: clientId,
          firestore: firestore,
        );

        final receivedCompleter = Completer();
        late final StreamSubscription sub;
        sub = clientOGM.stateStream.listen((state) {
          if (!receivedCompleter.isCompleted) {
            receivedCompleter.complete(state);
          }
        });
        clientOGM.startListening();

        await hostOGM.syncState(hostMatch);
        final receivedState = await receivedCompleter.future.timeout(
          const Duration(seconds: 2),
        );

        final clientMM = MatchManager();
        clientMM.replaceMatchState(receivedState);
        final clientMatch = clientMM.currentMatch!;

        // Client perspective is mirrored: host row 0 becomes client row 2.
        expect(
          clientMatch.board.getTile(2, 0).cards.any((c) => c.id == target.id),
          isTrue,
        );

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );

    test(
      'One-Side splash outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_b_one_side';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        final hostMatch = hostMM.currentMatch!;

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

        hostMatch.player.hand.add(attacker);
        hostMatch.opponent.hand.addAll([primary, splashCenter, splashFar]);

        expect(hostMM.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(hostMM.placeCardForOpponentTYC3(primary, 1, 0), isTrue);
        expect(hostMM.placeCardForOpponentTYC3(splashCenter, 1, 1), isTrue);
        expect(hostMM.placeCardForOpponentTYC3(splashFar, 1, 2), isTrue);

        final hostCenterHp = splashCenter.currentHealth;
        final hostFarHp = splashFar.currentHealth;

        final res = hostMM.attackCardTYC3(attacker, primary, 2, 0, 1, 0);
        expect(res, isNotNull);

        final hostCenterAfter = splashCenter.currentHealth;
        final hostFarAfter = splashFar.currentHealth;

        expect(hostCenterAfter, hostCenterHp - res!.damageDealt);
        expect(hostFarAfter, hostFarHp - res.damageDealt);

        final hostOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: hostId,
          firestore: firestore,
        );
        final clientOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: clientId,
          firestore: firestore,
        );

        final receivedCompleter = Completer();
        late final StreamSubscription sub;
        sub = clientOGM.stateStream.listen((state) {
          if (!receivedCompleter.isCompleted) {
            receivedCompleter.complete(state);
          }
        });
        clientOGM.startListening();

        await hostOGM.syncState(hostMatch);
        final receivedState = await receivedCompleter.future.timeout(
          const Duration(seconds: 2),
        );

        final clientMM = MatchManager();
        clientMM.replaceMatchState(receivedState);
        final clientMatch = clientMM.currentMatch!;

        // Host affected row 1. Row 1 does not mirror.
        final clientCenter = clientMatch.board
            .getTile(1, 1)
            .cards
            .firstWhere((c) => c.id == splashCenter.id);
        final clientFar = clientMatch.board
            .getTile(1, 2)
            .cards
            .firstWhere((c) => c.id == splashFar.id);

        expect(clientCenter.currentHealth, hostCenterAfter);
        expect(clientFar.currentHealth, hostFarAfter);

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );

    test(
      'Lane Sweep outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_b_lane_sweep';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        final hostMatch = hostMM.currentMatch!;

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

        hostMatch.player.hand.add(attacker);
        hostMatch.opponent.hand.addAll([
          primary,
          otherEnemyOnSameTile,
          otherEnemyAtEnemyBase,
        ]);

        expect(hostMM.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(hostMM.placeCardForOpponentTYC3(primary, 1, 0), isTrue);
        expect(
          hostMM.placeCardForOpponentTYC3(otherEnemyOnSameTile, 1, 0),
          isTrue,
        );
        expect(
          hostMM.placeCardForOpponentTYC3(otherEnemyAtEnemyBase, 0, 0),
          isTrue,
        );

        final hostSameTileHpBefore = otherEnemyOnSameTile.currentHealth;
        final hostEnemyBaseHpBefore = otherEnemyAtEnemyBase.currentHealth;

        final res = hostMM.attackCardTYC3(attacker, primary, 2, 0, 1, 0);
        expect(res, isNotNull);

        final hostSameTileHpAfter = otherEnemyOnSameTile.currentHealth;
        final hostEnemyBaseHpAfter = otherEnemyAtEnemyBase.currentHealth;

        expect(hostSameTileHpAfter, hostSameTileHpBefore - res!.damageDealt);
        expect(hostEnemyBaseHpAfter, hostEnemyBaseHpBefore - res.damageDealt);

        final hostOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: hostId,
          firestore: firestore,
        );
        final clientOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: clientId,
          firestore: firestore,
        );

        final receivedCompleter = Completer();
        late final StreamSubscription sub;
        sub = clientOGM.stateStream.listen((state) {
          if (!receivedCompleter.isCompleted) {
            receivedCompleter.complete(state);
          }
        });
        clientOGM.startListening();

        await hostOGM.syncState(hostMatch);
        final receivedState = await receivedCompleter.future.timeout(
          const Duration(seconds: 2),
        );

        final clientMM = MatchManager();
        clientMM.replaceMatchState(receivedState);
        final clientMatch = clientMM.currentMatch!;

        // Host used lane col 0. Opponent cards are mirrored in row (0<->2) but row 1 stays.
        final clientSameTile = clientMatch.board
            .getTile(1, 0)
            .cards
            .firstWhere((c) => c.id == otherEnemyOnSameTile.id);
        final clientEnemyBase = clientMatch.board
            .getTile(2, 0)
            .cards
            .firstWhere((c) => c.id == otherEnemyAtEnemyBase.id);

        expect(clientSameTile.currentHealth, hostSameTileHpAfter);
        expect(clientEnemyBase.currentHealth, hostEnemyBaseHpAfter);

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );

    test(
      'Diagonal Attack outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_b_diagonal_attack';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        final hostMatch = hostMM.currentMatch!;

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

        hostMatch.player.hand.add(attacker);
        hostMatch.opponent.hand.add(target);

        expect(hostMM.placeCardTYC3(attacker, 2, 0), isTrue);
        expect(hostMM.placeCardForOpponentTYC3(target, 1, 1), isTrue);

        final hostHpAfterBeforeSync = target.currentHealth;
        final res = hostMM.attackCardTYC3(attacker, target, 2, 0, 1, 1);
        expect(res, isNotNull);
        final hostHpAfter = target.currentHealth;
        expect(hostHpAfter, hostHpAfterBeforeSync - res!.damageDealt);

        final hostOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: hostId,
          firestore: firestore,
        );
        final clientOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: clientId,
          firestore: firestore,
        );

        final receivedCompleter = Completer();
        late final StreamSubscription sub;
        sub = clientOGM.stateStream.listen((state) {
          if (!receivedCompleter.isCompleted) {
            receivedCompleter.complete(state);
          }
        });
        clientOGM.startListening();

        await hostOGM.syncState(hostMatch);
        final receivedState = await receivedCompleter.future.timeout(
          const Duration(seconds: 2),
        );

        final clientMM = MatchManager();
        clientMM.replaceMatchState(receivedState);
        final clientMatch = clientMM.currentMatch!;

        // Host damaged opponent card on row 1, col 1. Row 1 does not mirror.
        final clientTarget = clientMatch.board
            .getTile(1, 1)
            .cards
            .firstWhere((c) => c.id == target.id);
        expect(clientTarget.currentHealth, hostHpAfter);

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );

    test(
      'Far Attack outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_b_far_attack';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        hostMM.fastMode = true;
        final hostMatch = hostMM.currentMatch!;

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

        hostMatch.player.hand.add(cannon);
        hostMatch.opponent.hand.add(enemyAtOtherTile);

        await hostMM.submitPlayerMoves({
          LanePosition.west: [cannon],
        });
        await hostMM.submitOpponentMoves({
          LanePosition.west: [enemyAtOtherTile],
        });

        final hostLane = hostMatch.getLane(LanePosition.west);
        final hostEnemyAtBase = hostLane.opponentCards.baseCards.activeCard;
        expect(hostEnemyAtBase, isNotNull);
        final hostEnemyHpAfter = hostEnemyAtBase!.currentHealth;
        expect(hostEnemyHpAfter, enemyAtOtherTile.health - cannon.damage);

        // Ensure the lane is revealed for the receiving client so the opponent base card
        // is present/visible on the synced board.
        hostMatch.revealedEnemyBaseLanes.add(LanePosition.west);

        final hostOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: hostId,
          firestore: firestore,
        );
        final clientOGM = OnlineGameManager(
          matchId: matchId,
          myPlayerId: clientId,
          firestore: firestore,
        );

        final receivedCompleter = Completer();
        late final StreamSubscription sub;
        sub = clientOGM.stateStream.listen((state) {
          if (!receivedCompleter.isCompleted) {
            receivedCompleter.complete(state);
          }
        });
        clientOGM.startListening();

        await hostOGM.syncState(hostMatch);
        final receivedState = await receivedCompleter.future.timeout(
          const Duration(seconds: 2),
        );

        final clientMM = MatchManager();
        clientMM.replaceMatchState(receivedState);
        final clientMatch = clientMM.currentMatch!;

        // Assert via synced GameBoard. Client perspective is mirrored, so host enemy base row 0
        // becomes client row 2 for the same physical tile.
        final clientTile = clientMatch.board.getTile(2, 0);
        final clientEnemy = clientTile.cards.firstWhere(
          (c) => c.id == enemyAtOtherTile.id,
        );
        expect(clientEnemy.currentHealth, hostEnemyHpAfter);

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );
  });
}
