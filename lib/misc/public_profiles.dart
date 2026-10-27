// PublicProfiles/<uid> — the server-maintained public mirror of Users
// (DB security lockdown, docs/superpowers/specs/
// 2026-10-27-db-security-lockdown-design.md §4). Once the rules flip,
// Users/<uid> is readable by its OWNER only; every other-user read goes
// through this node instead. The mirror carries exactly the whitelisted
// keys the trigger projects (functions/src/lib/public_mirrors.ts):
// 'First Name', 'Last Name', 'ProfileUrl', 'Played', 'TournamentsPlayed',
// 'Awards', 'Information', 'ProfileCompleted' — never DOB/phone/token/
// email/Date Joined.
//
// iOS parity (owner directive): reads here are onValue streams or once()
// only — RTDB get() is banned repo-wide (firebase-ios-sdk returns
// wrong-node/empty data for overlapping one-shot get()s).
//
// Parsing is pure (no Firebase objects) so test/public_profiles_test.dart
// covers it without a Firebase app, activity_entry.dart-style.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// One user's public identity + career data, as mirrored.
class PublicProfile {
  final String uid;
  final String firstName;
  final String lastName;
  final String profileUrl;

  /// Positions/height/age — same shape as `Users/<uid>/Information`.
  final Map<dynamic, dynamic> information;

  /// League history — same shape as `Users/<uid>/Played`
  /// ({sport: {season: team}}).
  final Map<dynamic, dynamic> played;

  /// Tournament index — same shape as `Users/<uid>/TournamentsPlayed`
  /// ({tournamentId: true}).
  final Map<dynamic, dynamic> tournamentsPlayed;

  /// Trophy cabinet — same shape as `Users/<uid>/Awards`.
  final Map<dynamic, dynamic> awards;

  final bool profileCompleted;

  const PublicProfile({
    required this.uid,
    this.firstName = '',
    this.lastName = '',
    this.profileUrl = '',
    this.information = const {},
    this.played = const {},
    this.tournamentsPlayed = const {},
    this.awards = const {},
    this.profileCompleted = false,
  });

  /// "First Last" (either half may be absent), '' when both are.
  String get fullName => '$firstName $lastName'.trim();

  /// Defensive parse of one `PublicProfiles/<uid>` node; null for a missing
  /// or malformed node (anything that isn't a Map — including the List an
  /// RTDB array coercion could produce).
  static PublicProfile? fromNode(String uid, Object? raw) {
    if (uid.isEmpty || raw is! Map) return null;
    Map<dynamic, dynamic> mapOf(Object? v) =>
        v is Map ? v : const <dynamic, dynamic>{};
    return PublicProfile(
      uid: uid,
      firstName: raw['First Name']?.toString() ?? '',
      lastName: raw['Last Name']?.toString() ?? '',
      profileUrl: raw['ProfileUrl']?.toString() ?? '',
      information: mapOf(raw['Information']),
      played: mapOf(raw['Played']),
      tournamentsPlayed: mapOf(raw['TournamentsPlayed']),
      awards: mapOf(raw['Awards']),
      profileCompleted: raw['ProfileCompleted'] == true,
    );
  }
}

/// Parses the whole PublicProfiles root into {uid: profile}, skipping
/// malformed children. Defensive about RTDB's List coercion: uid keys are
/// never dense integers in real data, but a List here must not crash —
/// its non-null Map entries parse under their index as the key.
Map<String, PublicProfile> publicProfilesFromNode(Object? raw) {
  final out = <String, PublicProfile>{};
  if (raw is Map) {
    raw.forEach((uid, node) {
      final profile = PublicProfile.fromNode(uid.toString(), node);
      if (profile != null) out[uid.toString()] = profile;
    });
  } else if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      final profile = PublicProfile.fromNode('$i', raw[i]);
      if (profile != null) out['$i'] = profile;
    }
  }
  return out;
}

/// True when [uid] is the signed-in user's own uid. Defensive: without a
/// Firebase app (widget tests) or signed out, every uid is "not self", so
/// callers degrade to the public-mirror path instead of throwing.
bool isSignedInUid(String uid) {
  if (uid.isEmpty) return false;
  try {
    return FirebaseAuth.instance.currentUser?.uid == uid;
  } catch (_) {
    return false;
  }
}

/// The node a profile screen reads [uid]'s data from: the private Users
/// node for the viewer's OWN profile (full fidelity, always readable by
/// its owner), the public mirror for everyone else.
String profileNodePathFor(String uid) =>
    isSignedInUid(uid) ? 'Users/$uid' : 'PublicProfiles/$uid';

/// Firebase reads over the mirror — once()/onValue only (iOS parity).
class PublicProfiles {
  static DatabaseReference _root() =>
      FirebaseDatabase.instance.ref('PublicProfiles');

  /// One-shot {uid: profile} of the whole mirror ({} on error) — the
  /// search index / event-attendee bulk read.
  static Future<Map<String, PublicProfile>> getAllOnce() async {
    try {
      final event = await _root().once();
      return publicProfilesFromNode(event.snapshot.value);
    } catch (_) {
      return {};
    }
  }

  /// One user's mirrored ProfileUrl ('' when absent/error) — roster photo
  /// enrichment.
  static Future<String> getProfileUrlOnce(String uid) async {
    try {
      final event = await _root().child('$uid/ProfileUrl').once();
      return event.snapshot.value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}
