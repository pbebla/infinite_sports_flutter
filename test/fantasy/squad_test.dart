import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  SquadPick p(String id, FantasyPosition pos, int price, {bool bench = false}) =>
      SquadPick(playerId: id, position: pos, priceTenths: price, bench: bench);

  List<SquadPick> legal() => [
        p('g1', FantasyPosition.gk, 70),
        p('d1', FantasyPosition.def, 80),
        p('d2', FantasyPosition.def, 60),
        p('a1', FantasyPosition.att, 90),
        p('a2', FantasyPosition.att, 80),
        p('d3', FantasyPosition.def, 50, bench: true),
        p('a3', FantasyPosition.att, 50, bench: true),
      ];

  test('legal squad validates with no errors', () {
    final s = FantasySquad(picks: legal(), captainId: 'a1', viceId: 'd1');
    expect(validateSquad(s, cfg), isEmpty);
  });
  test('budget overflow flagged', () {
    final picks = legal()..[3] = p('a1', FantasyPosition.att, 150);
    final s = FantasySquad(picks: picks, captainId: 'a1', viceId: 'd1');
    expect(validateSquad(s, cfg), contains(SquadIssue.overBudget));
  });
  test('wrong formation flagged (2 GKs)', () {
    final picks = legal()..[1] = p('g2', FantasyPosition.gk, 60);
    final s = FantasySquad(picks: picks, captainId: 'a1', viceId: 'g1');
    expect(validateSquad(s, cfg), contains(SquadIssue.formation));
  });
  test('wrong bench composition flagged', () {
    final picks = legal()
      ..[5] = p('d3', FantasyPosition.def, 50)
      ..[6] = p('a3', FantasyPosition.att, 50, bench: true)
      ..add(p('a4', FantasyPosition.att, 40, bench: true));
    final s = FantasySquad(picks: picks, captainId: 'a1', viceId: 'd1');
    expect(validateSquad(s, cfg), contains(SquadIssue.formation));
  });
  test('duplicate player flagged', () {
    final picks = legal()..[4] = p('a1', FantasyPosition.att, 80);
    final s = FantasySquad(picks: picks, captainId: 'a1', viceId: 'd1');
    expect(validateSquad(s, cfg), contains(SquadIssue.duplicatePlayer));
  });
  test('captain must be a starter; vice must differ', () {
    final s1 = FantasySquad(picks: legal(), captainId: 'd3', viceId: 'd1');
    expect(validateSquad(s1, cfg), contains(SquadIssue.badCaptain));
    final s2 = FantasySquad(picks: legal(), captainId: 'a1', viceId: 'a1');
    expect(validateSquad(s2, cfg), contains(SquadIssue.badCaptain));
  });
  test('round-trips through RTDB-safe map', () {
    final s = FantasySquad(picks: legal(), captainId: 'a1', viceId: 'd1');
    expect(FantasySquad.fromMap(s.toMap()).toMap(), s.toMap());
  });
  test('spentTenths and bank', () {
    final s = FantasySquad(picks: legal(), captainId: 'a1', viceId: 'd1');
    expect(s.spentTenths, 480);
    expect(cfg.budgetTenths - s.spentTenths, 20);
  });
}
