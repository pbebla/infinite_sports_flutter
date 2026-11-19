// Season pointers are live (fresh-reads plan, Task 2): `Current League`,
// `<Sport> Season` and `AFC San Jose/Current Season` come from ONE live
// source, so a phone last opened in Season 15 follows the league to Season 16
// (on first open, as soon as the server answers) and every consumer moves in
// one coordinated update. No Firebase: the pointer streams are seamed.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_season_resolver.dart';
import 'package:infinite_sports_flutter/frontpage.dart';
import 'package:infinite_sports_flutter/leagues.dart';
import 'package:infinite_sports_flutter/misc/calendar_sources.dart';
import 'package:infinite_sports_flutter/misc/season_pointers.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// One controller per pointer path; a path left out never answers.
class _Pointers {
  final Map<String, StreamController<Object?>> c = {};
  final Set<String> silent = {};
  final Map<String, int> listens = {};

  Stream<Object?> open(String path) {
    listens[path] = (listens[path] ?? 0) + 1;
    final ctrl = StreamController<Object?>();
    c[path] = ctrl; // a re-subscribe gets a fresh stream, like onValue
    return ctrl.stream;
  }

  void set(String path, Object? v) => c[path]!.add(v);

  void fail(String path) => c[path]!.addError(StateError('permission-denied'));

  /// The saved copy of a phone last opened in Futsal Season 15.
  void savedCopy({String league = 'Futsal', Object? futsal = 15}) {
    set(kCurrentLeaguePointer, league);
    set('Futsal Season', futsal);
    set('Basketball Season', 3);
    set('Flag Football Season', 2);
    set(kAfcSeasonPointer, 'Spring 2026');
  }
}

