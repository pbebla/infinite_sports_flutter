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
}
