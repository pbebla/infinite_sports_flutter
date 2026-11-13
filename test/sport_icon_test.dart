import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/calendar_tab.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/sport_icon.dart';

/// Release report #7: Flag Football match days on the calendar showed a
/// soccer ball — the day sheet hard-coded Icons.sports_soccer for every
/// league. It now uses the app's one sport → icon mapping.
void main() {
  group('sportIcon', () {
    test('each league sport maps to its own icon', () {
      expect(sportIcon('Flag Football'), Icons.sports_football);
      expect(sportIcon('Basketball'), Icons.sports_basketball);
      expect(sportIcon('Futsal'), Icons.sports_soccer);
      expect(sportIcon('AFC San Jose'), Icons.sports_soccer);
      expect(sportIcon('Soccer'), Icons.sports_soccer);
      expect(sportIcon('Tournament'), Icons.emoji_events);
    });
  });

  group('calendarEntryIcon', () {
    CalendarEntry league(String? sport) => CalendarEntry(
        kind: CalendarKind.league, sport: sport, season: '15', title: 'x');

    test('league match days use the league sport icon', () {
      expect(calendarEntryIcon(league('Flag Football')),
          Icons.sports_football);
      expect(calendarEntryIcon(league('Basketball')), Icons.sports_basketball);
      expect(calendarEntryIcon(league('Futsal')), Icons.sports_soccer);
      // No sport on the entry = the Futsal league (the page's own default).
      expect(calendarEntryIcon(league(null)), Icons.sports_soccer);
    });

    test('tournaments keep the trophy, events the event icon', () {
      expect(
          calendarEntryIcon(const CalendarEntry(
              kind: CalendarKind.tournament, title: 'Cup')),
          Icons.emoji_events);
      expect(
          calendarEntryIcon(const CalendarEntry(kind: CalendarKind.event)),
          Icons.event);
    });
  });
}
