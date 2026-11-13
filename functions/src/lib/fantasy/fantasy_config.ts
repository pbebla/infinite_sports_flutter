// Every tunable number in Infinite Fantasy. Values live in RTDB at
// `Fantasy/<sport>/<season>/Config`; the futsal default IS the launch config.
//
// Faithful port of lib/fantasy/engine/fantasy_config.dart, including the
// fromMap fallback semantics (any non-number falls back per field, never
// throws). All money/points values are integer tenths.

export type FantasyPosition = 'GK' | 'DEF' | 'ATT';

export const FANTASY_POSITIONS: readonly FantasyPosition[] = ['GK', 'DEF', 'ATT'];

/** Dart FantasyPosition.parse: throws on anything but GK/DEF/ATT. */
export function parsePosition(s: string): FantasyPosition {
  if (s === 'GK' || s === 'DEF' || s === 'ATT') return s;
  throw new Error(`Unknown fantasy position: ${s}`);
}

export interface ScoringRow {
  plays: number;
  goal: number;
  assist: number;
  cleanSheet: number;
  per2Saves: number;
  penSave: number;
  penMiss: number;
  per2Conceded: number;
  yellow: number;
  red: number;
  ownGoal: number;
  dplThreshold: number | null;
  dplBonus: number;
}

export interface BpsWeights {
  goal: number;
  assist: number;
  save: number;
  dpl: number;
  cleanSheet: number;
  penSave: number;
  penMiss: number;
  ownGoal: number;
  yellow: number;
  red: number;
}

export interface FantasyConfig {
  scoring: Record<FantasyPosition, ScoringRow>;
  bps: BpsWeights;
  budgetTenths: number;
  priceMinTenths: number;
  priceMaxTenths: number;
  priceStepTenths: number;
  rookiePriceTenths: number;
  /** Points above/below the position's gameweek mean that move a price ±1 step. */
  repriceGap: number;
  freeTransfersPerWeek: number;
  maxBankedTransfers: number;
  extraTransferCost: number;
  lockHour: number; // league-local
  benchFactorPercent: number; // 50 = half points
  captainMultiplier: number;
  tripleCaptainMultiplier: number;
  /** Last gameweek of chip set 1 (owner decision: GW1–6, then set 2 runs
   *  GW7 through the playoffs). Set 1's unused chips do not carry over. */
  chipSet1EndGw: number;
  startersGk: number;
  startersDef: number;
  startersAtt: number;
  benchDef: number;
  benchAtt: number;
}

export function squadSize(cfg: FantasyConfig): number {
  return cfg.startersGk + cfg.startersDef + cfg.startersAtt +
    cfg.benchDef + cfg.benchAtt;
}

/** Dart `_i`: `v is num ? v.toInt() : fallback`. Math.trunc replicates Dart
 *  num.toInt() (truncation toward zero) for the doubles RTDB can hand back. */
function intOr(v: unknown, fallback: number): number {
  return typeof v === 'number' ? Math.trunc(v) : fallback;
}

/** Plain object check — RTDB array coercion (a JS Array) is NOT a map,
 *  matching Dart's `is Map` on a List. */
function isPlainMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

const DEFAULT_BPS: BpsWeights = {
  goal: 12, assist: 9, save: 2, dpl: 2, cleanSheet: 5,
  penSave: 8, penMiss: -6, ownGoal: -8, yellow: -4, red: -9,
};

export function futsalDefault(): FantasyConfig {
  return {
    scoring: {
      GK: {
        plays: 1, goal: 10, assist: 5, cleanSheet: 8, per2Saves: 1,
        penSave: 5, penMiss: -2, per2Conceded: -1, yellow: -1,
        red: -3, ownGoal: -2, dplThreshold: null, dplBonus: 0,
      },
      DEF: {
        plays: 1, goal: 6, assist: 4, cleanSheet: 5, per2Saves: 0,
        penSave: 0, penMiss: -2, per2Conceded: -1, yellow: -1,
        red: -3, ownGoal: -2, dplThreshold: 5, dplBonus: 2,
      },
      ATT: {
        plays: 1, goal: 4, assist: 3, cleanSheet: 2, per2Saves: 0,
        penSave: 0, penMiss: -2, per2Conceded: 0, yellow: -1,
        red: -3, ownGoal: -2, dplThreshold: 7, dplBonus: 2,
      },
    },
    bps: { ...DEFAULT_BPS },
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
    chipSet1EndGw: 6,
    startersGk: 1,
    startersDef: 2,
    startersAtt: 2,
    benchDef: 1,
    benchAtt: 1,
  };
}

export function scoringRowToMap(r: ScoringRow): Record<string, unknown> {
  const out: Record<string, unknown> = {
    plays: r.plays, goal: r.goal, assist: r.assist,
    cleanSheet: r.cleanSheet, per2Saves: r.per2Saves,
    penSave: r.penSave, penMiss: r.penMiss,
    per2Conceded: r.per2Conceded, yellow: r.yellow, red: r.red,
    ownGoal: r.ownGoal,
  };
  if (r.dplThreshold !== null) out['dplThreshold'] = r.dplThreshold;
  out['dplBonus'] = r.dplBonus;
  return out;
}

