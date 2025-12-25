import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:card_game/models/card.dart';
import 'package:card_game/models/match_state.dart';
import 'package:card_game/services/online_game_manager.dart';

import '../helpers/match_manager_harness.dart';

void main() {
  group('Online sync tests', () {
    test('MatchState JSON roundtrip preserves ability runtime state', () {
      final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
      final match = mm.currentMatch!;

      // Create some ability runtime state that must survive online sync.
      final decoy = GameCard(
        id: 'd1',
        name: 'Decoy',
        damage: 1,
        health: 1,
        abilities: const ['shaco'],
        isDecoy: true,
      );
      decoy.ownerId = match.player.id;
      decoy.abilityCharges['shaco'] = 0;

      final poisoned = GameCard(
        id: 'p',
        name: 'Poisoned',
        damage: 1,
        health: 10,
        abilities: const [],
      );
      poisoned.ownerId = match.player.id;
      poisoned.poisonTicksRemaining = 2;

      final swappedA = GameCard(
        id: 'sa',
        name: 'SA',
        damage: 1,
        health: 5,
        abilities: const ['fear'],
      );
      swappedA.ownerId = match.player.id;
      swappedA.swappedAbilities = const ['glue'];

      match.board.getTile(2, 0).cards.addAll([decoy, poisoned, swappedA]);
      match.board.getTile(1, 1).ignitedUntilTurn = 123;

      final json = match.toJson();
      final restored = MatchState.fromJson(json, myPlayerId: match.player.id);

      final restoredTile = restored.board.getTile(2, 0);
      final rDecoy = restoredTile.cards.firstWhere((c) => c.id == 'd1');
      expect(rDecoy.isDecoy, isTrue);
      expect(rDecoy.abilityCharges['shaco'], 0);

      final rPoisoned = restoredTile.cards.firstWhere((c) => c.id == 'p');
      expect(rPoisoned.poisonTicksRemaining, 2);

      final rSwap = restoredTile.cards.firstWhere((c) => c.id == 'sa');
      expect(rSwap.abilities, contains('glue'));

      expect(restored.board.getTile(1, 1).ignitedUntilTurn, 123);
    });

    test(
      'OnlineGameManager syncState writes gameState.version and lastUpdatedBy',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'm1';
        const myId = 'p1';

        // Match doc must exist to allow update().
        await firestore.collection('matches').doc(matchId).set({});

        final mm = startHarnessedMatch(playerId: myId, opponentId: 'p2');
        final match = mm.currentMatch!;

        final ogm = OnlineGameManager(
          matchId: matchId,
          myPlayerId: myId,
          firestore: firestore,
        );

        await ogm.syncState(match);

        final snap = await firestore.collection('matches').doc(matchId).get();
        final data = snap.data()!;
        expect(data.containsKey('gameState'), isTrue);

        final gameState = data['gameState'] as Map<String, dynamic>;
        expect(gameState['version'], 1);
        expect(gameState['lastUpdatedBy'], myId);
        expect(gameState.containsKey('updatedAt'), isTrue);
      },
    );

    test(
      'OnlineGameManager emits state updates to opponent via stateStream',
      () async {
        final firestore = FakeFirebaseFirestore();
        const matchId = 'm2';
        const p1 = 'p1';
        const p2 = 'p2';

        await firestore.collection('matches').doc(matchId).set({});

        final mmP1 = startHarnessedMatch(playerId: p1, opponentId: p2);
        final matchP1 = mmP1.currentMatch!;

        final host = OnlineGameManager(
          matchId: matchId,
          myPlayerId: p1,
          firestore: firestore,
        );
        final client = OnlineGameManager(
          matchId: matchId,
          myPlayerId: p2,
          firestore: firestore,
        );

        final completer = Completer<MatchState>();
        final sub = client.stateStream.listen((s) {
          if (!completer.isCompleted) completer.complete(s);
        });

        client.startListening();

        // Host writes.
        await host.syncState(matchP1);

        final received = await completer.future.timeout(
          const Duration(seconds: 2),
        );

        // Client sees a state where (from its perspective) player.id == p2.
        expect(received.player.id, p2);
        expect(received.opponent.id, p1);

        await sub.cancel();
        client.dispose();
        host.dispose();
      },
    );
  });
}
