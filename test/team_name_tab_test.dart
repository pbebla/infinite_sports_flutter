import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/match_tabs/team_box_score_tab.dart';

/// Release report #4: on the match pages a long team name ("AFC San Jose
/// Rising Stars") was scaled down by a FittedBox to a tiny font in its tab.
/// The tab now keeps the TabBar's own label size and wraps to two lines
/// (ellipsized past that).
void main() {
  const longName = 'AFC San Jose Rising Stars';

  Future<void> pumpTabs(WidgetTester tester, String team2) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            bottom: TabBar(tabs: [
              const Tab(text: 'Summary'),
              teamNameTab('AFC San Jose Elite'),
              teamNameTab(team2),
            ]),
          ),
        ),
      ),
    ));
  }

  double fontSize(WidgetTester tester, String text) => tester
      .renderObject<RenderParagraph>(find.text(text))
      .text
      .style!
      .fontSize!;

  testWidgets('a long team name keeps the tab label size (no shrink-to-fit)',
      (tester) async {
    await pumpTabs(tester, longName);
    expect(tester.takeException(), isNull);
    expect(
      find.ancestor(of: find.text(longName), matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(fontSize(tester, longName), fontSize(tester, 'Summary'));
    // Laid out at full size: wraps instead of shrinking, at most two lines.
    final summaryHeight = tester.getSize(find.text('Summary')).height;
    final nameHeight = tester.getSize(find.text(longName)).height;
    expect(nameHeight, greaterThan(summaryHeight * 1.5));
    expect(nameHeight, lessThanOrEqualTo(summaryHeight * 2.2));
  });

  testWidgets('an absurdly long name ellipsizes within two lines',
      (tester) async {
    await pumpTabs(
        tester, 'The Extremely Long Named Football Club Of Northern San Jose');
    expect(tester.takeException(), isNull);
    final t = tester.widget<Text>(find.textContaining('Extremely'));
    expect(t.maxLines, 2);
    expect(t.overflow, TextOverflow.ellipsis);
  });
}
