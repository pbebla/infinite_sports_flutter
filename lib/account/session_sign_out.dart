// The ONE sign-out the app uses: Firebase + Google sign-out, then every
// per-user session cache forgotten, so nothing one person looked at survives
// into the next person's session on a shared phone.
//
// Used by the drawer's Logout (navbar.dart), the "accounts were combined"
// notice (merged_account_notice.dart), account deletion
// (delete_account_flow.dart) and the under-13 exit (about_you_page.dart) —
// add a new cache to clear HERE, not at a call site.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_session.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

/// Signs out of Firebase (and Google), then clears the session caches.
///
/// Signing out flips `authStateChanges()`, which swaps [AuthGate]'s content
/// to the welcome wall; callers that have a dialog open must pop it BEFORE
/// calling this (the swap can dispose the dialog's ancestors).
///
/// There is no auto-sign-in preference to clear: a persisted Firebase session
/// is the only auto sign-in, and `signOut()` ends it.
///
/// First (while the write is still authorised) this phone is detached from
/// the account's personal pushes: `Users/<uid>/Token` is removed if it holds
/// this phone's token, so the next person to sign in here does not receive
/// the previous person's support replies or reminders. That step is bounded
/// to [kTokenDetachTimeout] and can never fail or block the sign-out (every
/// caller has already popped its pages). [detachToken] and
/// [firebaseSignOut] are test seams.
Future<void> signOutAndClearSession({
  Future<void> Function()? detachToken,
  Future<void> Function()? firebaseSignOut,
}) async {
  try {
    await (detachToken ?? _detachThisDeviceToken)()
        .timeout(kTokenDetachTimeout);
  } catch (_) {
    // Offline / slow / already-deleted account: sign out regardless.
  }
  await (firebaseSignOut ?? auth.signOut)();
  ProfilePage.clearCareerCache();
  LeagueService.clearRostersSnapshotCache();
  // Every fantasy session cache (shared-phone hygiene): one call, so no
  // screen's cache can be forgotten here.
  clearFantasySessionState();
  signedIn = false;
}

Future<void> _detachThisDeviceToken() async {
  await removeUserTokenIfThisDevice(currentSignedInUid());
}
