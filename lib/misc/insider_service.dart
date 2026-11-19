import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/stream_resilience.dart';
import 'package:infinite_sports_flutter/model/insider.dart';

/// An Insider code check whose answer the server did not confirm (the
/// phone's saved copy, or a failed read) — fresh reads, Task 3 (#15-#17).
/// The promo field shows [kInsiderCodeCouldNotCheck] and stamps nothing.
class InsiderCheckUnavailable implements Exception {
  const InsiderCheckUnavailable([this.cause]);
  final Object? cause;
  @override
  String toString() => 'InsiderCheckUnavailable($cause)';
}

/// The promo field's "couldn't check" sentence (same shape as the join-code
/// page's).
const String kInsiderCodeCouldNotCheck =
    "Couldn't check the code. Check your connection and try again.";

/// [serverFirstValue] for a code check: the server's value, or
/// [InsiderCheckUnavailable].
Future<Object?> _checkedValue(String path) async {
  final FreshValue r;
  try {
    r = await serverFirstValue(path);
  } catch (e) {
    throw InsiderCheckUnavailable(e);
  }
  if (!r.fromServer) throw const InsiderCheckUnavailable('not from server');
  return r.value;
}

/// What [InsiderService.apply] may do.
enum InsiderApplyDecision { write, alreadyApplied, couldNotCheck }

/// [InsiderService.apply]'s guard, pure (fresh reads, Task 4, #14): an
/// existing pending/active/suspended application counts from ANY source (it
/// is never clobbered); "no application" or "declined" only allows a write
/// when the server said so — the saved copy can be older than an approval.
InsiderApplyDecision insiderApplyDecision(Object? raw, String uid,
    {required bool fromServer}) {
  final existing = Insider.fromFirebase(uid, raw);
  if (existing != null && !existing.isDeclined) {
    return InsiderApplyDecision.alreadyApplied;
  }
  return fromServer
      ? InsiderApplyDecision.write
      : InsiderApplyDecision.couldNotCheck;
}

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
    // Fresh reads (Task 4, #14): server-first — see insiderApplyDecision.
    // "Couldn't check" throws, and the info page's existing "Something went
    // wrong. Please try again." snackbar shows.
    final FreshValue read;
    try {
      read = await serverFirstValue('Insiders/$uid');
    } catch (e) {
      throw InsiderCheckUnavailable(e);
    }
    switch (insiderApplyDecision(read.value, uid, fromServer: read.fromServer)) {
      case InsiderApplyDecision.alreadyApplied:
        return;
      case InsiderApplyDecision.couldNotCheck:
        throw const InsiderCheckUnavailable('not from server');
      case InsiderApplyDecision.write:
        break;
    }

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

  //
  // The three checks below decide a discount and a referral credit, so they
  // are server-first (fresh reads, Task 3): an answer the server did not
  // confirm — the phone's saved copy (a revoked code, a suspended owner, a
  // stale "not referred yet") or a failed read — throws
  // [InsiderCheckUnavailable] instead of being treated as a fact.

  /// The uid owning [code] (normalized uppercase before lookup), or null
  /// when the code is blank or the server says it is unclaimed
  /// (evaluateCode's `invalid` branch). Throws [InsiderCheckUnavailable]
  /// when the server could not confirm the answer.
  static Future<String?> lookupCode(String code) async {
    final normalized = normalizeInsiderCode(code);
    if (normalized.isEmpty) return null;
    final uid = await _checkedValue('InsiderCodes/$normalized');
    return (uid is String && uid.isNotEmpty) ? uid : null;
  }

  /// Just the Status field for [uid] ('' when missing — evaluateCode treats
  /// any non-'active' status, including '', as suspended). Throws
  /// [InsiderCheckUnavailable] when the server could not confirm it.
  static Future<String> insiderStatus(String uid) async {
    final status = await _checkedValue('Insiders/$uid/Status');
    return status?.toString() ?? '';
  }

  /// True when `/ReferredUsers/{uid}` exists — the global once-ever guard
  /// (spec §3). Throws [InsiderCheckUnavailable] when the server could not
  /// confirm it (it used to answer false on an error — a second referral
  /// discount on a failed read).
  static Future<bool> alreadyReferred(String uid) async {
    return (await _checkedValue('ReferredUsers/$uid')) != null;
  }

  /// The code owner's display Name, for the "Code accepted — [Name]'s
  /// referral" message ('' when missing/error — the UI falls back to a
  /// generic phrasing in that case).
  static Future<String> getInsiderName(String uid) async {
    try {
      final snap =
          (await refreshingOnce(FirebaseDatabase.instance.ref('Insiders/$uid/Name')))
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
