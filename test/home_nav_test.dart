// Pure-logic tests for MyHomePage's bottom-nav tab builder
// (lib/misc/home_nav.dart, Task F4). MyHomePage itself is too entangled with
// Firebase/global-context singletons to widget-test cheaply, so per the F4
// plan this pure fn is extracted and tested directly instead — no
// pumpWidget needed.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §7 —
// "On approval, a 5th bottom-nav tab appears" (Insider-only, appended after
// Calendar); non-Insiders see exactly today's 4 tabs.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/misc/home_nav.dart';

void main() {
  group('navItemsFor', () {
    test('non-insider (or not-yet-loaded) sees exactly the 4 existing tabs', () {
      final tabs = navItemsFor(false);
      expect(tabs, [
        HomeTab.matches,
        HomeTab.leagues,
        HomeTab.tournaments,
        HomeTab.calendar,
      ]);
    });

    test('an active Insider gets a 5th tab appended after Calendar', () {
      final tabs = navItemsFor(true);
      expect(tabs, [
        HomeTab.matches,
        HomeTab.leagues,
        HomeTab.tournaments,
        HomeTab.calendar,
        HomeTab.insider,
      ]);
    });
  });

  group('destinationFor', () {
    test('every tab has a distinct, correct label', () {
      expect(destinationFor(HomeTab.matches).label, 'Matches');
      expect(destinationFor(HomeTab.leagues).label, 'Leagues');
      expect(destinationFor(HomeTab.tournaments).label, 'Tournaments');
      expect(destinationFor(HomeTab.calendar).label, 'Calendar');
      expect(destinationFor(HomeTab.insider).label, 'Insider');
    });
  });

  group('titleFor', () {
    test('Matches tab title tracks the live live-scores title', () {
      expect(titleFor(HomeTab.matches, 'Week 3'), 'Week 3');
    });
    test('every other tab has a fixed title', () {
      expect(titleFor(HomeTab.leagues, 'Week 3'), 'Leagues');
      expect(titleFor(HomeTab.tournaments, 'Week 3'), 'Tournaments');
      expect(titleFor(HomeTab.calendar, 'Week 3'), 'Calendar');
      expect(titleFor(HomeTab.insider, 'Week 3'), 'Insider');
    });
  });
}
