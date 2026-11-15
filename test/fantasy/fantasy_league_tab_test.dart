import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_league_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

void main() {
  final now = DateTime(2026, 7, 10);

  List<TournamentMatch> games() => leagueMatchesFromDateNode({
        '07032026': [
          {
            'team1': 'Babylon',
            'team2': 'Nineveh',
            'team1score': 2,
            'team2score': 1,
            'status': 2,
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

  List<TournamentTeam> standings() => leagueStandingsFromTeamsNode('Futsal', {
        'Babylon': {
          'Wins': 3, 'Draws': 0, 'Losses': 5, 'GP': 8, 'GS': 9, 'GC': 20, //
          'GD': -11, 'Points': 9,
        },
        'Nineveh': {
          'Wins': 7, 'Draws': 1, 'Losses': 0, 'GP': 8, 'GS': 30, 'GC': 5, //
          'GD': 25, 'Points': 22,
        },
      }, const {});

  late StreamController<List<TournamentMatch>> gamesC;
  late StreamController<List<TournamentTeam>> tableC;
  late void Function(Map<String, String>) reportLogos;
  late List<TournamentMatch> opened;
  late List<String> openedTeams;
  late int gamesSubscribes;

  FantasyLeagueSeams seams() => FantasyLeagueSeams(
        gamesStates: gamesC.stream,
        standingsFor: (_) => tableC.stream,
        watchLogos: (onLogos) {
          reportLogos = onLogos;
          return () {};
        },
        openMatch: (_, m) => opened.add(m),
        openTeam: (_, name) => openedTeams.add(name),
      );

  setUp(() {
    FantasyLeagueGamesFeed.clearSessionCache();
    FantasyLeagueTableFeed.clearSessionCache();
    gamesC = StreamController<List<TournamentMatch>>.broadcast(
        onListen: () => gamesSubscribes++);
    tableC = StreamController<List<TournamentTeam>>.broadcast();
    opened = [];
    openedTeams = [];
    gamesSubscribes = 0;
    reportLogos = (_) {};
    addTearDown(() {
      gamesC.close();
      tableC.close();
    });
  });

  Widget host({
    String season = '15',
    FantasyLeagueSeams? s,
    Brightness brightness = Brightness.light,
  }) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness, useMaterial3: true),
        home: Scaffold(
          body: FantasyLeagueTab(
            sport: 'Futsal',
            season: season,
            seams: s ?? seams(),
            now: now,
          ),
        ),
      );

  Future<void> loadAll(WidgetTester tester) async {
    await tester.pumpWidget(host());
    reportLogos(const {});
    gamesC.add(games());
    tableC.add(standings());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'skeleton until games AND table have answered, then one reveal with '
      'crests', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(const ValueKey('league_tab_skeleton')), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);

    gamesC.add(games());
    await tester.pump();
    // The table has not answered yet: still the skeleton, no card.
    expect(find.byKey(const ValueKey('league_tab_skeleton')), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);

    reportLogos(const {});
    tableC.add(standings());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('league_tab_skeleton')), findsNothing);
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Fixtures'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    // The day strip: day numbers 3 and 17.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('tapping a card calls openMatch with that game', (tester) async {
    await loadAll(tester);
    await tester.tap(find.text('Ashur'));
    await tester.pump();
    expect(opened.map((m) => '${m.team1Id} v ${m.team2Id}'), ['Ashur v Akkad']);
  });

  testWidgets(
      'Table shows the standings, and a row calls openTeam with the team name',
      (tester) async {
    await loadAll(tester);
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.text('Nineveh'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    // Only the chosen view is mounted.
    expect(find.text('Ashur'), findsNothing);
    await tester.tap(find.text('Babylon'));
    await tester.pump();
    expect(openedTeams, ['Babylon']);
  });

  testWidgets('pick a day, switch to Table and back: the same day is selected',
      (tester) async {
    await loadAll(tester);
    expect(find.text('Ashur'), findsOneWidget); // default: next day
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('Babylon'), findsWidgets);
    expect(find.text('Ashur'), findsNothing);

    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixtures'));
    await tester.pumpAndSettle();
    expect(find.text('Ashur'), findsNothing);
    expect(find.text('Babylon'), findsWidgets);
  });

  testWidgets(
      'games fail with nothing loaded: "Couldn\'t load the league", never '
      '"No fixtures available"; Try again re-subscribes', (tester) async {
    await tester.pumpWidget(host());
    reportLogos(const {});
    tableC.add(standings());
    gamesC.addError(StateError('boom'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the league"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No fixtures available'), findsNothing);

    final before = gamesSubscribes;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(gamesSubscribes, greaterThan(before));
    gamesC.add(games());
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the league"), findsNothing);
    expect(find.text('Ashur'), findsOneWidget);
  });

  testWidgets('standings fail: the Table shows the error while Fixtures works',
      (tester) async {
    await tester.pumpWidget(host());
    reportLogos(const {});
    gamesC.add(games());
    tableC.addError(StateError('boom'));
    await tester.pumpAndSettle();
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text("Couldn't load the league"), findsNothing);

    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the league"), findsOneWidget);
    expect(find.text('Table not yet available'), findsNothing);
  });

  testWidgets('no games and an empty table show the existing empty states',
      (tester) async {
    await tester.pumpWidget(host());
    reportLogos(const {});
    gamesC.add(const []);
    tableC.add(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('league_tab_skeleton')), findsNothing);
    expect(find.text('No fixtures available'), findsOneWidget);
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.text('Table not yet available'), findsOneWidget);
  });

  testWidgets('a new season drops the old games and table and loads the new',
      (tester) async {
    final seasonsAsked = <String>[];
    final controllers = <String, StreamController<List<TournamentMatch>>>{};
    var season = '15';
    FantasyLeagueSeams perSeason() => FantasyLeagueSeams(
          loadStartHour: () async => 8,
          leagueGamesFor: (_) {
            seasonsAsked.add(season);
            return (controllers[season] ??=
                    StreamController<List<TournamentMatch>>.broadcast())
                .stream;
          },
          standingsFor: (_) => tableC.stream,
          watchLogos: (onLogos) {
            reportLogos = onLogos;
            return () {};
          },
        );
    final s = perSeason();
    await tester.pumpWidget(host(season: '15', s: s));
    await tester.pump();
    reportLogos(const {});
    controllers['15']!.add(games());
    tableC.add(standings());
    await tester.pumpAndSettle();
    expect(find.text('Ashur'), findsOneWidget);

    season = '16';
    await tester.pumpWidget(host(season: '16', s: s));
    await tester.pump(const Duration(milliseconds: 400)); // the fade-out
    expect(find.byKey(const ValueKey('league_tab_skeleton')), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
    expect(seasonsAsked, containsAllInOrder(['15', '16']));
    reportLogos(const {});
    controllers['16']!.add(leagueMatchesFromDateNode({
      '07242026': [
        {
          'team1': 'Lagash',
          'team2': 'Uruk',
          'team1score': 0,
          'team2score': 0,
          'status': 0,
        },
      ],
    }));
    tableC.add(standings());
    await tester.pumpAndSettle();
    expect(find.text('Lagash'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
    for (final c in controllers.values) {
      await c.close();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('360 px, ${brightness.name}: no overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(brightness: brightness));
      reportLogos(const {});
      gamesC.add(games());
      tableC.add(standings());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
