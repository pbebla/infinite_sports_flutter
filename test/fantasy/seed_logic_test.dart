// Pure-logic tests for tool/seed_fantasy_logic.dart (P3a Task 0): position
// mapping from real registration spellings, season aggregation through the
// engine, per-position opening prices, and the seeded node shapes.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

import '../../tool/seed_fantasy_logic.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();

  group('mapRegistrationPosition', () {
    test('single registrations map per spec §3', () {
      expect(mapRegistrationPosition('Goal Keeper'), FantasyPosition.gk);
      expect(mapRegistrationPosition('Defender'), FantasyPosition.def);
      expect(mapRegistrationPosition('Midfielder'), FantasyPosition.att);
      expect(mapRegistrationPosition('Striker'), FantasyPosition.att);
    });
    test('short spellings tolerated', () {
      expect(mapRegistrationPosition('GK'), FantasyPosition.gk);
      expect(mapRegistrationPosition('D'), FantasyPosition.def);
      expect(mapRegistrationPosition('M'), FantasyPosition.att);
      expect(mapRegistrationPosition('S'), FantasyPosition.att);
    });
    test('multi-select uses the FIRST listed position — ";" and ":" both '
        'appear in live data', () {
      expect(mapRegistrationPosition('Defender;Midfielder;Striker'),
          FantasyPosition.def);
      expect(mapRegistrationPosition('Goal Keeper:Defender:Midfielder:Striker'),
          FantasyPosition.gk);
      expect(mapRegistrationPosition('Striker;Midfielder;Goal Keeper;Defender'),
          FantasyPosition.att);
      expect(mapRegistrationPosition('Defender:Midfielder'),
          FantasyPosition.def);
    });
    test('missing/empty/unknown default to ATT (owner-overridable)', () {
      expect(mapRegistrationPosition(null), FantasyPosition.att);
      expect(mapRegistrationPosition(''), FantasyPosition.att);
      expect(mapRegistrationPosition('  ;  '), FantasyPosition.att);
      expect(mapRegistrationPosition('Sweeper'), FantasyPosition.att);
    });
  });

  group('parseLineups', () {
    test('reads name/team/uid, normalizing missing/zero uids to null', () {
      final entries = parseLineups({
        'Hakkari': {
          'Johnny Lugo': {'UID': 'abc', 'number': 'GK', 'Saves': 37},
          'Unlinked Player': {'UID': '0', 'number': '4'},
          'No Uid': {'number': '9'},
          'Broken': 'not-a-map',
        },
        'BadTeam': 'not-a-map',
      });
      expect(entries, hasLength(3));
      final byName = {for (final e in entries) e.name: e};
      expect(byName['Johnny Lugo']!.uid, 'abc');
      expect(byName['Johnny Lugo']!.teamName, 'Hakkari');
      expect(byName['Unlinked Player']!.uid, isNull);
      expect(byName['No Uid']!.uid, isNull);
    });
    test('non-map node → empty', () {
      expect(parseLineups(null), isEmpty);
      expect(parseLineups([1, 2]), isEmpty);
    });
  });

  test('isGuestName', () {
    expect(isGuestName('Guest'), isTrue);
    expect(isGuestName(' guest '), isTrue);
    expect(isGuestName('Guest Player'), isFalse);
  });

  group('seasonPointsByPlayer', () {
    // One date, list-coerced games with null padding (live-shape parity).
    final dateNode = {
      '06292025': [
        null,
        {
          'team1': 'A',
          'team2': 'B',
          'team1score': 2,
          'team2score': 0,
          'team1activity': {
            "5'": [
              {'Goal': 'P1'}
            ],
            "7'": [
              {'Goal': 'P1'},
              {'Assist': 'P2'}
            ],
          },
          'team2activity': {
            "9'": [
              {'Goal': 'Guest'}
            ],
          },
        },
      ],
    };
    final positions = {
      'P1': FantasyPosition.att,
      'P2': FantasyPosition.def,
      'P3': FantasyPosition.gk,
    };
    final rosters = {
      'A': {'P1', 'P2'},
      'B': {'P3'},
    };

    test('hand math: appearance + goals + clean sheets + conceded', () {
      final agg = seasonPointsByPlayer(
        dateNode: dateNode,
        positionByName: positions,
        rosterByTeam: rosters,
        cfg: cfg,
      );
      // P1 (ATT): plays 1 + 2 goals ×4 + clean sheet 2 = 11
      expect(agg.pointsByName['P1'], 11);
      // P2 (DEF): plays 1 + assist 4 + clean sheet 5 = 10
      expect(agg.pointsByName['P2'], 10);
      // P3 (GK): plays 1 + conceded 2 → (2 ~/ 2) × −1 = 0
      expect(agg.pointsByName['P3'], 0);
    });
    test('activity-only names (Guest) are reported, never scored', () {
      final agg = seasonPointsByPlayer(
        dateNode: dateNode,
        positionByName: positions,
        rosterByTeam: rosters,
        cfg: cfg,
      );
      expect(agg.activityOnlyNames, {'Guest'});
      expect(agg.pointsByName.containsKey('Guest'), isFalse);
    });
    test('every lineup player has an aggregate even with no games', () {
      final agg = seasonPointsByPlayer(
        dateNode: null,
        positionByName: positions,
        rosterByTeam: rosters,
        cfg: cfg,
      );
      expect(agg.pointsByName, {'P1': 0.0, 'P2': 0.0, 'P3': 0.0});
    });
  });

  group('buildOpeningPrices', () {
    test('percentiles are computed WITHIN each position group', () {
      final prices = buildOpeningPrices(
        positionByName: {
          'gkBest': FantasyPosition.gk,
          'gkWorst': FantasyPosition.gk,
          'attBest': FantasyPosition.att,
          'attWorst': FantasyPosition.att,
        },
        pointsByName: {
          // GK group spans 0..10; ATT group spans 0..100 — both best players
          // must hit the ceiling because grouping is per position.
          'gkBest': 10, 'gkWorst': 0,
          'attBest': 100, 'attWorst': 0,
        },
        cfg: cfg,
      );
      expect(prices['gkBest'], cfg.priceMaxTenths);
      expect(prices['attBest'], cfg.priceMaxTenths);
      expect(prices['gkWorst'], cfg.priceMinTenths);
      expect(prices['attWorst'], cfg.priceMinTenths);
    });
    test('players without an aggregate are rookies at the rookie price', () {
      final prices = buildOpeningPrices(
        positionByName: {
          'vet': FantasyPosition.att,
          'rookie': FantasyPosition.att,
        },
        pointsByName: {'vet': 50},
        cfg: cfg,
      );
      expect(prices['rookie'], cfg.rookiePriceTenths);
      // Lone scored player in the group → midpoint, snapped (engine rule).
      expect(prices['vet'], 95);
    });
  });

  group('seeded node shapes', () {
    test('Players node carries position/priceTenths/eligible/teamName', () {
      final node = buildPlayersNode(
        lineups: const [
          LineupEntry(name: 'P1', teamName: 'A', uid: 'u1'),
          LineupEntry(name: 'Guest', teamName: 'B'),
        ],
        positionByName: {'P1': FantasyPosition.def},
        priceByName: {'P1': 85},
        cfg: cfg,
      );
      expect(node['P1'], {
        'position': 'DEF',
        'priceTenths': 85,
        'eligible': true,
        'teamName': 'A',
      });
      expect(node['Guest']!['eligible'], false);
      expect(node['Guest']!['priceTenths'], cfg.rookiePriceTenths);
      expect(node['Guest']!['position'], 'ATT');
      // No photoUrlByName passed → no photoUrl keys at all.
      expect(node['P1']!.containsKey('photoUrl'), isFalse);
    });
    test('photoUrl rides along when the UID link resolved one (P3b Task 3)',
        () {
      final node = buildPlayersNode(
        lineups: const [
          LineupEntry(name: 'P1', teamName: 'A', uid: 'u1'),
          LineupEntry(name: 'Unlinked', teamName: 'A'),
        ],
        positionByName: {
          'P1': FantasyPosition.def,
          'Unlinked': FantasyPosition.att,
        },
        priceByName: {'P1': 85, 'Unlinked': 60},
        cfg: cfg,
        photoUrlByName: {'P1': 'https://example.com/p1.jpg', 'Unlinked': ' '},
      );
      expect(node['P1']!['photoUrl'], 'https://example.com/p1.jpg');
      // Blank/missing URLs are omitted, never written as empty strings.
      expect(node['Unlinked']!.containsKey('photoUrl'), isFalse);
    });
    test('Config node = futsalDefault + lockOverride', () {
      final node = buildConfigNode(lockOverride: 'open');
      expect(node['lockOverride'], 'open');
      expect(node['budgetTenths'], cfg.budgetTenths);
      // Round-trips through the engine parser untouched.
      final parsed = FantasyConfig.fromMap(node);
      expect(parsed.toMap(), FantasyConfig.futsalDefault().toMap());
    });
  });

  group('seedRefusal', () {
    test('absent/absent → null (fresh season, nothing to overwrite)', () {
      expect(
        seedRefusal(existingPlayers: null, existingConfig: null, force: false),
        isNull,
      );
    });
    test('Players present → refusal naming Players and the override', () {
      final msg = seedRefusal(
          existingPlayers: {'P1': {}}, existingConfig: null, force: false);
      expect(msg, isNotNull);
      expect(msg, contains('Players'));
      expect(msg, isNot(contains('Config')));
      expect(msg, contains('--force-reseed'));
      expect(msg, contains('Manager'));
    });
    test('Config present alone → refusal naming Config', () {
      final msg = seedRefusal(
          existingPlayers: null,
          existingConfig: {'budgetTenths': 1000},
          force: false);
      expect(msg, isNotNull);
      expect(msg, contains('Config'));
      expect(msg, isNot(contains('Players')));
    });
    test('both present → refusal naming both', () {
      final msg = seedRefusal(
          existingPlayers: {'P1': {}},
          existingConfig: {'budgetTenths': 1000},
          force: false);
      expect(msg, contains('Players and Config'));
    });
    test('present + force → null (throwaway test season override)', () {
      expect(
        seedRefusal(
            existingPlayers: {'P1': {}},
            existingConfig: {'budgetTenths': 1000},
            force: true),
        isNull,
      );
    });
  });
}
