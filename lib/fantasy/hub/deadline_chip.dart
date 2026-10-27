// The deadline countdown chip (P3a Task 2) — pinned in the hub header and
// embedded on the Rules tab (spec §10a "contextual help everywhere"). League
// timezone only, and every countdown also shows the ABSOLUTE lock time
// (spec §5: "Sun, Oct 19 · 3:00 PM"). When the owner's lockOverride is
// 'open' (test bed) it shows an "editing open" chip instead.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

class FantasyDeadlineChip extends StatefulWidget {
  const FantasyDeadlineChip({
    super.key,
    required this.gameweeks,
    required this.lockOverride,
    this.nowUtc,
  });

  final List<Gameweek> gameweeks;
  final FantasyLockOverride lockOverride;

  /// Test seam: injected clock. Production leaves it null (real UTC now).
  final DateTime Function()? nowUtc;

  @override
  State<FantasyDeadlineChip> createState() => _FantasyDeadlineChipState();
}

class _FantasyDeadlineChipState extends State<FantasyDeadlineChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 30s refresh keeps the minute countdown honest without a per-second
    // rebuild; cancelled in dispose (never ticks a dead widget).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Fantasy accent: gold in dark mode, primary red in light (house rule).
    final accent = isDark
        ? TournamentColors.gold
        : Theme.of(context).colorScheme.primary;

    final (IconData icon, String title, String? detail) = _content();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, String?) _content() {
    switch (widget.lockOverride) {
      case FantasyLockOverride.open:
        return (Icons.lock_open, 'Editing open', 'league override');
      case FantasyLockOverride.locked:
        return (Icons.lock, 'Locked by the league', null);
      case FantasyLockOverride.auto:
        final gw = currentGameweek(widget.gameweeks, _now);
        if (gw == null) {
          return (Icons.flag, 'Season complete', null);
        }
        switch (gw.statusAt(_now)) {
          case GameweekStatus.open:
            final left = gw.lockUtc.difference(_now);
            return (
              Icons.timer_outlined,
              'GW${gw.number} locks in ${formatCountdown(left)}',
              formatAbsoluteLock(gw),
            );
          case GameweekStatus.upcoming:
            return (
              Icons.schedule,
              'GW${gw.number} opens Monday',
              'locks ${formatAbsoluteLock(gw)}',
            );
          case GameweekStatus.locked:
            return (
              Icons.lock,
              'GW${gw.number} locked',
              'locked ${formatAbsoluteLock(gw)}',
            );
        }
    }
  }
}
