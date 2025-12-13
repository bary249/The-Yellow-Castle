import 'package:flutter/material.dart';
import '../data/napoleon_progression.dart';
import '../services/campaign_persistence_service.dart';

/// Screen to view and manage Napoleon's progression tree
class ProgressionScreen extends StatefulWidget {
  final NapoleonProgressionState? progressionState;
  final VoidCallback? onStateChanged;
  final bool viewOnly;

  const ProgressionScreen({
    super.key,
    this.progressionState,
    this.onStateChanged,
    this.viewOnly = false,
  });

  @override
  State<ProgressionScreen> createState() => _ProgressionScreenState();
}

class _ProgressionScreenState extends State<ProgressionScreen> {
  late NapoleonProgressionState _state;
  bool _isLoading = true;
  final CampaignPersistenceService _persistence = CampaignPersistenceService();

  @override
  void initState() {
    super.initState();
    if (widget.progressionState != null) {
      _state = widget.progressionState!;
      _isLoading = false;
    } else {
      _loadProgression();
    }
  }

  Future<void> _loadProgression() async {
    final data = await _persistence.loadProgression();
    if (mounted) {
      setState(() {
        if (data != null) {
          _state = NapoleonProgressionState.fromJson(data);
        } else {
          _state = NapoleonProgressionState(); // Default start state
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProgression() async {
    await _persistence.saveProgression(_state.toJson());
    widget.onStateChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Napoleon\'s Legacy'),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  '${_state.progressionPoints} Points',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Info card
            Card(
              color: const Color(0xFF16213E),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Progression Tree',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Earn progression points by completing campaigns.\nUnlock abilities to strengthen Napoleon.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tier 0 - Start
            _buildTierSection(0, 'Origin'),
            const SizedBox(height: 16),

            // Tier 1 - First choices
            _buildTierSection(1, 'First Steps'),
            const SizedBox(height: 16),

            // Tier 2 - Specializations
            _buildTierSection(2, 'Specialization'),
            const SizedBox(height: 16),

            // Tier 3 - Mastery
            _buildTierSection(3, 'Mastery'),
          ],
        ),
      ),
    );
  }

  Widget _buildTierSection(int tier, String title) {
    final nodes = NapoleonProgression.getNodesAtTier(tier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.amber[300],
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: nodes.map((node) => _buildNodeCard(node)).toList(),
        ),
      ],
    );
  }

  Widget _buildNodeCard(ProgressionNode node) {
    final isUnlocked = _state.unlockedNodes.contains(node.id);
    final canUnlock = NapoleonProgression.canUnlock(
      node.id,
      _state.unlockedNodes,
    );
    final canAfford = _state.progressionPoints >= node.cost;

    Color borderColor;
    Color bgColor;
    if (isUnlocked) {
      borderColor = Colors.amber;
      bgColor = Colors.amber.withValues(alpha: 0.2);
    } else if (canUnlock && canAfford) {
      borderColor = Colors.green;
      bgColor = Colors.green.withValues(alpha: 0.1);
    } else if (canUnlock) {
      borderColor = Colors.grey;
      bgColor = Colors.grey.withValues(alpha: 0.1);
    } else {
      borderColor = Colors.grey[800]!;
      bgColor = Colors.grey[900]!;
    }

    return GestureDetector(
      onTap: () => _showNodeDetails(node, isUnlocked, canUnlock, canAfford),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getNodeIcon(node.type),
                  color: isUnlocked ? Colors.amber : Colors.grey,
                  size: 20,
                ),
                const Spacer(),
                if (!isUnlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: canAfford ? Colors.green : Colors.grey[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${node.cost}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isUnlocked)
                  const Icon(Icons.check_circle, color: Colors.amber, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              node.name,
              style: TextStyle(
                color: isUnlocked ? Colors.white : Colors.grey[400],
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              node.description,
              style: TextStyle(
                color: isUnlocked ? Colors.grey[300] : Colors.grey[600],
                fontSize: 11,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getNodeIcon(ProgressionNodeType type) {
    switch (type) {
      case ProgressionNodeType.heroAbility:
        return Icons.flash_on;
      case ProgressionNodeType.deckBonus:
        return Icons.style;
      case ProgressionNodeType.startingBonus:
        return Icons.rocket_launch;
      case ProgressionNodeType.special:
        return Icons.stars;
    }
  }

  void _showNodeDetails(
    ProgressionNode node,
    bool isUnlocked,
    bool canUnlock,
    bool canAfford,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            Icon(_getNodeIcon(node.type), color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.description,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (!isUnlocked) ...[
              Row(
                children: [
                  const Icon(Icons.stars, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Cost: ${node.cost} points',
                    style: TextStyle(
                      color: canAfford ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              if (node.prerequisites.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Requires: ${node.prerequisites.map((p) => NapoleonProgression.getNode(p)?.name ?? p).join(", ")}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text(
                    'Unlocked!',
                    style: TextStyle(color: Colors.green),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (!widget.viewOnly && !isUnlocked && canUnlock && canAfford)
            ElevatedButton(
              onPressed: () async {
                if (_state.unlock(node.id)) {
                  await _saveProgression();
                  setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Unlocked: ${node.name}!')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: Text('Unlock (${node.cost} pts)'),
            ),
        ],
      ),
    );
  }
}
