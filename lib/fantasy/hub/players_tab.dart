// The hub's Players market tab (P3c, spec §10) — every eligible player with
// price, position filter chips, search, a PERSISTENT sort (price / points /
// name — held in a session cache so it survives filter changes AND tab
// swipes), the risers & fallers strip, and an add/remove control wired to
// the SAME shared draft the My Team court edits (SquadDraftController —
// nothing here auto-saves; a dirty draft shows the "save on My Team" pill).
// Ineligible guests list last under a "Not eligible" divider, disabled.
// Tapping a row opens the large player detail sheet (market_player_sheet).
//
// Points & ownership render only while `PlayerTotals` exists (P4 writes it);
// absent → the column and the Points sort option hide gracefully. The strip
// reads `PriceChanges/<gw>` (latest) and hides entirely while empty.
//
// House rules: streams only; colorScheme + fantasy accent both themes;
// names wrap, never underlined; glass-navbar bottom clearance; initials
// avatar fallback; 250ms appear animations, zero under reduced motion.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_player_sheet.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

class FantasyPlayersTab extends StatefulWidget {
  const FantasyPlayersTab({
    super.key,
    required this.sport,
    required this.season,
    required this.players,
    required this.draft,
    required this.lockOverride,
    required this.gameweeks,
    this.totalsStates,
    this.priceChangeStates,
    this.rosterStates,
    this.nowUtc,
  });

  final String sport;
  final String season;

  /// The live market (the hub streams it; guests arrive eligible=false).
  final List<FantasyPlayer> players;

  /// The hub's shared draft — the same one the My Team court edits.
  final SquadDraftController draft;

  final FantasyLockOverride lockOverride;
  final List<Gameweek> gameweeks;

  /// Test seams — null = the real FantasyService / LeagueService streams.
  final Stream<Map<String, FantasyPlayerTotals>?>? totalsStates;
  final Stream<List<FantasyPriceChange>>? priceChangeStates;
  final Stream<Map<String, List<TournamentPlayer>>>? rosterStates;
  final DateTime Function()? nowUtc;

  /// The session-persistent market sort (spec §10 adopted decision: sort
  /// survives filter changes; house perceived-performance rule: and tab
  /// swipes). Reset only by a fresh app session — or tests.
  static MarketSort sessionSort = MarketSort.priceDesc;

  @override
  State<FantasyPlayersTab> createState() => _FantasyPlayersTabState();
}

class _FantasyPlayersTabState extends State<FantasyPlayersTab> {
  final TextEditingController _search = TextEditingController();
  FantasyPosition? _positionFilter;

  /// null = PlayerTotals absent (no finalized gameweeks): hide the points
  /// column and the Points sort option.
  Map<String, FantasyPlayerTotals>? _totals;
  List<FantasyPriceChange> _priceChanges = const [];

  /// Season-total league stats by player name — feeds the detail sheet
  /// (reuses LeagueService.watchRosters, the league Player Stats source).
  Map<String, TournamentPlayer> _statsByName = const {};

  /// Re-listen-safe feed for detail sheets (each sheet mounts its own
  /// StreamBuilder; the tab's single subscription fans out here).
  final StreamController<Map<String, TournamentPlayer>> _statsForSheets =
      StreamController<Map<String, TournamentPlayer>>.broadcast();

