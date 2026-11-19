import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_timeline_filter.dart';

void main() {
  group('isHiddenTimelineActivity', () {
    test('basketball hides Miss (case-insensitive)', () {
      expect(isHiddenTimelineActivity('Basketball', 'Miss'), isTrue);
      expect(isHiddenTimelineActivity('Basketball', 'miss'), isTrue);
      expect(isHiddenTimelineActivity('Basketball', '  MISS '), isTrue);
    });

    test('basketball keeps scoring + other events visible', () {
      for (final t in ['OnePointer', 'TwoPointer', 'ThreePointer', 'Rebound',
          'Assist', 'Steal', 'Block', 'Turnover', 'Foul']) {
        expect(isHiddenTimelineActivity('Basketball', t), isFalse,
            reason: '$t should stay visible');
      }
    });

    test('futsal + tournament (other sports) hide nothing', () {
      expect(isHiddenTimelineActivity('Futsal', 'Miss'), isFalse);
      expect(isHiddenTimelineActivity('Futsal', 'Goal'), isFalse);
      expect(isHiddenTimelineActivity('Soccer', 'Miss'), isFalse);
    });

    test('flag football L6.2: QBInc is NO LONGER hidden — the hidden set '
        'is now empty (case-insensitive)', () {
      expect(isHiddenTimelineActivity('Flag Football', 'QBInc'), isFalse);
      expect(isHiddenTimelineActivity('Flag Football', 'qbinc'), isFalse);
      expect(
          isHiddenTimelineActivity('Flag Football', '  QBINC '), isFalse);
    });

    test('flag football L6.1: RECMiss/PAT1Miss/TwoPTMiss NO LONGER hidden '
        '— they render on the timeline now', () {
      for (final t in ['RECMiss', 'PAT1Miss', 'TwoPTMiss']) {
        expect(isHiddenTimelineActivity('Flag Football', t), isFalse,
            reason: '$t should now be visible on the timeline');
      }
    });

    test('flag football keeps scored + defensive events visible', () {
      for (final t in ['Receiving TD', 'Rushing TD', 'INT TD', 'Interception',
          'Sack', 'FP', 'PBU', 'QBComp', 'REC', 'PAT1', 'TwoPT']) {
        expect(isHiddenTimelineActivity('Flag Football', t), isFalse,
            reason: '$t should stay visible');
      }
    });
  });

  group('saves and defense plays are hidden everywhere', () {
    test('Save and DPL hidden for every sport, league and tournament keys', () {
      for (final sport in [null, 'Futsal', 'Soccer', 'Basketball', 'Flag Football']) {
        for (final t in ['Save', 'save', 'DPL', 'dpl', ' Dpl ']) {
          expect(isHiddenTimelineActivity(sport, t), isTrue,
              reason: '$sport / $t');
        }
      }
    });
    test('PenSaved and penalty saved stay visible', () {
      for (final sport in [null, 'Futsal']) {
        for (final t in ['PenSaved', 'penalty saved', 'Goal', 'Foul']) {
          expect(isHiddenTimelineActivity(sport, t), isFalse,
              reason: '$sport / $t');
        }
      }
    });
    test('basketball miss still hidden, null-sport miss not', () {
      expect(isHiddenTimelineActivity('Basketball', 'Miss'), isTrue);
      expect(isHiddenTimelineActivity(null, 'Miss'), isFalse);
    });
  });
}
