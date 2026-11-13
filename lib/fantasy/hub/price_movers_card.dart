// The market's Price Risers / Price Fallers card (round 3, spec §5; owner
// mockup docs/superpowers/specs/assets/2026-10-29-fantasy-round3/
// mockup-players-market.webp — "Price Changes" with Risers | Fallers
// columns and "View all →"). Replaces the old chip strip; the tab hides it
// until the latest reprice moved somebody.
//
// The All chip groups both columns GK / DEF / ATT (top 2 each side, from
// market_logic.computePriceMovers); a position chip narrows it to that
// position. Rows show photo + short name + the move; every row — and every
// row of the "View all" sheet (every move of the latest reprice, live) —
// opens the player profile.
//
// House rules: light + dark from colorScheme (the profile's card surface,
// pitch green up / error red down); names wrap, never ellipsized or
// underlined; photos never gate content (initials first).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_common.dart';

/// Opens [playerName]'s fantasy profile from [context] (the tab supplies
/// it, with the hub's shared draft).
typedef OpenFantasyPlayer = void Function(
    BuildContext context, String playerName);

/// Every move of the latest reprice (the "View all" sheet's content).
class PriceMovesSnapshot {
  const PriceMovesSnapshot({
    required this.gameweek,
    required this.risers,
    required this.fallers,
  });

  /// The gameweek the reprice followed ("After Gameweek 3").
  final int gameweek;
  final List<PriceMove> risers;
  final List<PriceMove> fallers;
}

/// The card. [movers] is already narrowed to the position chip
/// ([position] = its code, null for All — then each position gets its own
/// labelled group).
class PriceMoversCard extends StatelessWidget {
  const PriceMoversCard({
    super.key,
    required this.gameweek,
    required this.movers,
    required this.position,
    required this.onOpenPlayer,
    required this.onViewAll,
  });

  final int gameweek;
  final PriceMovers movers;
  final String? position;
  final OpenFantasyPlayer onOpenPlayer;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grouped = position == null;
    final groups = [
      for (final key in movers.risers.keys)
        if ((movers.risers[key] ?? const []).isNotEmpty ||
            (movers.fallers[key] ?? const []).isNotEmpty)
          key,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: profileCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price Changes',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'After Gameweek $gameweek',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('price_movers_view_all'),
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: fantasyAccent(context),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View all'),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: _ColumnHeader(rising: true)),
                const SizedBox(width: 12),
                const Expanded(child: _ColumnHeader(rising: false)),
              ],
            ),
          ),
          if (groups.isEmpty)
            Padding(
              key: const ValueKey('price_movers_none'),
              padding: const EdgeInsets.fromLTRB(0, 12, 8, 2),
              child: Text(
                position == null
                    ? 'No price changes after Gameweek $gameweek.'
                    : 'No $position price changes after Gameweek $gameweek.',
                softWrap: true,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final key in groups) ...[
              if (grouped) _GroupLabel(code: key),
              Padding(
                padding: EdgeInsets.only(right: 8, top: grouped ? 0 : 6),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _MoverColumn(
                          moves: movers.risers[key] ?? const [],
                          onOpenPlayer: onOpenPlayer,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5.5),
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      Expanded(
                        child: _MoverColumn(
                          moves: movers.fallers[key] ?? const [],
                          onOpenPlayer: onOpenPlayer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// "▲ Price Risers" (pitch green) / "▼ Price Fallers" (error red).
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.rising});

  final bool rising;

  @override
  Widget build(BuildContext context) {
    final tone = rising ? profileUpColor(context) : profileDownColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(rising ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 20, color: tone),
        Expanded(
          child: Text(
            rising ? 'Price Risers' : 'Price Fallers',
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ),
      ],
    );
  }
}

/// The small "GK ——" label over a position's group (All chip only).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('price_movers_group_$code'),
      padding: const EdgeInsets.fromLTRB(0, 10, 8, 2),
      child: Row(
        children: [
          Text(
            code,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One side of a group: up to two movers, or a muted dash.
class _MoverColumn extends StatelessWidget {
  const _MoverColumn({required this.moves, required this.onOpenPlayer});

  final List<PriceMove> moves;
  final OpenFantasyPlayer onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (moves.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Text(
          '—',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in moves) _MoverRow(move: m, onOpenPlayer: onOpenPlayer),
      ],
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({required this.move, required this.onOpenPlayer});

  final PriceMove move;
  final OpenFantasyPlayer onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = move.player;
    return InkWell(
      key: ValueKey('price_mover_${p.name}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => onOpenPlayer(context, p.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            FantasyAvatar(name: p.name, photoUrl: p.photoUrl, size: 34),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shortPlayerName(p.name),
                    // Wraps, never ellipsized or underlined (house rules).
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    priceMoveText(move.deltaTenths),
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: profileMoveColor(context, move.deltaTenths),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "View all": every move of the latest reprice — risers, then fallers,
/// biggest move first — live ([updates] re-renders it; null = the reprice
/// is gone). Row taps open the profile on top of the sheet (back returns to
/// the list).
Future<void> showPriceMovesSheet(
  BuildContext context, {
  required PriceMovesSnapshot initial,
  required Stream<PriceMovesSnapshot?> updates,
  required OpenFantasyPlayer onOpenPlayer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => StreamBuilder<PriceMovesSnapshot?>(
        stream: updates,
        initialData: initial,
        builder: (context, snap) => _PriceMovesSheetBody(
          key: const ValueKey('price_moves_sheet'),
          controller: controller,
          snapshot: snap.data,
          onOpenPlayer: onOpenPlayer,
        ),
      ),
    ),
  );
}

class _PriceMovesSheetBody extends StatelessWidget {
  const _PriceMovesSheetBody({
    super.key,
    required this.controller,
    required this.snapshot,
    required this.onOpenPlayer,
  });

  final ScrollController controller;
  final PriceMovesSnapshot? snapshot;
  final OpenFantasyPlayer onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = snapshot;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      children: [
        Text(
          'Price Changes',
          softWrap: true,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          s == null
              ? 'No price changes right now.'
              : 'After Gameweek ${s.gameweek} · '
                  '${s.risers.length + s.fallers.length} '
                  '${s.risers.length + s.fallers.length == 1 ? 'move' : 'moves'}',
          softWrap: true,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (s != null) ...[
          if (s.risers.isNotEmpty) ...[
            _SheetSection(rising: true, count: s.risers.length),
            for (final m in s.risers)
              _SheetMoveRow(move: m, onOpenPlayer: onOpenPlayer),
          ],
          if (s.fallers.isNotEmpty) ...[
            _SheetSection(rising: false, count: s.fallers.length),
            for (final m in s.fallers)
              _SheetMoveRow(move: m, onOpenPlayer: onOpenPlayer),
          ],
        ],
      ],
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.rising, required this.count});

  final bool rising;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tone = rising ? profileUpColor(context) : profileDownColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: Row(
        children: [
          Icon(rising ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 22, color: tone),
          Expanded(
            child: Text(
              '${rising ? 'Price Risers' : 'Price Fallers'} ($count)',
              softWrap: true,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetMoveRow extends StatelessWidget {
  const _SheetMoveRow({required this.move, required this.onOpenPlayer});

  final PriceMove move;
  final OpenFantasyPlayer onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = move.player;
    return InkWell(
      key: ValueKey('price_move_all_${p.name}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpenPlayer(context, p.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            FantasyAvatar(name: p.name, photoUrl: p.photoUrl, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    '${p.position.db} · ${p.teamName}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              priceMoveText(move.deltaTenths),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: profileMoveColor(context, move.deltaTenths),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
