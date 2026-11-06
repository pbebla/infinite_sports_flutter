// Recent-form bars (round 3, spec §4, owner mockup): every gameweek he has a
// record for, oldest → newest. Six fit across; a longer season scrolls
// sideways, opening on the newest week with a "Swipe for earlier weeks" hint
// (owner 2026-11-06). The week's points sit on top of each bar
// and "GW7" under it; tapping a bar selects that week (the Overview shows its
// breakdown). Plain widgets — no chart package. Bars use the fantasy accent
// (gold on dark, primary red on light); a negative week is a red stub, a
// voided week a muted stub labelled "Void". The gameweek being played (live
// everywhere, Task 7) is drawn HOLLOW — a 2 px outline in the bar's own tone,
// no fill — with a small red "LIVE" under its "GW7"; it fills in when the week
// settles. Its points are the provisional ones.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

class FantasyFormBars extends StatelessWidget {
  const FantasyFormBars({
    super.key,
    required this.bars,
    this.selectedGw,
    this.onTapBar,
    this.maxBarHeight = 84,
  });

  final List<FormBar> bars;
  final int? selectedGw;
  final ValueChanged<int>? onTapBar;
  final double maxBarHeight;

  static const double _stub = 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    // One scale for the whole season, so a bar's height means the same thing
    // wherever the chart is scrolled to.
    final top =
        bars.fold<int>(1, (m, b) => b.voided ? m : math.max(m, b.points));
    final scrolls = bars.length > kProfileFormBarsVisible;

    return LayoutBuilder(
      key: const ValueKey('profile_form_bars'),
      builder: (context, constraints) {
        // Up to six weeks share the width; a longer season keeps the six-week
        // slot width and scrolls sideways.
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 336.0;
        final slot = width /
            (scrolls ? kProfileFormBarsVisible : math.max(1, bars.length));
        final chart = SizedBox(
          width: slot * bars.length,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in bars)
                    SizedBox(
                      width: slot,
                      child: _Bar(
                        bar: b,
                        height: (!b.voided && b.points > 0)
                            ? math.max(_stub, b.points / top * maxBarHeight)
                            : _stub,
                        tone: b.voided
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
                            : (b.points < 0 ? fantasyDownRed(context) : accent),
                        selected: b.gw == selectedGw,
                        onTap: onTapBar == null ? null : () => onTapBar!(b.gw),
                      ),
                    ),
                ],
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in bars)
                    SizedBox(
                      width: slot,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'GW${b.gw}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: b.gw == selectedGw
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: b.gw == selectedGw
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          if (b.live)
                            Text(
                              'LIVE',
                              key: ValueKey('form_bar_live_${b.gw}'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: fantasyDownRed(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
        if (!scrolls) return chart;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // reverse: the chart opens on its newest weeks (the right-hand
            // end); swiping right brings the earlier ones in from the left.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: chart,
            ),
            const SizedBox(height: 6),
            Row(
              key: const ValueKey('profile_form_bars_hint'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_left,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  'Swipe for earlier weeks',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bar,
    required this.height,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final FormBar bar;
  final double height;
  final Color tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('form_bar_${bar.gw}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        decoration: BoxDecoration(
          color: selected
              ? scheme.onSurface.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              bar.voided ? 'Void' : '${bar.points}',
              key: ValueKey('form_bar_value_${bar.gw}'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: bar.voided ? 10.5 : 13,
                fontWeight: FontWeight.w800,
                color: bar.voided ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              key: ValueKey('form_bar_fill_${bar.gw}'),
              width: 24,
              height: height,
              decoration: BoxDecoration(
                // The week being played is hollow: an outline, no fill.
                color: bar.live ? null : tone,
                border: bar.live ? Border.all(color: tone, width: 2) : null,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
