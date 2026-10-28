// The market's player detail sheet (P3c, spec §10 adopted decision: a LARGE
// bottom sheet for quick compare-and-buy). Big avatar, name (wraps), team ·
// position, price, eligibility badge, fantasy totals once finalized weeks
// exist, this season's REAL league stats (live from the same
// LeagueService.watchRosters feed the league Player Stats tab reads — the
// tab fans it out on a broadcast controller), and an Add/Remove button
// honoring the exact market rules (market_logic). Swipe-dismiss via the
// modal sheet's drag handle. Nothing here auto-saves — adds/removes edit the
// shared draft; the save stays on My Team.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

Future<void> showMarketPlayerSheet(
  BuildContext context, {
  required FantasyPlayer player,
  required SquadDraftController draft,
  required bool editable,
  FantasyPlayerTotals? totals,
  required bool totalsAvailable,
  required Map<String, TournamentPlayer> initialStats,
  required Stream<Map<String, TournamentPlayer>> statsStates,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => MarketPlayerSheet(
      player: player,
      draft: draft,
      editable: editable,
      totals: totals,
      totalsAvailable: totalsAvailable,
      initialStats: initialStats,
      statsStates: statsStates,
    ),
  );
}

class MarketPlayerSheet extends StatelessWidget {
  const MarketPlayerSheet({
    super.key,
    required this.player,
    required this.draft,
    required this.editable,
    required this.totals,
    required this.totalsAvailable,
    required this.initialStats,
    required this.statsStates,
  });

  final FantasyPlayer player;
  final SquadDraftController draft;
  final bool editable;
  final FantasyPlayerTotals? totals;
  final bool totalsAvailable;
  final Map<String, TournamentPlayer> initialStats;
  final Stream<Map<String, TournamentPlayer>> statsStates;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);

    return SizedBox(
      key: const ValueKey('market_player_sheet'),
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child:
                  FantasyAvatar(name: player.name, photoUrl: player.photoUrl,
                      size: 92),
            ),
            const SizedBox(height: 12),
            Text(
              player.name,
              textAlign: TextAlign.center,
              // Wraps, never ellipsized or underlined (house rules).
              softWrap: true,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${player.teamName} · ${player.position.db}',
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatMoneyTenths(player.priceTenths),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                _EligibilityBadge(eligible: player.eligible),
              ],
            ),
            // Fantasy totals render only once finalized gameweeks exist.
            if (totalsAvailable) ...[
              const SizedBox(height: 8),
              Text(
                [
                  '${totals?.points ?? 0} fantasy pts',
                  if (totals?.ownershipPct != null)
                    'owned by ${totals!.ownershipPct!.toStringAsFixed(0)}%',
                ].join(' · '),
                key: const ValueKey('sheet_totals'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'This season',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            // Live league season totals — the same stream feed the league
            // Player Stats tab renders from; a dash until the player's row
            // arrives (photos/stats never gate the sheet).
            StreamBuilder<Map<String, TournamentPlayer>>(
              initialData: initialStats,
              stream: statsStates,
              builder: (context, snapshot) {
                final stats = snapshot.data?[player.name];
                return _StatsGrid(stats: stats);
              },
            ),
            const SizedBox(height: 20),
            // Add/Remove under the SAME market rules — edits the shared
            // draft, saving stays on My Team (the button says so).
            ListenableBuilder(
              listenable: draft,
              builder: (context, _) => _SheetAction(
                player: player,
                draft: draft,
                editable: editable,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EligibilityBadge extends StatelessWidget {
  const _EligibilityBadge({required this.eligible});

  final bool eligible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = eligible ? fantasyAccent(context) : scheme.error;
    return Container(
      key: ValueKey(eligible ? 'badge_eligible' : 'badge_not_eligible'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Text(
        eligible ? 'Eligible' : 'Not eligible',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// Six league-stat tiles: Goals / Assists / Saves / DPL / Clean Sheets /
/// Cards — a dash wherever the season row hasn't arrived (or the player has
/// no league entry at all).
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final TournamentPlayer? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final tiles = <(String, String)>[
      ('Goals', s == null ? '—' : '${s.goals}'),
      ('Assists', s == null ? '—' : '${s.assists}'),
      ('Saves', s == null ? '—' : '${s.saves}'),
      ('DPL', s == null ? '—' : '${s.dpl}'),
      ('Clean Sheets', s == null ? '—' : '${s.cleanSheets}'),
      ('Cards', s == null ? '—' : '${s.yellowCards}Y · ${s.redCards}R'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final tileWidth = (constraints.maxWidth - 2 * gap) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, value) in tiles)
              SizedBox(width: tileWidth, child: _StatTile(label, value)),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            key: ValueKey('stat_${label}_$value'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary Add-to-team / Remove button + the reason line when neither is
/// available — identical availability rules to the market row's control.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.player,
    required this.draft,
    required this.editable,
  });

  final FantasyPlayer player;
  final SquadDraftController draft;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availability = marketAddState(
      player: player,
      slots: draft.slots,
      slotPicks: draft.picks,
      budgetTenths: draft.config.budgetTenths,
      editable: editable,
    );
    final inSquad = availability == MarketAddAvailability.inSquad;
    final addable = availability == MarketAddAvailability.addable;
    final reason = marketAddReason(availability, player.position);

    void onPressed() {
      if (inSquad) {
        final message = draft.removePlayer(player.name);
        if (message != null && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      } else {
        draft.addPlayer(player);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: ValueKey(inSquad ? 'sheet_remove' : 'sheet_add'),
          onPressed: addable || inSquad ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: inSquad ? scheme.surfaceContainerHigh : accent,
            foregroundColor: inSquad
                ? scheme.onSurface
                : (isDark ? Colors.black : scheme.onPrimary),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          child: Text(inSquad ? 'Remove from team' : 'Add to team'),
        ),
        if (reason != null) ...[
          const SizedBox(height: 8),
          Text(
            reason,
            key: const ValueKey('sheet_add_reason'),
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: availability == MarketAddAvailability.unaffordable
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
        ] else if (draft.dirty) ...[
          const SizedBox(height: 8),
          Text(
            'Changes save from the My Team tab.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
