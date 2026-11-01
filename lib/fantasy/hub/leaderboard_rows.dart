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
// House rules: theme-safe both modes (fantasy accent = gold in dark, primary
// red in light; movement up = the pitch-green family, down = error); manager
// names WRAP and are never underlined or ellipsized; list clears the glass
// navbar; photos never gate rows (FantasyAvatar's initials fallback); the
// pinned row's appear/disappear is 200ms and zero under reduced motion.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/badge_shelf.dart'
    show BadgeCountChip, kBadgeCountChipHeight, kBadgeCountChipWidth;
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
    this.badgeCount = 0,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final direction = movementDirection(row.movement);
    final secondary = row.secondaryName;
    final mover = this.mover;
    final badgeCount = this.badgeCount;
    final reserveBadge = badgeCount == null;
    final showBadge = badgeCount != null && badgeCount > 0;

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
    final body = InkWell(
      key: ValueKey('leaderboard_row_${row.uid}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap == null ? null : () => onTap!(row),
      child: row.isSelf
          ? Container(foregroundDecoration: selfBorder, child: content)
          : content,
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
  const _LeaderboardColumnHeader({required this.showMovement});

  final bool showMovement;

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
  /// null = the counts are still loading: every row reserves the chip's
  /// fixed-size slot (no row moves when they land).
  final Map<String, int>? badgeCounts;

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

  @override
  void initState() {
    super.initState();
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(RankedLeaderboardList old) {
    super.didUpdateWidget(old);
    _scheduleCheck();
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
