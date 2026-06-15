import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch m(Map<String, dynamic>? a1, Map<String, dynamic>? a2) =>
    TournamentMatch(
      id: 'M', stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Id: 'A', team2Id: 'B', team1Score: 0, team2Score: 0, status: 1,
      team1Activity: a1, team2Activity: a2, bracketPosition: 0,
    );

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
}
