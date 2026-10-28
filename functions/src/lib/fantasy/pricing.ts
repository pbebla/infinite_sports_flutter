// Opening prices + Monday repricing. Faithful port of
// lib/fantasy/engine/pricing.dart.

import { FantasyConfig } from './fantasy_config';

/** Dart num.clamp(lo, hi). */
function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/** Dart `~/` (integer division truncating toward zero); prices here are
 *  always positive so trunc == floor, but trunc is the faithful port. */
function intDiv(a: number, b: number): number {
  return Math.trunc(a / b);
}

function snap(tenths: number, cfg: FantasyConfig): number {
  const step = cfg.priceStepTenths;
  // Dart: ((tenths + step ~/ 2) ~/ step) * step
  const snapped = intDiv(tenths + intDiv(step, 2), step) * step;
  return clamp(snapped, cfg.priceMinTenths, cfg.priceMaxTenths);
}

/** Opening prices from a historical score per player (any comparable
 *  aggregate — the caller computes fantasy-points-per-season from historical
 *  stats). Percentile WITHIN the given group (callers pass one position at a
 *  time) maps linearly onto [priceMin, priceMax], snapped to the step.
 *  Rookies are absent here; the caller assigns cfg.rookiePriceTenths. */
export function openingPrices(
  scoreByPlayer: Record<string, number>, cfg: FantasyConfig,
): Record<string, number> {
  const entries = Object.entries(scoreByPlayer);
  if (entries.length === 0) return {};
  const values = entries.map(([, v]) => v).sort((a, b) => a - b);
  const lo = values[0];
  const hi = values[values.length - 1];
  const span = hi - lo;
  const out: Record<string, number> = {};
  for (const [id, v] of entries) {
    const t = span === 0 ? 0.5 : (v - lo) / span;
    // Dart .round() — half away from zero; the operand is non-negative here
    // so Math.round (half toward +inf) is identical.
    const tenths = cfg.priceMinTenths +
      Math.round((cfg.priceMaxTenths - cfg.priceMinTenths) * t);
    out[id] = snap(tenths, cfg);
  }
  return out;
}

/** Monday repricing (spec §4): performance-based and position-relative.
 *  Input: this gameweek's fantasy points for every eligible player of ONE
 *  position (absent players included at their real score, usually 0).
 *  A player [repriceGap]+ points above the position mean rises one step;
 *  [repriceGap]+ below falls one step. */
export function repriceDeltas(
  weekPoints: Record<string, number>, cfg: FantasyConfig,
): Record<string, number> {
  const entries = Object.entries(weekPoints);
  if (entries.length === 0) return {};
  const mean =
    entries.reduce((a, [, b]) => a + b, 0) / entries.length;
  const out: Record<string, number> = {};
  for (const [id, pts] of entries) {
    let d = 0;
    if (pts >= mean + cfg.repriceGap) d = cfg.priceStepTenths;
    if (pts <= mean - cfg.repriceGap) d = -cfg.priceStepTenths;
    out[id] = d;
  }
  return out;
}

export function applyDelta(
  priceTenths: number, delta: number, cfg: FantasyConfig,
): number {
  return clamp(priceTenths + delta, cfg.priceMinTenths, cfg.priceMaxTenths);
}
