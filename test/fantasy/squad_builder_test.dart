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
    Map<int, ChipHistoryEntry>? chipHistory,
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

    // Wildcard / Free Hit are visual-only until transfers (P3c).
    expect(find.text('Coming with transfers'), findsNWidgets(2));
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
}
