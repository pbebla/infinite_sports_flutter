import 'dart:io';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Renders [card] (any fixed-size share-card widget) offscreen to a PNG and
/// opens the system share sheet with [shareText] as the caption.
///
/// Reuses [captureCardToPng] from share_match_card_service so the
/// RepaintBoundary / Overlay pipeline lives in exactly one place.
///
/// Never throws; shows a SnackBar on failure.
Future<void> shareProfileCard(
  BuildContext context,
  Widget card, {
  required String shareText,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (!context.mounted) return;

    final bytes = await captureCardToPng(context, card);

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/profile_card_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: shareText),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't create the share card.")),
    );
  }
}
