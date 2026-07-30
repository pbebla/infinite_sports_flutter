import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

// Mirror the helper from single_match_tallies_test.dart
TournamentMatch _m(Map<String, dynamic>? a1, Map<String, dynamic>? a2) =>
    TournamentMatch(
      id: 'M',
      stage: 'Group Stage',
      label: 'Group Stage',
      date: '08272026',
      team1Id: 'A',
      team2Id: 'B',
      team1Score: 0,
      team2Score: 0,
      status: 1,
      team1Activity: a1,
      team2Activity: a2,
      bracketPosition: 0,
    );

void main() {
  group('matchStatLeaders', () {
    test('single leader — Alex 2 goals, Bea 1', () {
      final match = _m(
        {
          '10': [
            {'Goal': 'Alex'},
          ],
          '20': [
            {'Goal': 'Alex'},
            {'Assist': 'Sam'},
          ],
          '30': [
            {'Goal': 'Bea'},
          ],
        },
        null,
      );
      expect(matchStatLeaders(match, 'goals'), {'Alex'});
    });

    test('tied leaders — Alex 1 goal, Bea 1 goal', () {
      final match = _m(
        {
          '10': [
            {'Goal': 'Alex'},
          ],
          '20': [
            {'Goal': 'Bea'},
          ],
        },
        null,
      );
      expect(matchStatLeaders(match, 'goals'), {'Alex', 'Bea'});
    });

    test('nobody has saves — returns empty set', () {
      final match = _m(
        {
          '5': [
            {'Goal': 'Alex'},
          ],
        },
        null,
      );
      expect(matchStatLeaders(match, 'saves'), isEmpty);
    });

    test('empty match — all stats return empty', () {
      final match = _m(null, null);
      expect(matchStatLeaders(match, 'goals'), isEmpty);
      expect(matchStatLeaders(match, 'assists'), isEmpty);
      expect(matchStatLeaders(match, 'saves'), isEmpty);
      expect(matchStatLeaders(match, 'dpl'), isEmpty);
    });

    test('cross-team leaders counted together', () {
      final match = _m(
        {
          '1': [
            {'goal': 'Alice'},
          ],
        },
        {
          '2': [
            {'goal': 'Bob'},
            {'goal': 'Bob'},
          ],
        },
      );
      expect(matchStatLeaders(match, 'goals'), {'Bob'});
    });

    test('assist leader picked correctly', () {
      final match = _m(
        {
          '1': [
            {'assist': 'Sam'},
            {'assist': 'Sam'},
            {'assist': 'Kai'},
          ],
        },
        null,
      );
      expect(matchStatLeaders(match, 'assists'), {'Sam'});
    });
  });
}
