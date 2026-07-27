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
}
