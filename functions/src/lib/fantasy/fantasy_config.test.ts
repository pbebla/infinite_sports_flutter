// Port of test/fantasy/fantasy_config_test.dart.
import { describe, expect, it } from 'vitest';
import {
  configFromMap, configToMap, futsalDefault, parsePosition,
} from './fantasy_config';

describe('fantasy_config', () => {
  it('futsal defaults match the locked spec table', () => {
    const c = futsalDefault();
    expect(c.scoring.GK.goal).toBe(10);
    expect(c.scoring.DEF.goal).toBe(6);
    expect(c.scoring.ATT.goal).toBe(4);
    expect(c.scoring.GK.assist).toBe(5);
    expect(c.scoring.DEF.cleanSheet).toBe(5);
    expect(c.scoring.ATT.cleanSheet).toBe(2);
    expect(c.scoring.GK.per2Saves).toBe(1);
    expect(c.scoring.ATT.per2Conceded).toBe(0);
    expect(c.scoring.DEF.dplThreshold).toBe(5);
    expect(c.scoring.ATT.dplThreshold).toBe(7);
    expect(c.budgetTenths).toBe(500);
    expect(c.priceMinTenths).toBe(40);
    expect(c.priceMaxTenths).toBe(150);
    expect(c.priceStepTenths).toBe(5);
    expect(c.freeTransfersPerWeek).toBe(2);
    expect(c.maxBankedTransfers).toBe(7);
    expect(c.extraTransferCost).toBe(4);
    expect(c.lockHour).toBe(15);
    expect(c.benchFactorPercent).toBe(50);
    expect(c.captainMultiplier).toBe(2);
    expect(c.tripleCaptainMultiplier).toBe(3);
    expect(c.rookiePriceTenths).toBe(60);
    // Chip windows (owner decision): set 1 = GW1–6, set 2 = GW7–playoffs.
    expect(c.chipSet1EndGw).toBe(6);
  });
  it('round-trips through RTDB-safe map', () => {
    const c = futsalDefault();
    const back = configFromMap(configToMap(c));
    expect(configToMap(back)).toEqual(configToMap(c));
  });
  it('fromMap tolerates missing keys with defaults', () => {
    const c = configFromMap({ budgetTenths: 400 });
    expect(c.budgetTenths).toBe(400);
    expect(c.scoring.GK.goal).toBe(10);
    // Pre-chipSet1EndGw config nodes fall back to the default window.
    expect(c.chipSet1EndGw).toBe(6);
  });
  it('fromMap ignores non-numeric values and array-coerced maps', () => {
    const c = configFromMap({
      budgetTenths: 'oops',
      scoring: ['coerced'], // RTDB array coercion -> not a map -> defaults
      bps: 7, // not a map -> defaults
    });
    expect(c.budgetTenths).toBe(500);
    expect(c.scoring.DEF.goal).toBe(6);
    expect(c.bps.goal).toBe(12);
  });
  it('chipSet1EndGw round-trips and accepts a tuned value', () => {
    const m = configToMap(futsalDefault());
    m['chipSet1EndGw'] = 8;
    const tuned = configFromMap(m);
    expect(tuned.chipSet1EndGw).toBe(8);
    expect(configToMap(tuned)['chipSet1EndGw']).toBe(8);
  });
  it('position parsing', () => {
    expect(parsePosition('GK')).toBe('GK');
    expect(parsePosition('DEF')).toBe('DEF');
    expect(parsePosition('ATT')).toBe('ATT');
    expect(() => parsePosition('MID')).toThrow();
  });
});
