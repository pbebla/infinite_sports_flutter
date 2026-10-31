// Achievement badges (spec 2026-10-30 §5) — the shelf, the detail sheet and
// the leaderboard count chip, proved with plain data (no Firebase):
//   * the shelf groups repeats into ONE chip with "×N" (none for a single),
//     an uploaded picture wins over the icon, every curated icon key maps
//     (unknown → military_tech), an inactive-but-earned badge still shows
//     and an unknown badge id is a generic "Badge" chip; empty → the muted
//     line (or nothing);
//   * tapping a chip opens the sheet: name, description, when earned
//     ("GW3, GW7, GW9" / "Season 15"), "Given by Infinite Sports" + the
//     owner's notes for manual ones only;
//   * the count chip: military_tech + N, hidden at 0;
//   * Review Focus 5: many long-named badges at 360 px, light AND dark —
//     wrap, never overflow, never ellipsized or underlined.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/hub/badge_shelf.dart';

FantasyBadgeAward award(String id, String badge,
        {int? gw, int at = 0, bool manual = false, String? note}) =>
    FantasyBadgeAward(
      id: id,
      badgeId: badge,
      gw: gw,
      atMs: at,
      source: manual ? FantasyBadgeSource.manual : FantasyBadgeSource.auto,
      note: note,
    );

final catalog = badgeCatalogFromNode({
  'mvpOctober': {
    'Name': 'MVP of October',
    'Description': 'Voted by the league.',
    'Icon': 'star',
    'ImageUrl': 'https://img.test/mvp.png',
    'Kind': 'manual',
    'Order': 1,
  },
  'retired': {
    'Name': 'Retired Badge',
    'Icon': 'no_such_icon',
    'Active': false,
    'Order': 95,
  },
});

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> pumpBody(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(420, 900),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: brightness),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ));
}

