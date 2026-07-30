import 'package:infinite_sports_flutter/model/event.dart';
import 'package:intl/intl.dart';

/// Generic call-to-action appended to every shared event message.
const String kShareCta =
    'Download the Infinite Sports app for details and to sign up!';

/// The CTA plus tappable store links (whichever exist) so a recipient
/// without the app can download it in one tap.
String shareCtaWithLinks({String? androidUrl, String? iosUrl}) {
  final buf = StringBuffer(kShareCta);
  if (androidUrl != null && androidUrl.trim().isNotEmpty) {
    buf.write('\nAndroid: ${androidUrl.trim()}');
  }
  if (iosUrl != null && iosUrl.trim().isNotEmpty) {
    buf.write('\niPhone: ${iosUrl.trim()}');
  }
  return buf.toString();
}

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
/// Pass [androidUrl]/[iosUrl] (from getStoreLinks) to append download links.
String buildShareMessage(Event e, {String? androidUrl, String? iosUrl}) {
  final cta = shareCtaWithLinks(androidUrl: androidUrl, iosUrl: iosUrl);
  final caption = e.shareCaption?.trim() ?? '';
  if (caption.isNotEmpty) {
    return '$caption\n\n$cta';
  }
  final title = (e.title?.trim().isNotEmpty ?? false) ? e.title!.trim() : 'this event';
  final buf = StringBuffer('Check out $title!');
  final info = e.info?.trim() ?? '';
  if (info.isNotEmpty) buf.write('\n$info');
  final dt = shareDateTimeLine(e);
  if (dt.isNotEmpty) buf.write('\n$dt');
  buf.write('\n\n$cta');
  return buf.toString();
}
