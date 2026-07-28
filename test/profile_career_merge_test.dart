// PR #10: the profile's Stats and Career tabs are merged into ONE "Career"
// tab (the former Stats tab, enhanced). Covered here:
//   1. the tab bar is exactly Profile | Career,
//   2. each competition header carries team name (+ logo when resolvable)
//      before the position,
//   3. the picker's "Show all" option stacks every competition on one page
//      while single-competition selection keeps working.
// Firebase-free: ProfilePage uses the loadOverride seam (mirrors ProfileTab's
// insiderStream seam); StatsTab is pumped directly with fixtures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';
import 'package:infinite_sports_flutter/profile/stats_tab.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

Future<void> _pumpStats(
    WidgetTester tester, List<CompetitionStats> comps) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: StatsTab(competitions: comps)),
  ));
  await tester.pump();
}

const _futsal = CompetitionStats(
  label: 'Futsal · Season 15',
  sport: 'Futsal',
  position: 'Defender',
  team: 'Lamassu',
  stats: {'goals': 7, 'assists': 2},
  sortKey: 15,
);

const _basketball = CompetitionStats(
  label: 'Basketball · Season 5',
  sport: 'Basketball',
  position: 'Guard',
  team: 'Akkad',
  stats: {'points': 22},
  sortKey: 5,
);

void main() {
  group('ProfilePage tab bar', () {
    testWidgets('shows exactly Profile and Career', (tester) async {
      // Empty uid keeps ProfileTab's Insider box (the only other Firebase
      // touchpoint) dormant.
      await tester.pumpWidget(MaterialApp(
        home: ProfilePage(uid: '', loadOverride: () async => 1),
      ));
      await tester.pump(); // skeleton frame
      await tester.pump(); // loadOverride resolved → tabs

      expect(find.byType(Tab), findsNWidgets(2));
      expect(find.widgetWithText(Tab, 'Profile'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Career'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Stats'), findsNothing);
    });
  });

  group('Competition header team identity', () {
    testWidgets('renders team name before the position', (tester) async {
      await _pumpStats(tester, [_futsal]);

      expect(find.text('Lamassu · Defender'), findsOneWidget);
      // No logo URL resolved → name only, no broken image / fallback shield.
      expect(find.byType(TeamLogo), findsNothing);
    });

    testWidgets('renders the team logo when a URL resolved', (tester) async {
      const comp = CompetitionStats(
        label: 'Futsal · Season 15',
        sport: 'Futsal',
        position: 'Defender',
        team: 'Lamassu',
        teamLogoUrl: 'https://example.com/lamassu.png',
        stats: {'goals': 7},
      );
      await _pumpStats(tester, [comp]);

      expect(find.text('Lamassu · Defender'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is TeamLogo && w.url == 'https://example.com/lamassu.png'),
        findsOneWidget,
      );
    });

    testWidgets('no team recorded → old position-only line', (tester) async {
      const comp = CompetitionStats(
        label: 'Futsal · Season 15',
        sport: 'Futsal',
        position: 'Defender',
        stats: {'goals': 7},
      );
      await _pumpStats(tester, [comp]);

      expect(find.text('Defender'), findsOneWidget);
      expect(find.byType(TeamLogo), findsNothing);
    });
  });

  group('Show all', () {
    testWidgets('defaults to only the first (most recent) competition',
        (tester) async {
      await _pumpStats(tester, [_futsal, _basketball]);

      // Latest appears twice: selector header + card title.
      expect(find.text('Futsal · Season 15'), findsNWidgets(2));
      expect(find.text('Basketball · Season 5'), findsNothing);
    });

    testWidgets('picker option renders all competitions stacked',
        (tester) async {
      await _pumpStats(tester, [_futsal, _basketball]);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('All competitions'), findsOneWidget);
      expect(find.text('Futsal · Season 15'), findsOneWidget);
      expect(find.text('Basketball · Season 5'), findsOneWidget);
      // Each card keeps its own team + position header line.
      expect(find.text('Lamassu · Defender'), findsOneWidget);
      expect(find.text('Akkad · Guard'), findsOneWidget);
    });

    testWidgets('single-competition selection still works after Show all',
        (tester) async {
      await _pumpStats(tester, [_futsal, _basketball]);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(ListTile, 'Basketball · Season 5'));
      await tester.pumpAndSettle();

      // Header + card for the picked competition; the other one is gone.
      expect(find.text('Basketball · Season 5'), findsNWidgets(2));
      expect(find.text('Futsal · Season 15'), findsNothing);
    });
  });
}
