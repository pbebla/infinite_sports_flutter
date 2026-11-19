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

  // S16 Task 3: the live Futsal/16/Playoffs node (do not change data) —
  // 6 teams, 1st and 2nd skip the quarterfinals.
  group('Season 16 wiring (winnerTo → feeders)', () {
    final s16 = {
      'Format': 8,
      'ThirdPlace': false,
      'Slots': {
        'qf1': {'team1Seed': 3, 'team2Seed': 6, 'gameRef': {'date': '01312027', 'index': 1}, 'winnerTo': 'sf1'},
        'qf2': {'team1Seed': 4, 'team2Seed': 5, 'gameRef': {'date': '01312027', 'index': 2}, 'winnerTo': 'sf2'},
        'sf1': {'team2Seed': 2, 'gameRef': {'date': '02072027', 'index': 0}, 'winnerTo': 'f1'},
        'sf2': {'team2Seed': 1, 'gameRef': {'date': '02072027', 'index': 1}, 'winnerTo': 'f1'},
        'f1': {'gameRef': {'date': '02142027', 'index': 0}},
      },
    };

    test('slots expose winnerTo (\'\' when absent)', () {
      final p = LeaguePlayoffs.fromNode(s16)!;
      final byKey = {for (final s in p.slots) s.key: s};
      expect(byKey['qf1']!.winnerTo, 'sf1');
      expect(byKey['sf2']!.winnerTo, 'f1');
      expect(byKey['f1']!.winnerTo, '');
    });

    test('feeders map each game to the games whose winners feed it', () {
      final feeders = leagueBracketFeeders(LeaguePlayoffs.fromNode(s16));
      expect(feeders, {
        leagueGameId('02072027', 0): [leagueGameId('01312027', 1)],
        leagueGameId('02072027', 1): [leagueGameId('01312027', 2)],
        leagueGameId('02142027', 0): [
          leagueGameId('02072027', 0),
          leagueGameId('02072027', 1),
        ],
      });
    });

    test('feeders are ordered by the feeding slot\'s position', () {
      final feeders = leagueBracketFeeders(LeaguePlayoffs.fromNode({
        'Slots': {
          'sf2': {'gameRef': {'date': '1', 'index': 1}, 'winnerTo': 'f1'},
          'sf1': {'gameRef': {'date': '1', 'index': 0}, 'winnerTo': 'f1'},
          'f1': {'gameRef': {'date': '2', 'index': 0}},
        },
      }));
      expect(feeders![leagueGameId('2', 0)],
          [leagueGameId('1', 0), leagueGameId('1', 1)]);
    });

    test('no playoffs, or no winnerTo wiring at all → null (index pairing)',
        () {
      expect(leagueBracketFeeders(null), isNull);
      expect(
          leagueBracketFeeders(LeaguePlayoffs.fromNode({
            'Slots': {
              'sf1': {'gameRef': {'date': '1', 'index': 0}},
              'f1': {'gameRef': {'date': '2', 'index': 0}},
            },
          })),
          isNull);
    });

    test('a winnerTo pointing at a missing slot or a slot without a gameRef '
        'is skipped', () {
      final feeders = leagueBracketFeeders(LeaguePlayoffs.fromNode({
        'Slots': {
          'qf1': {'gameRef': {'date': '1', 'index': 0}, 'winnerTo': 'sf9'},
          'qf2': {'gameRef': {'date': '1', 'index': 1}, 'winnerTo': 'sf1'},
          'sf1': {'winnerTo': 'f1'},
        },
      }));
      expect(feeders, isNull);
    });
  });
}
