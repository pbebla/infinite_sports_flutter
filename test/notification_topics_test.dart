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

  group('leagueTeamTopic (League Experience P2)', () {
    test('builds the league team topic from sanitized parts', () {
      expect(leagueTeamTopic('Futsal', '16', 'Nineveh'),
          'league_Futsal_16_team_Nineveh');
    });

    test('sanitizes spaces and specials in every part', () {
      expect(leagueTeamTopic('Flag Football', '3', "Ashur's XI"),
          'league_Flag_Football_3_team_Ashur_s_XI');
    });
  });
}
