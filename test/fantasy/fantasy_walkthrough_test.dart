// P3a Task 4 — first-open walkthrough: config-driven copy, swipeable cards,
// skippable, and the never-reshow prefs flag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_walkthrough.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();

  testWidgets('four cards walk build-7 → captain → deadline → real games',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyWalkthrough(config: cfg, onDone: () => done++),
      ),
    ));

    // Card 1: build your 7 with the config budget, in plain language —
    // the owner-confusing "from around the league" phrasing stays gone.
    expect(find.text('Build your seven'), findsOneWidget);
    expect(find.textContaining('\$50.0M budget'), findsOneWidget);
    expect(find.textContaining("the league's real players"), findsOneWidget);
    expect(find.textContaining('from around the league'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Captain for double'), findsOneWidget);
    expect(find.textContaining('×2'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Beat the deadline'), findsOneWidget);
    expect(find.textContaining('3:00 PM league time'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Real games, real points'), findsOneWidget);

    // Final card button finishes.
    expect(done, 0);
    await tester.tap(find.text("Let's play"));
    expect(done, 1);
  });

  testWidgets('deadline card renders the lock time from the config, not a '
      'hard-coded 3:00 PM', (tester) async {
    // Owner tunes lockHour to 18 → the card must say 6:00 PM.
    final tuned = FantasyConfig.fromMap(
        FantasyConfig.futsalDefault().toMap()..['lockHour'] = 18);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyWalkthrough(config: tuned, onDone: () {}),
      ),
    ));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Beat the deadline'), findsOneWidget);
    expect(find.textContaining('6:00 PM league time'), findsOneWidget);
    expect(find.textContaining('3:00 PM'), findsNothing);
  });

  testWidgets('Skip finishes immediately from the first card',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyWalkthrough(config: cfg, onDone: () => done++),
      ),
    ));
    await tester.tap(find.text('Skip'));
    expect(done, 1);
  });

  test('prefs flag: unseen by default, sticky once marked', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await FantasyPrefs.hasSeenWalkthrough(), isFalse);
    await FantasyPrefs.markWalkthroughSeen();
    expect(await FantasyPrefs.hasSeenWalkthrough(), isTrue);
  });

  test('prefs flag: already-seen value respected', () async {
    SharedPreferences.setMockInitialValues(
        {FantasyPrefs.walkthroughSeenKey: true});
    expect(await FantasyPrefs.hasSeenWalkthrough(), isTrue);
  });
}
