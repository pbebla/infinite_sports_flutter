// Squad shapes + legality. Faithful port of lib/fantasy/engine/squad.dart,
// including the fromMap strictness (bad types throw, exactly like the Dart
// `as` casts) and the issue enum semantics.

import {
  FantasyConfig, FantasyPosition, parsePosition, squadSize,
} from './fantasy_config';

export interface SquadPick {
  playerId: string;
  position: FantasyPosition;
  priceTenths: number; // price PAID; sells by the FPL rule, selling.ts (spec §4)
  bench: boolean;
}

export type SquadIssue =
  | 'formation' | 'overBudget' | 'duplicatePlayer' | 'badCaptain';

export interface FantasySquad {
  picks: SquadPick[];
  captainId: string;
  viceId: string;
  chip: string | null; // 'tripleCaptain' | 'benchBoost' | null for the week
}

export function squadStarters(s: FantasySquad): SquadPick[] {
  return s.picks.filter((p) => !p.bench);
}

export function squadBench(s: FantasySquad): SquadPick[] {
  return s.picks.filter((p) => p.bench);
}

export function spentTenths(s: FantasySquad): number {
  return s.picks.reduce((a, p) => a + p.priceTenths, 0);
}

export function squadPickToMap(p: SquadPick): Record<string, unknown> {
  return {
    playerId: p.playerId,
    position: p.position,
    priceTenths: p.priceTenths,
    bench: p.bench,
  };
}

/** Dart SquadPick.fromMap: `as` casts throw on wrong types. */
export function squadPickFromMap(m: Record<string, unknown>): SquadPick {
  const playerId = m['playerId'];
  if (typeof playerId !== 'string') throw new Error('playerId is not a String');
  const price = m['priceTenths'];
  if (typeof price !== 'number') throw new Error('priceTenths is not a num');
  return {
    playerId,
    position: parsePosition(String(m['position'])),
    priceTenths: Math.trunc(price), // Dart (… as num).toInt()
    bench: m['bench'] === true,
  };
}

export function squadToMap(s: FantasySquad): Record<string, unknown> {
  const out: Record<string, unknown> = {
    picks: s.picks.map(squadPickToMap),
    captainId: s.captainId,
    viceId: s.viceId,
  };
  if (s.chip !== null) out['chip'] = s.chip;
  return out;
}

/** Dart FantasySquad.fromMap: picks must be a List (non-map entries are
 *  skipped, as `whereType<Map>` does); captain/vice must be Strings. */
export function squadFromMap(m: Record<string, unknown>): FantasySquad {
  const rawPicks = m['picks'];
  if (!Array.isArray(rawPicks)) throw new Error('picks is not a List');
  const captainId = m['captainId'];
  const viceId = m['viceId'];
  if (typeof captainId !== 'string') throw new Error('captainId is not a String');
  if (typeof viceId !== 'string') throw new Error('viceId is not a String');
  const chip = m['chip'];
  if (chip != null && typeof chip !== 'string') {
    throw new Error('chip is not a String');
  }
  return {
    picks: rawPicks
      .filter((p): p is Record<string, unknown> =>
        p !== null && typeof p === 'object' && !Array.isArray(p))
      .map(squadPickFromMap),
    captainId,
    viceId,
    chip: chip ?? null,
  };
}

/** `realizedTenths` is the running profit/loss from sales (may be negative):
 *  the budget rule is spent <= budget + realizedTenths (FPL selling, spec §4,
 *  selling.ts). It defaults to 0, which is the old "spent <= budget". */
export function validateSquad(
  s: FantasySquad, cfg: FantasyConfig, realizedTenths = 0,
): SquadIssue[] {
  const issues: SquadIssue[] = [];
  const count = (ps: SquadPick[], pos: FantasyPosition) =>
    ps.filter((p) => p.position === pos).length;

  const starters = squadStarters(s);
  const bench = squadBench(s);
  const okFormation = count(starters, 'GK') === cfg.startersGk &&
    count(starters, 'DEF') === cfg.startersDef &&
    count(starters, 'ATT') === cfg.startersAtt &&
    count(bench, 'GK') === 0 &&
    count(bench, 'DEF') === cfg.benchDef &&
    count(bench, 'ATT') === cfg.benchAtt &&
    s.picks.length === squadSize(cfg);
  if (!okFormation) issues.push('formation');

  if (spentTenths(s) > cfg.budgetTenths + realizedTenths) {
    issues.push('overBudget');
  }

  const ids = new Set(s.picks.map((p) => p.playerId));
  if (ids.size !== s.picks.length) issues.push('duplicatePlayer');

  const starterIds = new Set(starters.map((p) => p.playerId));
  if (!starterIds.has(s.captainId) ||
    !starterIds.has(s.viceId) ||
    s.captainId === s.viceId) {
    issues.push('badCaptain');
  }
  return issues;
}
