// The owner's steady-order rule (live everywhere, S1) as ONE pure helper:
// "like ESPN and the Premier League — numbers move, rows don't jump".
//
// A live list (the leaderboards now, the Players market in Task 7) gets a new
// order every time a number moves. Numbers update in place at once; the ORDER
// of the rows is what this helper holds still:
//
//   • the first order ever seen is applied at once (the tab was just opened);
//   • a new order is applied at once when the list is at the top — or when the
//     fan picked a sort / scope (callers pass `atTop: true` for that: nothing
//     is under his finger and he asked to see the new order);
//   • otherwise it WAITS as [pending] — the UI shows `Order changed · tap to
//     refresh` and calls [refresh] on the tap. Only the newest waiting order
//     is kept, and one that comes back to the applied order cancels itself.
//
// "Never re-order under a moving finger" is the caller's `atTop`: false while
// the list is scrolled away from the top OR the fan is dragging/flinging it.
//
// Membership is not ordering: a row that leaves the board vanishes at once and
// one that joins is appended at the end of the applied order at once (existing
// rows never shift because of a re-order they were not asked to take); where
// the newcomer really belongs waits as [pending] like any other re-order.
//
// Plain Dart, no widgets, no clock: unit-tested in
// test/fantasy/steady_order_test.dart.

import 'package:flutter/foundation.dart' show listEquals;

class SteadyOrder<T> {
  List<T> _applied = const [];
  List<T>? _pending;
  bool _started = false;

  /// The order to draw right now.
  List<T> get applied => _applied;

  /// The newest order that is waiting for a refresh; null = nothing waits
  /// (the applied order IS the latest).
  List<T>? get pending => _pending;

  /// There is a different order waiting — the UI shows its "tap to refresh".
  bool get hasPending => _pending != null;

  /// Feeds the latest order. [atTop] true applies it now (the list is at the
  /// top and nobody is scrolling it, or the fan just picked a sort / scope);
  /// false parks it as [pending]. Returns whether the APPLIED order changed.
  bool update(List<T> newOrder, {required bool atTop}) {
    final next = List<T>.of(newOrder);
    if (!_started) {
      _started = true;
      _applied = next;
      _pending = null;
      return true;
    }
    final before = _applied;
    if (atTop) {
      _applied = next;
      _pending = null;
    } else {
      // Rows that stay keep their applied order; leavers vanish; newcomers go
      // last. Anything the true order disagrees with waits.
      final present = next.toSet();
      final kept = [
        for (final item in before)
          if (present.contains(item)) item,
      ];
      final known = kept.toSet();
      final reconciled = [
        ...kept,
        for (final item in next)
          if (!known.contains(item)) item,
      ];
      _applied = reconciled;
      _pending = listEquals(reconciled, next) ? null : next;
    }
    return !listEquals(before, _applied);
  }

  /// The fan tapped "Order changed · tap to refresh": applies the waiting
  /// order. Returns whether anything changed (false = nothing was waiting).
  bool refresh() {
    final waiting = _pending;
    if (waiting == null) return false;
    _applied = waiting;
    _pending = null;
    return true;
  }
}

/// How far each row moved between two orders: item → places moved (negative =
/// up, toward the top; positive = down). Only rows in BOTH orders are
/// compared, by their place among those rows — a row inserted above or removed
/// does not make everyone below it "move". Rows that held their place are
/// absent.
Map<T, int> positionMoves<T>(List<T> before, List<T> after) {
  final inAfter = after.toSet();
  final inBefore = before.toSet();
  final common = [
    for (final item in before)
      if (inAfter.contains(item)) item,
  ];
  final next = [
    for (final item in after)
      if (inBefore.contains(item)) item,
  ];
  final place = <T, int>{for (final (i, item) in common.indexed) item: i};
  final out = <T, int>{};
  for (final (i, item) in next.indexed) {
    final delta = i - place[item]!;
    if (delta != 0) out[item] = delta;
  }
  return out;
}
