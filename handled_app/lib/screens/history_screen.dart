import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../agent_text.dart';
import '../ops_labels.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'action_detail.dart';

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
      final noneAtAll = _actions.isEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(noneAtAll ? Icons.history_outlined : Icons.filter_alt_off_outlined,
                size: 44, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 18),
            Text(
              noneAtAll ? 'No actions recorded yet' : 'Nothing in this tier yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 380,
              child: Text(
                noneAtAll
                    ? 'Every action the agent takes is written here permanently — including '
                      'the ones that run without asking. Run a tool to see the first entry.'
                    : 'No actions have fallen into this tier so far. Try another filter.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            if (noneAtAll) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.go('/ops'),
                icon: const Icon(Icons.bolt_outlined, size: 18),
                label: const Text('Go to Ops Tools'),
              ),
            ],
          ],
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

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> action;
  const _HistoryCard({required this.action});

  String _preview() {
    final out = (action['final_output'] ?? action['draft_output']) as Map<String, dynamic>?;
    if (out == null) return 'No output.';
    // Flattened, not rendered: these rows are two lines of summary, so the
    // markdown markers are stripped rather than shown as "**Heading**".
    if (out['body'] != null) return plainAgentText(out['body'].toString());
    if (out['agent_output'] != null) return plainAgentText(out['agent_output'].toString());
    if (out['error'] != null) return 'Error: ${out['error']}';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final toolName = action['tool_name'] as String? ?? '';
    final bucket = action['action_type'] as String? ?? '';
    final status = action['status'] as String? ?? '';
    final createdAt = action['created_at']?.toString();
    final approvedByName = action['approved_by_name'] as String?;
    final preview = _preview();

    return InkWell(
      onTap: () => showActionDetail(context, action),
      borderRadius: BorderRadius.circular(8),
      hoverColor: AppTheme.surfaceHighlight.withValues(alpha: 0.4),
      child: Container(
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
                formatTimestamp(createdAt) ?? '',
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (approvedByName != null)
                Expanded(
                  child: Text(
                    '${status == 'rejected' ? 'Rejected' : 'Approved'} by $approvedByName',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              Text('View full record',
                  style: TextStyle(
                      color: AppTheme.primaryAction.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward, size: 12, color: AppTheme.primaryAction.withValues(alpha: 0.9)),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
