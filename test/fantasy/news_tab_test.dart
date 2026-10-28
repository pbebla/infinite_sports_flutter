// P3d — the News tab's card feed proved with a fake stream: skeleton until
// the first emit, friendly empty state while nothing is published, cards
// newest-first with title/body/date (photo block only when the post carries
// one), and live re-render when a new post lands.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';

void main() {
  late StreamController<List<FantasyNewsPost>> news;

  setUp(() {
    news = StreamController<List<FantasyNewsPost>>.broadcast();
  });

  tearDown(() {
    news.close();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyNewsTab(
          sport: 'Futsal',
          season: '15',
          newsStates: news.stream,
        ),
      ),
    ));
  }

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
}
