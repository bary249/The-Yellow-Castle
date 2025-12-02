import 'package:flutter/material.dart';
import '../models/card.dart';
import '../data/card_library.dart';

/// Starter deck options for campaign
enum StarterDeckType {
  balanced, // Mix of units
  aggressive, // High damage, low HP
  defensive, // High HP, shields
  artillery, // Ranged focus
}

/// Screen to select starting deck for a campaign
class DeckSelectionScreen extends StatefulWidget {
  final String heroId;
  final Function(List<GameCard>) onDeckSelected;

  const DeckSelectionScreen({
    super.key,
    required this.heroId,
    required this.onDeckSelected,
  });

  @override
  State<DeckSelectionScreen> createState() => _DeckSelectionScreenState();
}

class _DeckSelectionScreenState extends State<DeckSelectionScreen> {
  StarterDeckType? _selectedDeck;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Choose Your Army'),
        backgroundColor: const Color(0xFF16213E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            const Text(
              '⚔️ Select Your Starting Forces',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the composition of your army for this campaign.',
              style: TextStyle(color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Deck options
            Expanded(
              child: ListView(
                children: [
                  _buildDeckOption(
                    StarterDeckType.balanced,
                    'Balanced Army',
                    'A well-rounded force with infantry, cavalry, and artillery.',
                    Icons.balance,
                    Colors.blue,
                    [
                      'Line Infantry x6',
                      'Fusiliers x4',
                      'Hussars x4',
                      'Field Cannon x2',
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDeckOption(
                    StarterDeckType.aggressive,
                    'Assault Force',
                    'Fast, hard-hitting units. Strike before they can react!',
                    Icons.flash_on,
                    Colors.red,
                    [
                      'Grenadiers x4',
                      'Hussars x6',
                      'Voltigeurs x4',
                      'Cuirassiers x2',
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDeckOption(
                    StarterDeckType.defensive,
                    'Defensive Line',
                    'Sturdy units that can hold the line against any assault.',
                    Icons.shield,
                    Colors.green,
                    ['Line Infantry x8', 'Fusiliers x6', 'Field Cannon x2'],
                  ),
                  const SizedBox(height: 12),
                  _buildDeckOption(
                    StarterDeckType.artillery,
                    'Artillery Corps',
                    'Rain fire from afar. Ranged units dominate the battlefield.',
                    Icons.gps_fixed,
                    Colors.orange,
                    ['Field Cannon x6', 'Voltigeurs x6', 'Line Infantry x4'],
                  ),
                ],
              ),
            ),

            // Confirm button
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedDeck != null ? _confirmSelection : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  disabledBackgroundColor: Colors.grey[700],
                ),
                child: Text(
                  _selectedDeck != null ? 'Begin Campaign' : 'Select a Deck',
                  style: TextStyle(
                    color: _selectedDeck != null ? Colors.black : Colors.grey,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeckOption(
    StarterDeckType type,
    String name,
    String description,
    IconData icon,
    Color color,
    List<String> units,
  ) {
    final isSelected = _selectedDeck == type;

    return GestureDetector(
      onTap: () => setState(() => _selectedDeck = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : const Color(0xFF16213E),
          border: Border.all(
            color: isSelected ? color : Colors.grey[700]!,
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
                color: color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: units
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

  void _confirmSelection() {
    if (_selectedDeck == null) return;

    final deck = _buildDeck(_selectedDeck!);
    widget.onDeckSelected(deck);
  }

  List<GameCard> _buildDeck(StarterDeckType type) {
    switch (type) {
      case StarterDeckType.balanced:
        return [
          // Line Infantry x6
          ...List.generate(6, (i) => napoleonLineInfantry(i)),
          // Fusiliers x4
          ...List.generate(4, (i) => napoleonFusilier(10 + i)),
          // Hussars x4
          ...List.generate(4, (i) => napoleonHussar(20 + i)),
          // Field Cannon x2
          ...List.generate(2, (i) => napoleonFieldCannon(30 + i)),
        ];

      case StarterDeckType.aggressive:
        return [
          // Grenadiers x4
          ...List.generate(4, (i) => napoleonGrenadier(i)),
          // Hussars x6
          ...List.generate(6, (i) => napoleonHussar(10 + i)),
          // Voltigeurs x4
          ...List.generate(4, (i) => napoleonVoltigeur(20 + i)),
          // Cuirassiers x2
          ...List.generate(2, (i) => napoleonCuirassier(30 + i)),
        ];

      case StarterDeckType.defensive:
        return [
          // Line Infantry x8
          ...List.generate(8, (i) => napoleonLineInfantry(i)),
          // Fusiliers x6
          ...List.generate(6, (i) => napoleonFusilier(10 + i)),
          // Field Cannon x2
          ...List.generate(2, (i) => napoleonFieldCannon(20 + i)),
        ];

      case StarterDeckType.artillery:
        return [
          // Field Cannon x6
          ...List.generate(6, (i) => napoleonFieldCannon(i)),
          // Voltigeurs x6
          ...List.generate(6, (i) => napoleonVoltigeur(10 + i)),
          // Line Infantry x4
          ...List.generate(4, (i) => napoleonLineInfantry(20 + i)),
        ];
    }
  }
}
