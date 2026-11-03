// P3c — the shared SquadDraftController both tabs edit: stream adoption
// (dirty drafts never overwritten), market add placement (starters before
// bench), removals with armband messages, config reshapes and the
// saved-clean cycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_preview.dart';

FantasyPlayer player(String name, FantasyPosition pos, int price) =>
    FantasyPlayer(
        name: name,
        position: pos,
        priceTenths: price,
        eligible: true,
        teamName: 'Team A');

SquadPick pick(String id, FantasyPosition pos,
        {int price = 50, bool bench = false}) =>
    SquadPick(playerId: id, position: pos, priceTenths: price, bench: bench);

FantasySquad fullSquad({String captainId = 'GK One', String viceId = 'Def One'}) =>
    FantasySquad(
      picks: [
        pick('GK One', FantasyPosition.gk),
        pick('Def One', FantasyPosition.def),
        pick('Def Two', FantasyPosition.def),
        pick('Att One', FantasyPosition.att),
        pick('Att Two', FantasyPosition.att),
        pick('Bench Def', FantasyPosition.def, bench: true),
        pick('Bench Att', FantasyPosition.att, bench: true),
      ],
      captainId: captainId,
      viceId: viceId,
    );

void main() {
  final cfg = FantasyConfig.futsalDefault();

  test('adopts the initial squad clean; notifies listeners on change', () {
    final draft = SquadDraftController(config: cfg, initial: fullSquad());
    expect(draft.dirty, isFalse);
    expect(draft.playerIds, hasLength(7));
    expect(draft.captainId, 'GK One');
    expect(draft.spentTenths, 350);

    var notified = 0;
    draft.addListener(() => notified++);
    draft.setChip('benchBoost');
    expect(notified, 1);
    expect(draft.dirty, isTrue);
    expect(draft.chip, 'benchBoost');
  });

  test('stream adoptions overwrite a CLEAN draft only; markSaved re-arms',
      () {
    final draft = SquadDraftController(config: cfg);
    draft.adoptFromStream(fullSquad());
    expect(draft.playerIds, contains('GK One'));

    // Dirty: a remote emit must NOT clobber the in-progress edit.
    draft.removePlayer('Att One');
    expect(draft.dirty, isTrue);
    draft.adoptFromStream(fullSquad());
    expect(draft.playerIds, isNot(contains('Att One')));

    // Saved: clean again — the echo (or a remote write) adopts normally.
    draft.markSaved();
    expect(draft.dirty, isFalse);
    draft.adoptFromStream(fullSquad(captainId: 'Att Two'));
    expect(draft.playerIds, contains('Att One'));
    expect(draft.captainId, 'Att Two');
  });

  test('addPlayer fills starters before the bench, same position', () {
    final draft = SquadDraftController(config: cfg);
    expect(draft.addPlayer(player('Def A', FantasyPosition.def, 50)), isTrue);
    expect(draft.addPlayer(player('Def B', FantasyPosition.def, 50)), isTrue);
    expect(draft.addPlayer(player('Def C', FantasyPosition.def, 50)), isTrue);
    // Futsal: 2 starter DEF + 1 bench DEF — the third lands on the bench.
    final benchIds = [
      for (var i = 0; i < draft.slots.length; i++)
        if (draft.slots[i].bench && draft.picks[i] != null)
          draft.picks[i]!.playerId
    ];
    expect(benchIds, ['Def C']);
    expect(draft.dirty, isTrue);
    // No DEF slot left — a fourth is refused (the UI disables first).
    expect(draft.addPlayer(player('Def D', FantasyPosition.def, 50)), isFalse);
    // GK slot untouched by DEF fills.
    expect(draft.addPlayer(player('GK A', FantasyPosition.gk, 50)), isTrue);
  });

  test('removePlayer returns the armband-loss message and clears the band',
      () {
    final draft = SquadDraftController(config: cfg, initial: fullSquad());
    expect(draft.removePlayer('GK One'),
        'Your captain left the squad — choose a new captain.');
    expect(draft.captainId, isNull);
    expect(draft.removePlayer('Def One'),
        'Your vice-captain left the squad — choose a new vice-captain.');
    expect(draft.viceId, isNull);
    expect(draft.removePlayer('Att One'), isNull);
    expect(draft.removePlayer('Nobody'), isNull);
    expect(draft.playerIds, hasLength(4));
  });

  test('captain/vice assignment swaps bands, never loses one silently', () {
    final draft = SquadDraftController(config: cfg, initial: fullSquad());
    // Captaining the current vice swaps the bands.
    draft.makeCaptain('Def One');
    expect(draft.captainId, 'Def One');
    expect(draft.viceId, 'GK One');
    draft.makeVice('Att One');
    expect(draft.viceId, 'Att One');
    expect(draft.captainId, 'Def One');
  });

  test('syncConfig reshapes slots and re-maps picks; non-formation tweaks '
      'stay silent', () {
    final draft = SquadDraftController(config: cfg, initial: fullSquad());
    var notified = 0;
    draft.addListener(() => notified++);

    // Budget-only change: silent reference swap.
    final retuned = FantasyConfig.fromMap(
        FantasyConfig.futsalDefault().toMap()..['budgetTenths'] = 600);
    draft.syncConfig(retuned);
    expect(notified, 0);
    expect(draft.config.budgetTenths, 600);

    // Formation shrink: slots rebuild; the overflow pick no longer fits a
    // slot and moves to the "Needs a new spot" list — never silently lost.
    final shrunk = FantasyConfig.fromMap(
        FantasyConfig.futsalDefault().toMap()..['startersAtt'] = 1);
    draft.syncConfig(shrunk);
    expect(notified, 1);
    expect(draft.slots, hasLength(6));
    expect(draft.picks.map((p) => p?.playerId), isNot(contains('Att Two')));
    expect(draft.unplaced.map((p) => p.playerId), ['Att Two']);
  });

  group('holder protection (spec §3): a pick whose position changed', () {
    /// The server re-labelled GK One as a DEF (position change): no slot
    /// fits him any more and the GK slot is empty.
    FantasySquad relabelled() => FantasySquad(
          picks: [
            pick('GK One', FantasyPosition.def, price: 80),
            pick('Def One', FantasyPosition.def),
            pick('Def Two', FantasyPosition.def),
            pick('Att One', FantasyPosition.att),
            pick('Att Two', FantasyPosition.att),
            pick('Bench Def', FantasyPosition.def, bench: true),
            pick('Bench Att', FantasyPosition.att, bench: true),
          ],
          captainId: 'GK One',
          viceId: 'Def One',
        );

    test('lands in unplaced (still owned, still paid for), not dropped', () {
      final draft = SquadDraftController(config: cfg);
      draft.adoptFromStream(relabelled());
      expect(draft.unplaced.map((p) => p.playerId), ['GK One']);
      expect(draft.picks[0], isNull);
      expect(draft.firstEmptySlot, 0);
      expect(draft.playerIds, contains('GK One'));
      expect(draft.spentTenths, 80 + 6 * 50);
      expect(draft.squad.picks, hasLength(7)); // nothing vanishes on save
      expect(draft.dirty, isFalse);
    });

    test('Remove drops him, says the armband went, marks the draft dirty',
        () {
      final draft = SquadDraftController(config: cfg, initial: relabelled());
      expect(draft.removeUnplaced('GK One'),
          'Your captain left the squad — choose a new captain.');
      expect(draft.unplaced, isEmpty);
      expect(draft.captainId, isNull);
      expect(draft.dirty, isTrue);
      expect(draft.removeUnplaced('Nobody'), isNull);
    });

    test('Swap fills the hole with the replacement; removePlayer finds him too',
        () {
      final draft = SquadDraftController(config: cfg, initial: relabelled());
      draft.swapUnplaced('GK One', draft.firstEmptySlot!,
          pick('GK New', FantasyPosition.gk, price: 45));
      expect(draft.unplaced, isEmpty);
      expect(draft.picks[0]!.playerId, 'GK New');
      expect(draft.squad.picks, hasLength(7));

      final other = SquadDraftController(config: cfg, initial: relabelled());
      other.removePlayer('GK One'); // the market's Remove
      expect(other.unplaced, isEmpty);
    });
  });

  group('one-week chips (S15 rehearsal Bug 2): the server switches it off',
      () {
    test('a clean draft adopts the cleared chip — no active chip shown', () {
      final draft = SquadDraftController(
          config: cfg,
          initial: FantasySquad(
              picks: fullSquad().picks,
              captainId: 'GK One',
              viceId: 'Def One',
              chip: 'benchBoost'));
      expect(draft.chip, 'benchBoost');
      draft.adoptFromStream(fullSquad()); // rollover removed Squads/<uid>/chip
      expect(draft.chip, isNull);
      expect(draft.squad.chip, isNull);
    });

    test('a dirty draft still takes the switch-off unless the user toggled '
        'the chip', () {
      final armed = FantasySquad(
          picks: fullSquad().picks,
          captainId: 'GK One',
          viceId: 'Def One',
          chip: 'benchBoost');
      // Dirty since before the lock (an armband edit), chip untouched.
      final stale = SquadDraftController(config: cfg, initial: armed);
      stale.makeCaptain('Att One');
      stale.adoptFromStream(fullSquad());
      expect(stale.chip, isNull); // the next save can't re-arm it
      expect(stale.captainId, 'Att One'); // the edit itself survives
      expect(stale.dirty, isTrue);

      // The user deliberately picked a chip in this draft: that intent wins.
      final chosen = SquadDraftController(config: cfg, initial: armed);
      chosen.setChip('tripleCaptain');
      chosen.adoptFromStream(fullSquad());
      expect(chosen.chip, 'tripleCaptain');
    });
  });

  test('setPickAt swaps and reports a lost armband', () {
    final draft = SquadDraftController(config: cfg, initial: fullSquad());
    // Slot 0 is the GK starter wearing the C.
    final message =
        draft.setPickAt(0, pick('GK New', FantasyPosition.gk, price: 45));
    expect(message, 'Your captain left the squad — choose a new captain.');
    expect(draft.captainId, isNull);
    expect(draft.playerIds, contains('GK New'));
    expect(draft.dirty, isTrue);
  });

  // Squad hardening (audit I3): a save the server refused after the lock.
  group('revertToStored', () {
    test('drops the edits and goes back to the stored squad, clean', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.makeCaptain('Att One');
      d.removeAt(4); // Att Two out
      expect(d.dirty, isTrue);
      d.revertToStored();
      expect(d.dirty, isFalse);
      expect(d.captainId, 'GK One');
      expect(d.playerIds, contains('Att Two'));
    });

    test('goes back to the LATEST stored squad (a remote emit while dirty)', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.makeCaptain('Att One');
      // The stored squad changed meanwhile (another device saved): the
      // dirty draft keeps the edit, but remembers what is stored.
      d.adoptFromStream(fullSquad(captainId: 'Def Two', viceId: 'Att Two'));
      expect(d.captainId, 'Att One');
      d.revertToStored();
      expect(d.captainId, 'Def Two');
      expect(d.viceId, 'Att Two');
      expect(d.dirty, isFalse);
    });

    test('after a successful save, the saved squad is the stored one', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.makeCaptain('Att One');
      d.markSaved();
      d.makeCaptain('Def Two');
      d.revertToStored();
      expect(d.captainId, 'Att One');
    });

    test('nothing stored yet (first squad): back to an empty draft', () {
      final d = SquadDraftController(config: cfg);
      d.addPlayer(player('Gus Glove', FantasyPosition.gk, 45));
      d.revertToStored();
      expect(d.playerIds, isEmpty);
      expect(d.dirty, isFalse);
    });
  });

  // FPL selling (spec §4): the draft charges what the server will charge.
  // Last week's squad is fullSquad() with Att One bought at 80; today Att
  // One trades at 90 (a riser) and Att Two at 40 (a faller, bought at 50).
  group('FPL selling money', () {
    const paid = {
      'GK One': 50,
      'Def One': 50,
      'Def Two': 50,
      'Att One': 80,
      'Att Two': 50,
      'Bench Def': 50,
      'Bench Att': 50,
    };
    const current = {
      'GK One': 50,
      'Def One': 50,
      'Def Two': 50,
      'Att One': 90,
      'Att Two': 40,
      'Bench Def': 50,
      'Bench Att': 50,
      'New Guy': 70,
    };

    FantasySquad heldSquad({int attOnePrice = 80}) => FantasySquad(
          picks: [
            pick('GK One', FantasyPosition.gk),
            pick('Def One', FantasyPosition.def),
            pick('Def Two', FantasyPosition.def),
            pick('Att One', FantasyPosition.att, price: attOnePrice),
            pick('Att Two', FantasyPosition.att),
            pick('Bench Def', FantasyPosition.def, bench: true),
            pick('Bench Att', FantasyPosition.att, bench: true),
          ],
          captainId: 'GK One',
          viceId: 'Def One',
        );

    SaleBaselineState sale({int forGw = 5, int realized = 0}) =>
        SaleBaselineState(
          baseline: SaleBaseline(
              forGw: forGw, prices: paid, realizedTenths: realized),
          loaded: true,
        );

    SquadDraftController draftWith({
      FantasySquad? squad,
      SaleBaselineState? state,
      int? editingGw = 5,
    }) {
      final d =
          SquadDraftController(config: cfg, initial: squad ?? heldSquad());
      d.setSaleContext(
          sale: state ?? sale(), currentPrices: current, editingGw: editingGw);
      return d;
    }

    SquadPick owned(SquadDraftController d, String id) =>
        [...d.picks.whereType<SquadPick>(), ...d.unplaced]
            .firstWhere((p) => p.playerId == id);

    test('re-adding a sold baseline player restores his baseline price', () {
      final d = draftWith(state: sale(realized: 7));
      expect(d.realizedTenths, 7);
      d.removePlayer('Att One'); // sold at 85: +5
      expect(d.realizedTenths, 12);
      expect(d.addPlayer(player('Att One', FantasyPosition.att, 90)), isTrue);
      expect(owned(d, 'Att One').priceTenths, 80);
      expect(d.realizedTenths, 7); // no sale, no profit
      expect(d.spentTenths, 380);
    });

    test('a held pick saved at another price counts at the baseline price',
        () {
      final d = draftWith(squad: heldSquad(attOnePrice: 90));
      expect(owned(d, 'Att One').priceTenths, 90); // as stored
      expect(d.priceOfPick(owned(d, 'Att One')), 80);
      expect(d.spentTenths, 6 * 50 + 80);
      // A pick that is not in the baseline keeps its own price (here also
      // today's price — see the market-floor test below).
      expect(
          d.priceOfPick(pick('New Guy', FantasyPosition.att, price: 70)), 70);
    });

    test('selling a riser grows the room', () {
      final d = draftWith();
      expect(d.availableTenths, 500);
      final before = d.remainingTenths;
      expect(before, 500 - 380);
      d.removePlayer('Att One');
      expect(d.remainingTenths, before + 85); // his 80 back + half the rise
      expect(d.availableTenths, 505);
    });

    test('selling a faller takes the full drop', () {
      final d = draftWith();
      final before = d.remainingTenths;
      d.removePlayer('Att Two');
      expect(d.realizedTenths, -10);
      expect(d.remainingTenths, before + 40);
    });

    test('remainingIfRemovedTenths matches remove-then-read', () {
      for (final id in ['Att One', 'Att Two', 'GK One']) {
        final d = draftWith();
        final predicted = d.remainingIfRemovedTenths(owned(d, id));
        d.removePlayer(id);
        expect(d.remainingTenths, predicted, reason: id);
      }
      // A pick bought this week (no baseline price): his price comes back,
      // and nobody is sold.
      final d = draftWith();
      d.removePlayer('Att Two');
      d.addPlayer(player('New Guy', FantasyPosition.att, 70));
      final predicted = d.remainingIfRemovedTenths(owned(d, 'New Guy'));
      d.removePlayer('New Guy');
      expect(d.remainingTenths, predicted);
      // No baseline at all (a first squad): the plain budget math.
      final first = SquadDraftController(config: cfg, initial: fullSquad());
      first.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: current,
          editingGw: 5);
      final p = owned(first, 'Att One');
      final room = first.remainingIfRemovedTenths(p);
      expect(room, 500 - 300);
      first.removePlayer('Att One');
      expect(first.remainingTenths, room);
    });

    test('stale baseline is not moneyReady', () {
      expect(
          draftWith(state: sale(forGw: 4), editingGw: 5).moneyReady, isFalse);
      expect(draftWith(state: sale(forGw: 5), editingGw: 5).moneyReady, isTrue);
      // The schedule is not known yet: a baseline can't be judged current.
      expect(draftWith(editingGw: null).moneyReady, isFalse);
      // Absent node + loaded = a first squad: never blocked.
      expect(
          draftWith(state: const SaleBaselineState(loaded: true), editingGw: 5)
              .moneyReady,
          isTrue);
      expect(
          draftWith(
                  state: const SaleBaselineState(loaded: true), editingGw: null)
              .moneyReady,
          isTrue);
      // Degraded (the read failed with nothing known) or not loaded yet.
      expect(
          draftWith(
                  state: const SaleBaselineState(degraded: true), editingGw: 5)
              .moneyReady,
          isFalse);
      expect(
          draftWith(state: const SaleBaselineState(), editingGw: 5).moneyReady,
          isFalse);
      // No sale context at all (nothing fed yet).
      expect(SquadDraftController(config: cfg).moneyReady, isFalse);
    });

    test('a new player costs today\'s price', () {
      final d = draftWith();
      final guy = player('New Guy', FantasyPosition.att, 70);
      expect(d.buyPriceOf(guy), 70);
      final p = d.newPick(guy, bench: true);
      expect(p.playerId, 'New Guy');
      expect(p.position, FantasyPosition.att);
      expect(p.priceTenths, 70);
      expect(p.bench, isTrue);
      // A baseline player is bought back at his baseline price.
      expect(d.buyPriceOf(player('Att One', FantasyPosition.att, 90)), 80);
      expect(
          d.newPick(player('Att One', FantasyPosition.att, 90), bench: false)
              .priceTenths,
          80);
      // No baseline (first squad / not loaded): always today's price.
      final first = SquadDraftController(config: cfg);
      expect(first.buyPriceOf(player('Att One', FantasyPosition.att, 90)), 90);
    });

    test('sellPriceOf: the FPL sell price, only for a baseline player', () {
      final d = draftWith();
      expect(d.sellPriceOf('Att One'), 85); // 80 -> 90 sells 85
      expect(d.sellPriceOf('Att Two'), 40); // 50 -> 40 sells 40
      expect(d.sellPriceOf('GK One'), 50);
      expect(d.sellPriceOf('New Guy'), isNull);
      // Gone from the market (or priced <= 0): sells for what was paid —
      // the server adds 0 for him.
      d.setSaleContext(
          sale: sale(), currentPrices: const {'Att One': 0}, editingGw: 5);
      expect(d.sellPriceOf('Att One'), 80);
      expect(d.sellPriceOf('Att Two'), 50);
    });

    test('setSaleContext notifies once per change, not on a repeat', () {
      final d = SquadDraftController(config: cfg, initial: heldSquad());
      var notified = 0;
      d.addListener(() => notified++);
      final s = sale();
      d.setSaleContext(sale: s, currentPrices: current, editingGw: 5);
      expect(notified, 1);
      d.setSaleContext(sale: s, currentPrices: Map.of(current), editingGw: 5);
      expect(notified, 1);
      d.setSaleContext(sale: s, currentPrices: current, editingGw: 6);
      expect(notified, 2);
      // Last week's prices are part of the context too.
      d.setSaleContext(
          sale: s,
          currentPrices: current,
          lastWeekPrices: const {'Att One': 70},
          editingGw: 6);
      expect(notified, 3);
      d.setSaleContext(
          sale: s,
          currentPrices: current,
          lastWeekPrices: const {'Att One': 70},
          editingGw: 6);
      expect(notified, 3);
    });

    // Server parity (squad_integrity.ts judgeSale): a NEW (non-baseline)
    // pick is charged max(0, client price, min(current, last week's
    // price)) — PriceHistory/<editingGw − 1>, absent → current.
    test('a carried non-baseline pick counts at the server\'s market floor',
        () {
      final d = SquadDraftController(config: cfg, initial: heldSquad());
      final carried = pick('Carry On', FantasyPosition.att, price: 60);
      d.setSaleContext(
          sale: sale(),
          currentPrices: const {...current, 'Carry On': 80},
          lastWeekPrices: const {'Carry On': 70},
          editingGw: 5);
      expect(d.priceOfPick(carried), 70);
      // No price history for him: the floor is today's price.
      d.setSaleContext(
          sale: sale(),
          currentPrices: const {...current, 'Carry On': 80},
          lastWeekPrices: null,
          editingGw: 5);
      expect(d.priceOfPick(carried), 80);
      // Gone from the market: his own price (the server's floor is 0).
      d.setSaleContext(sale: sale(), currentPrices: current, editingGw: 5);
      expect(d.priceOfPick(carried), 60);
      // A pick made this window at today's price is unchanged.
      d.setSaleContext(
          sale: sale(),
          currentPrices: current,
          lastWeekPrices: const {'New Guy': 60},
          editingGw: 5);
      final fresh = d.newPick(player('New Guy', FantasyPosition.att, 70),
          bench: false);
      expect(d.priceOfPick(fresh), 70);
      // A baseline pick stays at his baseline price whatever the floor.
      d.setSaleContext(
          sale: sale(),
          currentPrices: current,
          lastWeekPrices: const {'Att One': 100},
          editingGw: 5);
      expect(d.priceOfPick(owned(d, 'Att One')), 80);
    });

    test('moneyReady waits for the market prices (null = not loaded)', () {
      final d = SquadDraftController(config: cfg, initial: heldSquad());
      d.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: null,
          editingGw: 5);
      expect(d.moneyReady, isFalse);
      d.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: current,
          editingGw: 5);
      expect(d.moneyReady, isTrue);
      // An empty market is a loaded one.
      d.setSaleContext(
          sale: const SaleBaselineState(loaded: true),
          currentPrices: const {},
          editingGw: 5);
      expect(d.moneyReady, isTrue);
    });

    test('remainingIfRemovedTenths: the pick must be owned by the draft', () {
      final d = draftWith();
      expect(
          () => d.remainingIfRemovedTenths(
              pick('Not Mine', FantasyPosition.att, price: 70)),
          throwsA(isA<AssertionError>()));
    });

    test('addCostOf: what adding him takes from the room', () {
      // A new player: today's price.
      final d = draftWith();
      expect(d.addCostOf(player('New Guy', FantasyPosition.att, 70)), 70);

      // A sold riser (paid 80, now 90): re-adding undoes the sale — the
      // room drops by what selling him banked (85), not by 80 or 90.
      final riser = draftWith();
      riser.removePlayer('Att One');
      final attOne = player('Att One', FantasyPosition.att, 90);
      expect(riser.addCostOf(attOne), 85);
      final before = riser.remainingTenths;
      riser.addPlayer(attOne);
      expect(riser.remainingTenths, before - 85);

      // A sold faller (paid 50, now 40): undoing his sale costs 40.
      final faller = draftWith();
      faller.removePlayer('Att Two');
      final attTwo = player('Att Two', FantasyPosition.att, 40);
      expect(faller.addCostOf(attTwo), 40);
      final room = faller.remainingTenths;
      faller.addPlayer(attTwo);
      expect(faller.remainingTenths, room - 40);
    });

    test('addCostOf: the player must not already be owned', () {
      final d = draftWith();
      expect(() => d.addCostOf(player('Att One', FantasyPosition.att, 90)),
          throwsA(isA<AssertionError>()));
    });
  });

  group('saleEditingGameweek', () {
    // GW n locks Oct 4 + 7(n-1), 22:00 UTC.
    final gws = [
      for (var n = 1; n <= 4; n++)
        Gameweek(
          number: n,
          date: '10${(4 + 7 * (n - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 4 + 7 * (n - 1), 22),
          opensUtc: null,
        ),
    ];
    const b = SaleBaseline(forGw: 3, prices: {'A': 80}, realizedTenths: 0);

    test('auto: the first gameweek whose lock is still ahead', () {
      // Oct 19 is past GW3's lock (Oct 18 22:00): editing GW4.
      expect(
          saleEditingGameweek(
              gameweeks: gws,
              lockOverride: FantasyLockOverride.auto,
              baseline: b,
              nowUtc: DateTime.utc(2026, 10, 19, 12)),
          4);
      expect(
          saleEditingGameweek(
              gameweeks: gws,
              lockOverride: FantasyLockOverride.locked,
              baseline: b,
              nowUtc: DateTime.utc(2026, 10, 17, 12)),
          3);
    });

    test('schedule unknown: null (a baseline is not judged current)', () {
      expect(
          saleEditingGameweek(
              gameweeks: null,
              lockOverride: FantasyLockOverride.auto,
              baseline: b,
              nowUtc: DateTime.utc(2026, 10, 17, 12)),
          isNull);
    });

    test('the owner\'s open override: the stored baseline is the week being '
        'edited (the lock sweep stands down, so nothing can move it)', () {
      expect(
          saleEditingGameweek(
              gameweeks: gws,
              lockOverride: FantasyLockOverride.open,
              baseline: b,
              nowUtc: DateTime.utc(2026, 10, 19, 12)),
          3);
      // No baseline: the clock's week (nothing to judge anyway).
      expect(
          saleEditingGameweek(
              gameweeks: gws,
              lockOverride: FantasyLockOverride.open,
              baseline: null,
              nowUtc: DateTime.utc(2026, 10, 19, 12)),
          4);
    });
  });

  group('transfers (transferPreview over the draft picks and chip)', () {
    // The squad the manager came into gameweek 5 with: fullSquad()'s ids.
    final held = [for (final p in fullSquad().picks) p.playerId];
    TransferStateView view({int? free = 2, List<String>? countFrom}) =>
        TransferStateView(
            free: free, countFromGw: 5, countFrom: countFrom ?? held);

    SquadDraftController draftWith() {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.setTransferContext(state: view(), answered: true, editingGw: 5);
      return d;
    }

    test('nothing answered yet → notReady, never a first team', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      expect(d.transferPreview.kind, TransferPreviewKind.notReady);
    });

    test('an untouched draft has used nothing', () {
      final p = draftWith().transferPreview;
      expect(p.kind, TransferPreviewKind.counted);
      expect((p.used, p.free, p.costPoints), (0, 2, 0));
    });

    test('counts the CURRENT picks: a swap, then three more', () {
      final d = draftWith();
      d.removePlayer('Att One');
      d.addPlayer(player('Att New', FantasyPosition.att, 50));
      expect(d.transferPreview.used, 1);
      d.removePlayer('Def One');
      d.addPlayer(player('Def New', FantasyPosition.def, 50));
      d.removePlayer('Def Two');
      d.addPlayer(player('Def New2', FantasyPosition.def, 50));
      final p = d.transferPreview;
      expect((p.used, p.free, p.costPoints), (3, 2, 4));
    });

    test('a removed player with no replacement yet costs nothing', () {
      final d = draftWith();
      d.removePlayer('Att One');
      expect(d.transferPreview.used, 0);
    });

    test('every owned pick that is not in the baseline counts', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.setTransferContext(
          state: view(countFrom: ['GK One']), answered: true, editingGw: 5);
      // Six of the seven are not in a one-player baseline.
      expect(d.transferPreview.used, 6);
    });

    test('the draft chip lifts the count: Wildcard, then off again', () {
      final d = draftWith();
      d.removePlayer('Att One');
      d.addPlayer(player('Att New', FantasyPosition.att, 50));
      d.setChip('wildcard');
      expect(d.transferPreview.kind, TransferPreviewKind.unlimited);
      expect(d.transferPreview.costPoints, 0);
      d.setChip(null);
      expect(d.transferPreview.kind, TransferPreviewKind.counted);
      expect(d.transferPreview.used, 1);
    });

    test('a free swap sold this week is not counted', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.setTransferContext(
          state: TransferStateView(
              free: 2,
              countFromGw: 5,
              countFrom: held,
              freeSwapsGw: 5,
              freeSwaps: const ['Att One']),
          answered: true,
          editingGw: 5);
      d.removePlayer('Att One');
      d.addPlayer(player('Att New', FantasyPosition.att, 50));
      expect(d.transferPreview.used, 0);
    });

    test('a stale baseline week, or no week yet → notReady', () {
      final d = draftWith();
      d.setTransferContext(state: view(), answered: true, editingGw: 6);
      expect(d.transferPreview.kind, TransferPreviewKind.notReady);
      d.setTransferContext(state: view(), answered: true, editingGw: null);
      expect(d.transferPreview.kind, TransferPreviewKind.notReady);
    });

    test('a failed read (answered false) is notReady even after an answer',
        () {
      final d = draftWith();
      d.setTransferContext(state: null, answered: false, editingGw: 5);
      expect(d.transferPreview.kind, TransferPreviewKind.notReady);
    });

    test('an absent node, answered → firstTeam', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      d.setTransferContext(state: null, answered: true, editingGw: 5);
      expect(d.transferPreview.kind, TransferPreviewKind.firstTeam);
    });

    test('setTransferContext notifies once per change, not on a repeat', () {
      final d = SquadDraftController(config: cfg, initial: fullSquad());
      var notified = 0;
      d.addListener(() => notified++);
      d.setTransferContext(state: view(), answered: true, editingGw: 5);
      expect(notified, 1);
      // A fresh but EQUAL view (every stream emit builds a new object).
      d.setTransferContext(
          state: view(countFrom: List.of(held)), answered: true, editingGw: 5);
      expect(notified, 1);
      d.setTransferContext(state: view(), answered: true, editingGw: 6);
      expect(notified, 2);
      d.setTransferContext(state: view(free: 3), answered: true, editingGw: 6);
      expect(notified, 3);
      d.setTransferContext(state: view(free: 3), answered: false, editingGw: 6);
      expect(notified, 4);
    });

    test('edits and stream adoptions keep the transfer context', () {
      final d = draftWith();
      d.adoptFromStream(fullSquad(captainId: 'Att Two'));
      expect(d.transferPreview.kind, TransferPreviewKind.counted);
      d.revertToStored();
      expect(d.transferPreview.kind, TransferPreviewKind.counted);
    });
  });
}
