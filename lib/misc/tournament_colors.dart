import 'package:flutter/material.dart';

/// Centralized colors + theme-aware helpers for league and tournament
/// headers. Replaces hardcoded literals scattered across 10+ files.
///
/// P4.1 owner request: light-mode headers are plain WHITE boxes, exactly like
/// the app's standard AppBars (appBarTheme uses `colorScheme.surface`); dark
/// mode keeps the FotMob-style near-black grey from P3.2. Foregrounds flip
/// with the background: onSurface text/icons on white, white on the grey.
class TournamentColors {
  TournamentColors._();

  /// Dark-mode header — flat FotMob-style near-black neutral grey (P3.2
  /// owner request: colored headers glow too much on the dark surface).
  static const Color headerDark = Color(0xFF1C1C1E);

  /// Slightly lighter grey, bottom stop of the (subtle) dark-mode gradient.
  static const Color headerDarkAlt = Color(0xFF26262A);

  /// Gold — used for champion badges, trophy icons, prize highlights on
  /// dark/colored surfaces. On the white light-mode header use
  /// [championGold] instead (classic gold vanishes on white).
  static const Color gold = Color(0xFFFFD700);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Flat header/app-bar color for league + tournament screens: the app's
  /// standard white surface in light mode (P4.1), FotMob-style dark grey in
  /// dark mode. Pair with [headerForeground] for text/icons.
  static Color headerBackground(BuildContext context) =>
      _isDark(context) ? headerDark : Theme.of(context).colorScheme.surface;

  /// Header gradient (top → bottom): collapses to the flat white surface in
  /// light mode (P4.1), stays the subtle near-flat grey pair in dark mode.
  static LinearGradient headerGradient(BuildContext context) {
    if (_isDark(context)) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [headerDark, headerDarkAlt],
      );
    }
    final surface = Theme.of(context).colorScheme.surface;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [surface, surface],
    );
  }

  /// Primary header foreground: dark onSurface text/icons on the white
  /// light-mode header, white on the dark-mode grey. (P2.1 A3's "always
  /// visible back arrow" now means dark arrows on white, white on grey.)
  static Color headerForeground(BuildContext context) => _isDark(context)
      ? Colors.white
      : Theme.of(context).colorScheme.onSurface;

  /// Secondary header foreground (~70%): subtitles, dates, muted chips —
  /// the light-mode counterpart of the old `Colors.white70`.
  static Color headerForegroundMuted(BuildContext context) => _isDark(context)
      ? Colors.white70
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);

  /// Faint contained fill behind header chips / crest circles — the old
  /// `Colors.white` @ 15% overlay, which disappears on a white header.
  static Color headerChipFill(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.15)
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);

  /// Champion-trophy gold that stays readable on the header: classic gold
  /// on the dark grey, darker goldenrod on the white light-mode header.
  static Color championGold(BuildContext context) =>
      _isDark(context) ? gold : const Color(0xFFB8860B);

  /// Bottom hairline for plain-Container skeleton/loading headers so the
  /// white light-mode box doesn't melt into the white page body. The real
  /// SliverAppBars get their separation from the app-wide
  /// scrolledUnderElevation instead; dark grey headers need none.
  static Border? headerHairline(BuildContext context) => _isDark(context)
      ? null
      : Border(
          bottom: BorderSide(
              color: Theme.of(context).dividerColor, width: 0.5));
}
