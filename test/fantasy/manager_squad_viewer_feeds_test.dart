// Fantasy scale fixes, Task 7 (D9) — the manager squad sheet reads ONE
// manager's weeks, never everyone's: `PublishedPicks/<gw>/<uid>` and
// `History/<gw>/<uid>` per gameweek through the shared [perWeekStream], not
// the whole `PublishedPicks` / `History` node of every manager.
//
// Proved with fake per-path node streams (no Firebase) through the
// FantasyService `watchNode` seam: exactly one listener per week per feed on
// the manager's own small node (never the parent), the History feed parsing
// each week node ONCE into both the squad and the week's points
// ([HistoryWeek]), the session cache keyed `<root>|<uid>`, and a week that
// answers null first and a squad later (the lock — Review Focus 5) landing
// in a later emission. Then the widget over the same seam: a week that locks
// while the sheet is open appears live, and a schedule that grows from 3 to
// 4 gameweeks adds one listener per feed without a blank frame.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';

FantasySquad squad(String gk, {String? chip}) => FantasySquad(
      picks: [
        SquadPick(playerId: gk, position: FantasyPosition.gk, priceTenths: 50),
      ],
      captainId: gk,
      viceId: gk,
      chip: chip,
    );

const root = 'Fantasy/Futsal/15';

/// Fake RTDB: one controller per opened path, every open (and cancel)
/// recorded, so a test can say exactly which nodes were listened to.
class FakeNodes {
  final Map<String, StreamController<Object?>> byPath = {};
  final List<String> opened = [];
  final List<String> cancelled = [];

  Stream<Object?> watch(String path) {
    final c = byPath[path] = StreamController<Object?>(
      onListen: () => opened.add(path),
      onCancel: () => cancelled.add(path),
    );
    return c.stream;
  }

  void emit(String path, Object? value) => byPath[path]!.add(value);

  /// Sends null on the CURRENT controller of every opened path - answered
  /// or not (an answered week is overwritten with null, so call it BEFORE
  /// the weeks that should carry data). After a re-subscription `byPath`
  /// holds the new generation: the old controllers are no longer reached.
  void answerAllNull() {
    for (final c in byPath.values) {
      c.add(null);
    }
  }

  /// [answerAllNull] for every path except [silent] (left unanswered).
  void answerAllNullExcept(Set<String> silent) {
    byPath.forEach((path, c) {
      if (!silent.contains(path)) c.add(null);
    });
  }

  void fail(String path) => byPath[path]!.addError(StateError('denied'));

  Future<void> close() async {
    for (final c in byPath.values) {
      await c.close();
    }
  }
}

