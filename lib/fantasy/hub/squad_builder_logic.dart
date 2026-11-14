// Pure logic for the My Team squad builder (P3b) — no Flutter imports, fully
// unit-tested (test/fantasy/squad_builder_logic_test.dart). The widgets in
// squad_builder.dart / court_view.dart stay thin over these helpers: slot
// layout, draft<->engine mapping, picker filtering, affordability, armband
// reassignment, lock state and the human-sentence rendering of the engine's
// validateSquad issues.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';

/// One fixed slot of the builder. The formation is slots-first (a GK slot can
/// only ever hold a GK), so the engine's formation issue can only mean
/// "slots still empty" here.
class SquadSlot {
  const SquadSlot({required this.position, required this.bench});
  final FantasyPosition position;
  final bool bench;
}

/// The builder's slot order: GK, DEF…, ATT… starters, then the bench
/// (DEF…, ATT…) — counts straight from the live config.
List<SquadSlot> buildSlots(FantasyConfig cfg) => [
      for (var i = 0; i < cfg.startersGk; i++)
        const SquadSlot(position: FantasyPosition.gk, bench: false),
      for (var i = 0; i < cfg.startersDef; i++)
        const SquadSlot(position: FantasyPosition.def, bench: false),
      for (var i = 0; i < cfg.startersAtt; i++)
        const SquadSlot(position: FantasyPosition.att, bench: false),
      for (var i = 0; i < cfg.benchDef; i++)
        const SquadSlot(position: FantasyPosition.def, bench: true),
      for (var i = 0; i < cfg.benchAtt; i++)
        const SquadSlot(position: FantasyPosition.att, bench: true),
    ];

/// A Team of the Week laid onto the court: the config's STARTER slots only
/// (no bench — the Dream Team is five), each dream player in the first empty
/// slot of his position (extras from a config shrink are dropped), plus his
/// week points by name. Shared by the Dream Team card and its share image so
/// the two can never disagree.
({
  List<SquadSlot> slots,
  List<SquadPick?> slotPicks,
  Map<String, int> pointsByName,
}) dreamTeamCourt(FantasyConfig cfg, FantasyDreamTeam team) {
  final slots = [
    for (final slot in buildSlots(cfg))
      if (!slot.bench) slot,
  ];
  final slotPicks = List<SquadPick?>.filled(slots.length, null);
  for (final player in team.players) {
    for (var i = 0; i < slots.length; i++) {
      if (slotPicks[i] == null && slots[i].position == player.position) {
        slotPicks[i] = SquadPick(
          playerId: player.name,
          position: player.position,
          priceTenths: 0, // hidden: the court renders with showPrices false
        );
        break;
      }
    }
  }
  return (
    slots: slots,
    slotPicks: slotPicks,
    pointsByName: {for (final p in team.players) p.name: p.points},
  );
}

/// Court coordinates (0..1 fractions) for the STARTER slots, aligned with
/// [buildSlots] order: GK row near the top goal, DEF mid, ATT low. Each row
/// spreads its slots evenly.
List<({double x, double y})> starterOffsets(FantasyConfig cfg) {
  final out = <({double x, double y})>[];
  // [spread] = half the row's total x-width (owner feedback: defenders and
  // attackers were huddled too close; GK sat too far off the goal).
  void row(int count, double y, double spread) {
    if (count == 1) {
      out.add((x: 0.5, y: y));
      return;
    }
    for (var i = 0; i < count; i++) {
      out.add((x: 0.5 - spread + (2 * spread) * i / (count - 1), y: y));
    }
  }

  // Rows as far apart as the frame allows (release report #10: at 360 px the
  // old 0.02 / 0.44 / 0.87 rows let a 2-line name box run into the photos
  // of the row below). After pitchAssetPerspective these land at ~0 / 0.5 /
  // ~1 of the court's height: the GK chip tops out at the far goal, the ATT
  // chip bottoms out at the near edge, DEF sits midway — and
  // [courtHeightFor] grows the court whenever even that is not a full chip
  // apart (narrow phones, large text).
  row(cfg.startersGk, kStarterRowGkY, 0);
  row(cfg.startersDef, kStarterRowDefY, 0.24);
  row(cfg.startersAtt, kStarterRowAttY, 0.26);
  return out;
}

