// Part D (forced updates): UpdateGate + UpdateRequiredPage, with a fake
// store checker and injected pause streams (no Firebase, no network).
//
// The gate sits ABOVE the Navigator (MaterialApp.builder), exactly as in
// lib/main.dart, so these tests also prove the page needs no Navigator or
// Overlay. It fails open: any error means the fan gets in.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/update/store_update_check.dart';
import 'package:infinite_sports_flutter/update/update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChecker extends StoreUpdateChecker {
  _FakeChecker({this.required = false, this.withStoreButton = false});

  bool required;
  bool throws = false;
  final bool withStoreButton;

  /// When set, check() waits on it (a slow store).
  Completer<UpdateNeed>? pending;

  int checks = 0;
  final List<UpdateNeed> started = [];
  int storeOpens = 0;

  @override
  Future<UpdateNeed> check() async {
    checks++;
    final wait = pending;
    if (wait != null) return wait.future;
    if (throws) throw Exception('store unreachable');
    return UpdateNeed(
        required: required,
        storeUrl: required ? 'https://store.example.test/app' : null);
  }

  @override
  Future<void> startUpdate(UpdateNeed need) async => started.add(need);

  @override
  Future<void> Function()? get openStore =>
      withStoreButton ? () async => storeOpens++ : null;
}

const _installed = '5.0.0+30';
const _home = 'home app';
final _now = DateTime.utc(2026, 11, 16, 12);

