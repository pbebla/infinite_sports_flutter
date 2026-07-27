// Widget tests for the Insider private dashboard page
// (lib/insiders/insider_dashboard_page.dart, Task F4). Firebase-free:
// `insiderStream`/`referralsStream` overrides replace the live
// /Insiders/<uid> and /Referrals streams, and `setLeaderboardOptIn` /
// `setProfileBadgeOptIn` / `shareInvite` overrides replace the real writes
// and the share-sheet call — mirrors the injectable-stream + writeOverride
// seams in test/insiders_info_page_test.dart (Task F2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/insiders/insider_dashboard_page.dart';
import 'package:infinite_sports_flutter/model/insider.dart';

Insider _activeInsider({
  int tier = 2,
  int currentStanding = 12,
  int totalReferred = 14,
  int currentYearCount = 0,
  bool publicLeaderboardOptIn = true,
  bool profileBadgeOptIn = true,
  String status = 'active',
  String code = 'ZA4K9P2',
}) {
  return Insider.fromFirebase('u1', {
    'Status': status,
    'Code': code,
    'Tier': tier,
    'CurrentStanding': currentStanding,
    'TotalReferred': totalReferred,
    'CurrentYearCount': currentYearCount,
    'PublicLeaderboardOptIn': publicLeaderboardOptIn,
    'ProfileBadgeOptIn': profileBadgeOptIn,
  })!;
}

