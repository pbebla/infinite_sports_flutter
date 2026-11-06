// Keys-only reads + existence checks on the FantasyDb seam (scale fixes,
// D1/D2). shallowKeysOf parses a `?shallow=true` body in both RTDB shapes;
// childKeysOf prefers the db's childKeys and falls back to a full read —
// worst case exactly what the engine did before — with ONE warning; a
// season is never skipped because the shallow call failed.

import { describe, expect, it } from 'vitest';
import {
  childEntries, childKeysOf, shallowKeysOf, shallowUrl,
} from './orchestration_db';
import { FakeDb } from './test_support';

function spyLog() {
  const warns: Array<{ message: string; context?: Record<string, unknown> }> = [];
  return {
    warns,
    log: {
      info: () => undefined,
      warn: (message: string, context?: Record<string, unknown>) => {
        warns.push({ message, context });
      },
    },
  };
}

describe('shallowKeysOf', () => {
  it('reads an object body', () => {
    expect(shallowKeysOf({ '15': true, '16': true })).toEqual(['15', '16']);
  });

  it('reads a list-coerced array body, dropping null holes', () => {
    expect(shallowKeysOf([null, true, true])).toEqual(['1', '2']);
  });

  it('gives the same keys as childEntries for both shapes', () => {
    const asMap = { '15': true, '16': true };
    const asList = [...Array(15).fill(null), true, true];
    expect(shallowKeysOf(asMap)).toEqual(childEntries(asMap).map(([k]) => k));
    expect(shallowKeysOf(asList)).toEqual(childEntries(asList).map(([k]) => k));
    expect(shallowKeysOf(asList)).toEqual(['15', '16']);
  });

  it('is empty for null and for a non-container', () => {
    expect(shallowKeysOf(null)).toEqual([]);
    expect(shallowKeysOf(true)).toEqual([]);
  });
});

describe('childKeysOf', () => {
  const seed = () => ({
    Fantasy: { Futsal: { '15': { Config: { a: 1 } }, '16': { Config: { a: 1 } } } },
  });

  it('uses the db childKeys and never reads the node', async () => {
    const db = new FakeDb(seed());
    const { log, warns } = spyLog();
    expect(await childKeysOf(db, 'Fantasy/Futsal', log)).toEqual(['15', '16']);
    expect(db.reads).toEqual(['keys:Fantasy/Futsal']);
    expect(db.reads.some((r) => r.startsWith('read:'))).toBe(false);
    expect(warns).toEqual([]);
  });

  it('is empty for an absent node', async () => {
    const db = new FakeDb(seed());
    const { log } = spyLog();
    expect(await childKeysOf(db, 'Fantasy/Hockey', log)).toEqual([]);
  });

  it('falls back to a full read with exactly one warning when childKeys throws', async () => {
    const db = new FakeDb(seed());
    db.childKeys = async () => {
      throw new Error('shallow read: HTTP 503');
    };
    const { log, warns } = spyLog();
    expect(await childKeysOf(db, 'Fantasy/Futsal', log)).toEqual(['15', '16']);
    expect(db.reads).toEqual(['read:Fantasy/Futsal']);
    expect(warns).toHaveLength(1);
    expect(warns[0].message).toContain('fantasy keys: shallow read failed');
    expect(warns[0].context).toEqual({
      path: 'Fantasy/Futsal', error: 'shallow read: HTTP 503',
    });
  });

  it('falls back to the full-read keys, no warning, when the db has no childKeys', async () => {
    const db = new FakeDb(seed());
    db.childKeys = undefined;
    const { log, warns } = spyLog();
    expect(await childKeysOf(db, 'Fantasy/Futsal', log)).toEqual(['15', '16']);
    expect(db.reads).toEqual(['read:Fantasy/Futsal']);
    expect(warns).toEqual([]);
  });

  it('fallback sees list-coerced season nodes exactly like childEntries', async () => {
    const list = [...Array(15).fill(null), { Config: { a: 1 } }, { Config: { a: 1 } }];
    const db = new FakeDb({ Fantasy: { Futsal: list } });
    db.childKeys = undefined;
    const { log } = spyLog();
    expect(await childKeysOf(db, 'Fantasy/Futsal', log)).toEqual(['15', '16']);
  });

  it('a keys read that succeeds with no children is an empty list, not a fallback', async () => {
    const db = new FakeDb(seed());
    const { log, warns } = spyLog();
    expect(await childKeysOf(db, 'Fantasy/Futsal/15/Nothing', log)).toEqual([]);
    expect(db.reads).toEqual(['keys:Fantasy/Futsal/15/Nothing']);
    expect(warns).toEqual([]);
  });
});

