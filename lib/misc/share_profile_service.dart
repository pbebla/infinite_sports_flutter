import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';

/// Renders [card] (any fixed-size share-card widget) offscreen to a PNG and
/// opens the system share sheet with [shareText] as the caption.
///
/// A thin wrapper over [shareCardImage] (share_card_service.dart) so the
/// RepaintBoundary / Overlay / temp-file pipeline lives in exactly one place.
///
/// Never throws; shows a SnackBar on failure.
Future<void> shareProfileCard(
  BuildContext context,
  Widget card, {
  required String shareText,
}) =>
    shareCardImage(
      context,
      card,
      caption: shareText,
      filePrefix: 'profile_card',
    );
