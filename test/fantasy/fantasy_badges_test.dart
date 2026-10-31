// Achievement badges (spec 2026-10-30 §3/§5) — the PURE fan-side contract:
// the global catalog (`Fantasy/BadgeCatalog/<badgeId>`, stored over the
// starter set exactly like the server's catalogOf), the awards
// (`Fantasy/<sport>/<season>/Badges/<uid>/<awardId>`), and the shelf's
// grouping (count, weeks, season flag, owner notes) + "when earned" line.
// Map/List coercion and junk tolerance like every other fantasy parser.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';

void main() {
  group('badgeCatalogFromNode', () {
    test('absent node → the starter set (an unseeded database reads like a '
        'seeded one)', () {
      final catalog = badgeCatalogFromNode(null);
      expect(catalog.keys.toSet(), {
        'captainGenius',
        'crystalBall',
        'benchBoss',
        'hiddenGem',
        'topOfTheWeek',
        'everPresent',
        'champion',
        'runnerUp',
        'thirdPlace',
      });
      final captain = catalog['captainGenius']!;
      expect(captain.name, 'Captain Genius');
      expect(captain.icon, 'military_tech');
      expect(captain.kind, FantasyBadgeKind.auto);
      expect(captain.repeatable, isTrue);
      expect(captain.active, isTrue);
      expect(catalog['champion']!.icon, 'workspace_premium');
      expect(catalog['champion']!.repeatable, isFalse);
      expect(catalog['runnerUp']!.icon, 'looks_two');
      expect(catalog['thirdPlace']!.icon, 'looks_3');
    });

    test('stored fields win; a missing field of a starter id falls back to '
        'the starter value', () {
      final catalog = badgeCatalogFromNode({
        'captainGenius': {'Name': '  Captain Fantastic ', 'Active': false},
      });
      final e = catalog['captainGenius']!;
      expect(e.name, 'Captain Fantastic');
      expect(e.active, isFalse);
      expect(e.icon, 'military_tech'); // starter fallback
      expect(e.description, contains('captain'));
      expect(e.order, 10);
    });

    test('an owner-made manual badge with a picture parses whole', () {
      final catalog = badgeCatalogFromNode({
        'mvpOctober': {
          'Name': 'MVP of October',
          'Description': 'Voted by the league.',
          'Icon': 'star',
          'ImageUrl': ' https://img/mvp.png?token=1 ',
          'Kind': 'manual',
          'Repeatable': false,
          'Order': '5',
          'Active': true,
        },
      });
      final e = catalog['mvpOctober']!;
      expect(e.id, 'mvpOctober');
      expect(e.name, 'MVP of October');
      expect(e.description, 'Voted by the league.');
      expect(e.icon, 'star');
      expect(e.imageUrl, 'https://img/mvp.png?token=1');
      expect(e.kind, FantasyBadgeKind.manual);
      expect(e.repeatable, isFalse);
      expect(e.order, 5);
      // The starter set is still there underneath.
      expect(catalog.containsKey('captainGenius'), isTrue);
    });

    test('a non-starter id with missing fields gets the generic defaults; an '
        'empty ImageUrl is no picture; junk children are skipped', () {
      final catalog = badgeCatalogFromNode({
        'bare': {'Name': ''},
        'junk': 'not a map',
        'blankPic': {'Name': 'Blank', 'ImageUrl': '   '},
      });
      final bare = catalog['bare']!;
      expect(bare.name, 'bare'); // the server's own fallback: the id
      expect(bare.icon, 'military_tech');
      expect(bare.kind, FantasyBadgeKind.manual);
      expect(bare.active, isTrue);
      expect(bare.repeatable, isTrue);
      expect(catalog.containsKey('junk'), isFalse);
      expect(catalog['blankPic']!.imageUrl, isNull);
    });
  });

  group('badge awards', () {
    test('one uid: weekly auto, season auto and a manual award with a note; '
        'sorted by award time', () {
      final awards = badgeAwardsFromNode({
        'captainGenius_gw7': {
          'Badge': 'captainGenius',
          'Gw': 7,
          'At': 300,
          'Source': 'auto',
        },
        'champion_season': {'Badge': 'champion', 'At': 900, 'Source': 'auto'},
        '-Nmanual1': {
          'Badge': 'mvpOctober',
          'Gw': '3',
          'At': 100,
          'Source': 'manual',
          'Note': '  Best player of October ',
          'By': 'admin1',
        },
      });
      expect([for (final a in awards) a.id],
          ['-Nmanual1', 'captainGenius_gw7', 'champion_season']);
      final manual = awards.first;
      expect(manual.badgeId, 'mvpOctober');
      expect(manual.gw, 3);
      expect(manual.isManual, isTrue);
      expect(manual.note, 'Best player of October');
      expect(manual.by, 'admin1');
      expect(awards[1].gw, 7);
      expect(awards[1].isManual, isFalse);
      expect(awards[2].gw, isNull);
      expect(awards[2].note, isNull);
    });

    test('junk tolerated: no Badge, non-map, Gw 0 → no week, unknown Source '
        '→ auto; absent node → empty', () {
      final awards = badgeAwardsFromNode({
        'a': {'Gw': 2, 'At': 1},
        'b': 'junk',
        'c': {'Badge': 'benchBoss', 'Gw': 0, 'At': 'x', 'Source': '??'},
      });
      expect(awards, hasLength(1));
      expect(awards.single.badgeId, 'benchBoss');
      expect(awards.single.gw, isNull);
      expect(awards.single.atMs, 0);
      expect(awards.single.isManual, isFalse);
      expect(badgeAwardsFromNode(null), isEmpty);
      expect(badgeAwardsFromNode('nope'), isEmpty);
    });

    test('a list-coerced node still parses (index = id)', () {
      final awards = badgeAwardsFromNode([
        null,
        {'Badge': 'hiddenGem', 'Gw': 1, 'At': 5},
      ]);
      expect(awards.single.id, '1');
      expect(awards.single.badgeId, 'hiddenGem');
    });

    test('the whole season node → uid → awards; uids with nothing usable '
        'are absent', () {
      final byUid = badgesByUidFromNode({
        'u1': {
          'captainGenius_gw1': {'Badge': 'captainGenius', 'Gw': 1, 'At': 1},
          'benchBoss_gw1': {'Badge': 'benchBoss', 'Gw': 1, 'At': 2},
        },
        'u2': {'x': 'junk'},
        'u3': 'junk',
      });
      expect(byUid.keys, ['u1']);
      expect(byUid['u1'], hasLength(2));
      expect(badgesByUidFromNode(null), isEmpty);
    });
  });

  group('groupBadgeAwards', () {
    final catalog = badgeCatalogFromNode({
      'mvpOctober': {'Name': 'MVP of October', 'Kind': 'manual', 'Order': 1},
      'retired': {'Name': 'Retired Badge', 'Active': false, 'Order': 95},
    });

    FantasyBadgeAward award(String id, String badge,
            {int? gw, int at = 0, bool manual = false, String? note}) =>
        FantasyBadgeAward(
          id: id,
          badgeId: badge,
          gw: gw,
          atMs: at,
          source:
              manual ? FantasyBadgeSource.manual : FantasyBadgeSource.auto,
          note: note,
        );

    test('repeats group into one entry with the count, the sorted weeks and '
        'the season flag; order follows the catalog Order', () {
      final groups = groupBadgeAwards([
        award('captainGenius_gw9', 'captainGenius', gw: 9, at: 9),
        award('champion_season', 'champion', at: 20),
        award('captainGenius_gw3', 'captainGenius', gw: 3, at: 3),
        award('captainGenius_gw7', 'captainGenius', gw: 7, at: 7),
        award('-Nm', 'mvpOctober', manual: true, note: 'Clutch', at: 1),
      ], catalog);
      expect([for (final g in groups) g.badgeId],
          ['mvpOctober', 'captainGenius', 'champion']);
      final captain = groups[1];
      expect(captain.count, 3);
      expect(captain.weeks, [3, 7, 9]);
      expect(captain.seasonWide, isFalse);
      expect(captain.hasManual, isFalse);
      expect(captain.name, 'Captain Genius');
      expect(badgeEarnedLine(captain, season: '15'), 'GW3, GW7, GW9');

      final champion = groups[2];
      expect(champion.count, 1);
      expect(champion.weeks, isEmpty);
      expect(champion.seasonWide, isTrue);
      expect(badgeEarnedLine(champion, season: '15'), 'Season 15');

      final mvp = groups.first;
      expect(mvp.hasManual, isTrue);
      expect(mvp.notes, ['Clutch']);
      expect(badgeEarnedLine(mvp, season: '15'), 'Season 15');
    });

    test('a manual award for a week AND a season award: both in the line', () {
      final groups = groupBadgeAwards([
        award('-N1', 'mvpOctober', gw: 4, manual: true, note: 'One'),
        award('-N2', 'mvpOctober', manual: true),
        award('-N3', 'mvpOctober', gw: 4, manual: true, note: 'Two'),
      ], catalog);
      final g = groups.single;
      expect(g.count, 3);
      expect(g.weeks, [4]); // distinct
      expect(g.notes, ['One', 'Two']);
      expect(badgeEarnedLine(g, season: '15'), 'GW4 · Season 15');
    });

    test('an inactive catalog badge that was earned still groups with its '
        'catalog entry; an unknown id falls back to the generic badge (last)',
        () {
      final groups = groupBadgeAwards([
        award('gone_gw1', 'deletedBadge', gw: 1),
        award('retired_gw2', 'retired', gw: 2),
      ], catalog);
      expect([for (final g in groups) g.badgeId], ['retired', 'deletedBadge']);
      expect(groups.first.name, 'Retired Badge');
      expect(groups.first.entry!.active, isFalse);
      expect(groups.last.entry, isNull);
      expect(groups.last.name, kGenericBadgeName);
      expect(groups.last.description, '');
    });

    test('nothing earned → no groups', () {
      expect(groupBadgeAwards(const [], catalog), isEmpty);
    });
  });
}
