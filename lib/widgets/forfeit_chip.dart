// The "Forfeit" label on league match displays (spec §8a: fan match pages
// label a forfeited game "5–0 · Forfeit"). One shared pill for the match
// list cards, the team page rows' trailing score and the match page header,
// so the wording and colors never drift. Theme-safe in both modes: the
// Material 3 tertiary-container pair only (no hardcoded palette).

import 'package:flutter/material.dart';

class ForfeitChip extends StatelessWidget {
  const ForfeitChip({super.key, this.fontSize = 10.5});

  final double fontSize;

  /// The label text (tests and semantic callers share it).
  static const String label = 'Forfeit';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.7, vertical: fontSize * 0.18),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(fontSize),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
