import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// A single shareable image with the words up top so they're never missed:
/// a brand header (title + when/where), the owner's caption, then the flyer,
/// then the app call-to-action. Baking everything into one image means the
/// text always travels with the flyer (many apps drop separate text when an
/// image is attached). Rendered offscreen to PNG via captureCardToPng.
class EventShareCard extends StatelessWidget {
  const EventShareCard({
    super.key,
    required this.title,
    this.flyer,
    this.caption,
    this.dateLine,
    this.location,
  });

  /// Pre-resolved flyer image (precache the NetworkImage before capturing).
  final ImageProvider? flyer;
  final String title;
  final String? caption;
  final String? dateLine;
  final String? location;

  @override
  Widget build(BuildContext context) {
    const width = 420.0;
    final whenWhere = [dateLine, location]
        .where((s) => (s ?? '').trim().isNotEmpty)
        .join('  ·  ');
    final hasCaption = (caption ?? '').trim().isNotEmpty;

    return Container(
      width: width,
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand header — title + when/where, always the first thing seen.
          Container(
            color: infiniteSportsPrimaryColor,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                if (whenWhere.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(whenWhere,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white70)),
                  ),
              ],
            ),
          ),
          // Owner's caption, right under the header so it reads first.
          if (hasCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(caption!.trim(),
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500)),
            ),
          // Flyer.
          if (flyer != null)
            Padding(
              padding: EdgeInsets.only(top: hasCaption ? 12 : 12),
              child: Image(image: flyer!, width: width, fit: BoxFit.fitWidth),
            ),
          // App call-to-action footer.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Image.asset('assets/infinitelarge_dark.png', height: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Download the Infinite Sports app for details and to sign up!',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