void main() {
  late FakeNodes nodes;

  setUp(() {
    FantasyService.clearSessionCaches();
    nodes = FakeNodes();
  });

  tearDown(() => nodes.close());

  group('FantasyService per-week manager feeds', () {
    test('published picks: one listener per week on that manager\'s own '
        'node — never the whole PublishedPicks', () async {
      final sub = FantasyService.watchPublishedPicksFor(
              'Futsal', '15', 'u', const [1, 2, 3],
              watchNode: nodes.watch)
          .listen((_) {});
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(nodes.opened..sort(), [
        '$root/PublishedPicks/1/u',
        '$root/PublishedPicks/2/u',
        '$root/PublishedPicks/3/u',
      ]);
      expect(nodes.opened, isNot(contains('$root/PublishedPicks')));
    });

    test('history: one listener per week on that manager\'s own node — '
        'never the whole History', () async {
      final sub = FantasyService.watchHistoryFor(
              'Futsal', '15', 'u', const [1, 2, 3],
              watchNode: nodes.watch)
          .listen((_) {});
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(nodes.opened..sort(), [
        '$root/History/1/u',
        '$root/History/2/u',
        '$root/History/3/u',
      ]);
      expect(nodes.opened, isNot(contains('$root/History')));
    });

    test('the History feed parses each week node ONCE into both the squad '
        'and the week\'s points', () async {
      final seen = <Map<int, HistoryWeek>>[];
      final sub = FantasyService.watchHistoryFor(
              'Futsal', '15', 'u', const [1, 2],
              watchNode: nodes.watch)
          .listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      nodes.emit('$root/History/1/u', {
        ...squad('Old Keeper', chip: 'benchBoost').toMap(),
        'TotalTenths': 340,
        'Breakdown': [
          {'playerId': 'Old Keeper', 'countedTenths': 120, 'multiplier': 2},
        ],
      });
      await pumpEventQueue();
      expect(seen, isEmpty, reason: 'week 2 has not answered: nothing pops');

      nodes.emit('$root/History/2/u', null); // not played yet
      await pumpEventQueue();

      expect(seen, hasLength(1));
      final weeks = seen.single;
      expect(weeks.keys, [1], reason: 'a week with no record is left out');
      final one = weeks[1]!;
      expect(one.squad!.picks.single.playerId, 'Old Keeper');
      expect(one.squad!.chip, 'benchBoost');
      expect(one.totalTenths, 340);
      expect(one.slots.single.countedTenths, 120);
      expect(one.slots.single.multiplier, 2);
      expect(nodes.opened.where((p) => p.contains('/History/1/')), hasLength(1),
          reason: 'one listener serves the squad AND the points');
    });

    test('a week that answers null first and a squad later (the LOCK) '
        'appears in a later emission', () async {
      final seen = <Map<int, FantasySquad>>[];
      final sub = FantasyService.watchPublishedPicksFor(
              'Futsal', '15', 'u', const [1, 2],
              watchNode: nodes.watch)
          .listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      nodes.emit('$root/PublishedPicks/1/u', squad('Gw1 Keeper').toMap());
      nodes.emit('$root/PublishedPicks/2/u', null); // not locked yet
      await pumpEventQueue();
      expect(seen.single.keys, [1]);

      // GW2 locks while the sheet is open: the functions write the snapshot.
      nodes.emit('$root/PublishedPicks/2/u', squad('Gw2 Keeper').toMap());
      await pumpEventQueue();
      expect(seen, hasLength(2));
      expect(seen.last.keys.toSet(), {1, 2});
      expect(seen.last[2]!.picks.single.playerId, 'Gw2 Keeper');
    });

    test('a malformed node is "no squad that week", never a crash',
        () async {
      final seen = <Map<int, FantasySquad>>[];
      final sub = FantasyService.watchPublishedPicksFor(
              'Futsal', '15', 'u', const [1, 2],
              watchNode: nodes.watch)
          .listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      nodes.emit('$root/PublishedPicks/1/u', {'picks': 'junk'});
      nodes.emit('$root/PublishedPicks/2/u', 7);
      await pumpEventQueue();
      expect(seen.single, isEmpty);
    });

    test('session caches are keyed <root>|<uid>: a revisit paints from the '
        'seed before any week answers, another manager\'s does not',
        () async {
      final first = FantasyService.watchPublishedPicksFor(
              'Futsal', '15', 'u', const [1],
              watchNode: nodes.watch)
          .listen((_) {});
      await pumpEventQueue();
      nodes.emit('$root/PublishedPicks/1/u', squad('Cached Keeper').toMap());
      await pumpEventQueue();
      await first.cancel();

      final seen = <Map<int, FantasySquad>>[];
      final revisit = FantasyService.watchPublishedPicksFor(
              'Futsal', '15', 'u', const [1],
              watchNode: FakeNodes().watch)
          .listen(seen.add);
      addTearDown(revisit.cancel);
      await pumpEventQueue();
      expect(seen.single[1]!.picks.single.playerId, 'Cached Keeper');

      final other = <Map<int, FantasySquad>>[];
      final stranger = FantasyService.watchPublishedPicksFor(
              'Futsal', '15', 'someone-else', const [1],
              watchNode: FakeNodes().watch)
          .listen(other.add);
      addTearDown(stranger.cancel);
      await pumpEventQueue();
      expect(other, isEmpty);

      // History has its own cache under the same key shape.
      final history = <Map<int, HistoryWeek>>[];
      final h = FantasyService.watchHistoryFor(
              'Futsal', '15', 'u', const [1],
              watchNode: FakeNodes().watch)
          .listen(history.add);
      addTearDown(h.cancel);
      await pumpEventQueue();
      expect(history, isEmpty, reason: 'the published cache is not History\'s');
    });

    test('cancel releases every week listener', () async {
      final sub = FantasyService.watchHistoryFor(
              'Futsal', '15', 'u', const [1, 2],
              watchNode: nodes.watch)
          .listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
      expect(nodes.cancelled..sort(),
          ['$root/History/1/u', '$root/History/2/u']);
    });
  });

  group('the squad sheet over per-week feeds', () {
    List<Gameweek> gameweeks(int count) => [
          for (var i = 1; i <= count; i++)
            Gameweek(
              number: i,
              date: '0${i}012026',
              lockUtc: DateTime.utc(2026, i, 1, 23),
              opensUtc: i == 1 ? null : DateTime.utc(2026, i - 1, 2, 8),
            ),
        ];

    late ValueNotifier<List<Gameweek>> weeks;

    setUp(() => weeks = ValueNotifier(gameweeks(3)));
    tearDown(() => weeks.dispose());

    Future<void> pump(
      WidgetTester tester, {
      Size size = const Size(420, 1200),
      Brightness brightness = Brightness.light,
      List<FantasyBadgeAward> badges = const [],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        home: ValueListenableBuilder<List<Gameweek>>(
          valueListenable: weeks,
          builder: (_, list, __) => ManagerSquadViewerPage(
            sport: 'Futsal',
            season: '15',
            uid: 'them',
            title: 'Golden Boots',
            isSelf: false,
            config: FantasyConfig.futsalDefault(),
            players: const <FantasyPlayer>[],
            gameweeks: list,
            watchNode: nodes.watch,
            // 2026-01-15: GW2 is the current week.
            nowUtc: () => DateTime.utc(2026, 1, 15, 12),
            badgeStates: Stream<List<FantasyBadgeAward>>.value(badges),
            badgeCatalogStates:
                Stream<FantasyBadgeCatalog>.value(badgeCatalogFromNode(null)),
            liveStates: Stream.value(FantasyLiveState.none),
            liveSquadStates: Stream<LiveSquad?>.value(null),
            voidedStates: Stream.value(const <int>{}),
          ),
        ),
      ));
      await tester.pump();
    }

    String p(String feed, int week) => '$root/$feed/$week/them';

    testWidgets('opens exactly one listener per week on EACH feed, on this '
        'manager\'s nodes only', (tester) async {
      await pump(tester);
      expect(nodes.opened..sort(), [
        for (final feed in const ['History', 'PublishedPicks'])
          for (final w in const [1, 2, 3]) p(feed, w),
      ]..sort());
      expect(nodes.opened.where((o) => o == '$root/PublishedPicks'), isEmpty);
      expect(nodes.opened.where((o) => o == '$root/History'), isEmpty);
    });

    testWidgets('one reveal: the skeleton holds until EVERY week of both '
        'feeds has answered', (tester) async {
      await pump(tester);
      for (final path in nodes.byPath.keys.toList()..sort()) {
        expect(find.byKey(const ValueKey('viewer_skeleton')), findsOneWidget);
        nodes.emit(path, null);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer_skeleton')), findsNothing);
      expect(find.byKey(const ValueKey('viewer_unrevealed')), findsOneWidget);
    });

    testWidgets('Review Focus 5 — opened before GW2 locks and left open: the '
        'locked week\'s squad appears without reopening', (tester) async {
      await pump(tester);
      nodes.answerAllNull();
      await tester.pumpAndSettle();
      expect(find.text('Picks are revealed when the gameweek locks.'),
          findsOneWidget);

      // The lock: the functions write PublishedPicks/2/them.
      nodes.emit(p('PublishedPicks', 2), squad('Locked Keeper').toMap());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('viewer_unrevealed')), findsNothing);
      expect(find.byKey(const ValueKey('squad_chip_Locked Keeper')),
          findsOneWidget);
      expect(find.text('Gameweek 2 squad'), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer_week_2')), findsOneWidget);
    });

    testWidgets('a settled week: one History listener supplies the squad AND '
        'its points', (tester) async {
      await pump(tester);
      nodes.answerAllNull();
      nodes.emit(p('History', 1), {
        ...squad('Old Keeper').toMap(),
        'TotalTenths': 340,
        'Breakdown': [
          {'playerId': 'Old Keeper', 'countedTenths': 120, 'multiplier': 2},
        ],
      });
      await tester.pumpAndSettle();

      expect(find.text('Gameweek 1 squad'), findsOneWidget);
      expect(find.byKey(const ValueKey('squad_chip_Old Keeper')),
          findsOneWidget);
      expect(find.text('12 pts'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('viewer_week_strip_text')))
              .data,
          'Final · 34 pts');
      expect(nodes.opened.where((o) => o == p('History', 1)), hasLength(1));
    });

    testWidgets('gameweeks growing from 3 to 4 weeks reopens each feed over '
        'the 4 weeks (4 + 4 opened, the 6 old listeners released) and keeps '
        'the shown squad (no blank frame)', (tester) async {
      await pump(tester);
      nodes.answerAllNull();
      nodes.emit(p('PublishedPicks', 2), squad('Shown Keeper').toMap());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('squad_chip_Shown Keeper')),
          findsOneWidget);
      final before = nodes.opened.length;
      expect(before, 6);

      // No session seed to lean on: what stays on screen is what the sheet
      // already holds while the new subscriptions answer.
      FantasyService.clearSessionCaches();
      weeks.value = gameweeks(4);
      await tester.pump();

      // The squad is still on screen the very next frame — never the
      // skeleton, never the "revealed at lock" message.
      expect(find.byKey(const ValueKey('squad_chip_Shown Keeper')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('viewer_skeleton')), findsNothing);
      expect(find.byKey(const ValueKey('viewer_unrevealed')), findsNothing);

      // The set changed, so each feed was reopened over the 4 weeks: the
      // new subscriptions open 4 + 4 nodes (the 6 old ones were released,
      // asserted below).
      expect(nodes.opened.length, before + 8);
      expect(nodes.opened.where((o) => o == p('PublishedPicks', 4)),
          hasLength(1));
      expect(nodes.opened.where((o) => o == p('History', 4)), hasLength(1));

      // The old subscriptions are released (each cancel is async).
      await tester.runAsync(() => pumpEventQueue());
      expect(nodes.cancelled.length, 6);

      // The new subscriptions answer; the squad stays, GW4 is a null week.
      nodes.answerAllNull(); // byPath now holds the second generation
      nodes.emit(p('PublishedPicks', 2), squad('Shown Keeper').toMap());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('squad_chip_Shown Keeper')),
          findsOneWidget);
    });

    group('a squad feed that errors or stays silent (an error is not a '
        'fact)', () {
      Finder byKey(String key) => find.byKey(ValueKey(key));

      void expectUnreadable(WidgetTester tester) {
        expect(byKey('viewer_skeleton'), findsNothing);
        expect(byKey('viewer_load_failed'), findsOneWidget);
        expect(find.text("Couldn't load this team."), findsOneWidget);
        // Never an empty squad, never the "revealed at lock" claim, no
        // court, no points.
        expect(byKey('viewer_unrevealed'), findsNothing);
        expect(find.text('Picks are revealed when the gameweek locks.'),
            findsNothing);
        expect(byKey('viewer_content'), findsNothing);
        expect(byKey('viewer_week_strip'), findsNothing);
        expect(find.textContaining(' pts'), findsNothing);
        expect(tester.takeException(), isNull);
      }

      testWidgets('(a) one History week errors before its first answer: the '
          'sheet reveals (the error answers), says so, and shows no points '
          'and no "no team" claim', (tester) async {
        await pump(tester);
        nodes.answerAllNullExcept({p('History', 2)});
        nodes.fail(p('History', 2));
        await tester.pumpAndSettle();
        expectUnreadable(tester);
      });

      testWidgets('(b) the same for one PublishedPicks week', (tester) async {
        await pump(tester);
        nodes.answerAllNullExcept({p('PublishedPicks', 3)});
        nodes.fail(p('PublishedPicks', 3));
        await tester.pumpAndSettle();
        expectUnreadable(tester);
      });

      testWidgets('a feed that stays SILENT is bounded at 2 s: the skeleton '
          'until then, then the failure line', (tester) async {
        await pump(tester);
        nodes.answerAllNullExcept({p('History', 1)});
        await tester.pump(const Duration(milliseconds: 1900));
        expect(byKey('viewer_skeleton'), findsOneWidget);
        expect(byKey('viewer_load_failed'), findsNothing);

        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expectUnreadable(tester);
      });

      testWidgets('(c) data arriving after the failure replaces it, live: '
          'History', (tester) async {
        await pump(tester);
        nodes.answerAllNullExcept({p('History', 2)});
        nodes.fail(p('History', 2));
        await tester.pumpAndSettle();
        expectUnreadable(tester);

        // The week answers after all: its record is the squad AND points.
        nodes.emit(p('History', 2), {
          ...squad('Late Keeper').toMap(),
          'TotalTenths': 340,
          'Breakdown': [
            {'playerId': 'Late Keeper', 'countedTenths': 120, 'multiplier': 2},
          ],
        });
        await tester.pumpAndSettle();

        expect(byKey('viewer_load_failed'), findsNothing);
        expect(byKey('viewer_skeleton'), findsNothing);
        expect(byKey('squad_chip_Late Keeper'), findsOneWidget);
        expect(find.text('Gameweek 2 squad'), findsOneWidget);
        expect(find.text('Final · 34 pts'), findsOneWidget);
      });

      testWidgets('(c) data arriving after the failure replaces it, live: '
          'PublishedPicks (after a silent feed)', (tester) async {
        await pump(tester);
        nodes.answerAllNullExcept({p('PublishedPicks', 2)});
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expectUnreadable(tester);

        nodes.emit(p('PublishedPicks', 2), squad('Locked Keeper').toMap());
        await tester.pumpAndSettle();

        expect(byKey('viewer_load_failed'), findsNothing);
        expect(byKey('squad_chip_Locked Keeper'), findsOneWidget);
        expect(find.text('Gameweek 2 squad'), findsOneWidget);
      });

      testWidgets("the manager's badge shelf stays above the failure line",
          (tester) async {
        await pump(tester, badges: const [
          FantasyBadgeAward(
              id: 'captainGenius_gw1', badgeId: 'captainGenius', gw: 1),
        ]);
        nodes.answerAllNullExcept({p('History', 2)});
        nodes.fail(p('History', 2));
        await tester.pumpAndSettle();

        expect(byKey('viewer_load_failed_scroll'), findsOneWidget);
        expect(byKey('badge_shelf'), findsOneWidget);
        expect(byKey('viewer_load_failed'), findsOneWidget);
        expect(tester.getTopLeft(byKey('badge_shelf')).dy,
            lessThan(tester.getTopLeft(byKey('viewer_load_failed')).dy));
      });

      for (final brightness in Brightness.values) {
        testWidgets('360 px, $brightness: the failure line fits, no '
            'overflow', (tester) async {
          await pump(tester,
              size: const Size(360, 700), brightness: brightness);
          nodes.answerAllNullExcept({p('History', 2)});
          nodes.fail(p('History', 2));
          await tester.pumpAndSettle();

          expectUnreadable(tester);
          final line = find.text("Couldn't load this team.");
          final rect = tester.getRect(line);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          // Scheme colour (readable in both themes), not a fixed fill.
          expect(
              tester.widget<Text>(line).style!.color,
              Theme.of(tester.element(byKey('viewer_load_failed')))
                  .colorScheme
                  .onSurfaceVariant);
        });
      }

      testWidgets('an error AFTER good data keeps what the feed last said '
          '(no failure line for a team that did load)', (tester) async {
        await pump(tester);
        nodes.answerAllNullExcept({p('PublishedPicks', 2)});
        nodes.emit(p('PublishedPicks', 2), squad('Shown Keeper').toMap());
        await tester.pumpAndSettle();
        expect(byKey('squad_chip_Shown Keeper'), findsOneWidget);

        nodes.fail(p('PublishedPicks', 2));
        await tester.pumpAndSettle();

        expect(byKey('viewer_load_failed'), findsNothing);
        expect(byKey('squad_chip_Shown Keeper'), findsOneWidget);
      });
    });

    testWidgets('a rebuild with the SAME gameweek numbers opens nothing new',
        (tester) async {
      await pump(tester);
      nodes.answerAllNull();
      await tester.pumpAndSettle();
      final before = nodes.opened.length;

      weeks.value = gameweeks(3); // a fresh list, the same set
      await tester.pump();
      expect(nodes.opened.length, before);
      expect(nodes.cancelled, isEmpty);
    });
  });
}
