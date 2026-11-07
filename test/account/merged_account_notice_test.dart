// The "your accounts were combined" notice (Merge Duplicate Player Accounts,
// design D9): anyone still signed in on an account that was merged into
// another sees ONE plain dialog telling them which email to use, then is
// signed out. Pure copy first, then the watcher widget against test streams
// (no Firebase): once only, OK signs out, light + dark, 360 px.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/account/merged_account_notice.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';

const _title = 'Your accounts were combined';
const _hint = 'ca••••••••@gmail.com';
const _bodyWithHint =
    'All your seasons are now on your Infinite Sports account for '
    '$_hint. Please sign in with that email.';
const _bodyNoHint =
    'All your seasons are now on your other Infinite Sports account. '
    'Please sign in with your other email.';

Map<String, Object?> _merged({Object? hint = _hint}) =>
    {'MergedInto': 'keptUid', 'MergedHint': hint};

void main() {
  group('mergedNoticeFor', () {
    test('merged with a hint: D9 title and body name the hidden email', () {
      final notice = mergedNoticeFor('keptUid', _hint);
      expect(notice, isNotNull);
      expect(notice!.title, _title);
      expect(notice.body, _bodyWithHint);
    });

    test('merged without a hint: points at "your other email"', () {
      for (final hint in <Object?>[null, '', '   ', 7, true, <String>[]]) {
        final notice = mergedNoticeFor('keptUid', hint);
        expect(notice, isNotNull, reason: 'hint: $hint');
        expect(notice!.title, _title);
        expect(notice.body, _bodyNoHint, reason: 'hint: $hint');
      }
    });

    test('not merged: empty, missing or non-string MergedInto is null', () {
      for (final into in <Object?>[
        null,
        '',
        7,
        true,
        <String, Object?>{'a': 1},
        <String>['k'],
      ]) {
        expect(mergedNoticeFor(into, _hint), isNull, reason: 'into: $into');
      }
    });
  });

  group('combineMergedLeaves', () {
    late StreamController<Object?> into;
    late StreamController<Object?> hint;
    late List<Map<String, Object?>> seen;
    late StreamSubscription<Map<String, Object?>> sub;

    // Subscribed INSIDE each testWidgets body: the combiner's settle Timer
    // must be created in the test's fake-time zone for tester.pump to move it.
    void start() {
      into = StreamController<Object?>();
      hint = StreamController<Object?>();
      seen = [];
      sub = combineMergedLeaves(into.stream, hint.stream).listen(seen.add);
      addTearDown(() async {
        await sub.cancel();
        await into.close();
        await hint.close();
      });
    }

    testWidgets('waits for both leaves, then settles on the latest pair',
        (tester) async {
      start();
      into.add('keptUid');
      await tester.pump(const Duration(seconds: 1));
      expect(seen, isEmpty, reason: 'the hint leaf has not reported yet');

      hint.add(null);
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, isEmpty, reason: 'still settling');

      // The hint lands inside the settle window: one emission, with it.
      hint.add(_hint);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen, [
        {'MergedInto': 'keptUid', 'MergedHint': _hint},
      ]);
    });

    testWidgets('a leaf that errors counts as empty, never blocks the other',
        (tester) async {
      start();
      into.add('keptUid');
      hint.addError(StateError('denied'));
      await tester.pump(const Duration(seconds: 1));
      expect(seen, [
        {'MergedInto': 'keptUid', 'MergedHint': null},
      ]);
    });
  });

  group('MergedAccountWatcher', () {
    late StreamController<Map<String, Object?>> states;
    late int signOutCalls;

    setUp(() {
      states = StreamController<Map<String, Object?>>();
      signOutCalls = 0;
    });
    tearDown(() => states.close());

    Future<void> mount(
      WidgetTester tester, {
      ThemeData? theme,
      Future<void> Function()? onSignOut,
      Size size = const Size(360, 640),
      double textScale = 1.0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: theme ?? lightMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MergedAccountWatcher(
          states: states.stream,
          onSignOut: onSignOut ?? () async => signOutCalls++,
          child: const Scaffold(body: Text('home')),
        ),
      ));
    }

    testWidgets('a merged state shows the dialog once, second emission does '
        'not stack another', (tester) async {
      await mount(tester);
      expect(find.text(_title), findsNothing);

      states.add(_merged());
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_bodyWithHint), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      states.add(_merged());
      states.add(_merged(hint: 'zz••@other.com'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      // The dialog that is up keeps the copy it opened with.
      expect(find.text(_bodyWithHint), findsOneWidget);
    });

    testWidgets('no hint shows the "other email" body', (tester) async {
      await mount(tester);
      states.add({'MergedInto': 'keptUid'});
      await tester.pumpAndSettle();
      expect(find.text(_bodyNoHint), findsOneWidget);
    });

    testWidgets('OK signs out exactly once and closes the dialog',
        (tester) async {
      await mount(tester);
      states.add(_merged());
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(signOutCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);

      // More emissions after OK never re-open it or sign out again.
      states.add(_merged());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(signOutCalls, 1);
    });

    testWidgets('the dialog cannot be dismissed by tapping outside or back',
        (tester) async {
      await mount(tester);
      states.add(_merged());
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(signOutCalls, 0);
    });

    testWidgets('a sign-out that fails brings the notice back', (tester) async {
      var attempts = 0;
      await mount(tester, onSignOut: () async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
      });
      states.add(_merged());
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('not-merged states show nothing', (tester) async {
      await mount(tester);
      states.add({'MergedInto': null, 'MergedHint': null});
      states.add({'MergedInto': '', 'MergedHint': _hint});
      states.add(<String, Object?>{});
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(signOutCalls, 0);
    });

    testWidgets('leaving the tree cancels the live subscription',
        (tester) async {
      await mount(tester);
      expect(states.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(states.hasListener, isFalse);
    });

    testWidgets('a state that turns merged later still shows the dialog',
        (tester) async {
      await mount(tester);
      states.add({'MergedInto': null, 'MergedHint': null});
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      states.add(_merged());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('360x640 ${dark ? 'dark' : 'light'}: no overflow, readable '
          'copy, 1.5x text and a long email too', (tester) async {
        await mount(
          tester,
          theme: dark ? darkMode : lightMode,
          textScale: 1.5,
        );
        states.add(_merged(
          hint: 'ab••••••••'
              '@a-very-long-email-domain-name.example.co.uk',
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
        // Title + body take their colors from the theme, never a fixed
        // light-mode palette: in dark mode neither may be near-black.
        final scheme = (dark ? darkMode : lightMode).colorScheme;
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.backgroundColor, isNull,
            reason: 'dialog surface comes from the theme');
        final body = tester.widget<Text>(find.textContaining('Please sign in'));
        expect(body.style?.color, anyOf(isNull, scheme.onSurface, scheme.onSurfaceVariant));
        final okRect = tester.getRect(find.text('OK'));
        expect(okRect.right, lessThanOrEqualTo(360));
        expect(okRect.bottom, lessThanOrEqualTo(640));
      });
    }
  });
}
