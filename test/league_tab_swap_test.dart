import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tab_swap.dart';

/// P3.2 regression tests for the live 5↔6 tab swap on LeagueDetailPage.
///
/// LeagueDetailPage itself can't be pumped in a widget test: its initState
/// subscribes to static LeagueService streams that hit
/// FirebaseDatabase.instance directly (no injection seam), and its build
/// reads FirebaseAuth.instance. So the swap logic was extracted into
/// [swapTabController] (lib/misc/tab_swap.dart) and this harness reproduces
/// the page's exact tabbed structure — pushed route (implied back arrow),
/// NestedScrollView keyed by tab count, pinned SliverAppBar with bottom
/// TabBar, TabBarView — and drives the same swap the page performs when the
/// prediction config flips.
///
/// Root cause (reproduced in a harness before fixing): the page's State was
/// a SingleTickerProviderStateMixin, which permanently records its one
/// ticker — so creating the 6-tab replacement TabController threw
/// "multiple tickers were created", AFTER the old controller was already
/// disposed and `_tabs` grown to 6. The mounted TabBar was left holding a
/// disposed 5-length controller against 6 tabs, so the SliverAppBar chrome
/// (TabBar + back arrow) stopped painting and the header overflowed. Any
/// regression to that pattern fails these tests the same way.
class _TabSwapHarness extends StatefulWidget {
  const _TabSwapHarness();

  @override
  State<_TabSwapHarness> createState() => _TabSwapHarnessState();
}

class _TabSwapHarnessState extends State<_TabSwapHarness>
    with TickerProviderStateMixin {
  static const List<Tab> _baseTabs = [
    Tab(text: 'Fixtures'),
    Tab(text: 'Table'),
    Tab(text: 'Playoffs'),
    Tab(text: 'Player Stats'),
    Tab(text: 'Teams'),
  ];

  List<Tab> _tabs = _baseTabs;
  late TabController _tabController =
      TabController(length: _tabs.length, vsync: this);

  int get index => _tabController.index;
  int get length => _tabController.length;

  /// Mirrors LeagueDetailPage._applyPredictionConfig (P3.2 shape).
  void setPredictionsOpen(bool open) {
    final tabs = <Tab>[
      ..._baseTabs,
      if (open) const Tab(text: 'Predict'),
    ];
    if (tabs.length == _tabs.length) return;
    final controller = swapTabController(
      old: _tabController,
      newLength: tabs.length,
      vsync: this,
    );
    setState(() {
      _tabs = tabs;
      _tabController = controller;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        key: ValueKey(_tabs.length),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
              tabs: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            for (final t in _tabs) Center(child: Text('${t.text} body')),
          ],
        ),
      ),
    );
  }
}

Future<_TabSwapHarnessState> _pumpHarness(WidgetTester tester) async {
  // Push as a second route so the SliverAppBar implies a real back arrow —
  // its survival through the swap is part of the owner's repro.
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(MaterialPageRoute(builder: (_) => const _TabSwapHarness()));
  await tester.pumpAndSettle();
  return tester.state<_TabSwapHarnessState>(find.byType(_TabSwapHarness));
}

void main() {
  testWidgets('5→6 swap keeps TabBar, back arrow, and selected tab',
      (tester) async {
    final state = await _pumpHarness(tester);

    await tester.tap(find.text('Playoffs'));
    await tester.pumpAndSettle();
    expect(state.index, 2);

    state.setPredictionsOpen(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(state.length, 6);
    expect(state.index, 2, reason: 'selection survives the swap');
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Predict'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget,
        reason: 'implied back arrow must keep painting after the swap');
    expect(find.text('Playoffs body'), findsOneWidget);
  });

  testWidgets('6→5 swap while ON the Predict tab clamps to last tab',
      (tester) async {
    final state = await _pumpHarness(tester);

    state.setPredictionsOpen(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Predict'));
    await tester.pumpAndSettle();
    expect(state.index, 5);

    state.setPredictionsOpen(false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(state.length, 5);
    expect(state.index, 4, reason: 'clamped off the removed Predict tab');
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Predict'), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Teams body'), findsOneWidget);
  });

  testWidgets('repeated live flips never throw or drop the header chrome',
      (tester) async {
    final state = await _pumpHarness(tester);

    for (final open in [true, false, true, false]) {
      state.setPredictionsOpen(open);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    }
    expect(state.length, 5);
  });

  testWidgets('back-to-back flips within one frame dispose safely',
      (tester) async {
    final state = await _pumpHarness(tester);

    // Config stream flickers open→closed before a frame is pumped: two
    // swaps schedule two post-frame disposals of two distinct controllers.
    state.setPredictionsOpen(true);
    state.setPredictionsOpen(false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(state.length, 5);
    expect(find.byType(TabBar), findsOneWidget);
  });
}
