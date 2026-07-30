import 'package:infinite_sports_flutter/model/event.dart';

/// Parses a stored time string like "6:00PM" or "8:30 AM" into minutes since
/// midnight. Returns null when it can't be understood.
int? parseClockMinutes(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*$').firstMatch(raw);
  if (m == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  final pm = m.group(3)!.toUpperCase() == 'PM';
  if (hour == 12) hour = 0;
  if (pm) hour += 12;
  if (minute > 59) return null;
  return hour * 60 + minute;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Formats a DateTime as a floating (local, no timezone) ICS timestamp:
/// YYYYMMDDTHHMMSS.
String _icsLocal(DateTime dt) =>
    '${dt.year}${_two(dt.month)}${_two(dt.day)}T${_two(dt.hour)}${_two(dt.minute)}00';

/// Escapes text for an ICS field (commas, semicolons, newlines).
String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;');

/// Builds a single-event VCALENDAR (.ics) body for [event]. Uses the event's
/// start/end dates and clock times when present; falls back to an all-day
/// event when times are missing. [stampMs] is the DTSTAMP epoch (pass a real
/// clock time from the caller — kept as a parameter so this stays pure/testable).
String buildEventIcs(Event event, {required int stampMs, String? uid}) {
  final start = event.startDate ?? event.eventDateTime;
  if (start == null) return '';
  final end = event.endDate ?? start;

  final startMin = parseClockMinutes(event.startTime);
  final endMin = parseClockMinutes(event.endTime);

  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Infinite Sports//Events//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    'UID:${uid ?? 'is-${event.id ?? event.title ?? start.millisecondsSinceEpoch}'}@infinitesports',
    'DTSTAMP:${_icsLocal(DateTime.fromMillisecondsSinceEpoch(stampMs))}',
  ];

  if (startMin != null) {
    final dtStart = DateTime(start.year, start.month, start.day, startMin ~/ 60, startMin % 60);
    // End on the same/last day at the end time, or +1h if no end time.
    final endDay = DateTime(end.year, end.month, end.day);
    final dtEnd = endMin != null
        ? DateTime(endDay.year, endDay.month, endDay.day, endMin ~/ 60, endMin % 60)
        : dtStart.add(const Duration(hours: 1));
    lines.add('DTSTART:${_icsLocal(dtStart)}');
    lines.add('DTEND:${_icsLocal(dtEnd.isAfter(dtStart) ? dtEnd : dtStart.add(const Duration(hours: 1)))}');
  } else {
    // All-day: DTEND is exclusive, so add a day past the last day.
    String dateOnly(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';
    lines.add('DTSTART;VALUE=DATE:${dateOnly(start)}');
    lines.add('DTEND;VALUE=DATE:${dateOnly(end.add(const Duration(days: 1)))}');
  }

  lines.add('SUMMARY:${_esc(event.title ?? 'Event')}');
  final description = [event.info, event.details]
      .where((s) => s != null && s.trim().isNotEmpty)
      .join('\n\n');
  if (description.isNotEmpty) lines.add('DESCRIPTION:${_esc(description)}');
  final place = event.address?.trim().isNotEmpty ?? false
      ? event.address!
      : (event.location ?? '');
  if (place.trim().isNotEmpty) lines.add('LOCATION:${_esc(place)}');

  lines.add('END:VEVENT');
  lines.add('END:VCALENDAR');
  return lines.join('\r\n');
}
