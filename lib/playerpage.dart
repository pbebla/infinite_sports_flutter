import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

/// Thin wrapper that delegates to [ProfilePage].
///
/// All existing callers (navbar.dart, etc.) continue to use
/// `PlayerPage(uid: uid)` unchanged — this class simply forwards to the
/// new tabbed profile.
class PlayerPage extends StatelessWidget {
  final String uid;

  const PlayerPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) => ProfilePage(uid: uid);
}
