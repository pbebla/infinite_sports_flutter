import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/ics.dart';
import 'package:infinite_sports_flutter/model/event.dart';

void main() {
  group('parseClockMinutes', () {
    test('parses PM and AM correctly', () {
      expect(parseClockMinutes('6:00PM'), 18 * 60);
      expect(parseClockMinutes('8:30 AM'), 8 * 60 + 30);
      expect(parseClockMinutes('12:00AM'), 0);
      expect(parseClockMinutes('12:00PM'), 12 * 60);
    });

    test('rejects garbage', () {
      expect(parseClockMinutes(null), isNull);
      expect(parseClockMinutes('noon'), isNull);
      expect(parseClockMinutes('6:99PM'), isNull);
    });
  });

  Event ev() {
    final e = Event();
    e.id = 'abc';
    e.title = 'Futsal Night';
    e.startDate = DateTime(2026, 8, 15);
    e.endDate = DateTime(2026, 8, 15);
    e.startTime = '6:00PM';
    e.endTime = '8:00PM';
    e.location = 'Pioneer High';
    e.address = '1290 Blossom Hill Rd';
    e.info = 'Come play';
    return e;
  }

  group('buildEventIcs', () {
    test('emits a well-formed timed VEVENT', () {
      final ics = buildEventIcs(ev(), stampMs: 0);
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('SUMMARY:Futsal Night'));
      expect(ics, contains('DTSTART:20260815T180000'));
      expect(ics, contains('DTEND:20260815T200000'));
      expect(ics, contains('LOCATION:1290 Blossom Hill Rd'));
      expect(ics, contains('END:VCALENDAR'));
    });

    test('falls back to a 1-hour block when end time missing', () {
      final e = ev()..endTime = '';
      final ics = buildEventIcs(e, stampMs: 0);
      expect(ics, contains('DTSTART:20260815T180000'));
      expect(ics, contains('DTEND:20260815T190000'));
    });

    test('all-day event when no clock times', () {
      final e = ev()
        ..startTime = ''
        ..endTime = '';
      final ics = buildEventIcs(e, stampMs: 0);
      expect(ics, contains('DTSTART;VALUE=DATE:20260815'));
      // DTEND is exclusive -> next day.
      expect(ics, contains('DTEND;VALUE=DATE:20260816'));
    });

    test('escapes commas and newlines in text fields', () {
      final e = ev()..info = 'Bring water, snacks\nand cleats';
      final ics = buildEventIcs(e, stampMs: 0);
      expect(ics, contains(r'DESCRIPTION:Bring water\, snacks\nand cleats'));
    });

    test('empty when the event has no date', () {
      final e = Event()..title = 'x';
      expect(buildEventIcs(e, stampMs: 0), isEmpty);
    });
  });
}
