import 'package:flutter/material.dart';
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

  /// When true, a 🏆 badge is shown on the trailing side.
  final bool hasTrophy;

  /// Optional tap callback. Null → row is not interactive.
  final VoidCallback? onTap;

  const CareerRow({
    required this.teamLogoUrl,
    required this.title,
    required this.summary,
    this.hasTrophy = false,
    this.onTap,
  });
}

/// The "Career" tab of the tabbed player profile.
///
/// Renders [rows] (pre-sorted newest-first by the caller via [careerHistory])
/// as tappable list rows with a team logo, title, optional summary, and an
/// optional trophy badge.
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
      subtitle: row.summary.isNotEmpty
          ? Text(
              row.summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: onSurface.withValues(alpha: 0.6),
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: row.hasTrophy
          ? const Text(
              '🏆',
              style: TextStyle(fontSize: 20),
            )
          : null,
      onTap: row.onTap,
    );

    // Wrap in InkWell only when there is an onTap, so the splash is scoped to
    // the tile bounds. ListTile already does this internally when onTap != null,
    // so we just return the tile directly.
    return tile;
  }
}
