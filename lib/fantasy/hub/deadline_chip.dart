// The deadline countdown chip (P3a Task 2) — embedded on the Rules tab
// (spec §10a "contextual help everywhere") — plus the hub header's live
// FPL-style countdown (P3b feedback Task 4): four boxes (Days / Hours / Min
// / Sec) ticking every second toward the current gameweek's lock. League
// timezone only, and every countdown also shows the ABSOLUTE lock time
// (spec §5: "Sun, Oct 19 · 3:00 PM"). When the owner's lockOverride is
// 'open' (test bed) both render the "editing open" chip instead.
//
// Release report #8: the hub header collapses on scroll to a slim one-line
// bar that still shows the deadline ([FantasyDeadlineSlimLine]). The hub
// owns ONE [FantasyDeadlineClock]; the big boxes, their chip fallback and
// the slim line all read it, so the two faces never disagree and no second
// timer runs. Every face is computed by [deadlineChipFace] /
// [deadlineSlimFace] (pure, unit-tested).
//
// Review 6, I2: a failed schedule read is not a fact. With [scheduleUnknown]
// (FantasyScheduleFeed.scheduleUnknown) and the automatic lock, every face
// says "Deadline unavailable" — no made-up time, never "Season complete" or
// "Locked". The league's override is a Config fact and is still stated.
//
// The tick is INFORMATION, not decoration: it keeps running under reduced
// motion (a clock must tell the time) but nothing animates per tick, and
// every timer cancels on dispose — a stream reconnect can never replay them.

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
    this.clock,
    this.scheduleUnknown = false,
    this.onRetry,
  });

  final List<Gameweek> gameweeks;
  final FantasyLockOverride lockOverride;

  /// Test seam: injected clock. Production leaves it null (real UTC now).
  final DateTime Function()? nowUtc;

  /// A shared ticking clock (the hub header's): when set, the chip reads its
  /// time and owns no timer of its own.
  final FantasyDeadlineClock? clock;

  /// The schedule read failed ([gameweeks] is empty for that reason only).
  final bool scheduleUnknown;

  /// Non-null once the schedule feed has GIVEN UP retrying (re-review 6b,
  /// item 2): the unknown face says so and shows "Try again".
  final VoidCallback? onRetry;

  @override
  State<FantasyDeadlineChip> createState() => _FantasyDeadlineChipState();
}

