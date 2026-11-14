import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tab_swap.dart';

/// Release report #1: the league match page threw ~30 exceptions
/// ("Null check operator" / "'mounted': is not true" in TabBar/TabBarView)
/// on every tab switch once the Fantasy tab appeared live (3 → 4 tabs).
///
/// Root cause (reproduced in this harness before fixing): a
/// DefaultTabController whose `length` changes hands its ONE
/// AnimationController over to a new TabController and disposes the old
/// one. With the NestedScrollView keyed by tab count, the old TabBar /
/// TabBarView unmount while their controller is already disposed, so they
/// can't remove their listeners from the shared animation — every later tab
/// switch notifies dead States.
///
/// LeagueMatchDetailPage can't be pumped in a widget test (static
/// LeagueService / FantasyService streams, FirebaseAuth.instance — see
/// league_match_detail_tabs_test.dart), so the page now wraps its tabbed
/// subtree in [LiveLengthTabController] and this harness reproduces the
/// page's exact structure (pinned SliverAppBar + bottom TabBar inside a
/// NestedScrollView, TabBarView body) around it.
class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool fantasyOpen = false;

  void setFantasy(bool open) => setState(() => fantasyOpen = open);

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Summary',
      'Nineveh',
      'Babylon',
      if (fantasyOpen) 'Fantasy',
    ];
    return LiveLengthTabController(
      length: labels.length,
      child: Scaffold(
        body: NestedScrollView(
          // The page used to key this by tab count (the remount that leaked
          // the listeners); kept here so the helper is proven safe with it.
          key: ValueKey(labels.length),
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 196,
              bottom: TabBar(tabs: [for (final l in labels) Tab(text: l)]),
            ),
          ],
          body: TabBarView(
            children: [for (final l in labels) Center(child: Text('body $l'))],
          ),
        ),
      ),
    );
  }
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'switching to $label');
}

void main() {
  testWidgets(
      'tab count changing live (3 → 4 → 3) never throws on later tab '
      'switches', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
    expect(tester.takeException(), isNull);

    await _tapTab(tester, 'Nineveh');
    await _tapTab(tester, 'Babylon');
    await _tapTab(tester, 'Summary');

    key.currentState!.setFantasy(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, 'Fantasy'), findsOneWidget);

    for (final l in ['Fantasy', 'Nineveh', 'Summary', 'Babylon', 'Fantasy']) {
      await _tapTab(tester, l);
    }
    expect(find.text('body Fantasy'), findsOneWidget);

    // Config removed while the Fantasy tab is selected: clamps, no throw.
    key.currentState!.setFantasy(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final l in ['Summary', 'Nineveh', 'Babylon']) {
      await _tapTab(tester, l);
    }
  });

  testWidgets('the selected tab is kept when a tab is appended',
      (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
    await _tapTab(tester, 'Babylon');
    expect(find.text('body Babylon'), findsOneWidget);

    key.currentState!.setFantasy(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('body Babylon'), findsOneWidget);
  });
}
