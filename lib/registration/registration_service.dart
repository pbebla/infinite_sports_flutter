import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/stream_resilience.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// What a submit attempt came to. [alreadyRegistered] and [couldNotCheck]
/// are refusals made BEFORE anything is written (fresh-reads Task 3, #74):
/// a submit never overwrites an existing (maybe paid, maybe discounted)
/// submission, and never writes on an answer the server did not confirm.
enum SubmitOutcome { ok, alreadyRegistered, couldNotCheck, failed }

/// Where a Register tap leads (fresh-reads Task 3, #72/#74).
enum RegistrationRoute { status, register, closed, couldNotCheck }

/// The routing decision, pure. [configChecked]/[submissionChecked] say the
/// answers came from the server (a saved copy or a failed read is not a
/// fact): an existing submission (from any source) opens the status page;
/// "not registered" only counts when the server said so; a registration's
/// open/closed state and fee only count when the server said so.
RegistrationRoute registrationRoute({
  required bool configChecked,
  required RegistrationConfig? config,
  required bool submissionExists,
  required bool submissionChecked,
}) {
  if (!configChecked) return RegistrationRoute.couldNotCheck;
  if (config == null || !config.isOpen) return RegistrationRoute.closed;
  if (submissionExists) return RegistrationRoute.status;
  if (!submissionChecked) return RegistrationRoute.couldNotCheck;
  return RegistrationRoute.register;
}

/// The "couldn't check" sentence of the registration screens (same shape as
/// the join-code page's "Couldn't check the code…").
const String kRegistrationCouldNotCheck =
    "Couldn't check your registration. Check your connection and try again.";

/// Fan-side reads/writes for the new registration engine (L1a individual
/// path + L1b team paths). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — with
/// ONE exception: a joiner whose team code waives payment is born
/// Paid/'team code' (spec section 5); everything else is the Manager's
/// markPaid.
class RegistrationService {
  /// Test seam replacing the real callable round trip for
  /// [checkFirstTimer] / [resolveJoinCode]: receives the callable name and
  /// payload and returns the callable's `data` (or throws, like a failed
  /// call). null in production.
  @visibleForTesting
  static Future<Object?> Function(String name, Map<String, dynamic> data)?
      callableOverride;

  /// Test seam replacing the signed-in uid (null = FirebaseAuth).
  @visibleForTesting
  static String? Function()? uidOverride;

  static String? get _uid =>
      uidOverride != null ? uidOverride!() : FirebaseAuth.instance.currentUser?.uid;

  static Future<Object?> _callable(
      String name, Map<String, dynamic> data) async {
    final override = callableOverride;
    if (override != null) return override(name, data);
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call<Map<String, dynamic>>(data);
    return result.data;
  }

  /// {regId: config} for every registration whose Status is "open".
  ///
  /// DB lockdown B2: reads the RegistrationsPublic mirror (each child is
  /// the registration's Config node verbatim, maintained by the
  /// public-mirror trigger) instead of the Registrations root — that root
  /// also holds Submissions, which go owner-only when the rules flip, and
  /// RTDB denies a whole-node read unless the WHOLE subtree is readable.
  static Future<Map<String, RegistrationConfig>> getOpenRegistrations() async {
    try {
      final snap =
          (await refreshingOnce(FirebaseDatabase.instance.ref('RegistrationsPublic')))
              .snapshot;
      return openRegistrationsFromNode(snap.value);
    } catch (_) {
      return {};
    }
  }

  /// One registration's config checked against the server (fresh-reads
  /// Task 3, #72) — the event page's Register passes this config (and its
  /// fee) into the whole flow, so a saved copy is not enough. `config` is
  /// null when the registration is missing or not open; `checked` is false
  /// when the server could not confirm the answer (offline, timeout, error).
  static Future<({RegistrationConfig? config, bool checked})>
      checkOpenRegistration(String regId) async {
    try {
      final r = await serverFirstValue('RegistrationsPublic/$regId');
      final config = RegistrationConfig.fromFirebase(r.value);
      return (
        config: config != null && config.isOpen ? config : null,
        checked: r.fromServer,
      );
    } catch (_) {
      return (config: null, checked: false);
    }
  }

