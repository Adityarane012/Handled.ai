import 'package:flutter/material.dart';
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Needs Approval',
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 12, fontWeight: FontWeight.w600),
                ),
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
            isPO
                ? 'Purchase Order Request: ${draft['input']?['item_name'] ?? draft['item_name'] ?? 'Unknown Item'}'
                : _titleForTool(widget.action['tool_name']),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),

          if (!isPO) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agent Reasoning', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(
                    draft['agent_output'] ?? draft['agent_justification'] ?? 'No details provided.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],

          if (isPO) ...[
            Text('Current Stock: ${draft['input']?['current_stock'] ?? draft['current_stock'] ?? '-'}', style: Theme.of(context).textTheme.bodyMedium),
            Text('Vendor: ${draft['input']?['preferred_vendor'] ?? draft['preferred_vendor'] ?? 'Not specified'}', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agent Justification', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(draft['agent_output'] ?? draft['agent_justification'] ?? 'No justification provided.', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Manual Verification Required', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    decoration: const InputDecoration(labelText: 'Quantity to Order'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(labelText: 'Total Amount (₹)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() {}),
                  ),
                ),
              ],
            )
          ],

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
}
