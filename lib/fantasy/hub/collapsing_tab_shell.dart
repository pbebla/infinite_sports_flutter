// The Fantasy hub's tabbed shell (release report #8): a header that SHRINKS
// to a slim pinned bar once the active tab's content scrolls, the tab row
// pinned under it, and the tab bodies below.
//
//  • Expanded (at the top of the active tab): [expandedHeader] exactly as
//    given. Collapsed (the tab scrolled down): [collapsedHeader] — the hub
//    puts the gameweek + live deadline countdown there, so the deadline never
//    leaves the screen. The change is a 220 ms height + cross-fade animation
//    (no jump); only the header rebuilds — the tab bodies are siblings, never
//    rebuilt, and keep their own scroll offsets (each tab is kept alive, so a
//    tab switch and back lands where the fan left it).
//  • Which state: the ACTIVE tab's own list, from its scroll notifications
//    (no ScrollController — lists stay on the route's PrimaryScrollController,
//    see steady_scroll.dart). A fan scrolling down past [_kCollapseAfter]
//    collapses it; reaching the very top (or pulling down at it) expands it.
//    Only finger-driven scrolling counts, so the viewport growing under the
//    collapse can never bounce it back open. A tab switch restores the state
//    that tab was left in.
//  • The tab row scrolls horizontally from the start; an edge fade marks the
//    side where more tabs are off screen (five tabs never fit 360 px, and a
//    label is never ellipsized).
//  • The tab count may change live: [LiveLengthTabController] keys the
//    controller with its tabs (release report #1 / f4fdad6).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_sports_flutter/misc/tab_swap.dart';

/// Scrolling further than this (logical px) collapses the header.
const double _kCollapseAfter = 16;

const Duration _kCollapseDuration = Duration(milliseconds: 220);

class CollapsingTabShell extends StatelessWidget {
  const CollapsingTabShell({
    super.key,
    required this.expandedHeader,
    required this.collapsedHeader,
    required this.tabs,
    required this.children,
    this.initialIndex = 0,
  }) : assert(tabs.length == children.length);

  /// The full header shown at the top of the active tab.
  final Widget expandedHeader;

  /// The slim one-line bar pinned while the active tab is scrolled.
  final Widget collapsedHeader;

  /// Tab labels, one per [children] entry.
  final List<String> tabs;
  final List<Widget> children;

  /// The tab the shell opens on (clamped).
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return LiveLengthTabController(
      length: tabs.length,
      initialIndex: initialIndex.clamp(0, tabs.length - 1),
      child: _ShellBody(
        expandedHeader: expandedHeader,
        collapsedHeader: collapsedHeader,
        tabs: tabs,
        children: children,
      ),
    );
  }
}

class _ShellBody extends StatefulWidget {
  const _ShellBody({
    required this.expandedHeader,
    required this.collapsedHeader,
    required this.tabs,
    required this.children,
  });

  final Widget expandedHeader;
  final Widget collapsedHeader;
  final List<String> tabs;
  final List<Widget> children;

  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody>
    with SingleTickerProviderStateMixin {
  /// 1 = expanded, 0 = collapsed.
  late final AnimationController _expand =
      AnimationController(vsync: this, duration: _kCollapseDuration, value: 1);

  /// Each tab's collapsed state as it was last left (restored on a switch).
  final Map<int, bool> _collapsedByTab = {};

  /// A finger is dragging/flinging the given tab's list.
  final Map<int, bool> _userScrolling = {};

  TabController? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultTabController.of(context);
    if (identical(next, _tabs)) return;
    _tabs?.removeListener(_onTabChanged);
    _tabs = next..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    _expand.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final c = _tabs;
    if (c == null || c.indexIsChanging) return;
    _setCollapsed(_collapsedByTab[c.index] ?? false);
  }

