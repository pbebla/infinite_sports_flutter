// The profile's four tab bodies (round 3, spec §4): Overview (form bars +
// tapped week's breakdown, next game, league season stats), Stats (where his
// points came from + games/PPG/form), Matches (one row per gameweek, newest
// first, tap to expand; voided weeks "Week voided — 0") and Price (start /
// current / high / low + per-week price and the move after it). Every tab is
// a plain Column the page places in its single scroll view; empty states are
// friendly copy, never zeros.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_common.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_form_bars.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

const double _gap = 12;

// ── Overview ──────────────────────────────────────────────────────────────

class ProfileOverviewTab extends StatefulWidget {
  const ProfileOverviewTab({
    super.key,
    required this.model,
    required this.season,
    this.nextGameText,
    this.seasonStats,
  });

  final FantasyProfileModel model;
  final String season;

  /// "vs Nimrod · Sun 3 PM"; null hides the line (no upcoming game).
  final String? nextGameText;

  /// His league roster row (season totals); null → dashes.
  final TournamentPlayer? seasonStats;

  @override
  State<ProfileOverviewTab> createState() => _ProfileOverviewTabState();
}

class _ProfileOverviewTabState extends State<ProfileOverviewTab> {
  int? _selectedGw;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final scheme = Theme.of(context).colorScheme;
    MatchRow? selected;
    for (final r in model.matchRows) {
      if (r.gw == _selectedGw) selected = r;
    }

    return Column(
      key: const ValueKey('profile_overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          title: 'Recent form',
          child: model.hasWeeks
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FantasyFormBars(
                      bars: model.formBars,
                      selectedGw: _selectedGw,
                      onTapBar: (gw) => setState(
                          () => _selectedGw = _selectedGw == gw ? null : gw),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      _WeekBreakdown(row: selected),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tap a bar to see that week.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                )
              : Text(
                  kPointsStartCopy,
                  key: const ValueKey('profile_points_start'),
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
        if (widget.nextGameText != null) ...[
          const SizedBox(height: _gap),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: profileCardDecoration(context),
            child: Row(
              children: [
                Icon(Icons.event_outlined,
                    size: 20, color: fantasyAccent(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Next: ${widget.nextGameText}',
                    key: const ValueKey('profile_next_game'),
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: _gap),
        ProfileCard(
          title: 'Season stats (S${widget.season})',
          child: _SeasonStatsGrid(stats: widget.seasonStats),
        ),
      ],
    );
  }
}

/// The tapped week: its games, then each source line and the week total.
class _WeekBreakdown extends StatelessWidget {
  const _WeekBreakdown({required this.row});

  final MatchRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('week_breakdown'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'GW${row.gw} · ${row.opponentsText}',
            softWrap: true,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ..._weekLines(context, row),
        ],
      ),
    );
  }
}

/// A week's breakdown lines (shared by the Overview bar tap and the Matches
/// row expansion).
List<Widget> _weekLines(BuildContext context, MatchRow row) {
  final scheme = Theme.of(context).colorScheme;
  if (row.voided) {
    return [
      ProfileLineRow(
          label: 'Week voided',
          value: '0',
          valueColor: scheme.onSurfaceVariant),
    ];
  }
  if (row.lines.isEmpty) {
    return [
      ProfileLineRow(
        label: row.played ? 'No points this week' : "Didn't play",
        value: pointsText(row.points),
        valueColor: scheme.onSurfaceVariant,
      ),
    ];
  }
  return [
    for (final l in row.lines)
      ProfileLineRow(
        label: sourceLineLabel(l),
        value: pointsText(l.points),
        valueColor: l.points < 0 ? profileDownColor(context) : null,
      ),
    Divider(height: 10, color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ProfileLineRow(
        label: 'Week total', value: pointsText(row.points), bold: true),
  ];
}

class _SeasonStatsGrid extends StatelessWidget {
  const _SeasonStatsGrid({required this.stats});

  final TournamentPlayer? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    String v(int Function(TournamentPlayer) read) =>
        s == null ? '—' : '${read(s)}';
    return ProfileTileGrid(tiles: [
      ProfileTile(label: 'Goals', value: v((p) => p.goals)),
      ProfileTile(label: 'Assists', value: v((p) => p.assists)),
      ProfileTile(label: 'Saves', value: v((p) => p.saves)),
      ProfileTile(label: 'DPL', value: v((p) => p.dpl)),
      ProfileTile(label: 'Clean sheets', value: v((p) => p.cleanSheets)),
      ProfileTile(
        label: 'Cards',
        value: s == null ? '—' : '${s.yellowCards}Y · ${s.redCards}R',
      ),
    ]);
  }
}

// ── Stats ─────────────────────────────────────────────────────────────────

class ProfileStatsTab extends StatelessWidget {
  const ProfileStatsTab({super.key, required this.model});

