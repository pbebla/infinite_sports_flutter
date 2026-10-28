// Shared leaderboard presentation (P3d): the gameweek-podium top 3, the
// ranked row tile, and RankedLeaderboardList — the scrolling list that keeps
// the signed-in manager's row PINNED to the bottom of the viewport whenever
// its natural place is scrolled away (FPL-style sticky own-row, spec §10
// adopted decision). Used by the Overall and Gameweek scopes AND inside a
// mini-league, so the three can never drift apart.
//
// House rules: theme-safe both modes (fantasy accent = gold in dark, primary
// red in light; movement up = the pitch-green family, down = error); manager
// names WRAP and are never underlined; list clears the glass navbar; photos
// never gate rows (FantasyAvatar's initials fallback); the pinned row's
// appear/disappear is 200ms and zero under reduced motion.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

/// Movement arrow color for this theme: green up (pitch family — legitimate
/// in both themes), error down, muted neutral.
Color movementColor(BuildContext context, MovementDirection d) => switch (d) {
      MovementDirection.up => fantasyPitchGreen(context),
      MovementDirection.down => Theme.of(context).colorScheme.error,
      MovementDirection.none => Theme.of(context).colorScheme.onSurfaceVariant,
    };

/// One ranked row: rank, movement arrow (when the data provides one),
/// avatar, team name (wraps), points. The signed-in manager's row carries
/// the accent highlight.
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

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${row.displayRank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: row.isSelf ? accent : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (showMovement)
            SizedBox(
              width: 20,
              child: Text(
                movementGlyph(direction),
                key: ValueKey('movement_${row.uid}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: movementColor(context, direction),
                ),
              ),
            ),
          const SizedBox(width: 6),
          FantasyAvatar(name: row.name, photoUrl: row.photoUrl, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.name,
              // Wraps, never underlined or ellipsized (house rules).
              softWrap: true,
              style: TextStyle(
                fontSize: 14,
                fontWeight: row.isSelf ? FontWeight.w800 : FontWeight.w600,
                height: 1.25,
                color: scheme.onSurface,
              ),
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
        color: row.isSelf
            ? accent.withValues(alpha: 0.10)
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
                        Border.all(color: accent.withValues(alpha: 0.45)),
                  ),
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

/// The podium (spec §10 adopted decision): 2nd · 1st · 3rd, the champion
/// raised with the accent ring — medal-ish using the fantasy accent only,
/// no new assets.
class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({super.key, required this.top3, this.onTap});

  /// The first 1–3 rows, best first.
  final List<LeaderboardRowData> top3;
  final void Function(LeaderboardRowData row)? onTap;

  @override
  Widget build(BuildContext context) {
    // Visual order 2nd · 1st · 3rd; missing places just leave gaps.
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;
    return Padding(
      key: const ValueKey('leaderboard_podium'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : _PodiumSpot(row: second, champion: false, onTap: onTap)),
          Expanded(
              child: first == null
                  ? const SizedBox.shrink()
                  : _PodiumSpot(row: first, champion: true, onTap: onTap)),
          Expanded(
              child: third == null
                  ? const SizedBox.shrink()
                  : _PodiumSpot(row: third, champion: false, onTap: onTap)),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({
    required this.row,
    required this.champion,
    required this.onTap,
  });

  final LeaderboardRowData row;
  final bool champion;
  final void Function(LeaderboardRowData row)? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarSize = champion ? 64.0 : 50.0;

    return InkWell(
      key: ValueKey('podium_${row.uid}'),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap == null ? null : () => onTap!(row),
      child: Padding(
        // The runners-up sit a step lower than the champion.
        padding: EdgeInsets.only(top: champion ? 0 : 22, left: 4, right: 4),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      // Champion: the accent ring; runners-up: a quiet one.
                      color: champion
                          ? accent
                          : scheme.outlineVariant.withValues(alpha: 0.8),
                      width: champion ? 2.5 : 1.5,
                    ),
                  ),
                  child: FantasyAvatar(
                      name: row.name, photoUrl: row.photoUrl, size: avatarSize),
                ),
                Positioned(
                  bottom: -4,
                  right: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: champion ? accent : scheme.surfaceContainerHighest,
                      border: champion
                          ? null
                          : Border.all(color: scheme.outline, width: 1),
                    ),
                    child: Text(
                      '${row.displayRank}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        // Gold needs dark text; light's primary takes
                        // onPrimary (the armband badge's rule).
                        color: champion
                            ? (isDark ? Colors.black : scheme.onPrimary)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              row.name,
              textAlign: TextAlign.center,
              // Wraps, never underlined or ellipsized (house rules).
              softWrap: true,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${row.points} pts',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: champion ? accent : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrolling standings: podium for the top 3 (once there ARE three),
/// ranked tiles below, and the signed-in manager's row pinned to the bottom
/// of the viewport whenever its natural place is out of view.
class RankedLeaderboardList extends StatefulWidget {
  const RankedLeaderboardList({
    super.key,
    required this.rows,
    this.showMovement = true,
    this.usePodium = true,
    this.onRowTap,
    this.header,
  });

  final List<LeaderboardRowData> rows;
  final bool showMovement;
  final bool usePodium;
  final void Function(LeaderboardRowData row)? onRowTap;

  /// Optional widget scrolled above everything (e.g. the week chips).
  final Widget? header;

  @override
  State<RankedLeaderboardList> createState() => _RankedLeaderboardListState();
}

class _RankedLeaderboardListState extends State<RankedLeaderboardList> {
  /// Keys the signed-in manager's natural element (tile or podium spot) so
  /// the pin logic can ask where it is.
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
    final podium = widget.usePodium && rows.length >= 3;
    final podiumRows = podium ? rows.sublist(0, 3) : const <LeaderboardRowData>[];
    final tileRows = podium ? rows.sublist(3) : rows;
    final selfInPodium = podiumRows.any((r) => r.isSelf);
    final headerCount = (widget.header != null ? 1 : 0) + (podium ? 1 : 0);
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
            itemCount: headerCount + tileRows.length,
            itemBuilder: (context, i) {
              var index = i;
              if (widget.header != null) {
                if (index == 0) return widget.header!;
                index--;
              }
              if (podium) {
                if (index == 0) {
                  final podiumWidget = LeaderboardPodium(
                      top3: podiumRows, onTap: widget.onRowTap);
                  return selfInPodium
                      ? KeyedSubtree(key: _ownKey, child: podiumWidget)
                      : podiumWidget;
                }
                index--;
              }
              final row = tileRows[index];
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
