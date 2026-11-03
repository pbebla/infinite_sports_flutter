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
    double width = 800,
    ThemeData? theme,
  }) async {
    // Tall viewport so the lazy ListView builds every rules section.
    tester.view.physicalSize = Size(width, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = StreamController<FantasyConfigState?>.broadcast();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
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
    // Spec §7 stand-in goalkeeper line under the scoring table.
    expect(
        find.text('Stepping in goal: if an outfield player plays goalkeeper '
            'for a game, his saves, clean sheet and goals conceded count as '
            'a goalkeeper\'s for that game; his goals and assists still '
            'count at his own position.'),
        findsOneWidget);

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

  // Plan 2026-11-03: a first team is free and never banks — the Transfers
  // section says so first, then the usual allowance, all from the live config.
  testWidgets('Transfers: a first team is free, then the config\'s weekly '
      'allowance — and it follows the config', (tester) async {
    final controller = await pumpRules(tester);
    Text transfersBody() => tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Your first team')));

    expect(
        transfersBody().data,
        startsWith('Your first team is free: change it as much as you like '
            'until your first deadline. After that you get 2 free transfers '
            'each gameweek;'));
    // The rest of the old sentence follows, unchanged.
    expect(
        transfersBody().data,
        contains('unused ones bank up to 7. Every transfer beyond your free '
            'ones costs 4 points off that week\'s score.'));

    controller.add(_state(FantasyConfig.futsalDefault().toMap()
      ..['lockOverride'] = 'open'
      ..['freeTransfersPerWeek'] = 3));
    await tester.pump();
    expect(
        transfersBody().data,
        startsWith('Your first team is free: change it as much as you like '
            'until your first deadline. After that you get 3 free transfers '
            'each gameweek;'));

    await controller.close();
    await tester.pumpWidget(const SizedBox());
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

  // FPL selling rule (Task 8): the Rules tab explains that you keep half of
  // any price rise (rounded down to $0.1M) and take the full drop.
  group('Selling section explains the FPL selling rule', () {
    const sellingLines = <String>[
      'You buy at today\'s price. When you sell, you keep half of any rise '
          '(rounded down to \$0.1M) and take the full drop.',
      'Example: bought at \$8.0M, now \$9.0M → sells for \$8.5M. Bought at '
          '\$8.0M, now \$7.0M → sells for \$7.0M.',
      'Changed your mind? Put a player you sold this week back before the '
          'deadline and the sale is undone — he keeps the price you paid and '
          'no transfer is used.',
      'Prices change on Monday morning. If a change puts your saved team '
          'over budget, you\'ll get a message so you can fix it before the '
          'deadline.',
    ];

    testWidgets('shows the Selling copy and drops the old "current price" line',
        (tester) async {
      final controller = await pumpRules(tester);

      // The old promise is gone (it is no longer true).
      expect(find.textContaining('You always buy and sell at the'),
          findsNothing);
      expect(find.textContaining('current price'), findsNothing);

      // The config-driven price range still renders in the Prices section.
      expect(find.textContaining('\$4.0M to \$15.0M'), findsOneWidget);

      // The Selling section, in order, with the exact copy.
      expect(find.text('Selling'), findsOneWidget);
      for (final line in sellingLines) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      // It sits right after the Prices section.
      expect(tester.getTopLeft(find.text('Selling')).dy,
          greaterThan(tester.getTopLeft(find.text('Prices')).dy));

      await controller.close();
      await tester.pumpWidget(const SizedBox());
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits at 360 px wide in ${brightness.name} mode',
          (tester) async {
        final controller = await pumpRules(
          tester,
          width: 360,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color.fromRGBO(208, 0, 0, 1),
              brightness: brightness,
            ),
          ),
        );

        expect(find.text('Selling'), findsOneWidget);
        for (final line in sellingLines) {
          expect(find.text(line), findsOneWidget, reason: line);
        }
        // No RenderFlex / layout overflow anywhere on the page.
        expect(tester.takeException(), isNull);

        await controller.close();
        await tester.pumpWidget(const SizedBox());
      });
    }
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
