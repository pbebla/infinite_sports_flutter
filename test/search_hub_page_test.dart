// Widget tests for the Search hub's "Infinite Insiders" card (Task F6).
// Firebase-free: `insidersLeaderboardPageBuilder` is a test seam (mirrors
// insiders_info_page.dart's `dashboardPageBuilder`) so this test never
// constructs the real InsidersLeaderboardPage — which, unwrapped, reaches
// for InsiderService's live Firebase streams in its own default wiring.
//
// SearchHubPage's hub view (`_hub()`) renders unconditionally on the empty
// query, regardless of the FutureBuilder's search-index snapshot state, so
// no Firebase mocking is needed to see it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/search_hub_page.dart';

void main() {
  testWidgets('the hub shows an Infinite Insiders card alongside Around You',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchHubPage()));
    await tester.pump();

    expect(find.text('Around You'), findsOneWidget);
    expect(find.text('Infinite Insiders'), findsOneWidget);
  });

  testWidgets('tapping the Infinite Insiders card pushes the leaderboard page',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SearchHubPage(
        insidersLeaderboardPageBuilder: () =>
            const Scaffold(body: Center(child: Text('stub leaderboard'))),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Infinite Insiders'));
    await tester.pumpAndSettle();

    expect(find.text('stub leaderboard'), findsOneWidget);
  });
}