void main() {
  late _FakeChecker checker;
  late StreamController<Object?> pause;
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    checker = _FakeChecker();
    pause = StreamController<Object?>.broadcast();
    clock = _now;
  });

  tearDown(() => pause.close());

  Future<void> mount(
    WidgetTester tester, {
    String? cachedBlockedBuild,
    ThemeData? theme,
    Size size = const Size(360, 640),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? lightMode,
      builder: (context, child) => UpdateGate(
        checker: checker,
        installedBuild: _installed,
        cachedBlockedBuild: cachedBlockedBuild,
        pauseStates: pause.stream,
        now: () => clock,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: Text(_home)),
    ));
  }

  Future<void> backToForeground(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  final updateScreen = find.text('Update required');
  final homeApp = find.text(_home);

  testWidgets(
      'required: the Update screen shows and the child is not in '
      'the tree', (tester) async {
    checker.required = true;
    await mount(tester);
    await tester.pumpAndSettle();

    expect(updateScreen, findsOneWidget);
    expect(find.byType(UpdateRequiredPage), findsOneWidget);
    expect(homeApp, findsNothing);
    expect(checker.checks, 1);
  });

  testWidgets('not required: the child shows', (tester) async {
    await mount(tester);
    await tester.pumpAndSettle();

    expect(homeApp, findsOneWidget);
    expect(updateScreen, findsNothing);
    expect(checker.checks, 1);
  });

  testWidgets('the checker throws: the child shows (fails open)',
      (tester) async {
    checker
      ..required = true
      ..throws = true;
    await mount(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(homeApp, findsOneWidget);
    expect(updateScreen, findsNothing);
  });

  testWidgets('the check never delays the first frame', (tester) async {
    checker.pending = Completer<UpdateNeed>();
    await mount(tester);

    expect(homeApp, findsOneWidget);
    checker.pending!.complete(const UpdateNeed(required: true));
    await tester.pumpAndSettle();
    expect(updateScreen, findsOneWidget);
  });

  group('pause switch', () {
    final nowMs = _now.millisecondsSinceEpoch;

    testWidgets(
        'paused while required: the child shows; the pause ends: '
        'the Update screen shows', (tester) async {
      checker.required = true;
      await mount(tester);
      pause
          .add({'PausedUntil': nowMs + const Duration(days: 7).inMilliseconds});
      await tester.pumpAndSettle();

      expect(homeApp, findsOneWidget);
      expect(updateScreen, findsNothing);

      // The Manager turns forced updates back on.
      pause.add(null);
      await tester.pumpAndSettle();
      expect(updateScreen, findsOneWidget);
      expect(homeApp, findsNothing);
    });

    testWidgets(
        'a pause that runs out blocks again on the next foreground '
        'return', (tester) async {
      checker.required = true;
      await mount(tester);
      pause.add(
          {'PausedUntil': nowMs + const Duration(hours: 1).inMilliseconds});
      await tester.pumpAndSettle();
      expect(homeApp, findsOneWidget);

      clock = _now.add(const Duration(hours: 2));
      await backToForeground(tester);
      expect(updateScreen, findsOneWidget);
    });

    testWidgets('a pause stream error counts as not paused', (tester) async {
      checker.required = true;
      await mount(tester);
      pause
          .add({'PausedUntil': nowMs + const Duration(days: 7).inMilliseconds});
      await tester.pumpAndSettle();
      expect(homeApp, findsOneWidget);

      pause.addError(Exception('permission denied'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(updateScreen, findsOneWidget);
    });
  });

  testWidgets('Update calls startUpdate with the latest check', (tester) async {
    checker.required = true;
    await mount(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(checker.started, hasLength(1));
    expect(checker.started.single.required, isTrue);
    expect(checker.started.single.storeUrl, 'https://store.example.test/app');
  });

  testWidgets(
      'Open Google Play shows only when the checker offers it, and '
      'opens the store', (tester) async {
    checker.required = true;
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Open Google Play'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    checker = _FakeChecker(required: true, withStoreButton: true);
    await mount(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Google Play'));
    await tester.pumpAndSettle();
    expect(checker.storeOpens, 1);
    expect(checker.started, isEmpty);
  });

  testWidgets(
      'back to the foreground re-checks; the screen goes away when '
      'an update is no longer required', (tester) async {
    checker.required = true;
    await mount(tester);
    await tester.pumpAndSettle();
    expect(updateScreen, findsOneWidget);

    checker.required = false; // the fan updated / the store changed
    await backToForeground(tester);

    expect(checker.checks, 2);
    expect(updateScreen, findsNothing);
    expect(homeApp, findsOneWidget);
  });

  testWidgets('while blocked every foreground return re-checks',
      (tester) async {
    checker.required = true;
    await mount(tester);
    await tester.pumpAndSettle();

    await backToForeground(tester);
    await backToForeground(tester);
    expect(checker.checks, 3);
  });

  testWidgets('not blocked: at most one check every 30 minutes',
      (tester) async {
    await mount(tester);
    await tester.pumpAndSettle();
    expect(checker.checks, 1);

    clock = _now.add(const Duration(minutes: 10));
    await backToForeground(tester);
    expect(checker.checks, 1);

    clock = _now.add(const Duration(minutes: 31));
    await backToForeground(tester);
    expect(checker.checks, 2);
  });

  group('remembered block', () {
    testWidgets(
        'cachedBlockedBuild == installedBuild: the Update screen is '
        'in the first frame', (tester) async {
      checker.pending = Completer<UpdateNeed>();
      await mount(tester, cachedBlockedBuild: _installed);

      expect(updateScreen, findsOneWidget);
      expect(homeApp, findsNothing);

      // The first check clears it.
      checker.pending!.complete(const UpdateNeed(required: false));
      await tester.pumpAndSettle();
      expect(homeApp, findsOneWidget);
    });

    testWidgets('a different cached build: the child is in the first frame',
        (tester) async {
      checker.pending = Completer<UpdateNeed>();
      await mount(tester, cachedBlockedBuild: '4.9.0+29');

      expect(homeApp, findsOneWidget);
      expect(updateScreen, findsNothing);
      checker.pending!.complete(const UpdateNeed(required: false));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a check that never answers lets a remembered-blocked fan in after '
        'the limit (fails open)', (tester) async {
      checker.pending = Completer<UpdateNeed>(); // never completes
      await mount(tester, cachedBlockedBuild: _installed);
      expect(updateScreen, findsOneWidget);

      await tester.pump(kUpdateCheckLimit + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(homeApp, findsOneWidget);
      expect(updateScreen, findsNothing);
    });

    testWidgets(
        'a required check saves the installed build; a clear check '
        'removes it', (tester) async {
      checker.required = true;
      await mount(tester);
      await tester.pumpAndSettle();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kBlockedBuildPrefKey), _installed);

      checker.required = false;
      await backToForeground(tester);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kBlockedBuildPrefKey), isFalse);
    });

    testWidgets('a failing check also removes it (fails open)', (tester) async {
      SharedPreferences.setMockInitialValues(
          {kBlockedBuildPrefKey: _installed});
      checker.throws = true;
      await mount(tester, cachedBlockedBuild: _installed);
      await tester.pumpAndSettle();

      expect(homeApp, findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kBlockedBuildPrefKey), isFalse);
    });
  });

  for (final dark in [false, true]) {
    testWidgets(
        '360x640 ${dark ? 'dark' : 'light'}, 1.5x text: no overflow, '
        'all the copy, no back or close control', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      checker = _FakeChecker(required: true, withStoreButton: true);
      await mount(tester, theme: dark ? darkMode : lightMode);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Update required'), findsOneWidget);
      expect(
          find.text('A new version of Infinite Sports is ready. '
              'Update to keep using the app.'),
          findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Open Google Play'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget, reason: 'the app logo');

      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(CloseButton), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

      for (final label in ['Update', 'Open Google Play']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.left, greaterThanOrEqualTo(0));
      }
      // The surface follows the theme (light and dark).
      final scheme = (dark ? darkMode : lightMode).colorScheme;
      final surface = tester.widget<Material>(find
          .descendant(
              of: find.byType(UpdateRequiredPage),
              matching: find.byType(Material))
          .first);
      expect(surface.color, scheme.surface);
    });
  }
}
