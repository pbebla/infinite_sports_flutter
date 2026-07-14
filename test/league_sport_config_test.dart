import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_sport_config.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';

void main() {
  group('futsalLeagueConfig — capture layout (spec §3 table)', () {
    test('row buttons are G/A/Save/DPL/Foul in order', () {
      expect(
        futsalLeagueConfig.rowEvents.map((e) => e.activityType).toList(),
        ['Goal', 'Assist', 'Save', 'DPL', 'Foul'],
      );
    });

    test('top bar is the seven rare events in order', () {
      expect(
        futsalLeagueConfig.topBarEvents.map((e) => e.activityType).toList(),
        [
          'PenGoal',
          'PenMissed',
          'PenSaved',
          'OwnGoal',
          'Yellow',
          'SecondYellow',
          'Red',
        ],
      );
    });

    test('league Blue is retired — no event writes it', () {
      expect(futsalLeagueConfig.eventForActivity('Blue'), isNull);
    });

    test('eventForActivity finds row and top-bar events by type', () {
      expect(futsalLeagueConfig.eventForActivity('Goal')!.shortLabel, 'G');
      expect(
          futsalLeagueConfig.eventForActivity('SecondYellow')!.shortLabel,
          '2Y');
      expect(futsalLeagueConfig.eventForActivity('nope'), isNull);
    });
  });

  group('futsalLeagueConfig — stat writes', () {
    test('legacy stats keep their keys', () {
      expect(
          futsalLeagueConfig.eventForActivity('Goal')!.statKeys, ['Goals']);
      expect(futsalLeagueConfig.eventForActivity('Assist')!.statKeys,
          ['Assists']);
      expect(
          futsalLeagueConfig.eventForActivity('Save')!.statKeys, ['Saves']);
      expect(futsalLeagueConfig.eventForActivity('Yellow')!.statKeys,
          ['Yellow']);
      expect(futsalLeagueConfig.eventForActivity('Red')!.statKeys, ['Red']);
    });

    test('new additive stats: DPL, Fouls, PenGoal, PenMissed, OwnGoal', () {
      expect(futsalLeagueConfig.eventForActivity('DPL')!.statKeys, ['DPL']);
      expect(
          futsalLeagueConfig.eventForActivity('Foul')!.statKeys, ['Fouls']);
      expect(futsalLeagueConfig.eventForActivity('PenGoal')!.statKeys,
          ['PenGoal', 'Goals']);
      expect(futsalLeagueConfig.eventForActivity('PenMissed')!.statKeys,
          ['PenMissed']);
      expect(futsalLeagueConfig.eventForActivity('OwnGoal')!.statKeys,
          ['OwnGoal']);
    });

    test('penalty saved credits BOTH PenSaved and the keeper Save', () {
      expect(futsalLeagueConfig.eventForActivity('PenSaved')!.statKeys,
          ['PenSaved', 'Saves']);
    });

    test('penalty goal credits BOTH PenGoal and the scorer Goals', () {
      expect(futsalLeagueConfig.eventForActivity('PenGoal')!.statKeys,
          ['PenGoal', 'Goals']);
    });

    test('second yellow credits SecondYellow AND the red consequence', () {
      expect(futsalLeagueConfig.eventForActivity('SecondYellow')!.statKeys,
          ['SecondYellow', 'Red']);
    });

    test('every statKey (and the clean-sheet key) is in the stat catalog',
        () {
      final keys = futsalLeagueConfig.statCatalog.map((s) => s.key).toSet();
      for (final e in [
        ...futsalLeagueConfig.rowEvents,
        ...futsalLeagueConfig.topBarEvents,
      ]) {
        for (final k in e.statKeys) {
          expect(keys, contains(k), reason: '${e.activityType} writes $k');
        }
      }
      expect(futsalLeagueConfig.cleanSheetStatKey, 'CleanSheets');
      expect(keys, contains('CleanSheets'));
    });
  });

  group('futsalLeagueConfig — score mapping', () {
    test('goal and penalty goal are worth 1 to the own team', () {
      final goal = futsalLeagueConfig.eventForActivity('Goal')!;
      final pen = futsalLeagueConfig.eventForActivity('PenGoal')!;
      expect(goal.scorePoints, 1);
      expect(goal.scoresOpponent, isFalse);
      expect(pen.scorePoints, 1);
      expect(pen.scoresOpponent, isFalse);
    });

    test('own goal is worth 1 to the OPPONENT', () {
      final og = futsalLeagueConfig.eventForActivity('OwnGoal')!;
      expect(og.scorePoints, 1);
      expect(og.scoresOpponent, isTrue);
    });

    test('everything else never scores', () {
      for (final e in [
        ...futsalLeagueConfig.rowEvents,
        ...futsalLeagueConfig.topBarEvents,
      ]) {
        if (e.activityType == 'Goal' ||
            e.activityType == 'PenGoal' ||
            e.activityType == 'OwnGoal') {
          continue;
        }
        expect(e.scorePoints, 0, reason: e.activityType);
      }
    });
  });

  group('futsalLeagueConfig — chained prompts', () {
    test('only Goal chains the assist prompt', () {
      for (final e in [
        ...futsalLeagueConfig.rowEvents,
        ...futsalLeagueConfig.topBarEvents,
      ]) {
        expect(
          e.chained,
          e.activityType == 'Goal'
              ? LeagueChainedPrompt.assistedBy
              : LeagueChainedPrompt.none,
          reason: e.activityType,
        );
      }
    });

    test('every event is a timeline event (no silent counters in futsal)',
        () {
      for (final e in [
        ...futsalLeagueConfig.rowEvents,
        ...futsalLeagueConfig.topBarEvents,
      ]) {
        expect(e.isTimelineEvent, isTrue, reason: e.activityType);
      }
    });
  });

  group('captureMinute', () {
    test('0 when the clock was never started (no time picker anywhere)',
        () {
      expect(captureMinute(null, 999999), 0);
    });

    test('1-based elapsed minute while running (tournament convention)',
        () {
      const clock = MatchClock(
          startedAtMs: 0, pausedAccumMs: 0, pausedAtMs: null);
      expect(captureMinute(clock, 30 * 1000), 1); // 0:30 → minute 1
      expect(captureMinute(clock, 5 * 60 * 1000), 6); // 5:00 → minute 6
    });

    test('frozen at the pause instant while paused', () {
      const clock = MatchClock(
          startedAtMs: 0, pausedAccumMs: 0, pausedAtMs: 60 * 1000);
      // Now is way later, but elapsed stays 1:00 → minute 2.
      expect(captureMinute(clock, 999 * 60 * 1000), 2);
    });

    test('completed pauses subtract from elapsed', () {
      const clock = MatchClock(
          startedAtMs: 0, pausedAccumMs: 2 * 60 * 1000, pausedAtMs: null);
      // 5:00 wall time - 2:00 paused = 3:00 → minute 4.
      expect(captureMinute(clock, 5 * 60 * 1000), 4);
    });
  });

  group('playerHasLeagueActivity', () {
    test('finds the type for the player in a List bucket', () {
      final activity = <String, dynamic>{
        "7'": [
          {'Yellow': 'Zaya'},
          {'Goal': 'Alex'},
        ],
      };
      expect(playerHasLeagueActivity(activity, 'Yellow', 'Zaya'), isTrue);
      expect(playerHasLeagueActivity(activity, 'Yellow', 'Alex'), isFalse);
      expect(playerHasLeagueActivity(activity, 'Red', 'Zaya'), isFalse);
    });

    test('handles index-keyed Map buckets (Firebase array collapsing)',
        () {
      final activity = <String, dynamic>{
        "12'": {
          '0': {'Yellow': 'Zaya'},
        },
      };
      expect(playerHasLeagueActivity(activity, 'Yellow', 'Zaya'), isTrue);
    });

    test('type matches case-insensitively, player trimmed', () {
      final activity = <String, dynamic>{
        "3'": [
          {'yellow': ' Zaya '},
        ],
      };
      expect(playerHasLeagueActivity(activity, 'Yellow', 'Zaya'), isTrue);
    });

    test('false for null/empty activity', () {
      expect(playerHasLeagueActivity(null, 'Yellow', 'Zaya'), isFalse);
      expect(playerHasLeagueActivity({}, 'Yellow', 'Zaya'), isFalse);
    });

    test('_t insertion stamps neither match nor block a match (P2.1)', () {
      final activity = <String, dynamic>{
        "7'": [
          {'_t': 1700000000000, 'Yellow': 'Zaya'}, // _t first: worst order
        ],
      };
      expect(playerHasLeagueActivity(activity, 'Yellow', 'Zaya'), isTrue);
      expect(playerHasLeagueActivity(activity, '_t', '1700000000000'),
          isFalse);
    });
  });

  group('recentLeagueEvents', () {
    test('flattens both teams newest-first, later-recorded first within a minute',
        () {
      final t1 = <String, dynamic>{
        "3'": [
          {'Goal': 'Zaya'},
          {'Assist': 'Alex'},
        ],
        "10'": [
          {'Save': 'Kim'},
        ],
      };
      final t2 = <String, dynamic>{
        "7'": [
          {'Foul': 'Sam'},
        ],
      };
      final events =
          recentLeagueEvents(team1Activity: t1, team2Activity: t2);
      expect(
        events
            .map((e) => '${e.minuteKey}|${e.activityType}|${e.player}|'
                't${e.teamTag}|i${e.index}')
            .toList(),
        [
          "10'|Save|Kim|t0|i0",
          "7'|Foul|Sam|t1|i0",
          "3'|Assist|Alex|t0|i1", // later-recorded in minute 3 comes first
          "3'|Goal|Zaya|t0|i0",
        ],
      );
    });

    test('index counts flattened entries so undo targets the right one',
        () {
      // A bucket that arrives as an index-keyed Map with a null hole:
      // flattening skips the hole and re-indexes densely.
      final t1 = <String, dynamic>{
        "5'": {
          '0': {'Goal': 'Zaya'},
          '1': null,
          '2': {'Yellow': 'Alex'},
        },
      };
      final events =
          recentLeagueEvents(team1Activity: t1, team2Activity: null);
      expect(events.length, 2);
      expect(events[0].activityType, 'Yellow');
      expect(events[0].index, 1); // dense position after flattening
      expect(events[1].activityType, 'Goal');
      expect(events[1].index, 0);
    });

    test('empty for missing activity', () {
      expect(
          recentLeagueEvents(team1Activity: null, team2Activity: null),
          isEmpty);
    });

    test('parses type/player from _t-stamped leafs, any key order (P2.1)',
        () {
      final t1 = <String, dynamic>{
        "4'": [
          {'_t': 1700000000000, 'Goal': 'Zaya'}, // _t first: worst order
        ],
      };
      final events =
          recentLeagueEvents(team1Activity: t1, team2Activity: null);
      expect(events.length, 1);
      expect(events[0].activityType, 'Goal');
      expect(events[0].player, 'Zaya');
      expect(events[0].index, 0);
    });

    test('same-minute cross-team events order by _t, newest first (P2.1)',
        () {
      // Recorded order: Zaya (t1) scored, THEN Sam (t2) fouled, THEN
      // Alex (t1) scored — all in minute 7. Index/team order alone
      // cannot see across teams; the _t stamps can.
      final t1 = <String, dynamic>{
        "7'": [
          {'Goal': 'Zaya', '_t': 1000},
          {'Goal': 'Alex', '_t': 3000},
        ],
      };
      final t2 = <String, dynamic>{
        "7'": [
          {'Foul': 'Sam', '_t': 2000},
        ],
      };
      final events =
          recentLeagueEvents(team1Activity: t1, team2Activity: t2);
      expect(
        events.map((e) => e.player).toList(),
        ['Alex', 'Sam', 'Zaya'],
      );
    });

    test('legacy leafs without _t keep index/team ordering', () {
      final t1 = <String, dynamic>{
        "7'": [
          {'Goal': 'Zaya'},
          {'Assist': 'Alex'},
        ],
      };
      final t2 = <String, dynamic>{
        "7'": [
          {'Foul': 'Sam'},
        ],
      };
      final events =
          recentLeagueEvents(team1Activity: t1, team2Activity: t2);
      // Same minute: later index first, team1 before team2 on exact ties.
      expect(
        events.map((e) => e.player).toList(),
        ['Alex', 'Zaya', 'Sam'],
      );
    });

    test('metadata-only leaf occupies an index but emits no event, so '
        'undo indices stay aligned with removeActivityAt', () {
      final t1 = <String, dynamic>{
        "5'": [
          {'_t': 1000}, // degenerate: stamp only, no event
          {'Goal': 'Zaya', '_t': 2000},
        ],
      };
      final events =
          recentLeagueEvents(team1Activity: t1, team2Activity: null);
      expect(events.length, 1);
      expect(events[0].activityType, 'Goal');
      expect(events[0].index, 1); // position in the flattened bucket
    });
  });

  group('reassignStatMoves (P2.1 Task B3 — full event editor)', () {
    test('single-stat event: decrement old player, then increment new', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Goal', 'Zaya', 'Alex',
            isFriendly: false),
        [
          (player: 'Zaya', statKey: 'Goals', delta: -1),
          (player: 'Alex', statKey: 'Goals', delta: 1),
        ],
      );
    });

    test('paired credits follow statKeys — PenGoal moves Goals too', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'PenGoal', 'Zaya', 'Alex',
            isFriendly: false),
        [
          (player: 'Zaya', statKey: 'PenGoal', delta: -1),
          (player: 'Zaya', statKey: 'Goals', delta: -1),
          (player: 'Alex', statKey: 'PenGoal', delta: 1),
          (player: 'Alex', statKey: 'Goals', delta: 1),
        ],
      );
    });

    test('SecondYellow moves the Red consequence too', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'SecondYellow', 'Zaya', 'Alex',
            isFriendly: false),
        [
          (player: 'Zaya', statKey: 'SecondYellow', delta: -1),
          (player: 'Zaya', statKey: 'Red', delta: -1),
          (player: 'Alex', statKey: 'SecondYellow', delta: 1),
          (player: 'Alex', statKey: 'Red', delta: 1),
        ],
      );
    });

    test('friendly games never move stats', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Goal', 'Zaya', 'Alex',
            isFriendly: true),
        isEmpty,
      );
    });

    test('reassigning TO Guest removes the old stats only', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Goal', 'Zaya', 'Guest',
            isFriendly: false),
        [(player: 'Zaya', statKey: 'Goals', delta: -1)],
      );
    });

    test('reassigning FROM Guest adds the new stats only', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Goal', 'Guest', 'Alex',
            isFriendly: false),
        [(player: 'Alex', statKey: 'Goals', delta: 1)],
      );
    });

    test('no-ops: same player, Guest to Guest, unknown/legacy type', () {
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Goal', 'Zaya', 'Zaya',
            isFriendly: false),
        isEmpty,
      );
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Goal', 'Guest', 'Guest',
            isFriendly: false),
        isEmpty,
      );
      expect(
        reassignStatMoves(futsalLeagueConfig, 'Blue', 'Zaya', 'Alex',
            isFriendly: false),
        isEmpty,
      );
    });
  });

  group('undoScoreEffect', () {
    test('goal/pen goal undo takes 1 from the own team', () {
      expect(undoScoreEffect(futsalLeagueConfig, 'Goal', 0),
          (teamTag: 0, delta: -1));
      expect(undoScoreEffect(futsalLeagueConfig, 'PenGoal', 1),
          (teamTag: 1, delta: -1));
    });

    test('own-goal undo takes 1 from the OPPONENT', () {
      expect(undoScoreEffect(futsalLeagueConfig, 'OwnGoal', 0),
          (teamTag: 1, delta: -1));
      expect(undoScoreEffect(futsalLeagueConfig, 'OwnGoal', 1),
          (teamTag: 0, delta: -1));
    });

    test('null for non-scoring and unknown/legacy types', () {
      expect(undoScoreEffect(futsalLeagueConfig, 'Yellow', 0), isNull);
      expect(undoScoreEffect(futsalLeagueConfig, 'Save', 1), isNull);
      expect(undoScoreEffect(futsalLeagueConfig, 'Blue', 0), isNull);
    });
  });

  group('basketballLeagueConfig (P4) — owner-locked layout', () {
    test('rows are +1/+2/+3/Miss/Reb/Ast/Stl/Blk/Foul in order', () {
      expect(
        basketballLeagueConfig.rowEvents.map((e) => e.activityType).toList(),
        [
          'OnePointer',
          'TwoPointer',
          'ThreePointer',
          'Miss',
          'Rebound',
          'Assist',
          'Steal',
          'Block',
          'Foul',
        ],
      );
    });

    test('top bar is Turnover only', () {
      expect(
        basketballLeagueConfig.topBarEvents
            .map((e) => e.activityType)
            .toList(),
        ['Turnover'],
      );
    });

    test('score mapping: +1/+2/+3 to the OWN team, everything else 0', () {
      expect(basketballLeagueConfig.eventForActivity('OnePointer')!
          .scorePoints, 1);
      expect(basketballLeagueConfig.eventForActivity('TwoPointer')!
          .scorePoints, 2);
      expect(basketballLeagueConfig.eventForActivity('ThreePointer')!
          .scorePoints, 3);
      for (final e in [
        ...basketballLeagueConfig.rowEvents,
        ...basketballLeagueConfig.topBarEvents,
      ]) {
        expect(e.scoresOpponent, isFalse, reason: e.activityType);
        if (!['OnePointer', 'TwoPointer', 'ThreePointer']
            .contains(e.activityType)) {
          expect(e.scorePoints, 0, reason: e.activityType);
        }
      }
    });

    test('legacy stat keys keep their spelling; new keys are additive', () {
      expect(basketballLeagueConfig.eventForActivity('OnePointer')!.statKeys,
          ['OnePoint']);
      expect(basketballLeagueConfig.eventForActivity('TwoPointer')!.statKeys,
          ['TwoPoints']);
      expect(basketballLeagueConfig.eventForActivity('ThreePointer')!
          .statKeys, ['ThreePoints']);
      expect(basketballLeagueConfig.eventForActivity('Miss')!.statKeys,
          ['Misses']);
      expect(basketballLeagueConfig.eventForActivity('Rebound')!.statKeys,
          ['Rebounds']);
      expect(basketballLeagueConfig.eventForActivity('Assist')!.statKeys,
          ['Assists']);
      expect(basketballLeagueConfig.eventForActivity('Steal')!.statKeys,
          ['Steals']);
      expect(basketballLeagueConfig.eventForActivity('Block')!.statKeys,
          ['Blocks']);
      expect(basketballLeagueConfig.eventForActivity('Foul')!.statKeys,
          ['Fouls']);
      expect(basketballLeagueConfig.eventForActivity('Turnover')!.statKeys,
          ['Turnovers']);
    });

    test('no keeper/clean-sheet concept, no chains', () {
      expect(basketballLeagueConfig.cleanSheetStatKey, '');
      for (final e in [
        ...basketballLeagueConfig.rowEvents,
        ...basketballLeagueConfig.topBarEvents,
      ]) {
        expect(e.chained, LeagueChainedPrompt.none, reason: e.activityType);
      }
    });

    test('every statKey is in the stat catalog', () {
      final catalog =
          basketballLeagueConfig.statCatalog.map((s) => s.key).toSet();
      for (final e in [
        ...basketballLeagueConfig.rowEvents,
        ...basketballLeagueConfig.topBarEvents,
      ]) {
        for (final k in e.statKeys) {
          expect(catalog.contains(k), isTrue, reason: k);
        }
      }
    });

    test('every event is a timeline event (undo strip depends on it)', () {
      for (final e in [
        ...basketballLeagueConfig.rowEvents,
        ...basketballLeagueConfig.topBarEvents,
      ]) {
        expect(e.isTimelineEvent, isTrue, reason: e.activityType);
      }
    });
  });

  group('chainedOnlyEvents seam (P4)', () {
    test('futsal has none and eventForActivity behaves as before', () {
      expect(futsalLeagueConfig.chainedOnlyEvents, isEmpty);
      expect(futsalLeagueConfig.eventForActivity('Goal')!.shortLabel, 'G');
      expect(futsalLeagueConfig.eventForActivity('nope'), isNull);
    });

    test('basketball has none', () {
      expect(basketballLeagueConfig.chainedOnlyEvents, isEmpty);
    });
  });

  group('flagFootballLeagueConfig (P4) — owner-locked layout', () {
    test('rows are Comp/Inc/Rec/Drop/FP in order', () {
      expect(
        flagFootballLeagueConfig.rowEvents
            .map((e) => e.activityType)
            .toList(),
        ['QBComp', 'QBInc', 'REC', 'RECMiss', 'FP'],
      );
    });

    test('top bar is the ten rare events in order', () {
      expect(
        flagFootballLeagueConfig.topBarEvents
            .map((e) => e.activityType)
            .toList(),
        [
          'Receiving TD',
          'Rushing TD',
          'INT TD',
          'Interception',
          'Sack',
          'PBU',
          'PAT1',
          'PAT1Miss',
          'TwoPT',
          'TwoPTMiss',
        ],
      );
    });

    test('score mapping: TDs +6, PAT +1, 2PT +2, everything else 0', () {
      int pts(String type) =>
          flagFootballLeagueConfig.eventForActivity(type)!.scorePoints;
      expect(pts('Receiving TD'), 6);
      expect(pts('Rushing TD'), 6);
      expect(pts('INT TD'), 6);
      expect(pts('PAT1'), 1);
      expect(pts('TwoPT'), 2);
      for (final type in [
        'QBComp', 'QBInc', 'REC', 'RECMiss', 'FP',
        'Interception', 'Sack', 'PBU', 'PAT1Miss', 'TwoPTMiss',
      ]) {
        expect(pts(type), 0, reason: type);
      }
      for (final e in [
        ...flagFootballLeagueConfig.rowEvents,
        ...flagFootballLeagueConfig.topBarEvents,
        ...flagFootballLeagueConfig.chainedOnlyEvents,
      ]) {
        expect(e.scoresOpponent, isFalse, reason: e.activityType);
      }
    });

    test('all 17 legacy stat keys survive in the catalog', () {
      final catalog =
          flagFootballLeagueConfig.statCatalog.map((s) => s.key).toSet();
      for (final k in [
        'QBComp', 'QBInc', 'PassTD', 'PassINT', 'REC', 'RECMiss', 'RECTD',
        'INT', 'FP', 'Sack', 'PBU', 'RushTD', 'INTTD', 'PAT1', 'PAT1Miss',
        'TwoPT', 'TwoPTMiss',
      ]) {
        expect(catalog.contains(k), isTrue, reason: k);
      }
      expect(catalog.length, 17);
    });

    test('legacy activity types keep their spelling and stat keys', () {
      expect(flagFootballLeagueConfig.eventForActivity('Receiving TD')!
          .statKeys, ['RECTD']);
      expect(flagFootballLeagueConfig.eventForActivity('Rushing TD')!
          .statKeys, ['RushTD']);
      expect(flagFootballLeagueConfig.eventForActivity('INT TD')!.statKeys,
          ['INTTD']);
      expect(flagFootballLeagueConfig.eventForActivity('Interception')!
          .statKeys, ['INT']);
      expect(flagFootballLeagueConfig.eventForActivity('Sack')!.statKeys,
          ['Sack']);
    });

    test('Rec TD chains thrownBy; nothing else chains', () {
      expect(flagFootballLeagueConfig.eventForActivity('Receiving TD')!
          .chained, LeagueChainedPrompt.thrownBy);
      for (final e in [
        ...flagFootballLeagueConfig.rowEvents,
        ...flagFootballLeagueConfig.topBarEvents,
      ]) {
        if (e.activityType != 'Receiving TD') {
          expect(e.chained, LeagueChainedPrompt.none,
              reason: e.activityType);
        }
      }
    });

    test('chained-only: Pass TD (recorded by the chain, 0 points) and '
        'Pass INT (legacy resolution only)', () {
      expect(
        flagFootballLeagueConfig.chainedOnlyEvents
            .map((e) => e.activityType)
            .toList(),
        ['Pass TD', 'Pass INT'],
      );
      final passTd =
          flagFootballLeagueConfig.eventForActivity('Pass TD')!;
      expect(passTd.statKeys, ['PassTD']);
      expect(passTd.scorePoints, 0); // the +6 rode on Rec TD
      final passInt =
          flagFootballLeagueConfig.eventForActivity('Pass INT')!;
      expect(passInt.statKeys, ['PassINT']);
      expect(passInt.scorePoints, 0);
    });

    test('no keeper/clean-sheet concept', () {
      expect(flagFootballLeagueConfig.cleanSheetStatKey, '');
    });

    test('every event is a timeline event', () {
      for (final e in [
        ...flagFootballLeagueConfig.rowEvents,
        ...flagFootballLeagueConfig.topBarEvents,
        ...flagFootballLeagueConfig.chainedOnlyEvents,
      ]) {
        expect(e.isTimelineEvent, isTrue, reason: e.activityType);
      }
    });
  });
}
