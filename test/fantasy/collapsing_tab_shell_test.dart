// Release report #8 — the Fantasy hub header shrinks on scroll to a slim
// pinned bar, the tab row stays pinned under it, every tab keeps its own
// scroll offset, and the tab row shows when more tabs are off screen.
// The shell is proved here with plain tabs; fantasy_hub_page_test.dart
// proves it on the real hub (countdown still visible when collapsed).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/collapsing_tab_shell.dart';

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool extra = false;
  void setExtra(bool v) => setState(() => extra = v);

  @override
  Widget build(BuildContext context) {
    final labels = [
      'My Team',
      'Players',
      'Leaderboards',
      'News',
      'Rules',
      if (extra) 'Extra',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Hub')),
      body: CollapsingTabShell(
        initialIndex: widget.initialIndex,
        expandedHeader: const SizedBox(
          key: ValueKey('big'),
          height: 260,
          child: Center(child: Text('BIG HEADER')),
        ),
        collapsedHeader: const SizedBox(
          key: ValueKey('slim'),
          height: 40,
          child: Center(child: Text('SLIM BAR')),
        ),
        tabs: labels,
        children: [
          for (final l in labels)
            ListView.builder(
              key: ValueKey('list_$l'),
              itemCount: 60,
              itemBuilder: (_, i) =>
                  SizedBox(height: 48, child: Text('$l row $i')),
            ),
        ],
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester,
    {Brightness brightness = Brightness.light,
    double textScale = 1.0,
    GlobalKey<_HarnessState>? key,
    int initialIndex = 0}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: _Harness(key: key, initialIndex: initialIndex),
  ));
  await tester.pumpAndSettle();
}

ScrollableState _list(WidgetTester tester, String tab) => tester.state(
    find.descendant(
        of: find.byKey(ValueKey('list_$tab'), skipOffstage: false),
        matching: find.byType(Scrollable),
        skipOffstage: false));

double _headerHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('collapsing_header'))).height;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness, 360 px: expanded at top, slim after a scroll, '
        'expanded again at the top', (tester) async {
      await _pump(tester, brightness: brightness);
      expect(find.text('BIG HEADER'), findsOneWidget);
      expect(find.text('SLIM BAR'), findsNothing);
      expect(_headerHeight(tester), 260);

      await tester.drag(find.text('My Team row 2'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('BIG HEADER'), findsNothing);
      expect(find.text('SLIM BAR'), findsOneWidget);
      expect(_headerHeight(tester), 40);
      // The tab row stays pinned under the slim bar.
      expect(tester.getTopLeft(find.byType(TabBar)).dy,
          tester.getBottomLeft(find.byKey(const ValueKey('collapsing_header'))).dy);
      expect(tester.takeException(), isNull);

      await tester.fling(find.text('My Team row 8'), const Offset(0, 2000), 3000);
      await tester.pumpAndSettle();
      expect(find.text('BIG HEADER'), findsOneWidget);
      expect(find.text('SLIM BAR'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the collapse is animated: mid-way the header is between its '
      'two heights (no jump)', (tester) async {
    await _pump(tester);
    await tester.drag(find.text('My Team row 2'), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final h = _headerHeight(tester);
    expect(h, greaterThan(40));
    expect(h, lessThan(260));
    await tester.pumpAndSettle();
  });

  testWidgets('the collapse does not rebuild the tab body or move its scroll '
      'offset', (tester) async {
    await _pump(tester);
    final before = _list(tester, 'My Team');
    await tester.drag(find.text('My Team row 2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final after = _list(tester, 'My Team');
    expect(identical(before, after), isTrue);
    expect(after.position.pixels, greaterThan(0));
  });

  testWidgets('switching tabs and coming back keeps each tab\'s scroll offset '
      '(and its header state)', (tester) async {
    await _pump(tester);
    await tester.drag(find.text('My Team row 2'), const Offset(0, -500));
    await tester.pumpAndSettle();
    final myTeamOffset = _list(tester, 'My Team').position.pixels;
    expect(myTeamOffset, greaterThan(0));

    await tester.tap(find.widgetWithText(Tab, 'Players'));
    await tester.pumpAndSettle();
    // Players is at its top: the header opens again.
    expect(find.text('BIG HEADER'), findsOneWidget);
    expect(_list(tester, 'Players').position.pixels, 0);

    await tester.tap(find.widgetWithText(Tab, 'My Team'));
    await tester.pumpAndSettle();
    expect(_list(tester, 'My Team').position.pixels, myTeamOffset);
    expect(find.text('SLIM BAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness, 360 px: every tab label is whole (never '
        'ellipsized) and the clipped edge shows a "more tabs" fade',
        (tester) async {
      await _pump(tester, brightness: brightness);
      for (final l in ['My Team', 'Players', 'Leaderboards', 'News', 'Rules']) {
        final p = tester.renderObject<RenderParagraph>(find.descendant(
            of: find.widgetWithText(Tab, l), matching: find.text(l)));
        expect(p.didExceedMaxLines, isFalse, reason: l);
        expect(p.size.width,
            greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
            reason: l);
      }
      // Five tabs do not fit 360 px: the end edge fades, the start does not.
      expect(find.byKey(const ValueKey('tabs_more_end')), findsOneWidget);
      expect(find.byKey(const ValueKey('tabs_more_start')), findsNothing);

      await tester.drag(find.byType(TabBar), const Offset(-500, 0));
      await tester.pumpAndSettle();
      // Scrolled to the end: now the start edge fades instead.
      expect(find.byKey(const ValueKey('tabs_more_end')), findsNothing);
      expect(find.byKey(const ValueKey('tabs_more_start')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('text scale 1.3 at 360 px: no overflow expanded or collapsed',
      (tester) async {
    await _pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.drag(find.text('My Team row 2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('SLIM BAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens on the initial tab', (tester) async {
    await _pump(tester, initialIndex: 3);
    expect(find.text('News row 0'), findsOneWidget);
  });

  testWidgets('a live tab-count change (5 → 6 → 5) never throws, collapsed or '
      'not, on later tab switches', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await _pump(tester, key: key);
    await tester.drag(find.text('My Team row 2'), const Offset(0, -300));
    await tester.pumpAndSettle();

    key.currentState!.setExtra(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final l in ['Extra', 'Players', 'Rules', 'My Team']) {
      await tester.ensureVisible(find.widgetWithText(Tab, l));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, l));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: l);
    }
    await tester.ensureVisible(find.widgetWithText(Tab, 'Extra'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Extra'));
    await tester.pumpAndSettle();
    key.currentState!.setExtra(false); // removed while selected: clamps
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final l in ['Rules', 'My Team', 'News']) {
      await tester.ensureVisible(find.widgetWithText(Tab, l));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, l));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: l);
    }
  });
}