/// Flat-y of the three starter rows ([starterOffsets]); outside 0..1 on
/// purpose so the asset mapping puts GK / ATT on the frame's edges.
const double kStarterRowGkY = -0.06;
const double kStarterRowDefY = 0.5;
const double kStarterRowAttY = 1.06;

/// The court's height for [width]: the pitch's natural height
/// (`width / aspect`), grown just enough that consecutive rows — whose
/// chips are placed by [Align] at [rowFractions] of (height − chip) — sit
/// at least a whole [chipHeight] + [gap] apart, so a name box never covers
/// the next row's photo (release report #10).
double courtHeightFor({
  required double width,
  required double aspect,
  required List<double> rowFractions,
  required double chipHeight,
  double gap = 6,
}) {
  final natural = width / aspect;
  final rows = rowFractions.toSet().toList()..sort();
  var minStep = double.infinity;
  for (var i = 1; i < rows.length; i++) {
    final step = rows[i] - rows[i - 1];
    if (step < minStep) minStep = step;
  }
  if (minStep == double.infinity || minStep <= 0) return natural;
  final needed = chipHeight + (chipHeight + gap) / minStep;
  return needed > natural ? needed : natural;
}

// ── Tilted pitch geometry (P3b feedback Task 2) ────────────────────────────
// The court paints a TRAPEZOID pitch (narrow at the far/top end, full width
// at the near/bottom end) — perspective drawn directly in the painter rather
// than a Matrix4 transform, so the slot widgets stay ordinary Aligns whose
// hit zones always match the visuals.

/// Width of the pitch's far (top) edge as a fraction of its near (bottom)
/// edge — shared by the painter's trapezoid and the slot mapping below.
const double pitchTopScale = 0.74;

/// The pitch's drawable width fraction at row [y] (0 = far/top, 1 = near).
double pitchWidthFactor(double y) => pitchTopScale + (1 - pitchTopScale) * y;

/// Maps a flat starter offset into the trapezoid: x squeezes toward the
/// center the farther (higher) the row sits; y is unchanged. Keeps slots on
/// the drawn grass at every row.
({double x, double y}) pitchPerspective(({double x, double y}) o) =>
    (x: 0.5 + (o.x - 0.5) * pitchWidthFactor(o.y), y: o.y);

// ── Owner's "Neon Gold Isometric Soccer Pitch" asset geometry ──────────────
// The image (assets/fantasy/pitch_neon_gold.jpg, 1024×1244 — cropped from the
// original artwork to trim its heavy glow halo to a thin rim, owner feedback)
// bakes its own perspective; these fractions were measured off the artwork so
// slots land on its drawn grass. In the cropped frame the pitch surface spans
// y 0.056–0.944; its half-width grows from 0.335 (far/top) to 0.474
// (near/bottom) of the image width.
const double pitchAssetAspect = 1024 / 1244;
const double pitchAssetTopY = 0.0556;
const double pitchAssetBottomY = 0.9444;
const double pitchAssetHalfTop = 0.335;
const double pitchAssetHalfBottom = 0.474;

/// Maps a flat starter offset (pitch-relative 0..1, as [starterOffsets]
/// produces) onto the asset image's own perspective: y lands between the
/// image's far and near edges, x squeezes by the image's half-width at that
/// row. Output is in image fractions, ready for an [Alignment].
({double x, double y}) pitchAssetPerspective(({double x, double y}) o) {
  final y = pitchAssetTopY + (pitchAssetBottomY - pitchAssetTopY) * o.y;
  final half =
      pitchAssetHalfTop + (pitchAssetHalfBottom - pitchAssetHalfTop) * o.y;
  return (x: 0.5 + (o.x - 0.5) * (half / 0.5), y: y);
}