  /// THE entry decision every way into a registration uses (the event
  /// page's Register, the registration list reached from the home banner or
  /// the drawer — review fix Important 1). The config is re-read
  /// SERVER-FIRST together with "already registered?" (one barrier, one
  /// bound), and only that server config is handed to the path, form,
  /// status and payment pages — the fee shown and the Venmo/Zelle amount
  /// come from the same config the card charge does
  /// (createRegistrationPaymentIntent reads the server Config).
  /// `config` is null unless the route is status/register.
  static Future<({RegistrationRoute route, RegistrationConfig? config})>
      checkEntry(String regId) async {
    final checks = await Future.wait<Object>([
      checkOpenRegistration(regId),
      checkMySubmission(regId),
    ]);
    final open = checks[0] as ({RegistrationConfig? config, bool checked});
    final mine =
        checks[1] as ({RegSubmission? submission, bool exists, bool checked});
    final route = registrationRoute(
        configChecked: open.checked,
        config: open.config,
        submissionExists: mine.exists,
        submissionChecked: mine.checked);
    final goes =
        route == RegistrationRoute.status || route == RegistrationRoute.register;
    return (route: route, config: goes ? open.config : null);
  }

  /// Live config of ONE registration from `Registrations/<regId>/Config` —
  /// the node the card charge is computed from (second review, Important
  /// 2; readable by everyone under both rules files). null = missing or
  /// malformed. Errors are forwarded (a failed read is not a fact).
  static Stream<RegistrationConfig?> watchConfig(String regId) =>
      FirebaseDatabase.instance
          .ref('Registrations/$regId/Config')
          .onValue
          .map((event) => RegistrationConfig.fromFirebase(event.snapshot.value));

  /// Live {regId: config} stream of every open registration. Emits
  /// immediately from RTDB's local cache (if any) then on every change, so
  /// registrations opening/closing appear on the entry page without a
  /// refresh. Same stream style as TournamentService.watchMatches.
  /// Lockdown B2: rides the RegistrationsPublic mirror (see
  /// [getOpenRegistrations]).
  static Stream<Map<String, RegistrationConfig>> watchOpenRegistrations() {
    return FirebaseDatabase.instance
        .ref('RegistrationsPublic')
        .onValue
        .map((event) {
      try {
        return openRegistrationsFromNode(event.snapshot.value);
      } catch (_) {
        return <String, RegistrationConfig>{};
      }
    });
  }

  /// The ordered question list for a registration ([] on error).
  static Future<List<RegQuestion>> getForm(String regId) async {
    try {
      // once(), not get(): firebase-ios-sdk returns wrong/empty data for one-shot
      final snap = (await refreshingOnce(FirebaseDatabase.instance
              .ref('Registrations/$regId/Form')))
          .snapshot;
      return regQuestionsFromNode(snap.value);
    } catch (_) {
      return [];
    }
  }

  /// The signed-in user's submission checked against the server
  /// (fresh-reads Task 3, #74): `exists` is true when ANY node is there
  /// (even a malformed one — never route a registered fan back into the
  /// form); `checked` is true when the answer is a fact (it exists, or the
  /// server said it does not). A saved copy saying "none", or a failed read,
  /// is `checked: false`. Signed out: nothing to find (checked).
  static Future<({RegSubmission? submission, bool exists, bool checked})>
      checkMySubmission(String regId) async {
    final uid = _uid;
    if (uid == null) return (submission: null, exists: false, checked: true);
    try {
      final r = await serverFirstValue('Registrations/$regId/Submissions/$uid');
      final exists = r.value != null;
      return (
        submission: RegSubmission.fromFirebase(r.value),
        exists: exists,
        checked: exists || r.fromServer,
      );
    } catch (_) {
      return (submission: null, exists: false, checked: false);
    }
  }

