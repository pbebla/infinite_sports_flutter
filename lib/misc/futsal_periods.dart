// Shared futsal half, team-foul and man-down rules - pure Dart, no Flutter
// or Firebase imports, so the same file can live in both apps.
//
// Game node fields (written only by the Manager):
//   Period        '1H' | 'HT' | '2H' | 'ET'
//   PeriodStarts  {'2H': epoch ms, 'ET': epoch ms}
// An event's half is derived from its `_t` stamp against PeriodStarts, so
// events themselves never carry a half.
import 'package:infinite_sports_flutter/misc/activity_entry.dart';

enum FutsalPeriod {
  firstHalf('1H'),
  halfTime('HT'),
  secondHalf('2H'),
  extraTime('ET');

  const FutsalPeriod(this.key);

  final String key;

  /// null when [raw] is absent or not a known key.
  static FutsalPeriod? fromKey(Object? raw) {
    for (final p in FutsalPeriod.values) {
      if (p.key == raw) return p;
    }
    return null;
  }
}

int? _asMs(Object? v) => v is num ? v.toInt() : null;

class FutsalPeriodInfo {
  const FutsalPeriodInfo({
    this.period,
    this.secondHalfStartMs,
    this.extraTimeStartMs,
  });

  final FutsalPeriod? period;
  final int? secondHalfStartMs;
  final int? extraTimeStartMs;

  /// Reads `Period` and `PeriodStarts`; missing or malformed values become null.
  static FutsalPeriodInfo fromGame(Map<dynamic, dynamic> game) {
    final starts = game['PeriodStarts'];
    return FutsalPeriodInfo(
      period: FutsalPeriod.fromKey(game['Period']),
      secondHalfStartMs: starts is Map ? _asMs(starts['2H']) : null,
      extraTimeStartMs: starts is Map ? _asMs(starts['ET']) : null,
    );
  }
}

/// The half an event stamped [t] belongs to. A missing [t] or a missing start
/// counts as the 1st half, so an event during half time is a 1st-half event.
/// Never returns [FutsalPeriod.halfTime].
FutsalPeriod eventPeriod(int? t, FutsalPeriodInfo info) {
  if (t == null) return FutsalPeriod.firstHalf;
  final et = info.extraTimeStartMs;
  if (et != null && t >= et) return FutsalPeriod.extraTime;
  final h2 = info.secondHalfStartMs;
  if (h2 != null && t >= h2) return FutsalPeriod.secondHalf;
  return FutsalPeriod.firstHalf;
}

/// The team's `Foul` count for the half shown by `info.period`: 1H and HT show
/// the 1st half, 2H the 2nd half, ET the 2nd half plus extra time. A null
/// period gives 0. [teamActivity] is `team{1,2}activity` (minute buckets as a
/// List or a Map, each bucket a List or a Map of leaves).
int teamFoulsShown(Object? teamActivity, FutsalPeriodInfo info) {
  final shown = info.period;
  if (shown == null) return 0;
  final Set<FutsalPeriod> counted = switch (shown) {
    FutsalPeriod.firstHalf || FutsalPeriod.halfTime => {FutsalPeriod.firstHalf},
    FutsalPeriod.secondHalf => {FutsalPeriod.secondHalf},
    FutsalPeriod.extraTime => {FutsalPeriod.secondHalf, FutsalPeriod.extraTime},
  };
  var n = 0;
  for (final bucket in _values(teamActivity)) {
    for (final leaf in _values(bucket)) {
      if (leaf is! Map) continue;
      final event = activityEventOf(leaf);
      if (event == null || event.key.toLowerCase() != 'foul') continue;
      if (counted.contains(eventPeriod(_asMs(leaf['_t']), info))) n++;
    }
  }
  return n;
}

Iterable<Object?> _values(Object? node) {
  if (node is Map) return node.values;
  if (node is List) return node;
  return const [];
}

sealed class FoulPenalty {
  const FoulPenalty();
}

class FoulNone extends FoulPenalty {
  const FoulNone();
}

class FoulWarning extends FoulPenalty {
  const FoulWarning();
}

class FoulManDown extends FoulPenalty {
  const FoulManDown(this.duration);
  final Duration duration;
}

/// Penalty for a team's [nthFoul] in the half: 5th warns, 6th and 8th cost a
/// player for 1:00, every even foul from the 10th for 2:00, all others none.
FoulPenalty foulPenaltyFor(int nthFoul) {
  if (nthFoul == 5) return const FoulWarning();
  if (nthFoul == 6 || nthFoul == 8) {
    return const FoulManDown(Duration(minutes: 1));
  }
  if (nthFoul >= 10 && nthFoul.isEven) {
    return const FoulManDown(Duration(minutes: 2));
  }
  return const FoulNone();
}

/// Man-down length for a card type, or null when the type costs no player.
Duration? manDownForCard(String type) {
  switch (type) {
    case 'Yellow':
    case 'SecondYellow':
      return const Duration(minutes: 1);
    case 'Red':
      return const Duration(minutes: 2);
  }
  return null;
}

/// Man-down time left on the game clock, clamped to `0..durationMs`.
int manDownRemainingMs({
  required int durationMs,
  required int startElapsedMs,
  required int clockElapsedMs,
}) {
  if (durationMs <= 0) return 0;
  final left = durationMs - (clockElapsedMs - startElapsedMs);
  return left.clamp(0, durationMs);
}
