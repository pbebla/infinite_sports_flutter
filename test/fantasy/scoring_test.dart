import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/scoring.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  PlayerGameStats s({
    int goals = 0, int assists = 0, int saves = 0, int penSaved = 0,
    int penMissed = 0, int ownGoals = 0, int yellows = 0, int reds = 0,
    int dpl = 0, int conceded = 0, bool present = true, bool inGoal = false,
  }) =>
      PlayerGameStats(
          goals: goals, assists: assists, saves: saves, penSaved: penSaved,
          penMissed: penMissed, ownGoals: ownGoals, yellows: yellows,
          reds: reds, dpl: dpl, teamConceded: conceded, present: present,
          inGoal: inGoal);

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
  test('every line carries a stable key and count', () {
    // conceded 1: no clean sheet; ATT never loses points for conceding.
    final r = scorePlayerGame(
        s(goals: 2, assists: 1, yellows: 1, conceded: 1),
        FantasyPosition.att, cfg);
    expect([for (final l in r.breakdown) (l.key, l.count)],
        [('plays', 1), ('goals', 2), ('assists', 1), ('yellow', 1)]);
    // Labels and points are untouched by the new fields.
    expect([for (final l in r.breakdown) (l.label, l.points)], [
      ('Plays', 1),
      ('Goals ×2', 8),
      ('Assists ×1', 3),
      ('Yellow ×1', -1),
    ]);
  });
  test('keys/counts for every other source (the stat each count is)', () {
    final def = scorePlayerGame(
        s(goals: 1, assists: 2, dpl: 6, conceded: 3, yellows: 1, reds: 1,
            ownGoals: 1, penMissed: 1),
        FantasyPosition.def, cfg);
    expect([for (final l in def.breakdown) (l.key, l.count)], [
      ('plays', 1),
      ('goals', 1),
      ('assists', 2),
      ('penMissed', 1),
      ('conceded', 3),
      ('dpl', 6),
      ('yellow', 1),
      ('red', 1),
      ('ownGoals', 1),
    ]);
    final gk =
        scorePlayerGame(s(saves: 5, penSaved: 1), FantasyPosition.gk, cfg);
    expect([for (final l in gk.breakdown) (l.key, l.count)], [
      ('plays', 1),
      ('cleanSheet', 1),
      ('saves', 5),
      ('penSaved', 1),
    ]);
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
        expect([for (final l in r.breakdown) (l.key, l.count)], [('plays', 1)],
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

  group('stand-in goalkeeper (inGoal, spec §7)', () {
    // futsalDefault rows: GK CS +8 / every 2 saves +1 / pen save +5 / every
    // 2 conceded -1; DEF CS +5 / saves - / pen save - / conceded -1; ATT CS
    // +2 / saves - / pen save - / conceded -. Goals: GK 10, DEF 6, ATT 4;
    // assists GK 5, DEF 4, ATT 3.
    List<(String, int, int, String)> lines(GameScore r) =>
        [for (final l in r.breakdown) (l.key, l.count, l.points, l.label)];
    const def = FantasyPosition.def;
    const att = FantasyPosition.att;

    test('DEF in goal: 3 saves + clean sheet score at GK rates', () {
      final r = scorePlayerGame(s(saves: 3, inGoal: true), def, cfg);
      // plays 1 + CS(GK) 8 + floor(3/2)*1 = 10 (outfield DEF: 1 + 5 = 6)
      expect(r.total, 10);
      expect(lines(r), [
        ('plays', 1, 1, 'Plays'),
        ('cleanSheet', 1, 8, 'Clean sheet'),
        ('saves', 3, 1, 'Saves ×3'),
      ]);
      expect(scorePlayerGame(s(saves: 3), def, cfg).total, 6);
    });

    test('ATT in goal with 0 saves conceding 4: GK conceded rate', () {
      final r = scorePlayerGame(s(conceded: 4, inGoal: true), att, cfg);
      // plays 1 + floor(4/2)*-1 = -1 (outfield ATT is never docked: 1)
      expect(r.total, -1);
      expect(lines(r), [
        ('plays', 1, 1, 'Plays'),
        ('conceded', 4, -2, 'Conceded 4'),
      ]);
      expect(scorePlayerGame(s(conceded: 4), att, cfg).total, 1);
    });

    test('ATT in goal keeps a clean sheet at the GK rate', () {
      // plays 1 + CS(GK) 8 = 9 (outfield ATT: 1 + 2 = 3)
      expect(scorePlayerGame(s(inGoal: true), att, cfg).total, 9);
      expect(scorePlayerGame(s(), att, cfg).total, 3);
    });

    test('DEF in goal: goals/assists stay at DEF rates, saves/pens/conceded '
        'at GK rates', () {
      PlayerGameStats st({required bool inGoal}) => s(
          goals: 1, assists: 1, saves: 3, penSaved: 1, conceded: 2,
          inGoal: inGoal);
      final r = scorePlayerGame(st(inGoal: true), def, cfg);
      // plays 1 + goal(DEF) 6 + assist(DEF) 4 + floor(3/2)*1 + pen save 5
      // + floor(2/2)*-1 = 16 (listed GK would be 1+10+5+1+5-1 = 21)
      expect(r.total, 16);
      expect(lines(r), [
        ('plays', 1, 1, 'Plays'),
        ('goals', 1, 6, 'Goals ×1'),
        ('assists', 1, 4, 'Assists ×1'),
        ('saves', 3, 1, 'Saves ×3'),
        ('penSaved', 1, 5, 'Penalty saves ×1'),
        ('conceded', 2, -1, 'Conceded 2'),
      ]);
      expect(scorePlayerGame(st(inGoal: false), def, cfg).total, 1 + 6 + 4 - 1);
    });

    test('appearance, cards, own goals, pen misses and DPL stay at the '
        'listed position', () {
      PlayerGameStats st({int dpl = 5}) => s(
          dpl: dpl, yellows: 1, reds: 1, ownGoals: 1, penMissed: 1,
          conceded: 1, inGoal: true);
      // DEF: plays 1 - pen miss 2 + DPL(5>=5) 2 - yellow 1 - red 3 - OG 2 = -5
      // (GK has no DPL threshold — a GK row here would give -7)
      expect(scorePlayerGame(st(), def, cfg).total, -5);
      // ATT: DPL needs 7 -> 5 earns nothing: 1 - 2 - 1 - 3 - 2 = -7
      expect(scorePlayerGame(st(dpl: 7), att, cfg).total, -5);
      expect(scorePlayerGame(st(), att, cfg).total, -7);
    });

    test('listed GKs are unaffected by the flag', () {
      const gk = FantasyPosition.gk;
      for (final (inGoalStats, outfieldStats) in [
        (s(saves: 5, penSaved: 1, inGoal: true), s(saves: 5, penSaved: 1)),
        (s(conceded: 4, goals: 1, inGoal: true), s(conceded: 4, goals: 1)),
      ]) {
        final a = scorePlayerGame(inGoalStats, gk, cfg);
        final b = scorePlayerGame(outfieldStats, gk, cfg);
        expect(a.total, b.total);
        expect(lines(a), lines(b));
      }
    });

    test('rates come from the live config GK row, not constants', () {
      final base = FantasyConfig.futsalDefault().toMap();
      final gkRow = Map<String, dynamic>.from(
          (base['scoring'] as Map)['GK'] as Map)
        ..['cleanSheet'] = 9
        ..['per2Saves'] = 2
        ..['per2Conceded'] = -3;
      (base['scoring'] as Map)['GK'] = gkRow;
      final custom = FantasyConfig.fromMap(base);
      // plays 1 + CS 9 + floor(4/2)*2 = 14
      expect(scorePlayerGame(s(saves: 4, inGoal: true), def, custom).total, 14);
      // plays 1 + floor(2/2)*-3 = -2
      expect(
          scorePlayerGame(s(conceded: 2, inGoal: true), att, custom).total, -2);
    });

    test('forfeit rules are unchanged for a stand-in', () {
      final won = scorePlayerGame(
          const PlayerGameStats(forfeit: GameForfeit.won, inGoal: true),
          att,
          cfg);
      expect(won.total, 1);
      expect(lines(won), [('plays', 1, 1, 'Plays')]);
      expect(
          scorePlayerGame(
                  const PlayerGameStats(
                      forfeit: GameForfeit.lost, teamConceded: 5, inGoal: true),
                  def,
                  cfg)
              .total,
          0);
      expect(
          scorePlayerGame(
                  s(present: false, saves: 4, inGoal: true), def, cfg)
              .total,
          0);
    });
  });
}
