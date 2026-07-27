// Widget tests for the public Insiders leaderboard page (Task F6):
// lib/insiders/insiders_leaderboard_page.dart. Firebase-free: `insidersStream`
// / `referralsStream` / `nowMs` test seams replace the live
// `/Insiders` + `/Referrals` streams and the wall clock — mirrors the
// injectable-stream seam pattern in test/insider_dashboard_page_test.dart
// (Task F4) and test/insiders_info_page_test.dart (Task F2).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/insiders/insiders_leaderboard_page.dart';
import 'package:infinite_sports_flutter/model/insider.dart';

/// Finds text within a specific leaderboard row (by insider uid) — avoids
/// ambiguity with the same digits appearing in the program-stats header.
Finder _textInRow(String uid, String text) => find.descendant(
      of: find.byKey(ValueKey('insider_leaderboard_row_$uid')),
      matching: find.text(text),
    );

final int _nowMs = DateTime.utc(2026, 7, 27, 12).millisecondsSinceEpoch;

Insider _insider(
  String uid, {
  String name = '',
  String status = 'active',
  int tier = 0,
  int totalReferred = 0,
  bool publicLeaderboardOptIn = true,
}) {
  return Insider.fromFirebase(uid, {
    'Name': name,
    'Status': status,
    'Tier': tier,
    'TotalReferred': totalReferred,
    'PublicLeaderboardOptIn': publicLeaderboardOptIn,
  })!;
}

