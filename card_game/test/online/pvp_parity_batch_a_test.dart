import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:card_game/models/card.dart';
import 'package:card_game/models/match_state.dart';
import 'package:card_game/services/match_manager.dart';
import 'package:card_game/services/online_game_manager.dart';

import '../helpers/match_manager_harness.dart';

void main() {
  group('PvE vs PvP parity (Batch A)', () {
    test(
      'Trap outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_a_trap';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        final hostMatch = hostMM.currentMatch!;

        // Ensure terrain matches the trap requirement.
        const trapRow = 1;
        const trapCol = 0;
        hostMatch.board.getTile(trapRow, trapCol).terrain = 'Woods';

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
        hostMatch.player.hand.add(trap);
        expect(hostMM.placeCardTYC3(trap, trapRow, trapCol), isTrue);

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
        hostMatch.opponent.hand.add(enemy);
        expect(hostMM.placeCardForOpponentTYC3(enemy, 0, 0), isTrue);

        // Switch turn control to opponent for the move.
        hostMatch.activePlayerId = hostMatch.opponent.id;
        hostMatch.currentPhase = MatchPhase.opponentTurn;

        expect(hostMM.moveCardTYC3(enemy, 0, 0, trapRow, trapCol), isTrue);

        final hostTrapTile = hostMatch.board.getTile(trapRow, trapCol);
        expect(hostTrapTile.trap, isNull);
        expect(hostTrapTile.gravestones.isNotEmpty, isTrue);
        expect(enemy.isAlive, isFalse);

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

        // On the client, the trap kill happened on row 1 as well (row 1 does not mirror).
        final clientTrapTile = clientMatch.board.getTile(trapRow, trapCol);
        expect(clientTrapTile.trap, isNull);
        expect(clientTrapTile.gravestones.isNotEmpty, isTrue);

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );

    test(
      'Spy assassination outcome matches after OnlineGameManager sync + replaceMatchState',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'parity_a_spy';
        const hostId = 'p1';
        const clientId = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final hostMM = startHarnessedMatch(
          playerId: hostId,
          opponentId: clientId,
        );
        final hostMatch = hostMM.currentMatch!;

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

        hostMatch.player.hand.add(spy);
        hostMatch.opponent.hand.add(baseGuard);

        // Opponent unit sits on their base (host row 0).
        expect(hostMM.placeCardForOpponentTYC3(baseGuard, 0, 0), isTrue);

        // Player spy staged in middle (allowed because maxAP>=2).
        expect(hostMM.placeCardTYC3(spy, 1, 0), isTrue);

        // Move spy into enemy base tile.
        expect(hostMM.moveCardTYC3(spy, 1, 0, 0, 0), isTrue);

        // Host effects.
        final hostBaseTile = hostMatch.board.getTile(0, 0);
        expect(hostBaseTile.cards.any((c) => c.id == baseGuard.id), isFalse);
        expect(hostBaseTile.cards.any((c) => c.id == spy.id), isFalse);
        expect(hostBaseTile.hiddenSpies.any((c) => c.id == spy.id), isFalse);

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

        // In the client perspective, their base row is 2.
        final clientBaseTile = clientMatch.board.getTile(2, 0);
        expect(clientBaseTile.cards.any((c) => c.id == baseGuard.id), isFalse);
        expect(clientBaseTile.cards.any((c) => c.id == spy.id), isFalse);
        expect(clientBaseTile.hiddenSpies.any((c) => c.id == spy.id), isFalse);

        await sub.cancel();
        clientOGM.dispose();
        hostOGM.dispose();
      },
    );
  });
}
