// Per-manager chip availability for the My Team chip row (spec §6: "UI
// shows per-chip availability counts ('1 left')"). Pure Dart — no Flutter
// or Firebase — unit-tested in test/fantasy/chip_usage_test.dart; the
// History reads stream through FantasyService.watchChipHistoryFor.
//
// THE RULE (server parity — functions/src/lib/fantasy/transfer_state.ts
// priorChipsOfUid + shouldVoidChip): a chip is SPENT for a set once the
// manager's finalized History/<gw>/<uid> carries it in a gameweek of that
// set EARLIER than the one being edited. Set 1 = GW1..config.chipSet1EndGw,
// set 2 = the rest of the season incl. playoffs, so a chip used in set 1 is
// a fresh "1 left" again in set 2. A chip played in an owner-VOIDED week is
// REFUNDED. The server (transfer_state.ts priorChipsOfUid) reads the
// `Voided/<gw>` node itself, so the client does too ([voidedWeeksFromNode],
// streamed by FantasyService.watchVoidedWeeks — Opus audit item 4): a week
// voided AFTER its finalize refunds at once, not only once the void
// trigger's re-finalize has mirrored `Voided: true` into History. Either
// source refunds (the History mirror stays honoured too). History only ever
// holds HONORED chips (a set-repeat is stripped from the lock snapshot
// before History is written), so every chip it shows was really consumed.
//
// Documented limit: between a week's lock and its finalize the chip lives
// only in PublishedPicks/the live squad (History not written yet), so the
// row shows it "Active" (still armed) until the post-finalize rollover
// clears it and History marks it spent.

import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

/// The four chips, in chip-row order (spec §6).
const List<String> fantasyChipIds = [
  'tripleCaptain',
  'benchBoost',
  'wildcard',
  'freeHit',
];

/// What one `History/<gw>/<uid>` entry says about chips.
class ChipHistoryEntry {
  const ChipHistoryEntry({this.chip, this.voided = false});

  /// The chip the manager played that week (honored at lock); null = none.
  final String? chip;

  /// The owner voided the week (spec §15) — its chip is refunded.
  final bool voided;

  @override
  bool operator ==(Object other) =>
      other is ChipHistoryEntry &&
      other.chip == chip &&
      other.voided == voided;

  @override
  int get hashCode => Object.hash(chip, voided);
}

/// Tolerant parse of one `History/<gw>/<uid>` node; null when absent or not
/// a map (no finalized squad that week). Only a literal `Voided: true`
/// voids (finalize_core.ts writes exactly that).
ChipHistoryEntry? chipHistoryEntryFromNode(Object? node) {
  if (node is! Map) return null;
  final chip = node['chip'];
  return ChipHistoryEntry(
    chip: chip is String && chip.isNotEmpty ? chip : null,
    voided: node['Voided'] == true,
  );
}

/// The owner-voided gameweeks out of the season's `Voided` node
/// (`Voided/<gw> = true`, orchestration_db.ts voidedWeeksOf parity): ONLY a
/// literal `true` voids (the Manager writes true or removes the node);
/// absent / false / junk counts. Gameweek keys are small ints, so RTDB WILL
/// list-coerce the node (index = gameweek, holes null) — a List and an
/// int-keyed Map both parse; non-positive / non-int keys are skipped.
Set<int> voidedWeeksFromNode(Object? node) {
  final out = <int>{};
  void take(Object? key, Object? value) {
    final gw = key is int ? key : int.tryParse(key.toString());
    if (gw != null && gw > 0 && value == true) out.add(gw);
  }

  if (node is List) {
    for (var i = 0; i < node.length; i++) {
      take(i, node[i]);
    }
  } else if (node is Map) {
    node.forEach(take);
  }
  return out;
}

/// Chip set of a gameweek (transfer_state.ts chipSetOf parity).
int chipSetOf(int gw, FantasyConfig config) =>
    gw <= config.chipSet1EndGw ? 1 : 2;

/// The gameweek a squad saved NOW applies to: the first one whose lock is
/// still ahead. After the last lock (season over) it is one past the last
/// gameweek, so the final set's usage still shows.
int chipEditingGameweek(List<Gameweek> gameweeks, DateTime nowUtc) {
  for (final g in gameweeks) {
    if (nowUtc.isBefore(g.lockUtc)) return g.number;
  }
  return gameweeks.isEmpty ? 1 : gameweeks.last.number + 1;
}

enum ChipAvailability {
  /// Not spent in the active set: "1 left".
  available,

  /// Spent in an earlier gameweek of the active set: "Used".
  used,

  /// Armed on the squad on screen (and not spent this set): "Active".
  active,
}

/// The badge text for each state.
String chipAvailabilityLabel(ChipAvailability a) => switch (a) {
      ChipAvailability.available => '1 left',
      ChipAvailability.used => 'Used',
      ChipAvailability.active => 'Active',
    };

/// Per chip id (all of [fantasyChipIds]): Used when [historyByWeek] shows
/// it consumed (not voided) in a gameweek EARLIER than [editingGw] inside
/// the same set; else Active when it is [armedChip]; else available. A
/// spent chip stays Used even if armed again — the server would void that
/// replay at lock. A week is voided — its chip refunded — when it is in
/// [voidedWeeks] (the `Voided` node, what the server reads) OR its History
/// entry carries the `Voided` mirror.
Map<String, ChipAvailability> chipAvailability({
  required Map<int, ChipHistoryEntry> historyByWeek,
  required int editingGw,
  required String? armedChip,
  required FantasyConfig config,
  Set<int> voidedWeeks = const {},
}) {
  final set = chipSetOf(editingGw, config);
  final spent = <String>{};
  historyByWeek.forEach((week, entry) {
    final chip = entry.chip;
    // None, or refunded (either source says the week was voided).
    if (chip == null || entry.voided || voidedWeeks.contains(week)) return;
    if (week < editingGw && chipSetOf(week, config) == set) spent.add(chip);
  });
  return {
    for (final id in fantasyChipIds)
      id: spent.contains(id)
          ? ChipAvailability.used
          : id == armedChip
              ? ChipAvailability.active
              : ChipAvailability.available,
  };
}
