import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

void main() {
  group('TournamentTeam.captainName', () {
    test('fromFirebase parses CaptainName', () {
      final t = TournamentTeam.fromFirebase(
        'alpha',
        {'Name': 'Alpha FC', 'CaptainName': 'Sam Rivera'},
        {},
      );
      expect(t.captainName, 'Sam Rivera');
    });

    test('fromFirebase falls back to lowercase captainName key', () {
      final t = TournamentTeam.fromFirebase(
        'alpha',
        {'Name': 'Alpha FC', 'captainName': 'Sam Rivera'},
        {},
      );
      expect(t.captainName, 'Sam Rivera');
    });

    test('fromFirebase leaves captainName null when absent', () {
      final t = TournamentTeam.fromFirebase('alpha', {'Name': 'Alpha FC'}, {});
      expect(t.captainName, isNull);
    });
  });
}
