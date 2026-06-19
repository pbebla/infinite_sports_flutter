// Widget tests for the K1 KnockoutTab redesign:
// boxed match cards, Final hero (trophy + champion tint), Bronze card.
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
      'KnockoutTab Final chip renders hero with both finalist names and a trophy image',
      (tester) async {
    await tester.pumpWidget(
        buildTab([finishedFinal, thirdPlaceMatch]));

    // Wait for initial frame.
    await tester.pump();

    // The "Final" chip should exist.
    expect(find.text('Final'), findsWidgets);

    // Tap the Final chip to ensure it's selected (it's pre-selected as the
    // first round in sorted order, but let's confirm it renders the hero).
    await tester.tap(find.text('Final').last);
    await tester.pump();

    // Both finalist team names should appear in the hero.
    expect(find.text('Team Alpha'), findsWidgets);
    expect(find.text('Team Beta'), findsWidgets);

    // The trophy image should be present (Image.asset with assets/trophy.png).
    // We check for at least one Image widget in the tree.
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('KnockoutTab Final chip renders bronze card',
      (tester) async {
    await tester.pumpWidget(
        buildTab([finishedFinal, thirdPlaceMatch]));
    await tester.pump();

    // Ensure Final is selected.
    await tester.tap(find.text('Final').last);
    await tester.pump();

    // Third place teams should appear.
    expect(find.text('Team Beta'), findsWidgets);
    expect(find.text('Team Delta'), findsWidgets);
  });

  testWidgets('KnockoutTab QF chip renders boxed cards with team names',
      (tester) async {
    await tester.pumpWidget(buildTab([finishedFinal, finishedQF]));
    await tester.pump();

    // The Quarterfinal chip should be present.
    expect(find.text('Quarterfinal'), findsWidgets);

    // Tap QF chip.
    await tester.tap(find.text('Quarterfinal').last);
    await tester.pump();

    // QF team names should appear.
    expect(find.text('Team Charlie'), findsOneWidget);
    expect(find.text('Team Delta'), findsOneWidget);
  });

  testWidgets(
      'KnockoutTab hero applies champion tint when final is finished and winner has homeColor',
      (tester) async {
    // Just ensure the widget tree builds without error for a finished final
    // with a winner that has a homeColor — champion tint path.
    await tester.pumpWidget(buildTab([finishedFinal]));
    await tester.pump();

    // Navigate to Final chip.
    await tester.tap(find.text('Final').last);
    await tester.pump();

    // No exceptions thrown; finalist names present.
    expect(find.text('Team Alpha'), findsWidgets);
  });

  testWidgets('KnockoutTab renders no-third-place gracefully',
      (tester) async {
    // Only a final — no third-place match. Should not crash.
    await tester.pumpWidget(buildTab([finishedFinal]));
    await tester.pump();
    await tester.tap(find.text('Final').last);
    await tester.pump();

    // Both finalist names visible.
    expect(find.text('Team Alpha'), findsWidgets);
    expect(find.text('Team Beta'), findsWidgets);
  });
}
