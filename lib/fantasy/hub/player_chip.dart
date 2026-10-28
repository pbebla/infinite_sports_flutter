// The squad builder's player chip and empty-slot affordance (P3b): circular
// initials avatar (photos never gate content — the fantasy market carries no
// photo URLs, so initials are the whole story here), a compact nameplate that
// WRAPS (two lines max, soft wrap, never an ellipsis), the price in engine
// tenths, and the armband states — captain = gold-accent ring + 'C' badge
// (colorScheme-derived accent, NOT the chip asset), vice = 'V' badge. A
// week-points line renders only when provided (live wiring lands in P4/P6).
//
// Theme: the fantasy accent pairing (gold in dark, primary red in light —
// the deadline chip's rule); everything else from colorScheme.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

/// The fantasy accent for this theme: gold on dark, primary red on light —
/// single-sourced on the shared brand surface (FantasyBanner).
Color fantasyAccent(BuildContext context) => FantasyBanner.accent(context);

class FantasyPlayerChip extends StatelessWidget {
  const FantasyPlayerChip({
    super.key,
    required this.name,
    required this.priceTenths,
    this.isCaptain = false,
    this.isVice = false,
    this.weekPoints,
    this.onTap,
    this.width = 84,
  });

  final String name;
  final int priceTenths;
  final bool isCaptain;
  final bool isVice;

  /// Rendered only when provided — nothing live feeds it yet (P4/P6).
  final String? weekPoints;

  /// null = not tappable (locked state).
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);

    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: scheme.surfaceContainerHighest,
      child: Text(
        initialsFor(name),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Captain: gold-accent ring around the avatar.
                Container(
                  key: isCaptain ? ValueKey('captain_ring_$name') : null,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCaptain ? accent : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: avatar,
                ),
                if (isCaptain || isVice)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: _ArmbandBadge(
                      key: ValueKey(
                          isCaptain ? 'captain_badge_$name' : 'vice_badge_$name'),
                      label: isCaptain ? 'C' : 'V',
                      filled: isCaptain,
                      accent: accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    // Wraps to two lines, soft wrap, no ellipsis (house rule:
                    // never ellipsize a name).
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isCaptain
                        ? '${formatMoneyTenths(priceTenths)} · ×2'
                        : formatMoneyTenths(priceTenths),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isCaptain ? accent : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (weekPoints != null)
                    Text(
                      weekPoints!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArmbandBadge extends StatelessWidget {
  const _ArmbandBadge({
    super.key,
    required this.label,
    required this.filled,
    required this.accent,
  });

  final String label;
  final bool filled;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? accent : scheme.surfaceContainerHighest,
        border: filled ? null : Border.all(color: scheme.outline, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          // Gold needs dark text on it; light mode's primary takes onPrimary.
          color: filled
              ? (isDark ? Colors.black : scheme.onPrimary)
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// An unfilled slot: a quiet circular affordance ("+ GK") that opens the
/// picker while editing is open.
class FantasyEmptySlot extends StatelessWidget {
  const FantasyEmptySlot({
    super.key,
    required this.position,
    this.onTap,
    this.width = 84,
  });

  final FantasyPosition position;

  /// null = not tappable (locked state).
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final tone = enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurfaceVariant.withValues(alpha: 0.45);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.6), width: 1.2),
              ),
              child: Icon(Icons.add, size: 20, color: tone),
            ),
            const SizedBox(height: 4),
            Text(
              '+ ${position.db}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
