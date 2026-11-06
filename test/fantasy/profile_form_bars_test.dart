// Recent-form bars show the whole season: up to six fit at once; more scroll
// sideways, opening on the latest week, with a hint to swipe for earlier
// weeks. One scale (the season's best week) sizes every bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_form_bars.dart';

List<FormBar> _bars(int n, {int Function(int gw)? points}) => [
      for (var gw = 1; gw <= n; gw++)
        FormBar(gw: gw, points: points?.call(gw) ?? gw, voided: false),
    ];

Future<void> _pump(
  WidgetTester tester,
  List<FormBar> bars, {
  ValueChanged<int>? onTap,
  Size size = const Size(420, 800),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FantasyFormBars(bars: bars, onTapBar: onTap),
      ),
    ),
  ));
}

Finder _key(String k) => find.byKey(ValueKey(k));

bool _onScreen(WidgetTester tester, Finder f, double width) {
  final r = tester.getRect(f);
  return r.right > 0 && r.left < width;
}

void main() {
  testWidgets('six weeks or fewer fill the width with no scrolling and no hint',
      (tester) async {
    await _pump(tester, _bars(4));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(_key('profile_form_bars_hint'), findsNothing);
    for (var gw = 1; gw <= 4; gw++) {
      expect(_key('form_bar_$gw'), findsOneWidget);
    }
  });

  testWidgets(
      'more than six weeks: every week is there, the latest is on screen first '
      'and the oldest is off to the left', (tester) async {
    await _pump(tester, _bars(12));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    for (var gw = 1; gw <= 12; gw++) {
      expect(_key('form_bar_$gw'), findsOneWidget);
    }
    expect(_onScreen(tester, _key('form_bar_12'), 420), isTrue);
    expect(_onScreen(tester, _key('form_bar_7'), 420), isTrue);
    expect(tester.getRect(_key('form_bar_1')).right, lessThanOrEqualTo(0));
    expect(_key('profile_form_bars_hint'), findsOneWidget);
    expect(find.text('Swipe for earlier weeks'), findsOneWidget);
  });

  testWidgets('swiping reveals the earlier weeks, and a tap still picks a week',
      (tester) async {
    final tapped = <int>[];
    await _pump(tester, _bars(12), onTap: tapped.add);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(_onScreen(tester, _key('form_bar_1'), 420), isTrue);
    await tester.tap(_key('form_bar_1'));
    expect(tapped, [1]);
  });

  testWidgets('one scale for the whole season: a big early week sets the height',
      (tester) async {
    // GW1 scored 30, every other week 10: the on-screen GW12 bar is a third
    // of the tallest bar, not full height.
    await _pump(tester, _bars(12, points: (gw) => gw == 1 ? 30 : 10));
    final fill = tester.getSize(_key('form_bar_fill_12')).height;
    expect(fill, closeTo(84 / 3, 0.5));
  });

  for (final brightness in Brightness.values) {
    testWidgets('360 px, 15 weeks: no overflow — $brightness', (tester) async {
      await _pump(tester, _bars(15),
          size: const Size(360, 640), brightness: brightness);
      expect(tester.takeException(), isNull);
      expect(_onScreen(tester, _key('form_bar_15'), 360), isTrue);
    });
  }
}