void main() {
  group('badgeIconFor', () {
    test('every curated key maps to its Material icon; unknown → '
        'military_tech', () {
      const expected = {
        'military_tech': Icons.military_tech,
        'auto_awesome': Icons.auto_awesome,
        'event_seat': Icons.event_seat,
        'diamond': Icons.diamond,
        'emoji_events': Icons.emoji_events,
        'calendar_month': Icons.calendar_month,
        'workspace_premium': Icons.workspace_premium,
        'looks_two': Icons.looks_two,
        'looks_3': Icons.looks_3,
        'star': Icons.star,
        'local_fire_department': Icons.local_fire_department,
        'bolt': Icons.bolt,
        'sports_soccer': Icons.sports_soccer,
        'verified': Icons.verified,
        'celebration': Icons.celebration,
        'favorite': Icons.favorite,
        'thumb_up': Icons.thumb_up,
      };
      expected.forEach((key, icon) => expect(badgeIconFor(key), icon));
      expect(badgeIconFor('nope'), Icons.military_tech);
      expect(badgeIconFor(''), Icons.military_tech);
      // Every starter badge's icon is a curated key.
      for (final e in kStarterBadgeCatalog.values) {
        expect(expected.containsKey(e.icon), isTrue, reason: e.id);
      }
    });
  });

  group('BadgeShelf', () {
    testWidgets('one chip per badge, "×N" only when repeated; catalog order',
        (tester) async {
      await pumpBody(
        tester,
        BadgeShelf(
          awards: [
            award('captainGenius_gw3', 'captainGenius', gw: 3, at: 3),
            award('captainGenius_gw7', 'captainGenius', gw: 7, at: 7),
            award('captainGenius_gw9', 'captainGenius', gw: 9, at: 9),
            award('champion_season', 'champion', at: 20),
          ],
          catalog: catalog,
          season: '15',
        ),
        // Wide enough for both chips on one line in the test font.
        size: const Size(900, 600),
      );
      expect(byKey('badge_chip_captainGenius'), findsOneWidget);
      expect(byKey('badge_chip_champion'), findsOneWidget);
      expect(find.text('Captain Genius'), findsOneWidget);
      expect(find.text('Champion'), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      expect(byKey('badge_chip_count_captainGenius'), findsOneWidget);
      expect(byKey('badge_chip_count_champion'), findsNothing);
      // Catalog order: Captain Genius (10) before Champion (70).
      expect(tester.getTopLeft(byKey('badge_chip_captainGenius')).dx,
          lessThan(tester.getTopLeft(byKey('badge_chip_champion')).dx));
    });

    testWidgets('a picture wins over the icon; icons map by key; an '
        'inactive-but-earned badge still shows; an unknown id is a generic '
        'chip', (tester) async {
      await pumpBody(
        tester,
        BadgeShelf(
          awards: [
            award('-Nm', 'mvpOctober', manual: true),
            award('hiddenGem_gw2', 'hiddenGem', gw: 2),
            award('retired_gw4', 'retired', gw: 4),
            award('gone_gw5', 'deletedBadge', gw: 5),
          ],
          catalog: catalog,
          season: '15',
        ),
      );
      // Picture: the network image, keyed, with that URL — and no icon key.
      final image = tester.widget<CachedNetworkImage>(find.descendant(
          of: byKey('badge_image_mvpOctober'),
          matching: find.byType(CachedNetworkImage)));
      expect(image.imageUrl, 'https://img.test/mvp.png');
      expect(byKey('badge_icon_mvpOctober'), findsNothing);

      Icon icon(String id) => tester.widget<Icon>(byKey('badge_icon_$id'));
      expect(icon('hiddenGem').icon, Icons.diamond);
      expect(byKey('badge_image_hiddenGem'), findsNothing);

      // Inactive but earned → shown; its unknown icon key → military_tech.
      expect(find.text('Retired Badge'), findsOneWidget);
      expect(icon('retired').icon, Icons.military_tech);

      // Not in the catalog at all → the generic badge.
      expect(byKey('badge_chip_deletedBadge'), findsOneWidget);
      expect(find.text(kGenericBadgeName), findsOneWidget);
      expect(icon('deletedBadge').icon, Icons.military_tech);
    });

    testWidgets('empty: the muted line when asked for, otherwise nothing',
        (tester) async {
      await pumpBody(
        tester,
        BadgeShelf(
          awards: const [],
          catalog: catalog,
          season: '15',
          emptyText: kNoBadgesCopy,
        ),
      );
      expect(byKey('badge_shelf_empty'), findsOneWidget);
      expect(find.text(kNoBadgesCopy), findsOneWidget);

      await pumpBody(
        tester,
        BadgeShelf(awards: const [], catalog: catalog, season: '15'),
      );
      expect(byKey('badge_shelf_empty'), findsNothing);
      expect(byKey('badge_shelf'), findsNothing);
    });

    testWidgets('tapping a chip opens its detail sheet', (tester) async {
      await pumpBody(
        tester,
        BadgeShelf(
          awards: [
            award('captainGenius_gw3', 'captainGenius', gw: 3),
            award('captainGenius_gw7', 'captainGenius', gw: 7),
          ],
          catalog: catalog,
          season: '15',
        ),
      );
      await tester.tap(byKey('badge_chip_captainGenius'));
      await tester.pumpAndSettle();
      expect(byKey('badge_sheet'), findsOneWidget);
      expect(
          tester.widget<Text>(byKey('badge_sheet_earned')).data, 'GW3, GW7');
    });
  });

  group('BadgeDetailSheet', () {
    FantasyBadgeGroup group(List<FantasyBadgeAward> awards) =>
        groupBadgeAwards(awards, catalog).single;

    Future<void> pumpSheet(WidgetTester tester, FantasyBadgeGroup g,
            {Size size = const Size(420, 900),
            Brightness brightness = Brightness.light}) =>
        pumpBody(tester, BadgeDetailSheet(group: g, season: '15'),
            size: size, brightness: brightness);

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(byKey(key)).data!;

    testWidgets('weekly badge: name, description, the weeks, earned N×; no '
        '"Given by" for an automatic badge', (tester) async {
      await pumpSheet(
        tester,
        group([
          award('captainGenius_gw9', 'captainGenius', gw: 9, at: 9),
          award('captainGenius_gw3', 'captainGenius', gw: 3, at: 3),
          award('captainGenius_gw7', 'captainGenius', gw: 7, at: 7),
        ]),
      );
      expect(text(tester, 'badge_sheet_name'), 'Captain Genius');
      expect(text(tester, 'badge_sheet_description'),
          kStarterBadgeCatalog['captainGenius']!.description);
      expect(text(tester, 'badge_sheet_earned'), 'GW3, GW7, GW9');
      expect(find.text('Earned 3×'), findsOneWidget);
      expect(byKey('badge_sheet_given_by'), findsNothing);
      expect(byKey('badge_sheet_note_0'), findsNothing);
    });

    testWidgets('season badge: "Season 15", no count line for one',
        (tester) async {
      await pumpSheet(tester, group([award('champion_season', 'champion')]));
      expect(text(tester, 'badge_sheet_name'), 'Champion');
      expect(text(tester, 'badge_sheet_earned'), 'Season 15');
      expect(find.textContaining('Earned 1'), findsNothing);
    });

    testWidgets('manual badge: "Given by Infinite Sports" and the owner\'s '
        'notes', (tester) async {
      await pumpSheet(
        tester,
        group([
          award('-N1', 'mvpOctober',
              manual: true, gw: 4, note: 'Four goals in the final', at: 1),
          award('-N2', 'mvpOctober', manual: true, at: 2),
        ]),
      );
      expect(text(tester, 'badge_sheet_name'), 'MVP of October');
      expect(text(tester, 'badge_sheet_description'), 'Voted by the league.');
      expect(text(tester, 'badge_sheet_earned'), 'GW4 · Season 15');
      expect(text(tester, 'badge_sheet_given_by'), kBadgeGivenByCopy);
      expect(text(tester, 'badge_sheet_note_0'), '“Four goals in the final”');
      expect(byKey('badge_sheet_note_1'), findsNothing);
    });

    testWidgets('unknown badge id: the generic name, no empty description '
        'line', (tester) async {
      await pumpSheet(tester, group([award('x_gw2', 'deletedBadge', gw: 2)]));
      expect(text(tester, 'badge_sheet_name'), kGenericBadgeName);
      expect(byKey('badge_sheet_description'), findsNothing);
      expect(text(tester, 'badge_sheet_earned'), 'GW2');
    });
  });

  group('BadgeCountChip', () {
    testWidgets('0 → nothing at all', (tester) async {
      await pumpBody(
          tester,
          const Align(
              alignment: Alignment.topLeft,
              child: BadgeCountChip(count: 0)));
      expect(find.byType(Icon), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(tester.getSize(find.byType(BadgeCountChip)), Size.zero);
    });

    testWidgets('N > 0 → military_tech + N, read as "N badges"',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBody(tester, const BadgeCountChip(count: 3));
      expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.military_tech);
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('3 badges'), findsOneWidget);
      expect(find.byTooltip('3 badges'), findsOneWidget);

      await pumpBody(tester, const BadgeCountChip(count: 1));
      expect(find.bySemanticsLabel('1 badge'), findsOneWidget);
      semantics.dispose();
    });

    // Opus audit item 1: the leaderboard rows reserve exactly this slot
    // while the counts load, so the chip's size must not depend on N.
    testWidgets('one fixed size for 1, 2 and 3 digits (3 scale down, never '
        'overflow)', (tester) async {
      for (final n in [1, 42, 128]) {
        await pumpBody(
            tester,
            Align(
                alignment: Alignment.topLeft,
                child: BadgeCountChip(count: n)));
        expect(tester.takeException(), isNull, reason: '$n');
        expect(tester.getSize(find.byType(BadgeCountChip)),
            const Size(kBadgeCountChipWidth, kBadgeCountChipHeight),
            reason: '$n');
        expect(find.text('$n'), findsOneWidget);
      }
    });
  });

  group('Review Focus 5 — 360 px, light + dark', () {
    const longName =
        'The Extraordinarily Magnificent Never-Ending Captaincy Award';
    final longCatalog = badgeCatalogFromNode({
      for (var i = 0; i < 8; i++)
        'long$i': {'Name': '$longName $i', 'Icon': 'bolt', 'Order': i},
    });
    final many = [
      for (var i = 0; i < 8; i++)
        for (var gw = 1; gw <= (i % 3) + 1; gw++)
          award('long${i}_gw$gw', 'long$i', gw: gw),
      award('captainGenius_gw1', 'captainGenius', gw: 1),
      award('-Nm', 'mvpOctober',
          manual: true,
          note: 'A very long owner note that should wrap onto several lines '
              'instead of running off the edge of a small phone screen'),
    ];

    for (final brightness in Brightness.values) {
      testWidgets('many long-named badges wrap, never overflow — $brightness',
          (tester) async {
        await pumpBody(
          tester,
          BadgeShelf(
              awards: many,
              catalog: {...catalog, ...longCatalog},
              season: '15'),
          size: const Size(360, 1400),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 8; i++) {
          final r = tester.getRect(byKey('badge_chip_long$i'));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
        }
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.overflow, isNot(TextOverflow.ellipsis));
          expect(t.maxLines, isNull);
          expect(t.style?.decoration, isNot(TextDecoration.underline));
        }

        // The sheet too (long name + long note).
        await tester.tap(byKey('badge_chip_mvpOctober'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(byKey('badge_sheet_note_0'), findsOneWidget);
        final note = tester.getRect(byKey('badge_sheet_note_0'));
        expect(note.right, lessThanOrEqualTo(360));
      });

      testWidgets('a long sheet name wraps at 360 px — $brightness',
          (tester) async {
        await pumpBody(
          tester,
          BadgeDetailSheet(
            group: groupBadgeAwards(
                    [award('long0_gw1', 'long0', gw: 1)], longCatalog)
                .single,
            season: '15',
          ),
          size: const Size(360, 800),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        final name = tester.widget<Text>(byKey('badge_sheet_name'));
        expect(name.overflow, isNot(TextOverflow.ellipsis));
        expect(tester.getRect(byKey('badge_sheet_name')).right,
            lessThanOrEqualTo(360));
      });
    }
  });
}
