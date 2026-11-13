// The "Share match" app-bar icon shared by the league and tournament match
// pages: tapping it renders the match card and hands the share sheet an iPad
// popover origin equal to THAT ICON's rect (share_plus rejects an iPad share
// with no origin; the old page-level context anchored to the whole page).
// Driven through the shareMatchCard `share` seam.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/widgets/match_share_button.dart';

import '../helpers/share_capture.dart';

void main() {
  testWidgets('tapping the icon shares the card anchored to the icon, not '
      'the page', (tester) async {
    final recorder = ShareRecorder();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          MatchShareButton(
            match: const TournamentMatch(
              id: 'm1', stage: 'Final', label: 'F', date: '08272026',
              team1Id: 'eagles', team2Id: 'lions', team1Score: 2,
              team2Score: 1, status: 2, bracketPosition: 1,
            ),
            team1: null,
            team2: null,
            tournamentName: 'Cup',
            sport: 'Futsal',
            share: recorder.call,
          ),
        ]),
        body: const SizedBox.expand(),
      ),
    ));

    final icon = find.widgetWithIcon(IconButton, Icons.ios_share);
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await pumpUntil(tester, () => recorder.calls.isNotEmpty);

    final call = recorder.calls.single;
    expect(isPng(call.png), isTrue);
    expect(call.caption, contains('eagles'));
    expectOriginAnchoredTo(tester, call.origin, icon);
    // Not the page: the origin is the small icon, far from the Scaffold rect.
    expect(call.origin, isNot(tester.getRect(find.byType(Scaffold))));
    expect(call.origin!.width, lessThan(100));
  });
}
