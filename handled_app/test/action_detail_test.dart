// Renders the audit-trail detail dialog against realistic records.
//
// These exist because the dialog reads loosely-typed JSON straight from the
// API (draft_output/final_output differ in shape per tool), which is exactly
// where a null cast or a missing key turns into a red screen at demo time.
// Building the app is not enough to catch that — the widget has to be built.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handled_app/screens/action_detail.dart';
import 'package:handled_app/theme.dart';

/// The default test surface is 800x600, which is shorter than this dialog —
/// the bottom of it lands past the fold and taps there hit the modal barrier
/// instead, silently dismissing the dialog. This is a desktop/web app, so
/// tests run at a desktop-sized surface.
Future<void> _open(WidgetTester tester, Map<String, dynamic> action) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showActionDetail(context, action),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// An approved purchase order: agent drafted the prose, a human typed the
/// figures. The most important case, since the gap between draft and final is
/// the safety argument.
Map<String, dynamic> _approvedPo() => {
      'id': 'aaaa-1111',
      'tool_name': 'purchase_order_approval',
      'action_type': 'approval_required',
      'status': 'executed',
      'draft_output': {
        'input': {'item_name': 'Oil Seal TC 25x42x7', 'current_stock': 88},
        'agent_output': 'Stock has fallen below the reorder point; a replenishment order is needed.',
      },
      'final_output': {
        'input': {'item_name': 'Oil Seal TC 25x42x7', 'current_stock': 88},
        'agent_output': 'Stock has fallen below the reorder point; a replenishment order is needed.',
        'quantity': 250,
        'amount': 15875.0,
      },
      'requested_by_name': 'Rohit Sharma',
      'approved_by_name': 'Rohit Sharma',
      'approved_at': '2026-09-19T14:32:10.123456',
      'created_at': '2026-09-19T14:30:02.000000',
    };

void main() {
  testWidgets('approved PO shows agent prose and the human-entered figures separately',
      (tester) async {
    await _open(tester, _approvedPo());

    expect(find.text('Purchase Order'), findsOneWidget);
    expect(find.text('Approval Required'), findsOneWidget);
    expect(find.text('Approved & executed'), findsOneWidget);

    expect(find.text('WHAT THE AGENT PRODUCED'), findsOneWidget);
    expect(find.textContaining('below the reorder point'), findsOneWidget);

    // The figures the agent was forbidden to supply, called out as the
    // human's own.
    expect(find.text('WHAT THE HUMAN TYPED IN'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('₹15875.0'), findsOneWidget);

    // ...and who did it, in words rather than UUIDs.
    expect(find.textContaining('Rohit Sharma'), findsWidgets);
  });

  testWidgets('a pending action says nobody has decided yet', (tester) async {
    final pending = _approvedPo()
      ..['status'] = 'pending_approval'
      ..['final_output'] = null
      ..['approved_by_name'] = null
      ..['approved_at'] = null;

    await _open(tester, pending);

    expect(find.text('Pending approval'), findsOneWidget);
    expect(find.textContaining('No human has decided yet'), findsOneWidget);
    // Nothing was authorised, so there are no human figures to show.
    expect(find.text('WHAT THE HUMAN TYPED IN'), findsNothing);
  });

  testWidgets('a rejected action reads as rejected, keeping the draft', (tester) async {
    final rejected = _approvedPo()
      ..['tool_name'] = 'workflow_exception_approval'
      ..['status'] = 'rejected'
      ..['final_output'] = null;

    await _open(tester, rejected);

    expect(find.text('Workflow Exception'), findsOneWidget);
    expect(find.text('Rejected'), findsWidgets);
    // Draft is preserved and still shown — rejection never erases it.
    expect(find.textContaining('below the reorder point'), findsOneWidget);
  });

  testWidgets('a template action renders its sent message body', (tester) async {
    await _open(tester, {
      'id': 'bbbb-2222',
      'tool_name': 'vendor_status_update',
      'action_type': 'template_restricted',
      'status': 'auto_executed',
      'draft_output': {
        'template_key': 'delay_notification_v1',
        'subject': 'Order Delay Notification',
        'body': 'Dear Shree Fasteners, order #PO-2288 is currently delayed.',
        'error': null,
      },
      'final_output': {
        'template_key': 'delay_notification_v1',
        'subject': 'Order Delay Notification',
        'body': 'Dear Shree Fasteners, order #PO-2288 is currently delayed.',
        'error': null,
      },
      'created_at': '2026-09-19T14:30:02.000000',
    });

    expect(find.text('Vendor Status Update'), findsOneWidget);
    expect(find.text('Template'), findsOneWidget);
    expect(find.textContaining('currently delayed'), findsOneWidget);
  });

  testWidgets('survives a sparse record without throwing', (tester) async {
    // Defensive: an auto action with no final_output and no names at all.
    await _open(tester, {
      'id': 'cccc-3333',
      'tool_name': 'ops_status_summary',
      'action_type': 'auto',
      'status': 'auto_executed',
      'draft_output': {'agent_output': 'Four purchase orders raised this week.'},
      'final_output': null,
      'created_at': '2026-09-19T14:30:02.000000',
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Status Summary'), findsOneWidget);
    expect(find.textContaining('Four purchase orders'), findsOneWidget);
  });

  testWidgets('the stored record is inspectable, not just asserted', (tester) async {
    await _open(tester, _approvedPo());

    expect(find.text('Stored record'), findsOneWidget);
    expect(find.textContaining('drafts are never overwritten'), findsOneWidget);

    // The dialog scrolls internally, so this sits below the fold on a taller
    // record — tapping without scrolling first lands on the modal barrier and
    // quietly closes the dialog instead.
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    // The raw row, so "we log everything and never overwrite the draft" can be
    // shown on the spot rather than asserted.
    expect(find.textContaining('draft_output'), findsOneWidget);
    expect(find.textContaining('final_output'), findsOneWidget);
  });
}
