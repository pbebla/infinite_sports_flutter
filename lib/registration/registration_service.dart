import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// Fan-side reads/writes for the new registration engine (L1a: individual
/// path only). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — only
/// the Manager's markPaid does.
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

  /// The ordered question list for a registration ([] on error).
  static Future<List<RegQuestion>> getForm(String regId) async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('Registrations/$regId/Form').get();
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
    if (infoUpdates.isNotEmpty) await root.child('Information').update(infoUpdates);
  }
}
