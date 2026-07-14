import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

void main() {
  group('statIconAsset', () {
    test('maps all 13 known event types to their asset', () {
      expect(statIconAsset('goal'), 'assets/goal.png');
      expect(statIconAsset('own goal'), 'assets/own_goal.png');
      expect(statIconAsset('penalty goal'), 'assets/goal_penalty.png');
      expect(statIconAsset('penalty missed'), 'assets/penalty_missed.png');
      expect(statIconAsset('penalty saved'), 'assets/penalty_saved.png');
      expect(statIconAsset('save'), 'assets/save.png');
      expect(statIconAsset('assist'), 'assets/assist.png');
      expect(statIconAsset('substitution'), 'assets/substitution.png');
      expect(statIconAsset('yellow card'), 'assets/yellow.png');
      expect(statIconAsset('red card'), 'assets/red.png');
      expect(statIconAsset('second yellow'), 'assets/second_yellow.png');
      expect(statIconAsset('foul'), 'assets/foul.png');
      expect(statIconAsset('dpl'), 'assets/dpl.png');
    });

    test('is case-insensitive and trims surrounding whitespace', () {
      expect(statIconAsset('GOAL'), 'assets/goal.png');
      expect(statIconAsset('  Yellow Card  '), 'assets/yellow.png');
    });

    test('returns null for unknown or empty event types', () {
      expect(statIconAsset('teleport'), isNull);
      expect(statIconAsset(''), isNull);
    });
  });

  group('statIconAssetForStat', () {
    test('maps fixtures stat keys to the matching icon asset', () {
      expect(statIconAssetForStat('goals'), 'assets/goal.png');
      expect(statIconAssetForStat('assists'), 'assets/assist.png');
      expect(statIconAssetForStat('saves'), 'assets/save.png');
      expect(statIconAssetForStat('dpl'), 'assets/dpl.png');
    });

    test('is case-insensitive and trims surrounding whitespace', () {
      expect(statIconAssetForStat('GOALS'), 'assets/goal.png');
      expect(statIconAssetForStat('  Saves  '), 'assets/save.png');
    });

    test('returns null for unknown stat keys', () {
      expect(statIconAssetForStat('rebounds'), isNull);
    });
  });

  group('statIconAsset — league activity types (League Experience P2)', () {
    test('league penalty + own-goal spellings map to the tournament artwork',
        () {
      expect(statIconAsset('PenGoal'), 'assets/goal_penalty.png');
      expect(statIconAsset('PenMissed'), 'assets/penalty_missed.png');
      expect(statIconAsset('PenSaved'), 'assets/penalty_saved.png');
      expect(statIconAsset('OwnGoal'), 'assets/own_goal.png');
    });

    test('league card spellings map to card artwork', () {
      expect(statIconAsset('Yellow'), 'assets/yellow.png');
      expect(statIconAsset('SecondYellow'), 'assets/second_yellow.png');
      expect(statIconAsset('Red'), 'assets/red.png');
    });

    test('legacy league Blue still renders (retired for new capture)', () {
      expect(statIconAsset('Blue'), 'assets/blue.png');
    });

    test('league row events already resolved via lowercase — stays true', () {
      expect(statIconAsset('Goal'), 'assets/goal.png');
      expect(statIconAsset('Assist'), 'assets/assist.png');
      expect(statIconAsset('Save'), 'assets/save.png');
      expect(statIconAsset('DPL'), 'assets/dpl.png');
      expect(statIconAsset('Foul'), 'assets/foul.png');
    });
  });

  group('P4 — basketball activity icons', () {
    test('legacy basketball spellings map to the bundled art', () {
      expect(statIconAsset('OnePointer'), 'assets/onepointer.png');
      expect(statIconAsset('TwoPointer'), 'assets/twopointer.png');
      expect(statIconAsset('ThreePointer'), 'assets/threepointer.png');
      expect(statIconAsset('Rebound'), 'assets/rebound.png');
    });

    test('art-less P4 types fall back to null (grey StatIcon)', () {
      expect(statIconAsset('Steal'), isNull);
      expect(statIconAsset('Block'), isNull);
      expect(statIconAsset('Turnover'), isNull);
      expect(statIconAsset('Miss'), isNull);
      expect(statIconAsset('QBComp'), isNull);
      expect(statIconAsset('Receiving TD'), isNull);
    });
  });
}
