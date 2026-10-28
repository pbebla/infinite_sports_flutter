import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/scoring.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  PlayerGameStats s({
    int goals = 0, int assists = 0, int saves = 0, int penSaved = 0,
    int penMissed = 0, int ownGoals = 0, int yellows = 0, int reds = 0,
    int dpl = 0, int conceded = 0, bool present = true,
  }) =>
      PlayerGameStats(
          goals: goals, assists: assists, saves: saves, penSaved: penSaved,
          penMissed: penMissed, ownGoals: ownGoals, yellows: yellows,
          reds: reds, dpl: dpl, teamConceded: conceded, present: present);

  test('absent player scores zero regardless of stats', () {
    final r = scorePlayerGame(s(goals: 3, present: false), FantasyPosition.att, cfg);
    expect(r.total, 0);
    expect(r.breakdown, isEmpty);
  });
  test('appearance point (CS suppressed by a conceded goal)', () {
    expect(scorePlayerGame(s(conceded: 1), FantasyPosition.def, cfg).total, 1);
  });
  test('GK goal is +10 on top of plays', () {
    expect(scorePlayerGame(s(goals: 1, conceded: 1), FantasyPosition.gk, cfg)
        .total, 1 + 10);
  });
  test('clean sheet needs present + zero conceded', () {
    expect(scorePlayerGame(s(), FantasyPosition.gk, cfg).total, 1 + 8);
    expect(scorePlayerGame(s(conceded: 1), FantasyPosition.gk, cfg).total, 1);
  });
  test('every 2 saves = +1 (GK), floors', () {
    expect(scorePlayerGame(s(saves: 5), FantasyPosition.gk, cfg).total,
        1 + 8 + 2); // plays + CS + floor(5/2)
  });
  test('ATT never loses for conceding; GK/DEF lose 1 per 2', () {
    expect(scorePlayerGame(s(conceded: 4), FantasyPosition.att, cfg).total, 1);
    expect(scorePlayerGame(s(conceded: 4), FantasyPosition.def, cfg).total, 1 - 2);
    expect(scorePlayerGame(s(conceded: 5), FantasyPosition.gk, cfg).total, 1 - 2);
  });
  test('DPL threshold bonus (conceded: 1 suppresses CS, too few to deduct)', () {
    expect(scorePlayerGame(s(dpl: 5, conceded: 1), FantasyPosition.def, cfg)
        .total, 1 + 2);
    expect(scorePlayerGame(s(dpl: 4, conceded: 1), FantasyPosition.def, cfg)
        .total, 1);
    expect(scorePlayerGame(s(dpl: 7, conceded: 1), FantasyPosition.att, cfg)
        .total, 1 + 2);
    expect(scorePlayerGame(s(dpl: 99, conceded: 1), FantasyPosition.gk, cfg)
        .total, 1);
  });
  test('cards, own goals, pens', () {
    expect(scorePlayerGame(s(yellows: 1, reds: 1, conceded: 1),
        FantasyPosition.att, cfg).total, 1 - 1 - 3);
    expect(scorePlayerGame(s(ownGoals: 1, conceded: 1), FantasyPosition.def, cfg)
        .total, 1 - 2);
    expect(scorePlayerGame(s(penSaved: 1), FantasyPosition.gk, cfg).total,
        1 + 8 + 5);
    expect(scorePlayerGame(s(penMissed: 1, conceded: 1), FantasyPosition.att, cfg)
        .total, 1 - 2);
  });
  test('kitchen-sink DEF example matches hand math', () {
    // plays 1 + goal 6 + assist 4 + dpl(6>=5) 2 - conceded(3)/2 1 - yellow 1 = 11
    expect(scorePlayerGame(
        s(goals: 1, assists: 1, dpl: 6, conceded: 3, yellows: 1),
        FantasyPosition.def, cfg).total, 11);
  });
  test('breakdown lines sum to total', () {
    final r = scorePlayerGame(
        s(goals: 2, saves: 4, conceded: 2), FantasyPosition.gk, cfg);
    expect(r.breakdown.fold<int>(0, (a, b) => a + b.points), r.total);
  });
  test('gameweek sum across multiple games', () {
    final wk = scorePlayerWeek(
        [s(goals: 1, conceded: 1), s(conceded: 2, yellows: 1)],
        FantasyPosition.att, cfg);
    expect(wk.total, (1 + 4) + (1 - 1));
    expect(wk.played, isTrue);
  });
  test('week with no present games = not played', () {
    final wk = scorePlayerWeek([s(present: false)], FantasyPosition.att, cfg);
    expect(wk.total, 0);
    expect(wk.played, isFalse);
  });

  group('forfeits (spec §8a, Option B)', () {
    PlayerGameStats f(GameForfeit forfeit,
            {bool present = true, int goals = 0, int conceded = 0}) =>
        PlayerGameStats(
            goals: goals,
            teamConceded: conceded,
            present: present,
            forfeit: forfeit);

    test('team that showed up: ONLY the Plays line, every position — no '
        'clean sheet even at 0 conceded, stray stats ignored', () {
      for (final pos in FantasyPosition.values) {
        final r = scorePlayerGame(f(GameForfeit.won, goals: 2), pos, cfg);
        expect(r.total, 1, reason: pos.db);
        expect([for (final l in r.breakdown) l.label], ['Plays'],
            reason: pos.db);
      }
    });

    test('team that showed up: an absent player still gets 0', () {
      final r = scorePlayerGame(
          f(GameForfeit.won, present: false), FantasyPosition.def, cfg);
      expect(r.total, 0);
      expect(r.breakdown, isEmpty);
    });

    test('forfeiting team: 0, no appearance, no goals-conceded penalty', () {
      for (final pos in FantasyPosition.values) {
        final r =
            scorePlayerGame(f(GameForfeit.lost, conceded: 5), pos, cfg);
        expect(r.total, 0, reason: pos.db);
        expect(r.breakdown, isEmpty, reason: pos.db);
      }
    });

    test('played: showing-up present = played; forfeiting team = NOT played',
        () {
      expect(f(GameForfeit.won).played, isTrue);
      expect(f(GameForfeit.won, present: false).played, isFalse);
      expect(f(GameForfeit.lost).played, isFalse);
      expect(f(GameForfeit.none).played, isTrue);

      final forfeitOnly =
          scorePlayerWeek([f(GameForfeit.lost)], FantasyPosition.gk, cfg);
      expect(forfeitOnly.total, 0);
      expect(forfeitOnly.played, isFalse);

      // A second, normal game the same week still counts as playing.
      final twoGames = scorePlayerWeek(
          [f(GameForfeit.lost), s(conceded: 1)], FantasyPosition.att, cfg);
      expect(twoGames.total, 1);
      expect(twoGames.played, isTrue);
    });
  });
}
