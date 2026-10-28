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

  row(cfg.startersGk, 0.12, 0);
  row(cfg.startersDef, 0.46, 0.24);
  row(cfg.startersAtt, 0.78, 0.26);
  return out;
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
/// empty slot matching its (position, bench). Picks that fit no slot (a
/// malformed node, or a config shrink) are dropped — the resulting draft
/// simply shows them missing.
List<SquadPick?> picksToSlots(FantasySquad? squad, List<SquadSlot> slots) {
  final out = List<SquadPick?>.filled(slots.length, null);
  if (squad == null) return out;
  for (final pick in squad.picks) {
    for (var i = 0; i < slots.length; i++) {
      if (out[i] == null &&
          slots[i].position == pick.position &&
          slots[i].bench == pick.bench) {
        out[i] = pick;
        break;
      }
    }
  }
  return out;
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

/// Total paid for the filled slots, in tenths.
int draftSpentTenths(List<SquadPick?> slotPicks) =>
    slotPicks.fold(0, (a, p) => a + (p?.priceTenths ?? 0));

/// Picker candidates for one slot: eligible players of [position], not
/// already in the squad, matching [query] on name or team. Sorted by price
/// (desc, ties by name) or by name. Affordability does NOT filter — the
/// sheet shows unaffordable players disabled instead.
List<FantasyPlayer> pickerCandidates({
  required List<FantasyPlayer> players,
  required FantasyPosition position,
  required Set<String> excludeIds,
  String query = '',
  bool sortByPrice = true,
}) {
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
      final byPrice = b.priceTenths.compareTo(a.priceTenths);
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
List<String> issueSentences({
  required List<SquadSlot> slots,
  required List<SquadPick?> slotPicks,
  required String? captainId,
  required String? viceId,
  String? chip,
  required FantasyConfig cfg,
}) {
  final squad = draftToSquad(
      slotPicks: slotPicks, captainId: captainId, viceId: viceId, chip: chip);
  final issues = validateSquad(squad, cfg);
  final out = <String>[];

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

    need(FantasyPosition.gk, false, cfg.startersGk, 'a goalkeeper',
        'goalkeepers');
    need(FantasyPosition.def, false, cfg.startersDef, 'a defender',
        'defenders');
    need(FantasyPosition.att, false, cfg.startersAtt, 'an attacker',
        'attackers');
    need(FantasyPosition.def, true, cfg.benchDef, 'a bench defender',
        'bench defenders');
    need(FantasyPosition.att, true, cfg.benchAtt, 'a bench attacker',
        'bench attackers');
  }

  if (issues.contains(SquadIssue.overBudget)) {
    final over = squad.spentTenths - cfg.budgetTenths;
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
String pickerTitle(FantasyPosition pos) => switch (pos) {
      FantasyPosition.gk => 'Pick a goalkeeper',
      FantasyPosition.def => 'Pick a defender',
      FantasyPosition.att => 'Pick an attacker',
    };

/// Two-letter initials for the avatar fallback (photos never gate content).
String initialsFor(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}
