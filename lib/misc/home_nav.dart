import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';

/// The bottom-nav tab identifiers for MyHomePage's IndexedStack, in display
/// order. `insider` is appended only for an approved (Status=='active')
/// Insider — spec §7 "the app visibly unlocks" the 5th tab the moment
/// approval lands, and it disappears again the moment status stops being
/// active (Task F4).
enum HomeTab { matches, leagues, tournaments, calendar, insider }

/// Pure tab-list builder (Task F4) — kept out of MyHomePage (and out of
/// main.dart entirely) so it's unit-testable without pumping the whole
/// entangled home screen, which reaches for Firebase/mainContext globals at
/// build time. [isActiveInsider] mirrors
/// `InsiderService.watchMyInsider(uid)` emitting a Status=='active' node.
///
/// Everyone else — signed-in but not an Insider, pending/declined/suspended
/// Insiders, or before the stream's first emission — sees exactly the 4
/// tabs the app shipped with before Infinite Insiders.
List<HomeTab> navItemsFor(bool isActiveInsider) => [
      HomeTab.matches,
      HomeTab.leagues,
      HomeTab.tournaments,
      HomeTab.calendar,
      if (isActiveInsider) HomeTab.insider,
    ];

/// The glass nav bar destination (icon/label) for [tab].
GlassNavDestination destinationFor(HomeTab tab) {
  switch (tab) {
    case HomeTab.matches:
      return const GlassNavDestination(
          icon: ImageIcon(AssetImage('assets/scores.png')), label: 'Matches');
    case HomeTab.leagues:
      return const GlassNavDestination(
          icon: ImageIcon(AssetImage('assets/leagues.png')), label: 'Leagues');
    case HomeTab.tournaments:
      return const GlassNavDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: 'Tournaments',
      );
    case HomeTab.calendar:
      return const GlassNavDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Calendar',
      );
    case HomeTab.insider:
      return const GlassNavDestination(
        icon: Icon(Icons.diamond_outlined),
        selectedIcon: Icon(Icons.diamond),
        label: 'Insider',
      );
  }
}

/// Display title for [tab] — Matches keeps whatever the live-scores title
/// currently is (season/sport specific, set via `setLiveScoreTitle`); every
/// other tab (including Insider) has a fixed title.
String titleFor(HomeTab tab, String liveScoresTitle) {
  switch (tab) {
    case HomeTab.matches:
      return liveScoresTitle;
    case HomeTab.leagues:
      return 'Leagues';
    case HomeTab.tournaments:
      return 'Tournaments';
    case HomeTab.calendar:
      return 'Calendar';
    case HomeTab.insider:
      return 'Insider';
  }
}