/// Lays a saved squad into the fixed slots: each pick lands in the first
/// empty slot matching its (position, bench). Picks that fit NO slot come
/// back in [unplaced] instead of vanishing — typically a player whose
/// fantasy position changed (spec §3: the server re-labels holders, so a
/// GK who became a DEF no longer fits the GK slot and the DEF slots are
/// full), or a config shrink. The builder shows them in its "Needs a new
/// spot" strip with Swap/Remove.
///
/// Two passes so the MOVED player is the one left over: drafts save picks
/// in slot order and the server re-labels a pick in place, so a pick that
/// still fits the slot at its own index keeps it first; the rest then take
/// the first empty matching slot. (One pass would let a GK re-labelled DEF
/// at index 0 grab the first DEF slot and strand a defender who never
/// moved.)
({List<SquadPick?> slotPicks, List<SquadPick> unplaced}) placePicks(
    FantasySquad? squad, List<SquadSlot> slots) {
  final out = List<SquadPick?>.filled(slots.length, null);
  final unplaced = <SquadPick>[];
  if (squad == null) return (slotPicks: out, unplaced: unplaced);
  bool fits(SquadSlot s, SquadPick p) =>
      s.position == p.position && s.bench == p.bench;
  final rest = <SquadPick>[];
  for (var i = 0; i < squad.picks.length; i++) {
    final pick = squad.picks[i];
    if (i < slots.length && fits(slots[i], pick)) {
      out[i] = pick;
    } else {
      rest.add(pick);
    }
  }
  for (final pick in rest) {
    final i = List.generate(slots.length, (k) => k)
        .firstWhere((k) => out[k] == null && fits(slots[k], pick),
            orElse: () => -1);
    if (i < 0) {
      unplaced.add(pick);
    } else {
      out[i] = pick;
    }
  }
  return (slotPicks: out, unplaced: unplaced);
}

/// [placePicks]' slot half — read-only viewers (history, other managers)
/// that just render the court.
List<SquadPick?> picksToSlots(FantasySquad? squad, List<SquadSlot> slots) =>
    placePicks(squad, slots).slotPicks;

/// The My Team alert banner sentence (spec §3 holder protection):
/// "Ann moved to DEF — your team needs rearranging before Sun, Oct 19 ·
/// 3:00 PM. Swapping him out is free this week." Several changes join with
/// commas/"and" and the last sentence says "them". [freeThisWeek] false
/// (the alert's gameweek has passed — its free swap expired) drops the
/// free-swap sentence.
String squadAlertText({
  required List<({String player, FantasyPosition to})> changes,
  required String deadline,
  required bool freeThisWeek,
}) {
  final parts = [for (final c in changes) '${c.player} moved to ${c.to.short}'];
  final head = parts.length <= 1
      ? parts.join()
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  final free = freeThisWeek
      ? ' Swapping ${changes.length == 1 ? 'him' : 'them'} out is free this '
          'week.'
      : '';
  return '$head — your team needs rearranging before $deadline.$free';
}

/// The integrity alert's sentence (squad hardening, audit I2): "Your
/// Gameweek 3 team didn't count: duplicate player and over budget. Fix it
/// before the next deadline." Known server issue names in plain words, in a
/// fixed order, duplicates and unknown names dropped; none known = "it
/// broke the squad rules".
String squadInvalidAlertText({
  required int gameweek,
  required List<String> issues,
}) {
  const words = {
    'tooManyPlayers': 'too many players',
    'tooManyStarters': 'too many starters',
    'duplicatePlayer': 'duplicate player',
    'unknownPlayer': 'unknown player',
    'ineligiblePlayer': 'ineligible player',
    'overBudget': 'over budget',
  };
  final parts = [
    for (final e in words.entries)
      if (issues.contains(e.key)) e.value,
  ];
  final why = parts.isEmpty
      ? 'it broke the squad rules'
      : parts.length == 1
          ? parts.single
          : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  final team = gameweek > 0 ? 'Gameweek $gameweek team' : 'team';
  return "Your $team didn't count: $why. Fix it before the next deadline.";
}

/// The over-budget preview's sentence (FPL selling, spec §4 — the sweep
/// re-judged the saved squad at the coming lock's prices): "Your team is
/// $1.0M over budget after this week's price changes. Fix it before the
/// deadline or this week won't count." No amount (0 or less — an old or
/// partial node) drops the "$X".
String squadOverBudgetPreviewText({required int overTenths}) {
  final amount = overTenths > 0 ? ' ${formatMoneyTenths(overTenths)}' : '';
  return "Your team is$amount over budget after this week's price changes. "
      "Fix it before the deadline or this week won't count.";
}

/// Shown when a squad save is refused after the deadline (squad hardening,
/// audit I3): the database rules reject a Squads write from the lock
/// instant on by the SERVER's clock, so a phone whose clock runs slow can
/// still be editing when the real deadline passes.
const String squadSaveLockedMessage =
    "The deadline passed while you were editing — this week's team is "
    "locked. Your changes weren't saved.";

