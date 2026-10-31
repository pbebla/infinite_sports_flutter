// The profile page's app-bar Share icon (trophy-cabinet card on the Profile
// tab): the iPad popover origin must be THAT ICON's rect — share_plus rejects
// an iPad share with no origin, and the page-level context anchored to the
// whole page. Driven through ProfilePage's `share` seam (-> shareProfileCard
// -> shareCardImage); loadOverride keeps it Firebase-free.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

import 'helpers/share_capture.dart';

void main() {
  setUp(ProfilePage.clearCareerCache);

  testWidgets('Share icon on the Profile tab shares the cabinet card '
      'anchored to the icon, not the page', (tester) async {
    final recorder = ShareRecorder();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Empty uid keeps ProfileTab's Insider box (the only other Firebase
    // touchpoint) dormant.
    await tester.pumpWidget(MaterialApp(
      home: ProfilePage(
        uid: '',
        loadOverride: () async => 1,
        share: recorder.call,
      ),
    ));
    await tester.pump();
    await tester.pump();

    final icon = find.widgetWithIcon(IconButton, Icons.ios_share);
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await pumpUntil(tester, () => recorder.calls.isNotEmpty);

    final call = recorder.calls.single;
    expect(isPng(call.png), isTrue);
    expect(call.caption, contains('trophy cabinet'));
    expectOriginAnchoredTo(tester, call.origin, icon);
    expect(call.origin, isNot(tester.getRect(find.byType(Scaffold).first)));
    expect(call.origin!.width, lessThan(100));
  });
}
