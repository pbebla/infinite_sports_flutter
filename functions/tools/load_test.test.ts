// The read meter of the load test (load_test.ts): what it counts, how it
// names paths, how it summarizes. The replay itself is exercised by running
// `npm run loadtest`, not here.
import { describe, expect, it } from 'vitest';
import { FantasyDb } from '../src/lib/fantasy/orchestration_db';
import {
  collapsePath, countingDb, EXISTS_BYTES, percentile, ReadMeter, summarize,
} from './load_test';

/** A db that answers from a path -> value table and remembers what it was
 *  asked and what was written. */
function stubDb(values: Record<string, unknown>, withChildKeys = false) {
  const log: string[] = [];
  const db: FantasyDb = {
    read: async (p) => { log.push(`read:${p}`); return values[p] ?? null; },
    exists: async (p) => { log.push(`exists:${p}`); return values[p] != null; },
    write: async (p, v) => { log.push(`write:${p}=${JSON.stringify(v)}`); },
    writeIfAbsent: async (p) => { log.push(`writeIfAbsent:${p}`); return true; },
    transaction: async (p, update) => {
      log.push(`transaction:${p}`);
      return { committed: true, value: update(values[p] ?? null) };
    },
    ...(withChildKeys
      ? { childKeys: async (p: string) => { log.push(`childKeys:${p}`); return ['x', 'y']; } }
      : {}),
  };
  return { db, log };
}

const bytes = (v: unknown) => Buffer.byteLength(JSON.stringify(v));

describe('collapsePath', () => {
  it('drops the season prefix and collapses week numbers and manager uids', () => {
    expect(collapsePath('Fantasy/Futsal/15/History/3/load-0042')).toBe('History/<n>/<uid>');
    expect(collapsePath('Fantasy/Futsal/15/LockedWeeks/12')).toBe('LockedWeeks/<n>');
    expect(collapsePath('Fantasy/Futsal/15/Squads/test-07')).toBe('Squads/<uid>');
    expect(collapsePath('Fantasy/Futsal/15/Config')).toBe('Config');
    expect(collapsePath('Futsal/Futsal Season')).toBe('Futsal/Futsal Season');
  });

  it('leaves the discovery paths readable', () => {
    expect(collapsePath('Fantasy')).toBe('Fantasy');
    expect(collapsePath('Fantasy/Futsal')).toBe('Fantasy/Futsal');
    expect(collapsePath('Fantasy/Futsal/15')).toBe('Fantasy/Futsal/<n>');
    expect(collapsePath('/Fantasy/')).toBe('Fantasy');
  });
});

