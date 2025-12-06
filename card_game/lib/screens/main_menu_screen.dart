import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'hero_selection_screen.dart';
import 'matchmaking_screen.dart';
import 'deck_editor_screen.dart';
import 'campaign_select_screen.dart';
import 'ui_test_screen.dart';

/// Main menu screen with Play vs AI and Play Online options
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final AuthService _authService = AuthService();

  String? _playerName;
  int? _playerElo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlayerProfile();
  }

  Future<void> _loadPlayerProfile() async {
    final user = _authService.currentUser;
    if (user != null) {
      final profile = await _authService.getUserProfile(user.uid);
      if (mounted) {
        setState(() {
          _playerName = profile?['displayName'] as String? ?? 'Player';
          _playerElo = profile?['elo'] as int? ?? 1000;
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _playerName = 'Guest';
        _playerElo = 1000;
        _isLoading = false;
      });
    }
  }

  void _playVsAI() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HeroSelectionScreen()));
  }

  void _playOnline() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MatchmakingScreen()));
  }

  void _editDeck() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DeckEditorScreen()));
  }

  void _openUITest() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UITestScreen()));
  }

  void _playCampaign() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CampaignSelectScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: SafeArea(
          child: Column(
            children: [
              // Player info header
              _buildPlayerHeader(),

              // Main content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Game title
                      const Text(
                        '⚔️ Land of Clans',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const Text(
                        '& Wanderers',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 60),

                      // Campaign button
                      _buildMenuButton(
                        icon: Icons.military_tech,
                        label: 'CAMPAIGN',
                        sublabel: 'Lead your army to glory!',
                        color: Colors.orange,
                        onTap: _playCampaign,
                      ),

                      const SizedBox(height: 20),

                      // Play vs AI button
                      _buildMenuButton(
                        icon: Icons.smart_toy,
                        label: 'PLAY vs AI',
                        sublabel: 'Practice against computer',
                        color: Colors.green,
                        onTap: _playVsAI,
                      ),

                      const SizedBox(height: 20),

                      // Play Online button
                      _buildMenuButton(
                        icon: Icons.public,
                        label: 'PLAY ONLINE',
                        sublabel: 'Battle real players!',
                        color: Colors.blue,
                        onTap: _playOnline,
                        enabled: true,
                      ),

                      const SizedBox(height: 20),

                      // Deck Editor button
                      _buildMenuButton(
                        icon: Icons.style,
                        label: 'EDIT DECK',
                        sublabel: 'Customize your cards',
                        color: Colors.amber,
                        onTap: _editDeck,
                      ),

                      const SizedBox(height: 20),

                      // UI Test button (dev only)
                      _buildMenuButton(
                        icon: Icons.science,
                        label: 'UI TEST',
                        sublabel: 'Test stacked cards & drag/drop',
                        color: Colors.purple,
                        onTap: _openUITest,
                      ),

                      const SizedBox(height: 40),

                      // Firebase connection status
                      _buildConnectionStatus(),
                    ],
                  ),
                ),
              ),

              // Version / footer
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'v0.1.0 - Alpha',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),

          // Name and ELO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading)
                  const Text(
                    'Loading...',
                    style: TextStyle(color: Colors.white70),
                  )
                else ...[
                  Text(
                    _playerName ?? 'Player',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: Colors.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ELO: ${_playerElo ?? 1000}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Account menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: Colors.grey[900],
            onSelected: (value) async {
              if (value == 'logout') {
                await _authService.signOut();
                // Auth wrapper will automatically show login screen
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'account',
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _authService.currentUser?.email ?? 'Guest Account',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    if (_authService.currentUser?.isAnonymous == true)
                      const Text(
                        '(Guest - Sign up to save progress)',
                        style: TextStyle(color: Colors.amber, fontSize: 10),
                      ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? [color.withValues(alpha: 0.8), color]
                : [Colors.grey[600]!, Colors.grey[700]!],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: enabled ? color.withValues(alpha: 0.4) : Colors.black26,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final isConnected = _authService.isSignedIn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.cloud_done : Icons.cloud_off,
            color: isConnected ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Connected to Firebase' : 'Offline',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
