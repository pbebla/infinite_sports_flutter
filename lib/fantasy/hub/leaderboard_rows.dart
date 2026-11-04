// Shared leaderboard presentation (P3d, redesigned in round 3): the ranked row
// tile and RankedLeaderboardList — the scrolling list that keeps the signed-in
// manager's row PINNED to the bottom of the viewport whenever its natural
// place is scrolled away (FPL-style sticky own-row, spec §10 adopted
// decision). Used by the Overall and Gameweek scopes AND inside a mini-league,
// so the three can never drift apart.
//
// Round 3 (spec §6, the owner's mockup): the podium is gone — every manager is
// a plain row: gold rank, movement cell (Overall only: ▲n green / ▼n red / —
// muted), avatar, the manager's real name with the team name UNDER it (both
// wrap — no side-by-side columns), points. The own row carries the gold
// highlight.
//
// Leaderboard extra (follow-up), opt-in so the Gameweek scope and the
// mini-league lists are untouched: [RankedLeaderboardList.movers] puts the
// week's biggest-climber flame / biggest-drop badge beside a manager's name
// (Overall). Every row — the signed-in manager's own included, natural AND
// pinned copy — is a plain tap target ([RankedLeaderboardList.onRowTap]);
// the own row's "Your rank this season" chart lives on your team page (the
// squad viewer), not in the list.
//
// Badges (spec 2026-10-30 §5), opt-in like the extras:
// [RankedLeaderboardList.badgeCounts] puts the small military_tech + N chip
// beside a manager's name (Overall and Gameweek — never the mini-league
// lists); it wraps with the climber/drop badge after a long name. The chip
// is a FIXED-size slot ([kBadgeCountChipWidth] × [kBadgeCountChipHeight]):
// while the counts are still loading (`badgeCounts == null`) every row
// reserves that slot empty, so the numbers fill in after the reveal without
// moving the name, the climber badge or the row (Opus audit item 1).
//
// Live everywhere (Task 6) — "like ESPN and the Premier League: numbers move,
// rows don't jump":
//   • [RankedLeaderboardList] keeps its rows in a [SteadyOrder]: a row's rank
//     and points update IN PLACE the moment they arrive, but the ORDER only
//     changes when the list is at the top (and nobody is scrolling it), when
//     the list is opened or replaced (a scope / week pick builds a new list)
//     — otherwise "Order changed · tap to refresh" floats over the top of the
//     list and re-orders on its tap. Never under a moving finger.
//   • [LeaderboardRowTile] tints a moved row for 800 ms (up = the up colour,
//     down = the bright fantasy red, each at 18 % alpha) and cross-fades its
//     rank number over 250 ms; both are instant under reduced motion.
//   • the column header carries the shared LIVE pill while the board is live.
//
// House rules: theme-safe both modes (fantasy accent = gold in dark, primary
// red in light; movement up = the pitch-green family, down = error); manager
// names WRAP and are never underlined or ellipsized; list clears the glass
// navbar; photos never gate rows (FantasyAvatar's initials fallback); the
// pinned row's appear/disappear is 200ms and zero under reduced motion.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/badge_shelf.dart'
    show BadgeCountChip, kBadgeCountChipHeight, kBadgeCountChipWidth;
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/steady_order.dart';
import 'package:infinite_sports_flutter/fantasy/hub/steady_scroll.dart';

/// How long a moved row stays tinted.
const Duration kRowTintHold = Duration(milliseconds: 800);

/// How long a moved row's rank number takes to cross-fade to its new value.
const Duration kRankCrossFade = Duration(milliseconds: 250);

/// The moved-row tint's strength.
const double kRowTintAlpha = 0.18;

/// The pill that appears while a new order waits (the owner's copy).
const String kOrderChangedCopy = 'Order changed · tap to refresh';

// Column geometry shared by the rows and the column header so "#", the
// movement cell and the manager column line up.
const double _rankWidth = 30;
const double _movementWidth = 36;
const double _avatarSize = 38;
const double _afterMovementGap = 6;
const double _afterAvatarGap = 10;

/// Movement arrow color for this theme: green up (pitch family — legitimate
/// in both themes), error down, muted neutral.
Color movementColor(BuildContext context, MovementDirection d) => switch (d) {
      MovementDirection.up => fantasyPitchGreen(context),
      MovementDirection.down => fantasyDownRed(context),
      MovementDirection.none => Theme.of(context).colorScheme.onSurfaceVariant,
    };

