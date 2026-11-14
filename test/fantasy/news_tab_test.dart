// P3d — the News tab's card feed proved with a fake stream: skeleton until
// the first emit, friendly empty state while nothing is published, cards
// newest-first with title/body/date (photo block only when the post carries
// one), and live re-render when a new post lands.
//
// News desk 2.0 (spec 2026-10-28 §4.2): the header label line, tagged-player
// cards (1–2 full cards with '–' for unknown stats + View player, 3+
// compact rows) and the push-tap focus (scroll + highlight, or "This post
// was removed." once).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

Map<String, Object?> _card(
  String name, {
  String position = 'ATT',
  String team = 'Lions',
  int price = 150,
  int? delta,
  int? gw,
  int? gwPoints,
  int? seasonPoints,
  num? owned,
  int goals = 0,
  int assists = 0,
}) =>
    {
      'name': name,
      'position': position,
      'team': team,
      'priceTenths': price,
      if (delta != null) 'priceDeltaTenths': delta,
      if (gw != null) 'gw': gw,
      if (gwPoints != null) 'gwPoints': gwPoints,
      if (seasonPoints != null) 'seasonPoints': seasonPoints,
      if (owned != null) 'ownershipPct': owned,
      'goals': goals,
      'assists': assists,
    };

void main() {
  late StreamController<List<FantasyNewsPost>> news;

  setUp(() {
    news = StreamController<List<FantasyNewsPost>>.broadcast();
  });

  tearDown(() {
    news.close();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    String? focusPostId,
    VoidCallback? onFocusHandled,
    void Function(String name)? onOpenPlayer,
    bool reduceMotion = false,
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: FantasyNewsTab(
            sport: 'Futsal',
            season: '15',
            newsStates: news.stream,
            focusPostId: focusPostId,
            onFocusHandled: onFocusHandled,
            onOpenPlayer: onOpenPlayer,
          ),
        ),
      ),
    ));
  }

  /// [count] untitled-template posts, newest first: 'p0' is the newest.
  Map<String, Object?> manyPosts(int count) => {
        for (var i = 0; i < count; i++)
          'p$i': {
            'Title': 'Story number $i',
            'Body': 'A fairly long body line so every card has some height '
                'to it and the feed runs well past one screen.',
            'At': 100000 - i,
          },
      };

  testWidgets('skeleton until the stream emits, then the friendly empty '
      'state', (tester) async {
    await pumpTab(tester);
    expect(find.byKey(const ValueKey('news_skeleton')), findsOneWidget);

    news.add(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('news_empty')), findsOneWidget);
    expect(find.text('League news lands here during the season.'),
        findsOneWidget);
  });

  testWidgets('cards render newest-first with title, body and date; a new '
      'post re-renders live', (tester) async {
    await pumpTab(tester);
    // The parser emits newest-first; the tab renders in stream order.
    news.add(newsPostsFromNode({
      'a': {
        'Title': 'Week one recap',
        'Body': 'Goals everywhere.',
        'At': DateTime(2026, 10, 20, 10).millisecondsSinceEpoch,
      },
      'b': {
        'Title': 'Price risers',
        'Body': 'Three climbers this Monday.',
        'At': DateTime(2026, 10, 26, 9).millisecondsSinceEpoch,
      },
    }));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('news_feed')), findsOneWidget);
    final newerY = tester.getTopLeft(find.text('Price risers')).dy;
    final olderY = tester.getTopLeft(find.text('Week one recap')).dy;
    expect(newerY, lessThan(olderY));
    expect(find.text('Goals everywhere.'), findsOneWidget);
    expect(find.text('Oct 26 · 9:00 AM'), findsOneWidget);
    // No photo on these posts → no image block at all.
    expect(find.byType(Image), findsNothing);

    // A fresh publish lands on top, live.
    news.add(newsPostsFromNode({
      'c': {
        'Title': 'Breaking news',
        'At': DateTime(2026, 10, 27).millisecondsSinceEpoch,
      },
      'b': {
        'Title': 'Price risers',
        'At': DateTime(2026, 10, 26, 9).millisecondsSinceEpoch,
      },
    }));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('news_card_c')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Breaking news')).dy,
        lessThan(tester.getTopLeft(find.text('Price risers')).dy));
  });

  group('News desk 2.0 — header + tagged players', () {
    testWidgets('header label line: template label · GW, plain "News" for '
        'old posts', (tester) async {
      await pumpTab(tester);
      news.add(newsPostsFromNode({
        'a': {'Title': 'Spot', 'At': 3, 'Template': 'spotlight', 'Gw': 7},
        'b': {'Title': 'Old', 'At': 2},
        'c': {'Title': 'Totw', 'At': 1, 'Template': 'dreamteam', 'Gw': 3},
      }));
      await tester.pumpAndSettle();
      expect(find.text('Spotlight · GW7'), findsOneWidget);
      expect(find.text('News'), findsOneWidget);
      expect(find.text('Team of the week · GW3'), findsOneWidget);
    });

    testWidgets('1–2 players → full cards: price line with delta, four stat '
        'tiles, "–" for unknown stats, names never ellipsized',
        (tester) async {
      const longName = 'Maximiliano Fernández-Rodríguez de la Cruz';
      await pumpTab(tester, onOpenPlayer: (_) {});
      news.add(newsPostsFromNode({
        'h': {
          'Title': 'Bruno vs Max',
          'At': 1,
          'Template': 'h2h',
          'Gw': 7,
          'Players': [
            _card('Bruno Siva',
                delta: 5,
                gw: 7,
                gwPoints: 12,
                seasonPoints: 88,
                owned: 31,
                goals: 9,
                assists: 4),
            // Fresh card: no week, no ownership, a price drop.
            _card(longName,
                position: 'DEF', team: 'Wolves', price: 65, delta: -5),
          ],
        },
      }));
      await tester.pumpAndSettle();

      expect(find.text('Head to head · GW7'), findsOneWidget);
      final bruno = find.byKey(const ValueKey('news_player_card_Bruno Siva'));
      expect(bruno, findsOneWidget);
      expect(find.byKey(ValueKey('news_player_card_$longName')),
          findsOneWidget);
      // No compact rows for a 2-player post.
      expect(find.byKey(const ValueKey('news_player_row_Bruno Siva')),
          findsNothing);

      // Price line in the market's money style + the signed delta.
      expect(
          find.descendant(
              of: bruno,
              matching: find.textContaining(r'ATT · Lions · $15.0M')),
          findsOneWidget);
      expect(
          find.descendant(of: bruno, matching: find.textContaining(r'+$0.5M')),
          findsOneWidget);
      final max = find.byKey(ValueKey('news_player_card_$longName'));
      expect(
          find.descendant(
              of: max, matching: find.textContaining(r'DEF · Wolves · $6.5M')),
          findsOneWidget);
      expect(
          find.descendant(of: max, matching: find.textContaining(r'−$0.5M')),
          findsOneWidget);

      // Four tiles with the known stats.
      String tile(String name, String label) => tester
          .widget<Text>(find.byKey(ValueKey('news_stat_${name}_$label')))
          .data!;
      expect(tile('Bruno Siva', 'gw'), '12');
      expect(tile('Bruno Siva', 'goals'), '9');
      expect(tile('Bruno Siva', 'assists'), '4');
      expect(tile('Bruno Siva', 'owned'), '31%');
      expect(find.descendant(of: bruno, matching: find.text('GW7 pts')),
          findsOneWidget);
      // Unknown stats render "–"; goals/assists default to 0.
      expect(tile(longName, 'gw'), '–');
      expect(tile(longName, 'owned'), '–');
      expect(tile(longName, 'goals'), '0');
      expect(find.descendant(of: max, matching: find.text('GW pts')),
          findsOneWidget);

      // The long name wraps — never an ellipsis or a line cap.
      final nameText = tester.widget<Text>(find.text(longName));
      expect(nameText.maxLines, isNull);
      expect(nameText.overflow, isNot(TextOverflow.ellipsis));
      expect(nameText.softWrap, isTrue);

      expect(find.text('View player'), findsNWidgets(2));
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
          '${mode.name} 360 px: View player looks enabled — the fantasy accent '
          'fill, not the grey tonal one (release report #9)', (tester) async {
        await pumpTab(tester,
            onOpenPlayer: (_) {},
            themeMode: mode,
            size: const Size(360, 800));
        news.add(newsPostsFromNode({
          's': {
            'Title': 'Spotlight: Bruno Siva',
            'At': 1,
            'Template': 'spotlight',
            'Players': [_card('Bruno Siva', gwPoints: 3)],
          },
        }));
        await tester.pumpAndSettle();
        final finder =
            find.byKey(const ValueKey('news_view_player_Bruno Siva'));
        final button = tester.widget<ButtonStyleButton>(finder);
        expect(button.enabled, isTrue);
        final ctx = tester.element(finder);
        final dark = mode == ThemeMode.dark;
        final scheme = Theme.of(ctx).colorScheme;
        final bg = button.style!.backgroundColor!.resolve(const {});
        final fg = button.style!.foregroundColor!.resolve(const {});
        // Gold on dark, brand primary on light — the hub's accent.
        expect(bg, fantasyAccent(ctx));
        expect(bg, dark ? TournamentColors.gold : scheme.primary);
        expect(bg, isNot(scheme.secondaryContainer));
        expect(fg, dark ? Colors.black : scheme.onPrimary);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('View player invokes the hub callback with the player name',
        (tester) async {
      final opened = <String>[];
      await pumpTab(tester, onOpenPlayer: opened.add);
      news.add(newsPostsFromNode({
        's': {
          'Title': 'Spotlight: Bruno Siva',
          'At': 1,
          'Template': 'spotlight',
          'Players': [_card('Bruno Siva', gwPoints: 3)],
        },
      }));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('news_view_player_Bruno Siva')));
      await tester.pump();
      expect(opened, ['Bruno Siva']);
    });

    testWidgets('3+ players → compact rows (position chip + week points); '
        'tapping a row opens the player', (tester) async {
      final opened = <String>[];
      await pumpTab(tester, onOpenPlayer: opened.add);
      news.add(newsPostsFromNode({
        't': {
          'Title': 'Team of the Week is out',
          'At': 1,
          'Template': 'dreamteam',
          'Gw': 3,
          'Players': {
            '0': _card('Gale', position: 'GK', gwPoints: 14),
            '1': _card('Dana', position: 'DEF', gwPoints: 12),
            '2': _card('Alex', gwPoints: 11),
            '3': _card('Bo', gwPoints: 8),
            '4': _card('Cy'), // no week entry
          },
        },
      }));
      await tester.pumpAndSettle();

      for (final n in ['Gale', 'Dana', 'Alex', 'Bo', 'Cy']) {
        expect(find.byKey(ValueKey('news_player_row_$n')), findsOneWidget);
        expect(find.byKey(ValueKey('news_player_card_$n')), findsNothing);
      }
      expect(find.text('View player'), findsNothing);
      expect(find.text('14 pts'), findsOneWidget);
      expect(find.text('8 pts'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('news_player_row_Cy')),
              matching: find.text('–')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('news_player_row_Gale')),
              matching: find.text('GK')),
          findsOneWidget);
      // Rows keep the stored display order (GK first).
      expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('news_player_row_Gale')))
              .dy,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('news_player_row_Cy')))
              .dy));

      await tester.tap(find.byKey(const ValueKey('news_player_row_Dana')));
      await tester.pump();
      expect(opened, ['Dana']);
    });

    testWidgets('a narrow phone in dark mode lays out full cards and compact '
        'rows with long names and no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const longName = 'Maximiliano Fernández-Rodríguez de la Cruz';
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromRGBO(208, 0, 0, 1),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: FantasyNewsTab(
            sport: 'Futsal',
            season: '15',
            newsStates: news.stream,
            onOpenPlayer: (_) {},
          ),
        ),
      ));
      news.add(newsPostsFromNode({
        'a': {
          'Title': 'Head to head',
          'At': 2,
          'Template': 'h2h',
          'Gw': 12,
          'Players': [
            _card(longName,
                team: 'The Extremely Long Team Name FC',
                price: 1250,
                delta: 15,
                gw: 12,
                gwPoints: 104,
                owned: 100,
                goals: 112,
                assists: 98),
            _card('Bo', delta: -10),
          ],
        },
        'b': {
          'Title': 'Team of the week',
          'At': 1,
          'Template': 'dreamteam',
          'Players': [
            for (final n in [longName, 'Bo', 'Cy', 'Di', 'Ed'])
              _card(n, gwPoints: 100),
          ],
        },
      }));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(ValueKey('news_player_card_$longName')),
          findsOneWidget);
      expect(find.byKey(ValueKey('news_player_row_$longName')),
          findsOneWidget);
    });
  });

  group('push-tap focus', () {
    BoxDecoration? highlightOf(WidgetTester tester, String id) {
      final card = tester.widget<AnimatedContainer>(
          find.byKey(ValueKey('news_card_$id')));
      return card.foregroundDecoration as BoxDecoration?;
    }

    bool isHighlighted(WidgetTester tester, String id) {
      final border = highlightOf(tester, id)?.border as Border?;
      return border != null && border.top.color.a > 0;
    }

    testWidgets('a post far down the feed scrolls into view, highlights, '
        'then the highlight clears', (tester) async {
      var handled = 0;
      await pumpTab(tester,
          focusPostId: 'p17', onFocusHandled: () => handled++);
      news.add(newsPostsFromNode(manyPosts(20)));
      // Frame by frame: the lazy list steps down until the card is built,
      // then the reveal animates (350ms) and the 1.2s highlight starts.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final card = find.byKey(const ValueKey('news_card_p17'));
      expect(card, findsOneWidget);
      final top = tester.getTopLeft(card).dy;
      expect(top, greaterThanOrEqualTo(0));
      expect(top, lessThan(900));
      expect(isHighlighted(tester, 'p17'), isTrue);
      expect(handled, 1);

      // The reveal animation finishes, THEN the 1.2s outline starts.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(isHighlighted(tester, 'p17'), isTrue);
      await tester.pump(FantasyNewsTab.highlightFor);
      await tester.pumpAndSettle();
      expect(isHighlighted(tester, 'p17'), isFalse);
      expect(find.text('This post was removed.'), findsNothing);
    });

    testWidgets('reduced motion: jumps straight to the post, highlight with '
        'no animation', (tester) async {
      await pumpTab(tester, focusPostId: 'p12', reduceMotion: true);
      news.add(newsPostsFromNode(manyPosts(16)));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final card = find.byKey(const ValueKey('news_card_p12'));
      expect(card, findsOneWidget);
      expect(tester.getTopLeft(card).dy, inInclusiveRange(0, 900));
      final container = tester.widget<AnimatedContainer>(card);
      expect(container.duration, Duration.zero);
      expect(isHighlighted(tester, 'p12'), isTrue);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(isHighlighted(tester, 'p12'), isFalse);
    });

    testWidgets('a removed post shows "This post was removed." once',
        (tester) async {
      var handled = 0;
      await pumpTab(tester,
          focusPostId: 'gone', onFocusHandled: () => handled++);
      news.add(newsPostsFromNode(manyPosts(3)));
      await tester.pump();
      // The first emit may be a stale cache — a short grace before saying so.
      expect(find.text('This post was removed.'), findsNothing);

      await tester.pump(FantasyNewsTab.focusGrace);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('This post was removed.'), findsOneWidget);
      expect(handled, 1);

      // Later emits never repeat it.
      ScaffoldMessenger.of(tester.element(find.byType(FantasyNewsTab)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      news.add(newsPostsFromNode(manyPosts(4)));
      await tester.pump(FantasyNewsTab.focusGrace * 2);
      await tester.pumpAndSettle();
      expect(find.text('This post was removed.'), findsNothing);
      expect(handled, 1);
    });

    testWidgets('a stale first emit without the post, then the live emit '
        'with it → focus, no SnackBar', (tester) async {
      await pumpTab(tester, focusPostId: 'fresh');
      news.add(newsPostsFromNode(manyPosts(2))); // stale cache seed
      await tester.pump(const Duration(milliseconds: 600));
      news.add(newsPostsFromNode({
        'fresh': {'Title': 'Just published', 'At': 999999},
        ...manyPosts(2),
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(isHighlighted(tester, 'fresh'), isTrue);

      await tester.pump(FantasyNewsTab.focusGrace);
      await tester.pumpAndSettle();
      expect(find.text('This post was removed.'), findsNothing);
    });

    testWidgets('no focusPostId → nothing highlighted, no SnackBar',
        (tester) async {
      await pumpTab(tester);
      news.add(newsPostsFromNode(manyPosts(2)));
      await tester.pump(FantasyNewsTab.focusGrace * 2);
      await tester.pumpAndSettle();
      expect(isHighlighted(tester, 'p0'), isFalse);
      expect(find.text('This post was removed.'), findsNothing);
    });
  });
}
