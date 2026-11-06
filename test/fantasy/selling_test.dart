// The FPL selling rule (spec §4). The (purchase, current) -> sell table below
// is the SAME table as functions/src/lib/fantasy/selling.test.ts: the two
// twins must agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';

void main() {
  // (purchase, current) -> sell, in tenths of $1M.
  const sellTable = <List<int>>[
    [80, 90, 85],
    [80, 85, 82],
    [80, 81, 80],
    [80, 80, 80],
    [80, 70, 70],
    [40, 150, 95],
    [150, 40, 40],
  ];

  group('sellPriceTenths', () {
    for (final row in sellTable) {
      test('(${row[0]}, ${row[1]}) -> ${row[2]}', () {
        expect(sellPriceTenths(purchaseTenths: row[0], currentTenths: row[1]),
            row[2]);
      });
    }
  });

  group('saleBaselineFromNode', () {
    test('parses ForGw, Prices and RealizedTenths', () {
      final b = saleBaselineFromNode({
        'ForGw': 4,
        'Prices': {'A': 80, 'B': 60},
        'RealizedTenths': 5,
      })!;
      expect(b.forGw, 4);
      expect(b.prices, {'A': 80, 'B': 60});
      expect(b.realizedTenths, 5);
    });
    test('null when not a map or ForGw is missing', () {
      expect(saleBaselineFromNode(null), isNull);
      expect(saleBaselineFromNode('nope'), isNull);
      expect(saleBaselineFromNode(7), isNull);
      expect(saleBaselineFromNode(<dynamic>[]), isNull);
      expect(
          saleBaselineFromNode({
            'Prices': {'A': 80}
          }),
          isNull);
    });
    test('drops non-int Prices values; absent RealizedTenths is 0', () {
      final b = saleBaselineFromNode({
        'ForGw': 2,
        'Prices': {'A': 80, 'B': 'x', 'C': null, 'D': 7.5},
      })!;
      expect(b.prices, {'A': 80});
      expect(b.realizedTenths, 0);
    });
    test('absent Prices is an empty map', () {
      final b = saleBaselineFromNode({'ForGw': 2})!;
      expect(b.prices, isEmpty);
    });
    // [M3] The server keeps the baseline it replaced under `Prev` so a
    // rewind can restore it. The app only ever reads the current one.
    test('a `Prev` child is ignored: the current baseline is what counts', () {
      final b = saleBaselineFromNode({
        'ForGw': 4,
        'Prices': {'A': 80, 'B': 60},
        'RealizedTenths': 5,
        'Prev': {
          'ForGw': 3,
          'Prices': {'A': 70, 'C': 90},
          'RealizedTenths': -20,
        },
      })!;
      expect(b.forGw, 4);
      expect(b.prices, {'A': 80, 'B': 60});
      expect(b.realizedTenths, 5);
    });
    test('a node holding only `Prev` is not a baseline', () {
      expect(
          saleBaselineFromNode({
            'Prev': {
              'ForGw': 3,
              'Prices': {'A': 70},
            },
          }),
          isNull);
      expect(
          saleBaselineStateFromNode({
            'Prev': {'ForGw': 3, 'Prices': {'A': 70}},
          }).degraded,
          isTrue);
    });
    test('the feed state of a node with a `Prev` child is the current one',
        () {
      final state = saleBaselineStateFromNode({
        'ForGw': 4,
        'Prices': {'A': 80},
        'Prev': {'ForGw': 3, 'Prices': {'A': 70}},
      });
      expect(state.loaded, isTrue);
      expect(state.degraded, isFalse);
      expect(state.baseline!.forGw, 4);
      expect(state.baseline!.prices, {'A': 80});
    });
  });

  group('saleBaselineStateFromNode', () {
    test('absent node: a first squad — loaded, no baseline, not degraded', () {
      final s = saleBaselineStateFromNode(null);
      expect(s.loaded, isTrue);
      expect(s.baseline, isNull);
      expect(s.degraded, isFalse);
    });
    test('a readable node: loaded with its baseline', () {
      final s = saleBaselineStateFromNode({
        'ForGw': 4,
        'Prices': {'A': 80},
        'RealizedTenths': -3,
      });
      expect(s.loaded, isTrue);
      expect(s.degraded, isFalse);
      expect(s.baseline!.forGw, 4);
      expect(s.baseline!.prices, {'A': 80});
      expect(s.baseline!.realizedTenths, -3);
    });
    test('a present but unreadable node is degraded, never "no sales"', () {
      for (final node in <Object>[
        'junk',
        {
          'Prices': {'A': 80}
        },
      ]) {
        final s = saleBaselineStateFromNode(node);
        expect(s.degraded, isTrue, reason: '$node');
        expect(s.loaded, isFalse, reason: '$node');
        expect(s.baseline, isNull, reason: '$node');
      }
    });
  });

  group('realizedNowTenths', () {
    const b =
        SaleBaseline(forGw: 3, prices: {'A': 80, 'B': 60}, realizedTenths: 5);
    const current = {'A': 90, 'B': 50};

    test('squad {A}: B sold at a loss -> 5 + (50 - 60) = -5', () {
      expect(realizedNowTenths(b, ['A'], current), -5);
    });
    test('squad {B}: A sold at 85 -> 5 + (85 - 80) = 10', () {
      expect(realizedNowTenths(b, ['B'], current), 10);
    });
    test('squad {A, B}: nobody sold -> the carried 5', () {
      expect(realizedNowTenths(b, ['A', 'B'], current), 5);
    });
    test('squad {} : both sold -> 5 + 5 + (-10) = 0', () {
      expect(realizedNowTenths(b, const <String>[], current), 0);
    });
    test('a sold player missing from current prices adds 0', () {
      expect(realizedNowTenths(b, ['B'], const {'B': 50}), 5);
    });
    test(
        'a sold player priced 0 or below adds 0 (server judgeSale parity: '
        'no usable price, never a "sale at 0")', () {
      expect(realizedNowTenths(b, ['B'], const {'A': 0, 'B': 50}), 5);
      expect(realizedNowTenths(b, ['B'], const {'A': -10, 'B': 50}), 5);
      expect(realizedNowTenths(b, const <String>[], const {'A': 0, 'B': 0}), 5);
    });
    test('ids outside the baseline never count', () {
      expect(realizedNowTenths(b, ['A', 'B', 'Z'], current), 5);
    });
    test('null baseline -> 0', () {
      expect(realizedNowTenths(null, ['A'], current), 0);
    });
  });

  group('buyPriceTenths', () {
    const b =
        SaleBaseline(forGw: 3, prices: {'A': 80, 'B': 60}, realizedTenths: 0);
    test('a baseline id re-adds at its baseline price, current differs', () {
      expect(buyPriceTenths(b, 'A', 90), 80);
      expect(buyPriceTenths(b, 'B', 40), 60);
    });
    test('any other id buys at the current price', () {
      expect(buyPriceTenths(b, 'Z', 70), 70);
    });
    test('null baseline buys at the current price', () {
      expect(buyPriceTenths(null, 'A', 90), 90);
    });
  });
}
