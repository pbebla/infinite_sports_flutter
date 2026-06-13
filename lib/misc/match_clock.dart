/// Pure match-clock math, shared in spirit with the Manager app's copy at
/// InfiniteSportsManagerFlutter/lib/services/match_clock.dart — keep both in
/// sync. No Flutter imports so it stays unit-testable.
///
/// Stored under Tournaments/{tid}/Matches/{mid}/Clock as:
///   StartedAt     ms timestamp at kickoff
///   PausedAccumMs total ms of COMPLETED pauses (default 0)
///   PausedAt      ms timestamp the current pause began, or absent while running
class MatchClock {
  final int startedAtMs;
  final int pausedAccumMs;
  final int? pausedAtMs;

  const MatchClock({
    required this.startedAtMs,
    required this.pausedAccumMs,
    required this.pausedAtMs,
  });

  bool get isPaused => pausedAtMs != null;

  /// Elapsed play time at wall-clock [nowMs]. Frozen at [pausedAtMs] while paused.
  Duration elapsedAt(int nowMs) {
    final end = pausedAtMs ?? nowMs;
    final ms = end - startedAtMs - pausedAccumMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Builds from the raw `Clock` map. Returns null when there's no usable
  /// StartedAt — callers then show LIVE with no minute.
  static MatchClock? fromMap(Object? raw) {
    if (raw is! Map) return null;
    if (raw['StartedAt'] == null && raw['startedAt'] == null) return null;
    return MatchClock(
      startedAtMs: _toInt(raw['StartedAt'] ?? raw['startedAt']),
      pausedAccumMs: _toInt(raw['PausedAccumMs'] ?? raw['pausedAccumMs']),
      pausedAtMs: (raw['PausedAt'] ?? raw['pausedAt']) == null
          ? null
          : _toInt(raw['PausedAt'] ?? raw['pausedAt']),
    );
  }
}

/// "37'" — 1-based, minimum 1.
String minuteLabel(Duration elapsed) => "${elapsed.inMinutes + 1}'";

/// "47:30" — zero-padded mm:ss.
String clockLabel(Duration elapsed) {
  final mm = elapsed.inMinutes.toString().padLeft(2, '0');
  final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
