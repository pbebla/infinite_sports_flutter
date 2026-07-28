import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Data class representing a single competition entry in the Career tab.
/// Define here so Task 6 (ProfilePage) imports from this file.
class CompetitionStats {
  final String label;    // e.g. "Futsal · Season 5" or "Summer Cup 2026"
  final String sport;    // e.g. "Futsal", "Basketball", "Flag Football"
  final String position; // raw position string (e.g. "GK", "Guard", "QB")
  /// Team the player was on for this competition ('' when unknown).
  final String team;
  /// Resolved team logo URL ('' → no logo rendered, name only).
  final String teamLogoUrl;
  final Map<String, num> stats; // statKey → value
  /// Higher = newer. Used by ProfilePage to sort competitions latest-first.
  final int sortKey;

  const CompetitionStats({
    required this.label,
    required this.sport,
    required this.position,
    this.team = '',
    this.teamLogoUrl = '',
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

/// The "Career" tab of the tabbed player profile (PR #10 — the former
/// "Stats" tab, which absorbed the old career-history tab).
///
/// A picker lets the user select a competition (default: index 0 = most
/// recent) or "Show all", which stacks every competition on one page. The
/// selected competition's stats are displayed ordered by
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
  /// user presses the Share button on the Career tab. Not called for
  /// "Show all" — the share card keeps the last single selection.
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

  /// "Show all" picker option: every competition stacked on one page.
  bool _showAll = false;

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
    // L6.2 Task 5: these gain gold badge icons — give them a matching
    // Title Case label instead of falling through to _humanize (which only
    // splits on capital letters, so an all-lowercase key like 'steals'
    // would otherwise render as-is).
    'steals': 'Steals',
    'blocks': 'Blocks',
    'turnovers': 'Turnovers',
    'fouls': 'Fouls',
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

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        // Competition selector header
        _competitionHeader(context),
        const SizedBox(height: 16),
        if (_showAll)
          // Every competition stacked — list order is the parent's
          // newest-first sort, so the most recent card is on top.
          for (var i = 0; i < widget.competitions.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _competitionCard(context, widget.competitions[i]),
          ]
        else
          _competitionCard(context, widget.competitions[_selectedIndex]),
      ],
    );
  }

  /// One competition's stats card: label, team + position line, stat rows.
  Widget _competitionCard(BuildContext context, CompetitionStats comp) {
    return Card(
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
            _teamPositionLine(context, comp),
            const Divider(height: 20),
            ..._buildStatRows(context, comp),
          ],
        ),
      ),
    );
  }

  /// "[logo] Lamassu · Defender" — team (with logo when one resolved) before
  /// the position (PR #10). No team recorded → the old position/sport line.
  /// A missing logo shows just the name — never a broken image or fallback.
  Widget _teamPositionLine(BuildContext context, CompetitionStats comp) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        );
    if (comp.team.isEmpty) {
      return Text(
        comp.position.isNotEmpty ? comp.position : comp.sport,
        style: style,
      );
    }
    final text = comp.position.isNotEmpty
        ? '${comp.team} · ${comp.position}'
        : comp.team;
    return Row(
      children: [
        if (comp.teamLogoUrl.isNotEmpty) ...[
          TeamLogo(url: comp.teamLogoUrl, size: 18),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  /// Tappable header card that shows the current selection ("Show all" or a
  /// single competition) and opens a bottom-sheet picker when tapped.
  Widget _competitionHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected =
        _showAll ? null : widget.competitions[_selectedIndex];
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
              selected != null ? sportIcon(selected.sport) : Icons.view_agenda,
              size: 22,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected?.label ?? 'All competitions',
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
                // +1 for the "Show all" entry at the top.
                itemCount: widget.competitions.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    final isSelected = _showAll;
                    return ListTile(
                      leading: Icon(
                        Icons.view_agenda,
                        color: isSelected
                            ? Theme.of(sheetCtx).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        'Show all',
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
                        setState(() => _showAll = true);
                        Navigator.pop(sheetCtx);
                      },
                    );
                  }
                  final c = widget.competitions[i - 1];
                  final isSelected = !_showAll && i - 1 == _selectedIndex;
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
                      setState(() {
                        _showAll = false;
                        _selectedIndex = i - 1;
                      });
                      widget.onCompetitionChanged?.call(i - 1);
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
        .map((key) {
          final icon = _statIconForKey(comp.sport, key);
          return _StatRow(
            label: _statLabels[key] ?? _humanize(key),
            // Catch % (L6.1) renders with its % suffix; everything else
            // stays a plain count.
            value: key == 'catchPercentage'
                ? '${_formatValue(comp.stats[key]!)}%'
                : _formatValue(comp.stats[key]!),
            iconAsset: icon.asset,
            badge: icon.badge,
          );
        })
        .toList();
  }

  /// Maps a profile stat key (+ sport) to the matching StatIcon asset/badge.
  /// Basketball and Flag Football keys resolve through the SAME gold-badge
  /// tables ([leagueStatIcon]) the league screens use — this is what gives
  /// points/steals/blocks/turnovers (previously iconless here) and every FF
  /// key their bball_*.png / ff_*.png badge art. Futsal/soccer/AFC/
  /// tournament keys are unchanged: line-art on the white chip (badge:false).
  static ({String? asset, bool badge}) _statIconForKey(String sport, String key) {
    if (sport == 'Basketball' || sport == 'Flag Football') {
      return leagueStatIcon(sport, key);
    }
    switch (key) {
      case 'goals':
      case 'cleanSheets':
        return (asset: statIconAsset('goal'), badge: false);
      case 'assists':
        return (asset: statIconAsset('assist'), badge: false);
      case 'saves':
        return (asset: statIconAsset('save'), badge: false);
      case 'dpl':
        return (asset: statIconAsset('dpl'), badge: false);
      default:
        return (asset: null, badge: false);
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
  /// True for the gold self-contained badge assets (basketball/flag
  /// football) — passed straight through to [StatIcon] so they render
  /// bare, with no white chip (L6.2 Task 5).
  final bool badge;

  const _StatRow({
    required this.label,
    required this.value,
    this.iconAsset,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          // Stat icon
          StatIcon(asset: iconAsset, size: 22, badge: badge),
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
