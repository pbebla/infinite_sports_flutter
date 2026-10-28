// Port of test/fantasy/transfers_test.dart — cost + rollover clamps.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import { rolloverFreeTransfers, transferCost } from './transfers';

const cfg = futsalDefault();

describe('transfers', () => {
  it('cost: within free allowance is zero', () => {
    expect(transferCost({ used: 2, free: 2, cfg })).toBe(0);
    expect(transferCost({ used: 1, free: 2, cfg })).toBe(0);
  });
  it('cost: -4 per extra', () => {
    expect(transferCost({ used: 3, free: 2, cfg })).toBe(4);
    expect(transferCost({ used: 5, free: 2, cfg })).toBe(12);
  });
  it('cost: wildcard/free hit weeks are free', () => {
    expect(transferCost({ used: 9, free: 2, cfg, unlimited: true })).toBe(0);
  });
  it('rollover banks unused up to 7', () => {
    expect(rolloverFreeTransfers({ free: 2, used: 0, cfg })).toBe(4);
    expect(rolloverFreeTransfers({ free: 4, used: 1, cfg })).toBe(5);
    expect(rolloverFreeTransfers({ free: 7, used: 0, cfg })).toBe(7);
  });
  it('rollover floors at the weekly grant even after overspend', () => {
    expect(rolloverFreeTransfers({ free: 2, used: 6, cfg })).toBe(2);
  });
  it('rollover on wildcard/free-hit week keeps the bank', () => {
    expect(rolloverFreeTransfers({ free: 5, used: 9, cfg, unlimited: true }))
      .toBe(7);
  });
});
