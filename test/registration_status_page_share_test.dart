// iPad parity for the registration status page's "Share code" button (the
// approved captain's join-code card): share_plus REJECTS an iPad share with no
// `sharePositionOrigin`, so the share must carry the rect of that button.
// Firebase-free via the page's stream / future / `shareSheet` seams.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

import 'helpers/share_capture.dart';

void main() {
  testWidgets('captain "Share code" shares the join code, anchored to the '
      'button', (tester) async {
    final recorder = ShareSheetRecorder();
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const team = RegTeam(
      id: 't1',
      name: 'Sunday FC',
      captainUid: 'u1',
      status: 'approved',
      joinCode: 'AB12CD',
    );
    await tester.pumpWidget(MaterialApp(
      home: RegistrationStatusPage(
        regId: 'r1',
        config: const RegistrationConfig(
            targetType: 'league', sport: 'Futsal', season: '16'),
        submissionStream: Stream<RegSubmission?>.value(const RegSubmission(
            path: 'captain', answers: {}, teamId: 't1', paid: true)),
        formFuture: Future.value(const <RegQuestion>[]),
        teamStream: Stream<RegTeam?>.value(team),
        rosterStream: Stream<List<RegSubmission>>.value(const []),
        shareSheet: recorder.call,
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final shareButton = find.widgetWithText(ElevatedButton, 'Share code');
    expect(shareButton, findsOneWidget);
    await tester.tap(shareButton);
    await tester.pump();

    final params = recorder.calls.single;
    expect(params.text, contains('AB12CD'));
    expect(params.text, contains('Sunday FC'));
    expectShareAnchoredTo(tester, params, shareButton);
  });
}
