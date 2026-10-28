// P3d — the manager squad viewer (pick transparency, spec §9) proved with
// fake streams: another manager's current week comes from PublishedPicks,
// earlier weeks from History (published wins on overlap), browsable via the
// week chips; nothing published yet → "Picks are revealed when the gameweek
// locks."; the court is READ-ONLY (no slot taps) with the captain armband
// shown; the viewer's own squad renders live under the "Now" chip.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';

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
      ),
    ));
  }

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