class _FantasyDeadlineChipState extends State<FantasyDeadlineChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 30s refresh keeps the minute countdown honest without a per-second
    // rebuild; cancelled in dispose (never ticks a dead widget). A shared
    // clock replaces the timer (its owner rebuilds this chip per tick).
    if (widget.clock == null) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now =>
      widget.clock?.value ?? (widget.nowUtc ?? () => DateTime.now().toUtc())();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Fantasy accent: gold in dark mode, primary red in light (house rule).
    final accent = isDark
        ? TournamentColors.gold
        : Theme.of(context).colorScheme.primary;

    final face = deadlineChipFace(widget.gameweeks, widget.lockOverride, _now,
        scheduleUnknown: widget.scheduleUnknown,
        gaveUp: widget.onRetry != null);
    final retry = face.title == kDeadlineUnavailable ? widget.onRetry : null;
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
          Icon(face.icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  face.title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (face.detail != null)
                  Text(
                    face.detail!,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                      fontSize: 11.5,
                    ),
                  ),
                if (retry != null)
                  TextButton(
                    key: const ValueKey('deadline_retry'),
                    onPressed: retry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Try again'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chip's face at [now] — icon, title and the muted detail line. One
/// source for the chip, the big countdown's fallback and (through
/// [deadlineSlimFace]) the collapsed header's slim line.
({IconData icon, String title, String? detail}) deadlineChipFace(
    List<Gameweek> gameweeks, FantasyLockOverride lockOverride, DateTime now,
    {bool scheduleUnknown = false, bool gaveUp = false}) {
  switch (lockOverride) {
    case FantasyLockOverride.open:
      return (
        icon: Icons.lock_open,
        title: 'Editing open',
        detail: 'league override',
      );
    case FantasyLockOverride.locked:
      return (icon: Icons.lock, title: 'Locked by the league', detail: null);
    case FantasyLockOverride.auto:
      final gw = currentGameweek(gameweeks, now);
      if (gw == null && scheduleUnknown) {
        // The read failed: say so — no time, no "complete", no "locked".
        return (
          icon: Icons.schedule,
          title: kDeadlineUnavailable,
          // Retrying: nothing to add. Given up: say so plainly.
          detail: gaveUp ? "Couldn't load the schedule" : null,
        );
      }
      if (gw == null) {
        return (icon: Icons.flag, title: 'Season complete', detail: null);
      }
      switch (gw.statusAt(now)) {
        case GameweekStatus.open:
          final left = gw.lockUtc.difference(now);
          return (
            icon: Icons.timer_outlined,
            title: 'GW${gw.number} locks in ${formatCountdown(left)}',
            detail: formatAbsoluteLock(gw),
          );
        case GameweekStatus.upcoming:
          // A week opens at league midnight after the previous game day,
          // so it names that weekday — game days are not always Sundays.
          // (An upcoming week always has an opens instant: only GW1 has
          // none, and it is open from launch.)
          final opens = gw.opensUtc;
          return (
            icon: Icons.schedule,
            title: opens == null
                ? 'GW${gw.number} opens soon'
                : 'GW${gw.number} opens ${formatOpensWeekday(opens)}',
            detail: 'locks ${formatAbsoluteLock(gw)}',
          );
        case GameweekStatus.locked:
          return (
            icon: Icons.lock,
            title: 'GW${gw.number} locked',
            detail: 'locked ${formatAbsoluteLock(gw)}',
          );
      }
  }
}

/// The neutral face when the schedule could not be read (review 6, I2).
const String kDeadlineUnavailable = 'Deadline unavailable';

/// The gameweek whose deadline is counting down at [now] (open under the
/// automatic lock), or null — the big boxes and the slim line agree on it.
Gameweek? _countingGameweek(
    List<Gameweek> gameweeks, FantasyLockOverride lockOverride, DateTime now) {
  if (lockOverride != FantasyLockOverride.auto) return null;
  final gw = currentGameweek(gameweeks, now);
  if (gw == null || gw.statusAt(now) != GameweekStatus.open) return null;
  return gw;
}

/// The collapsed hub header's one-line face (release report #8): while the
/// deadline counts down, `GW3 locks in` + `2d 04:13:22` (seconds live, like
/// the boxes); otherwise the chip's title, naming the gameweek when the
/// league override hides it ("GW3 · Editing open").
({IconData icon, String label, String? countdown}) deadlineSlimFace(
    List<Gameweek> gameweeks, FantasyLockOverride lockOverride, DateTime now,
    {bool scheduleUnknown = false}) {
  final counting = _countingGameweek(gameweeks, lockOverride, now);
  if (counting != null) {
    final p = countdownParts(counting.lockUtc.difference(now));
    final hms = '${countdownDigits(p.hours)}:${countdownDigits(p.minutes)}'
        ':${countdownDigits(p.seconds)}';
    return (
      icon: Icons.timer_outlined,
      label: 'GW${counting.number} locks in',
      countdown: p.days > 0 ? '${p.days}d $hms' : hms,
    );
  }
  final face = deadlineChipFace(gameweeks, lockOverride, now,
      scheduleUnknown: scheduleUnknown);
  var label = face.title;
  if (lockOverride != FantasyLockOverride.auto) {
    final gw = currentGameweek(gameweeks, now);
    if (gw != null) label = 'GW${gw.number} · $label';
  }
  return (icon: face.icon, label: label, countdown: null);
}

/// The ONE ticking clock behind the hub header (release report #8): the big
/// countdown boxes, their chip fallback and the collapsed slim line all read
/// it, so the two faces never disagree and there is no second timer. Ticks
/// every second (information, not decoration — it keeps running under
/// reduced motion); [dispose] cancels it.
class FantasyDeadlineClock extends ValueNotifier<DateTime> {
  FantasyDeadlineClock({DateTime Function()? nowUtc})
      : this._(nowUtc ?? () => DateTime.now().toUtc());

  FantasyDeadlineClock._(this._now) : super(_now()) {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      value = _now();
    });
  }

  final DateTime Function() _now;
  late final Timer _ticker;

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }
}

