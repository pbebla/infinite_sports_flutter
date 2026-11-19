import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';

/// The Home top bar no longer carries the old Table and Stats buttons (the
/// "Futsal League >" card opens the league page with both tabs). The AFC San
/// Jose ShowLeaguePage keeps its own pair.
void main() {
  test('the Home app bar has no Table or Stats button', () {
    final src = File('lib/frontpage.dart').readAsStringSync();
    expect(src.contains('assets/table.png'), isFalse);
    expect(src.contains('assets/leader.png'), isFalse);
    expect(src.contains('tableWidget'), isFalse);
    expect(src.contains('leaderboardWidget'), isFalse);
  });

  test('ShowLeaguePage still shows both buttons', () {
    final src = File('lib/showleague.dart').readAsStringSync();
    expect(src.contains('assets/table.png'), isTrue);
    expect(src.contains('assets/leader.png'), isTrue);
    expect(src.contains('TablePage('), isTrue);
    expect(src.contains('LeaderboardPage('), isTrue);
  });

  testWidgets('a GlobalAppBar built without the two widgets has no actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: GlobalAppBar(title: const Text('Home'), height: kToolbarHeight),
      ),
    ));
    expect(find.byType(ImageIcon), findsOneWidget); // only the profile icon
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.actions, anyOf(isNull, isEmpty));
  });

  testWidgets('a GlobalAppBar given the two widgets still shows them',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: GlobalAppBar(
          title: const Text('AFC'),
          height: kToolbarHeight,
          tableWidget: const Icon(Icons.table_chart),
          leaderboardWidget: const Icon(Icons.leaderboard),
        ),
      ),
    ));
    expect(find.byIcon(Icons.table_chart), findsOneWidget);
    expect(find.byIcon(Icons.leaderboard), findsOneWidget);
  });
}
