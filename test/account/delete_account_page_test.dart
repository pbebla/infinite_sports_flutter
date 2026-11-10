// Widget tests for the Delete account page (account deletion, design D3).
// Firebase-free: the page takes `reauth`, `callDelete` and `onDeleted`
// closures (lib/account/delete_account_flow.dart supplies the real ones),
// the same seam pattern as `writeOverride` on About You.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/account/delete_account_flow.dart';
import 'package:infinite_sports_flutter/account/delete_account_page.dart';
import 'package:infinite_sports_flutter/account/password_reauth_dialog.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart';

const _field = ValueKey('delete_account_confirm_field');
const _button = ValueKey('delete_account_button');

Finder get _buttonFinder => find.byKey(_button);

bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_buttonFinder).onPressed != null;

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function() reauth,
  required Future<void> Function() callDelete,
  Future<void> Function()? onDeleted,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: DeleteAccountPage(
      reauth: (_) => reauth(),
      callDelete: callDelete,
      onDeleted: (_) => (onDeleted ?? () async {})(),
    ),
  ));
}

Future<void> _typeAndTap(WidgetTester tester, [String text = 'DELETE']) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pump();
  await tester.ensureVisible(_buttonFinder);
  await tester.pump();
  await tester.tap(_buttonFinder);
  await tester.pump();
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('shows what is deleted and what is kept, and the confirm field',
      (tester) async {
    await _pump(tester, reauth: () async {}, callDelete: () async {});
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('What is deleted'), findsOneWidget);
    expect(find.text('What is kept'), findsOneWidget);
    expect(find.text('Type DELETE to confirm'), findsOneWidget);
    expect(find.text('Delete my account'), findsOneWidget);
  });

  testWidgets('button is enabled only when the trimmed text is exactly DELETE',
      (tester) async {
    await _pump(tester, reauth: () async {}, callDelete: () async {});
    expect(_enabled(tester), isFalse);

    for (final wrong in ['delete', 'Delete', 'DELET', 'DELETE!', '']) {
      await tester.enterText(find.byKey(_field), wrong);
      await tester.pump();
      expect(_enabled(tester), isFalse, reason: '"$wrong" must not enable');
    }
    for (final right in ['DELETE', 'DELETE ', '  DELETE']) {
      await tester.enterText(find.byKey(_field), right);
      await tester.pump();
      expect(_enabled(tester), isTrue, reason: '"$right" must enable');
    }
  });

  testWidgets('tapping runs reauth, then callDelete, then onDeleted once',
      (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      reauth: () async => calls.add('reauth'),
      callDelete: () async => calls.add('delete'),
      onDeleted: () async => calls.add('deleted'),
    );
    await _typeAndTap(tester);
    // Success keeps the spinner (the real onDeleted leaves the page), so
    // never settles: run the pending futures instead.
    await _flush(tester);
    expect(calls, ['reauth', 'delete', 'deleted']);
  });

  testWidgets('recent-login-required once: re-auths again and retries',
      (tester) async {
    final calls = <String>[];
    var deleteCalls = 0;
    await _pump(
      tester,
      reauth: () async => calls.add('reauth'),
      callDelete: () async {
        calls.add('delete');
        deleteCalls++;
        if (deleteCalls == 1) {
          throw const DeleteAccountError(DeleteAccountError.recentLogin);
        }
      },
      onDeleted: () async => calls.add('deleted'),
    );
    await _typeAndTap(tester);
    // Success keeps the spinner (the real onDeleted leaves the page), so
    // never settles: run the pending futures instead.
    await _flush(tester);
    expect(calls, ['reauth', 'delete', 'reauth', 'delete', 'deleted']);
  });

  testWidgets('recent-login-required twice: stops and shows the generic error',
      (tester) async {
    var reauths = 0;
    var deleted = 0;
    await _pump(
      tester,
      reauth: () async => reauths++,
      callDelete: () async =>
          throw const DeleteAccountError(DeleteAccountError.recentLogin),
      onDeleted: () async => deleted++,
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(reauths, 2);
    expect(deleted, 0);
    expect(find.textContaining('Something went wrong'), findsOneWidget);
  });

  testWidgets('already-merged shows the kept account hint', (tester) async {
    await _pump(
      tester,
      reauth: () async {},
      callDelete: () async => throw const DeleteAccountError(
          DeleteAccountError.alreadyMerged,
          keepHint: 'k***@example.com'),
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('This account was combined into another one. Sign in with '
          'k***@example.com and delete that account instead.'),
      findsOneWidget,
    );
  });

  testWidgets('deletion-incomplete shows the try-again message',
      (tester) async {
    var deleted = 0;
    await _pump(
      tester,
      reauth: () async {},
      callDelete: () async =>
          throw const DeleteAccountError(DeleteAccountError.incomplete),
      onDeleted: () async => deleted++,
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Some data could not be removed. Please try again; if it '
          'keeps failing, email contact@infinitesports.org.'),
      findsOneWidget,
    );
    expect(deleted, 0);
    // Back to idle: the button can be tapped again (the server is idempotent).
    expect(_enabled(tester), isTrue);
  });

  testWidgets('a cancelled re-auth returns to idle with no message',
      (tester) async {
    var deleteCalls = 0;
    await _pump(
      tester,
      reauth: () async => throw const ReauthCancelled(),
      callDelete: () async => deleteCalls++,
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);
    expect(find.textContaining('Something went wrong'), findsNothing);
    expect(find.textContaining('contact@infinitesports.org'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_enabled(tester), isTrue);
  });

  testWidgets(
      'a failed re-auth or unknown error shows the generic message and never '
      'raw exception text', (tester) async {
    await _pump(
      tester,
      reauth: () async => throw Exception('uid-abc123 raw boom'),
      callDelete: () async {},
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Something went wrong. Please try again or email '
          'contact@infinitesports.org.'),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('uid-abc123'), findsNothing);
  });

  testWidgets('a wrong Google account shows the same-account message, idle',
      (tester) async {
    var deleteCalls = 0;
    await _pump(
      tester,
      reauth: () async => throw const ReauthFailed(
          reason: ReauthFailureReason.googleAccountMismatch),
      callDelete: () async => deleteCalls++,
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);
    expect(
      find.text('Please choose the same Google account you signed in with.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_enabled(tester), isTrue);
  });

  testWidgets('any other ReauthFailed shows the generic message',
      (tester) async {
    await _pump(
      tester,
      reauth: () async => throw const ReauthFailed(),
      callDelete: () async {},
    );
    await _typeAndTap(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(_enabled(tester), isTrue);
  });

  test('Apple re-auth credential carries the identity token only', () {
    final credential = appleReauthCredential('id-token-1');
    expect(credential.providerId, 'apple.com');
    expect(credential.idToken, 'id-token-1');
    expect(credential.accessToken, isNull);
  });

  testWidgets('busy: spinner shows and a second tap does nothing',
      (tester) async {
    final gate = Completer<void>();
    var reauths = 0;
    var deletes = 0;
    var deleted = 0;
    await _pump(
      tester,
      reauth: () async => reauths++,
      callDelete: () async {
        deletes++;
        await gate.future;
      },
      onDeleted: () async => deleted++,
    );
    await _typeAndTap(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_enabled(tester), isFalse);
    await tester.tap(_buttonFinder, warnIfMissed: false);
    await tester.pump();
    expect(reauths, 1);
    expect(deletes, 1);

    gate.complete();
    // Success keeps the spinner (the real onDeleted leaves the page), so
    // never settles: run the pending futures instead.
    await _flush(tester);
    expect(deleted, 1);
  });

  testWidgets('fits a 360 px wide screen in light and dark themes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await _pump(
        tester,
        reauth: () async {},
        callDelete: () async =>
            throw const DeleteAccountError(DeleteAccountError.incomplete),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFD00000), brightness: brightness),
        ),
      );
      await _typeAndTap(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scheme = Theme.of(tester.element(_buttonFinder)).colorScheme;
      final style = tester.widget<FilledButton>(_buttonFinder).style!;
      expect(style.backgroundColor!.resolve(<WidgetState>{}), scheme.error);
    }
  });

  group('deleteAccountErrorFrom', () {
    FirebaseFunctionsException ex(String code, Object? details) =>
        FirebaseFunctionsException(message: 'x', code: code, details: details);

    test('maps every server code', () {
      expect(
        deleteAccountErrorFrom(
            ex('failed-precondition', {'code': 'recent-login-required'})).code,
        DeleteAccountError.recentLogin,
      );
      final merged = deleteAccountErrorFrom(ex('failed-precondition',
          {'code': 'already-merged', 'keepHint': 'k***@example.com'}));
      expect(merged.code, DeleteAccountError.alreadyMerged);
      expect(merged.keepHint, 'k***@example.com');
      expect(
        deleteAccountErrorFrom(ex('internal', {'code': 'deletion-incomplete'}))
            .code,
        DeleteAccountError.incomplete,
      );
      expect(deleteAccountErrorFrom(ex('unauthenticated', {'code': 'x'})).code,
          DeleteAccountError.other);
      expect(deleteAccountErrorFrom(ex('internal', null)).code,
          DeleteAccountError.other);
    });

    test('already-merged without a hint falls back to the generic message', () {
      expect(
        deleteAccountErrorFrom(
            ex('failed-precondition', {'code': 'already-merged'})).code,
        DeleteAccountError.other,
      );
    });
  });

  group('PasswordReauthDialog', () {
    Future<List<String?>> open(WidgetTester tester, {String? errorText}) async {
      final results = <String?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await showDialog<String>(
              context: context,
              builder: (_) => PasswordReauthDialog(errorText: errorText),
            )),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('obscured field; Continue returns the typed password',
        (tester) async {
      final results = await open(tester);
      final field = tester.widget<TextField>(
          find.byKey(const ValueKey('reauth_password_field')));
      expect(field.obscureText, isTrue);
      await tester.enterText(
          find.byKey(const ValueKey('reauth_password_field')), 'pw-123');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(results, ['pw-123']);
    });

    testWidgets('shows Wrong password and Cancel returns null', (tester) async {
      final results = await open(tester, errorText: 'Wrong password');
      expect(find.text('Wrong password'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
