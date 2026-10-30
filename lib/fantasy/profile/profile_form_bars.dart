// Recent-form bars (round 3, spec §4, owner mockup): the last six gameweeks
// he has a record for, oldest → newest, the week's points on top of each bar
// and "GW7" under it; tapping a bar selects that week (the Overview shows its
// breakdown). Plain widgets — no chart package. Bars use the fantasy accent
// (gold on dark, primary red on light); a negative week is a red stub, a
// voided week a muted stub labelled "Void".

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';

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
    final top =
        bars.fold<int>(1, (m, b) => b.voided ? m : math.max(m, b.points));

    return Column(
      key: const ValueKey('profile_form_bars'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in bars)
              Expanded(
                child: _Bar(
                  bar: b,
                  height: (!b.voided && b.points > 0)
                      ? math.max(_stub, b.points / top * maxBarHeight)
                      : _stub,
                  tone: b.voided
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
                      : (b.points < 0 ? scheme.error : accent),
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
          children: [
            for (final b in bars)
              Expanded(
                child: Text(
                  'GW${b.gw}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        b.gw == selectedGw ? FontWeight.w800 : FontWeight.w600,
                    color: b.gw == selectedGw
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
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
              width: 24,
              height: height,
              decoration: BoxDecoration(
                color: tone,
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
