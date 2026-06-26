import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';

/// Data class representing a single competition entry in the Stats tab.
/// Define here so Task 6 (ProfilePage) imports from this file.
class CompetitionStats {
  final String label;    // e.g. "Futsal · Season 5" or "Summer Cup 2026"
  final String sport;    // e.g. "Futsal", "Basketball", "Flag Football"
  final String position; // raw position string (e.g. "GK", "Guard", "QB")
  final Map<String, num> stats; // statKey → value

  const CompetitionStats({
    required this.label,
    required this.sport,
    required this.position,
    required this.stats,
  });
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

  const StatsTab({super.key, required this.competitions});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  int _selectedIndex = 0;

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
        // Competition selector
        if (widget.competitions.length > 1) ...[
          _competitionDropdown(context),
          const SizedBox(height: 16),
        ],
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

  Widget _competitionDropdown(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: _selectedIndex,
      decoration: InputDecoration(
        labelText: 'Competition',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        for (int i = 0; i < widget.competitions.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              widget.competitions[i].label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _selectedIndex = v);
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
              value: _formatValue(comp.stats[key]!),
            ))
        .toList();
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

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onSurface.withValues(alpha: 0.75),
                  ),
            ),
          ),
          // Dotted spacer
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '..............................',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.15),
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
