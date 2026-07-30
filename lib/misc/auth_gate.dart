import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// Pure root-widget decision for the auth wall, extracted out of the
/// `authStateChanges()` `StreamBuilder` in `main.dart` so the gate's logic
/// can be unit-tested without standing up real Firebase (mocking `User` is
/// infeasible without adding a mocking dependency; a plain `null` already
/// means "signed out" and is the only value this function inspects).
///
/// A `null` [user] (signed out) always chooses [signedOutHome] — the
/// welcome wall. Any non-null [user] chooses [signedInHome].
Widget chooseRootWidget({
  required User? user,
  required Widget Function() signedInHome,
  required Widget Function() signedOutHome,
}) {
  return user == null ? signedOutHome() : signedInHome();
}
