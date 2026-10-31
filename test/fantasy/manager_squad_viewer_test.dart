// P3d — the manager squad viewer (pick transparency, spec §9) proved with
// fake streams: another manager's current week comes from PublishedPicks,
// earlier weeks from History (published wins on overlap), browsable via the
// week chips; nothing published yet → "Picks are revealed when the gameweek
// locks."; the court is READ-ONLY (no slot edits) with the captain armband
// shown; the viewer's own squad renders live under the "Now" chip; (round 3)
// a chip tap opens that player's profile via the hub callback; and
// (badges, spec 2026-10-30 §5) the manager's badge shelf sits at the top —
// its feeds join the single reveal, nothing earned shows no shelf, and a
// failing badge feed never holds the skeleton.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

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
  }) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ManagerSquadViewerPage(
        sport: 'Futsal',
        season: '15',
        uid: 'them',
        title: 'Golden Boots',
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
      ),
    ));
  }

  const twoBadges = [
    FantasyBadgeAward(id: 'captainGenius_gw1', badgeId: 'captainGenius', gw: 1),
    FantasyBadgeAward(id: 'captainGenius_gw2', badgeId: 'captainGenius', gw: 2),
  ];

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

    // Browse back to GW1 (full history, spec: forever).
    await tester.tap(find.byKey(const ValueKey('viewer_week_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Old Keeper')), findsOneWidget);
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
