// Widget tests for TeamBoxScoreTab (Match Box Score spec, 2026-07-28).
// Firebase-free: the widget takes plain roster/tally data, and the
// `openProfileOverride` seam (insiders_leaderboard_page convention)
// replaces openPlayerProfileById so no ProfilePage is ever constructed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/match_tabs/box_score_columns.dart';
import 'package:infinite_sports_flutter/match_tabs/team_box_score_tab.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

TournamentPlayer _p(String name, {String? number, String? uid}) =>
    TournamentPlayer(
      name: name,
      teamId: 'T',
      teamName: 'T',
      number: number,
      uid: uid,
      goals: 0,
      assists: 0,
      saves: 0,
      dpl: 0,
      cleanSheets: 0,
      yellowCards: 0,
      redCards: 0,
    );

MatchPlayerTally _goals(int n) => MatchPlayerTally()..goals = n;

Future<void> _pump(
  WidgetTester tester, {
  required List<TournamentPlayer> roster,
  Map<String, MatchPlayerTally> tallies = const {},
  List<BoxScoreColumn>? columns,
  Future<void> Function(BuildContext context,
          {String? uid, required String name})?
      openProfileOverride,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TeamBoxScoreTab(
        roster: roster,
        tallies: tallies,
        columns: columns ?? boxScoreColumnsFor('Futsal'),
        openProfileOverride: openProfileOverride,
      ),
    ),
  ));
}

/// Vertical position of a rendered text — for asserting row order.
double _dy(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('renders roster rows with names and jersey numbers',
      (tester) async {
    await _pump(tester,
        roster: [_p('Ashur', number: '10'), _p('Ninos', number: '9')],
        tallies: {'Ashur': _goals(2)});

    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Ninos'), findsOneWidget);
    expect(find.text('#10'), findsOneWidget);
    expect(find.text('#9'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
  });

  testWidgets('auto-hides columns nobody recorded', (tester) async {
    await _pump(tester,
        roster: [_p('Ashur'), _p('Ninos')],
        tallies: {'Ashur': _goals(1)});

    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Assists'), findsNothing);
    expect(find.text('Saves'), findsNothing);
    expect(find.text('Fouls'), findsNothing);
  });

  testWidgets(
      'zero recorded stats: roster rows render under a muted note — never a '
      'blank tab', (tester) async {
    await _pump(tester, roster: [_p('Ashur', number: '10'), _p('Ninos')]);

    expect(find.text('No stats recorded yet'), findsOneWidget);
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Ninos'), findsOneWidget);
    expect(find.text('#10'), findsOneWidget);
    expect(find.text('Goals'), findsNothing); // no headers in the empty state
  });

  testWidgets('default sort is primary stat descending; tapping the header '
      'toggles to ascending', (tester) async {
    await _pump(tester,
        roster: [_p('Ashur'), _p('Ninos')],
        tallies: {'Ashur': _goals(1), 'Ninos': _goals(3)});

    // Best first: Ninos (3) above Ashur (1).
    expect(_dy(tester, 'Ninos'), lessThan(_dy(tester, 'Ashur')));

    await tester.tap(find.text('Goals'));
    await tester.pump();

    expect(_dy(tester, 'Ashur'), lessThan(_dy(tester, 'Ninos')));
  });

  testWidgets('tapping another stat header switches the sort to it',
      (tester) async {
    await _pump(tester, roster: [
      _p('Ashur'),
      _p('Ninos')
    ], tallies: {
      'Ashur': _goals(2),
      'Ninos': MatchPlayerTally()
        ..goals = 1
        ..assists = 4,
    });

    expect(_dy(tester, 'Ashur'), lessThan(_dy(tester, 'Ninos'))); // by goals

    await tester.tap(find.text('Assists'));
    await tester.pump();

    expect(_dy(tester, 'Ninos'), lessThan(_dy(tester, 'Ashur')));
  });

  testWidgets('name header sorts alphabetically, toggling A-Z / Z-A',
      (tester) async {
    await _pump(tester,
        roster: [_p('Zaya'), _p('Adam')],
        tallies: {'Zaya': _goals(5), 'Adam': _goals(1)});

    // Default: best first.
    expect(_dy(tester, 'Zaya'), lessThan(_dy(tester, 'Adam')));

    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(_dy(tester, 'Adam'), lessThan(_dy(tester, 'Zaya'))); // A-Z

    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(_dy(tester, 'Zaya'), lessThan(_dy(tester, 'Adam'))); // Z-A
  });

  testWidgets('tapping a player row opens their profile via the seam',
      (tester) async {
    String? openedUid;
    String? openedName;
    await _pump(tester,
        roster: [_p('Ashur', uid: 'u1')],
        tallies: {'Ashur': _goals(1)},
        openProfileOverride: (context, {uid, required name}) async {
      openedUid = uid;
      openedName = name;
    });

    await tester.tap(find.text('Ashur'));
    await tester.pump();

    expect(openedUid, 'u1');
    expect(openedName, 'Ashur');
  });
}
