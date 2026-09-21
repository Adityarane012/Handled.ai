// The rule the whole safety argument rests on: an approval that needs figures
// must not be approvable until a human has typed real ones.
//
// This regressed once already — the check was "field is not empty", so "abc"
// parsed to 0 via `?? 0` and a purchase order could be approved for zero
// units at zero rupees while the UI still claimed manual entry was required.
import 'package:flutter_test/flutter_test.dart';
import 'package:handled_app/ops_labels.dart';

void main() {
  group('manualFiguresAreUsable', () {
    test('accepts ordinary figures', () {
      expect(manualFiguresAreUsable('200', '36400'), isTrue);
      expect(manualFiguresAreUsable('1', '0.5'), isTrue);
      expect(manualFiguresAreUsable(' 250 ', ' 15875.00 '), isTrue);
    });

    test('rejects empty input', () {
      expect(manualFiguresAreUsable('', ''), isFalse);
      expect(manualFiguresAreUsable('200', ''), isFalse);
      expect(manualFiguresAreUsable('', '36400'), isFalse);
      expect(manualFiguresAreUsable('   ', '   '), isFalse);
    });

    test('rejects non-numeric text rather than treating it as zero', () {
      // The exact regression: this used to enable Approve and send 0.
      expect(manualFiguresAreUsable('abc', 'xyz'), isFalse);
      expect(manualFiguresAreUsable('200', 'lots'), isFalse);
      expect(manualFiguresAreUsable('two hundred', '36400'), isFalse);
    });

    test('rejects zero and negative figures', () {
      expect(manualFiguresAreUsable('0', '36400'), isFalse);
      expect(manualFiguresAreUsable('200', '0'), isFalse);
      expect(manualFiguresAreUsable('-5', '100'), isFalse);
      expect(manualFiguresAreUsable('200', '-100'), isFalse);
    });

    test('rejects a fractional quantity', () {
      // Quantity is an int on the wire; "2.5 units" would silently truncate.
      expect(manualFiguresAreUsable('2.5', '100'), isFalse);
    });

    test('rejects non-finite amounts', () {
      expect(manualFiguresAreUsable('200', 'Infinity'), isFalse);
      expect(manualFiguresAreUsable('200', 'NaN'), isFalse);
    });
  });

  group('formatPercent', () {
    test('shows an em dash when there is genuinely no data', () {
      // Not 0% — a company that has done nothing has no rate, and claiming
      // "0% rejected" would read as "the human approves everything".
      expect(formatPercent(null), '—');
    });

    test('renders a rate as a whole percentage', () {
      expect(formatPercent(0.556), '56%');
      expect(formatPercent(0.5), '50%');
      expect(formatPercent(1), '100%');
      expect(formatPercent(0), '0%');
    });
  });

  group('tier presentation', () {
    test('every tier has a label, colour and stated guarantee', () {
      for (final tier in ['auto', 'template_restricted', 'approval_required']) {
        expect(kBucketLabels[tier], isNotNull, reason: '$tier has no label');
        expect(kBucketColors[tier], isNotNull, reason: '$tier has no colour');
        expect(kBucketBlurbs[tier], isNotNull, reason: '$tier has no blurb');
      }
    });

    test('every backend status maps to wording a person can read', () {
      // These are the statuses agent_action's CHECK constraint permits.
      for (final status in [
        'auto_executed',
        'pending_approval',
        'executed',
        'rejected',
        'drafted',
      ]) {
        expect(kStatusLabels[status], isNotNull, reason: '$status has no label');
        expect(kStatusColors[status], isNotNull, reason: '$status has no colour');
      }
    });
  });

  group('formatTimestamp', () {
    test('converts offset-aware API timestamps to local time', () {
      // Two spellings of the same instant must render identically — the
      // audit trail once showed "approved" before "triggered" because one
      // path stayed in UTC and the other didn't.
      expect(formatTimestamp('2026-09-21T07:29:00+00:00'),
          formatTimestamp('2026-09-21T12:59:00+05:30'));
      final local = DateTime.parse('2026-09-21T07:29:00Z').toLocal();
      expect(formatTimestamp('2026-09-21T07:29:00+00:00'),
          contains('${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'));
    });

    test('null stays null and junk is shown as-is', () {
      expect(formatTimestamp(null), isNull);
      expect(formatTimestamp('not a date'), 'not a date');
    });
  });
}
