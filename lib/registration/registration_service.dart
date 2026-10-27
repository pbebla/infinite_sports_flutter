import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// Fan-side reads/writes for the new registration engine (L1a individual
/// path + L1b team paths). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — with
/// ONE exception: a joiner whose team code waives payment is born
/// Paid/'team code' (spec section 5); everything else is the Manager's
/// markPaid.
class RegistrationService {
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
          (await FirebaseDatabase.instance.ref('RegistrationsPublic').once())
              .snapshot;
      return openRegistrationsFromNode(snap.value);
    } catch (_) {
      return {};
    }
  }

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
      final snap = (await FirebaseDatabase.instance
              .ref('Registrations/$regId/Form')
              .once())
          .snapshot;
      return regQuestionsFromNode(snap.value);
    } catch (_) {
      return [];
    }
  }

  /// The signed-in user's submission, or null (not signed in / none / error).
  static Future<RegSubmission?> getMySubmission(String regId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = (await FirebaseDatabase.instance
              .ref('Registrations/$regId/Submissions/$uid')
              .once())
          .snapshot;
      return RegSubmission.fromFirebase(snap.value);
    } catch (_) {
      return null;
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
          (await FirebaseDatabase.instance.ref('Users/$uid').once()).snapshot;
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
  static Future<RegPromo> getPromo(String regId) async {
    try {
      final snap = (await FirebaseDatabase.instance
              .ref('Registrations/$regId/Promo')
              .once())
          .snapshot;
      return RegPromo.fromFirebase(snap.value);
    } catch (_) {
      return const RegPromo();
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
  /// Defensive: any error degrades to "first-timer" — exactly what the old
  /// scan's silent-failure path produced (an empty prior-submissions list).
  /// Same callable pattern as createRegistrationPaymentIntent
  /// (payment_screen.dart).
  static Future<FirstTimerResult> checkFirstTimer({
    required String email,
    required String phone,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('checkFirstTimer');
      final result = await callable
          .call<Map<String, dynamic>>({'email': email, 'phone': phone});
      return firstTimerResultFromCallable(result.data);
    } catch (_) {
      return const FirstTimerResult(isFirstTimer: true);
    }
  }

  /// Resolves an entered team join code server-side (DB lockdown B4) via
  /// the resolveJoinCode callable. The old flow downloaded ALL of a
  /// registration's teams — join codes included, payment-waiving ones among
  /// them — and matched locally; the callable never returns other teams'
  /// codes. The result maps onto the same [JoinCodeMatch] statuses the page
  /// has always branched on ('ok' | 'notApproved' | 'notFound'); errors
  /// degrade to 'notFound'.
  static Future<JoinCodeMatch> resolveJoinCode({
    required String regId,
    required String code,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('resolveJoinCode');
      final result = await callable
          .call<Map<String, dynamic>>({'regId': regId, 'code': code});
      return joinCodeMatchFromCallable(result.data);
    } catch (_) {
      return const JoinCodeMatch('notFound');
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
  /// Returns false when signed out or any write throws.
  static Future<bool> submitIndividual({
    required String regId,
    required RegistrationConfig config,
    required Map<String, dynamic> answers,
    String insiderCode = '',
    bool? firstTimer,
    String discountSource = '',
    double? discountPct,
    double? eligibleFee,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
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
      await _writeBackProfile(user.uid, config.sport, answers);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Writes well-known answer keys back to the profile, using update() so
  /// unrelated fields are never clobbered (same nodes createDatabaseLocation
  /// and addUpdateInfo in lib/misc/utility.dart write).
  static Future<void> _writeBackProfile(
      String uid, String sport, Map<String, dynamic> answers) async {
    final root = FirebaseDatabase.instance.ref('Users/$uid');
    final rootUpdates = <String, Object?>{};
    final firstName = answers['firstName'];
    if (firstName is String && firstName.isNotEmpty) {
      rootUpdates['First Name'] = firstName;
    }
    final lastName = answers['lastName'];
    if (lastName is String && lastName.isNotEmpty) {
      rootUpdates['Last Name'] = lastName;
    }
    final phone = answers['phone'];
    if (phone != null && normalizePhone(phone.toString()).isNotEmpty) {
      rootUpdates['Phone Number'] = normalizePhone(phone.toString());
    }
    if (rootUpdates.isNotEmpty) await root.update(rootUpdates);

    final infoUpdates = <String, Object?>{};
    final positions = answers['positions'];
    final posField = positionsFieldForSport(sport);
    if (positions is List && positions.isNotEmpty && posField.isNotEmpty) {
      infoUpdates[posField] = positions.map((p) => p.toString()).join(';');
    }
    final age = int.tryParse(answers['age']?.toString() ?? '');
    if (age != null) infoUpdates['Age'] = age;
    final height = answers['height'];
    if (height is String && height.isNotEmpty) infoUpdates['Height'] = height;
    if (infoUpdates.isNotEmpty) {
      await root.child('Information').update(infoUpdates);
    }
  }

  // -------- Teams (L1b) --------

  // getTeams (the whole-Teams read the join-code page matched against) was
  // removed in lockdown B4: Teams/{tid} is captain-only under default-deny
  // and the join-code match runs server-side now ([resolveJoinCode]).

  /// One team, or null (missing / malformed / error).
  static Future<RegTeam?> getTeam(String regId, String teamId) async {
    if (teamId.isEmpty) return null;
    try {
      final snap = (await FirebaseDatabase.instance
              .ref('Registrations/$regId/Teams/$teamId')
              .once())
          .snapshot;
      return RegTeam.fromNode(teamId, snap.value);
    } catch (_) {
      return null;
    }
  }

  /// Live stream of one team — the captain sees approval, the join code and
  /// waive changes the moment an admin writes them. Emits null while the
  /// node is missing/malformed; an empty [teamId] gets a single null.
  static Stream<RegTeam?> watchTeam(String regId, String teamId) {
    if (teamId.isEmpty) return Stream.value(null);
    return FirebaseDatabase.instance
        .ref('Registrations/$regId/Teams/$teamId')
        .onValue
        .map((event) {
      try {
        return RegTeam.fromNode(teamId, event.snapshot.value);
      } catch (_) {
        return null;
      }
    });
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
  /// Returns false when signed out or any write throws.
  static Future<bool> submitCaptain({
    required String regId,
    required RegistrationConfig config,
    required String teamName,
    required Map<String, dynamic> answers,
    String insiderCode = '',
    bool? firstTimer,
    String discountSource = '',
    double? discountPct,
    double? eligibleFee,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
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
      await _writeBackProfile(user.uid, config.sport, answers);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Joiner-path submit. When [team].codeWaivesPayment the submission is
  /// born Paid ('team code') and the legacy dual-write goes straight to the
  /// Paid bucket; otherwise it lands in NotPaid exactly like an individual.
  /// Returns false when signed out or any write throws.
  static Future<bool> submitJoiner({
    required String regId,
    required RegistrationConfig config,
    required RegTeam team,
    required Map<String, dynamic> answers,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final displayName = collapseTrailingSpaces(user.displayName ?? '');
    try {
      final waived = team.codeWaivesPayment;
      final submission = RegSubmission(
        path: 'joiner',
        answers: answers,
        teamId: team.id,
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
      await _writeBackProfile(user.uid, config.sport, answers);
      return true;
    } catch (_) {
      return false;
    }
  }
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
