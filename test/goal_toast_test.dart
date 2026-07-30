import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/goal_toast.dart';

void main() {
  testWidgets('slides in with title + body, then auto-dismisses', (tester) async {
    late BuildContext ctx;
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    GoalToast.show(
      context: ctx,
      title: 'GOAL! Sharks 2 – 1 Falcons',
      body: 'Morgan Clark 37',
      onTap: () => tapped = true,
    );
    await tester.pump(); // insert overlay
    await tester.pump(const Duration(milliseconds: 300)); // slide in
    expect(find.textContaining('GOAL!'), findsOneWidget);
    expect(find.textContaining('Morgan Clark'), findsOneWidget);

    await tester.tap(find.textContaining('GOAL!'));
    await tester.pumpAndSettle();
    expect(tapped, true);
    expect(find.textContaining('GOAL!'), findsNothing); // closed after tap
  });
}