  /// Test seam replacing the legacy sign-up repair write (path, value).
  @visibleForTesting
  static Future<void> Function(String path, Object value)? legacyWriteOverride;

  /// Review fix (Minor 1): a submit whose submission write landed but whose
  /// legacy `Sign Ups/<league>/<season>/<bucket>/<uid>` dual-write did not
  /// (the "try again" now meets the existing submission) is completed here,
  /// on the retry and when the status page opens. Idempotent and safe: the
  /// three reads are server-first and run together; nothing is written
  /// unless all three came from the server ([legacyRepairBucket]); an entry
  /// in EITHER bucket means nothing to do (a Paid entry is never touched);
  /// only the signed-in fan's own uid is written. Never throws.
  static Future<void> repairLegacySignUp(
      String regId, RegistrationConfig config,
      {String? displayName}) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      final target = legacySignUpTarget(config);
      final base = 'Sign Ups/${target.league}/${target.season}';
      final reads = await Future.wait([
        serverFirstValue('Registrations/$regId/Submissions/$uid'),
        serverFirstValue('$base/NotPaid/$uid'),
        serverFirstValue('$base/Paid/$uid'),
      ]);
      if (!reads.every((r) => r.fromServer)) return;
      final bucket = legacyRepairBucket(
          submission: RegSubmission.fromFirebase(reads[0].value),
          notPaidExists: reads[1].value != null,
          paidExists: reads[2].value != null);
      if (bucket == null) return;
      final name = displayName ??
          collapseTrailingSpaces(
              FirebaseAuth.instance.currentUser?.displayName ?? '');
      final path = '$base/$bucket/$uid';
      final write = legacyWriteOverride;
      if (write != null) {
        await write(path, name);
      } else {
        await FirebaseDatabase.instance.ref(path).set(name);
      }
    } catch (e) {
      debugPrint('RegistrationService: legacy sign-up repair failed: $e');
    }
  }

  /// The pre-write guard every submit runs (fresh-reads Task 3, #74). The
  /// rules let the owner overwrite their own submission while the
  /// registration is open (database.rules.stage1.json
  /// Registrations/$regId/Submissions/$uid: `.write` has no
  /// `!data.exists()`, and `.validate` accepts Paid:false over Paid:true),
  /// so the app refuses: an existing submission → [alreadyRegistered];
  /// "none" not confirmed by the server → [couldNotCheck].
  static Future<SubmitOutcome> guardNewSubmission(
      String regId, String uid) async {
    try {
      final r = await serverFirstValue('Registrations/$regId/Submissions/$uid');
      if (r.value != null) return SubmitOutcome.alreadyRegistered;
      if (!r.fromServer) return SubmitOutcome.couldNotCheck;
      return SubmitOutcome.ok;
    } catch (_) {
      return SubmitOutcome.couldNotCheck;
    }
  }

  /// Live stream of the signed-in user's submission — a Paid flip in the
  /// Manager shows up on the open status page instantly. Emits null when the
  /// node is missing/malformed; a signed-out user gets a single null.
  static Stream<RegSubmission?> watchMySubmission(String regId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return FirebaseDatabase.instance
        .ref('Registrations/$regId/Submissions/$uid')
        .onValue
        .map((event) {
      try {
        return RegSubmission.fromFirebase(event.snapshot.value);
      } catch (_) {
        return null;
      }
    });
  }

  /// Pre-fills well-known keys from Users/{uid} (First Name, Last Name,
  /// Phone Number) and Users/{uid}/Information (Age, Height, positions for
  /// [sport]). Returns {} when signed out or on error.
  static Future<Map<String, dynamic>> getPrefill(String sport) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    try {
      final snap =
          (await refreshingOnce(FirebaseDatabase.instance.ref('Users/$uid'))).snapshot;
      if (snap.value is! Map) return {};
      final user = snap.value as Map;
      final out = <String, dynamic>{};
      if (user['First Name'] != null) {
        out['firstName'] = user['First Name'].toString();
      }
      if (user['Last Name'] != null) {
        out['lastName'] = user['Last Name'].toString();
      }
      if (user['Phone Number'] != null) {
        out['phone'] = user['Phone Number'].toString();
      }
      final info = user['Information'];
      if (info is Map) {
        if (info['Age'] != null) out['age'] = info['Age'].toString();
        if (info['Height'] != null) out['height'] = info['Height'].toString();
        final posField = positionsFieldForSport(sport);
        final positions = posField.isEmpty ? null : info[posField];
        if (positions is String && positions.isNotEmpty) {
          out['positions'] = positions.split(';');
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  // -- Insider promo-code entry (Infinite Insiders P2, Task F3) ----------

  /// The per-registration first-timer promo config at
  /// Registrations/{regId}/Promo (spec §9). M3 (the Manager's config
  /// editor) has not shipped yet — [RegPromo.fromFirebase] is defensive, so
  /// a missing node (every registration today) parses to an all-defaults,
  /// DISABLED promo rather than throwing/returning null.
  ///
  /// Server-first (fresh-reads Task 3, #76): the promo percent is stamped
  /// onto the submission, so `checked` says whether the server confirmed it.
  /// A saved copy or a failed read comes back `checked: false` (with the
  /// saved copy, or the disabled default) and the form applies NO promo
  /// discount on it.
  static Future<({RegPromo promo, bool checked})> getPromo(String regId) async {
    try {
      final r = await serverFirstValue('Registrations/$regId/Promo');
      return (promo: RegPromo.fromFirebase(r.value), checked: r.fromServer);
    } catch (_) {
      return (promo: const RegPromo(), checked: false);
    }
  }

  /// The signed-in registrant's first-timer verdict (spec §4), via the
  /// checkFirstTimer callable (DB lockdown B4). The old client-side scan
  /// downloaded EVERY submission of EVERY registration to match email/
  /// phone locally — a privacy bug in its own right, and impossible under
  /// default-deny (Submissions are owner-only). The callable runs the
  /// identical match server-side (functions/src/registration_lookups.ts,
  /// same normalization as promo_engine.dart's [firstTimer]) and returns
  /// the same FirstTimerResult shape.
  ///
  /// An error is not a verdict: a failed call (offline, timeout, cold
  /// start) comes back as NOT a first-timer with
  /// [FirstTimerResult.checkFailed] set, so no first-timer promo discount is
  /// handed out on a guess — the promo field tells the person the standard
  /// fee applies and to contact us (an admin can still grant the promo in
  /// the Manager). Same callable pattern as createRegistrationPaymentIntent
  /// (payment_screen.dart).
  static Future<FirstTimerResult> checkFirstTimer({
    required String email,
    required String phone,
  }) async {
    try {
      final data =
          await _callable('checkFirstTimer', {'email': email, 'phone': phone});
      return firstTimerResultFromCallable(data);
    } catch (_) {
      return const FirstTimerResult(isFirstTimer: false, checkFailed: true);
    }
  }

  /// Resolves an entered team join code server-side (DB lockdown B4) via
  /// the resolveJoinCode callable. The old flow downloaded ALL of a
  /// registration's teams — join codes included, payment-waiving ones among
  /// them — and matched locally; the callable never returns other teams'
  /// codes. The result maps onto the same [JoinCodeMatch] statuses the page
  /// has always branched on ('ok' | 'notApproved' | 'notFound'). A FAILED
  /// call (offline, timeout, cold start) is 'error' — never 'notFound', which
  /// would tell a teammate holding a correct code that it is wrong.
  static Future<JoinCodeMatch> resolveJoinCode({
    required String regId,
    required String code,
  }) async {
    try {
      final data =
          await _callable('resolveJoinCode', {'regId': regId, 'code': code});
      return joinCodeMatchFromCallable(data);
    } catch (_) {
      return const JoinCodeMatch('error');
    }
  }

  /// Individual-path submit:
  ///  1. writes Registrations/{regId}/Submissions/{uid}
  ///     {Path:'individual', Answers, Paid:false, DisplayName, SubmittedAt}
  ///  2. legacy dual-write Sign Ups/{league}/{season}/NotPaid/{uid} =
  ///     displayName (same shape utility.dart's signUpToPlay writes, so the
  ///     Manager Sign Ups page + Add-from-signups picker keep working)
  ///  3. profile write-back for well-known keys.
  ///
  /// [insiderCode]/[firstTimer]/[discountSource]/[discountPct]/[eligibleFee]
  /// are the Task F3 promo-code stamp — all optional, populated by
  /// RegistrationFormPage from the InsiderPromoCodeField's validated
  /// [InsiderPromoOutcome] (empty/null when no code was entered).
  /// Refuses (writing nothing) when a submission already exists or the
  /// server could not confirm there is none ([guardNewSubmission]);
  /// [SubmitOutcome.failed] when signed out or any write throws.
  static Future<SubmitOutcome> submitIndividual({
    required String regId,
    required RegistrationConfig config,
    required Map<String, dynamic> answers,
    String insiderCode = '',
    bool? firstTimer,
    String discountSource = '',
    double? discountPct,
    double? eligibleFee,
    Map<String, dynamic> prefill = const {},
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SubmitOutcome.failed;
    final guard = await guardNewSubmission(regId, user.uid);
    if (guard != SubmitOutcome.ok) return guard;
    final displayName = collapseTrailingSpaces(user.displayName ?? '');
    try {
      final submission = RegSubmission(
        path: 'individual',
        answers: answers,
        paid: false,
        displayName: displayName,
        submittedAt: DateTime.now().millisecondsSinceEpoch,
        insiderCode: insiderCode,
        firstTimer: firstTimer,
        discountSource: discountSource,
        discountPct: discountPct,
        eligibleFee: eligibleFee,
      );
      await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/${user.uid}')
          .set(submission.toFirebaseMap());
      final target = legacySignUpTarget(config);
      await FirebaseDatabase.instance
          .ref('Sign Ups/${target.league}/${target.season}/NotPaid/${user.uid}')
          .set(displayName);
      await _writeBackProfile(user.uid, config.sport, answers, prefill);
      return SubmitOutcome.ok;
    } catch (_) {
      return SubmitOutcome.failed;
    }
  }

  /// Writes well-known answer keys back to the profile, using update() so
  /// unrelated fields are never clobbered (same nodes createDatabaseLocation
  /// and addUpdateInfo in lib/misc/utility.dart write) — and only the ones
  /// the fan changed from the form's [prefill] ([profileWriteBack]).
  static Future<void> _writeBackProfile(String uid, String sport,
      Map<String, dynamic> answers, Map<String, dynamic> prefill) async {
    final root = FirebaseDatabase.instance.ref('Users/$uid');
    final w = profileWriteBack(sport: sport, answers: answers, prefill: prefill);
    if (w.root.isNotEmpty) await root.update(w.root);
    if (w.info.isNotEmpty) await root.child('Information').update(w.info);
  }

  // -------- Teams (L1b) --------

  // getTeams (the whole-Teams read the join-code page matched against) was
  // removed in lockdown B4: Teams/{tid} is captain-only under default-deny
  // and the join-code match runs server-side now ([resolveJoinCode]).

  /// One team, or null (missing / malformed / error).
  static Future<RegTeam?> getTeam(String regId, String teamId) async {
    if (teamId.isEmpty) return null;
    try {
      final snap = (await refreshingOnce(FirebaseDatabase.instance
              .ref('Registrations/$regId/Teams/$teamId')))
          .snapshot;
      return RegTeam.fromNode(teamId, snap.value);
    } catch (_) {
      return null;
    }
  }

  /// Live stream of one team — the captain sees approval, the join code and
  /// waive changes the moment an admin writes them. Emits null while the
  /// node is missing/malformed; an empty [teamId] gets a single null.
  /// Lockdown B8: a DENIED read (joiners can't read `Teams/<tid>` under
  /// default-deny) also emits null instead of an error, so the status page
  /// degrades to the submission-stamped team name rather than an error
  /// state.
  static Stream<RegTeam?> watchTeam(String regId, String teamId) {
    if (teamId.isEmpty) return Stream.value(null);
    return streamErrorsAs(
        FirebaseDatabase.instance
            .ref('Registrations/$regId/Teams/$teamId')
            .onValue
            .map<RegTeam?>((event) {
          try {
            return RegTeam.fromNode(teamId, event.snapshot.value);
          } catch (_) {
            return null;
          }
        }),
        null);
  }

  /// Live roster of a team's joiners for the captain's status page, sorted
  /// by display name (case-insensitive). Defensive: junk children are
  /// skipped and a missing/malformed node yields an empty list.
  ///
  /// DB lockdown B3: streams the trigger-maintained
  /// Registrations/{regId}/Teams/{teamId}/Members mirror ({uid:
  /// {DisplayName, Paid}}) instead of scanning the whole Submissions bucket
  /// (owner-only under default-deny). The mirror also carries the CAPTAIN's
  /// own submission — pass [captainUid] so it is filtered out, preserving
  /// the pre-mirror roster shape (the old scan kept Path=='joiner' only).
  static Stream<List<RegSubmission>> watchTeamMembers(
      String regId, String teamId,
      {String captainUid = ''}) {
    return FirebaseDatabase.instance
        .ref('Registrations/$regId/Teams/$teamId/Members')
        .onValue
        .map((event) {
      try {
        return teamMembersFromNode(event.snapshot.value,
            teamId: teamId, captainUid: captainUid);
      } catch (_) {
        return <RegSubmission>[];
      }
    });
  }

  /// Captain-path submit:
  ///  1. pushes the pending Team under Registrations/{regId}/Teams
  ///     {Name (hygiene-cleaned), CaptainUid, Status:'pending',
  ///      CodeWaivesPayment:false, CreatedAt}
  ///  2. writes Submission{Path:'captain', TeamId, Paid:false}
  ///  3. legacy dual-write Sign Ups NotPaid + profile write-back — exactly
  ///     like submitIndividual.
  ///
  /// [insiderCode]/[firstTimer]/[discountSource]/[discountPct]/[eligibleFee]:
  /// same Task F3 promo-code stamp as submitIndividual — the code field is
  /// offered on the captain path too (spec §7), discounting the team fee
  /// when eligible.
  /// Same refusals as [submitIndividual] (checked before the team is
  /// created).
  static Future<SubmitOutcome> submitCaptain({
    required String regId,
    required RegistrationConfig config,
    required String teamName,
    required Map<String, dynamic> answers,
    String insiderCode = '',
    bool? firstTimer,
    String discountSource = '',
    double? discountPct,
    double? eligibleFee,
    Map<String, dynamic> prefill = const {},
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SubmitOutcome.failed;
    final guard = await guardNewSubmission(regId, user.uid);
    if (guard != SubmitOutcome.ok) return guard;
    final displayName = collapseTrailingSpaces(user.displayName ?? '');
    try {
      final teamNode =
          FirebaseDatabase.instance.ref('Registrations/$regId/Teams').push();
      final teamId = teamNode.key!;
      final team = RegTeam(
        id: teamId,
        name: cleanTeamName(teamName),
        captainUid: user.uid,
        status: 'pending',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await teamNode.set(team.toFirebaseMap());
      final submission = RegSubmission(
        path: 'captain',
        answers: answers,
        teamId: teamId,
        paid: false,
        displayName: displayName,
        submittedAt: DateTime.now().millisecondsSinceEpoch,
        insiderCode: insiderCode,
        firstTimer: firstTimer,
        discountSource: discountSource,
        discountPct: discountPct,
        eligibleFee: eligibleFee,
      );
      await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/${user.uid}')
          .set(submission.toFirebaseMap());
      final target = legacySignUpTarget(config);
      await FirebaseDatabase.instance
          .ref('Sign Ups/${target.league}/${target.season}/NotPaid/${user.uid}')
          .set(displayName);
      await _writeBackProfile(user.uid, config.sport, answers, prefill);
      return SubmitOutcome.ok;
    } catch (_) {
      return SubmitOutcome.failed;
    }
  }

  /// Joiner-path submit. When [team].codeWaivesPayment the submission is
  /// born Paid ('team code') and the legacy dual-write goes straight to the
  /// Paid bucket; otherwise it lands in NotPaid exactly like an individual.
  /// Same refusals as [submitIndividual].
  static Future<SubmitOutcome> submitJoiner({
    required String regId,
    required RegistrationConfig config,
    required RegTeam team,
    required Map<String, dynamic> answers,
    Map<String, dynamic> prefill = const {},
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SubmitOutcome.failed;
    final guard = await guardNewSubmission(regId, user.uid);
    if (guard != SubmitOutcome.ok) return guard;
    final displayName = collapseTrailingSpaces(user.displayName ?? '');
    try {
      final waived = team.codeWaivesPayment;
      final submission = RegSubmission(
        path: 'joiner',
        answers: answers,
        teamId: team.id,
        // B8: stamped so the status page can render the team card without
        // reading Teams/<tid> (captain+admin-only under default-deny).
        teamName: team.name,
        paid: waived,
        paidVia: waived ? 'team code' : '',
        displayName: displayName,
        submittedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/${user.uid}')
          .set(submission.toFirebaseMap());
      final target = legacySignUpTarget(config);
      final bucket = waived ? 'Paid' : 'NotPaid';
      await FirebaseDatabase.instance
          .ref('Sign Ups/${target.league}/${target.season}/$bucket/${user.uid}')
          .set(displayName);
      await _writeBackProfile(user.uid, config.sport, answers, prefill);
      return SubmitOutcome.ok;
    } catch (_) {
      return SubmitOutcome.failed;
    }
  }
}

/// Which legacy Sign Ups bucket a resumed submit must fill in (review fix
/// Minor 1), or null for nothing: no submission, an entry already in either
/// bucket (never downgrade a Paid entry), or a submission paid some other
/// way (the Manager's flip moves it). Same buckets the submit writes: a
/// team-code-waived joiner is born Paid, everyone else NotPaid.
String? legacyRepairBucket({
  required RegSubmission? submission,
  required bool notPaidExists,
  required bool paidExists,
}) {
  if (submission == null || notPaidExists || paidExists) return null;
  if (!submission.paid) return 'NotPaid';
  if (submission.paidVia == 'team code') return 'Paid';
  return null;
}

/// What the registration write-back writes (fresh reads, Task 3, #75): only
/// the well-known answers the fan CHANGED from the form's [prefill]. The
/// prefill is read from `Users/<uid>` and may be the phone's saved copy; an
/// untouched (maybe stale) value is never written back over a newer one set
/// by the Manager or another device. A field the profile did not have is a
/// change. Phone numbers compare normalized.
({Map<String, Object?> root, Map<String, Object?> info}) profileWriteBack({
  required String sport,
  required Map<String, dynamic> answers,
  required Map<String, dynamic> prefill,
}) {
  final root = <String, Object?>{};
  final info = <String, Object?>{};
  String text(Object? v) => v?.toString() ?? '';

  for (final (key, field) in [
    ('firstName', 'First Name'),
    ('lastName', 'Last Name'),
  ]) {
    final v = answers[key];
    if (v is String && v.isNotEmpty && v != text(prefill[key])) root[field] = v;
  }
  final phone = answers['phone'];
  if (phone != null) {
    final n = normalizePhone(phone.toString());
    if (n.isNotEmpty && n != normalizePhone(text(prefill['phone']))) {
      root['Phone Number'] = n;
    }
  }

  final positions = answers['positions'];
  final posField = positionsFieldForSport(sport);
  if (positions is List && positions.isNotEmpty && posField.isNotEmpty) {
    final joined = positions.map((p) => p.toString()).join(';');
    final before = prefill['positions'];
    final beforeJoined =
        before is List ? before.map((p) => p.toString()).join(';') : '';
    if (joined != beforeJoined) info[posField] = joined;
  }
  final age = int.tryParse(text(answers['age']));
  if (age != null && age != int.tryParse(text(prefill['age']))) {
    info['Age'] = age;
  }
  final height = answers['height'];
  if (height is String && height.isNotEmpty && height != text(prefill['height'])) {
    info['Height'] = height;
  }
  return (root: root, info: info);
}

// ---------------------------------------------------------------------------
// Pure parsing for the lockdown mirrors (unit-tested without Firebase —
// test/registration_callables_test.dart; activity_entry.dart-style).
// ---------------------------------------------------------------------------

/// Parses the RegistrationsPublic root ({regId: Config-verbatim}) into
/// {regId: config}, keeping only OPEN registrations. {} for null/junk;
/// malformed children are skipped. Defensive about RTDB's List coercion
/// (regIds like "Futsal-17" are never dense ints, but a List must not
/// crash — non-null entries parse under their index).
Map<String, RegistrationConfig> openRegistrationsFromNode(Object? raw) {
  final out = <String, RegistrationConfig>{};
  void add(String regId, Object? node) {
    final config = RegistrationConfig.fromFirebase(node);
    if (config != null && config.isOpen) out[regId] = config;
  }

  if (raw is Map) {
    raw.forEach((regId, node) => add(regId.toString(), node));
  } else if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add('$i', raw[i]);
    }
  }
  return out;
}

/// Parses a Registrations/{regId}/Teams/{teamId}/Members mirror node
/// ({uid: {DisplayName, Paid}}) into the joiner-roster shape the status
/// page has always consumed: RegSubmissions with path 'joiner', this
/// [teamId], the mirrored DisplayName/Paid, sorted by display name
/// (case-insensitive). The entry whose uid equals [captainUid] is skipped
/// (captains appear in Members too, but the roster lists joiners only).
/// [] for null/junk; malformed children are skipped; an RTDB List
/// coercion parses non-null entries under their index without crashing.
List<RegSubmission> teamMembersFromNode(Object? raw,
    {required String teamId, String captainUid = ''}) {
  final out = <RegSubmission>[];
  void add(String uid, Object? node) {
    if (node is! Map) return;
    if (captainUid.isNotEmpty && uid == captainUid) return;
    out.add(RegSubmission(
      path: 'joiner',
      answers: const {},
      teamId: teamId,
      paid: node['Paid'] == true,
      displayName: node['DisplayName']?.toString() ?? '',
    ));
  }

  if (raw is Map) {
    raw.forEach((uid, node) => add(uid.toString(), node));
  } else if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add('$i', raw[i]);
    }
  }
  out.sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return out;
}

/// Maps a resolveJoinCode callable result onto the [JoinCodeMatch] shape
/// the join-code page has always branched on. The callable returns
/// {found: true, status: 'ok', teamId, teamName, codeWaivesPayment} for an
/// approved match, or {found: false, status: 'notApproved'|'notFound'}.
/// An 'ok' result becomes an approved [RegTeam] carrying exactly the
/// fields the joiner flow uses downstream (id for the submission's TeamId,
/// name for the headers, codeWaivesPayment for the born-Paid path);
/// CaptainUid is not returned (never needed on the joiner path).
/// Malformed/incomplete payloads degrade to 'notFound'.
JoinCodeMatch joinCodeMatchFromCallable(Object? data) {
  if (data is! Map) return const JoinCodeMatch('notFound');
  final status = data['status']?.toString() ?? '';
  if (data['found'] == true && status == 'ok') {
    final teamId = data['teamId']?.toString() ?? '';
    final teamName = data['teamName']?.toString() ?? '';
    if (teamId.isEmpty || teamName.isEmpty) {
      return const JoinCodeMatch('notFound');
    }
    return JoinCodeMatch(
        'ok',
        RegTeam(
          id: teamId,
          name: teamName,
          captainUid: '',
          status: 'approved',
          codeWaivesPayment: data['codeWaivesPayment'] == true,
        ));
  }
  if (status == 'notApproved') return const JoinCodeMatch('notApproved');
  return const JoinCodeMatch('notFound');
}
