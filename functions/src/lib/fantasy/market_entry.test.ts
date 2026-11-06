// What a market entry starts with (season setup + schedule plan 2026-11-05,
// Task 6): the registration -> fantasy position mapping (port of
// tool/seed_fantasy_logic.dart), the position-average price, the Line Ups
// roster, and the carry-over of a returning player's last price + position.
// Task 7 (mid-season joiners) reuses every export.

import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import {
  loadCarryOver, mapRegistrationPosition, MarketEntry, marketEntriesOf,
  positionAveragePrice, rosterOf, signupPositionField,
} from './market_entry';
import { FakeDb } from './test_support';

const cfg = futsalDefault();

describe('mapRegistrationPosition (tool/seed_fantasy_logic.dart parity)', () => {
  it('maps the registration words', () => {
    expect(mapRegistrationPosition('Goal Keeper')).toBe('GK');
    expect(mapRegistrationPosition('Goalkeeper')).toBe('GK');
    expect(mapRegistrationPosition('keeper')).toBe('GK');
    expect(mapRegistrationPosition('GK')).toBe('GK');
    expect(mapRegistrationPosition('Defender')).toBe('DEF');
    expect(mapRegistrationPosition('defence')).toBe('DEF');
    expect(mapRegistrationPosition('D')).toBe('DEF');
    expect(mapRegistrationPosition('Midfielder')).toBe('ATT');
    expect(mapRegistrationPosition('Striker')).toBe('ATT');
  });

  it('the first listed position of a multi-select wins, whatever the separator', () => {
    expect(mapRegistrationPosition('Defender;Striker')).toBe('DEF');
    expect(mapRegistrationPosition('Goal Keeper:Defender:Midfielder')).toBe('GK');
    expect(mapRegistrationPosition('Striker, Goal Keeper')).toBe('ATT');
    expect(mapRegistrationPosition(';; Defender')).toBe('DEF');
  });

  it('missing, blank or unknown reads as ATT', () => {
    expect(mapRegistrationPosition(null)).toBe('ATT');
    expect(mapRegistrationPosition(undefined)).toBe('ATT');
    expect(mapRegistrationPosition('')).toBe('ATT');
    expect(mapRegistrationPosition('  ')).toBe('ATT');
    expect(mapRegistrationPosition('Winger')).toBe('ATT');
    expect(mapRegistrationPosition({ a: 1 })).toBe('ATT');
  });
});

describe('signupPositionField', () => {
  it('names the Users/<uid>/Information field per sport', () => {
    expect(signupPositionField('Futsal')).toBe('FutsalPosition');
    expect(signupPositionField('Basketball')).toBe('BasketballPosition');
    expect(signupPositionField('Flag Football')).toBe('FlagFootballPosition');
  });
});

describe('positionAveragePrice', () => {
  const entry = (position: MarketEntry['position'], priceTenths: number,
    eligible = true): MarketEntry => ({ position, priceTenths, eligible });

  it('is the mean of the position, snapped to the step (63 -> 65)', () => {
    const market = { a: entry('DEF', 60), b: entry('DEF', 66), c: entry('ATT', 120) };
    expect(positionAveragePrice(market, 'DEF', cfg)).toBe(65);
    expect(positionAveragePrice(market, 'ATT', cfg)).toBe(120);
  });

  it('rounds a fractional mean to the nearest tenth before snapping', () => {
    // mean 62.67 -> 63 -> 65 (not truncated down to 60)
    const market = { a: entry('DEF', 60), b: entry('DEF', 60), c: entry('DEF', 68) };
    expect(positionAveragePrice(market, 'DEF', cfg)).toBe(65);
  });

  it('only eligible entries count', () => {
    const market = { a: entry('DEF', 60), g: entry('DEF', 150, false) };
    expect(positionAveragePrice(market, 'DEF', cfg)).toBe(60);
  });

  it('excludeName leaves that entry out', () => {
    const market = { a: entry('DEF', 60), me: entry('DEF', 100) };
    expect(positionAveragePrice(market, 'DEF', cfg, 'me')).toBe(60);
  });

  it('no eligible entry of the position -> the rookie price', () => {
    expect(positionAveragePrice({}, 'GK', cfg)).toBe(60);
    expect(positionAveragePrice({ a: entry('DEF', 80) }, 'GK', cfg)).toBe(60);
    expect(positionAveragePrice({ me: entry('GK', 80) }, 'GK', cfg, 'me')).toBe(60);
  });

  it('never leaves the price range', () => {
    expect(positionAveragePrice({ a: entry('ATT', 400) }, 'ATT', cfg)).toBe(150);
    expect(positionAveragePrice({ a: entry('ATT', 5) }, 'ATT', cfg)).toBe(40);
  });
});

