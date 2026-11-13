// News desk 2.0 (spec 2026-10-28 §4.1/§4.2) — the fan-side parse of a
// published post's template, gameweek and tagged-player snapshots, plus the
// card header label. Pure parsers, RTDB Map/List-coercion tolerant.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

Map<String, Object?> _card(String name,
        {String position = 'ATT', Map<String, Object?> extra = const {}}) =>
    {
      'name': name,
      'position': position,
      'team': 'Lions',
      'priceTenths': 75,
      'goals': 3,
      'assists': 1,
      ...extra,
    };

void main() {
  group('newsPostsFromNode — News desk 2.0 fields', () {
    test('an old post (no Template/Gw/Players) reads as free news with no '
        'players', () {
      final post = newsPostsFromNode({
        'a': {'Title': 'Old post', 'Body': 'b', 'At': 1},
      }).single;
      expect(post.template, 'free');
      expect(post.gw, isNull);
      expect(post.players, isEmpty);
      expect(post.headerText, 'News');
    });

    test('Players as an RTDB-coerced List: index order, null holes and '
        'malformed cards skipped', () {
      final post = newsPostsFromNode({
        'p': {
          'Title': 'Team of the week',
          'At': 5,
          'Template': 'dreamteam',
          'Gw': 3,
          'Players': [
            _card('Gale', position: 'GK', extra: {
              'photoUrl': 'https://x/gale.jpg',
              'priceDeltaTenths': -5,
              'gw': 3,
              'gwPoints': 14,
              'seasonPoints': 40,
              'ownershipPct': 31,
            }),
            null,
            {'name': 'No Position', 'priceTenths': 50},
            {'name': 'Bad Position', 'position': 'MID', 'priceTenths': 50},
            {'name': 'No Price', 'position': 'DEF'},
            {'position': 'DEF', 'priceTenths': 50}, // no name
            'junk',
            _card('Dana', position: 'DEF'),
          ],
        },
      }).single;

      expect(post.template, 'dreamteam');
      expect(post.gw, 3);
      expect(post.headerText, 'Team of the week · GW3');
      expect(post.players.map((c) => c.name), ['Gale', 'Dana']);

      final gale = post.players.first;
      expect(gale.position, FantasyPosition.gk);
      expect(gale.team, 'Lions');
      expect(gale.photoUrl, 'https://x/gale.jpg');
      expect(gale.priceTenths, 75);
      expect(gale.priceDeltaTenths, -5);
      expect(gale.gw, 3);
      expect(gale.gwPoints, 14);
      expect(gale.seasonPoints, 40);
      expect(gale.ownershipPct, 31);
      expect(gale.goals, 3);
      expect(gale.assists, 1);

      // Optional fields the server OMITS when unknown parse as null.
      final dana = post.players.last;
      expect(dana.photoUrl, isNull);
      expect(dana.priceDeltaTenths, isNull);
      expect(dana.gw, isNull);
      expect(dana.gwPoints, isNull);
      expect(dana.seasonPoints, isNull);
      expect(dana.ownershipPct, isNull);
    });

    test('Players as an index-keyed Map sorts numerically by key ("10" after '
        '"2"); goals/assists default to 0; string numbers tolerated', () {
      final post = newsPostsFromNode({
        'p': {
          'Title': 'Price watch',
          'At': 5,
          'Template': 'price',
          'Players': {
            '10': _card('Ten'),
            '2': _card('Two'),
            '0': {
              'name': 'Zero',
              'position': 'DEF',
              'team': 'Wolves',
              'priceTenths': '60',
              'ownershipPct': '12.5',
            },
            'x': _card('Not an index'),
          },
        },
      }).single;
      expect(post.players.map((c) => c.name), ['Zero', 'Two', 'Ten']);
      final zero = post.players.first;
      expect(zero.priceTenths, 60);
      expect(zero.ownershipPct, 12.5);
      expect(zero.goals, 0);
      expect(zero.assists, 0);
      // No Gw on the post → the header is just the label.
      expect(post.headerText, 'Price watch');
    });

    test('rows with an empty/missing Title are skipped (a push stamp that '
        'landed after a delete)', () {
      final posts = newsPostsFromNode({
        'ghost': {'PushedAt': 123, 'PushSent': 4},
        'blank': {'Title': '   ', 'Body': 'x', 'At': 9},
        'real': {'Title': 'Real', 'At': 1},
      });
      expect(posts.map((p) => p.id), ['real']);
    });

    test('a junk Template reads as News; Gw 0/junk reads as no gameweek', () {
      final posts = newsPostsFromNode({
        'a': {'Title': 'A', 'At': 2, 'Template': 'mystery', 'Gw': 0},
        'b': {'Title': 'B', 'At': 1, 'Template': '  ', 'Gw': 'x'},
      });
      expect(posts[0].template, 'mystery');
      expect(posts[0].gw, isNull);
      expect(posts[0].headerText, 'News');
      expect(posts[1].template, 'free');
      expect(posts[1].gw, isNull);
    });
  });

  group('newsTemplateLabel', () {
    test('every template maps to its fan-facing label', () {
      expect(newsTemplateLabel('spotlight'), 'Spotlight');
      expect(newsTemplateLabel('star'), 'Star of the week');
      expect(newsTemplateLabel('price'), 'Price watch');
      expect(newsTemplateLabel('h2h'), 'Head to head');
      expect(newsTemplateLabel('dreamteam'), 'Team of the week');
      expect(newsTemplateLabel('free'), 'News');
      expect(newsTemplateLabel('ai'), 'News');
      expect(newsTemplateLabel(''), 'News');
    });

    test('header text adds the gameweek when the post has one', () {
      final post = newsPostsFromNode({
        'a': {'Title': 'A', 'At': 1, 'Template': 'ai', 'Gw': 4},
        'b': {'Title': 'B', 'At': 2, 'Template': 'spotlight', 'Gw': '7'},
      });
      expect(post.map((p) => p.headerText),
          ['Spotlight · GW7', 'News · GW4']);
    });
  });
}
