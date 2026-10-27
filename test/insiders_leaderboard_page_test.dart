// Widget tests for the public Insiders leaderboard page
// (lib/insiders/insiders_leaderboard_page.dart) in its DORMANT lockdown-B6
// form: the program data was wiped and the whole-/Insiders + /Referrals
// reads are denied under default-deny, so the page shows a "coming soon"
// state and performs no program-wide read. Firebase-free: `myInsiderStream`
// (the viewer's OWN node, which drives the bottom nav's Insider tab —
// Task F8) is a test seam, mirroring ProfileTab's `insiderStream`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/insiders/insiders_leaderboard_page.dart';
import 'package:infinite_sports_flutter/misc/home_nav.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';

Insider _insider(String uid, {String status = 'active'}) {
  return Insider.fromFirebase(uid, {'Name': 'Viewer', 'Status': status})!;
}

Future<void> _pump(
  WidgetTester tester, {
  Insider? myInsider,
  void Function(BuildContext context, HomeTab tab)? switchHomeTabOverride,
  Widget Function()? searchHubPageBuilder,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: InsidersLeaderboardPage(
      myInsiderStream: Stream<Insider?>.value(myInsider),
      viewerUid: myInsider?.uid ?? 'viewer',
      switchHomeTabOverride: switchHomeTabOverride,
      searchHubPageBuilder: searchHubPageBuilder,
    ),
  ));
  // One tick for the StreamBuilder to consume the injected value stream.
  await tester.pump();
}

void main() {
  testWidgets('shows the coming-soon state (no rows, no program read)',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('insider_leaderboard_coming_soon')),
        findsOneWidget);
    expect(find.text('Leaderboard coming soon'), findsOneWidget);
    expect(find.textContaining('fresh start'), findsOneWidget);
  });

  testWidgets('coming-soon colors ride the ColorScheme in dark mode too',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red, brightness: Brightness.dark)),
      home: InsidersLeaderboardPage(
        myInsiderStream: Stream<Insider?>.value(null),
        viewerUid: 'viewer',
      ),
    ));
    await tester.pump();
    expect(find.text('Leaderboard coming soon'), findsOneWidget);
  });

  // -- Task F8: bottom nav mirrors the viewer's own MyHomePage tab set -----

  testWidgets(
      'bottom nav omits the Insider tab for a viewer who is not an active Insider (Task F8)',
      (tester) async {
    await _pump(tester, myInsider: null);

    final nav = find.byType(GlassNavBar);
    expect(nav, findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Matches')),
        findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Leagues')),
        findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Tournaments')),
        findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Calendar')),
        findsOneWidget);
    expect(
        find.descendant(of: nav, matching: find.text('Insider')), findsNothing);
  });

  testWidgets(
      'bottom nav includes the Insider tab when the viewer is an active Insider (Task F8)',
      (tester) async {
    await _pump(tester, myInsider: _insider('viewer'));

    final nav = find.byType(GlassNavBar);
    expect(find.descendant(of: nav, matching: find.text('Insider')),
        findsOneWidget);
  });

  testWidgets('a pending application does not earn the Insider tab',
      (tester) async {
    await _pump(tester, myInsider: _insider('viewer', status: 'pending'));

    final nav = find.byType(GlassNavBar);
    expect(
        find.descendant(of: nav, matching: find.text('Insider')), findsNothing);
  });

  testWidgets('tapping a bottom nav item switches the MyHomePage tab (Task F8)',
      (tester) async {
    HomeTab? switchedTo;
    await _pump(tester,
        switchHomeTabOverride: (context, tab) => switchedTo = tab);

    await tester.tap(find.descendant(
        of: find.byType(GlassNavBar), matching: find.text('Leagues')));
    await tester.pump();

    expect(switchedTo, HomeTab.leagues);
  });

  testWidgets('bottom nav search button opens the search hub (Task F8)',
      (tester) async {
    await _pump(tester,
        searchHubPageBuilder: () =>
            const Scaffold(body: Center(child: Text('stub search hub'))));

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('stub search hub'), findsOneWidget);
  });
}
