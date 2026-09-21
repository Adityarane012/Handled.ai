import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../ops_labels.dart';
import '../services/api_service.dart';
import '../theme.dart';

/// Ops tools launcher — one card per tool, grouped by autonomy bucket.
/// Auto / template tools show their result inline; approval tools tell the
/// user to go to the queue.
class OpsToolsScreen extends StatelessWidget {
  const OpsToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ops Tools',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
          const SizedBox(height: 8),
          const Text(
            'Auto tools run immediately. Template tools send a pre-approved message. '
            'Approval tools draft an action and place it in the queue for a human.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          const _Bucket('auto'),
          _ToolCard(
            title: 'Ops status summary',
            subtitle: 'Summarise recent activity',
            fields: const [],
            endpoint: '/ops/status-summary',
            resultKey: 'summary',
          ),
          _ToolCard(
            title: 'Inventory Q&A',
            subtitle: 'Ask about stock — grounded in your uploaded inventory',
            fields: const [_F('question', 'Question', hint: 'How many 12V motors are in stock?')],
            endpoint: '/ops/inventory-qa',
            resultKey: 'answer',
            extra: _InventoryUpload(),
          ),
          const SizedBox(height: 28),
          const _Bucket('template_restricted'),
          const _VendorUpdateCard(),
          const SizedBox(height: 28),
          const _Bucket('approval_required'),
          _ToolCard(
            title: 'Purchase order',
            subtitle: 'Draft a PO justification — you enter quantity & amount in the queue',
            fields: const [
              _F('item_name', 'Item name'),
              _F('current_stock', 'Current stock', number: true),
              _F('reorder_reason', 'Reorder reason', required: false),
              _F('preferred_vendor', 'Preferred vendor', required: false),
            ],
            endpoint: '/ops/purchase-order',
            queued: true,
          ),
          _ToolCard(
            title: 'Workflow exception',
            subtitle: 'Flag an SOP deviation for a Department Head',
            fields: const [
              _F('request_description', 'What is being requested'),
              _F('sop_reference', 'SOP reference', required: false),
              _F('justification', 'Why'),
            ],
            endpoint: '/ops/workflow-exception',
            queued: true,
          ),
        ],
      ),
    );
  }
}

/// Section heading for one autonomy tier, using the same badge and wording as
/// History and the dashboard so a tier reads identically everywhere.
class _Bucket extends StatelessWidget {
  final String bucket;
  const _Bucket(this.bucket);

