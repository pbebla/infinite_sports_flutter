// P3c — the shared SquadDraftController both tabs edit: stream adoption
// (dirty drafts never overwritten), market add placement (starters before
// bench), removals with armband messages, config reshapes and the
// saved-clean cycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';

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
}
