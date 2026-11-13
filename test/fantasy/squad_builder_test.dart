// P3b — the court squad builder, proved with fake streams (no Firebase):
// building a full valid squad through the picker enables Save; an
// over-budget streamed squad disables Save with the money sentence; the
// captain sheet sets the gold ring; bench chips never offer an armband;
// removing the captain says so out loud; the locked state disables every
// edit affordance; the chip toggles stay mutually exclusive; and (Opus audit
// item 7) the alert banner + "Needs a new spot" strip at 360 px in light AND
// dark, scrolled end to end with no overflow.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';

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
    FantasySquadAlert? alert,
    List<Gameweek> gameweeks = const [],
    // Default: History loaded and empty (nothing spent). An explicit null is
    // "History unknown" — Wildcard / Free Hit can't be armed then.
    Map<int, ChipHistoryEntry>? chipHistory = const {},
    Set<int> voidedWeeks = const {},
    DateTime Function()? nowUtc,
    void Function(String playerName)? onOpenPlayer,
    // Default: a tall, phone-wide surface so the whole column (budget bar,
    // court, bench, chips, save) is on screen and tappable without
    // scrolling.
    Size size = const Size(420, 1900),
    Brightness brightness = Brightness.light,
    // A shared draft (the hub's): its money context is the test's to feed.
    SquadDraftController? draft,
    // The locked week's live / settled view (the hub's feed); null = nothing
    // known yet.
    LockedWeekModel? lockedWeek,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: FantasySquadBuilder(
          config: FantasyConfig.futsalDefault(),
          lockOverride: lockOverride,
          gameweeks: gameweeks,
          players: players,
          squadStates: squads.stream,
          initialSquad: initialSquad,
          onSaveSquad: onSave ??
              (squad) async {
                savedSquads.add(squad);
              },
          alert: alert,
          chipHistory: chipHistory,
          voidedWeeks: voidedWeeks,
          nowUtc: nowUtc,
          onOpenPlayer: onOpenPlayer,
          draft: draft,
          lockedWeek: lockedWeek,
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

    // Header swaps to the compact live strip (same-layout decision); with
    // nothing known about the week yet it is the honest default.
    expect(find.byKey(const ValueKey('locked_live_strip')), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Locked · waiting for kickoff'), findsNothing);
    expect(find.text('Gameweek locked — live points coming here'),
        findsNothing);
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

    // P3b Task 6: the heading carries the set windows from the config
    // (futsal default chipSet1EndGw = 6) and every chip shows its count
    // badge ("1 left" with no chip history — real usage is covered by the
    // 'chip availability counts' group below).
    expect(
        find.text('One chip may be active per gameweek · Set 1: GW1–6 · '
            'Set 2: GW7–final'),
        findsOneWidget);
    expect(find.text('1 left'), findsNWidgets(4));
    expect(find.text('0 left'), findsNothing);

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

    // Wildcard / Free Hit are playable now (plan 2026-11-03): no placeholder
    // caption — the 'transfers' group below covers their dialogs.
    expect(find.text('Coming with transfers'), findsNothing);
  });

  group('chip availability counts (real usage)', () {
    // Ten weekly gameweeks locking Jan 1..10 22:00Z; chipSet1EndGw = 6.
    final gws = [
      for (var n = 1; n <= 10; n++)
        Gameweek(
          number: n,
          date: '01${n.toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 1, n, 22),
          opensUtc: null,
        ),
    ];
    String badge(WidgetTester tester, String id) => tester
        .widget<Text>(find.descendant(
            of: find.byKey(ValueKey('chip_count_$id')),
            matching: find.byType(Text)))
        .data!;

    testWidgets('set 1: a chip spent in an earlier week reads Used and can '
        'not be armed; the others still 1 left', (tester) async {
      await pumpBuilder(
        tester,
        gameweeks: gws,
        nowUtc: () => DateTime.utc(2026, 1, 3, 23), // editing GW4
        chipHistory: {2: const ChipHistoryEntry(chip: 'tripleCaptain')},
      );
      expect(badge(tester, 'tripleCaptain'), 'Used');
      expect(badge(tester, 'benchBoost'), '1 left');
      expect(badge(tester, 'wildcard'), '1 left');
      expect(badge(tester, 'freeHit'), '1 left');

      await tester.tap(find.byKey(const ValueKey('fantasy_chip_tripleCaptain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chip_active_tripleCaptain')),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('fantasy_chip_benchBoost')));
      await tester.pumpAndSettle();
      expect(badge(tester, 'benchBoost'), 'Active');
      expect(find.byKey(const ValueKey('chip_active_benchBoost')),
          findsOneWidget);
    });

    testWidgets('set 2: set-1 chips are fresh again; a voided week refunds',
        (tester) async {
      await pumpBuilder(
        tester,
        gameweeks: gws,
        nowUtc: () => DateTime.utc(2026, 1, 8, 23), // editing GW9 (set 2)
        chipHistory: {
          2: const ChipHistoryEntry(chip: 'tripleCaptain'),
          7: const ChipHistoryEntry(chip: 'benchBoost'),
          8: const ChipHistoryEntry(chip: 'wildcard', voided: true),
        },
      );
      expect(badge(tester, 'tripleCaptain'), '1 left');
      expect(badge(tester, 'benchBoost'), 'Used');
      expect(badge(tester, 'wildcard'), '1 left');
    });

    testWidgets(
        'a week voided in the Voided node refunds its chip before the '
        're-finalize mirrors it into History (Opus audit item 4)',
        (tester) async {
      await pumpBuilder(
        tester,
        gameweeks: gws,
        nowUtc: () => DateTime.utc(2026, 1, 3, 23), // editing GW4
        // GW2's History still says nothing about the void...
        chipHistory: {2: const ChipHistoryEntry(chip: 'tripleCaptain')},
        // ...but the owner voided GW2 — what the server reads.
        voidedWeeks: const {2},
      );
      expect(badge(tester, 'tripleCaptain'), '1 left');
      await tester.tap(find.byKey(const ValueKey('fantasy_chip_tripleCaptain')));
      await tester.pumpAndSettle();
      expect(badge(tester, 'tripleCaptain'), 'Active'); // armable again
    });

    testWidgets('the chip armed on the live squad reads Active',
        (tester) async {
      await pumpBuilder(
        tester,
        gameweeks: gws,
        nowUtc: () => DateTime.utc(2026, 1, 3, 23),
        initialSquad: fullSquad(chip: 'benchBoost'),
        chipHistory: const {},
      );
      expect(badge(tester, 'benchBoost'), 'Active');
      expect(badge(tester, 'tripleCaptain'), '1 left');
    });
  });

  testWidgets('no underlined text anywhere on the builder (house rule)',
      (tester) async {
    await pumpBuilder(tester, initialSquad: fullSquad());
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
          reason: '"${t.data}" must not be underlined');
    }
  });

  // Round 3 (spec §4): every player tap opens the fantasy player profile.
  group('player profile (round 3)', () {
    testWidgets('a filled chip action sheet leads with "Player profile"; '
        'it opens the tapped player and changes nothing in the draft',
        (tester) async {
      final opened = <String>[];
      await pumpBuilder(tester,
          initialSquad: fullSquad(), onOpenPlayer: opened.add);

      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      final profile = find.byKey(const ValueKey('action_profile'));
      expect(profile, findsOneWidget);
      expect(find.text('Player profile'), findsOneWidget);
      // FIRST item: above the armband actions, swap and remove.
      final profileY = tester.getTopLeft(profile).dy;
      for (final key in const [
        'action_make_captain',
        'action_make_vice',
        'action_swap',
        'action_remove',
      ]) {
        expect(profileY, lessThan(tester.getTopLeft(find.byKey(ValueKey(key))).dy),
            reason: 'Player profile must sit above $key');
      }

      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(opened, ['Att One']);
      // The sheet closed and nothing was edited.
      expect(find.byKey(const ValueKey('action_profile')), findsNothing);
      expect(find.byKey(const ValueKey('squad_chip_Att One')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('bench chips offer Player profile too', (tester) async {
      final opened = <String>[];
      await pumpBuilder(tester,
          initialSquad: fullSquad(), onOpenPlayer: opened.add);
      await tester.tap(find.byKey(const ValueKey('squad_chip_Bench Def')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('action_make_captain')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('action_profile')));
      await tester.pumpAndSettle();
      expect(opened, ['Bench Def']);
    });

    testWidgets('without an opener (standalone builder) the sheet is '
        'unchanged — no Player profile item', (tester) async {
      await pumpBuilder(tester, initialSquad: fullSquad());
      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('action_profile')), findsNothing);
      expect(find.byKey(const ValueKey('action_make_captain')), findsOneWidget);
    });

    testWidgets('locked court: a chip tap opens the profile directly (no '
        'sheet); empty slots stay inert', (tester) async {
      final opened = <String>[];
      await pumpBuilder(tester,
          lockOverride: FantasyLockOverride.locked,
          initialSquad: FantasySquad(
            // One empty starter slot: no ATT Two.
            picks: [
              pick('GK One', FantasyPosition.gk),
              pick('Def One', FantasyPosition.def),
              pick('Def Two', FantasyPosition.def),
              pick('Att One', FantasyPosition.att),
              pick('Bench Def', FantasyPosition.def, bench: true),
              pick('Bench Att', FantasyPosition.att, bench: true),
            ],
            captainId: 'GK One',
            viceId: 'Def One',
          ),
          onOpenPlayer: opened.add);

      await tester.tap(find.byKey(const ValueKey('squad_chip_GK One')));
      await tester.pumpAndSettle();
      expect(opened, ['GK One']);
      expect(find.byKey(const ValueKey('action_profile')), findsNothing);
      expect(find.byKey(const ValueKey('action_make_captain')), findsNothing);

      // Bench chips are locked-viewable too.
      await tester.tap(find.byKey(const ValueKey('squad_chip_Bench Att')));
      await tester.pumpAndSettle();
      expect(opened, ['GK One', 'Bench Att']);

      // The empty slot never reacts — not the picker, not the profile.
      await tester.tap(find.byKey(const ValueKey('empty_slot_4')));
      await tester.pumpAndSettle();
      expect(find.text('Pick an attacker'), findsNothing);
      expect(opened, hasLength(2));
    });

    testWidgets('the deadline passing under an open court (the 30s ticker has '
        'not re-locked it yet): a chip tap opens the profile, never the '
        'edit sheet', (tester) async {
      final opened = <String>[];
      var clock = DateTime.utc(2026, 1, 1, 21); // an hour before the lock
      await pumpBuilder(
        tester,
        lockOverride: FantasyLockOverride.auto,
        initialSquad: fullSquad(),
        gameweeks: [
          Gameweek(
            number: 1,
            date: '01012026',
            lockUtc: DateTime.utc(2026, 1, 1, 22),
            opensUtc: null,
          ),
        ],
        nowUtc: () => clock,
        onOpenPlayer: opened.add,
      );
      expect(find.byKey(const ValueKey('squad_save')), findsOneWidget);

      // The lock passes; the builder hasn't rebuilt yet.
      clock = DateTime.utc(2026, 1, 1, 22, 5);
      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      expect(opened, ['Att One']);
      expect(find.byKey(const ValueKey('action_make_captain')), findsNothing);
      expect(find.byKey(const ValueKey('action_profile')), findsNothing);
    });

    testWidgets('locked without an opener keeps chips inert (unchanged)',
        (tester) async {
      await pumpBuilder(tester,
          lockOverride: FantasyLockOverride.locked, initialSquad: fullSquad());
      await tester.tap(find.byKey(const ValueKey('squad_chip_GK One')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('action_profile')), findsNothing);
    });
  });

  group('holder protection (spec §3)', () {
    /// The server re-labelled GK One as a DEF: no slot fits him, the GK
    /// slot is the hole his move left.
    FantasySquad relabelled() => FantasySquad(
          picks: [
            pick('GK One', FantasyPosition.def),
            pick('Def One', FantasyPosition.def),
            pick('Def Two', FantasyPosition.def),
            pick('Att One', FantasyPosition.att),
            pick('Att Two', FantasyPosition.att),
            pick('Bench Def', FantasyPosition.def, bench: true),
            pick('Bench Att', FantasyPosition.att, bench: true),
          ],
          captainId: 'Att One',
          viceId: 'Def One',
        );

    const alert = FantasySquadAlert(gameweek: 4, changes: [
      FantasyPositionChange(
          player: 'GK One', from: FantasyPosition.gk, to: FantasyPosition.def),
    ]);

    testWidgets('the alert banner sits at the top while the alert exists',
        (tester) async {
      await pumpBuilder(tester, initialSquad: relabelled(), alert: alert);
      expect(find.byKey(const ValueKey('squad_alert_banner')), findsOneWidget);
      expect(
          find.text('GK One moved to DEF — your team needs rearranging '
              'before the deadline. Swapping him out is free this week.'),
          findsOneWidget);
      // Banner above the budget bar.
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('squad_alert_banner'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const ValueKey('budget_bar'))).dy));

      await pumpBuilder(tester, initialSquad: relabelled());
      expect(find.byKey(const ValueKey('squad_alert_banner')), findsNothing);
    });

    testWidgets('an unplaceable pick shows in "Needs a new spot", never dropped',
        (tester) async {
      await pumpBuilder(tester, initialSquad: relabelled());
      expect(find.byKey(const ValueKey('unplaced_strip')), findsOneWidget);
      expect(find.text('Needs a new spot'), findsOneWidget);
      expect(find.text('Now a defender · \$5.0M'), findsOneWidget);
      expect(find.byKey(const ValueKey('empty_slot_0')), findsOneWidget);
      expect(
          find.text('Find GK One a new spot — swap him out or remove him.'),
          findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('Swap picks a replacement for the hole and unlocks Save',
        (tester) async {
      await pumpBuilder(tester, initialSquad: relabelled());
      await tester.tap(find.byKey(const ValueKey('unplaced_swap_GK One')));
      await tester.pumpAndSettle();
      expect(find.text('Pick a goalkeeper'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picker_row_Alan Keeper')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unplaced_strip')), findsNothing);
      expect(find.byKey(const ValueKey('squad_chip_Alan Keeper')),
          findsOneWidget);
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('squad_save')));
      await tester.pumpAndSettle();
      expect(savedSquads.single.picks.map((p) => p.playerId),
          isNot(contains('GK One')));
      expect(savedSquads.single.picks, hasLength(7));
    });

    testWidgets('Remove drops him and leaves the hole to fill',
        (tester) async {
      await pumpBuilder(tester, initialSquad: relabelled());
      await tester.tap(find.byKey(const ValueKey('unplaced_remove_GK One')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unplaced_strip')), findsNothing);
      expect(find.text('Pick a goalkeeper.'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    // Opus audit item 7: the errorContainer banner and the strip, with a
    // long moved player, at 360 px in both themes — scrolled end to end.
    for (final brightness in Brightness.values) {
      testWidgets('360 px: alert banner + "Needs a new spot" strip fit, '
          'no overflow anywhere — $brightness', (tester) async {
        const longName = 'Maximiliano Bartholomew Featherstonehaugh-Smythe';
        final squad = FantasySquad(
          picks: [
            pick(longName, FantasyPosition.def), // re-labelled GK → DEF
            pick('Def One', FantasyPosition.def),
            pick('Def Two', FantasyPosition.def),
            pick('Att One', FantasyPosition.att),
            pick('Att Two', FantasyPosition.att),
            pick('Bench Def', FantasyPosition.def, bench: true),
            pick('Bench Att', FantasyPosition.att, bench: true),
          ],
          captainId: 'Att One',
          viceId: 'Def One',
        );
        await pumpBuilder(
          tester,
          size: const Size(360, 760),
          brightness: brightness,
          initialSquad: squad,
          alert: const FantasySquadAlert(gameweek: 4, changes: [
            FantasyPositionChange(
                player: longName,
                from: FantasyPosition.gk,
                to: FantasyPosition.def),
          ]),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('squad_alert_banner')), findsOneWidget);
        expect(find.byKey(const ValueKey('unplaced_strip')), findsOneWidget);

        // Scroll the whole builder through: banner, court, strip, chips,
        // issues, Save.
        final scrollable = find.byType(Scrollable).first;
        for (final key in [
          'squad_alert_banner',
          'unplaced_strip',
          'squad_save',
        ]) {
          await tester.dragUntilVisible(
              find.byKey(ValueKey(key)), scrollable, const Offset(0, -200));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: key);
          final r = tester.getRect(find.byKey(ValueKey(key)));
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(360), reason: key);
        }
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
        }
      });
    }

    testWidgets('locked: the strip shows but Swap/Remove are disabled',
        (tester) async {
      await pumpBuilder(tester,
          initialSquad: relabelled(),
          lockOverride: FantasyLockOverride.locked);
      expect(find.byKey(const ValueKey('unplaced_strip')), findsOneWidget);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.byKey(const ValueKey('unplaced_swap_GK One')))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('unplaced_remove_GK One')))
              .onPressed,
          isNull);
    });
  });

  // Squad hardening (audit I2/I3).
  group('squad hardening', () {
    /// Makes the draft dirty + valid: Def Two takes the vice armband.
    Future<void> editVice(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('squad_chip_Def Two')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('action_make_vice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vice_badge_Def Two')), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    }

    testWidgets('a save refused after the deadline: kind message, edits '
        'dropped, the stored squad shown again', (tester) async {
      await pumpBuilder(tester,
          initialSquad: fullSquad(),
          onSave: (_) async => throw FirebaseException(
              plugin: 'firebase_database',
              code: 'permission-denied',
              message:
                  "Client doesn't have permission to access the desired data."));
      await editVice(tester);
      await tester.tap(find.byKey(const ValueKey('squad_save')));
      await tester.pumpAndSettle();

      expect(
          find.text("The deadline passed while you were editing — this week's "
              "team is locked. Your changes weren't saved."),
          findsOneWidget);
      expect(find.text("Couldn't save — try again."), findsNothing);
      // Back to the stored squad: Def One wears the vice armband again and
      // there is nothing left to save.
      expect(find.byKey(const ValueKey('vice_badge_Def One')), findsOneWidget);
      expect(find.byKey(const ValueKey('vice_badge_Def Two')), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('the refusal re-reads the LATEST stored squad from the stream',
        (tester) async {
      await pumpBuilder(tester,
          initialSquad: fullSquad(),
          onSave: (_) async => throw FirebaseException(
              plugin: 'firebase_database', code: 'permission-denied'));
      await editVice(tester);
      // Another device saved meanwhile (captain Att One, vice Att Two).
      squads.add(fullSquad(captainId: 'Att One', viceId: 'Att Two'));
      await tester.pump();
      expect(find.byKey(const ValueKey('vice_badge_Def Two')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('squad_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('captain_ring_Att One')), findsOneWidget);
      expect(find.byKey(const ValueKey('vice_badge_Att Two')), findsOneWidget);
    });

    testWidgets('any other failure keeps the edits and says try again',
        (tester) async {
      await pumpBuilder(tester,
          initialSquad: fullSquad(),
          onSave: (_) async => throw FirebaseException(
              plugin: 'firebase_database', code: 'unavailable'));
      await editVice(tester);
      await tester.tap(find.byKey(const ValueKey('squad_save')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save — try again."), findsOneWidget);
      expect(find.byKey(const ValueKey('vice_badge_Def Two')), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    });

    const invalid = FantasySquadAlert(
      gameweek: 3,
      kind: FantasySquadAlertKind.invalid,
      issues: ['duplicatePlayer', 'overBudget'],
    );

    testWidgets("the integrity alert renders in the banner: 'didn't count'",
        (tester) async {
      await pumpBuilder(tester, initialSquad: fullSquad(), alert: invalid);
      expect(find.byKey(const ValueKey('squad_alert_banner')), findsOneWidget);
      expect(
          find.text("Your Gameweek 3 team didn't count: duplicate player and "
              'over budget. Fix it before the next deadline.'),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('squad_alert_banner')),
              matching: find.byIcon(Icons.error_outline_rounded)),
          findsOneWidget);
      // The position alert keeps its own icon.
      await pumpBuilder(tester,
          initialSquad: fullSquad(),
          alert: const FantasySquadAlert(gameweek: 4, changes: [
            FantasyPositionChange(
                player: 'GK One',
                from: FantasyPosition.gk,
                to: FantasyPosition.def),
          ]));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('squad_alert_banner')),
              matching: find.byIcon(Icons.swap_horiz_rounded)),
          findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px: the integrity banner fits, no overflow — $brightness',
          (tester) async {
        await pumpBuilder(tester,
            size: const Size(360, 760),
            brightness: brightness,
            initialSquad: fullSquad(),
            alert: const FantasySquadAlert(
              gameweek: 12,
              kind: FantasySquadAlertKind.invalid,
              issues: [
                'tooManyPlayers', 'duplicatePlayer', 'unknownPlayer',
                'ineligiblePlayer', 'overBudget',
              ],
            ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final r = tester.getRect(find.byKey(const ValueKey('squad_alert_banner')));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      });
    }

    // FPL selling (spec §4): the sweep's over-budget preview — the exact
    // sentence, bright red (fantasyDownRed) in both themes, 360 px.
    const preview = FantasySquadAlert(
      gameweek: 2,
      kind: FantasySquadAlertKind.overBudgetPreview,
      issues: ['overBudget'],
      overTenths: 10,
    );
    const previewText = "Your team is \$1.0M over budget after this week's "
        "price changes. Fix it before the deadline or this week won't count.";

    for (final brightness in Brightness.values) {
      testWidgets(
          '360 px: the over-budget preview banner — exact copy, bright red, '
          'no overflow — $brightness', (tester) async {
        await pumpBuilder(tester,
            size: const Size(360, 760),
            brightness: brightness,
            initialSquad: fullSquad(),
            alert: preview);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final banner = find.byKey(const ValueKey('squad_alert_banner'));
        expect(banner, findsOneWidget);
        expect(find.text(previewText), findsOneWidget);
        final r = tester.getRect(banner);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));

        final red = brightness == Brightness.dark
            ? const Color(0xFFFF5252)
            : const Color(0xFFD32F2F);
        expect(tester.widget<Text>(find.text(previewText)).style?.color, red);
        final icon = tester.widget<Icon>(
            find.descendant(of: banner, matching: find.byType(Icon)));
        expect(icon.color, red);
        final box =
            tester.widget<Container>(banner).decoration! as BoxDecoration;
        expect(box.border, isNotNull);
        expect((box.border! as Border).top.color, red);
      });
    }
  });

  // FPL selling (spec §4): the shared draft's money — budget + realized
  // sales − spent at the charged prices — is what the bar, the picker, the
  // chips and the over-budget sentence show; Save waits until it is real.
  group('FPL selling money', () {
    const fullIds = [
      'GK One',
      'Def One',
      'Def Two',
      'Att One',
      'Att Two',
      'Bench Def',
      'Bench Att',
    ];

    /// Today's market by id: the fixture squad at $5.0M each, the test
    /// market's own prices, plus [moved].
    Map<String, int> market([Map<String, int> moved = const {}]) => {
          for (final id in fullIds) id: 50,
          for (final p in players) p.name: p.priceTenths,
          ...moved,
        };

    /// Last week's locked squad (the fixture squad at $5.0M each unless
    /// [prices] says otherwise), for gameweek [forGw].
    SaleBaselineState baseline(
            {int realized = 0, Map<String, int>? prices, int forGw = 3}) =>
        SaleBaselineState(
          baseline: SaleBaseline(
              forGw: forGw,
              prices: prices ?? {for (final id in fullIds) id: 50},
              realizedTenths: realized),
          loaded: true,
        );

    SquadDraftController draftWith({
      FantasySquad? squad,
      SaleBaselineState? sale,
      Map<String, int>? current,
      bool withContext = true,
    }) {
      final d = SquadDraftController(
          config: FantasyConfig.futsalDefault(),
          initial: squad ?? fullSquad());
      if (withContext) {
        d.setSaleContext(
            sale: sale ?? baseline(),
            currentPrices: current ?? market(),
            editingGw: 3);
      }
      return d;
    }

    Color red(Brightness b) => b == Brightness.dark
        ? const Color(0xFFFF5252)
        : const Color(0xFFD32F2F);

    Text realizedLine(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('budget_realized')));

    for (final brightness in Brightness.values) {
      testWidgets(
          'the bar counts realized sales: +/− line, red only when '
          'negative — $brightness', (tester) async {
        final draft = draftWith(sale: baseline(realized: 5));
        await pumpBuilder(tester, draft: draft, brightness: brightness);
        await tester.pump();

        // $35.0M spent of $50.0M + $0.5M from sales.
        expect(find.text('\$35.0M spent'), findsOneWidget);
        expect(find.text('\$15.5M left'), findsOneWidget);
        expect(realizedLine(tester).data, 'Includes +\$0.5M from sales');
        final context =
            tester.element(find.byKey(const ValueKey('budget_bar')));
        expect(realizedLine(tester).style?.color,
            Theme.of(context).colorScheme.onSurfaceVariant);

        // A loss narrows the room and reads in the bright down red.
        draft.setSaleContext(
            sale: baseline(realized: -5),
            currentPrices: market(),
            editingGw: 3);
        await tester.pump();
        expect(find.text('\$14.5M left'), findsOneWidget);
        expect(realizedLine(tester).data, 'Includes −\$0.5M from sales');
        expect(realizedLine(tester).style?.color, red(brightness));

        // Nothing realized: no second line.
        draft.setSaleContext(
            sale: baseline(), currentPrices: market(), editingGw: 3);
        await tester.pump();
        expect(find.byKey(const ValueKey('budget_realized')), findsNothing);
        expect(find.text('\$15.0M left'), findsOneWidget);
      });
    }

    testWidgets('selling a riser grows the room, and the bar says why',
        (tester) async {
      // Att One was bought at $5.0M and is $7.0M today: he sells for $6.0M.
      final draft = draftWith(current: market({'Att One': 70}));
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.text('\$15.0M left'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('action_remove')));
      await tester.pumpAndSettle();
      // $50.0M + $1.0M from the sale − $30.0M spent.
      expect(find.text('\$30.0M spent'), findsOneWidget);
      expect(find.text('\$21.0M left'), findsOneWidget);
      expect(realizedLine(tester).data, 'Includes +\$1.0M from sales');
    });

    testWidgets('a held player saved at another price shows and counts his '
        'baseline price', (tester) async {
      final squad = FantasySquad(
        picks: [
          for (final p in fullSquad().picks)
            p.playerId == 'Att One'
                ? pick('Att One', FantasyPosition.att, price: 90)
                : p,
        ],
        captainId: 'GK One',
        viceId: 'Def One',
      );
      final draft = draftWith(squad: squad);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      final chip = find.byKey(const ValueKey('squad_chip_Att One'));
      expect(
          find.descendant(of: chip, matching: find.textContaining('\$5.0M')),
          findsOneWidget);
      expect(
          find.descendant(of: chip, matching: find.textContaining('\$9.0M')),
          findsNothing);
      expect(find.text('\$35.0M spent'), findsOneWidget);
    });

    testWidgets('Swap: the picker offers the room after his sale, priced by '
        'the draft', (tester) async {
      // Last week: Ava (bought $5.0M, now $7.0M) instead of Att Two — she
      // was sold (+$1.0M). Att One was bought $5.0M, now $7.0M.
      final draft = draftWith(
        sale: baseline(prices: {
          for (final id in fullIds)
            if (id != 'Att Two') id: 50,
          'Ava Striker': 50,
        }),
        current: market({'Att One': 70}),
      );
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.text('\$16.0M left'), findsOneWidget);
      expect(realizedLine(tester).data, 'Includes +\$1.0M from sales');

      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('action_swap')));
      await tester.pumpAndSettle();
      // His $5.0M back + his sale (+$1.0M): $16.0M + $6.0M.
      expect(find.text('\$22.0M left'), findsOneWidget);
      // Ava comes back at what selling her banked ($6.0M) — taking her back
      // undoes that sale — not at the market's $7.0M.
      final ava = find.byKey(const ValueKey('picker_row_Ava Striker'));
      expect(find.descendant(of: ava, matching: find.text('\$6.0M')),
          findsOneWidget);
      expect(find.descendant(of: ava, matching: find.text('\$7.0M')),
          findsNothing);
      await tester.tap(ava);
      await tester.pumpAndSettle();

      // She is held again at her baseline $5.0M; Att One's sale is booked.
      final chip = find.byKey(const ValueKey('squad_chip_Ava Striker'));
      expect(
          find.descendant(of: chip, matching: find.textContaining('\$5.0M')),
          findsOneWidget);
      expect(find.text('\$16.0M left'), findsOneWidget);
      expect(draft.remainingTenths, 160);
    });

    testWidgets('the over-budget sentence counts realized sales',
        (tester) async {
      // Spent $50.5M: over the bare budget, legal with +$0.5M from sales.
      final squad = FantasySquad(
        picks: [
          for (final p in fullSquad().picks)
            p.playerId == 'Att One'
                ? pick('Att One', FantasyPosition.att, price: 205)
                : p,
        ],
        captainId: 'GK One',
        viceId: 'Def One',
      );
      final prices = {for (final id in fullIds) id: 50, 'Att One': 205};
      final draft = draftWith(
          squad: squad, sale: baseline(prices: prices, realized: 5));
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.text('\$0.0M left'), findsOneWidget);
      expect(find.textContaining('over budget'), findsNothing);

      draft.setSaleContext(
          sale: baseline(prices: prices, realized: -5),
          currentPrices: market(),
          editingGw: 3);
      await tester.pump();
      expect(find.text("You're \$1.0M over budget."), findsOneWidget);
      expect(find.text('\$1.0M over'), findsOneWidget);
    });

    testWidgets('Save waits for the money: disabled with the exact sentence '
        'until the draft is moneyReady', (tester) async {
      const sentence =
          'Your budget is still updating — try again in a few minutes.';
      final draft = draftWith(withContext: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      // A clean draft can't save anyway: no sentence.
      expect(find.text(sentence), findsNothing);

      // A valid edit: captain moves to Att One.
      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('action_make_captain')));
      await tester.pumpAndSettle();
      expect(draft.dirty, isTrue);
      expect(saveEnabled(tester), isFalse);
      expect(find.text(sentence), findsOneWidget);

      // A stale baseline (last week's) is not this week's money either.
      draft.setSaleContext(
          sale: baseline(forGw: 2), currentPrices: market(), editingGw: 3);
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      expect(find.text(sentence), findsOneWidget);

      draft.setSaleContext(
          sale: baseline(), currentPrices: market(), editingGw: 3);
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      expect(find.text(sentence), findsNothing);
      await tester.tap(find.byKey(const ValueKey('squad_save')));
      await tester.pumpAndSettle();
      expect(savedSquads, hasLength(1));
    });

    const pendingText =
        'Your budget is still updating — try again in a few minutes.';

    String? leftText(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data;

    Future<void> makeAttOneCaptain(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('action_make_captain')));
      await tester.pumpAndSettle();
    }

    /// Every [keys] widget is on screen inside 360 px (scrolled to), and no
    /// text anywhere is ellipsized.
    Future<void> expectFits360(WidgetTester tester, List<String> keys) async {
      final scrollable = find.byType(Scrollable).first;
      for (final key in keys) {
        await tester.dragUntilVisible(
            find.byKey(ValueKey(key)), scrollable, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: key);
        final r = tester.getRect(find.byKey(ValueKey(key)));
        expect(r.left, greaterThanOrEqualTo(0), reason: key);
        expect(r.right, lessThanOrEqualTo(360), reason: key);
      }
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('360 px: the realized line fits, no overflow — $brightness',
          (tester) async {
        final draft = draftWith(sale: baseline(realized: -125));
        await pumpBuilder(tester,
            draft: draft,
            brightness: brightness,
            size: const Size(360, 760));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(leftText(tester, 'budget_left'), '\$2.5M left');
        expect(realizedLine(tester).data, 'Includes −\$12.5M from sales');
        expect(realizedLine(tester).style?.color, red(brightness));
        await expectFits360(tester, ['budget_bar', 'budget_realized']);
      });

      // Error ≠ fact: last week's baseline is not this week's money — the
      // bar keeps what is spent but claims no room, no sales and no
      // over-budget verdict; an edit is told the budget is still updating.
      testWidgets('360 px, money not ready (a stale baseline): "— left", no '
          'realized line, no over-budget sentence — only "still updating" '
          '— $brightness', (tester) async {
        // If it were this week's money: $30.0M available, $35.0M spent —
        // "$5.0M over" with a −$20.0M line. None of it may show.
        final draft = draftWith(sale: baseline(realized: -200, forGw: 2));
        await pumpBuilder(tester,
            draft: draft,
            brightness: brightness,
            size: const Size(360, 760));
        await tester.pump();
        expect(draft.moneyReady, isFalse);
        expect(find.text('\$35.0M spent'), findsOneWidget);
        expect(leftText(tester, 'budget_left'), '— left');
        expect(find.byKey(const ValueKey('budget_realized')), findsNothing);
        expect(find.textContaining(RegExp(r'\bover\b')), findsNothing);
        final bar = tester.widget<LinearProgressIndicator>(find.descendant(
            of: find.byKey(const ValueKey('budget_bar')),
            matching: find.byType(LinearProgressIndicator)));
        expect(bar.value, 0); // no total implied
        // Clean: Save is off anyway — no sentence yet.
        expect(find.text(pendingText), findsNothing);

        await makeAttOneCaptain(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(pendingText), findsOneWidget);
        expect(find.textContaining('over budget'), findsNothing);
        expect(saveEnabled(tester), isFalse);
        await expectFits360(tester, ['budget_bar', 'squad_save']);
        final r = tester.getRect(find.text(pendingText));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      });
    }

    testWidgets('not ready + dirty + over budget: the pending sentence only; '
        'ready again: the numbers come back', (tester) async {
      // 7 × $8.0M = $56.0M against $50.0M — but nothing has loaded yet.
      final draft = draftWith(squad: fullSquad(price: 80), withContext: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.text('\$56.0M spent'), findsOneWidget);
      expect(leftText(tester, 'budget_left'), '— left');
      expect(find.text('\$6.0M over'), findsNothing);

      await makeAttOneCaptain(tester);
      expect(find.text(pendingText), findsOneWidget);
      expect(find.textContaining('over budget'), findsNothing);
      expect(find.text('Choose a captain.'), findsNothing);
      expect(saveEnabled(tester), isFalse);

      // The money lands (a first squad at today's market): the real
      // verdict replaces the pending sentence.
      draft.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: market(),
          editingGw: 3);
      await tester.pump();
      expect(find.text(pendingText), findsNothing);
      expect(find.text("You're \$6.0M over budget."), findsOneWidget);
      expect(leftText(tester, 'budget_left'), '\$6.0M over');
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('the picker claims no room while the money is not ready',
        (tester) async {
      final draft = draftWith(withContext: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      Future<void> openSwap() async {
        await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('action_swap')));
        await tester.pumpAndSettle();
      }

      await openSwap();
      expect(leftText(tester, 'picker_left'), '— left');
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker_left')), findsNothing);

      draft.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: market(),
          editingGw: 3);
      await tester.pump();
      await openSwap();
      // $50.0M − $35.0M + his $5.0M back.
      expect(leftText(tester, 'picker_left'), '\$20.0M left');
    });
  });

  // Transfers (plan 2026-11-03, Task 4): the line under the budget bar, the
  // "Take a points hit?" confirm before a save that adds a cost, and the
  // Wildcard / Free Hit chips — all read the shared draft's transferPreview.
  group('transfers (plan 2026-11-03)', () {
    final held = [for (final p in fullSquad().picks) p.playerId];
    const editingGw = 3;

    Color red(Brightness b) => b == Brightness.dark
        ? const Color(0xFFFF5252)
        : const Color(0xFFD32F2F);

    /// The transfers that never touch the armbands (captain GK One, vice
    /// Def One): fixture player out → market player in, same position.
    const swaps = [
      ('Def Two', 'Deb Rock'),
      ('Att One', 'Ava Striker'),
      ('Att Two', 'Axel Shot'),
      ('Bench Def', 'Dom Stone'),
      ('Bench Att', 'Ari Goal'),
    ];

    FantasyPlayer market(String name) =>
        players.firstWhere((p) => p.name == name);

    /// The saved squad: the fixture squad with the first [n] [swaps] made.
    FantasySquad savedWith(int n, {String? chip}) {
      final out = {for (final s in swaps.take(n)) s.$1: s.$2};
      return FantasySquad(
        picks: [
          for (final p in fullSquad().picks)
            out.containsKey(p.playerId)
                ? pick(out[p.playerId]!, p.position,
                    price: market(out[p.playerId]!).priceTenths,
                    bench: p.bench)
                : p,
        ],
        captainId: 'GK One',
        viceId: 'Def One',
        chip: chip,
      );
    }

    /// A shared draft the way the hub feeds it: money ready (a first squad
    /// at today's market), the transfer feed's [state] (null = the node is
    /// absent) and whether it has [answered].
    SquadDraftController draftWith({
      FantasySquad? stored,
      TransferStateView? state,
      bool answered = true,
    }) {
      final d = SquadDraftController(
          config: FantasyConfig.futsalDefault(),
          initial: stored ?? fullSquad());
      d.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: {
            for (final id in held) id: 50,
            for (final p in players) p.name: p.priceTenths,
          },
          editingGw: editingGw);
      d.setTransferContext(
          state: state, answered: answered, editingGw: editingGw);
      return d;
    }

    /// Last week's locked squad is the fixture squad; 2 free this week.
    TransferStateView counted({int? free = 2}) =>
        TransferStateView(free: free, countFromGw: editingGw, countFrom: held);

    /// Transfers [from]..[n] on the draft (the first [n] of [swaps]).
    void transfer(SquadDraftController d, int n, {int from = 0}) {
      for (final s in swaps.skip(from).take(n - from)) {
        final i = d.picks.indexWhere((p) => p?.playerId == s.$1);
        d.setPickAt(i, d.newPick(market(s.$2), bench: d.slots[i].bench));
      }
    }

    Text lineText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('transfers_line_text')));

    /// The chip row scrolls sideways (four 132 px cards): bring the chip on
    /// screen first, as a thumb would, then tap it.
    Future<void> tapChip(WidgetTester tester, String id) async {
      final chip = find.byKey(ValueKey('fantasy_chip_$id'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    Future<void> tapSave(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('squad_save')));
      await tester.pumpAndSettle();
    }

    // The line.

    testWidgets('a first team: the free line, muted; Wildcard and Free Hit '
        'sit out under "Your first team is free"', (tester) async {
      final draft = draftWith(state: null);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(lineText(tester).data,
          'Your first team is free — change anything until the deadline.');
      final context =
          tester.element(find.byKey(const ValueKey('transfers_line')));
      expect(lineText(tester).style?.color,
          Theme.of(context).colorScheme.onSurfaceVariant);
      expect(find.text('Your first team is free'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('fantasy_chip_wildcard')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsNothing);
      expect(draft.chip, isNull);
    });

    testWidgets('not answered yet (or the read failed): "Transfer count '
        'updating…", never a first team', (tester) async {
      final draft = draftWith(state: null, answered: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(lineText(tester).data, 'Transfer count updating…');
      expect(find.text('Your first team is free'), findsNothing);
      expect(find.text('Coming with transfers'), findsNothing);
    });

    // Error ≠ fact: an unknown count may BE a first team, and the server does
    // not guard a first-team Wildcard / Free Hit (the chip is spent) — so
    // arming waits for the answer; disarming never does.
    testWidgets('count unknown: Wildcard and Free Hit cannot be armed '
        '("Checking your transfers…"); Triple Captain still can',
        (tester) async {
      final draft = draftWith(state: null, answered: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.text('Checking your transfers…'), findsNWidgets(2));
      expect(find.text('Your first team is free'), findsNothing);

      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      expect(find.byType(AlertDialog), findsNothing);
      expect(draft.chip, isNull);

      await tapChip(tester, 'tripleCaptain');
      expect(draft.chip, 'tripleCaptain');
    });

    testWidgets('count unknown: an armed Wildcard can still be switched '
        'off', (tester) async {
      final draft =
          draftWith(stored: savedWith(0, chip: 'wildcard'), answered: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(draft.chip, 'wildcard');
      await tapChip(tester, 'wildcard');
      expect(find.byType(AlertDialog), findsNothing);
      expect(draft.chip, isNull);
    });

    testWidgets('the answer lifts the hold: the captions go and the chips '
        'ask as usual', (tester) async {
      final draft = draftWith(state: null, answered: false);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.text('Checking your transfers…'), findsNWidgets(2));

      draft.setTransferContext(
          state: counted(), answered: true, editingGw: editingGw);
      await tester.pump();
      expect(find.text('Checking your transfers…'), findsNothing);
      await tapChip(tester, 'wildcard');
      expect(find.text('Play your Wildcard?'), findsOneWidget);
    });

    // A node with no CountFromGw (written before the baseline shipped, e.g. a
    // GW1 save on the old server code) is as unknown as no answer: it may be
    // a first team, whose chip the server spends for nothing. No line, but
    // the chips are held.
    testWidgets('an older node (no baseline) holds the chips too — no line, '
        'no arming', (tester) async {
      final draft = draftWith(state: const TransferStateView(free: 2));
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.byKey(const ValueKey('transfers_line')), findsNothing);
      expect(find.text('Checking your transfers…'), findsNWidgets(2));

      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      expect(find.byType(AlertDialog), findsNothing);
      expect(draft.chip, isNull);

      await tapChip(tester, 'benchBoost');
      expect(draft.chip, 'benchBoost');
    });

    // The History read failed (the hub passes null): "nothing used" would be
    // a guess — a Wildcard spent earlier this set looks "1 left", and the
    // lock would void a replay and charge every transfer.
    testWidgets('chip history unknown (null): Wildcard / Free Hit are held, '
        'Triple Captain / Bench Boost keep their "1 left" and arm',
        (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft, chipHistory: null);
      await tester.pump();
      expect(find.text('Checking your transfers…'), findsNWidgets(2));
      expect(find.text('1 left'), findsNWidgets(4));

      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      expect(find.byType(AlertDialog), findsNothing);
      expect(draft.chip, isNull);

      await tapChip(tester, 'tripleCaptain');
      expect(draft.chip, 'tripleCaptain');
    });

    testWidgets('chip history unknown: an armed Wildcard still switches off',
        (tester) async {
      final draft = draftWith(
          stored: savedWith(0, chip: 'wildcard'), state: counted());
      await pumpBuilder(tester, draft: draft, chipHistory: null);
      await tester.pump();
      await tapChip(tester, 'wildcard');
      expect(draft.chip, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('chip history loaded EMPTY is known: Wildcard asks as usual',
        (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft, chipHistory: const {});
      await tester.pump();
      expect(find.text('Checking your transfers…'), findsNothing);
      await tapChip(tester, 'wildcard');
      expect(find.text('Play your Wildcard?'), findsOneWidget);
    });

    testWidgets('an older node with no baseline: no line at all',
        (tester) async {
      final draft = draftWith(state: const TransferStateView(free: 2));
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(find.byKey(const ValueKey('transfers_line')), findsNothing);
      expect(find.byKey(const ValueKey('budget_bar')), findsOneWidget);
    });

    testWidgets('the line follows the draft: within the free ones muted, '
        'past them in the bright down red', (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(lineText(tester).data, '0 of 2 free transfers used');

      transfer(draft, 1);
      await tester.pump();
      expect(lineText(tester).data, '1 of 2 free transfers used');
      final context =
          tester.element(find.byKey(const ValueKey('transfers_line')));
      expect(lineText(tester).style?.color,
          Theme.of(context).colorScheme.onSurfaceVariant);

      transfer(draft, 3, from: 1);
      await tester.pump();
      expect(lineText(tester).data, '3 transfers · 2 free · −4 pts this week');
      expect(lineText(tester).style?.color, red(Brightness.light));
    });

    for (final brightness in Brightness.values) {
      testWidgets('the cost text is fantasyDownRed in $brightness — never '
          'the soft error pink', (tester) async {
        final draft = draftWith(state: counted());
        transfer(draft, 4);
        await pumpBuilder(tester, draft: draft, brightness: brightness);
        await tester.pump();
        expect(lineText(tester).data,
            '4 transfers · 2 free · −8 pts this week');
        expect(lineText(tester).style?.color, red(brightness));
        final icon = tester.widget<Icon>(find.descendant(
            of: find.byKey(const ValueKey('transfers_line')),
            matching: find.byType(Icon)));
        expect(icon.color, red(brightness));
      });
    }

    testWidgets('the chip in the draft is said in the line', (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft);
      draft.setChip('wildcard');
      await tester.pump();
      expect(lineText(tester).data,
          'Wildcard on — every transfer is free this week.');
      draft.setChip('freeHit');
      await tester.pump();
      expect(lineText(tester).data,
          'Free Hit on — every transfer is free, and your team comes back '
          'after this week.');
    });

    testWidgets('sits directly under the budget bar, above the court',
        (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      final bar = tester.getRect(find.byKey(const ValueKey('budget_bar')));
      final line = tester.getRect(find.byKey(const ValueKey('transfers_line')));
      final court =
          tester.getRect(find.byKey(const ValueKey('squad_chip_GK One')));
      expect(line.top, greaterThanOrEqualTo(bar.bottom));
      expect(line.top - bar.bottom, lessThan(16));
      expect(line.bottom, lessThanOrEqualTo(court.top));
    });

    testWidgets('a locked court has no transfers line', (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester,
          draft: draft, lockOverride: FantasyLockOverride.locked);
      await tester.pump();
      expect(find.byKey(const ValueKey('transfers_line')), findsNothing);
    });

    // The confirm.

    testWidgets('a save whose cost rises from 0 to 4 asks first; Cancel '
        'saves nothing', (tester) async {
      final draft = draftWith(state: counted());
      transfer(draft, 3);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();

      await tapSave(tester);
      expect(find.text('Take a points hit?'), findsOneWidget);
      expect(
          find.text('This team uses 3 transfers and you have 2 free, so it '
              'costs 4 points this week.'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save (−4 pts)'), findsOneWidget);
      expect(savedSquads, isEmpty, reason: 'nothing is saved before the yes');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Take a points hit?'), findsNothing);
      expect(savedSquads, isEmpty);
      expect(find.text('Squad saved — good luck!'), findsNothing);
      // Still editable: the draft is dirty and Save is armed, not stuck.
      expect(draft.dirty, isTrue);
      expect(find.text('Save squad'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('confirming "Save (−4 pts)" saves the squad as it was',
        (tester) async {
      final draft = draftWith(state: counted());
      transfer(draft, 3);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();

      await tapSave(tester);
      await tester.tap(find.text('Save (−4 pts)'));
      await tester.pumpAndSettle();
      expect(savedSquads, hasLength(1));
      expect({for (final p in savedSquads.single.picks) p.playerId},
          containsAll(['Deb Rock', 'Ava Striker', 'Axel Shot']));
      expect(find.text('Squad saved — good luck!'), findsOneWidget);
      expect(draft.dirty, isFalse);
    });

    testWidgets('one transfer with 0 free reads singular', (tester) async {
      final draft = draftWith(state: counted(free: 0));
      transfer(draft, 1);
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      await tapSave(tester);
      expect(
          find.text('This team uses 1 transfer and you have 0 free, so it '
              'costs 4 points this week.'),
          findsOneWidget);
      expect(find.text('Save (−4 pts)'), findsOneWidget);
    });

    testWidgets('a hit already saved is not asked again; going deeper is',
        (tester) async {
      // Saved with 3 transfers (−4); the draft starts from it.
      final draft = draftWith(stored: savedWith(3), state: counted());
      draft.setChip('tripleCaptain'); // an edit that changes no transfer
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(lineText(tester).data, '3 transfers · 2 free · −4 pts this week');

      await tapSave(tester);
      expect(find.text('Take a points hit?'), findsNothing);
      expect(savedSquads, hasLength(1));

      // A fourth transfer takes the cost from −4 to −8: ask again.
      transfer(draft, 4, from: 3);
      await tester.pump();
      await tapSave(tester);
      expect(
          find.text('This team uses 4 transfers and you have 2 free, so it '
              'costs 8 points this week.'),
          findsOneWidget);
      expect(find.text('Save (−8 pts)'), findsOneWidget);
    });

    testWidgets('a save that does not raise the cost shows no dialog — '
        'within the free ones, or when it drops', (tester) async {
      // Within the free ones: 0 → 0.
      final within = draftWith(state: counted());
      transfer(within, 2);
      await pumpBuilder(tester, draft: within);
      await tester.pump();
      await tapSave(tester);
      expect(find.text('Take a points hit?'), findsNothing);
      expect(savedSquads, hasLength(1));

      // Cost drops: saved with 4 transfers (−8), back to 3 (−4).
      savedSquads.clear();
      final drops = draftWith(stored: savedWith(4), state: counted());
      final i = drops.picks.indexWhere((p) => p?.playerId == 'Dom Stone');
      drops.setPickAt(i, pick('Bench Def', FantasyPosition.def, bench: true));
      await pumpBuilder(tester, draft: drops);
      await tester.pump();
      expect(lineText(tester).data, '3 transfers · 2 free · −4 pts this week');
      await tapSave(tester);
      expect(find.text('Take a points hit?'), findsNothing);
      expect(savedSquads, hasLength(1));
    });

    testWidgets('Save is never blocked by the line: a save while the count '
        'is not ready, or the node is older, or a first team, saves '
        'without a dialog (D1d)', (tester) async {
      final cases = <String, SquadDraftController>{
        'not answered': draftWith(state: null, answered: false),
        'older node': draftWith(state: const TransferStateView(free: 2)),
        'first team': draftWith(state: null),
      };
      for (final entry in cases.entries) {
        savedSquads.clear();
        transfer(entry.value, 4);
        await pumpBuilder(tester, draft: entry.value);
        await tester.pump();
        await tapSave(tester);
        expect(find.text('Take a points hit?'), findsNothing,
            reason: entry.key);
        expect(savedSquads, hasLength(1), reason: entry.key);
      }
    });

    testWidgets('a Wildcard / Free Hit week costs nothing: no dialog, the '
        'chip is saved', (tester) async {
      final draft = draftWith(state: counted());
      transfer(draft, 4);
      draft.setChip('wildcard');
      await pumpBuilder(tester, draft: draft);
      await tester.pump();
      expect(lineText(tester).data,
          'Wildcard on — every transfer is free this week.');
      await tapSave(tester);
      expect(find.text('Take a points hit?'), findsNothing);
      expect(savedSquads.single.chip, 'wildcard');
    });

    testWidgets('a failed save after the yes keeps the edits and says try '
        'again', (tester) async {
      final draft = draftWith(state: counted());
      transfer(draft, 3);
      await pumpBuilder(tester,
          draft: draft, onSave: (_) async => throw StateError('network'));
      await tester.pump();
      await tapSave(tester);
      await tester.tap(find.text('Save (−4 pts)'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save — try again."), findsOneWidget);
      expect(draft.dirty, isTrue);
    });

    // The chips.

    testWidgets('Wildcard from the builder: tap, confirm, armed — and the '
        'line says so', (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft);
      await tester.pump();

      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsOneWidget);
      expect(draft.chip, isNull);
      await tester.tap(find.text('Play Wildcard'));
      await tester.pumpAndSettle();
      expect(draft.chip, 'wildcard');
      expect(find.byKey(const ValueKey('chip_active_wildcard')),
          findsOneWidget);
      expect(lineText(tester).data,
          'Wildcard on — every transfer is free this week.');

      // Free Hit replaces it, after its own question.
      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(find.text('Play your Free Hit?'), findsOneWidget);
      await tester.tap(find.text('Play Free Hit'));
      await tester.pumpAndSettle();
      expect(draft.chip, 'freeHit');
      expect(find.byKey(const ValueKey('chip_active_wildcard')), findsNothing);
    });

    testWidgets('arm Wildcard, make 4 transfers, switch it off: the cost '
        'line and the confirm are back at once', (tester) async {
      final draft = draftWith(state: counted());
      await pumpBuilder(tester, draft: draft);
      await tester.pump();

      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play Wildcard'));
      await tester.pumpAndSettle();

      // Four transfers through the real picker.
      for (final s in swaps.take(4)) {
        await tester.tap(find.byKey(ValueKey('squad_chip_${s.$1}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('action_swap')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('picker_row_${s.$2}')));
        await tester.pumpAndSettle();
      }
      expect(lineText(tester).data,
          'Wildcard on — every transfer is free this week.');

      // Tapping the armed chip switches it off — no dialog.
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsNothing);
      expect(draft.chip, isNull);
      expect(lineText(tester).data,
          '4 transfers · 2 free · −8 pts this week');

      await tapSave(tester);
      expect(find.text('Take a points hit?'), findsOneWidget);
      expect(
          find.text('This team uses 4 transfers and you have 2 free, so it '
              'costs 8 points this week.'),
          findsOneWidget);
      expect(find.text('Save (−8 pts)'), findsOneWidget);
    });

    testWidgets('"Used" still blocks arming Wildcard and Free Hit',
        (tester) async {
      // Ten weekly gameweeks locking Jan 1..10 22:00Z; editing GW4.
      final gws = [
        for (var n = 1; n <= 10; n++)
          Gameweek(
            number: n,
            date: '01${n.toString().padLeft(2, '0')}2026',
            lockUtc: DateTime.utc(2026, 1, n, 22),
            opensUtc: null,
          ),
      ];
      final draft = draftWith(state: counted());
      await pumpBuilder(
        tester,
        draft: draft,
        gameweeks: gws,
        nowUtc: () => DateTime.utc(2026, 1, 3, 23),
        chipHistory: {
          1: const ChipHistoryEntry(chip: 'wildcard'),
          2: const ChipHistoryEntry(chip: 'freeHit'),
        },
      );
      await tester.pump();
      expect(find.text('Used'), findsNWidgets(2));
      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(draft.chip, isNull);
    });

    // 360 px, both themes.

    for (final brightness in Brightness.values) {
      testWidgets('360 px: the line, the captions and the hit dialog fit, '
          'no overflow — $brightness', (tester) async {
        void expectInside360(Finder finder) {
          final r = tester.getRect(finder);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
        }

        // A first team: the longest free line + two caption cards.
        final first = draftWith(state: null);
        await pumpBuilder(tester,
            draft: first, brightness: brightness, size: const Size(360, 1900));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectInside360(find.byKey(const ValueKey('transfers_line')));
        expect(find.text('Your first team is free'), findsNWidgets(2));

        // A hit: the cost line and the dialog.
        final hit = draftWith(state: counted());
        transfer(hit, 4);
        await pumpBuilder(tester,
            draft: hit, brightness: brightness, size: const Size(360, 1900));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectInside360(find.byKey(const ValueKey('transfers_line')));
        expect(lineText(tester).style?.color, red(brightness));
        await tapSave(tester);
        expect(tester.takeException(), isNull);
        for (final text in [
          'Take a points hit?',
          'This team uses 4 transfers and you have 2 free, so it costs 8 '
              'points this week.',
          'Cancel',
          'Save (−8 pts)',
        ]) {
          expectInside360(find.text(text));
        }
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
        }
      });
    }
  });

  // Live everywhere, Task 5: the locked My Team. The placeholder is gone: the
  // strip says what the week is doing (copy pinned in live_logic_test.dart),
  // the LIVE pill shows only while the numbers are live, and every court chip
  // carries that player's counted points. Nothing here animates on its own
  // except the pill's pulse, so these tests pump explicit durations (a
  // pumpAndSettle would never return with a pulsing pill on screen).
  group('locked week (live everywhere)', () {
    const live = LockedWeekView.live(weekPoints: 34, rank: 5, movement: 2);

    LockedWeekModel model(LockedWeekView view,
            {Map<String, String> chips = const {}, FantasySquad? squad}) =>
        LockedWeekModel(view: view, chipTexts: chips, squad: squad);


    Future<void> pumpLocked(
      WidgetTester tester,
      LockedWeekModel? lockedWeek, {
      Size size = const Size(420, 1900),
      Brightness brightness = Brightness.light,
      FantasySquad? squad,
      FantasyLockOverride lockOverride = FantasyLockOverride.locked,
    }) async {
      await pumpBuilder(tester,
          lockOverride: lockOverride,
          initialSquad: squad ?? fullSquad(),
          lockedWeek: lockedWeek,
          size: size,
          brightness: brightness);
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('live: the pill, the points and rank and the movement',
        (tester) async {
      await pumpLocked(tester, model(live));
      expect(find.byType(FantasyLivePill), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('34 pts · #5 ▲2'), findsOneWidget);
      expect(find.text('Locked · waiting for kickoff'), findsNothing);
      // The pill sits inside the strip.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('locked_live_strip')),
              matching: find.byType(FantasyLivePill)),
          findsOneWidget);
    });

    testWidgets('the movement reads green up / bright red down, colour from '
        'the shared leaderboard pair', (tester) async {
      Color? colorOf(String glyphText) {
        final rich = tester.widget<RichText>(find.descendant(
            of: find.byKey(const ValueKey('locked_live_strip')),
            matching: find.byWidgetPredicate((w) =>
                w is RichText && w.text.toPlainText().contains(' pts'))));
        Color? found;
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == glyphText) {
            found = span.style?.color;
          }
          return true;
        });
        return found;
      }

      await pumpLocked(tester, model(live));
      expect(colorOf('▲2'), const Color(0xFF2FA05A)); // fantasyPitchGreen light

      await pumpLocked(
          tester,
          model(const LockedWeekView.live(
              weekPoints: 34, rank: 5, movement: -1)));
      expect(colorOf('▼1'), const Color(0xFFD32F2F)); // fantasyDownRed light
    });

    testWidgets('every other state: no pill', (tester) async {
      for (final (view, text) in [
        (const LockedWeekView.waiting(), 'Locked · waiting for kickoff'),
        (const LockedWeekView.unknown(), 'Locked'),
        (
          const LockedWeekView.settled(weekPoints: 34, rank: 5),
          'Final · 34 pts · #5'
        ),
        (const LockedWeekView.voided(), 'Voided · this week counts 0'),
        (const LockedWeekView.invalid(), "0 pts · this week didn't count"),
      ]) {
        await pumpLocked(tester, model(view));
        expect(find.byType(FantasyLivePill), findsNothing, reason: text);
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('no model at all: the honest default, no pill',
        (tester) async {
      await pumpLocked(tester, null);
      // Nothing is known about the week: "Locked", never a claim about
      // kickoff.
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Locked · waiting for kickoff'), findsNothing);
      expect(find.byType(FantasyLivePill), findsNothing);
    });

    testWidgets('the court chips show the slot texts', (tester) async {
      await pumpLocked(
          tester,
          model(live, chips: {
            'GK One': '16 pts · live',
            'Def One': 'Not started',
            'Def Two': '4 pts',
            'Att Two': 'Out',
            'Bench Def': '2.5 pts',
          }));
      Finder inChip(String id, String text) => find.descendant(
          of: find.byKey(ValueKey('squad_chip_$id')),
          matching: find.text(text));
      expect(inChip('GK One', '16 pts · live'), findsOneWidget);
      expect(inChip('Def One', 'Not started'), findsOneWidget);
      expect(inChip('Def Two', '4 pts'), findsOneWidget);
      expect(inChip('Att Two', 'Out'), findsOneWidget);
      expect(inChip('Bench Def', '2.5 pts'), findsOneWidget);
      // A pick with no text (not in the squad's slots) shows none.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('squad_chip_Att One')),
              matching: find.textContaining('pts')),
          findsNothing);
    });

    testWidgets('voided: the chips stay quiet', (tester) async {
      await pumpLocked(tester, model(const LockedWeekView.voided()));
      expect(find.textContaining(' pts'), findsNothing);
    });

    testWidgets('while editing is open the model is ignored: the budget '
        'bar, no strip, no pill, no chip text', (tester) async {
      await pumpLocked(tester, model(live, chips: {'GK One': '16 pts · live'}),
          lockOverride: FantasyLockOverride.open);
      expect(find.byKey(const ValueKey('budget_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('locked_live_strip')), findsNothing);
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(find.text('16 pts · live'), findsNothing);
    });

    testWidgets('the numbers update in place when the model changes',
        (tester) async {
      Widget builder(LockedWeekModel m) => MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: FantasySquadBuilder(
                config: FantasyConfig.futsalDefault(),
                lockOverride: FantasyLockOverride.locked,
                gameweeks: const [],
                players: players,
                squadStates: squads.stream,
                initialSquad: fullSquad(),
                onSaveSquad: (_) async {},
                chipHistory: const {},
                lockedWeek: m,
              ),
            ),
          );
      tester.view.physicalSize = const Size(420, 1900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(builder(model(live, chips: {'GK One': '8 pts · live'})));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('8 pts · live'), findsOneWidget);

      await tester.pumpWidget(builder(model(
          const LockedWeekView.live(weekPoints: 40, rank: 4, movement: 3),
          chips: {'GK One': '14 pts · live'})));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('40 pts · #4 ▲3'), findsOneWidget);
      expect(find.text('14 pts · live'), findsOneWidget);
      expect(find.text('8 pts · live'), findsNothing);
      // The same pill widget lives on (no remount flash).
      expect(find.byType(FantasyLivePill), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px, scrolled end to end: no overflow, no ellipsis — '
          '$brightness', (tester) async {
        await pumpLocked(
            tester,
            model(
                const LockedWeekView.live(
                    weekPoints: 112, rank: 1203, movement: -14),
                chips: {
                  'GK One': '10.5 pts · live',
                  'Def One': 'Not started',
                  'Def Two': '104 pts',
                  'Att One': 'Out',
                  'Att Two': '12 pts · live',
                  'Bench Def': '2.5 pts',
                  'Bench Att': '0 pts',
                }),
            size: const Size(360, 760),
            brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('112 pts · #1203 ▼14'), findsOneWidget);
        final scrollable = find.byType(Scrollable).first;
        for (final key in [
          'locked_live_strip',
          'squad_chip_Bench Att',
        ]) {
          await tester.dragUntilVisible(
              find.byKey(ValueKey(key)), scrollable, const Offset(0, -200));
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull, reason: key);
          final r = tester.getRect(find.byKey(ValueKey(key)));
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(360), reason: key);
        }
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
        }
      });
    }

    testWidgets('the voided / invalid / final copy fits 360 px in dark mode',
        (tester) async {
      for (final view in [
        const LockedWeekView.voided(),
        const LockedWeekView.invalid(),
        const LockedWeekView.settled(weekPoints: 112, rank: 1203),
      ]) {
        await pumpLocked(tester, model(view),
            size: const Size(360, 760), brightness: Brightness.dark);
        expect(tester.takeException(), isNull);
        final r =
            tester.getRect(find.byKey(const ValueKey('locked_live_strip')));
        expect(r.right, lessThanOrEqualTo(360));
      }
    });
  });

  // Live everywhere, Task 5: the captain nameplate's multiplier is the REAL
  // one (the inventory bug: "×2" was hard-coded — a Triple Captain week
  // showed ×2 while scoring ×3).
  group('captain nameplate multiplier', () {
    testWidgets('×2 without a chip', (tester) async {
      await pumpBuilder(tester, initialSquad: fullSquad());
      expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsNothing);
    });

    testWidgets('×3 under Triple Captain', (tester) async {
      await pumpBuilder(tester,
          initialSquad: fullSquad(chip: 'tripleCaptain'));
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×2'), findsNothing);
    });

    testWidgets('another chip keeps ×2; only the captain carries a ×',
        (tester) async {
      await pumpBuilder(tester, initialSquad: fullSquad(chip: 'benchBoost'));
      expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
      expect(find.textContaining(' · ×'), findsOneWidget);
    });

    testWidgets('arming and disarming Triple Captain flips the nameplate at '
        'once', (tester) async {
      await pumpBuilder(tester, initialSquad: fullSquad());
      expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('fantasy_chip_tripleCaptain')));
      await tester.pumpAndSettle();
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('fantasy_chip_tripleCaptain')));
      await tester.pumpAndSettle();
      expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
    });

    testWidgets(
        'a locked court with no locked squad loaded falls back to the '
        'draft\'s squad (and its multiplier)', (tester) async {
      await pumpBuilder(tester,
          lockOverride: FantasyLockOverride.locked,
          initialSquad: fullSquad(chip: 'tripleCaptain'));
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
    });
  });

  // Live everywhere, Task 5 fix round 1: while the week is locked the court
  // is the squad that was LOCKED (PublishedPicks while live, History once
  // settled) — never Squads/<uid>, which the server rewrites after finalize
  // (the spent chip removed; a Free Hit week's squad replaced by last week's)
  // and which keeps a chip the lock voided.
  group('the locked court is the locked squad', () {
    LockedWeekModel lockedModel(FantasySquad? squad,
            {Map<String, String> chips = const {},
            LockedWeekView view = const LockedWeekView.settled(
                weekPoints: 34, rank: 5)}) =>
        LockedWeekModel(view: view, chipTexts: chips, squad: squad);

    Future<void> pumpLockedCourt(
      WidgetTester tester, {
      required FantasySquad saved,
      LockedWeekModel? lockedWeek,
      Brightness brightness = Brightness.light,
      Size size = const Size(420, 1900),
    }) async {
      await pumpBuilder(tester,
          lockOverride: FantasyLockOverride.locked,
          initialSquad: saved,
          lockedWeek: lockedWeek,
          size: size,
          brightness: brightness);
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
        'a settled Triple Captain week whose Squads chip was removed by the '
        'rollover: the nameplate reads ×3', (tester) async {
      await pumpLockedCourt(tester,
          saved: fullSquad(), // Squads: the chip is gone
          lockedWeek: lockedModel(fullSquad(chip: 'tripleCaptain')));
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×2'), findsNothing);
    });

    testWidgets(
        'a chip the lock VOIDED (Squads keeps it) is ×2 during the live '
        'week', (tester) async {
      await pumpLockedCourt(tester,
          saved: fullSquad(chip: 'tripleCaptain'), // Squads: still armed
          lockedWeek: lockedModel(fullSquad(), // PublishedPicks: stripped
              view: const LockedWeekView.live(weekPoints: 12, rank: 3)));
      expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsNothing);
    });

    testWidgets(
        'a settled Free Hit week whose Squads was restored to last week\'s '
        'squad: the court shows the Free Hit squad, with its points',
        (tester) async {
      // Squads (restored): last week's players. The Free Hit squad played.
      final restored = FantasySquad(
        picks: [
          pick('Old GK', FantasyPosition.gk),
          pick('Old Def One', FantasyPosition.def),
          pick('Old Def Two', FantasyPosition.def),
          pick('Old Att One', FantasyPosition.att),
          pick('Old Att Two', FantasyPosition.att),
          pick('Old Bench Def', FantasyPosition.def, bench: true),
          pick('Old Bench Att', FantasyPosition.att, bench: true),
        ],
        captainId: 'Old GK',
        viceId: 'Old Def One',
      );
      await pumpLockedCourt(tester,
          saved: restored,
          lockedWeek: lockedModel(fullSquad(chip: 'freeHit'), chips: {
            'GK One': '16 pts',
            'Def One': '4 pts',
            'Bench Att': '2.5 pts',
          }));
      for (final id in [
        'GK One',
        'Def One',
        'Def Two',
        'Att One',
        'Att Two',
        'Bench Def',
        'Bench Att'
      ]) {
        expect(find.byKey(ValueKey('squad_chip_$id')), findsOneWidget,
            reason: id);
      }
      expect(find.byKey(const ValueKey('squad_chip_Old GK')), findsNothing);
      expect(find.byKey(const ValueKey('squad_chip_Old Att Two')),
          findsNothing);
      Finder inChip(String id, String text) => find.descendant(
          of: find.byKey(ValueKey('squad_chip_$id')), matching: find.text(text));
      expect(inChip('GK One', '16 pts'), findsOneWidget);
      expect(inChip('Def One', '4 pts'), findsOneWidget);
      expect(inChip('Bench Att', '2.5 pts'), findsOneWidget);
      // The Free Hit squad's own armband and ring.
      expect(find.byKey(const ValueKey('captain_ring_GK One')), findsOneWidget);
      // The saved squad's "Needs a new spot" strip has no business here.
      expect(find.byKey(const ValueKey('unplaced_strip')), findsNothing);
    });

    testWidgets(
        'the armband is the locked squad\'s: the captain ring and the vice '
        'badge follow it, not the draft', (tester) async {
      await pumpLockedCourt(tester,
          saved: fullSquad(), // Squads: GK One captain, Def One vice
          lockedWeek: lockedModel(
              fullSquad(captainId: 'Att One', viceId: 'Att Two')));
      expect(find.byKey(const ValueKey('captain_ring_Att One')), findsOneWidget);
      expect(find.byKey(const ValueKey('captain_ring_GK One')), findsNothing);
      expect(find.byKey(const ValueKey('vice_badge_Att Two')), findsOneWidget);
    });

    testWidgets(
        'the locked squad not loaded (failed / none): the court falls back '
        'to the draft\'s squad and shows NO chip lines', (tester) async {
      await pumpLockedCourt(tester,
          saved: fullSquad(chip: 'tripleCaptain'),
          lockedWeek: lockedModel(null,
              view: const LockedWeekView.live(weekPoints: 34, rank: 5)));
      expect(find.byKey(const ValueKey('squad_chip_GK One')), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
      expect(find.textContaining(' pts'), findsOneWidget,
          reason: 'only the strip says points (34 pts · #5)');
      expect(find.text('34 pts · #5'), findsOneWidget);
    });

    // Final review I2: the chip row reads the LOCKED squad's chip while
    // locked, like the court — never Squads/<uid>'s (which keeps a chip the
    // lock voided, and is switched off / restored after finalize).
    String chipBadge(WidgetTester tester, String id) => tester
        .widget<Text>(find.descendant(
            of: find.byKey(ValueKey('chip_count_$id')),
            matching: find.byType(Text)))
        .data!;
    bool chipLit(WidgetTester tester, String id) {
      final box = tester.widget<AnimatedContainer>(find.descendant(
          of: find.byKey(ValueKey('fantasy_chip_$id')),
          matching: find.byType(AnimatedContainer)));
      return ((box.decoration as BoxDecoration).boxShadow ?? const [])
          .isNotEmpty;
    }

    const chipIds = ['tripleCaptain', 'benchBoost', 'wildcard', 'freeHit'];

    testWidgets(
        'a chip the lock VOIDED (Squads keeps it): the chip row shows no '
        '"Active" chip during the live week', (tester) async {
      await pumpLockedCourt(tester,
          saved: fullSquad(chip: 'tripleCaptain'), // Squads: still armed
          lockedWeek: lockedModel(fullSquad(), // PublishedPicks: stripped
              view: const LockedWeekView.live(weekPoints: 12, rank: 3)));
      expect(find.text('Active'), findsNothing);
      for (final id in chipIds) {
        expect(find.byKey(ValueKey('chip_active_$id')), findsNothing,
            reason: id);
        expect(chipLit(tester, id), isFalse, reason: id);
      }
      expect(chipBadge(tester, 'tripleCaptain'), '1 left');
    });

    testWidgets(
        'a live Triple Captain week (History not written yet): the row shows '
        'it Active, matching the ×3 nameplate — even with Squads switched '
        'off', (tester) async {
      await pumpLockedCourt(tester,
          saved: fullSquad(),
          lockedWeek: lockedModel(fullSquad(chip: 'tripleCaptain'),
              view: const LockedWeekView.live(weekPoints: 34, rank: 5)));
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_active_tripleCaptain')),
          findsOneWidget);
      expect(chipLit(tester, 'tripleCaptain'), isTrue);
      expect(chipLit(tester, 'benchBoost'), isFalse);
    });

    testWidgets(
        'a settled Triple Captain week whose Squads chip was switched off by '
        'the rollover: the row shows Triple Captain as the week\'s chip (lit, '
        'Used), consistent with the ×3 nameplate', (tester) async {
      // GW2 locked Jan 2 22:00Z and has settled (the court still locked on
      // it); the row's set is the next week's (GW3), so GW2's chip is Used.
      final gws = [
        for (var n = 1; n <= 3; n++)
          Gameweek(
            number: n,
            date: '01${n.toString().padLeft(2, '0')}2026',
            lockUtc: DateTime.utc(2026, 1, n, 22),
            opensUtc: null,
          ),
      ];
      await pumpBuilder(tester,
          lockOverride: FantasyLockOverride.locked,
          gameweeks: gws,
          nowUtc: () => DateTime.utc(2026, 1, 2, 23),
          initialSquad: fullSquad(), // Squads: the chip is gone
          chipHistory: {2: const ChipHistoryEntry(chip: 'tripleCaptain')},
          lockedWeek: lockedModel(fullSquad(chip: 'tripleCaptain')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('budget_bar')), findsNothing,
          reason: 'the court is locked on GW2');
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);
      expect(chipLit(tester, 'tripleCaptain'), isTrue);
      expect(chipBadge(tester, 'tripleCaptain'), 'Used');
      for (final id in chipIds.skip(1)) {
        expect(chipLit(tester, id), isFalse, reason: id);
      }
    });

    testWidgets('tapping a chip of the locked court opens his profile',
        (tester) async {
      final opened = <String>[];
      await pumpBuilder(tester,
          lockOverride: FantasyLockOverride.locked,
          initialSquad: fullSquad(),
          onOpenPlayer: opened.add,
          lockedWeek: lockedModel(
              fullSquad(chip: 'freeHit', captainId: 'Att One')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('squad_chip_Att One')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, ['Att One']);
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px, $brightness: the locked squad court fits, no '
          'overflow', (tester) async {
        await pumpLockedCourt(tester,
            saved: fullSquad(),
            size: const Size(360, 760),
            brightness: brightness,
            lockedWeek: lockedModel(fullSquad(chip: 'tripleCaptain'),
                chips: {'GK One': '16 pts', 'Bench Att': '2.5 pts'}));
        expect(tester.takeException(), isNull);
        await tester.dragUntilVisible(
            find.byKey(const ValueKey('squad_chip_Bench Att')),
            find.byType(Scrollable).first,
            const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Fix round 1: the hub drops the locked-week model at lock + 24 h while the
  // builder flips on its own 30 s ticker — no "waiting for kickoff" /
  // placeholder flash in between: the builder keeps the last model until it
  // is itself editable.
  group('the builder keeps the last locked-week model until it is editable',
      () {
    LockedWeekModel liveModel() => LockedWeekModel(
          view: const LockedWeekView.settled(weekPoints: 34, rank: 5),
          chipTexts: const {'GK One': '16 pts'},
          squad: fullSquad(chip: 'tripleCaptain'),
        );

    Widget builderApp(
            {required FantasyLockOverride lockOverride,
            LockedWeekModel? lockedWeek,
            bool readOnly = false}) =>
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: FantasySquadBuilder(
              config: FantasyConfig.futsalDefault(),
              lockOverride: lockOverride,
              gameweeks: const [],
              players: players,
              squadStates: squads.stream,
              initialSquad: fullSquad(),
              onSaveSquad: (_) async {},
              chipHistory: const {},
              lockedWeek: lockedWeek,
              readOnly: readOnly,
            ),
          ),
        );

    testWidgets(
        'the model going null while the court is still locked changes '
        'nothing on screen; once editable the strip is gone', (tester) async {
      tester.view.physicalSize = const Size(420, 1900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(builderApp(
          lockOverride: FantasyLockOverride.locked, lockedWeek: liveModel()));
      expect(find.text('Final · 34 pts · #5'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);

      // The hub dropped the model (editing reopened for it); the builder's
      // own clock has not flipped yet: nothing changes, no placeholder.
      await tester.pumpWidget(builderApp(
          lockOverride: FantasyLockOverride.locked, lockedWeek: null));
      expect(find.text('Final · 34 pts · #5'), findsOneWidget);
      expect(find.text('Locked'), findsNothing);
      expect(find.text('Locked · waiting for kickoff'), findsNothing);
      expect(find.text('16 pts'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);

      // The builder itself becomes editable: the locked header is gone.
      await tester.pumpWidget(builderApp(
          lockOverride: FantasyLockOverride.open, lockedWeek: null));
      expect(find.byKey(const ValueKey('locked_live_strip')), findsNothing);
      expect(find.byKey(const ValueKey('budget_bar')), findsOneWidget);
      expect(find.text('16 pts'), findsNothing);

      // A later lock never resurrects the old week's model.
      await tester.pumpWidget(builderApp(
          lockOverride: FantasyLockOverride.locked, lockedWeek: null));
      expect(find.text('Final · 34 pts · #5'), findsNothing);
      expect(find.text('Locked'), findsOneWidget);
    });

    // Final review I1: a read-only manager (no season pass) is never
    // editable, but the WEEK reopens for him too: the kept model goes with
    // the schedule, not with his (absent) edit rights.
    testWidgets(
        'read-only: once the schedule reopens, the court is the saved squad '
        'with no stale locked lines or chip', (tester) async {
      tester.view.physicalSize = const Size(420, 1900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(builderApp(
          readOnly: true,
          lockOverride: FantasyLockOverride.locked,
          lockedWeek: liveModel()));
      expect(find.text('16 pts'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);

      // The hub dropped the model; the clock has not flipped yet: kept.
      await tester.pumpWidget(builderApp(
          readOnly: true,
          lockOverride: FantasyLockOverride.locked,
          lockedWeek: null));
      expect(find.text('16 pts'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsOneWidget);

      // Editing reopens (for the schedule): the saved squad, no lines, ×2.
      await tester.pumpWidget(builderApp(
          readOnly: true,
          lockOverride: FantasyLockOverride.open,
          lockedWeek: null));
      expect(find.text('16 pts'), findsNothing);
      expect(find.textContaining(' pts'), findsNothing);
      expect(find.text('GK · \$5.0M · ×2'), findsOneWidget);
      expect(find.text('GK · \$5.0M · ×3'), findsNothing);
      expect(find.byKey(const ValueKey('chip_active_tripleCaptain')),
          findsNothing);
      // Still read-only: no budget bar, no Save.
      expect(find.byKey(const ValueKey('budget_bar')), findsNothing);
      expect(find.byKey(const ValueKey('squad_save')), findsNothing);
    });

    testWidgets('a NEW model replaces the kept one', (tester) async {
      tester.view.physicalSize = const Size(420, 1900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(builderApp(
          lockOverride: FantasyLockOverride.locked, lockedWeek: liveModel()));
      await tester.pumpWidget(builderApp(
          lockOverride: FantasyLockOverride.locked,
          lockedWeek: const LockedWeekModel(
              view: LockedWeekView.voided())));
      expect(find.text('Voided · this week counts 0'), findsOneWidget);
      expect(find.text('Final · 34 pts · #5'), findsNothing);
    });
  });
}
