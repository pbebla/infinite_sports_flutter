// iPad parity for the event page's three share entry points (flyer share,
// text-only share, "Add to my calendar" .ics): share_plus REJECTS an iPad
// share with no `sharePositionOrigin`, so each must hand the share sheet an
// origin equal to the rect of the button that was tapped. Firebase-free: the
// `eventStream` / `shareSheet` / `flyerDownloader` / `tempDirectory` seams
// replace the live RTDB stream, the system sheet, the HTTP flyer download and
// path_provider. (getAllUsers / getStoreLinks swallow their own Firebase
// failures, so they resolve to {} / the fallback Play link without a seam.)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/model/event.dart';

import 'helpers/share_capture.dart';

Event _event({String? imageUrl}) {
  final e = Event()
    ..title = 'Futsal Night'
    ..info = 'Come play'
    ..address = ''
    ..eventDate = 'September 27, 2026'
    ..startDate = DateTime(2026, 9, 27)
    ..eventDateTime = DateTime(2026, 9, 27)
    ..startTime = '6:00PM'
    ..endTime = '8:00PM'
    ..imageUrl = imageUrl;
  return e;
}

void main() {
  late Directory tmp;
  late ShareSheetRecorder recorder;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('event_share_test');
    recorder = ShareSheetRecorder();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpPage(WidgetTester tester, Event event,
      {Future<File?> Function(String url)? flyerDownloader}) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: EventPage(
        index: 0,
        eventStream: Stream<Event?>.value(event),
        shareSheet: recorder.call,
        tempDirectory: () async => tmp,
        flyerDownloader: flyerDownloader,
      ),
    ));
    // Real async for getAllUsers() (its Firebase read fails fast), then frames.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();
  }

  final shareButton = find.widgetWithText(ElevatedButton, 'Share');
  final calendarButton = find.widgetWithText(OutlinedButton, 'Add to my calendar');

  testWidgets('text share (no flyer) is anchored to the Share button',
      (tester) async {
    await pumpPage(tester, _event());
    expect(shareButton, findsOneWidget);

    await tester.tap(shareButton);
    await pumpUntil(tester, () => recorder.calls.isNotEmpty);

    final params = recorder.calls.single;
    expect(params.files, isNull);
    expect(params.text, contains('Futsal Night'));
    expect(params.subject, 'Futsal Night');
    expectShareAnchoredTo(tester, params, shareButton);
  });

  testWidgets('flyer share is anchored to the Share button too',
      (tester) async {
    // The flyer path also copies the caption to the clipboard first.
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final flyer = File('${tmp.path}/flyer.jpg')..writeAsBytesSync([1, 2, 3]);

    await pumpPage(tester, _event(imageUrl: 'https://example.test/flyer.jpg'),
        flyerDownloader: (url) async => flyer);

    await tester.tap(shareButton);
    await pumpUntil(tester, () => recorder.calls.isNotEmpty);

    final params = recorder.calls.single;
    expect(params.files!.single.path, flyer.path);
    expectShareAnchoredTo(tester, params, shareButton);
  });

  testWidgets('"Add to my calendar" .ics share is anchored to its button',
      (tester) async {
    await pumpPage(tester, _event());
    expect(calendarButton, findsOneWidget);

    await tester.tap(calendarButton);
    await pumpUntil(tester, () => recorder.calls.isNotEmpty);

    final params = recorder.calls.single;
    expect(params.files!.single.mimeType, 'text/calendar');
    expect(params.files!.single.path, endsWith('.ics'));
    expectShareAnchoredTo(tester, params, calendarButton);
    // The two buttons must not share an anchor (page-level context would).
    expect(tester.getRect(calendarButton), isNot(tester.getRect(shareButton)));
  });
}
