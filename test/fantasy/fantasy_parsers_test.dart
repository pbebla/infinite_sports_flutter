// P3a Task 1 — pure parser + formatting tests for the fantasy data layer
// (RTDB Map/List coercion tolerance as always).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

void main() {
  group('configStateFromNode', () {
    test('absent/malformed node → null (gates the Fantasy tab)', () {
      expect(configStateFromNode(null), isNull);
      expect(configStateFromNode('nope'), isNull);
      expect(configStateFromNode([1, 2]), isNull);
    });
    test('parses engine config + lockOverride', () {
      final node = FantasyConfig.futsalDefault().toMap()
        ..['lockOverride'] = 'open';
      final state = configStateFromNode(node)!;
      expect(state.lockOverride, FantasyLockOverride.open);
      expect(state.config.budgetTenths, 500);
      expect(state.config.scoring[FantasyPosition.gk]!.goal, 10);
    });
    test('absent lockOverride = auto (production behavior)', () {
      final state = configStateFromNode(FantasyConfig.futsalDefault().toMap());
      expect(state!.lockOverride, FantasyLockOverride.auto);
      expect(FantasyLockOverride.parse('locked'), FantasyLockOverride.locked);
      expect(FantasyLockOverride.parse('weird'), FantasyLockOverride.auto);
    });
  });

  group('managerFromNode', () {
    test('absent/malformed/empty-name node → null (prompt to name)', () {
      expect(managerFromNode(null), isNull);
      expect(managerFromNode('nope'), isNull);
      expect(managerFromNode({'NameFlagged': true}), isNull);
      expect(managerFromNode({'TeamName': '   '}), isNull);
    });
    test('parses TeamName + NameFlagged, flag defaults false', () {
      final m = managerFromNode({'TeamName': 'Golden Boots'})!;
      expect(m.teamName, 'Golden Boots');
      expect(m.nameFlagged, isFalse);

      final flagged = managerFromNode(
          {'TeamName': 'Bad Name', 'NameFlagged': true})!;
      expect(flagged.nameFlagged, isTrue);
      // Non-bool junk never counts as flagged.
      expect(
          managerFromNode({'TeamName': 'X Y Z', 'NameFlagged': 'yes'})!
              .nameFlagged,
          isFalse);
    });
  });

  group('playersFromNode', () {
    test('parses entries, skips unusable ones, sorts by name', () {
      final players = playersFromNode({
        'Zed Last': {
          'position': 'ATT',
          'priceTenths': 60,
          'eligible': true,
          'teamName': 'B',
        },
        'Ana First': {
          'position': 'GK',
          'priceTenths': '85', // string-coerced numbers happen in RTDB
          'eligible': true,
          'teamName': 'A',
        },
        'Guest': {
          'position': 'ATT',
          'priceTenths': 60,
          'eligible': false,
          'teamName': 'C',
        },
        'Broken': {'position': 'MID', 'priceTenths': 60},
        'AlsoBroken': 'not-a-map',
      });
      expect(players.map((p) => p.name), ['Ana First', 'Guest', 'Zed Last']);
      expect(players.first.position, FantasyPosition.gk);
      expect(players.first.priceTenths, 85);
      expect(players[1].eligible, isFalse);
    });
    test('non-map node → empty', () {
      expect(playersFromNode(null), isEmpty);
      expect(playersFromNode([]), isEmpty);
    });
    test('FantasyPlayer round-trips through its own map', () {
      final p = FantasyPlayer.fromNode('P1', {
        'position': 'DEF',
        'priceTenths': 70,
        'eligible': true,
        'teamName': 'Hakkari',
      })!;
      expect(FantasyPlayer.fromNode('P1', p.toMap())!.toMap(), p.toMap());
    });
    test('photoUrl parses when present, null when absent/blank (P3b Task 3)',
        () {
      final withPhoto = FantasyPlayer.fromNode('P1', {
        'position': 'DEF',
        'priceTenths': 70,
        'eligible': true,
        'teamName': 'Hakkari',
        'photoUrl': 'https://example.com/p1.jpg',
      })!;
      expect(withPhoto.photoUrl, 'https://example.com/p1.jpg');
      expect(withPhoto.toMap()['photoUrl'], 'https://example.com/p1.jpg');
      // Round-trips with the photo intact.
      expect(FantasyPlayer.fromNode('P1', withPhoto.toMap())!.photoUrl,
          'https://example.com/p1.jpg');

      final without = FantasyPlayer.fromNode('P2', {
        'position': 'ATT',
        'priceTenths': 60,
        'eligible': true,
        'teamName': 'B',
      })!;
      expect(without.photoUrl, isNull);
      expect(without.toMap().containsKey('photoUrl'), isFalse);

      final blank = FantasyPlayer.fromNode('P3', {
        'position': 'ATT',
        'priceTenths': 60,
        'eligible': true,
        'teamName': 'B',
        'photoUrl': '  ',
      })!;
      expect(blank.photoUrl, isNull);
    });
  });

  group('squadFromNode', () {
    final squadMap = {
      'picks': [
        {'playerId': 'gk1', 'position': 'GK', 'priceTenths': 50, 'bench': false},
        {'playerId': 'd1', 'position': 'DEF', 'priceTenths': 60, 'bench': false},
        {'playerId': 'd2', 'position': 'DEF', 'priceTenths': 60, 'bench': false},
        {'playerId': 'a1', 'position': 'ATT', 'priceTenths': 80, 'bench': false},
        {'playerId': 'a2', 'position': 'ATT', 'priceTenths': 80, 'bench': false},
        {'playerId': 'd3', 'position': 'DEF', 'priceTenths': 40, 'bench': true},
        {'playerId': 'a3', 'position': 'ATT', 'priceTenths': 40, 'bench': true},
      ],
      'captainId': 'a1',
      'viceId': 'gk1',
    };
    test('parses the engine shape', () {
      final squad = squadFromNode(squadMap)!;
      expect(squad.picks, hasLength(7));
      expect(squad.captainId, 'a1');
      expect(squad.chip, isNull);
      expect(squad.spentTenths, 410);
    });
    test('absent or malformed → null, never a throw', () {
      expect(squadFromNode(null), isNull);
      expect(squadFromNode('x'), isNull);
      expect(squadFromNode({'picks': 'bad'}), isNull);
      expect(squadFromNode({'picks': []}), isNull); // missing captain/vice
    });
  });

  group('playerTotalsFromNode (P3c)', () {
    test('absent/malformed → null (hide the points column + Points sort)',
        () {
      expect(playerTotalsFromNode(null), isNull);
      expect(playerTotalsFromNode('nope'), isNull);
      expect(playerTotalsFromNode([1, 2]), isNull);
    });
    test('parses points + ownershipPct, tolerating strings and bare numbers',
        () {
      final totals = playerTotalsFromNode({
        'Ava Striker': {'points': 54, 'ownershipPct': 62.5},
        'Deb Rock': {'points': '31', 'ownershipPct': '12'},
        'No Pct': {'points': 9},
        'Bare': 17,
        'Junk': 'nope',
      })!;
      expect(totals['Ava Striker']!.points, 54);
      expect(totals['Ava Striker']!.ownershipPct, 62.5);
      expect(totals['Deb Rock']!.points, 31);
      expect(totals['Deb Rock']!.ownershipPct, 12);
      expect(totals['No Pct']!.points, 9);
      expect(totals['No Pct']!.ownershipPct, isNull);
      expect(totals['Bare']!.points, 17);
      expect(totals.containsKey('Junk'), isFalse);
    });
  });

  group('latestPriceChangesFromNode (P3c)', () {
    test('absent/malformed → empty (the strip hides entirely)', () {
      expect(latestPriceChangesFromNode(null), isEmpty);
      expect(latestPriceChangesFromNode('nope'), isEmpty);
      expect(latestPriceChangesFromNode({'1': 'junk'}), isEmpty);
    });
    test('map node: numerically LATEST gameweek wins, risers first, zeros '
        'and junk skipped', () {
      final changes = latestPriceChangesFromNode({
        '2': {
          'Old Riser': {'delta': 5}
        },
        '10': {
          'Faller': {'delta': -5},
          'Big Riser': {'delta': 10},
          'Riser': {'delta': 5},
          'Flat': {'delta': 0},
          'Junk': {'delta': 'nope'},
        },
        'weird': {
          'Ignored': {'delta': 5}
        },
      });
      expect(changes.map((c) => c.name).toList(),
          ['Big Riser', 'Riser', 'Faller']);
      expect(changes.first.deltaTenths, 10);
      expect(changes.last.deltaTenths, -5);
    });
    test('list coercion (gw keys ARE small ints): last non-null entry wins; '
        'bare-number deltas tolerated', () {
      final changes = latestPriceChangesFromNode([
        null,
        {'Old': 5},
        {'Up': 5, 'Down': -5},
        null,
      ]);
      expect(changes.map((c) => c.name).toList(), ['Up', 'Down']);
      expect(changes.first.deltaTenths, 5);
      expect(changes.last.deltaTenths, -5);
    });
  });

  group('squadAlertFromNode (spec §3 holder protection)', () {
    test('functions shape → alert; junk changes skipped', () {
      final alert = squadAlertFromNode({
        'Gw': 4,
        'Changes': [
          {'player': 'Ann Keeper', 'from': 'GK', 'to': 'DEF'},
          {'player': '', 'from': 'GK', 'to': 'DEF'},
          {'player': 'Bad', 'from': 'MID', 'to': 'DEF'},
          'nope',
        ],
        'CreatedAt': 1761660000000,
      })!;
      expect(alert.gameweek, 4);
      expect(alert.changes, hasLength(1));
      expect(alert.changes.single.player, 'Ann Keeper');
      expect(alert.changes.single.from, FantasyPosition.gk);
      expect(alert.changes.single.to, FantasyPosition.def);
    });

    test('index-keyed Changes map tolerated; absent/empty → null', () {
      final alert = squadAlertFromNode({
        'Gw': '2',
        'Changes': {
          '0': {'player': 'A', 'from': 'DEF', 'to': 'ATT'},
        },
      })!;
      expect(alert.gameweek, 2);
      expect(alert.changes.single.to, FantasyPosition.att);
      expect(squadAlertFromNode(null), isNull);
      expect(squadAlertFromNode({'Gw': 2, 'Changes': []}), isNull);
    });
  });

  group('dateKeysFromNode', () {
    test('map keys with non-null values', () {
      expect(
        dateKeysFromNode({'06292025': [1], '07062025': [1], 'gone': null}),
        unorderedEquals(['06292025', '07062025']),
      );
    });
    test('non-map → empty', () {
      expect(dateKeysFromNode(null), isEmpty);
      expect(dateKeysFromNode([1]), isEmpty);
    });
  });

  group('effectiveGameweekStatus', () {
    final cfg = FantasyConfig.futsalDefault();
    final gws = deriveGameweeks(['06282026', '07052026'], cfg);
    final beforeLock = DateTime.utc(2026, 6, 28, 12); // GW1 open
    final afterLock = DateTime.utc(2026, 6, 28, 23); // GW1 locked

    test('override open wins even when the engine says locked', () {
      expect(
        effectiveGameweekStatus(
            gameweek: gws[0],
            override: FantasyLockOverride.open,
            nowUtc: afterLock),
        GameweekStatus.open,
      );
    });
    test('override locked wins even when the engine says open', () {
      expect(
        effectiveGameweekStatus(
            gameweek: gws[0],
            override: FantasyLockOverride.locked,
            nowUtc: beforeLock),
        GameweekStatus.locked,
      );
    });
    test('auto follows the engine; no gameweek (season over) = locked', () {
      expect(
        effectiveGameweekStatus(
            gameweek: gws[0],
            override: FantasyLockOverride.auto,
            nowUtc: beforeLock),
        GameweekStatus.open,
      );
      expect(
        effectiveGameweekStatus(
            gameweek: null,
            override: FantasyLockOverride.auto,
            nowUtc: beforeLock),
        GameweekStatus.locked,
      );
    });
  });

  group('fantasy_format', () {
    test('money tenths', () {
      expect(formatMoneyTenths(85), '\$8.5M');
      expect(formatMoneyTenths(500), '\$50.0M');
      expect(formatMoneyTenths(40), '\$4.0M');
    });
    test('lock hour', () {
      expect(formatLockHour(15), '3:00 PM');
      expect(formatLockHour(0), '12:00 AM');
      expect(formatLockHour(12), '12:00 PM');
      expect(formatLockHour(9), '9:00 AM');
    });
    test('absolute lock is league wall-clock (PDT in July)', () {
      final cfg = FantasyConfig.futsalDefault();
      final gw = deriveGameweeks(['07052026'], cfg).single;
      // lockUtc = Jul 5 22:00 UTC; league local = 15:00 on Sunday Jul 5.
      expect(formatAbsoluteLock(gw), 'Sun, Jul 5 · 3:00 PM');
      expect(leagueLocalLock(gw), DateTime.utc(2026, 7, 5, 15));
    });
    test('absolute lock in PST (winter)', () {
      final cfg = FantasyConfig.futsalDefault();
      final gw = deriveGameweeks(['01112026'], cfg).single;
      expect(formatAbsoluteLock(gw), 'Sun, Jan 11 · 3:00 PM');
    });
    test('countdown buckets', () {
      expect(formatCountdown(const Duration(seconds: 40)), 'under a minute');
      expect(formatCountdown(const Duration(minutes: 41)), '41m');
      expect(
          formatCountdown(const Duration(hours: 3, minutes: 12)), '3h 12m');
      expect(formatCountdown(const Duration(days: 2, hours: 4, minutes: 9)),
          '2d 4h');
    });
  });
}
