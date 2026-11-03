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

FantasyConfigState _config(int lockHour) => FantasyConfigState(
      config: FantasyConfig.fromMap({'lockHour': lockHour}),
      lockOverride: FantasyLockOverride.open,
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
    late List<bool> scheduleCancelled;
    late List<List<int>> weekRequests;
    late List<StreamController<Map<int, int>>> weekFeeds;
    late int changes;

    setUp(() {
      config = StreamController<FantasyConfigState?>.broadcast();
      schedules = [];
      scheduleLockHours = [];
      scheduleCancelled = [];
      weekRequests = [];
      weekFeeds = [];
      changes = 0;
    });

    tearDown(() => config.close());

    Stream<List<Gameweek>> derived(FantasyConfig cfg) {
      final i = schedules.length;
      scheduleLockHours.add(cfg.lockHour);
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
        gameweeksFor: (_) => throw StateError('no app'),
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
