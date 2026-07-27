// Pure-logic tests for the public Insiders leaderboard (Task F6):
// lib/model/insider.dart's insidersFromNode, leaderboardRows, and
// programStats. TDD failing-first: written before the implementation
// exists.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §8
// (public leaderboard — rank by counted referrals, sport/tier/period
// filters, opt-out respected, program-wide stats header).

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/model/insider.dart';

Insider _insider(
  String uid, {
  String status = 'active',
  int tier = 0,
  int totalReferred = 0,
  bool publicLeaderboardOptIn = true,
  String name = '',
}) {
  return Insider.fromFirebase(uid, {
    'Status': status,
    'Tier': tier,
    'TotalReferred': totalReferred,
    'PublicLeaderboardOptIn': publicLeaderboardOptIn,
    'Name': name,
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

void main() {
  group('insidersFromNode', () {
    test('parses an /Insiders root node into {uid: Insider}, skipping malformed entries', () {
      final map = insidersFromNode({
        'u1': {'Status': 'active', 'Tier': 2},
        'u2': {'Status': 'pending'},
        'u3': 'not a map',
      });
      expect(map.keys.toSet(), {'u1', 'u2'});
      expect(map['u1']!.tier, 2);
      expect(map['u1']!.isActive, isTrue);
    });

    test('non-Map root returns an empty map', () {
      expect(insidersFromNode(null), isEmpty);
      expect(insidersFromNode('nope'), isEmpty);
    });
  });

  group('leaderboardRows — eligibility (active + opted-in only)', () {
    test('excludes pending/suspended/declined insiders', () {
      final insiders = [
        _insider('u1', status: 'active', totalReferred: 5),
        _insider('u2', status: 'pending', totalReferred: 9),
        _insider('u3', status: 'suspended', totalReferred: 9),
        _insider('u4', status: 'declined', totalReferred: 9),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: const [],
        nowMs: 1000000,
      );
      expect(rows.map((r) => r.uid).toSet(), {'u1'});
    });

    test('excludes opted-out insiders even if active', () {
      final insiders = [
        _insider('u1', totalReferred: 5, publicLeaderboardOptIn: true),
        _insider('u2', totalReferred: 9, publicLeaderboardOptIn: false),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: const [],
        nowMs: 1000000,
      );
      expect(rows.map((r) => r.uid).toSet(), {'u1'});
    });
  });

  group('leaderboardRows — all-time ranking (uses TotalReferred)', () {
    test('ranks by TotalReferred desc when no sport filter', () {
      final insiders = [
        _insider('u1', name: 'Alex', totalReferred: 5),
        _insider('u2', name: 'Beth', totalReferred: 20),
        _insider('u3', name: 'Cy', totalReferred: 12),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: const [],
        nowMs: 1000000,
      );
      expect(rows.map((r) => r.uid).toList(), ['u2', 'u3', 'u1']);
      expect(rows.map((r) => r.referralCount).toList(), [20, 12, 5]);
    });

    test('stable tie-break: equal counts sort by name ascending', () {
      final insiders = [
        _insider('u1', name: 'Zed', totalReferred: 10),
        _insider('u2', name: 'Amy', totalReferred: 10),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: const [],
        nowMs: 1000000,
      );
      expect(rows.map((r) => r.name).toList(), ['Amy', 'Zed']);
    });
  });

  group('leaderboardRows — sport filter (counts only that sport\'s referrals)', () {
    test('all-time + sport filter derives count from referrals, not TotalReferred', () {
      final insiders = [
        _insider('u1', name: 'Alex', totalReferred: 50), // cross-sport lifetime total
      ];
      final referrals = [
        _referral(id: 'r1', insiderUid: 'u1', sport: 'Futsal', countedAt: 100),
        _referral(id: 'r2', insiderUid: 'u1', sport: 'Futsal', countedAt: 200),
        _referral(id: 'r3', insiderUid: 'u1', sport: 'Basketball', countedAt: 300),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: referrals,
        sportFilter: 'Futsal',
        nowMs: 1000000,
      );
      expect(rows.single.referralCount, 2); // NOT 50
    });

    test('voided referrals never count toward the sport-filtered count', () {
      final insiders = [_insider('u1', totalReferred: 50)];
      final referrals = [
        _referral(id: 'r1', insiderUid: 'u1', sport: 'Futsal', state: 'counted', countedAt: 100),
        _referral(id: 'r2', insiderUid: 'u1', sport: 'Futsal', state: 'voided', countedAt: 200),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: referrals,
        sportFilter: 'Futsal',
        nowMs: 1000000,
      );
      expect(rows.single.referralCount, 1);
    });
  });

  group('leaderboardRows — period filter (this-month / this-year from /Referrals)', () {
    test('thisMonth only counts referrals CountedAt within the current UTC month', () {
      final now = DateTime.utc(2026, 7, 27, 12);
      final nowMs = now.millisecondsSinceEpoch;
      final insiders = [_insider('u1', totalReferred: 99)];
      final referrals = [
        _referral(
            id: 'r1',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 7, 1).millisecondsSinceEpoch), // this month
        _referral(
            id: 'r2',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 6, 30).millisecondsSinceEpoch), // last month
        _referral(
            id: 'r3',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 7, 27, 11).millisecondsSinceEpoch), // this month
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: referrals,
        periodFilter: LeaderboardPeriod.thisMonth,
        nowMs: nowMs,
      );
      expect(rows.single.referralCount, 2);
    });

    test('thisYear counts referrals CountedAt within the current UTC year, across months', () {
      final now = DateTime.utc(2026, 7, 27, 12);
      final nowMs = now.millisecondsSinceEpoch;
      final insiders = [_insider('u1', totalReferred: 99)];
      final referrals = [
        _referral(
            id: 'r1',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 1, 5).millisecondsSinceEpoch), // this year
        _referral(
            id: 'r2',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2025, 12, 31).millisecondsSinceEpoch), // last year
        _referral(
            id: 'r3',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 7, 27, 11).millisecondsSinceEpoch), // this year
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: referrals,
        periodFilter: LeaderboardPeriod.thisYear,
        nowMs: nowMs,
      );
      expect(rows.single.referralCount, 2);
    });

    test('voided referrals never count in a period window', () {
      final now = DateTime.utc(2026, 7, 27, 12);
      final insiders = [_insider('u1')];
      final referrals = [
        _referral(
            id: 'r1',
            insiderUid: 'u1',
            state: 'voided',
            countedAt: DateTime.utc(2026, 7, 10).millisecondsSinceEpoch),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: referrals,
        periodFilter: LeaderboardPeriod.thisMonth,
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(rows.single.referralCount, 0);
    });
  });

  group('leaderboardRows — tier filter', () {
    test('only includes insiders at the exact tier', () {
      final insiders = [
        _insider('u1', tier: 1, totalReferred: 5),
        _insider('u2', tier: 3, totalReferred: 15),
        _insider('u3', tier: 3, totalReferred: 16),
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: const [],
        tierFilter: 3,
        nowMs: 1000000,
      );
      expect(rows.map((r) => r.uid).toSet(), {'u2', 'u3'});
    });
  });

  group('leaderboardRows — per-sport breakdown', () {
    test('breakdown reflects the period filter but not the sport filter', () {
      final insiders = [_insider('u1', totalReferred: 99)];
      final now = DateTime.utc(2026, 7, 27, 12);
      final referrals = [
        _referral(
            id: 'r1',
            insiderUid: 'u1',
            sport: 'Futsal',
            countedAt: DateTime.utc(2026, 7, 1).millisecondsSinceEpoch),
        _referral(
            id: 'r2',
            insiderUid: 'u1',
            sport: 'Basketball',
            countedAt: DateTime.utc(2026, 7, 2).millisecondsSinceEpoch),
        _referral(
            id: 'r3',
            insiderUid: 'u1',
            sport: 'Futsal',
            countedAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch), // outside this-month
      ];
      final rows = leaderboardRows(
        insiders: insiders,
        referrals: referrals,
        periodFilter: LeaderboardPeriod.thisMonth,
        sportFilter: 'Futsal',
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(rows.single.referralCount, 1); // sport-filtered count
      expect(rows.single.perSport, {'Futsal': 1, 'Basketball': 1}); // all sports, same period
    });
  });

  group('programStats', () {
    test('totalInsiders counts active insiders only', () {
      final insiders = [
        _insider('u1', status: 'active'),
        _insider('u2', status: 'active'),
        _insider('u3', status: 'pending'),
        _insider('u4', status: 'suspended'),
      ];
      final stats = programStats(insiders, const [], 1000000);
      expect(stats.totalInsiders, 2);
    });

    test('totalReferrals counts all currently-counted /Referrals (voided excluded)', () {
      final referrals = [
        _referral(id: 'r1', insiderUid: 'u1', state: 'counted'),
        _referral(id: 'r2', insiderUid: 'u1', state: 'counted'),
        _referral(id: 'r3', insiderUid: 'u2', state: 'voided'),
      ];
      final stats = programStats(const [], referrals, 1000000);
      expect(stats.totalReferrals, 2);
    });

    test('thisMonth counts counted referrals within the current UTC month', () {
      final now = DateTime.utc(2026, 7, 27, 12);
      final referrals = [
        _referral(
            id: 'r1',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 7, 1).millisecondsSinceEpoch),
        _referral(
            id: 'r2',
            insiderUid: 'u1',
            countedAt: DateTime.utc(2026, 6, 1).millisecondsSinceEpoch),
        _referral(
            id: 'r3',
            insiderUid: 'u1',
            state: 'voided',
            countedAt: DateTime.utc(2026, 7, 2).millisecondsSinceEpoch),
      ];
      final stats = programStats(const [], referrals, now.millisecondsSinceEpoch);
      expect(stats.thisMonth, 1);
    });
  });
}
