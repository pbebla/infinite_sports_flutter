import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/event_share.dart';
import 'package:infinite_sports_flutter/model/event.dart';

Event _event({
  String? title,
  String? info,
  String? eventDate,
  DateTime? startDate,
  DateTime? endDate,
  String? startTime,
  String? endTime,
  String? caption,
}) {
  final e = Event();
  e.title = title;
  e.info = info;
  e.eventDate = eventDate;
  e.startDate = startDate;
  e.endDate = endDate;
  e.startTime = startTime;
  e.endTime = endTime;
  e.shareCaption = caption;
  return e;
}

void main() {
  group('buildShareMessage', () {
    test('uses custom caption plus the CTA when set', () {
      final msg = buildShareMessage(_event(
        title: 'Futsal Tournament',
        caption: 'Early bird pricing ends Friday!',
      ));
      expect(msg, 'Early bird pricing ends Friday!\n\n$kShareCta');
    });

    test('auto invite from title, info, date and time when no caption', () {
      final msg = buildShareMessage(_event(
        title: 'Futsal Tournament',
        info: 'Open to all skill levels',
        eventDate: 'September 27, 2026',
        startDate: DateTime(2026, 9, 27),
        endDate: DateTime(2026, 9, 27),
        startTime: '6:00AM',
        endTime: '8:00PM',
      ));
      expect(msg,
          'Check out Futsal Tournament!\n'
          'Open to all skill levels\n'
          'September 27, 2026 · 6:00AM - 8:00PM\n\n'
          '$kShareCta');
    });

    test('multi-day event shows a date range', () {
      final line = shareDateTimeLine(_event(
        eventDate: 'August 7, 2026',
        startDate: DateTime(2026, 8, 7),
        endDate: DateTime(2026, 8, 9),
        startTime: '',
        endTime: '',
      ));
      expect(line, 'August 7, 2026 - August 9, 2026');
    });

    test('falls back gracefully with almost no data', () {
      final msg = buildShareMessage(_event());
      expect(msg, 'Check out this event!\n\n$kShareCta');
    });

    test('single start time only (no end) still shows', () {
      final line = shareDateTimeLine(_event(
        eventDate: 'July 4, 2026',
        startDate: DateTime(2026, 7, 4),
        endDate: DateTime(2026, 7, 4),
        startTime: '5:00PM',
        endTime: '',
      ));
      expect(line, 'July 4, 2026 · 5:00PM');
    });
  });
}