Future<void> _tick([int ms = 5]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _Pointers p;
  late DebugPrintCallback original;

  setUp(() {
    p = _Pointers();
    SeasonPointers.debugReset();
    SeasonPointers.sourceOverride = p.open;
    SeasonPointers.firstEventTimeout = const Duration(milliseconds: 40);
    SeasonPointers.settle = const Duration(milliseconds: 10);
    original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {};
  });

  tearDown(() {
    SeasonPointers.debugReset();
    SeasonPointers.sourceOverride = null;
    SeasonPointers.firstEventTimeout = const Duration(seconds: 8);
    SeasonPointers.settle = const Duration(milliseconds: 250);
    debugPrint = original;
  });

  group('SeasonPointers', () {
    test('the getters answer from the first events (the saved copy)', () async {
      final sport = getCurrentSport();
      await _tick(0);
      p.savedCopy();
      expect(await sport, 'Futsal');
      expect(await getCurrentSeason('Futsal'), '15');
      expect(await getAFCCurrentSeason(), 'Spring 2026');
    });

    test('ONE listener per pointer, kept for the app lifetime', () async {
      final read = getCurrentSport();
      await _tick(0);
      p.savedCopy();
      await read;
      await getCurrentSeason('Futsal');
      await getCurrentSeason('Futsal');
      await getCurrentSport();
      expect(p.listens[kCurrentLeaguePointer], 1);
      expect(p.listens['Futsal Season'], 1);
      expect(p.c['Futsal Season']!.hasListener, isTrue);
    });

    test(
        'a phone last opened in Season 15 follows the server to 16, '
        'published once', () async {
      final read = getCurrentSeason('Futsal');
      await _tick(0);
      p.savedCopy();
      expect(await read, '15');
      final seen = <SeasonPointerValues>[];
      void listener() => seen.add(SeasonPointers.listenable.value);
      SeasonPointers.listenable.addListener(listener);
      final v0 = SeasonPointers.version;

      p.set('Futsal Season', 16); // the server's value arrives
      await _tick(30);
      expect(seen, hasLength(1));
      expect(seen.single.seasonFor('Futsal'), '16');
      expect(SeasonPointers.version, v0 + 1);
      expect(await getCurrentSeason('Futsal'), '16');
      SeasonPointers.listenable.removeListener(listener);
    });

    test('a new league and its season arrive as ONE update', () async {
      final read = getCurrentSport();
      await _tick(0);
      p.savedCopy();
      await read;
      var count = 0;
      void listener() => count++;
      SeasonPointers.listenable.addListener(listener);
      p.set(kCurrentLeaguePointer, 'Basketball');
      p.set('Basketball Season', 4);
      await _tick(30);
      expect(count, 1);
      expect(SeasonPointers.listenable.value.currentLeague, 'Basketball');
      expect(SeasonPointers.listenable.value.currentSeason, '4');
      SeasonPointers.listenable.removeListener(listener);
    });

    test('an unchanged value publishes nothing', () async {
      final read = getCurrentSport();
      await _tick(0);
      p.savedCopy();
      await read;
      var count = 0;
      void listener() => count++;
      SeasonPointers.listenable.addListener(listener);
      p.set('Futsal Season', 15);
      await _tick(30);
      expect(count, 0);
      SeasonPointers.listenable.removeListener(listener);
    });

    test(
        'the first wait is bounded; a silent pointer is an error, not '
        '"no season"', () async {
      // Every pointer but Futsal Season answers.
      final read = SeasonPointers.read('Futsal Season');
      await _tick(0);
      p.set(kCurrentLeaguePointer, 'Futsal');
      p.set('Basketball Season', 3);
      p.set('Flag Football Season', 2);
      p.set(kAfcSeasonPointer, 'Spring 2026');
      await expectLater(read, throwsA(isA<TimeoutException>()));
      // The others answer.
      expect(await SeasonPointers.read(kCurrentLeaguePointer), 'Futsal');
      // A later first event still lands.
      p.set('Futsal Season', 16);
      await _tick(0);
      expect(await SeasonPointers.read('Futsal Season'), '16');
    });

    test(
        'a stream error is an error (not "no season"), and the next read '
        're-subscribes', () async {
      final read = SeasonPointers.read('Futsal Season');
      await _tick(0);
      p.set(kCurrentLeaguePointer, 'Futsal');
      p.set('Basketball Season', 3);
      p.set('Flag Football Season', 2);
      p.set(kAfcSeasonPointer, 'Spring 2026');
      p.fail('Futsal Season');
      await expectLater(read, throwsStateError);
      expect(p.listens['Futsal Season'], 1);
      final again = SeasonPointers.read('Futsal Season');
      await _tick(0);
      expect(p.listens['Futsal Season'], 2);
      p.set('Futsal Season', 16);
      expect(await again, '16');
    });

    test('an absent pointer reads as null (the getters keep "null")', () async {
      final read = SeasonPointers.read(kCurrentLeaguePointer);
      await _tick(0);
      p.savedCopy(futsal: null);
      expect(await read, 'Futsal');
      expect(await SeasonPointers.read('Futsal Season'), isNull);
      expect(await getCurrentSeason('Futsal'), 'null');
    });
  });

  group('fantasy resolver follows the pointers', () {
    test('the memo is dropped when a pointer changes', () async {
      final read = SeasonPointers.read(kCurrentLeaguePointer);
      await _tick(0);
      p.savedCopy();
      await read;
      debugSetLastResolvedFantasySeason((sport: 'Futsal', season: '15'));
      expect(lastResolvedFantasySeason, (sport: 'Futsal', season: '15'));
      p.set('Futsal Season', 16);
      await _tick(30);
      expect(lastResolvedFantasySeason, isNull);
    });

    test('a failed pointer resolves as failed, never as "no season"', () async {
      final r = resolveFantasySeasonWith(
        readSport: () => readSeasonPointer(kCurrentLeaguePointer),
        readSeason: (s) => readSeasonPointer(seasonPointerPath(s)),
        hasConfig: (s, n) async => true,
      );
      await _tick(0);
      p.set(kCurrentLeaguePointer, 'Futsal');
      p.set('Basketball Season', 3);
      p.set('Flag Football Season', 2);
      p.set(kAfcSeasonPointer, 'x');
      p.fail('Futsal Season');
      final out = await r;
      expect(out.failed, isTrue);
      expect(out.isNone, isFalse);
    });

    test('reads the live pointer', () async {
      final r = resolveFantasySeasonWith(
        readSport: () => readSeasonPointer(kCurrentLeaguePointer),
        readSeason: (s) => readSeasonPointer(seasonPointerPath(s)),
        hasConfig: (s, n) async => true,
      );
      await _tick(0);
      p.savedCopy(futsal: 16);
      expect((await r).season, (sport: 'Futsal', season: '16'));
    });
  });

  group('calendar league days follow the season pointer', () {
    test(
        'a season change moves that sport to the new Date node in one '
        'update', () async {
      final dates = <String, StreamController<Object?>>{};
      Stream<Object?> dateNode(String path) =>
          dates.putIfAbsent(path, () => StreamController<Object?>()).stream;
      final out = <Map<DateTime, List<CalendarEntry>>>[];
      final sub = watchLeagueDays(dateNode: dateNode).listen(out.add);
      await _tick(0);
      p.savedCopy();
      await _tick(10);
      expect(dates.keys, containsAll(['Futsal/15/Date', 'Basketball/3/Date']));
      dates['Futsal/15/Date']!.add({'09052026': {}});
      await _tick(0);
      expect(out.last.values.expand((e) => e).single.season, '15');

      p.set('Futsal Season', 16);
      await _tick(30);
      expect(dates.keys, contains('Futsal/16/Date'));
      expect(dates['Futsal/15/Date']!.hasListener, isFalse,
          reason: 'the old season stream is cancelled');
      final before = out.length;
      dates['Futsal/16/Date']!.add({'11202026': {}, '11272026': {}});
      await _tick(0);
      expect(out.length, before + 1, reason: 'one update, no empty flash');
      final futsal = out.last.values
          .expand((e) => e)
          .where((e) => e.sport == 'Futsal')
          .toList();
      expect(futsal.map((e) => e.season).toSet(), {'16'});
      expect(futsal, hasLength(2));
      await sub.cancel();
    });
  });

  group('Matches tab header follows', () {
    test('a league header on the old season moves to the new one', () {
      expect(
          followHeader(['Futsal', '15'],
              oldSport: 'Futsal',
              oldSeason: '15',
              oldAfcSeason: 'S',
              newSport: 'Futsal',
              newSeason: '16',
              newAfcSeason: 'S'),
          ['Futsal', '16']);
    });

    test('an AFC header follows the AFC pointer only', () {
      expect(
          followHeader(['AFC San Jose', 'S1'],
              oldSport: 'Futsal',
              oldSeason: '15',
              oldAfcSeason: 'S1',
              newSport: 'Futsal',
              newSeason: '16',
              newAfcSeason: 'S1'),
          isNull);
      expect(
          followHeader(['AFC San Jose', 'S1'],
              oldSport: 'Futsal',
              oldSeason: '15',
              oldAfcSeason: 'S1',
              newSport: 'Futsal',
              newSeason: '15',
              newAfcSeason: 'S2'),
          ['AFC San Jose', 'S2']);
    });

    test('an unset header takes the current league', () {
      expect(
          followHeader(['', ''],
              oldSport: 'Futsal',
              oldSeason: '15',
              oldAfcSeason: 'S',
              newSport: 'Futsal',
              newSeason: '16',
              newAfcSeason: 'S'),
          ['Futsal', '16']);
    });
  });

  group('Leagues season list follows', () {
    testWidgets('a new season tile appears without a skeleton flash',
        (tester) async {
      // Widget tests require debugPrint untouched at the end of the body.
      debugPrint = original;
      final loads = <String>[];
      SeasonTilesPage.tilesOverride = (sport, context) async {
        final season = await getCurrentSeason(sport);
        loads.add(season);
        return [Text('$sport up to $season')];
      };
      addTearDown(() => SeasonTilesPage.tilesOverride = null);
      await tester.pumpWidget(const MaterialApp(
          home: SeasonTilesPage(sport: 'Futsal', title: 'Futsal')));
      p.savedCopy();
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pump();
      expect(find.text('Futsal up to 15'), findsOneWidget);

      p.set('Futsal Season', 16);
      await tester.pump(); // the value lands; the update waits to settle
      expect(find.text('Futsal up to 15'), findsOneWidget,
          reason: 'the old list stays until the new one is ready');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(find.text('Futsal up to 16'), findsOneWidget);
      expect(find.text('Futsal up to 15'), findsNothing);
      expect(loads, ['15', '16']);

      // Another sport's change does not reload this list.
      p.set('Basketball Season', 9);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(loads, ['15', '16']);
    });
  });
}
