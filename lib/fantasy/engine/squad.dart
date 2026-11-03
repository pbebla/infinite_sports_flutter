import 'fantasy_config.dart';

class SquadPick {
  const SquadPick({
    required this.playerId,
    required this.position,
    required this.priceTenths,
    this.bench = false,
  });
  final String playerId;
  final FantasyPosition position;
  final int priceTenths; // price PAID; sells by the FPL rule, selling.dart (spec §4)
  final bool bench;

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'position': position.db,
        'priceTenths': priceTenths,
        'bench': bench,
      };
  static SquadPick fromMap(Map m) => SquadPick(
        playerId: m['playerId'] as String,
        position: FantasyPosition.parse(m['position'] as String),
        priceTenths: (m['priceTenths'] as num).toInt(),
        bench: m['bench'] == true,
      );
}

enum SquadIssue { formation, overBudget, duplicatePlayer, badCaptain }

class FantasySquad {
  const FantasySquad({
    required this.picks,
    required this.captainId,
    required this.viceId,
    this.chip,
  });
  final List<SquadPick> picks;
  final String captainId;
  final String viceId;
  final String? chip; // 'tripleCaptain' | 'benchBoost' | null for the week

  Iterable<SquadPick> get starters => picks.where((p) => !p.bench);
  Iterable<SquadPick> get bench => picks.where((p) => p.bench);
  int get spentTenths => picks.fold(0, (a, p) => a + p.priceTenths);

  Map<String, dynamic> toMap() => {
        'picks': [for (final p in picks) p.toMap()],
        'captainId': captainId,
        'viceId': viceId,
        if (chip != null) 'chip': chip,
      };
  static FantasySquad fromMap(Map m) => FantasySquad(
        picks: [
          for (final p in (m['picks'] as List).whereType<Map>())
            SquadPick.fromMap(p)
        ],
        captainId: m['captainId'] as String,
        viceId: m['viceId'] as String,
        chip: m['chip'] as String?,
      );
}

/// [realizedTenths] is the running profit/loss from sales (may be negative):
/// the budget rule is spent <= budget + realizedTenths (FPL selling, spec §4,
/// selling.dart). It defaults to 0, which is the old "spent <= budget".
List<SquadIssue> validateSquad(FantasySquad s, FantasyConfig cfg,
    {int realizedTenths = 0}) {
  final issues = <SquadIssue>[];
  int count(Iterable<SquadPick> ps, FantasyPosition pos) =>
      ps.where((p) => p.position == pos).length;

  final okFormation = count(s.starters, FantasyPosition.gk) == cfg.startersGk &&
      count(s.starters, FantasyPosition.def) == cfg.startersDef &&
      count(s.starters, FantasyPosition.att) == cfg.startersAtt &&
      count(s.bench, FantasyPosition.gk) == 0 &&
      count(s.bench, FantasyPosition.def) == cfg.benchDef &&
      count(s.bench, FantasyPosition.att) == cfg.benchAtt &&
      s.picks.length == cfg.squadSize;
  if (!okFormation) issues.add(SquadIssue.formation);

  if (s.spentTenths > cfg.budgetTenths + realizedTenths) {
    issues.add(SquadIssue.overBudget);
  }

  final ids = s.picks.map((p) => p.playerId).toSet();
  if (ids.length != s.picks.length) issues.add(SquadIssue.duplicatePlayer);

  final starterIds = s.starters.map((p) => p.playerId).toSet();
  if (!starterIds.contains(s.captainId) ||
      !starterIds.contains(s.viceId) ||
      s.captainId == s.viceId) {
    issues.add(SquadIssue.badCaptain);
  }
  return issues;
}
