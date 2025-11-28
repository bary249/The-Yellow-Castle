import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card.dart';
import '../data/card_library.dart';

/// Service for persisting player decks to local storage
class DeckStorageService {
  static const String _deckKey = 'player_deck';

  /// Singleton instance
  static final DeckStorageService _instance = DeckStorageService._internal();
  factory DeckStorageService() => _instance;
  DeckStorageService._internal();

  /// Save deck to local storage
  /// Stores card data as JSON for full reconstruction
  Future<bool> saveDeck(List<GameCard> deck) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Convert cards to JSON-serializable format
      final cardDataList = deck
          .map(
            (card) => {
              'id': card.id,
              'name': card.name,
              'damage': card.damage,
              'health': card.health,
              'tick': card.tick,
              'element': card.element,
              'abilities': card.abilities,
              'cost': card.cost,
              'rarity': card.rarity,
            },
          )
          .toList();

      final jsonString = jsonEncode(cardDataList);
      await prefs.setString(_deckKey, jsonString);
      return true;
    } catch (e) {
      print('Error saving deck: $e');
      return false;
    }
  }

  /// Load deck from local storage
  /// Returns saved deck, or default starter deck if none saved
  Future<List<GameCard>> loadDeck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_deckKey);

      if (jsonString == null || jsonString.isEmpty) {
        // No saved deck, return default
        return buildStarterCardPool();
      }

      final cardDataList = jsonDecode(jsonString) as List<dynamic>;

      final deck = cardDataList.map((data) {
        return GameCard(
          id: data['id'] as String,
          name: data['name'] as String,
          damage: data['damage'] as int,
          health: data['health'] as int,
          tick: data['tick'] as int,
          element: data['element'] as String?,
          abilities: List<String>.from(data['abilities'] ?? []),
          cost: data['cost'] as int? ?? 1,
          rarity: data['rarity'] as int? ?? 1,
        );
      }).toList();

      return deck;
    } catch (e) {
      print('Error loading deck: $e');
      // Return default deck on error
      return buildStarterCardPool();
    }
  }

  /// Check if player has a saved deck
  Future<bool> hasSavedDeck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_deckKey);
    } catch (e) {
      return false;
    }
  }

  /// Clear saved deck (reset to default)
  Future<bool> clearDeck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deckKey);
      return true;
    } catch (e) {
      print('Error clearing deck: $e');
      return false;
    }
  }
}
