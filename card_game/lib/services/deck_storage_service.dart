import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
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

  /// In-memory fallback for when SharedPreferences fails (e.g., web without proper setup)
  static List<GameCard>? _inMemoryDeck;
  static bool _storageAvailable = true;

  /// Try to get SharedPreferences, return null if unavailable
  Future<SharedPreferences?> _getPrefs() async {
    if (!_storageAvailable) return null;

    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SharedPreferences not available: $e');
      _storageAvailable = false;
      return null;
    }
  }

  /// Save deck to local storage
  /// Stores card data as JSON for full reconstruction
  Future<bool> saveDeck(List<GameCard> deck) async {
    // Always save to memory as backup
    _inMemoryDeck = List.from(deck);

    final prefs = await _getPrefs();
    if (prefs == null) {
      debugPrint('Using in-memory storage for deck');
      return true; // Saved to memory
    }

    try {
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
      debugPrint('Error saving deck: $e');
      return true; // Still saved to memory
    }
  }

  /// Load deck from local storage
  /// Returns saved deck, or default starter deck if none saved
  Future<List<GameCard>> loadDeck() async {
    // Check in-memory first
    if (_inMemoryDeck != null) {
      return List.from(_inMemoryDeck!);
    }

    final prefs = await _getPrefs();
    if (prefs == null) {
      return buildStarterCardPool();
    }

    try {
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

      // Cache in memory
      _inMemoryDeck = List.from(deck);
      return deck;
    } catch (e) {
      debugPrint('Error loading deck: $e');
      // Return default deck on error
      return buildStarterCardPool();
    }
  }

  /// Check if player has a saved deck
  Future<bool> hasSavedDeck() async {
    if (_inMemoryDeck != null) return true;

    final prefs = await _getPrefs();
    if (prefs == null) return false;

    try {
      return prefs.containsKey(_deckKey);
    } catch (e) {
      return false;
    }
  }

  /// Clear saved deck (reset to default)
  Future<bool> clearDeck() async {
    _inMemoryDeck = null;

    final prefs = await _getPrefs();
    if (prefs == null) return true;

    try {
      await prefs.remove(_deckKey);
      return true;
    } catch (e) {
      debugPrint('Error clearing deck: $e');
      return true; // Memory already cleared
    }
  }
}
