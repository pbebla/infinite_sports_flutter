// FotMob-style icon legend (L6.2 Task 2): a small "Icons" card that always
// renders at the bottom of the Facts tab — tournaments AND every league
// sport — so fans can decode the timeline art before any events exist
// (including the pre-kickoff state, where the timeline itself is empty).
//
// NO Flutter-widget logic lives in the entry-list helper below: it's a pure
// function over stat_icon.dart's existing resolvers, unit-tested directly.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

/// One legend row: a human label + the icon it resolves to. Mirrors
/// [StatIcon]'s own asset/badge shape so callers can render it directly:
/// `StatIcon(asset: entry.asset, badge: entry.badge)`.
typedef LegendEntry = ({String label, String? asset, bool badge});

LegendEntry _soccerEntry(String label, String token) =>
    (label: label, asset: statIconAsset(token), badge: false);

LegendEntry? _leagueEntry(String sportKey, String label, String token) {
  final ic = leagueStatIcon(sportKey, token);
  if (ic.asset == null) return null;
  return (label: label, asset: ic.asset, badge: ic.badge);
}

/// The legend rows for one Facts tab, keyed by the league sport key (null =
/// tournament/soccer — futsal shares the same soccer icon set). Always
/// returns a non-empty list for every known sport.
List<LegendEntry> legendEntriesForSport(String? leagueSportKey) {
  switch (leagueSportKey) {
    case 'Basketball':
      return [
        for (final e in [
          _leagueEntry('Basketball', 'Free Throw Made', 'freeThrows'),
          _leagueEntry('Basketball', '2-Pointer', 'twoPointers'),
          _leagueEntry('Basketball', '3-Pointer', 'threePointers'),
          _leagueEntry('Basketball', 'Rebound', 'rebounds'),
          _leagueEntry('Basketball', 'Assist', 'assists'),
          _leagueEntry('Basketball', 'Steal', 'steals'),
          _leagueEntry('Basketball', 'Block', 'blocks'),
          _leagueEntry('Basketball', 'Turnover', 'turnovers'),
          _leagueEntry('Basketball', 'Foul', 'fouls'),
        ])
          if (e != null) e,
      ];
    case 'Flag Football':
      // Order per the owner spec; a null-asset resolution (shouldn't happen
      // for this list today) is skipped rather than shown broken.
      const tokensInOrder = <String, String>{
        'Completion': 'qbcomp',
        'Reception': 'rec',
        'Drop': 'recmiss',
        'Receiving TD': 'receiving td',
        'Rushing TD': 'rushing td',
        'Pick-Six': 'int td',
        'Pass TD': 'pass td',
        'Interception': 'interception',
        'Flag Pull': 'fp',
        'Sack': 'sack',
        'Pass Breakup': 'pbu',
        'PAT Made': 'pat1',
        'PAT Missed': 'pat1miss',
        '2PT Made': 'twopt',
        '2PT Missed': 'twoptmiss',
      };
      return [
        for (final resolved in tokensInOrder.entries
            .map((e) => _leagueEntry('Flag Football', e.key, e.value)))
          if (resolved != null) resolved,
      ];
    default: // null (tournament), 'Futsal', 'Soccer'
      return [
        _soccerEntry('Goal', 'goal'),
        _soccerEntry('Own Goal', 'own goal'),
        _soccerEntry('Penalty Goal', 'penalty goal'),
        _soccerEntry('Penalty Missed', 'penalty missed'),
        _soccerEntry('Penalty Saved', 'penalty saved'),
        _soccerEntry('Save', 'save'),
        _soccerEntry('Assist', 'assist'),
        _soccerEntry('Substitution', 'substitution'),
        _soccerEntry('Yellow Card', 'yellow card'),
        _soccerEntry('Second Yellow', 'second yellow'),
        _soccerEntry('Red Card', 'red card'),
        _soccerEntry('Foul', 'foul'),
        _soccerEntry('DPL', 'dpl'),
      ];
  }
}

/// The "Icons" legend card — FotMob-style 2-column wrap of icon+label pairs.
/// Renders for EVERY match state (live, finished, upcoming): the whole point
/// is to let a fan decode the timeline art even before a single event has
/// happened. Theme-aware text/border; [StatIcon] already handles both
/// badge (gold, no chip) and line-art (white chip) rendering per entry.
class IconLegend extends StatelessWidget {
  final String? leagueSportKey;

  const IconLegend({super.key, this.leagueSportKey});

  @override
  Widget build(BuildContext context) {
    final entries = legendEntriesForSport(leagueSportKey);
    if (entries.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Icons',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final itemWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 10,
                  children: [
                    for (final e in entries)
                      SizedBox(
                        width: itemWidth,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatIcon(asset: e.asset, size: 22, badge: e.badge),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                e.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.8),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
