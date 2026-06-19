// Widget tests for the KnockoutTab continuous-bracket redesign:
// all rounds in one horizontal bracket, Final hero, Bronze card, feeder sources.
//
// These tests are Firebase-free: they build presentational widgets only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/knockout_tab.dart';

// ---------------------------------------------------------------------------
// Helpers — build minimal TournamentMatch / TournamentTeam fixtures
// ---------------------------------------------------------------------------

TournamentMatch _makeMatch({
  required String id,
  required String stage,
  String? team1Id,
  String? team2Id,
  String? team1Source,
  String? team2Source,
  int team1Score = 0,
  int team2Score = 0,
  int status = 0, // 0=pending, 1=live, 2=finished
  int bracketPosition = 0,
}) {
  return TournamentMatch.fromFirebase(id, {
    'Stage': stage,
    'Label': stage,
    'Date': '06212026',
    'Time': '7:00 PM',
    'Team1Id': team1Id,
    'Team2Id': team2Id,
    if (team1Source != null) 'Team1Source': team1Source,
    if (team2Source != null) 'Team2Source': team2Source,
    'Team1Score': team1Score,
    'Team2Score': team2Score,
    'Status': status,
    'BracketPosition': bracketPosition,
  });
}

TournamentTeam _makeTeam({
  required String id,
  required String name,
  String? homeColor,
}) {
  return TournamentTeam.fromFirebase(
    id,
    {
      'Name': name,
      if (homeColor != null) 'HomeColor': homeColor,
    },
    {},
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // A finished final: team A (2) beat team B (1).
  final teamA = _makeTeam(id: 'tA', name: 'Team Alpha', homeColor: '#1565C0');
  final teamB = _makeTeam(id: 'tB', name: 'Team Beta');
  final teamC = _makeTeam(id: 'tC', name: 'Team Charlie');
  final teamD = _makeTeam(id: 'tD', name: 'Team Delta');

  final finishedFinal = _makeMatch(
    id: 'mFinal',
    stage: 'Final',
    team1Id: 'tA',
    team2Id: 'tB',
    team1Score: 2,
    team2Score: 1,
    status: 2, // finished
    bracketPosition: 0,
  );

  final finishedQF = _makeMatch(
    id: 'mQF1',
    stage: 'Quarterfinal',
    team1Id: 'tC',
    team2Id: 'tD',
    team1Score: 3,
    team2Score: 0,
    status: 2,
    bracketPosition: 0,
  );

  final thirdPlaceMatch = _makeMatch(
    id: 'mThird',
    stage: 'Third Place',
    team1Id: 'tB',
    team2Id: 'tD',
    team1Score: 1,
    team2Score: 0,
    status: 2,
    bracketPosition: 0,
  );

  final teams = {
    'tA': teamA,
    'tB': teamB,
    'tC': teamC,
    'tD': teamD,
  };

  Widget buildTab(List<TournamentMatch> matches) {
    return MaterialApp(
      home: Scaffold(
        body: KnockoutTab(
          matches: matches,
          teams: teams,
          tournamentId: 't1',
          rosters: const {},
          sport: 'Soccer',
        ),
      ),
    );
  }

  testWidgets('KnockoutTab shows "not yet available" with no matches',
      (tester) async {
    await tester.pumpWidget(buildTab([]));
    expect(find.text('Knockout stage not yet available'), findsOneWidget);
  });

  testWidgets(
      'KnockoutTab renders final hero with both finalist names and a trophy image',
      (tester) async {
    await tester.pumpWidget(buildTab([finishedFinal, thirdPlaceMatch]));
    await tester.pump();

    // The "Final" chip should exist (scroll-to shortcut).
    expect(find.text('Final'), findsWidgets);

    // Both finalist team names should appear in the hero (always rendered).
    expect(find.text('Team Alpha'), findsWidgets);
    expect(find.text('Team Beta'), findsWidgets);

    // The trophy image should be present (Image.asset with assets/trophy.png).
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('KnockoutTab renders bronze card below the bracket',
      (tester) async {
    await tester.pumpWidget(buildTab([finishedFinal, thirdPlaceMatch]));
    await tester.pump();

    // Third place teams should appear somewhere in the widget tree.
    // Team Beta appears in both the Final hero and the bronze card.
    expect(find.text('Team Beta'), findsWidgets);
    expect(find.text('Team Delta'), findsWidgets);
  });

  testWidgets(
      'KnockoutTab renders QF and Final cards simultaneously in the bracket',
      (tester) async {
    await tester.pumpWidget(buildTab([finishedFinal, finishedQF]));
    await tester.pump();

    // Both Quarterfinal and Final chips exist.
    expect(find.text('Quarterfinal'), findsWidgets);
    expect(find.text('Final'), findsWidgets);

    // QF team names appear (they're in the bracket at all times).
    expect(find.text('Team Charlie'), findsWidgets);
    expect(find.text('Team Delta'), findsWidgets);

    // Final teams also appear simultaneously.
    expect(find.text('Team Alpha'), findsWidgets);
  });

  testWidgets(
      'KnockoutTab hero applies champion tint when final is finished and winner has homeColor',
      (tester) async {
    // Just ensure the widget tree builds without error for a finished final
    // with a winner that has a homeColor — champion tint path.
    await tester.pumpWidget(buildTab([finishedFinal]));
    await tester.pump();

    // No exceptions thrown; finalist names present.
    expect(find.text('Team Alpha'), findsWidgets);
  });

  testWidgets('KnockoutTab renders no-third-place gracefully', (tester) async {
    // Only a final — no third-place match. Should not crash.
    await tester.pumpWidget(buildTab([finishedFinal]));
    await tester.pump();

    // Both finalist names visible.
    expect(find.text('Team Alpha'), findsWidgets);
    expect(find.text('Team Beta'), findsWidgets);
  });

  testWidgets('KnockoutTab chips trigger scroll (no crash)', (tester) async {
    await tester.pumpWidget(buildTab([finishedFinal, finishedQF]));
    await tester.pump();

    // Tap each chip — should not throw; scroll controller handles it.
    await tester.tap(find.text('Quarterfinal').last);
    await tester.pump();
    await tester.tap(find.text('Final').last);
    await tester.pump();

    expect(find.text('Team Alpha'), findsWidgets);
  });

  testWidgets('KnockoutTab renders feeder source placeholders', (tester) async {
    // Match with no teams assigned but feeder sources set
    final pendingSF = _makeMatch(
      id: 'mSF1',
      stage: 'Semifinal',
      team1Source: 'W:mQF1',
      team2Source: 'G:B:2',
      bracketPosition: 0,
    );
    await tester.pumpWidget(buildTab([pendingSF, finishedQF]));
    await tester.pump();

    // Feeder placeholder labels should appear (no crash).
    // "Group B 2nd" from G:B:2 source.
    expect(find.text('Group B 2nd'), findsWidgets);
    // "Winner QF1" from W:mQF1 (mQF1 is finishedQF which is in the match list).
    expect(find.text('Winner QF1'), findsWidgets);
  });

  testWidgets('formatFeederSource produces correct group labels', (tester) async {
    // Unit-style checks via the helper directly (no widget needed).
    final matches = <TournamentMatch>[];
    expect(formatFeederSource('G:A:1', matches), 'Group A 1st');
    expect(formatFeederSource('G:B:2', matches), 'Group B 2nd');
    expect(formatFeederSource('G:C:3', matches), 'Group C 3rd');
    expect(formatFeederSource('G:D:4', matches), 'Group D 4th');
    expect(formatFeederSource('unknown', matches), 'TBD');
  });
}
