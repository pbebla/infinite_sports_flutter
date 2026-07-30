import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  test('finished/live text uses score', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 4,
      team2Score: 3, status: 2, bracketPosition: 1,
    );
    expect(
      buildShareText(
          match: m,
          team1Name: 'Eagles',
          team2Name: 'Lions',
          tournamentName: 'Test Tournament 2026'),
      'Eagles 4–3 Lions · Test Tournament 2026 — follow live on Infinite Sports.',
    );
  });

  test('upcoming text uses vs', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 0,
      team2Score: 0, status: 0, bracketPosition: 1,
    );
    expect(
      buildShareText(
          match: m,
          team1Name: 'Eagles',
          team2Name: 'Lions',
          tournamentName: 'Test Tournament 2026'),
      'Eagles vs Lions · Test Tournament 2026 — follow live on Infinite Sports.',
    );
  });

  test('empty tournament name omits the middle dot segment', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 1,
      team2Score: 0, status: 2, bracketPosition: 1,
    );
    expect(
      buildShareText(
          match: m, team1Name: 'A', team2Name: 'B', tournamentName: ''),
      'A 1–0 B — follow live on Infinite Sports.',
    );
  });
}