InsiderReferral _referral({
  required String id,
  required String insiderUid,
  String sport = 'Futsal',
  String state = 'counted',
  int countedAt = 0,
}) {
  return InsiderReferral.fromFirebase(id, {
    'InsiderUid': insiderUid,
    'Sport': sport,
    'State': state,
    'CountedAt': countedAt,
  })!;
}

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, Insider> insiders,
  List<InsiderReferral> referrals = const [],
  int? nowMs,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: InsidersLeaderboardPage(
      insidersStream: Stream<Map<String, Insider>>.value(insiders),
      referralsStream: Stream<List<InsiderReferral>>.value(referrals),
      nowMs: nowMs ?? _nowMs,
    ),
  ));
  // Two nested StreamBuilders each need a tick to consume the injected
  // single-value streams (same as insider_dashboard_page_test.dart).
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows a skeleton while the streams are still loading',
      (tester) async {
    // Controllers that never emit/close keep StreamBuilder in the
    // `waiting` connection state — unlike Stream.empty(), which completes
    // immediately and would (correctly) render the loaded empty state.
    final insidersController = StreamController<Map<String, Insider>>();
    final referralsController = StreamController<List<InsiderReferral>>();
    addTearDown(insidersController.close);
    addTearDown(referralsController.close);

    await tester.pumpWidget(MaterialApp(
      home: InsidersLeaderboardPage(
        insidersStream: insidersController.stream,
        referralsStream: referralsController.stream,
      ),
    ));
    await tester.pump();
    expect(find.text('No insiders yet'), findsNothing);
  });

  testWidgets('empty program shows "No insiders yet"', (tester) async {
    await _pump(tester, insiders: {});
    expect(find.text('No insiders yet'), findsOneWidget);
  });

  testWidgets('opted-out insiders never appear, even though they are active',
      (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'Alex', totalReferred: 9),
      'u2': _insider('u2',
          name: 'Beth', totalReferred: 20, publicLeaderboardOptIn: false),
    });
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Beth'), findsNothing);
  });

  testWidgets('program stats header shows totals', (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'Alex', status: 'active'),
      'u2': _insider('u2', name: 'Beth', status: 'pending'),
    }, referrals: [
      _referral(id: 'r1', insiderUid: 'u1', countedAt: _nowMs),
      _referral(id: 'r2', insiderUid: 'u1', state: 'voided', countedAt: _nowMs),
    ]);
    // 1 active insider (u2 is pending), 1 currently-counted referral.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('renders rank, name, tier label, and referral count',
      (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'Alex', tier: 2, totalReferred: 14),
    });
    expect(find.text('Alex'), findsOneWidget);
    expect(find.textContaining('Silver'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('per-sport breakdown line renders for a row', (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'Alex', totalReferred: 3),
    }, referrals: [
      _referral(id: 'r1', insiderUid: 'u1', sport: 'Futsal', countedAt: 1),
      _referral(id: 'r2', insiderUid: 'u1', sport: 'Futsal', countedAt: 2),
      _referral(id: 'r3', insiderUid: 'u1', sport: 'Basketball', countedAt: 3),
    ]);
    expect(find.textContaining('Futsal 2'), findsOneWidget);
    expect(find.textContaining('Basketball 1'), findsOneWidget);
  });

  testWidgets('Top 3 rows get a medal accent, 4th does not', (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'First', totalReferred: 40),
      'u2': _insider('u2', name: 'Second', totalReferred: 30),
      'u3': _insider('u3', name: 'Third', totalReferred: 20),
      'u4': _insider('u4', name: 'Fourth', totalReferred: 10),
    });
    expect(find.byKey(const ValueKey('insider_leaderboard_medal_1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('insider_leaderboard_medal_2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('insider_leaderboard_medal_3')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('insider_leaderboard_medal_4')),
        findsNothing);
  });

  testWidgets(
      'switching period to This Month re-ranks using /Referrals instead of TotalReferred',
      (tester) async {
    await _pump(tester, insiders: {
      // Huge lifetime total, but nothing counted this month.
      'u1': _insider('u1', name: 'LifetimeLeader', totalReferred: 100),
      // Small lifetime total, but 3 counted this month.
      'u2': _insider('u2', name: 'MonthLeader', totalReferred: 3),
    }, referrals: [
      _referral(
          id: 'r1',
          insiderUid: 'u1',
          countedAt: DateTime.utc(2025, 1, 1).millisecondsSinceEpoch),
      _referral(
          id: 'r2',
          insiderUid: 'u2',
          countedAt: DateTime.utc(2026, 7, 10).millisecondsSinceEpoch),
      _referral(
          id: 'r3',
          insiderUid: 'u2',
          countedAt: DateTime.utc(2026, 7, 11).millisecondsSinceEpoch),
      _referral(
          id: 'r4',
          insiderUid: 'u2',
          countedAt: DateTime.utc(2026, 7, 12).millisecondsSinceEpoch),
    ]);

    // All-time: LifetimeLeader (100) ranks above MonthLeader (3).
    expect(_textInRow('u1', '100'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('insider_leaderboard_period_thisMonth')));
    await tester.pump();

    // This month: LifetimeLeader has 0 counted this month, MonthLeader has 3.
    expect(_textInRow('u1', '0'), findsOneWidget);
    expect(_textInRow('u2', '3'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });

  testWidgets('sport filter chip narrows the ranked count to that sport',
      (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'Alex', totalReferred: 99),
    }, referrals: [
      _referral(id: 'r1', insiderUid: 'u1', sport: 'Futsal', countedAt: 1),
      _referral(
          id: 'r2', insiderUid: 'u1', sport: 'Basketball', countedAt: 2),
    ]);

    await tester.tap(
        find.byKey(const ValueKey('insider_leaderboard_sport_chip_Futsal')));
    await tester.pump();

    expect(_textInRow('u1', '1'), findsOneWidget); // just the Futsal referral
    expect(find.text('99'), findsNothing);
  });

  testWidgets('tier dropdown filters to the selected tier only',
      (tester) async {
    await _pump(tester, insiders: {
      'u1': _insider('u1', name: 'BronzeAlex', tier: 1, totalReferred: 5),
      'u2': _insider('u2', name: 'GoldBeth', tier: 3, totalReferred: 15),
    });

    await tester
        .tap(find.byKey(const ValueKey('insider_leaderboard_tier_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold').last);
    await tester.pumpAndSettle();

    expect(find.text('GoldBeth'), findsOneWidget);
    expect(find.text('BronzeAlex'), findsNothing);
  });
}
