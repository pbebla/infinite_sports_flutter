// Fresh reads, Task 4 — the most-opened all-one-shot screens (survey list C)
// repaint IN PLACE when a lingering refreshing read reports a newer server
// value while they are open: one setState, no skeleton, the rest of the
// screen kept. Driven through FreshReads.debugReportNewer (what a lingering
// listener reports) and the screens' loader seams.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/futsalteaminfo.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/model/teaminfo.dart';
import 'package:infinite_sports_flutter/table.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

FutsalPlayer _p(String name, int goals) => FutsalPlayer()
  ..name = name
  ..number = '9'
  ..goals = goals;

FutsalTeamInfo _t(int points) => FutsalTeamInfo()..points = points;

void main() {
  testWidgets('top-bar Leaderboard repaints in place on newer Line Ups',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var goals = 3;
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
      home: LeaderboardPage(
        sport: 'Futsal',
        season: '16',
        playersLoader: () async {
          loads++;
          return <Player>[_p('Bruno', goals)];
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(loads, 1);

    // Another season's lineups: nothing happens.
    FreshReads.debugReportNewer('Futsal/15/Line Ups', {});
    await tester.pump();
    expect(loads, 1);

    goals = 7;
    FreshReads.debugReportNewer('/Futsal/16//Line Ups', {});
    await tester.pump(); // the re-read resolves
    expect(find.byType(SkeletonList), findsNothing, reason: 'no reload flash');
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(loads, 2);

    // A plain rebuild no longer re-reads (the future is kept).
    await tester.pumpWidget(MaterialApp(
      home: LeaderboardPage(
        sport: 'Futsal',
        season: '16',
        playersLoader: () async {
          loads++;
          return <Player>[_p('Bruno', goals)];
        },
      ),
    ));
    await tester.pump();
    expect(loads, 2);
  });

  testWidgets('top-bar Table repaints in place on newer Teams', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var points = 10;
    await tester.pumpWidget(MaterialApp(
      home: TablePage(
        sport: 'Futsal',
        season: '16',
        tableLoader: () async => <String, TeamInfo>{'Lions': _t(points)},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);

    points = 13;
    FreshReads.debugReportNewer('Futsal/16/Teams', {});
    await tester.pump();
    expect(find.byType(SkeletonList), findsNothing);
    await tester.pump();
    expect(find.text('13'), findsOneWidget);
    expect(find.text('10'), findsNothing);
  });

  test('the source paths the screens follow', () {
    expect(leaderboardSourcePath('Futsal', '16'), 'Futsal/16/Line Ups');
    expect(leaderboardSourcePath('AFC San Jose', 'S1'),
        'AFC San Jose/Seasons/S1/Roster');
    expect(tableSourcePath('Basketball', '4'), 'Basketball/4/Teams');
    expect(
        tableSourcePath('AFC San Jose', 'S1'), 'AFC San Jose/Seasons/S1/Table');
  });

  testWidgets('a failed read shows a plain message, not a crash',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: LeaderboardPage(
        sport: 'Futsal',
        season: '16',
        playersLoader: () async => throw StateError('no answer'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this right now. Try again later."),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
      home: TablePage(
        sport: 'Futsal',
        season: '16',
        tableLoader: () async => throw StateError('no answer'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this right now. Try again later."),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'second review Minor 4: a newer value during an in-flight refresh is '
      'not dropped (one queued refresh shows the latest)', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var goals = 1;
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
      home: LeaderboardPage(
        sport: 'Futsal',
        season: '16',
        playersLoader: () async {
          loads++;
          final g = goals; // the value at read time
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return <Player>[_p('Bruno', g)];
        },
      ),
    ));
    await tester.pumpAndSettle();
    goals = 2;
    FreshReads.debugReportNewer('Futsal/16/Line Ups', {});
    await tester.pump(const Duration(milliseconds: 10)); // refresh in flight
    goals = 3;
    FreshReads.debugReportNewer('Futsal/16/Line Ups', {});
    FreshReads.debugReportNewer('Futsal/16/Line Ups', {}); // coalesced
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(loads, 3, reason: 'first load + 1 refresh + exactly 1 queued');
  });
}
