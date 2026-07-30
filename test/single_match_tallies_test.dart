import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch m(Map<String, dynamic>? a1, Map<String, dynamic>? a2) =>
    TournamentMatch(
      id: 'M', stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Id: 'A', team2Id: 'B', team1Score: 0, team2Score: 0, status: 1,
      team1Activity: a1, team2Activity: a2, bracketPosition: 0,
    );

/// Named-parameter fixture builder (P4) — mirrors [m] for tests that only
/// care about one team's activity.
TournamentMatch matchWithActivities({
  Map<String, dynamic>? team1Activity,
  Map<String, dynamic>? team2Activity,
}) =>
    m(team1Activity, team2Activity);

void main() {
  test('tallies goals/assists/saves/dpl across both teams', () {
    final t = singleMatchPlayerTallies(m(
      {
        '12': [
          {'goal': 'Sam'},
          {'assist': 'Kai'},
        ],
        '20': [
          {'penalty goal': 'Sam'},
        ],
      },
      {
        '5': [
          {'save': 'Gary'},
          {'dpl': 'Gary'},
        ],
      },
    ));
    expect(t['Sam']!.goals, 2);
    expect(t['Kai']!.assists, 1);
    expect(t['Gary']!.saves, 1);
    expect(t['Gary']!.dpl, 1);
  });

  test('non-counter events ignored; empty when no activity', () {
    final t = singleMatchPlayerTallies(m({
      '1': [
        {'foul': 'Sam'},
        {'substitution': 'Kai'},
        {'yellow card': 'Sam'},
      ],
    }, null));
    expect(t['Sam']?.goals ?? 0, 0);
    expect(t['Sam']?.saves ?? 0, 0);
    expect(singleMatchPlayerTallies(m(null, null)), isEmpty);
  });

  test('index-keyed Map bucket tolerated', () {
    final t = singleMatchPlayerTallies(m({
      '5': {
        '0': {'goal': 'Sam'},
      },
    }, null));
    expect(t['Sam']!.goals, 1);
  });

  group('league activity types (League Experience P2)', () {
    test('PenGoal counts as a goal — a penalty goal writes ONE entry', () {
      final tallies = playerTalliesForActivity({
        "5'": [
          {'PenGoal': 'Ashur'},
        ],
      });
      expect(tallies['Ashur']!.goals, 1);
    });

    test('PenSaved counts as a save for the keeper', () {
      final tallies = playerTalliesForActivity({
        "12'": [
          {'PenSaved': 'Sargon'},
        ],
      });
      expect(tallies['Sargon']!.saves, 1);
    });

    test('OwnGoal does NOT count toward goals leaders', () {
      final tallies = playerTalliesForActivity({
        "20'": [
          {'OwnGoal': 'Ninos'},
        ],
      });
      expect(tallies['Ninos']?.goals ?? 0, 0);
    });

    test('league Goal/Assist/Save/DPL spellings keep counting', () {
      final tallies = playerTalliesForActivity({
        "3'": [
          {'Goal': 'Ashur'},
          {'Assist': 'Ninos'},
        ],
        "9'": [
          {'Save': 'Sargon'},
          {'DPL': 'Ramina'},
        ],
      });
      expect(tallies['Ashur']!.goals, 1);
      expect(tallies['Ninos']!.assists, 1);
      expect(tallies['Sargon']!.saves, 1);
      expect(tallies['Ramina']!.dpl, 1);
    });
  });

  group('P4 — basketball/flag football tallies', () {
    test('basketball: points weighted 1/2/3 + counting stats', () {
      final match = matchWithActivities(team1Activity: {
        "3'": [
          {'OnePointer': 'Sam'},
          {'TwoPointer': 'Sam'},
          {'ThreePointer': 'Sam'},
          {'Rebound': 'Sam'},
          {'Assist': 'Alex'},
          {'Steal': 'Sam'},
          {'Block': 'Alex'},
        ],
      });
      final tallies = singleMatchPlayerTallies(match);
      expect(tallies['Sam']!.byStat('points'), 6); // 1+2+3
      expect(tallies['Sam']!.byStat('rebounds'), 1);
      expect(tallies['Sam']!.byStat('steals'), 1);
      expect(tallies['Alex']!.byStat('assists'), 1);
      expect(tallies['Alex']!.byStat('blocks'), 1);
    });

    test('flag football: touchdowns sum the three TD types', () {
      final match = matchWithActivities(team1Activity: {
        "5'": [
          {'Receiving TD': 'Sam'},
          {'Rushing TD': 'Sam'},
          {'INT TD': 'Alex'},
          {'Pass TD': 'Q'},
          {'REC': 'Sam'},
          {'Interception': 'Alex'},
          {'FP': 'Alex'},
          {'Sack': 'Alex'},
        ],
      });
      final tallies = singleMatchPlayerTallies(match);
      expect(tallies['Sam']!.byStat('touchdowns'), 2);
      expect(tallies['Alex']!.byStat('touchdowns'), 1);
      expect(tallies['Q']!.byStat('passTouchdowns'), 1);
      expect(tallies['Sam']!.byStat('receptions'), 1);
      expect(tallies['Alex']!.byStat('interceptions'), 1);
      expect(tallies['Alex']!.byStat('flagPulls'), 1);
      expect(tallies['Alex']!.byStat('sacks'), 1);
    });

    test('futsal tallies unchanged', () {
      final match = matchWithActivities(team1Activity: {
        "7'": [
          {'Goal': 'Sam'},
          {'PenGoal': 'Sam'},
          {'Assist': 'Alex'},
        ],
      });
      final tallies = singleMatchPlayerTallies(match);
      expect(tallies['Sam']!.byStat('goals'), 2);
      expect(tallies['Alex']!.byStat('assists'), 1);
    });

    test('leagueMatchLeaderCategories per sport', () {
      expect(
        leagueMatchLeaderCategories('Basketball')
            .map((c) => c['stat'])
            .toList(),
        ['points', 'rebounds', 'assists', 'steals', 'blocks'],
      );
      expect(
        leagueMatchLeaderCategories('Flag Football')
            .map((c) => c['stat'])
            .toList(),
        ['touchdowns', 'passTouchdowns', 'receptions', 'catchPercentage',
          'interceptions', 'flagPulls', 'sacks'],
      );
      expect(
        leagueMatchLeaderCategories('Futsal')
            .map((c) => c['stat'])
            .toList(),
        ['goals', 'assists', 'saves', 'dpl'],
      );
    });

    test('Catch % leader category carries the % suffix', () {
      final cat = leagueMatchLeaderCategories('Flag Football')
          .firstWhere((c) => c['stat'] == 'catchPercentage');
      expect(cat['label'], 'Catch %');
      expect(cat['suffix'], '%');
    });
  });

  group('L6.1 — catchPercentage (Task 3)', () {
    test('null when there are zero targets (no data, not 0%)', () {
      expect(catchPercentage(0, 0), isNull);
    });

    test('computes a rounded whole-number percent', () {
      expect(catchPercentage(3, 1), 75); // 3/4
      expect(catchPercentage(2, 1), 67); // 2/3 = 66.67 -> 67
      expect(catchPercentage(5, 0), 100);
      expect(catchPercentage(0, 5), 0); // legitimate 0% (has targets)
    });

    test('minTargets gates small samples to null (default: no gate)', () {
      expect(catchPercentage(1, 0), 100); // no gate by default
      expect(catchPercentage(1, 0, minTargets: 3), isNull); // 1 target < 3
      expect(catchPercentage(1, 1, minTargets: 3), isNull); // 2 targets < 3
      expect(catchPercentage(2, 1, minTargets: 3), 67); // 3 targets, passes
    });
  });

  group('L6.1 — RECMiss tally + Catch % byStat (Task 3)', () {
    test('recmiss events tally into recMisses count', () {
      final match = matchWithActivities(team1Activity: {
        "5'": [
          {'REC': 'Sam'},
          {'REC': 'Sam'},
          {'RECMiss': 'Sam'},
        ],
      });
      final tallies = singleMatchPlayerTallies(match);
      expect(tallies['Sam']!.byStat('receptions'), 2);
      expect(tallies['Sam']!.counts['recMisses'], 1);
    });

    test('byStat("catchPercentage") applies the built-in >=3-target gate',
        () {
      // Only 2 targets (1 REC + 1 RECMiss) -> below the gate -> 0 (hidden
      // from the Match Leaders "> 0" filter, same as "no data").
      final below = singleMatchPlayerTallies(matchWithActivities(
        team1Activity: {
          "1'": [
            {'REC': 'Sam'},
            {'RECMiss': 'Sam'},
          ],
        },
      ));
      expect(below['Sam']!.byStat('catchPercentage'), 0);

      // 3 targets (2 REC + 1 RECMiss) -> passes the gate -> 67%.
      final atGate = singleMatchPlayerTallies(matchWithActivities(
        team1Activity: {
          "1'": [
            {'REC': 'Sam'},
            {'REC': 'Sam'},
            {'RECMiss': 'Sam'},
          ],
        },
      ));
      expect(atGate['Sam']!.byStat('catchPercentage'), 67);
    });
  });
}