describe('countingDb', () => {
  it('counts a read as the JSON bytes of what came back, and returns it untouched', async () => {
    const node = { a: 1, b: ['xé', null] };
    const { db } = stubDb({ 'Fantasy/Futsal/15/Players': node });
    const meter = new ReadMeter();
    const counted = meter.wrap(db, new Date(0));
    expect(await counted.read('Fantasy/Futsal/15/Players')).toBe(node);
    expect(await counted.read('Fantasy/Futsal/15/Absent')).toBeNull();
    expect(meter.sweeps[0].bytes).toBe(bytes(node)); // the absent read costs 0
    expect(meter.sweeps[0].wholeFantasyReads).toBe(0);
  });

  it('flags only a read of the whole Fantasy node, counts its bytes, and names it read:Fantasy', async () => {
    const whole = { Futsal: { 15: { Config: { x: 1 } } } };
    const { db } = stubDb({ Fantasy: whole, '/Fantasy/': whole, 'Fantasy/Futsal': whole.Futsal });
    const meter = new ReadMeter();
    const counted = meter.wrap(db, new Date(0));
    await counted.read('Fantasy/Futsal');
    expect(meter.sweeps[0].wholeFantasyReads).toBe(0);
    await counted.read('Fantasy');
    await counted.read('/Fantasy/');
    expect(meter.sweeps[0].wholeFantasyReads).toBe(2);
    expect(meter.sweeps[0].bytes).toBe(bytes(whole.Futsal) + 2 * bytes(whole));
    expect(meter.byPath.get('read:Fantasy')?.bytes).toBe(2 * bytes(whole));
  });

  it('counts exists as about 1 KB, however big the node is', async () => {
    const { db } = stubDb({ 'Fantasy/Futsal/15/History/4': { big: 'x'.repeat(50_000) } });
    const meter = new ReadMeter();
    const counted = meter.wrap(db, new Date(0));
    expect(await counted.exists('Fantasy/Futsal/15/History/4')).toBe(true);
    expect(await counted.exists('Fantasy/Futsal/15/History/5')).toBe(false);
    expect(EXISTS_BYTES).toBe(1024);
    expect(meter.sweeps[0].bytes).toBe(2 * 1024);
    expect(meter.byPath.get('exists:History/<n>')).toEqual({ bytes: 2048, calls: 2 });
  });

  it('childKeys: the keys array JSON, not the node, even on a db without childKeys (and list-coerced nodes)', async () => {
    const big = { Futsal: { 15: { s: 'x'.repeat(40_000) }, 16: { s: 'y'.repeat(40_000) } }, BadgeCatalog: { a: 1 } };
    const arrayNode = [null, { s: 1 }, { s: 2 }];
    const { db, log } = stubDb({ Fantasy: big, 'Fantasy/Futsal/15/Weeks': arrayNode });
    expect(db.childKeys).toBeUndefined();
    const meter = new ReadMeter();
    const counted = meter.wrap(db, new Date(0));
    // The wrapper offers childKeys (production's db has it), so the engine
    // takes the keys path instead of a full read.
    expect(typeof counted.childKeys).toBe('function');
    expect(await counted.childKeys!('Fantasy')).toEqual(['Futsal', 'BadgeCatalog']);
    expect(await counted.childKeys!('Fantasy/Futsal/15/Weeks')).toEqual(['1', '2']);
    expect(meter.sweeps[0].bytes).toBe(bytes(['Futsal', 'BadgeCatalog']) + bytes(['1', '2']));
    expect(meter.sweeps[0].wholeFantasyReads).toBe(0);
    expect(log).toEqual(['read:Fantasy', 'read:Fantasy/Futsal/15/Weeks']); // the keys came from the underlying db
  });

  it('childKeys goes through the db own childKeys when it has one', async () => {
    const { db, log } = stubDb({}, true);
    const meter = new ReadMeter();
    const counted = meter.wrap(db, new Date(0));
    expect(await counted.childKeys!('Fantasy/Futsal')).toEqual(['x', 'y']);
    expect(log).toEqual(['childKeys:Fantasy/Futsal']);
    expect(meter.sweeps[0].bytes).toBe(bytes(['x', 'y']));
  });

  it('writes, writeIfAbsent and transactions pass straight through, uncounted', async () => {
    const { db, log } = stubDb({ 'Fantasy/Futsal/15/Live': { k: 1 } });
    const meter = new ReadMeter();
    const counted = meter.wrap(db, new Date(0));
    await counted.write('a/b', 5);
    expect(await counted.writeIfAbsent('a/c', 1)).toBe(true);
    const res = await counted.transaction('Fantasy/Futsal/15/Live', (cur) => ({ ...(cur as object), z: 1 }));
    expect(res).toEqual({ committed: true, value: { k: 1, z: 1 } });
    expect(log).toEqual(['write:a/b=5', 'writeIfAbsent:a/c', 'transaction:Fantasy/Futsal/15/Live']);
    expect(meter.sweeps[0].bytes).toBe(0);
  });

  it('countingDb on its own writes into the record it is given', async () => {
    const { db } = stubDb({ 'Fantasy/Futsal/15/Config': { a: 1 } });
    const rec = { at: 'x', bytes: 0, wholeFantasyReads: 0 };
    const byPath = new Map<string, { bytes: number; calls: number }>();
    await countingDb(db, rec, byPath).read('Fantasy/Futsal/15/Config');
    expect(rec.bytes).toBe(bytes({ a: 1 }));
    expect(byPath.get('read:Config')).toEqual({ bytes: bytes({ a: 1 }), calls: 1 });
  });
});

