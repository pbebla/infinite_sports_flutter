// P3d — the manager squad viewer (pick transparency, spec §9) proved with
// fake streams: another manager's current week comes from PublishedPicks,
// earlier weeks from History (published wins on overlap), browsable via the
// week chips; nothing published yet → "Picks are revealed when the gameweek
// locks."; the court is READ-ONLY (no slot edits) with the captain armband
// shown; the viewer's own squad renders live under the "Now" chip; (round 3)
// a chip tap opens that player's profile via the hub callback; and
// (badges, spec 2026-10-30 §5) the manager's badge shelf sits at the top —
// its feeds join the single reveal, nothing earned shows no shelf, and a
// failing badge feed never holds the skeleton; (Opus audit item 7) a long
// badge shelf above the court AND above the unrevealed message at 360 px in
// light and dark, scrolled end to end with no overflow; and (own-row
// decision) YOUR page — only yours — opens with the "Your rank this season"
// card (chart + "Share my rank", the opener's series; under two weeks the
// muted note) under the badge shelf, inside the same single reveal, fitting
// at 360 px in light and dark.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';
import '../helpers/chart_paint.dart';

FantasySquad squad(String gk, {String? chip}) => FantasySquad(
      picks: [
        SquadPick(playerId: gk, position: FantasyPosition.gk, priceTenths: 50),
      ],
      captainId: gk,
      viceId: gk,
      chip: chip,
    );

/// Three scheduled gameweeks locking Jan 1 / Feb 1 / Mar 1 2026; the test
/// clock sits between GW1's lock and GW2's, so GW2 is "current".
List<Gameweek> gameweeks() => [
      for (var i = 1; i <= 3; i++)
        Gameweek(
          number: i,
          date: '0${i}012026',
          lockUtc: DateTime.utc(2026, i, 1, 23),
          opensUtc: i == 1 ? null : DateTime.utc(2026, i - 1, 2, 8),
        ),
    ];

DateTime testNow() => DateTime.utc(2026, 1, 15, 12);

