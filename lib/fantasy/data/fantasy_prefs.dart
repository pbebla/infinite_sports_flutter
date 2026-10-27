// Fantasy hub preferences (P3a Task 4): the first-open walkthrough flag.
// shared_preferences-backed; read errors fail CLOSED (treat as seen) so a
// broken prefs store can never trap users in the intro.

import 'package:shared_preferences/shared_preferences.dart';

class FantasyPrefs {
  FantasyPrefs._();

  static const String walkthroughSeenKey = 'fantasyWalkthroughSeen';

  static Future<bool> hasSeenWalkthrough() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(walkthroughSeenKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markWalkthroughSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(walkthroughSeenKey, true);
    } catch (_) {
      // Best effort — worst case the intro shows once more.
    }
  }
}
