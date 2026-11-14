// S16 Task 3: the knockout bracket layout.
//
// Group 1 pins TODAY's card positions for a standard 8-team and 4-team
// tournament bracket (no `feeders`) — written and green BEFORE the layout
// change, so tournaments stay pixel-for-pixel as they were.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/knockout_tab.dart';

TournamentMatch _m(String id, String stage, int pos,
        {String? t1, String? t2, int? s1, int? s2}) =>
    TournamentMatch(
      id: id,
      stage: stage,
      label: stage,
      date: '06212026',
      time: '7:00 PM',
      team1Id: t1,
      team2Id: t2,
      team1Score: 0,
      team2Score: 0,
      status: 0,
      bracketPosition: pos,
      team1Seed: s1,
      team2Seed: s2,
    );

TournamentTeam _team(String id) =>
    TournamentTeam.fromFirebase(id, {'Name': id}, {});

/// An 8-team bracket: 4 QF, 2 SF, final. Team names are unique per card
/// ('QF1 home', …) so each card can be located by its text.
List<TournamentMatch> _eight() => [
      for (var i = 1; i <= 4; i++)
        _m('qf$i', 'Quarterfinal', i, t1: 'QF$i home', t2: 'QF$i away'),
      for (var i = 1; i <= 2; i++)
        _m('sf$i', 'Semifinal', i, t1: 'SF$i home', t2: 'SF$i away'),
      _m('f1', 'Final', 1, t1: 'F home', t2: 'F away'),
    ];

List<TournamentMatch> _four() => [
      for (var i = 1; i <= 2; i++)
        _m('sf$i', 'Semifinal', i, t1: 'SF$i home', t2: 'SF$i away'),
      _m('f1', 'Final', 1, t1: 'F home', t2: 'F away'),
    ];

Map<String, TournamentTeam> _teamsFor(List<TournamentMatch> ms) => {
      for (final m in ms)
        for (final n in [m.team1Id, m.team2Id])
          if (n != null) n: _team(n),
    };

Future<void> _pump(WidgetTester tester, List<TournamentMatch> matches,
    {Map<String, List<String>>? feeders, double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: KnockoutTab(
          matches: matches,
          teams: _teamsFor(matches),

        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The bracket box (the Positioned card / hero column) holding [teamName].
Rect _boxOf(WidgetTester tester, String teamName) => tester.getRect(find
    .ancestor(of: find.text(teamName).first, matching: find.byType(Positioned))
    .first);

void main() {
  group('tournament brackets (no feeders) keep today\'s positions', () {
    testWidgets('8 teams', (tester) async {
      await _pump(tester, _eight());
      // Cards are 210 wide, 96 tall; columns 16 / 270 / 524; the bracket
      // content starts 64 px down (48 chips + 16 padding).
      expect(_boxOf(tester, 'QF1 home'), const Rect.fromLTWH(16, 64, 210, 96));
      expect(_boxOf(tester, 'QF2 home'), const Rect.fromLTWH(16, 178, 210, 96));
      expect(_boxOf(tester, 'QF3 home'), const Rect.fromLTWH(16, 292, 210, 96));
      expect(_boxOf(tester, 'QF4 home'), const Rect.fromLTWH(16, 406, 210, 96));
      expect(_boxOf(tester, 'SF1 home'), const Rect.fromLTWH(270, 121, 210, 96));
      expect(_boxOf(tester, 'SF2 home'), const Rect.fromLTWH(270, 349, 210, 96));
      // Final hero: 360 wide, top = centre 219 - 75 (+64).
      final hero = _boxOf(tester, 'F home');
      expect(hero.left, 524);
      expect(hero.top, 208);
      expect(hero.width, 360);
    });

    testWidgets('4 teams', (tester) async {
      await _pump(tester, _four());
      expect(_boxOf(tester, 'SF1 home'), const Rect.fromLTWH(16, 64, 210, 96));
      expect(_boxOf(tester, 'SF2 home'), const Rect.fromLTWH(16, 178, 210, 96));
      final hero = _boxOf(tester, 'F home');
      expect(hero.left, 270);
      expect(hero.top, 64 + (105 - 75));
      expect(hero.width, 360);
    });
  });
}
