// P3b — the court squad builder, proved with fake streams (no Firebase):
// building a full valid squad through the picker enables Save; an
// over-budget streamed squad disables Save with the money sentence; the
// captain sheet sets the gold ring; bench chips never offer an armband;
// removing the captain says so out loud; the locked state disables every
// edit affordance; the chip toggles stay mutually exclusive.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder.dart';

void main() {
  late StreamController<FantasySquad?> squads;
  late List<FantasySquad> savedSquads;

  final players = <FantasyPlayer>[
    const FantasyPlayer(
        name: 'Alan Keeper',
        position: FantasyPosition.gk,
        priceTenths: 50,
        eligible: true,
        teamName: 'Team A'),
    const FantasyPlayer(
        name: 'Gus Glove',
        position: FantasyPosition.gk,
        priceTenths: 45,
        eligible: true,
        teamName: 'Team B'),
    const FantasyPlayer(
        name: 'Dana Wall',
        position: FantasyPosition.def,
        priceTenths: 60,
        eligible: true,
        teamName: 'Team A'),
    const FantasyPlayer(
        name: 'Deb Rock',
        position: FantasyPosition.def,
        priceTenths: 55,
        eligible: true,
        teamName: 'Team B'),
    const FantasyPlayer(
        name: 'Dom Stone',
        position: FantasyPosition.def,
        priceTenths: 50,
        eligible: true,
        teamName: 'Team C'),
    const FantasyPlayer(
        name: 'Ava Striker',
        position: FantasyPosition.att,
        priceTenths: 70,
        eligible: true,
        teamName: 'Team A'),
    const FantasyPlayer(
        name: 'Axel Shot',
        position: FantasyPosition.att,
        priceTenths: 65,
        eligible: true,
        teamName: 'Team B'),
    const FantasyPlayer(
        name: 'Ari Goal',
        position: FantasyPosition.att,
        priceTenths: 60,
        eligible: true,
        teamName: 'Team C'),
    // A guest: real stats count, never selectable (spec §3).
    const FantasyPlayer(
        name: 'Guest Guy',
        position: FantasyPosition.att,
        priceTenths: 70,
        eligible: false,
        teamName: 'Team A'),
  ];

  setUp(() {
    squads = StreamController<FantasySquad?>.broadcast();
    savedSquads = [];
  });

  tearDown(() => squads.close());

  SquadPick pick(String id, FantasyPosition pos,
          {int price = 50, bool bench = false}) =>
      SquadPick(playerId: id, position: pos, priceTenths: price, bench: bench);

  /// 1 GK + 2 DEF + 2 ATT + bench DEF/ATT at [price] each.
  FantasySquad fullSquad(
          {int price = 50,
          String captainId = 'GK One',
          String viceId = 'Def One',
          String? chip}) =>
      FantasySquad(
        picks: [
          pick('GK One', FantasyPosition.gk, price: price),
          pick('Def One', FantasyPosition.def, price: price),
          pick('Def Two', FantasyPosition.def, price: price),
          pick('Att One', FantasyPosition.att, price: price),
          pick('Att Two', FantasyPosition.att, price: price),
          pick('Bench Def', FantasyPosition.def, price: price, bench: true),
          pick('Bench Att', FantasyPosition.att, price: price, bench: true),
        ],
        captainId: captainId,
        viceId: viceId,
        chip: chip,
      );

  Future<void> pumpBuilder(
    WidgetTester tester, {
    FantasyLockOverride lockOverride = FantasyLockOverride.open,
    FantasySquad? initialSquad,
    Future<void> Function(FantasySquad)? onSave,
  }) async {
    // Tall, phone-wide surface so the whole column (budget bar, court,
    // bench, chips, save) is on screen and tappable without scrolling.
    tester.view.physicalSize = const Size(420, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasySquadBuilder(
          config: FantasyConfig.futsalDefault(),
          lockOverride: lockOverride,
          gameweeks: const [],
          players: players,
          squadStates: squads.stream,
          initialSquad: initialSquad,
          onSaveSquad: onSave ??
              (squad) async {
                savedSquads.add(squad);
              },
        ),
      ),
    ));
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('squad_save')))
          .onPressed !=
      null;

  Future<void> pickIntoSlot(
      WidgetTester tester, int slot, String playerName) async {
    await tester.tap(find.byKey(ValueKey('empty_slot_$slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('picker_row_$playerName')));
    await tester.pumpAndSettle();
  }

  testWidgets('building a full valid squad through the picker enables Save',
      (tester) async {
    await pumpBuilder(tester);

    // Empty court: Save disabled, formation guidance inline.
    expect(saveEnabled(tester), isFalse);
    expect(find.text('Pick a goalkeeper.'), findsOneWidget);

    // GK slot → position-filtered picker, price-desc, guests invisible.
    await tester.tap(find.byKey(const ValueKey('empty_slot_0')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a goalkeeper'), findsOneWidget);
    expect(find.byKey(const ValueKey('picker_row_Alan Keeper')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('picker_row_Dana Wall')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('picker_row_Alan Keeper')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Alan Keeper')),
        findsOneWidget);

    await pickIntoSlot(tester, 1, 'Dana Wall');
    // An already-picked player never reappears in the next picker.
    await tester.tap(find.byKey(const ValueKey('empty_slot_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picker_row_Dana Wall')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('picker_row_Deb Rock')));
    await tester.pumpAndSettle();

    // ATT picker: the ineligible guest is invisible (spec §3).
    await tester.tap(find.byKey(const ValueKey('empty_slot_3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picker_row_Guest Guy')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('picker_row_Ava Striker')));
    await tester.pumpAndSettle();

    await pickIntoSlot(tester, 4, 'Axel Shot');
    await pickIntoSlot(tester, 5, 'Dom Stone');
    await pickIntoSlot(tester, 6, 'Ari Goal');

    // 50+60+55+70+65+50+60 = $41.0M spent of $50.0M.
    expect(find.text('\$41.0M spent'), findsOneWidget);
    expect(find.text('\$9.0M left'), findsOneWidget);

    // Formation is complete; the armband is the only thing left.
    expect(find.text('Choose a captain and vice-captain.'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    await tester.tap(find.byKey(const ValueKey('squad_chip_Dana Wall')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action_make_captain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('captain_ring_Dana Wall')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('squad_chip_Ava Striker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action_make_vice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vice_badge_Ava Striker')),
        findsOneWidget);

    // Valid + changed → Save enabled; the save lands the engine shape.
    expect(saveEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('squad_save')));
    await tester.pumpAndSettle();
    expect(savedSquads, hasLength(1));
    final saved = savedSquads.single;
    expect(saved.picks, hasLength(7));
    expect(saved.captainId, 'Dana Wall');
    expect(saved.viceId, 'Ava Striker');
    expect(saved.bench.map((p) => p.playerId).toSet(),
        {'Dom Stone', 'Ari Goal'});
    expect(find.text('Squad saved — good luck!'), findsOneWidget);
    // Clean again until the next edit.
    expect(saveEnabled(tester), isFalse);

    // The write echoes back on the stream: adopted as a no-op, nothing
    // doubles (self-echo safe).
    squads.add(saved);
    await tester.pump();
    expect(find.byKey(const ValueKey('squad_chip_Alan Keeper')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('captain_ring_Dana Wall')),
        findsOneWidget);
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('an over-budget streamed squad shows the overage and blocks '
      'Save', (tester) async {
    await pumpBuilder(tester);
    // 7 × $8.0M = $56.0M against $50.0M (prices moved after a save).
    squads.add(fullSquad(price: 80));
    await tester.pump();

    expect(find.text("You're \$6.0M over budget."), findsOneWidget);
    expect(find.text('\$6.0M over'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('armband flows: ring follows the captain sheet, bench chips '
      'offer no armband, removals speak up', (tester) async {
    await pumpBuilder(tester, initialSquad: fullSquad());
    expect(find.byKey(const ValueKey('captain_ring_GK One')), findsOneWidget);

    // Captain sheet moves the gold ring.
    await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action_make_captain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('captain_ring_Att One')), findsOneWidget);
    expect(find.byKey(const ValueKey('captain_ring_GK One')), findsNothing);
    expect(
        find.byKey(const ValueKey('captain_badge_Att One')), findsOneWidget);

    // A bench chip's sheet has no armband actions at all (spec §2: a bench
    // captain is impossible by construction).
    await tester.tap(find.byKey(const ValueKey('squad_chip_Bench Def')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('action_make_captain')), findsNothing);
    expect(find.byKey(const ValueKey('action_make_vice')), findsNothing);
    expect(find.byKey(const ValueKey('action_swap')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('action_remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Bench Def')), findsNothing);

    // Removing the captain reassigns nothing silently — it says so.
    await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action_remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('squad_chip_Att One')), findsNothing);
    expect(find.text('Your captain left the squad — choose a new captain.'),
        findsOneWidget);
    expect(find.text('Choose a captain.'), findsOneWidget);
  });

  testWidgets('locked state keeps the layout but disables every edit '
      'affordance', (tester) async {
    await pumpBuilder(tester,
        lockOverride: FantasyLockOverride.locked, initialSquad: fullSquad());

    // Header swaps to the compact live strip (same-layout decision).
    expect(find.byKey(const ValueKey('locked_live_strip')), findsOneWidget);
    expect(find.text('Gameweek locked — live points coming here'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('budget_bar')), findsNothing);
    expect(find.byKey(const ValueKey('squad_save')), findsNothing);

    // Chips and slots still render — tapping does nothing.
    await tester.tap(find.byKey(const ValueKey('squad_chip_GK One')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('action_make_captain')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fantasy_chip_tripleCaptain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chip_active_tripleCaptain')),
        findsNothing);
  });

  testWidgets('empty slots stay inert while locked', (tester) async {
    await pumpBuilder(tester, lockOverride: FantasyLockOverride.locked);
    await tester.tap(find.byKey(const ValueKey('empty_slot_0')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a goalkeeper'), findsNothing);
  });

  testWidgets('Triple Captain and Bench Boost toggle exclusively',
      (tester) async {
    await pumpBuilder(tester);

    await tester.tap(find.byKey(const ValueKey('fantasy_chip_tripleCaptain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chip_active_tripleCaptain')),
        findsOneWidget);

    // Selecting the other deselects the first (one chip per week).
    await tester.tap(find.byKey(const ValueKey('fantasy_chip_benchBoost')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chip_active_benchBoost')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chip_active_tripleCaptain')),
        findsNothing);

    // Tapping the active chip clears it.
    await tester.tap(find.byKey(const ValueKey('fantasy_chip_benchBoost')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chip_active_benchBoost')), findsNothing);

    // Wildcard / Free Hit are visual-only until transfers (P3c).
    expect(find.text('Coming with transfers'), findsNWidgets(2));
  });

  testWidgets('no underlined text anywhere on the builder (house rule)',
      (tester) async {
    await pumpBuilder(tester, initialSquad: fullSquad());
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
          reason: '"${t.data}" must not be underlined');
    }
  });
}
