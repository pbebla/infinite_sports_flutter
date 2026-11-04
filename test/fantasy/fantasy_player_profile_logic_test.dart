// Fantasy round 3, Task 5 — the full-screen player profile's pure model
// (spec §4): season points by source, the Matches rows with season-to-date
// totals (voided weeks excluded), the last-6 form bars, the Price tab's
// start/high/low + per-week rows, "this week's" move and the "—" rules for
// PPG/form when he has played no games.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/next_game.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

const _name = 'Demsin Betvarda';

FantasyPlayer _player({int price = 75, String team = 'Ishtar'}) =>
    FantasyPlayer(
      name: _name,
      position: FantasyPosition.def,
      priceTenths: price,
      eligible: true,
      teamName: team,
    );

PlayerWeekStats _week(
  int points, {
  Map<String, ScoreSourceLine> lines = const {},
  List<PlayerWeekGame> games = const [
    PlayerWeekGame(vs: 'Nimrod', goalsFor: 3, goalsAgainst: 1),
  ],
  bool voided = false,
  bool played = true,
}) =>
    PlayerWeekStats(
      points: points,
      played: played,
      gamesPlayed: played ? games.length : 0,
      games: games,
      lines: lines,
      voided: voided,
    );

ScoreSourceLine _l(int count, int points) =>
    ScoreSourceLine(count: count, points: points);

FantasyProfileModel _build({
  FantasyPlayer? player,
  FantasyPlayerTotals? totals,
  Map<int, PlayerWeekStats> weeks = const {},
  Map<int, Map<String, int>> priceHistory = const {},
  Map<int, Map<String, int>> priceChanges = const {},
}) =>
    buildProfileModel(
      player: player ?? _player(),
      totals: totals,
      weeks: weeks,
      priceHistory: priceHistory,
      priceChanges: priceChanges,
    );