  void _setCollapsed(bool collapsed) {
    final target = collapsed ? 0.0 : 1.0;
    if (_expand.value == target && !_expand.isAnimating) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _expand.value = target;
    } else {
      _expand.animateTo(target, curve: Curves.easeInOut);
    }
  }

  bool _onScroll(int index, ScrollNotification n) {
    // The tab's own vertical list only — not a horizontal chip strip or a
    // list nested inside it.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      _userScrolling[index] = n.direction != ScrollDirection.idle;
      return false;
    }
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling[index] = true;
    }
    if (_userScrolling[index] != true) return false;

    bool? collapse;
    if (n is ScrollUpdateNotification) {
      final delta = n.scrollDelta ?? 0;
      if (n.metrics.pixels <= n.metrics.minScrollExtent) {
        collapse = false;
      } else if (delta > 0 &&
          n.metrics.pixels - n.metrics.minScrollExtent > _kCollapseAfter) {
        collapse = true;
      }
    } else if (n is OverscrollNotification && n.overscroll < 0) {
      collapse = false; // pulling down at the top
    }
    if (collapse == null) return false;
    _collapsedByTab[index] = collapse;
    if (_tabs?.index == index) _setCollapsed(collapse);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _expand,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_expand.value);
            return _CollapsingHeader(
              key: const ValueKey('collapsing_header'),
              t: t,
              // Mounted only while visible: at rest exactly one face exists.
              expanded: t > 0
                  ? IgnorePointer(
                      ignoring: t < 0.5,
                      child: Opacity(
                        opacity: ((t - 0.4) / 0.6).clamp(0.0, 1.0),
                        child: widget.expandedHeader,
                      ),
                    )
                  : null,
              collapsed: t < 1
                  ? IgnorePointer(
                      ignoring: t >= 0.5,
                      child: Opacity(
                        opacity: ((0.6 - t) / 0.6).clamp(0.0, 1.0),
                        child: widget.collapsedHeader,
                      ),
                    )
                  : null,
            );
          },
        ),
        _EdgeFadeTabBar(tabs: widget.tabs),
        Expanded(
          child: TabBarView(
            children: [
              for (var i = 0; i < widget.children.length; i++)
                _KeepAlive(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) => _onScroll(i, n),
                    child: widget.children[i],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps a tab's State (scroll offset, filters, its streams) while another
/// tab is shown.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The scrollable tab row, start-aligned, with an edge fade on each side that
/// has more tabs off screen.
class _EdgeFadeTabBar extends StatefulWidget {
  const _EdgeFadeTabBar({required this.tabs});
  final List<String> tabs;

  @override
  State<_EdgeFadeTabBar> createState() => _EdgeFadeTabBarState();
}

class _EdgeFadeTabBarState extends State<_EdgeFadeTabBar> {
  bool _moreStart = false;
  bool _moreEnd = false;

  bool _onMetrics(ScrollMetrics m) {
    if (m.axis != Axis.horizontal) return false;
    final start = m.pixels > m.minScrollExtent + 0.5;
    final end = m.pixels < m.maxScrollExtent - 0.5;
    if (start != _moreStart || end != _moreEnd) {
      // Notifications can arrive during layout: repaint after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _moreStart = start;
          _moreEnd = end;
        });
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bar = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [for (final t in widget.tabs) Tab(text: t)],
    );
    Widget child = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: bar,
      ),
    );
    // Always wrapped (an opaque mask when nothing is clipped) so toggling a
    // fade never remounts the TabBar and loses its scroll position.
    const fade = 32.0;
    child = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final f = (fade / rect.width).clamp(0.0, 0.5);
        return LinearGradient(
          colors: [
            _moreStart ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            _moreEnd ? Colors.transparent : Colors.black,
          ],
          stops: [0, f, 1 - f, 1],
        ).createShader(rect);
      },
      child: child,
    );
    return Stack(
      children: [
        child,
        // Test/semantics markers for the visible affordance.
        if (_moreStart)
          const Positioned(
              left: 0, top: 0, child: SizedBox(key: ValueKey('tabs_more_start'))),
        if (_moreEnd)
          const Positioned(
              right: 0, top: 0, child: SizedBox(key: ValueKey('tabs_more_end'))),
      ],
    );
  }
}

/// Lays out the header between its two faces: height = lerp(collapsed,
/// expanded, [t]) from their natural heights, both faces bottom-aligned (the
/// big header slides up under the clip as it shrinks), clipped to the
/// current height.
class _CollapsingHeader extends SlottedMultiChildRenderObjectWidget<_Face, RenderBox> {
  const _CollapsingHeader({
    super.key,
    required this.t,
    required this.expanded,
    required this.collapsed,
  });

  final double t;
  final Widget? expanded;
  final Widget? collapsed;

  @override
  Iterable<_Face> get slots => _Face.values;

  @override
  Widget? childForSlot(_Face slot) => switch (slot) {
        _Face.expanded => expanded,
        _Face.collapsed => collapsed,
      };

  @override
  _RenderCollapsingHeader createRenderObject(BuildContext context) =>
      _RenderCollapsingHeader(t);

  @override
  void updateRenderObject(
      BuildContext context, _RenderCollapsingHeader renderObject) {
    renderObject.t = t;
  }
}

enum _Face { expanded, collapsed }

class _RenderCollapsingHeader extends RenderBox
    with SlottedContainerRenderObjectMixin<_Face, RenderBox> {
  _RenderCollapsingHeader(this._t);

  double _t;
  set t(double v) {
    if (v == _t) return;
    _t = v;
    markNeedsLayout();
  }

  RenderBox? get _expanded => childForSlot(_Face.expanded);
  RenderBox? get _collapsed => childForSlot(_Face.collapsed);

  @override
  Iterable<RenderBox> get children => [if (_expanded != null) _expanded!, if (_collapsed != null) _collapsed!];

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final childConstraints = BoxConstraints.tightFor(width: width);
    double? he, hc;
    final e = _expanded, c = _collapsed;
    if (e != null) {
      e.layout(childConstraints, parentUsesSize: true);
      he = e.size.height;
    }
    if (c != null) {
      c.layout(childConstraints, parentUsesSize: true);
      hc = c.size.height;
    }
    final double h;
    if (he != null && hc != null) {
      h = hc + (he - hc) * _t;
    } else {
      h = he ?? hc ?? 0;
    }
    size = constraints.constrain(Size(width, h));
    if (e != null) {
      (e.parentData! as BoxParentData).offset = Offset(0, size.height - he!);
    }
    if (c != null) {
      (c.parentData! as BoxParentData).offset = Offset(0, size.height - hc!);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    void paintFaces(PaintingContext context, Offset offset) {
      for (final child in children) {
        context.paintChild(
            child, offset + (child.parentData! as BoxParentData).offset);
      }
    }

    _clip.layer = context.pushClipRect(
        needsCompositing, offset, Offset.zero & size, paintFaces,
        oldLayer: _clip.layer);
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!(Offset.zero & size).contains(position)) return false;
    for (final child in [if (_collapsed != null) _collapsed!, if (_expanded != null) _expanded!]) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, p) => child.hitTest(result, position: p),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width);
  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width);

  double _heightFor(double width) {
    final he = _expanded?.getMaxIntrinsicHeight(width);
    final hc = _collapsed?.getMaxIntrinsicHeight(width);
    if (he != null && hc != null) return hc + (he - hc) * _t;
    return he ?? hc ?? 0;
  }
}
