// Fantasy round 3, Task 4 — fantasy player ↔ league account link (spec §4,
// "Name → account"): a runtime join over LeagueService.watchRosters
// ({team name: [TournamentPlayer]}), matched on team AND name. No uid is
// stored on fantasy Players. Review Focus 1: the same name on two teams must
// never cross-link, and an ambiguous match must yield no "See full profile".

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_account_link.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

FantasyPlayer fp(String name, String team,
        {FantasyPosition pos = FantasyPosition.att, bool eligible = true}) =>
    FantasyPlayer(
      name: name,
      position: pos,
      priceTenths: 60,
      eligible: eligible,
      teamName: team,
    );

/// A roster entry as leaguePlayerFromLineup yields it (team-keyed map; the
/// adapter already normalises UID '0'/empty to null, but the join defends
/// against the raw values too).
TournamentPlayer rp(String name, String team, String? uid) => TournamentPlayer(
      name: name,
      teamId: team,
      teamName: team,
      uid: uid,
      goals: 0,
      assists: 0,
      saves: 0,
      dpl: 0,
      cleanSheets: 0,
      yellowCards: 0,
      redCards: 0,
    );

void main() {
  group('uidForFantasyPlayer', () {
    test('links a roster entry with the same team and name', () {
      final rosters = {
        'Titans': [rp('Sam Lee', 'Titans', 'uid-sam'), rp('Bo', 'Titans', 'b')],
        'Kings': [rp('Al', 'Kings', 'uid-al')],
      };
      expect(uidForFantasyPlayer(fp('Sam Lee', 'Titans'), rosters), 'uid-sam');
      expect(uidForFantasyPlayer(fp('Al', 'Kings'), rosters), 'uid-al');
    });

    test('same name on two teams links only the matching team', () {
      final rosters = {
        'Titans': [rp('Alex Kim', 'Titans', 'uid-titans-alex')],
        'Kings': [rp('Alex Kim', 'Kings', 'uid-kings-alex')],
      };
      expect(uidForFantasyPlayer(fp('Alex Kim', 'Titans'), rosters),
          'uid-titans-alex');
      expect(uidForFantasyPlayer(fp('Alex Kim', 'Kings'), rosters),
          'uid-kings-alex');
    });

    test('same name on another team only (wrong team) → null', () {
      final rosters = {
        'Kings': [rp('Alex Kim', 'Kings', 'uid-kings-alex')],
      };
      expect(uidForFantasyPlayer(fp('Alex Kim', 'Titans'), rosters), isNull);
    });

    test("'0', empty and null uids mean unlinked → null", () {
      final rosters = {
        'Titans': [
          rp('Zero', 'Titans', '0'),
          rp('Blank', 'Titans', ''),
          rp('Spaces', 'Titans', '   '),
          rp('Nobody', 'Titans', null),
        ],
      };
      for (final n in ['Zero', 'Blank', 'Spaces', 'Nobody']) {
        expect(uidForFantasyPlayer(fp(n, 'Titans'), rosters), isNull,
            reason: n);
      }
    });

    test('unknown team / name / empty rosters → null', () {
      expect(uidForFantasyPlayer(fp('Sam', 'Titans'), const {}), isNull);
      expect(uidForFantasyPlayer(fp('Sam', 'Titans'), {'Titans': const []}),
          isNull);
      expect(
          uidForFantasyPlayer(fp('Sam', 'Nope FC'), {
            'Titans': [rp('Sam', 'Titans', 'u')]
          }),
          isNull);
    });

    test('surrounding whitespace on either side does not break the join', () {
      final rosters = {
        'Titans': [rp('Sam Lee', 'Titans', ' uid-sam ')],
      };
      expect(
          uidForFantasyPlayer(fp(' Sam Lee ', ' Titans'), rosters), 'uid-sam');
    });

    test('duplicate roster rows disagreeing on the uid → null (ambiguous)', () {
      final rosters = {
        'Titans': [rp('Sam', 'Titans', 'u1'), rp('Sam', 'Titans', 'u2')],
      };
      expect(uidForFantasyPlayer(fp('Sam', 'Titans'), rosters), isNull);
      // Duplicates that agree are still one account.
      final agree = {
        'Titans': [rp('Sam', 'Titans', 'u1'), rp('Sam', 'Titans', 'u1')],
      };
      expect(uidForFantasyPlayer(fp('Sam', 'Titans'), agree), 'u1');
    });
  });

  group('fantasyPlayerForUid', () {
    final players = [
      fp('Alex Kim', 'Titans'),
      fp('Alex Kim', 'Kings'),
      fp('Sam Lee', 'Titans'),
      fp('Pat Quinn', 'Kings'),
    ];
    final rosters = {
      'Titans': [
        rp('Alex Kim', 'Titans', 'uid-titans-alex'),
        rp('Sam Lee', 'Titans', 'uid-sam'),
      ],
      'Kings': [
        rp('Alex Kim', 'Kings', 'uid-kings-alex'),
        rp('Pat Quinn', 'Kings', '0'),
      ],
    };

    test('finds the one fantasy player whose roster entry carries the uid', () {
      final a = fantasyPlayerForUid('uid-titans-alex', players, rosters)!;
      expect((a.name, a.teamName), ('Alex Kim', 'Titans'));
      final b = fantasyPlayerForUid('uid-kings-alex', players, rosters)!;
      expect((b.name, b.teamName), ('Alex Kim', 'Kings'));
      expect(fantasyPlayerForUid('uid-sam', players, rosters)!.name, 'Sam Lee');
    });

    test('unknown uid, unlinked player or no fantasy entry → null', () {
      expect(fantasyPlayerForUid('nobody', players, rosters), isNull);
      // On a roster, but not a fantasy market player.
      expect(
          fantasyPlayerForUid('uid-extra', players, {
            ...rosters,
            'Rovers': [rp('Extra', 'Rovers', 'uid-extra')],
          }),
          isNull);
    });

    test("an empty or '0' uid never matches (unlinked rows share them)", () {
      expect(fantasyPlayerForUid('', players, rosters), isNull);
      expect(fantasyPlayerForUid('0', players, rosters), isNull);
      expect(fantasyPlayerForUid('  ', players, rosters), isNull);
    });

    test('ambiguous uid match returns null', () {
      // One account listed on two teams, both with a fantasy entry
      // (a mid-season team change): which player is "his"? Don't guess.
      final twoTeams = {
        'Titans': [rp('Jo Moves', 'Titans', 'uid-jo')],
        'Kings': [rp('Jo Moves', 'Kings', 'uid-jo')],
      };
      final both = [fp('Jo Moves', 'Titans'), fp('Jo Moves', 'Kings')];
      expect(fantasyPlayerForUid('uid-jo', both, twoTeams), isNull);

      // Only one of the two teams has a fantasy entry → unambiguous.
      expect(fantasyPlayerForUid('uid-jo', [both.first], twoTeams)!.teamName,
          'Titans');

      // Duplicated fantasy entries for the same roster row → ambiguous.
      expect(
          fantasyPlayerForUid('uid-sam',
              [fp('Sam Lee', 'Titans'), fp('Sam Lee', 'Titans')], rosters),
          isNull);
    });

    test('empty inputs → null', () {
      expect(fantasyPlayerForUid('uid-sam', const [], rosters), isNull);
      expect(fantasyPlayerForUid('uid-sam', players, const {}), isNull);
    });
  });
}