InsiderReferral _referral({
  required String id,
  String referredName = 'Sara Kim',
  String sport = 'Futsal',
  String state = 'counted',
  bool verified = false,
  bool manual = false,
  int countedAt = 1000,
}) {
  return InsiderReferral.fromFirebase(id, {
    'InsiderUid': 'u1',
    'ReferredName': referredName,
    'Sport': sport,
    'State': state,
    'Verified': verified,
    'Manual': manual,
    'CountedAt': countedAt,
  })!;
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Insider? insider,
  List<InsiderReferral> referrals = const [],
  Future<void> Function(bool)? setLeaderboardOptIn,
  Future<void> Function(bool)? setProfileBadgeOptIn,
  void Function(String)? shareInvite,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: InsiderDashboardPage(
      insiderStream: Stream<Insider?>.value(insider),
      referralsStream: Stream<List<InsiderReferral>>.value(referrals),
      setLeaderboardOptIn: setLeaderboardOptIn,
      setProfileBadgeOptIn: setProfileBadgeOptIn,
      shareInvite: shareInvite,
    ),
  ));
  // Two nested StreamBuilders (insider, then referrals) each need a tick to
  // pick up their injected single-value stream.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders tier badge, progress label, and the two stat boxes',
      (tester) async {
    await _pumpDashboard(tester,
        insider: _activeInsider(tier: 2, currentStanding: 12, totalReferred: 14));

    expect(find.textContaining('Silver'), findsWidgets);
    expect(find.text('2 of 5 referrals to Gold'), findsOneWidget);
    expect(find.text('Total Referred'), findsOneWidget);
    expect(find.text('Current Standing'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('shows the code and copying it shows a confirmation snackbar',
      (tester) async {
    await _pumpDashboard(tester, insider: _activeInsider(code: 'ZA4K9P2'));

    expect(find.text('ZA4K9P2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('insider_dashboard_copy_button')));
    await tester.pump();
    expect(find.textContaining('copied'), findsOneWidget);
  });

  testWidgets('tapping Share calls shareInvite with the exact invite message',
      (tester) async {
    String? captured;
    await _pumpDashboard(
      tester,
      insider: _activeInsider(code: 'ZA4K9P2'),
      shareInvite: (msg) => captured = msg,
    );

    await tester.tap(find.byKey(const ValueKey('insider_dashboard_share_button')));
    await tester.pump();

    expect(captured, inviteMessage('ZA4K9P2'));
  });

  testWidgets('empty referrals shows the "share your code" empty state',
      (tester) async {
    await _pumpDashboard(tester, insider: _activeInsider(), referrals: const []);

    expect(find.text('No referrals yet — share your code to get started!'),
        findsOneWidget);
  });

  testWidgets(
      'referral rows show name/sport, ✓ Verified / Counted / Voided, and a Manual tag',
      (tester) async {
    await _pumpDashboard(tester, insider: _activeInsider(), referrals: [
      _referral(id: 'r1', referredName: 'Sara Kim', verified: true, state: 'counted'),
      _referral(id: 'r2', referredName: 'Alex Wong', state: 'counted'),
      _referral(
          id: 'r3',
          referredName: 'Jamie Lee',
          state: 'voided',
          manual: true),
    ]);

    expect(find.text('Sara Kim'), findsOneWidget);
    expect(find.text('✓ Verified'), findsOneWidget);
    expect(find.text('Alex Wong'), findsOneWidget);
    expect(find.text('Counted'), findsOneWidget);
    expect(find.text('Jamie Lee'), findsOneWidget);
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
  });

  testWidgets('per-sport chips reflect counted referrals only', (tester) async {
    await _pumpDashboard(tester, insider: _activeInsider(), referrals: [
      _referral(id: 'r1', sport: 'Futsal', state: 'counted'),
      _referral(id: 'r2', sport: 'Futsal', state: 'counted'),
      _referral(id: 'r3', sport: 'Basketball', state: 'counted'),
      _referral(id: 'r4', sport: 'Futsal', state: 'voided'),
    ]);

    expect(find.text('Futsal 2'), findsOneWidget);
    expect(find.text('Basketball 1'), findsOneWidget);
  });

  testWidgets('Infinite maintenance meter only shows at Tier 5', (tester) async {
    await _pumpDashboard(tester,
        insider: _activeInsider(tier: 5, currentStanding: 30, currentYearCount: 3));
    expect(find.textContaining('3 of 5 this year'), findsOneWidget);
  });

  testWidgets('Infinite maintenance meter is absent below Tier 5', (tester) async {
    await _pumpDashboard(tester, insider: _activeInsider(tier: 4, currentStanding: 22));
    expect(find.textContaining('this year'), findsNothing);
  });

  testWidgets(
      'settings switches reflect current opt-ins and write through on toggle',
      (tester) async {
    bool? leaderboardWrite;
    bool? badgeWrite;
    await _pumpDashboard(
      tester,
      insider: _activeInsider(
          publicLeaderboardOptIn: true, profileBadgeOptIn: false),
      setLeaderboardOptIn: (v) async => leaderboardWrite = v,
      setProfileBadgeOptIn: (v) async => badgeWrite = v,
    );

    final leaderboardSwitchFinder =
        find.byKey(const ValueKey('insider_leaderboard_switch'));
    final badgeSwitchFinder =
        find.byKey(const ValueKey('insider_profile_badge_switch'));
    await tester.ensureVisible(leaderboardSwitchFinder);
    await tester.pump();

    final leaderboardSwitch = tester.widget<SwitchListTile>(leaderboardSwitchFinder);
    final badgeSwitch = tester.widget<SwitchListTile>(badgeSwitchFinder);
    expect(leaderboardSwitch.value, isTrue);
    expect(badgeSwitch.value, isFalse);

    await tester.tap(leaderboardSwitchFinder);
    await tester.pump();
    expect(leaderboardWrite, isFalse);

    await tester.ensureVisible(badgeSwitchFinder);
    await tester.pump();
    await tester.tap(badgeSwitchFinder);
    await tester.pump();
    expect(badgeWrite, isTrue);
  });

  testWidgets(
      'See full leaderboard pushes the leaderboard page builder (Task F6)',
      (tester) async {
    // leaderboardPageBuilder is a test seam (like insiders_info_page.dart's
    // dashboardPageBuilder) so this test never constructs the real
    // InsidersLeaderboardPage — which, unwrapped, reaches for
    // InsiderService's live Firebase streams in its own default wiring.
    await tester.pumpWidget(MaterialApp(
      home: InsiderDashboardPage(
        insiderStream: Stream<Insider?>.value(_activeInsider()),
        referralsStream: Stream<List<InsiderReferral>>.value(const []),
        leaderboardPageBuilder: () =>
            const Scaffold(body: Center(child: Text('stub leaderboard'))),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(
        find.byKey(const ValueKey('insider_dashboard_leaderboard_button')));
    await tester.tap(
        find.byKey(const ValueKey('insider_dashboard_leaderboard_button')));
    await tester.pumpAndSettle();

    expect(find.text('stub leaderboard'), findsOneWidget);
  });

  testWidgets('renders a suspended notice defensively when status flips while open',
      (tester) async {
    await _pumpDashboard(tester,
        insider: _activeInsider(status: 'suspended'));

    expect(find.textContaining('suspended'), findsOneWidget);
    expect(find.text('Total Referred'), findsNothing);
  });
}
