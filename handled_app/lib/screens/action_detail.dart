import 'dart:convert';
import 'package:flutter/material.dart';
import '../ops_labels.dart';
import '../theme.dart';

/// The full record for a single action.
///
/// This is where the audit trail stops being a claim and becomes something you
/// can read: what the agent drafted, what a human actually authorised, which
/// fields the human typed in themselves, and who decided what, when. For a
/// purchase order the draft is deliberately shown *next to* the final, because
/// the difference between them is the entire safety argument.
void showActionDetail(BuildContext context, Map<String, dynamic> action) {
  showDialog(
    context: context,
    builder: (_) => _ActionDetailDialog(action: action),
  );
}

const _prettyJson = JsonEncoder.withIndent('  ');

/// Fields the human is required to type in themselves on an approval.
/// Mirrors TOOL_REGISTRY's manual_fields in the backend.
const _manualFields = {'quantity', 'amount'};

class _ActionDetailDialog extends StatelessWidget {
  final Map<String, dynamic> action;
  const _ActionDetailDialog({required this.action});

  Map<String, dynamic> get _draft =>
      (action['draft_output'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> get _final =>
      (action['final_output'] as Map?)?.cast<String, dynamic>() ?? {};

  String get _bucket => action['action_type'] as String? ?? '';
  String get _status => action['status'] as String? ?? '';

  /// The agent's own prose, wherever it lives for this tool shape.
  String? get _agentText {
    final src = _final.isNotEmpty ? _final : _draft;
    return (src['body'] ?? src['agent_output'])?.toString();
  }

  /// Values a human typed that the agent never supplied — the money shot.
  Map<String, dynamic> get _humanEntered {
    final out = <String, dynamic>{};
    for (final entry in _final.entries) {
      final isManual = _manualFields.contains(entry.key);
      final addedByHuman = !_draft.containsKey(entry.key);
      if (isManual || (addedByHuman && entry.value is! Map && entry.value is! List)) {
        if (entry.key == 'agent_output' || entry.key == 'input') continue;
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final toolName = action['tool_name'] as String? ?? '';

    return Dialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, toolName),
            const Divider(height: 1, color: AppTheme.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _whyThisBucket(context),
                    const SizedBox(height: 20),
                    if (_agentText != null) ...[
                      _sectionLabel(context, 'What the agent produced'),
                      const SizedBox(height: 8),
                      _panel(child: SelectableText(
                        _agentText!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                      )),
                      const SizedBox(height: 20),
                    ],
                    if (_humanEntered.isNotEmpty) ...[
                      _sectionLabel(context, 'What the human typed in'),
                      const SizedBox(height: 4),
                      Text(
                        'The agent is not allowed to supply these — they are entered by hand at approval.',
                        style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      _humanFieldsPanel(context),
                      const SizedBox(height: 20),
                    ],
                    _trail(context),
                    const SizedBox(height: 20),
                    _rawRecord(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String toolName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kToolLabels[toolName] ?? toolName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OpsBadge(
                    text: kBucketLabels[_bucket] ?? _bucket,
                    color: kBucketColors[_bucket] ?? AppTheme.textSecondary,
                  ),
                  OpsBadge(
                    text: kStatusLabels[_status] ?? _status,
                    color: kStatusColors[_status] ?? AppTheme.textSecondary,
                  ),
                ]),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  /// States the rule this action was held to — and that a human picked that
  /// rule in advance, rather than the model deciding at runtime.
  Widget _whyThisBucket(BuildContext context) {
    final colour = kBucketColors[_bucket] ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kBucketBlurbs[_bucket] ?? '',
                  style: TextStyle(color: colour, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  'This tier is fixed in code for this tool, not chosen by the model.',
                  style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _humanFieldsPanel(BuildContext context) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _humanEntered.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      e.key.replaceAll('_', ' '),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                  Text(
                    e.key == 'amount' ? '₹${e.value}' : '${e.value}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.lightGreenAccent,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trail(BuildContext context) {
    final created = _formatTs(action['created_at']);
    final approvedAt = _formatTs(action['approved_at']);
    final requestedBy = action['requested_by_name'] as String?;
    final approvedBy = action['approved_by_name'] as String?;
    final decided = _status == 'rejected' ? 'Rejected' : 'Approved';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, 'Trail'),
        const SizedBox(height: 8),
        _trailRow(Icons.play_arrow_outlined, 'Triggered',
            [if (requestedBy != null) 'by $requestedBy', ?created].join(' · ')),
        if (approvedBy != null || approvedAt != null)
          _trailRow(
            _status == 'rejected' ? Icons.block_outlined : Icons.check_circle_outline,
            decided,
            [if (approvedBy != null) 'by $approvedBy', ?approvedAt].join(' · '),
            colour: _status == 'rejected' ? Colors.redAccent : Colors.lightGreenAccent,
          ),
        if (_status == 'pending_approval')
          _trailRow(Icons.hourglass_empty, 'Waiting', 'No human has decided yet',
              colour: Colors.orange),
        if ((action['decision_note'] as String?)?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          _trailRow(Icons.notes_outlined, 'Reason', action['decision_note'].toString()),
        ],
      ],
    );
  }

  Widget _trailRow(IconData icon, String label, String detail, {Color? colour}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: colour ?? AppTheme.textSecondary),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    color: colour ?? AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(detail,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// The unedited stored record. Present because "we log everything" is worth
  /// being able to prove on the spot rather than assert.
  Widget _rawRecord(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        title: Text('Stored record',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
        subtitle: Text('The row exactly as saved — drafts are never overwritten',
            style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75), fontSize: 11)),
        children: [
          _panel(
            child: SelectableText(
              _prettyJson.convert({
                'id': action['id'],
                'tool_name': action['tool_name'],
                'action_type': action['action_type'],
                'status': action['status'],
                'draft_output': action['draft_output'],
                'final_output': action['final_output'],
              }),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7),
      );

  Widget _panel({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );
}

/// "2026-09-19T14:32:10.12" -> "19 Sep 2026, 14:32"
String? _formatTs(dynamic raw) {
  if (raw == null) return null;
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hh:$mm';
}
