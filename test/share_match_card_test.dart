import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/share_match_card.dart';

TournamentTeam _team(String id, String name) => TournamentTeam(
      id: id,
      name: name,
      qualification: 'Qualified',
      gp: 0, wins: 0, draws: 0, losses: 0, gs: 0, gc: 0, gd: 0, points: 0,
      homeColor: const Color(0xFF0066CC),
    );

Future<void> _pump(WidgetTester tester, TournamentMatch m) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ShareMatchCard(
        match: m,
        team1: _team('eagles', 'Eagles'),
        team2: _team('lions', 'Lions'),
        tournamentName: 'Test Tournament 2026',
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('finished card renders score, FINAL, follow, no overflow',
      (tester) async {
    const m = TournamentMatch(
      id: 'm', stage: 'Quarterfinal', label: 'QF', date: '08272026',
      time: '10:00 AM', team1Id: 'eagles', team2Id: 'lions',
      team1Score: 4, team2Score: 3, status: 2, bracketPosition: 1,
      team1Activity: {
        '1': [
          {'goal': 'Sam'},
          {'assist': 'Drew'}
        ]
      },
    );
    await _pump(tester, m);
    expect(tester.takeException(), isNull);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.textContaining('Follow Infinite Sports'), findsOneWidget);
  });

  testWidgets('upcoming card shows no FINAL', (tester) async {
    const m = TournamentMatch(
      id: 'm', stage: 'Quarterfinal', label: 'QF', date: '08272026',
      time: '10:00 AM', team1Id: 'eagles', team2Id: 'lions',
      team1Score: 0, team2Score: 0, status: 0, bracketPosition: 1,
    );
    await _pump(tester, m);
    expect(tester.takeException(), isNull);
    expect(find.text('FINAL'), findsNothing);
  });

  testWidgets('live card renders without overflow', (tester) async {
    const m = TournamentMatch(
      id: 'm', stage: 'Quarterfinal', label: 'QF', date: '08272026',
      team1Id: 'eagles', team2Id: 'lions', team1Score: 1, team2Score: 0,
      status: 1, bracketPosition: 1,
    );
    await _pump(tester, m);
    expect(tester.takeException(), isNull);
  });
}
