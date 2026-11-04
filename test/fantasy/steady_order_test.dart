// Live everywhere, Task 6 — SteadyOrder: the owner's steady-order rule ("like
// ESPN and the Premier League: numbers move, rows don't jump") as ONE pure
// helper, reused by the leaderboards (Task 6) and the Players market (Task 7).
// No widgets, no clock: a list is re-ordered at once when it is at the top
// (or has never been shown), and otherwise the newest order WAITS until the
// fan asks for it.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/steady_order.dart';

void main() {
  group('SteadyOrder.update', () {
    test('the first order is applied at once, even when not at the top', () {
      final order = SteadyOrder<String>();
      expect(order.applied, isEmpty);
      expect(order.pending, isNull);

      final changed = order.update(['a', 'b', 'c'], atTop: false);

      expect(changed, isTrue);
      expect(order.applied, ['a', 'b', 'c']);
      expect(order.pending, isNull);
      expect(order.hasPending, isFalse);
    });

    test('scrolled down: a new order waits as pending, rows stay put', () {
      final order = SteadyOrder<String>()..update(['a', 'b', 'c'], atTop: true);

      final changed = order.update(['c', 'a', 'b'], atTop: false);

      expect(changed, isFalse);
      expect(order.applied, ['a', 'b', 'c']);
      expect(order.pending, ['c', 'a', 'b']);
      expect(order.hasPending, isTrue);
    });

    test('at the top: a new order is applied at once and nothing is pending',
        () {
      final order = SteadyOrder<String>()..update(['a', 'b', 'c'], atTop: true);

      final changed = order.update(['c', 'a', 'b'], atTop: true);

      expect(changed, isTrue);
      expect(order.applied, ['c', 'a', 'b']);
      expect(order.pending, isNull);
    });

    test('applying at the top also clears an older pending order', () {
      final order = SteadyOrder<String>()
        ..update(['a', 'b', 'c'], atTop: true)
        ..update(['b', 'a', 'c'], atTop: false);
      expect(order.hasPending, isTrue);

      order.update(['c', 'b', 'a'], atTop: true);

      expect(order.applied, ['c', 'b', 'a']);
      expect(order.pending, isNull);
    });

    test('only the NEWEST waiting order is kept', () {
      final order = SteadyOrder<String>()
        ..update(['a', 'b', 'c'], atTop: true)
        ..update(['b', 'a', 'c'], atTop: false)
        ..update(['c', 'b', 'a'], atTop: false);

      expect(order.applied, ['a', 'b', 'c']);
      expect(order.pending, ['c', 'b', 'a']);
    });

    test(
        'an order that comes back to the applied one cancels the pending '
        'refresh (nothing to tap)', () {
      final order = SteadyOrder<String>()
        ..update(['a', 'b', 'c'], atTop: true)
        ..update(['b', 'a', 'c'], atTop: false);
      expect(order.hasPending, isTrue);

      final changed = order.update(['a', 'b', 'c'], atTop: false);

      expect(changed, isFalse);
      expect(order.pending, isNull);
      expect(order.applied, ['a', 'b', 'c']);
    });

    test('the same order again changes nothing', () {
      final order = SteadyOrder<String>()..update(['a', 'b', 'c'], atTop: true);

      expect(order.update(['a', 'b', 'c'], atTop: false), isFalse);
      expect(order.update(['a', 'b', 'c'], atTop: true), isFalse);
      expect(order.pending, isNull);
    });

    test('the caller\'s list is copied, never aliased', () {
      final input = ['a', 'b'];
      final order = SteadyOrder<String>()..update(input, atTop: true);
      input.add('z');
      expect(order.applied, ['a', 'b']);

      final next = ['b', 'a'];
      order.update(next, atTop: false);
      next.clear();
      expect(order.pending, ['b', 'a']);
    });
  });

  group('SteadyOrder.refresh', () {
    test('applies the waiting order and clears it', () {
      final order = SteadyOrder<String>()
        ..update(['a', 'b', 'c'], atTop: true)
        ..update(['c', 'a', 'b'], atTop: false);

      final changed = order.refresh();

      expect(changed, isTrue);
      expect(order.applied, ['c', 'a', 'b']);
      expect(order.pending, isNull);
    });

    test('with nothing waiting it is a no-op', () {
      final order = SteadyOrder<String>()..update(['a', 'b', 'c'], atTop: true);

      expect(order.refresh(), isFalse);
      expect(order.applied, ['a', 'b', 'c']);
    });
  });

  group('SteadyOrder membership', () {
    test(
        'a manager who joins the board is appended without re-ordering the '
        'rows already shown; the true order waits as pending', () {
      final order = SteadyOrder<String>()..update(['a', 'b', 'c'], atTop: true);

      final changed = order.update(['n', 'a', 'b', 'c'], atTop: false);

      expect(changed, isTrue); // a row appeared
      expect(order.applied, ['a', 'b', 'c', 'n']);
      expect(order.pending, ['n', 'a', 'b', 'c']);
    });

    test('a newcomer who belongs at the end leaves nothing pending', () {
      final order = SteadyOrder<String>()..update(['a', 'b'], atTop: true);

      order.update(['a', 'b', 'n'], atTop: false);

      expect(order.applied, ['a', 'b', 'n']);
      expect(order.pending, isNull);
    });

    test(
        'a row that leaves the board vanishes at once; the rest keep their '
        'order and nothing is pending', () {
      final order = SteadyOrder<String>()..update(['a', 'b', 'c'], atTop: true);

      final changed = order.update(['a', 'c'], atTop: false);

      expect(changed, isTrue);
      expect(order.applied, ['a', 'c']);
      expect(order.pending, isNull);
    });

    test(
        'a removal and a re-order together: the removal is shown, the '
        're-order waits', () {
      final order = SteadyOrder<String>()
        ..update(['a', 'b', 'c', 'd'], atTop: true);

      order.update(['d', 'c', 'a'], atTop: false);

      expect(order.applied, ['a', 'c', 'd']);
      expect(order.pending, ['d', 'c', 'a']);
    });
  });

  group('positionMoves', () {
    test('rows that changed place get their signed move (negative = up)', () {
      final moves = positionMoves(['a', 'b', 'c'], ['c', 'a', 'b']);
      expect(moves, {'c': -2, 'a': 1, 'b': 1});
    });

    test('an unchanged order moves nothing', () {
      expect(positionMoves(['a', 'b', 'c'], ['a', 'b', 'c']), isEmpty);
    });

    test('a row inserted above does not make everyone below "move down"', () {
      expect(positionMoves(['a', 'b', 'c'], ['n', 'a', 'b', 'c']), isEmpty);
    });

    test('a removed row does not make everyone below "move up"', () {
      expect(positionMoves(['a', 'b', 'c'], ['b', 'c']), isEmpty);
    });

    test('only rows in both orders are compared', () {
      final moves = positionMoves(['a', 'b', 'x'], ['b', 'a', 'y']);
      expect(moves, {'b': -1, 'a': 1});
    });
  });
}
