// Widget smoke tests for the app's Firebase-free presentational widgets.
//
// Note: the app root `MyApp` cannot be smoke-tested in a plain `flutter test`
// run. Its build reads `Provider.of<ThemeProvider>` (so it needs that ancestor)
// and `MyHomePage.initState` immediately calls into Firebase
// (FirebaseAuth.instance.currentUser, Realtime Database queries) which isn't
// initialized in unit tests. Instead we smoke-test the presentational widgets
// that make up the Tournaments UI, which build without any backend.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/tournament_day_view.dart';

void main() {
  testWidgets('FixturesTab shows an empty state when there are no matches',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FixturesTab(
            matches: [],
            teams: {},
            rosters: {},
            tournamentId: 't1',
            sport: 'Soccer',
          ),
        ),
      ),
    );

    expect(find.text('No fixtures available'), findsOneWidget);
  });

  testWidgets('TournamentDayView renders one day pill per distinct match day',
      (tester) async {
    final matches = [
      TournamentMatch.fromFirebase('m1', {
        'Date': '05292026',
        'Stage': 'Group Stage',
        'Label': 'Group Stage',
      }),
      TournamentMatch.fromFirebase('m2', {
        'Date': '06012026',
        'Stage': 'Group Stage',
        'Label': 'Group Stage',
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentDayView(
            matches: matches,
            teams: const {},
            rosters: const {},
            tournamentId: 't1',
            sport: 'Soccer',
            initialDay: '05292026',
          ),
        ),
      ),
    );
    // Let the post-frame scroll-into-view callback run.
    await tester.pump();

    // Two distinct days -> the strip shows both day-of-month numbers.
    expect(find.text('29'), findsOneWidget); // May 29
    expect(find.text('1'), findsOneWidget); // June 1
  });
}