describe('marketEntriesOf (Task 7 reads the live market with it)', () => {
  it('parses name -> {position, priceTenths, eligible}, skipping unusable entries', () => {
    const parsed = marketEntriesOf({
      Ann: { position: 'DEF', priceTenths: 85, eligible: true, teamName: 'A' },
      Gus: { position: 'ATT', priceTenths: 60, eligible: false },
      Bad: { position: 'MID', priceTenths: 60, eligible: true },
      Junk: 'x',
    });
    expect(parsed).toEqual({
      Ann: { position: 'DEF', priceTenths: 85, eligible: true },
      Gus: { position: 'ATT', priceTenths: 60, eligible: false },
    });
    expect(marketEntriesOf(null)).toEqual({});
  });
});

describe('rosterOf (parseLineups parity)', () => {
  it('lists every real player with team and uid; Guest (any case) is out', () => {
    const rows = rosterOf({
      'Team A': {
        Ann: { UID: 'u1', Goals: 3 },
        Bob: { UID: '' },
        Guest: { Goals: 1 },
        guest: { UID: 'u9' },
        ' GUEST ': { UID: 'u8' },
      },
      'Team B': { Cy: { UID: '0' }, Dee: { UID: ' u4 ' }, Eve: {} },
    });
    expect(rows).toEqual([
      { name: 'Ann', team: 'Team A', uid: 'u1' },
      { name: 'Bob', team: 'Team A', uid: null },
      { name: 'Cy', team: 'Team B', uid: null },
      { name: 'Dee', team: 'Team B', uid: 'u4' },
      { name: 'Eve', team: 'Team B', uid: null },
    ]);
  });

  it('tolerates junk: non-map teams and players are skipped, a null node is empty', () => {
    expect(rosterOf(null)).toEqual([]);
    expect(rosterOf('x')).toEqual([]);
    expect(rosterOf({ T: 'x', U: { Ann: 'x', Bob: { UID: 5 } } })).toEqual([
      { name: 'Bob', team: 'U', uid: '5' },
    ]);
  });
});

