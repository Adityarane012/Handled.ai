import 'package:flutter/material.dart';
import '../ops_labels.dart';
import '../services/api_service.dart';
import '../theme.dart';

/// Full audit trail — every action the agent has taken or drafted, across
/// all three autonomy buckets. This is the screen that makes the tiered-
/// autonomy pitch visible: what ran on its own, what went out under a fixed
/// template, and what a human had to approve or reject.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _actions = [];
  bool _isLoading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getList('/ops/history');
      setState(() {
        _actions = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = ApiService.friendlyError(e);
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filtered =>
      _filter == 'all' ? _actions : _actions.where((a) => a['action_type'] == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('History', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            'Every action the agent has taken or drafted — the full audit trail.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _FilterBar(current: _filter, onChanged: (f) => setState(() => _filter = f)),
          const SizedBox(height: 24),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _actions.isEmpty
              ? 'No actions yet — run a tool from Ops Tools to see it here.'
              : 'Nothing in this bucket yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _HistoryCard(action: items[i]),
    );
  }
}

class _FilterOption {
  final String value;
  final String label;
  const _FilterOption(this.value, this.label);
}

const _filterOptions = [
  _FilterOption('all', 'All'),
  _FilterOption('auto', 'Auto'),
  _FilterOption('template_restricted', 'Template'),
  _FilterOption('approval_required', 'Approval Required'),
];

class _FilterBar extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _FilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _filterOptions.map((o) {
        final selected = current == o.value;
        return ChoiceChip(
          label: Text(o.label),
          selected: selected,
          onSelected: (_) => onChanged(o.value),
          selectedColor: AppTheme.primaryAction,
          backgroundColor: AppTheme.surface,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontSize: 13,
          ),
          side: BorderSide(color: AppTheme.border),
        );
      }).toList(),
    );
  }
}

class _HistoryCard extends StatefulWidget {
  final Map<String, dynamic> action;
  const _HistoryCard({required this.action});

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;

  String _preview() {
    final out = (widget.action['final_output'] ?? widget.action['draft_output']) as Map<String, dynamic>?;
    if (out == null) return 'No output.';
    if (out['body'] != null) return out['body'].toString();
    if (out['agent_output'] != null) return out['agent_output'].toString();
    if (out['error'] != null) return 'Error: ${out['error']}';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final toolName = widget.action['tool_name'] as String? ?? '';
    final bucket = widget.action['action_type'] as String? ?? '';
    final status = widget.action['status'] as String? ?? '';
    final createdAt = widget.action['created_at']?.toString();
    final preview = _preview();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OpsBadge(text: kBucketLabels[bucket] ?? bucket, color: kBucketColors[bucket] ?? AppTheme.textSecondary),
              const SizedBox(width: 8),
              OpsBadge(text: kStatusLabels[status] ?? status, color: kStatusColors[status] ?? AppTheme.textSecondary),
              const Spacer(),
              Text(
                createdAt != null && createdAt.length >= 16
                    ? createdAt.substring(0, 16).replaceFirst('T', ' ')
                    : '',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(kToolLabels[toolName] ?? toolName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            preview,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (preview.length > 120)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show more'),
              ),
            ),
        ],
      ),
    );
  }
}
