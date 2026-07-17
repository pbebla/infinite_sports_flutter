import 'package:flutter/material.dart';
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

  group('StatIcon badge path (L6)', () {
    testWidgets('badge icons render bare (no white chip Container)', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: StatIcon(asset: 'assets/rebound.png', badge: true),
      ));
      // Bare path is SizedBox + Image, no decorated chip Container.
      expect(
        find.descendant(
            of: find.byType(StatIcon), matching: find.byType(Container)),
        findsNothing,
      );
      expect(
        find.descendant(
            of: find.byType(StatIcon), matching: find.byType(Image)),
        findsOneWidget,
      );
    });

    testWidgets('non-badge icons keep the white chip Container', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: StatIcon(asset: 'assets/goal.png'),
      ));
      expect(
        find.descendant(
            of: find.byType(StatIcon), matching: find.byType(Container)),
        findsOneWidget,
      );
    });
  });

  group('leagueStatIcon — basketball badges (L6)', () {
    test('badge stat/activity tokens return bball asset + badge:true', () {
      expect(leagueStatIcon('Basketball', 'OnePointer'),
          (asset: 'assets/bball_freethrow.png', badge: true));
      expect(leagueStatIcon('Basketball', 'ThreePointer').badge, isTrue);
      expect(leagueStatIcon('Basketball', 'points').asset,
          'assets/bball_points.png');
      expect(leagueStatIcon('Basketball', 'Steal').asset,
          'assets/bball_steal.png');
      expect(leagueStatIcon('Basketball', 'blocks').asset,
          'assets/bball_block.png');
      expect(leagueStatIcon('Basketball', 'Assist').asset,
          'assets/bball_assist.png');
      expect(leagueStatIcon('Basketball', 'rebounds').asset,
          'assets/bball_rebound.png');
      expect(leagueStatIcon('Basketball', 'Turnover').asset,
          'assets/bball_turnover.png');
    });

    test('foul reuses the shared chip icon (badge:false)', () {
      expect(leagueStatIcon('Basketball', 'Foul'),
          (asset: 'assets/foul.png', badge: false));
    });

    test('miss is icon-less (hidden background stat)', () {
      expect(leagueStatIcon('Basketball', 'Miss').asset, isNull);
    });

    test('unknown sport / token → (null, false)', () {
      expect(leagueStatIcon('Futsal', 'Goal').asset, isNull);
      expect(leagueStatIcon('Basketball', 'teleport').asset, isNull);
    });

    test('isBadgeLeagueSport', () {
      expect(isBadgeLeagueSport('Basketball'), isTrue);
      expect(isBadgeLeagueSport('Flag Football'), isTrue);
      expect(isBadgeLeagueSport('Futsal'), isFalse);
    });
  });

  group('leagueStatIcon — flag football badges (L6 Group F)', () {
    test('scored-TD timeline events map to badge assets', () {
      expect(leagueStatIcon('Flag Football', 'Receiving TD').asset,
          'assets/ff_rec_td.png');
      expect(leagueStatIcon('Flag Football', 'Rushing TD').badge, isTrue);
      expect(leagueStatIcon('Flag Football', 'INT TD').asset,
          'assets/ff_int_td.png');
      expect(leagueStatIcon('Flag Football', 'Interception').asset,
          'assets/ff_int.png');
      expect(leagueStatIcon('Flag Football', 'Sack').asset,
          'assets/ff_sack.png');
    });

    test('leader stat keys map to badge assets', () {
      expect(leagueStatIcon('Flag Football', 'touchdowns').asset,
          'assets/ff_touchdown.png');
      expect(leagueStatIcon('Flag Football', 'receptions').asset,
          'assets/ff_rec.png');
      expect(leagueStatIcon('Flag Football', 'passTouchdowns').asset,
          'assets/ff_pass_td.png');
      expect(leagueStatIcon('Flag Football', 'flagPulls').asset,
          'assets/ff_flag_pull.png');
      expect(leagueStatIcon('Flag Football', 'sacks').asset,
          'assets/ff_sack.png');
    });

    test('hidden negatives / thrown INT carry no icon', () {
      expect(leagueStatIcon('Flag Football', 'QBInc').asset, isNull);
      expect(leagueStatIcon('Flag Football', 'RECMiss').asset, isNull);
      expect(leagueStatIcon('Flag Football', 'Pass INT').asset, isNull);
    });
  });
}
