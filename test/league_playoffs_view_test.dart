import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';

void main() {
  Map<dynamic, dynamic> game(String t1, String t2,
          {String stage = '', int status = 0}) =>
      {
        'team1': t1,
        'team2': t2,
        'team1score': 0,
        'team2score': 0,
        'status': status,
        if (stage.isNotEmpty) 'Stage': stage,
      };

  group('LeaguePlayoffs.fromNode', () {
    test('parses Format/ThirdPlace/Champion/Slots with gameRefs + seeds', () {
      final p = LeaguePlayoffs.fromNode({
        'Format': 4,
        'ThirdPlace': true,
        'Champion': 'Nineveh',
        'Slots': {
          'sf1': {
            'team1Seed': 1,
            'team2Seed': 4,
            'gameRef': {'date': '07132026', 'index': 0},
            'winnerTo': 'f1',
          },
          'sf2': {
            'team1Seed': 2,
            'team2Seed': 3,
            'gameRef': {'date': '07132026', 'index': 1},
            'winnerTo': 'f1',
          },
          'f1': {
            'gameRef': {'date': '07202026', 'index': 0},
          },
        },
      })!;
      expect(p.format, 4);
      expect(p.thirdPlace, isTrue);
      expect(p.champion, 'Nineveh');
      expect(p.slots.length, 3);
      final sf2 = p.slots.firstWhere((s) => s.key == 'sf2');
      expect(sf2.team1Seed, 2);
      expect(sf2.position, 2);
      expect(sf2.gameId, '07132026#1');
    });

    test('missing Champion reads as empty; non-map is null', () {
      final p = LeaguePlayoffs.fromNode({'Format': 8, 'Slots': {}})!;
      expect(p.champion, '');
      expect(p.thirdPlace, isFalse);
      expect(LeaguePlayoffs.fromNode(null), isNull);
      expect(LeaguePlayoffs.fromNode('x'), isNull);
    });
  });

  group('leagueBracketMatches', () {
    test('keeps only knockout stages — regular season + friendlies out', () {
      final matches = leagueMatchesFromDateNode({
        '07062026': [
          game('A', 'B'), // regular season
          game('C', 'D', stage: 'friendly'),
        ],
        '07132026': [
          game('A', 'D', stage: 'semifinal'),
        ],
      });
      final bracket = leagueBracketMatches(null, matches);
      expect(bracket.length, 1);
      expect(bracket.single.stage, 'semifinal');
    });

    test('slot gameRefs override bracketPosition + round-1 seeds', () {
      final matches = leagueMatchesFromDateNode({
        '07132026': [
          game('Seed4 FC', 'Seed1 FC', stage: 'semifinal'),
          game('Seed2 FC', 'Seed3 FC', stage: 'semifinal'),
        ],
        '07202026': [
          game('Winner of SF1', 'Winner of SF2', stage: 'final'),
        ],
      });
      final playoffs = LeaguePlayoffs.fromNode({
        'Format': 4,
        'ThirdPlace': false,
        'Slots': {
          // The Manager's wiring says the SECOND game on the date is SF1.
          'sf1': {
            'team1Seed': 1,
            'team2Seed': 4,
            'gameRef': {'date': '07132026', 'index': 1},
          },
          'sf2': {
            'team1Seed': 2,
            'team2Seed': 3,
            'gameRef': {'date': '07132026', 'index': 0},
          },
          'f1': {
            'gameRef': {'date': '07202026', 'index': 0},
          },
        },
      });
      final bracket = leagueBracketMatches(playoffs, matches);
      final sf1 = bracket.firstWhere((m) => m.id == '07132026#1');
      expect(sf1.bracketPosition, 1);
      expect(sf1.team1Seed, 1);
      final sf2 = bracket.firstWhere((m) => m.id == '07132026#0');
      expect(sf2.bracketPosition, 2);
      final f1 = bracket.firstWhere((m) => m.id == '07202026#0');
      expect(f1.bracketPosition, 1);
      expect(f1.team1Id, 'Winner of SF1'); // placeholder passes through
    });

    test('staged matches missing from Slots still render (manual inserts)',
        () {
      final matches = leagueMatchesFromDateNode({
        '07132026': [
          game('A', 'B', stage: 'semifinal'),
        ],
      });
      final playoffs =
          LeaguePlayoffs.fromNode({'Format': 4, 'Slots': {}});
      expect(leagueBracketMatches(playoffs, matches).length, 1);
    });
  });
}
