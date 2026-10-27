// The Infinite Fantasy banner card (P3a Task 2): a dark gradient surface in
// BOTH themes carrying the gold wordmark — the house rule for the fantasy
// brand (plan hard gates). Reused by the hub header and the league page's
// Fantasy entry card.

import 'package:flutter/material.dart';

class FantasyBanner extends StatelessWidget {
  const FantasyBanner({super.key, this.subtitle, this.bottom});

  /// Muted line under the wordmark (e.g. "Futsal · Season 15").
  final String? subtitle;

  /// Optional row pinned under the text (e.g. the deadline chip or the entry
  /// button).
  final Widget? bottom;

  /// Deliberately NOT theme-derived: the banner stays a dark, subtly-lit
  /// card in light mode too, so the gold wordmark always sits on dark.
  static const Color gradientTop = Color(0xFF15171E);
  static const Color gradientBottom = Color(0xFF262A38);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientTop, gradientBottom],
        ),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/fantasy/fantasy_logo.png',
            height: 52,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (bottom != null) ...[
            const SizedBox(height: 14),
            bottom!,
          ],
        ],
      ),
    );
  }
}
