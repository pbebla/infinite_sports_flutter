/// Represents the bracket stage of a tournament match.
/// Stored as a free-form string in Firebase for flexibility;
/// this enum normalizes parsing and ordering.
enum TournamentStage {
  group(0, 'Group Stage', false),
  roundOf16(1, 'Round of 16', true),
  quarterFinal(2, 'Quarterfinal', true),
  semiFinal(3, 'Semifinal', true),
  thirdPlace(4, 'Third Place', true),
  finalStage(5, 'Final', true),
  unknown(99, 'Other', false);

  final int sortOrder;
  final String label;
  final bool isKnockout;

  const TournamentStage(this.sortOrder, this.label, this.isKnockout);

  /// Parse a raw stage string from Firebase into the enum.
  /// Tolerant of common variants (case, hyphens, abbreviations).
  static TournamentStage fromString(String? raw) {
    if (raw == null || raw.isEmpty) return TournamentStage.unknown;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');

    if (normalized.contains('group') || normalized == 'groups') {
      return TournamentStage.group;
    }
    if (normalized == 'ro16' ||
        normalized == 'r16' ||
        normalized.contains('roundof16')) {
      return TournamentStage.roundOf16;
    }
    if (normalized == 'qf' || normalized.contains('quarter')) {
      return TournamentStage.quarterFinal;
    }
    if (normalized.contains('third') ||
        normalized.contains('3rdplace') ||
        normalized == '3rd') {
      return TournamentStage.thirdPlace;
    }
    if (normalized == 'sf' || normalized.contains('semi')) {
      return TournamentStage.semiFinal;
    }
    if (normalized == 'f' ||
        normalized == 'final' ||
        normalized == 'finals') {
      return TournamentStage.finalStage;
    }
    return TournamentStage.unknown;
  }
}
