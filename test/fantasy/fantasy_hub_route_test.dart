// Fantasy push taps (spec 2026-10-28 §4.2): every fantasy push carries
// `{type:'fantasy', sport, season, gw}` and news pushes add `postId`. The
// pure route helper decides where the tap lands — News + the post when a
// postId is present, My Team otherwise — and refuses unusable payloads so a
// tap can never crash the app.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';

void main() {
  group('fantasyRouteFromPayload', () {
    test('a news push opens the News tab focused on the post', () {
      final route = fantasyRouteFromPayload({
        'type': 'fantasy',
        'sport': 'Futsal',
        'season': '16',
        'gw': '3',
        'postId': '-Nabc123',
      })!;
      expect(route.sport, 'Futsal');
      expect(route.season, '16');
      expect(route.initialTab, FantasyHubTab.news);
      expect(route.focusPostId, '-Nabc123');
    });

    test('deadline reminder / recap / alert / owner message (no postId) '
        'opens My Team', () {
      for (final data in [
        {'type': 'fantasy', 'sport': 'Futsal', 'season': '16', 'gw': '3'},
        {
          'type': 'fantasy',
          'sport': 'Futsal',
          'season': '16',
          'gw': '0',
          'postId': '  ',
        },
      ]) {
        final route = fantasyRouteFromPayload(data)!;
        expect(route.initialTab, FantasyHubTab.myTeam);
        expect(route.focusPostId, isNull);
      }
    });

    test('missing sport or season → null (the tap does nothing)', () {
      expect(
          fantasyRouteFromPayload(
              {'type': 'fantasy', 'season': '16', 'postId': 'p'}),
          isNull);
      expect(
          fantasyRouteFromPayload(
              {'type': 'fantasy', 'sport': 'Futsal', 'season': ''}),
          isNull);
    });

    test('non-fantasy payloads are not fantasy routes', () {
      // A league-watcher payload also carries sport/season — it must keep
      // flowing to the match page, never the hub.
      expect(
          fantasyRouteFromPayload({
            'sport': 'Futsal',
            'season': '16',
            'dateKey': '11022026',
            'gameIndex': '0',
          }),
          isNull);
      expect(fantasyRouteFromPayload({'type': 'goal'}), isNull);
      expect(fantasyRouteFromPayload(const {}), isNull);
    });

    test('tab enum order matches the hub TabBar order', () {
      expect(FantasyHubTab.values.map((t) => t.index), [0, 1, 2, 3, 4]);
      expect(FantasyHubTab.myTeam.index, 0);
      expect(FantasyHubTab.players.index, 1);
      expect(FantasyHubTab.leaderboards.index, 2);
      expect(FantasyHubTab.news.index, 3);
      expect(FantasyHubTab.rules.index, 4);
    });
  });
}
