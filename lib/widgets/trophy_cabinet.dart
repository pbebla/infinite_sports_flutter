import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/trophy_icons.dart';
import 'package:infinite_sports_flutter/model/award.dart';

// ─── Grouping helper ──────────────────────────────────────────────────────────

/// Groups [awards] by trophyId (or name when trophyId is empty) and returns
/// an ordered list of groups, preserving the first-seen order of each group.
List<List<Award>> _groupAwards(List<Award> awards) {
  final seen = <String, int>{};
  final groups = <List<Award>>[];

  for (final a in awards) {
    final key = a.trophyId.isNotEmpty ? a.trophyId : a.name;
    if (seen.containsKey(key)) {
      groups[seen[key]!].add(a);
    } else {
      seen[key] = groups.length;
      groups.add([a]);
    }
  }

  // Within each group sort newest-first by date (MMDDYYYY → YYYY first).
  for (final group in groups) {
    group.sort((a, b) {
      final da = _dateForSort(a.date);
      final db = _dateForSort(b.date);
      return db.compareTo(da); // descending → newest first
    });
  }

  return groups;
}

/// Converts an MMDDYYYY string to YYYYMMDD for lexicographic sort.
String _dateForSort(String raw) {
  if (raw.length == 8) {
    try {
      return '${raw.substring(4)}${raw.substring(0, 2)}${raw.substring(2, 4)}';
    } catch (_) {}
  }
  return raw;
}

// ─── TrophyCabinet ────────────────────────────────────────────────────────────

class TrophyCabinet extends StatelessWidget {
  final List<Award> awards;

  const TrophyCabinet({super.key, required this.awards});

  @override
  Widget build(BuildContext context) {
    if (awards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Text(
            'No trophies yet — go win some! 🏆',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final groups = _groupAwards(awards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Trophy Cabinet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: groups
                .map((group) => _TrophyChip(group: group))
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─── Tile ─────────────────────────────────────────────────────────────────────

class _TrophyChip extends StatelessWidget {
  /// All awards in this group (same trophyId/name). Pre-sorted newest-first.
  final List<Award> group;

  const _TrophyChip({required this.group});

  Award get _rep => group.first; // representative award (newest)

  String _formatDate(String raw) {
    if (raw.length == 8) {
      try {
        final month = raw.substring(0, 2);
        final day = raw.substring(2, 4);
        final year = raw.substring(4, 8);
        const monthNames = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final m = int.tryParse(month) ?? 0;
        final d = int.tryParse(day) ?? 0;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return '${monthNames[m]} $d, $year';
        }
      } catch (_) {}
    }
    return raw;
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) {
        final color = tierColor(_rep.tier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    isAssetIcon(_rep.icon)
                        ? trophyIconWidget(_rep.icon, size: 56)
                        : CircleAvatar(
                            radius: 28,
                            backgroundColor: color,
                            child: Icon(
                              trophyIconData(_rep.icon),
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _rep.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (group.length > 1) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Earned ${group.length}×',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── Occurrence list ──────────────────────────────────────────
                ...group.map((award) {
                  final lines = <String>[];
                  if (award.context.isNotEmpty) lines.add(award.context);
                  if (award.sport.isNotEmpty) lines.add(award.sport);
                  if (award.season.isNotEmpty) {
                    final last = lines.isNotEmpty ? lines.last : '';
                    // Append season to the sport line if it's the same string
                    if (last == award.sport) {
                      lines[lines.length - 1] =
                          '${award.sport} · Season ${award.season}';
                    } else {
                      lines.add('Season ${award.season}');
                    }
                  }
                  if (award.date.isNotEmpty) {
                    lines.add(_formatDate(award.date));
                  }
                  final subtitle = lines.join('\n');

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Subtle bullet
                        Padding(
                          padding: const EdgeInsets.only(top: 3, right: 8),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            subtitle.isNotEmpty ? subtitle : '—',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = tierColor(_rep.tier);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final count = group.length;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon with optional ×N badge ──────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                isAssetIcon(_rep.icon)
                    ? trophyIconWidget(_rep.icon, size: 44)
                    : CircleAvatar(
                        radius: 22,
                        backgroundColor: color,
                        child: Icon(
                          trophyIconData(_rep.icon),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                if (count > 1)
                  Positioned(
                    right: -6,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '×$count',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _rep.name,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // For a single award keep context line; for grouped show count pill
            if (count == 1 && _rep.context.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                _rep.context,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

