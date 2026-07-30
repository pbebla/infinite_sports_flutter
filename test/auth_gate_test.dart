// Unit tests for the auth-wall's pure routing decision
// (lib/misc/auth_gate.dart), extracted out of the `authStateChanges()`
// StreamBuilder in main.dart specifically so it's testable without standing
// up real Firebase or a mocking package (no new dependencies allowed).
//
// `User` from firebase_auth is a big abstract interface we can't easily
// construct for the "signed in" case, so `_FakeUser` below overrides
// `noSuchMethod` — a well-known no-dependency fake pattern. The function
// under test never calls any member on it; it only checks `== null`.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/misc/auth_gate.dart';

class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a null user (signed out) chooses the signed-out (welcome) branch', () {
    final result = chooseRootWidget(
      user: null,
      signedInHome: () => const Text('home'),
      signedOutHome: () => const Text('wall'),
    );

    expect((result as Text).data, 'wall');
  });

  test('a non-null user (signed in) chooses the signed-in (home) branch', () {
    final result = chooseRootWidget(
      user: _FakeUser(),
      signedInHome: () => const Text('home'),
      signedOutHome: () => const Text('wall'),
    );

    expect((result as Text).data, 'home');
  });
}
