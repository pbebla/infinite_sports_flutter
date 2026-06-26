import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/widgets/share_profile_card.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Award _award(String id, String name, String tier) => Award(
      id: id,
      trophyId: 'trophy_$id',
      name: name,
      icon: 'trophy_gold',
      iconType: 'builtin',
      tier: tier,
      sport: 'Futsal',
      scopeType: 'league',
      scopeId: 'futsal',
      season: '15',
      edition: '2026',
      context: 'Summer Cup 2026',
      date: '08302026',
      source: 'auto',
    );

Future<void> _pumpCabinet(
    WidgetTester tester, List<Award> awards) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ShareProfileCabinetCard(
        name: 'Sam Rivera',
        photoUrl: '',
        currentLabel: 'Eagles · Futsal',
        awards: awards,
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpStats(
    WidgetTester tester,
    List<({String label, String value})> stats) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ShareProfileStatsCard(
        name: 'Sam Rivera',
        photoUrl: '',
        competitionLabel: 'Futsal · Season 15',
        stats: stats,
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpCareer(
    WidgetTester tester,
    List<({String label, String value})> totals) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ShareProfileCareerCard(
        name: 'Sam Rivera',
        photoUrl: '',
        headlineTotals: totals,
      ),
    ),
  ));
  await tester.pump();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Cabinet card
  group('ShareProfileCabinetCard', () {
    testWidgets('empty awards renders without overflow or exception',
        (tester) async {
      await _pumpCabinet(tester, []);
      expect(tester.takeException(), isNull);
      expect(find.text('0 Trophies'), findsOneWidget);
    });

    testWidgets('populated awards shows trophy names and count', (tester) async {
      final awards = [
        _award('a1', 'Golden Boot', 'gold'),
        _award('a2', 'Best GK', 'silver'),
        _award('a3', 'Champions', 'gold'),
      ];
      await _pumpCabinet(tester, awards);
      expect(tester.takeException(), isNull);
      expect(find.text('3 Trophies'), findsOneWidget);
      expect(find.text('Golden Boot'), findsOneWidget);
    });

    testWidgets('more than 8 awards shows +N chip', (tester) async {
      final awards = List.generate(
          10, (i) => _award('a$i', 'Award $i', 'gold'));
      await _pumpCabinet(tester, awards);
      expect(tester.takeException(), isNull);
      // 8 shown + 1 "+2 more" chip
      expect(find.textContaining('+2'), findsOneWidget);
    });

    testWidgets('singular trophy label when exactly 1 award', (tester) async {
      await _pumpCabinet(tester, [_award('a1', 'Golden Boot', 'gold')]);
      expect(tester.takeException(), isNull);
      expect(find.text('1 Trophy'), findsOneWidget);
    });
  });

  // Stats card
  group('ShareProfileStatsCard', () {
    testWidgets('empty stats renders without overflow', (tester) async {
      await _pumpStats(tester, []);
      expect(tester.takeException(), isNull);
      expect(find.text('No stats recorded'), findsOneWidget);
    });

    testWidgets('populated stats shows label and value rows', (tester) async {
      final stats = [
        (label: 'Goals', value: '12'),
        (label: 'Assists', value: '7'),
        (label: 'Saves', value: '3'),
      ];
      await _pumpStats(tester, stats);
      expect(tester.takeException(), isNull);
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Assists'), findsOneWidget);
    });

    testWidgets('caps at 5 stat rows even if more provided', (tester) async {
      final stats = List.generate(
          8,
          (i) => (label: 'Stat $i', value: '$i'));
      await _pumpStats(tester, stats);
      expect(tester.takeException(), isNull);
      // Only first 5 shown; 'Stat 5', 'Stat 6', 'Stat 7' absent
      expect(find.text('Stat 4'), findsOneWidget);
      expect(find.text('Stat 5'), findsNothing);
    });
  });

  // Career card
  group('ShareProfileCareerCard', () {
    testWidgets('empty totals renders without overflow', (tester) async {
      await _pumpCareer(tester, []);
      expect(tester.takeException(), isNull);
      expect(find.text('No career data yet'), findsOneWidget);
    });

    testWidgets('populated totals shows big numbers', (tester) async {
      final totals = [
        (label: 'Sports Played', value: '3'),
        (label: 'Goals', value: '42'),
        (label: 'Trophies', value: '5'),
        (label: 'Seasons', value: '8'),
      ];
      await _pumpCareer(tester, totals);
      expect(tester.takeException(), isNull);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Trophies'), findsOneWidget);
    });

    testWidgets('caps at 4 cells even if more provided', (tester) async {
      final totals = List.generate(
          6, (i) => (label: 'Label $i', value: '$i'));
      await _pumpCareer(tester, totals);
      expect(tester.takeException(), isNull);
      // Cell 4 and 5 (index 4 and 5) should not appear
      expect(find.text('Label 4'), findsNothing);
      expect(find.text('Label 5'), findsNothing);
    });
  });
}
