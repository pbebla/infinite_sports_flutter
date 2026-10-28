// P3c — the Players market tab, proved with fake streams (no Firebase):
// sort persists across filter changes AND a remount (session cache); adds
// flow into the SAME shared draft with the unsaved pill; a full position
// disables the row with its reason; unaffordable prices go error-red; the
// detail sheet renders live league stats; the risers strip hides while the
// node is absent; points column + Points sort exist only with totals.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

FantasyPlayer player(String name, FantasyPosition pos, int price,
        {bool eligible = true, String team = 'Team A'}) =>
    FantasyPlayer(
        name: name,
        position: pos,
        priceTenths: price,
        eligible: eligible,
        teamName: team);

void main() {
  late SquadDraftController draft;
  late StreamController<Map<String, FantasyPlayerTotals>?> totals;
  late StreamController<List<FantasyPriceChange>> priceChanges;
  late StreamController<Map<String, List<TournamentPlayer>>> rosters;

  final players = <FantasyPlayer>[
    player('Alan Keeper', FantasyPosition.gk, 50),
    player('Gus Glove', FantasyPosition.gk, 45, team: 'Team B'),
    player('Dana Wall', FantasyPosition.def, 60),
    player('Deb Rock', FantasyPosition.def, 55, team: 'Team B'),
    player('Ava Striker', FantasyPosition.att, 70),
    player('Axel Shot', FantasyPosition.att, 65, team: 'Team B'),
    player('Guest Guy', FantasyPosition.att, 65, eligible: false),
  ];

  setUp(() {
    FantasyPlayersTab.sessionSort = MarketSort.priceDesc;
    draft = SquadDraftController(config: FantasyConfig.futsalDefault());
    totals = StreamController<Map<String, FantasyPlayerTotals>?>.broadcast();
    priceChanges = StreamController<List<FantasyPriceChange>>.broadcast();
    rosters = StreamController<Map<String, List<TournamentPlayer>>>.broadcast();
  });

  tearDown(() {
    totals.close();
    priceChanges.close();
    rosters.close();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    List<FantasyPlayer>? marketPlayers,
    FantasyLockOverride lockOverride = FantasyLockOverride.open,
  }) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyPlayersTab(
          sport: 'Futsal',
          season: '15',
          players: marketPlayers ?? players,
          draft: draft,
          lockOverride: lockOverride,
          gameweeks: const [],
          totalsStates: totals.stream,
          priceChangeStates: priceChanges.stream,
          rosterStates: rosters.stream,
        ),
      ),
    ));
  }

  double rowY(WidgetTester tester, String name) =>
      tester.getTopLeft(find.byKey(ValueKey('market_row_$name'))).dy;

  testWidgets('market lists by price desc with guests last under the '
      'divider, disabled', (tester) async {
    await pumpTab(tester);

    // Price-desc default order.
    expect(rowY(tester, 'Ava Striker'), lessThan(rowY(tester, 'Axel Shot')));
    expect(rowY(tester, 'Axel Shot'), lessThan(rowY(tester, 'Dana Wall')));
    expect(rowY(tester, 'Gus Glove'), lessThan(rowY(tester, 'Guest Guy')));

    // Guest: below the divider, add disabled with the guest reason.
    expect(find.byKey(const ValueKey('not_eligible_divider')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('not_eligible_divider'))).dy,
        lessThan(rowY(tester, 'Guest Guy')));
    expect(find.byKey(const ValueKey('market_add_Guest Guy')), findsNothing);
    final guestTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Guest Guy')));
    expect(guestTooltip.message, 'Guest player — not eligible for fantasy.');
  });

  testWidgets('sort persists across filter and search changes AND a remount '
      '(session cache)', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();
    expect(rowY(tester, 'Alan Keeper'), lessThan(rowY(tester, 'Ava Striker')));

    // Position filter flips — the sort stays A–Z.
    await tester.tap(find.byKey(const ValueKey('market_pos_ATT')));
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionSort, MarketSort.nameAz);
    expect(rowY(tester, 'Ava Striker'), lessThan(rowY(tester, 'Axel Shot')));
    expect(find.byKey(const ValueKey('market_row_Alan Keeper')), findsNothing);

    // Search change — still A–Z.
    await tester.tap(find.byKey(const ValueKey('market_pos_All')));
    await tester.enterText(
        find.byKey(const ValueKey('market_search')), 'team b');
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionSort, MarketSort.nameAz);
    expect(rowY(tester, 'Axel Shot'), lessThan(rowY(tester, 'Deb Rock')));

    // Remount (a tab swipe unmounts far tabs): the session cache holds.
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester);
    expect(FantasyPlayersTab.sessionSort, MarketSort.nameAz);
    expect(rowY(tester, 'Alan Keeper'), lessThan(rowY(tester, 'Ava Striker')));
  });

  testWidgets('add flows into the SHARED draft: pill shows, control flips to '
      'remove, and the My Team builder sees the same pick', (tester) async {
    await pumpTab(tester);
    expect(find.byKey(const ValueKey('unsaved_pill')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('market_add_Alan Keeper')));
    await tester.pumpAndSettle();

    expect(draft.playerIds, contains('Alan Keeper'));
    expect(draft.dirty, isTrue);
    expect(find.byKey(const ValueKey('unsaved_pill')), findsOneWidget);
    expect(find.text('Unsaved changes — save on My Team'), findsOneWidget);
    expect(find.byKey(const ValueKey('market_add_Alan Keeper')), findsNothing);
    expect(
        find.byKey(const ValueKey('market_remove_Alan Keeper')), findsOneWidget);

    // The OTHER GK's add is now disabled: the one GK slot is taken.
    final gkTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Gus Glove')));
    expect(gkTooltip.message, 'GK slots are full — remove someone first.');

    // The My Team court renders the SAME draft (cross-tab proof).
    tester.view.physicalSize = const Size(420, 1900);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasySquadBuilder(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open,
          gameweeks: const [],
          players: players,
          squadStates: const Stream.empty(),
          onSaveSquad: (_) async {},
          draft: draft,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('squad_chip_Alan Keeper')),
        findsOneWidget);

    // Back on the market: remove drops it from the shared draft.
    await pumpTab(tester);
    await tester.tap(find.byKey(const ValueKey('market_remove_Alan Keeper')));
    await tester.pumpAndSettle();
    expect(draft.playerIds, isNot(contains('Alan Keeper')));
    expect(find.byKey(const ValueKey('market_add_Alan Keeper')), findsOneWidget);
  });

  testWidgets('unaffordable: price goes error-red and the add control is '
      'dead with the money reason', (tester) async {
    final rich = [
      player('Money Bags', FantasyPosition.def, 460),
      player('Cheapo', FantasyPosition.att, 40),
      ...players,
    ];
    await pumpTab(tester, marketPlayers: rich);
    await tester.tap(find.byKey(const ValueKey('market_add_Money Bags')));
    await tester.pumpAndSettle();

    // $46.0M of $50.0M spent: everyone above $4.0M flips unaffordable.
    final context =
        tester.element(find.byKey(const ValueKey('players_market')));
    final errorColor = Theme.of(context).colorScheme.error;
    final price = tester.widget<Text>(
        find.byKey(const ValueKey('market_price_Dana Wall')));
    expect(price.style?.color, errorColor);
    final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Dana Wall')));
    expect(tooltip.message, 'Over budget — free up some money first.');
    // An exactly-affordable row keeps its live add AND its normal price.
    expect(find.byKey(const ValueKey('market_add_Cheapo')), findsOneWidget);
    final cheapoPrice = tester
        .widget<Text>(find.byKey(const ValueKey('market_price_Cheapo')));
    expect(cheapoPrice.style?.color, isNot(errorColor));
  });

  testWidgets('locked: every control is dead with the locked reason',
      (tester) async {
    await pumpTab(tester, lockOverride: FantasyLockOverride.locked);
    expect(find.byKey(const ValueKey('market_add_Alan Keeper')), findsNothing);
    final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Alan Keeper')));
    expect(tooltip.message, 'Gameweek locked — no changes now.');
  });

  testWidgets('points column + Points sort exist only while totals exist',
      (tester) async {
    await pumpTab(tester);
    expect(find.text('Pts'), findsNothing);
    expect(find.textContaining(' pts'), findsNothing);

    totals.add({
      'Ava Striker': const FantasyPlayerTotals(points: 54, ownershipPct: 62),
      'Gus Glove': const FantasyPlayerTotals(points: 70),
    });
    await tester.pumpAndSettle();
    expect(find.text('Pts'), findsOneWidget);
    expect(find.text('54 pts · 62%'), findsOneWidget);
    expect(find.text('70 pts'), findsOneWidget);

    // Points sort re-orders: Gus (70) above Ava (54) above the zero-point rest.
    await tester.tap(find.text('Pts'));
    await tester.pumpAndSettle();
    expect(rowY(tester, 'Gus Glove'), lessThan(rowY(tester, 'Ava Striker')));
    expect(rowY(tester, 'Ava Striker'), lessThan(rowY(tester, 'Dana Wall')));

    // Node vanishes → the option and column hide, sort falls back to price.
    totals.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Pts'), findsNothing);
    expect(find.textContaining(' pts'), findsNothing);
    expect(rowY(tester, 'Ava Striker'), lessThan(rowY(tester, 'Gus Glove')));
  });

  testWidgets('risers & fallers strip: hidden while absent, chips once the '
      'node lands', (tester) async {
    await pumpTab(tester);
    expect(find.byKey(const ValueKey('price_changes_strip')), findsNothing);

    priceChanges.add(const [
      FantasyPriceChange(name: 'Ava Striker', deltaTenths: 5),
      FantasyPriceChange(name: 'Deb Rock', deltaTenths: -5),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('price_changes_strip')), findsOneWidget);
    expect(find.text('▲ Ava Striker +\$0.5M'), findsOneWidget);
    expect(find.text('▼ Deb Rock −\$0.5M'), findsOneWidget);

    // Emptied again (voided week) → gone entirely, no shell.
    priceChanges.add(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('price_changes_strip')), findsNothing);
  });

  testWidgets('detail sheet: live league stats, dashes first, add from the '
      'sheet edits the shared draft', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byKey(const ValueKey('market_row_Ava Striker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('market_player_sheet')), findsOneWidget);
    expect(find.text('Team A · ATT'), findsWidgets);
    expect(find.byKey(const ValueKey('badge_eligible')), findsOneWidget);
    // No roster row yet → every stat dashes.
    expect(find.text('—'), findsNWidgets(6));

    // The live season stats arrive (same feed as the league Player Stats tab).
    rosters.add({
      'Team A': [
        const TournamentPlayer(
          name: 'Ava Striker',
          teamId: 'Team A',
          teamName: 'Team A',
          goals: 12,
          assists: 7,
          saves: 0,
          dpl: 3,
          cleanSheets: 2,
          yellowCards: 1,
          redCards: 0,
        ),
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('—'), findsNothing);
    expect(find.text('12'), findsOneWidget); // goals
    expect(find.text('7'), findsOneWidget); // assists
    expect(find.text('1Y · 0R'), findsOneWidget); // cards

    // Buy from the sheet → the shared draft takes the pick, button flips.
    await tester.tap(find.byKey(const ValueKey('sheet_add')));
    await tester.pumpAndSettle();
    expect(draft.playerIds, contains('Ava Striker'));
    expect(find.byKey(const ValueKey('sheet_remove')), findsOneWidget);
    expect(find.text('Changes save from the My Team tab.'), findsOneWidget);
  });

  testWidgets('no underlined text anywhere on the market (house rule)',
      (tester) async {
    await pumpTab(tester);
    totals.add({
      'Ava Striker': const FantasyPlayerTotals(points: 54, ownershipPct: 62),
    });
    priceChanges.add(const [
      FantasyPriceChange(name: 'Ava Striker', deltaTenths: 5),
    ]);
    await tester.pumpAndSettle();
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
          reason: '"${t.data}" must not be underlined');
    }
  });
}
