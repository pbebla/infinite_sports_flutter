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
//  • Which state: the ACTIVE tab's own list, from its scroll and metrics
//    notifications (no ScrollController — lists stay on the route's
//    PrimaryScrollController, see steady_scroll.dart). Only a finger
//    scrolling down past [_kCollapseAfter] collapses it; reaching the very
//    top (however — a finger, a fling, the status-bar tap) or pulling down at
//    it expands it.
//  • Never stuck collapsed (review 6, I1): a scroll view that only drags
//    while its content overflows (My Team, News, Team of the Week) loses its
//    drag once the content fits — so the header collapses ONLY when the tab
//    overflows by more than the WHOLE expanded header (+ [_kCollapseAfter]):
//    the viewport grows by less than that, so the tab still overflows and
//    stays draggable. And whenever the active tab has nothing left to scroll
//    while collapsed (content shrank, the keyboard closed), the header
//    expands. The two thresholds are at least [_kCollapseAfter] apart, so the
//    states cannot oscillate. A tab switch restores the state that tab was
//    left in only if it can still be left.
//  • A tab switch drops the keyboard (review 6, M-a): a kept-alive tab's
//    focused field (the Players search) would otherwise keep it open over
//    the next tab.
//  • Typing in a tab (the Players search) with the keyboard up collapses the
//    header for as long as the keyboard stays open — at 360 px the full
//    header + tab row + keyboard leave the tab no room at all. When the
//    keyboard goes, the tab's own state (and the escape rule) decide again.
//  • Only the ACTIVE tab answers a scroll-to-top (review 6, M-c): every
//    kept-alive tab's list attaches to the primary scroll controller, so
//    iOS's tap-the-status-bar-to-top would scroll them all. The owner gives
//    the shell an [ActiveTabScrollController] and puts it as the primary
//    controller above its Scaffold (the status-bar tap's source); the shell
//    marks which tab is on screen and the controller's animateTo / jumpTo
//    move only that tab's list (reaching the top reopens the header). The
//    tabs see one stable controller, so nothing is remounted on a switch.
//  • The tab row scrolls horizontally from the start; an edge fade marks the
//    side where more tabs are off screen (five tabs never fit 360 px, and a
//    label is never ellipsized).
//  • The tab count may change live: [LiveLengthTabController] keys the
//    controller with its tabs (release report #1 / f4fdad6).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
    this.primaryScrollController,
  }) : assert(tabs.length == children.length);

  /// When given, the tabs' primary scroll controller (put the SAME one above
  /// the page's Scaffold): a scroll-to-top through it moves only the tab on
  /// screen. null = the tabs inherit whatever primary controller is above.
  final ActiveTabScrollController? primaryScrollController;

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
        primaryScrollController: primaryScrollController,
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
    required this.primaryScrollController,
    required this.expandedHeader,
    required this.collapsedHeader,
    required this.tabs,
    required this.children,
  });

  final ActiveTabScrollController? primaryScrollController;
  final Widget expandedHeader;
  final Widget collapsedHeader;
  final List<String> tabs;
  final List<Widget> children;

  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 1 = expanded, 0 = collapsed.
  late final AnimationController _expand =
      AnimationController(vsync: this, duration: _kCollapseDuration, value: 1);

  /// Each tab's collapsed state as it was last left (restored on a switch).
  final Map<int, bool> _collapsedByTab = {};

  /// A finger is dragging/flinging the given tab's list.
  final Map<int, bool> _userScrolling = {};

  /// Each tab's list metrics as last reported (scroll or metrics
  /// notification).
  final Map<int, ScrollMetrics> _metrics = {};

  /// The header's height when last measured fully expanded (null: unknown —
  /// never collapse on a guess).
  double? _expandedHeight;
  final GlobalKey _headerBox = GlobalKey();

  /// The header is collapsed or on its way there.
  bool _wantCollapsed = false;

  /// The tab on screen once a switch has settled — the one that answers the
  /// route's primary scroll controller.
  int? _activeIndex;

  /// Holds the tab bodies' focus, so a tab switch can drop it.
  final FocusScopeNode _bodyFocus = FocusScopeNode(debugLabel: 'hub tabs');

  /// Collapsed because a tab field is focused with the keyboard up.
  bool _keyboardCollapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bodyFocus.addListener(_syncKeyboard);
  }

  @override
  void didChangeMetrics() => _syncKeyboard();

  /// The Scaffold strips the keyboard inset from its body's MediaQuery, so
  /// read it from the view itself.
  void _syncKeyboard() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    final inset = view != null && view.viewInsets.bottom > 0;
    // Entered by typing in a tab; left only once the keyboard has gone (not
    // when the focus goes — the keyboard is still sliding away then).
    final keyboard = _keyboardCollapsed ? inset : inset && _bodyFocus.hasFocus;
    if (keyboard && !_keyboardCollapsed) {
      _keyboardCollapsed = true;
      // At once, in the same frame as the inset (the keyboard's own slide
      // is the motion): an animated collapse would overflow the tab body
      // for its first frames.
      _wantCollapsed = true;
      _expand.value = 0;
    } else if (!keyboard && _keyboardCollapsed) {
      _keyboardCollapsed = false;
      final i = _tabs?.index;
      final m = i == null ? null : _metrics[i];
      final keep = i != null &&
          (_collapsedByTab[i] ?? false) &&
          m != null &&
          !_nothingToScroll(m) &&
          m.pixels > m.minScrollExtent;
      _setCollapsed(keep);
    }
  }

  TabController? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultTabController.of(context);
    if (identical(next, _tabs)) return;
    _tabs?.removeListener(_onTabChanged);
    _tabs = next..addListener(_onTabChanged);
    _activeIndex = next.index;
    widget.primaryScrollController?.activeTab = next.index;
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    _bodyFocus.removeListener(_syncKeyboard);
    _expand.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final c = _tabs;
    if (c == null) return;
    // Leaving a tab drops its keyboard at once (M-a).
    if (_bodyFocus.hasFocus) FocusManager.instance.primaryFocus?.unfocus();
    if (c.indexIsChanging) return;
    final i = c.index;
    _activeIndex = i;
    widget.primaryScrollController?.activeTab = i;
    final m = _metrics[i];
    // Back to a tab left collapsed: only if it can still be left (it still
    // has something to scroll and is not at its top).
    final keep = (_collapsedByTab[i] ?? false) &&
        m != null &&
        !_nothingToScroll(m) &&
        m.pixels > m.minScrollExtent;
    _collapsedByTab[i] = keep;
    _setCollapsed(keep);
  }

  static bool _nothingToScroll(ScrollMetrics m) =>
      m.maxScrollExtent - m.minScrollExtent <= 0.5;

  /// Collapsing this tab leaves it scrollable: it overflows the expanded
  /// viewport by more than the whole expanded header (the most the viewport
  /// can grow) plus the collapse threshold.
  bool _canCollapse(ScrollMetrics m) {
    if (!_wantCollapsed && _expand.value == 1) {
      final box = _headerBox.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) _expandedHeight = box.size.height;
    }
    final header = _expandedHeight;
    if (header == null) return false;
    return m.maxScrollExtent - m.minScrollExtent > header + _kCollapseAfter;
  }

  void _setCollapsed(bool collapsed) {
    // The keyboard holds it collapsed until it has gone (see _syncKeyboard).
    if (!collapsed && _keyboardCollapsed) return;
    _wantCollapsed = collapsed;
    final target = collapsed ? 0.0 : 1.0;
    // Notifications can arrive during layout: never drive the animation (and
    // its rebuild) from inside a frame's build/layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wantCollapsed == collapsed) _animateTo(target);
      });
      return;
    }
    _animateTo(target);
  }

  void _animateTo(double target) {
    if (_expand.value == target && !_expand.isAnimating) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _expand.value = target;
    } else {
      _expand.animateTo(target, curve: Curves.easeInOut);
    }
  }

  /// The active tab has nothing left to scroll while collapsed: expand, so
  /// the header is never out of reach.
  void _escapeIfStuck(int index) {
    final m = _metrics[index];
    if (m == null || _tabs?.index != index || _keyboardCollapsed) return;
    if (_wantCollapsed && _nothingToScroll(m)) {
      _collapsedByTab[index] = false;
      _setCollapsed(false);
    }
  }

  bool _onMetrics(int index, ScrollMetricsNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _metrics[index] = n.metrics;
    _escapeIfStuck(index);
    return false;
  }

  bool _onScroll(int index, ScrollNotification n) {
    // The tab's own vertical list only — not a horizontal chip strip or a
    // list nested inside it.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _metrics[index] = n.metrics;
    if (n is UserScrollNotification) {
      _userScrolling[index] = n.direction != ScrollDirection.idle;
      _escapeIfStuck(index);
      return false;
    }
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling[index] = true;
    }

    bool? collapse;
    if (n is ScrollUpdateNotification &&
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      // Reaching the very top expands, however it got there.
      collapse = false;
    } else if (n is OverscrollNotification && n.overscroll < 0) {
      collapse = false; // pulling down at the top
    } else if (n is ScrollUpdateNotification &&
        _userScrolling[index] == true &&
        (n.scrollDelta ?? 0) > 0 &&
        n.metrics.pixels - n.metrics.minScrollExtent > _kCollapseAfter &&
        (_wantCollapsed || _canCollapse(n.metrics))) {
      // Only a finger collapses it, and only when it can be left again.
      collapse = true;
    }
    if (collapse == null) {
      _escapeIfStuck(index);
      return false;
    }
    _collapsedByTab[index] = collapse;
    if (_tabs?.index == index) _setCollapsed(collapse);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryScrollController;
    return Column(
      children: [
        AnimatedBuilder(
          animation: _expand,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_expand.value);
            return KeyedSubtree(
              key: _headerBox,
              child: _CollapsingHeader(
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
              ),
            );
          },
        ),
        _EdgeFadeTabBar(tabs: widget.tabs),
        Expanded(
          child: FocusScope(
            node: _bodyFocus,
            child: TabBarView(
              children: [
                for (var i = 0; i < widget.children.length; i++)
                  _KeepAlive(
                    child: _TabMarker(
                      index: i,
                      child: _withPrimary(
                        primary,
                        NotificationListener<ScrollMetricsNotification>(
                          onNotification: (n) => _onMetrics(i, n),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) => _onScroll(i, n),
                            child: widget.children[i],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _withPrimary(ScrollController? primary, Widget child) => primary == null
    ? child
    : PrimaryScrollController(controller: primary, child: child);

/// Marks which tab a scroll position lives in (see [ActiveTabScrollController]).
class _TabMarker extends StatelessWidget {
  const _TabMarker({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The hub tabs' primary scroll controller (review 6, M-c). Every kept-alive
/// tab's list attaches to it; [animateTo] / [jumpTo] — iOS's tap-the-status-
/// bar-to-top among them — move only the list of the tab on screen
/// ([activeTab], kept by [CollapsingTabShell]), so the other tabs keep their
/// own offsets. Platform-neutral: nothing calls it on Android.
class ActiveTabScrollController extends ScrollController {
  ActiveTabScrollController({super.debugLabel});

  /// The tab on screen (set by the shell).
  int? activeTab;

  int? _tabOf(ScrollPosition p) {
    final ctx = p.context.storageContext;
    if (!ctx.mounted) return null;
    return ctx.findAncestorWidgetOfExactType<_TabMarker>()?.index;
  }

  Iterable<ScrollPosition> get _active =>
      positions.where((p) => activeTab == null || _tabOf(p) == activeTab);

  @override
  Future<void> animateTo(double offset,
      {required Duration duration, required Curve curve}) async {
    await Future.wait<void>([
      for (final p in _active)
        p.animateTo(offset, duration: duration, curve: curve),
    ]);
  }

  @override
  void jumpTo(double value) {
    for (final p in _active.toList()) {
      p.jumpTo(value);
    }
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
              left: 0,
              top: 0,
              child: SizedBox(key: ValueKey('tabs_more_start'))),
        if (_moreEnd)
          const Positioned(
              right: 0,
              top: 0,
              child: SizedBox(key: ValueKey('tabs_more_end'))),
      ],
    );
  }
}

/// Lays out the header between its two faces: height = lerp(collapsed,
/// expanded, [t]) from their natural heights, both faces bottom-aligned (the
/// big header slides up under the clip as it shrinks), clipped to the
/// current height.
class _CollapsingHeader
    extends SlottedMultiChildRenderObjectWidget<_Face, RenderBox> {
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
  Iterable<RenderBox> get children =>
      [if (_expanded != null) _expanded!, if (_collapsed != null) _collapsed!];

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
    for (final child in [
      if (_collapsed != null) _collapsed!,
      if (_expanded != null) _expanded!
    ]) {
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
