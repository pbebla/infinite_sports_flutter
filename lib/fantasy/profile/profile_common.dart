// Shared building blocks of the fantasy player profile (round 3, spec §4):
// the card surface, a section card, the stat tile, the friendly empty note
// and the up/down tones. Light + dark via colorScheme only; the fantasy
// accent (gold on dark, primary red on light) comes from fantasyAccent; the
// "up" green is the hub's pitch green (reads on both surfaces).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

/// Price/points rising tone.
Color profileUpColor(BuildContext context) => fantasyPitchGreen(context);

/// Price/points falling tone.
Color profileDownColor(BuildContext context) =>
    Theme.of(context).colorScheme.error;

/// The tone for a signed move (null/0 = muted).
Color profileMoveColor(BuildContext context, int? move) {
  if (move == null || move == 0) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  return move > 0 ? profileUpColor(context) : profileDownColor(context);
}

/// The profile's card surface (mockup: a raised rounded panel on the page).
BoxDecoration profileCardDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
  );
}

/// A titled section card.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
  });

  final String? title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: profileCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              softWrap: true,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// A small label-over-value tile (the mockup's season stats grid).
class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// [tiles] laid out [perRow] to a row with even gaps (wraps cleanly at
/// phone widths).
class ProfileTileGrid extends StatelessWidget {
  const ProfileTileGrid({super.key, required this.tiles, this.perRow = 3});

  final List<Widget> tiles;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - (perRow - 1) * gap) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: width, child: t),
          ],
        );
      },
    );
  }
}

/// A friendly empty state inside a card (no data yet ≠ zeros).
class ProfileEmptyNote extends StatelessWidget {
  const ProfileEmptyNote({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: profileCardDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One "label ··· value" line (points by source, a week's breakdown).
class ProfileLineRow extends StatelessWidget {
  const ProfileLineRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
