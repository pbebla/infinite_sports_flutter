// S16 Task 3: the knockout bracket layout.
//
// Group 1 pins TODAY's card positions for a standard 8-team and 4-team
// tournament bracket (no `feeders`) — written and green BEFORE the layout
// change, so tournaments stay pixel-for-pixel as they were.
// Group 2 checks that the same brackets WITH `feeders` lay out the same.
// Group 3 is the Season 16 shape (2 QF, 2 SF each fed by ONE QF, final).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_playoffs_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/knockout_tab.dart';

TournamentMatch _m(String id, String stage, int pos,
        {String? t1, String? t2, int? s1, int? s2, String time = '7:00 PM'}) =>
    TournamentMatch(
      id: id,
      stage: stage,
      label: stage,
      date: '06212026',
      time: time,
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
    {Map<String, List<String>>? feeders,
    Map<String, TournamentTeam>? teams,
    double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(360, 800), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: KnockoutTab(
          matches: matches,
          teams: teams ?? _teamsFor(matches),
          feeders: feeders,
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
      expect(
          _boxOf(tester, 'SF1 home'), const Rect.fromLTWH(270, 121, 210, 96));
      expect(
          _boxOf(tester, 'SF2 home'), const Rect.fromLTWH(270, 349, 210, 96));
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

  group('standard brackets WITH feeders lay out exactly as without', () {
    const eightFeeders = {
      'sf1': ['qf1', 'qf2'],
      'sf2': ['qf3', 'qf4'],
      'f1': ['sf1', 'sf2'],
    };
    const fourFeeders = {
      'f1': ['sf1', 'sf2'],
    };

    test('pure layout: same centres as index pairing', () {
      final eight = knockoutFeederLayout([
        ['qf1', 'qf2', 'qf3', 'qf4'],
        ['sf1', 'sf2'],
        ['f1'],
      ], eightFeeders);
      expect(eight.centers, [
        [48.0, 162.0, 276.0, 390.0],
        [105.0, 333.0],
        [219.0],
      ]);
      final four = knockoutFeederLayout([
        ['sf1', 'sf2'],
        ['f1'],
      ], fourFeeders);
      expect(four.centers, [
        [48.0, 162.0],
        [105.0],
      ]);
    });

    testWidgets('8 teams', (tester) async {
      await _pump(tester, _eight(), feeders: eightFeeders);
      expect(_boxOf(tester, 'QF1 home'), const Rect.fromLTWH(16, 64, 210, 96));
      expect(_boxOf(tester, 'QF4 home'), const Rect.fromLTWH(16, 406, 210, 96));
      expect(
          _boxOf(tester, 'SF1 home'), const Rect.fromLTWH(270, 121, 210, 96));
      expect(
          _boxOf(tester, 'SF2 home'), const Rect.fromLTWH(270, 349, 210, 96));
      expect(_boxOf(tester, 'F home').topLeft, const Offset(524, 208));
    });

    testWidgets('4 teams', (tester) async {
      await _pump(tester, _four(), feeders: fourFeeders);
      expect(_boxOf(tester, 'SF1 home'), const Rect.fromLTWH(16, 64, 210, 96));
      expect(_boxOf(tester, 'SF2 home'), const Rect.fromLTWH(16, 178, 210, 96));
      expect(_boxOf(tester, 'F home').topLeft, const Offset(270, 94));
    });
  });

  group('Season 16: 6 teams, 1st and 2nd skip the quarterfinals', () {
    const s16Feeders = {
      'sf1': ['qf1'],
      'sf2': ['qf2'],
      'f1': ['sf1', 'sf2'],
    };
    // Short kick-off times: the test font draws every glyph as a full
    // square, so at 1.3x a '7:00 PM' header overflows the card's existing
    // (unchanged) header row in tests only — a real font fits it.
    List<TournamentMatch> s16() => [
          _m('qf1', 'Quarterfinal', 1,
              t1: '3rd Place', t2: '6th Place', s1: 3, s2: 6, time: '7PM'),
          _m('qf2', 'Quarterfinal', 2,
              t1: '4th Place', t2: '5th Place', s1: 4, s2: 5, time: '8PM'),
          _m('sf1', 'Semifinal', 1,
              t1: 'Winner of QF1', t2: '2nd Place', s2: 2, time: '7PM'),
          _m('sf2', 'Semifinal', 2,
              t1: 'Winner of QF2', t2: '1st Place', s2: 1, time: '8PM'),
          _m('f1', 'Final', 1,
              t1: 'Winner of SF1', t2: 'Winner of SF2', time: '7PM'),
        ];

    test(
        'pure layout: each SF level with its feeder QF, final midway, '
        'exactly four connectors joining only real feeders', () {
      final layout = knockoutFeederLayout([
        ['qf1', 'qf2'],
        ['sf1', 'sf2'],
        ['f1'],
      ], s16Feeders);
      expect(layout.centers[1], layout.centers[0]);
      expect(layout.centers[2].single,
          (layout.centers[1][0] + layout.centers[1][1]) / 2);
      final links = [
        for (final c in layout.connectors)
          for (final from in c.fromIndices)
            '${c.round - 1}:$from>${c.round}:${c.toIndex}',
      ];
      expect(links, ['0:0>1:0', '0:1>1:1', '1:0>2:0', '1:1>2:0']);
    });

    testWidgets(
        'no two cards overlap at 360 px (text scale 1.3), each SF is '
        'level with its feeder QF, the final sits midway', (tester) async {
      // No resolved teams yet (placeholders only, as live).
      await _pump(tester, s16(),
          feeders: s16Feeders, teams: const {}, textScale: 1.3);
      // Seeded sides read the slot's seed (no team resolved yet).
      final qf1 = _boxOf(tester, 'Seed #3');
      final qf2 = _boxOf(tester, 'Seed #4');
      final sf1 = _boxOf(tester, 'Winner of QF1');
      final sf2 = _boxOf(tester, 'Winner of QF2');
      // The hero reads TBD for an unresolved final (today's behaviour).
      final hero = _boxOf(tester, 'TBD');
      expect(sf1.center.dy, qf1.center.dy);
      expect(sf2.center.dy, qf2.center.dy);
      final cards = [qf1, qf2, sf1, sf2, hero];
      for (var i = 0; i < cards.length; i++) {
        for (var j = i + 1; j < cards.length; j++) {
          expect(cards[i].overlaps(cards[j]), isFalse,
              reason: 'card $i overlaps card $j: ${cards[i]} / ${cards[j]}');
        }
      }
      // Hero: 150 tall, centred midway between the semifinals.
      expect(hero.top + 75, (sf1.center.dy + sf2.center.dy) / 2);
      expect(tester.takeException(), isNull);
    });

    test(
        'a card with no feeder takes the next free row; crowded cards are '
        'pushed apart and the push carries to what they feed', () {
      final layout = knockoutFeederLayout([
        ['qf1', 'qf2'],
        ['sf1', 'sf2', 'sf3'],
        ['f1'],
      ], {
        'sf1': ['qf1'],
        'sf2': ['qf1'], // same feeder as sf1, so pushed one row down
        'f1': ['sf2', 'sf3'],
      });
      // sf1 level with qf1; sf2 pushed one pitch (114) below; sf3 has no
      // feeder: the next free row below the lowest card.
      expect(layout.centers[1], [48.0, 162.0, 276.0]);
      // The final sits midway between sf2 and sf3 at their pushed rows.
      expect(layout.centers[2], [219.0]);
      // No connector into sf3 (no real feeder).
      expect(layout.connectors.where((c) => c.round == 1).map((c) => c.toIndex),
          [0, 1]);
    });

    testWidgets(
        'league tab, live S16 data: bye sides read Seed #2 / Seed #1, '
        'feeder sides Winner of QF1 / Winner of QF2', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Map<String, Object> g(String t1, String t2, String stage) => {
            'team1': t1,
            'team2': t2,
            'team1score': 0,
            'team2score': 0,
            'status': 0,
            'Stage': stage,
          };
      final matches = leagueMatchesFromDateNode({
        '01312027': [
          g('1st Place', '2nd Place', 'friendly'),
          g('3rd Place', '6th Place', 'quarterfinal'),
          g('4th Place', '5th Place', 'quarterfinal'),
        ],
        '02072027': [
          g('Winner of QF1', '2nd Place', 'semifinal'),
          g('Winner of QF2', '1st Place', 'semifinal'),
        ],
        '02142027': [
          g('Winner of SF1', 'Winner of SF2', 'final'),
        ],
      });
      final playoffs = LeaguePlayoffs.fromNode({
        'Format': 8,
        'ThirdPlace': false,
        'Slots': {
          'qf1': {
            'team1Seed': 3,
            'team2Seed': 6,
            'gameRef': {'date': '01312027', 'index': 1},
            'winnerTo': 'sf1',
          },
          'qf2': {
            'team1Seed': 4,
            'team2Seed': 5,
            'gameRef': {'date': '01312027', 'index': 2},
            'winnerTo': 'sf2',
          },
          'sf1': {
            'team2Seed': 2,
            'gameRef': {'date': '02072027', 'index': 0},
            'winnerTo': 'f1',
          },
          'sf2': {
            'team2Seed': 1,
            'gameRef': {'date': '02072027', 'index': 1},
            'winnerTo': 'f1',
          },
          'f1': {
            'gameRef': {'date': '02142027', 'index': 0},
          },
        },
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeaguePlayoffsTab(
            playoffs: playoffs,
            matches: matches,
            teams: const {},
            season: '16',
            onMatchTap: (_) {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Seed #2'), findsOneWidget);
      expect(find.text('Seed #1'), findsOneWidget);
      expect(find.text('Winner of QF1'), findsOneWidget);
      expect(find.text('Winner of QF2'), findsOneWidget);
      // The friendly (1st v 2nd) is not in the bracket.
      expect(find.text('1st Place'), findsNothing);
      final sf1 = _boxOf(tester, 'Winner of QF1');
      final sf2 = _boxOf(tester, 'Winner of QF2');
      expect(sf1.overlaps(sf2), isFalse);
      expect(sf1.center.dy, _boxOf(tester, 'Seed #3').center.dy);
      expect(sf2.center.dy, _boxOf(tester, 'Seed #4').center.dy);
    });
  });
}
