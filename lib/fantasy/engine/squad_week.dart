import 'fantasy_config.dart';
import 'squad.dart';

class PlayerWeek {
  const PlayerWeek({required this.points, required this.played});
  final int points; // whole points from scorePlayerWeek().total
  final bool played;
}

class SlotResult {
  const SlotResult({
    required this.playerId,
    required this.position,
    required this.bench,
    required this.rawPoints,
    required this.countedTenths,
    required this.multiplier,
    required this.autoSubbedIn,
    required this.played,
  });
  final String playerId;
  final FantasyPosition position;
  final bool bench;
  final int rawPoints;
  final int countedTenths;
  final int multiplier; // 1 normal, 2 captain, 3 triple captain
  final bool autoSubbedIn;
  final bool played;
}

class SquadWeekResult {
  const SquadWeekResult(this.slots);
  final List<SlotResult> slots;
  int get totalTenths => slots.fold(0, (a, s) => a + s.countedTenths);
  SlotResult slot(String playerId) =>
      slots.firstWhere((s) => s.playerId == playerId);
}

SquadWeekResult scoreSquadWeek(
    FantasySquad squad, Map<String, PlayerWeek> week, FantasyConfig cfg) {
  PlayerWeek of(String id) =>
      week[id] ?? const PlayerWeek(points: 0, played: false);

  // Auto-subs: each absent starter is covered by the first unused bench
  // player of the SAME position who played (spec §2). Covering bench scores
  // FULL; uncovered bench scores half (or full on Bench Boost).
  final promoted = <String>{};
  for (final starter in squad.starters) {
    if (of(starter.playerId).played) continue;
    for (final b in squad.bench) {
      if (b.position == starter.position &&
          !promoted.contains(b.playerId) &&
          of(b.playerId).played) {
        promoted.add(b.playerId);
        break;
      }
    }
  }

  // Armband: captain if played, else vice if played, else nobody (spec §2).
  final capMult =
      squad.chip == 'tripleCaptain' ? cfg.tripleCaptainMultiplier : cfg.captainMultiplier;
  String? armband;
  if (of(squad.captainId).played) {
    armband = squad.captainId;
  } else if (of(squad.viceId).played) {
    armband = squad.viceId;
  }

  final benchBoost = squad.chip == 'benchBoost';
  final slots = <SlotResult>[];
  for (final p in squad.picks) {
    final w = of(p.playerId);
    final mult = p.playerId == armband ? capMult : 1;
    int counted;
    if (!w.played) {
      counted = 0;
    } else if (!p.bench) {
      counted = w.points * mult * 10;
    } else if (benchBoost || promoted.contains(p.playerId)) {
      counted = w.points * mult * 10;
    } else {
      counted = w.points * mult * cfg.benchFactorPercent ~/ 10;
    }
    slots.add(SlotResult(
      playerId: p.playerId,
      position: p.position,
      bench: p.bench,
      rawPoints: w.points,
      countedTenths: counted,
      multiplier: p.playerId == armband && w.played ? capMult : 1,
      autoSubbedIn: promoted.contains(p.playerId),
      played: w.played,
    ));
  }
  return SquadWeekResult(slots);
}
