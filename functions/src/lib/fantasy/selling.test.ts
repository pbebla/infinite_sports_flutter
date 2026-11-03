// The FPL selling rule (spec §4). The (purchase, current) -> sell table below
// is the SAME table as test/fantasy/selling_test.dart: the two twins must agree.
import { describe, expect, it } from 'vitest';
import { realizedOf, sellPriceTenths } from './selling';

// (purchase, current) -> sell, in tenths of $1M.
const SELL_TABLE: Array<[number, number, number]> = [
  [80, 90, 85],
  [80, 85, 82],
  [80, 81, 80],
  [80, 80, 80],
  [80, 70, 70],
  [40, 150, 95],
  [150, 40, 40],
];

describe('sellPriceTenths', () => {
  for (const [purchase, current, sell] of SELL_TABLE) {
    it(`(${purchase}, ${current}) -> ${sell}`, () => {
      expect(sellPriceTenths(purchase, current)).toBe(sell);
    });
  }
});

describe('realizedOf', () => {
  it('reads realizedTenths when it is a finite number', () => {
    expect(realizedOf({ realizedTenths: 5 })).toBe(5);
    expect(realizedOf({ realizedTenths: -12 })).toBe(-12);
    expect(realizedOf({ realizedTenths: 0 })).toBe(0);
  });
  it('truncates a fractional value toward zero', () => {
    expect(realizedOf({ realizedTenths: 5.9 })).toBe(5);
    expect(realizedOf({ realizedTenths: -5.9 })).toBe(-5);
  });
  it('is 0 for anything that is not a finite number', () => {
    expect(realizedOf(null)).toBe(0);
    expect(realizedOf(undefined)).toBe(0);
    expect(realizedOf('nope')).toBe(0);
    expect(realizedOf(7)).toBe(0);
    expect(realizedOf([])).toBe(0);
    expect(realizedOf({})).toBe(0);
    expect(realizedOf({ realizedTenths: '5' })).toBe(0);
    expect(realizedOf({ realizedTenths: null })).toBe(0);
    expect(realizedOf({ realizedTenths: NaN })).toBe(0);
    expect(realizedOf({ realizedTenths: Infinity })).toBe(0);
    expect(realizedOf({ realizedTenths: -Infinity })).toBe(0);
  });
});
