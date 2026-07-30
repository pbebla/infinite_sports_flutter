import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';

void main() {
  group('P4 campaign topics', () {
    test('all-users topic is the shared constant', () {
      expect(allUsersTopic, 'all_users');
    });

    test('sport topic sanitizes the category', () {
      expect(sportTopic('Futsal'), 'sport_Futsal');
      expect(sportTopic('Flag Football'), 'sport_Flag_Football');
    });

    test('event topic sanitizes the id', () {
      expect(eventTopic('-OxUPA3v'), 'event_-OxUPA3v');
      expect(eventTopic('a/b c'), 'event_a_b_c');
    });
  });
}
