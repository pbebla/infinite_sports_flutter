import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';

/// iOS wrong-node fix: [TournamentService.parseTournamentBundle] is the pure
/// parse core behind getTournamentBundle (one-shot, via once()) and
/// watchTournamentBundle (the detail page's live stream). These tests pin
/// that the bundle produces exactly what the separate per-node calls used
/// to, off one realistic snapshot — and that the ROOT-shape guard refuses
/// the exact payload firebase-ios-sdk handed back during the incident
/// (get() under an active /Tournaments root listener returned the root map,
/// whose tournament children rendered as "teams").
void main() {
  /// Mirrors the live /Tournaments/<id> node shape.
  Map<String, dynamic> realisticTournament() => {
        'Name': 'Infinite Cup',
        'Sport': 'Soccer',
        'Edition': '2026',
        'Finished': false,
        'Status': 'Group Stage',
        'LogoUrl': 'https://example.com/cup.png',
        'Teams': {
          'lions': {
            'Name': 'Lions FC',
            'LogoUrl': 'https://example.com/lions.png',
          },
          'tigers': {
            'Name': 'Tigers FC',
            'LogoUrl': 'https://example.com/tigers.png',
          },
        },
        'Table': {
          'lions': {
            'GP': 3,
            'W': 2,
            'D': 1,
            'L': 0,
            'GS': 7,
            'GC': 2,
            'GD': 5,
            'Pts': 7,
          },
          'tigers': {
            'GP': 3,
            'W': 1,
            'D': 1,
            'L': 1,
            'GS': 4,
            'GC': 4,
            'GD': 0,
            'Pts': 4,
          },
        },
        'Matches': {
          'm2': {
            'Team1Id': 'tigers',
            'Team2Id': 'lions',
            'Team1Score': 0,
            'Team2Score': 0,
            'Date': '06082026',
            'Status': 0,
            'Stage': 'Group Stage',
            'BracketPosition': 0,
          },
          'm1': {
            'Team1Id': 'lions',
            'Team2Id': 'tigers',
            'Team1Score': 2,
            'Team2Score': 1,
            'Date': '06012026',
            'Status': 2,
            'Stage': 'Group Stage',
            'BracketPosition': 0,
          },
        },
        'Rosters': {
          'lions': {
            'Leo Striker': {
              'Number': '10',
              'Position': 'Forward',
              'Goals': 3,
              'Assists': 1,
            },
          },
        },
        'PredictionConfig': {
          'Open': true,
          'Scoring': {'MatchWinner': 1, 'ExactScoreBonus': 3},
        },
      };

  group('TournamentService.parseTournamentBundle', () {
    test('parses the header exactly like getTournamentHeader', () {
      final bundle = TournamentService.parseTournamentBundle(
          'cup-a', realisticTournament())!;
      final t = bundle.tournament;
      expect(t, isNotNull);
      expect(t!.id, 'cup-a');
      expect(t.name, 'Infinite Cup');
      expect(t.sport, 'Soccer');
      expect(t.edition, '2026');
      expect(t.finished, isFalse);
      expect(t.status, 'Group Stage');
      expect(t.logoUrl, 'https://example.com/cup.png');
    });

    test('merges Teams with Table numbers exactly like getTeams', () {
      final bundle = TournamentService.parseTournamentBundle(
          'cup-a', realisticTournament())!;
      expect(bundle.teams.length, 2);
      final lions = bundle.teams['lions']!;
      expect(lions.name, 'Lions FC');
      expect(lions.logoUrl, 'https://example.com/lions.png');
      expect(lions.gp, 3);
      expect(lions.wins, 2);
      expect(lions.draws, 1);
      expect(lions.losses, 0);
      expect(lions.gs, 7);
      expect(lions.gc, 2);
      expect(lions.gd, 5);
      expect(lions.points, 7);
      expect(bundle.teams['tigers']!.points, 4);
    });

    test('parses matches with fields, sorted by date', () {
      final bundle = TournamentService.parseTournamentBundle(
          'cup-a', realisticTournament())!;
      expect(bundle.matches.length, 2);
      // m1 (06012026) sorts before m2 (06082026)
      final first = bundle.matches.first;
      expect(first.id, 'm1');
      expect(first.team1Id, 'lions');
      expect(first.team2Id, 'tigers');
      expect(first.team1Score, 2);
      expect(first.team2Score, 1);
      expect(first.status, 2);
      expect(bundle.matches.last.id, 'm2');
    });

    test('parses the prediction config open flag + scoring', () {
      final bundle = TournamentService.parseTournamentBundle(
          'cup-a', realisticTournament())!;
      expect(bundle.config.open, isTrue);
      expect(bundle.config.matchWinnerPoints, 1);
      expect(bundle.config.exactScorePoints, 3);
    });

    test('rosters parse inside the bundle via parseRosters', () {
      final bundle = TournamentService.parseTournamentBundle(
          'cup-a', realisticTournament())!;
      final rosters = bundle.rosters;
      expect(rosters.length, 1);
      final players = rosters['lions']!;
      expect(players.length, 1);
      final p = players.single;
      expect(p.name, 'Leo Striker');
      // Team name resolves through the bundle's teams map, not the raw id.
      expect(p.teamName, 'Lions FC');
      expect(p.number, '10');
      expect(p.position, 'Forward');
      expect(p.goals, 3);
      expect(p.assists, 1);
    });

    test('missing Table node: teams still parse with zeroed table rows', () {
      final raw = realisticTournament()..remove('Table');
      final bundle = TournamentService.parseTournamentBundle('cup-a', raw)!;
      expect(bundle.teams.length, 2);
      final lions = bundle.teams['lions']!;
      expect(lions.name, 'Lions FC');
      expect(lions.gp, 0);
      expect(lions.wins, 0);
      expect(lions.points, 0);
    });

    test('numbers arriving as doubles (iOS NSNumber shape) parse as ints', () {
      final bundle = TournamentService.parseTournamentBundle('cup-a', {
        'Name': 'Infinite Cup',
        'Sport': 'Soccer',
        'Edition': '2026',
        'Finished': false,
        'Teams': {
          'lions': {'Name': 'Lions FC'},
        },
        'Table': {
          'lions': {
            'GP': 5.0,
            'W': 5.0,
            'D': 0.0,
            'L': 0.0,
            'GS': 20.0,
            'GC': 3.0,
            'GD': 17.0,
            'Pts': 15.0,
          },
        },
        'Matches': {
          'm1': {
            'Team1Id': 'lions',
            'Team2Id': 'tigers',
            'Team1Score': 2.0,
            'Team2Score': 1.0,
            'Date': '06012026',
            'Status': 2.0,
            'BracketPosition': 0.0,
          },
        },
      })!;
      final lions = bundle.teams['lions']!;
      expect(lions.gp, 5);
      expect(lions.wins, 5);
      expect(lions.gd, 17);
      expect(lions.points, 15);
      final m = bundle.matches.single;
      expect(m.team1Score, 2);
      expect(m.team2Score, 1);
      expect(m.status, 2);
    });

    test('null / garbage input returns null without throwing', () {
      for (final raw in [
        null,
        'not-a-map',
        42,
        ['a', 'list'],
      ]) {
        expect(TournamentService.parseTournamentBundle('cup-a', raw), isNull);
      }
    });

    test('TournamentBundle.empty carries the graceful one-shot defaults', () {
      // getTournamentBundle degrades an unusable snapshot to empty() so the
      // one-shot callers (front page, profile, notification router) keep
      // their existing behavior.
      final bundle = TournamentBundle.empty();
      expect(bundle.tournament, isNull);
      expect(bundle.teams, isEmpty);
      expect(bundle.matches, isEmpty);
      expect(bundle.rosters, isEmpty);
      // getPredictionConfig's graceful defaults
      expect(bundle.config.open, isTrue);
      expect(bundle.config.matchWinnerPoints, 1);
      expect(bundle.config.exactScorePoints, 3);
    });

    test('missing child nodes yield empty collections, header still parses',
        () {
      final bundle = TournamentService.parseTournamentBundle('cup-a', {
        'Name': 'Header Only Cup',
        'Sport': 'Basketball',
        'Edition': '1',
        'Finished': true,
      })!;
      expect(bundle.tournament!.name, 'Header Only Cup');
      expect(bundle.tournament!.finished, isTrue);
      expect(bundle.teams, isEmpty);
      expect(bundle.matches, isEmpty);
      expect(bundle.rosters, isEmpty);
    });

    test(
        'REGRESSION (iOS wrong-node get): a /Tournaments ROOT payload returns '
        'null instead of parsing tournaments as teams', () {
      // The exact shape firebase-ios-sdk handed back for
      // get('/Tournaments/<id>/...') while the permanent /Tournaments root
      // listener was live: the ROOT map — several tournament nodes plus the
      // 'Current Tournament' string pointer. Parsing it as a tournament made
      // the Teams tab list THE TOURNAMENTS THEMSELVES as 0-stat teams.
      final root = {
        'Current Tournament': 'test-tournament-2026',
        'basket123': realisticTournament()..['Name'] = '3vs3 basketballl',
        'ca_state_assyrian_2026': realisticTournament()
          ..['Name'] = 'California State Assyrian Tournament 2026',
        'test-tournament-2026': realisticTournament()
          ..['Name'] = 'Test Tournament 2026',
      };
      expect(
          TournamentService.parseTournamentBundle('basket123', root), isNull);
    });

    test(
        'root shape without the Current Tournament pointer is still refused '
        '(majority of values are tournament-shaped maps)', () {
      final root = {
        'a': realisticTournament(),
        'b': realisticTournament(),
        'c': realisticTournament(),
      };
      expect(TournamentService.parseTournamentBundle('a', root), isNull);
    });
  });
}
