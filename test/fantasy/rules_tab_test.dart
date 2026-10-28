// P3a Task 3 — the Rules tab renders from the LIVE config (spec §10a):
// real values from the streamed FantasyConfig, and a config change
// re-renders the page (proved with a fake stream).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rules_tab.dart';

FantasyConfigState _state(Map<String, dynamic> configMap) =>
    configStateFromNode(configMap)!;

void main() {
  final defaultMap = FantasyConfig.futsalDefault().toMap()
    ..['lockOverride'] = 'open';

  Future<StreamController<FantasyConfigState?>> pumpRules(
    WidgetTester tester, {
    List<Gameweek> gameweeks = const [],
    Widget Function()? supportPageBuilder,
  }) async {
    // Tall viewport so the lazy ListView builds every rules section.
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = StreamController<FantasyConfigState?>.broadcast();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyRulesTab(
          configStates: controller.stream,
          initialState: _state(defaultMap),
          gameweeks: gameweeks,
          nowUtc: () => DateTime.utc(2026, 7, 3, 12),
          supportPageBuilder: supportPageBuilder,
        ),
      ),
    ));
    return controller;
  }

  testWidgets('renders the real config values, never hard-coded text',
      (tester) async {
    final controller = await pumpRules(tester);

    // How to play from config: budget + formation + captain multiplier.
    expect(find.textContaining('\$50.0M budget'), findsOneWidget);
    expect(find.textContaining('×2'), findsWidgets);

    // Scoring table: GK goal +10 (unique value in the table).
    expect(find.text('+10'), findsOneWidget);
    // DPL threshold cells render as "5+ → +2" / "7+ → +2".
    expect(find.text('5+ → +2'), findsOneWidget);
    expect(find.text('7+ → +2'), findsOneWidget);

    // BPS published weights.
    expect(find.text('Goal +12'), findsOneWidget);
    expect(find.text('Red −9'), findsOneWidget);

    // Deadlines: lock hour -> 3:00 PM league time.
    expect(find.textContaining('3:00 PM league time'), findsOneWidget);

    // Transfers worked example uses the engine's own math (1 extra = −4).
    expect(find.textContaining('making 3 costs −4 points'),
        findsOneWidget);
    expect(find.textContaining('making 4 costs −8'), findsOneWidget);

    // Prices from config.
    expect(find.textContaining('\$4.0M to \$15.0M'), findsOneWidget);

    // Chips, eligibility, FAQ present — with the set windows rendered from
    // the config (chipSet1EndGw = 6 → GW1–6 / GW7, P3b Task 6).
    expect(find.text('Triple Captain'), findsOneWidget);
    expect(find.text('Free Hit'), findsOneWidget);
    expect(find.textContaining('Set 1 covers GW1–6'), findsOneWidget);
    expect(find.textContaining('Set 2 covers GW7'), findsOneWidget);
    expect(find.text('Eligibility'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);

    await controller.close();
    await tester.pumpWidget(const SizedBox()); // dispose chip timer
  });

  testWidgets('a changed config re-renders the page from the stream',
      (tester) async {
    final controller = await pumpRules(tester);
    expect(find.text('+10'), findsOneWidget); // GK goal, default

    // The owner tunes GK goal to 99, the budget to $60.0M and the chip-set
    // split to GW8.
    final tuned = FantasyConfig.futsalDefault().toMap()
      ..['lockOverride'] = 'open'
      ..['budgetTenths'] = 600
      ..['chipSet1EndGw'] = 8;
    (tuned['scoring'] as Map)['GK'] =
        Map<String, dynamic>.from((tuned['scoring'] as Map)['GK'] as Map)
          ..['goal'] = 99;
    controller.add(_state(tuned));
    await tester.pump();

    expect(find.text('+99'), findsOneWidget);
    expect(find.text('+10'), findsNothing);
    expect(find.textContaining('\$60.0M budget'), findsOneWidget);
    expect(find.textContaining('\$50.0M budget'), findsNothing);
    expect(find.textContaining('Set 1 covers GW1–8'), findsOneWidget);
    expect(find.textContaining('Set 2 covers GW9'), findsOneWidget);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('feedback card at the bottom opens the support form',
      (tester) async {
    final controller = await pumpRules(
      tester,
      supportPageBuilder: () =>
          const Scaffold(body: Center(child: Text('stub support form'))),
    );

    expect(find.text('Spotted an issue or have feedback? Tell us'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fantasy_rules_feedback')));
    await tester.pumpAndSettle();
    expect(find.text('stub support form'), findsOneWidget);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deadline chip on the page shows the live countdown',
      (tester) async {
    final cfg = FantasyConfig.futsalDefault();
    final controller = await pumpRules(
      tester,
      gameweeks: deriveGameweeks(['07052026'], cfg),
    );
    // lockOverride=open in the test-bed config → the override face shows.
    expect(find.text('Editing open'), findsOneWidget);

    // Production config (auto) → countdown + absolute league time.
    controller.add(_state(FantasyConfig.futsalDefault().toMap()));
    await tester.pump();
    expect(find.text('GW1 locks in 2d 10h'), findsOneWidget);
    expect(find.text('Sun, Jul 5 · 3:00 PM'), findsOneWidget);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });
}
