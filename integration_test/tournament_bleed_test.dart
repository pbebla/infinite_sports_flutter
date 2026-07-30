// On-device diagnostic for the owner-reported cross-tournament data bleed:
// opens the three real tournaments' detail pages back-to-back against the
// LIVE database (public read) and asserts no tournament renders another's
// team names or title anywhere in its Table / Player Stats / Teams tabs.
//
// Run: C:\src\flutter\bin\flutter.bat test integration_test -d emulator-5554
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/firebase_options.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';
import 'package:integration_test/integration_test.dart';

const basketNames = {
  'Akkad', 'Ashur', 'Babylon', 'ishtar', 'Lamassu', 'Nimrod', 'Nineveh',
  'Urmia', '3vs3 basketballl',
};
const calNames = {
  'Active FC', 'AFC San Jose Elite', 'AFC San Jose Rising Stars',
  'Club Assyria', 'FC Babylon', 'Westcoast Winged Bulls',
  'California State Assyrian Tournament 2026',
};
const testNames = {
  'Bears', 'Bulls', 'Cobras', 'Comets', 'Eagles', 'Falcons', 'Foxes',
  'Hawks', 'Kings', 'Lions', 'Panthers', 'Rovers', 'Sharks', 'Storm',
  'Tigers', 'Wolves', 'Test Tournament 2026',
};

Set<String> visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toSet();

Future<void> settleReal(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tournament pages never render another tournament\'s data',
      (tester) async {
    await FlutterConfig.loadEnvVariables();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    Future<Set<String>> openAndCollect(String id, String name) async {
      await tester.pumpWidget(MaterialApp(
          home: TournamentDetailPage(tournamentId: id, tournamentName: name)));
      await settleReal(tester, 6);
      final all = <String>{...visibleTexts(tester)};
      for (final tab in ['Table', 'Player Stats', 'Teams', 'Predict']) {
        final f = find.text(tab);
        if (f.evaluate().isEmpty) continue;
        await tester.tap(f.first, warnIfMissed: false);
        await settleReal(tester, 3);
        all.addAll(visibleTexts(tester));
      }
      return all;
    }

    // Same browsing order the owner described: basketball and California
    // first, then the Test tournament that showed their data.
    final basket = await openAndCollect('basket123', '3vs3 basketballl');
    final cal = await openAndCollect(
        'ca_state_assyrian_2026', 'California State Assyrian Tournament 2026');
    final test = await openAndCollect(
        'test-tournament-2026', 'Test Tournament 2026');

    debugPrint('=== BLEED REPORT ===');
    debugPrint('basket page foreign texts: '
        '${basket.intersection(calNames)} ${basket.intersection(testNames)}');
    debugPrint('california page foreign texts: '
        '${cal.intersection(basketNames)} ${cal.intersection(testNames)}');
    debugPrint('test page foreign texts: '
        '${test.intersection(basketNames)} ${test.intersection(calNames)}');
    debugPrint('=== END BLEED REPORT ===');

    expect(test.intersection(calNames), isEmpty,
        reason: 'California data rendered inside Test Tournament');
    expect(test.intersection(basketNames), isEmpty,
        reason: 'Basketball data rendered inside Test Tournament');
    expect(cal.intersection(basketNames), isEmpty,
        reason: 'Basketball data rendered inside California');
  });
}
