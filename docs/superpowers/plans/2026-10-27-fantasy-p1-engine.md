# Infinite Fantasy P1 — Pure Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The pure, exhaustively-tested Dart library that computes every Infinite Fantasy number — scoring, bonus points, squad weeks (captain/bench/auto-subs/chips), transfers, gameweeks/locks, prices — with zero Firebase or UI dependencies.

**Architecture:** Small single-purpose modules under `lib/fantasy/engine/`, all pure functions over immutable inputs. Config-driven: every point value, threshold, and price step lives in `FantasyConfig` (futsal defaults match spec §7 of `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md`); basketball/FF later = new config, not new code. A golden-fixtures task pins behavior so the later TypeScript finalizer (P4) can run the same vectors.

**Tech Stack:** Dart (fan repo `infinite_sports_flutter`, branch `zaya-fantasy`), `flutter_test`. Flutter CLI: `C:\src\flutter\bin\flutter.bat`. No new dependencies.

**Conventions:** All engine files import nothing from Flutter/Firebase (pure Dart, `import 'dart:...'` only). Money is in **tenths of millions as int** (e.g. $7.5M = 75) to avoid double drift; points that can halve (bench) are **tenths of points as int** (half of 7 = 35 tenths, rendered 3.5). The UI layer formats. Rationale: integer math = deterministic golden fixtures across Dart/TS.

---

### Task 1: League time (Pacific lock instants)

**Files:**
- Create: `lib/fantasy/engine/league_time.dart`
- Test: `test/fantasy/league_time_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/league_time.dart';

void main() {
  test('PST offset in January', () {
    // Jan 15 2026 is PST (UTC-8): 3PM local = 23:00 UTC
    expect(lockInstantUtc('01152026', hour: 15),
        DateTime.utc(2026, 1, 15, 23, 0));
  });
  test('PDT offset in July', () {
    // Jul 12 2026 is PDT (UTC-7): 3PM local = 22:00 UTC
    expect(lockInstantUtc('07122026', hour: 15),
        DateTime.utc(2026, 7, 12, 22, 0));
  });
  test('DST start day 2026 (Mar 8) is PDT', () {
    expect(lockInstantUtc('03082026', hour: 15),
        DateTime.utc(2026, 3, 8, 22, 0));
  });
  test('day before DST start is PST', () {
    expect(lockInstantUtc('03072026', hour: 15),
        DateTime.utc(2026, 3, 7, 23, 0));
  });
  test('DST end day 2026 (Nov 1) is PST', () {
    expect(lockInstantUtc('11012026', hour: 15),
        DateTime.utc(2026, 11, 1, 23, 0));
  });
  test('parses MMDDYYYY', () {
    final d = parseDbDate('05202026');
    expect([d.year, d.month, d.day], [2026, 5, 20]);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fantasy/league_time_test.dart`
Expected: FAIL (file does not exist)

- [ ] **Step 3: Implement**

```dart
/// League wall-clock → UTC. The league runs on America/Los_Angeles; deadlines
/// are league-local (spec §5), never the phone's timezone.
library;

DateTime parseDbDate(String mmddyyyy) => DateTime.utc(
      int.parse(mmddyyyy.substring(4, 8)),
      int.parse(mmddyyyy.substring(0, 2)),
      int.parse(mmddyyyy.substring(2, 4)),
    );

/// Nth (1-based) given weekday of a month, as a UTC date.
DateTime _nthWeekday(int year, int month, int weekday, int n) {
  var d = DateTime.utc(year, month, 1);
  final first = (weekday - d.weekday + 7) % 7;
  return DateTime.utc(year, month, 1 + first + 7 * (n - 1));
}

/// True if this local-calendar date is inside US daylight saving time
/// (2nd Sunday of March through the day before the 1st Sunday of November).
bool isPacificDst(DateTime localDate) {
  final start = _nthWeekday(localDate.year, 3, DateTime.sunday, 2);
  final end = _nthWeekday(localDate.year, 11, DateTime.sunday, 1);
  final d = DateTime.utc(localDate.year, localDate.month, localDate.day);
  return !d.isBefore(start) && d.isBefore(end);
}

/// UTC instant of [hour]:00 league time on a database date (MMDDYYYY).
DateTime lockInstantUtc(String mmddyyyy, {required int hour}) {
  final d = parseDbDate(mmddyyyy);
  final offset = isPacificDst(d) ? 7 : 8; // PDT -7, PST -8
  return DateTime.utc(d.year, d.month, d.day, hour + offset);
}
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): league timezone lock instants (engine)`

---

### Task 2: FantasyConfig (all tunables + futsal defaults)

