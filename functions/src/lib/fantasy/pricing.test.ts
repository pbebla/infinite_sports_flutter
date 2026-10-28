// Port of test/fantasy/pricing_test.dart — percentile snapping, reprice
// gap rule, clamps.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import { applyDelta, openingPrices, repriceDeltas } from './pricing';

const cfg = futsalDefault();

describe('pricing', () => {
  it('opening prices: percentile within position maps to range', () => {
    const prices = openingPrices({ best: 100.0, mid: 50.0, low: 0.0 }, cfg);
    expect(prices['best']).toBe(cfg.priceMaxTenths);
    expect(prices['low']).toBe(cfg.priceMinTenths);
    expect(prices['mid']).toBe(95); // midpoint of 40..150 snapped to step 5
  });
  it('opening price snaps to 0.5M steps', () => {
    const prices = openingPrices({ a: 61.0, b: 0.0, c: 100.0 }, cfg);
    expect(prices['a']! % cfg.priceStepTenths).toBe(0);
  });
  it('rookies (no history) get the rookie price', () => {
    expect(openingPrices({}, cfg)).toEqual({});
    expect(cfg.rookiePriceTenths).toBe(60);
  });
  it('single-player position gets midpoint', () => {
    expect(openingPrices({ only: 42.0 }, cfg)['only']).toBe(95);
  });
  it('reprice: beat the position mean by the gap -> +1 step', () => {
    // mean of {10, 2, 0} = 4; gap 4 -> rise at >= 8, fall at <= 0
    const deltas = repriceDeltas({ hot: 10, ok: 2, cold: 0 }, cfg);
    expect(deltas['hot']).toBe(cfg.priceStepTenths);
    expect(deltas['ok']).toBe(0);
    expect(deltas['cold']).toBe(-cfg.priceStepTenths);
  });
  it('reprice clamps at floor and ceiling', () => {
    expect(applyDelta(150, 5, cfg)).toBe(150);
    expect(applyDelta(40, -5, cfg)).toBe(40);
    expect(applyDelta(70, 5, cfg)).toBe(75);
  });
  it('empty week -> no movement', () => {
    expect(repriceDeltas({}, cfg)).toEqual({});
  });
});
