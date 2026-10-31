// Test helpers for the share-card pipeline (share_card_service.dart): the
// offscreen capture needs real frames (pump) AND real async (image decode,
// RenderRepaintBoundary.toImage, PNG encode — tester.runAsync), so a tap
// that starts a share is driven by alternating the two until it lands.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:share_plus/share_plus.dart' show ShareParams;

/// One recorded call of the injected [SharePng] seam.
typedef SharedCard = ({Uint8List png, String caption, Rect? origin});

/// A [SharePng] recorder: every call lands in [calls].
class ShareRecorder {
  final List<SharedCard> calls = [];

  Future<void> call(Uint8List png, String caption, Rect? origin) async {
    calls.add((png: png, caption: caption, origin: origin));
  }
}

/// A [ShareSheet] recorder (the text / file shares: invites, join codes,
/// event flyers, calendar files): every call's finished [ShareParams] lands in
/// [calls], so a test can assert the iPad popover anchor on the very object
/// share_plus would receive.
class ShareSheetRecorder {
  final List<ShareParams> calls = [];

  Future<void> call(ShareParams params) async {
    calls.add(params);
  }
}

/// iPad parity: share_plus REJECTS a share without a non-empty
/// `sharePositionOrigin` inside the view. Asserts [params] carries one AND that
/// it is the rect of the tapped [button] (not the whole page), so the popover
/// points at the button. [button] must be fully on screen.
void expectShareAnchoredTo(
    WidgetTester tester, ShareParams params, Finder button) {
  final origin = params.sharePositionOrigin;
  expect(origin, isNotNull,
      reason: 'share_plus rejects an iPad share with no sharePositionOrigin');
  expect(origin!.isEmpty, isFalse);
  expect(origin, tester.getRect(button),
      reason: 'the popover must anchor to the tapped button');
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
