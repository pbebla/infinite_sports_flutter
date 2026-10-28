// P6 — the DreamTeam parser against the functions' pinned write shape
// (finalize_core.ts): DreamTeam/<gw> = {Players:[{name, position, points}],
// ComputedAt, Auto?}, with the usual RTDB Map/List coercion tolerance
// (small-int gameweek keys list-coerce; a Players hole index-Map-coerces).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

Map week1() => {
      'Players': [
        {'name': 'Gale', 'position': 'GK', 'points': 14},
        {'name': 'Dana', 'position': 'DEF', 'points': 12},
        {'name': 'Yara', 'position': 'DEF', 'points': 9},
        {'name': 'Alex', 'position': 'ATT', 'points': 11},
        {'name': 'Wren', 'position': 'ATT', 'points': 8},
      ],
      'ComputedAt': 1760000000000,
      'Auto': true,
    };

void main() {
  group('dreamTeamFromNode', () {
    test('parses the functions shape, order preserved (GK, DEF, ATT)', () {
      final team = dreamTeamFromNode(week1())!;
      expect([for (final p in team.players) p.name],
          ['Gale', 'Dana', 'Yara', 'Alex', 'Wren']);
      expect(team.players.first.position, FantasyPosition.gk);
      expect(team.players.first.points, 14);
      expect(team.players.last.position, FantasyPosition.att);
      expect(team.computedAtMs, 1760000000000);
    });

    test('admin-edited node (Auto absent) parses identically', () {
      final node = week1()..remove('Auto');
      expect(dreamTeamFromNode(node), isNotNull);
    });

    test('Players index-Map-coerced keeps index order; string points '
        'tolerated', () {
      final team = dreamTeamFromNode({
        'Players': {
          '1': {'name': 'Dana', 'position': 'DEF', 'points': '12'},
          '0': {'name': 'Gale', 'position': 'GK', 'points': 14},
        },
      })!;
      expect([for (final p in team.players) p.name], ['Gale', 'Dana']);
      expect(team.players[1].points, 12);
      expect(team.computedAtMs, isNull);
    });

    test('malformed slots are skipped, never crash; all-bad -> null', () {
      final team = dreamTeamFromNode({
        'Players': [
          {'name': 'Gale', 'position': 'GK', 'points': 14},
          {'name': '', 'position': 'DEF', 'points': 3}, // empty name
          {'name': 'Bad', 'position': 'MID', 'points': 3}, // unknown position
          'garbage',
          null,
        ],
      })!;
      expect(team.players.map((p) => p.name), ['Gale']);

      expect(dreamTeamFromNode({'Players': []}), isNull);
      expect(dreamTeamFromNode({'ComputedAt': 1}), isNull);
      expect(dreamTeamFromNode('nope'), isNull);
      expect(dreamTeamFromNode(null), isNull);
    });
  });

  group('dreamTeamsFromNode', () {
    test('Map shape: gw keys parsed, unusable weeks dropped', () {
      final teams = dreamTeamsFromNode({
        '1': week1(),
        '2': {'Players': []}, // unusable
        'x': week1(), // non-int key
      });
      expect(teams.keys.toList(), [1]);
      expect(teams[1]!.players, hasLength(5));
    });

    test('List coercion: index = gameweek number, null padding skipped', () {
      final teams = dreamTeamsFromNode([null, week1(), null, week1()]);
      expect(teams.keys.toList()..sort(), [1, 3]);
    });

    test('absent/malformed node -> empty (the hub hides the card)', () {
      expect(dreamTeamsFromNode(null), isEmpty);
      expect(dreamTeamsFromNode('nope'), isEmpty);
    });
  });
}
