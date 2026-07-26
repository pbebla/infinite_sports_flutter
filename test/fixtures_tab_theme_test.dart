// Regression test for F3 Fix 1 (auth-wall owner feedback round 3): toggling
// Dark Theme left match cards on the home Matches tab rendering with the
// OLD theme's colors (faded text/numbers in light mode) until something
// forced the row to remount (navigating away and back).
//
// Root cause: FixturesTab renders its rows via ListView.builder. Flutter's
// underlying sliver list (SliverChildBuilderDelegate) reuses each row's
// `itemBuilder` BuildContext across ancestor Theme changes instead of
// remounting it, so Theme.of(context) calls made DIRECTLY with that context
// can keep resolving to the ThemeData that was current when the row was
// first built — even across a full MaterialApp theme swap + pumpAndSettle.
// The fix wraps each row's content in a Builder so every Theme.of() lookup
// underneath uses a context that Flutter actually keeps live/dependency-
// tracked. See lib/tournament_tabs/fixtures_tab.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';

const _match = TournamentMatch(
  id: 'm1',
  stage: 'Group Stage',
  label: 'Group Stage',
  date: '07242026',
  time: '7:00PM',
  team1Id: 't1',
  team2Id: 't2',
  team1Score: 0,
  team2Score: 0,
  status: 0, // upcoming — renders its time in colorScheme.onSurfaceVariant
  bracketPosition: 0,
);

Widget _host(ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: FixturesTab(
          matches: const [_match],
          teams: const {},
          rosters: const {},
          tournamentId: '',
          sport: 'Futsal',
        ),
      ),
    );

void main() {
  testWidgets(
      'FixturesTab row color follows a live theme swap, not the theme it '
      'first rendered with', (tester) async {
    await tester.pumpWidget(_host(lightMode));
    await tester.pumpAndSettle();
    final lightColor = tester.widget<Text>(find.text('7:00PM')).style?.color;
    expect(lightColor, lightMode.colorScheme.onSurfaceVariant);

    await tester.pumpWidget(_host(darkMode));
    await tester.pumpAndSettle();
    final darkColor = tester.widget<Text>(find.text('7:00PM')).style?.color;
    expect(darkColor, darkMode.colorScheme.onSurfaceVariant,
        reason: 'row should pick up the new (dark) theme, not stay stuck on '
            'the light-mode color it first rendered with');
    expect(darkColor, isNot(equals(lightColor)));
  });
}
