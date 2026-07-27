import 'package:firebase_database/firebase_database.dart';
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
  static Future<void> apply({
    required String uid,
    required String name,
    required String email,
    required List<String> sports,
  }) async {
    final nodeRef = _ref(uid);
    final snapshot = await nodeRef.get();
    final existing = Insider.fromFirebase(uid, snapshot.value);
    if (existing != null && !existing.isDeclined) return;

    await nodeRef.set({
      'Name': name,
      'Email': email,
      'SportsOfInterest': sports,
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
      final snap =
          await FirebaseDatabase.instance.ref('InsiderCodes/$normalized').get();
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
          await FirebaseDatabase.instance.ref('Insiders/$uid/Status').get();
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
      final snap = await FirebaseDatabase.instance.ref('ReferredUsers/$uid').get();
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
      final snap = await FirebaseDatabase.instance.ref('Insiders/$uid/Name').get();
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
  static Stream<List<InsiderReferral>> watchMyReferrals(String uid) =>
      FirebaseDatabase.instance
          .ref('Referrals')
          .orderByChild('InsiderUid')
          .equalTo(uid)
          .onValue
          .map((event) => sortReferralsNewestFirst<InsiderReferral>(
                referralsFromNode(event.snapshot.value),
                (r) => r.countedAt,
              ));

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

  // -- Public leaderboard (Infinite Insiders P4, Task F6) ----------------
  // Mirrors the Manager's own InsiderService.watchAllInsiders /
  // watchAllReferrals (lib/services/firebase/insider_service.dart) — same
  // node, same live-stream semantics — so both apps agree on what "the
  // program" looks like right now.

  /// Live {uid: Insider} for every Insider node, any status — the public
  /// leaderboard page (Task F6) filters this down to active +
  /// PublicLeaderboardOptIn via [leaderboardRows]/[programStats].
  static Stream<Map<String, Insider>> watchAllInsiders() =>
      FirebaseDatabase.instance
          .ref('Insiders')
          .onValue
          .map((event) => insidersFromNode(event.snapshot.value));

  /// Live referral history for every Insider (spec §9 — `/Referrals` is a
  /// single flat node); callers filter/sort as needed ([leaderboardRows]
  /// filters by insider/period/sport, [programStats] aggregates program-wide).
  static Stream<List<InsiderReferral>> watchAllReferrals() =>
      FirebaseDatabase.instance
          .ref('Referrals')
          .onValue
          .map((event) => referralsFromNode(event.snapshot.value));
}
