// "At the top, and nobody is touching it" — the scroll half of the owner's
// steady-order rule (live everywhere, S1), shared by every sorted live list
// (the leaderboards, the Players market) so the two can never drift apart.
//
// [SteadyOrder] (steady_order.dart) decides WHAT order to show; the list
// feeds it `atTop: tracker.atTop`. The tracker learns from the list's own
// scroll notifications alone (no ScrollController of its own — the list stays
// on the route's PrimaryScrollController, so iOS's tap-the-status-bar-to-top
// keeps working):
//
//   • [pixels] the offset as of the last scroll / metrics notification;
//   • [userScrolling] a finger is dragging or flinging the list and it has not
//     come to rest — never re-order under a moving finger;
//   • [atTop] within [kListTopSlop] of the top AND nobody scrolling.
//
// Plain Dart over the notification types; unit-tested through the two lists'
// widget tests (leaderboards_tab_test.dart, players_tab_test.dart).

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// How near the top (logical px) still counts as "at the top" — a hair of
/// slop so a settled list that sits a pixel off 0 still follows the rule.
const double kListTopSlop = 2;

class SteadyScrollTracker {
  /// The list's scroll offset as of its last scroll / metrics notification
  /// (0 until it scrolls).
  double pixels = 0;

  /// The fan is dragging or flinging the list (user-driven scrolling that has
  /// not come to rest).
  bool userScrolling = false;

  /// At the top and nobody is scrolling: a new order may be applied now.
  bool get atTop => !userScrolling && pixels <= kListTopSlop;

  /// Feeds one scroll notification. Only the list's OWN vertical scroll
  /// counts (depth 0 — not a horizontal strip inside it). Returns true when a
  /// scroll has just come to rest at the top: the caller applies an order that
  /// was waiting (deferred to after the frame — notifications can fire during
  /// layout).
  bool onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    pixels = n.metrics.pixels;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      // A finger has started dragging (before its first movement counts).
      userScrolling = true;
    } else if (n is UserScrollNotification) {
      userScrolling = n.direction != ScrollDirection.idle;
    } else if (n is ScrollEndNotification) {
      userScrolling = false;
      return n.metrics.pixels <= kListTopSlop;
    }
    return false;
  }

  /// The content grew or shrank under the viewport: the offset may have been
  /// clamped without a scroll.
  void onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      pixels = n.metrics.pixels;
    }
  }
}
