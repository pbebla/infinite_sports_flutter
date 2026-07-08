import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_form.dart';

void main() {
  Map<dynamic, dynamic> game(String t1, String t2, int s1, int s2,
          {int status = 2, String stage = ''}) =>
      {
        'team1': t1,
        'team2': t2,
        'team1score': s1,
        'team2score': s2,
        'status': status,
        if (stage.isNotEmpty) 'Stage': stage,
      };

  group('compareLeagueDates', () {
    test('orders MMDDYYYY chronologically across months and years', () {
      expect(compareLeagueDates('12152025', '01052026'), lessThan(0));
      expect(compareLeagueDates('06152026', '05202026'), greaterThan(0));
      expect(compareLeagueDates('06152026', '06152026'), 0);
    });
  });

  group('teamLeagueMatches / teamResultLetter / teamLeagueForm', () {
    final matches = leagueMatchesFromDateNode({
      '01052026': [
        game('Nineveh', 'Babylon', 3, 1), // W
      ],
      '12152025': [
        game('Akkad', 'Nineveh', 2, 2), // D (earliest)
      ],
      '01122026': [
        game('Nineveh', 'Ashur FC', 0, 1), // L
        game('Nineveh', 'Babylon', 9, 0, stage: 'friendly'), // excluded
      ],
      '01192026': [
        game('Nineveh', 'Akkad', 1, 0, status: 1), // live — excluded
      ],
    });

    test('teamLeagueMatches finds both home and away, chronologically', () {
      final mine = teamLeagueMatches('Nineveh', matches);
      expect(mine.length, 5);
      expect(mine.first.date, '12152025');
      expect(mine.last.date, '01192026');
    });

    test('result letters from the team perspective', () {
      final mine = teamLeagueMatches('Nineveh', matches);
      expect(teamResultLetter('Nineveh', mine[0]), 'D');
      expect(teamResultLetter('Nineveh', mine[1]), 'W');
    });

    test('form = finished, non-friendly, oldest→newest, capped', () {
      expect(teamLeagueForm('Nineveh', matches), ['D', 'W', 'L']);
      expect(teamLeagueForm('Nineveh', matches, count: 2), ['W', 'L']);
      expect(teamLeagueForm('Nobody FC', matches), isEmpty);
    });
  });
}
