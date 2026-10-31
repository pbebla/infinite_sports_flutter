// Achievement badges in the fan app (spec 2026-10-30 §5):
//
//   * [BadgeShelf] — a wrapping row of badge chips (icon or uploaded
//     picture + name + "×3" when repeated), one chip per badge. Shown on the
//     Infinite profile's Fantasy tab (manager section) and at the top of the
//     manager squad viewer. Tap a chip → [showBadgeDetailSheet].
//   * [BadgeDetailSheet] — name, description, when earned ("GW3, GW7, GW9" /
//     "Season 15"), and for owner-given badges "Given by Infinite Sports"
//     plus the owner's notes.
//   * [BadgeCountChip] — the leaderboard's small military_tech + N beside a
//     manager's name (Overall + Gameweek); nothing at 0.
//
// Data: fantasy_badges.dart (pure). Earned badges always show — an inactive
// catalog entry included; an id missing from the catalog is a generic badge.
//
// House rules: light + dark via colorScheme and the fantasy accent (gold in
// dark, primary red in light); names WRAP (never ellipsized/underlined) and
// the chips wrap onto new lines at 360 px; a picture never gates the chip
// (the icon is its placeholder and error fallback).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart'
    show fantasyAccent;

/// The curated badge icon keys (the server's starter set + the Manager's
/// picker) → Material icons.
const Map<String, IconData> kBadgeIcons = {
  'military_tech': Icons.military_tech,
  'auto_awesome': Icons.auto_awesome,
  'event_seat': Icons.event_seat,
  'diamond': Icons.diamond,
  'emoji_events': Icons.emoji_events,
  'calendar_month': Icons.calendar_month,
  'workspace_premium': Icons.workspace_premium,
  'looks_two': Icons.looks_two,
  'looks_3': Icons.looks_3,
  'star': Icons.star,
  'local_fire_department': Icons.local_fire_department,
  'bolt': Icons.bolt,
  'sports_soccer': Icons.sports_soccer,
  'verified': Icons.verified,
  'celebration': Icons.celebration,
  'favorite': Icons.favorite,
  'thumb_up': Icons.thumb_up,
};

/// A catalog icon key → its Material icon; unknown keys → military_tech.
IconData badgeIconFor(String key) =>
    kBadgeIcons[key] ?? Icons.military_tech;

/// A badge's picture (when the catalog has one) or its icon, in the fantasy
/// accent. Keyed `badge_image_<id>` / `badge_icon_<id>`.
class BadgeVisual extends StatelessWidget {
  const BadgeVisual({
    super.key,
    required this.badgeId,
    required this.entry,
    this.size = 20,
  });

  final String badgeId;

  /// null = an id the catalog doesn't know (the generic icon).
  final FantasyBadgeCatalogEntry? entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = fantasyAccent(context);
    final iconData = badgeIconFor(entry?.icon ?? kDefaultBadgeIcon);
    final url = entry?.imageUrl;
    if (url == null || url.isEmpty) {
      return Icon(iconData,
          key: ValueKey('badge_icon_$badgeId'), size: size, color: accent);
    }
    final fallback = Icon(iconData, size: size, color: accent);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      key: ValueKey('badge_image_$badgeId'),
      width: size,
      height: size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          fadeInDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          placeholderFadeInDuration: Duration.zero,
          // The icon stands in while the picture loads (never gates) and if
          // it fails.
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// A manager's earned badges as wrapping chips (one per badge, "×N" when
/// repeated), in catalog order. Empty: [emptyText] as a muted line, or
/// nothing when it is null.
class BadgeShelf extends StatelessWidget {
  const BadgeShelf({
    super.key,
    required this.awards,
    required this.catalog,
    required this.season,
    this.emptyText,
  });

  final List<FantasyBadgeAward> awards;
  final FantasyBadgeCatalog catalog;

  /// The season number ("15") — the sheet's "Season 15".
  final String season;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final groups = groupBadgeAwards(awards, catalog);
    if (groups.isEmpty) {
      final text = emptyText;
      if (text == null) return const SizedBox.shrink();
      return Text(
        text,
        key: const ValueKey('badge_shelf_empty'),
        softWrap: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      );
    }
    return Wrap(
      key: const ValueKey('badge_shelf'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in groups) _BadgeChip(group: g, season: season),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.group, required this.season});

  final FantasyBadgeGroup group;
  final String season;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final radius = BorderRadius.circular(18);
    return Material(
      color: accent.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        key: ValueKey('badge_chip_${group.badgeId}'),
        borderRadius: radius,
        onTap: () => showBadgeDetailSheet(context, group, season: season),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeVisual(badgeId: group.badgeId, entry: group.entry),
              const SizedBox(width: 6),
              // A long name wraps inside the chip (never ellipsized).
              Flexible(
                child: Text(
                  group.name,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (group.count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '×${group.count}',
                  key: ValueKey('badge_chip_count_${group.badgeId}'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [BadgeDetailSheet] for [group] as a modal bottom sheet.
Future<void> showBadgeDetailSheet(
  BuildContext context,
  FantasyBadgeGroup group, {
  required String season,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: BadgeDetailSheet(group: group, season: season),
        ),
      ),
    );

/// One badge, explained: what it is, when it was earned, and who gave it.
class BadgeDetailSheet extends StatelessWidget {
  const BadgeDetailSheet({
    super.key,
    required this.group,
    required this.season,
  });

  final FantasyBadgeGroup group;
  final String season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = fantasyAccent(context);
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final description = group.description.trim();
    final notes = group.notes;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      color: muted,
    );

    return Padding(
      key: const ValueKey('badge_sheet'),
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                ),
                child: BadgeVisual(
                    badgeId: group.badgeId, entry: group.entry, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      key: const ValueKey('badge_sheet_name'),
                      softWrap: true,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (group.count > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Earned ${group.count}×',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              description,
              key: const ValueKey('badge_sheet_description'),
              softWrap: true,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Text('EARNED', style: labelStyle),
          const SizedBox(height: 4),
          Text(
            badgeEarnedLine(group, season: season),
            key: const ValueKey('badge_sheet_earned'),
            softWrap: true,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (group.hasManual) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.verified, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kBadgeGivenByCopy,
                    key: const ValueKey('badge_sheet_given_by'),
                    softWrap: true,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            for (final (i, note) in notes.indexed) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Text(
                  '“$note”',
                  key: ValueKey('badge_sheet_note_$i'),
                  softWrap: true,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The leaderboard's badge count beside a manager's name: military_tech + N
/// in the fantasy accent, read as "N badges". Nothing at all when [count] is
/// 0 or less.
class BadgeCountChip extends StatelessWidget {
  const BadgeCountChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final accent = fantasyAccent(context);
    final label = count == 1 ? '1 badge' : '$count badges';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      // Its own semantics node: read as one phrase, not merged into the name.
      child: Semantics(
        container: true,
        label: label,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(3, 1, 6, 1),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.military_tech, size: 14, color: accent),
                const SizedBox(width: 2),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
