// The ONE share-card pipeline (match cards, profile cards, the Infinite
// Fantasy story images): render a fixed-size widget offscreen to a PNG, write
// it to a temp file, and open the system share sheet with a caption.
//
// iOS parity: on iPad the share sheet is a popover and share_plus REJECTS a
// share without a non-empty `sharePositionOrigin` inside the root view, so
// every share here anchors itself to the tapped widget ([shareOriginFor]).
// The same goes for EVERY other share in the app (text invites, join codes,
// event flyers, calendar files): build the [ShareParams] with
// `sharePositionOrigin: shareOriginFor(buttonContext)` and hand them to
// [openShareSheet] (or an injected [ShareSheet] in tests) — never call
// SharePlus / Share directly.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a rendered card (PNG bytes) and its caption to a share sheet,
/// anchored at [origin] (global coordinates; the iPad popover's anchor).
/// The real one writes a temp file and opens the system sheet
/// ([sharePngWithSystemSheet]); widget tests inject a recorder.
typedef SharePng = Future<void> Function(
    Uint8List png, String caption, Rect? origin);

/// Hands finished [ShareParams] (text, files, subject AND the iPad popover
/// anchor `sharePositionOrigin`) to a share sheet. The real one is
/// [openShareSheet]; widget tests inject a recorder and assert the origin.
typedef ShareSheet = Future<void> Function(ShareParams params);

/// Opens the system share sheet with [params] — the ONE place (with
/// [sharePngWithSystemSheet]) the app touches share_plus, so a call site
/// can't forget the iPad anchor without it being visible in its own params.
Future<void> openShareSheet(ShareParams params) async {
  await SharePlus.instance.share(params);
}

/// The first eight bytes of every PNG file.
const List<int> kPngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// Renders [card] offscreen via a transparent root-overlay entry and returns
/// the PNG bytes at [pixelRatio] (a 360-wide card at 3.0 -> 1080 px).
Future<Uint8List> captureCardToPng(
  BuildContext context,
  Widget card, {
  double pixelRatio = 3.0,
}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(key: key, child: card),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 32));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// The global rect of the widget behind [context] (the tapped button, or a
/// whole page), clipped to the screen — the iPad share popover's anchor.
/// null when it has no laid-out box or nothing of it is on screen.
Rect? shareOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.maybeSizeOf(context);
  final clipped = screen == null ? rect : rect.intersect(Offset.zero & screen);
  return clipped.isEmpty ? null : clipped;
}

/// Writes [png] to a temp file named [fileName] and opens the system share
/// sheet with [caption], anchored at [origin] (required on iPad).
Future<void> sharePngWithSystemSheet(
  Uint8List png, {
  required String caption,
  required String fileName,
  Rect? origin,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(png);
  await openShareSheet(
    ShareParams(
      files: [XFile(file.path)],
      text: caption,
      sharePositionOrigin: origin,
    ),
  );
}

/// Precaches [precache] (assets, photos — failures ignored, the card's own
/// fallbacks show), renders [card] to a PNG and shares it with [caption].
/// The share sheet anchors to [context]'s widget (pass the tapped button's
/// context). [share] replaces the system sheet (tests); the default writes
/// `<filePrefix>_<timestamp>.png`.
///
/// Waits at most [precacheTimeout] for images (photos never gate the share).
/// Never throws; shows a SnackBar on failure.
Future<void> shareCardImage(
  BuildContext context,
  Widget card, {
  required String caption,
  String filePrefix = 'share_card',
  double pixelRatio = 3.0,
  List<ImageProvider> precache = const [],
  Duration precacheTimeout = const Duration(seconds: 3),
  SharePng? share,
}) async {
  ScaffoldMessengerState? messenger;
  try {
    // Both context lookups sit INSIDE the try (a stale context asserts) and
    // run NOW, before any await: the messenger outlives the awaits below and
    // the popover anchors to the tapped widget as it is at tap time.
    messenger = ScaffoldMessenger.maybeOf(context);
    final origin = shareOriginFor(context);
    if (precache.isNotEmpty) {
      // .timeout cancels its timer once the images land (no stray timer).
      await Future.wait([
        for (final image in precache)
          precacheImage(image, context, onError: (_, __) {}),
      ]).timeout(precacheTimeout, onTimeout: () => const []);
    }
    if (!context.mounted) return;

    final bytes = await captureCardToPng(context, card, pixelRatio: pixelRatio);

    final sink = share ??
        (png, text, anchor) => sharePngWithSystemSheet(
              png,
              caption: text,
              fileName:
                  '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.png',
              origin: anchor,
            );
    await sink(bytes, caption, origin);
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't create the share card.")),
    );
  }
}
