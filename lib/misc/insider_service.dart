import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/stream_resilience.dart';
import 'package:infinite_sports_flutter/model/insider.dart';

/// Live reads + the application write for the Infinite Insiders program
/// (Task F2). Mirrors the static-method service style of
/// lib/registration/registration_service.dart.
class InsiderService {
  static DatabaseReference _ref(String uid) =>
      FirebaseDatabase.instance.ref('Insiders/$uid');

  /// Live view of the signed-in fan's own `/Insiders/<uid>` node — null while
  /// no application has ever been submitted. Drives the drawer row's
  /// subtitle/icon and the info page's per-state body in real time (a
  /// Manager approval/decline flips this stream while the info page is
  /// open — spec §7).
  static Stream<Insider?> watchMyInsider(String uid) => _ref(uid)
      .onValue
      .map((event) => Insider.fromFirebase(uid, event.snapshot.value));

  /// Submits (or re-submits) an Insider application. Writes ONLY when the
  /// node is absent or the prior application was declined — an
  /// already-pending, active, or suspended Insider is never clobbered by a
  /// re-tap of "Accept & Apply" (spec §7, owner "once-per-person" guard
  /// amendment applied to re-applying, not just referral crediting).
  ///
  /// SportsOfInterest was removed 2026-07-27 (owner decision): Insiders can
  /// refer anyone for any sport, so the question carried no signal.
  static Future<void> apply({
    required String uid,
    required String name,
    required String email,
  }) async {
    final nodeRef = _ref(uid);
    final snapshot = (await nodeRef.once()).snapshot;
    final existing = Insider.fromFirebase(uid, snapshot.value);
    if (existing != null && !existing.isDeclined) return;

    await nodeRef.set({
      'Name': name,
      'Email': email,
      'Status': 'pending',
      'AppliedAt': ServerValue.timestamp,
    });
  }

  // -- Registration promo-code entry (Infinite Insiders P2, Task F3) ----
  // One-shot lookups InsiderPromoCodeField needs to run the evaluateCode
  // chain (lib/registration/promo_engine.dart) against a freshly typed
  // code — these are NOT streams (the field validates on blur/change, not
  // continuously) and are deliberately separate O(1) single-field reads
  // rather than one big Insider fetch, matching /InsiderCodes' spec §9
  // "O(1) validation lookup" intent.

  /// The uid owning [code] (normalized uppercase before lookup), or null
  /// when the code is blank/unclaimed/on error — evaluateCode's `invalid`
  /// branch for either case.
  static Future<String?> lookupCode(String code) async {
    final normalized = normalizeInsiderCode(code);
    if (normalized.isEmpty) return null;
    try {
      final snap = (await FirebaseDatabase.instance
              .ref('InsiderCodes/$normalized')
              .once())
          .snapshot;
      final uid = snap.value;
      return (uid is String && uid.isNotEmpty) ? uid : null;
    } catch (_) {
      return null;
    }
  }

  /// Just the Status field for [uid] ('' when missing/error — evaluateCode
  /// treats any non-'active' status, including '', as suspended).
  static Future<String> insiderStatus(String uid) async {
    try {
      final snap =
          (await FirebaseDatabase.instance.ref('Insiders/$uid/Status').once())
              .snapshot;
      return snap.value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// True when `/ReferredUsers/{uid}` exists — the global once-ever guard
  /// (spec §3). False (never blocks) on error, matching this file's
  /// existing silent-failure convention.
  static Future<bool> alreadyReferred(String uid) async {
    try {
      final snap =
          (await FirebaseDatabase.instance.ref('ReferredUsers/$uid').once())
              .snapshot;
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// The code owner's display Name, for the "Code accepted — [Name]'s
  /// referral" message ('' when missing/error — the UI falls back to a
  /// generic phrasing in that case).
  static Future<String> getInsiderName(String uid) async {
    try {
      final snap =
          (await FirebaseDatabase.instance.ref('Insiders/$uid/Name').once())
              .snapshot;
      return snap.value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // -- Insider dashboard (Infinite Insiders P3, Task F4) -----------------

  /// Live "Your referrals" list for the signed-in Insider — every
  /// `/Referrals` row with `InsiderUid == uid`, newest-counted first (spec
  /// §7). A missing/malformed node (or one still using the pre-index
  /// shape) degrades to an empty list rather than throwing.
  /// Lockdown B8: a DENIED read also degrades to an empty list — RTDB
  /// queries need read permission at `/Referrals` itself (admin-only under
  /// default-deny), so the dashboard shows zero referrals instead of an
  /// error state until the Insiders rebuild moves this server-side.
  static Stream<List<InsiderReferral>> watchMyReferrals(String uid) =>
      streamErrorsAs(
          FirebaseDatabase.instance
              .ref('Referrals')
              .orderByChild('InsiderUid')
              .equalTo(uid)
              .onValue
              .map((event) => sortReferralsNewestFirst<InsiderReferral>(
                    referralsFromNode(event.snapshot.value),
                    (r) => r.countedAt,
                  )),
          const <InsiderReferral>[]);

  /// Toggles the "Show me on the public leaderboard" opt-out (spec §7 —
  /// individually opt-out-able from the leaderboard row).
  static Future<void> setLeaderboardOptIn({
    required String uid,
    required bool value,
  }) =>
      _ref(uid).update({'PublicLeaderboardOptIn': value});

  /// Toggles the "Show Insider badge on my profile" opt-out (spec §7 — the
  /// profile-box exposure, independently opt-out-able from the leaderboard
  /// row above).
  static Future<void> setProfileBadgeOptIn({
    required String uid,
    required bool value,
  }) =>
      _ref(uid).update({'ProfileBadgeOptIn': value});

  // watchAllInsiders / watchAllReferrals (the whole-`/Insiders` and
  // `/Referrals` root streams the public leaderboard rode, emails
  // included) were removed in DB lockdown B6: both roots are denied under
  // default-deny and the program is dormant. The pure leaderboard logic
  // (leaderboardRows/programStats in model/insider.dart) stays for the
  // Insiders rebuild, which will feed it from a public mirror instead.
}
