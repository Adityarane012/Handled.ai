import 'dart:convert';
import 'package:flutter/material.dart';
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
          const _Bucket('Auto — runs immediately'),
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
          const SizedBox(height: 24),
          const _Bucket('Template-restricted — sends a fixed, pre-approved message'),
          _ToolCard(
            title: 'Vendor status update',
            subtitle: 'Notify a vendor using a vetted template',
            fields: const [
              _F('vendor_name', 'Vendor name'),
              _F('template_key', 'Template',
                  hint: 'delay_notification_v1 | delivery_confirmed_v1 | quality_issue_v1'),
              _F('details', 'Template fields (JSON)',
                  hint: '{"vendor_name":"Acme","order_ref":"PO-1","revised_date":"2026-09-05","company_name":"Co"}',
                  json: true),
            ],
            endpoint: '/ops/vendor-status',
            resultKey: 'message',
          ),
          const SizedBox(height: 24),
          const _Bucket('Approval-required — drafts an action, then waits for a human'),
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

class _Bucket extends StatelessWidget {
  final String label;
  const _Bucket(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

/// Field spec.
class _F {
  final String key;
  final String label;
  final String? hint;
  final bool number;
  final bool json;
  final bool required;
  const _F(this.key, this.label,
      {this.hint, this.number = false, this.json = false, this.required = true});
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
        } else if (f.json) {
          body[f.key] = jsonDecode(raw);
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
      setState(() => _error = e.toString());
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
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: SelectableText(_result!, style: Theme.of(context).textTheme.bodyMedium),
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
      setState(() => _msg = e.toString());
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
