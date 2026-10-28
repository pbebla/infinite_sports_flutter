// The squad builder's player chip and empty-slot affordance (P3b; sized up
// in the owner's feedback round, Task 3): a BIG photo avatar on top (the
// market's photoUrl via cached_network_image — initials stay the instant
// fallback, photos never gate content), a card-style nameplate below that
// WRAPS (two lines max, soft wrap, never an ellipsis), the price in engine
// tenths, and the armband states — captain = gold-accent ring + 'C' badge
// (colorScheme-derived accent, NOT the chip asset), vice = 'V' badge. A
// week-points line renders only when provided (live wiring lands in P4/P6).
//
// Theme: the fantasy accent pairing (gold in dark, primary red in light —
// the deadline chip's rule); everything else from colorScheme. Photo fade-in
// is 200ms and collapses to zero under reduced motion.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

/// The fantasy accent for this theme: gold on dark, primary red on light —
/// single-sourced on the shared brand surface (FantasyBanner).
Color fantasyAccent(BuildContext context) => FantasyBanner.accent(context);

/// The fantasy photo-or-initials avatar (house rule: photos never gate
/// content — initials render instantly under the load and stay on error).
/// Shared by the squad chip, the market rows and the player detail sheet.
class FantasyAvatar extends StatelessWidget {
  const FantasyAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 44,
  });

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final initials = Center(
      child: Text(
        initialsFor(name),
        style: TextStyle(
          fontSize: size * 0.30,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              fadeInDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              placeholderFadeInDuration: Duration.zero,
              placeholder: (_, __) => initials,
              errorWidget: (_, __, ___) => initials,
            )
          : initials,
    );
  }
}

class FantasyPlayerChip extends StatelessWidget {
  const FantasyPlayerChip({
    super.key,
    required this.name,
    required this.priceTenths,
    this.position,
    this.photoUrl,
    this.isCaptain = false,
    this.isVice = false,
    this.weekPoints,
    this.onTap,
    this.width = 96,
    this.avatarSize = 58,
  });

  final String name;
  final int priceTenths;

  /// Shown on the nameplate ("DEF · $5.5M") when provided — owner feedback.
  final FantasyPosition? position;

  /// Profile photo (Task 3) — null/empty renders the initials fallback
  /// immediately (photos never gate content).
  final String? photoUrl;
  final bool isCaptain;
  final bool isVice;

  /// Rendered only when provided — nothing live feeds it yet (P4/P6).
  final String? weekPoints;

  /// null = not tappable (locked state).
  final VoidCallback? onTap;
  final double width;

  /// Photo avatar diameter — owner: "clear image, can't have them tiny".
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);

    final avatar =
        FantasyAvatar(name: name, photoUrl: photoUrl, size: avatarSize);

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
                  padding: const EdgeInsets.all(2),
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
            const SizedBox(height: 3),
            Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                    width: 0.7),
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
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (position != null) position!.db,
                      formatMoneyTenths(priceTenths),
                      if (isCaptain) '×2',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 10.5,
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
    this.width = 96,
    this.onPitch = false,
  });

  final FantasyPosition position;

  /// null = not tappable (locked state).
  final VoidCallback? onTap;
  final double width;

  /// true for starter slots sitting on the green grass (Task 2): white-on-
  /// green styling reads in BOTH themes there, while bench slots keep the
  /// colorScheme styling of their neutral surface.
  final bool onPitch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final tone = onPitch
        ? Colors.white.withValues(alpha: enabled ? 0.9 : 0.5)
        : (enabled
            ? scheme.onSurfaceVariant
            : scheme.onSurfaceVariant.withValues(alpha: 0.45));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onPitch
                    ? Colors.black.withValues(alpha: 0.18)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                border: Border.all(
                    color: onPitch
                        ? Colors.white.withValues(alpha: 0.65)
                        : scheme.outline.withValues(alpha: 0.6),
                    width: 1.2),
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
