import 'package:flutter/material.dart';
import '../ops_labels.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ApprovalQueueScreen extends StatefulWidget {
  const ApprovalQueueScreen({super.key});

  @override
  State<ApprovalQueueScreen> createState() => _ApprovalQueueScreenState();
}

class _ApprovalQueueScreenState extends State<ApprovalQueueScreen> {
  List<dynamic> _pendingApprovals = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchApprovals();
  }

  Future<void> _fetchApprovals() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getList('/ops/approvals');
      setState(() {
        _pendingApprovals = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Error loading approvals', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _fetchApprovals, child: const Text('Retry'))
          ],
        ),
      );
    }

    if (_pendingApprovals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.textSecondary.withValues(alpha: 0.5), size: 64),
            const SizedBox(height: 24),
            Text('All caught up', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24)),
            const SizedBox(height: 8),
            Text('No tasks pending your approval.', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending Approvals', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
          const SizedBox(height: 8),
          Text('Review and approve actions drafted by the operations agent.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              itemCount: _pendingApprovals.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return _ApprovalCard(
                  action: _pendingApprovals[index],
                  onResolved: _fetchApprovals,
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  final Map<String, dynamic> action;
  final VoidCallback onResolved;

  const _ApprovalCard({required this.action, required this.onResolved});

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  final _quantityController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSubmitting = false;

  int? get _quantity => int.tryParse(_quantityController.text.trim());
  double? get _amount => double.tryParse(_amountController.text.trim());

  Future<void> _submitDecision(String decision) async {
    setState(() => _isSubmitting = true);

    Map<String, dynamic> manualFields = {};
    if (widget.action['tool_name'] == 'purchase_order_approval' && decision == 'approved') {
      // canApprove already gates the button on both being valid positive
      // numbers, but the ints/doubles are re-read here (not defaulted to 0)
      // so a bad parse can never silently become a real approval.
      manualFields = {
        'quantity': _quantity!,
        'amount': _amount!,
      };
    }

    try {
      await ApiService.post('/ops/approve', {
        'action_id': widget.action['id'],
        'decision': decision,
        'manual_fields': manualFields
      });
      widget.onResolved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _isSubmitting = false);
    }
  }

  String _titleForTool(String? toolName) {
    switch (toolName) {
      case 'workflow_exception_approval':
        return 'Workflow Exception — needs a decision';
      case 'purchase_order_approval':
        return 'Purchase Order Request';
      default:
        return toolName ?? 'Pending action';
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.action['draft_output'] ?? {};
    final isPO = widget.action['tool_name'] == 'purchase_order_approval';
    
    // Safety check: isPO requires manually-typed, valid positive numbers
    // before approval — a non-numeric or zero entry must NOT enable the
    // button (silently defaulting to 0 would defeat the point of making
    // the human type the real figure in).
    bool canApprove = true;
    if (isPO) {
      canApprove = (_quantity ?? 0) > 0 && (_amount ?? 0) > 0;
    }

    final input = (draft['input'] as Map?) ?? const {};
    final itemName = input['item_name'] ?? draft['item_name'] ?? 'Unknown item';

    return Container(
      padding: const EdgeInsets.all(24),
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
              const OpsBadge(text: 'Approval Required', color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Blocked until a human decides',
                style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), fontSize: 11),
              ),
              const Spacer(),
              Text(
                widget.action['created_at']?.toString().substring(0, 10) ?? '',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isPO ? 'Purchase Order: $itemName' : _titleForTool(widget.action['tool_name']),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),

          if (isPO) ...[
            Wrap(spacing: 24, runSpacing: 6, children: [
              _fact('Current stock', '${input['current_stock'] ?? draft['current_stock'] ?? '-'}'),
              _fact('Vendor', '${input['preferred_vendor'] ?? draft['preferred_vendor'] ?? 'Not specified'}'),
              if (input['reorder_reason'] != null) _fact('Trigger', '${input['reorder_reason']}'),
            ]),
            const SizedBox(height: 16),
          ],

          _draftPanel(
            context,
            label: isPO ? 'What the agent drafted' : 'Agent reasoning',
            text: draft['agent_output'] ?? draft['agent_justification'] ?? 'No details provided.',
          ),

          if (isPO) ...[
            const SizedBox(height: 20),
            _manualEntryBlock(context),
          ],

          const SizedBox(height: 20),
          if (isPO && canApprove) ...[
            _confirmationLine(context),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              if (isPO && !canApprove)
                Expanded(
                  child: Text(
                    _quantityController.text.trim().isEmpty && _amountController.text.trim().isEmpty
                        ? 'Enter both figures to enable approval.'
                        : 'Both figures must be numbers greater than zero.',
                    style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), fontSize: 11),
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: _isSubmitting ? null : () => _submitDecision('rejected'),
                child: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: (_isSubmitting || !canApprove) ? null : () => _submitDecision('approved'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAction),
                child: _isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Approve'),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        ],
      );

  Widget _draftPanel(BuildContext context, {required String label, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_outlined, size: 13, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
        ],
      ),
    );
  }

  /// The fields the agent is forbidden to fill. Rendered as its own block,
  /// visually separated from the draft above it, because the split between
  /// "what the AI wrote" and "what the human commits to" is the product.
  Widget _manualEntryBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryAction.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primaryAction.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.edit_outlined, size: 13, color: AppTheme.primaryAction),
            const SizedBox(width: 6),
            Text('You enter these',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryAction,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Text(
            'The agent is not permitted to suggest a quantity or an amount. '
            'These fields start empty on purpose.',
            style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.95), fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  decoration: const InputDecoration(labelText: 'Quantity to order'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: 'Total amount (₹)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Restates the commitment in the human's own figures immediately above the
  /// button, so approving is a deliberate act rather than a reflex click.
  Widget _confirmationLine(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.lightGreenAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.lightGreenAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Colors.lightGreenAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                children: [
                  const TextSpan(text: 'You are authorising '),
                  TextSpan(
                    text: '$_quantity units',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' at a total of '),
                  TextSpan(
                    text: '₹${_amount!.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' — your figures, not the agent\'s.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
