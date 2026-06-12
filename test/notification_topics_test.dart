import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';

void main() {
  group('sanitizeTopicId', () {
    test('keeps letters, digits, underscore, hyphen', () {
      expect(sanitizeTopicId('abc-DEF_123'), 'abc-DEF_123');
    });
    test('replaces everything else with underscore (parity with decide.ts)', () {
      expect(sanitizeTopicId('Test Tournament 2026!'), 'Test_Tournament_2026_');
    });
  });

  group('topic builders', () {
    test('tournamentTopic', () {
      expect(tournamentTopic('T 1'), 'tournament_T_1');
    });
    test('teamTopic', () {
      expect(teamTopic('T1', 'team a'), 'tournament_T1_team_team_a');
    });
  });
}
