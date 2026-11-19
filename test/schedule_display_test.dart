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
    test('maps the five stages, empty otherwise', () {
      expect(stageDisplayName('quarterfinal'), 'Quarterfinal');
      expect(stageDisplayName('semifinal'), 'Semifinal');
      expect(stageDisplayName('final'), 'Championship');
      expect(stageDisplayName('thirdPlace'), '3rd Place');
      expect(stageDisplayName('friendly'), 'Friendly');
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

    // S16 Task 2: seed placeholders ('3rd Place', filled in by the Manager
    // once the regular season ends) behave like 'Winner of QF1'.
    test('ordinal seed placeholders are placeholders', () {
      expect(isPlaceholderTeam('1st Place'), isTrue);
      expect(isPlaceholderTeam('2nd Place'), isTrue);
      expect(isPlaceholderTeam('3rd Place'), isTrue);
      expect(isPlaceholderTeam('6th Place'), isTrue);
      expect(isPlaceholderTeam('12th place '), isTrue);
      expect(isPlaceholderTeam(' 4TH PLACE'), isTrue);
      expect(isPlaceholderTeam('Winner of QF1'), isTrue);
    });

    test('real teams that merely mention a place are still teams', () {
      expect(isPlaceholderTeam('Park Place FC'), isFalse);
      expect(isPlaceholderTeam('1st Place FC'), isFalse);
      expect(isPlaceholderTeam('The 3rd Place'), isFalse);
      expect(isPlaceholderTeam('123rd Place'), isFalse);
      expect(isPlaceholderTeam('Place'), isFalse);
      expect(isPlaceholderTeam('3rdPlace'), isFalse);
      expect(isPlaceholderTeam(''), isFalse);
      expect(isPlaceholderTeam('   '), isFalse);
    });
  });
}
