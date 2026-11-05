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

  group('seasonFinishedFromNode (/<sport>/<season>/Finished)', () {
    test('only an exact true means the season is over', () {
      expect(seasonFinishedFromNode(true), isTrue);
    });
    test('absent / false / anything else is not finished', () {
      expect(seasonFinishedFromNode(null), isFalse);
      expect(seasonFinishedFromNode(false), isFalse);
      expect(seasonFinishedFromNode('true'), isFalse);
      expect(seasonFinishedFromNode(1), isFalse);
      expect(seasonFinishedFromNode({'a': true}), isFalse);
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

    // Squad hardening (audit I2): the server's integrity verdict shares the
    // node — {Gw, Kind:'invalid', Issues:[...], CreatedAt}.
    test('integrity alert (Kind invalid) → an invalid alert with its issues', () {
      final alert = squadAlertFromNode({
        'Gw': 3,
        'Kind': 'invalid',
        'Issues': ['duplicatePlayer', 'overBudget'],
        'CreatedAt': 1761660000000,
      })!;
      expect(alert.isInvalid, isTrue);
      expect(alert.kind, FantasySquadAlertKind.invalid);
      expect(alert.gameweek, 3);
      expect(alert.issues, ['duplicatePlayer', 'overBudget']);
      expect(alert.changes, isEmpty);
    });

    test('integrity alert: lower-case fields, index-keyed issues, junk skipped, '
        'no issues still an alert', () {
      final lower = squadAlertFromNode({
        'gameweek': '5',
        'kind': 'invalid',
        'issues': {'0': 'tooManyPlayers', '1': '', '2': 7, '3': 'somethingNew'},
      })!;
      expect(lower.isInvalid, isTrue);
      expect(lower.gameweek, 5);
      expect(lower.issues, ['tooManyPlayers', 'somethingNew']);

      final bare = squadAlertFromNode({'Gw': 2, 'Kind': 'invalid'})!;
      expect(bare.isInvalid, isTrue);
      expect(bare.issues, isEmpty);
    });

    test('a position alert is unchanged (no Kind) and is never "invalid"', () {
      final alert = squadAlertFromNode({
        'Gw': 4,
        'Changes': [
          {'player': 'Ann', 'from': 'GK', 'to': 'DEF'},
        ],
      })!;
      expect(alert.isInvalid, isFalse);
      expect(alert.isOverBudgetPreview, isFalse);
      expect(alert.kind, FantasySquadAlertKind.positionChange);
      expect(alert.issues, isEmpty);
      // An unknown future Kind falls back to the position shape.
      expect(squadAlertFromNode({'Gw': 4, 'Kind': 'other'}), isNull);
    });

    // FPL selling (spec §4): the sweep's over-budget preview shares the
    // node — {Gw, Kind:'preview', Issues:['overBudget'], OverTenths,
    // CreatedAt}.
    test('preview (Kind preview) → an over-budget preview with OverTenths',
        () {
      final alert = squadAlertFromNode({
        'Gw': 2,
        'Kind': 'preview',
        'Issues': ['overBudget'],
        'OverTenths': 5,
        'CreatedAt': 1782597600000,
      })!;
      expect(alert.kind, FantasySquadAlertKind.overBudgetPreview);
      expect(alert.isOverBudgetPreview, isTrue);
      expect(alert.isInvalid, isFalse);
      expect(alert.gameweek, 2);
      expect(alert.overTenths, 5);
      expect(alert.issues, ['overBudget']);
      expect(alert.changes, isEmpty);
    });

    test('preview: lower-case fields, a string amount; no amount still an '
        'alert (0)', () {
      final lower = squadAlertFromNode({
        'gameweek': '3',
        'kind': 'preview',
        'issues': {'0': 'overBudget'},
        'overTenths': '12',
      })!;
      expect(lower.isOverBudgetPreview, isTrue);
      expect(lower.gameweek, 3);
      expect(lower.overTenths, 12);
      expect(lower.issues, ['overBudget']);

      final bare = squadAlertFromNode({'Gw': 2, 'Kind': 'preview'})!;
      expect(bare.isOverBudgetPreview, isTrue);
      expect(bare.overTenths, 0);
      // The other kinds carry no amount.
      expect(
          squadAlertFromNode({'Gw': 2, 'Kind': 'invalid', 'OverTenths': 5})!
              .overTenths,
          0);
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

  group('parseTransferState (Fantasy/<sport>/<season>/TransferState/<uid>)',
      () {
    test('absent node → null (a first team, the preview decides)', () {
      expect(parseTransferState(null), isNull);
    });

    test('a present node that is not a map reads as "no baseline", never '
        'as absent', () {
      final v = parseTransferState('junk')!;
      expect(v.countFromGw, isNull);
      expect(v.free, isNull);
    });

    test('every field of the server shape', () {
      final v = parseTransferState({
        'Free': 4,
        'UsedThisGw': 2,
        'ChipPlayed': 'wildcard', // ignored by the view
        'SavedGw': 5,
        'RolledGw': 4,
        'CountFromGw': 5,
        'CountFrom': ['a', 'b', 'c'],
        'FreeSwapsGw': 5,
        'FreeSwaps': ['a'],
      })!;
      expect(v.free, 4);
      expect(v.usedThisGw, 2);
      expect(v.countFromGw, 5);
      expect(v.countFrom, ['a', 'b', 'c']);
      expect(v.freeSwapsGw, 5);
      expect(v.freeSwaps, ['a']);
    });

    test('a bare {Free, UsedThisGw} node (pre-feature) has no baseline', () {
      final v = parseTransferState({'Free': 2, 'UsedThisGw': 0})!;
      expect(v.free, 2);
      expect(v.countFromGw, isNull);
      expect(v.countFrom, isNull);
      expect(v.freeSwaps, isEmpty);
      expect(v.freeSwapsGw, isNull);
    });

    test('Free absent stays null; UsedThisGw absent reads 0', () {
      final v = parseTransferState({'CountFromGw': 3})!;
      expect(v.free, isNull);
      expect(v.usedThisGw, 0);
    });

    test('CountFromGw alone = a first team for that week (countFrom null)',
        () {
      final v = parseTransferState({'Free': 2, 'CountFromGw': 1})!;
      expect(v.countFromGw, 1);
      expect(v.countFrom, isNull);
    });

    test('CountFrom without CountFromGw is half-written: treated as none',
        () {
      final v = parseTransferState({'CountFrom': ['a', 'b']})!;
      expect(v.countFromGw, isNull);
      expect(v.countFrom, isNull);
    });

    test('FreeSwaps without FreeSwapsGw (and the reverse) is none', () {
      final noGw = parseTransferState({'FreeSwaps': ['a']})!;
      expect(noGw.freeSwaps, isEmpty);
      expect(noGw.freeSwapsGw, isNull);
      final noSwaps = parseTransferState({'FreeSwapsGw': 5})!;
      expect(noSwaps.freeSwaps, isEmpty);
      expect(noSwaps.freeSwapsGw, isNull);
    });

    test('RTDB list coercion: holed lists and index-keyed maps both read',
        () {
      final holed = parseTransferState({
        'CountFromGw': 2,
        'CountFrom': ['a', null, 'c'],
        'FreeSwapsGw': 2,
        'FreeSwaps': {'0': 'a', '2': 'c'},
      })!;
      expect(holed.countFrom, ['a', 'c']);
      expect(holed.freeSwaps, unorderedEquals(['a', 'c']));
    });

    test('blank and non-string ids are skipped; none left = first team',
        () {
      final v = parseTransferState({
        'CountFromGw': 2,
        'CountFrom': ['', 7, null],
      })!;
      expect(v.countFromGw, 2);
      expect(v.countFrom, isNull);
    });

    test('numbers arrive as ints, doubles or numeric strings; junk is none',
        () {
      final v = parseTransferState({
        'Free': 3.0,
        'UsedThisGw': '2',
        'CountFromGw': '5',
      })!;
      expect(v.free, 3);
      expect(v.usedThisGw, 2);
      expect(v.countFromGw, 5);
      final bad = parseTransferState({'Free': 'x', 'CountFromGw': 0})!;
      expect(bad.free, isNull);
      expect(bad.countFromGw, isNull); // a gameweek is 1+
    });

    test('equal nodes parse to equal views (the draft notifies on change '
        'only)', () {
      Object? node() => {
            'Free': 2,
            'CountFromGw': 5,
            'CountFrom': ['a', 'b'],
            'FreeSwapsGw': 5,
            'FreeSwaps': ['a'],
          };
      expect(parseTransferState(node()), parseTransferState(node()));
      expect(parseTransferState(node()).hashCode,
          parseTransferState(node()).hashCode);
      expect(
          parseTransferState(node()),
          isNot(parseTransferState(
              {...(node() as Map), 'CountFrom': ['a', 'c']})));
    });
  });

  // Live everywhere, Task 4: History/<gw>/<uid>.Breakdown (written by
  // finalize since the live design, unread by the app until now) — the
  // SETTLED per-player points the squad viewer shows for a past week, the
  // same row shape as the live node's Squads/<uid>.Slots.
  group('historyBreakdownFromNode (History/<gw>/<uid>.Breakdown)', () {
    Map<String, Object?> row(String id, int tenths, int x,
            {bool sub = false}) =>
        {
          'playerId': id,
          'countedTenths': tenths,
          'multiplier': x,
          'autoSubbedIn': sub,
        };

    test('parses {playerId, countedTenths, multiplier, autoSubbedIn} in '
        'pick order', () {
      final slots = historyBreakdownFromNode([
        row('Ava Striker', 80, 2),
        row('Deb Rock', 30, 1, sub: true),
        row('Bench Bob', 0, 0),
      ]);
      expect(slots.map((s) => s.playerId),
          ['Ava Striker', 'Deb Rock', 'Bench Bob']);
      expect(slots[0].countedTenths, 80);
      expect(slots[0].multiplier, 2);
      expect(slots[0].autoSubbedIn, isFalse);
      expect(slots[1].autoSubbedIn, isTrue);
      expect(slots[2].multiplier, 0);
    });

    test('tolerates the index-keyed map shape and the whole History entry',
        () {
      final asMap = historyBreakdownFromNode({
        '1': row('B', 20, 1),
        '0': row('A', 10, 1),
      });
      expect(asMap.map((s) => s.playerId), ['A', 'B']);

      final entry = historyBreakdownFromNode({
        'TotalTenths': 30,
        'Breakdown': [row('A', 10, 1), row('B', 20, 1)],
      });
      expect(entry.map((s) => s.playerId), ['A', 'B']);
    });

    test('absent (an invalid squad has no Breakdown) / junk → empty; '
        'malformed rows skipped', () {
      expect(historyBreakdownFromNode(null), isEmpty);
      expect(historyBreakdownFromNode('nope'), isEmpty);
      expect(historyBreakdownFromNode({'TotalTenths': 0}), isEmpty);
      final slots = historyBreakdownFromNode([
        row('A', 10, 1),
        {'countedTenths': 5, 'multiplier': 1}, // no player
        {'playerId': 'B', 'multiplier': 1}, // no tenths
        {'playerId': 'C', 'countedTenths': 5}, // no multiplier
        'junk',
      ]);
      expect(slots.map((s) => s.playerId), ['A']);
    });
  });

  // Live everywhere, Task 5: the locked My Team's settled week. One small
  // `History/<gw>/<uid>` node (never the whole History) and one
  // `Leaderboards/Overall/<uid>` row.
  group('historyWeekFromNode (History/<gw>/<uid>)', () {
    Map<String, Object?> row(String id, int tenths, int x) => {
          'playerId': id,
          'countedTenths': tenths,
          'multiplier': x,
          'autoSubbedIn': false,
        };

    test('a settled week: net tenths + the Breakdown slots', () {
      final week = historyWeekFromNode({
        'picks': [],
        'TotalTenths': 345,
        'Breakdown': [row('A', 100, 2), row('B', 245, 1)],
      })!;
      expect(week.totalTenths, 345);
      expect(week.slots.map((s) => s.playerId), ['A', 'B']);
      expect(week.voided, isFalse);
      expect(week.invalid, isFalse);
    });

    test(
        'the squad that scored the week rides along: its picks, armband and '
        'the chip honored at the lock', () {
      final week = historyWeekFromNode({
        'picks': [
          {
            'playerId': 'Ava Striker',
            'position': 'ATT',
            'priceTenths': 70,
            'bench': false
          },
          {
            'playerId': 'Dom Stone',
            'position': 'DEF',
            'priceTenths': 50,
            'bench': true
          },
        ],
        'captainId': 'Ava Striker',
        'viceId': 'Dom Stone',
        'chip': 'tripleCaptain',
        'TotalTenths': 345,
        'Breakdown': const [],
      })!;
      expect(week.squad, isNotNull);
      expect(week.squad!.chip, 'tripleCaptain');
      expect(week.squad!.captainId, 'Ava Striker');
      expect(week.squad!.picks.map((p) => p.playerId),
          ['Ava Striker', 'Dom Stone']);
      expect(week.squad!.picks.last.bench, isTrue);
    });

    test('a node with no readable squad has none (never a made-up one)', () {
      expect(historyWeekFromNode({'TotalTenths': 5})!.squad, isNull);
      expect(
          historyWeekFromNode({'TotalTenths': 5, 'picks': 'junk'})!.squad,
          isNull);
    });

    test('a voided week keeps its would-have-counted slots and says so', () {
      final week = historyWeekFromNode({
        'TotalTenths': 0,
        'Voided': true,
        'Breakdown': [row('A', 100, 2)],
      })!;
      expect(week.voided, isTrue);
      expect(week.totalTenths, 0);
      expect(week.slots, hasLength(1));
    });

    test('an invalid squad: the Invalid marker, no Breakdown', () {
      final week = historyWeekFromNode({
        'TotalTenths': 0,
        'Invalid': ['over budget'],
      })!;
      expect(week.invalid, isTrue);
      expect(week.slots, isEmpty);
      // Only a literal Voided:true voids; an empty/absent Invalid is valid.
      expect(historyWeekFromNode({'TotalTenths': 5, 'Voided': 'yes'})!.voided,
          isFalse);
      expect(historyWeekFromNode({'TotalTenths': 5, 'Invalid': []})!.invalid,
          isFalse);
    });

    test('absent / not a map → null; a missing TotalTenths stays null '
        '(never a made-up 0)', () {
      expect(historyWeekFromNode(null), isNull);
      expect(historyWeekFromNode('nope'), isNull);
      expect(historyWeekFromNode([1]), isNull);
      expect(historyWeekFromNode({'picks': []})!.totalTenths, isNull);
    });
  });

  group('overallStandingFromNode (Leaderboards/Overall/<uid>)', () {
    test('rank + movement (places climbed)', () {
      final s = overallStandingFromNode(
          {'points': 120, 'rank': 5, 'movement': -2})!;
      expect(s.rank, 5);
      expect(s.movement, -2);
      expect(overallStandingFromNode({'points': 9, 'rank': 7})!.movement,
          isNull);
    });

    test('no usable rank → null (never rank 0)', () {
      expect(overallStandingFromNode(null), isNull);
      expect(overallStandingFromNode({'points': 3}), isNull);
      expect(overallStandingFromNode('x'), isNull);
    });
  });

  group('live flag defaults (live everywhere, Task 4)', () {
    test('official totals and dream teams are not live', () {
      final totals = playerTotalsFromNode({
        'Ava': {'points': 5},
      })!;
      expect(totals['Ava']!.live, isFalse);
      final teams = dreamTeamsFromNode([
        null,
        {
          'Players': [
            {'name': 'Ava', 'position': 'ATT', 'points': 5},
          ],
        },
      ]);
      expect(teams[1]!.live, isFalse);
    });
  });

  // ── Schedule nodes (season setup + schedule changes, Task 1) ─────────────
  group('lockedWeeksFromNode (LockedWeeks/<n>)', () {
    final week1 = {'Date': '10042026', 'LockAtUtc': 1791154800000};
    final expected1 = LockedWeek(
        date: '10042026', lockUtc: DateTime.utc(2026, 10, 4, 23));

    test('RTDB hands keys 1..n back as a List with a null index 0', () {
      expect(lockedWeeksFromNode([null, week1]), {1: expected1});
    });
    test('and as a Map when the keys are not dense', () {
      expect(lockedWeeksFromNode({'1': week1}), {1: expected1});
      expect(
          lockedWeeksFromNode({
            '1': week1,
            '3': {...week1, 'Date': '10182026'},
          }),
          {
            1: expected1,
            3: LockedWeek(
                date: '10182026', lockUtc: DateTime.utc(2026, 10, 4, 23)),
          });
    });
    test('a double epoch (web) counts; the instant is UTC', () {
      final w = lockedWeeksFromNode([null, {...week1, 'LockAtUtc': 1791154800000.0}])[1]!;
      expect(w.lockUtc, DateTime.utc(2026, 10, 4, 23));
      expect(w.lockUtc.isUtc, isTrue);
    });
    test('Scored counts only as a literal true', () {
      expect(lockedWeeksFromNode([null, {...week1, 'Scored': true}])[1]!.scored,
          isTrue);
      expect(lockedWeeksFromNode([null, {...week1, 'Scored': 'yes'}])[1]!.scored,
          isFalse);
      expect(lockedWeeksFromNode([null, {...week1, 'Scored': 1}])[1]!.scored,
          isFalse);
    });
    test('junk is skipped, never thrown on', () {
      expect(
          lockedWeeksFromNode([
            week1, // index 0 is not a week
            null,
            'nope',
            {'Date': '1004', 'LockAtUtc': 1791154800000}, // not MMDDYYYY
            {'Date': '13452026', 'LockAtUtc': 1791154800000}, // month 13
            {'Date': '02302026', 'LockAtUtc': 1791154800000}, // Feb 30
            {'Date': '10042026', 'LockAtUtc': '1791154800000'}, // not a number
            {'Date': '10042026', 'LockAtUtc': double.nan},
            {'Date': '10042026', 'LockAtUtc': 0},
            {'Date': 10042026, 'LockAtUtc': 1791154800000}, // Date not a string
            {'LockAtUtc': 1791154800000},
          ]),
          isEmpty);
      expect(lockedWeeksFromNode({'x': week1, '-1': week1, '1.5': week1}),
          isEmpty);
      expect(lockedWeeksFromNode(null), isEmpty);
      expect(lockedWeeksFromNode('nope'), isEmpty);
      expect(lockedWeeksFromNode(7), isEmpty);
    });
  });

  group('scheduleOverridesFromConfigNode (Config/SkippedDates, Deadlines)', () {
    test('SkippedDates: only a literal true counts', () {
      expect(
          scheduleOverridesFromConfigNode({
            'SkippedDates': {'10112026': true, '10182026': 'yes', '10252026': 1},
          }),
          const ScheduleOverrides(skippedDates: {'10112026'}));
    });
    test('Deadlines: epoch-ms numbers only, valid date keys only', () {
      final o = scheduleOverridesFromConfigNode({
        'Deadlines': {
          '10112026': 1791154800000,
          '10182026': 'x',
          '10252026': true,
          '11012026': '1791154800000',
          'junk': 5,
        },
      });
      expect(o.deadlineOverrides, {'10112026': DateTime.utc(2026, 10, 4, 23)});
      expect(o.deadlineOverrides['10112026']!.isUtc, isTrue);
    });
    test('deadlineMinutesBeforeKickoff: default 60, clamp 0..240, ints only',
        () {
      int m(Object? v) => scheduleOverridesFromConfigNode(
              {'deadlineMinutesBeforeKickoff': v})
          .minutesBeforeKickoff;
      expect(scheduleOverridesFromConfigNode(const {}).minutesBeforeKickoff, 60);
      expect(m(45), 45);
      expect(m(45.0), 45);
      expect(m(0), 0);
      expect(m(240), 240);
      expect(m(999), 240);
      expect(m(-5), 0);
      expect(m('45'), 60);
      expect(m(45.5), 60);
      expect(m(double.nan), 60);
      expect(m(1e300), 60); // not a representable integer
      expect(m(null), 60);
      expect(m(true), 60);
    });
    test('an absent or malformed Config is all defaults', () {
      for (final node in [null, 'x', 3, [1, 2]]) {
        expect(scheduleOverridesFromConfigNode(node), const ScheduleOverrides());
      }
    });
  });

  group('firstKickoffByDateFromNode (Date/<date>/<game>/Time)', () {
    test('takes the earliest valid Time of the day, in league time', () {
      expect(
          firstKickoffByDateFromNode({
            '10112026': [
              {'Time': '7pm'},
              {'Time': '15:30'},
              {'Time': '14:00'},
              {'Time': '25:00'},
              {'Time': '14:60'},
              {'Time': ''},
              <String, Object>{},
            ],
          }),
          {'10112026': DateTime.utc(2026, 10, 11, 21)}); // 14:00 PDT
    });
    test('PST dates use the winter offset', () {
      expect(
          firstKickoffByDateFromNode({
            '11012026': [
              {'Time': '14:00'}
            ]
          }),
          {'11012026': DateTime.utc(2026, 11, 1, 22)});
    });
    test('accepts a single-digit hour and padding like the schedule display',
        () {
      expect(
          firstKickoffByDateFromNode({
            '10112026': [
              {'Time': ' 9:05 '}
            ]
          }),
          {'10112026': DateTime.utc(2026, 10, 11, 16, 5)});
    });
    test('no Time and no start hour -> no kickoff for that date', () {
      expect(
          firstKickoffByDateFromNode({
            '10112026': [
              {'team1': 'A'}
            ]
          }),
          isEmpty);
      expect(
          firstKickoffByDateFromNode({
            '10112026': [
              {'Time': '7pm'}
            ]
          }, startHour: 0),
          isEmpty);
    });
    test('falls back per game to the legacy derived time when startHour > 0',
        () {
      // game 0: '7pm' invalid -> legacy(5,0)=17:00; game 1: 15:30 stored;
      // game 2: no Time -> legacy(5,2)=19:00. Earliest = 15:30 PDT.
      expect(
          firstKickoffByDateFromNode({
            '10112026': [
              {'Time': '7pm'},
              {'Time': '15:30'},
              <String, Object>{},
            ],
          }, startHour: 5),
          {'10112026': DateTime.utc(2026, 10, 11, 22, 30)});
      // only a derived time: 17:00 PDT
      expect(
          firstKickoffByDateFromNode({
            '10112026': [
              {'team1': 'A'}
            ]
          }, startHour: 5),
          {'10112026': DateTime.utc(2026, 10, 12, 0)});
    });
    test('the legacy index is the list position (null holes still count)', () {
      // index 1 -> legacy(3,1) = 16:00 PDT = 23:00Z
      expect(
          firstKickoffByDateFromNode({
            '10112026': [null, <String, Object>{}],
          }, startHour: 3),
          {'10112026': DateTime.utc(2026, 10, 11, 23)});
    });
    test('an index-keyed Map of games uses the numeric key as the index', () {
      // hole-collapsed node: games 0 and 2 survive; game 2 has no Time ->
      // legacy(2,2) = 16:00 PDT; game 0 stores 17:30.
      expect(
          firstKickoffByDateFromNode({
            '10112026': {
              '0': {'Time': '17:30'},
              '2': {'team1': 'A'},
            },
          }, startHour: 2),
          {'10112026': DateTime.utc(2026, 10, 11, 23)});
      // a non-numeric key has no index: skipped
      expect(
          firstKickoffByDateFromNode({
            '10112026': {'x': <String, Object>{}},
          }, startHour: 2),
          isEmpty);
    });
    test('non-date keys and a malformed node are skipped, not thrown on', () {
      expect(
          firstKickoffByDateFromNode({
            'junk': [
              {'Time': '14:00'}
            ]
          }),
          isEmpty);
      expect(firstKickoffByDateFromNode({'10112026': 'x', '10182026': null}),
          isEmpty);
      expect(firstKickoffByDateFromNode(null), isEmpty);
      expect(firstKickoffByDateFromNode('nope'), isEmpty);
      expect(
          firstKickoffByDateFromNode([
            {'Time': '14:00'}
          ]),
          isEmpty);
    });
  });
}
