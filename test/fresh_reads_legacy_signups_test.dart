// Fresh reads, Task 3 — legacy sign-ups (survey list A #7, #8: #54 Sign Up
// Status, #58/#59 isSignedUp, #63 <league> Season, #64 other sign-ups).
// The screens keep today's display when the server cannot be reached; the
// sign-up WRITE re-checks with the server first, so a fan cannot sign up
// for the wrong season number, into a closed sign-up, or twice, on a stale
// saved copy.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

void main() {
  group('legacySignUpAllowed (pure)', () {
    LegacySignUpVerdict verdict({
      Object? status = 1,
      Object? pointer = 15,
      String sport = 'Futsal',
      String season = '16',
      bool already = false,
      bool fromServer = true,
    }) =>
        legacySignUpAllowed(
            status: status,
            seasonPointer: pointer,
            sport: sport,
            season: season,
            alreadySignedUp: already,
            allFromServer: fromServer);

    test('open, right season, not yet signed up: allowed', () {
      expect(verdict(), LegacySignUpVerdict.allowed);
      expect(verdict(status: 2, sport: 'Basketball', pointer: '3', season: '4'),
          LegacySignUpVerdict.allowed);
    });

    test('anything the server did not confirm: could not check', () {
      expect(verdict(fromServer: false), LegacySignUpVerdict.couldNotCheck);
    });

    test('the season moved on (stale "Futsal Season" + 1): refused', () {
      expect(verdict(pointer: 16, season: '16'), LegacySignUpVerdict.changed);
    });

    test('sign-ups closed, or open for another league: refused', () {
      expect(verdict(status: 0), LegacySignUpVerdict.changed);
      expect(verdict(status: 2), LegacySignUpVerdict.changed);
    });

    test('already signed up: refused (no duplicate)', () {
      expect(verdict(already: true), LegacySignUpVerdict.alreadySignedUp);
    });
  });

  group('server-first reads', () {
    late Map<String, FreshValue Function()> answers;

    setUp(() {
      answers = {};
      FreshReads.serverFirstValueOverride = (path) async {
        final a = answers[path];
        if (a == null) throw StateError('unexpected read of $path');
        return a();
      };
    });

    tearDown(() => FreshReads.serverFirstValueOverride = null);

    void fresh(String path, Object? v, {bool fromServer = true}) =>
        answers[path] = () => FreshValue(v, fromServer: fromServer);

    test("isSignedUpUid reads only this fan's two entries, refreshing",
        () async {
      FreshReads.refreshingValueOverride = (path) async => {
            'Sign Ups/Futsal/16/NotPaid/u1': null,
            'Sign Ups/Futsal/16/Paid/u1': 'Sam',
          }[path];
      addTearDown(() => FreshReads.refreshingValueOverride = null);
      expect(await isSignedUpUid('u1', 'Futsal', '16'), isTrue);
    });

    test('checkLegacySignUp: the write is allowed only on server facts',
        () async {
      fresh('Sign Ups/Sign Up Status', 1);
      fresh('Futsal Season', 15);
      fresh('Sign Ups/Futsal/16/NotPaid/u1', null);
      fresh('Sign Ups/Futsal/16/Paid/u1', null);
      expect(await checkLegacySignUp('u1', 'Futsal', '16'),
          LegacySignUpVerdict.allowed);

      fresh('Futsal Season', 15, fromServer: false);
      expect(await checkLegacySignUp('u1', 'Futsal', '16'),
          LegacySignUpVerdict.couldNotCheck);

      answers['Futsal Season'] = () => throw StateError('offline');
      expect(await checkLegacySignUp('u1', 'Futsal', '16'),
          LegacySignUpVerdict.couldNotCheck);
    });

    test('getSignUpStatus: the saved state at once (refreshing), 0 on error',
        () async {
      Object? answer = 2;
      FreshReads.refreshingValueOverride = (path) async {
        expect(path, 'Sign Ups/Sign Up Status');
        if (answer is Error) throw answer as Error;
        return answer;
      };
      addTearDown(() => FreshReads.refreshingValueOverride = null);
      expect(await getSignUpStatus(), 2);
      answer = StateError('offline');
      expect(await getSignUpStatus(), 0);
    });
  });
}
