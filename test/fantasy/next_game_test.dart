// Fantasy round 3, Task 4 — "Next: vs Nimrod · Sun 3 PM" (spec §4/§5): the
// earliest not-yet-final league game of a team, seen from that team.
//
// Dates (MMDDYYYY, the league key format) used below — 2026: Nov 1, Nov 8
// and Nov 15 are Sundays; Oct 28 is a Wednesday; Oct 31 a Saturday.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/next_game.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// A league game exactly as LeagueService.watchGames adapts it.
TournamentMatch game(
  String date,
  String team1,
  String team2, {
  int status = 0,
  String? time = '15:00',
  int index = 0,
  String stage = '',
}) =>
    leagueMatchFromGameMap(
      dateKey: date,
      index: index,
      raw: {
        'team1': team1,
        'team2': team2,
        'status': status,
        if (time != null) 'Time': time,
        if (stage.isNotEmpty) 'Stage': stage,
      },
    );

void main() {
  // Monday Nov 2, 2026, mid-morning (local).
  final now = DateTime(2026, 11, 2, 10, 30);

  group('nextGameForTeam', () {
    test('skips finals, picks the earliest future game', () {
      final matches = [
        game('11152026', 'Titans', 'Kings'), // later
        game('10282026', 'Titans', 'Rovers', status: 2), // final, past
        game('11012026', 'Titans', 'Rovers', status: 2), // final
        game('11082026', 'Nimrod', 'Titans'), // the next one (Titans = team2)
        game('11082026', 'Other', 'Else'), // not Titans
      ];
      final next = nextGameForTeam('Titans', matches, now)!;
      expect(next.opponent, 'Nimrod');
      expect(next.date, DateTime(2026, 11, 8));
      expect(next.timeText, '3:00 PM');
      expect(next.placeholder, isFalse);
      expect(formatNextGame(next), 'vs Nimrod · Sun 3 PM');
    });

    test('a pending game dated TODAY counts (on/after today, any hour)', () {
      final matches = [
        game('11022026', 'Titans', 'Today FC', time: '09:00'),
        game('11082026', 'Titans', 'Later FC'),
      ];
      final next = nextGameForTeam('Titans', matches, now)!;
      expect(next.opponent, 'Today FC');
      expect(next.date, DateTime(2026, 11, 2));
    });

    test('a stale pending game from a past date is skipped', () {
      final matches = [
        game('10282026', 'Titans', 'Ghost FC'), // pending but in the past
        game('11082026', 'Titans', 'Real FC'),
      ];
      expect(nextGameForTeam('Titans', matches, now)!.opponent, 'Real FC');
    });

    test('a live game is not final, so it is the next game', () {
      final matches = [
        game('11022026', 'Titans', 'Live FC', status: 1),
        game('11082026', 'Titans', 'Later FC'),
      ];
      expect(nextGameForTeam('Titans', matches, now)!.opponent, 'Live FC');
    });

    test('same day: in-day order decides (bracket position / index)', () {
      final matches = [
        game('11082026', 'Titans', 'Second FC', index: 3, time: '16:00'),
        game('11082026', 'Titans', 'First FC', index: 1, time: '15:00'),
      ];
      final next = nextGameForTeam('Titans', matches, now)!;
      expect(next.opponent, 'First FC');
      expect(next.timeText, '3:00 PM');
    });

    test('orders chronologically across a year boundary', () {
      final dec = DateTime(2026, 12, 30);
      final matches = [
        game('01112027', 'Titans', 'Late FC'),
        game('01042027', 'Titans', 'Early FC'),
      ];
      final next = nextGameForTeam('Titans', matches, dec)!;
      expect(next.opponent, 'Early FC');
      expect(next.date, DateTime(2027, 1, 4));
    });

    test('no upcoming game (or no matches at all) → null', () {
      expect(nextGameForTeam('Titans', const [], now), isNull);
      expect(
        nextGameForTeam(
            'Titans',
            [
              game('11012026', 'Titans', 'Rovers', status: 2),
              game('11082026', 'Other', 'Else'),
            ],
            now),
        isNull,
      );
    });

    test('friendlies never settle fantasy points, so they are not "next"', () {
      final matches = [
        game('11082026', 'Titans', 'Friendly FC', stage: 'friendly'),
        game('11152026', 'Titans', 'Real FC'),
      ];
      expect(nextGameForTeam('Titans', matches, now)!.opponent, 'Real FC');
    });

    test('unusable rows (bad date, empty opponent) are skipped', () {
      final matches = [
        game('garbage', 'Titans', 'Nowhere FC'),
        game('11082026', 'Titans', ''), // schedule slot not filled in yet
        game('11152026', 'Titans', 'Real FC'),
      ];
      expect(nextGameForTeam('Titans', matches, now)!.opponent, 'Real FC');
    });

    test('a bracket placeholder opponent is flagged', () {
      final matches = [
        game('11082026', 'Titans', 'Winner of SF1', stage: 'final'),
      ];
      final next = nextGameForTeam('Titans', matches, now)!;
      expect(next.placeholder, isTrue);
      expect(next.opponent, 'Winner of SF1');
      expect(formatNextGame(next), 'Playoffs · Sun');
    });

    test('a game with no stored time still resolves (legacy text)', () {
      final matches = [game('11082026', 'Titans', 'Nimrod', time: null)];
      final next = nextGameForTeam('Titans', matches, now)!;
      expect(next.opponent, 'Nimrod');
      // formatNextGame must never throw on whatever time text arrives.
      expect(formatNextGame(next), startsWith('vs Nimrod · Sun'));
    });
  });

  group('formatNextGame', () {
    NextGame g(String time, {DateTime? date, bool placeholder = false}) =>
        NextGame(
          opponent: placeholder ? 'Winner of SF2' : 'Nimrod',
          date: date ?? DateTime(2026, 11, 8),
          timeText: time,
          placeholder: placeholder,
        );

    test('on-the-hour times drop ":00"', () {
      expect(formatNextGame(g('3:00 PM')), 'vs Nimrod · Sun 3 PM');
      expect(formatNextGame(g('12:00 AM')), 'vs Nimrod · Sun 12 AM');
      expect(formatNextGame(g('11:00 AM')), 'vs Nimrod · Sun 11 AM');
    });

    test('off-the-hour times keep their minutes', () {
      expect(formatNextGame(g('3:30 PM')), 'vs Nimrod · Sun 3:30 PM');
      expect(formatNextGame(g('10:15 AM')), 'vs Nimrod · Sun 10:15 AM');
    });

    test('legacy no-space text ("5:00PM") is normalised', () {
      expect(formatNextGame(g('5:00PM')), 'vs Nimrod · Sun 5 PM');
    });

    test('compaction is idempotent on already-compact text', () {
      expect(formatNextGame(g('3 PM')), 'vs Nimrod · Sun 3 PM');
    });

    test('unrecognised or empty time text is dropped / passed through', () {
      expect(formatNextGame(g('')), 'vs Nimrod · Sun');
      expect(formatNextGame(g('   ')), 'vs Nimrod · Sun');
      expect(formatNextGame(g('TBD')), 'vs Nimrod · Sun TBD');
    });

    test('weekday abbreviations Mon..Sun', () {
      // Nov 2 2026 is a Monday.
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (var i = 0; i < 7; i++) {
        expect(formatNextGame(g('3:00 PM', date: DateTime(2026, 11, 2 + i))),
            'vs Nimrod · ${days[i]} 3 PM');
      }
    });

    test('placeholder opponents read "Playoffs · <day>" with no time', () {
      expect(
          formatNextGame(
              g('3:00 PM', date: DateTime(2026, 11, 14), placeholder: true)),
          'Playoffs · Sat');
    });
  });
}
