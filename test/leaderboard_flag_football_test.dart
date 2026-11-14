import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/model/flagfootballplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';

/// Fix round 1, M5: the Flag Football leaderboard has 13 stat columns, far
/// more than fit 360 px, so it stays a sideways-scrolling table — but now
/// with a visible cue: an edge fade on the clipped right side (theme surface
/// colour, light AND dark) that disappears once the table is scrolled to its
/// end.
FlagFootballPlayer _p(String name, String number) => FlagFootballPlayer()
  ..name = name
  ..number = number
  ..catchRate = '50%'
  ..qbCompletionRate = '60%'
  ..passingTouchdowns = 3;

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('${mode.name} 360 px: a right-edge fade shows while more '
        'columns are off screen, and goes at the end', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: mode,
        home: LeaderboardPage(
          sport: 'Flag Football',
          season: '3',
          playersLoader: () async => <Player>[_p('Sam Q', '7'), _p('Lee R', '9')],
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final fade = find.byKey(const ValueKey('leaderboard_scroll_fade'));
      expect(fade, findsOneWidget);
      double opacity() => tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: fade, matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(), 1);
      // Hugs the right edge, in the theme's surface colour.
      final rect = tester.getRect(fade);
      expect(rect.right, 360);
      final ctx = tester.element(fade);
      final gradient = (tester.widget<DecoratedBox>(fade).decoration
              as BoxDecoration)
          .gradient as LinearGradient;
      expect(gradient.colors.last, Theme.of(ctx).colorScheme.surface);

      // Scroll the stat columns all the way: nothing left to hint at.
      await tester.drag(find.text('P-TD'), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a screen wide enough for every column shows no fade',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: LeaderboardPage(
        sport: 'Flag Football',
        season: '3',
        playersLoader: () async => <Player>[_p('Sam Q', '7')],
      ),
    ));
    await tester.pumpAndSettle();
    final fade = find.byKey(const ValueKey('leaderboard_scroll_fade'));
    expect(
        tester
            .widget<AnimatedOpacity>(
                find.ancestor(of: fade, matching: find.byType(AnimatedOpacity)))
            .opacity,
        0);
  });
}
