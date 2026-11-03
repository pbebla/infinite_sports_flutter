// Paid access (season pass, spec 2026-11-01) — the fan app's pure data
// layer: the Config/Access block (§3), the Access/<uid> record (§4), the
// AccessClaims payload (§6), the Checkout callable's result and the paywall
// copy fill (§9). RTDB Map/List coercion tolerance as always; no Firebase.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

void main() {
  group('accessConfigFromNode (Config/Access, spec §3)', () {
    test('absent / malformed → free mode with every default', () {
      for (final node in [null, 'pass', 7, <Object>[], <String, Object>{}]) {
        final cfg = accessConfigFromNode(node);
        expect(cfg.mode, FantasyAccessMode.free, reason: '$node');
        expect(cfg.isPass, isFalse);
        expect(cfg.amountDollars, 0);
        expect(cfg.venmo, isTrue);
        expect(cfg.zelle, isFalse);
        expect(cfg.card, isTrue);
        expect(cfg.headline, 'Join Infinite Fantasy');
        expect(cfg.body,
            'A season pass for {season} Fantasy is {amount}. Pay once, play the whole season.');
        expect(cfg.button, 'Pay with card');
      }
      expect(FantasyAccessConfig.free.isPass, isFalse);
    });

    test('pass mode with price, methods and copy', () {
      final cfg = accessConfigFromNode({
        'Mode': 'pass',
        'AmountDollars': 10,
        'Methods': {'Venmo': false, 'Zelle': true, 'Card': true},
        'Copy': {
          'Headline': 'Season 16 is here',
          'Body': 'It costs {amount} for {season}.',
          'Button': 'Pay now',
        },
        'ChangedAt': 1,
        'ChangedBy': 'admin',
      });
      expect(cfg.mode, FantasyAccessMode.pass);
      expect(cfg.isPass, isTrue);
      expect(cfg.amountDollars, 10);
      expect(cfg.venmo, isFalse);
      expect(cfg.zelle, isTrue);
      expect(cfg.card, isTrue);
      expect(cfg.headline, 'Season 16 is here');
      expect(cfg.body, 'It costs {amount} for {season}.');
      expect(cfg.button, 'Pay now');
    });

    test('an unknown Mode is free; half dollars keep their cents', () {
      expect(accessConfigFromNode({'Mode': 'PASS'}).mode,
          FantasyAccessMode.free);
      expect(accessConfigFromNode({'Mode': 'monthly'}).mode,
          FantasyAccessMode.free);
      expect(accessConfigFromNode({'AmountDollars': 12.5}).amountDollars,
          12.5);
    });

    test('bad types fall back field by field, never the whole block', () {
      final cfg = accessConfigFromNode({
        'Mode': 'pass',
        'AmountDollars': 'ten',
        'Methods': 'yes',
        'Copy': ['x'],
      });
      expect(cfg.isPass, isTrue);
      expect(cfg.amountDollars, 0);
      expect(cfg.venmo, isTrue);
      expect(cfg.zelle, isFalse);
      expect(cfg.card, isTrue);
      expect(cfg.headline, 'Join Infinite Fantasy');

      final partial = accessConfigFromNode({
        'Mode': 'pass',
        'AmountDollars': -3,
        'Methods': {'Venmo': 'true', 'Card': false},
        'Copy': {'Headline': '   ', 'Body': 7},
      });
      expect(partial.amountDollars, 0, reason: 'negative → 0');
      expect(partial.venmo, isTrue, reason: 'a string is not a bool');
      expect(partial.card, isFalse);
      expect(partial.headline, 'Join Infinite Fantasy',
          reason: 'blank copy → default');
      expect(partial.body, contains('{season}'));
    });

    test('NaN / infinite amounts read as 0', () {
      expect(accessConfigFromNode({'AmountDollars': double.nan}).amountDollars,
          0);
      expect(
          accessConfigFromNode({'AmountDollars': double.infinity})
              .amountDollars,
          0);
    });
  });

  group('configStateFromNode carries .access (no second subscription)', () {
    test('absent Access block → free', () {
      final state = configStateFromNode(FantasyConfig.futsalDefault().toMap())!;
      expect(state.access.isPass, isFalse);
      expect(state.access, same(FantasyAccessConfig.free));
    });

    test('a pass-mode Access block rides the same Config node', () {
      final node = FantasyConfig.futsalDefault().toMap()
        ..['Access'] = {
          'Mode': 'pass',
          'AmountDollars': 10,
          'Methods': {'Venmo': true, 'Zelle': false, 'Card': true},
        };
      final state = configStateFromNode(node)!;
      expect(state.access.isPass, isTrue);
      expect(state.access.amountDollars, 10);
      expect(state.config.budgetTenths, 500);
    });

    test('the constructor defaults to free (existing callers untouched)', () {
      final state = FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open);
      expect(state.access.isPass, isFalse);
    });
  });

  group('accessRecordFromNode (Access/<uid>, spec §4)', () {
    test('absent / malformed / unknown status → null (= none)', () {
      expect(accessRecordFromNode(null), isNull);
      expect(accessRecordFromNode('active'), isNull);
      expect(accessRecordFromNode(<String, Object>{}), isNull);
      expect(accessRecordFromNode({'Status': 'paid'}), isNull);
      expect(accessRecordFromNode({'Status': 'ACTIVE'}), isNull);
    });

    test('active card record', () {
      final rec = accessRecordFromNode({
        'Status': 'active',
        'Via': 'card',
        'AmountCents': 1000,
        'PaidAt': 1700000000000,
        'By': 'stripe',
        'StripePaymentIntent': 'pi_1',
        'Notified': {'active_1700000000000': true},
      })!;
      expect(rec.status, FantasyAccessStatus.active);
      expect(rec.via, 'card');
      expect(rec.amountCents, 1000);
      expect(rec.paidAt, 1700000000000);
      expect(rec.isActive, isTrue);
    });

    test('pending and revoked, with tolerant fields', () {
      final pending = accessRecordFromNode({
        'Status': 'pending',
        'Via': 'venmo',
        'AmountCents': '1000',
        'PaidAt': null,
      })!;
      expect(pending.status, FantasyAccessStatus.pending);
      expect(pending.via, 'venmo');
      expect(pending.amountCents, 0, reason: 'a string is not a number');
      expect(pending.paidAt, isNull);
      expect(pending.isActive, isFalse);

      final revoked = accessRecordFromNode({
        'Status': 'revoked',
        'Via': 'card',
        'AmountCents': 1000,
        'PaidAt': 5,
        'RefundedAt': 9,
        'RevokedBy': 'stripe',
      })!;
      expect(revoked.status, FantasyAccessStatus.revoked);
      expect(revoked.isActive, isFalse);
    });

    test('a granted record is just active — the fan app never sees why', () {
      final rec = accessRecordFromNode({
        'Status': 'active',
        'Via': 'granted',
        'AmountCents': 0,
        'PaidAt': 1,
        'By': 'adminUid',
        'Reason': 'friend of the league',
      })!;
      expect(rec.isActive, isTrue);
      expect(rec.via, 'granted');
    });
  });

  group('FantasyAccessState', () {
    test('none / degraded / from a record', () {
      expect(FantasyAccessState.none.status, FantasyAccessStatus.none);
      expect(FantasyAccessState.none.isActive, isFalse);
      expect(FantasyAccessState.none.degraded, isFalse);

      const degraded = FantasyAccessState(degraded: true);
      expect(degraded.status, FantasyAccessStatus.none);
      expect(degraded.degraded, isTrue);

      final active = FantasyAccessState(
          record: accessRecordFromNode({'Status': 'active', 'Via': 'venmo'}));
      expect(active.status, FantasyAccessStatus.active);
      expect(active.isActive, isTrue);
      expect(active.degraded, isFalse);
    });

    test('accessStateFromNode wraps the parser', () {
      expect(accessStateFromNode(null).status, FantasyAccessStatus.none);
      expect(accessStateFromNode({'Status': 'pending'}).status,
          FantasyAccessStatus.pending);
    });
  });

  group('accessClaimPayload (AccessClaims/<uid>/<key>, spec §6)', () {
    test('the exact shape the rules validate', () {
      final payload = accessClaimPayload(
        method: FantasyAccessMethod.venmo,
        amountDollars: 10,
        note: 'Fantasy Futsal S16 Ava',
        at: 'SERVER_TS',
      );
      expect(payload, {
        'Method': 'venmo',
        'AmountDollars': 10,
        'Note': 'Fantasy Futsal S16 Ava',
        'At': 'SERVER_TS',
      });
      expect(payload['AmountDollars'], isA<int>(),
          reason: 'whole dollars write as an integer');
    });

    test('zelle, half dollars, and a note clipped to 120 chars', () {
      final payload = accessClaimPayload(
        method: FantasyAccessMethod.zelle,
        amountDollars: 12.5,
        note: 'x' * 200,
        at: 1,
      );
      expect(payload['Method'], 'zelle');
      expect(payload['AmountDollars'], 12.5);
      expect((payload['Note'] as String).length, 120);
    });

    test('a fan can only claim Venmo or Zelle (cash is Manager-only)', () {
      // The brief spells the accessor `db`; the enum's field is `key`.
      expect(FantasyAccessMethod.values.map((m) => m.key), ['venmo', 'zelle']);
    });

    test('a negative amount never reaches the database', () {
      expect(
          () => accessClaimPayload(
              method: FantasyAccessMethod.venmo,
              amountDollars: -1,
              note: '',
              at: 1),
          throwsArgumentError);
    });
  });

  group('accessClaimNote', () {
    test('"Fantasy <sport> S<season> <display name>"', () {
      expect(accessClaimNote(sport: 'Futsal', season: '16', displayName: 'Ava'),
          'Fantasy Futsal S16 Ava');
      expect(
          accessClaimNote(sport: 'Futsal', season: '16', displayName: '  '),
          'Fantasy Futsal S16');
      expect(
          accessClaimNote(
                  sport: 'Futsal', season: '16', displayName: 'n' * 200)
              .length,
          lessThanOrEqualTo(120));
    });
  });

  group('checkoutUrlFromResult (createFantasyCheckoutSession)', () {
    test('{url} → the Uri', () {
      final uri = checkoutUrlFromResult(
          {'url': 'https://checkout.stripe.com/c/pay/cs_test_1'});
      expect(uri, Uri.parse('https://checkout.stripe.com/c/pay/cs_test_1'));
    });

    test('{alreadyActive:true} → null (the card dismisses on its own)', () {
      expect(checkoutUrlFromResult({'alreadyActive': true}), isNull);
      expect(checkoutUrlFromResult({'alreadyActive': true, 'url': 'x'}),
          isNull);
    });

    test('anything else is an error, never a blank launch', () {
      expect(() => checkoutUrlFromResult(null), throwsStateError);
      expect(() => checkoutUrlFromResult({'url': ''}), throwsStateError);
      expect(() => checkoutUrlFromResult({'url': 'ftp://x'}), throwsStateError);
      expect(() => checkoutUrlFromResult({'url': 'not a url'}),
          throwsStateError);
      expect(() => checkoutUrlFromResult('https://x'), throwsStateError);
    });
  });

  group('paywall copy (spec §9)', () {
    test('formatAccessDollars: whole dollars plain, cents when present', () {
      expect(formatAccessDollars(10), r'$10');
      expect(formatAccessDollars(10.5), r'$10.50');
      expect(formatAccessDollars(0), r'$0');
    });

    test('accessSeasonLabel', () {
      expect(accessSeasonLabel('Futsal', '16'), 'Futsal Season 16');
    });

    test('fillAccessCopy replaces {season} and {amount}; unknown placeholders '
        'stay literal', () {
      expect(
          fillAccessCopy(
              'A season pass for {season} is {amount}. {name}',
              season: 'Futsal Season 16',
              amount: r'$10'),
          r'A season pass for Futsal Season 16 is $10. {name}');
    });

    test('FantasyAccessConfig.priceLabel / bodyFor', () {
      final cfg = accessConfigFromNode({'Mode': 'pass', 'AmountDollars': 10});
      expect(cfg.priceLabel, r'$10');
      expect(cfg.bodyFor(sport: 'Futsal', season: '16'),
          r'A season pass for Futsal Season 16 Fantasy is $10. Pay once, play the whole season.');
      expect(cfg.headlineFor(sport: 'Futsal', season: '16'),
          'Join Infinite Fantasy');
    });
  });
}
