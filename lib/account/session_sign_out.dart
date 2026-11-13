// The ONE sign-out the app uses: Firebase + Google sign-out, then every
// per-user session cache forgotten, so nothing one person looked at survives
// into the next person's session on a shared phone.
//
// Used by the drawer's Logout (navbar.dart) and by the "accounts were
// combined" notice (merged_account_notice.dart) — add a new cache to clear
// HERE, not at either call site.

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
Future<void> signOutAndClearSession() async {
  await auth.signOut();
  ProfilePage.clearCareerCache();
  LeagueService.clearRostersSnapshotCache();
  // Every fantasy session cache (shared-phone hygiene): one call, so no
  // screen's cache can be forgotten here.
  clearFantasySessionState();
  signedIn = false;
}
