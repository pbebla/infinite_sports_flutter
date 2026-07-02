import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// Fan-side reads/writes for the new registration engine (L1a individual
/// path + L1b team paths). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — with
/// ONE exception: a joiner whose team code waives payment is born
/// Paid/'team code' (spec section 5); everything else is the Manager's
/// markPaid.
class RegistrationService {
  /// {regId: config} for every registration whose Status is "open".
  static Future<Map<String, RegistrationConfig>> getOpenRegistrations() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('Registrations').get();
      if (snap.value is! Map) return {};
      final out = <String, RegistrationConfig>{};
      (snap.value as Map).forEach((regId, value) {
        if (value is! Map) return;
        final config = RegistrationConfig.fromFirebase(value['Config']);
        if (config != null && config.isOpen) out[regId.toString()] = config;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Live {regId: config} stream of every open registration. Emits
  /// immediately from RTDB's local cache (if any) then on every change, so
  /// registrations opening/closing appear on the entry page without a
  /// refresh. Same stream style as TournamentService.watchMatches.
  static Stream<Map<String, RegistrationConfig>> watchOpenRegistrations() {
    return FirebaseDatabase.instance.ref('Registrations').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <String, RegistrationConfig>{};
      final out = <String, RegistrationConfig>{};
      value.forEach((regId, node) {
        if (node is! Map) return;
        try {
          final config = RegistrationConfig.fromFirebase(node['Config']);
          if (config != null && config.isOpen) out[regId.toString()] = config;
        } catch (_) {}
      });
      return out;
    });
  }

  /// The ordered question list for a registration ([] on error).
  static Future<List<RegQuestion>> getForm(String regId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Form')
          .get();
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
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/$uid')
          .get();
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
      final snap = await FirebaseDatabase.instance.ref('Users/$uid').get();
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

  /// Individual-path submit:
  ///  1. writes Registrations/{regId}/Submissions/{uid}
  ///     {Path:'individual', Answers, Paid:false, DisplayName, SubmittedAt}
  ///  2. legacy dual-write Sign Ups/{league}/{season}/NotPaid/{uid} =
  ///     displayName (same shape utility.dart's signUpToPlay writes, so the
  ///     Manager Sign Ups page + Add-from-signups picker keep working)
  ///  3. profile write-back for well-known keys.
  /// Returns false when signed out or any write throws.
  static Future<bool> submitIndividual({
    required String regId,
    required RegistrationConfig config,
    required Map<String, dynamic> answers,
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

  /// {teamId: team} for a registration ({} on error). The joiner code page
  /// matches entered codes against this map (matchJoinCode).
  static Future<Map<String, RegTeam>> getTeams(String regId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Teams')
          .get();
      return regTeamsFromNode(snap.value);
    } catch (_) {
      return {};
    }
  }

  /// One team, or null (missing / malformed / error).
  static Future<RegTeam?> getTeam(String regId, String teamId) async {
    if (teamId.isEmpty) return null;
    try {
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Teams/$teamId')
          .get();
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

  /// Captain-path submit:
  ///  1. pushes the pending Team under Registrations/{regId}/Teams
  ///     {Name (hygiene-cleaned), CaptainUid, Status:'pending',
  ///      CodeWaivesPayment:false, CreatedAt}
  ///  2. writes Submission{Path:'captain', TeamId, Paid:false}
  ///  3. legacy dual-write Sign Ups NotPaid + profile write-back — exactly
  ///     like submitIndividual.
  /// Returns false when signed out or any write throws.
  static Future<bool> submitCaptain({
    required String regId,
    required RegistrationConfig config,
    required String teamName,
    required Map<String, dynamic> answers,
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
