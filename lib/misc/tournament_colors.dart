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
  /// LIGHT-mode value only — screens should use [headerBackground] /
  /// [headerGradient] so dark mode gets the FotMob-style grey instead.
  static const Color headerAccent = Color(0xFF1A237E);

  /// Lighter navy used as the bottom stop of light-mode header gradients.
  static const Color headerAccentAlt = Color(0xFF283593);

  /// Dark-mode header — flat FotMob-style near-black neutral grey (P3.2
  /// owner request: navy headers glow too much on the dark surface).
  static const Color headerDark = Color(0xFF1C1C1E);

  /// Slightly lighter grey, bottom stop of the (subtle) dark-mode gradient.
  static const Color headerDarkAlt = Color(0xFF26262A);

  /// Gold — used for champion badges, trophy icons, prize highlights.
  static const Color gold = Color(0xFFFFD700);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Flat header/app-bar color for league + tournament screens:
  /// navy in light mode, FotMob-style dark grey in dark mode. White
  /// foreground text/icons stay legible on both.
  static Color headerBackground(BuildContext context) =>
      _isDark(context) ? headerDark : headerAccent;

  /// Header gradient (top → bottom): the classic navy pair in light mode,
  /// a subtle near-flat grey pair in dark mode.
  static LinearGradient headerGradient(BuildContext context) =>
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _isDark(context)
            ? const [headerDark, headerDarkAlt]
            : const [headerAccent, headerAccentAlt],
      );
}