/// The collapsed hub header's line (release report #8): icon, label and —
/// while the deadline counts down — the live countdown, on ONE line that
/// scales down rather than wrapping or clipping at large text sizes.
class FantasyDeadlineSlimLine extends StatelessWidget {
  const FantasyDeadlineSlimLine({
    super.key,
    required this.gameweeks,
    required this.lockOverride,
    required this.clock,
    this.scheduleUnknown = false,
    this.onRetry,
  });

  final List<Gameweek> gameweeks;
  final FantasyLockOverride lockOverride;
  final FantasyDeadlineClock clock;

  /// The schedule read failed (see [deadlineSlimFace]).
  final bool scheduleUnknown;

  /// Non-null once retrying has stopped: a "Try again" button on the line.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = FantasyBanner.accent(context);
    return ValueListenableBuilder<DateTime>(
      valueListenable: clock,
      builder: (context, now, _) {
        final f = deadlineSlimFace(gameweeks, lockOverride, now,
            scheduleUnknown: scheduleUnknown);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(f.icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                f.label,
                key: const ValueKey('deadline_slim_label'),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FantasyBanner.foreground(context),
                ),
              ),
              if (onRetry != null && f.label == kDeadlineUnavailable) ...[
                const SizedBox(width: 6),
                TextButton(
                  key: const ValueKey('deadline_slim_retry'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Try again'),
                ),
              ],
              if (f.countdown != null) ...[
                const SizedBox(width: 6),
                Text(
                  f.countdown!,
                  key: const ValueKey('deadline_slim_countdown'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    // Tabular figures: the line never jitters per tick.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
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
    this.clock,
    this.scheduleUnknown = false,
    this.onRetry,
  });

  final List<Gameweek> gameweeks;
  final FantasyLockOverride lockOverride;

  /// Test seam: injected clock. Production leaves it null (real UTC now).
  final DateTime Function()? nowUtc;

  /// The schedule read failed: the chip face says "Deadline unavailable".
  final bool scheduleUnknown;

  /// Non-null once retrying has stopped (passed to the chip face).
  final VoidCallback? onRetry;

  /// A shared ticking clock (the hub header's — release report #8): when
  /// set, the countdown follows it and owns no timer, so the collapsed
  /// header's slim line and these boxes tick from ONE source.
  final FantasyDeadlineClock? clock;

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
    // and it's cancelled in dispose. With a shared clock, the clock ticks.
    if (widget.clock == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    if (clock == null) {
      return _face(
          context, (widget.nowUtc ?? () => DateTime.now().toUtc())());
    }
    return ValueListenableBuilder<DateTime>(
      valueListenable: clock,
      builder: (context, now, _) => _face(context, now),
    );
  }

  Widget _face(BuildContext context, DateTime now) {
    final gw = _countingGameweek(widget.gameweeks, widget.lockOverride, now);
    if (gw == null) {
      // Override / upcoming / locked / season-over: the chip faces.
      return FantasyDeadlineChip(
        gameweeks: widget.gameweeks,
        lockOverride: widget.lockOverride,
        nowUtc: widget.nowUtc,
        clock: widget.clock,
        scheduleUnknown: widget.scheduleUnknown,
        onRetry: widget.onRetry,
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
