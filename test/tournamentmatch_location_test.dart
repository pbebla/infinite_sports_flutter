import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  test('parses structured Location into locationInfo', () {
    final m = TournamentMatch.fromFirebase('M1', {
      'Team1Id': 'a', 'Team2Id': 'b', 'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
      'Location': {'Venue': 'Pioneer HS', 'Address': '1290 Blossom Hill Rd', 'Field': 'Field 1'},
    });
    expect(m.locationInfo, isNotNull);
    expect(m.locationInfo!.venue, 'Pioneer HS');
    expect(m.locationInfo!.field, 'Field 1');
  });

  test('falls back to MatchLocation string', () {
    final m = TournamentMatch.fromFirebase('M2', {
      'Team1Id': 'a', 'Team2Id': 'b', 'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
      'MatchLocation': 'City Park',
    });
    expect(m.locationInfo!.venue, 'City Park');
    expect(m.locationInfo!.address, isNull);
  });

  test('locationInfo null when no location', () {
    final m = TournamentMatch.fromFirebase('M3', {
      'Team1Id': 'a', 'Team2Id': 'b', 'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
    });
    expect(m.locationInfo, isNull);
  });
}
