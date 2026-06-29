import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/widgets/trophy_cabinet.dart';

/// The "Profile" tab of the tabbed player profile.
///
/// Renders in order:
/// 1. **"Player Info"** card — biographical fields.
/// 2. **"Current Team"** card — sport icon, team name, position, jersey #.
/// 3. **Current-season stats** card — stat grid for the active stint.
/// 4. [TrophyCabinet].
///
/// Parameters:
/// - [information] — raw `Users/{uid}/Information` Firebase map.
/// - [awards] — pre-loaded award list.
/// - [current] — active / most-recent [ParticipationStint]; null if none.
/// - [currentTeamNumber] — jersey number for the current stint (if available).
/// - [currentStatsLabel] — display label for the current-season stats card
///   (e.g. "Futsal League Season 13" or "Summer Cup 2026").
/// - [currentStats] — stat items for the current-season card.
class ProfileTab extends StatelessWidget {
  final Map<dynamic, dynamic> information;
  final List<Award> awards;
  final ParticipationStint? current;
  final String? currentTeamNumber;
  final String? currentStatsLabel;
  final List<({String label, String value})> currentStats;

  const ProfileTab({
    super.key,
    required this.information,
    required this.awards,
    this.current,
    this.currentTeamNumber,
    this.currentStatsLabel,
    this.currentStats = const [],
  });

  // Known fields shown in this exact order when present and non-empty.
  static const List<({String key, String label})> _knownFields = [
    (key: 'Height', label: 'Height'),
    (key: 'Weight', label: 'Weight'),
    (key: 'Age', label: 'Age'),
    (key: 'Foot', label: 'Preferred Foot'),
    (key: 'PreferredFoot', label: 'Preferred Foot'),
    (key: 'Hand', label: 'Preferred Hand'),
    (key: 'PreferredHand', label: 'Preferred Hand'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_hasAnyInfo()) _infoCard(context),
        _currentTeamCard(context),
        if (current != null &&
            currentStatsLabel != null &&
            currentStats.isNotEmpty)
          _currentSeasonStatsCard(context),
        TrophyCabinet(awards: awards),
      ],
    );
  }

  bool _hasAnyInfo() {
    if (information.isEmpty) return false;
    return _resolvedRows().isNotEmpty;
  }

  /// Build the ordered list of (label, value) pairs to display.
  List<({String label, String value})> _resolvedRows() {
    final rows = <({String label, String value})>[];
    final usedKeys = <String>{};
    // Deduplicate known labels (Foot / PreferredFoot both map to the same
    // display row — show the first one that has a value).
    final shownLabels = <String>{};

    for (final field in _knownFields) {
      if (shownLabels.contains(field.label)) continue;
      final raw = information[field.key];
      final value = _stringify(raw);
      if (value.isNotEmpty) {
        rows.add((label: field.label, value: value));
        shownLabels.add(field.label);
      }
      usedKeys.add(field.key);
    }

    // Remaining keys: exclude *Position variants and already-used keys.
    for (final entry in information.entries) {
      final key = entry.key.toString();
      if (usedKeys.contains(key)) continue;
      if (key.endsWith('Position')) continue;
      final value = _stringify(entry.value);
      if (value.isEmpty) continue;
      rows.add((label: _humanize(key), value: value));
    }

    return rows;
  }

  static String _stringify(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    return s == 'null' || s == '0' ? '' : s;
  }

  /// Insert spaces before capital letters: `JerseySize` → `Jersey Size`.
  static String _humanize(String key) {
    return key.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => ' ${m.group(0)}',
    ).trim();
  }

  Widget _infoCard(BuildContext context) {
    final rows = _resolvedRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Player Info',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 10),
            ...rows.map((r) => _InfoRow(label: r.label, value: r.value)),
          ],
        ),
      ),
    );
  }

  Widget _currentTeamCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Team',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 10),
            if (current == null)
              Text(
                'Not currently on a roster.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    _sportIcon(current!.sport),
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current!.team,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (current!.position.isNotEmpty ||
                            (currentTeamNumber?.isNotEmpty ?? false))
                          Wrap(
                            spacing: 8,
                            children: [
                              if (current!.position.isNotEmpty)
                                Text(
                                  current!.position,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                              if (currentTeamNumber?.isNotEmpty ?? false)
                                Text(
                                  '#$currentTeamNumber',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _currentSeasonStatsCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentStatsLabel!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: currentStats
                  .map((s) => _StatCell(label: s.label, value: s.value))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _sportIcon(String sport) {
    switch (sport) {
      case 'Basketball':
        return Icons.sports_basketball;
      case 'Flag Football':
        return Icons.sports_football;
      case 'Tournament':
        return Icons.emoji_events;
      default:
        // Futsal, AFC San Jose, Soccer — all soccer ball
        return Icons.sports_soccer;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.6),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
