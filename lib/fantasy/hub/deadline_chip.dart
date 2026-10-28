// The deadline countdown chip (P3a Task 2) — embedded on the Rules tab
// (spec §10a "contextual help everywhere") — plus the hub header's live
// FPL-style countdown (P3b feedback Task 4): four boxes (Days / Hours / Min
// / Sec) ticking every second toward the current gameweek's lock. League
// timezone only, and every countdown also shows the ABSOLUTE lock time
// (spec §5: "Sun, Oct 19 · 3:00 PM"). When the owner's lockOverride is
// 'open' (test bed) both render the "editing open" chip instead.
//
// The tick is INFORMATION, not decoration: it keeps running under reduced
// motion (a clock must tell the time) but nothing animates per tick, and
// both timers cancel on dispose — a stream reconnect can never replay them.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
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

/// The hub header's live deadline countdown (P3b feedback Task 4): while the
/// current gameweek is OPEN under the automatic lock, four boxes — Days /
/// Hours / Min / Sec — tick every second over the absolute lock line. Every
/// other state (league override open/locked, upcoming, locked, season over)
/// falls back to the [FantasyDeadlineChip] faces, so "Editing open · league
/// override" and "GW locked" keep their chips.
class FantasyDeadlineCountdown extends StatefulWidget {
  const FantasyDeadlineCountdown({
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
  State<FantasyDeadlineCountdown> createState() =>
      _FantasyDeadlineCountdownState();
}

class _FantasyDeadlineCountdownState extends State<FantasyDeadlineCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 1s tick — the seconds box is live. Information, not decoration: it
    // keeps ticking under reduced motion (no per-tick animation anywhere),
    // and it's cancelled in dispose.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
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
    final now = _now;
    final gw = widget.lockOverride == FantasyLockOverride.auto
        ? currentGameweek(widget.gameweeks, now)
        : null;
    final counting = gw != null && gw.statusAt(now) == GameweekStatus.open;
    if (!counting) {
      // Override / upcoming / locked / season-over: the chip faces.
      return FantasyDeadlineChip(
        gameweeks: widget.gameweeks,
        lockOverride: widget.lockOverride,
        nowUtc: widget.nowUtc,
      );
    }

    final accent = FantasyBanner.accent(context);
    final parts = countdownParts(gw.lockUtc.difference(now));
    return Column(
      key: const ValueKey('deadline_countdown'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CountdownBox(
                value: parts.days, label: 'Days', accent: accent),
            const SizedBox(width: 8),
            _CountdownBox(
                value: parts.hours, label: 'Hours', accent: accent),
            const SizedBox(width: 8),
            _CountdownBox(
                value: parts.minutes, label: 'Min', accent: accent),
            const SizedBox(width: 8),
            _CountdownBox(
                value: parts.seconds, label: 'Sec', accent: accent),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'GW${gw.number} deadline · ${formatAbsoluteLock(gw)}',
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: FantasyBanner.foregroundMuted(context),
          ),
        ),
      ],
    );
  }
}

class _CountdownBox extends StatelessWidget {
  const _CountdownBox({
    required this.value,
    required this.label,
    required this.accent,
  });

  final int value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            countdownDigits(value),
            style: TextStyle(
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w800,
              // Tabular figures: the boxes never jitter as digits tick.
              fontFeatures: const [FontFeature.tabularFigures()],
              color: FantasyBanner.foreground(context),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: FantasyBanner.foregroundMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}