  StreamSubscription<Map<String, FantasyPlayerTotals>?>? _totalsSub;
  StreamSubscription<List<FantasyPriceChange>>? _priceChangesSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _rostersSub;
  Timer? _lockTicker;

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  bool get _editable => squadEditable(
        lockOverride: widget.lockOverride,
        gameweeks: widget.gameweeks,
        nowUtc: _now,
      );

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_onDraftChanged);
    _totalsSub = (widget.totalsStates ??
            FantasyService.watchPlayerTotals(widget.sport, widget.season))
        .listen((totals) {
      if (mounted) setState(() => _totals = totals);
    });
    _priceChangesSub = (widget.priceChangeStates ??
            FantasyService.watchPriceChanges(widget.sport, widget.season))
        .listen((changes) {
      if (mounted) setState(() => _priceChanges = changes);
    });
    _rostersSub = (widget.rosterStates ??
            LeagueService.watchRosters(widget.sport, widget.season))
        .listen((rosters) {
      if (!mounted) return;
      final byName = <String, TournamentPlayer>{
        for (final players in rosters.values)
          for (final p in players) p.name: p,
      };
      setState(() => _statsByName = byName);
      _statsForSheets.add(byName);
    });
    // 30s tick keeps the editable/locked flip honest around the deadline
    // (same cadence as the squad builder); cancelled in dispose.
    _lockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(FantasyPlayersTab old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) {
      old.draft.removeListener(_onDraftChanged);
      widget.draft.addListener(_onDraftChanged);
    }
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.draft.removeListener(_onDraftChanged);
    _totalsSub?.cancel();
    _priceChangesSub?.cancel();
    _rostersSub?.cancel();
    _statsForSheets.close();
    _lockTicker?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  /// The sort users see/apply: a stale Points selection silently reads as
  /// Price while totals are absent (the segment is hidden then too).
  MarketSort get _effectiveSort =>
      FantasyPlayersTab.sessionSort == MarketSort.pointsDesc && _totals == null
          ? MarketSort.priceDesc
          : FantasyPlayersTab.sessionSort;

  void _setSort(MarketSort sort) {
    setState(() => FantasyPlayersTab.sessionSort = sort);
  }

  void _add(FantasyPlayer player) {
    widget.draft.addPlayer(player);
  }

  void _remove(FantasyPlayer player) {
    final message = widget.draft.removePlayer(player.name);
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openDetail(FantasyPlayer player) {
    showMarketPlayerSheet(
      context,
      player: player,
      draft: widget.draft,
      editable: _editable,
      totals: _totals?[player.name],
      totalsAvailable: _totals != null,
      initialStats: _statsByName,
      statsStates: _statsForSheets.stream,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editable = _editable;
    final market = composeMarket(
      players: widget.players,
      query: _search.text,
      position: _positionFilter,
      sort: _effectiveSort,
      totals: _totals,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final appear = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 250);

    final itemCount = market.eligible.length +
        (market.ineligible.isEmpty ? 0 : 1 + market.ineligible.length);

    return Column(
      key: const ValueKey('players_market'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Risers & fallers (Task 5): hidden ENTIRELY while empty — no shell.
        AnimatedSwitcher(
          duration: appear,
          child: _priceChanges.isEmpty
              ? const SizedBox.shrink(key: ValueKey('no_price_changes'))
              : _PriceChangesStrip(
                  key: const ValueKey('price_changes_strip'),
                  changes: _priceChanges,
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('market_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search players or teams',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<MarketSort>(
                key: const ValueKey('market_sort'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  const ButtonSegment(
                      value: MarketSort.priceDesc, label: Text('\$')),
                  // The Points sort exists only once finalized totals do.
                  if (_totals != null)
                    const ButtonSegment(
                        value: MarketSort.pointsDesc, label: Text('Pts')),
                  const ButtonSegment(
                      value: MarketSort.nameAz, label: Text('A–Z')),
                ],
                selected: {_effectiveSort},
                onSelectionChanged: (s) => _setSort(s.first),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final (label, pos) in [
                ('All', null),
                ('GK', FantasyPosition.gk),
                ('DEF', FantasyPosition.def),
                ('ATT', FantasyPosition.att),
              ]) ...[
                ChoiceChip(
                  key: ValueKey('market_pos_$label'),
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  selected: _positionFilter == pos,
                  onSelected: (_) => setState(() => _positionFilter = pos),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        // Cross-tab honesty (Task 1): the market edits the draft, the SAVE
        // lives on My Team — say so whenever the draft is dirty.
        AnimatedSwitcher(
          duration: appear,
          child: widget.draft.dirty
              ? Padding(
                  key: const ValueKey('unsaved_pill'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: fantasyAccent(context).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color:
                              fantasyAccent(context).withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.pending_actions,
                            size: 15, color: fantasyAccent(context)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Unsaved changes — save on My Team',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_unsaved_pill')),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: itemCount == 0
              ? Center(
                  child: Text(
                    'No players match.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      0, 4, 0, 24 + MediaQuery.paddingOf(context).bottom),
                  itemCount: itemCount,
                  itemBuilder: (context, i) {
                    if (i < market.eligible.length) {
                      return _row(market.eligible[i], editable);
                    }
                    final j = i - market.eligible.length;
                    if (j == 0) return const _NotEligibleDivider();
                    return _row(market.ineligible[j - 1], editable);
                  },
                ),
        ),
      ],
    );
  }

  Widget _row(FantasyPlayer p, bool editable) {
    final scheme = Theme.of(context).colorScheme;
    final availability = marketAddState(
      player: p,
      slots: widget.draft.slots,
      slotPicks: widget.draft.picks,
      budgetTenths: widget.draft.config.budgetTenths,
      editable: editable,
      unplaced: widget.draft.unplaced,
    );
    final totals = _totals?[p.name];
    final unaffordable = availability == MarketAddAvailability.unaffordable;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          FantasyAvatar(name: p.name, photoUrl: p.photoUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  // Wraps, never ellipsized or underlined (house rules).
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  '${p.teamName} · ${p.position.db}',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoneyTenths(p.priceTenths),
                key: ValueKey('market_price_${p.name}'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  // Unaffordable = the price itself carries the warning.
                  color: unaffordable ? scheme.error : scheme.onSurface,
                ),
              ),
              // Points & ownership only once finalized totals exist (Task 4).
              if (_totals != null)
                Text(
                  [
                    '${totals?.points ?? 0} pts',
                    if (totals?.ownershipPct != null)
                      '${totals!.ownershipPct!.toStringAsFixed(0)}%',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
          _MarketAddControl(
            player: p,
            availability: availability,
            onAdd: () => _add(p),
            onRemove: () => _remove(p),
          ),
        ],
      ),
    );

    return InkWell(
      key: ValueKey('market_row_${p.name}'),
      onTap: () => _openDetail(p),
      child: p.eligible ? content : Opacity(opacity: 0.55, child: content),
    );
  }
}

/// The row's add/remove control (shared rules with the detail sheet's
/// button via market_logic): live add = accent +, in-squad = accent check
/// (tap removes), everything else = greyed + with a tap-to-see reason.
class _MarketAddControl extends StatelessWidget {
  const _MarketAddControl({
    required this.player,
    required this.availability,
    required this.onAdd,
    required this.onRemove,
  });

  final FantasyPlayer player;
  final MarketAddAvailability availability;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    switch (availability) {
      case MarketAddAvailability.inSquad:
        return IconButton(
          key: ValueKey('market_remove_${player.name}'),
          tooltip: 'In your team — tap to remove',
          icon: Icon(Icons.check_circle, color: accent),
          onPressed: onRemove,
          visualDensity: VisualDensity.compact,
        );
      case MarketAddAvailability.addable:
        return IconButton(
          key: ValueKey('market_add_${player.name}'),
          tooltip: 'Add to team',
          icon: Icon(Icons.add_circle_outline, color: accent),
          onPressed: onAdd,
          visualDensity: VisualDensity.compact,
        );
      case MarketAddAvailability.locked:
      case MarketAddAvailability.ineligible:
      case MarketAddAvailability.positionFull:
      case MarketAddAvailability.unaffordable:
        // Tooltip-style reason on tap (the button is dead, the WHY isn't).
        return Tooltip(
          key: ValueKey('market_add_disabled_${player.name}'),
          message: marketAddReason(availability, player.position)!,
          triggerMode: TooltipTriggerMode.tap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              availability == MarketAddAvailability.locked
                  ? Icons.lock_outline
                  : Icons.add_circle_outline,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
          ),
        );
    }
  }
}

/// The small divider heading the disabled guest section.
class _NotEligibleDivider extends StatelessWidget {
  const _NotEligibleDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('not_eligible_divider'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Row(
        children: [
          Text(
            'Not eligible',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal risers & fallers chips: "▲ Name +$0.5M" (pitch-green up,
/// error-red down), latest repricing only (Task 5).
class _PriceChangesStrip extends StatelessWidget {
  const _PriceChangesStrip({super.key, required this.changes});

  final List<FantasyPriceChange> changes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = fantasyPitchGreen(context);
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        itemCount: changes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = changes[i];
          final up = c.deltaTenths > 0;
          final tone = up ? green : scheme.error;
          return Container(
            key: ValueKey('price_change_${c.name}'),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone.withValues(alpha: 0.45)),
            ),
            child: Text(
              '${up ? '▲' : '▼'} ${c.name} ${formatPriceDelta(c.deltaTenths)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}
