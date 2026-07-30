import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/model/event.dart';

Event _event(String title, DateTime? when) {
  final e = Event();
  e.title = title;
  e.eventDateTime = when;
  return e;
}

void main() {
  final now = DateTime(2026, 7, 13, 15, 30);

  test('keeps today and future events, drops past, sorts ascending', () {
    final events = [
      _event('past', DateTime(2026, 7, 1)),
      _event('later', DateTime(2026, 9, 1)),
      _event('today', DateTime(2026, 7, 13)),
      _event('soon', DateTime(2026, 7, 20)),
    ];
    final result = upcomingEvents(events, now);
    expect(result.map((e) => e.value.title).toList(), ['today', 'soon', 'later']);
  });

  test('preserves original list indexes for EventPage navigation', () {
    final events = [
      _event('past', DateTime(2026, 1, 1)),
      _event('future', DateTime(2026, 12, 1)),
    ];
    final result = upcomingEvents(events, now);
    expect(result.single.key, 1);
  });

  test('skips events with unparseable dates', () {
    final result = upcomingEvents([_event('broken', null)], now);
    expect(result, isEmpty);
  });

  group('eventsByDay', () {
    test('groups events on the same calendar day regardless of time', () {
      final byDay = eventsByDay([
        _event('morning', DateTime(2026, 7, 20, 9)),
        _event('evening', DateTime(2026, 7, 20, 18)),
        _event('other day', DateTime(2026, 7, 21)),
      ]);
      expect(byDay[DateTime(2026, 7, 20)]!.map((e) => e.event!.title).toList(),
          ['morning', 'evening']);
      expect(byDay[DateTime(2026, 7, 21)]!.single.event!.title, 'other day');
    });

    test('keys are midnight-normalized and legacy indexes preserved', () {
      final byDay = eventsByDay([
        _event('skipped', null),
        _event('kept', DateTime(2026, 8, 2, 14, 45)),
      ]);
      expect(byDay.keys.single, DateTime(2026, 8, 2));
      expect(byDay.values.single.single.legacyIndex, 1);
    });
  });
}
