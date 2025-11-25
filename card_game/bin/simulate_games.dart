import 'dart:io';

import 'package:card_game/models/deck.dart';
import 'package:card_game/simulation/match_simulator.dart';
import 'package:card_game/data/card_library.dart';

Future<void> main(List<String> args) async {
  const games = 10;

  // For simulations, use element-focused decks: Water Control vs Fire Aggro.
  final deck1 = Deck(
    id: 'water_control',
    name: 'Water Control',
    cards: buildWaterControlDeck(),
  );

  final deck2 = Deck(
    id: 'fire_aggro',
    name: 'Fire Aggro',
    cards: buildFireAggroDeck(),
  );

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
