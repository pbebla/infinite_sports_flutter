// Widget tests for the public "Infinite Insider" box on ProfileTab
// (lib/profile/profile_tab.dart, Task F7) — placed between the Player Info
// card and the Current Team card. Firebase-free: `insiderStream` is a test
// seam (mirrors insider_dashboard_page.dart's `insiderStream`) replacing the
// live `/Insiders/<uid>` stream.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §7
// privacy paragraph — shown ONLY when Status == active AND
// ProfileBadgeOptIn == true, exactly two lines: 'Status: <TierName>'
// (tier 0 -> 'Insider') and 'Total Referrals: <N>'.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/profile/profile_tab.dart';

Insider _insider({
  String status = 'active',
  int tier = 2,
  int totalReferred = 14,
  bool profileBadgeOptIn = true,
}) {
  return Insider.fromFirebase('u1', {
    'Status': status,
    'Tier': tier,
    'TotalReferred': totalReferred,
    'ProfileBadgeOptIn': profileBadgeOptIn,
  })!;
}

Widget _wrap(Insider? insider, {Map<dynamic, dynamic> information = const {}}) {
  return MaterialApp(
    home: Scaffold(
      body: ProfileTab(
        uid: 'u1',
        information: information,
        awards: const [],
        insiderStream: Stream<Insider?>.value(insider),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the Insider box for an active, opted-in insider',
      (tester) async {
    await tester.pumpWidget(_wrap(_insider(tier: 2, totalReferred: 14)));
    await tester.pump();

    expect(find.text('Status: Silver'), findsOneWidget);
    expect(find.text('Total Referrals: 14'), findsOneWidget);
  });

  testWidgets('tier 0 reads as plain "Insider"', (tester) async {
    await tester.pumpWidget(_wrap(_insider(tier: 0, totalReferred: 2)));
    await tester.pump();

    expect(find.text('Status: Insider'), findsOneWidget);
    expect(find.text('Total Referrals: 2'), findsOneWidget);
  });

  testWidgets('hidden when the insider has opted out of the profile badge',
      (tester) async {
    await tester.pumpWidget(_wrap(_insider(profileBadgeOptIn: false)));
    await tester.pump();

    expect(find.textContaining('Status:'), findsNothing);
    expect(find.textContaining('Total Referrals:'), findsNothing);
  });

  testWidgets('hidden when the insider is suspended', (tester) async {
    await tester.pumpWidget(_wrap(_insider(status: 'suspended')));
    await tester.pump();

    expect(find.textContaining('Status:'), findsNothing);
  });

  testWidgets('hidden when there is no /Insiders node at all', (tester) async {
    await tester.pumpWidget(_wrap(null));
    await tester.pump();

    expect(find.textContaining('Status:'), findsNothing);
    expect(find.textContaining('Total Referrals:'), findsNothing);
  });

  testWidgets(
      'renders between Player Info and Current Team, in that vertical order',
      (tester) async {
    await tester.pumpWidget(_wrap(
      _insider(),
      information: {'Height': "5'10\""},
    ));
    await tester.pump();

    final infoY = tester.getTopLeft(find.text('Player Info')).dy;
    final statusY = tester.getTopLeft(find.text('Status: Silver')).dy;
    final teamY = tester.getTopLeft(find.text('Current Team')).dy;

    expect(infoY, lessThan(statusY));
    expect(statusY, lessThan(teamY));
  });
}