**Files:**
- Create: `lib/fantasy/engine/fantasy_config.dart`
- Test: `test/fantasy/fantasy_config_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

void main() {
  test('futsal defaults match the locked spec table', () {
    final c = FantasyConfig.futsalDefault();
    expect(c.scoring[FantasyPosition.gk]!.goal, 10);
    expect(c.scoring[FantasyPosition.def]!.goal, 6);
    expect(c.scoring[FantasyPosition.att]!.goal, 4);
    expect(c.scoring[FantasyPosition.gk]!.assist, 5);
    expect(c.scoring[FantasyPosition.def]!.cleanSheet, 5);
    expect(c.scoring[FantasyPosition.att]!.cleanSheet, 2);
    expect(c.scoring[FantasyPosition.gk]!.per2Saves, 1);
    expect(c.scoring[FantasyPosition.att]!.per2Conceded, 0);
    expect(c.scoring[FantasyPosition.def]!.dplThreshold, 5);
    expect(c.scoring[FantasyPosition.att]!.dplThreshold, 7);
    expect(c.budgetTenths, 500);
    expect(c.priceMinTenths, 40);
    expect(c.priceMaxTenths, 150);
    expect(c.priceStepTenths, 5);
    expect(c.freeTransfersPerWeek, 2);
    expect(c.maxBankedTransfers, 7);
    expect(c.extraTransferCost, 4);
    expect(c.lockHour, 15);
    expect(c.benchFactorPercent, 50);
    expect(c.captainMultiplier, 2);
    expect(c.tripleCaptainMultiplier, 3);
    expect(c.rookiePriceTenths, 60);
  });
  test('round-trips through RTDB-safe map', () {
    final c = FantasyConfig.futsalDefault();
    final back = FantasyConfig.fromMap(c.toMap());
    expect(back.toMap(), c.toMap());
  });
  test('fromMap tolerates missing keys with defaults', () {
    final c = FantasyConfig.fromMap({'budgetTenths': 400});
    expect(c.budgetTenths, 400);
    expect(c.scoring[FantasyPosition.gk]!.goal, 10);
  });
  test('position parsing', () {
    expect(FantasyPosition.parse('GK'), FantasyPosition.gk);
    expect(FantasyPosition.parse('DEF'), FantasyPosition.def);
    expect(FantasyPosition.parse('ATT'), FantasyPosition.att);
    expect(() => FantasyPosition.parse('MID'), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run to verify failure** (same command pattern; expect FAIL)
- [ ] **Step 3: Implement**

```dart
/// Every tunable number in Infinite Fantasy. Values live in RTDB at
/// Fantasy/<sport>/<season>/Config; this default IS the futsal launch config
/// and the Rules page renders from the same object (spec §10a).
library;

enum FantasyPosition {
  gk,
  def,
  att;

  String get db => switch (this) { gk => 'GK', def => 'DEF', att => 'ATT' };

  static FantasyPosition parse(String s) => switch (s) {
        'GK' => gk,
        'DEF' => def,
        'ATT' => att,
        _ => throw ArgumentError('Unknown fantasy position: $s'),
      };
}

class ScoringRow {
  const ScoringRow({
    required this.plays,
    required this.goal,
    required this.assist,
    required this.cleanSheet,
    required this.per2Saves,
    required this.penSave,
    required this.penMiss,
    required this.per2Conceded,
    required this.yellow,
    required this.red,
    required this.ownGoal,
    this.dplThreshold,
    this.dplBonus = 0,
  });

  final int plays, goal, assist, cleanSheet, per2Saves, penSave, penMiss;
  final int per2Conceded, yellow, red, ownGoal;
  final int? dplThreshold;
  final int dplBonus;

  Map<String, dynamic> toMap() => {
        'plays': plays, 'goal': goal, 'assist': assist,
        'cleanSheet': cleanSheet, 'per2Saves': per2Saves,
        'penSave': penSave, 'penMiss': penMiss,
        'per2Conceded': per2Conceded, 'yellow': yellow, 'red': red,
        'ownGoal': ownGoal,
        if (dplThreshold != null) 'dplThreshold': dplThreshold,
        'dplBonus': dplBonus,
      };

  static ScoringRow fromMap(Map m, ScoringRow fallback) => ScoringRow(
        plays: _i(m['plays'], fallback.plays),
        goal: _i(m['goal'], fallback.goal),
        assist: _i(m['assist'], fallback.assist),
        cleanSheet: _i(m['cleanSheet'], fallback.cleanSheet),
        per2Saves: _i(m['per2Saves'], fallback.per2Saves),
        penSave: _i(m['penSave'], fallback.penSave),
        penMiss: _i(m['penMiss'], fallback.penMiss),
        per2Conceded: _i(m['per2Conceded'], fallback.per2Conceded),
        yellow: _i(m['yellow'], fallback.yellow),
        red: _i(m['red'], fallback.red),
        ownGoal: _i(m['ownGoal'], fallback.ownGoal),
        dplThreshold: m['dplThreshold'] == null
            ? fallback.dplThreshold
            : _i(m['dplThreshold'], 0),
        dplBonus: _i(m['dplBonus'], fallback.dplBonus),
      );
}

int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;

/// Weights for the published bonus-points formula (spec §7).
class BpsWeights {
  const BpsWeights({
    this.goal = 12, this.assist = 9, this.save = 2, this.dpl = 2,
    this.cleanSheet = 5, this.penSave = 8, this.penMiss = -6,
    this.ownGoal = -8, this.yellow = -4, this.red = -9,
  });
  final int goal, assist, save, dpl, cleanSheet, penSave, penMiss;
  final int ownGoal, yellow, red;

  Map<String, dynamic> toMap() => {
        'goal': goal, 'assist': assist, 'save': save, 'dpl': dpl,
        'cleanSheet': cleanSheet, 'penSave': penSave, 'penMiss': penMiss,
        'ownGoal': ownGoal, 'yellow': yellow, 'red': red,
      };
  static BpsWeights fromMap(Map m) {
    const d = BpsWeights();
    return BpsWeights(
      goal: _i(m['goal'], d.goal), assist: _i(m['assist'], d.assist),
      save: _i(m['save'], d.save), dpl: _i(m['dpl'], d.dpl),
      cleanSheet: _i(m['cleanSheet'], d.cleanSheet),
      penSave: _i(m['penSave'], d.penSave),
      penMiss: _i(m['penMiss'], d.penMiss),
      ownGoal: _i(m['ownGoal'], d.ownGoal),
      yellow: _i(m['yellow'], d.yellow), red: _i(m['red'], d.red),
    );
  }
}

