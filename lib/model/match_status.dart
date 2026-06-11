/// Represents the lifecycle state of a tournament match.
/// Stored as an int in Firebase for backwards compatibility:
/// 0 = pending, 1 = live, 2 = finished.
enum MatchStatus {
  pending(0, 'Upcoming'),
  live(1, 'Live'),
  finished(2, 'Final');

  final int _intValue;
  final String label;

  const MatchStatus(this._intValue, this.label);

  int toInt() => _intValue;

  static MatchStatus fromInt(int value) {
    for (final status in MatchStatus.values) {
      if (status._intValue == value) return status;
    }
    return MatchStatus.pending;
  }

  bool get isLive => this == MatchStatus.live;
  bool get isFinished => this == MatchStatus.finished;
  bool get isPending => this == MatchStatus.pending;
}
