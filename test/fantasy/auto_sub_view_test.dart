// Task 4 (substitute plan): the locked court shows the auto-sub. The pure
// display rule: a scored row that names the starter it replaced swaps the
// two picks' slots for display only; rows without the pairing move nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/auto_sub_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

void main() {
  final slots = buildSlots(FantasyConfig.futsalDefault());

  SquadPick pick(String id, FantasyPosition pos, {bool bench = false}) =>
      SquadPick(playerId: id, position: pos, priceTenths: 50, bench: bench);

  // GK, DEF, DEF, ATT, ATT | bench DEF, bench ATT.
  final squad = FantasySquad(picks: [
    pick('Kip Keeper', FantasyPosition.gk),
    pick('Dax Dunn', FantasyPosition.def),
    pick('Dov Dale', FantasyPosition.def),
    pick('Ari Ames', FantasyPosition.att),
    pick('Abe Arno', FantasyPosition.att),
    pick('Ben Def', FantasyPosition.def, bench: true),
    pick('Bo Att', FantasyPosition.att, bench: true),
  ], captainId: 'Ari Ames', viceId: 'Kip Keeper');

  final placed = picksToSlots(squad, slots);
  List<String?> ids(List<SquadPick?> picks) =>
      [for (final p in picks) p?.playerId];

  LiveSlot row(String id, {bool sub = false, String? replaces}) => LiveSlot(
      playerId: id,
      countedTenths: 40,
      multiplier: 1,
      autoSubbedIn: sub,
      replacesId: replaces);

  test('no rows: the picks come back as they are, nobody badged', () {
    final d = autoSubDisplay(slots, placed, const []);
    expect(ids(d.slotPicks), ids(placed));
    expect(d.subbedIn, isEmpty);
    expect(d.subbedOut, isEmpty);
  });

  test('one recorded pair swaps the two slots and returns both sets', () {
    final d = autoSubDisplay(slots, placed, [
      row('Dax Dunn'),
      row('Ben Def', sub: true, replaces: 'Dax Dunn'),
    ]);
    expect(ids(d.slotPicks), [
      'Kip Keeper',
      'Ben Def', // on the pitch in the starter's slot
      'Dov Dale',
      'Ari Ames',
      'Abe Arno',
      'Dax Dunn', // on the bench
      'Bo Att',
    ]);
    expect(d.subbedIn, {'Ben Def'});
    expect(d.subbedOut, {'Dax Dunn'});
    // Display only: the input list is untouched.
    expect(placed[1]!.playerId, 'Dax Dunn');
  });

  test(
      'two absent starters, one sub: only the recorded pair moves (Review '
      'Focus 3)', () {
    final d = autoSubDisplay(slots, placed, [
      row('Dax Dunn'),
      row('Dov Dale'), // also absent, nobody left to cover him
      row('Ben Def', sub: true, replaces: 'Dax Dunn'),
    ]);
    expect(ids(d.slotPicks).sublist(1, 3), ['Ben Def', 'Dov Dale']);
    expect(d.slotPicks[5]!.playerId, 'Dax Dunn');
    expect(d.subbedOut, {'Dax Dunn'});
    expect(d.subbedIn, {'Ben Def'});
  });

  test(
      'a sub scored before the pairing existed (no replacesId) moves nothing '
      'and is badged "came on" only (Review Focus 4)', () {
    final d = autoSubDisplay(slots, placed, [
      row('Dax Dunn'),
      row('Ben Def', sub: true),
    ]);
    expect(ids(d.slotPicks), ids(placed));
    expect(d.subbedIn, {'Ben Def'});
    expect(d.subbedOut, isEmpty);
  });

  test('rows naming a player not in the squad are ignored', () {
    final d = autoSubDisplay(slots, placed, [
      row('Stranger', sub: true, replaces: 'Dax Dunn'),
      row('Ghost', sub: true),
    ]);
    expect(ids(d.slotPicks), ids(placed));
    expect(d.subbedIn, isEmpty);
    expect(d.subbedOut, isEmpty);
  });

  test(
      'a pair that does not sit starter-on-pitch / sub-on-bench (or names a '
      'starter not in the squad) moves nothing; the sub keeps his badge', () {
    final notInSquad = autoSubDisplay(slots, placed, [
      row('Ben Def', sub: true, replaces: 'Nobody Here'),
    ]);
    expect(ids(notInSquad.slotPicks), ids(placed));
    expect(notInSquad.subbedIn, {'Ben Def'});
    expect(notInSquad.subbedOut, isEmpty);

    // A "replaces" pointing at another bench player is junk for the pitch.
    final benchToBench = autoSubDisplay(slots, placed, [
      row('Ben Def', sub: true, replaces: 'Bo Att'),
    ]);
    expect(ids(benchToBench.slotPicks), ids(placed));
    expect(benchToBench.subbedOut, isEmpty);
  });

  test('two recorded pairs (one per position) both move', () {
    final d = autoSubDisplay(slots, placed, [
      row('Ben Def', sub: true, replaces: 'Dov Dale'),
      row('Bo Att', sub: true, replaces: 'Ari Ames'),
    ]);
    expect(ids(d.slotPicks), [
      'Kip Keeper',
      'Dax Dunn',
      'Ben Def',
      'Bo Att',
      'Abe Arno',
      'Dov Dale',
      'Ari Ames',
    ]);
    expect(d.subbedIn, {'Ben Def', 'Bo Att'});
    expect(d.subbedOut, {'Dov Dale', 'Ari Ames'});
  });

  test('subbedOutChipText: the replaced starter reads Out, others unchanged',
      () {
    String? base(String id) => id == 'Dax Dunn' ? '0 pts' : '4 pts';
    final text = subbedOutChipText(base, {'Dax Dunn'})!;
    expect(text('Dax Dunn'), 'Out');
    expect(text('Ben Def'), '4 pts');
    // No one went off: the base callback as-is (null stays null).
    expect(identical(subbedOutChipText(base, const {}), base), isTrue);
    expect(subbedOutChipText(null, const {}), isNull);
  });
}
