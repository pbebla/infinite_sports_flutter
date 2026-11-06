// The ONE schedule wiring every Fantasy screen shares (final review A/B):
// Config → schedule gameweeks (lock-hour resubscribe, a real null Config
// clears + cancels, errors logged with the last good value kept, the
// session cache) → one per-gameweek listener (week-number / key
// resubscribe; only weeks up to the current gameweek, growing as the season
// advances — Opus audit items 3 + 11); and its sibling for the league games
// behind the "next game"
// lines (start hour → games, the session cache storing the hour the games
// were DERIVED with so a revisit never shows "0 PM").

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/gameweek_nodes_stream.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/data/next_game.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

List<Gameweek> _gws(int count) => [
      for (var i = 1; i <= count; i++)
        Gameweek(
          number: i,
          date: '1101202${i % 10}',
          lockUtc: DateTime.utc(2026, 11, i, 22),
          opensUtc: null,
        ),
    ];

FantasyConfigState _config(int lockHour,
        {ScheduleOverrides schedule = const ScheduleOverrides()}) =>
    FantasyConfigState(
      config: FantasyConfig.fromMap({'lockHour': lockHour}),
      lockOverride: FantasyLockOverride.open,
      schedule: schedule,
    );

/// A legacy game with NO stored time: its time is derived from [startHour]
/// (0 → "0:00PM", the trap no screen may show).
TournamentMatch _legacyGame({int startHour = 0}) => leagueMatchFromGameMap(
      dateKey: '11082026',
      index: 0,
      raw: {'team1': 'Ishtar', 'team2': 'Nimrod', 'status': 0},
      startHour: startHour,
    );

/// What the "Next:" line would read for [feed]'s games right now.
String _nextLine(FantasyLeagueGamesFeed feed) {
  final next = nextGameForTeam(
      'Ishtar', feed.games, DateTime.utc(2026, 11, 2, 18).toLocal());
  return nextGameText(next!, startHourKnown: feed.startHourKnown);
}

