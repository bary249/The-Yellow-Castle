import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/card.dart';
import '../models/hero.dart';
import '../data/card_library.dart';
import '../data/hero_library.dart';
import '../services/auth_service.dart';
import 'test_match_screen.dart';

/// Template for a selectable deck
class DeckTemplate {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> unitPreview;
  final List<GameCard> Function() builder;

  const DeckTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.unitPreview,
    required this.builder,
  });
}

/// Screen to select starting deck for a campaign or match
class DeckSelectionScreen extends StatefulWidget {
  final String heroId;
  final String?
  onlineMatchId; // If set, we are in PvP Lobby mode (legacy/reconnect)
  final bool
  isOnline; // If true (and matchId null), we are in Pre-Matchmaking mode
  final Function(List<GameCard>)?
  onDeckSelected; // Callback for both local and pre-matchmaking

  const DeckSelectionScreen({
    super.key,
    required this.heroId,
    this.onlineMatchId,
    this.isOnline = false,
    this.onDeckSelected,
  });

  @override
  State<DeckSelectionScreen> createState() => _DeckSelectionScreenState();
}

class _DeckSelectionScreenState extends State<DeckSelectionScreen> {
  final AuthService _authService = AuthService();
  DeckTemplate? _selectedDeck;
  late List<DeckTemplate> _availableDecks;
  late GameHero _hero;

  // PvP State
  bool _isSubmitted = false;
  int _secondsRemaining = 20;
  Timer? _timer;
  StreamSubscription? _matchSubscription;

