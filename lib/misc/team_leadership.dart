// Pure display-logic helper for the tournament team detail page (TAS.1
// Task 3): decides which "Coach:" / "Captain:" lines to show for a team's
// leadership card. No Flutter/Firebase imports.

/// Builds the leadership display lines for a tournament team:
/// - Coach set only -> ['Coach: X']
/// - Captain set only (coach empty) -> ['Captain: Y']
/// - Both set -> ['Coach: X', 'Captain: Y']
/// - Neither set -> [] (caller hides the row/card entirely)
List<String> teamLeadershipLines({
  required String? coachName,
  required String? captainName,
}) {
  final lines = <String>[];
  if (coachName != null && coachName.isNotEmpty) {
    lines.add('Coach: $coachName');
  }
  if (captainName != null && captainName.isNotEmpty) {
    lines.add('Captain: $captainName');
  }
  return lines;
}