export function scoringRowFromMap(m: Record<string, unknown>, fallback: ScoringRow): ScoringRow {
  return {
    plays: intOr(m['plays'], fallback.plays),
    goal: intOr(m['goal'], fallback.goal),
    assist: intOr(m['assist'], fallback.assist),
    cleanSheet: intOr(m['cleanSheet'], fallback.cleanSheet),
    per2Saves: intOr(m['per2Saves'], fallback.per2Saves),
    penSave: intOr(m['penSave'], fallback.penSave),
    penMiss: intOr(m['penMiss'], fallback.penMiss),
    per2Conceded: intOr(m['per2Conceded'], fallback.per2Conceded),
    yellow: intOr(m['yellow'], fallback.yellow),
    red: intOr(m['red'], fallback.red),
    ownGoal: intOr(m['ownGoal'], fallback.ownGoal),
    // Dart: `m['dplThreshold'] == null ? fallback.dplThreshold : _i(.., 0)`
    dplThreshold: m['dplThreshold'] == null
      ? fallback.dplThreshold
      : intOr(m['dplThreshold'], 0),
    dplBonus: intOr(m['dplBonus'], fallback.dplBonus),
  };
}

export function bpsWeightsToMap(w: BpsWeights): Record<string, unknown> {
  return {
    goal: w.goal, assist: w.assist, save: w.save, dpl: w.dpl,
    cleanSheet: w.cleanSheet, penSave: w.penSave, penMiss: w.penMiss,
    ownGoal: w.ownGoal, yellow: w.yellow, red: w.red,
  };
}

export function bpsWeightsFromMap(m: Record<string, unknown>): BpsWeights {
  const d = DEFAULT_BPS;
  return {
    goal: intOr(m['goal'], d.goal), assist: intOr(m['assist'], d.assist),
    save: intOr(m['save'], d.save), dpl: intOr(m['dpl'], d.dpl),
    cleanSheet: intOr(m['cleanSheet'], d.cleanSheet),
    penSave: intOr(m['penSave'], d.penSave),
    penMiss: intOr(m['penMiss'], d.penMiss),
    ownGoal: intOr(m['ownGoal'], d.ownGoal),
    yellow: intOr(m['yellow'], d.yellow), red: intOr(m['red'], d.red),
  };
}

export function configToMap(c: FantasyConfig): Record<string, unknown> {
  const scoring: Record<string, unknown> = {};
  for (const p of FANTASY_POSITIONS) scoring[p] = scoringRowToMap(c.scoring[p]);
  return {
    scoring,
    bps: bpsWeightsToMap(c.bps),
    budgetTenths: c.budgetTenths,
    priceMinTenths: c.priceMinTenths,
    priceMaxTenths: c.priceMaxTenths,
    priceStepTenths: c.priceStepTenths,
    rookiePriceTenths: c.rookiePriceTenths,
    repriceGap: c.repriceGap,
    freeTransfersPerWeek: c.freeTransfersPerWeek,
    maxBankedTransfers: c.maxBankedTransfers,
    extraTransferCost: c.extraTransferCost,
    lockHour: c.lockHour,
    benchFactorPercent: c.benchFactorPercent,
    captainMultiplier: c.captainMultiplier,
    tripleCaptainMultiplier: c.tripleCaptainMultiplier,
    chipSet1EndGw: c.chipSet1EndGw,
    startersGk: c.startersGk,
    startersDef: c.startersDef,
    startersAtt: c.startersAtt,
    benchDef: c.benchDef,
    benchAtt: c.benchAtt,
  };
}

/** Same fallback semantics as the Dart FantasyConfig.fromMap: every field
 *  falls back to the futsal default independently; a scoring row is taken
 *  from the node only when `scoring` is a map AND the row itself is a map
 *  (RTDB array coercion fails both checks, as in Dart). */
export function configFromMap(m: Record<string, unknown>): FantasyConfig {
  const d = futsalDefault();
  const rawScoring = m['scoring'];
  const scoring = {} as Record<FantasyPosition, ScoringRow>;
  for (const p of FANTASY_POSITIONS) {
    scoring[p] = isPlainMap(rawScoring) && isPlainMap(rawScoring[p])
      ? scoringRowFromMap(rawScoring[p] as Record<string, unknown>, d.scoring[p])
      : d.scoring[p];
  }
  return {
    scoring,
    bps: isPlainMap(m['bps'])
      ? bpsWeightsFromMap(m['bps'] as Record<string, unknown>)
      : d.bps,
    budgetTenths: intOr(m['budgetTenths'], d.budgetTenths),
    priceMinTenths: intOr(m['priceMinTenths'], d.priceMinTenths),
    priceMaxTenths: intOr(m['priceMaxTenths'], d.priceMaxTenths),
    priceStepTenths: intOr(m['priceStepTenths'], d.priceStepTenths),
    rookiePriceTenths: intOr(m['rookiePriceTenths'], d.rookiePriceTenths),
    repriceGap: intOr(m['repriceGap'], d.repriceGap),
    freeTransfersPerWeek: intOr(m['freeTransfersPerWeek'], d.freeTransfersPerWeek),
    maxBankedTransfers: intOr(m['maxBankedTransfers'], d.maxBankedTransfers),
    extraTransferCost: intOr(m['extraTransferCost'], d.extraTransferCost),
    lockHour: intOr(m['lockHour'], d.lockHour),
    benchFactorPercent: intOr(m['benchFactorPercent'], d.benchFactorPercent),
    captainMultiplier: intOr(m['captainMultiplier'], d.captainMultiplier),
    tripleCaptainMultiplier:
      intOr(m['tripleCaptainMultiplier'], d.tripleCaptainMultiplier),
    chipSet1EndGw: intOr(m['chipSet1EndGw'], d.chipSet1EndGw),
    startersGk: intOr(m['startersGk'], d.startersGk),
    startersDef: intOr(m['startersDef'], d.startersDef),
    startersAtt: intOr(m['startersAtt'], d.startersAtt),
    benchDef: intOr(m['benchDef'], d.benchDef),
    benchAtt: intOr(m['benchAtt'], d.benchAtt),
  };
}