  @override
  void initState() {
    super.initState();
    _hero = HeroLibrary.getHeroById(widget.heroId) ?? HeroLibrary.napoleon();
    _availableDecks = _getDeckTemplatesForHero(widget.heroId);

    // Auto-select first deck
    if (_availableDecks.isNotEmpty) {
      _selectedDeck = _availableDecks.first;
    }

    if (widget.onlineMatchId != null) {
      _startPvPTimer();
      _listenToMatch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _matchSubscription?.cancel();
    super.dispose();
  }

  void _startPvPTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          timer.cancel();
          if (!_isSubmitted) {
            _confirmSelection(); // Auto-confirm on timeout
          }
        }
      });
    });
  }

  void _listenToMatch() {
    final firestore = FirebaseFirestore.instance;
    _matchSubscription = firestore
        .collection('matches')
        .doc(widget.onlineMatchId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) return;
          final data = snapshot.data()!;
          final player1 = data['player1'] as Map<String, dynamic>;
          final player2 = data['player2'] as Map<String, dynamic>;

          // Check if BOTH are ready.
          if (player1['ready'] == true && player2['ready'] == true) {
            _timer?.cancel();
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      TestMatchScreen(onlineMatchId: widget.onlineMatchId),
                ),
              );
            }
          }
        });
  }

  List<DeckTemplate> _getDeckTemplatesForHero(String heroId) {
    debugPrint('DeckSelectionScreen: Loading decks for heroId=$heroId');
    switch (heroId) {
      case 'napoleon':
        return [
          DeckTemplate(
            id: 'grand_army',
            name: 'Grand Army',
            description:
                'Balanced force with strong infantry and artillery support.',
            icon: Icons.balance,
            color: Colors.blue,
            unitPreview: ['Line Infantry', 'Fusiliers', 'Field Cannon'],
            builder: buildNapoleonStarterDeck,
          ),
          DeckTemplate(
            id: 'imperial_guard',
            name: 'Imperial Guard',
            description: 'Elite heavy units. High cost but devastating power.',
            icon: Icons.shield,
            color: Colors.indigo,
            unitPreview: ['Old Guard', 'Grenadiers', 'Cuirassiers'],
            builder: () =>
                buildNapoleonStarterDeck(), // Placeholder: create variant if needed
          ),
          DeckTemplate(
            id: 'artillery_corps',
            name: 'Artillery Corps',
            description: 'Dominate from range with massed cannons.',
            icon: Icons.gps_fixed,
            color: Colors.orange,
            unitPreview: ['Field Cannon', 'Horse Artillery', 'Voltigeurs'],
            builder: () => buildNapoleonStarterDeck(), // Placeholder
          ),
        ];
      case 'saladin':
        return [
          DeckTemplate(
            id: 'desert_host',
            name: 'Desert Host',
            description: 'Fast, aggressive units that strike hard.',
            icon: Icons.flash_on,
            color: Colors.amber,
            unitPreview: ['Mamluk Cavalry', 'Saracen Infantry', 'Archers'],
            builder: buildSaladinStarterDeck,
          ),
          DeckTemplate(
            id: 'sandstorm',
            name: 'Sandstorm',
            description: 'Overwhelm enemies with speed and numbers.',
            icon: Icons.tornado,
            color: Colors.orangeAccent,
            unitPreview: ['Light Cavalry', 'Skirmishers', 'Decoys'],
            builder: buildSaladinSandstormDeck,
          ),
        ];
      case 'admiral_nelson':
        return [
          DeckTemplate(
            id: 'royal_navy',
            name: 'Royal Navy',
            description: 'Balanced naval force with marine infantry.',
            icon: Icons.water,
            color: Colors.teal,
            unitPreview: ['Royal Marines', 'Naval Gunners', 'Ship Cannons'],
            builder: buildNelsonStarterDeck,
          ),
          DeckTemplate(
            id: 'blockade',
            name: 'Blockade',
            description: 'Defensive powerhouse. Hold the line at all costs.',
            icon: Icons.lock,
            color: Colors.blueGrey,
            unitPreview: ['Ironclad Hulls', 'Elite Guards', 'Supply Ships'],
            builder: buildNelsonBlockadeDeck,
          ),
          DeckTemplate(
            id: 'broadside',
            name: 'Broadside',
            description: 'Massed artillery fire to obliterate the enemy.',
            icon: Icons.waves,
            color: Colors.cyan,
            unitPreview: ['Naval Cannons', 'Musketeers', 'First Mates'],
            builder: buildNelsonBroadsideDeck,
          ),
        ];
      case 'archduke_charles':
        return [
          DeckTemplate(
            id: 'austrian_line',
            name: 'Austrian Line',
            description: 'Disciplined infantry and heavy cavalry.',
            icon: Icons.security,
            color: Colors.red,
            unitPreview: ['Line Infantry', 'Grenadiers', 'Cuirassiers'],
            builder: buildAct1EnemyDeck, // Uses Act 1 deck
          ),
          DeckTemplate(
            id: 'alpine_defense',
            name: 'Alpine Defense',
            description: 'Masters of the woods and mountain warfare.',
            icon: Icons.landscape,
            color: Colors.green[800]!,
            unitPreview: ['Alpine Guards', 'Rangers', 'Mountain Guns'],
            builder: buildArchdukeDefenseDeck,
          ),
          DeckTemplate(
            id: 'coalition',
            name: 'Coalition',
            description: 'A diverse force of allied nations.',
            icon: Icons.flag,
            color: Colors.amber[900]!,
            unitPreview: ['Mixed Infantry', 'Allied Cannons', 'Elites'],
            builder: buildArchdukeCoalitionDeck,
          ),
        ];
      case 'tester':
        return [
          DeckTemplate(
            id: 'specials',
            name: 'Specials Deck',
            description: 'One of each ability card for testing.',
            icon: Icons.science,
            color: Colors.purple,
            unitPreview: ['Medic', 'Enhancer', 'Switcher', 'Spy', 'Shaco'],
            builder: buildSpecialsDeck,
          ),
        ];
      default:
        return [
          DeckTemplate(
            id: 'balanced',
            name: 'Balanced Army',
            description: 'A well-rounded force.',
            icon: Icons.balance,
            color: Colors.grey,
            unitPreview: ['Infantry', 'Cavalry', 'Archers'],
            builder: buildStarterCardPool,
          ),
        ];
    }
  }

  Future<void> _confirmSelection() async {
    if (_selectedDeck == null || _isSubmitted) return;

    debugPrint(
      'DeckSelectionScreen: Confirming deck ${_selectedDeck!.id} for hero ${widget.heroId}',
    );

    setState(() => _isSubmitted = true);

    final deckCards = _selectedDeck!.builder();
    debugPrint(
      'DeckSelectionScreen: Built ${deckCards.length} cards. First: ${deckCards.first.name}',
    );

    if (widget.onlineMatchId != null) {
      // PvP Lobby Mode: Sync to Firebase
      try {
        final userId = _authService.currentUser?.uid;
        if (userId == null) return;
        // ... (rest of sync logic)
        final firestore = FirebaseFirestore.instance;
        final matchRef = firestore
            .collection('matches')
            .doc(widget.onlineMatchId);

        final doc = await matchRef.get();
        if (!doc.exists) return;

        final data = doc.data()!;
        final p1 = data['player1'] as Map<String, dynamic>;

        // Determine if we are player1 or player2
        final isPlayer1 = p1['userId'] == userId;
        final playerField = isPlayer1 ? 'player1' : 'player2';

        // Update player readiness and deck
        final cardNames = deckCards.map((c) => c.name).toList();

        await matchRef.update({
          '$playerField.ready': true,
          '$playerField.deck': cardNames,
          '$playerField.heroId': _hero.id,
        });
      } catch (e) {
        print('Error submitting deck: $e');
      }
    } else {
      // PvE OR Pre-Matchmaking Online: Callback
      widget.onDeckSelected?.call(deckCards);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text(
          widget.onlineMatchId != null
              ? 'Prepare for Battle'
              : 'Choose Your Army',
        ),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        automaticallyImplyLeading:
            widget.onlineMatchId == null, // Hide back button in PvP
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Timer for PvP
            if (widget.onlineMatchId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _secondsRemaining <= 10
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _secondsRemaining <= 10 ? Colors.red : Colors.green,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      '$_secondsRemaining s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[800],
                  child: Text(_hero.name.substring(0, 1)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hero.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Select your strategy',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Deck options
            Expanded(
              child: _isSubmitted && widget.onlineMatchId != null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 20),
                          Text(
                            'Waiting for opponent...',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _availableDecks.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildDeckOption(_availableDecks[index]),
                        );
                      },
                    ),
            ),

            // Confirm button
            if (!_isSubmitted) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedDeck != null ? _confirmSelection : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hero.id == 'saladin'
                        ? Colors.orange
                        : Colors.amber,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    disabledBackgroundColor: Colors.grey[700],
                  ),
                  child: Text(
                    _selectedDeck != null
                        ? (widget.onlineMatchId != null
                              ? 'Lock In Deck'
                              : (widget.isOnline
                                    ? 'Find Match'
                                    : 'Begin Campaign'))
                        : 'Select a Deck',
                    style: TextStyle(
                      color: _selectedDeck != null ? Colors.black : Colors.grey,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeckOption(DeckTemplate template) {
    final isSelected = _selectedDeck == template;

    return GestureDetector(
      onTap: () => setState(() => _selectedDeck = template),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? template.color.withValues(alpha: 0.2)
              : const Color(0xFF16213E),
          border: Border.all(
            color: isSelected ? template.color : Colors.grey[700]!,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: template.color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(template.icon, color: template.color, size: 32),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    template.description,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: template.unitPreview
                        .map(
                          (unit) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              unit,
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            // Selection indicator
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }
}
