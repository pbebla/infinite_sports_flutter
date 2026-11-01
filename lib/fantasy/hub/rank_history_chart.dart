// "Your rank this season" (leaderboard extras follow-up): the card at the top
// of the signed-in manager's OWN team page (the squad viewer, isSelf only) —
// a small line chart of his Overall rank after every finalized gameweek
// (Leaderboards/RankHistory, written by the functions' finalize) with rank 1
// at the TOP and the "#start → #now" journey label. (It used to fold open
// under the own leaderboard row; that row now opens the team page like every
// other row, and the card lives here.) Share follow-up: a "Share my rank"
// action renders your season as a branded story image (fantasy_share.dart)
// for Instagram stories / group chats.
//
// Plain widgets + CustomPaint (no chart package — house rule). Under two
// weeks of history there is no line to draw: a short muted note instead.
//
// House rules: theme-safe both modes (the line is the fantasy accent — gold
// in dark, primary red in light — on a scheme surface card); labels scale
// down rather than overflow at 360 px; screen readers get every week's rank.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_share_button.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

/// The panel's note while there is no line yet (0–1 weeks of history).
const String kRankHistoryNote =
    'Your rank line appears after your second scored gameweek.';

/// The chart's point layout inside [size]: gameweeks left → right (by week
/// number, so a gap week leaves a gap), the BEST rank (smallest number) at
/// the top and the worst at the bottom; a flat line runs through the middle.
/// [inset] keeps the dots inside the canvas.
List<Offset> rankChartOffsets(List<RankPoint> series, Size size,
    {double inset = 6}) {
  if (series.isEmpty) return const [];
  final ranks = series.map((p) => p.rank);
  final best = ranks.reduce((a, b) => a < b ? a : b);
  final worst = ranks.reduce((a, b) => a > b ? a : b);
  final firstGw = series.first.gameweek;
  final lastGw = series.last.gameweek;
  final w = size.width - 2 * inset;
  final h = size.height - 2 * inset;
  return [
    for (final p in series)
      Offset(
        inset +
            (lastGw == firstGw
                ? w / 2
                : (p.gameweek - firstGw) / (lastGw - firstGw) * w),
        inset + (worst == best ? h / 2 : (p.rank - best) / (worst - best) * h),
      ),
  ];
}

/// The own-team-page card: title + journey label, the chart (or the note),
/// and "Share my rank".
class RankHistoryPanel extends StatelessWidget {
  const RankHistoryPanel({
    super.key,
    required this.series,
    this.onShare,
  });

  final List<RankPoint> series;

  /// Renders + shares your rank story (given the button's context, the
  /// iPad share anchor). null = no "Share my rank" action.
  final Future<void> Function(BuildContext buttonContext)? onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final journey = rankJourneyLabel(series);
    return DecoratedBox(
      key: const ValueKey('rank_history_panel'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  'Your rank this season',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                if (journey != null)
                  Text(
                    journey,
                    key: const ValueKey('rank_history_journey'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (journey != null)
              RankHistoryChart(series: series)
            else
              Text(
                kRankHistoryNote,
                key: const ValueKey('rank_history_note'),
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            // Right-aligned; wraps rather than overflow.
            if (onShare != null)
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  FantasyShareButton(
                    key: const ValueKey('rank_history_share'),
                    label: 'Share my rank',
                    tooltip: 'Share my rank',
                    onShare: onShare!,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The line itself: best/worst rank labels down the left (rank 1 side on
/// top), the first/last gameweek under it. [series] needs ≥ 2 points.
class RankHistoryChart extends StatelessWidget {
  const RankHistoryChart({super.key, required this.series});

  final List<RankPoint> series;

  static const double _axisWidth = 40;
  static const double _axisGap = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ranks = series.map((p) => p.rank);
    final best = ranks.reduce((a, b) => a < b ? a : b);
    final worst = ranks.reduce((a, b) => a > b ? a : b);
    final label = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );
    Widget axisText(String text, Alignment alignment) => Align(
          alignment: alignment,
          child: FittedBox(
              fit: BoxFit.scaleDown, child: Text(text, style: label)),
        );

    return Semantics(
      container: true,
      label: rankSeriesSemantics(series),
      child: ExcludeSemantics(
        child: Column(
          key: const ValueKey('rank_history_chart'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 92,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _axisWidth,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        axisText('#$best', Alignment.centerRight),
                        if (worst != best)
                          axisText('#$worst', Alignment.centerRight),
                      ],
                    ),
                  ),
                  const SizedBox(width: _axisGap),
                  Expanded(
                    child: CustomPaint(
                      painter: _RankLinePainter(
                        series: series,
                        line: fantasyAccent(context),
                        grid: scheme.outlineVariant.withValues(alpha: 0.6),
                        dotCenter: scheme.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: _axisWidth + _axisGap),
              child: Row(
                children: [
                  Flexible(
                      child: axisText(
                          'GW${series.first.gameweek}', Alignment.centerLeft)),
                  const Spacer(),
                  Flexible(
                      child: axisText(
                          'GW${series.last.gameweek}', Alignment.centerRight)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankLinePainter extends CustomPainter {
  _RankLinePainter({
    required this.series,
    required this.line,
    required this.grid,
    required this.dotCenter,
  });

  final List<RankPoint> series;
  final Color line;
  final Color grid;
  final Color dotCenter;

  static const double _inset = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || size.isEmpty) return;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // The best-rank (top) and worst-rank (bottom) guides.
    for (final y in [_inset, size.height - _inset]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = rankChartOffsets(series, size, inset: _inset);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = line;
    for (final p in points.take(points.length - 1)) {
      canvas.drawCircle(p, 3, dot);
    }
    // "Now": a bigger ringed dot.
    canvas.drawCircle(points.last, 5, dot);
    canvas.drawCircle(points.last, 2.2, Paint()..color = dotCenter);
  }

  @override
  bool shouldRepaint(_RankLinePainter old) =>
      !listEquals(old.series, series) ||
      old.line != line ||
      old.grid != grid ||
      old.dotCenter != dotCenter;
}