class FantasyConfig {
  const FantasyConfig({
    required this.scoring,
    required this.bps,
    required this.budgetTenths,
    required this.priceMinTenths,
    required this.priceMaxTenths,
    required this.priceStepTenths,
    required this.rookiePriceTenths,
    required this.repriceGap,
    required this.freeTransfersPerWeek,
    required this.maxBankedTransfers,
    required this.extraTransferCost,
    required this.lockHour,
    required this.benchFactorPercent,
    required this.captainMultiplier,
    required this.tripleCaptainMultiplier,
    required this.startersGk,
    required this.startersDef,
    required this.startersAtt,
    required this.benchDef,
    required this.benchAtt,
  });

  final Map<FantasyPosition, ScoringRow> scoring;
  final BpsWeights bps;
  final int budgetTenths, priceMinTenths, priceMaxTenths, priceStepTenths;
  final int rookiePriceTenths;
  /// Points above/below the position's gameweek mean that move a price ±1 step.
  final int repriceGap;
  final int freeTransfersPerWeek, maxBankedTransfers, extraTransferCost;
  final int lockHour; // league-local (Task 1)
  final int benchFactorPercent; // 50 = half points
  final int captainMultiplier, tripleCaptainMultiplier;
  final int startersGk, startersDef, startersAtt, benchDef, benchAtt;

  int get squadSize =>
      startersGk + startersDef + startersAtt + benchDef + benchAtt;

  factory FantasyConfig.futsalDefault() => FantasyConfig(
        scoring: {
          FantasyPosition.gk: const ScoringRow(
              plays: 1, goal: 10, assist: 5, cleanSheet: 8, per2Saves: 1,
              penSave: 5, penMiss: -2, per2Conceded: -1, yellow: -1,
              red: -3, ownGoal: -2),
          FantasyPosition.def: const ScoringRow(
              plays: 1, goal: 6, assist: 4, cleanSheet: 5, per2Saves: 0,
              penSave: 0, penMiss: -2, per2Conceded: -1, yellow: -1,
              red: -3, ownGoal: -2, dplThreshold: 5, dplBonus: 2),
          FantasyPosition.att: const ScoringRow(
              plays: 1, goal: 4, assist: 3, cleanSheet: 2, per2Saves: 0,
              penSave: 0, penMiss: -2, per2Conceded: 0, yellow: -1,
              red: -3, ownGoal: -2, dplThreshold: 7, dplBonus: 2),
        },
        bps: const BpsWeights(),
        budgetTenths: 500,
        priceMinTenths: 40,
        priceMaxTenths: 150,
        priceStepTenths: 5,
        rookiePriceTenths: 60,
        repriceGap: 4,
        freeTransfersPerWeek: 2,
        maxBankedTransfers: 7,
        extraTransferCost: 4,
        lockHour: 15,
        benchFactorPercent: 50,
        captainMultiplier: 2,
        tripleCaptainMultiplier: 3,
        startersGk: 1,
        startersDef: 2,
        startersAtt: 2,
        benchDef: 1,
        benchAtt: 1,
      );

  Map<String, dynamic> toMap() => {
        'scoring': {for (final e in scoring.entries) e.key.db: e.value.toMap()},
        'bps': bps.toMap(),
        'budgetTenths': budgetTenths,
        'priceMinTenths': priceMinTenths,
        'priceMaxTenths': priceMaxTenths,
        'priceStepTenths': priceStepTenths,
        'rookiePriceTenths': rookiePriceTenths,
        'repriceGap': repriceGap,
        'freeTransfersPerWeek': freeTransfersPerWeek,
        'maxBankedTransfers': maxBankedTransfers,
        'extraTransferCost': extraTransferCost,
        'lockHour': lockHour,
        'benchFactorPercent': benchFactorPercent,
        'captainMultiplier': captainMultiplier,
        'tripleCaptainMultiplier': tripleCaptainMultiplier,
        'startersGk': startersGk,
        'startersDef': startersDef,
        'startersAtt': startersAtt,
        'benchDef': benchDef,
        'benchAtt': benchAtt,
      };

