import 'package:flutter/material.dart';
import '../models/hero.dart';
import '../data/hero_library.dart';
import 'test_match_screen.dart';

/// Screen for selecting a hero before starting a match.
class HeroSelectionScreen extends StatefulWidget {
  const HeroSelectionScreen({super.key});

  @override
  State<HeroSelectionScreen> createState() => _HeroSelectionScreenState();
}

class _HeroSelectionScreenState extends State<HeroSelectionScreen> {
  GameHero? _selectedHero;

  @override
  void initState() {
    super.initState();
    // Default to first hero
    _selectedHero = HeroLibrary.allHeroes.first;
  }

  void _startMatch() {
    if (_selectedHero == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TestMatchScreen(selectedHero: _selectedHero),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Army'),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.indigo[900]!,
              Colors.indigo[700]!,
              Colors.purple[900]!,
            ],
          ),
        ),
        child: Column(
          children: [
            // Hero list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: HeroLibrary.allHeroes.length,
                itemBuilder: (context, index) {
                  final hero = HeroLibrary.allHeroes[index];
                  final isSelected = _selectedHero?.id == hero.id;

                  return _buildHeroCard(hero, isSelected);
                },
              ),
            ),

            // Start button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _selectedHero != null ? _startMatch : null,
                  icon: const Icon(Icons.play_arrow, size: 28),
                  label: const Text(
                    'START MATCH',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(GameHero hero, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedHero = hero;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber[100] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.grey[300]!,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Hero avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _getHeroColor(hero),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    _getHeroInitials(hero),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Hero info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hero.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getArmyName(hero),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.terrain,
                          size: 14,
                          color: Colors.brown,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hero.terrainAffinities.join(', '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.flash_on,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              hero.abilityDescription,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Selection indicator
              if (isSelected)
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
            ],
          ),
        ),
      ),
    );
  }

  Color _getHeroColor(GameHero hero) {
    switch (hero.id) {
      case 'napoleon':
        return Colors.blue[700]!;
      case 'saladin':
        return Colors.orange[700]!;
      case 'admiral_nelson':
        return Colors.teal[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  String _getArmyName(GameHero hero) {
    switch (hero.id) {
      case 'napoleon':
        return "French Grand Army";
      case 'saladin':
        return "Desert Warriors";
      case 'admiral_nelson':
        return "Royal Navy";
      case 'archduke_charles':
        return "Austrian Forces";
      default:
        return "Standard Army";
    }
  }

  String _getHeroInitials(GameHero hero) {
    final parts = hero.name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return hero.name.substring(0, 2).toUpperCase();
  }
}
