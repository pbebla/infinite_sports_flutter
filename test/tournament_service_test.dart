import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';

/// TAS.3 Task 3: [TournamentService.parseTournaments] is the pure parse+sort
/// core shared by getAllTournaments (one-shot) and watchAllTournaments
/// (live) — extracted here so it's directly unit-testable without touching
/// FirebaseDatabase.instance (no injection seam on the static class).
void main() {
  group('TournamentService.parseTournaments', () {
    test('parses tournaments, skips the Current Tournament pointer', () {
      final result = TournamentService.parseTournaments({
        'Current Tournament': 'cup-a',
        'cup-a': {'Name': 'Cup A', 'Finished': false, 'Edition': '2026'},
        'cup-b': {'Name': 'Cup B', 'Finished': true, 'Edition': '2025'},
      });
      expect(result.length, 2);
      expect(result.map((t) => t.id), containsAll(['cup-a', 'cup-b']));
    });

    test('active tournaments sort before finished ones', () {
      final result = TournamentService.parseTournaments({
        'finished-cup': {
          'Name': 'Old Cup',
          'Finished': true,
          'Edition': '2024',
        },
        'active-cup': {
          'Name': 'New Cup',
          'Finished': false,
          'Edition': '2026',
        },
      });
      expect(result.first.id, 'active-cup');
      expect(result.last.id, 'finished-cup');
    });

    test('finished tournaments sort newest edition first', () {
      final result = TournamentService.parseTournaments({
        'a': {'Name': 'A', 'Finished': true, 'Edition': '2023'},
        'b': {'Name': 'B', 'Finished': true, 'Edition': '2026'},
        'c': {'Name': 'C', 'Finished': true, 'Edition': '2024'},
      });
      expect(result.map((t) => t.id).toList(), ['b', 'c', 'a']);
    });

    test('non-map entries are skipped without throwing', () {
      final result = TournamentService.parseTournaments({
        'broken': 'not-a-map',
        'ok': {'Name': 'OK', 'Finished': false, 'Edition': '1'},
      });
      expect(result.length, 1);
      expect(result.single.id, 'ok');
    });

    test('non-map / null input yields an empty list', () {
      expect(TournamentService.parseTournaments(null), isEmpty);
      expect(TournamentService.parseTournaments('x'), isEmpty);
    });
  });

  group('TournamentService.activeTournamentIds (TAS.3 Task 5)', () {
    test('keeps only unfinished tournaments, sorted', () {
      final tournaments = TournamentService.parseTournaments({
        'zzz-cup': {'Name': 'Zzz', 'Finished': false, 'Edition': '1'},
        'aaa-cup': {'Name': 'Aaa', 'Finished': false, 'Edition': '1'},
        'finished-cup': {'Name': 'Done', 'Finished': true, 'Edition': '1'},
      });
      expect(TournamentService.activeTournamentIds(tournaments),
          ['aaa-cup', 'zzz-cup']);
    });

    test('empty list yields an empty id list', () {
      expect(TournamentService.activeTournamentIds([]), isEmpty);
    });

    test('all finished yields an empty id list', () {
      final tournaments = TournamentService.parseTournaments({
        'a': {'Name': 'A', 'Finished': true, 'Edition': '1'},
      });
      expect(TournamentService.activeTournamentIds(tournaments), isEmpty);
    });

    test('same active set in different orders compares equal (List ==)', () {
      final a = TournamentService.parseTournaments({
        'x': {'Name': 'X', 'Finished': false, 'Edition': '2'},
        'y': {'Name': 'Y', 'Finished': false, 'Edition': '1'},
      });
      final b = TournamentService.parseTournaments({
        'y': {'Name': 'Y', 'Finished': false, 'Edition': '1'},
        'x': {'Name': 'X', 'Finished': false, 'Edition': '2'},
      });
      expect(TournamentService.activeTournamentIds(a),
          TournamentService.activeTournamentIds(b));
    });
  });
}
