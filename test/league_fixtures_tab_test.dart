import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_fixtures_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  final now = DateTime(2026, 7, 10); // reference "today"

  List<TournamentMatch> twoDayMatches({int firstDayStatus = 2}) =>
      leagueMatchesFromDateNode({
        '07032026': [
          {
            'team1': 'Babylon',
            'team2': 'Nineveh',
            'team1score': 2,
            'team2score': 1,
            'status': firstDayStatus,
          },
        ],
        '07172026': [
          {
            'team1': 'Ashur',
            'team2': 'Akkad',
            'team1score': 0,
            'team2score': 0,
            'status': 0,
          },
        ],
      });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows date boxes and only the default day\'s matches',
      (tester) async {
    await tester.pumpWidget(wrap(LeagueFixturesTab(
      matches: twoDayMatches(),
      teams: const {},
      rosters: const {},
      sport: 'Futsal',
      now: now,
    )));
    // One box per game date: day numbers 3 and 17 (July).
    expect(find.text('3'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    // Default = nearest upcoming day (Jul 17): only that day's game shows.
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Babylon'), findsNothing);
  });

  testWidgets('tapping a date box switches to that day\'s matches',
      (tester) async {
    await tester.pumpWidget(wrap(LeagueFixturesTab(
      matches: twoDayMatches(),
      teams: const {},
      rosters: const {},
      sport: 'Futsal',
      now: now,
    )));
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('Babylon'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
  });

  testWidgets('a live day is selected over the nearest upcoming day',
      (tester) async {
    await tester.pumpWidget(wrap(LeagueFixturesTab(
      matches: twoDayMatches(firstDayStatus: 1), // Jul 3 game is LIVE
      teams: const {},
      rosters: const {},
      sport: 'Futsal',
      now: now,
    )));
    expect(find.text('Babylon'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
  });

  testWidgets('all days in the past fall back to the last day', (tester) async {
    await tester.pumpWidget(wrap(LeagueFixturesTab(
      matches: twoDayMatches(),
      teams: const {},
      rosters: const {},
      sport: 'Futsal',
      now: DateTime(2026, 8, 1),
    )));
    // Last day (Jul 17) selected.
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Babylon'), findsNothing);
  });

  testWidgets('tapping a team name opens that match, not a team page',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(wrap(LeagueFixturesTab(
      matches: twoDayMatches(),
      teams: {'Ashur': leagueTeamStub('Ashur', null)},
      rosters: const {},
      sport: 'Futsal',
      now: now,
      onMatchTap: (match) => tapped.add('${match.team1Id} v ${match.team2Id}'),
    )));
    await tester.tap(find.text('Ashur'));
    await tester.pump();
    expect(tapped, ['Ashur v Akkad']);
  });

  testWidgets(
      'with onDayPicked the owner holds the day: a tap calls it and the shown '
      'day follows pickedDay', (tester) async {
    final picks = <String>[];
    Widget build(String? picked) => wrap(LeagueFixturesTab(
          matches: twoDayMatches(),
          teams: const {},
          rosters: const {},
          sport: 'Futsal',
          now: now,
          pickedDay: picked,
          onDayPicked: picks.add,
        ));
    await tester.pumpWidget(build(null));
    expect(find.text('Ashur'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(picks, ['07032026']);
    // The owner did not change pickedDay: the shown day does not move.
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Babylon'), findsNothing);
    await tester.pumpWidget(build('07032026'));
    expect(find.text('Babylon'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
  });

  testWidgets('without onDayPicked a tapped day sticks as before',
      (tester) async {
    await tester.pumpWidget(wrap(LeagueFixturesTab(
      matches: twoDayMatches(),
      teams: const {},
      rosters: const {},
      sport: 'Futsal',
      now: now,
    )));
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('Babylon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Babylon'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
  });
}
