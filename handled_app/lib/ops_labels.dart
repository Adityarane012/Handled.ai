import 'package:flutter/material.dart';
import 'theme.dart';

/// Shared presentation for the three autonomy buckets and the action
/// statuses. Kept in one place so the History screen and the dashboard can't
/// drift into labelling or colouring the same bucket differently — the whole
/// point of the buckets is that they read identically everywhere.
const kToolLabels = {
  'ops_status_summary': 'Status Summary',
  'inventory_qa': 'Inventory Q&A',
  'vendor_status_update': 'Vendor Status Update',
  'purchase_order_approval': 'Purchase Order',
  'workflow_exception_approval': 'Workflow Exception',
};

const kBucketLabels = {
  'auto': 'Auto',
  'template_restricted': 'Template',
  'approval_required': 'Approval Required',
};

/// One-line explanation of what each bucket actually guarantees — used as
/// helper text so a first-time viewer doesn't have to be told verbally.
const kBucketBlurbs = {
  'auto': 'Runs immediately, always logged',
  'template_restricted': 'Fixed pre-approved wording only',
  'approval_required': 'A human must approve before it counts',
};

const kBucketColors = {
  'auto': Color(0xFF5E9EFF),
  'template_restricted': Color(0xFFB07CF2),
  'approval_required': Colors.orange,
};

const kStatusLabels = {
  'auto_executed': 'Ran automatically',
  'pending_approval': 'Pending approval',
  'executed': 'Approved & executed',
  'rejected': 'Rejected',
  'drafted': 'Drafted — missing info',
};

const kStatusColors = {
  'auto_executed': Colors.lightGreenAccent,
  'pending_approval': Colors.orange,
  'executed': Colors.lightGreenAccent,
  'rejected': Colors.redAccent,
  'drafted': Colors.amber,
};

/// Small rounded pill used for bucket/status tags.
class OpsBadge extends StatelessWidget {
  final String text;
  final Color color;
  const OpsBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Whether a human has supplied usable figures for an approval that requires
/// them.
///
/// This is the single most safety-critical rule in the UI, so it lives here as
/// a pure function rather than inside a build method: the whole architecture
/// rests on a human typing the real quantity and amount, and an earlier
/// version only checked the fields were non-empty — so "abc" silently became
/// 0 and could still be approved. Both values must parse and be greater than
/// zero.
bool manualFiguresAreUsable(String quantityText, String amountText) {
  final q = int.tryParse(quantityText.trim());
  final a = double.tryParse(amountText.trim());
  if (q == null || a == null) return false;
  if (!a.isFinite) return false;
  return q > 0 && a > 0;
}

/// Renders a value that may legitimately be absent (no data yet) as "—"
/// rather than a misleading 0%.
String formatPercent(dynamic rate) {
  if (rate == null) return '—';
  return '${((rate as num) * 100).round()}%';
}

/// Shared card shell for dashboard figures.
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? caption;
  final Color? valueColor;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.caption,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
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
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 30,
                  color: valueColor ?? AppTheme.textPrimary,
                ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
