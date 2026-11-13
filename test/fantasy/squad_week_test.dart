import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad_week.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  SquadPick p(String id, FantasyPosition pos, {bool bench = false}) =>
      SquadPick(playerId: id, position: pos, priceTenths: 50, bench: bench);
  FantasySquad squad({String captain = 'a1', String vice = 'd1', String? chip}) =>
      FantasySquad(picks: [
        p('g1', FantasyPosition.gk),
        p('d1', FantasyPosition.def),
        p('d2', FantasyPosition.def),
        p('a1', FantasyPosition.att),
        p('a2', FantasyPosition.att),
        p('d3', FantasyPosition.def, bench: true),
        p('a3', FantasyPosition.att, bench: true),
      ], captainId: captain, viceId: vice, chip: chip);

  // player week points (whole points) + played flags
  Map<String, PlayerWeek> wk(Map<String, (int, bool)> m) =>
      m.map((k, v) => MapEntry(k, PlayerWeek(points: v.$1, played: v.$2)));

  final allPlay = wk({
    'g1': (6, true), 'd1': (5, true), 'd2': (4, true),
    'a1': (10, true), 'a2': (3, true), 'd3': (7, true), 'a3': (2, true),
  });

  test('normal week: starters full, captain x2, bench half', () {
    final r = scoreSquadWeek(squad(), allPlay, cfg);
    // starters: 6+5+4+10+3 = 28, captain a1 doubles → +10, bench half: (7+2)/2 = 4.5
    expect(r.totalTenths, 280 + 100 + 45);
    expect(r.slot('a1').multiplier, 2);
    expect(r.slot('d3').countedTenths, 35);
  });
  test('captain absent → vice doubles', () {
    final m = wk({...{
      'g1': (6, true), 'd1': (5, true), 'd2': (4, true),
      'a1': (0, false), 'a2': (3, true), 'd3': (7, true), 'a3': (2, true),
    }});
    final r = scoreSquadWeek(squad(), m, cfg);
    expect(r.slot('d1').multiplier, 2);
    // a1 absent → bench a3 auto-subbed in at FULL; d3 stays half
    expect(r.slot('a3').countedTenths, 20);
    expect(r.slot('a3').autoSubbedIn, isTrue);
    expect(r.slot('d3').countedTenths, 35);
    expect(r.totalTenths, (6 + 5 + 5 + 4 + 3 + 2) * 10 + 35);
  });
  test('both captain and vice absent → nobody doubles', () {
    final m = wk({
      'g1': (6, true), 'd1': (0, false), 'd2': (4, true),
      'a1': (0, false), 'a2': (3, true), 'd3': (7, true), 'a3': (2, true),
    });
    final r = scoreSquadWeek(squad(), m, cfg);
    expect(r.slots.where((s) => s.multiplier > 1), isEmpty);
  });
  test('absent DEF starter → bench DEF in full, bench ATT stays half', () {
    final m = wk({
      'g1': (6, true), 'd1': (5, true), 'd2': (0, false),
      'a1': (10, true), 'a2': (3, true), 'd3': (7, true), 'a3': (2, true),
    });
    final r = scoreSquadWeek(squad(), m, cfg);
    expect(r.slot('d3').countedTenths, 70);
    expect(r.slot('a3').countedTenths, 10);
  });
  test('two absent ATT starters, one bench ATT covers one; other scores 0', () {
    final m = wk({
      'g1': (6, true), 'd1': (5, true), 'd2': (4, true),
      'a1': (0, false), 'a2': (0, false), 'd3': (7, true), 'a3': (2, true),
    });
    final r = scoreSquadWeek(squad(captain: 'g1', vice: 'd1'), m, cfg);
    expect(r.slot('a3').autoSubbedIn, isTrue);
    expect(r.slot('a3').countedTenths, 20);
    // absent starters contribute 0; d3 half
    expect(r.totalTenths, (6 * 2 + 5 + 4 + 2) * 10 + 35);
  });
  test('absent GK has no cover (no bench GK by design)', () {
    final m = wk({
      'g1': (0, false), 'd1': (5, true), 'd2': (4, true),
      'a1': (10, true), 'a2': (3, true), 'd3': (7, true), 'a3': (2, true),
    });
    final r = scoreSquadWeek(squad(), m, cfg);
    expect(r.slot('g1').countedTenths, 0);
    expect(r.slots.where((s) => s.autoSubbedIn).length, 0);
  });
  test('bench boost: bench full, no auto-sub semantics change', () {
    final r = scoreSquadWeek(squad(chip: 'benchBoost'), allPlay, cfg);
    // starters 28 + captain extra 10 + bench full 7+2 = 47 pts = 470 tenths
    expect(r.totalTenths, (28 + 10 + 7 + 2) * 10);
  });
  test('triple captain: x3', () {
    final r = scoreSquadWeek(squad(chip: 'tripleCaptain'), allPlay, cfg);
    expect(r.slot('a1').multiplier, 3);
    expect(r.totalTenths, 280 + 200 + 45);
  });
  test('absent bench player scores zero even boosted', () {
    final m = wk({
      'g1': (6, true), 'd1': (5, true), 'd2': (4, true),
      'a1': (10, true), 'a2': (3, true), 'd3': (0, false), 'a3': (2, true),
    });
    final r = scoreSquadWeek(squad(chip: 'benchBoost'), m, cfg);
    expect(r.slot('d3').countedTenths, 0);
  });
}
