// Rendering of the light markdown the model emits.
//
// Written against real output: the approval screen was showing
// "**SOP Rule at Stake:** ..." with the asterisks intact, on the screen a
// reviewer reads most closely.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handled_app/agent_text.dart';

// Verbatim from a workflow-exception draft.
const realDraft = '''
**Request Evaluation Report**

**SOP Rule at Stake:** SOP-LOG-02: Road freight is the default for domestic replenishment.

**Recommendation:** I recommend that the Department Head reviews the request:

* Evaluate the potential impact on production schedules.
* Consider alternative solutions that align with the current SOP.
''';

Future<void> _pump(WidgetTester tester, String text) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: AgentText(text))),
  ));
  await tester.pumpAndSettle();
}

/// All text the widget actually put on screen.
String _rendered(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    buffer.write(w.data ?? w.textSpan?.toPlainText() ?? '');
    buffer.write('\n');
  }
  return buffer.toString();
}

void main() {
  group('AgentText', () {
    testWidgets('renders bold without showing the asterisks', (tester) async {
      await _pump(tester, realDraft);
      final out = _rendered(tester);

      expect(out, contains('Request Evaluation Report'));
      expect(out, contains('SOP Rule at Stake:'));
      // The actual defect.
      expect(out, isNot(contains('**')));
    });

    testWidgets('renders bullets without showing the leading marker', (tester) async {
      await _pump(tester, realDraft);
      final out = _rendered(tester);

      expect(out, contains('Evaluate the potential impact on production schedules.'));
      expect(out, isNot(contains('* Evaluate')));
    });

    testWidgets('a bold line is a heading, not a bullet', (tester) async {
      // "**Heading**" starts with an asterisk but must not be read as a list
      // item — that distinction is the fiddly part of the bullet pattern.
      await _pump(tester, '**Recommendation:** approve it');
      final out = _rendered(tester);
      expect(out, contains('Recommendation:'));
      expect(out, contains('approve it'));
      expect(out, isNot(contains('*')));
    });

    testWidgets('plain prose passes through untouched', (tester) async {
      const prose = 'Stock has fallen below the reorder point; a replenishment order is needed.';
      await _pump(tester, prose);
      expect(_rendered(tester), contains(prose));
    });

    testWidgets('does not throw on empty or marker-only text', (tester) async {
      await _pump(tester, '');
      expect(tester.takeException(), isNull);
      await _pump(tester, '\n\n');
      expect(tester.takeException(), isNull);
    });
  });

  group('plainAgentText', () {
    test('flattens to a single line with the markers stripped', () {
      final flat = plainAgentText(realDraft);

      expect(flat, isNot(contains('**')));
      expect(flat, isNot(contains('\n')));
      expect(flat, startsWith('Request Evaluation Report'));
      expect(flat, contains('Evaluate the potential impact'));
    });

    test('keeps bold content rather than deleting it', () {
      // An early version stripped the markers *and* the words between them.
      expect(plainAgentText('**SOP Rule at Stake:** road freight'),
          'SOP Rule at Stake: road freight');
    });

    test('leaves plain text alone', () {
      expect(plainAgentText('We have 46 units on hand.'), 'We have 46 units on hand.');
    });
  });
}
