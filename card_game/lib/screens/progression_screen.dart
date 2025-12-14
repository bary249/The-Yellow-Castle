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
  final GlobalKey _treeKey = GlobalKey();
  final Map<String, GlobalKey> _nodeKeys = <String, GlobalKey>{};
  List<_NodeConnection> _connections = const <_NodeConnection>[];
  bool _connectionsDirty = true;
  bool _connectionsScheduled = false;

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
        _connectionsDirty = true;
      });
    }
  }

  GlobalKey _keyForNode(String nodeId) {
    return _nodeKeys.putIfAbsent(nodeId, () => GlobalKey());
  }

  void _scheduleRebuildConnectionsIfNeeded() {
    if (_connectionsScheduled) return;
    if (!_connectionsDirty) return;
    _connectionsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectionsScheduled = false;
      if (!mounted) return;
      final treeContext = _treeKey.currentContext;
      if (treeContext == null) return;

      final treeBox = treeContext.findRenderObject();
      if (treeBox is! RenderBox) return;

      final next = <_NodeConnection>[];
      for (final node in NapoleonProgression.nodes) {
        if (node.prerequisites.isEmpty) continue;
        final toKey = _nodeKeys[node.id];
        final toContext = toKey?.currentContext;
        if (toContext == null) continue;
        final toBox = toContext.findRenderObject();
        if (toBox is! RenderBox) continue;

        final end = toBox.localToGlobal(
          Offset(toBox.size.width / 2, 0),
          ancestor: treeBox,
        );

        for (final prereqId in node.prerequisites) {
          final fromKey = _nodeKeys[prereqId];
          final fromContext = fromKey?.currentContext;
          if (fromContext == null) continue;
          final fromBox = fromContext.findRenderObject();
          if (fromBox is! RenderBox) continue;

          final start = fromBox.localToGlobal(
            Offset(fromBox.size.width / 2, fromBox.size.height),
            ancestor: treeBox,
          );

          next.add(
            _NodeConnection(
              fromId: prereqId,
              toId: node.id,
              start: start,
              end: end,
            ),
          );
        }
      }

      setState(() {
        _connections = next;
        _connectionsDirty = false;
      });
    });
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

    _scheduleRebuildConnectionsIfNeeded();

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
        child: CustomPaint(
          key: _treeKey,
          painter: _ProgressionConnectionsPainter(
            connections: _connections,
            unlockedNodes: _state.unlockedNodes,
          ),
          child: Column(
            children: [
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
              _buildTierSection(0, 'Origin'),
              const SizedBox(height: 16),
              _buildTierSection(1, 'First Steps'),
              const SizedBox(height: 16),
              _buildTierSection(2, 'Specialization'),
              const SizedBox(height: 16),
              _buildTierSection(3, 'Mastery'),
            ],
          ),
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
        key: _keyForNode(node.id),
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
                  setState(() {
                    _connectionsDirty = true;
                  });
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

class _NodeConnection {
  final String fromId;
  final String toId;
  final Offset start;
  final Offset end;

  const _NodeConnection({
    required this.fromId,
    required this.toId,
    required this.start,
    required this.end,
  });
}

class _ProgressionConnectionsPainter extends CustomPainter {
  final List<_NodeConnection> connections;
  final Set<String> unlockedNodes;

  _ProgressionConnectionsPainter({
    required this.connections,
    required this.unlockedNodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in connections) {
      final bool fromUnlocked = unlockedNodes.contains(c.fromId);
      final bool toUnlocked = unlockedNodes.contains(c.toId);
      final bool active = fromUnlocked && toUnlocked;

      final paint = Paint()
        ..color = active
            ? Colors.amber.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = active ? 3 : 2
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(c.start.dx, c.start.dy);

      final midY = (c.start.dy + c.end.dy) / 2;
      path.cubicTo(c.start.dx, midY, c.end.dx, midY, c.end.dx, c.end.dy);

      canvas.drawPath(path, paint);

      if (active) {
        final dotPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(c.end, 3.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressionConnectionsPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.unlockedNodes != unlockedNodes;
  }
}