  static FantasyConfig fromMap(Map m) {
    final d = FantasyConfig.futsalDefault();
    final rawScoring = m['scoring'];
    return FantasyConfig(
      scoring: {
        for (final p in FantasyPosition.values)
          p: rawScoring is Map && rawScoring[p.db] is Map
              ? ScoringRow.fromMap(rawScoring[p.db] as Map, d.scoring[p]!)
              : d.scoring[p]!,
      },
      bps: m['bps'] is Map ? BpsWeights.fromMap(m['bps'] as Map) : d.bps,
      budgetTenths: _i(m['budgetTenths'], d.budgetTenths),
      priceMinTenths: _i(m['priceMinTenths'], d.priceMinTenths),
      priceMaxTenths: _i(m['priceMaxTenths'], d.priceMaxTenths),
      priceStepTenths: _i(m['priceStepTenths'], d.priceStepTenths),
      rookiePriceTenths: _i(m['rookiePriceTenths'], d.rookiePriceTenths),
      repriceGap: _i(m['repriceGap'], d.repriceGap),
      freeTransfersPerWeek:
          _i(m['freeTransfersPerWeek'], d.freeTransfersPerWeek),
      maxBankedTransfers: _i(m['maxBankedTransfers'], d.maxBankedTransfers),
      extraTransferCost: _i(m['extraTransferCost'], d.extraTransferCost),
      lockHour: _i(m['lockHour'], d.lockHour),
      benchFactorPercent: _i(m['benchFactorPercent'], d.benchFactorPercent),
      captainMultiplier: _i(m['captainMultiplier'], d.captainMultiplier),
      tripleCaptainMultiplier:
          _i(m['tripleCaptainMultiplier'], d.tripleCaptainMultiplier),
      startersGk: _i(m['startersGk'], d.startersGk),
      startersDef: _i(m['startersDef'], d.startersDef),
      startersAtt: _i(m['startersAtt'], d.startersAtt),
      benchDef: _i(m['benchDef'], d.benchDef),
      benchAtt: _i(m['benchAtt'], d.benchAtt),
    );
  }
}
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): FantasyConfig with locked futsal defaults`

---

### Task 3: Per-player gameweek scoring

**Files:**
- Create: `lib/fantasy/engine/player_game_stats.dart`, `lib/fantasy/engine/scoring.dart`
- Test: `test/fantasy/scoring_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/scoring.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  PlayerGameStats s({
    int goals = 0, int assists = 0, int saves = 0, int penSaved = 0,
    int penMissed = 0, int ownGoals = 0, int yellows = 0, int reds = 0,
    int dpl = 0, int conceded = 0, bool present = true,
  }) =>
      PlayerGameStats(
          goals: goals, assists: assists, saves: saves, penSaved: penSaved,
          penMissed: penMissed, ownGoals: ownGoals, yellows: yellows,
          reds: reds, dpl: dpl, teamConceded: conceded, present: present);

  test('absent player scores zero regardless of stats', () {
    final r = scorePlayerGame(s(goals: 3, present: false), FantasyPosition.att, cfg);
    expect(r.total, 0);
    expect(r.breakdown, isEmpty);
  });
  test('appearance point (CS suppressed by a conceded goal)', () {
    expect(scorePlayerGame(s(conceded: 1), FantasyPosition.def, cfg).total, 1);
  });
  test('GK goal is +10 on top of plays', () {
    expect(scorePlayerGame(s(goals: 1, conceded: 1), FantasyPosition.gk, cfg)
        .total, 1 + 10);
  });
  test('clean sheet needs present + zero conceded', () {
    expect(scorePlayerGame(s(), FantasyPosition.gk, cfg).total, 1 + 8);
    expect(scorePlayerGame(s(conceded: 1), FantasyPosition.gk, cfg).total, 1);
  });
  test('every 2 saves = +1 (GK), floors', () {
    expect(scorePlayerGame(s(saves: 5), FantasyPosition.gk, cfg).total,
        1 + 8 + 2); // plays + CS + floor(5/2)
  });
  test('ATT never loses for conceding; GK/DEF lose 1 per 2', () {
    expect(scorePlayerGame(s(conceded: 4), FantasyPosition.att, cfg).total, 1);
    expect(scorePlayerGame(s(conceded: 4), FantasyPosition.def, cfg).total, 1 - 2);
    expect(scorePlayerGame(s(conceded: 5), FantasyPosition.gk, cfg).total, 1 - 2);
  });
  test('DPL threshold bonus (conceded: 1 suppresses CS, too few to deduct)', () {
    expect(scorePlayerGame(s(dpl: 5, conceded: 1), FantasyPosition.def, cfg)
        .total, 1 + 2);
    expect(scorePlayerGame(s(dpl: 4, conceded: 1), FantasyPosition.def, cfg)
        .total, 1);
    expect(scorePlayerGame(s(dpl: 7, conceded: 1), FantasyPosition.att, cfg)
        .total, 1 + 2);
    expect(scorePlayerGame(s(dpl: 99, conceded: 1), FantasyPosition.gk, cfg)
        .total, 1);
  });
  test('cards, own goals, pens', () {
    expect(scorePlayerGame(s(yellows: 1, reds: 1, conceded: 1),
        FantasyPosition.att, cfg).total, 1 - 1 - 3);
    expect(scorePlayerGame(s(ownGoals: 1, conceded: 1), FantasyPosition.def, cfg)
        .total, 1 - 2);
    expect(scorePlayerGame(s(penSaved: 1), FantasyPosition.gk, cfg).total,
        1 + 8 + 5);
    expect(scorePlayerGame(s(penMissed: 1, conceded: 1), FantasyPosition.att, cfg)
        .total, 1 - 2);
  });
  test('kitchen-sink DEF example matches hand math', () {
    // plays 1 + goal 6 + assist 4 + dpl(6>=5) 2 - conceded(3)/2 1 - yellow 1 = 11
    expect(scorePlayerGame(
        s(goals: 1, assists: 1, dpl: 6, conceded: 3, yellows: 1),
        FantasyPosition.def, cfg).total, 11);
  });
  test('breakdown lines sum to total', () {
    final r = scorePlayerGame(
        s(goals: 2, saves: 4, conceded: 2), FantasyPosition.gk, cfg);
    expect(r.breakdown.fold<int>(0, (a, b) => a + b.points), r.total);
  });
  test('gameweek sum across multiple games', () {
    final wk = scorePlayerWeek(
        [s(goals: 1, conceded: 1), s(conceded: 2, yellows: 1)],
        FantasyPosition.att, cfg);
    expect(wk.total, (1 + 4) + (1 - 1));
    expect(wk.played, isTrue);
  });
  test('week with no present games = not played', () {
    final wk = scorePlayerWeek([s(present: false)], FantasyPosition.att, cfg);
    expect(wk.total, 0);
    expect(wk.played, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement `player_game_stats.dart`**

```dart
/// One player's raw stats in one real game — the engine's only input shape.
/// `present` comes from the attendance step (P2); `teamConceded` from the
/// final score. Everything else from captured activities.
class PlayerGameStats {
  const PlayerGameStats({
    this.goals = 0, this.assists = 0, this.saves = 0, this.penSaved = 0,
    this.penMissed = 0, this.ownGoals = 0, this.yellows = 0, this.reds = 0,
    this.dpl = 0, this.teamConceded = 0, this.present = true,
  });
  final int goals, assists, saves, penSaved, penMissed, ownGoals;
  final int yellows, reds, dpl, teamConceded;
  final bool present;
}
```

- [ ] **Step 4: Implement `scoring.dart`**

```dart
import 'fantasy_config.dart';
import 'player_game_stats.dart';

class ScoreLine {
  const ScoreLine(this.label, this.points);
  final String label;
  final int points;
}

class GameScore {
  const GameScore(this.total, this.breakdown);
  final int total;
  final List<ScoreLine> breakdown;
}

class WeekScore {
  const WeekScore(this.total, this.played, this.games);
  final int total;
  final bool played;
  final List<GameScore> games;
}

GameScore scorePlayerGame(
    PlayerGameStats s, FantasyPosition pos, FantasyConfig cfg) {
  if (!s.present) return const GameScore(0, []);
  final r = cfg.scoring[pos]!;
  final lines = <ScoreLine>[
    ScoreLine('Plays', r.plays),
    if (s.goals > 0) ScoreLine('Goals ×${s.goals}', s.goals * r.goal),
    if (s.assists > 0) ScoreLine('Assists ×${s.assists}', s.assists * r.assist),
    if (s.teamConceded == 0 && r.cleanSheet != 0)
      ScoreLine('Clean sheet', r.cleanSheet),
    if (r.per2Saves != 0 && s.saves >= 2)
      ScoreLine('Saves ×${s.saves}', (s.saves ~/ 2) * r.per2Saves),
    if (s.penSaved > 0 && r.penSave != 0)
      ScoreLine('Penalty saves ×${s.penSaved}', s.penSaved * r.penSave),
    if (s.penMissed > 0)
      ScoreLine('Penalty misses ×${s.penMissed}', s.penMissed * r.penMiss),
    if (r.per2Conceded != 0 && s.teamConceded >= 2)
      ScoreLine('Conceded ${s.teamConceded}',
          (s.teamConceded ~/ 2) * r.per2Conceded),
    if (r.dplThreshold != null && s.dpl >= r.dplThreshold!)
      ScoreLine('Defensive plays ${s.dpl}', r.dplBonus),
    if (s.yellows > 0) ScoreLine('Yellow ×${s.yellows}', s.yellows * r.yellow),
    if (s.reds > 0) ScoreLine('Red ×${s.reds}', s.reds * r.red),
    if (s.ownGoals > 0)
      ScoreLine('Own goals ×${s.ownGoals}', s.ownGoals * r.ownGoal),
  ];
  return GameScore(lines.fold(0, (a, l) => a + l.points), lines);
}

WeekScore scorePlayerWeek(
    List<PlayerGameStats> games, FantasyPosition pos, FantasyConfig cfg) {
  final scored = [for (final g in games) scorePlayerGame(g, pos, cfg)];
  return WeekScore(
    scored.fold(0, (a, g) => a + g.total),
    games.any((g) => g.present),
    scored,
  );
}
```

- [ ] **Step 5: Run tests — PASS expected**
- [ ] **Step 6: Commit** `feat(fantasy): per-player gameweek scoring with breakdown`

---

### Task 4: Bonus points (BPS) with FPL-style tie sharing

**Files:**
- Create: `lib/fantasy/engine/bps.dart`
- Test: `test/fantasy/bps_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/bps.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  test('bps raw score', () {
    // goal 12*2 + assist 9 + save 2*3 + yellow -4 = 35
    expect(
        bpsScore(const PlayerGameStats(goals: 2, assists: 1, saves: 3, yellows: 1, teamConceded: 1), cfg),
        35);
  });
  test('absent player has no bps', () {
    expect(bpsScore(const PlayerGameStats(goals: 2, present: false), cfg), 0);
  });
  test('top three get 3/2/1', () {
    final b = awardBonus({'a': 50, 'b': 40, 'c': 30, 'd': 20});
    expect(b, {'a': 3, 'b': 2, 'c': 1});
  });
  test('tie for first: both get 3, next gets 1', () {
    expect(awardBonus({'a': 50, 'b': 50, 'c': 30, 'd': 20}),
        {'a': 3, 'b': 3, 'c': 1});
  });
  test('tie for second: 3,2,2 and nobody gets 1', () {
    expect(awardBonus({'a': 50, 'b': 40, 'c': 40, 'd': 20}),
        {'a': 3, 'b': 2, 'c': 2});
  });
  test('triple tie for first: 3,3,3', () {
    expect(awardBonus({'a': 50, 'b': 50, 'c': 50, 'd': 20}),
        {'a': 3, 'b': 3, 'c': 3});
  });
  test('zero/negative bps earn nothing', () {
    expect(awardBonus({'a': 0, 'b': -5, 'c': 10}), {'c': 3});
  });
  test('fewer than three players', () {
    expect(awardBonus({'a': 10}), {'a': 3});
  });
}
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement**

```dart
import 'fantasy_config.dart';
import 'player_game_stats.dart';

/// Raw bonus-points-system score for one player in one game (published
/// formula, spec §7 — shown verbatim on the Rules page).
int bpsScore(PlayerGameStats s, FantasyConfig cfg) {
  if (!s.present) return 0;
  final w = cfg.bps;
  return s.goals * w.goal +
      s.assists * w.assist +
      s.saves * w.save +
      s.dpl * w.dpl +
      (s.teamConceded == 0 ? w.cleanSheet : 0) +
      s.penSaved * w.penSave +
      s.penMissed * w.penMiss +
      s.ownGoals * w.ownGoal +
      s.yellows * w.yellow +
      s.reds * w.red;
}

/// 3/2/1 to the best BPS scores in a match, FPL tie rule: equal scores share
/// the higher bonus and consume the slots below it. Only positive BPS counts.
Map<String, int> awardBonus(Map<String, int> bpsByPlayer) {
  final entries = bpsByPlayer.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  const ladder = [3, 2, 1];
  final out = <String, int>{};
  var slot = 0;
  var i = 0;
  while (i < entries.length && slot < ladder.length) {
    final tied = entries.where((e) => e.value == entries[i].value).toList();
    for (final e in tied) {
      out[e.key] = ladder[slot];
    }
    i += tied.length;
    slot += tied.length;
  }
  return out;
}
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): bonus points formula + 3/2/1 tie sharing`

---

### Task 5: Squad model + validation

**Files:**
- Create: `lib/fantasy/engine/squad.dart`
- Test: `test/fantasy/squad_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement**

```dart
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
  final int priceTenths; // price PAID (buy/sell at current price, spec §4)
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

List<SquadIssue> validateSquad(FantasySquad s, FantasyConfig cfg) {
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

  if (s.spentTenths > cfg.budgetTenths) issues.add(SquadIssue.overBudget);

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
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): squad model + validation`

---

### Task 6: Squad week scoring (captain/vice, bench half, auto-subs, chips)

**Files:**
- Create: `lib/fantasy/engine/squad_week.dart`
- Test: `test/fantasy/squad_week_test.dart`

Points here are **tenths** (half of 7 pts = 35 tenths → UI shows 3.5).

- [ ] **Step 1: Write the failing tests**

```dart
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
    expect(r.totalTenths, (28 + 10 + 7 + 2) * 10 + 100);
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
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement**

```dart
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
```

**Note for implementer:** `w.points * mult * cfg.benchFactorPercent ~/ 10`
with benchFactorPercent 50 gives `points * mult * 5` tenths = exactly half.
Keep that integer path (no doubles).

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): squad week scoring — armband, bench, auto-subs, chips`

---

### Task 7: Transfer state machine

**Files:**
- Create: `lib/fantasy/engine/transfers.dart`
- Test: `test/fantasy/transfers_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/transfers.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  test('cost: within free allowance is zero', () {
    expect(transferCost(used: 2, free: 2, cfg: cfg), 0);
    expect(transferCost(used: 1, free: 2, cfg: cfg), 0);
  });
  test('cost: -4 per extra', () {
    expect(transferCost(used: 3, free: 2, cfg: cfg), 4);
    expect(transferCost(used: 5, free: 2, cfg: cfg), 12);
  });
  test('cost: wildcard/free hit weeks are free', () {
    expect(transferCost(used: 9, free: 2, cfg: cfg, unlimited: true), 0);
  });
  test('rollover banks unused up to 7', () {
    expect(rolloverFreeTransfers(free: 2, used: 0, cfg: cfg), 4);
    expect(rolloverFreeTransfers(free: 4, used: 1, cfg: cfg), 5);
    expect(rolloverFreeTransfers(free: 7, used: 0, cfg: cfg), 7);
  });
  test('rollover floors at the weekly grant even after overspend', () {
    expect(rolloverFreeTransfers(free: 2, used: 6, cfg: cfg), 2);
  });
  test('rollover on wildcard/free-hit week keeps the bank', () {
    expect(rolloverFreeTransfers(free: 5, used: 9, cfg: cfg, unlimited: true), 7);
  });
}
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement**

```dart
import 'fantasy_config.dart';

/// Point cost of making [used] transfers with [free] available (spec §5).
/// Wildcard / Free Hit weeks ([unlimited]) are always free.
int transferCost(
    {required int used,
    required int free,
    required FantasyConfig cfg,
    bool unlimited = false}) {
  if (unlimited) return 0;
  final extra = used - free;
  return extra > 0 ? extra * cfg.extraTransferCost : 0;
}

/// Free transfers available next gameweek. Unused ones bank (cap 7); a
/// wildcard/free-hit week doesn't consume the bank.
int rolloverFreeTransfers(
    {required int free,
    required int used,
    required FantasyConfig cfg,
    bool unlimited = false}) {
  final remaining = unlimited ? free : (free - used).clamp(0, free);
  return (remaining + cfg.freeTransfersPerWeek)
      .clamp(0, cfg.maxBankedTransfers);
}
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): transfer cost + free-transfer banking`

---

### Task 8: Gameweeks from the schedule

**Files:**
- Create: `lib/fantasy/engine/gameweeks.dart`
- Test: `test/fantasy/gameweeks_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  // unsorted on purpose; typical futsal Sundays
  final dates = ['07122026', '06282026', '07052026'];

  test('derives ordered gameweeks, one per match day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws.map((g) => g.number), [1, 2, 3]);
    expect(gws.map((g) => g.date), ['06282026', '07052026', '07122026']);
  });
  test('lock = 3PM league time on the match day (PDT in July)', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws[0].lockUtc, DateTime.utc(2026, 6, 28, 22, 0));
  });
  test('status transitions', () {
    final gws = deriveGameweeks(dates, cfg);
    final gw2 = gws[1]; // Jul 5
    expect(gw2.statusAt(DateTime.utc(2026, 7, 3, 12)), GameweekStatus.open);
    expect(gw2.statusAt(DateTime.utc(2026, 7, 5, 23)), GameweekStatus.locked);
    expect(gw2.statusAt(DateTime.utc(2026, 6, 20)), GameweekStatus.upcoming);
  });
  test('gw1 opens immediately; later gws open after the previous match day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws[0].opensUtc, isNull);
    // gw2 opens Jun 29 00:00 league time = 07:00 UTC (PDT)
    expect(gws[1].opensUtc, DateTime.utc(2026, 6, 29, 7, 0));
  });
  test('current gameweek at a moment', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(currentGameweek(gws, DateTime.utc(2026, 7, 3))!.number, 2);
    expect(currentGameweek(gws, DateTime.utc(2026, 8, 1)), isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement**

```dart
import 'fantasy_config.dart';
import 'league_time.dart';

enum GameweekStatus { upcoming, open, locked }

class Gameweek {
  const Gameweek({
    required this.number,
    required this.date,
    required this.lockUtc,
    required this.opensUtc,
  });
  final int number;
  final String date; // MMDDYYYY
  final DateTime lockUtc;
  final DateTime? opensUtc; // null = open from launch (gw1)

  GameweekStatus statusAt(DateTime nowUtc) {
    if (opensUtc != null && nowUtc.isBefore(opensUtc!)) {
      return GameweekStatus.upcoming;
    }
    return nowUtc.isBefore(lockUtc)
        ? GameweekStatus.open
        : GameweekStatus.locked;
  }
}

List<Gameweek> deriveGameweeks(List<String> matchDates, FantasyConfig cfg) {
  final sorted = [...matchDates]
    ..sort((a, b) => parseDbDate(a).compareTo(parseDbDate(b)));
  final out = <Gameweek>[];
  for (var i = 0; i < sorted.length; i++) {
    DateTime? opens;
    if (i > 0) {
      final prev = parseDbDate(sorted[i - 1]).add(const Duration(days: 1));
      final mm = prev.month.toString().padLeft(2, '0');
      final dd = prev.day.toString().padLeft(2, '0');
      opens = lockInstantUtc('$mm$dd${prev.year}', hour: 0);
    }
    out.add(Gameweek(
      number: i + 1,
      date: sorted[i],
      lockUtc: lockInstantUtc(sorted[i], hour: cfg.lockHour),
      opensUtc: opens,
    ));
  }
  return out;
}

/// The gameweek a manager is editing/watching at [nowUtc]: the first one
/// whose lock is still ahead, else the last locked one while its match day
/// is ongoing (lock day), else null (season over).
Gameweek? currentGameweek(List<Gameweek> gws, DateTime nowUtc) {
  for (final g in gws) {
    final dayEnd = g.lockUtc.add(const Duration(hours: 24));
    if (nowUtc.isBefore(dayEnd)) return g;
  }
  return null;
}
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): gameweek derivation + lock windows`

---

### Task 9: Pricing (openers + Monday repricing)

**Files:**
- Create: `lib/fantasy/engine/pricing.dart`
- Test: `test/fantasy/pricing_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/pricing.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();

  test('opening prices: percentile within position maps to range', () {
    final prices = openingPrices({
      'best': 100.0, 'mid': 50.0, 'low': 0.0,
    }, cfg);
    expect(prices['best'], cfg.priceMaxTenths);
    expect(prices['low'], cfg.priceMinTenths);
    expect(prices['mid'], 95); // midpoint of 40..150 snapped to step 5
  });
  test('opening price snaps to 0.5M steps', () {
    final prices = openingPrices({'a': 61.0, 'b': 0.0, 'c': 100.0}, cfg);
    expect(prices['a']! % cfg.priceStepTenths, 0);
  });
  test('rookies (no history) get the rookie price', () {
    expect(openingPrices({}, cfg), isEmpty);
    expect(cfg.rookiePriceTenths, 60);
  });
  test('single-player position gets midpoint', () {
    expect(openingPrices({'only': 42.0}, cfg)['only'], 95);
  });
  test('reprice: beat the position mean by the gap → +1 step', () {
    // mean of {10, 2, 0} = 4; gap 4 → rise at >= 8, fall at <= 0
    final deltas = repriceDeltas({'hot': 10, 'ok': 2, 'cold': 0}, cfg);
    expect(deltas['hot'], cfg.priceStepTenths);
    expect(deltas['ok'], 0);
    expect(deltas['cold'], -cfg.priceStepTenths);
  });
  test('reprice clamps at floor and ceiling', () {
    expect(applyDelta(150, 5, cfg), 150);
    expect(applyDelta(40, -5, cfg), 40);
    expect(applyDelta(70, 5, cfg), 75);
  });
  test('empty week → no movement', () {
    expect(repriceDeltas({}, cfg), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement**

```dart
import 'fantasy_config.dart';

int _snap(int tenths, FantasyConfig cfg) {
  final step = cfg.priceStepTenths;
  final snapped = ((tenths + step ~/ 2) ~/ step) * step;
  return snapped.clamp(cfg.priceMinTenths, cfg.priceMaxTenths);
}

/// Opening prices from a historical score per player (any comparable
/// aggregate — the caller computes fantasy-points-per-season from historical
/// stats). Percentile WITHIN the given group (callers pass one position at a
/// time) maps linearly onto [priceMin, priceMax], snapped to the step.
/// Rookies are absent here; the caller assigns cfg.rookiePriceTenths.
Map<String, int> openingPrices(Map<String, double> scoreByPlayer, FantasyConfig cfg) {
  if (scoreByPlayer.isEmpty) return {};
  final values = scoreByPlayer.values.toList()..sort();
  final lo = values.first, hi = values.last;
  final span = hi - lo;
  return scoreByPlayer.map((id, v) {
    final t = span == 0 ? 0.5 : (v - lo) / span;
    final tenths = cfg.priceMinTenths +
        ((cfg.priceMaxTenths - cfg.priceMinTenths) * t).round();
    return MapEntry(id, _snap(tenths, cfg));
  });
}

/// Monday repricing (spec §4): performance-based and position-relative.
/// Input: this gameweek's fantasy points for every eligible player of ONE
/// position (absent players included at their real score, usually 0).
/// A player [repriceGap]+ points above the position mean rises one step;
/// [repriceGap]+ below falls one step.
Map<String, int> repriceDeltas(Map<String, int> weekPoints, FantasyConfig cfg) {
  if (weekPoints.isEmpty) return {};
  final mean =
      weekPoints.values.fold<int>(0, (a, b) => a + b) / weekPoints.length;
  return weekPoints.map((id, pts) {
    var d = 0;
    if (pts >= mean + cfg.repriceGap) d = cfg.priceStepTenths;
    if (pts <= mean - cfg.repriceGap) d = -cfg.priceStepTenths;
    return MapEntry(id, d);
  });
}

int applyDelta(int priceTenths, int delta, FantasyConfig cfg) =>
    (priceTenths + delta).clamp(cfg.priceMinTenths, cfg.priceMaxTenths);
```

- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): opening prices + position-relative repricing`

---

### Task 10: Activities → PlayerGameStats mapper

**Files:**
- Create: `lib/fantasy/engine/stats_mapper.dart`
- Test: `test/fantasy/stats_mapper_test.dart`

**Context for implementer:** real futsal game nodes look like
`Futsal/<season>/Date/<MMDDYYYY>/<i>` with keys `team1`, `team2`,
`team1score`, `team2score`, `team1activity`, `team2activity`, `status`.
Each activity list entry has `activityType` (one of `Goal`, `Assist`, `Save`,
`DPL`, `Foul`, `PenGoal`, `PenMissed`, `PenSaved`, `OwnGoal`, `Yellow`,
`SecondYellow`, `Red` — see Manager `lib/models/league_sport_config.dart`),
a player name/id field, and a minute. **Read the fan app's existing activity
parsing first** (`lib/tournament_tabs/single_match_tallies.dart` and
`lib/model/gameactivity.dart`) and reuse its field handling — activities can
arrive as List OR Map (RTDB array coercion), entries may be null-padded.

Counting rules (document in code):
- `goals` = Goal + PenGoal events for the player.
- `yellows` = Yellow events only. `reds` = Red + SecondYellow events (a
  second yellow IS the red; it is not an extra yellow). Net: 2nd-yellow player
  = first Yellow (−1) + red (−3).
- `penMissed` = PenMissed by the player; `penSaved` = PenSaved credited to
  the KEEPER (verify which side's activity list carries it in the existing
  parser before wiring).
- `teamConceded` = the opposing team's final score; both activity lists in a
  game map to their own team's players.
- `present` is NOT derivable here — the mapper takes an
  `Attendance` map (`playerId -> bool`, default true when the node is absent,
  per spec §8) and stamps it through.

- [ ] **Step 1: Write failing tests** using a hand-built fixture map that mirrors
  the real shape (including one List-coerced activity list with a leading
  null), covering: goals+pen goal aggregation, second-yellow → red counting,
  conceded from opposing score, attendance default-true, attendance
  explicit-absent, and a player with zero activities still present.
- [ ] **Step 2: Run to verify failure**
- [ ] **Step 3: Implement** `mapGameToStats(Map gameNode, {required String teamName, Map<String, bool>? attendance})` → `Map<String, PlayerGameStats>` reusing the existing tally parsing helpers.
- [ ] **Step 4: Run tests — PASS expected**
- [ ] **Step 5: Commit** `feat(fantasy): game-node → PlayerGameStats mapper`

---

### Task 11: Golden gameweek fixture (cross-engine contract)

**Files:**
- Create: `test/fantasy/fixtures/golden_gameweek.json`, `test/fantasy/golden_test.dart`

- [ ] **Step 1:** Build one JSON fixture describing a full fictional gameweek:
  config (futsal default), 12 players with positions, 2 games of raw
  per-player stats + attendance, 3 manager squads (one with captain absent →
  vice, one bench-boost, one with 3 transfers used/2 free), and the
  **expected outputs** (per-player points, bonus awards, per-squad totals in
  tenths, transfer costs, reprice deltas).
- [ ] **Step 2:** Write `golden_test.dart` that loads the JSON, runs the full
  pipeline (mapper → scoring → bps → squad weeks → transfer costs →
  reprice), and asserts every expected number.
- [ ] **Step 3:** Run — PASS. Fix any expectation that was hand-computed wrong
  (recompute by hand; the engine must not be "fixed" to match a wrong
  expectation).
- [ ] **Step 4: Commit** `test(fantasy): golden gameweek fixture pins engine behavior`
  (P4's TypeScript finalizer will replay this same file.)

---

### Task 12: Full verification

- [ ] **Step 1:** `C:\src\flutter\bin\flutter.bat test test/fantasy/` → all pass
- [ ] **Step 2:** `C:\src\flutter\bin\flutter.bat test` → full suite stays green
- [ ] **Step 3:** `C:\src\flutter\bin\flutter.bat analyze lib/fantasy test/fantasy` → no issues
- [ ] **Step 4: Commit** any stragglers; push nothing (owner reviews first).

---

## Self-review notes

- Spec coverage: §2 (squad/armband/bench/auto-sub → Tasks 5–6), §4 (prices →
  Task 9), §5 (gameweeks/locks/transfers → Tasks 7–8 + Task 1 timezone), §6
  (chips → Tasks 6–7; Wildcard/FreeHit are data-level states consumed as
  `unlimited` in Task 7 — squad snapshot/revert for FreeHit is P3/P4 storage
  logic, not engine math), §7 (scoring/BPS → Tasks 3–4), §8 attendance enters
  as `present` (Tasks 3, 10). Mini-leagues/leaderboards are aggregation of
  these outputs (P3/P4), not engine.
- The `scoring[pos]!` lookups are safe: `FantasyConfig.fromMap` always fills
  all three positions.
- Bench half uses integer tenths exclusively; goldens stay byte-stable.
