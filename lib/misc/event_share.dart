import 'package:infinite_sports_flutter/model/event.dart';
import 'package:intl/intl.dart';

/// Generic call-to-action appended to every shared event message.
const String kShareCta =
    'Download the Infinite Sports app for details and to sign up!';

/// The date/time line for a share message: "September 27, 2026" (or a range
/// across multiple days) plus "6:00AM - 8:00PM" when times are set.
String shareDateTimeLine(Event e) {
  final parts = <String>[];
  final start = e.eventDate?.trim() ?? '';
  var dateStr = start;
  final startD = e.startDate;
  final endD = e.endDate;
  final multiDay = startD != null &&
      endD != null &&
      !(endD.year == startD.year &&
          endD.month == startD.month &&
          endD.day == startD.day);
  if (multiDay && start.isNotEmpty) {
    dateStr = '$start - ${DateFormat.yMMMMd('en_US').format(endD)}';
  }
  if (dateStr.isNotEmpty) parts.add(dateStr);

  final st = e.startTime?.trim() ?? '';
  final et = e.endTime?.trim() ?? '';
  if (st.isNotEmpty && et.isNotEmpty) {
    parts.add('$st - $et');
  } else if (st.isNotEmpty) {
    parts.add(st);
  }
  return parts.join(' · ');
}

/// The message shared as plain text alongside the flyer.
/// - Custom caption set: "<caption>\n\n<CTA>".
/// - No caption: an auto invite from the event's own title, short info, and
///   date/time, then the CTA.
String buildShareMessage(Event e) {
  final caption = e.shareCaption?.trim() ?? '';
  if (caption.isNotEmpty) {
    return '$caption\n\n$kShareCta';
  }
  final title = (e.title?.trim().isNotEmpty ?? false) ? e.title!.trim() : 'this event';
  final buf = StringBuffer('Join us for $title!');
  final info = e.info?.trim() ?? '';
  if (info.isNotEmpty) buf.write('\n$info');
  final dt = shareDateTimeLine(e);
  if (dt.isNotEmpty) buf.write('\n$dt');
  buf.write('\n\n$kShareCta');
  return buf.toString();
}
