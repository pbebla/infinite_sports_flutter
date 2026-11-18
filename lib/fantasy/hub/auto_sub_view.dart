// The locked court's auto-sub picture (substitute plan, Task 4) — DISPLAY
// ONLY. Scoring already covers an absent starter with the first bench player
// of his position who played, at full points, and (since Task 3) the scored
// row of that bench player names the starter he replaced (`replaces` /
// `r` -> LiveSlot.replacesId). This turns those rows into what the court
// draws for the week: the sub on the pitch in the starter's slot, the
// starter on the bench, and who gets which corner badge. Nothing saved,
// scored or editable changes; the editable court never passes rows.
//
// Pure: both locked views (My Team's locked court, the leaderboard's squad
// viewer) call it with their LockedWeekModel's rows. No view computes
// pairings itself.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

/// What the court draws for a scored week.
///
/// For every row with a [LiveSlot.replacesId] whose starter stands in a
/// starter slot and whose bench player sits in a bench slot of [slots], the
/// two picks trade slot positions (a copy — [slotPicks] is untouched); the
/// bench player goes in `subbedIn` and the starter in `subbedOut`.
///
/// A row with [LiveSlot.autoSubbedIn] but no usable pairing (a week scored
/// before the pairing was recorded, or a pairing that does not fit the
/// squad on screen) moves nothing: its player, when in the squad, goes in
/// `subbedIn` only — never a wrong picture. Rows naming a player who is not
/// in the squad are ignored.
({List<SquadPick?> slotPicks, Set<String> subbedIn, Set<String> subbedOut})
    autoSubDisplay(
  List<SquadSlot> slots,
  List<SquadPick?> slotPicks,
  List<LiveSlot> rows,
) {
  final picks = List<SquadPick?>.of(slotPicks);
  final subbedIn = <String>{};
  final subbedOut = <String>{};
  if (rows.isEmpty) {
    return (slotPicks: picks, subbedIn: subbedIn, subbedOut: subbedOut);
  }

  int indexOf(String id) {
    for (var i = 0; i < picks.length && i < slots.length; i++) {
      if (picks[i]?.playerId == id) return i;
    }
    return -1;
  }

  for (final row in rows) {
    final replaced = row.replacesId;
    if (!row.autoSubbedIn && replaced == null) continue;
    final sub = indexOf(row.playerId);
    if (sub < 0) continue; // not in the squad on screen
    if (replaced != null && !subbedOut.contains(replaced)) {
      final starter = indexOf(replaced);
      if (starter >= 0 && slots[sub].bench && !slots[starter].bench) {
        final pick = picks[sub];
        picks[sub] = picks[starter];
        picks[starter] = pick;
        subbedIn.add(row.playerId);
        subbedOut.add(replaced);
        continue;
      }
    }
    // Scored as a sub but without a pairing that fits: badge only.
    if (row.autoSubbedIn) subbedIn.add(row.playerId);
  }
  return (slotPicks: picks, subbedIn: subbedIn, subbedOut: subbedOut);
}

/// The chip text for the locked views: a starter who went off reads `Out`
/// whatever his status source says (a settled week passes "done" for
/// everyone, which would read "0 pts"); everyone else keeps [base]'s text.
/// With nobody off, [base] itself.
String? Function(String playerId)? subbedOutChipText(
  String? Function(String playerId)? base,
  Set<String> subbedOut,
) {
  if (subbedOut.isEmpty) return base;
  return (id) => subbedOut.contains(id) ? 'Out' : base?.call(id);
}