  final FantasyProfileModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('profile_stats'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          title: 'Where his points came from',
          child: model.sourceTotals.isEmpty
              ? Text(
                  // No record at all → before GW1; records but nothing
                  // scored (never played / only voided weeks) → neutral.
                  model.hasWeeks ? kNoPointsYetCopy : kPointsStartCopy,
                  key: ValueKey(
                      model.hasWeeks ? 'sources_none' : 'sources_empty'),
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in model.sourceTotals)
                      ProfileLineRow(
                        key: ValueKey('source_${s.key}'),
                        label: sourceLineLabel(s),
                        value: pointsText(s.points),
                        valueColor:
                            s.points < 0 ? profileDownColor(context) : null,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: _gap),
        ProfileCard(
          title: 'Season so far',
          child: ProfileTileGrid(tiles: [
            ProfileTile(label: 'Games played', value: model.gamesText),
            ProfileTile(label: 'PPG', value: model.ppgText),
            ProfileTile(label: 'Form', value: model.formText),
          ]),
        ),
      ],
    );
  }
}

// ── Matches ───────────────────────────────────────────────────────────────

class ProfileMatchesTab extends StatefulWidget {
  const ProfileMatchesTab({super.key, required this.model});

  final FantasyProfileModel model;

  @override
  State<ProfileMatchesTab> createState() => _ProfileMatchesTabState();
}

class _ProfileMatchesTabState extends State<ProfileMatchesTab> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final rows = widget.model.matchRows;
    if (rows.isEmpty) {
      return const ProfileEmptyNote(
        key: ValueKey('matches_empty'),
        icon: Icons.sports_soccer_outlined,
        text: 'No gameweeks scored yet — his week-by-week points show up '
            'here after Gameweek 1.',
      );
    }
    return Column(
      key: const ValueKey('profile_matches'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows) ...[
          _MatchRowCard(
            row: r,
            expanded: _expanded.contains(r.gw),
            onTap: r.voided
                ? null
                : () => setState(() {
                      if (!_expanded.remove(r.gw)) _expanded.add(r.gw);
                    }),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _GwPill extends StatelessWidget {
  const _GwPill(this.gw);

  final int gw;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'GW$gw',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _MatchRowCard extends StatelessWidget {
  const _MatchRowCard({
    required this.row,
    required this.expanded,
    required this.onTap,
  });

  final MatchRow row;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('match_row_${row.gw}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: profileCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GwPill(row.gw),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.opponentsText,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (!row.played && row.opponentsText != 'No game')
                          Text(
                            "Didn't play",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (row.voided)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 104),
                      child: Text(
                        'Week voided — 0',
                        key: ValueKey('match_voided_${row.gw}'),
                        textAlign: TextAlign.end,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          pointsText(row.points),
                          key: ValueKey('match_points_${row.gw}'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: row.points < 0
                                ? profileDownColor(context)
                                : scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Season ${row.seasonToDate}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (expanded && !row.voided) ...[
                const SizedBox(height: 8),
                Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.6)),
                const SizedBox(height: 4),
                ..._weekLines(context, row),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Price ─────────────────────────────────────────────────────────────────

class ProfilePriceTab extends StatelessWidget {
  const ProfilePriceTab({super.key, required this.model});

  final FantasyProfileModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String money(int? tenths) =>
        tenths == null ? '—' : formatMoneyTenths(tenths);
    return Column(
      key: const ValueKey('profile_price_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          child: ProfileTileGrid(perRow: 2, tiles: [
            ProfileTile(
                label: 'Starting price', value: money(model.startPriceTenths)),
            ProfileTile(
              label: 'Current price',
              value: money(model.priceTenths),
              valueColor: fantasyAccent(context),
            ),
            ProfileTile(label: 'Season high', value: money(model.highTenths)),
            ProfileTile(label: 'Season low', value: money(model.lowTenths)),
          ]),
        ),
        const SizedBox(height: _gap),
        if (model.priceRows.isEmpty)
          const ProfileEmptyNote(
            key: ValueKey('price_empty'),
            icon: Icons.show_chart,
            text: 'No price history yet — his price is recorded at each '
                'gameweek deadline.',
          )
        else
          ProfileCard(
            title: 'By gameweek',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in model.priceRows)
                  Padding(
                    key: ValueKey('price_row_${r.gw}'),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        _GwPill(r.gw),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            formatMoneyTenths(r.priceTenths),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          priceMoveText(r.moveAfterTenths),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: profileMoveColor(context, r.moveAfterTenths),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Price during each gameweek, and the move after it.',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
