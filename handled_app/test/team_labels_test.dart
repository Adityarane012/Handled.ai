// The "whose work is this" line a manager reads on every History row, and the
// role wording on the Team screen. Permissions themselves are enforced (and
// tested) in the backend — these guard the display from drifting.
import 'package:flutter_test/flutter_test.dart';
import 'package:handled_app/ops_labels.dart';

void main() {
  group('trailSummary', () {
    test('names who drafted and who decided', () {
      expect(trailSummary('Amit', 'Neha', 'executed'), 'Requested by Amit · Approved by Neha');
      expect(trailSummary('Amit', 'Neha', 'rejected'), 'Requested by Amit · Rejected by Neha');
    });

    test('pending or automatic rows show only the requester', () {
      expect(trailSummary('Amit', null, 'pending_approval'), 'Requested by Amit');
      expect(trailSummary('Amit', null, 'auto_executed'), 'Requested by Amit');
    });

    test('rows from before requested_by existed still render', () {
      expect(trailSummary(null, 'Neha', 'executed'), 'Approved by Neha');
      expect(trailSummary(null, null, 'auto_executed'), '');
    });
  });

  test('every role the backend can return has a label, blurb and colour', () {
    // Mirrors the app_user role CHECK constraint in db_models.py.
    for (final role in ['owner_admin', 'department_head', 'staff']) {
      expect(kRoleLabels[role], isNotNull, reason: '$role has no label');
      expect(kRoleBlurbs[role], isNotNull, reason: '$role has no blurb');
      expect(kRoleColors[role], isNotNull, reason: '$role has no colour');
    }
    expect(kRoleBlurbs['staff'], contains('cannot approve'));
  });
}
