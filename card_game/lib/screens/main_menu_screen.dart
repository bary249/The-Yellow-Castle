import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'test_match_screen.dart';
import 'matchmaking_screen.dart';

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
    ).push(MaterialPageRoute(builder: (_) => const TestMatchScreen()));
  }

  void _playOnline() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MatchmakingScreen()));
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
                child: Center(
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

          // Settings button (placeholder)
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings coming soon!')),
              );
            },
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
