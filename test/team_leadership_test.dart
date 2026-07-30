import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/team_leadership.dart';

void main() {
  group('teamLeadershipLines', () {
    test('coach only', () {
      expect(
        teamLeadershipLines(coachName: 'Jane Smith', captainName: null),
        ['Coach: Jane Smith'],
      );
    });

    test('captain only, when coach is empty', () {
      expect(
        teamLeadershipLines(coachName: null, captainName: 'Sam Rivera'),
        ['Captain: Sam Rivera'],
      );
    });

    test('captain only, when coach is an empty string', () {
      expect(
        teamLeadershipLines(coachName: '', captainName: 'Sam Rivera'),
        ['Captain: Sam Rivera'],
      );
    });

    test('both set shows both lines, coach first', () {
      expect(
        teamLeadershipLines(coachName: 'Jane Smith', captainName: 'Sam Rivera'),
        ['Coach: Jane Smith', 'Captain: Sam Rivera'],
      );
    });

    test('neither set is empty (row should be hidden)', () {
      expect(teamLeadershipLines(coachName: null, captainName: null), isEmpty);
      expect(teamLeadershipLines(coachName: '', captainName: ''), isEmpty);
    });
  });
}
