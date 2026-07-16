import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// A single shareable image: the event flyer with a caption strip baked in
/// below it, so the words always travel with the flyer (many apps drop
/// separate text when an image is attached). Rendered offscreen to PNG via
/// captureCardToPng, mirroring the match/profile share cards.
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
    return Container(
      width: width,
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (flyer != null)
            Image(image: flyer!, width: width, fit: BoxFit.fitWidth)
          else
            Container(
              width: width,
              height: 160,
              color: infiniteSportsPrimaryColor,
              alignment: Alignment.center,
              child: const Icon(Icons.event, color: Colors.white, size: 64),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                if ((dateLine ?? '').isNotEmpty || (location ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [dateLine, location].where((s) => (s ?? '').isNotEmpty).join('  ·  '),
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                if ((caption ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(caption!.trim(),
                        style: const TextStyle(fontSize: 15, color: Colors.black87)),
                  ),
                const SizedBox(height: 14),
                Row(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
