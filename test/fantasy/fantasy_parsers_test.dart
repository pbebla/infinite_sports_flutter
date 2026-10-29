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

    group('lockOverrideUntil expiry (spec §2: effective override)', () {
      final now = DateTime.utc(2026, 11, 2, 23);
      final nowMs = now.millisecondsSinceEpoch;
      FantasyLockOverride effective(Object? override, Object? until) {
        final node = FantasyConfig.futsalDefault().toMap()
          ..['lockOverride'] = override;
        if (until != null) node['lockOverrideUntil'] = until;
        return configStateFromNode(node, now: now)!.lockOverride;
      }

      test('no until → the override stands (Never / testing)', () {
        expect(effective('locked', null), FantasyLockOverride.locked);
        expect(effective('open', null), FantasyLockOverride.open);
      });
      test('until in the future → still overridden', () {
        expect(effective('open', nowMs + 60000), FantasyLockOverride.open);
        expect(
            effective('locked', nowMs + 1), FantasyLockOverride.locked);
      });
      test('until passed (or exactly now) → auto', () {
        expect(effective('open', nowMs - 1), FantasyLockOverride.auto);
        expect(effective('locked', nowMs), FantasyLockOverride.auto);
        expect(effective('locked', (nowMs - 5000).toDouble()),
            FantasyLockOverride.auto);
      });
      test('junk until is treated as absent; auto stays auto', () {
        expect(effective('locked', 'x'), FantasyLockOverride.locked);
        expect(effective('locked', '123'), FantasyLockOverride.locked);
        expect(effective('auto', nowMs + 60000), FantasyLockOverride.auto);
        expect(effective(null, nowMs - 1), FantasyLockOverride.auto);
      });
      test('defaults to the real clock when no now is given', () {
        final node = FantasyConfig.futsalDefault().toMap()
          ..['lockOverride'] = 'locked'
          ..['lockOverrideUntil'] = 1000; // 1970: long expired
        expect(configStateFromNode(node)!.lockOverride,
            FantasyLockOverride.auto);
      });
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

    test('round 3: reads form / ppg (tenths) and games when the server wrote '
        'them', () {
      final totals = playerTotalsFromNode({
        'Ava Striker': {
          'points': 54,
          'ownershipPct': 62,
          'form': 85,
          'ppg': 77,
          'games': 7,
        },
        'Strings': {'points': 9, 'form': '40', 'ppg': '30', 'games': '3'},
        // A player with no games: the server writes zeros, never NaN.
        'Fresh': {
          'points': 0,
          'ownershipPct': 0,
          'form': 0,
          'ppg': 0,
          'games': 0,
        },
      })!;
      final ava = totals['Ava Striker']!;
      expect(ava.formTenths, 85);
      expect(ava.ppgTenths, 77);
      expect(ava.games, 7);
      final s = totals['Strings']!;
      expect((s.formTenths, s.ppgTenths, s.games), (40, 30, 3));
      // Zeros are real values, not "absent".
      final fresh = totals['Fresh']!;
      expect((fresh.formTenths, fresh.ppgTenths, fresh.games), (0, 0, 0));
    });

    test('round 3: old-shape nodes leave form / ppg / games null (UI "—")',
        () {
      final totals = playerTotalsFromNode({
        'Old': {'points': 12, 'ownershipPct': 10},
        'Bare': 17,
        'Junk': {'points': 3, 'form': 'nope', 'ppg': null, 'games': {}},
      })!;
      for (final name in ['Old', 'Bare', 'Junk']) {
        final t = totals[name]!;
        expect(t.formTenths, isNull, reason: '$name form');
        expect(t.ppgTenths, isNull, reason: '$name ppg');
        expect(t.games, isNull, reason: '$name games');
      }
      expect(totals['Old']!.points, 12);
      expect(totals['Junk']!.points, 3);
    });
  });

  group('priceHistoryFromNode (round 3, PriceHistory/<gw>/<name>)', () {
    test('absent/malformed → empty', () {
      expect(priceHistoryFromNode(null), isEmpty);
      expect(priceHistoryFromNode('nope'), isEmpty);
      expect(priceHistoryFromNode(5), isEmpty);
    });
    test('map node: week → name → tenths, strings coerced, junk skipped', () {
      final h = priceHistoryFromNode({
        '1': {'Ava Striker': 60, 'Deb Rock': '55', 'Bad': 'x', 'Nul': null},
        '2': {'Ava Striker': 65},
        'weird': {'Ignored': 1},
        '3': 'not-a-map',
      });
      expect(h.keys.toList()..sort(), [1, 2]);
      expect(h[1], {'Ava Striker': 60, 'Deb Rock': 55});
      expect(h[2], {'Ava Striker': 65});
    });
    test('list coercion (gw keys ARE small ints): index = gameweek', () {
      final h = priceHistoryFromNode([
        null,
        {'Ava Striker': 60},
        {'Ava Striker': 65},
      ]);
      expect(h[1], {'Ava Striker': 60});
      expect(h[2], {'Ava Striker': 65});
      expect(h.containsKey(0), isFalse);
    });
    test('a week with no usable price is omitted (never an empty row)', () {
      final h = priceHistoryFromNode({
        '1': {'Bad': 'x'},
        '2': {'Ok': 50},
      });
      expect(h.keys, [2]);
    });
  });

  group('allPriceChangesFromNode (round 3, PriceChanges/<gw>)', () {
    test('absent/malformed → empty', () {
      expect(allPriceChangesFromNode(null), isEmpty);
      expect(allPriceChangesFromNode('nope'), isEmpty);
    });
    test('every week kept; Manual/Voided flag keys and zeros ignored', () {
      final c = allPriceChangesFromNode({
        '2': {'Ava Striker': 5, 'Deb Rock': -5, 'Flat': 0},
        '3': {'Ava Striker': -10, 'Manual': true, 'Voided': false},
        '4': {'Voided': true}, // flag-only reprice week
        '5': {'Bare': 5, 'Mapped': {'delta': -5}, 'Str': '10'},
        'weird': {'Ignored': 5},
      });
      expect(c.keys.toList()..sort(), [2, 3, 4, 5]);
      expect(c[2], {'Ava Striker': 5, 'Deb Rock': -5});
      expect(c[3], {'Ava Striker': -10});
      expect(c[4], isEmpty);
      expect(c[5], {'Bare': 5, 'Mapped': -5, 'Str': 10});
    });
    test('list coercion: index = gameweek, holes skipped', () {
      final c = allPriceChangesFromNode([
        null,
        {'Up': 5},
        null,
        {'Down': -5, 'Manual': true},
      ]);
      expect(c.keys.toList()..sort(), [1, 3]);
      expect(c[1], {'Up': 5});
      expect(c[3], {'Down': -5});
    });
  });

  group('watchlistFromNode (round 3, Watchlists/<uid>)', () {
    test('absent/malformed → empty set', () {
      expect(watchlistFromNode(null), isEmpty);
      expect(watchlistFromNode('nope'), isEmpty);
      expect(watchlistFromNode([true]), isEmpty);
    });
    test('only names whose value is exactly true are starred', () {
      expect(
          watchlistFromNode({
            'Ava Striker': true,
            'Deb Rock': true,
            'Un-starred': false,
            'Weird': 'yes',
            'Gone': null,
          }),
          {'Ava Striker', 'Deb Rock'});
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
