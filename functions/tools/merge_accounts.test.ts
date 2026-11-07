import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { maskEmail } from '../src/lib/mask_email';
import {
  applyMerge, BACKUP_KIND, checkTargetFlags, DB_URL, dryRun, findDupes, guardRest, HintLookup,
  installReadOnlyFetchGuard, loadMap, LOOKUP_URL, parseArgs, readMergeSnapshot, resolveTarget,
  Rest, RunDeps, Target, undoMerge,
} from './merge_accounts';
import { MergeMap } from './merge_accounts_logic';

// ── in-memory RTDB-like REST stub (no network) ─────────────────────────────

const isMap = (v: unknown): v is Record<string, any> => v !== null && typeof v === 'object' && !Array.isArray(v);
const clone = <T>(v: T): T => (v === undefined ? v : JSON.parse(JSON.stringify(v)));

class MemDb implements Rest {
  calls: Array<{ method: string; path: string; shallow?: boolean }> = [];
  onPut?: (p: string, v: unknown) => void;
  constructor(public root: Record<string, any>) {}
  async get(p: string, o?: { shallow?: boolean }): Promise<unknown> {
    this.calls.push({ method: 'GET', path: p, shallow: o?.shallow === true });
    let cur: unknown = this.root;
    for (const seg of p.split('/')) {
      if (!isMap(cur)) return null;
      cur = cur[seg];
    }
    if (cur === undefined || cur === null) return null;
    if (o?.shallow && isMap(cur)) return Object.fromEntries(Object.keys(cur).map((k) => [k, true]));
    return clone(cur);
  }
  async put(p: string, v: unknown): Promise<void> {
    this.calls.push({ method: 'PUT', path: p });
    this.set(p, clone(v));
    this.onPut?.(p, v);
  }
  async del(p: string): Promise<void> {
    this.calls.push({ method: 'DELETE', path: p });
    this.set(p, null);
  }
  /** RTDB semantics: null removes, and parents left empty vanish. */
  set(p: string, v: unknown): void {
    const segs = p.split('/');
    const chain: Array<Record<string, any>> = [this.root];
    let cur = this.root;
    for (const s of segs.slice(0, -1)) {
      if (!isMap(cur[s])) {
        if (v === null) return;
        cur[s] = {};
      }
      cur = cur[s];
      chain.push(cur);
    }
    const last = segs[segs.length - 1];
    if (v === null) delete cur[last];
    else cur[last] = v;
    for (let i = chain.length - 1; i > 0; i--) {
      if (Object.keys(chain[i]).length > 0) break;
      delete chain[i - 1][segs[i - 1]];
    }
  }
  writes(): Array<{ method: string; path: string }> {
    return this.calls.filter((c) => c.method !== 'GET');
  }
}

// ── fixture shaped like the audit ──────────────────────────────────────────

const EMAILS: Record<string, string> = {
  keepA: 'hiram.alvarez.real@gmail.com',
  oldA: 'hiram.old.addr@yahoo.com',
  keepB: 'carlo11rocks@gmail.com',
  oldB: 'carlo.first@hotmail.com',
  keepC: 'robert.s@outlook.com',
};

