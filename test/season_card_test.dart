// P2.1 Task A3: modern seasons-list card (lib/leagues.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/leagues.dart';

void main() {
  testWidgets('SeasonCard renders title + chevron and fires onTap',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SeasonCard(
          title: 'Season 16',
          iconAsset: 'assets/FutsalLeague.png',
          onTap: () => taps++,
        ),
      ),
    ));
    expect(find.text('Season 16'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    await tester.tap(find.text('Season 16'));
    expect(taps, 1);
  });
}
