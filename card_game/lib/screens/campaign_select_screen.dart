import 'package:flutter/material.dart';
import 'campaign_map_screen.dart';
import 'deck_selection_screen.dart';

/// Campaign selection screen - choose which leader's campaign to play
class CampaignSelectScreen extends StatelessWidget {
  const CampaignSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.brown[900]!,
              Colors.brown[700]!,
              Colors.orange[900]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'SELECT CAMPAIGN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Campaign cards
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Napoleon Campaign
                    _CampaignCard(
                      leaderName: 'Napoleon Bonaparte',
                      subtitle: 'Emperor of France',
                      description:
                          'Lead the Grande Armée across Europe. Command elite infantry, devastating artillery, and legendary cavalry.',
                      icon: Icons.military_tech,
                      color: Colors.blue[800]!,
                      isAvailable: true,
                      onTap: () => _startNapoleonCampaign(context),
                    ),

                    const SizedBox(height: 20),

                    // Saladin Campaign (Coming Soon)
                    _CampaignCard(
                      leaderName: 'Saladin',
                      subtitle: 'Sultan of Egypt',
                      description:
                          'Unite the Muslim world and defend the Holy Land with swift cavalry and cunning tactics.',
                      icon: Icons.shield,
                      color: Colors.green[800]!,
                      isAvailable: false,
                      onTap: null,
                    ),

                    const SizedBox(height: 20),

                    // Genghis Khan Campaign (Coming Soon)
                    _CampaignCard(
                      leaderName: 'Genghis Khan',
                      subtitle: 'Great Khan of the Mongols',
                      description:
                          'Conquer the world with unstoppable horse archers and brutal siege warfare.',
                      icon: Icons.sports_martial_arts,
                      color: Colors.red[800]!,
                      isAvailable: false,
                      onTap: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startNapoleonCampaign(BuildContext context) {
    // Navigate to deck selection first
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeckSelectionScreen(
          heroId: 'napoleon',
          onDeckSelected: (deck) {
            // After deck selection, go to campaign map
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    const CampaignMapScreen(leaderId: 'napoleon', act: 1),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A card representing a campaign option
class _CampaignCard extends StatelessWidget {
  final String leaderName;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final bool isAvailable;
  final VoidCallback? onTap;

  const _CampaignCard({
    required this.leaderName,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isAvailable ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isAvailable
                ? [color.withValues(alpha: 0.8), color]
                : [Colors.grey[700]!, Colors.grey[800]!],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isAvailable
                  ? color.withValues(alpha: 0.4)
                  : Colors.black26,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isAvailable ? Colors.amber : Colors.grey[600]!,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leaderName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isAvailable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'COMING SOON',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (isAvailable) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'START CAMPAIGN',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.play_arrow, color: Colors.black, size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