function fixture(): Record<string, any> {
  return {
    Users: {
      keepA: {
        'First Name': 'Hiram', 'Last Name': 'Alvarez', Email: EMAILS.keepA, Token: 'tok-keepA',
        Played: { Futsal: { 'Season 15': 'Ashur' } }, Information: { Position: 'Defender' },
      },
      oldA: {
        'First Name': 'Hiram', 'Last Name': 'A', Email: EMAILS.oldA, Token: 'tok-oldA', Phone: '555-0100',
        Played: { Futsal: { 'Season 11': 'Nineveh' } }, ProfileUrl: 'https://storage.example/oldA.jpg',
        Information: { Position: 'Forward', Jersey: 7, Phone: '555-0100' },
      },
      keepB: { 'First Name': 'Carlo', 'Last Name': 'Gewargis', Email: EMAILS.keepB },
      oldB: { 'First Name': 'Carlo', 'Last Name': 'Gewargis', Email: EMAILS.oldB },
      keepC: { 'First Name': 'Rabert', 'Last Name': 'Shamoeilzadeh', Email: EMAILS.keepC },
      subOwn: { 'First Name': 'Ninos', 'Last Name': 'Own', Email: 'ninos@example.com' },
      subNone: { 'First Name': 'Nobody', 'Last Name': 'Here', Email: 'nobody@example.com' },
      subNoName: { Email: 'anon@example.com' },
    },
    Futsal: {
      Settings: { Ignored: true },
      '10': { 'Line Ups': { Nineveh: { 'Robert Shamoelzadeh': { Goals: 1 }, 'Robben Tatari': { Goals: 2 } } } },
      '11': { 'Line Ups': { Nineveh: { 'Hiram A': { UID: 'oldA', Goals: 3 } } } },
      '15': { 'Line Ups': { Ashur: { 'Hiram Alvarez': { UID: 'keepA', Goals: 4 }, 'Ninos Own': { UID: 'subOwn' } } } },
    },
    Basketball: { '3': { 'Line Ups': { Hoopers: { 'Hiram A': { UID: 'someoneElse' } } } } },
    'AFC San Jose': { Seasons: { 'Spring 2025': { Roster: { 'Carlo G': { UID: 'oldB', Number: 9 } } } } },
    Fantasy: { Futsal: { '15': { Config: { lockOverride: 'open' } } } },
    PublicProfiles: { oldA: { 'First Name': 'Hiram' }, oldB: { 'First Name': 'Carlo' }, keepA: { 'First Name': 'Hiram' } },
    Registrations: {
      'Futsal-16': {
        Config: { TargetType: 'league', Sport: 'Futsal', Season: '16' },
        Submissions: {
          keepA: { Answers: { email: EMAILS.keepA, phone: '555-0199' } },
          keepC: { Answers: { email: EMAILS.keepC } },
          subOwn: { Answers: { email: 'ninos@example.com' } },
          subNone: { Answers: { email: 'nobody@example.com' } },
          subNoName: { Answers: { email: 'anon@example.com' } },
        },
      },
    },
  };
}

const MAP: MergeMap = {
  clusters: [
    { who: 'Hiram Alvarez', keep: 'keepA', old: ['oldA'] },
    { who: 'Carlo Gewargis', keep: 'keepB', old: ['oldB'] },
    {
      who: 'Robert Shamoeilzadeh', keep: 'keepC', old: [],
      nameRows: [{ sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Robert Shamoelzadeh' }],
      firstNameFix: 'Robert',
    },
  ],
};

const hints: HintLookup = async (uids) =>
  Object.fromEntries(uids.filter((u) => EMAILS[u]).map((u) => [u, maskEmail(EMAILS[u])]));

const PROD: Target = { kind: 'production', base: DB_URL, query: '', label: 'PRODUCTION' };
const EMU: Target = { kind: 'emulator', base: 'http://127.0.0.1:9000', query: 'ns=x', label: 'EMULATOR' };

let outDir: string;
beforeEach(() => { outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'merge-accounts-test-')); });
afterEach(() => { fs.rmSync(outDir, { recursive: true, force: true }); });

function deps(db: MemDb, over: Partial<RunDeps> = {}): RunDeps & { lines: string[] } {
  const lines: string[] = [];
  return {
    rest: db, hints, log: (l) => lines.push(l), now: () => 1_762_400_000_000,
    sleep: async () => undefined, outDir, target: PROD, lines, ...over,
  };
}

/** The mirror function's effect: a stamped MergedInto drops PublicProfiles. */
function withMirror(db: MemDb): MemDb {
  db.onPut = (p, v) => {
    const m = /^Users\/([^/]+)\/MergedInto$/.exec(p);
    if (m && typeof v === 'string') db.set(`PublicProfiles/${m[1]}`, null);
  };
  return db;
}

const noPublic = (root: Record<string, any>): Record<string, any> => {
  const c = clone(root);
  delete c.PublicProfiles;
  return c;
};

const RAW_EMAIL_RE = /[A-Za-z0-9._-]{3,}@/;

// ── snapshot + dry run ─────────────────────────────────────────────────────