/// Shown with the issues while Save waits for the money (FPL selling, spec
/// §4) — whenever the draft has unsaved edits and is not moneyReady (the
/// market prices or this week's `Baselines/<uid>` haven't loaded, or the
/// read failed), so its budget can't be trusted yet.
const String squadMoneyPendingMessage =
    'Your budget is still updating — try again in a few minutes.';

/// Whether a failed squad save was refused by the database rules
/// (`permission-denied` — FirebaseException's text is
/// "[firebase_database/permission-denied] Client doesn't have permission…"
/// on Android and iOS alike). The only rule a squad the builder lets you
/// save can still break is the deadline, so this reads as "locked".
bool isSaveRefusedByRules(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('permission-denied') ||
      text.contains('permission_denied') ||
      text.contains("doesn't have permission");
}

/// The engine squad a draft saves as — empty slots skipped, a missing
/// armband written as '' (which validateSquad flags as badCaptain).
FantasySquad draftToSquad({
  required List<SquadPick?> slotPicks,
  String? captainId,
  String? viceId,
  String? chip,
}) =>
    FantasySquad(
      picks: [
        for (final p in slotPicks)
          if (p != null) p
      ],
      captainId: captainId ?? '',
      viceId: viceId ?? '',
      chip: chip,
    );

/// Picker candidates for one slot: eligible players of [position], not
/// already in the squad, matching [query] on name or team. Sorted by price
/// (desc, ties by name) or by name — the price the sheet shows ([priceOf],
/// the draft's; default the market's). Affordability does NOT filter — the
/// sheet shows unaffordable players disabled instead.
List<FantasyPlayer> pickerCandidates({
  required List<FantasyPlayer> players,
  required FantasyPosition position,
  required Set<String> excludeIds,
  String query = '',
  bool sortByPrice = true,
  int Function(FantasyPlayer player)? priceOf,
}) {
  final price = priceOf ?? (FantasyPlayer p) => p.priceTenths;
  final q = query.trim().toLowerCase();
  final out = players
      .where((p) =>
          p.eligible &&
          p.position == position &&
          !excludeIds.contains(p.name) &&
          (q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.teamName.toLowerCase().contains(q)))
      .toList();
  if (sortByPrice) {
    out.sort((a, b) {
      final byPrice = price(b).compareTo(price(a));
      return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
    });
  } else {
    out.sort((a, b) => a.name.compareTo(b.name));
  }
  return out;
}

/// Armband after "Make Captain" on [id]. Kind invariants: captaining the
/// current vice swaps the bands (the old captain becomes vice) so nothing is
/// lost silently; otherwise the vice stays put.
({String? captainId, String? viceId}) assignCaptain({
  required String id,
  String? captainId,
  String? viceId,
}) {
  if (id == captainId) return (captainId: captainId, viceId: viceId);
  if (id == viceId) return (captainId: id, viceId: captainId);
  return (captainId: id, viceId: viceId);
}

/// Armband after "Make Vice-Captain" on [id] — mirror of [assignCaptain].
({String? captainId, String? viceId}) assignVice({
  required String id,
  String? captainId,
  String? viceId,
}) {
  if (id == viceId) return (captainId: captainId, viceId: viceId);
  if (id == captainId) return (captainId: viceId, viceId: id);
  return (captainId: captainId, viceId: id);
}

/// What to tell the manager when [removedId] leaves the squad (removed or
/// swapped out) while wearing an armband — null when no band was lost.
/// The caller also clears the band; nothing happens silently.
String? armbandLossMessage({
  required String removedId,
  String? captainId,
  String? viceId,
}) {
  if (removedId == captainId) {
    return 'Your captain left the squad — choose a new captain.';
  }
  if (removedId == viceId) {
    return 'Your vice-captain left the squad — choose a new vice-captain.';
  }
  return null;
}

/// Whether the squad is editable right now: the owner's override wins,
/// otherwise the engine's current-gameweek status (no current gameweek =
/// locked).
bool squadEditable({
  required FantasyLockOverride lockOverride,
  required List<Gameweek> gameweeks,
  required DateTime nowUtc,
}) =>
    effectiveGameweekStatus(
      gameweek: currentGameweek(gameweeks, nowUtc),
      override: lockOverride,
      nowUtc: nowUtc,
    ) ==
    GameweekStatus.open;

