// Way back fix round, Important 1: every tap that leads into a registration
// — the list's "My registrations" rows, the home banner, the open rows —
// confirms with the server first (RegistrationService.checkEntry) and
// follows its outcome; a saved copy never opens the status page on its own.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/live_registration_config.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_open.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

const _config = RegistrationConfig(
  targetType: 'league',
  sport: 'Futsal',
  season: '16',
  status: 'closed',
  fee: 60,
  paymentMode: 'perPlayer',
);

void main() {
  late List<String> checked;
  late List<String> opened;

  setUp(() {
    checked = [];
    opened = [];
    RegistrationOpen.statusPageOverride = (regId, config) {
      opened.add('status:$regId:${config.fee}');
      return const Scaffold(body: Text('status page'));
    };
    RegistrationOpen.pathPageOverride = (regId, config) {
      opened.add('path:$regId');
      return const Scaffold(body: Text('path page'));
    };
  });

  tearDown(() {
    RegistrationOpen.checkOverride = null;
    RegistrationOpen.statusPageOverride = null;
    RegistrationOpen.pathPageOverride = null;
  });

  Future<void> tapOpen(
      WidgetTester tester,
      ({RegistrationRoute route, RegistrationConfig? config}) Function()
          answer) async {
    RegistrationOpen.checkOverride = (regId) async {
      checked.add(regId);
      return answer();
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => RegistrationOpen.open(context, 'r1'),
            child: const Text('tap'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
  }

  testWidgets('registered: the status page opens with the SERVER config',
      (tester) async {
    await tapOpen(
        tester, () => (route: RegistrationRoute.status, config: _config));
    expect(checked, ['r1']);
    expect(opened, ['status:r1:60']);
  });

  testWidgets('cannot check: no status page, couldn\'t-check with Try again',
      (tester) async {
    await tapOpen(
        tester, () => (route: RegistrationRoute.couldNotCheck, config: null));
    expect(opened, isEmpty);
    expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(checked, ['r1', 'r1'], reason: 'Try again checks again');
  });

  testWidgets('deleted: the unavailable message', (tester) async {
    await tapOpen(
        tester, () => (route: RegistrationRoute.unavailable, config: null));
    expect(opened, isEmpty);
    expect(find.text(kRegistrationUnavailable), findsOneWidget);
  });

  testWidgets('no submission any more and closed: closed', (tester) async {
    await tapOpen(
        tester, () => (route: RegistrationRoute.closed, config: null));
    expect(opened, isEmpty);
    expect(find.text('Registration is closed'), findsOneWidget);
  });

  testWidgets('no submission, open: the path page', (tester) async {
    await tapOpen(
        tester, () => (route: RegistrationRoute.register, config: _config));
    expect(opened, ['path:r1']);
  });

  // A guard: neither the home banner nor the registration list may build
  // the status page themselves (they must go through RegistrationOpen).
  test('no screen opens the status page without the check', () {
    for (final path in [
      'lib/frontpage.dart',
      'lib/registration/registration_entry_page.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('RegistrationStatusPage('), isFalse,
          reason: '$path must open registrations via RegistrationOpen.open');
    }
  });

  // Final small round, N2: "Try again" goes back through the CALLER's
  // guarded handler (its spinner and one-tap guard), never around it.
  testWidgets('Try again calls the caller\'s retry, not a bare re-check',
      (tester) async {
    var retries = 0;
    RegistrationOpen.checkOverride = (regId) async {
      checked.add(regId);
      return (route: RegistrationRoute.couldNotCheck, config: null);
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                RegistrationOpen.open(context, 'r1', onRetry: () => retries++),
            child: const Text('tap'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(checked, ['r1'], reason: 'the caller runs the retry itself');
  });

  test('every caller wires Try again to its guarded handler', () {
    for (final path in [
      'lib/frontpage.dart',
      'lib/registration/registration_entry_page.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('onRetry:'), isTrue, reason: path);
    }
  });
}
