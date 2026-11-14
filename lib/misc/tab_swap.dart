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

/// A [DefaultTabController] whose [length] may change while it is mounted
/// (release report #1 — the league match page's Fantasy tab appearing
/// live, 3 → 4).
///
/// A plain DefaultTabController handles a new length by moving its single
/// AnimationController onto a new TabController and disposing the old one.
/// Any TabBar/TabBarView that unmounts in that same frame (e.g. a subtree
/// keyed by tab count) can then no longer remove its listeners from the
/// shared animation, and every later tab switch notifies those dead States:
/// ~30 "Null check operator" / "'mounted': is not true" exceptions per
/// switch. Keying the controller itself by [length] rebuilds the controller
/// and its whole subtree together — children unmount (and unsubscribe)
/// before the old controller is disposed, and the new tabs start on a
/// fresh controller.
///
/// The selected tab carries over, clamped when the last tab disappears.
class LiveLengthTabController extends StatefulWidget {
  const LiveLengthTabController({
    super.key,
    required this.length,
    required this.child,
    this.initialIndex = 0,
  });

  final int length;
  final Widget child;

  /// The tab selected on first build (clamped to [length]); later length
  /// changes keep the tab the user is on instead.
  final int initialIndex;

  @override
  State<LiveLengthTabController> createState() =>
      _LiveLengthTabControllerState();
}

class _LiveLengthTabControllerState extends State<LiveLengthTabController> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: ValueKey(widget.length),
      length: widget.length,
      initialIndex: _index.clamp(0, widget.length - 1),
      child: _TabIndexRecorder(
        onIndex: (i) => _index = i,
        child: widget.child,
      ),
    );
  }
}

/// Remembers the selected tab (no rebuild) so a length change can restore it.
class _TabIndexRecorder extends StatefulWidget {
  const _TabIndexRecorder({required this.onIndex, required this.child});

  final ValueChanged<int> onIndex;
  final Widget child;

  @override
  State<_TabIndexRecorder> createState() => _TabIndexRecorderState();
}

class _TabIndexRecorderState extends State<_TabIndexRecorder> {
  TabController? _controller;

  void _record() {
    final c = _controller;
    if (c != null) widget.onIndex(c.index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultTabController.of(context);
    if (identical(next, _controller)) return;
    _controller?.removeListener(_record);
    _controller = next..addListener(_record);
  }

  @override
  void dispose() {
    _controller?.removeListener(_record);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
