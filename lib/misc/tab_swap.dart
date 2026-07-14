import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Replaces a live [TabController] with one of a different length without
/// breaking a mounted [TabBar]/[TabBarView] (League Experience P3.2).
///
/// The original in-place swap broke the SliverAppBar chrome — TabBar and
/// the implied back arrow stopped painting, RenderFlex overflow under the
/// header (owner repro on LeagueDetailPage when the prediction config
/// flipped open). Reproduced root cause: SingleTickerProviderStateMixin
/// permanently records its one ticker, so constructing ANY second
/// TabController throws "multiple tickers were created" — after the old
/// controller was already disposed and the tab list already grown, leaving
/// the mounted TabBar on a disposed, wrong-length controller. The safe
/// sequence is:
///
///  1. create the replacement controller FIRST — which is why the vsync
///     MUST come from [TickerProviderStateMixin], never
///     SingleTickerProviderStateMixin (two tickers are alive for one frame);
///  2. rebuild with the new controller AND remount the tabbed subtree with a
///     key derived from the tab count (e.g. `ValueKey(tabs.length)` on the
///     NestedScrollView), so TabBar/TabBarView attach to the new controller
///     fresh instead of updating across different lengths;
///  3. dispose the old controller only after that frame, once nothing
///     references it anymore.
///
/// The selected tab index carries over, clamped to the new length so
/// removing the last tab while it is selected never crashes.
///
/// Returns the replacement controller; the caller stores it (inside
/// `setState`) and must NOT dispose the old one itself.
TabController swapTabController({
  required TabController old,
  required int newLength,
  required TickerProvider vsync,
}) {
  final replacement = TabController(
    length: newLength,
    vsync: vsync,
    initialIndex: old.index.clamp(0, newLength - 1),
  );
  SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
  return replacement;
}
