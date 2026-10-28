import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/stats_mapper.dart';

void main() {
  // Mirrors a REAL `Futsal/<season>/Date/<MMDDYYYY>/<i>` node:
  // - minute-keyed activity map with List buckets (team1activity),
  //   one bucket index-Map-coerced (RTDB), `_t` insertion stamps on leaves;
  // - team2activity arrives LIST-coerced (dense numeric minute keys) with a
  //   leading null and one null leaf inside a bucket;
  // - mixed score types (String '3' vs int 1) as utility.dart tolerates.
  Map gameNode() => {
        'team1': 'Sharks',
        'team2': 'Wolves',
        'team1score': '3',
        'team2score': 1,
        'status': 2,
        'team1activity': {
          "5'": [
            {'Goal': 'Alex', '_t': 1111},
            {'Assist': 'Dana'},
          ],
          "12'": [
            {'PenGoal': 'Alex'},
          ],
          "18'": {
            // bucket coerced to an index-keyed Map
            '0': {'Save': 'Sam'},
            '1': {'Save': 'Sam'},
          },
          "27'": [
            {'PenSaved': 'Sam', '_t': 2222},
          ],
          "30'": [
            {'Goal': 'Dana'},
            {'Foul': 'Dana'}, // no fantasy counter — ignored
          ],
        },
        'team2activity': [
          null, // RTDB null padding
          [
            {'Yellow': 'Will'},
          ],
          [
            {'Save': 'Wes'},
            {'Goal': 'Wren'},
          ],
          [
            {'SecondYellow': 'Will'},
            {'PenMissed': 'Wren'},
            null, // null leaf inside a bucket
          ],
          [
            {'DPL': 'Will'},
            {'OwnGoal': 'Wes'},
            {'Red': 'Wade'},
          ],
        ],
      };

  test('goals aggregate Goal + PenGoal; Foul has no fantasy counter', () {
    final stats = mapGameToStats(gameNode(), teamName: 'Sharks');
    expect(stats['Alex']!.goals, 2); // Goal + PenGoal
    final dana = stats['Dana']!;
    expect(dana.goals, 1);
    expect(dana.assists, 1);
    // Dana's Foul leaf changed nothing else.
    expect(dana.saves + dana.dpl + dana.yellows + dana.reds, 0);
  });

  test('PenSaved credits the keeper on his OWN team list: penSaved AND a save',
      () {
    // League pairing (league_sport_config.dart statKeys ['PenSaved','Saves'],
    // tournament_stats_engine PenSaved -> Saves): a penalty save is also a
    // save, so Sam = 2 Save events + 1 PenSaved = 3 saves.
    final stats = mapGameToStats(gameNode(), teamName: 'Sharks');
    expect(stats['Sam']!.penSaved, 1);
    expect(stats['Sam']!.saves, 3);
  });

  test('second yellow counts as a red, never a yellow; plain Red too', () {
    final stats = mapGameToStats(gameNode(), teamName: 'Wolves');
    expect(stats['Will']!.yellows, 1); // the first Yellow only
    expect(stats['Will']!.reds, 1); // the SecondYellow IS the red
    expect(stats['Wade']!.reds, 1); // plain Red
  });

  test('teamConceded is the OPPOSING team final score, any score type', () {
    final sharks = mapGameToStats(gameNode(), teamName: 'Sharks');
    final wolves = mapGameToStats(gameNode(), teamName: 'Wolves');
    expect(sharks['Alex']!.teamConceded, 1); // int score
    expect(wolves['Wren']!.teamConceded, 3); // String score '3'
  });

  test('List-coerced activity with leading null and null leaves parses', () {
    final wolves = mapGameToStats(gameNode(), teamName: 'Wolves');
    expect(wolves['Wren']!.goals, 1);
    expect(wolves['Wren']!.penMissed, 1);
    expect(wolves['Wes']!.saves, 1);
    expect(wolves['Wes']!.ownGoals, 1);
    expect(wolves['Will']!.dpl, 1);
  });

  test('`_t` metadata keys on leaves are never read as event types', () {
    final sharks = mapGameToStats(gameNode(), teamName: 'Sharks');
    // The '_t'-stamped leaves still land on the right counters...
    expect(sharks['Alex']!.goals, 2);
    expect(sharks['Sam']!.penSaved, 1);
    // ...and no phantom player named like an epoch stamp appears.
    expect(sharks.keys.where((k) => k.startsWith('_')), isEmpty);
    expect(sharks.keys, isNot(contains('1111')));
  });

  test('attendance null (absent node) means everyone present — spec §8', () {
    final stats = mapGameToStats(gameNode(), teamName: 'Sharks');
    expect(stats.values.every((s) => s.present), isTrue);
  });

  test('explicit attendance stamps through: absent player, zero-event player',
      () {
    final stats = mapGameToStats(gameNode(), teamName: 'Sharks', attendance: {
      'Sam': true,
      'Dana': true,
      'Alex': false, // captured events but marked absent
      'Riley': true, // zero activities, still present via attendance keys
    });
    expect(stats['Alex']!.present, isFalse);
    expect(stats['Alex']!.goals, 2); // stats still tallied; scoring zeroes him
    final riley = stats['Riley']!;
    expect(riley.present, isTrue);
    expect(riley.goals, 0);
    expect(riley.saves, 0);
    expect(riley.teamConceded, 1); // conceded stamps every roster entry
  });

  test('player with events but missing from attendance defaults to present',
      () {
    final stats = mapGameToStats(gameNode(), teamName: 'Sharks',
        attendance: {'Sam': true}); // Dana/Alex not listed
    expect(stats['Dana']!.present, isTrue);
  });

  test('a game with no activity yields only attendance players', () {
    final node = {
      'team1': 'Sharks',
      'team2': 'Wolves',
      'team1score': 0,
      'team2score': 0,
      'status': 0,
    };
    expect(mapGameToStats(node, teamName: 'Sharks'), isEmpty);
    final stats = mapGameToStats(node,
        teamName: 'Sharks', attendance: {'Sam': true, 'Riley': false});
    expect(stats.keys, unorderedEquals(['Sam', 'Riley']));
    expect(stats['Sam']!.present, isTrue);
    expect(stats['Riley']!.present, isFalse);
    expect(stats['Sam']!.teamConceded, 0);
  });

  test('clean sheet source: conceded 0 when opponent never scored', () {
    final node = gameNode()..['team2score'] = 0;
    final sharks = mapGameToStats(node, teamName: 'Sharks');
    expect(sharks['Sam']!.teamConceded, 0);
  });

  test('legacy score spelling team1Score/team2Score is read too', () {
    final node = gameNode()
      ..remove('team2score')
      ..['team2Score'] = 2;
    final sharks = mapGameToStats(node, teamName: 'Sharks');
    expect(sharks['Sam']!.teamConceded, 2);
  });

  test('unknown team name throws ArgumentError', () {
    expect(() => mapGameToStats(gameNode(), teamName: 'Eagles'),
        throwsArgumentError);
  });

  group('forfeits (spec §8a)', () {
    // Wolves forfeited (forfeitedBy 2): 5–0 to the Sharks; the node still
    // carries the stray events above, which must be ignored entirely.
    Map forfeitNode([Object? marker = 2]) => gameNode()
      ..['team1score'] = 5
      ..['team2score'] = 0
      ..['forfeitedBy'] = marker;

    test('showing-up side = won, forfeiting side = lost; the player set is '
        'the attendance keys only, events ignored', () {
      final sharks = mapGameToStats(forfeitNode(),
          teamName: 'Sharks',
          attendance: {'Sam': true, 'Dana': true, 'Riley': false});
      // Alex scored twice on the timeline but is not in the attendance map:
      // a forfeit never discovers players from events.
      expect(sharks.keys, unorderedEquals(['Sam', 'Dana', 'Riley']));
      for (final s in sharks.values) {
        expect(s.forfeit, GameForfeit.won);
        expect(s.goals + s.assists + s.saves + s.penSaved, 0);
      }
      expect(sharks['Riley']!.present, isFalse);
      expect(sharks['Dana']!.teamConceded, 0);

      final wolves = mapGameToStats(forfeitNode(),
          teamName: 'Wolves', attendance: {'Wes': true, 'Will': true});
      expect(wolves.keys, unorderedEquals(['Wes', 'Will']));
      for (final s in wolves.values) {
        expect(s.forfeit, GameForfeit.lost);
        expect(s.played, isFalse);
        expect(s.yellows + s.reds + s.saves + s.ownGoals, 0);
      }
    });

    test('no attendance map on a forfeit -> no players (callers must pass '
        'the roster-composed map)', () {
      expect(mapGameToStats(forfeitNode(), teamName: 'Sharks'), isEmpty);
    });

    test('tolerant marker parse: "1"/2.0 count; 0, 3, junk = not a forfeit',
        () {
      final byString = mapGameToStats(forfeitNode('1'),
          teamName: 'Sharks', attendance: {'Sam': true});
      expect(byString['Sam']!.forfeit, GameForfeit.lost); // team1 forfeited
      final byDouble = mapGameToStats(forfeitNode(2.0),
          teamName: 'Sharks', attendance: {'Sam': true});
      expect(byDouble['Sam']!.forfeit, GameForfeit.won);
      for (final junk in [0, 3, 'x', null, true]) {
        final stats = mapGameToStats(forfeitNode(junk), teamName: 'Sharks');
        expect(stats['Alex']!.forfeit, GameForfeit.none, reason: '$junk');
        expect(stats['Alex']!.goals, 2, reason: '$junk'); // events count
      }
    });

    test('undo (marker removed) maps the same node normally again', () {
      final node = forfeitNode()..remove('forfeitedBy');
      final sharks = mapGameToStats(node, teamName: 'Sharks');
      expect(sharks['Alex']!.forfeit, GameForfeit.none);
      expect(sharks['Alex']!.goals, 2);
    });
  });
}
