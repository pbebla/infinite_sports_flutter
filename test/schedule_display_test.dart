import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/schedule_display.dart';

void main() {
  group('gameTimeText', () {
    test('stored time wins and formats as h:mm AM/PM', () {
      expect(gameTimeText('17:00', 5), '5:00 PM');
      expect(gameTimeText('09:30', 5), '9:30 AM');
      expect(gameTimeText('12:00', 5), '12:00 PM');
      expect(gameTimeText('00:15', 5), '12:15 AM');
      expect(gameTimeText('5:05', 7), '5:05 AM');
    });

    test('falls back to the exact legacy derived rendering', () {
      expect(gameTimeText('', 5), '5:00PM');
      expect(gameTimeText('', 7), '7:00PM');
      expect(gameTimeText('not-a-time', 6), '6:00PM');
      expect(gameTimeText('24:00', 6), '6:00PM');
      expect(gameTimeText('17:75', 6), '6:00PM');
    });
  });

  group('stageDisplayName', () {
    test('maps the four stages, empty otherwise', () {
      expect(stageDisplayName('quarterfinal'), 'Quarterfinal');
      expect(stageDisplayName('semifinal'), 'Semifinal');
      expect(stageDisplayName('final'), 'Championship');
      expect(stageDisplayName('thirdPlace'), '3rd Place');
      expect(stageDisplayName(''), '');
      expect(stageDisplayName('regular'), '');
    });
  });

  group('isPlaceholderTeam', () {
    test('true only for bracket placeholder names', () {
      expect(isPlaceholderTeam('Winner of SF1'), isTrue);
      expect(isPlaceholderTeam('Loser of QF2'), isTrue);
      expect(isPlaceholderTeam('Red Dragons'), isFalse);
      expect(isPlaceholderTeam('Winnerless FC'), isFalse);
      expect(isPlaceholderTeam(''), isFalse);
    });
  });
}
