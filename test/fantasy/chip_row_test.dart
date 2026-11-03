// The chips row on its own (plan 2026-11-03 Task 4): Wildcard and Free Hit
// are playable like Triple Captain / Bench Boost — one chip per week, the
// armed one taps off with no dialog — but ARMING either one asks first (the
// copy is the owner's), a spent chip still can't be armed, and while the team
// is still a first team (nothing to transfer) both sit out under "Your first
// team is free". The copy reads chipSet1EndGw from the live config.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/chip_row.dart';

void main() {
  const wildcardBody =
      'Every transfer this week is free and your new team stays. You can '
      'switch it off until the deadline. You get one Wildcard for Gameweeks '
      '1–6 and one for the rest of the season.';
  const freeHitBody =
      'Every transfer this week is free. After this week\'s games, the team '
      'you have now comes back. You can switch it off until the deadline.';

  /// Pumps the row with the armed chip held in a notifier (the builder's
  /// draft in miniature); every change the row reports lands in [log].
  Future<ValueNotifier<String?>> pumpRow(
    WidgetTester tester, {
    String? active,
    bool enabled = true,
    bool firstTeam = false,
    bool transfersUnknown = false,
    Map<String, ChipAvailability>? availability,
    FantasyConfig? config,
    double width = 420,
    Brightness brightness = Brightness.light,
    List<String?>? log,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final armed = ValueNotifier<String?>(active);
    addTearDown(armed.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: ValueListenableBuilder<String?>(
            valueListenable: armed,
            builder: (_, chip, __) => FantasyChipRow(
              config: config ?? FantasyConfig.futsalDefault(),
              activeChip: chip,
              enabled: enabled,
              firstTeam: firstTeam,
              transfersUnknown: transfersUnknown,
              availability: availability,
              onChipChanged: (id) {
                log?.add(id);
                armed.value = id;
              },
            ),
          ),
        ),
      ),
    ));
    return armed;
  }

  Finder chip(String id) => find.byKey(ValueKey('fantasy_chip_$id'));

  /// The row scrolls sideways (four 132 px cards): bring the chip on screen
  /// first, as a thumb would, then tap it.
  Future<void> tapChip(WidgetTester tester, String id) async {
    await tester.ensureVisible(chip(id));
    await tester.pumpAndSettle();
    await tester.tap(chip(id), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  group('Wildcard', () {
    testWidgets(
        'a tap asks "Play your Wildcard?" with the owner\'s copy; '
        'confirming arms it', (tester) async {
      final log = <String?>[];
      final armed = await pumpRow(tester, log: log);

      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsOneWidget);
      expect(find.text(wildcardBody), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Play Wildcard'), findsOneWidget);
      expect(log, isEmpty, reason: 'nothing is armed before the answer');

      await tester.tap(find.text('Play Wildcard'));
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsNothing);
      expect(log, ['wildcard']);
      expect(armed.value, 'wildcard');
      expect(
          find.byKey(const ValueKey('chip_active_wildcard')), findsOneWidget);
    });

    testWidgets('"Not now" arms nothing', (tester) async {
      final log = <String?>[];
      final armed = await pumpRow(tester, log: log);
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsNothing);
      expect(log, isEmpty);
      expect(armed.value, isNull);
    });

    testWidgets(
        'the body names the live config\'s set 1 end, never a '
        'hard-coded 6', (tester) async {
      final cfg = FantasyConfig.fromMap(
          FantasyConfig.futsalDefault().toMap()..['chipSet1EndGw'] = 4);
      await pumpRow(tester, config: cfg);
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(
          find.text(wildcardBody.replaceFirst('1–6', '1–4')), findsOneWidget);
      expect(find.textContaining('1–6'), findsNothing);
    });

    testWidgets('tapping the armed Wildcard switches it off — no dialog',
        (tester) async {
      final log = <String?>[];
      final armed = await pumpRow(tester, active: 'wildcard', log: log);
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsNothing);
      expect(log, [null]);
      expect(armed.value, isNull);
    });

    testWidgets('arming another chip while one is armed replaces it',
        (tester) async {
      final armed = await pumpRow(tester, active: 'wildcard');
      await tapChip(tester, 'tripleCaptain');
      await tester.pumpAndSettle();
      expect(armed.value, 'tripleCaptain');
      // And Wildcard over Triple Captain asks first.
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsOneWidget);
      await tester.tap(find.text('Play Wildcard'));
      await tester.pumpAndSettle();
      expect(armed.value, 'wildcard');
    });
  });

  group('Free Hit', () {
    testWidgets(
        'a tap asks "Play your Free Hit?" with the owner\'s copy; '
        'confirming arms it', (tester) async {
      final log = <String?>[];
      final armed = await pumpRow(tester, log: log);

      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(find.text('Play your Free Hit?'), findsOneWidget);
      expect(find.text(freeHitBody), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Play Free Hit'), findsOneWidget);
      expect(log, isEmpty);

      await tester.tap(find.text('Play Free Hit'));
      await tester.pumpAndSettle();
      expect(log, ['freeHit']);
      expect(armed.value, 'freeHit');
      expect(find.byKey(const ValueKey('chip_active_freeHit')), findsOneWidget);
    });

    testWidgets(
        '"Not now" arms nothing; the armed Free Hit switches off '
        'with no dialog', (tester) async {
      final armed = await pumpRow(tester);
      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(armed.value, isNull);

      armed.value = 'freeHit';
      await tester.pump();
      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(find.text('Play your Free Hit?'), findsNothing);
      expect(armed.value, isNull);
    });
  });

  testWidgets('Triple Captain and Bench Boost still toggle with no dialog',
      (tester) async {
    final armed = await pumpRow(tester);
    await tapChip(tester, 'tripleCaptain');
    await tester.pumpAndSettle();
    expect(armed.value, 'tripleCaptain');
    await tapChip(tester, 'benchBoost');
    await tester.pumpAndSettle();
    expect(armed.value, 'benchBoost');
    await tapChip(tester, 'benchBoost');
    await tester.pumpAndSettle();
    expect(armed.value, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('no chip carries the old "Coming with transfers" caption',
      (tester) async {
    await pumpRow(tester);
    expect(find.text('Coming with transfers'), findsNothing);
    expect(find.text('Your first team is free'), findsNothing);
  });

  group('a first team has nothing to transfer', () {
    testWidgets(
        'Wildcard and Free Hit are untappable under "Your first team '
        'is free"; the other two are not affected', (tester) async {
      final log = <String?>[];
      await pumpRow(tester, firstTeam: true, log: log);
      expect(find.text('Your first team is free'), findsNWidgets(2));

      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(log, isEmpty);

      await tapChip(tester, 'tripleCaptain');
      await tester.pumpAndSettle();
      expect(log, ['tripleCaptain']);
    });

    testWidgets('an already armed Wildcard can still be switched off',
        (tester) async {
      final armed = await pumpRow(tester, firstTeam: true, active: 'wildcard');
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(armed.value, isNull);
    });

    testWidgets('while not a first team the caption is gone and they tap',
        (tester) async {
      await pumpRow(tester, firstTeam: false);
      expect(find.text('Your first team is free'), findsNothing);
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(find.text('Play your Wildcard?'), findsOneWidget);
    });
  });

  // Error ≠ fact: while the transfer count is unknown the team may be a first
  // team, whose Wildcard / Free Hit the server would spend for nothing — so
  // arming waits ("Checking your transfers…"); disarming never does.
  group('the transfer count is not known yet', () {
    testWidgets(
        'Wildcard and Free Hit cannot be armed, captioned '
        '"Checking your transfers…"; the other two are not affected',
        (tester) async {
      final log = <String?>[];
      await pumpRow(tester, transfersUnknown: true, log: log);
      expect(find.text('Checking your transfers…'), findsNWidgets(2));
      expect(find.text('Your first team is free'), findsNothing);

      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      expect(find.byType(AlertDialog), findsNothing);
      expect(log, isEmpty);

      await tapChip(tester, 'benchBoost');
      expect(log, ['benchBoost']);
    });

    testWidgets('an armed Free Hit can still be switched off', (tester) async {
      final armed =
          await pumpRow(tester, transfersUnknown: true, active: 'freeHit');
      await tapChip(tester, 'freeHit');
      expect(find.byType(AlertDialog), findsNothing);
      expect(armed.value, isNull);
    });

    testWidgets('known again: no caption, and they ask as usual',
        (tester) async {
      await pumpRow(tester, transfersUnknown: false);
      expect(find.text('Checking your transfers…'), findsNothing);
      await tapChip(tester, 'freeHit');
      expect(find.text('Play your Free Hit?'), findsOneWidget);
    });
  });

  group('availability still blocks arming', () {
    const used = {
      'tripleCaptain': ChipAvailability.available,
      'benchBoost': ChipAvailability.available,
      'wildcard': ChipAvailability.used,
      'freeHit': ChipAvailability.used,
    };

    testWidgets(
        'a spent Wildcard / Free Hit cannot be armed: no dialog, '
        'no change', (tester) async {
      final log = <String?>[];
      await pumpRow(tester, availability: used, log: log);
      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('locked: nothing taps, not even Wildcard', (tester) async {
      final log = <String?>[];
      await pumpRow(tester, enabled: false, log: log);
      await tapChip(tester, 'wildcard');
      await tapChip(tester, 'tripleCaptain');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(log, isEmpty);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '360 px: the first-team captions and both dialogs fit, no '
        'overflow — $brightness', (tester) async {
      await pumpRow(tester,
          firstTeam: true, width: 360, brightness: brightness);
      expect(tester.takeException(), isNull);
      expect(find.text('Your first team is free'), findsNWidgets(2));

      await pumpRow(tester,
          transfersUnknown: true, width: 360, brightness: brightness);
      expect(tester.takeException(), isNull);
      expect(find.text('Checking your transfers…'), findsNWidgets(2));

      await pumpRow(tester, width: 360, brightness: brightness);
      await tapChip(tester, 'wildcard');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Play Wildcard'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      await tapChip(tester, 'freeHit');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Play Free Hit'), findsOneWidget);
      for (final finder in [
        find.text('Play your Free Hit?'),
        find.text(freeHitBody),
        find.text('Not now'),
        find.text('Play Free Hit'),
      ]) {
        final r = tester.getRect(finder);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      }
    });
  }
}