void main() {
  late StreamController<Map<int, FantasySquad>> published;
  late StreamController<Map<int, FantasySquad>> history;
  late StreamController<FantasySquad?> live;

  setUp(() {
    published = StreamController<Map<int, FantasySquad>>.broadcast();
    history = StreamController<Map<int, FantasySquad>>.broadcast();
    live = StreamController<FantasySquad?>.broadcast();
  });

  tearDown(() {
    published.close();
    history.close();
    live.close();
  });

  Future<void> pumpViewer(
    WidgetTester tester, {
    bool isSelf = false,
    FantasySquad? initialSquad,
    void Function(String playerName)? onOpenPlayer,
    Stream<List<FantasyBadgeAward>>? badgeStates,
    Stream<FantasyBadgeCatalog>? badgeCatalogStates,
    List<FantasyBadgeAward>? initialBadges,
    FantasyBadgeCatalog? initialBadgeCatalog,
    Size size = const Size(420, 1200),
    Brightness brightness = Brightness.light,
    String title = 'Golden Boots',
    List<RankPoint>? rankSeries,
    Stream<List<RankPoint>>? rankStates,
    Future<void> Function(BuildContext buttonContext)? onShareRank,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: ManagerSquadViewerPage(
        sport: 'Futsal',
        season: '15',
        uid: 'them',
        title: title,
        isSelf: isSelf,
        config: FantasyConfig.futsalDefault(),
        players: const [
          FantasyPlayer(
              name: 'Pub Keeper',
              position: FantasyPosition.gk,
              priceTenths: 50,
              eligible: true,
              teamName: 'A',
              photoUrl: null),
        ],
        gameweeks: gameweeks(),
        squadStates: isSelf ? live.stream : null,
        initialSquad: initialSquad,
        publishedStates: published.stream,
        historyStates: history.stream,
        nowUtc: testNow,
        onOpenPlayer: onOpenPlayer,
        // Default: nothing earned, answered at once (a cache-seeded feed).
        badgeStates:
            badgeStates ?? Stream<List<FantasyBadgeAward>>.value(const []),
        badgeCatalogStates: badgeCatalogStates ??
            Stream<FantasyBadgeCatalog>.value(badgeCatalogFromNode(null)),
        initialBadges: initialBadges,
        initialBadgeCatalog: initialBadgeCatalog,
        rankSeries: rankSeries,
        rankStates: rankStates,
        onShareRank: onShareRank,
      ),
    ));
  }

  const twoBadges = [
    FantasyBadgeAward(id: 'captainGenius_gw1', badgeId: 'captainGenius', gw: 1),
    FantasyBadgeAward(id: 'captainGenius_gw2', badgeId: 'captainGenius', gw: 2),
  ];

  const season = <RankPoint>[
    (gameweek: 1, rank: 14, live: false),
    (gameweek: 2, rank: 12, live: false),
    (gameweek: 3, rank: 10, live: false),
  ];

  Finder byKey(String key) => find.byKey(ValueKey(key));

  group('your rank this season (own team page, isSelf only)', () {
    /// Lands every feed so the page reveals (the live squad answers through
    /// [initialSquad]).
    Future<void> land(WidgetTester tester) async {
      published.add(const {});
      history.add({1: squad('Old Keeper')});
      await tester.pumpAndSettle();
    }

    testWidgets('your page opens with the card — title, "#14 → #10", the '
        'chart and "Share my rank" — ABOVE the week chips and the court',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: season,
          onShareRank: (_) async {});
      await land(tester);

      expect(byKey('viewer_content'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(find.text('Your rank this season'), findsOneWidget);
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(byKey('rank_history_chart'), findsOneWidget);
      expect(byKey('rank_history_note'), findsNothing);
      expect(find.bySemanticsLabel('Your rank by gameweek: GW1 #14, GW2 #12, '
          'GW3 #10'), findsOneWidget);
      expect(byKey('rank_history_share'), findsOneWidget);
      expect(find.text('Share my rank'), findsOneWidget);
      // You are already on your team: no "View team" action.
      expect(byKey('rank_history_view_team'), findsNothing);
      expect(find.text('View team'), findsNothing);

      final panel = tester.getRect(byKey('rank_history_panel'));
      expect(panel.bottom,
          lessThanOrEqualTo(tester.getTopLeft(byKey('viewer_week_now')).dy));
      expect(panel.bottom,
          lessThan(tester.getTopLeft(byKey('squad_chip_Live Keeper')).dy));
      // It is a card on a scheme surface (both themes), not the old panel
      // folded under a leaderboard row.
      final box = tester
          .widget<DecoratedBox>(byKey('rank_history_panel'))
          .decoration as BoxDecoration;
      final scheme = Theme.of(tester.element(byKey('rank_history_panel')))
          .colorScheme;
      expect(box.color, scheme.surfaceContainerHigh);
      semantics.dispose();
    });

    testWidgets('the card is LIVE: a gameweek finalizing while your page is '
        'open moves the chart (seeded by the opener, then the feed)',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final rank = StreamController<List<RankPoint>>.broadcast();
      addTearDown(rank.close);
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: season,
          rankStates: rank.stream,
          onShareRank: (_) async {});
      await land(tester);
      expect(find.text('#14 → #10'), findsOneWidget);

      // GW4 finalizes: RankHistory gains a week, you climbed to #7.
      rank.add(const [...season, (gameweek: 4, rank: 7, live: false)]);
      await tester.pumpAndSettle();
      expect(find.text('#14 → #7'), findsOneWidget);
      expect(find.text('#14 → #10'), findsNothing);
      expect(find.bySemanticsLabel('Your rank by gameweek: GW1 #14, GW2 #12, '
          'GW3 #10, GW4 #7'), findsOneWidget);
      // Still one card, still above the court, share still there.
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(byKey('rank_history_share'), findsOneWidget);
      expect(tester.getRect(byKey('rank_history_panel')).bottom,
          lessThan(tester.getTopLeft(byKey('squad_chip_Live Keeper')).dy));

      // A feed that errors keeps the series as last seen — no skeleton,
      // no exception.
      rank.addError(StateError('rules'));
      await tester.pumpAndSettle();
      expect(find.text('#14 → #7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('a LIVE gameweek: the end point is a hollow ring with the '
        'pill; when the week settles the same chart goes solid and the pill '
        'goes (live everywhere, Task 6)', (tester) async {
      final rank = StreamController<List<RankPoint>>.broadcast();
      addTearDown(rank.close);
      const liveLine = <RankPoint>[
        (gameweek: 1, rank: 14, live: false),
        (gameweek: 2, rank: 12, live: false),
        (gameweek: 3, rank: 10, live: true),
      ];
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: liveLine,
          rankStates: rank.stream);
      published.add(const {});
      history.add({1: squad('Old Keeper')});
      // The pill pulses forever: fixed pumps, never pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      Finder painter() => find.descendant(
          of: byKey('rank_history_chart'),
          matching: find.byWidgetPredicate((w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_RankLinePainter'));
      Finder panelPill() => find.descendant(
          of: byKey('rank_history_panel'),
          matching: find.byType(FantasyLivePill));
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(panelPill(), findsOneWidget);
      expect(tester.renderObject(painter()),
          paintsHollowRing());

      // finalize settles GW3: same rank, now official.
      rank.add(season);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(panelPill(), findsNothing);
      expect(tester.renderObject(painter()),
          paintsNoRing());
    });

    testWidgets('with badges: the card sits just BELOW the shelf and above '
        'the week chips', (tester) async {
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          badgeStates: Stream.value(twoBadges),
          rankSeries: season);
      await land(tester);

      final shelf = tester.getRect(byKey('badge_shelf'));
      final panel = tester.getRect(byKey('rank_history_panel'));
      expect(shelf.bottom, lessThanOrEqualTo(panel.top));
      expect(panel.bottom,
          lessThanOrEqualTo(tester.getTopLeft(byKey('viewer_week_now')).dy));
    });

    testWidgets('the card is part of the SINGLE reveal: never in the skeleton, '
        'present in the very first content frame', (tester) async {
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: season);
      expect(byKey('viewer_skeleton'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);

      published.add(const {});
      await tester.pump();
      // Picks are in, the history isn't: still the skeleton, still no card.
      expect(byKey('viewer_skeleton'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);

      history.add(const {});
      // ONE frame after the last feed: the reveal starts with the card
      // already inside it — nothing pops in afterwards.
      await tester.pump();
      expect(byKey('viewer_content'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(byKey('rank_history_chart'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(byKey('viewer_skeleton'), findsNothing);
      expect(byKey('rank_history_panel'), findsOneWidget);
    });

    testWidgets("someone else's page never shows it, even if a series is "
        'handed in', (tester) async {
      await pumpViewer(tester,
          rankSeries: season, onShareRank: (_) async {});
      published.add({2: squad('Pub Keeper')});
      history.add(const {});
      await tester.pumpAndSettle();
      expect(byKey('viewer_content'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);
      expect(byKey('rank_history_share'), findsNothing);
      expect(find.text('Your rank this season'), findsNothing);
    });

    testWidgets('your page without a series (none passed) shows no card',
        (tester) async {
      await pumpViewer(tester,
          isSelf: true, initialSquad: squad('Live Keeper'));
      await land(tester);
      expect(byKey('viewer_content'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);
    });

    for (final (label, series) in [
      ('no history at all', const <RankPoint>[]),
      ('one week of history', const <RankPoint>[(gameweek: 1, rank: 4, live: false)]),
    ]) {
      testWidgets('under two weeks ($label): the card is the short muted '
          'note, no chart, sharing still offered', (tester) async {
        await pumpViewer(tester,
            isSelf: true,
            initialSquad: squad('Live Keeper'),
            rankSeries: series,
            onShareRank: (_) async {});
        await land(tester);

        expect(byKey('rank_history_panel'), findsOneWidget);
        expect(find.text('Your rank this season'), findsOneWidget);
        expect(byKey('rank_history_chart'), findsNothing);
        expect(find.textContaining('→'), findsNothing);
        final note = tester.widget<Text>(byKey('rank_history_note'));
        expect(note.data, kRankHistoryNote);
        final context = tester.element(byKey('rank_history_note'));
        expect(note.style!.color,
            Theme.of(context).colorScheme.onSurfaceVariant);
        expect(byKey('rank_history_share'), findsOneWidget);
      });
    }

    testWidgets('the card stays put while you browse weeks (it is not '
        'tied to the selected squad)', (tester) async {
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: season);
      await land(tester);
      final before = tester.getRect(byKey('rank_history_panel'));

      await tester.tap(byKey('viewer_week_1'));
      await tester.pumpAndSettle();
      expect(find.text('Gameweek 1 squad'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(tester.getRect(byKey('rank_history_panel')), before);
    });

    testWidgets('"Share my rank" calls the opener\'s share once, with the '
        'button\'s own context (the iPad anchor)', (tester) async {
      final contexts = <BuildContext>[];
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: season,
          onShareRank: (ctx) async => contexts.add(ctx));
      await land(tester);

      await tester.tap(byKey('rank_history_share'));
      await tester.pumpAndSettle();
      expect(contexts, hasLength(1));
      final box = contexts.single.findRenderObject()! as RenderBox;
      expect(box.localToGlobal(Offset.zero) & box.size,
          tester.getRect(byKey('rank_history_share')));
    });

    testWidgets('no onShareRank = the card without a share button',
        (tester) async {
      await pumpViewer(tester,
          isSelf: true,
          initialSquad: squad('Live Keeper'),
          rankSeries: season);
      await land(tester);
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(byKey('rank_history_share'), findsNothing);
    });

    // 360 px, light AND dark: a long team name, a long badge shelf and the
    // card (chart, and the muted note), scrolled end to end.
    for (final brightness in Brightness.values) {
      for (final (label, series) in [
        (
          'chart',
          const <RankPoint>[
            (gameweek: 1, rank: 1234, live: false),
            (gameweek: 2, rank: 987, live: false),
            (gameweek: 5, rank: 1, live: false),
          ]
        ),
        ('note', const <RankPoint>[]),
      ]) {
        testWidgets('360 px: long title + badges + the card ($label) fit, no '
            'overflow when scrolled through — $brightness', (tester) async {
          const longName =
              'The Extraordinarily Magnificent Never-Ending Captaincy Award';
          final catalog = badgeCatalogFromNode({
            for (var i = 0; i < 3; i++)
              'long$i': {'Name': '$longName $i', 'Icon': 'bolt', 'Order': i},
          });
          await pumpViewer(
            tester,
            isSelf: true,
            initialSquad: squad('Live Keeper'),
            size: const Size(360, 760),
            brightness: brightness,
            title: 'The Extraordinarily Long-Named Assyrian Futsal Club',
            badgeStates: Stream.value([
              for (var i = 0; i < 3; i++)
                FantasyBadgeAward(
                    id: 'long${i}_gw1', badgeId: 'long$i', gw: 1),
            ]),
            badgeCatalogStates: Stream.value(catalog),
            rankSeries: series,
            onShareRank: (_) async {},
          );
          published.add(const {});
          history.add({1: squad('Old Keeper')});
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(byKey('rank_history_panel'), findsOneWidget);
          expect(byKey('rank_history_chart'),
              label == 'chart' ? findsOneWidget : findsNothing);

          final scrollable = find.byType(Scrollable).first;
          for (final key in [
            'rank_history_panel',
            if (label == 'chart') 'rank_history_chart',
            'rank_history_share',
          ]) {
            await tester.dragUntilVisible(
                byKey(key), scrollable, const Offset(0, -150));
            await tester.pumpAndSettle();
            final r = tester.getRect(byKey(key));
            expect(r.left, greaterThanOrEqualTo(0), reason: key);
            expect(r.right, lessThanOrEqualTo(360), reason: key);
          }
          await tester.drag(scrollable, const Offset(0, -2000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final t in tester.widgetList<Text>(find.byType(Text))) {
            expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
          }
        });
      }
    }
  });

  group('badges (spec 2026-10-30 §5)', () {
    testWidgets('the shelf sits at the TOP (above the week chips); its feeds '
        'join the single reveal', (tester) async {
      final badges = StreamController<List<FantasyBadgeAward>>();
      final catalog = StreamController<FantasyBadgeCatalog>();
      addTearDown(badges.close);
      addTearDown(catalog.close);
      await pumpViewer(tester,
          badgeStates: badges.stream, badgeCatalogStates: catalog.stream);
      published.add({2: squad('Pub Keeper')});
      history.add({1: squad('Old Keeper')});
      await tester.pump();
      // Picks landed, badges not yet: still the skeleton (no piecemeal pop).
      expect(find.byKey(const ValueKey('viewer_skeleton')), findsOneWidget);
      badges.add(twoBadges);
      await tester.pump();
      expect(find.byKey(const ValueKey('viewer_skeleton')), findsOneWidget);
      catalog.add(badgeCatalogFromNode(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer_skeleton')), findsNothing);

      expect(find.byKey(const ValueKey('badge_shelf')), findsOneWidget);
      expect(find.text('Captain Genius'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(
          tester.getRect(find.byKey(const ValueKey('badge_shelf'))).bottom,
          lessThanOrEqualTo(tester
              .getRect(find.byKey(const ValueKey('viewer_week_1')))
              .top));

      // Live: a new award re-renders the shelf.
      badges.add([
        ...twoBadges,
        const FantasyBadgeAward(
            id: 'champion_season', badgeId: 'champion', atMs: 9),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Champion'), findsOneWidget);

      // A chip opens its sheet.
      await tester.tap(find.byKey(const ValueKey('badge_chip_captainGenius')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('badge_sheet')), findsOneWidget);
      expect(find.text('GW1, GW2'), findsOneWidget);
    });

    testWidgets('nothing earned → no shelf at all', (tester) async {
      await pumpViewer(tester);
      published.add({2: squad('Pub Keeper')});
      history.add(const {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer_content')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_shelf')), findsNothing);
      expect(find.byKey(const ValueKey('viewer_badges_label')), findsNothing);
    });

    testWidgets('picks not revealed yet: the shelf still shows above the '
        'message', (tester) async {
      await pumpViewer(tester,
          badgeStates: Stream.value(twoBadges.take(1).toList()));
      published.add(const {});
      history.add(const {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer_unrevealed')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_shelf')), findsOneWidget);
      expect(
          tester.getRect(find.byKey(const ValueKey('badge_shelf'))).bottom,
          lessThan(tester
              .getRect(find.byKey(const ValueKey('viewer_unrevealed')))
              .top));
    });

    testWidgets('failing badge feeds never hold the skeleton (no shelf)',
        (tester) async {
      await pumpViewer(
        tester,
        badgeStates: Stream.error(StateError('denied')),
        badgeCatalogStates: Stream.error(StateError('offline')),
      );
      published.add({2: squad('Pub Keeper')});
      history.add(const {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer_content')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_shelf')), findsNothing);
    });

    // Opus audit item 7: 360 px, light AND dark — a long shelf of
    // long-named badges above the court, and above the unrevealed message.
    for (final brightness in Brightness.values) {
      for (final revealed in [true, false]) {
        final state = revealed ? 'picks revealed' : 'not revealed yet';
        testWidgets('360 px: a long badge shelf ($state) fits, no overflow '
            'when scrolled through — $brightness', (tester) async {
          const longName =
              'The Extraordinarily Magnificent Never-Ending Captaincy Award';
          final catalog = badgeCatalogFromNode({
            for (var i = 0; i < 6; i++)
              'long$i': {'Name': '$longName $i', 'Icon': 'bolt', 'Order': i},
          });
          await pumpViewer(
            tester,
            size: const Size(360, 760),
            brightness: brightness,
            title: 'The Extraordinarily Long-Named Assyrian Futsal Club',
            badgeStates: Stream.value([
              for (var i = 0; i < 6; i++)
                for (var gw = 1; gw <= (i % 3) + 1; gw++)
                  FantasyBadgeAward(
                      id: 'long${i}_gw$gw', badgeId: 'long$i', gw: gw),
            ]),
            badgeCatalogStates: Stream.value(catalog),
          );
          published.add(revealed ? {2: squad('Pub Keeper')} : const {});
          history.add(revealed ? {1: squad('Old Keeper')} : const {});
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('badge_shelf')), findsOneWidget);
          final last = revealed ? 'viewer_content' : 'viewer_unrevealed';
          expect(find.byKey(ValueKey(last)), findsOneWidget);

          final scrollable = find.byType(Scrollable).first;
          for (var i = 0; i < 6; i++) {
            final chip = find.byKey(ValueKey('badge_chip_long$i'));
            await tester.dragUntilVisible(
                chip, scrollable, const Offset(0, -150));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'long$i');
            final r = tester.getRect(chip);
            expect(r.left, greaterThanOrEqualTo(0), reason: 'long$i');
            expect(r.right, lessThanOrEqualTo(360), reason: 'long$i');
          }
          // And on to the end of the page.
          await tester.drag(scrollable, const Offset(0, -2000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final t in tester.widgetList<Text>(find.byType(Text))) {
            expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
          }
        });
      }
    }

    testWidgets('seeded badges (from the opener) need no feed to reveal',
        (tester) async {
      await pumpViewer(
        tester,
        badgeStates: const Stream.empty(),
        badgeCatalogStates: const Stream.empty(),
        initialBadges: twoBadges,
        initialBadgeCatalog: badgeCatalogFromNode(null),
      );
      published.add({2: squad('Pub Keeper')});
      history.add(const {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('badge_shelf')), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
    });
  });

  testWidgets('skeleton until both streams land; title is the TEAM name',
      (tester) async {
    await pumpViewer(tester);
    expect(find.byKey(const ValueKey('viewer_skeleton')), findsOneWidget);
    expect(find.text('Golden Boots'), findsOneWidget);

    published.add(const {});
    await tester.pump();
    expect(find.byKey(const ValueKey('viewer_skeleton')), findsOneWidget);

    history.add(const {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewer_skeleton')), findsNothing);
  });

  testWidgets('nothing published for another manager → the reveal-at-lock '
      'message', (tester) async {
    await pumpViewer(tester);
    published.add(const {});
    history.add(const {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewer_unrevealed')), findsOneWidget);
    expect(find.text('Picks are revealed when the gameweek locks.'),
        findsOneWidget);
  });

  testWidgets('current week from PublishedPicks (wins over History on the '
      'same week), earlier weeks from History; chips browse the full '
      'history; the court is read-only with armbands', (tester) async {
    await pumpViewer(tester);
    // GW2 is current: a published GW2 + history GW1 and a STALE history GW2.
    published.add({2: squad('Pub Keeper', chip: 'tripleCaptain')});
    history.add({1: squad('Old Keeper'), 2: squad('Stale Keeper')});
    await tester.pumpAndSettle();

    // Opens on the current week — the published copy, not the stale one.
    expect(find.byKey(const ValueKey('squad_chip_Pub Keeper')), findsOneWidget);
    expect(find.byKey(const ValueKey('squad_chip_Stale Keeper')), findsNothing);
    expect(find.text('Gameweek 2 squad'), findsOneWidget);
    // Transparency extras: the active chip banner + the captain armband.
    expect(find.byKey(const ValueKey('viewer_chip_Triple Captain')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('captain_badge_Pub Keeper')),
        findsOneWidget);

    // READ-ONLY: no slot is tappable.
    final court = tester.widget<FantasyCourtView>(find.byType(FantasyCourtView));
    expect(court.onSlotTap, isNull);
    // The captain's nameplate carries the REAL multiplier: this week played
    // Triple Captain (×3), never a hard-coded ×2.
    expect(court.captainMultiplier, 3);
    expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);

    // Browse back to GW1 (full history, spec: forever).
    await tester.tap(find.byKey(const ValueKey('viewer_week_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Old Keeper')), findsOneWidget);
    // No chip that week: the ordinary ×2.
    expect(
        tester
            .widget<FantasyCourtView>(find.byType(FantasyCourtView))
            .captainMultiplier,
        2);
    expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
    expect(find.text('Gameweek 1 squad'), findsOneWidget);
    // No "Now" chip for someone else's squad.
    expect(find.byKey(const ValueKey('viewer_week_now')), findsNothing);
  });

  testWidgets('round 3: tapping a player on the court opens his profile '
      '(slots stay read-only); empty slots stay inert', (tester) async {
    final opened = <String>[];
    await pumpViewer(tester, onOpenPlayer: opened.add);
    published.add({2: squad('Pub Keeper')});
    history.add(const {});
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('squad_chip_Pub Keeper')));
    await tester.pumpAndSettle();
    expect(opened, ['Pub Keeper']);

    // Still read-only: no edit slot callback, empty slots do nothing.
    final court = tester.widget<FantasyCourtView>(find.byType(FantasyCourtView));
    expect(court.onSlotTap, isNull);
    await tester.tap(find.byKey(const ValueKey('empty_slot_1')));
    await tester.pumpAndSettle();
    expect(opened, ['Pub Keeper']);

    // An earlier week's chips open too (browsing history).
    history.add({1: squad('Old Keeper')});
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer_week_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('squad_chip_Old Keeper')));
    await tester.pumpAndSettle();
    expect(opened, ['Pub Keeper', 'Old Keeper']);
  });

  testWidgets('own live squad ("Now") opens profiles too', (tester) async {
    final opened = <String>[];
    await pumpViewer(tester,
        isSelf: true,
        initialSquad: squad('Live Keeper'),
        onOpenPlayer: opened.add);
    published.add(const {});
    history.add(const {});
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('squad_chip_Live Keeper')));
    await tester.pumpAndSettle();
    expect(opened, ['Live Keeper']);
  });

  testWidgets('without an opener the court stays fully inert (unchanged)',
      (tester) async {
    await pumpViewer(tester);
    published.add({2: squad('Pub Keeper')});
    history.add(const {});
    await tester.pumpAndSettle();
    final chip = tester.widget<FantasyPlayerChip>(
        find.byKey(const ValueKey('squad_chip_Pub Keeper')));
    expect(chip.onTap, isNull);
  });

  testWidgets('current week not published yet → opens on the LATEST history '
      'week', (tester) async {
    await pumpViewer(tester);
    published.add(const {});
    history.add({1: squad('Old Keeper')});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Old Keeper')), findsOneWidget);
    expect(find.text('Gameweek 1 squad'), findsOneWidget);
  });

  testWidgets('own squad: live under the "Now" chip, history still '
      'browsable, live stream updates re-render', (tester) async {
    await pumpViewer(tester, isSelf: true, initialSquad: squad('Live Keeper'));
    published.add(const {});
    history.add({1: squad('Old Keeper')});
    await tester.pumpAndSettle();

    // Defaults to the live squad.
    expect(find.byKey(const ValueKey('viewer_week_now')), findsOneWidget);
    expect(find.byKey(const ValueKey('squad_chip_Live Keeper')),
        findsOneWidget);
    expect(find.text('Current squad'), findsOneWidget);

    // A live save re-renders (stream-driven).
    live.add(squad('Fresh Keeper'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Fresh Keeper')),
        findsOneWidget);

    // Week browsing still works for the manager's own history.
    await tester.tap(find.byKey(const ValueKey('viewer_week_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Old Keeper')), findsOneWidget);

    // And back to Now.
    await tester.tap(find.byKey(const ValueKey('viewer_week_now')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Fresh Keeper')),
        findsOneWidget);
  });

  testWidgets('own squad with nothing saved yet → the build-one nudge, not '
      'the lock message', (tester) async {
    await pumpViewer(tester, isSelf: true);
    published.add(const {});
    history.add(const {});
    live.add(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewer_no_squad')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer_unrevealed')), findsNothing);
  });
}
