import 'package:flutter/material.dart';

/// The branded strip along the bottom of every share card (match, profile,
/// Infinite Fantasy stories): the Infinite Sports mark + "Follow Infinite
/// Sports for live scores". Theme-independent — share images are fixed art.
class ShareCardFooter extends StatelessWidget {
  const ShareCardFooter({super.key});

  static const Color background = Color(0xFF111111);
  static const Color brandRed = Color(0xFFFF5A5A);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('share_card_footer'),
      color: background,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/infinite_mark.png', height: 34),
          const SizedBox(width: 6),
          const Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Follow '),
                  TextSpan(
                    text: 'Infinite Sports',
                    style: TextStyle(color: brandRed),
                  ),
                  TextSpan(text: ' for live scores'),
                ],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