void main() {
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    FantasyScheduleFeed.clearSessionCache();
    FantasyLeagueGamesFeed.clearSessionCache();
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
  });

  tearDown(() => debugPrint = originalDebugPrint);

  group('FantasyScheduleFeed', () {
    late StreamController<FantasyConfigState?> config;
    late List<StreamController<List<Gameweek>>> schedules;
    late List<int> scheduleLockHours;
    late List<ScheduleOverrides> scheduleOverrides;
    late List<bool> scheduleCancelled;
    late List<List<int>> weekRequests;
    late List<StreamController<Map<int, int>>> weekFeeds;
    late int changes;

    setUp(() {
      config = StreamController<FantasyConfigState?>.broadcast();
      schedules = [];
      scheduleLockHours = [];
      scheduleOverrides = [];
      scheduleCancelled = [];
      weekRequests = [];
      weekFeeds = [];
      changes = 0;
    });

    tearDown(() => config.close());

    Stream<List<Gameweek>> derived(
        FantasyConfig cfg, ScheduleOverrides overrides) {
      final i = schedules.length;
      scheduleLockHours.add(cfg.lockHour);
      scheduleOverrides.add(overrides);
      scheduleCancelled.add(false);
      final c = StreamController<List<Gameweek>>.broadcast(
          onCancel: () => scheduleCancelled[i] = true);
      schedules.add(c);
      return c.stream;
    }

    Stream<Map<int, int>> perWeek(List<int> weeks) {
      weekRequests.add(weeks);
      final c = StreamController<Map<int, int>>.broadcast();
      weekFeeds.add(c);
      return c.stream;
    }

    FantasyScheduleFeed<Map<int, int>> feed({
      Stream<List<Gameweek>>? gameweekStates,
      bool withWeeks = true,
      // Default: after every test schedule's last lock day (season over —
      // every week is listened to).
      DateTime Function()? nowUtc,
    }) {
      final f = FantasyScheduleFeed<Map<int, int>>(
        sport: 'Futsal',
        season: '15',
        owner: 'TestOwner',
        onChanged: () => changes++,
        configStates: config.stream,
        gameweekStates: gameweekStates,
        gameweeksFor: derived,
        weekFeed: withWeeks ? perWeek : null,
        weekLabel: 'week stats feed',
        nowUtc: nowUtc ?? () => DateTime.utc(2027, 1, 1),
      );
      addTearDown(f.dispose);
      return f..start();
    }

    test('resubscribes the schedule only when the lock hour changes',
        () async {
      final f = feed();
      config.add(_config(15));
      await pumpEventQueue();
      expect(scheduleLockHours, [15]);
      expect(f.config!.config.lockHour, 15);
      expect(f.configLoaded, isTrue);

      config.add(_config(15)); // a re-emit that keeps the lock hour
      await pumpEventQueue();
      expect(scheduleLockHours, [15]);
      expect(scheduleCancelled, [false]);

      config.add(_config(16));
      await pumpEventQueue();
      expect(scheduleLockHours, [15, 16]);
      expect(scheduleCancelled, [true, false]);
    });

    // Task 9: the owner's schedule overrides (moved deadlines, skipped days,
    // the kickoff margin) move the weeks exactly as the lock hour does, so a
    // change of any of them re-derives; an equal re-emit does not.
    test('a Config change of Deadlines resubscribes; an equal re-emit does not',
        () async {
      final f = feed();
      final moved = DateTime.utc(2026, 11, 4, 2);
      config.add(_config(15));
      await pumpEventQueue();
      expect(scheduleOverrides, [const ScheduleOverrides()]);
      schedules[0].add(_gws(2));
      await pumpEventQueue();

      config.add(_config(15,
          schedule: ScheduleOverrides(deadlineOverrides: {'11042026': moved})));
      await pumpEventQueue();
      expect(scheduleLockHours, [15, 15]);
      expect(scheduleOverrides.last.deadlineOverrides, {'11042026': moved});
      expect(scheduleCancelled, [true, false]);
      // The schedule on screen stays until the new listener answers.
      expect(f.gameweeks, hasLength(2));

      // A NEW but equal ScheduleOverrides: value equality, no resubscribe.
      config.add(_config(15,
          schedule: ScheduleOverrides(
              deadlineOverrides: {'11042026': DateTime.utc(2026, 11, 4, 2)})));
      await pumpEventQueue();
      expect(scheduleOverrides, hasLength(2));
      expect(scheduleCancelled, [true, false]);

      // A skipped date and a new margin each re-derive too.
      config.add(_config(15,
          schedule: ScheduleOverrides(
              deadlineOverrides: {'11042026': moved},
              skippedDates: const {'11112026'})));
      await pumpEventQueue();
      expect(scheduleOverrides, hasLength(3));
      expect(scheduleOverrides.last.skippedDates, {'11112026'});
      config.add(_config(15,
          schedule: ScheduleOverrides(
              deadlineOverrides: {'11042026': moved},
              skippedDates: const {'11112026'},
              minutesBeforeKickoff: 30)));
      await pumpEventQueue();
      expect(scheduleOverrides, hasLength(4));
      expect(scheduleOverrides.last.minutesBeforeKickoff, 30);
      expect(scheduleCancelled, [true, true, true, false]);
    });

    test('a REAL null Config then the same overrides: a fresh listener',
        () async {
      feed();
      config.add(_config(15,
          schedule: const ScheduleOverrides(skippedDates: {'11112026'})));
      await pumpEventQueue();
      config.add(null);
      await pumpEventQueue();
      config.add(_config(15,
          schedule: const ScheduleOverrides(skippedDates: {'11112026'})));
      await pumpEventQueue();
      expect(scheduleOverrides, hasLength(2));
    });

    test(
        'the per-week listener follows the schedule: resubscribed only when '
        'the week numbers change, the last data kept meanwhile', () async {
      final f = feed();
      config.add(_config(15));
      await pumpEventQueue();
      expect(weekRequests, isEmpty); // no schedule yet
      expect(f.weekLoaded, isFalse);

      schedules[0].add(_gws(3));
      await pumpEventQueue();
      expect(weekRequests, [
        [1, 2, 3]
      ]);
      weekFeeds[0].add({1: 4});
      await pumpEventQueue();
      expect(f.weekData, {1: 4});
      expect(f.weekLoaded, isTrue);

      schedules[0].add(_gws(3)); // same weeks: no resubscribe
      await pumpEventQueue();
      expect(weekRequests, hasLength(1));

      schedules[0].add(_gws(4)); // a new match day appeared
      await pumpEventQueue();
      expect(weekRequests.last, [1, 2, 3, 4]);
      expect(f.weekData, {1: 4}); // kept until the new feed answers
      weekFeeds[1].add({1: 4, 4: 9});
      await pumpEventQueue();
      expect(f.weekData, {1: 4, 4: 9});
    });

    test(
        'a new week-feed KEY (another player) resets the data and '
        'resubscribes at once', () async {
      final f = feed(withWeeks: false);
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(2));
      await pumpEventQueue();

      f.setWeekFeed('Alan', perWeek);
      weekFeeds[0].add({1: 3});
      await pumpEventQueue();
      expect(f.weekData, {1: 3});

      f.setWeekFeed('Alan', perWeek); // same key: nothing happens
      expect(weekRequests, hasLength(1));

      f.setWeekFeed('Ben', perWeek);
      expect(f.weekData, isNull); // never another player's weeks
      expect(f.weekLoaded, isFalse);
      expect(weekRequests, hasLength(2));
      weekFeeds[0].add({1: 99}); // the old player's feed is cancelled
      await pumpEventQueue();
      expect(f.weekData, isNull);
    });

    test(
        'a REAL null Config clears the schedule, cancels its listener, '
        'drops the cached schedule and re-points the week feed at no weeks',
        () async {
      final f = feed();
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(3));
      await pumpEventQueue();
      expect(f.gameweeks, hasLength(3));

      config.add(null); // fantasy removed for the season
      await pumpEventQueue();
      expect(f.config, isNull);
      expect(f.configAbsent, isTrue);
      expect(f.gameweeks, isEmpty);
      expect(scheduleCancelled, [true]);
      expect(weekRequests.last, isEmpty);

      // Nothing stale seeds the next visit.
      final next = feed();
      expect(next.gameweeks, isNull);

      // Fantasy back with the SAME lock hour: a fresh schedule listener.
      config.add(_config(15));
      await pumpEventQueue();
      expect(scheduleLockHours, [15, 15, 15]);
    });

    test(
        'the derived schedule is cached for the session: a revisit has it '
        '(and starts its week feed) before any feed answers', () async {
      feed();
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(5));
      await pumpEventQueue();

      weekRequests.clear();
      final revisit = feed();
      expect(revisit.gameweeks!.map((g) => g.number), [1, 2, 3, 4, 5]);
      expect(weekRequests, [
        [1, 2, 3, 4, 5]
      ]);
    });

    test('a seamed schedule is never written to the session cache',
        () async {
      final seam = StreamController<List<Gameweek>>.broadcast();
      addTearDown(seam.close);
      feed(gameweekStates: seam.stream);
      seam.add(_gws(4));
      await pumpEventQueue();

      final next = feed();
      expect(next.gameweeks, isNull);
    });

    test(
        'errors are logged and keep the last good value: config, schedule '
        'and week feed', () async {
      final f = feed();
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(3));
      await pumpEventQueue();
      weekFeeds[0].add({2: 7});
      await pumpEventQueue();

      config.addError(StateError('config-denied'));
      schedules[0].addError(StateError('schedule-offline'));
      weekFeeds[0].addError(StateError('weeks-offline'));
      await pumpEventQueue();

      expect(f.config!.config.lockHour, 15); // last good config
      expect(f.configAbsent, isFalse); // an error is not "removed"
      expect(f.gameweeks, hasLength(3)); // last good schedule
      expect(f.weekData, {2: 7}); // last good weeks
      final all = logs.join('\n');
      expect(all, contains('TestOwner: config feed failed'));
      expect(all, contains('config-denied'));
      expect(all, contains('TestOwner: schedule feed failed'));
      expect(all, contains('schedule-offline'));
      expect(all, contains('TestOwner: week stats feed failed'));
      expect(all, contains('weeks-offline'));
    });

    test(
        'with nothing good yet, errors still open the gates ("no data", '
        'never an eternal skeleton)', () async {
      final f = feed();
      config.addError(StateError('offline'));
      await pumpEventQueue();
      expect(f.configLoaded, isTrue);
      expect(f.config, isNull);
      expect(f.gameweeks, isEmpty); // no schedule can be derived
      expect(weekRequests.single, isEmpty);
      weekFeeds[0].addError(StateError('x'));
      await pumpEventQueue();
      expect(f.weekLoaded, isTrue);
      expect(f.weekData, isNull);
    });

    // Final fix wave: a failed History read must not look like "nothing
    // used" (the chip row would offer a spent Wildcard again).
    test(
        'weekUnknown: an error with no good value is UNKNOWN — not an empty '
        'answer, not a kept last-good value, not "not asked yet"', () async {
      final f = feed();
      expect(f.weekUnknown, isFalse); // nothing asked, nothing answered
      config.addError(StateError('offline'));
      await pumpEventQueue();
      expect(f.weekLoaded, isFalse);
      expect(f.weekUnknown, isFalse); // asked, not answered yet

      weekFeeds[0].addError(StateError('permission-denied'));
      await pumpEventQueue();
      expect(f.weekLoaded, isTrue);
      expect(f.weekData, isNull);
      expect(f.weekUnknown, isTrue);

      // A later answer ends it (an empty map is a real "nothing used").
      weekFeeds[0].add(<int, int>{});
      await pumpEventQueue();
      expect(f.weekData, isEmpty);
      expect(f.weekUnknown, isFalse);
    });

    test('weekUnknown: a loaded-empty answer and a kept last-good value are '
        'known; a new key forgets the old answer', () async {
      final f = feed();
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(3));
      await pumpEventQueue();
      weekFeeds[0].add(<int, int>{});
      await pumpEventQueue();
      expect(f.weekLoaded, isTrue);
      expect(f.weekUnknown, isFalse); // loaded-empty is "nothing there"

      weekFeeds[0].add({2: 7});
      await pumpEventQueue();
      weekFeeds[0].addError(StateError('weeks-offline'));
      await pumpEventQueue();
      expect(f.weekData, {2: 7});
      expect(f.weekUnknown, isFalse); // last good kept

      f.setWeekFeed('another player', perWeek);
      expect(f.weekLoaded, isFalse);
      expect(f.weekUnknown, isFalse);
    });

    test(
        'a stream that cannot even be created (no Firebase) degrades and is '
        'logged — never a throw, never a notify during start', () async {
      final f = FantasyScheduleFeed<Map<int, int>>(
        sport: 'Futsal',
        season: '15',
        owner: 'TestOwner',
        onChanged: () => changes++,
        configStates: config.stream,
        gameweeksFor: (_, __) => throw StateError('no app'),
        weekFeed: (_) => throw StateError('no app either'),
      );
      addTearDown(f.dispose);
      f.start();
      expect(changes, 0);
      config.add(_config(15));
      await pumpEventQueue();
      expect(f.gameweeks, isEmpty);
      expect(f.weekLoaded, isTrue);
      expect(logs.join('\n'), contains('no app'));
    });

    test('dispose cancels every listener and stops notifying', () async {
      final f = feed();
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(2));
      await pumpEventQueue();
      final before = changes;
      f.dispose();
      expect(scheduleCancelled, [true]);
      config.add(_config(16));
      await pumpEventQueue();
      expect(changes, before);
    });

    // Opus audit items 3 + 11: History / PlayerWeekStats can't exist for a
    // week that hasn't locked — future weeks get NO listener.
    test(
        'only weeks up to the current gameweek get a listener (future weeks '
        'none); season over = every week', () async {
      // _gws: GW n locks Nov n, 22:00 UTC. Nov 2 23:00 = GW1's lock day is
      // over, GW2 is the current week.
      feed(nowUtc: () => DateTime.utc(2026, 11, 2, 23));
      config.add(_config(15));
      await pumpEventQueue();
      schedules[0].add(_gws(5));
      await pumpEventQueue();
      expect(weekRequests, [
        [1, 2]
      ]);

      // Before GW1 even locks: GW1 is current — just its own listener.
      weekRequests.clear();
      FantasyScheduleFeed.clearSessionCache();
      feed(nowUtc: () => DateTime.utc(2026, 10, 20));
      config.add(_config(15));
      await pumpEventQueue();
      schedules.last.add(_gws(5));
      await pumpEventQueue();
      expect(weekRequests.last, [1]);

      // The season is over: every week.
      FantasyScheduleFeed.clearSessionCache();
      feed(nowUtc: () => DateTime.utc(2027, 1, 1));
      config.add(_config(15));
      await pumpEventQueue();
      schedules.last.add(_gws(5));
      await pumpEventQueue();
      expect(weekRequests.last, [1, 2, 3, 4, 5]);
    });

    testWidgets(
        'the week list grows when the current week ends — even with no '
        'schedule re-emit (the boundary timer), the last data kept meanwhile',
        (tester) async {
      var now = DateTime.utc(2026, 11, 2, 23); // GW2 current
      final f = feed(nowUtc: () => now);
      config.add(_config(15));
      await tester.pump();
      schedules[0].add(_gws(5));
      await tester.pump();
      expect(weekRequests, [
        [1, 2]
      ]);
      weekFeeds[0].add({1: 4});
      await tester.pump();
      expect(f.weekData, {1: 4});

      // GW2's lock day ends Nov 3 22:00 (23 h on): the feed re-syncs itself.
      now = DateTime.utc(2026, 11, 3, 22, 1);
      await tester.pump(const Duration(hours: 23));
      expect(weekRequests.last, [1, 2, 3]);
      expect(f.weekData, {1: 4}); // kept until the new listener answers
      expect(f.weekLoaded, isTrue); // no skeleton flash

      f.dispose(); // cancels the next boundary timer too
      // The file's setUp captures debugPrint; a widget test must hand it
      // back inside its own body (the binding checks before tearDown runs).
      debugPrint = originalDebugPrint;
    });
  });

  // Task 9: the app's schedule is derived from THREE live nodes — the season's
  // Date, the server's frozen-week ledger (LockedWeeks) and the legacy Start
  // Time — and is shown only once all three have answered.
  group('gameweeksFromNodeStreams (Date + LockedWeeks + Start Time)', () {
    final cfg = FantasyConfig.futsalDefault();
    late StreamController<Object?> dates;
    late StreamController<Object?> locked;
    late StreamController<Object?> start;
    late List<List<Gameweek>> emitted;
    late List<Object> errors;
    StreamSubscription<List<Gameweek>>? sub;

    Map<String, Object?> days(List<String> keys) => {
          for (final k in keys)
            k: [
              {'team1': 'A', 'team2': 'B'}
            ],
        };
    List<String> dateList(List<Gameweek> g) => [for (final x in g) x.date];

    void listen({ScheduleOverrides overrides = const ScheduleOverrides()}) {
      sub = gameweeksFromNodeStreams(
        dates: dates.stream,
        lockedWeeks: locked.stream,
        startTime: start.stream,
        config: cfg,
        overrides: overrides,
      ).listen(emitted.add, onError: (Object e) => errors.add(e));
    }

    // Broadcast: a controller no test listened to must still close in tearDown
    // (a single-subscription one never completes close() without a listener).
    setUp(() {
      dates = StreamController<Object?>.broadcast();
      locked = StreamController<Object?>.broadcast();
      start = StreamController<Object?>.broadcast();
      emitted = [];
      errors = [];
    });

    tearDown(() async {
      await sub?.cancel();
      await dates.close();
      await locked.close();
      await start.close();
    });

    test('emits nothing until ALL THREE have answered (null = answered)',
        () async {
      listen();
      dates.add(days(['10042026']));
      await pumpEventQueue();
      expect(emitted, isEmpty); // Date alone is not a schedule
      locked.add(null); // no LockedWeeks node yet: that is an answer
      await pumpEventQueue();
      expect(emitted, isEmpty);
      start.add(null); // no Start Time: an answer too
      await pumpEventQueue();
      expect(emitted, hasLength(1));
      expect(dateList(emitted.single), ['10042026']);
    });

    test('the order the three answer in does not matter', () async {
      listen();
      start.add(1);
      locked.add(null);
      await pumpEventQueue();
      expect(emitted, isEmpty);
      dates.add(days(['10042026']));
      await pumpEventQueue();
      expect(emitted, hasLength(1));
    });

    test('re-derives on every later event of any of the three', () async {
      listen();
      dates.add(days(['10042026']));
      locked.add(null);
      start.add(null);
      await pumpEventQueue();
      expect(emitted, hasLength(1));

      // The server locks week 1: the ledger now freezes it, then the owner
      // moves the (now past) game day out of the schedule.
      locked.add([
        null,
        {'Date': '10042026', 'LockAtUtc': 1791154800000},
      ]);
      await pumpEventQueue();
      expect(emitted, hasLength(2));
      expect(emitted.last.single.frozen, isTrue);

      dates.add(days(['10112026']));
      await pumpEventQueue();
      expect(emitted, hasLength(3));
      expect(dateList(emitted.last), ['10042026', '10112026']);
      expect(emitted.last.first.frozen, isTrue);
      expect(emitted.last.first.lockUtc, DateTime.utc(2026, 10, 4, 23));

      // Start Time arriving late changes a deadline: game 0 at 13:00 PDT,
      // an hour of margin -> 19:00Z.
      start.add(1);
      await pumpEventQueue();
      expect(emitted.last.last.lockUtc, DateTime.utc(2026, 10, 11, 19));
    });

    test('games without a stored Time use Start Time for the kickoff deadline',
        () async {
      listen();
      dates.add(days(['10042026']));
      locked.add(null);
      start.add('1'); // a numeric string counts, as on the server
      await pumpEventQueue();
      expect(emitted.single.single.lockUtc, DateTime.utc(2026, 10, 4, 19));
    });

    test('an override moves the countdown, a skipped date renumbers', () async {
      listen(
        overrides: ScheduleOverrides(
          deadlineOverrides: {'10182026': DateTime.utc(2026, 10, 18, 17)},
          skippedDates: const {'10112026'},
        ),
      );
      dates.add(days(['10042026', '10112026', '10182026']));
      locked.add(null);
      start.add(null);
      await pumpEventQueue();
      final gws = emitted.single;
      expect(gws.map((g) => (g.number, g.date)),
          [(1, '10042026'), (2, '10182026')]);
      expect(gws[1].lockUtc, DateTime.utc(2026, 10, 18, 17));
    });

    test('an error on ANY node is forwarded and never becomes "no weeks"',
        () async {
      for (final failing in [0, 1, 2]) {
        emitted.clear();
        errors.clear();
        await sub?.cancel();
        final controllers = [
          StreamController<Object?>.broadcast(),
          StreamController<Object?>.broadcast(),
          StreamController<Object?>.broadcast(),
        ];
        sub = gameweeksFromNodeStreams(
          dates: controllers[0].stream,
          lockedWeeks: controllers[1].stream,
          startTime: controllers[2].stream,
          config: cfg,
          overrides: const ScheduleOverrides(),
        ).listen(emitted.add, onError: (Object e) => errors.add(e));
        controllers[failing].addError(StateError('denied-$failing'));
        await pumpEventQueue();
        expect(errors.map((e) => e.toString()), [contains('denied-$failing')],
            reason: 'node $failing');
        expect(emitted, isEmpty, reason: 'node $failing');
        await sub?.cancel();
        sub = null;
        for (final c in controllers) {
          await c.close();
        }
      }
    });

    test('a derive that throws (a junk date key) is an error, not a schedule',
        () async {
      listen();
      dates.add({
        'junk': [
          {'team1': 'A', 'team2': 'B'}
        ]
      });
      locked.add(null);
      start.add(null);
      await pumpEventQueue();
      expect(emitted, isEmpty);
      expect(errors, hasLength(1));
    });

    test('cancelling cancels all three listeners', () async {
      var cancelled = 0;
      final a = StreamController<Object?>.broadcast(onCancel: () => cancelled++);
      final b = StreamController<Object?>.broadcast(onCancel: () => cancelled++);
      final c = StreamController<Object?>.broadcast(onCancel: () => cancelled++);
      final s = gameweeksFromNodeStreams(
        dates: a.stream,
        lockedWeeks: b.stream,
        startTime: c.stream,
        config: cfg,
        overrides: const ScheduleOverrides(),
      ).listen((_) {});
      await s.cancel();
      expect(cancelled, 3);
    });

    test(
        'the feed waits for all three streams: no reveal on Date alone, then '
        'the week list appears at once', () async {
      FantasyScheduleFeed.clearSessionCache();
      final config = StreamController<FantasyConfigState?>.broadcast();
      addTearDown(config.close);
      var changes = 0;
      final f = FantasyScheduleFeed<Map<int, int>>(
        sport: 'Futsal',
        season: '15',
        owner: 'TestOwner',
        onChanged: () => changes++,
        configStates: config.stream,
        gameweeksFor: (cfg, overrides) => gameweeksFromNodeStreams(
          dates: dates.stream,
          lockedWeeks: locked.stream,
          startTime: start.stream,
          config: cfg,
          overrides: overrides,
        ),
        nowUtc: () => DateTime.utc(2027, 1, 1),
      );
      addTearDown(f.dispose);
      f.start();
      config.add(_config(15));
      await pumpEventQueue();
      expect(f.gameweeks, isNull);

      dates.add(days(['10042026', '10112026']));
      await pumpEventQueue();
      expect(f.gameweeks, isNull); // not on Date alone
      locked.add([
        null,
        {'Date': '10042026', 'LockAtUtc': 1791154800000},
      ]);
      await pumpEventQueue();
      expect(f.gameweeks, isNull); // not on Date + LockedWeeks either
      final before = changes;
      start.add(0);
      await pumpEventQueue();
      expect(f.gameweeks!.map((g) => g.number), [1, 2]);
      expect(f.gameweeks!.first.frozen, isTrue);
      expect(changes, before + 1); // ONE reveal, not piecemeal
    });
  });

  group('FantasyLeagueGamesFeed', () {
    late List<int> requestedHours;
    late List<StreamController<List<TournamentMatch>>> gameFeeds;

    setUp(() {
      requestedHours = [];
      gameFeeds = [];
    });

    Stream<List<TournamentMatch>> gamesFor(int hour) {
      requestedHours.add(hour);
      final c = StreamController<List<TournamentMatch>>.broadcast();
      gameFeeds.add(c);
      return c.stream;
    }

    FantasyLeagueGamesFeed feed(Future<int> Function() loadHour,
        {Stream<List<TournamentMatch>>? gamesStates}) {
      final f = FantasyLeagueGamesFeed(
        sport: 'Futsal',
        season: '15',
        owner: 'TestOwner',
        onChanged: () {},
        gamesStates: gamesStates,
        gamesFor: gamesStates == null ? gamesFor : null,
        loadStartHour: loadHour,
      );
      addTearDown(f.dispose);
      return f..start();
    }

    test(
        'a first visit waits for the start hour, then listens with it '
        '(a real hour is read once per session)', () async {
      var calls = 0;
      Future<int> fivePm() async {
        calls++;
        return 5;
      }

      final f = feed(fivePm);
      expect(f.ready, isFalse);
      await pumpEventQueue();
      expect(requestedHours, [5]);
      gameFeeds[0].add([_legacyGame(startHour: 5)]);
      await pumpEventQueue();
      expect(f.ready, isTrue);
      expect(f.startHourKnown, isTrue);
      expect(_nextLine(f), 'vs Nimrod · Sun 5 PM');

      final revisit = feed(fivePm);
      expect(revisit.ready, isTrue); // painted from the session at once
      expect(_nextLine(revisit), 'vs Nimrod · Sun 5 PM');
      expect(calls, 1); // the real hour came from the session
      expect(requestedHours, [5, 5]);
    });

    test(
        'B: a failed hour read, then a successful one — the revisit never '
        'shows "0 PM" while the re-derived games are on their way', () async {
      // Visit 1: the hour read fails → games derived with hour 0.
      final first = feed(() async => throw StateError('offline'));
      await pumpEventQueue();
      expect(requestedHours, [0]);
      gameFeeds[0].add([_legacyGame()]);
      await pumpEventQueue();
      expect(first.startHourKnown, isFalse);
      expect(_nextLine(first), 'vs Nimrod · Sun'); // never "0 PM"
      expect(logs.join('\n'), contains('TestOwner: start hour failed'));

      // Visit 2: the hour read now succeeds. The cached hour-0 games paint
      // at once — still flagged as derived WITHOUT a real hour.
      final hour = Completer<int>();
      final revisit = feed(() => hour.future);
      expect(revisit.ready, isTrue);
      expect(_nextLine(revisit), 'vs Nimrod · Sun');

      hour.complete(5);
      await pumpEventQueue();
      expect(requestedHours, [0, 5]);
      // The hour is known now, but the games on screen were derived with 0
      // until the stream re-delivers: still no "0 PM".
      expect(_nextLine(revisit), 'vs Nimrod · Sun');
      expect(_nextLine(revisit), isNot(contains('0 PM')));

      gameFeeds[1].add([_legacyGame(startHour: 5)]);
      await pumpEventQueue();
      expect(revisit.startHourKnown, isTrue);
      expect(_nextLine(revisit), 'vs Nimrod · Sun 5 PM');
    });

    test('an unknown hour (0) is never cached — the next visit asks again',
        () async {
      var calls = 0;
      Future<int> unknown() async {
        calls++;
        return 0;
      }

      feed(unknown);
      await pumpEventQueue();
      gameFeeds[0].add([_legacyGame()]);
      await pumpEventQueue();
      final revisit = feed(unknown);
      expect(revisit.ready, isTrue); // no skeleton while it re-asks
      await pumpEventQueue();
      expect(calls, 2);
    });

    test(
        'a games-feed error is logged and keeps the last good games; with '
        'none it still opens the gate', () async {
      final f = feed(() async => 5);
      await pumpEventQueue();
      gameFeeds[0].addError(StateError('games-offline'));
      await pumpEventQueue();
      expect(f.ready, isTrue);
      expect(f.games, isEmpty);
      expect(logs.join('\n'), contains('TestOwner: games feed failed'));

      gameFeeds[0].add([_legacyGame(startHour: 5)]);
      await pumpEventQueue();
      gameFeeds[0].addError(StateError('again'));
      await pumpEventQueue();
      expect(f.games, hasLength(1));
    });

    test(
        'fed games (a seam) carry their own times: the loaded hour applies '
        'to them as soon as it lands', () async {
      final seam = StreamController<List<TournamentMatch>>.broadcast();
      addTearDown(seam.close);
      final hour = Completer<int>();
      final f = feed(() => hour.future, gamesStates: seam.stream);
      seam.add([_legacyGame()]);
      await pumpEventQueue();
      expect(f.ready, isFalse); // still waiting on the hour
      hour.complete(0);
      await pumpEventQueue();
      expect(f.ready, isTrue);
      expect(f.startHourKnown, isFalse);
      expect(_nextLine(f), 'vs Nimrod · Sun');
    });
  });
}
