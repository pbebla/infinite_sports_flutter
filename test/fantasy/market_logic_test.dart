// P3c — pure market logic: search/filter/sort composition (eligible vs
// ineligible partition), the add/remove availability rules + their reason
// sentences, and the price-delta chip text.

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

  group('composeMarket', () {
    test('default: price desc, ties by name, guests partitioned last', () {
      final m = composeMarket(players: players);
      expect(m.eligible.map((p) => p.name).toList(), [
        'Ava Striker', // 70
        'axel shot', // 70 — tie broken by name (case-sensitive, stable)
        'Dana Wall', // 60
        'Deb Rock', // 55
        'Alan Keeper', // 50
        'Gus Glove', // 45
      ]);
      expect(m.ineligible.map((p) => p.name).toList(), ['Guest Guy']);
    });

    test('position filter + search compose and never drop the partition', () {
      final gk = composeMarket(players: players, position: FantasyPosition.gk);
      expect(gk.eligible.map((p) => p.name).toList(),
          ['Alan Keeper', 'Gus Glove']);
      expect(gk.ineligible, isEmpty);

      // Search is case-insensitive over name AND team.
      final byTeam = composeMarket(players: players, query: 'team b');
      expect(byTeam.eligible.map((p) => p.name).toList(),
          ['axel shot', 'Deb Rock', 'Gus Glove']);
      final byName = composeMarket(players: players, query: 'GUEST');
      expect(byName.eligible, isEmpty);
      expect(byName.ineligible.map((p) => p.name).toList(), ['Guest Guy']);

      // Both at once.
      final both = composeMarket(
          players: players, position: FantasyPosition.att, query: 'ava');
      expect(both.eligible.map((p) => p.name).toList(), ['Ava Striker']);
    });

    test('name sort is case-insensitive A–Z', () {
      final m = composeMarket(players: players, sort: MarketSort.nameAz);
      expect(m.eligible.map((p) => p.name).toList(), [
        'Alan Keeper',
        'Ava Striker',
        'axel shot',
        'Dana Wall',
        'Deb Rock',
        'Gus Glove',
      ]);
    });

    test('points sort reads totals, missing players count 0, ties fall back '
        'to price then name', () {
      final totals = {
        'Deb Rock': const FantasyPlayerTotals(points: 31),
        'Ava Striker': const FantasyPlayerTotals(points: 54),
        'Alan Keeper': const FantasyPlayerTotals(points: 31),
      };
      final m = composeMarket(
          players: players, sort: MarketSort.pointsDesc, totals: totals);
      expect(m.eligible.map((p) => p.name).toList(), [
        'Ava Striker', // 54
        'Deb Rock', // 31, $5.5M beats
        'Alan Keeper', // 31, $5.0M
        'axel shot', // 0, $7.0M
        'Dana Wall', // 0, $6.0M
        'Gus Glove', // 0, $4.5M
      ]);
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

    test('lock silences everything — even Remove', () {
      final picks = empty()..[0] = pickFor(players[0], bench: false);
      for (final p in players) {
        expect(
            marketAddState(
                player: p,
                slots: slots,
                slotPicks: picks,
                budgetTenths: cfg.budgetTenths,
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
              budgetTenths: cfg.budgetTenths,
              editable: true),
          MarketAddAvailability.inSquad);
    });

    test('guest → ineligible, never addable', () {
      expect(
          marketAddState(
              player: players.last,
              slots: slots,
              slotPicks: empty(),
              budgetTenths: cfg.budgetTenths,
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
              budgetTenths: cfg.budgetTenths,
              editable: true),
          MarketAddAvailability.positionFull);
    });

    test('price above remaining budget → unaffordable', () {
      // One DEF at $46.0M leaves $4.0M — the $5.5M DEF can't come.
      final rich = player('Money Bags', FantasyPosition.def, 460);
      final picks = empty()..[1] = pickFor(rich, bench: false);
      expect(
          marketAddState(
              player: players[3], // Deb Rock $5.5M
              slots: slots,
              slotPicks: picks,
              budgetTenths: cfg.budgetTenths,
              editable: true),
          MarketAddAvailability.unaffordable);
      // An exactly-affordable price still adds.
      expect(
          marketAddState(
              player: player('Fits Just', FantasyPosition.def, 40),
              slots: slots,
              slotPicks: picks,
              budgetTenths: cfg.budgetTenths,
              editable: true),
          MarketAddAvailability.addable);
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
