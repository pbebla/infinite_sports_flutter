import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/frontpage.dart';

/// Fix round 1, I1: the home screen's tab count changes LIVE — the
/// /Tournaments listener appends a tab when a tournament starts and drops
/// it when one finishes, without the loading skeleton. The tab shell must
/// keep the surviving tabs' state (no reload, no lost scroll, no reset
/// selected day) and never throw.
class _Body extends StatefulWidget {
  const _Body(this.label);
  final String label;
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static int creations = 0;
  int day = 0;
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    creations++;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        controller: scroll,
        children: [
          TextButton(
            onPressed: () => setState(() => day++),
            child: Text('${widget.label} day $day'),
          ),
          for (var i = 0; i < 40; i++) SizedBox(height: 50, child: Text('row $i')),
        ],
      );
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  List<String> tournaments = const [];
  void setTournaments(List<String> t) => setState(() => tournaments = t);

  @override
  Widget build(BuildContext context) {
    final names = ['League', ...tournaments];
    return HomeTabShell(
      tabNames: [for (final n in names) Tab(text: n)],
      tabs: [for (final n in names) _Body(n)],
      onTabTap: (_) {},
      onRefresh: () {},
    );
  }
}

void main() {
  testWidgets('a tournament tab appearing / disappearing live keeps the '
      'league tab\'s state and scroll, and never throws', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _BodyState.creations = 0;

    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
    await tester.tap(find.text('League day 0'));
    await tester.pump();
    final state = tester.state<_BodyState>(find.byType(_Body));
    state.scroll.jumpTo(300);
    await tester.pump();
    expect(_BodyState.creations, 1);

    key.currentState!.setTournaments(['Cup']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, 'Cup'), findsOneWidget);
    // Same State object: nothing reloaded, scroll + selected day kept.
    expect(tester.state<_BodyState>(find.byType(_Body).first), same(state));
    expect(state.day, 1);
    expect(state.scroll.offset, 300);

    // Tab switches after the live change work without exceptions.
    await tester.tap(find.widgetWithText(Tab, 'Cup'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(Tab, 'League'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The tournament finishes while the fan is on the league tab.
    final league = tester.state<_BodyState>(find.byType(_Body).first);
    league.scroll.jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('League day ${league.day}'));
    await tester.pump();
    final dayBefore = league.day;
    key.currentState!.setTournaments(const []);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.state<_BodyState>(find.byType(_Body).first), same(league));
    expect(league.day, dayBefore);
    expect(find.widgetWithText(Tab, 'Cup'), findsNothing);
  });
}
