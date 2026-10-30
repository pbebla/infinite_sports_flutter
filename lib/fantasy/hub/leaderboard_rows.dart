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
// House rules: theme-safe both modes (fantasy accent = gold in dark, primary
// red in light; movement up = the pitch-green family, down = error); manager
// names WRAP and are never underlined or ellipsized; list clears the glass
// navbar; photos never gate rows (FantasyAvatar's initials fallback); the
// pinned row's appear/disappear is 200ms and zero under reduced motion.

import 'package:flutter/material.dart';
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

/// One ranked row: rank, movement cell (when the data provides one), avatar,
/// the two-line manager cell (real name; team name under it), points. The
/// signed-in manager's row carries the accent highlight.
class LeaderboardRowTile extends StatelessWidget {
  const LeaderboardRowTile({
    super.key,
    required this.row,
    this.showMovement = true,
    this.onTap,
  });

  final LeaderboardRowData row;
  final bool showMovement;
  final void Function(LeaderboardRowData row)? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final direction = movementDirection(row.movement);
    final secondary = row.secondaryName;

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
                Text(
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        // The own row: a clear gold (red in light) wash, not a whisper.
        color: row.isSelf
            ? accent.withValues(alpha: 0.20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('leaderboard_row_${row.uid}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap == null ? null : () => onTap!(row),
          child: row.isSelf
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: accent.withValues(alpha: 0.65)),
                  ),
                  child: content,
                )
              : content,
        ),
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
  });

  final List<LeaderboardRowData> rows;
  final bool showMovement;
  final void Function(LeaderboardRowData row)? onRowTap;

  /// Optional widget scrolled above everything (e.g. the week chips).
  final Widget? header;

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
                    showMovement: widget.showMovement);
              }
              index--;
              final row = rows[index];
              return LeaderboardRowTile(
                key: row.isSelf ? _ownKey : null,
                row: row,
                showMovement: widget.showMovement,
                onTap: widget.onRowTap,
              );
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
                      child: LeaderboardRowTile(
                        row: selfRow,
                        showMovement: widget.showMovement,
                        onTap: widget.onRowTap,
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no_pinned_own_row')),
          ),
        ),
      ],
    );
  }
}