  @override
  Widget build(BuildContext context) {
    final colour = kBucketColors[bucket] ?? AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Row(
        children: [
          Container(width: 3, height: 26, color: colour),
          const SizedBox(width: 12),
          OpsBadge(text: kBucketLabels[bucket] ?? bucket, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              kBucketBlurbs[bucket] ?? '',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Field spec.
class _F {
  final String key;
  final String label;
  final String? hint;
  final bool number;
  final bool required;
  const _F(this.key, this.label, {this.hint, this.number = false, this.required = true});
}

class _ToolCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<_F> fields;
  final String endpoint;
  final String? resultKey; // where to read the human-readable result
  final bool queued; // approval tool → point at the queue
  final Widget? extra;

  const _ToolCard({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.endpoint,
    this.resultKey,
    this.queued = false,
    this.extra,
  });

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  String? _result;
  String? _error;

  TextEditingController _c(String k) => _controllers.putIfAbsent(k, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final body = <String, dynamic>{};
      for (final f in widget.fields) {
        final raw = _c(f.key).text.trim();
        if (raw.isEmpty) {
          if (f.required) throw Exception('${f.label} is required');
          continue;
        }
        if (f.number) {
          body[f.key] = int.tryParse(raw) ?? raw;
        } else {
          body[f.key] = raw;
        }
      }
      final res = await ApiService.post(widget.endpoint, body);
      setState(() {
        _result = widget.queued
            ? 'Drafted and sent to the approval queue (id ${res['id']}).'
            : (widget.resultKey != null && res[widget.resultKey] != null
                ? (res[widget.resultKey] is String
                    ? res[widget.resultKey] as String
                    : const JsonEncoder.withIndent('  ').convert(res[widget.resultKey]))
                : const JsonEncoder.withIndent('  ').convert(res));
      });
    } catch (e) {
      setState(() => _error = ApiService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(widget.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          if (widget.extra != null) ...[const SizedBox(height: 12), widget.extra!],
          const SizedBox(height: 16),
          for (final f in widget.fields) ...[
            TextField(
              controller: _c(f.key),
              keyboardType: f.number ? TextInputType.number : null,
              decoration: InputDecoration(
                labelText: f.label + (f.required ? '' : ' (optional)'),
                hintText: f.hint,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              ElevatedButton(
                onPressed: _busy ? null : _run,
                child: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.queued ? 'Draft & queue' : 'Run'),
              ),
              // Generation runs on a local model and takes ~10s. Without this
              // the button just spins and the app reads as hung.
              if (_busy) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Generating on the local model — usually about ten seconds.',
                    style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.9), fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.queued
                    ? Colors.orange.withValues(alpha: 0.07)
                    : AppTheme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.queued
                      ? Colors.orange.withValues(alpha: 0.35)
                      : AppTheme.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(_result!, style: Theme.of(context).textTheme.bodyMedium),
                  // An approval-required tool has deliberately NOT done the
                  // thing yet, so hand the user straight to the queue rather
                  // than leaving them to find it.
                  if (widget.queued) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => context.go('/approvals'),
                      icon: const Icon(Icons.pending_actions_outlined, size: 16),
                      label: const Text('Review it now'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.orange,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One entry per TOOL_REGISTRY vendor template (backend/agent/tool_registry.py).
/// Keeps the field labels human-readable instead of asking the user to type
/// the template_key or hand-write the details JSON themselves.
class _VendorTemplate {
  final String key;
  final String label;
  final String fieldKey;
  final String fieldLabel;
  final String fieldHint;
  const _VendorTemplate(this.key, this.label, this.fieldKey, this.fieldLabel, this.fieldHint);
}

const _vendorTemplates = [
  _VendorTemplate('delay_notification_v1', 'Delay notification', 'revised_date',
      'Revised delivery date', 'e.g. 2026-09-05'),
  _VendorTemplate('delivery_confirmed_v1', 'Delivery confirmation', 'delivery_date',
      'Delivery date', 'e.g. 2026-09-01'),
  _VendorTemplate('quality_issue_v1', 'Quality issue report', 'issue_description',
      'Issue description', 'e.g. 2 units arrived damaged'),
];

class _VendorUpdateCard extends StatefulWidget {
  const _VendorUpdateCard();

  @override
  State<_VendorUpdateCard> createState() => _VendorUpdateCardState();
}

class _VendorUpdateCardState extends State<_VendorUpdateCard> {
  _VendorTemplate _selected = _vendorTemplates[0];
  final _vendorName = TextEditingController();
  final _companyName = TextEditingController();
  final _orderRef = TextEditingController();
  final _extraField = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _vendorName.dispose();
    _companyName.dispose();
    _orderRef.dispose();
    _extraField.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      if ([_vendorName, _companyName, _orderRef, _extraField].any((c) => c.text.trim().isEmpty)) {
        throw Exception('All fields are required.');
      }
      final details = {
        'vendor_name': _vendorName.text.trim(),
        'company_name': _companyName.text.trim(),
        'order_ref': _orderRef.text.trim(),
        _selected.fieldKey: _extraField.text.trim(),
      };
      final res = await ApiService.post('/ops/vendor-status', {
        'vendor_name': _vendorName.text.trim(),
        'template_key': _selected.key,
        'details': details,
      });
      setState(() => _result = Map<String, dynamic>.from(res['message'] ?? {}));
    } catch (e) {
      setState(() => _error = ApiService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vendor status update', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Notify a vendor using a vetted template — the wording is fixed, you only fill the blanks',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          DropdownButtonFormField<_VendorTemplate>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Template'),
            items: _vendorTemplates
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (t) => setState(() => _selected = t!),
          ),
          const SizedBox(height: 12),
          TextField(controller: _vendorName, decoration: const InputDecoration(labelText: 'Vendor name')),
          const SizedBox(height: 12),
          TextField(controller: _companyName, decoration: const InputDecoration(labelText: 'Your company name')),
          const SizedBox(height: 12),
          TextField(controller: _orderRef, decoration: const InputDecoration(labelText: 'Order reference')),
          const SizedBox(height: 12),
          TextField(
            controller: _extraField,
            decoration: InputDecoration(labelText: _selected.fieldLabel, hintText: _selected.fieldHint),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _run,
            child: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send update'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: _result!['error'] != null
                  ? Text(_result!['error'].toString(), style: const TextStyle(color: Colors.redAccent, fontSize: 13))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_result!['subject']?.toString() ?? '',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(_result!['body']?.toString() ?? '', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InventoryUpload extends StatefulWidget {
  @override
  State<_InventoryUpload> createState() => _InventoryUploadState();
}

class _InventoryUploadState extends State<_InventoryUpload> {
  final _doc = TextEditingController();
  String? _msg;
  bool _busy = false;

  @override
  void dispose() {
    _doc.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final res = await ApiService.post('/ops/inventory-upload', {'doc_text': _doc.text});
      setState(() => _msg = 'Indexed ${res['indexed_chunks']} chunk(s).');
    } catch (e) {
      setState(() => _msg = ApiService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _doc,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Inventory document (paste rows, then upload)',
            hintText: 'SKU A100 Widget | on_hand 40 | reorder_point 50 | vendor Acme',
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton(
            onPressed: _busy ? null : _upload,
            child: Text(_busy ? 'Uploading…' : 'Upload inventory'),
          ),
          const SizedBox(width: 12),
          if (_msg != null)
            Expanded(child: Text(_msg!, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      ],
    );
  }
}
