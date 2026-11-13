// P3c / round 3 — pure market logic: search/filter/sort composition (four
// sorts × both directions, ties by name, the watchlist filter, eligible vs
// ineligible partition), the sort-pill state rules, Price Risers / Fallers
// by position, the add/remove availability rules + their reason sentences,
// and the price-delta chip text.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

FantasyPlayer player(String name, FantasyPosition pos, int price,
        {bool eligible = true, String team = 'Team A'}) =>
    FantasyPlayer(
        name: name,
        position: pos,
        priceTenths: price,
        eligible: eligible,
        teamName: team);

void main() {
  final players = <FantasyPlayer>[
    player('Alan Keeper', FantasyPosition.gk, 50),
    player('Gus Glove', FantasyPosition.gk, 45, team: 'Team B'),
    player('Dana Wall', FantasyPosition.def, 60),
    player('Deb Rock', FantasyPosition.def, 55, team: 'Team B'),
    player('Ava Striker', FantasyPosition.att, 70),
    player('axel shot', FantasyPosition.att, 70, team: 'Team B'),
    player('Guest Guy', FantasyPosition.att, 65, eligible: false),
  ];

  List<String> names(List<FantasyPlayer> ps) => ps.map((p) => p.name).toList();

  group('composeMarket', () {
    test('price desc, ties by name, guests partitioned last', () {
      final m = composeMarket(
          players: players, sort: MarketSort.price, descending: true);
      expect(names(m.eligible), [
        'Ava Striker', // 70
        'axel shot', // 70 — tie broken by name A–Z (case-insensitive)
        'Dana Wall', // 60
        'Deb Rock', // 55
        'Alan Keeper', // 50
        'Gus Glove', // 45
      ]);
      expect(names(m.ineligible), ['Guest Guy']);
    });

    test('price asc: cheapest first, ties STILL by name A–Z', () {
      final m = composeMarket(
          players: players, sort: MarketSort.price, descending: false);
      expect(names(m.eligible), [
        'Gus Glove', // 45
        'Alan Keeper', // 50
        'Deb Rock', // 55
        'Dana Wall', // 60
        'Ava Striker', // 70
        'axel shot', // 70
      ]);
    });

    test('position filter + search compose and never drop the partition', () {
      final gk = composeMarket(
          players: players, position: FantasyPosition.gk, descending: true);
      expect(names(gk.eligible), ['Alan Keeper', 'Gus Glove']);
      expect(gk.ineligible, isEmpty);

      // Search is case-insensitive over name AND team.
      final byTeam =
          composeMarket(players: players, query: 'team b', descending: true);
      expect(names(byTeam.eligible), ['axel shot', 'Deb Rock', 'Gus Glove']);
      final byName =
          composeMarket(players: players, query: 'GUEST', descending: true);
      expect(byName.eligible, isEmpty);
      expect(names(byName.ineligible), ['Guest Guy']);

      // Both at once.
      final both = composeMarket(
          players: players,
          position: FantasyPosition.att,
          query: 'ava',
          descending: true);
      expect(names(both.eligible), ['Ava Striker']);
    });

    test('points sort reads totals, missing players count 0, ties by name '
        '(both directions)', () {
      final totals = {
        'Deb Rock': const FantasyPlayerTotals(points: 31),
        'Ava Striker': const FantasyPlayerTotals(points: 54),
        'Alan Keeper': const FantasyPlayerTotals(points: 31),
      };
      final desc = composeMarket(
          players: players,
          sort: MarketSort.points,
          descending: true,
          totals: totals);
      expect(names(desc.eligible), [
        'Ava Striker', // 54
        'Alan Keeper', // 31 — tie by name
        'Deb Rock', // 31
        'axel shot', // 0 (absent) — tie by name
        'Dana Wall', // 0
        'Gus Glove', // 0
      ]);
      final asc = composeMarket(
          players: players,
          sort: MarketSort.points,
          descending: false,
          totals: totals);
      expect(names(asc.eligible), [
        'axel shot', // 0
        'Dana Wall', // 0
        'Gus Glove', // 0
        'Alan Keeper', // 31
        'Deb Rock', // 31
        'Ava Striker', // 54
      ]);
    });

    test('form sort: tenths, ties by name, no form value sorts LAST in both '
        'directions (never treated as 0)', () {
      final totals = {
        'Ava Striker': const FantasyPlayerTotals(points: 54, formTenths: 40),
        'Dana Wall': const FantasyPlayerTotals(points: 10, formTenths: 67),
        'Deb Rock': const FantasyPlayerTotals(points: 10, formTenths: 40),
        'Gus Glove': const FantasyPlayerTotals(points: 9, formTenths: 0),
        // Alan Keeper: old-shape node (form null); axel shot: absent.
        'Alan Keeper': const FantasyPlayerTotals(points: 70),
      };
      final desc = composeMarket(
          players: players,
          sort: MarketSort.form,
          descending: true,
          totals: totals);
      expect(names(desc.eligible), [
        'Dana Wall', // 6.7
        'Ava Striker', // 4.0 — tie by name
        'Deb Rock', // 4.0
        'Gus Glove', // 0.0 (a real zero)
        'Alan Keeper', // no form — last, by name
        'axel shot', // absent — last
      ]);
      final asc = composeMarket(
          players: players,
          sort: MarketSort.form,
          descending: false,
          totals: totals);
      expect(names(asc.eligible), [
        'Gus Glove', // 0.0
        'Ava Striker', // 4.0
        'Deb Rock', // 4.0
        'Dana Wall', // 6.7
        'Alan Keeper', // still last
        'axel shot',
      ]);
    });

    test('ownership sort: percent, ties by name, no value sorts last', () {
      final totals = {
        'Ava Striker': const FantasyPlayerTotals(points: 1, ownershipPct: 62),
        'Dana Wall': const FantasyPlayerTotals(points: 1, ownershipPct: 12.5),
        'Deb Rock': const FantasyPlayerTotals(points: 1, ownershipPct: 62),
        'Gus Glove': const FantasyPlayerTotals(points: 1, ownershipPct: 0),
        'Alan Keeper': const FantasyPlayerTotals(points: 1),
      };
      final desc = composeMarket(
          players: players,
          sort: MarketSort.ownership,
          descending: true,
          totals: totals);
      expect(names(desc.eligible), [
        'Ava Striker', // 62 — tie by name
        'Deb Rock', // 62
        'Dana Wall', // 12.5
        'Gus Glove', // 0
        'Alan Keeper', // none
        'axel shot', // none
      ]);
      final asc = composeMarket(
          players: players,
          sort: MarketSort.ownership,
          descending: false,
          totals: totals);
      expect(names(asc.eligible), [
        'Gus Glove',
        'Dana Wall',
        'Ava Striker',
        'Deb Rock',
        'Alan Keeper',
        'axel shot',
      ]);
    });

    test('watchlist filter: only starred players, guests keep their '
        'partition, composes with position + search', () {
      const starred = {'Deb Rock', 'Ava Striker', 'Guest Guy', 'Gone Player'};
      final m = composeMarket(
          players: players,
          descending: true,
          watchlist: starred,
          watchlistOnly: true);
      expect(names(m.eligible), ['Ava Striker', 'Deb Rock']);
      expect(names(m.ineligible), ['Guest Guy']);

      final defs = composeMarket(
          players: players,
          position: FantasyPosition.def,
          descending: true,
          watchlist: starred,
          watchlistOnly: true);
      expect(names(defs.eligible), ['Deb Rock']);

      final searched = composeMarket(
          players: players,
          query: 'ava',
          descending: true,
          watchlist: starred,
          watchlistOnly: true);
      expect(names(searched.eligible), ['Ava Striker']);

      // Off: the watchlist is ignored entirely.
      final off = composeMarket(
          players: players, descending: true, watchlist: starred);
      expect(off.eligible, hasLength(6));

      // On with an empty watchlist: nothing.
      final empty = composeMarket(
          players: players, descending: true, watchlistOnly: true);
      expect(empty.eligible, isEmpty);
      expect(empty.ineligible, isEmpty);
    });
  });

  group('market sort state', () {
    test('effective sort: Total Pts / Form / Ownership need totals — '
        'without them the market reads Price, highest first', () {
      for (final s in [
        MarketSort.points,
        MarketSort.form,
        MarketSort.ownership
      ]) {
        expect(marketSortNeedsTotals(s), isTrue);
        expect(
            effectiveMarketSort(s, descending: false, hasTotals: false),
            (sort: MarketSort.price, descending: true));
        expect(effectiveMarketSort(s, descending: false, hasTotals: true),
            (sort: s, descending: false));
      }
      expect(marketSortNeedsTotals(MarketSort.price), isFalse);
      expect(
          effectiveMarketSort(MarketSort.price,
              descending: false, hasTotals: false),
          (sort: MarketSort.price, descending: false));
    });

    test('tapping the active sort flips direction; another sort starts '
        'highest first', () {
      expect(
          tapMarketSort(
              current: MarketSort.points,
              descending: true,
              tapped: MarketSort.points),
          (sort: MarketSort.points, descending: false));
      expect(
          tapMarketSort(
              current: MarketSort.points,
              descending: false,
              tapped: MarketSort.points),
          (sort: MarketSort.points, descending: true));
      expect(
          tapMarketSort(
              current: MarketSort.points,
              descending: false,
              tapped: MarketSort.form),
          (sort: MarketSort.form, descending: true));
    });

    test('the four sorts, in the pill order', () {
      expect(MarketSort.values, [
        MarketSort.points,
        MarketSort.form,
        MarketSort.price,
        MarketSort.ownership,
      ]);
    });
  });

  group('price movers', () {
    final market = <FantasyPlayer>[
      player('Gil Keeper', FantasyPosition.gk, 50),
      player('Gary Gloves', FantasyPosition.gk, 45, team: 'Team B'),
      player('Gus Goalie', FantasyPosition.gk, 40, team: 'Team C'),
      player('Dan Back', FantasyPosition.def, 60),
      player('Dee Block', FantasyPosition.def, 55, team: 'Team B'),
      player('Dov Wall', FantasyPosition.def, 52, team: 'Team C'),
      player('Abe Shot', FantasyPosition.att, 70),
      player('Ari Goal', FantasyPosition.att, 65, team: 'Team B'),
      player('Amos Net', FantasyPosition.att, 64, team: 'Team C'),
      player('Axel Ace', FantasyPosition.att, 63, team: 'Team D'),
    ];
    final totals = {
      'Gil Keeper': const FantasyPlayerTotals(points: 20),
      'Gary Gloves': const FantasyPlayerTotals(points: 40),
      'Dan Back': const FantasyPlayerTotals(points: 12),
      'Dee Block': const FantasyPlayerTotals(points: 12),
      'Ari Goal': const FantasyPlayerTotals(points: 30),
      'Amos Net': const FantasyPlayerTotals(points: 10),
    };
    const changes = {
      'Gil Keeper': 3, // GK riser
      'Gary Gloves': 3, // GK riser — same move, more points → first
      'Gus Goalie': 1, // GK riser #3 → dropped from the top 2
      'Dan Back': -2, // DEF faller — tie with Dee on move AND points
      'Dee Block': -2, // → name breaks it (Dan < Dee)
      'Dov Wall': -5, // DEF faller, biggest drop → first
      'Abe Shot': 5, // ATT riser
      'Ari Goal': -1, // ATT faller
      'Amos Net': -1, // ATT faller (fewer points than Ari → second)
      'Axel Ace': 0, // no move — never listed
      'Ghost Player': 9, // not in the market — skipped
    };

    List<String> moveNames(List<PriceMove> ms) =>
        ms.map((m) => m.player.name).toList();

    test('All: grouped GK/DEF/ATT, top 2 risers and fallers each by size of '
        'move, ties by season points then name', () {
      final m = computePriceMovers(changes, market, totals);
      expect(m.risers.keys.toList(), ['GK', 'DEF', 'ATT']);
      expect(m.fallers.keys.toList(), ['GK', 'DEF', 'ATT']);
      expect(moveNames(m.risers['GK']!), ['Gary Gloves', 'Gil Keeper']);
      expect(m.risers['DEF'], isEmpty);
      expect(moveNames(m.risers['ATT']!), ['Abe Shot']);
      expect(m.fallers['GK'], isEmpty);
      expect(moveNames(m.fallers['DEF']!), ['Dov Wall', 'Dan Back']);
      expect(moveNames(m.fallers['ATT']!), ['Ari Goal', 'Amos Net']);
      expect(m.risers['GK']!.first.deltaTenths, 3);
      expect(m.fallers['DEF']!.first.deltaTenths, -5);
      expect(m.isEmpty, isFalse);
    });

    test('position filter → only that key, that position\'s top 2 each', () {
      final def = computePriceMovers(changes, market, totals, position: 'DEF');
      expect(def.risers.keys.toList(), ['DEF']);
      expect(def.fallers.keys.toList(), ['DEF']);
      expect(def.risers['DEF'], isEmpty);
      expect(moveNames(def.fallers['DEF']!), ['Dov Wall', 'Dan Back']);

      final gk = computePriceMovers(changes, market, totals, position: 'GK');
      expect(gk.risers.keys.toList(), ['GK']);
      expect(moveNames(gk.risers['GK']!), ['Gary Gloves', 'Gil Keeper']);
    });

    test('no totals: ties fall straight to the name', () {
      final m = computePriceMovers(changes, market, null);
      expect(moveNames(m.risers['GK']!), ['Gary Gloves', 'Gil Keeper']);
      expect(moveNames(m.fallers['ATT']!), ['Amos Net', 'Ari Goal']);
    });

    test('nothing moved → empty groups', () {
      final m = computePriceMovers(const {}, market, totals);
      expect(m.isEmpty, isTrue);
      expect(m.risers.keys.toList(), ['GK', 'DEF', 'ATT']);
    });

    test('every move (View all): risers then fallers, uncapped, same order',
        () {
      final all = sortedPriceMoves(changes, market, totals);
      expect(moveNames(all.risers),
          ['Abe Shot', 'Gary Gloves', 'Gil Keeper', 'Gus Goalie']);
      expect(moveNames(all.fallers),
          ['Dov Wall', 'Dan Back', 'Dee Block', 'Ari Goal', 'Amos Net']);
      expect(all.risers.first.seasonPoints, 0);
      expect(all.risers[1].seasonPoints, 40);
    });

    test('latest reprice: the highest gameweek; null before any', () {
      expect(latestPriceMoves(const {}), isNull);
      final latest = latestPriceMoves(const {
        1: {'A': 2},
        3: {'B': -1},
        2: {'C': 4},
      });
      expect(latest!.gameweek, 3);
      expect(latest.changes, {'B': -1});
      // A flag-only latest week (voided — nothing moved) is still the
      // latest: no moves to show.
      final voided = latestPriceMoves(const {
        2: {'C': 4},
        3: {},
      });
      expect(voided!.gameweek, 3);
      expect(voided.changes, isEmpty);
    });

    test('short names: first initial + the rest; one word stays', () {
      expect(shortPlayerName('Demsin Bet varda'), 'D. Bet varda');
      expect(shortPlayerName('Eli Derazizyan'), 'E. Derazizyan');
      expect(shortPlayerName('  Pele  '), 'Pele');
      expect(shortPlayerName('Ana  Maria   Lopez'), 'A. Maria Lopez');
      expect(shortPlayerName(''), '');
    });
  });

  group('marketAddState', () {
    final cfg = FantasyConfig.futsalDefault();
    final slots = buildSlots(cfg);
    List<SquadPick?> empty() => List<SquadPick?>.filled(slots.length, null);

    SquadPick pickFor(FantasyPlayer p, {required bool bench}) => SquadPick(
        playerId: p.name,
        position: p.position,
        priceTenths: p.priceTenths,
        bench: bench);

    // The market's own price (a draft with no sale context charges it).
    int marketPrice(FantasyPlayer p) => p.priceTenths;

    test('lock silences everything — even Remove', () {
      final picks = empty()..[0] = pickFor(players[0], bench: false);
      for (final p in players) {
        expect(
            marketAddState(
                player: p,
                slots: slots,
                slotPicks: picks,
                remainingTenths: cfg.budgetTenths,
                priceOf: marketPrice,
                editable: false),
            MarketAddAvailability.locked);
      }
    });

    test('drafted player → inSquad (Remove)', () {
      final picks = empty()..[0] = pickFor(players[0], bench: false);
      expect(
          marketAddState(
              player: players[0],
              slots: slots,
              slotPicks: picks,
              remainingTenths: cfg.budgetTenths,
              priceOf: marketPrice,
              editable: true),
          MarketAddAvailability.inSquad);
    });

    test('guest → ineligible, never addable', () {
      expect(
          marketAddState(
              player: players.last,
              slots: slots,
              slotPicks: empty(),
              remainingTenths: cfg.budgetTenths,
              priceOf: marketPrice,
              editable: true),
          MarketAddAvailability.ineligible);
    });

    test('no empty slot for the position → positionFull (futsal: 1 GK)', () {
      final picks = empty()..[0] = pickFor(players[0], bench: false);
      expect(
          marketAddState(
              player: players[1], // the other GK
              slots: slots,
              slotPicks: picks,
              remainingTenths: cfg.budgetTenths,
              priceOf: marketPrice,
              editable: true),
          MarketAddAvailability.positionFull);
    });

    test('price above the room left → unaffordable', () {
      // One DEF at $46.0M leaves $4.0M — the $5.5M DEF can't come.
      final rich = player('Money Bags', FantasyPosition.def, 460);
      final picks = empty()..[1] = pickFor(rich, bench: false);
      expect(
          marketAddState(
              player: players[3], // Deb Rock $5.5M
              slots: slots,
              slotPicks: picks,
              remainingTenths: 40,
              priceOf: marketPrice,
              editable: true),
          MarketAddAvailability.unaffordable);
      // An exactly-affordable price still adds.
      expect(
          marketAddState(
              player: player('Fits Just', FantasyPosition.def, 40),
              slots: slots,
              slotPicks: picks,
              remainingTenths: 40,
              priceOf: marketPrice,
              editable: true),
          MarketAddAvailability.addable);
    });

    // FPL selling (spec §4): the money test is the DRAFT's price for him,
    // never the market's — a sold baseline player comes back at what the
    // draft says, with the room the draft says.
    test('affordability uses priceOf, not the market price', () {
      final baselineGuy = player('Back Again', FantasyPosition.att, 90);
      expect(
          marketAddState(
              player: baselineGuy,
              slots: slots,
              slotPicks: empty(),
              remainingTenths: 80,
              priceOf: (p) => p.name == 'Back Again' ? 80 : p.priceTenths,
              editable: true),
          MarketAddAvailability.addable);
      // The market price alone would have refused him.
      expect(
          marketAddState(
              player: baselineGuy,
              slots: slots,
              slotPicks: empty(),
              remainingTenths: 80,
              priceOf: marketPrice,
              editable: true),
          MarketAddAvailability.unaffordable);
    });

    test('reasons: sentences for every disabled state, null when live', () {
      expect(marketAddReason(MarketAddAvailability.addable, FantasyPosition.gk),
          isNull);
      expect(marketAddReason(MarketAddAvailability.inSquad, FantasyPosition.gk),
          isNull);
      expect(
          marketAddReason(
              MarketAddAvailability.positionFull, FantasyPosition.gk),
          'GK slots are full — remove someone first.');
      expect(
          marketAddReason(
              MarketAddAvailability.unaffordable, FantasyPosition.att),
          contains('Over budget'));
      expect(
          marketAddReason(MarketAddAvailability.locked, FantasyPosition.def),
          contains('locked'));
      expect(
          marketAddReason(
              MarketAddAvailability.ineligible, FantasyPosition.att),
          contains('not eligible'));
    });
  });

  group('formatPriceDelta', () {
    test('signed tenths chips', () {
      expect(formatPriceDelta(5), '+\$0.5M');
      expect(formatPriceDelta(-5), '−\$0.5M');
      expect(formatPriceDelta(10), '+\$1.0M');
    });
  });
}
