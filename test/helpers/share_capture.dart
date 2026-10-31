// Test helpers for the share-card pipeline (share_card_service.dart): the
// offscreen capture needs real frames (pump) AND real async (image decode,
// RenderRepaintBoundary.toImage, PNG encode — tester.runAsync), so a tap
// that starts a share is driven by alternating the two until it lands.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';

/// One recorded call of the injected [SharePng] seam.
typedef SharedCard = ({Uint8List png, String caption, Rect? origin});

/// A [SharePng] recorder: every call lands in [calls].
class ShareRecorder {
  final List<SharedCard> calls = [];

  Future<void> call(Uint8List png, String caption, Rect? origin) async {
    calls.add((png: png, caption: caption, origin: origin));
  }
}

/// Alternates frames and real async until [done] (or ~10 s of real time).
Future<void> pumpUntil(WidgetTester tester, bool Function() done,
    {int maxRounds = 200}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// True when [bytes] start with the PNG file signature.
bool isPng(Uint8List bytes) =>
    bytes.length > kPngSignature.length &&
    listEquals(bytes.sublist(0, kPngSignature.length), kPngSignature);

/// The pixel size in a PNG's IHDR chunk (bytes 16..23, big-endian).
Size pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
}
