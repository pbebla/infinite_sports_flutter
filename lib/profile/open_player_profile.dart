import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

/// Identifies a player to open a profile for. [uid] is the Firebase Auth uid
/// when known (full profile); otherwise only [displayName] is available
/// (limited, not-linked profile).
class PlayerIdentity {
  final String? uid;
  final String displayName;
  const PlayerIdentity({this.uid, required this.displayName});

  bool get isLinked => uid != null && uid!.trim().isNotEmpty;
}

/// Opens the player profile. Linked → full ProfilePage; unlinked → limited.
Future<void> openPlayerProfile(BuildContext context, PlayerIdentity player) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => player.isLinked
        ? ProfilePage(uid: player.uid!.trim())
        : ProfilePage.limited(name: player.displayName),
  ));
}

/// Convenience overload from raw values.
Future<void> openPlayerProfileById(
  BuildContext context, {
  String? uid,
  required String name,
}) {
  return openPlayerProfile(context, PlayerIdentity(uid: uid, displayName: name));
}
