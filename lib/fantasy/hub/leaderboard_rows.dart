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
// Leaderboard extras (follow-up), both opt-in so the Gameweek scope and the
// mini-league lists are untouched: [RankedLeaderboardList.movers] puts the
// week's biggest-climber flame / biggest-drop badge beside a manager's name
// (Overall), and [RankedLeaderboardList.selfPanelBuilder] makes the signed-in
// manager's row — natural AND pinned copy — expand into a panel ("Your rank
// this season") instead of opening the squad viewer (Overall).
//
// Badges (spec 2026-10-30 §5), opt-in like the extras:
// [RankedLeaderboardList.badgeCounts] puts the small military_tech + N chip
// beside a manager's name (Overall and Gameweek — never the mini-league
// lists); it wraps with the climber/drop badge after a long name.
//
// House rules: theme-safe both modes (fantasy accent = gold in dark, primary
// red in light; movement up = the pitch-green family, down = error); manager
// names WRAP and are never underlined or ellipsized; list clears the glass
// navbar; photos never gate rows (FantasyAvatar's initials fallback); the
// pinned row's appear/disappear and the own-row panel's expand are 200ms and
// zero under reduced motion.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/badge_shelf.dart'
    show BadgeCountChip;
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

// Column geometry shared by the rows and the column header so "#", the
// movement cell and the manager column line up.
const double _rankWidth = 30;
const double _movementWidth = 36;
const double _avatarSize = 38;
const double _afterMovementGap = 6;
const double _afterAvatarGap = 10;
// The own row's expand chevron after the points. When a list has one, EVERY
// row (and the "Pts" header) reserves this width so the points column lines
// up (review fix).
const double _chevronGap = 2;
const double _chevronSize = 18;

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

/// One ranked row: rank, movement cell (when the data provides one), avatar,
/// the two-line manager cell (real name; team name under it), points. The
/// signed-in manager's row carries the accent highlight.
class LeaderboardRowTile extends StatelessWidget {
  const LeaderboardRowTile({
    super.key,
    required this.row,
    this.showMovement = true,
    this.onTap,
    this.mover,
    this.expanded,
    this.footer,
    this.reserveChevron = false,
    this.badgeCount = 0,
  });

  final LeaderboardRowData row;
  final bool showMovement;
  final void Function(LeaderboardRowData row)? onTap;

  /// The week's biggest climber / faller badge beside the name (Overall).
  final WeeklyMover? mover;

  /// The manager's achievement-badge count, shown as a chip beside the name
  /// when > 0 (Overall + Gameweek).
  final int badgeCount;

  /// Expandable row (the own row on Overall): null = not expandable (no
  /// chevron); false/true = the folded/unfolded chevron after the points.
  final bool? expanded;

  /// Rendered under the row, inside its highlight (the own-row panel slot).
  final Widget? footer;

  /// A non-expandable row in a list whose own row HAS the chevron: keep its
  /// width empty after the points so every row's points line up.
  final bool reserveChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final direction = movementDirection(row.movement);
    final secondary = row.secondaryName;
    final mover = this.mover;
    final expanded = this.expanded;

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
            child: Text(
              '${row.displayRank}',
              textAlign: TextAlign.center,
              // The rank is the gold/red accent on every row (the mockup).
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: accent,
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
                if (mover == null && badgeCount <= 0)
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
                      if (badgeCount > 0)
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
          if (expanded != null) ...[
            const SizedBox(width: _chevronGap),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              key: ValueKey('own_row_chevron_${row.uid}'),
              size: _chevronSize,
              color: scheme.onSurfaceVariant,
              semanticLabel: expanded
                  ? 'Hide your rank this season'
                  : 'Show your rank this season',
            ),
          ] else if (reserveChevron)
            const SizedBox(width: _chevronGap + _chevronSize),
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
    final footer = this.footer;
    final Widget body;
    if (footer == null) {
      body = InkWell(
        key: ValueKey('leaderboard_row_${row.uid}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap == null ? null : () => onTap!(row),
        child: row.isSelf
            ? Container(foregroundDecoration: selfBorder, child: content)
            : content,
      );
    } else {
      // The tappable row with its panel under it, both inside the highlight.
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('leaderboard_row_${row.uid}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap == null ? null : () => onTap!(row),
            child: content,
          ),
          footer,
        ],
      );
      body = row.isSelf
          ? Container(foregroundDecoration: selfBorder, child: column)
          : column;
    }

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
  const _LeaderboardColumnHeader({
    required this.showMovement,
    this.reserveChevron = false,
  });

  final bool showMovement;

  /// Mirrors [LeaderboardRowTile.reserveChevron] so "Pts" sits over points.
  final bool reserveChevron;

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
              Expanded(child: Text('Manager', style: style)),
              Text('Pts', style: style),
              if (reserveChevron)
                const SizedBox(width: _chevronGap + _chevronSize),
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
class RankedLeaderboardList extends StatefulWidget {
  const RankedLeaderboardList({
    super.key,
    required this.rows,
    this.showMovement = true,
    this.onRowTap,
    this.header,
    this.movers = const {},
    this.selfPanelBuilder,
    this.badgeCounts = const {},
  });

