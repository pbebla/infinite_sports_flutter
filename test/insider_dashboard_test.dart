// Pure-logic tests for the Infinite Insiders dashboard helpers
// (lib/model/insider.dart, Task F4). TDD failing-first: written before the
// implementation exists.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §2
// (tiers/progress), §7 (fan dashboard contents + per-sport breakdown).

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/model/insider.dart';

void main() {
  group('nextTierThreshold', () {
    test('below Bronze -> 5', () {
      expect(nextTierThreshold(0), 5);
      expect(nextTierThreshold(4), 5);
    });
    test('at/after Bronze, below Silver -> 10', () {
      expect(nextTierThreshold(5), 10);
      expect(nextTierThreshold(9), 10);
    });
    test('at/after Silver, below Gold -> 15', () {
      expect(nextTierThreshold(10), 15);
      expect(nextTierThreshold(14), 15);
    });
    test('at/after Gold, below Platinum -> 20', () {
      expect(nextTierThreshold(15), 20);
      expect(nextTierThreshold(19), 20);
    });
    test('at/after Platinum, below Infinite -> 25', () {
      expect(nextTierThreshold(20), 25);
      expect(nextTierThreshold(24), 25);
    });
    test('Infinite (>=25) has no further ceiling -> 25', () {
      expect(nextTierThreshold(25), 25);
      expect(nextTierThreshold(40), 25);
    });
  });

  group('tierProgress (0..1 fraction toward next threshold from previous)',
      () {
    test('0 -> 0.0 (start of Bronze climb)', () => expect(tierProgress(0), 0.0));
    test('3 of 5 toward Bronze -> 0.6', () => expect(tierProgress(3), 0.6));
    test('exactly at Bronze -> 0.0 toward Silver',
        () => expect(tierProgress(5), 0.0));
    test('7 -> 2 of 5 toward Silver -> 0.4', () => expect(tierProgress(7), 0.4));
    test('12 -> 2 of 5 toward Gold -> 0.4', () => expect(tierProgress(12), 0.4));
    test('24 -> 4 of 5 toward Infinite -> 0.8',
        () => expect(tierProgress(24), 0.8));
    test('Infinite reached (25) -> 1.0', () => expect(tierProgress(25), 1.0));
    test('well past Infinite (40) -> 1.0', () => expect(tierProgress(40), 1.0));
    test('negative standing clamps to 0.0', () => expect(tierProgress(-5), 0.0));
  });

  group('progressLabel', () {
    test('3 of 5 referrals to Bronze', () {
      expect(progressLabel(3), '3 of 5 referrals to Bronze');
    });
    test('0 of 5 referrals to Bronze', () {
      expect(progressLabel(0), '0 of 5 referrals to Bronze');
    });
    test('just reached Bronze -> 0 of 5 referrals to Silver', () {
      expect(progressLabel(5), '0 of 5 referrals to Silver');
    });
    test('7 -> 2 of 5 referrals to Silver', () {
      expect(progressLabel(7), '2 of 5 referrals to Silver');
    });
    test('12 -> 2 of 5 referrals to Gold', () {
      expect(progressLabel(12), '2 of 5 referrals to Gold');
    });
    test('24 -> 4 of 5 referrals to Infinite', () {
      expect(progressLabel(24), '4 of 5 referrals to Infinite');
    });
    test('Infinite reached at 25', () {
      expect(progressLabel(25), 'Infinite reached');
    });
    test('Infinite reached well past 25 too', () {
      expect(progressLabel(40), 'Infinite reached');
    });
  });

  group('inviteMessage', () {
    test('builds the exact share-sheet invite text with the code inserted', () {
      expect(
        inviteMessage('ZA4K9P2'),
        'Join Infinite Sports leagues & tournaments! Use my Insider code '
        'ZA4K9P2 when you register. Download the app: '
        'https://play.google.com/store/apps/details?'
        'id=com.infinitesports.Infinite_Sports_App',
      );
    });
  });

  group('sortReferralsNewestFirst (generic, keyed by CountedAt)', () {
    test('sorts descending by the extracted key', () {
      final result = sortReferralsNewestFirst<int>([3, 1, 2], (v) => v);
      expect(result, [3, 2, 1]);
    });

    test('does not mutate the input list', () {
      final input = [1, 3, 2];
      final result = sortReferralsNewestFirst<int>(input, (v) => v);
      expect(input, [1, 3, 2]); // unchanged
      expect(result, [3, 2, 1]);
    });

    test('sorts a list of InsiderReferral by countedAt, newest first', () {
      final r1 = InsiderReferral.fromFirebase('a', {
        'InsiderUid': 'u1',
        'CountedAt': 100,
      })!;
      final r2 = InsiderReferral.fromFirebase('b', {
        'InsiderUid': 'u1',
        'CountedAt': 300,
      })!;
      final r3 = InsiderReferral.fromFirebase('c', {
        'InsiderUid': 'u1',
        'CountedAt': 200,
      })!;
      final sorted = sortReferralsNewestFirst<InsiderReferral>(
          [r1, r2, r3], (r) => r.countedAt);
      expect(sorted.map((r) => r.id).toList(), ['b', 'c', 'a']);
    });
  });

  group('InsiderReferral.fromFirebase', () {
    test('returns null when raw is not a Map', () {
      expect(InsiderReferral.fromFirebase('r1', null), isNull);
      expect(InsiderReferral.fromFirebase('r1', 'nope'), isNull);
    });

    test('returns null when InsiderUid is missing/blank', () {
      expect(InsiderReferral.fromFirebase('r1', {'Sport': 'Futsal'}), isNull);
      expect(
          InsiderReferral.fromFirebase('r1', {'InsiderUid': ''}), isNull);
    });

    test('parses a full counted referral', () {
      final r = InsiderReferral.fromFirebase('r1', {
        'InsiderUid': 'u1',
        'ReferredUid': 'u2',
        'ReferredName': 'Sara Kim',
        'Sport': 'Futsal',
        'State': 'counted',
        'Verified': true,
        'CountedAt': 1000,
        'VoidedAt': 0,
        'Manual': false,
      });
      expect(r, isNotNull);
      expect(r!.id, 'r1');
      expect(r.insiderUid, 'u1');
      expect(r.referredUid, 'u2');
      expect(r.referredName, 'Sara Kim');
      expect(r.sport, 'Futsal');
      expect(r.state, 'counted');
      expect(r.isCounted, isTrue);
      expect(r.isVoided, isFalse);
      expect(r.verified, isTrue);
      expect(r.countedAt, 1000);
      expect(r.voidedAt, 0);
      expect(r.manual, isFalse);
    });

    test('parses a voided manual referral', () {
      final r = InsiderReferral.fromFirebase('r2', {
        'InsiderUid': 'u1',
        'State': 'voided',
        'VoidedAt': 2000,
        'Manual': true,
      });
      expect(r!.isVoided, isTrue);
      expect(r.isCounted, isFalse);
      expect(r.manual, isTrue);
      expect(r.voidedAt, 2000);
    });

    test('an unrecognized State falls back to counted', () {
      final r = InsiderReferral.fromFirebase(
          'r3', {'InsiderUid': 'u1', 'State': 'bogus'});
      expect(r!.state, 'counted');
    });
  });

  group('referralsFromNode', () {
    test('parses a /Referrals root node, skipping malformed entries', () {
      final list = referralsFromNode({
        'r1': {'InsiderUid': 'u1', 'Sport': 'Futsal', 'State': 'counted'},
        'r2': {'InsiderUid': 'u1', 'Sport': 'Basketball', 'State': 'voided'},
        'r3': 'not a map',
        'r4': {'Sport': 'Soccer'}, // missing InsiderUid
      });
      expect(list.length, 2);
      expect(list.map((r) => r.id).toSet(), {'r1', 'r2'});
    });

    test('non-Map root returns an empty list', () {
      expect(referralsFromNode(null), isEmpty);
      expect(referralsFromNode('nope'), isEmpty);
    });
  });

  group('perSportCounts (counted referrals only)', () {
    test('counts by sport, excluding voided referrals', () {
      final referrals = [
        InsiderReferral.fromFirebase('r1',
            {'InsiderUid': 'u1', 'Sport': 'Futsal', 'State': 'counted'})!,
        InsiderReferral.fromFirebase('r2',
            {'InsiderUid': 'u1', 'Sport': 'Futsal', 'State': 'counted'})!,
        InsiderReferral.fromFirebase('r3',
            {'InsiderUid': 'u1', 'Sport': 'Basketball', 'State': 'counted'})!,
        InsiderReferral.fromFirebase('r4',
            {'InsiderUid': 'u1', 'Sport': 'Futsal', 'State': 'voided'}),
      ].whereType<InsiderReferral>().toList();
      final counts = perSportCounts(referrals);
      expect(counts, {'Futsal': 2, 'Basketball': 1});
    });

    test('empty when there are no counted referrals', () {
      expect(perSportCounts(const []), isEmpty);
    });
  });

  group('infiniteMaintenanceLabel', () {
    test('formats the annual counter', () {
      expect(infiniteMaintenanceLabel(3), '3 of 5 this year');
      expect(infiniteMaintenanceLabel(0), '0 of 5 this year');
      expect(infiniteMaintenanceLabel(5), '5 of 5 this year');
    });
  });
}
