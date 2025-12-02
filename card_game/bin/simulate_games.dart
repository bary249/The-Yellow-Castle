import 'dart:io';

import 'package:card_game/models/deck.dart';
import 'package:card_game/simulation/match_simulator.dart';
import 'package:card_game/data/card_library.dart';

Future<void> main(List<String> args) async {
  const games = 10;

  // Check command line args for deck type
  final useNapoleon = args.contains('--napoleon');

  late final Deck deck1;
  late final Deck deck2;

  if (useNapoleon) {
    // Napoleon's starter deck vs Desert Aggro
    print('🎖️ Testing Napoleon\'s Campaign Deck vs Desert Aggro\n');
    deck1 = Deck(
      id: 'napoleon_starter',
      name: 'Napoleon Starter',
      cards: buildNapoleonStarterDeck(),
    );
    deck2 = Deck(
      id: 'desert_aggro',
      name: 'Desert Aggro',
      cards: buildFireAggroDeck(),
    );
  } else {
    // Default: Lake Control vs Desert Aggro
    print('🌊 Testing Lake Control vs Desert Aggro\n');
    deck1 = Deck(
      id: 'lake_control',
      name: 'Lake Control',
      cards: buildWaterControlDeck(),
    );
    deck2 = Deck(
      id: 'desert_aggro',
      name: 'Desert Aggro',
      cards: buildFireAggroDeck(),
    );
  }

  final report = await simulateManyGames(
    count: games,
    deck1: deck1,
    deck2: deck2,
  );

  // Print summary to console
  print(report.toConsoleString());

  // Also write summary and per-game outcomes to a new log file
  final logsDir = Directory('simulation_logs');
  if (!logsDir.existsSync()) {
    logsDir.createSync(recursive: true);
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file = File('simulation_logs/sim_$timestamp.txt');

  final buffer = StringBuffer();
  buffer.writeln(report.toConsoleString());
  buffer.writeln();
  for (var i = 0; i < report.outcomes.length; i++) {
    final o = report.outcomes[i];
    buffer.writeln(
      '=== Game ${i + 1} === winner=${o.winner}, turns=${o.turns}, P1=${o.playerCrystalHp} HP, P2=${o.opponentCrystalHp} HP',
    );
    buffer.writeln(o.fullLog);
    buffer.writeln();
  }

  await file.writeAsString(buffer.toString());
}