/// The engine's validateSquad, rendered as human sentences the builder shows
/// inline. Formation problems come out per position ("Pick 2 defenders — you
/// have 1"); the armband line appears only once there's a squad to captain.
///
/// Money (FPL selling, spec §4) is the shared draft's, not the picks' own
/// prices against the bare budget: over budget = [spentTenths] (at the
/// charged prices, SquadDraftController.spentTenths) above
/// [availableTenths] (budget + realized sales,
/// SquadDraftController.availableTenths) — the same figures as the bar.
/// [moneyReady] false (SquadDraftController.moneyReady: the market or this
/// week's baseline hasn't loaded, or the read failed) drops the over-budget
/// sentence — an over-budget fact is never asserted from unready money; the
/// builder says "still updating" instead.
List<String> issueSentences({
  required List<SquadSlot> slots,
  required List<SquadPick?> slotPicks,
  required String? captainId,
  required String? viceId,
  String? chip,
  required FantasyConfig cfg,
  List<SquadPick> unplaced = const [],
  required int spentTenths,
  required int availableTenths,
  required bool moneyReady,
}) {
  final squad = draftToSquad(
      slotPicks: slotPicks, captainId: captainId, viceId: viceId, chip: chip);
  final issues = validateSquad(squad, cfg);
  final out = <String>[
    // A pick with no fitting slot blocks Save until it's swapped or removed
    // (it would otherwise save in an illegal formation, or vanish).
    for (final p in unplaced)
      'Find ${p.playerId} a new spot — swap him out or remove him.',
  ];

  if (issues.contains(SquadIssue.formation)) {
    int have(FantasyPosition pos, bool bench) => List.generate(slots.length,
            (i) => i)
        .where((i) =>
            slots[i].position == pos &&
            slots[i].bench == bench &&
            slotPicks[i] != null)
        .length;
    void need(FantasyPosition pos, bool bench, int want, String singular,
        String plural) {
      final got = have(pos, bench);
      if (got >= want || want == 0) return;
      out.add(want == 1
          ? 'Pick $singular.'
          : 'Pick $want $plural — you have $got.');
    }

    const gk = FantasyPosition.gk, def = FantasyPosition.def;
    const att = FantasyPosition.att;
    need(gk, false, cfg.startersGk, gk.withArticle, gk.nounPlural);
    need(def, false, cfg.startersDef, def.withArticle, def.nounPlural);
    need(att, false, cfg.startersAtt, att.withArticle, att.nounPlural);
    need(def, true, cfg.benchDef, 'a bench ${def.noun}',
        'bench ${def.nounPlural}');
    need(att, true, cfg.benchAtt, 'a bench ${att.noun}',
        'bench ${att.nounPlural}');
  }

  // The engine's own overBudget (pick prices vs the bare budget) is NOT
  // read: the draft's figures are the ones the server will judge — and
  // only once they are real.
  if (moneyReady && spentTenths > availableTenths) {
    final over = spentTenths - availableTenths;
    out.add("You're ${formatMoneyTenths(over)} over budget.");
  }

  if (issues.contains(SquadIssue.duplicatePlayer)) {
    out.add("You've picked the same player twice — remove the duplicate.");
  }

  if (issues.contains(SquadIssue.badCaptain) &&
      squad.starters.isNotEmpty) {
    final hasCaptain =
        captainId != null && squad.starters.any((p) => p.playerId == captainId);
    final hasVice =
        viceId != null && squad.starters.any((p) => p.playerId == viceId);
    if (!hasCaptain && !hasVice) {
      out.add('Choose a captain and vice-captain.');
    } else if (!hasCaptain) {
      out.add('Choose a captain.');
    } else if (!hasVice) {
      out.add('Choose a vice-captain.');
    } else {
      // Both set but invalid (same player) — unreachable via the UI.
      out.add('Captain and vice-captain must be different players.');
    }
  }

  return out;
}

/// "Pick a goalkeeper" / "Pick a defender" / "Pick an attacker" sheet titles.
String pickerTitle(FantasyPosition pos) => 'Pick ${pos.withArticle}';

/// Two-letter initials for the avatar fallback (photos never gate content).
String initialsFor(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}
