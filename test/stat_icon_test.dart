import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

void main() {
  group('statIconAsset', () {
    test('maps all 13 known event types to their asset', () {
      expect(statIconAsset('goal'), 'assets/stat_icons/goal.png');
      expect(statIconAsset('own goal'), 'assets/stat_icons/own_goal.png');
      expect(statIconAsset('penalty goal'), 'assets/stat_icons/goal_penalty.png');
      expect(statIconAsset('penalty missed'), 'assets/stat_icons/penalty_missed.png');
      expect(statIconAsset('penalty saved'), 'assets/stat_icons/penalty_saved.png');
      expect(statIconAsset('save'), 'assets/stat_icons/save.png');
      expect(statIconAsset('assist'), 'assets/stat_icons/assist.png');
      expect(statIconAsset('substitution'), 'assets/stat_icons/substitution.png');
      expect(statIconAsset('yellow card'), 'assets/stat_icons/yellow_card.png');
      expect(statIconAsset('red card'), 'assets/stat_icons/red_card.png');
      expect(statIconAsset('second yellow'), 'assets/stat_icons/second_yellow.png');
      expect(statIconAsset('foul'), 'assets/stat_icons/foul.png');
      expect(statIconAsset('dpl'), 'assets/stat_icons/dpl.png');
    });

    test('is case-insensitive and trims surrounding whitespace', () {
      expect(statIconAsset('GOAL'), 'assets/stat_icons/goal.png');
      expect(statIconAsset('  Yellow Card  '), 'assets/stat_icons/yellow_card.png');
    });

    test('returns null for unknown or empty event types', () {
      expect(statIconAsset('teleport'), isNull);
      expect(statIconAsset(''), isNull);
    });
  });

  group('statIconAssetForStat', () {
    test('maps fixtures stat keys to the matching icon asset', () {
      expect(statIconAssetForStat('goals'), 'assets/stat_icons/goal.png');
      expect(statIconAssetForStat('assists'), 'assets/stat_icons/assist.png');
      expect(statIconAssetForStat('saves'), 'assets/stat_icons/save.png');
      expect(statIconAssetForStat('dpl'), 'assets/stat_icons/dpl.png');
    });

    test('returns null for unknown stat keys', () {
      expect(statIconAssetForStat('rebounds'), isNull);
    });
  });
}