/// The "biggest climber" flame: a warm orange that reads in both themes
/// (≥3:1 on the hub's light and dark surfaces) and never borrows the
/// fantasy "down" red the biggest-drop badge uses.
Color fantasyFlameOrange(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFA726)
        : const Color(0xFFE65100);

/// The week's biggest-climber flame / biggest-drop badge beside a manager's
/// name: icon only, its text in the tooltip and for screen readers.
class LeaderboardMoverBadge extends StatelessWidget {
  const LeaderboardMoverBadge({
    super.key,
    required this.mover,
  });

  final WeeklyMover mover;

  @override
  Widget build(BuildContext context) {
    final climber = mover.kind == MoverKind.climber;
    final color =
        climber ? fantasyFlameOrange(context) : fantasyDownRed(context);
    final label = moverLabel(mover);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      // Its own semantics node: read as one phrase, not merged into the name.
      child: Semantics(
        container: true,
        label: label,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              climber ? Icons.local_fire_department : Icons.trending_down,
              size: 14,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that just moved: which way, and a [serial] that is new for every
/// move so a second move of the same row restarts its tint. A tile starts the
/// tint when it SEES the serial change — a row built later (scrolled into
/// view) never replays an old one.
class RowFlash {
  const RowFlash(this.direction, this.serial);

  final MovementDirection direction;
  final int serial;
}

/// One ranked row: rank, movement cell (when the data provides one), avatar,
/// the two-line manager cell (real name; team name under it), points. The
/// signed-in manager's row carries the accent highlight.
class LeaderboardRowTile extends StatefulWidget {
  const LeaderboardRowTile({
    super.key,
    required this.row,
    this.showMovement = true,
    this.onTap,
    this.mover,
    this.badgeCount = 0,
    this.flash,
  });

  final LeaderboardRowData row;
  final bool showMovement;
  final void Function(LeaderboardRowData row)? onTap;

  /// The week's biggest climber / faller badge beside the name (Overall).
  final WeeklyMover? mover;

  /// The manager's achievement-badge count, shown as a chip beside the name
  /// when > 0 (Overall + Gameweek). null = not known yet: the chip's
  /// fixed-size slot is reserved empty, so the number fills in later
  /// without moving anything.
  final int? badgeCount;

  /// The row moved (rank number or place): tint it for [kRowTintHold]. null =
  /// nothing new (a running tint is left to finish).
  final RowFlash? flash;

  @override
  State<LeaderboardRowTile> createState() => _LeaderboardRowTileState();
}

class _LeaderboardRowTileState extends State<LeaderboardRowTile> {
  Timer? _tintTimer;
  bool _tinted = false;

  /// Kept after the tint ends so it fades OUT in its own colour, never
  /// through a darker blend.
  MovementDirection _tintDirection = MovementDirection.up;

  @override
  void didUpdateWidget(LeaderboardRowTile old) {
    super.didUpdateWidget(old);
    final flash = widget.flash;
    if (flash == null || flash.serial == old.flash?.serial) return;
    _tintTimer?.cancel();
    // No setState: this build is already happening.
    _tintDirection = flash.direction;
    _tinted = true;
    _tintTimer = Timer(kRowTintHold, () {
      if (mounted) setState(() => _tinted = false);
    });
  }

  @override
  void dispose() {
    _tintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final showMovement = widget.showMovement;
    final onTap = widget.onTap;
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final direction = movementDirection(row.movement);
    final secondary = row.secondaryName;
    final mover = widget.mover;
    final badgeCount = widget.badgeCount;
    final reserveBadge = badgeCount == null;
    final showBadge = badgeCount != null && badgeCount > 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tint = movementColor(context, _tintDirection)
        .withValues(alpha: _tinted ? kRowTintAlpha : 0);

    final nameText = Text(
      row.name,
      key: ValueKey('leaderboard_name_${row.uid}'),
      // Wraps, never underlined or ellipsized (house rules).
      softWrap: true,
      style: TextStyle(
        fontSize: 14,
        fontWeight: row.isSelf ? FontWeight.w800 : FontWeight.w700,
        height: 1.25,
        color: scheme.onSurface,
      ),
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _rankWidth,
            // A moved rank cross-fades to its new number (instant under
            // reduced motion); a row that did not move never animates.
            child: AnimatedSwitcher(
              key: ValueKey('leaderboard_rank_${row.uid}'),
              duration: reduceMotion ? Duration.zero : kRankCrossFade,
              child: Text(
                '${row.displayRank}',
                key: ValueKey(row.displayRank),
                textAlign: TextAlign.center,
                // The rank is the gold/red accent on every row (the mockup).
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ),
          if (showMovement)
            SizedBox(
              width: _movementWidth,
              // Scales down rather than overflow on a 3-digit climb.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  movementLabel(row.movement),
                  key: ValueKey('movement_${row.uid}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: movementColor(context, direction),
                  ),
                ),
              ),
            ),
          const SizedBox(width: _afterMovementGap),
          FantasyAvatar(
              name: row.name, photoUrl: row.photoUrl, size: _avatarSize),
          const SizedBox(width: _afterAvatarGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mover == null && !reserveBadge && !showBadge)
                  nameText
                else
                  // The badges follow the name and drop to their own line
                  // when a long name fills the cell (never squeeze it).
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      nameText,
                      if (reserveBadge)
                        SizedBox(
                          key: ValueKey('badge_slot_${row.uid}'),
                          width: kBadgeCountChipWidth,
                          height: kBadgeCountChipHeight,
                        )
                      else if (showBadge)
                        BadgeCountChip(
                          key: ValueKey('badge_count_${row.uid}'),
                          count: badgeCount,
                        ),
                      if (mover != null)
                        LeaderboardMoverBadge(
                          key: ValueKey(mover.kind == MoverKind.climber
                              ? 'climber_badge_${row.uid}'
                              : 'faller_badge_${row.uid}'),
                          mover: mover,
                        ),
                    ],
                  ),
                if (secondary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      secondary,
                      key: ValueKey('leaderboard_team_${row.uid}'),
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${row.points} pts',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: row.isSelf ? accent : scheme.onSurface,
            ),
          ),
        ],
      ),
    );

    // Painted OVER the row (foregroundDecoration), never as a decoration: a
    // decoration's border insets the content by its width, which nudged the
    // own row's columns 1 px off everyone else's (review fix).
    final selfBorder = BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: 0.65)),
    );
    final body = AnimatedContainer(
      // The moved-row tint, painted over the row (own highlight included).
      key: ValueKey('row_tint_${row.uid}'),
      duration: reduceMotion ? Duration.zero : kRankCrossFade,
      foregroundDecoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        key: ValueKey('leaderboard_row_${row.uid}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap == null ? null : () => onTap(row),
        child: row.isSelf
            ? Container(foregroundDecoration: selfBorder, child: content)
            : content,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        // The own row: a clear gold (red in light) wash, not a whisper.
        color: row.isSelf
            ? accent.withValues(alpha: 0.20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: body,
      ),
    );
  }
}