describe('shallowUrl', () => {
  const DB_URL = 'https://infinite-sports-app.firebaseio.com';

  it('production: the database URL, the path, ?shallow=true, no credential', () => {
    expect(shallowUrl(DB_URL, 'Fantasy/Futsal')).toBe(
      'https://infinite-sports-app.firebaseio.com/Fantasy/Futsal.json?shallow=true');
    expect(shallowUrl(DB_URL, '/Fantasy/')).toBe(
      'https://infinite-sports-app.firebaseio.com/Fantasy.json?shallow=true');
  });

  it('emulator: http://<host>/<path>.json?ns=<namespace>&shallow=true', () => {
    expect(shallowUrl(DB_URL, 'Fantasy/Futsal', '127.0.0.1:9000')).toBe(
      'http://127.0.0.1:9000/Fantasy/Futsal.json?ns=infinite-sports-app&shallow=true');
  });

  it('emulator namespace is the URL subdomain (or its ns param), never the project id', () => {
    expect(shallowUrl(
      'https://my-ns-default-rtdb.europe-west1.firebasedatabase.app', 'A', 'localhost:9000',
    )).toBe('http://localhost:9000/A.json?ns=my-ns-default-rtdb&shallow=true');
    expect(shallowUrl('http://localhost:9000/?ns=other', 'A', 'localhost:9000'))
      .toBe('http://localhost:9000/A.json?ns=other&shallow=true');
  });

  it('encodes path segments', () => {
    expect(shallowUrl(DB_URL, 'Fantasy/A B')).toContain('/Fantasy/A%20B.json');
  });
});

describe('FakeDb.exists', () => {
  it('is true for a present node, false for absent and for an empty map', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': { History: { '1': { u1: { pts: 3 } }, '2': {} } } } },
    });
    expect(await db.exists('Fantasy/Futsal/15/History/1')).toBe(true);
    expect(await db.exists('Fantasy/Futsal/15/History/1/u1/pts')).toBe(true);
    expect(await db.exists('Fantasy/Futsal/15/History/3')).toBe(false);
    expect(await db.exists('Fantasy/Futsal/15/History/2')).toBe(false);
  });

  it('records exists:, read: and keys: in call order', async () => {
    const db = new FakeDb({ A: { B: { c: 1 } } });
    await db.exists('A/B');
    await db.read('A');
    await db.childKeys!('A');
    await db.exists('A/Z');
    expect(db.reads).toEqual(['exists:A/B', 'read:A', 'keys:A', 'exists:A/Z']);
  });

  it('a transaction or claim is not an engine read, and does not hide one', async () => {
    const db = new FakeDb({ A: { B: { c: 1 } } });
    await db.transaction('A/B', (cur) => cur);
    await db.writeIfAbsent('A/New', 1);
    expect(db.reads).toEqual([]);
    // A concurrent engine read started alongside a transaction is kept.
    const [, v] = await Promise.all([db.transaction('A/B', (cur) => cur), db.read('A/B')]);
    expect(v).toEqual({ c: 1 });
    expect(db.reads).toEqual(['read:A/B']);
  });
});
