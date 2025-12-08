import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/card.dart';
import '../models/deck.dart';
import '../data/card_library.dart';

/// Service for persisting player decks to Firebase Firestore
class DeckStorageService {
  static const String _decksCollection = 'user_decks';
  static const String _defaultDeckId = 'default';

  /// Singleton instance
  static final DeckStorageService _instance = DeckStorageService._internal();
  factory DeckStorageService() => _instance;
  DeckStorageService._internal() {
    try {
      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
    } catch (e) {
      debugPrint('DeckStorageService running in offline mode: $e');
    }
  }

  FirebaseFirestore? _firestore;
  FirebaseAuth? _auth;

  /// In-memory cache
  static List<GameCard>? _cachedDeck;

  /// Get current user ID
  String? get _userId => _auth?.currentUser?.uid;

  /// Get user's decks collection reference
  CollectionReference<Map<String, dynamic>>? get _userDecksRef {
    final uid = _userId;
    if (uid == null || _firestore == null) return null;
    return _firestore!
        .collection('users')
        .doc(uid)
        .collection(_decksCollection);
  }

  /// Convert card to Firestore-compatible map
  Map<String, dynamic> _cardToMap(GameCard card) => {
    'id': card.id,
    'name': card.name,
    'damage': card.damage,
    'health': card.health,
    'tick': card.tick,
    'element': card.element,
    'abilities': card.abilities,
    'cost': card.cost,
    'rarity': card.rarity,
  };

  /// Convert Firestore map to GameCard
  /// Looks up the card by name from the card library to get full definition
  GameCard _mapToCard(Map<String, dynamic> data) {
    final name = data['name'] as String;
    // Try to get the card from the library by name (uses Deck._createCardByName)
    final libraryCard = _getCardFromLibrary(name);
    if (libraryCard != null) {
      return libraryCard;
    }
    // Fallback: create from stored data (may have incomplete AP fields)
    return GameCard(
      id: data['id'] as String,
      name: name,
      damage: data['damage'] as int,
      health: data['health'] as int,
      tick: data['tick'] as int,
      moveSpeed: data['moveSpeed'] as int? ?? 1,
      maxAP: data['maxAP'] as int? ?? 1,
      apPerTurn: data['apPerTurn'] as int? ?? 1,
      attackAPCost: data['attackAPCost'] as int? ?? 1,
      attackRange: data['attackRange'] as int? ?? 1,
      element: data['element'] as String?,
      abilities: List<String>.from(data['abilities'] ?? []),
      cost: data['cost'] as int? ?? 1,
      rarity: data['rarity'] as int? ?? 1,
    );
  }

  /// Get a card from the library by name
  GameCard? _getCardFromLibrary(String name) {
    // Use the same lookup as Deck.fromCardNames
    return Deck.createCardByName(name, 1);
  }

  /// Save deck to Firebase
  /// [deckId] - optional deck name, defaults to 'default'
  Future<bool> saveDeck(
    List<GameCard> deck, {
    String deckId = _defaultDeckId,
  }) async {
    // Always cache locally
    _cachedDeck = List.from(deck);

    final decksRef = _userDecksRef;
    if (decksRef == null) {
      debugPrint('No user logged in, deck saved to memory only');
      return true;
    }

    try {
      final cardDataList = deck.map(_cardToMap).toList();

      await decksRef.doc(deckId).set({
        'cards': cardDataList,
        'cardCount': deck.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('Deck saved to Firebase: $deckId (${deck.length} cards)');
      return true;
    } catch (e) {
      debugPrint('Error saving deck to Firebase: $e');
      return false;
    }
  }

  /// Load deck from Firebase
  /// Returns saved deck, or default starter deck if none saved
  Future<List<GameCard>> loadDeck({String deckId = _defaultDeckId}) async {
    // Check cache first for quick load
    if (_cachedDeck != null) {
      return List.from(_cachedDeck!);
    }

    final decksRef = _userDecksRef;
    if (decksRef == null) {
      debugPrint('No user logged in, returning default deck');
      return buildStarterCardPool();
    }

    try {
      final doc = await decksRef.doc(deckId).get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('No saved deck found, returning default');
        return buildStarterCardPool();
      }

      final data = doc.data()!;
      final cardsList = data['cards'] as List<dynamic>?;

      if (cardsList == null || cardsList.isEmpty) {
        return buildStarterCardPool();
      }

      final deck = cardsList
          .map((c) => _mapToCard(c as Map<String, dynamic>))
          .toList();

      // Cache in memory
      _cachedDeck = List.from(deck);
      debugPrint('Deck loaded from Firebase: $deckId (${deck.length} cards)');
      return deck;
    } catch (e) {
      debugPrint('Error loading deck from Firebase: $e');
      return buildStarterCardPool();
    }
  }

  /// Get all saved deck IDs for current user
  Future<List<String>> getSavedDeckIds() async {
    final decksRef = _userDecksRef;
    if (decksRef == null) return [];

    try {
      final snapshot = await decksRef.get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('Error getting deck IDs: $e');
      return [];
    }
  }

  /// Check if player has a saved deck
  Future<bool> hasSavedDeck({String deckId = _defaultDeckId}) async {
    if (_cachedDeck != null) return true;

    final decksRef = _userDecksRef;
    if (decksRef == null) return false;

    try {
      final doc = await decksRef.doc(deckId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Clear saved deck (reset to default)
  Future<bool> clearDeck({String deckId = _defaultDeckId}) async {
    _cachedDeck = null;

    final decksRef = _userDecksRef;
    if (decksRef == null) return true;

    try {
      await decksRef.doc(deckId).delete();
      debugPrint('Deck deleted from Firebase: $deckId');
      return true;
    } catch (e) {
      debugPrint('Error deleting deck: $e');
      return false;
    }
  }

  /// Clear local cache (force reload from Firebase next time)
  void clearCache() {
    _cachedDeck = null;
  }
}
