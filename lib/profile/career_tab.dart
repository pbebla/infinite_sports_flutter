import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/trophy_icons.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Data class for a single row in the Career tab.
/// Define here so Task 6 (ProfilePage) imports from this file.
class CareerRow {
  /// URL for the team logo; empty string → fallback shield icon.
  final String teamLogoUrl;

  /// Primary title line, e.g. "Futsal · 2026" or "Summer Cup 2026".
  final String title;

  /// Compact stat summary shown as a subtitle, e.g. "12G · 4A".
  final String summary;

  /// Trophies earned during this stint.
  /// Each entry carries the trophy name and icon key (for [trophyIconWidget]).
  /// Empty list → no trophy decoration is shown.
  final List<({String name, String icon})> trophies;

  /// Optional tap callback. Null → row is not interactive.
  final VoidCallback? onTap;

  const CareerRow({
    required this.teamLogoUrl,
    required this.title,
    required this.summary,
    this.trophies = const [],
    this.onTap,
  });

  /// Convenience getter — true when at least one trophy was earned.
  bool get hasTrophy => trophies.isNotEmpty;
}

/// The "Career" tab of the tabbed player profile.
///
/// Renders [rows] (pre-sorted newest-first by the caller via [careerHistory])
/// as tappable list rows with a team logo, title, optional summary, and a
/// compact row of trophy icons for every trophy earned that stint.
///
/// Empty [rows] → "No history yet." message.
class CareerTab extends StatelessWidget {
  final List<CareerRow> rows;

  const CareerTab({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No history yet.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => _CareerRowTile(row: rows[index]),
    );
  }
}

class _CareerRowTile extends StatelessWidget {
  final CareerRow row;

  const _CareerRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Build subtitle: summary text + optional trophy row.
    Widget? subtitleWidget;

    if (row.summary.isNotEmpty || row.trophies.isNotEmpty) {
      subtitleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (row.summary.isNotEmpty)
            Text(
              row.summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: onSurface.withValues(alpha: 0.6),
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (row.trophies.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: row.trophies.map((t) {
                return Tooltip(
                  message: t.name,
                  child: trophyIconWidget(t.icon, size: 18),
                );
              }).toList(),
            ),
          ],
        ],
      );
    }

    final tile = ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: TeamLogo(
        url: row.teamLogoUrl.isNotEmpty ? row.teamLogoUrl : null,
        size: 36,
      ),
      title: Text(
        row.title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleWidget,
      onTap: row.onTap,
    );

    return tile;
  }
}
