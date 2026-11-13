// Live everywhere, Task 6 — the "Your rank this season" chart while a
// gameweek is being played: the live end point is drawn HOLLOW (a 2 px ring,
// no fill; settled it is solid), the "#start → #now" label uses the live rank,
// and the panel says LIVE with the shared pill (only while live). Light and
// dark, 360 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart'
    show fantasyAccent;
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';

import '../helpers/chart_paint.dart';

const settledSeries = <RankPoint>[
  (gameweek: 1, rank: 14, live: false),
  (gameweek: 2, rank: 12, live: false),
  (gameweek: 3, rank: 10, live: false),
];

const liveSeries = <RankPoint>[
  (gameweek: 1, rank: 14, live: false),
  (gameweek: 2, rank: 12, live: false),
  (gameweek: 3, rank: 10, live: true),
];

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    List<RankPoint> series, {
    Brightness brightness = Brightness.light,
    Size size = const Size(420, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: RankHistoryPanel(series: series, onShare: (_) async {}),
        ),
      ),
    ));
    // The live pill pulses forever: a fixed pump, never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder linePainter() => find.descendant(
      of: find.byKey(const ValueKey('rank_history_chart')),
      matching: find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_RankLinePainter'));

  group('the end point', () {
    for (final brightness in Brightness.values) {
      testWidgets(
          'live: hollow — a 2 px ring in the line colour, no fill '
          '— $brightness', (tester) async {
        await pumpPanel(tester, liveSeries, brightness: brightness);
        final accent = fantasyAccent(tester.element(linePainter()));
        final render = tester.renderObject<RenderBox>(linePainter());
        final end = rankChartOffsets(liveSeries, render.size).last;

        expect(
            render,
            paints
              // The settled weeks stay solid dots…
              ..circle(radius: 3, style: PaintingStyle.fill)
              ..circle(radius: 3, style: PaintingStyle.fill));
        // …the live one is a 2 px ring in the line colour, centred on its
        // point…
        expect(render, paintsHollowRing(center: end, color: accent));
        // …and NOTHING is filled at the live point: no solid "now" dot, no
        // centre dot.
        expect(render, isNot(paintsSolidDotAt(end)));
      });

      testWidgets(
          'settled: the "now" dot is solid again, nothing hollow '
          '— $brightness', (tester) async {
        await pumpPanel(tester, settledSeries, brightness: brightness);
        final render = tester.renderObject<RenderBox>(linePainter());
        final end = rankChartOffsets(settledSeries, render.size).last;

        expect(render, paintsSolidDotAt(end, radius: 5));
        expect(render, paintsNoRing());
      });
    }

    testWidgets(
        'only the LAST point can be live: an earlier flag draws '
        'nothing special', (tester) async {
      const odd = <RankPoint>[
        (gameweek: 1, rank: 14, live: true),
        (gameweek: 2, rank: 12, live: false),
      ];
      await pumpPanel(tester, odd);
      final render = tester.renderObject<RenderBox>(linePainter());
      expect(render, paintsNoRing());
    });
  });

  group('the label and the pill', () {
    testWidgets(
        'the "#start → #now" label uses the live rank; the pill is '
        'there only while live', (tester) async {
      await pumpPanel(tester, liveSeries);
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('rank_history_panel')),
              matching: find.byType(FantasyLivePill)),
          findsOneWidget);

      await pumpPanel(tester, settledSeries);
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(find.byType(FantasyLivePill), findsNothing);
    });

    testWidgets('under two weeks there is no line, so no live pill either',
        (tester) async {
      await pumpPanel(tester, const [(gameweek: 1, rank: 4, live: true)]);
      expect(find.byKey(const ValueKey('rank_history_note')), findsOneWidget);
      expect(find.byType(FantasyLivePill), findsNothing);
    });

    testWidgets('a repaint when the week settles: ring → dot', (tester) async {
      await pumpPanel(tester, liveSeries);
      expect(tester.renderObject(linePainter()), paintsHollowRing());
      await pumpPanel(tester, settledSeries);
      expect(tester.renderObject(linePainter()), paintsNoRing());
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px: title + journey + pill + share fit — $brightness',
          (tester) async {
        await pumpPanel(tester, liveSeries,
            brightness: brightness, size: const Size(360, 640));
        expect(tester.takeException(), isNull);
        for (final finder in [
          find.byKey(const ValueKey('rank_history_panel')),
          find.byKey(const ValueKey('rank_history_journey')),
          find.byType(FantasyLivePill),
          find.byKey(const ValueKey('rank_history_share')),
        ]) {
          final r = tester.getRect(finder);
          expect(r.left, greaterThanOrEqualTo(0), reason: '$finder');
          expect(r.right, lessThanOrEqualTo(360), reason: '$finder');
        }
      });
    }
  });
}