describe('readMergeSnapshot (the planner contract)', () => {
  it('carries Users nodes, old-uid UID leaves (league + AFC), the name row NODE and Config checks', async () => {
    const db = new MemDb(fixture());
    const { snap, stats } = await readMergeSnapshot(guardRest(db, { readOnly: true }), MAP, hints);
    expect(Object.keys(snap.nodes).filter((k) => k.startsWith('Users/')).sort())
      .toEqual(['Users/keepA', 'Users/keepB', 'Users/keepC', 'Users/oldA', 'Users/oldB']);
    expect(snap.nodes['Futsal/11/Line Ups/Nineveh/Hiram A/UID']).toBe('oldA');
    expect(snap.nodes['AFC San Jose/Seasons/Spring 2025/Roster/Carlo G/UID']).toBe('oldB');
    expect(snap.nodes['Futsal/10/Line Ups/Nineveh/Robert Shamoelzadeh']).toEqual({ Goals: 1 });
    expect(snap.nodes).not.toHaveProperty('Futsal/10/Line Ups/Nineveh/Robert Shamoelzadeh/UID');
    // null = checked and absent; the fantasy season 15 is not touched.
    expect(snap.nodes['Fantasy/Futsal/11/Config']).toBeNull();
    expect(snap.nodes['Fantasy/Futsal/10/Config']).toBeNull();
    expect(snap.nodes).not.toHaveProperty('Fantasy/Futsal/15/Config');
    // the Basketball row held by an unrelated account is not ours.
    expect(Object.keys(snap.nodes).some((k) => k.startsWith('Basketball/'))).toBe(false);
    expect(snap.keptHints.keepB).toBe(maskEmail(EMAILS.keepB));
    expect(stats.seasons).toEqual({ Futsal: 3, Basketball: 1, 'Flag Football': 0, 'AFC San Jose': 1 });
  });
});