/// The mockup's "# · Manager · Pts" header — same paddings and column widths
/// as [LeaderboardRowTile] so the labels sit over their columns.
class _LeaderboardColumnHeader extends StatelessWidget {
  const _LeaderboardColumnHeader(
      {required this.showMovement, required this.live});

  final bool showMovement;

  /// The board is the live gameweek's: the shared LIVE pill sits by the
  /// "Manager" label.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: scheme.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('leaderboard_column_header'),
      children: [
        Padding(
          // Outer 10 + inner 12, matching the tile.
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 6),
          child: Row(
            children: [
              SizedBox(
                  width: _rankWidth,
                  child: Text('#', textAlign: TextAlign.center, style: style)),
              if (showMovement) const SizedBox(width: _movementWidth),
              const SizedBox(
                  width: _afterMovementGap + _avatarSize + _afterAvatarGap),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text('Manager', style: style),
                    if (live) const FantasyLivePill(),
                  ],
                ),
              ),
              Text('Pts', style: style),
            ],
          ),
        ),
        Divider(
            height: 1,
            thickness: 1,
            indent: 12,
            endIndent: 12,
            color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ],
    );
  }
}

/// The scrolling standings: a column header, plain ranked rows, and the
/// signed-in manager's row pinned to the bottom of the viewport whenever its
/// natural place is out of view.
///
/// STEADY ORDER (live everywhere, Task 6): [rows] arrives in the board's
/// order every time a number moves. Each row's numbers are drawn from the
/// LATEST [rows] at once; the order they are drawn in is a [SteadyOrder] — it
/// follows the data only when the list is at the top and not being scrolled,
/// else it waits behind the "Order changed · tap to refresh" pill. A new list
/// (the opener gives each scope / week its own key) is a fresh start: the
/// first order is applied at once.
class RankedLeaderboardList extends StatefulWidget {
  const RankedLeaderboardList({
    super.key,
    required this.rows,
    this.showMovement = true,
    this.onRowTap,
    this.header,
    this.movers = const {},
    this.badgeCounts = const {},
    this.live = false,
  });