describe('loadCarryOver', () => {
  const players = (m: Record<string, unknown>) => m;

  it('a returning player keeps the newest earlier season\'s price and position', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: {
        14: { Players: players({ Ann: { position: 'ATT', priceTenths: 50, eligible: true } }) },
        15: { Players: players({ Ann: { position: 'DEF', priceTenths: 85, eligible: true } }) },
      } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Ann', null)).toEqual({ priceTenths: 85, position: 'DEF', season: '15' });
  });

  it('a player who sat out the newest season comes back at the older price', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: {
        14: { Players: players({ Bob: { position: 'GK', priceTenths: 70, eligible: true } }) },
        15: { Players: players({ Ann: { position: 'DEF', priceTenths: 85, eligible: true } }) },
      } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Bob', null)).toEqual({ priceTenths: 70, position: 'GK', season: '14' });
  });

  it('matches names trimmed and case-insensitively', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { 15: { Players: players({
        'Ann Lee': { position: 'DEF', priceTenths: 85, eligible: true },
      }) } } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('  ann lee ', null)?.priceTenths).toBe(85);
    expect(carry('Ann Li', null)).toBeNull();
  });

  it('a uid match beats a renamed entry (via that season\'s Line Ups)', async () => {
    const db = new FakeDb({
      Futsal: { 15: { 'Line Ups': { T: { Bob: { UID: 'u2' } } } } },
      Fantasy: { Futsal: { 15: { Players: players({
        Bob: { position: 'DEF', priceTenths: 70, eligible: true },
      }) } } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Robert', 'u2')).toEqual({ priceTenths: 70, position: 'DEF', season: '15' });
    expect(carry('Robert', 'u3')).toBeNull();
    expect(carry('Robert', null)).toBeNull();
  });

  it('a uid match also works through a Players `uid` field', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { 15: { Players: players({
        Bob: { position: 'DEF', priceTenths: 70, eligible: true, uid: 'u2' },
      }) } } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Robert', 'u2')?.priceTenths).toBe(70);
  });

  it('a newer season\'s name match beats an older season\'s uid match when the newer entry has no conflicting uid', async () => {
    const db = new FakeDb({
      Futsal: { 14: { 'Line Ups': { T: { Ben: { UID: 'u7' } } } } },
      Fantasy: { Futsal: {
        14: { Players: players({ Ben: { position: 'DEF', priceTenths: 80, eligible: true } }) },
        15: { Players: players({ ben: { position: 'GK', priceTenths: 100, eligible: true } }) },
      } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    // Season 15 is checked first: no uid match there, and its 'ben' carries no
    // uid of its own, so the name match wins over season 14's uid match.
    expect(carry('Ben', 'u7')).toEqual({ priceTenths: 100, position: 'GK', season: '15' });
    expect(carry('Ben', null)?.season).toBe('15');
  });

  it('within one season the uid match beats a same-name entry of another uid', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { 15: { Players: players({
        Ben: { position: 'GK', priceTenths: 100, eligible: true, uid: 'u1' },
        'Ben R': { position: 'DEF', priceTenths: 80, eligible: true, uid: 'u7' },
      }) } } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Ben', 'u7')).toEqual({ priceTenths: 80, position: 'DEF', season: '15' });
  });

  it('a same-name entry linked to a different uid is not matched (namesake)', async () => {
    const db = new FakeDb({
      Futsal: { 15: { 'Line Ups': { T: { Cal: { UID: 'u1' } } } } },
      Fantasy: { Futsal: { 15: { Players: players({
        Ben: { position: 'GK', priceTenths: 100, eligible: true, uid: 'u1' },
        Cal: { position: 'DEF', priceTenths: 90, eligible: true }, // linked via Line Ups
        Dee: { position: 'ATT', priceTenths: 70, eligible: true },
      }) } } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Ben', 'u2')).toBeNull(); // a different Ben
    expect(carry('Cal', 'u2')).toBeNull(); // linked through that season's Line Ups
    expect(carry('Ben', 'u1')?.priceTenths).toBe(100); // the same Ben
    expect(carry('Ben', null)?.priceTenths).toBe(100); // no uid to contradict it
    expect(carry('Dee', 'u2')?.priceTenths).toBe(70); // an unlinked entry is no namesake
  });

  it('a namesake in a newer season is skipped: the older season decides', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: {
        14: { Players: players({ Ben: { position: 'DEF', priceTenths: 60, eligible: true } }) },
        15: { Players: players({
          Ben: { position: 'GK', priceTenths: 100, eligible: true, uid: 'u1' },
        }) },
      } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    // 15: this Ben is another uid's (skip). 14: an unlinked 'Ben' -> match.
    expect(carry('Ben', 'u2')).toEqual({ priceTenths: 60, position: 'DEF', season: '14' });
    // The real u1 is still found in 15.
    expect(carry('Ben', 'u1')?.season).toBe('15');
  });

  it('only seasons below the one being started count, and only with a Players node', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: {
        15: { Config: { lockHour: 15 } }, // no Players: does not count
        16: { Players: players({ Ann: { position: 'DEF', priceTenths: 99, eligible: true } }) },
        17: { Players: players({ Ann: { position: 'DEF', priceTenths: 98, eligible: true } }) },
      } },
    });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    expect(carry('Ann', null)).toBeNull();
  });

  it('a non-numeric season has no earlier seasons', async () => {
    const db = new FakeDb({ Fantasy: { Futsal: { 15: { Players: players({
      Ann: { position: 'DEF', priceTenths: 85, eligible: true },
    }) } } } });
    expect((await loadCarryOver(db, 'Futsal', 'spring'))('Ann', null)).toBeNull();
  });

  it('skips unusable entries (bad position, no positive price)', async () => {
    const db = new FakeDb({ Fantasy: { Futsal: { 15: { Players: players({
      A: { position: 'MID', priceTenths: 85, eligible: true },
      B: { position: 'DEF', priceTenths: 0, eligible: true },
      C: { position: 'DEF', eligible: true },
      D: 'junk',
    }) } } } });
    const carry = await loadCarryOver(db, 'Futsal', '16');
    for (const n of ['A', 'B', 'C', 'D']) expect(carry(n, null)).toBeNull();
  });

  it('a failed read throws — never an empty carry-over', async () => {
    const db = new FakeDb({ Fantasy: { Futsal: { 15: { Players: { A: {} } } } } });
    db.read = async (path: string) => {
      if (path === 'Fantasy/Futsal/15/Players') throw new Error('boom');
      return null;
    };
    await expect(loadCarryOver(db, 'Futsal', '16')).rejects.toThrow('boom');
  });
});