TournamentPlayer _row(String name, String team, {String? uid}) =>
    TournamentPlayer(
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
  group('sourceTotals', () {
    test(
        'sums each source across weeks, sorted by |points| desc, zero-point '
        'sources dropped', () {
      final model = _build(weeks: {
        1: _week(9, lines: {
          'plays': _l(1, 2),
          'goals': _l(1, 4),
          'yellow': _l(1, -1),
          'saves': _l(1, 0),
          'bonus': _l(3, 3),
          'unknownKey': _l(1, 1),
        }),
        2: _week(14, lines: {
          'plays': _l(1, 2),
          'goals': _l(2, 8),
          'assists': _l(1, 3),
          'yellow': _l(1, -1),
        }),
      });

      final byKey = {for (final s in model.sourceTotals) s.key: s};
      expect(byKey['goals']!.count, 3);
      expect(byKey['goals']!.points, 12);
      expect(byKey['plays']!.count, 2);
      expect(byKey['plays']!.points, 4);
      expect(byKey['yellow']!.count, 2);
      expect(byKey['yellow']!.points, -2);
      expect(byKey['bonus']!.points, 3);
      expect(byKey['assists']!.points, 3);
      expect(byKey['unknownKey']!.points, 1);
      // Zero-point source (saves ×1 — 0 pts) never shows.
      expect(byKey.containsKey('saves'), isFalse);

      // |points| desc; ties (assists 3 / bonus 3) keep the canonical source
      // order (assists before bonus); unknown keys sort after known ones.
      expect(model.sourceTotals.map((s) => s.key).toList(),
          ['goals', 'plays', 'assists', 'bonus', 'yellow', 'unknownKey']);
      expect(byKey['goals']!.label, 'Goals');
    });

    test('source line text: "Goals ×13" / "52 pts", bonus without a count', () {
      expect(
          sourceLineLabel(
              const SourceTotal(key: 'goals', count: 13, points: 52)),
          'Goals ×13');
      expect(
          sourceLineLabel(const SourceTotal(key: 'bonus', count: 3, points: 3)),
          'Bonus');
      expect(pointsText(52), '52 pts');
      expect(pointsText(1), '1 pt');
      expect(pointsText(-1), '-1 pt');
      expect(pointsText(0), '0 pts');
    });
  });

  group('matchRows', () {
    test(
        'newest first; seasonToDate is the running total and skips voided '
        'weeks', () {
      final model = _build(weeks: {
        1: _week(5, lines: {'plays': _l(1, 2), 'goals': _l(1, 3)}),
        2: _week(0, voided: true),
        3: _week(7, lines: {'plays': _l(1, 2), 'assists': _l(1, 5)}),
      });
      expect(model.matchRows.map((r) => r.gw).toList(), [3, 2, 1]);
      expect(model.matchRows[0].points, 7);
      expect(model.matchRows[0].seasonToDate, 12);
      expect(model.matchRows[1].voided, isTrue);
      expect(model.matchRows[1].seasonToDate, 5);
      expect(model.matchRows[2].seasonToDate, 5);
      // The week's own breakdown rides on the row.
      expect(model.matchRows[0].lines.map((l) => l.key).toList(),
          ['assists', 'plays']);
    });

    test('opponents text: score per game, forfeits, no game', () {
      expect(
        opponentsText(const [
          PlayerWeekGame(vs: 'Nimrod', goalsFor: 3, goalsAgainst: 2),
          PlayerWeekGame(
              vs: 'Kings', goalsFor: 5, goalsAgainst: 0, forfeit: 'won'),
          PlayerWeekGame(
              vs: 'Ishtar', goalsFor: 0, goalsAgainst: 5, forfeit: 'lost'),
        ]),
        'vs Nimrod 3–2 · vs Kings (forfeit win) · vs Ishtar (forfeit loss)',
      );
      expect(opponentsText(const []), 'No game');
    });

    test('a week he missed keeps its row with played=false', () {
      final model = _build(weeks: {1: _week(0, played: false)});
      expect(model.matchRows.single.played, isFalse);
      expect(model.matchRows.single.opponentsText, 'vs Nimrod 3–1');
    });
  });

  group('formBars', () {
    test('last 6 weeks present, oldest to newest, capped at 6', () {
      final model = _build(weeks: {
        for (var gw = 1; gw <= 8; gw++) gw: _week(gw * 2),
      });
      expect(model.formBars.map((b) => b.gw).toList(), [3, 4, 5, 6, 7, 8]);
      expect(model.formBars.first.points, 6);
      expect(model.formBars.last.points, 16);
    });

    test('only weeks that exist (added mid-season); voided bar flagged', () {
      final model = _build(weeks: {
        4: _week(3),
        5: _week(0, voided: true),
        7: _week(8),
      });
      expect(model.formBars.map((b) => b.gw).toList(), [4, 5, 7]);
      expect(model.formBars[1].voided, isTrue);
      expect(model.formBars[1].points, 0);
    });
  });

  group('price', () {
    test(
        'rows per priced week (newest first) with the move after it; start, '
        'high, low (current price counts)', () {
      final model = _build(
        player: _player(price: 78),
        priceHistory: {
          1: {_name: 70, 'Other': 50},
          2: {_name: 75},
          3: {_name: 72},
          4: {'Other': 55}, // not priced for him that week
        },
        priceChanges: {
          1: {_name: 5},
          2: {_name: -3},
          3: {'Other': 1}, // a reprice ran, he didn't move
        },
      );
      expect(model.priceRows.map((r) => r.gw).toList(), [3, 2, 1]);
      expect(model.priceRows[0].priceTenths, 72);
      expect(model.priceRows[0].moveAfterTenths, 0);
      expect(model.priceRows[1].priceTenths, 75);
      expect(model.priceRows[1].moveAfterTenths, -3);
      expect(model.priceRows[2].moveAfterTenths, 5);
      expect(model.startPriceTenths, 70);
      expect(model.highTenths, 78); // current price is the season high
      expect(model.lowTenths, 70);
    });

    test('a priced week with no reprice yet has a null move', () {
      final model = _build(priceHistory: {
        1: {_name: 70},
      });
      expect(model.priceRows.single.moveAfterTenths, isNull);
      expect(model.highTenths, 75);
      expect(model.lowTenths, 70);
    });

    test(
        'latestMoveTenths: null before any reprice, 0 when the latest '
        'reprice skipped him, the delta otherwise', () {
      expect(_build().latestMoveTenths, isNull);
      expect(
          _build(priceChanges: {
            1: {_name: 5},
            2: {'Other': -2},
          }).latestMoveTenths,
          0);
      // A flag-only reprice week (nothing moved) is still "No change".
      expect(
          _build(priceChanges: {
            1: {_name: 5},
            2: {},
          }).latestMoveTenths,
          0);
      expect(
          _build(priceChanges: {
            1: {_name: -3},
            3: {_name: 5},
          }).latestMoveTenths,
          5);
    });

    test('move texts', () {
      expect(moveThisWeekText(null), isNull);
      expect(moveThisWeekText(0), 'No change');
      expect(moveThisWeekText(5), '▲ \$0.5M this week');
      expect(moveThisWeekText(-5), '▼ \$0.5M this week');
      expect(priceMoveText(null), '—');
      expect(priceMoveText(0), 'No change');
      expect(priceMoveText(3), '▲ \$0.3M');
      expect(priceMoveText(-12), '▼ \$1.2M');
    });
  });

  group('next game text (start hour)', () {
    // Sunday Nov 8, 2026.
    NextGame g(String time) => NextGame(
        opponent: 'Nimrod',
        date: DateTime(2026, 11, 8),
        timeText: time,
        placeholder: false);

    test('derived legacy times are recognised; stored times are not', () {
      expect(isDerivedGameTime('0:00PM'), isTrue);
      expect(isDerivedGameTime('5:00PM'), isTrue);
      expect(isDerivedGameTime('3:00 PM'), isFalse);
      expect(isDerivedGameTime('3:30 PM'), isFalse);
      expect(isDerivedGameTime(''), isFalse);
    });

    test(
        'unknown start hour (0 = absent or failed read) drops a derived '
        'time — never "0 PM"', () {
      expect(
          nextGameText(g('0:00PM'), startHourKnown: false), 'vs Nimrod · Sun');
      expect(
          nextGameText(g('1:00PM'), startHourKnown: false), 'vs Nimrod · Sun');
      // A stored time is real whatever the start hour.
      expect(nextGameText(g('3:00 PM'), startHourKnown: false),
          'vs Nimrod · Sun 3 PM');
      // Known start hour: the derived time is the league's own time.
      expect(nextGameText(g('5:00PM'), startHourKnown: true),
          'vs Nimrod · Sun 5 PM');
    });
  });

  group('stat strip texts', () {
    test('PPG and form read "—" when he has no games (never 0.0)', () {
      final none = _build(
          totals: const FantasyPlayerTotals(
              points: 0, formTenths: 0, ppgTenths: 0, games: 0));
      expect(none.ppgText, '—');
      expect(none.formText, '—');
      expect(none.gamesText, '0');

      final oldShape = _build(totals: const FantasyPlayerTotals(points: 12));
      expect(oldShape.ppgText, '—');
      expect(oldShape.formText, '—');
      expect(oldShape.gamesText, '—');
      expect(oldShape.totalPointsText, '12');
      expect(oldShape.ownedText, '—');

      final some = _build(
          totals: const FantasyPlayerTotals(
              points: 64,
              ownershipPct: 55.4,
              formTenths: 67,
              ppgTenths: 53,
              games: 12));
      expect(some.ppgText, '5.3');
      expect(some.formText, '6.7');
      expect(some.gamesText, '12');
      expect(some.totalPointsText, '64');
      expect(some.ownedText, '55%');
    });

    test('position labels', () {
      expect(positionLabel(FantasyPosition.gk), 'Goalkeeper');
      expect(positionLabel(FantasyPosition.def), 'Defender');
      expect(positionLabel(FantasyPosition.att), 'Attacker');
    });
  });

  group('rosterRowFor', () {
    test(
        'matches on team AND name — the same name on another team is never '
        'his row', () {
      final rosters = {
        'Nimrod': [_row(_name, 'Nimrod', uid: 'other')],
        'Ishtar': [_row(_name, 'Ishtar', uid: 'mine')],
      };
      expect(rosterRowFor(_player(), rosters)!.uid, 'mine');
    });

    test(
        'no row on HIS team → null, even when the name exists elsewhere '
        '(a different person — never his stats)', () {
      final rosters = {
        'Kings': [_row(_name, 'Kings', uid: 'someone-else')],
      };
      expect(rosterRowFor(_player(), rosters), isNull);
      expect(rosterRowFor(_player(), const {}), isNull);
      // Trimmed team/name still match.
      expect(
          rosterRowFor(_player(), {
            ' Ishtar ': [_row(' $_name ', 'Ishtar', uid: 'mine')],
          })!
              .uid,
          'mine');
    });
  });

  // ── Review Focus 2 + 3 ────────────────────────────────────────────────
  test('player with no weeks builds an empty model without errors', () {
    final model = _build();
    expect(model.hasWeeks, isFalse);
    expect(model.formBars, isEmpty);
    expect(model.sourceTotals, isEmpty);
    expect(model.matchRows, isEmpty);
    expect(model.priceRows, isEmpty);
    expect(model.startPriceTenths, isNull);
    expect(model.highTenths, isNull);
    expect(model.lowTenths, isNull);
    expect(model.latestMoveTenths, isNull);
    expect(model.totalPointsText, '—');
    expect(model.ppgText, '—');
    expect(model.formText, '—');
    expect(model.ownedText, '—');
    expect(model.priceTenths, 75);
  });

  test('voided week shows in match rows as voided and is excluded from totals',
      () {
    final model = _build(
      weeks: {
        1: _week(6, lines: {'plays': _l(1, 2), 'goals': _l(1, 4)}),
        // Defensive: even if a voided record carried lines, they never count.
        2: _week(0,
            voided: true, lines: {'goals': _l(3, 12), 'plays': _l(1, 2)}),
        3: _week(2, lines: {'plays': _l(1, 2)}),
      },
      priceHistory: {
        1: {_name: 70},
        2: {_name: 72},
        3: {_name: 72},
      },
    );
    final voided = model.matchRows.firstWhere((r) => r.gw == 2);
    expect(voided.voided, isTrue);
    expect(voided.points, 0);
    expect(voided.lines, isEmpty);
    expect(model.matchRows.first.seasonToDate, 8); // 6 + 2, GW2 skipped

    final byKey = {for (final s in model.sourceTotals) s.key: s};
    expect(byKey['goals']!.count, 1);
    expect(byKey['goals']!.points, 4);
    expect(byKey['plays']!.count, 2);

    // The voided week's form bar is flagged; its price row is still listed.
    expect(model.formBars.firstWhere((b) => b.gw == 2).voided, isTrue);
    expect(model.priceRows.map((r) => r.gw), contains(2));
  });

  // ── Live everywhere (Task 7) ───────────────────────────────────────────

  group('live week (the in-progress gameweek on the profile)', () {
    PlayerWeekStats liveWeek(
      int points, {
      Map<String, ScoreSourceLine> lines = const {},
      bool bonusProvisional = false,
    }) =>
        PlayerWeekStats(
          points: points,
          played: true,
          gamesPlayed: 1,
          games: const [],
          lines: lines,
          voided: false,
          live: true,
          bonusProvisional: bonusProvisional,
        );

    test('model.live: a live totals row, or a live week record', () {
      expect(_build().live, isFalse);
      expect(
          _build(
              totals: const FantasyPlayerTotals(points: 5, live: true)).live,
          isTrue);
      expect(
          _build(
              totals: const FantasyPlayerTotals(points: 5, live: false)).live,
          isFalse);
      expect(_build(weeks: {1: _week(5), 2: liveWeek(3)}).live, isTrue);
      expect(_build(weeks: {1: _week(5), 2: _week(3)}).live, isFalse);
    }, );

    test('only the live week\'s form bar is live (the newest, flagged), '
        'its points still count', () {
      final model = _build(weeks: {1: _week(5), 2: liveWeek(7)});
      expect(model.formBars.map((b) => b.live).toList(), [false, true]);
      expect(model.formBars.last.points, 7);
    });

    test('the live week\'s Matches row is flagged live, season-to-date '
        'includes it', () {
      final model = _build(weeks: {1: _week(5), 2: liveWeek(7)});
      expect(model.matchRows.map((r) => (r.gw, r.live)).toList(),
          [(2, true), (1, false)]);
      expect(model.matchRows.first.seasonToDate, 12);
    });

    test('a provisional bonus is labelled on the week\'s bonus line and in '
        'the season sources — and nowhere else', () {
      final model = _build(weeks: {
        1: _week(8, lines: {'goals': _l(1, 4), 'bonus': _l(3, 3)}),
        2: liveWeek(9, lines: {
          'goals': _l(1, 4),
          'bonus': _l(2, 2),
        }, bonusProvisional: true),
      });
      final live = model.matchRows.first;
      expect(live.gw, 2);
      expect({for (final l in live.lines) l.key: l.provisional},
          {'goals': false, 'bonus': true});
      // The settled week's bonus is final.
      expect(model.matchRows.last.lines.every((l) => !l.provisional), isTrue);
      // Season totals carry the live week's provisional bonus: flagged.
      final bonus = model.sourceTotals.firstWhere((s) => s.key == 'bonus');
      expect(bonus.points, 5);
      expect(bonus.provisional, isTrue);
      expect(model.sourceTotals.firstWhere((s) => s.key == 'goals').provisional,
          isFalse);
    });

    test('a live week whose bonus is not provisional (its game is Final) '
        'reads plain "Bonus"', () {
      final model = _build(weeks: {
        2: liveWeek(9, lines: {'bonus': _l(2, 2)}),
      });
      expect(model.matchRows.first.lines.single.provisional, isFalse);
      expect(
          sourceLineLabel(model.matchRows.first.lines.single), 'Bonus');
    });

    test('sourceLineLabel: "Bonus (provisional)" only for a provisional '
        'bonus', () {
      expect(
          sourceLineLabel(const SourceTotal(
              key: 'bonus', count: 2, points: 2, provisional: true)),
          'Bonus (provisional)');
      expect(
          sourceLineLabel(const SourceTotal(key: 'bonus', count: 3, points: 3)),
          'Bonus');
      // Never on another source, whatever the flag.
      expect(
          sourceLineLabel(const SourceTotal(
              key: 'goals', count: 2, points: 8, provisional: true)),
          'Goals ×2');
    });
  });
}