  final List<LeaderboardRowData> rows;
  final bool showMovement;
  final void Function(LeaderboardRowData row)? onRowTap;

  /// Optional widget scrolled above everything (e.g. the week chips).
  final Widget? header;

  /// uid → the week's biggest climber / faller badge (Overall only).
  final Map<String, WeeklyMover> movers;

  /// uid → achievement-badge count (Overall + Gameweek; empty elsewhere).
  /// null = the counts are still loading: every row reserves the chip's
  /// fixed-size slot (no row moves when they land).
  final Map<String, int>? badgeCounts;

  /// [rows] are the live gameweek's provisional numbers: the column header
  /// carries the shared LIVE pill.
  final bool live;

  int? _badgeCountFor(String uid) {
    final counts = badgeCounts;
    return counts == null ? null : (counts[uid] ?? 0);
  }

  @override
  State<RankedLeaderboardList> createState() => _RankedLeaderboardListState();
}

class _RankedLeaderboardListState extends State<RankedLeaderboardList> {
  /// Keys the signed-in manager's natural tile so the pin logic can ask where
  /// it is.
  final GlobalKey _ownKey = GlobalKey();
  bool _pinned = false;

  /// Where the list is and whether a finger is on it (steady_scroll.dart).
  /// Read from notifications, NOT from an owned ScrollController: the list
  /// stays on the route's PrimaryScrollController, so iOS's
  /// tap-the-status-bar-to-scroll-to-top keeps working on it.
  final SteadyScrollTracker _scroll = SteadyScrollTracker();

  /// The order the rows are drawn in (uids); see the class doc.
  final SteadyOrder<String> _order = SteadyOrder<String>();

  /// The rows that just moved, by uid, and the serial that tells a tile it is
  /// a NEW move.
  Map<String, RowFlash> _flashes = const {};
  int _flashSerial = 0;

