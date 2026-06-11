import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  group('TournamentMatch.fromFirebase activity parsing', () {
    test('reads activity stored as a normal map (sparse minute keys)', () {
      final m = TournamentMatch.fromFirebase('m1', {
        'Team1Activity': {
          '5': [
            {'goal': 'Ashur'}
          ],
          '12': [
            {'assist': 'Sargis'}
          ],
        },
      });
      expect(m.team1Activity, isNotNull);
      expect(m.team1Activity!.keys, containsAll(['5', '12']));
    });

    test('recovers activity when Firebase coerces minute keys into a list', () {
      // Minutes 1, 2, 3 are stored as keys "1","2","3"; Firebase Realtime
      // Database returns that node as a List with a null hole at index 0.
      // The match model must recover the timeline instead of dropping it,
      // otherwise the score shows but the match facts never appear.
      final m = TournamentMatch.fromFirebase('m1', {
        'Team1Activity': [
          null,
          [
            {'goal': 'Ashur'}
          ],
          [
            {'assist': 'Sargis'}
          ],
        ],
      });
      expect(m.team1Activity, isNotNull,
          reason: 'list-coerced activity should be recovered, not dropped');
      expect(m.team1Activity!.containsKey('0'), isFalse);
      expect(m.team1Activity!['1'], isA<List>());
      expect(m.team1Activity!['2'], isA<List>());
    });
  });
}
