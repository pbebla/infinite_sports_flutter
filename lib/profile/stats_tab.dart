import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

/// Data class representing a single competition entry in the Stats tab.
/// Define here so Task 6 (ProfilePage) imports from this file.
class CompetitionStats {
  final String label;    // e.g. "Futsal · Season 5" or "Summer Cup 2026"
  final String sport;    // e.g. "Futsal", "Basketball", "Flag Football"
  final String position; // raw position string (e.g. "GK", "Guard", "QB")
  final Map<String, num> stats; // statKey → value
  /// Higher = newer. Used by ProfilePage to sort competitions latest-first.
  final int sortKey;

  const CompetitionStats({
    required this.label,
    required this.sport,
    required this.position,
    required this.stats,
    this.sortKey = 0,
  });
}

/// Returns the appropriate icon for a given sport string.
IconData sportIcon(String sport) {
  final s = sport.toLowerCase();
  if (s.contains('basket')) return Icons.sports_basketball;
  if (s.contains('flag') || s.contains('football')) return Icons.sports_football;
  // Futsal, AFC San Jose, Soccer, or any tournament defaulting to soccer-style
  if (s.contains('futsal') || s.contains('afc') || s.contains('soccer')) {
    return Icons.sports_soccer;
  }
  // Tournaments / unknown
  return Icons.emoji_events;
}

/// The "Stats" tab of the tabbed player profile.
///
/// A [DropdownButton] lets the user select a competition (default: index 0).
/// The selected competition's stats are displayed ordered by
/// [profileStatPriority], with human-readable labels.
///
/// Empty [competitions] → "No stats yet." message.
class StatsTab extends StatefulWidget {
  final List<CompetitionStats> competitions;

  /// Initial selection (default 0 = latest). The parent can seed this and will
  /// receive change notifications via [onCompetitionChanged].
  final int initialIndex;

  /// Called whenever the user selects a different competition. The parent
  /// (ProfilePage) uses this to know which competition is active when the
  /// user presses the Share button on the Stats tab.
  final ValueChanged<int>? onCompetitionChanged;

  const StatsTab({
    super.key,
    required this.competitions,
    this.initialIndex = 0,
    this.onCompetitionChanged,
  });

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = (widget.initialIndex >= 0 &&
            widget.initialIndex < widget.competitions.length)
        ? widget.initialIndex
        : 0;
  }

  // Human-readable labels for known stat keys.
  static const Map<String, String> _statLabels = {
    'games': 'Games Played',
    'goals': 'Goals',
    'assists': 'Assists',
    'saves': 'Saves',
    'cleanSheets': 'Clean Sheets',
    'dpl': 'Discipline (DPL)',
    'points': 'Points',
    'rebounds': 'Rebounds',
    'threePointers': '3-Pointers Made',
    'twoPointers': '2-Pointers Made',
    'freeThrows': 'Free Throws Made',
    'passTouchdowns': 'Pass Touchdowns',
    'receivingTouchdowns': 'Receiving Touchdowns',
    'receptions': 'Receptions',
    'catchPercentage': 'Catch %',
    'interceptions': 'Interceptions',
    'flagPulls': 'Flag Pulls',
    'sacks': 'Sacks',
    'passBreakups': 'Pass Breakups',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.competitions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No stats yet.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final comp = widget.competitions[_selectedIndex];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        // Competition selector header
        _competitionHeader(context, comp),
        const SizedBox(height: 16),
        // Stats card
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comp.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  comp.position.isNotEmpty ? comp.position : comp.sport,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                ),
                const Divider(height: 20),
                ..._buildStatRows(context, comp),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Tappable header card that shows the selected competition and opens a
  /// bottom-sheet picker when tapped.
  Widget _competitionHeader(BuildContext context, CompetitionStats selected) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openCompetitionPicker(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              sportIcon(selected.sport),
              size: 22,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  void _openCompetitionPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(sheetCtx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Select Competition',
                style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.competitions.length,
                itemBuilder: (_, i) {
                  final c = widget.competitions[i];
                  final isSelected = i == _selectedIndex;
                  return ListTile(
                    leading: Icon(
                      sportIcon(c.sport),
                      color: isSelected
                          ? Theme.of(sheetCtx).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      c.label,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(sheetCtx).colorScheme.primary
                            : null,
                      ),
                    ),
                    selected: isSelected,
                    onTap: () {
                      setState(() => _selectedIndex = i);
                      widget.onCompetitionChanged?.call(i);
                      Navigator.pop(sheetCtx);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  List<Widget> _buildStatRows(BuildContext context, CompetitionStats comp) {
    if (comp.stats.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No stats recorded.'),
        ),
      ];
    }

    final group = positionGroup(comp.sport, comp.position);
    final priority = profileStatPriority(comp.sport, group);

    // Ordered keys: priority list first (filtered to what's in stats), then
    // any remaining keys not in the priority list.
    final orderedKeys = <String>[
      for (final k in priority)
        if (comp.stats.containsKey(k)) k,
      for (final k in comp.stats.keys)
        if (!priority.contains(k)) k,
    ];

    return orderedKeys
        .map((key) => _StatRow(
              label: _statLabels[key] ?? _humanize(key),
              // Catch % (L6.1) renders with its % suffix; everything else
              // stays a plain count.
              value: key == 'catchPercentage'
                  ? '${_formatValue(comp.stats[key]!)}%'
                  : _formatValue(comp.stats[key]!),
              iconAsset: _statIconAssetForKey(key),
            ))
        .toList();
  }

  /// Maps a profile stat key to the matching StatIcon asset path.
  /// Falls back to null (StatIcon will show its generic fallback).
  static String? _statIconAssetForKey(String key) {
    switch (key) {
      case 'goals':
      case 'cleanSheets':
        return statIconAsset('goal');
      case 'assists':
        return statIconAsset('assist');
      case 'saves':
        return statIconAsset('save');
      case 'dpl':
        return statIconAsset('dpl');
      case 'rebounds':
        return 'assets/rebound.png';
      case 'threePointers':
        return 'assets/threepointer.png';
      case 'twoPointers':
        return 'assets/twopointer.png';
      case 'freeThrows':
        return 'assets/onepointer.png';
      // No asset for these — fall back to generic Material icon via null
      case 'points':
      case 'passTouchdowns':
      case 'receivingTouchdowns':
      case 'receptions':
      case 'interceptions':
      case 'flagPulls':
      case 'sacks':
      case 'passBreakups':
      case 'games':
      default:
        return null;
    }
  }

  static String _formatValue(num v) {
    // Show integers without decimals; keep meaningful decimal places.
    if (v is int) return v.toString();
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  static String _humanize(String key) {
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .trim();
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  /// Asset path for the stat icon. Null → generic bar_chart icon fallback.
  final String? iconAsset;

  const _StatRow({
    required this.label,
    required this.value,
    this.iconAsset,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          // Stat icon
          StatIcon(asset: iconAsset, size: 22),
          const SizedBox(width: 10),
          // Label
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onSurface.withValues(alpha: 0.75),
                  ),
            ),
          ),
          // Value — right-aligned, no dotted spacer
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
