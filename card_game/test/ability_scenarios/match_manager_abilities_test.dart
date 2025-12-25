import 'package:flutter_test/flutter_test.dart';

import 'package:card_game/models/card.dart';

import '../helpers/match_manager_harness.dart';

void main() {
  group('MatchManager ability scenarios (TYC3)', () {
    test('Shaco spawns decoys and decoys have shaco charge 0', () {
      final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
      final match = mm.currentMatch!;

      final shaco = GameCard(
        id: 'shaco_test',
        name: 'Shaco',
        damage: 3,
        health: 3,
        maxAP: 1,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['shaco'],
      );
      match.player.hand.add(shaco);

      final placed = mm.placeCardTYC3(shaco, 2, 1);
      expect(placed, isTrue);

      final leftTile = match.board.getTile(2, 0);
      final rightTile = match.board.getTile(2, 2);

      expect(leftTile.cards.where((c) => c.isDecoy).length, 1);
      expect(rightTile.cards.where((c) => c.isDecoy).length, 1);

      final decoy0 = leftTile.cards.firstWhere((c) => c.isDecoy);
      final decoy1 = rightTile.cards.firstWhere((c) => c.isDecoy);
      expect(decoy0.abilityCharges['shaco'], 0);
      expect(decoy1.abilityCharges['shaco'], 0);

      // Original Shaco should have consumed its charge.
      expect(shaco.abilityCharges['shaco'], 0);
    });

    test('Ignite consumes charge and sets ignitedUntilTurn', () {
      final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
      final match = mm.currentMatch!;

      final igniter = GameCard(
        id: 'ignite_test',
        name: 'Firestarter',
        damage: 1,
        health: 2,
        maxAP: 2,
        apPerTurn: 2,
        attackAPCost: 1,
        abilities: const ['ignite_2'],
      );
      match.player.hand.add(igniter);

      expect(mm.placeCardTYC3(igniter, 2, 1), isTrue);

      final ok = mm.igniteTileTYC3(igniter, 2, 1, 1, 1);
      expect(ok, isTrue);

      final tile = match.board.getTile(1, 1);
      expect(tile.ignitedUntilTurn, 2);
      expect(igniter.abilityCharges['ignite_2'], 0);
    });

    test('Poisoner applies poison and stacks with ignite tick (2 total)', () {
      final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
      final match = mm.currentMatch!;

      final poisoner = GameCard(
        id: 'poisoner_test',
        name: 'Poisoner',
        damage: 2,
        health: 4,
        maxAP: 2,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['poisoner'],
      );

      final victim = GameCard(
        id: 'victim_test',
        name: 'Victim',
        damage: 1,
        health: 10,
        maxAP: 1,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const [],
      );

      match.player.hand.add(poisoner);
      match.opponent.hand.add(victim);

      expect(mm.placeCardTYC3(poisoner, 2, 1), isTrue);
      expect(mm.placeCardForOpponentTYC3(victim, 1, 1), isTrue);

      final result = mm.attackCardTYC3(poisoner, victim, 2, 1, 1, 1);
      expect(result, isNotNull);
      expect(victim.poisonTicksRemaining, 2);
      expect(poisoner.abilityCharges['poisoner'], 0);

      // Set the victim tile on fire and ensure stacking occurs at the start of opponent's turn.
      match.board.getTile(1, 1).ignitedUntilTurn = match.turnNumber + 10;

      final hpBefore = victim.currentHealth;
      mm.endTurnTYC3(); // switches to opponent and triggers turn-start effects for opponent
      final hpAfter = victim.currentHealth;

      expect(hpBefore - hpAfter, 2);
      expect(victim.poisonTicksRemaining, 1);
    });

    test('Resetter refreshes consumable charges and self-destructs', () {
      final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
      final match = mm.currentMatch!;

      final target = GameCard(
        id: 'fear_target',
        name: 'Fear Target',
        damage: 1,
        health: 5,
        maxAP: 1,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['fear'],
      );
      final resetter = GameCard(
        id: 'resetter_test',
        name: 'Resetter',
        damage: 0,
        health: 1,
        maxAP: 2,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['resetter'],
      );

      match.player.hand.add(target);
      match.player.hand.add(resetter);

      expect(mm.placeCardTYC3(target, 2, 0), isTrue);
      expect(mm.placeCardTYC3(resetter, 2, 0), isTrue);

      // Simulate spent charge.
      target.abilityCharges['fear'] = 0;

      final res = mm.resetCardTYC3(resetter, target, 2, 0, 2, 0);
      expect(res, isNotNull);
      expect(target.abilityCharges['fear'], 1);

      final tile = match.board.getTile(2, 0);
      expect(tile.cards.any((c) => c.id == 'resetter_test'), isFalse);
      expect(resetter.currentHealth, 0);
    });

    test('Switcher swaps abilities (swappedAbilities) and self-destructs', () {
      final mm = startHarnessedMatch(playerId: 'p1', opponentId: 'p2');
      final match = mm.currentMatch!;

      final t1 = GameCard(
        id: 't1',
        name: 'T1',
        damage: 1,
        health: 5,
        maxAP: 1,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['fear'],
      );
      final t2 = GameCard(
        id: 't2',
        name: 'T2',
        damage: 1,
        health: 5,
        maxAP: 1,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['glue'],
      );
      final switcher = GameCard(
        id: 'switcher_test',
        name: 'Switcher',
        damage: 1,
        health: 2,
        maxAP: 2,
        apPerTurn: 1,
        attackAPCost: 1,
        abilities: const ['switcher'],
      );

      match.player.hand.addAll([t1, t2, switcher]);

      expect(mm.placeCardTYC3(t1, 2, 0), isTrue);
      expect(mm.placeCardTYC3(t2, 2, 2), isTrue);
      expect(mm.placeCardTYC3(switcher, 2, 1), isTrue);

      final res = mm.switchCardsTYC3(switcher, t1, t2, 2, 1);
      expect(res, isNotNull);

      expect(t1.abilities, contains('glue'));
      expect(t2.abilities, contains('fear'));

      final tile = match.board.getTile(2, 1);
      expect(tile.cards.any((c) => c.id == 'switcher_test'), isFalse);
      expect(switcher.currentHealth, 0);
    });
  });
}
