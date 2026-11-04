// Live everywhere, Task 5 — the shared LIVE pill (a red dot + "LIVE"): the
// bright fantasy "down" red in both themes, a 1.2 s pulse on the dot, static
// under reduced motion (and then it schedules nothing, so pumpAndSettle
// returns).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';

void main() {
  Future<void> pumpPill(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool reduceMotion = false,
    double? width,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: width == null
                  ? const FantasyLivePill()
                  : SizedBox(width: width, child: const FantasyLivePill()),
            ),
          ),
        ),
      ),
    ));
  }

  double dotOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find.byKey(const ValueKey('live_pill_dot')))
      .opacity
      .value;

  Color dotColor(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(find.descendant(
        of: find.byKey(const ValueKey('live_pill_dot')),
        matching: find.byType(DecoratedBox)));
    return (box.decoration as BoxDecoration).color!;
  }

  testWidgets('a red dot and the word LIVE', (tester) async {
    await pumpPill(tester);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byKey(const ValueKey('live_pill_dot')), findsOneWidget);
    // Read as "Live" (the dot and the caps are not read letter by letter).
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Live'),
        findsOneWidget);
  });

  testWidgets('the bright down red in both themes (never the soft M3 error)',
      (tester) async {
    await pumpPill(tester, brightness: Brightness.light);
    expect(dotColor(tester), const Color(0xFFD32F2F));
    expect(tester.widget<Text>(find.text('LIVE')).style!.color,
        const Color(0xFFD32F2F));

    await pumpPill(tester, brightness: Brightness.dark);
    await tester
        .pump(const Duration(milliseconds: 400)); // the theme cross-fade
    expect(dotColor(tester), const Color(0xFFFF5252));
    expect(tester.widget<Text>(find.text('LIVE')).style!.color,
        const Color(0xFFFF5252));
  });

  testWidgets('the dot pulses with a 1.2 s period', (tester) async {
    await pumpPill(tester);
    final start = dotOpacity(tester);
    expect(start, 1.0);

    await tester.pump(const Duration(milliseconds: 600));
    final trough = dotOpacity(tester);
    expect(trough, lessThan(0.5), reason: 'half a period: faded');

    await tester.pump(const Duration(milliseconds: 600));
    expect(dotOpacity(tester), closeTo(start, 0.02),
        reason: 'a full 1.2 s period is back where it started');
  });

  testWidgets('reduced motion: the dot is static and nothing is scheduled',
      (tester) async {
    await pumpPill(tester, reduceMotion: true);
    expect(dotOpacity(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(dotOpacity(tester), 1.0);
    // pumpAndSettle only returns when no animation keeps scheduling frames.
    await tester.pumpAndSettle();
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('switching to reduced motion stops the pulse', (tester) async {
    await pumpPill(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(dotOpacity(tester), lessThan(0.5));
    await pumpPill(tester, reduceMotion: true);
    await tester.pumpAndSettle();
    expect(dotOpacity(tester), 1.0);
  });

  testWidgets('compact: about 70 px wide and 20 px tall, no overflow',
      (tester) async {
    await pumpPill(tester);
    final size = tester.getSize(find.byType(FantasyLivePill));
    expect(size.width, lessThan(80));
    expect(size.height, lessThan(24));
    expect(tester.takeException(), isNull);
  });
}