describe('ReadMeter + summarize', () => {
  it('starts a fresh record per sweep, stamped with the sweep time', async () => {
    const { db } = stubDb({ 'Fantasy/Futsal/15/Config': { a: 1 } });
    const meter = new ReadMeter();
    const first = meter.wrap(db, new Date('2026-10-01T00:15:00Z'));
    await first.read('Fantasy/Futsal/15/Config');
    const second = meter.wrap(db, new Date('2026-10-01T00:30:00Z'));
    await second.exists('Fantasy/Futsal/15/Config');
    expect(meter.sweeps.map((s) => [s.at, s.bytes])).toEqual([
      ['2026-10-01T00:15:00.000Z', bytes({ a: 1 })],
      ['2026-10-01T00:30:00.000Z', 1024],
    ]);
  });

  it('percentile is nearest-rank on sorted values', () => {
    expect(percentile([], 0.5)).toBe(0);
    expect(percentile([5], 0.95)).toBe(5);
    const v = Array.from({ length: 100 }, (_, i) => i + 1);
    expect(percentile(v, 0.5)).toBe(50);
    expect(percentile(v, 0.95)).toBe(95);
    expect(percentile(v, 1)).toBe(100);
    expect(percentile([1, 2, 3, 4], 0.5)).toBe(2);
  });

  it('summarize: per-sweep MB median/p95/max, whole-Fantasy reads, top paths, verdict', () => {
    const MB = 1_048_576;
    const meter = new ReadMeter();
    meter.sweeps.push(
      { at: 'a', bytes: 1 * MB, wholeFantasyReads: 0 },
      { at: 'b', bytes: 3 * MB, wholeFantasyReads: 0 },
      { at: 'c', bytes: 2 * MB, wholeFantasyReads: 0 },
    );
    meter.byPath.set('read:Squads', { bytes: 5 * MB, calls: 3 });
    meter.byPath.set('read:Config', { bytes: 100, calls: 9 });
    const ok = summarize(250, { crashes: 0, invariantFailures: 0, ledgerMismatches: 0 }, meter);
    expect(ok.report).toEqual({
      managers: 250, crashes: 0, invariantFailures: 0, ledgerMismatches: 0, sweeps: 3,
      wholeFantasyReads: 0,
      perSweepMB: { median: 2, p95: 3, max: 3 },
      topPaths: [
        { path: 'read:Squads', MB: 5, calls: 3 },
        { path: 'read:Config', MB: 0, calls: 9 },
      ],
    });
    expect(ok.failed).toBe(false);

    meter.sweeps[1].wholeFantasyReads = 2;
    const whole = summarize(250, { crashes: 0, invariantFailures: 0, ledgerMismatches: 0 }, meter);
    expect(whole.report.wholeFantasyReads).toBe(2);
    expect(whole.failed).toBe(true);
    expect(summarize(250, { crashes: 1, invariantFailures: 0, ledgerMismatches: 0 }, new ReadMeter()).failed).toBe(true);
    expect(summarize(250, { crashes: 0, invariantFailures: 3, ledgerMismatches: 0 }, new ReadMeter()).failed).toBe(true);
    // A ledger mismatch is reported, not a gate (the fill tool treats it the same way).
    expect(summarize(250, { crashes: 0, invariantFailures: 0, ledgerMismatches: 4 }, new ReadMeter()).failed).toBe(false);
  });

  it('topPaths keeps only the biggest N', () => {
    const meter = new ReadMeter();
    for (let i = 0; i < 20; i++) meter.byPath.set(`read:P${i}`, { bytes: (i + 1) * 1_048_576, calls: 1 });
    const { report } = summarize(1, { crashes: 0, invariantFailures: 0, ledgerMismatches: 0 }, meter, 5);
    expect(report.topPaths.map((p) => p.path)).toEqual(['read:P19', 'read:P18', 'read:P17', 'read:P16', 'read:P15']);
  });
});