  final List<LeaderboardRowData> rows;
  final bool showMovement;
  final void Function(LeaderboardRowData row)? onRowTap;

  /// Optional widget scrolled above everything (e.g. the week chips).
  final Widget? header;

  /// uid → the week's biggest climber / faller badge (Overall only).
  final Map<String, WeeklyMover> movers;

  /// uid → achievement-badge count (Overall + Gameweek; empty elsewhere).
  final Map<String, int> badgeCounts;

  /// When set (Overall), tapping the signed-in manager's row — natural or
  /// pinned — folds this panel open under it instead of calling [onRowTap];
  /// the panel carries its own way to the squad viewer.
  final Widget Function(LeaderboardRowData self)? selfPanelBuilder;

  @override
  State<RankedLeaderboardList> createState() => _RankedLeaderboardListState();
}

class _RankedLeaderboardListState extends State<RankedLeaderboardList> {
  /// Keys the signed-in manager's natural tile so the pin logic can ask where
  /// it is.
  final GlobalKey _ownKey = GlobalKey();
  bool _pinned = false;

  /// The own-row panel is open (shared by the natural row and its pinned
  /// copy, so both always agree).
  bool _selfExpanded = false;

  @override
  void initState() {
    super.initState();
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(RankedLeaderboardList old) {
    super.didUpdateWidget(old);
    // A scope without the panel (the State can be reused across scopes)
    // starts folded the next time one has it.
    if (widget.selfPanelBuilder == null) _selfExpanded = false;
    _scheduleCheck();
  }

  void _toggleSelfPanel() {
    setState(() => _selfExpanded = !_selfExpanded);
    // The own row changed height: re-check whether it is still in view.
    _scheduleCheck();
  }

  /// A row tile with the opt-in extras: the mover badge, and for the own
  /// row (when [RankedLeaderboardList.selfPanelBuilder] is set) the
  /// tap-to-expand panel.
  /// The own row expands (chevron after its points) — so every other row
  /// and the column header reserve the chevron's width.
  bool get _hasExpandableOwnRow =>
      widget.selfPanelBuilder != null && widget.rows.any((r) => r.isSelf);

  Widget _tile(LeaderboardRowData row, {Key? key}) {
    final builder = row.isSelf ? widget.selfPanelBuilder : null;
    if (builder == null) {
      return LeaderboardRowTile(
        key: key,
        row: row,
        showMovement: widget.showMovement,
        onTap: widget.onRowTap,
        mover: widget.movers[row.uid],
        badgeCount: widget.badgeCounts[row.uid] ?? 0,
        reserveChevron: _hasExpandableOwnRow,
      );
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final panel = _selfExpanded
        ? builder(row)
        : const SizedBox(width: double.infinity);
    return LeaderboardRowTile(
      key: key,
      row: row,
      showMovement: widget.showMovement,
      onTap: (_) => _toggleSelfPanel(),
      mover: widget.movers[row.uid],
      badgeCount: widget.badgeCounts[row.uid] ?? 0,
      expanded: _selfExpanded,
      footer: reduceMotion
          ? panel
          : AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: panel,
            ),
    );
  }

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
    final rows = widget.rows;
    // The optional header, then the column header, then the rows.
    final headerCount = (widget.header != null ? 1 : 0) + 1;
    final selfRow = rows.where((r) => r.isSelf).firstOrNull;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            // Scroll notifications can fire DURING viewport layout — reading
            // render-box geometry there asserts. Defer to after the frame.
            _scheduleCheck();
            return false;
          },
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
                0, 4, 0, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: headerCount + rows.length,
            itemBuilder: (context, i) {
              var index = i;
              if (widget.header != null) {
                if (index == 0) return widget.header!;
                index--;
              }
              if (index == 0) {
                return _LeaderboardColumnHeader(
                  showMovement: widget.showMovement,
                  reserveChevron: _hasExpandableOwnRow,
                );
              }
              index--;
              final row = rows[index];
              return _tile(row, key: row.isSelf ? _ownKey : null);
            },
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
