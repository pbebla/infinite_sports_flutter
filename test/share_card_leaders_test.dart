import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_card_leaders.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch _match() => const TournamentMatch(
      id: 'm',
      stage: 'Group Stage',
      label: 'x',
      date: '',
      team1Score: 3,
      team2Score: 1,
      status: 2,
      bracketPosition: 1,
      team1Activity: {
        '1': [
          {'goal': 'Sam'},
          {'assist': 'Drew'}
        ],
        '2': [
          {'goal': 'Sam'},
          {'goal': 'Cam'},
          {'save': 'Lee'},
          {'dpl': 'Avery'}
        ],
      },
      team2Activity: {
        '1': [
          {'goal': 'Chris'},
          {'assist': 'Bo'}
        ],
      },
    );

void main() {
  test('top goals for team1 are ordered by count then name, capped at n', () {
    final r = topNForStat(_match(), true, 'goals', n: 2);
    expect(r.map((e) => '${e.name}:${e.count}').toList(), ['Sam:2', 'Cam:1']);
  });

  test('team separation — team2 goals do not include team1 players', () {
    final r = topNForStat(_match(), false, 'goals');
    expect(r.map((e) => e.name).toList(), ['Chris']);
  });

  test('zero-count stat returns empty list', () {
    expect(topNForStat(_match(), false, 'saves'), isEmpty);
  });

  test('ties broken alphabetically by name', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 0,
      team2Score: 0, status: 2, bracketPosition: 1,
      team1Activity: {
        '1': [
          {'goal': 'Zed'},
          {'goal': 'Abe'}
        ]
      },
    );
    expect(topNForStat(m, true, 'goals').map((e) => e.name).toList(),
        ['Abe', 'Zed']);
  });

  test('assists and dpl tallies work', () {
    expect(topNForStat(_match(), true, 'assists').map((e) => e.name).toList(),
        ['Drew']);
    expect(topNForStat(_match(), true, 'dpl').map((e) => e.name).toList(),
        ['Avery']);
  });
}
