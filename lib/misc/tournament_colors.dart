import 'package:flutter/material.dart';

/// Centralized color constants for tournament screens.
/// Replaces hardcoded literals scattered across 10+ files.
///
/// Note: these are intentionally NOT pulled from `Theme.of(context)` —
/// tournament screens use a distinct visual identity (navy header) that
/// is separate from the app's brand-red theme on purpose.
class TournamentColors {
  TournamentColors._();

  /// Header accent — navy, used for app bars and headers in tournament
  /// screens. Distinguishes tournament context from league screens.
  static const Color headerAccent = Color(0xFF1A237E);

  /// Gold — used for champion badges, trophy icons, prize highlights.
  static const Color gold = Color(0xFFFFD700);
}