describe('dry run', () => {
  it('reads only, prints the plan + digest and never a raw email or uid', async () => {
    const db = new MemDb(fixture());
    const d = deps(db);
    const { plan, digest } = await dryRun(MAP, d);
    expect(db.writes()).toEqual([]);
    expect(plan.refusals).toEqual([]);
    const out = d.lines.join('\n');
    expect(out).toContain('DRY RUN - nothing was written.');
    expect(out).toContain('Hiram Alvarez: relink Futsal Season 11, Nineveh, "Hiram A"');
    expect(out).toContain('Robert Shamoeilzadeh: fix the kept account\'s first name');
    expect(out).toContain(`--apply --expect-plan ${digest}`);
    expect(out).not.toMatch(RAW_EMAIL_RE);
    expect(out).not.toMatch(/keepA|oldA|keepB|oldB|keepC|tok-/);
  });

  it('a whole-tree or Submissions-body read is refused by the read rules', async () => {
    const db = new MemDb(fixture());
    const ro = guardRest(db, { readOnly: true });
    await expect(ro.get('Users')).rejects.toThrow(/not a path the merge tool reads/);
    await expect(ro.get('Registrations/Futsal-16/Submissions')).rejects.toThrow(/only its keys/);
    await expect(ro.put('Users/keepA/MergedInto', 'x')).rejects.toThrow(/read-only client/);
    await expect(ro.del('Users/keepA')).rejects.toThrow(/read-only client/);
    expect(db.calls).toEqual([]);
  });

  it('a write client refuses any path not on its allowlist', async () => {
    const db = new MemDb(fixture());
    const w = guardRest(db, { readOnly: false, allowedWrites: new Set(['Users/oldA/MergedInto']) });
    await expect(w.put('Users/oldA/Token', 'x')).rejects.toThrow(/not on this run's merge allowlist/);
    await w.put('Users/oldA/MergedInto', 'keepA');
    expect(db.writes()).toEqual([{ method: 'PUT', path: 'Users/oldA/MergedInto' }]);
  });
});

// ── apply / undo ───────────────────────────────────────────────────────────

describe('apply + undo', () => {
  it('backup/undo round trip: apply writes the plan, undo restores every path verbatim', async () => {
    const before = fixture();
    const db = withMirror(new MemDb(fixture()));
    const d = deps(db);
    const r = await applyMerge(MAP, d, { canary: true });
    expect(r.ok).toBe(true);
    expect(r.applied).toEqual(['Hiram Alvarez', 'Carlo Gewargis', 'Robert Shamoeilzadeh']);
    const u = db.root.Users;
    expect(db.root.Futsal['11']['Line Ups'].Nineveh['Hiram A']).toEqual({ UID: 'keepA', Goals: 3 });
    expect(db.root['AFC San Jose'].Seasons['Spring 2025'].Roster['Carlo G'].UID).toBe('keepB');
    expect(db.root.Futsal['10']['Line Ups'].Nineveh['Robert Shamoelzadeh']).toEqual({ Goals: 1, UID: 'keepC' });
    expect(u.keepA.Played.Futsal).toEqual({ 'Season 15': 'Ashur', 'Season 11': 'Nineveh' });
    expect(u.keepA.ProfileUrl).toBe('https://storage.example/oldA.jpg');
    expect(u.keepA.Information).toEqual({ Position: 'Defender', Jersey: 7 });
    expect(u.keepC['First Name']).toBe('Robert');
    expect(u.oldA.MergedInto).toBe('keepA');
    expect(u.oldA.MergedHint).toBe(maskEmail(EMAILS.keepA));
    expect(u.oldA.MergedAt).toBe(1_762_400_000_000);
    expect(u.oldA.Played).toEqual(before.Users.oldA.Played); // D5: the old record is untouched
    expect(d.lines.join('\n')).toMatch(/canary passed/);

    const backup = JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8'));
    expect(backup.kind).toBe(BACKUP_KIND);
    expect(backup.entries.every((e: { attempted: boolean }) => e.attempted)).toBe(true);
    expect(JSON.stringify(backup)).not.toMatch(RAW_EMAIL_RE);

    // A second apply writes nothing (Review Focus 3).
    const again = deps(db, { now: () => 1_762_400_100_000 });
    const n = db.writes().length;
    const r2 = await applyMerge(MAP, again, { canary: true });
    expect(r2.writes).toBe(0);
    expect(db.writes().length).toBe(n);

    const und = await undoMerge(r.backupFile as string, deps(db));
    expect(und).toEqual({ ok: true, restored: backup.entries.length, alreadyBefore: 0, leftAlone: [] });
    expect(noPublic(db.root)).toEqual(noPublic(before));
    // Stamps are undone first (reverse order).
    const undoWrites = db.writes().slice(n);
    expect(undoWrites[0].path).toMatch(/^Users\/keepC\/|^Futsal\/10\//);
    expect(undoWrites.find((w) => w.path === 'Users/oldA/MergedInto')).toBeDefined();
  });

  it('a target that changed since the plan refuses that cluster only (Review Focus 1)', async () => {
    const before = fixture();
    const db = withMirror(new MemDb(fixture()));
    const d = deps(db, {
      afterPlan: () => { db.set('Futsal/11/Line Ups/Nineveh/Hiram A/UID', 'managerLinkedSomeoneElse'); },
    });
    const r = await applyMerge(MAP, d, { canary: true });
    expect(r.ok).toBe(false);
    expect(r.refusedAtApply).toEqual(['Hiram Alvarez']);
    expect(r.applied).toEqual(['Carlo Gewargis', 'Robert Shamoeilzadeh']);
    expect(d.lines.join('\n')).toContain(
      'Hiram Alvarez: REFUSED at apply - changed since the plan: roster Futsal Season 11, Nineveh, "Hiram A"');
    expect(db.root.Users.keepA).toEqual(before.Users.keepA);
    expect(db.root.Users.oldA).toEqual(before.Users.oldA);
    expect(db.writes().some((w) => w.path.includes('keepA') || w.path.includes('oldA') || w.path.startsWith('Futsal/11'))).toBe(false);

    // The undo never touches (or even weighs) the refused cluster's paths.
    const u = await undoMerge(r.backupFile as string, deps(db));
    expect(u.leftAlone).toEqual([]);
    expect(u.ok).toBe(true);
    expect(db.root.Futsal['11']['Line Ups'].Nineveh['Hiram A'].UID).toBe('managerLinkedSomeoneElse');
    expect(db.root.Users.keepB).toEqual(before.Users.keepB);
    expect(db.root.Users.keepC).toEqual(before.Users.keepC);
  });

  it('a fantasy Config that appeared since the plan refuses the cluster (D2 re-checked)', async () => {
    const db = withMirror(new MemDb(fixture()));
    const d = deps(db, { afterPlan: () => { db.set('Fantasy/Futsal/11/Config', { lockOverride: 'open' }); } });
    const r = await applyMerge(MAP, d, { canary: true });
    expect(r.refusedAtApply).toEqual(['Hiram Alvarez']);
    expect(d.lines.join('\n')).toContain('Futsal Season 11 now has a fantasy Config');
  });

  it('the canary stops the run when PublicProfiles/<old> stays (Review Focus 4)', async () => {
    const before = fixture();
    const db = new MemDb(fixture()); // no mirror function
    const sleeps: number[] = [];
    const d = deps(db, { sleep: async (ms) => { sleeps.push(ms); } });
    // The name-row cluster is listed first: the canary cluster still goes first.
    const map: MergeMap = { clusters: [MAP.clusters[2], MAP.clusters[0], MAP.clusters[1]] };
    const r = await applyMerge(map, d, { canary: true });
    expect(r.ok).toBe(false);
    expect(r.stoppedByCanary).toBe(true);
    expect(r.applied).toEqual(['Hiram Alvarez']);
    expect(sleeps).toEqual(Array(9).fill(10_000)); // ~90 s in 10 s polls
    const out = d.lines.join('\n');
    expect(out).toContain('CANARY FAILED');
    expect(out).toContain(`npm run merge:accounts -- --undo "${r.backupFile}"`);
    expect(db.root.Users.keepB).toEqual(before.Users.keepB);
    expect(db.root.Users.oldB).toEqual(before.Users.oldB);
    expect(db.root.Users.keepC).toEqual(before.Users.keepC);
    expect(db.root.Futsal['10']).toEqual(before.Futsal['10']);

    // ...and the printed undo puts Hiram back.
    await undoMerge(r.backupFile as string, deps(db));
    expect(db.root).toEqual(before);
  });

  it('--expect-plan with another digest refuses before any write', async () => {
    const db = new MemDb(fixture());
    await expect(applyMerge(MAP, deps(db), { canary: true, expectPlan: 'deadbeefdeadbeef' }))
      .rejects.toThrow(/plan digest is [0-9a-f]{16}, not the deadbeefdeadbeef/);
    expect(db.writes()).toEqual([]);
  });

  it('the canary cannot be skipped against production', async () => {
    const db = new MemDb(fixture());
    await expect(applyMerge(MAP, deps(db), { canary: false })).rejects.toThrow(/only be skipped under the emulator/);
    expect(db.calls).toEqual([]);
  });
});

describe('undo refusals', () => {
  const writeJson = (name: string, v: unknown): string => {
    const f = path.join(outDir, name);
    fs.writeFileSync(f, JSON.stringify(v));
    return f;
  };

  it('refuses a backup of the wrong kind (a fill backup) before any network call', async () => {
    const db = new MemDb(fixture());
    const f = writeJson('fill.json', { kind: 'fantasy-test-fill-backup', root: 'Fantasy/Futsal/15', entries: [] });
    await expect(undoMerge(f, deps(db))).rejects.toThrow(/Not a merge-accounts-backup file/);
    expect(db.calls).toEqual([]);
  });

  it('refuses an emulator backup against production, and a tampered entry', async () => {
    const db = withMirror(new MemDb(fixture()));
    const r = await applyMerge(MAP, deps(db, { target: EMU }), { canary: false });
    const fresh = new MemDb(fixture());
    await expect(undoMerge(r.backupFile as string, deps(fresh))).rejects.toThrow(/taken against emulator/);
    const b = JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8'));
    b.target = 'production';
    b.entries[0] = { path: 'Users/keepA/Token', who: 'x', before: null, after: 'stolen', attempted: true };
    await expect(undoMerge(writeJson('tampered.json', b), deps(fresh))).rejects.toThrow(/not a leaf the merge writes/);
    b.entries[0] = { path: 'Users/strangerUid/MergedInto', who: 'x', before: null, after: 'keepA', attempted: true };
    await expect(undoMerge(writeJson('tampered2.json', b), deps(fresh))).rejects.toThrow(/not in this backup's clusters/);
    expect(fresh.calls).toEqual([]);
  });

  it("refuses another run's merge (MergedAt differs) and changes nothing", async () => {
    const db = withMirror(new MemDb(fixture()));
    const r1 = await applyMerge(MAP, deps(db), { canary: true });
    await undoMerge(r1.backupFile as string, deps(db));
    const r2 = await applyMerge(MAP, deps(db, { now: () => 1_762_500_000_000 }), { canary: true });
    expect(r2.ok).toBe(true);
    const snapshot = clone(db.root);
    const n = db.writes().length;
    await expect(undoMerge(r1.backupFile as string, deps(db))).rejects.toThrow(/different MergedAt/);
    expect(db.writes().length).toBe(n);
    expect(db.root).toEqual(snapshot);
  });

  it('leaves alone (and lists) a path someone changed after the merge', async () => {
    const db = withMirror(new MemDb(fixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true });
    db.set('Users/keepA/Information/Jersey', 10); // the player edited it since
    const d = deps(db);
    const u = await undoMerge(r.backupFile as string, d);
    expect(u.ok).toBe(false);
    expect(u.leftAlone).toEqual(['Hiram Alvarez: kept account Information/Jersey']);
    expect(db.root.Users.keepA.Information.Jersey).toBe(10);
    expect(db.root.Users.oldA.MergedInto).toBeUndefined();
  });
});

// ── find-dupes ─────────────────────────────────────────────────────────────

describe('--find-dupes (D16)', () => {
  it('lists "already linked to another account" and "unlinked row" candidates, never an email', async () => {
    const root = fixture();
    // A second account named like the linked S15 row, and a submitter whose
    // name matches the S10 row that has no UID.
    root.Users.subDup = { 'First Name': ' hiram ', 'Last Name': 'ALVAREZ', Email: 'second.hiram@example.com' };
    root.Users.subNone = { 'First Name': 'Robert', 'Last Name': 'Shamoelzadeh', Email: 'robert.two@example.com' };
    root.Registrations['Futsal-16'].Submissions.subDup = { Answers: { email: 'second.hiram@example.com' } };
    const db = new MemDb(root);
    const d = deps(db);
    const found = await findDupes('Futsal-16', d);
    // keepA owns its S15 row and subOwn owns its row: neither is a candidate.
    expect(found).toEqual([
      { name: 'Hiram Alvarez', where: ['S15 Ashur'], kind: 'already linked to another account' },
      { name: 'Robert Shamoelzadeh', where: ['S10 Nineveh'], kind: 'unlinked row' },
    ]);
    const out = d.lines.join('\n');
    expect(out).toContain('Hiram Alvarez — S15 Ashur — "already linked to another account"');
    expect(out).toContain('Robert Shamoelzadeh — S10 Nineveh — "unlinked row"');
    expect(out).toContain('6 submissions (1 without a first + last name on the account)');
    expect(out).not.toMatch(RAW_EMAIL_RE);
    expect(out).not.toContain('@');
    expect(db.writes()).toEqual([]);
    // Submissions: keys only; Users: name leaves only (no whole user node).
    expect(db.calls.find((c) => c.path === 'Registrations/Futsal-16/Submissions')?.shallow).toBe(true);
    expect(db.calls.some((c) => /^Users\/[^/]+$/.test(c.path))).toBe(false);
  });

  it('prints one line when two submitters with the same name match the same rows', async () => {
    const root = fixture();
    root.Users.subNone = { 'First Name': 'Robert', 'Last Name': 'Shamoelzadeh' };
    root.Users.subDup = { 'First Name': 'Robert', 'Last Name': 'Shamoelzadeh' };
    root.Registrations['Futsal-16'].Submissions.subDup = { Answers: {} };
    const found = await findDupes('Futsal-16', deps(new MemDb(root)));
    expect(found).toEqual([{ name: 'Robert Shamoelzadeh', where: ['S10 Nineveh'], kind: 'unlinked row' }]);
  });

  it('refuses a registration that is not a league sport, and a bad id', async () => {
    const root = fixture();
    root.Registrations['Soccer-1'] = { Config: { Sport: 'Soccer' } };
    await expect(findDupes('Soccer-1', deps(new MemDb(root)))).rejects.toThrow(/covers Futsal/);
    await expect(findDupes('../Users', deps(new MemDb(root)))).rejects.toThrow(/not a registration id/);
  });
});

// ── command line + guards ──────────────────────────────────────────────────

describe('command line', () => {
  it('parses the modes and refuses mixes and strays', () => {
    expect(parseArgs([]).mode).toBe('dry-run');
    expect(parseArgs(['--apply', '--expect-plan', 'abc']).expectPlan).toBe('abc');
    expect(parseArgs(['--undo', 'b.json']).backupFile).toBe('b.json');
    expect(parseArgs(['--find-dupes', 'Futsal-16']).regId).toBe('Futsal-16');
    expect(() => parseArgs(['--apply', '--undo', 'b.json'])).toThrow(/Pick one/);
    expect(() => parseArgs(['--undo'])).toThrow(/needs a value/);
    expect(() => parseArgs(['--force'])).toThrow(/Unknown argument/);
    expect(() => parseArgs(['--no-canary'])).toThrow(/goes with --apply/);
  });

  it('--fake-emails and --no-canary only work under the emulator; the emulator needs --fake-emails', () => {
    expect(() => checkTargetFlags(parseArgs(['--fake-emails']), PROD)).toThrow(/only works with FIREBASE_DATABASE_EMULATOR_HOST/);
    expect(() => checkTargetFlags(parseArgs(['--apply', '--no-canary']), PROD)).toThrow(/only works under the emulator/);
    expect(() => checkTargetFlags(parseArgs(['--apply']), EMU)).toThrow(/pass --fake-emails/);
    expect(() => checkTargetFlags(parseArgs(['--apply', '--fake-emails', '--no-canary']), EMU)).not.toThrow();
    expect(() => checkTargetFlags(parseArgs(['--undo', 'b.json']), EMU)).not.toThrow();
  });

  it('resolves the target from FIREBASE_DATABASE_EMULATOR_HOST (local only)', () => {
    expect(resolveTarget({}).kind).toBe('production');
    expect(resolveTarget({ FIREBASE_DATABASE_EMULATOR_HOST: '127.0.0.1:9000' }).base).toBe('http://127.0.0.1:9000');
    expect(() => resolveTarget({ FIREBASE_DATABASE_EMULATOR_HOST: 'evil.example:9000' })).toThrow(/local host/);
  });

  it('a malformed map stops the run ("Refusing merge map")', () => {
    const f = path.join(outDir, 'bad_map.json');
    fs.writeFileSync(f, JSON.stringify({ clusters: [{ who: 'X', keep: 'a', old: ['a'] }] }));
    expect(() => loadMap(f)).toThrow(/Refusing merge map/);
  });

  it('the read-only fetch guard lets only GETs and the two reading POSTs out', async () => {
    const seen: string[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = (async (input: any, init?: any) => {
      seen.push(`${init?.method ?? 'GET'} ${String(input)}`);
      return new Response('null');
    }) as typeof fetch;
    const restore = installReadOnlyFetchGuard(PROD);
    try {
      await fetch(`${DB_URL}/Users/x.json`);
      await fetch(LOOKUP_URL, { method: 'POST', body: '{}' });
      await fetch('https://oauth2.googleapis.com/token', { method: 'POST', body: '' });
      await expect(fetch(`${DB_URL}/Users/x.json`, { method: 'PUT', body: '1' })).rejects.toThrow(/read-only/);
      await expect(fetch(`${DB_URL}/Users/x.json`, { method: 'DELETE' })).rejects.toThrow(/read-only/);
      await expect(fetch(`${DB_URL}/Users/x.json`, { method: 'PATCH', body: '{}' })).rejects.toThrow(/read-only/);
      await expect(fetch('https://identitytoolkit.googleapis.com/v1/projects/infinite-sports-app/accounts:update',
        { method: 'POST', body: '{}' })).rejects.toThrow(/read-only/);
      await expect(fetch('https://example.com/x')).rejects.toThrow(/read-only/);
    } finally {
      restore();
      globalThis.fetch = original;
    }
    expect(seen).toHaveLength(3);
    expect(seen.every((s) => !/PUT|DELETE|PATCH|update/.test(s))).toBe(true);
  });
});
