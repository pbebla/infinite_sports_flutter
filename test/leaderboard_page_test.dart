import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';

/// Release report #5/#6: the Futsal stats leaderboard at phone width — the
/// "S" column was cut off on the right, the jersey-number column had no
/// header, and the subtitle read "15 Leaderboard".
FutsalPlayer _p(String name, String number, int g, int a, int s) =>
    FutsalPlayer()
      ..name = name
      ..number = number
      ..goals = g
      ..assists = a
      ..saves = s;

Future<void> _pump(WidgetTester tester,
    {required ThemeMode mode, String season = '15'}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    darkTheme: ThemeData(brightness: Brightness.dark),
    themeMode: mode,
    home: LeaderboardPage(
      sport: 'Futsal',
      season: season,
      playersLoader: () async => <Player>[
        _p('Zaya Shahbaz Arami', '10', 12, 10, 3),
        _p('Bruno Siva', '9', 39, 19, 43),
        _p('Demsin Bet varda', '3', 44, 13, 0),
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('${mode.name} 360 px: every column fits on screen, the '
        'jersey column is headed "#"', (tester) async {
      await _pump(tester, mode: mode);
      expect(tester.takeException(), isNull);
      for (final h in ['#', 'Name', 'G', 'A', 'S']) {
        final r = tester.getRect(find.text(h));
        expect(r.left, greaterThanOrEqualTo(0), reason: h);
        expect(r.right, lessThanOrEqualTo(360), reason: '$h is cut off');
      }
      // Rows too: the last (saves) cell is fully on screen.
      final saves = tester.getRect(find.text('43'));
      expect(saves.right, lessThanOrEqualTo(360));
    });
  }

  testWidgets('subtitle reads "Season 15 Leaderboard"', (tester) async {
    await _pump(tester, mode: ThemeMode.light);
    expect(find.textContaining('Season 15 Leaderboard', findRichText: true),
        findsOneWidget);
  });
}
