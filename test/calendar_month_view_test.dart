import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/calendar_tab.dart';
import 'package:infinite_sports_flutter/model/event.dart';

Event _event(String title, DateTime when) {
  final e = Event();
  e.title = title;
  e.eventDateTime = when;
  return e;
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

void main() {
  testWidgets('renders every day of the month exactly once', (tester) async {
    await tester.pumpWidget(_wrap(CalendarMonthView(
      month: DateTime(2026, 7, 1),
      eventsByDay: const {},
      onDayTap: (_, __) {},
    )));
    expect(find.text('July 2026'), findsOneWidget);
    for (var d = 1; d <= 31; d++) {
      expect(find.text('$d'), findsOneWidget);
    }
  });

  testWidgets('tapping a day with events reports that day', (tester) async {
    final day = DateTime(2026, 7, 20);
    DateTime? tapped;
    List<MapEntry<int, Event>>? tappedEvents;
    await tester.pumpWidget(_wrap(CalendarMonthView(
      month: DateTime(2026, 7, 1),
      eventsByDay: {
        day: [MapEntry(3, _event('Futsal Finals', DateTime(2026, 7, 20, 18)))],
      },
      onDayTap: (d, evts) {
        tapped = d;
        tappedEvents = evts;
      },
    )));
    await tester.tap(find.text('20'));
    expect(tapped, day);
    expect(tappedEvents!.single.key, 3);
    expect(tappedEvents!.single.value.title, 'Futsal Finals');
  });

  testWidgets('days without events do not trigger the day sheet', (tester) async {
    var called = false;
    await tester.pumpWidget(_wrap(CalendarMonthView(
      month: DateTime(2026, 7, 1),
      eventsByDay: const {},
      onDayTap: (_, __) => called = true,
    )));
    await tester.tap(find.text('15'));
    expect(called, isFalse);
  });
}