  @override
  void initState() {
    super.initState();
    _order.update(_uids(widget.rows), atTop: true);
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(RankedLeaderboardList old) {
    super.didUpdateWidget(old);
    final before = List<String>.of(_order.applied);
    _order.update(_uids(widget.rows), atTop: _scroll.atTop);
    _noteMoves(old.rows, before);
    _scheduleCheck();
  }

  static List<String> _uids(List<LeaderboardRowData> rows) =>
      [for (final row in rows) row.uid];

  /// Works out which rows moved between the previous rows / order and the
  /// current ones (a rank number changed, or the order moved them) and hands
  /// each its [RowFlash]. Nobody moved = no flashes (a running tint finishes).
  void _noteMoves(List<LeaderboardRowData> beforeRows, List<String> beforeOrder) {
    final moved = movedRows(
      before: beforeRows,
      after: widget.rows,
      beforeOrder: beforeOrder,
      afterOrder: _order.applied,
    );
    if (moved.isEmpty) {
      _flashes = const {};
      return;
    }
    _flashSerial++;
    _flashes = {
      for (final e in moved.entries) e.key: RowFlash(e.value, _flashSerial),
    };
  }

  /// "Order changed · tap to refresh" was tapped (or the list came to rest at
  /// the top): apply the waiting order.
  void _refresh() {
    final beforeOrder = List<String>.of(_order.applied);
    setState(() {
      if (_order.refresh()) _noteMoves(widget.rows, beforeOrder);
    });
  }

  /// A scroll came to rest at the top with an order waiting: apply it.
  /// Deferred — scroll notifications can fire during layout.
  void _applyWaitingAtRest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _order.hasPending && _scroll.atTop) _refresh();
    });
  }

  bool _onScroll(ScrollNotification n) {
    // Only THIS list's own vertical scroll counts (not the week chips'
    // strip) — the tracker knows; true = it just came to rest at the top.
    if (_scroll.onScroll(n) && _order.hasPending) _applyWaitingAtRest();
    // Scroll notifications can fire DURING viewport layout — reading
    // render-box geometry there asserts. Defer to after the frame.
    _scheduleCheck();
    return false;
  }

  /// A row tile with the opt-in extras (mover badge, badge-count chip). The
  /// own row is tapped like every other row.
  Widget _tile(LeaderboardRowData row, {Key? key}) => LeaderboardRowTile(
        key: key,
        row: row,
        showMovement: widget.showMovement,
        onTap: widget.onRowTap,
        mover: widget.movers[row.uid],
        badgeCount: widget._badgeCountFor(row.uid),
        flash: _flashes[row.uid],
      );

  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOwnRow());
  }

  /// Pin when the manager HAS a row and that row's element is outside the
  /// viewport: not built at all (beyond the builder's cache) or built but
  /// scrolled past either edge.
  void _checkOwnRow() {
    if (!mounted) return;
    var shouldPin = false;
    if (widget.rows.any((r) => r.isSelf)) {
      final ctx = _ownKey.currentContext;
      if (ctx == null) {
        shouldPin = true;
      } else {
        final box = ctx.findRenderObject();
        final listBox = context.findRenderObject();
        if (box is RenderBox &&
            box.attached &&
            listBox is RenderBox &&
            listBox.attached) {
          final top = box.localToGlobal(Offset.zero, ancestor: listBox).dy;
          shouldPin =
              top + box.size.height <= 0 || top >= listBox.size.height;
        }
      }
    }
    if (shouldPin != _pinned) setState(() => _pinned = shouldPin);
  }

  @override
  Widget build(BuildContext context) {
    // The latest numbers, in the order currently shown.
    final latest = {for (final row in widget.rows) row.uid: row};
    final rows = [
      for (final uid in _order.applied)
        if (latest[uid] case final row?) row,
    ];
    // The optional header, then the column header, then the rows.
    final headerCount = (widget.header != null ? 1 : 0) + 1;
    final selfRow = rows.where((r) => r.isSelf).firstOrNull;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Each tile's key follows its row, so a re-order moves the tile (and its
    // running tint / rank fade) instead of re-using it for another manager.
    Key tileKey(LeaderboardRowData row) =>
        row.isSelf ? _ownKey : ValueKey<String>('leaderboard_tile_${row.uid}');
    final indexOf = <Key, int>{
      for (final (i, row) in rows.indexed) tileKey(row): i + headerCount,
    };

    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          // The content grew or shrank under the viewport: the offset may
          // have been clamped without a scroll.
          onNotification: (n) {
            _scroll.onMetrics(n);
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                  0, 4, 0, 24 + MediaQuery.paddingOf(context).bottom),
              itemCount: headerCount + rows.length,
              findChildIndexCallback: (key) => indexOf[key],
              itemBuilder: (context, i) {
                var index = i;
                if (widget.header != null) {
                  if (index == 0) return widget.header!;
                  index--;
                }
                if (index == 0) {
                  return _LeaderboardColumnHeader(
                    showMovement: widget.showMovement,
                    live: widget.live,
                  );
                }
                index--;
                final row = rows[index];
                return _tile(row, key: tileKey(row));
              },
            ),
          ),
        ),
        // A new order is waiting (the fan is scrolled away or scrolling):
        // floats over the top of the list, under the fixed header.
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: _order.hasPending
                  ? OrderChangedPill(
                      key: const ValueKey('order_changed_pill_shown'),
                      onTap: _refresh,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('no_order_changed_pill')),
            ),
          ),
        ),
        // The sticky own-row: bottom of the viewport, above the navbar.
        Positioned(
          left: 0,
          right: 0,
          bottom: 8 + MediaQuery.paddingOf(context).bottom,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: _pinned && selfRow != null
                ? Material(
                    key: const ValueKey('pinned_own_row'),
                    color: Colors.transparent,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _tile(selfRow),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no_pinned_own_row')),
          ),
        ),
      ],
    );
  }
}

/// "Order changed · tap to refresh": the accent-coloured pill that floats over
/// the top of a list whose order is being held still (the leaderboards and the
/// Players market share it). Filled with the fantasy accent (gold in dark, the
/// primary red in light) with whichever of black / white reads on it.
class OrderChangedPill extends StatelessWidget {
  const OrderChangedPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = fantasyAccent(context);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Semantics(
      key: const ValueKey('order_changed_pill'),
      button: true,
      label: kOrderChangedCopy,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: accent,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert, size: 16, color: onAccent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      kOrderChangedCopy,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: onAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
