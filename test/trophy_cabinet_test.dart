import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/profile/career_tab.dart';
import 'package:infinite_sports_flutter/widgets/trophy_cabinet.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Award _award({
  required String id,
  String trophyId = 't1',
  String name = 'Golden Boot',
  String icon = 'boot',
  String context = '',
  String date = '08302026',
  String season = '14',
}) =>
    Award(
      id: id,
      trophyId: trophyId,
      name: name,
      icon: icon,
      iconType: 'builtin',
      tier: 'gold',
      sport: 'Futsal',
      scopeType: 'tournament',
      scopeId: 'x',
      season: season,
      edition: '2026',
      context: context,
      date: date,
      source: 'auto',
    );

// ─── TrophyCabinet ────────────────────────────────────────────────────────────

void main() {
  group('TrophyCabinet', () {
    testWidgets('empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TrophyCabinet(awards: []))),
      );
      expect(find.textContaining('No trophies'), findsOneWidget);
    });

    testWidgets('single award — renders name, no badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrophyCabinet(awards: [_award(id: 'a')]),
          ),
        ),
      );
      expect(find.text('Golden Boot'), findsOneWidget);
      // No ×N badge for a single award
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('two awards with same trophyId → grouped with ×2 badge',
        (tester) async {
      final awards = [
        _award(id: 'a', context: 'Summer Cup 2026'),
        _award(id: 'b', context: 'Winter Cup 2026'),
      ];
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrophyCabinet(awards: awards))),
      );
      // One tile
      expect(find.text('Golden Boot'), findsOneWidget);
      // ×2 badge
      expect(find.text('×2'), findsOneWidget);
    });

    testWidgets('two awards with different trophyIds → two separate tiles',
        (tester) async {
      final awards = [
        _award(id: 'a', trophyId: 't1', name: 'Golden Boot'),
        _award(id: 'b', trophyId: 't2', name: 'MVP'),
      ];
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrophyCabinet(awards: awards))),
      );
      expect(find.text('Golden Boot'), findsOneWidget);
      expect(find.text('MVP'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('trophyId empty → groups by name', (tester) async {
      final awards = [
        _award(id: 'a', trophyId: '', name: 'Champion'),
        _award(id: 'b', trophyId: '', name: 'Champion'),
      ];
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrophyCabinet(awards: awards))),
      );
      expect(find.text('Champion'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
    });

    testWidgets('detail sheet lists all occurrences for grouped awards',
        (tester) async {
      final awards = [
        _award(id: 'a', context: 'Summer Cup 2026', date: '08302026'),
        _award(id: 'b', context: 'Winter Cup 2026', date: '12302026'),
      ];
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrophyCabinet(awards: awards))),
      );

      // Tap the tile to open the detail sheet
      await tester.tap(find.text('Golden Boot'));
      await tester.pumpAndSettle();

      // Both contexts should appear in the sheet (text may include extra lines)
      expect(find.textContaining('Summer Cup 2026'), findsOneWidget);
      expect(find.textContaining('Winter Cup 2026'), findsOneWidget);
    });
  });

  // ─── CareerRow ──────────────────────────────────────────────────────────────

  group('CareerRow', () {
    test('hasTrophy is true when trophies is non-empty', () {
      const row = CareerRow(
        teamLogoUrl: '',
        title: 'Futsal · Season 14',
        summary: '5G',
        trophies: [(name: 'Golden Boot', icon: 'boot')],
      );
      expect(row.hasTrophy, isTrue);
    });

    test('hasTrophy is false when trophies is empty', () {
      const row = CareerRow(
        teamLogoUrl: '',
        title: 'Futsal · Season 13',
        summary: '',
      );
      expect(row.hasTrophy, isFalse);
    });

    testWidgets('renders trophy icons via Wrap', (tester) async {
      const row = CareerRow(
        teamLogoUrl: '',
        title: 'Futsal · Season 14',
        summary: '5G',
        trophies: [
          (name: 'Golden Boot', icon: 'boot'),
          (name: 'MVP', icon: 'star'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CareerTab(rows: [row]),
          ),
        ),
      );
      // The row title should be visible
      expect(find.text('Futsal · Season 14'), findsOneWidget);
      // Two Tooltip widgets — one per trophy
      expect(find.byType(Tooltip), findsNWidgets(2));
    });

    testWidgets('renders no Tooltip when trophies is empty', (tester) async {
      const row = CareerRow(
        teamLogoUrl: '',
        title: 'Futsal · Season 13',
        summary: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CareerTab(rows: [row]),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
