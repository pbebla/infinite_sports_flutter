import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_timeline_filter.dart';

void main() {
  group('isHiddenLeagueTimelineActivity', () {
    test('basketball hides Miss (case-insensitive)', () {
      expect(isHiddenLeagueTimelineActivity('Basketball', 'Miss'), isTrue);
      expect(isHiddenLeagueTimelineActivity('Basketball', 'miss'), isTrue);
      expect(isHiddenLeagueTimelineActivity('Basketball', '  MISS '), isTrue);
    });

    test('basketball keeps scoring + other events visible', () {
      for (final t in ['OnePointer', 'TwoPointer', 'ThreePointer', 'Rebound',
          'Assist', 'Steal', 'Block', 'Turnover', 'Foul']) {
        expect(isHiddenLeagueTimelineActivity('Basketball', t), isFalse,
            reason: '$t should stay visible');
      }
    });

    test('futsal + tournament (other sports) hide nothing', () {
      expect(isHiddenLeagueTimelineActivity('Futsal', 'Miss'), isFalse);
      expect(isHiddenLeagueTimelineActivity('Futsal', 'Goal'), isFalse);
      expect(isHiddenLeagueTimelineActivity('Soccer', 'Miss'), isFalse);
    });

    test('flag football hides QBInc/RECMiss/PAT1Miss/TwoPTMiss', () {
      for (final t in ['QBInc', 'RECMiss', 'PAT1Miss', 'TwoPTMiss']) {
        expect(isHiddenLeagueTimelineActivity('Flag Football', t), isTrue,
            reason: '$t should be hidden');
      }
    });

    test('flag football keeps scored + defensive events visible', () {
      for (final t in ['Receiving TD', 'Rushing TD', 'INT TD', 'Interception',
          'Sack', 'FP', 'PBU', 'QBComp', 'REC', 'PAT1', 'TwoPT']) {
        expect(isHiddenLeagueTimelineActivity('Flag Football', t), isFalse,
            reason: '$t should stay visible');
      }
    });
  });
}
