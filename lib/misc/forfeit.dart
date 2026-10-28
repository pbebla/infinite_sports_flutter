// League forfeits (fantasy spec §8a, owner decision 2026-10-28) — the fan
// app's read side of the contract the Manager's Forfeit button writes.
// Pure Dart (no Flutter/Firebase): shared by the fantasy engine's stats
// mapper, the league match adapters and the legacy game parsers.
//
// Game-node contract (Manager lib/services/forfeit.dart — do not deviate):
// - `forfeitedBy`: 1 | 2 on `<Sport>/<season>/Date/<date>/<i>` — which team
//   forfeited. Absent = not a forfeit. Only an explicit admin mark writes
//   it; it is NEVER inferred from "5–0 with no stats".
// - Marking sets the other team's score to 5, the forfeiter's to 0 and the
//   status to Final; Undo removes the marker and restores the old result.

/// Game-node key for the forfeit marker (1 | 2).
const String kForfeitedByKey = 'forfeitedBy';

/// `forfeitedBy` as 1 or 2; null for absent / junk / any other number.
/// Tolerant like every league parser (RTDB hands back int / double /
/// String mixes) — exact parity with the Manager's `parseForfeitedBy` and
/// the functions' stats_mapper.ts `parseForfeitedBy`.
int? parseForfeitedBy(Object? raw) {
  int? v;
  if (raw is int) {
    v = raw;
  } else if (raw is num) {
    if (raw.isFinite && raw == raw.roundToDouble()) v = raw.toInt();
  } else if (raw is String) {
    v = int.tryParse(raw.trim());
  }
  return (v == 1 || v == 2) ? v : null;
}
