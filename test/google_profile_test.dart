// Unit tests for the pure Google sign-in helpers
// (lib/onboarding/google_profile.dart). No Firebase involved — these back
// the "new-vs-returning Google user" decision and the display-name split
// used to write the base Users/<uid> profile for brand-new Google sign-ups
// (auth-wall C2 plan), mirroring the Firebase-free pattern already used by
// test/profile_completion_test.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/onboarding/google_profile.dart';

void main() {
  group('splitDisplayName', () {
    test('null returns empty first and last', () {
      final r = splitDisplayName(null);
      expect(r.first, '');
      expect(r.last, '');
    });

    test('empty string returns empty first and last', () {
      final r = splitDisplayName('');
      expect(r.first, '');
      expect(r.last, '');
    });

    test('whitespace-only returns empty first and last', () {
      final r = splitDisplayName('   ');
      expect(r.first, '');
      expect(r.last, '');
    });

    test('a single token becomes the first name only', () {
      final r = splitDisplayName('Cher');
      expect(r.first, 'Cher');
      expect(r.last, '');
    });

    test('two tokens split into first/last', () {
      final r = splitDisplayName('Jane Doe');
      expect(r.first, 'Jane');
      expect(r.last, 'Doe');
    });

    test('three or more tokens: first token is the first name, the rest is '
        'the last name', () {
      final r = splitDisplayName('Mary Jane Watson');
      expect(r.first, 'Mary');
      expect(r.last, 'Jane Watson');
    });

    test('collapses extra internal/leading/trailing whitespace', () {
      final r = splitDisplayName('  Mary   Jane   Watson  ');
      expect(r.first, 'Mary');
      expect(r.last, 'Jane Watson');
    });
  });

  group('isNewSignInUser', () {
    test('true when Firebase flags a new user, even if the node exists', () {
      expect(
        isNewSignInUser(isNewUserFlag: true, usersNodeExists: true),
        isTrue,
      );
    });

    test('true when the node is missing, even if Firebase says not-new', () {
      expect(
        isNewSignInUser(isNewUserFlag: false, usersNodeExists: false),
        isTrue,
      );
    });

    test('true when both signals say new', () {
      expect(
        isNewSignInUser(isNewUserFlag: true, usersNodeExists: false),
        isTrue,
      );
    });

    test('false only when both signals agree the user is returning', () {
      expect(
        isNewSignInUser(isNewUserFlag: false, usersNodeExists: true),
        isFalse,
      );
    });
  });
}
