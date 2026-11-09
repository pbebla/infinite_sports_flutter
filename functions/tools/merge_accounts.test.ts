import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { parseCampaign } from '../src/lib/campaigns';
import { maskEmail } from '../src/lib/mask_email';
import { mergeNoticeCampaignId } from '../src/lib/merge_notice';
import {
  applyMerge, assertWriteAllowed, BACKUP_KIND, checkTargetFlags, clusterOfWrite, DB_URL, dryRun, findDupes, guardRest,
  HintLookup, httpRest, identityToolkitHints, identityToolkitSetDisabled, installLoginSwitchFetchGuard,
  installReadOnlyFetchGuard, labelOf, loadMap, LOOKUP_URL, LoginSwitch, notifyMerge, parseArgs, planDigest,
  printableError, readMergeSnapshot, redactUids, removablePaths, resolveTarget, Rest, RunDeps, runCli,
  switchOldLogins, Target, UPDATE_URL, undoMerge, validateBackup,
} from './merge_accounts';
import { looksMasked, MergeMap, PlanWrite } from './merge_accounts_logic';

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
  keepA: 'player.a.kept@example.test',
  oldA: 'player.a.old@example.test',
  keepB: 'testplayer12@example.test',
  oldB: 'player.b.old@example.test',
  keepC: 'player.c.kept@example.test',
};

function fixture(): Record<string, any> {
  return {
    Users: {
      keepA: {
        'First Name': 'Player', 'Last Name': 'A', Email: EMAILS.keepA, Token: 'tok-keepA',
        Played: { Futsal: { 'Season 15': 'Ashur' } }, Information: { Position: 'Defender' },
      },
      oldA: {
        'First Name': 'Player', 'Last Name': 'A', Email: EMAILS.oldA, Token: 'tok-oldA', Phone: '555-0100',
        Played: { Futsal: { 'Season 11': 'Nineveh' } }, ProfileUrl: 'https://storage.example/oldA.jpg',
        Information: { Position: 'Forward', Jersey: 7, Phone: '555-0100' },
      },
      keepB: { 'First Name': 'Player', 'Last Name': 'B', Email: EMAILS.keepB },
      oldB: { 'First Name': 'Player', 'Last Name': 'B', Email: EMAILS.oldB },
      keepC: { 'First Name': 'Plyer', 'Last Name': 'C', Email: EMAILS.keepC },
      subOwn: { 'First Name': 'Player F', 'Last Name': 'Own', Email: 'player.f@example.test' },
      subNone: { 'First Name': 'Nobody', 'Last Name': 'Here', Email: 'nobody@example.com' },
      subNoName: { Email: 'anon@example.com' },
    },
    Futsal: {
      Settings: { Ignored: true },
      '10': { 'Line Ups': { Nineveh: { 'Player C Variant': { Goals: 1 }, 'Player D': { Goals: 2 } } } },
      '11': { 'Line Ups': { Nineveh: { 'Player A2': { UID: 'oldA', Goals: 3 } } } },
      '15': { 'Line Ups': { Ashur: { 'Player A': { UID: 'keepA', Goals: 4 }, 'Player F Own': { UID: 'subOwn' } } } },
    },
    Basketball: { '3': { 'Line Ups': { Hoopers: { 'Player A2': { UID: 'someoneElse' } } } } },
    'AFC San Jose': { Seasons: { 'Spring 2025': { Roster: { 'Player B2': { UID: 'oldB', Number: 9 } } } } },
    Fantasy: { Futsal: { '15': { Config: { lockOverride: 'open' }, Managers: { keepA: { TeamName: 'Secret Squad' } } } } },
    PublicProfiles: { oldA: { 'First Name': 'Player' }, oldB: { 'First Name': 'Player' }, keepA: { 'First Name': 'Player' } },
    Registrations: {
      'Futsal-16': {
        Config: { TargetType: 'league', Sport: 'Futsal', Season: '16' },
        Submissions: {
          keepA: { Answers: { email: EMAILS.keepA, phone: '555-0199' } },
          keepC: { Answers: { email: EMAILS.keepC } },
          subOwn: { Answers: { email: 'player.f@example.test' } },
          subNone: { Answers: { email: 'nobody@example.com' } },
          subNoName: { Answers: { email: 'anon@example.com' } },
        },
      },
    },
  };
}

const MAP: MergeMap = {
  clusters: [
    { who: 'Player A', keep: 'keepA', old: ['oldA'] },
    { who: 'Player B', keep: 'keepB', old: ['oldB'] },
    {
      who: 'Player C', keep: 'keepC', old: [],
      nameRows: [{ sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player C Variant' }],
      firstNameFix: 'Player',
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

/** The digest a dry run over [root] prints (on a copy - no calls recorded). */
async function digestOf(map: MergeMap, root: Record<string, any>): Promise<string> {
  const { digest } = await dryRun(map, deps(new MemDb(clone(root)), { log: () => undefined }));
  return digest;
}

// ── snapshot + dry run ─────────────────────────────────────────────────────

describe('readMergeSnapshot (the planner contract)', () => {
  it('carries Users nodes, old-uid UID leaves (league + AFC), the name row NODE and Config checks', async () => {
    const db = new MemDb(fixture());
    const { snap, stats } = await readMergeSnapshot(guardRest(db, { readOnly: true }), MAP, hints);
    expect(Object.keys(snap.nodes).filter((k) => k.startsWith('Users/')).sort())
      .toEqual(['Users/keepA', 'Users/keepB', 'Users/keepC', 'Users/oldA', 'Users/oldB']);
    expect(snap.nodes['Futsal/11/Line Ups/Nineveh/Player A2/UID']).toBe('oldA');
    expect(snap.nodes['AFC San Jose/Seasons/Spring 2025/Roster/Player B2/UID']).toBe('oldB');
    expect(snap.nodes['Futsal/10/Line Ups/Nineveh/Player C Variant']).toEqual({ Goals: 1 });
    expect(snap.nodes).not.toHaveProperty('Futsal/10/Line Ups/Nineveh/Player C Variant/UID');
    // null = checked and absent; the fantasy season 15 is not touched by a relink
    // but is checked too (a fantasy manager entry of an old account in ANY season).
    expect(snap.nodes['Fantasy/Futsal/11/Config']).toBeNull();
    expect(snap.nodes['Fantasy/Futsal/10/Config']).toBeNull();
    expect(snap.nodes['Fantasy/Futsal/15/Config']).toEqual({ lockOverride: true }); // keys only
    // the Basketball row held by an unrelated account is not ours.
    expect(Object.keys(snap.nodes).some((k) => k.startsWith('Basketball/'))).toBe(false);
    expect(snap.keptHints.keepB).toBe(maskEmail(EMAILS.keepB));
    expect(stats.seasons).toEqual({ Futsal: 3, Basketball: 1, 'Flag Football': 0, 'AFC San Jose': 1 });
  });
});

describe('readMergeSnapshot: old-account data the merge does not move (final-review fix 4)', () => {
  it('reads fantasy seasons, manager uids, registration forms and submitter uids - keys only', async () => {
    const db = new MemDb(fixture());
    const { snap, stats } = await readMergeSnapshot(guardRest(db, { readOnly: true }), MAP, hints);
    expect(snap.nodes['Fantasy/Futsal']).toEqual({ '15': true });
    expect(snap.nodes['Fantasy/Basketball']).toBeNull();
    expect(snap.nodes['Fantasy/Flag Football']).toBeNull();
    // The season with a Config gets its manager uids (keys, never a team name).
    expect(snap.nodes['Fantasy/Futsal/15/Managers']).toEqual({ keepA: true });
    const checks = Object.entries(snap.nodes).filter(([k]) => k.startsWith('Fantasy/') || k.startsWith('Registrations'));
    expect(JSON.stringify(checks)).not.toContain('Secret Squad');
    expect(snap.nodes['Registrations']).toEqual({ 'Futsal-16': true });
    expect(snap.nodes['Registrations/Futsal-16/Submissions']).toEqual({
      keepA: true, keepC: true, subOwn: true, subNone: true, subNoName: true,
    });
    expect(JSON.stringify(checks)).not.toMatch(RAW_EMAIL_RE);
    expect(stats).toMatchObject({ fantasySeasons: 1, registrationForms: 1, oldAccounts: 2, oldPublicProfiles: 2 });
    // Every one of those reads was key-only and nothing was written.
    const shallowPaths = ['Fantasy/Futsal', 'Fantasy/Futsal/15/Managers', 'Registrations', 'Registrations/Futsal-16/Submissions'];
    for (const path of shallowPaths) {
      expect(db.calls.filter((c) => c.path === path).every((c) => c.shallow === true), path).toBe(true);
      expect(db.calls.some((c) => c.path === path), path).toBe(true);
    }
    expect(db.writes()).toEqual([]);
  });

  it('reads the sign-up listing per league, the uid keys per season/status, and the value of a mapped uid only (E2 scan)', async () => {
    const root = fixture();
    root['Sign Ups'] = {
      Futsal: {
        '12': {
          Paid: { oldA: 'Player A ', stranger: 'Secret Name' },
          NotPaid: { keepB: 'Player B' },
          Due: 25,
          Comments: { 'Secret Name': 'secret comment' },
        },
      },
    };
    const db = new MemDb(root);
    const { snap } = await readMergeSnapshot(guardRest(db, { readOnly: true }), MAP, hints);
    expect(snap.nodes['Sign Ups/Futsal']).toEqual({ '12': true });
    expect(snap.nodes['Sign Ups/Basketball']).toBeNull();
    expect(snap.nodes['Sign Ups/Flag Football']).toBeNull();
    expect(snap.nodes['Sign Ups/Futsal/12/Paid/oldA']).toBe('Player A '); // byte for byte
    expect(snap.nodes['Sign Ups/Futsal/12/NotPaid/keepB']).toBe('Player B');
    expect(snap.nodes['Sign Ups/Futsal/12/Paid/keepA']).toBeNull(); // mapped, no record
    expect(snap.nodes['Sign Ups/Futsal/12/NotPaid/oldA']).toBeNull();
    expect(Object.keys(snap.nodes).some((k) => k.includes('stranger'))).toBe(false);
    expect(JSON.stringify(snap.nodes)).not.toContain('Secret');
    // key-only scans; nothing but those paths is read under Sign Ups; nothing written
    const reads = db.calls.filter((c) => c.path.startsWith('Sign Ups'));
    expect(reads.filter((c) => c.shallow).map((c) => c.path).sort()).toEqual([
      'Sign Ups/Basketball', 'Sign Ups/Flag Football', 'Sign Ups/Futsal',
      'Sign Ups/Futsal/12/NotPaid', 'Sign Ups/Futsal/12/Paid',
    ]);
    expect(reads.some((c) => /Comments|Due/.test(c.path))).toBe(false);
    expect(db.writes()).toEqual([]);
    const ro = guardRest(new MemDb(root), { readOnly: true });
    await Promise.all([
      expect(ro.get('Sign Ups/Futsal')).rejects.toThrow(/only its keys/),
      expect(ro.get('Sign Ups/Futsal/12/Paid')).rejects.toThrow(/only its keys/),
      expect(ro.get('Sign Ups/Futsal/12/Comments')).rejects.toThrow(/not a path the merge tool reads/),
      expect(ro.get('Sign Ups/Futsal/12/Comments', { shallow: true })).rejects.toThrow(/not a path the merge tool reads/),
      expect(ro.get('Sign Ups/Futsal/12/Due')).rejects.toThrow(/not a path the merge tool reads/),
    ]);
  });

  it('the read allowlist takes these paths only as keys, and no deeper', () => {
    const ro = guardRest(new MemDb(fixture()), { readOnly: true });
    return Promise.all([
      expect(ro.get('Registrations')).rejects.toThrow(/only its keys/),
      expect(ro.get('Fantasy/Futsal')).rejects.toThrow(/only its keys/),
      expect(ro.get('Fantasy/Futsal/15/Managers')).rejects.toThrow(/only its keys/),
      expect(ro.get('Fantasy/Futsal/15/Managers/keepA')).rejects.toThrow(/not a path the merge tool reads/),
      expect(ro.get('Registrations/Futsal-16/Submissions/keepA')).rejects.toThrow(/not a path the merge tool reads/),
      expect(ro.get('Fantasy/Futsal/15/Managers', { shallow: true })).resolves.toEqual({ keepA: true }),
    ]);
  });

  const refusedBy = async (mutate: (root: Record<string, any>) => void, why: RegExp) => {
    const root = fixture();
    mutate(root);
    const d = deps(new MemDb(root));
    const { plan } = await dryRun(MAP, d);
    expect(plan.refusals.map((r) => r.who)).toEqual(['Player A']);
    expect(plan.refusals[0].why).toMatch(why);
    // The other people are still planned, and nothing private is printed.
    expect(plan.writes.length).toBeGreaterThan(0);
    const out = d.lines.join('\n');
    expect(out).toContain('Player A: REFUSED');
    expect(out).not.toMatch(RAW_EMAIL_RE);
    expect(out).not.toMatch(/Secret Squad|Futsal-16|keepA|oldA/);
  };

  it('a dry run refuses a person whose old account has Awards or TournamentsPlayed', async () => {
    await refusedBy((r) => { r.Users.oldA.Awards = { a1: { Tier: 'gold' } }; }, /Awards/);
    await refusedBy((r) => { r.Users.oldA.TournamentsPlayed = { t1: 'Cup' }; }, /TournamentsPlayed/);
  });

  it('a dry run refuses a person whose old account is a fantasy manager or registered', async () => {
    await refusedBy((r) => { r.Fantasy.Futsal['15'].Managers.oldA = { TeamName: 'Secret Squad' }; }, /fantasy manager/);
    await refusedBy((r) => { r.Registrations['Futsal-16'].Submissions.oldA = { Answers: {} }; }, /registration submission/);
  });

  it('--apply plans nothing for that person either (same planner), and the others still go', async () => {
    const root = fixture();
    root.Users.oldA.Awards = { a1: 1 };
    const db = withMirror(new MemDb(root));
    const digest = await digestOf(MAP, root);
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: digest });
    expect(db.writes().some((w) => w.path.startsWith('Users/oldA/'))).toBe(false);
    expect(db.root.Users.oldB.MergedInto).toBe('keepB');
    expect(r.ok).toBe(false);
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
    expect(out).toContain('Player A: relink Futsal Season 11, Nineveh, "Player A2"');
    expect(out).toContain('Player C: fix the kept account\'s first name');
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

describe('dry run: public profiles of the old accounts (final-review fix 6)', () => {
  it('prints how many old accounts have a public profile entry now, so the owner knows what the canary can watch', async () => {
    const d = deps(new MemDb(fixture()));
    await dryRun(MAP, d);
    const out = d.lines.join('\n');
    expect(out).toContain('public profiles: 2 of 2 old account(s) have a public profile entry right now');
    expect(out).toContain('the mirror check watches one of them leave');
    expect(out).not.toMatch(/keepA|oldA|keepB|oldB/);
  });

  it('says plainly when none has one (the canary would be skipped)', async () => {
    const root = fixture();
    delete root.PublicProfiles.oldA;
    delete root.PublicProfiles.oldB;
    const d = deps(new MemDb(root));
    await dryRun(MAP, d);
    const out = d.lines.join('\n');
    expect(out).toContain('public profiles: 0 of 2 old account(s) have a public profile entry right now');
    expect(out).toContain('mirror check (canary) will have nothing to watch and is skipped');
  });

  it('counts only some of them when only some have one', async () => {
    const root = fixture();
    delete root.PublicProfiles.oldB;
    const d = deps(new MemDb(root));
    await dryRun(MAP, d);
    expect(d.lines.join('\n')).toContain('public profiles: 1 of 2 old account(s)');
  });
});

describe('apply + undo', () => {
  it('stamp order (final-review fix 5): MergedHint and MergedAt first, MergedInto LAST per old account; --undo takes MergedInto off first', async () => {
    const db = withMirror(new MemDb(fixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r.ok).toBe(true);
    for (const o of ['oldA', 'oldB']) {
      expect(db.writes().map((w) => w.path).filter((p) => p.startsWith(`Users/${o}/`)), o).toEqual([
        `Users/${o}/MergedHint`, `Users/${o}/MergedAt`, `Users/${o}/MergedInto`,
      ]);
    }
    // Undo is the reverse of the write order: the "done" marker goes first.
    db.calls = [];
    await undoMerge(r.backupFile as string, deps(db));
    const undone = db.writes().map((w) => w.path).filter((p) => p.startsWith('Users/oldA/'));
    expect(undone).toEqual(['Users/oldA/MergedInto', 'Users/oldA/MergedAt', 'Users/oldA/MergedHint']);
  });

  it('backup/undo round trip: apply writes the plan, undo restores every path verbatim', async () => {
    const before = fixture();
    const db = withMirror(new MemDb(fixture()));
    const d = deps(db);
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r.ok).toBe(true);
    expect(r.applied).toEqual(['Player A', 'Player B', 'Player C']);
    const u = db.root.Users;
    expect(db.root.Futsal['11']['Line Ups'].Nineveh['Player A2']).toEqual({ UID: 'keepA', Goals: 3 });
    expect(db.root['AFC San Jose'].Seasons['Spring 2025'].Roster['Player B2'].UID).toBe('keepB');
    expect(db.root.Futsal['10']['Line Ups'].Nineveh['Player C Variant']).toEqual({ Goals: 1, UID: 'keepC' });
    expect(u.keepA.Played.Futsal).toEqual({ 'Season 15': 'Ashur', 'Season 11': 'Nineveh' });
    expect(u.keepA.ProfileUrl).toBe('https://storage.example/oldA.jpg');
    expect(u.keepA.Information).toEqual({ Position: 'Defender', Jersey: 7 });
    expect(u.keepC['First Name']).toBe('Player');
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
    const r2 = await applyMerge(MAP, again, { canary: true, expectPlan: await digestOf(MAP, db.root) });
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
      afterPlan: () => { db.set('Futsal/11/Line Ups/Nineveh/Player A2/UID', 'managerLinkedSomeoneElse'); },
    });
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r.ok).toBe(false);
    expect(r.refusedAtApply).toEqual(['Player A']);
    expect(r.applied).toEqual(['Player B', 'Player C']);
    expect(d.lines.join('\n')).toContain(
      'Player A: REFUSED at apply - changed since the plan: roster Futsal Season 11, Nineveh, "Player A2"');
    expect(db.root.Users.keepA).toEqual(before.Users.keepA);
    expect(db.root.Users.oldA).toEqual(before.Users.oldA);
    expect(db.writes().some((w) => w.path.includes('keepA') || w.path.includes('oldA') || w.path.startsWith('Futsal/11'))).toBe(false);

    // The undo never touches (or even weighs) the refused cluster's paths.
    const u = await undoMerge(r.backupFile as string, deps(db));
    expect(u.leftAlone).toEqual([]);
    expect(u.ok).toBe(true);
    expect(db.root.Futsal['11']['Line Ups'].Nineveh['Player A2'].UID).toBe('managerLinkedSomeoneElse');
    expect(db.root.Users.keepB).toEqual(before.Users.keepB);
    expect(db.root.Users.keepC).toEqual(before.Users.keepC);
  });

  it('a fantasy Config that appeared since the plan refuses the cluster (D2 re-checked)', async () => {
    const db = withMirror(new MemDb(fixture()));
    const d = deps(db, { afterPlan: () => { db.set('Fantasy/Futsal/11/Config', { lockOverride: 'open' }); } });
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r.refusedAtApply).toEqual(['Player A']);
    expect(d.lines.join('\n')).toContain('Futsal Season 11 now has a fantasy Config');
  });

  it('the canary stops the run when PublicProfiles/<old> stays (Review Focus 4)', async () => {
    const before = fixture();
    const db = new MemDb(fixture()); // no mirror function
    const sleeps: number[] = [];
    const d = deps(db, { sleep: async (ms) => { sleeps.push(ms); } });
    // The name-row cluster is listed first: the canary cluster still goes first.
    const map: MergeMap = { clusters: [MAP.clusters[2], MAP.clusters[0], MAP.clusters[1]] };
    const r = await applyMerge(map, d, { canary: true, expectPlan: await digestOf(map, db.root) });
    expect(r.ok).toBe(false);
    expect(r.stoppedByCanary).toBe(true);
    expect(r.applied).toEqual(['Player A']);
    expect(sleeps).toEqual(Array(9).fill(10_000)); // ~90 s in 10 s polls
    const out = d.lines.join('\n');
    expect(out).toContain('CANARY FAILED');
    expect(out).toContain(`npm run merge:accounts -- --undo "${r.backupFile}"`);
    expect(db.root.Users.keepB).toEqual(before.Users.keepB);
    expect(db.root.Users.oldB).toEqual(before.Users.oldB);
    expect(db.root.Users.keepC).toEqual(before.Users.keepC);
    expect(db.root.Futsal['10']).toEqual(before.Futsal['10']);

    // ...and the printed undo puts Player A back.
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
    const r1 = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    await undoMerge(r1.backupFile as string, deps(db));
    const r2 = await applyMerge(MAP, deps(db, { now: () => 1_762_500_000_000 }), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r2.ok).toBe(true);
    const snapshot = clone(db.root);
    const n = db.writes().length;
    await expect(undoMerge(r1.backupFile as string, deps(db))).rejects.toThrow(/different MergedAt/);
    expect(db.writes().length).toBe(n);
    expect(db.root).toEqual(snapshot);
  });

  it('leaves alone (and lists) a path someone changed after the merge', async () => {
    const db = withMirror(new MemDb(fixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    db.set('Users/keepA/Information/Jersey', 10); // the player edited it since
    const d = deps(db);
    const u = await undoMerge(r.backupFile as string, d);
    expect(u.ok).toBe(false);
    expect(u.leftAlone).toEqual(['Player A: kept account Information/Jersey']);
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
    root.Users.subDup = { 'First Name': ' player ', 'Last Name': 'A', Email: 'second.player@example.test' };
    root.Users.subNone = { 'First Name': 'Player', 'Last Name': 'C Variant', Email: 'player.two@example.test' };
    root.Registrations['Futsal-16'].Submissions.subDup = { Answers: { email: 'second.player@example.test' } };
    const db = new MemDb(root);
    const d = deps(db);
    const found = await findDupes('Futsal-16', d);
    // keepA owns its S15 row and subOwn owns its row: neither is a candidate.
    expect(found).toEqual([
      { name: 'Player A', where: ['S15 Ashur'], kind: 'already linked to another account' },
      { name: 'Player C Variant', where: ['S10 Nineveh'], kind: 'unlinked row' },
    ]);
    const out = d.lines.join('\n');
    expect(out).toContain('Player A — S15 Ashur — "already linked to another account"');
    expect(out).toContain('Player C Variant — S10 Nineveh — "unlinked row"');
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
    root.Users.subNone = { 'First Name': 'Player', 'Last Name': 'C Variant' };
    root.Users.subDup = { 'First Name': 'Player', 'Last Name': 'C Variant' };
    root.Registrations['Futsal-16'].Submissions.subDup = { Answers: {} };
    const found = await findDupes('Futsal-16', deps(new MemDb(root)));
    expect(found).toEqual([{ name: 'Player C Variant', where: ['S10 Nineveh'], kind: 'unlinked row' }]);
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

// ── review fix round 1 ─────────────────────────────────────────────────────

describe('fix round 1', () => {
  it('a production --apply without --expect-plan refuses before any network call', async () => {
    const db = new MemDb(fixture());
    await expect(applyMerge(MAP, deps(db), { canary: true })).rejects.toThrow(/without --expect-plan/);
    await expect(applyMerge(MAP, deps(db), { canary: true, expectPlan: '' })).rejects.toThrow(/run the dry run first/);
    expect(db.calls).toEqual([]);
    expect(() => checkTargetFlags(parseArgs(['--apply']), PROD)).toThrow(/without --expect-plan/);
    expect(() => checkTargetFlags(parseArgs(['--apply', '--expect-plan', 'abc']), PROD)).not.toThrow();
    // The emulator may omit it.
    const emu = withMirror(new MemDb(fixture()));
    expect((await applyMerge(MAP, deps(emu, { target: EMU }), { canary: true })).ok).toBe(true);
  });

  it('the backup is written atomically (no temp file left behind)', async () => {
    const db = withMirror(new MemDb(fixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(fs.readdirSync(outDir).filter((f) => f.endsWith('.tmp'))).toEqual([]);
    expect(JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8')).kind).toBe(BACKUP_KIND);
  });

  it('an error mid-apply prints the undo command, and that undo restores what landed', async () => {
    const before = fixture();
    const db = withMirror(new MemDb(fixture()));
    const digest = await digestOf(MAP, db.root);
    let puts = 0;
    const realPut = db.put.bind(db);
    db.put = async (p: string, v: unknown) => {
      if (++puts === 5) throw new Error('PUT failed: network error');
      await realPut(p, v);
    };
    const d = deps(db);
    await expect(applyMerge(MAP, d, { canary: true, expectPlan: digest })).rejects.toThrow(/network error/);
    const out = d.lines.join('\n');
    expect(out).toContain('STOPPED by an error after the backup was written');
    const file = /--undo "([^"]+)"/.exec(out)?.[1] as string;
    expect(file).toBeTruthy();
    db.put = realPut;
    await undoMerge(file, deps(db));
    expect(db.root).toEqual(before);
  });

  it('with nothing for the canary to watch, a loud warning is printed and the run continues', async () => {
    const root = fixture();
    delete root.PublicProfiles;
    const db = new MemDb(root);
    const d = deps(db);
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: await digestOf(MAP, root) });
    expect(r.ok).toBe(true);
    expect(r.applied).toHaveLength(3);
    expect(d.lines.join('\n')).toContain('WARNING: THE MIRROR CHECK (CANARY) IS SKIPPED FOR THIS RUN.');
  });

  it('a cluster the planner refused makes the run not ok, with a closing count; the others are written', async () => {
    const map: MergeMap = { clusters: [...MAP.clusters, { who: 'Ghost Person', keep: 'ghostKeep', old: ['ghostOld'] }] };
    const db = withMirror(new MemDb(fixture()));
    const d = deps(db);
    const r = await applyMerge(map, d, { canary: true, expectPlan: await digestOf(map, db.root) });
    expect(r.ok).toBe(false);
    expect(r.refusedByPlan).toEqual(['Ghost Person']);
    expect(r.applied).toHaveLength(3);
    expect(d.lines.join('\n')).toContain('1 cluster(s) REFUSED by the plan (see refusals) - nothing of them was written: Ghost Person');
    // A re-run with nothing left to write is still not ok while a cluster is refused.
    const again = deps(db, { now: () => 1_762_400_100_000 });
    const r2 = await applyMerge(map, again, { canary: true, expectPlan: await digestOf(map, db.root) });
    expect(r2.writes).toBe(0);
    expect(r2.ok).toBe(false);
    expect(again.lines.join('\n')).toContain('1 cluster(s) REFUSED by the plan');
  });

  it('unreadable map and backup files give a generic message (no JSON.parse text)', async () => {
    const bad = path.join(outDir, 'bad.json');
    fs.writeFileSync(bad, '{"clusters": [ "keepA-secret-snippet');
    let mapErr = '';
    try { loadMap(bad); } catch (e) { mapErr = (e as Error).message; }
    expect(mapErr).toMatch(/^Couldn't read the merge map .*bad\.json - not valid JSON\.$/);
    expect(mapErr).not.toMatch(/secret-snippet|Unexpected|position/);
    const undoErr = ((await undoMerge(bad, deps(new MemDb(fixture()))).catch((e: Error) => e)) as Error).message;
    expect(undoErr).toMatch(/^Couldn't read the backup .* - not valid JSON\.$/);
    expect(undoErr).not.toMatch(/secret-snippet|Unexpected|position/);
    expect(() => loadMap(path.join(outDir, 'missing.json'))).toThrow(/missing or cannot be opened/);
  });

  it('labelOf never prints a raw path', () => {
    expect(labelOf('Users/keepA/Played/Futsal/Season 11', MAP)).toBe('Player A: kept account Played/Futsal/Season 11');
    expect(labelOf('Users/oldA/MergedInto', MAP)).toBe('Player A: old account #1 MergedInto');
    expect(labelOf('PublicProfiles/oldB', MAP)).toBe('public profile of Player B: old account #1');
    expect(labelOf('Somewhere/keepA/Else', MAP)).toBe('Player A: an unrecognized path');
    expect(labelOf('Users/strangerUid/Token', MAP)).toBe('an unrecognized path');
    expect(labelOf('PublicProfiles/strangerUid', MAP)).toBe('an unrecognized path');
    expect(labelOf('Registrations/x/Submissions', MAP)).toBe('an unrecognized path');
  });
});

describe('network clients (stubbed fetch)', () => {
  let original: typeof fetch;
  const sent: Array<{ url: string; init: any }> = [];
  beforeEach(() => { original = globalThis.fetch; sent.length = 0; });
  afterEach(() => { globalThis.fetch = original; });

  it('identityToolkitHints masks inside the lookup; no raw email reaches any output', async () => {
    globalThis.fetch = (async (url: any, init?: any) => {
      sent.push({ url: String(url), init });
      const ids: string[] = JSON.parse(init.body).localId;
      const users = ids.filter((u) => EMAILS[u]).map((u) => ({ localId: u, email: EMAILS[u], phoneNumber: '+15550100' }));
      return new Response(JSON.stringify({ users }), { status: 200 });
    }) as typeof fetch;
    const lookup = identityToolkitHints(async () => 'tok-abc');
    const got = await lookup(['keepA', 'keepB', 'nobody']);
    expect(got).toEqual({ keepA: maskEmail(EMAILS.keepA), keepB: maskEmail(EMAILS.keepB) });
    expect(Object.values(got).every((h) => looksMasked(h))).toBe(true);
    expect(JSON.stringify(got)).not.toMatch(RAW_EMAIL_RE);
    expect(sent[0].url).toBe(LOOKUP_URL);
    expect(sent[0].init.method).toBe('POST');
    expect(sent[0].init.headers.Authorization).toBe('Bearer tok-abc');

    const db = new MemDb(fixture());
    const d = deps(db, { hints: lookup });
    const { plan } = await dryRun(MAP, d);
    expect(plan.refusals).toEqual([]);
    expect(d.lines.join('\n')).not.toMatch(RAW_EMAIL_RE);
    expect(d.lines.join('\n')).toContain('kept-email hints found (masked, not shown): 3 of 3');
  });

  it('an Identity Toolkit error names the status only', async () => {
    globalThis.fetch = (async () => new Response(JSON.stringify({ error: { message: 'PERMISSION_DENIED' } }), { status: 403 })) as typeof fetch;
    await expect(identityToolkitHints(async () => 'tok-abc')(['keepA'])).rejects.toThrow(/^Identity Toolkit lookup failed \(HTTP 403, PERMISSION_DENIED\)\.$/);
  });

  it('httpRest sends the token only in the Authorization header, never in the URL or an error', async () => {
    globalThis.fetch = (async (url: any, init?: any) => {
      sent.push({ url: String(url), init });
      return sent.length === 3 ? new Response('{"error":"Permission denied"}', { status: 401 }) : new Response('{"a":true}');
    }) as typeof fetch;
    const token = 'secret-token-123';
    const rest = httpRest(PROD, async () => token);
    expect(await rest.get('Users/keepA', { shallow: true })).toEqual({ a: true });
    await rest.put('Users/oldA/MergedInto', 'keepA');
    const err = await rest.get('Users/keepB').catch((e: Error) => e);
    expect(sent.map((s) => s.url)).toEqual([
      `${DB_URL}/Users/keepA.json?shallow=true`,
      `${DB_URL}/Users/oldA/MergedInto.json`,
      `${DB_URL}/Users/keepB.json`,
    ]);
    expect(sent.every((s) => !s.url.includes(token) && s.init.headers.Authorization === `Bearer ${token}`)).toBe(true);
    expect(sent[1].init.method).toBe('PUT');
    expect(sent[1].init.body).toBe('"keepA"');
    expect((err as Error).message).toBe('GET Users/keepB -> HTTP 401: {"error":"Permission denied"}');
    expect((err as Error).message).not.toContain(token);
    // The emulator: namespace in the query, never a token.
    const emu = httpRest(EMU, async () => 'owner');
    await emu.get('Futsal', { shallow: true });
    expect(sent[3].url).toBe('http://127.0.0.1:9000/Futsal.json?ns=x&shallow=true');
  });
});

// ── --notify (D11 / D12) ───────────────────────────────────────────────────

/** A database the merge was applied to: the old accounts carry their stamps. */
async function appliedDb(map: MergeMap = MAP, at = 1_762_400_000_000): Promise<MemDb> {
  const db = withMirror(new MemDb(fixture()));
  // (a distinct `at` per call: the backup file is named after it)
  const r = await applyMerge(map, deps(db, { now: () => at }), { canary: true, expectPlan: await digestOf(map, db.root) });
  expect(r.ok).toBe(true);
  db.calls = [];
  return db;
}

const NOW = 1_762_500_000_000;
const SEND = { send: true };
const notifyDeps = (db: MemDb, over: Partial<RunDeps> = {}) => deps(db, { now: () => NOW, ...over });

describe('--notify (D11 / D12)', () => {
  it('writes one MergeNotices/<old> per old account and one campaign PER kept account that had one', async () => {
    const db = await appliedDb();
    const d = notifyDeps(db);
    const r = await notifyMerge(MAP, d, SEND);
    expect(r.ok).toBe(true);
    expect(r.noticesWritten).toBe(2);
    expect(r.campaignsWritten).toBe(2);
    const idA = mergeNoticeCampaignId('keepA');
    const idB = mergeNoticeCampaignId('keepB');
    expect(db.writes()).toEqual([
      { method: 'PUT', path: 'MergeNotices/oldA' },
      { method: 'PUT', path: 'MergeNotices/oldB' },
      { method: 'PUT', path: `Campaigns/${idA}` },
      { method: 'PUT', path: `Campaigns/${idB}` },
    ]);
    // The notice carries the masked hint that --apply stamped, and nothing else.
    expect(db.root.MergeNotices.oldA).toEqual({ KeepHint: maskEmail(EMAILS.keepA), CreatedAt: NOW });
    expect(db.root.MergeNotices.oldB).toEqual({ KeepHint: maskEmail(EMAILS.keepB), CreatedAt: NOW });
    // Each campaign reaches exactly ONE kept account - and none exists for keepC
    // (the name-variant cluster has no second account).
    expect(Object.keys(db.root.Campaigns).sort()).toEqual([idA, idB].sort());
    for (const [id, keep] of [[idA, 'keepA'], [idB, 'keepB']]) {
      const campaign = parseCampaign(db.root.Campaigns[id]);
      expect(campaign).not.toBeNull();
      expect(campaign?.audience).toEqual({ type: 'users', uids: [keep] });
      expect(campaign?.title).toBe('Your accounts were combined');
      expect(campaign?.body).toBe('All your seasons are now on this profile.');
      expect(campaign?.sendAtMs).toBe(0);
      expect(campaign?.status).toBe('pending');
    }
    // Never an address in the database or the output.
    expect(JSON.stringify([db.root.MergeNotices, db.root.Campaigns])).not.toMatch(RAW_EMAIL_RE);
    const out = d.lines.join('\n');
    expect(out).not.toMatch(RAW_EMAIL_RE);
    expect(out).not.toMatch(/keepA|oldA|keepB|oldB|keepC|tok-/);
  });

  it('a second run writes nothing (Review Focus 3)', async () => {
    const db = await appliedDb();
    await notifyMerge(MAP, notifyDeps(db), SEND);
    db.calls = [];
    const d = notifyDeps(db, { now: () => NOW + 60_000 });
    const r = await notifyMerge(MAP, d, SEND);
    expect(db.writes()).toEqual([]);
    expect(r).toMatchObject({ ok: true, noticesWritten: 0, campaignsWritten: 0, campaignsPresent: 2 });
    expect(d.lines.join('\n')).toContain('Nothing to write');
    // Even after the trigger stamped its Status on a notice, it is left alone.
    db.root.MergeNotices.oldA.Status = 'sent';
    await notifyMerge(MAP, notifyDeps(db), SEND);
    expect(db.writes()).toEqual([]);
    expect(db.root.MergeNotices.oldA.Status).toBe('sent');
  });

  it('writes only what is missing: an existing notice or campaign is left alone', async () => {
    const db = await appliedDb();
    db.root.MergeNotices = { oldA: { KeepHint: maskEmail(EMAILS.keepA), CreatedAt: 5, Status: 'sent' } };
    await notifyMerge(MAP, notifyDeps(db), SEND);
    expect(db.writes().map((w) => w.path)).toEqual([
      'MergeNotices/oldB', `Campaigns/${mergeNoticeCampaignId('keepA')}`, `Campaigns/${mergeNoticeCampaignId('keepB')}`,
    ]);
    expect(db.root.MergeNotices.oldA.CreatedAt).toBe(5);

    const db2 = await appliedDb(MAP, 1_762_400_001_000);
    db2.root.Campaigns = { [mergeNoticeCampaignId('keepA')]: { Title: 'x', Status: 'sent' } };
    const r2 = await notifyMerge(MAP, notifyDeps(db2), SEND);
    expect(db2.writes().map((w) => w.path)).toEqual([
      'MergeNotices/oldA', 'MergeNotices/oldB', `Campaigns/${mergeNoticeCampaignId('keepB')}`,
    ]);
    expect(r2).toMatchObject({ campaignsWritten: 1, campaignsPresent: 1 });
  });

  it('an EXTENDED map re-run pushes only the new person: nobody already notified is pushed twice', async () => {
    const db = await appliedDb();
    await notifyMerge(MAP, notifyDeps(db), SEND);
    const idA = mergeNoticeCampaignId('keepA');
    const idB = mergeNoticeCampaignId('keepB');
    const before = JSON.stringify(db.root.Campaigns);
    // The trigger / sender already ran for the first two people.
    db.root.MergeNotices.oldA.Status = 'sent';
    db.root.MergeNotices.oldB.Status = 'sent';

    // One more person is merged later and the map is extended with them.
    db.set('Users/keepD', { 'First Name': 'Player' });
    db.set('Users/oldD', { MergedInto: 'keepD', MergedAt: 1, MergedHint: 'pl••@example.test' });
    const extended: MergeMap = { clusters: [...MAP.clusters, { who: 'Player D', keep: 'keepD', old: ['oldD'] }] };
    db.calls = [];

    // The preview already says it: one email, one push.
    const pd = notifyDeps(db);
    const preview = await notifyMerge(extended, pd);
    expect(db.writes()).toEqual([]);
    expect(preview).toMatchObject({ noticesToWrite: 1, campaignsToWrite: 1, campaignsPresent: 2, audience: 3 });
    expect(pd.lines.join('\n')).toContain('1 email(s) and 1 push campaign(s) would go out');

    const r = await notifyMerge(extended, notifyDeps(db, { now: () => NOW + 60_000 }), SEND);
    const idD = mergeNoticeCampaignId('keepD');
    expect(db.writes()).toEqual([
      { method: 'PUT', path: 'MergeNotices/oldD' },
      { method: 'PUT', path: `Campaigns/${idD}` },
    ]);
    expect(r).toMatchObject({ noticesWritten: 1, campaignsWritten: 1, campaignsPresent: 2 });
    // The first two people's campaigns were not touched, and the new one reaches only the new person.
    const after = db.root.Campaigns as Record<string, unknown>;
    expect(JSON.stringify({ [idA]: after[idA], [idB]: after[idB] }))
      .toBe(JSON.stringify({ [idA]: JSON.parse(before)[idA], [idB]: JSON.parse(before)[idB] }));
    expect(parseCampaign(after[idD])?.audience).toEqual({ type: 'users', uids: ['keepD'] });
    expect(Object.keys(after).sort()).toEqual([idA, idB, idD].sort());
    expect(db.root.MergeNotices.oldA.Status).toBe('sent');
  });

  it('refuses unless EVERY old account is stamped, and writes nothing', async () => {
    const fresh = new MemDb(fixture()); // not applied: no stamps at all
    await expect(notifyMerge(MAP, notifyDeps(fresh), SEND)).rejects.toThrow(/Refusing --notify.*not stamped/);
    expect(fresh.writes()).toEqual([]);

    const half = await appliedDb();
    half.set('Users/oldB/MergedInto', null); // one of the two lost its stamp
    await expect(notifyMerge(MAP, notifyDeps(half), SEND)).rejects.toThrow(/Player B: old account #1/);
    expect(half.writes()).toEqual([]);
    half.set('Users/oldB/MergedInto', '   ');
    await expect(notifyMerge(MAP, notifyDeps(half), SEND)).rejects.toThrow(/not stamped/);
    expect(half.writes()).toEqual([]);
  });

  it('refuses an account stamped into a DIFFERENT kept account than the map says', async () => {
    const db = await appliedDb();
    db.set('Users/oldA/MergedInto', 'someoneElse');
    await expect(notifyMerge(MAP, notifyDeps(db), SEND)).rejects.toThrow(/Player A: old account #1.*different account/);
    expect(db.writes()).toEqual([]);
  });

  it('refuses a stamp hint that is not masked (a raw address never goes into a notice)', async () => {
    const db = await appliedDb();
    db.set('Users/oldA/MergedHint', EMAILS.keepA);
    const err = (await notifyMerge(MAP, notifyDeps(db), SEND).catch((e: Error) => e)) as Error;
    expect(err.message).toMatch(/not masked/);
    expect(err.message).not.toContain(EMAILS.keepA);
    expect(db.writes()).toEqual([]);
  });

  it('only ever writes MergeNotices/<old> and the campaign: every other write is refused', async () => {
    const db = await appliedDb();
    const w = guardRest(db, {
      readOnly: false,
      allowedWrites: new Set(['MergeNotices/oldA', `Campaigns/${mergeNoticeCampaignId('keepA')}`]),
    });
    await expect(w.put('MergeNotices/oldB', {})).rejects.toThrow(/not on this run's merge allowlist/);
    await expect(w.put('Users/oldA/Token', 'x')).rejects.toThrow(/not on this run's merge allowlist/);
    await expect(w.put('Campaigns/another', {})).rejects.toThrow(/not on this run's merge allowlist/);
    expect(db.writes()).toEqual([]);
    // And the reads it makes are limited: no notice body, no other campaign.
    const ro = guardRest(db, { readOnly: true });
    await expect(ro.get('MergeNotices/oldA')).rejects.toThrow(/only its keys/);
    await expect(ro.get('MergeNotices')).rejects.toThrow(/not a path the merge tool reads/);
    await expect(ro.get('Campaigns/anything')).rejects.toThrow(/not a path the merge tool reads/);
    await expect(ro.get(`Campaigns/${mergeNoticeCampaignId('keepA')}`)).rejects.toThrow(/only its keys/);
  });

  it('three old accounts of one person: three notices, a campaign of one', async () => {
    const map: MergeMap = { clusters: [{ who: 'Player E', keep: 'keepA', old: ['oldA', 'oldB', 'oldC'] }] };
    const db = new MemDb({
      Users: {
        keepA: { 'First Name': 'Player' },
        oldA: { MergedInto: 'keepA', MergedAt: 1, MergedHint: 'pl••@example.test' },
        oldB: { MergedInto: 'keepA', MergedAt: 1, MergedHint: 'pl••@example.test' },
        oldC: { MergedInto: 'keepA', MergedAt: 1 }, // the kept account has no email: no hint
      },
    });
    const r = await notifyMerge(map, notifyDeps(db), SEND);
    expect(r.noticesWritten).toBe(3);
    expect(Object.keys(db.root.MergeNotices).sort()).toEqual(['oldA', 'oldB', 'oldC']);
    expect(db.root.MergeNotices.oldC).toEqual({ KeepHint: '', CreatedAt: NOW });
    const ids = Object.keys(db.root.Campaigns);
    expect(ids).toEqual([mergeNoticeCampaignId('keepA')]);
    expect(parseCampaign(db.root.Campaigns[ids[0]])?.audience.uids).toEqual(['keepA']);
  });

  it('a map with no old accounts has nothing to notify', async () => {
    const db = new MemDb(fixture());
    const d = notifyDeps(db);
    const r = await notifyMerge({ clusters: [MAP.clusters[2]] }, d, SEND);
    expect(r).toMatchObject({ ok: true, noticesWritten: 0, campaignsWritten: 0 });
    expect(db.calls).toEqual([]);
  });

  it('command line: --notify is its own mode, takes --map, and nothing else', () => {
    expect(parseArgs(['--notify']).mode).toBe('notify');
    expect(parseArgs(['--notify', '--map', 'm.json']).mapFile).toBe('m.json');
    expect(() => parseArgs(['--notify', '--apply'])).toThrow(/Pick one/);
    expect(() => parseArgs(['--notify', '--undo', 'b.json'])).toThrow(/Pick one/);
    expect(() => parseArgs(['--notify', '--expect-plan', 'abc'])).toThrow(/goes with --apply/);
    expect(() => parseArgs(['--notify', '--no-canary'])).toThrow(/goes with --apply/);
    expect(() => parseArgs(['--notify', '--fake-emails'])).toThrow(/does not go with --notify/);
    // No emails are looked up, so the emulator does not need --fake-emails for it.
    expect(() => checkTargetFlags(parseArgs(['--notify']), EMU)).not.toThrow();
  });
});

describe('--notify fix round 1: previews by default, only --send writes', () => {
  it('--notify alone writes NOTHING and prints exactly what --send would write', async () => {
    const db = await appliedDb();
    const d = notifyDeps(db);
    const r = await notifyMerge(MAP, d); // no options: the preview
    expect(db.writes()).toEqual([]);
    expect(db.root.MergeNotices).toBeUndefined();
    expect(db.root.Campaigns).toBeUndefined();
    expect(r).toMatchObject({
      ok: true, noticesWritten: 0, campaignsWritten: 0, noticesToWrite: 2, campaignsToWrite: 2, audience: 2,
    });
    const out = d.lines.join('\n');
    expect(out).toContain('PREVIEW - nothing was written');
    expect(out).toContain('npm run merge:accounts -- --notify --send');
    expect(out).toContain('2 notice(s) to write');
    expect(out).toContain('Player A: old account #1');
    expect(out).toContain('Player B: old account #1');
    expect(out).toContain('push to 2 kept account(s), one campaign each: 2 to write');
    expect(out).not.toMatch(/wrote /);
    expect(out).not.toMatch(RAW_EMAIL_RE);
    expect(out).not.toMatch(/keepA|oldA|keepB|oldB|keepC/);
  });

  it('the preview is the same under the emulator, and still refuses an unstamped map', async () => {
    const db = await appliedDb();
    await notifyMerge(MAP, notifyDeps(db, { target: EMU }));
    expect(db.writes()).toEqual([]);
    const fresh = new MemDb(fixture());
    await expect(notifyMerge(MAP, notifyDeps(fresh, { target: EMU }))).rejects.toThrow(/Refusing --notify.*not stamped/);
    expect(fresh.writes()).toEqual([]);
  });

  it('the preview of an already-notified map says there is nothing to send', async () => {
    const db = await appliedDb();
    await notifyMerge(MAP, notifyDeps(db), SEND);
    db.calls = [];
    const d = notifyDeps(db);
    await notifyMerge(MAP, d);
    expect(db.writes()).toEqual([]);
    expect(d.lines.join('\n')).toContain('Nothing to write');
  });

  it('--send writes, and its DONE message says the notices only send if the trigger is deployed', async () => {
    const db = await appliedDb();
    const d = notifyDeps(db);
    const r = await notifyMerge(MAP, d, SEND);
    expect(r).toMatchObject({ noticesWritten: 2, campaignsWritten: 2 });
    expect(db.writes()).toHaveLength(4);
    const out = d.lines.join('\n');
    expect(out).toContain('DONE - 2 notice(s) and 2 campaign(s) written.');
    expect(out).toContain('Notices only send if onMergeNoticeCreated is deployed');
    expect(out).toContain('delete MergeNotices/<old> and re-run --notify --send after deploying');
  });

  it('command line: --send belongs to --notify and nothing else', () => {
    expect(parseArgs(['--notify']).send).toBe(false);
    expect(parseArgs(['--notify', '--send'])).toMatchObject({ mode: 'notify', send: true });
    expect(() => parseArgs(['--send'])).toThrow(/--send goes with --notify/);
    expect(() => parseArgs(['--apply', '--send'])).toThrow(/--send goes with --notify/);
    expect(() => parseArgs(['--undo', 'b.json', '--send'])).toThrow(/--send goes with --notify/);
    expect(() => parseArgs(['--notify', '--send', '--send'])).toThrow(/given twice/);
    expect(() => checkTargetFlags(parseArgs(['--notify', '--send']), EMU)).not.toThrow();
  });
});

// ── old-login switch (D13): --disable-old-logins / --enable-old-logins ─────

/** A recording stand-in for Identity Toolkit accounts:update. */
function loginSwitch(failFor: string[] = []): { calls: Array<[string, boolean]>; fn: LoginSwitch } {
  const calls: Array<[string, boolean]> = [];
  return {
    calls,
    fn: async (uid, disabled) => {
      calls.push([uid, disabled]);
      if (failFor.includes(uid)) throw new Error('Identity Toolkit accounts:update failed (HTTP 400, USER_NOT_FOUND).');
    },
  };
}

const DISABLE = { disable: true, send: false };
const ENABLE = { disable: false, send: false };

describe('old-login switch (D13)', () => {
  it("refuses unless EVERY old account is stamped into the map's kept account - and calls nothing", async () => {
    const fresh = new MemDb(fixture()); // never applied: no stamps
    const sw = loginSwitch();
    await expect(switchOldLogins(MAP, deps(fresh, { setLoginDisabled: sw.fn }), { ...DISABLE, send: true }))
      .rejects.toThrow(/Refusing --disable-old-logins.*not stamped yet.*Run --apply first.*Nothing was changed/);
    expect(sw.calls).toEqual([]);
    expect(fresh.writes()).toEqual([]);

    // One of two stamped is still a refusal: all or nothing.
    const half = await appliedDb();
    half.set('Users/oldB/MergedInto', null);
    await expect(switchOldLogins(MAP, deps(half, { setLoginDisabled: sw.fn }), { ...DISABLE, send: true }))
      .rejects.toThrow(/Player B: old account #1 is not stamped yet/);
    expect(sw.calls).toEqual([]);

    // Stamped into a DIFFERENT account than the map's kept account: refused too.
    const wrong = await appliedDb(MAP, 1_762_400_000_001);
    wrong.set('Users/oldA/MergedInto', 'someoneElse');
    await expect(switchOldLogins(MAP, deps(wrong, { setLoginDisabled: sw.fn }), { ...ENABLE, send: true }))
      .rejects.toThrow(/Refusing --enable-old-logins.*Player A: old account #1 is stamped into a different account/);
    expect(sw.calls).toEqual([]);
  });

  it('the preview (the default) changes nothing and prints who would be switched', async () => {
    const db = await appliedDb();
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(MAP, d, DISABLE);
    expect(sw.calls).toEqual([]);
    expect(db.writes()).toEqual([]);
    expect(r).toMatchObject({ ok: true, toSwitch: 2, switched: 0, failed: 0 });
    const out = d.lines.join('\n');
    expect(out).toContain('DISABLE OLD LOGINS PREVIEW');
    expect(out).toContain('PREVIEW - nothing was changed');
    expect(out).toContain('2 old login(s) would be DISABLED');
    expect(out).toContain('Player A: old account #1 (oldA)');
    expect(out).toContain('Player B: old account #1 (oldB)');
    expect(out).toContain('npm run merge:accounts -- --disable-old-logins --send');
    expect(out).not.toMatch(RAW_EMAIL_RE);
    // The enable preview points at the enable command.
    const e = deps(db, { setLoginDisabled: sw.fn });
    await switchOldLogins(MAP, e, ENABLE);
    expect(e.lines.join('\n')).toContain('2 old login(s) would be ENABLED');
    expect(e.lines.join('\n')).toContain('npm run merge:accounts -- --enable-old-logins --send');
    expect(sw.calls).toEqual([]);
  });

  it('--send disables every old account (and only those), writing nothing to the database', async () => {
    const db = await noticedDb();
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(MAP, d, { ...DISABLE, send: true });
    expect(sw.calls).toEqual([['oldA', true], ['oldB', true]]); // never keepA / keepB / keepC
    expect(db.writes()).toEqual([]);
    expect(r).toMatchObject({ ok: true, toSwitch: 2, switched: 2, failed: 0 });
    const out = d.lines.join('\n');
    expect(out).toContain('DONE - 2 old login(s) disabled');
    expect(out).toContain('npm run merge:accounts -- --enable-old-logins --send');
    expect(out).toContain('works before or after --undo');
    expect(out).not.toContain('BEFORE --undo');
    expect(out).not.toMatch(RAW_EMAIL_RE);
  });

  it('--enable-old-logins --send is the exact reverse and safe to repeat', async () => {
    const db = await appliedDb();
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(MAP, d, { ...ENABLE, send: true });
    await switchOldLogins(MAP, d, { ...ENABLE, send: true });
    expect(sw.calls).toEqual([['oldA', false], ['oldB', false], ['oldA', false], ['oldB', false]]);
    expect(r).toMatchObject({ ok: true, switched: 2 });
    expect(d.lines.join('\n')).toContain('DONE - 2 old login(s) enabled');
    expect(db.writes()).toEqual([]);
  });

  it('prints uid prefixes only: the first 6 characters, never a whole uid', async () => {
    const keep = 'KEEPuidABCDEFGHIJKLMNOPQRST';
    const old1 = 'OLD1uidABCDEFGHIJKLMNOPQRST';
    const old2 = 'OLD2uidABCDEFGHIJKLMNOPQRST';
    const map: MergeMap = { clusters: [{ who: 'Long Uid', keep, old: [old1, old2] }] };
    const db = new MemDb({ Users: {
      [keep]: { 'First Name': 'Long' },
      [old1]: { MergedInto: keep }, [old2]: { MergedInto: keep },
    }, MergeNotices: { [old1]: { Status: 'sent' }, [old2]: { Status: 'no-email' } } });
    const sw = loginSwitch([old2]);
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(map, d, { ...DISABLE, send: true });
    const out = d.lines.join('\n');
    expect(out).toContain('(OLD1ui)');
    expect(out).toContain('(OLD2ui)');
    expect(out).not.toContain('OLD1uid');
    expect(out).not.toContain('KEEPui');
    // One failure does not stop the others; the run reports it and is not ok.
    expect(sw.calls).toEqual([[old1, true], [old2, true]]);
    expect(r).toMatchObject({ ok: false, switched: 1, failed: 1 });
    expect(out).toContain('FAILED Long Uid: old account #2 (OLD2ui): Identity Toolkit accounts:update failed (HTTP 400, USER_NOT_FOUND).');
    expect(out).toContain('1 of 2 FAILED');
    expect(out).toContain('safe to run again');
    expect(out).not.toContain(old2);
  });

  it('--enable-old-logins accepts an ABSENT stamp (after --undo) but still refuses a stamp pointing elsewhere', async () => {
    const at = 1_762_400_000_002;
    const db = withMirror(new MemDb(fixture()));
    const r = await applyMerge(MAP, deps(db, { now: () => at }), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r.ok).toBe(true);
    await undoMerge(r.backupFile as string, deps(db));
    expect(db.root.Users.oldA.MergedInto).toBeUndefined(); // the stamps are gone
    expect(db.root.Users.oldB.MergedInto).toBeUndefined();
    db.calls = [];
    const sw = loginSwitch();

    // Disabling stays strict: nothing is stamped now, so it is refused.
    await expect(switchOldLogins(MAP, deps(db, { setLoginDisabled: sw.fn }), { ...DISABLE, send: true }))
      .rejects.toThrow(/Refusing --disable-old-logins.*not stamped yet.*Run --apply first/);
    expect(sw.calls).toEqual([]);

    // Enabling (the undo direction) goes through, preview and --send.
    const pv = deps(db, { setLoginDisabled: sw.fn });
    await switchOldLogins(MAP, pv, ENABLE);
    expect(sw.calls).toEqual([]);
    expect(pv.lines.join('\n')).toContain('2 old login(s) would be ENABLED');
    expect(pv.lines.join('\n')).toContain('note: 2 old account(s) not stamped (undone or never applied)');
    const d = deps(db, { setLoginDisabled: sw.fn });
    const res = await switchOldLogins(MAP, d, { ...ENABLE, send: true });
    expect(sw.calls).toEqual([['oldA', false], ['oldB', false]]);
    expect(res).toMatchObject({ ok: true, switched: 2 });
    expect(d.lines.join('\n')).toContain('DONE - 2 old login(s) enabled');
    expect(db.writes()).toEqual([]);

    // A stamp that points elsewhere still refuses enable - even beside an absent one.
    db.set('Users/oldA/MergedInto', 'someoneElse');
    sw.calls.length = 0;
    await expect(switchOldLogins(MAP, deps(db, { setLoginDisabled: sw.fn }), { ...ENABLE, send: true }))
      .rejects.toThrow(/Refusing --enable-old-logins: Player A: old account #1 is stamped into a different account.*Nothing was changed/);
    expect(sw.calls).toEqual([]);
  });

  it('redacts every uid from a Google error message before printing it', async () => {
    const keep = 'KEEPuidABCDEFGHIJKLMNOPQRST';
    const old1 = 'OLD1uidABCDEFGHIJKLMNOPQRST';
    const old2 = 'OLD2uidABCDEFGHIJKLMNOPQRST';
    const map: MergeMap = { clusters: [{ who: 'Long Uid', keep, old: [old1, old2] }] };
    const db = new MemDb({
      Users: { [old1]: { MergedInto: keep }, [old2]: { MergedInto: keep } },
      MergeNotices: { [old1]: { Status: 'sent' }, [old2]: { Status: 'sent' } },
    });
    const calls: string[] = [];
    const d = deps(db, {
      setLoginDisabled: async (uid) => {
        calls.push(uid);
        throw new Error(`Identity Toolkit accounts:update failed (HTTP 400, USER ${uid} NOT_FOUND; also ${keep} and ${old1}).`);
      },
    });
    const r = await switchOldLogins(map, d, { ...DISABLE, send: true });
    const out = d.lines.join('\n');
    expect(calls).toEqual([old1, old2]);
    expect(r).toMatchObject({ ok: false, failed: 2 });
    expect(out).toContain('FAILED Long Uid: old account #1 (OLD1ui): Identity Toolkit accounts:update failed (HTTP 400, USER OLD1ui NOT_FOUND; also KEEPui and OLD1ui).');
    expect(out).toContain('FAILED Long Uid: old account #2 (OLD2ui): Identity Toolkit accounts:update failed (HTTP 400, USER OLD2ui NOT_FOUND; also KEEPui and OLD1ui).');
    for (const u of [keep, old1, old2]) expect(out).not.toContain(u);
    expect(out).not.toContain('OLD1uid');
    expect(out).not.toContain('KEEPuid');
  });

  it('a --send run without a switch function stops before anything', async () => {
    const db = await appliedDb();
    await expect(switchOldLogins(MAP, deps(db), { ...DISABLE, send: true })).rejects.toThrow(/no way to reach Identity Toolkit/);
  });

  it('a map with no old account has nothing to switch', async () => {
    const db = new MemDb(fixture());
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins({ clusters: [MAP.clusters[2]] }, d, { ...DISABLE, send: true });
    expect(r).toMatchObject({ ok: true, toSwitch: 0, switched: 0 });
    expect(d.lines.join('\n')).toContain('Nothing to switch');
    expect(sw.calls).toEqual([]);
  });

  describe('identityToolkitSetDisabled (stubbed fetch)', () => {
    let original: typeof fetch;
    const sent: Array<{ url: string; init: any }> = [];
    beforeEach(() => { original = globalThis.fetch; sent.length = 0; });
    afterEach(() => { globalThis.fetch = original; });

    it('POSTs { localId, disableUser } to accounts:update with the token only in the Authorization header', async () => {
      globalThis.fetch = (async (url: any, init?: any) => {
        sent.push({ url: String(url), init });
        return new Response(JSON.stringify({ localId: 'oldA' }), { status: 200 });
      }) as typeof fetch;
      const setDisabled = identityToolkitSetDisabled(async () => 'secret-tok-9');
      await setDisabled('oldA', true);
      await setDisabled('oldA', false);
      expect(UPDATE_URL).toBe('https://identitytoolkit.googleapis.com/v1/projects/infinite-sports-app/accounts:update');
      expect(sent.map((s) => s.url)).toEqual([UPDATE_URL, UPDATE_URL]);
      expect(sent.every((s) => s.init.method === 'POST' && s.init.headers.Authorization === 'Bearer secret-tok-9')).toBe(true);
      expect(sent.every((s) => !s.url.includes('secret-tok-9'))).toBe(true);
      expect(JSON.parse(sent[0].init.body)).toEqual({ localId: 'oldA', disableUser: true });
      expect(JSON.parse(sent[1].init.body)).toEqual({ localId: 'oldA', disableUser: false });
    });

    it("an error names the status and Google's reason only - never the token, the URL or the uid", async () => {
      globalThis.fetch = (async () => new Response(JSON.stringify({ error: { message: 'USER_NOT_FOUND' } }), { status: 400 })) as typeof fetch;
      const e1 = await identityToolkitSetDisabled(async () => 'secret-tok-9')('oldA', true).catch((e: Error) => e);
      expect((e1 as Error).message).toBe('Identity Toolkit accounts:update failed (HTTP 400, USER_NOT_FOUND).');
      globalThis.fetch = (async () => { throw new Error(`connect ECONNREFUSED ${UPDATE_URL}?key=secret-tok-9`); }) as typeof fetch;
      const e2 = await identityToolkitSetDisabled(async () => 'secret-tok-9')('oldA', true).catch((e: Error) => e);
      expect((e2 as Error).message).toBe('Identity Toolkit accounts:update failed (network error).');
    });
  });

  it('the login-switch fetch guard lets out the database GETs, the token exchange and the accounts:update POST - nothing else', async () => {
    const seen: string[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = (async (input: any, init?: any) => {
      seen.push(`${init?.method ?? 'GET'} ${String(input)}`);
      return new Response('null');
    }) as typeof fetch;
    const restore = installLoginSwitchFetchGuard(PROD);
    try {
      await fetch(`${DB_URL}/Users/x/MergedInto.json`);
      await fetch('https://oauth2.googleapis.com/token', { method: 'POST', body: '' });
      await fetch(UPDATE_URL, { method: 'POST', body: '{}' });
      await expect(fetch(`${DB_URL}/Users/x.json`, { method: 'PUT', body: '1' })).rejects.toThrow(/Refusing PUT/);
      await expect(fetch(`${DB_URL}/Users/x.json`, { method: 'DELETE' })).rejects.toThrow(/Refusing DELETE/);
      await expect(fetch(`${DB_URL}/Users/x.json`, { method: 'PATCH', body: '{}' })).rejects.toThrow(/Refusing PATCH/);
      await expect(fetch(UPDATE_URL, { method: 'GET' })).rejects.toThrow(/Refusing GET/);
      await expect(fetch(UPDATE_URL, { method: 'PUT', body: '{}' })).rejects.toThrow(/Refusing PUT/);
      await expect(fetch(LOOKUP_URL, { method: 'POST', body: '{}' })).rejects.toThrow(/Refusing POST/);
      await expect(fetch('https://identitytoolkit.googleapis.com/v1/projects/other-project/accounts:update',
        { method: 'POST', body: '{}' })).rejects.toThrow(/Refusing POST/);
      await expect(fetch('https://identitytoolkit.googleapis.com/v1/projects/infinite-sports-app/accounts:delete',
        { method: 'POST', body: '{}' })).rejects.toThrow(/Refusing POST/);
      await expect(fetch('https://example.com/x', { method: 'POST' })).rejects.toThrow(/Refusing POST/);
    } finally {
      restore();
      globalThis.fetch = original;
    }
    expect(seen).toHaveLength(3);
    // The PREVIEW runs behind the read-only guard instead, which still refuses
    // accounts:update (pinned by 'the read-only fetch guard lets only GETs ...').
  });

  describe('command line', () => {
    it('parses the two flags as modes; --send belongs to --notify and these two only', () => {
      expect(parseArgs(['--disable-old-logins'])).toMatchObject({ mode: 'disable-logins', send: false });
      expect(parseArgs(['--enable-old-logins', '--send'])).toMatchObject({ mode: 'enable-logins', send: true });
      expect(parseArgs(['--disable-old-logins', '--send', '--map', 'm.json'])).toMatchObject({ mapFile: 'm.json', send: true });
      expect(() => parseArgs(['--send'])).toThrow(/--send goes with --notify, --disable-old-logins or --enable-old-logins/);
      expect(() => parseArgs(['--apply', '--send'])).toThrow(/--send goes with/);
    });

    it('--disable-old-logins and --enable-old-logins are mutually exclusive with every other mode and each other', () => {
      const others = [['--apply'], ['--undo', 'b.json'], ['--find-dupes', 'Futsal-16'], ['--notify']];
      for (const flag of ['--disable-old-logins', '--enable-old-logins']) {
        for (const o of others) {
          expect(() => parseArgs([flag, ...o])).toThrow(/Pick one of/);
          expect(() => parseArgs([...o, flag])).toThrow(/Pick one of/);
        }
      }
      expect(() => parseArgs(['--disable-old-logins', '--enable-old-logins'])).toThrow(/Pick one of/);
      expect(() => parseArgs(['--disable-old-logins', '--disable-old-logins'])).toThrow(/given twice/);
    });

    it('takes none of --expect-plan, --no-canary, --fake-emails (they look up no emails and apply no plan)', () => {
      for (const flag of ['--disable-old-logins', '--enable-old-logins']) {
        expect(() => parseArgs([flag, '--expect-plan', 'abc'])).toThrow(/--expect-plan goes with --apply/);
        expect(() => parseArgs([flag, '--no-canary'])).toThrow(/--no-canary goes with --apply/);
        expect(() => parseArgs([flag, '--fake-emails'])).toThrow(/--fake-emails does not go with/);
      }
    });

    it('under the emulator the preview is fine but --send is refused (no Auth emulator: it would hit the real project)', () => {
      for (const flag of ['--disable-old-logins', '--enable-old-logins']) {
        expect(() => checkTargetFlags(parseArgs([flag]), EMU)).not.toThrow();
        expect(() => checkTargetFlags(parseArgs([flag, '--send']), EMU)).toThrow(/Auth emulator/);
        expect(() => checkTargetFlags(parseArgs([flag, '--send']), PROD)).not.toThrow();
        expect(() => checkTargetFlags(parseArgs([flag]), PROD)).not.toThrow();
      }
    });
  });
});

// ── fix round 2: no mode may print a full uid (the catch redacts, once) ────

describe('top-level error output prints uid prefixes only (every mode)', () => {
  const KEEP = 'KEEPuidABCDEFGHIJKLMNOPQRST';
  const OLD1 = 'OLD1uidABCDEFGHIJKLMNOPQRST';
  const OLD2 = 'OLD2uidABCDEFGHIJKLMNOPQRST';
  const FULL = [KEEP, OLD1, OLD2];
  const CWD = path.resolve(__dirname, '..');
  let original: typeof fetch;
  beforeEach(() => { original = globalThis.fetch; });
  afterEach(() => { globalThis.fetch = original; });

  function mapFile(): string {
    const f = path.join(outDir, 'long_map.json');
    fs.writeFileSync(f, JSON.stringify({ clusters: [{ who: 'Long Uid', keep: KEEP, old: [OLD1, OLD2] }] }));
    return f;
  }

  /** A database whose GET of any Users/<uid>/MergedInto fails (HTTP 500 or a dropped connection). */
  function failingDb(how: 'http500' | 'dropped'): void {
    globalThis.fetch = (async (url: any) => {
      if (/MergedInto\.json/.test(String(url))) {
        if (how === 'dropped') throw new Error('socket hang up');
        return new Response('{"error":"Internal error for Users/' + OLD1 + '"}', { status: 500 });
      }
      return new Response('null');
    }) as typeof fetch;
  }

  async function cli(argv: string[]): Promise<{ code: number; out: string; err: string }> {
    const lines: string[] = [];
    const errs: string[] = [];
    const code = await runCli(argv, {}, {
      cwd: CWD, token: async () => 'tok-xyz', log: (l) => lines.push(l), error: (e) => errs.push(e),
    });
    return { code, out: lines.join('\n'), err: errs.join('\n') };
  }

  const MODES: Array<[string, string[]]> = [
    ['--disable-old-logins preview', ['--disable-old-logins']],
    ['--disable-old-logins --send', ['--disable-old-logins', '--send']],
    ['--enable-old-logins preview', ['--enable-old-logins']],
    ['--notify preview', ['--notify']],
    ['--notify --send', ['--notify', '--send']],
  ];

  for (const how of ['http500', 'dropped'] as const) {
    for (const [name, flags] of MODES) {
      it(`${name}: a preflight read that fails (${how}) prints the 6-character prefix, never the full uid`, async () => {
        failingDb(how);
        const r = await cli([...flags, '--map', mapFile()]);
        expect(r.code).toBe(1);
        expect(r.err).toContain('Users/OLD1ui/MergedInto');
        expect(r.err).toMatch(/GET Users\/OLD1ui\/MergedInto (failed|-> HTTP 500)/);
        for (const u of FULL) {
          expect(r.err).not.toContain(u);
          expect(r.out).not.toContain(u);
        }
        expect(r.err).not.toContain('OLD1uid');
        expect(r.err).not.toContain('tok-xyz');
        expect(globalThis.fetch).toBeDefined();
      });
    }
  }

  it('the fetch guard is restored after a failed run (the error path does not leak it)', async () => {
    failingDb('http500');
    const stub = globalThis.fetch;
    await cli(['--disable-old-logins', '--map', mapFile()]);
    expect(globalThis.fetch).toBe(stub);
  });

  it('a map that fails to load cannot print its own uids either', async () => {
    const f = path.join(outDir, 'bad_long_map.json');
    fs.writeFileSync(f, JSON.stringify({ clusters: [{ who: 'Bad', keep: KEEP, old: [KEEP, OLD1] }] }));
    const r = await cli(['--disable-old-logins', '--map', f]);
    expect(r.code).toBe(1);
    expect(r.err).toContain('Refusing merge map');
    for (const u of FULL) expect(r.err).not.toContain(u);
  });

  it('redactUids: the given uids (any characters) and then any uid-shaped path segment, nothing else', () => {
    expect(redactUids(`GET Users/${OLD1}/MergedInto failed`, [OLD1])).toBe('GET Users/OLD1ui/MergedInto failed');
    // no map loaded: the 20-40 character run between slashes is cut
    expect(redactUids(`GET Users/${OLD2}/MergedInto -> HTTP 500: Users/${KEEP}`)).toBe(
      'GET Users/OLD2ui/MergedInto -> HTTP 500: Users/KEEPui');
    // a uid with underscore/hyphen is covered by the map's own list
    expect(redactUids('Users/abc_def-ghi-jkl-mno-pqr-stu/x', ['abc_def-ghi-jkl-mno-pqr-stu'])).toBe('Users/abc_de/x');
    // short ids, season numbers, team and roster names are left alone
    const keepAsIs = 'GET Users/oldA/MergedInto Futsal/15/Line Ups/Ashur/Player A/UID -> HTTP 500';
    expect(redactUids(keepAsIs, ['oldA', 'keepA'])).toBe(keepAsIs);
    // a run longer than 40 characters is not a uid (a digest, say)
    const long = 'a'.repeat(64);
    expect(redactUids(`/x/${long}/y`)).toBe(`/x/${long}/y`);
  });

  it('printableError: the stack AND the message are redacted; a message the stack lacks is added', () => {
    const e = new Error(`GET Users/${OLD1}/MergedInto -> HTTP 500: gone`);
    const text = printableError(e, [OLD1]);
    expect(text).toContain('GET Users/OLD1ui/MergedInto -> HTTP 500: gone');
    expect(text).toContain('merge_accounts.test'); // the stack frames are still printed
    expect(text).not.toContain(OLD1);
    const odd = new Error('first');
    odd.message = `later ${OLD2}`;
    const t2 = printableError(odd, [OLD2]);
    expect(t2).toContain('later OLD2ui');
    expect(t2).not.toContain(OLD2);
    expect(printableError(`plain Users/${KEEP}`, [])).toBe('plain Users/KEEPui');
    expect(printableError(undefined)).toBe('undefined');
  });

  describe('enable DONE line and the unstamped note', () => {
    it('after an undo (not stamped): says so, and suggests no disable that would refuse', async () => {
      const db = new MemDb({ Users: { [OLD1]: { 'First Name': 'x' } } });
      const map: MergeMap = { clusters: [{ who: 'Long Uid', keep: KEEP, old: [OLD1] }] };
      const sw = loginSwitch();
      const d = deps(db, { setLoginDisabled: sw.fn });
      await switchOldLogins(map, d, { ...ENABLE, send: true });
      const out = d.lines.join('\n');
      expect(out).toContain('note: 1 old account(s) not stamped (undone or never applied); re-enabling a login is safe either way.');
      expect(out).toContain('DONE - 1 old login(s) enabled.');
      expect(out).toContain('--disable-old-logins refuses until --apply has stamped the old accounts again');
      expect(out).not.toContain('To switch them off again');
      expect(out).not.toContain('carry no stamp');
    });

    it('while stamped: still offers the way back to disabled', async () => {
      const db = await appliedDb();
      const d = deps(db, { setLoginDisabled: loginSwitch().fn });
      await switchOldLogins(MAP, d, { ...ENABLE, send: true });
      const out = d.lines.join('\n');
      expect(out).toContain('To switch them off again: npm run merge:accounts -- --disable-old-logins --send.');
      expect(out).not.toContain('not stamped');
    });
  });
});

// ── final-review fix 7: do not shut the old email off before the person was told ──

/** A stamped database whose notices have settled (what the trigger leaves). */
async function noticedDb(statuses: Record<string, string | null> = { oldA: 'sent', oldB: 'sent' }): Promise<MemDb> {
  const db = await appliedDb(MAP, 1_762_400_000_000 + Math.floor(Math.random() * 1_000_000));
  for (const [uid, status] of Object.entries(statuses)) {
    if (status !== null) db.set(`MergeNotices/${uid}`, { KeepHint: 'x', CreatedAt: 1, Status: status });
  }
  db.calls = [];
  return db;
}

describe('--disable-old-logins --send waits for the notices (final-review fix 7)', () => {
  const sendOpts = { disable: true, send: true };

  it('refuses when an old account has no notice at all, naming labels (never a uid) and the way out', async () => {
    const db = await noticedDb({ oldA: 'sent', oldB: null });
    const sw = loginSwitch();
    const err = (await switchOldLogins(MAP, deps(db, { setLoginDisabled: sw.fn }), sendOpts).catch((e: Error) => e)) as Error;
    expect(err.message).toMatch(/Refusing --disable-old-logins --send/);
    expect(err.message).toMatch(/not been told yet/);
    expect(err.message).toContain('Player B: old account #1');
    expect(err.message).not.toContain('Player A: old account #1');
    expect(err.message).toContain('--notify --send');
    expect(err.message).toContain('--skip-notice-check');
    expect(err.message).toMatch(/Nothing was changed/);
    expect(err.message).not.toMatch(/oldA|oldB|keepA|keepB/);
    expect(sw.calls).toEqual([]);
    expect(db.writes()).toEqual([]);
  });

  it('refuses while a notice is still sending, failed, or has any other status', async () => {
    for (const status of ['sending', 'failed', 'weird']) {
      const db = await noticedDb({ oldA: 'sent', oldB: status });
      const sw = loginSwitch();
      await expect(switchOldLogins(MAP, deps(db, { setLoginDisabled: sw.fn }), sendOpts), status)
        .rejects.toThrow(/not been told yet/);
      expect(sw.calls, status).toEqual([]);
    }
  });

  it('goes ahead when every notice is sent or has no email', async () => {
    const db = await noticedDb({ oldA: 'sent', oldB: 'no-email' });
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(MAP, d, sendOpts);
    expect(r).toMatchObject({ ok: true, switched: 2, failed: 0 });
    expect(sw.calls).toEqual([['oldA', true], ['oldB', true]]);
    expect(d.lines.join(' ')).not.toMatch(/SKIPPED/);
  });

  it('reads only each notice\'s Status leaf - never a notice body - and writes nothing', async () => {
    const db = await noticedDb();
    await switchOldLogins(MAP, deps(db, { setLoginDisabled: loginSwitch().fn }), sendOpts);
    const reads = db.calls.filter((c) => c.path.startsWith('MergeNotices'));
    expect(reads.map((c) => c.path).sort()).toEqual(['MergeNotices/oldA/Status', 'MergeNotices/oldB/Status']);
    expect(db.writes()).toEqual([]);
  });

  it('--skip-notice-check overrides, and prints it loudly', async () => {
    const db = await noticedDb({ oldA: null, oldB: 'sending' });
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(MAP, d, { ...sendOpts, skipNoticeCheck: true });
    expect(r).toMatchObject({ ok: true, switched: 2 });
    expect(sw.calls).toEqual([['oldA', true], ['oldB', true]]);
    const out = d.lines.join(' ');
    expect(out).toContain('--skip-notice-check');
    expect(out).toMatch(/NOTICE CHECK IS OFF/);
    expect(out).toMatch(/2 old account\(s\) were NOT confirmed as told/);
  });

  it('the preview never refuses: it says how many notices have settled and how to proceed', async () => {
    const db = await noticedDb({ oldA: 'sent', oldB: null });
    const sw = loginSwitch();
    const d = deps(db, { setLoginDisabled: sw.fn });
    const r = await switchOldLogins(MAP, d, { disable: true, send: false });
    expect(r.ok).toBe(true);
    expect(sw.calls).toEqual([]);
    const out = d.lines.join(' ');
    expect(out).toContain('notices: 1 of 2 old account(s) have a settled notice');
    expect(out).toContain('--send will refuse until every one has');
    expect(out).toContain('Player B: old account #1');
  });

  it('--enable-old-logins never checks notices (it is the safe direction)', async () => {
    const db = await appliedDb(MAP, 1_762_400_000_777); // no notices at all
    db.calls = [];
    const sw = loginSwitch();
    const r = await switchOldLogins(MAP, deps(db, { setLoginDisabled: sw.fn }), { disable: false, send: true });
    expect(r).toMatchObject({ ok: true, switched: 2 });
    expect(db.calls.some((c) => c.path.startsWith('MergeNotices'))).toBe(false);
  });

  it('command line: --skip-notice-check belongs to --disable-old-logins and nothing else', () => {
    expect(parseArgs(['--disable-old-logins', '--send', '--skip-notice-check'])).toMatchObject({
      mode: 'disable-logins', send: true, skipNoticeCheck: true,
    });
    expect(parseArgs(['--disable-old-logins']).skipNoticeCheck).toBe(false);
    expect(() => parseArgs(['--enable-old-logins', '--skip-notice-check'])).toThrow(/--skip-notice-check goes with --disable-old-logins/);
    expect(() => parseArgs(['--notify', '--skip-notice-check'])).toThrow(/--skip-notice-check goes with --disable-old-logins/);
    expect(() => parseArgs(['--skip-notice-check'])).toThrow(/--skip-notice-check goes with --disable-old-logins/);
  });
});

// ── Task 2: sign-up moves (E2) and test-season relinks (E1) in the CLI ─────

/** The audit's shape: the old account also sits on a roster of the fantasy TEST
 *  season (Config + TestFill), and holds sign-up records in several seasons. The
 *  display names are made up and distinctive so a leak into any output shows. */
function moveFixture(): Record<string, any> {
  const root = fixture();
  root.Futsal['15']['Line Ups'].Ashur['Player A Old'] = { UID: 'oldA', Goals: 1 };
  root.Fantasy.Futsal['15'].TestFill = { At: 1_762_000_000_000, Managers: 20 };
  root['Sign Ups'] = {
    Futsal: {
      '12': {
        Paid: { oldA: 'Zed Display', stranger: 'Hidden Stranger' }, Due: 25,
        Comments: { 'Zed Display': 'a private comment' },
      },
      '13': { Paid: { oldA: ' Zed Display ' }, Info: { Note: 'x' } },
      '16': { Paid: { keepA: 'Zed Display' } },
    },
    Basketball: { '3': { NotPaid: { oldB: 'Yan Display' } } },
  };
  return root;
}

const SU_LEAK_RE = /Zed Display|Yan Display|Hidden Stranger|private comment/;
const wr = (db: MemDb, prefix: string): string[] =>
  db.writes().filter((w) => w.path.startsWith(prefix)).map((w) => `${w.method} ${w.path}`);

describe('Task 2: reads and guards for the test-season gate and the sign-up removes', () => {
  it('reads TestFill (keys only) for a relinked season whose Config exists; null when absent; nothing when there is no Config', async () => {
    const db = new MemDb(moveFixture());
    const { snap } = await readMergeSnapshot(guardRest(db, { readOnly: true }), MAP, hints);
    expect(snap.nodes['Fantasy/Futsal/15/Config']).toEqual({ lockOverride: true });
    expect(snap.nodes['Fantasy/Futsal/15/TestFill']).toEqual({ At: true, Managers: true }); // keys, not values
    expect('Fantasy/Futsal/11/TestFill' in snap.nodes).toBe(false); // no Config there: no marker read
    const reads = db.calls.filter((c) => c.path.endsWith('/TestFill'));
    expect(reads.length).toBeGreaterThan(0);
    expect(reads.every((c) => c.shallow)).toBe(true);
    expect(db.writes()).toEqual([]);

    const live = moveFixture();
    delete live.Fantasy.Futsal['15'].TestFill; // a LIVE fantasy season: checked, absent
    const again = await readMergeSnapshot(guardRest(new MemDb(live), { readOnly: true }), MAP, hints);
    expect(again.snap.nodes['Fantasy/Futsal/15/TestFill']).toBeNull();
    const { plan } = await dryRun(MAP, deps(new MemDb(live)));
    expect(plan.refusals.map((r) => r.who)).toEqual(['Player A']);
    expect(plan.refusals[0].why).toMatch(/live fantasy season/);
  });

  it('the read allowlist takes TestFill only as keys', async () => {
    const ro = guardRest(new MemDb(moveFixture()), { readOnly: true });
    await Promise.all([
      expect(ro.get('Fantasy/Futsal/15/TestFill')).rejects.toThrow(/only its keys/),
      expect(ro.get('Fantasy/Futsal/15/TestFill', { shallow: true })).resolves.toEqual({ At: true, Managers: true }),
      expect(ro.get('Fantasy/Futsal/15/TestFill/At')).rejects.toThrow(/not a path the merge tool reads/),
    ]);
  });

  it('a DELETE is only for a path on the remove list; a PUT never carries null', async () => {
    const db = new MemDb(moveFixture());
    const w = guardRest(db, {
      readOnly: false,
      allowedWrites: new Set(['Sign Ups/Futsal/12/Paid/keepA', 'Users/oldA/MergedInto']),
      allowedDeletes: new Set(['Sign Ups/Futsal/12/Paid/oldA']),
    });
    await expect(w.del('Users/oldA/MergedInto')).rejects.toThrow(/not on this run's merge allowlist/); // a PUT path is not a remove path
    await expect(w.del('Sign Ups/Futsal/13/Paid/oldA')).rejects.toThrow(/not on this run's merge allowlist/);
    await expect(w.del('Users/oldA')).rejects.toThrow(/not on this run's merge allowlist/);
    await expect(w.put('Sign Ups/Futsal/12/Paid/oldA', 'x')).rejects.toThrow(/not on this run's merge allowlist/); // a remove path is not a PUT path
    await expect(w.put('Sign Ups/Futsal/12/Paid/keepA', null)).rejects.toThrow(/never carries null/);
    await expect(w.put('Sign Ups/Futsal/12/Paid/keepA', undefined)).rejects.toThrow(/never carries null/);
    expect(db.writes()).toEqual([]);
    await w.put('Sign Ups/Futsal/12/Paid/keepA', 'Zed Display');
    await w.del('Sign Ups/Futsal/12/Paid/oldA');
    expect(db.writes()).toEqual([
      { method: 'PUT', path: 'Sign Ups/Futsal/12/Paid/keepA' },
      { method: 'DELETE', path: 'Sign Ups/Futsal/12/Paid/oldA' },
    ]);
    // no allowedDeletes at all (notify, the plain guard): no DELETE ever
    const none = guardRest(db, { readOnly: false, allowedWrites: new Set(['MergeNotices/oldA']) });
    await expect(none.del('MergeNotices/oldA')).rejects.toThrow(/not on this run's merge allowlist/);
    expect(() => assertWriteAllowed('DELETE', 'Users/oldA', { readOnly: true })).toThrow(/read-only client/);
  });

  it('removablePaths is exactly the old-uid sign-up leaves of the plan that carry after: null', () => {
    const rm = (path: string, before: unknown = 'Zed Display'): PlanWrite => ({ path, before, after: null });
    const writes: PlanWrite[] = [
      { path: 'Sign Ups/Futsal/12/Paid/keepA', before: null, after: 'Zed Display' },
      rm('Sign Ups/Futsal/12/Paid/oldA'),
      rm('Sign Ups/Futsal/12/Paid/keepA'), // a kept account's record: never
      rm('Users/oldA/Played/Futsal/Season 11', 'Nineveh'),
      rm('Sign Ups/Futsal/12/Comments/Zed Display', 'x'),
      rm('Sign Ups/Futsal/12/Paid/stranger'),
      rm('Sign Ups/Tournaments/9/Paid/oldA'),
    ];
    expect([...removablePaths(writes, MAP)]).toEqual(['Sign Ups/Futsal/12/Paid/oldA']);
  });

  it('clusterOfWrite maps a sign-up path to its cluster through the uid (kept or old)', () => {
    const w = (path: string, after: unknown = 'x'): PlanWrite => ({ path, before: null, after });
    expect(clusterOfWrite(w('Sign Ups/Futsal/12/Paid/oldA', null), MAP)).toBe(0);
    expect(clusterOfWrite(w('Sign Ups/Futsal/12/Paid/keepA'), MAP)).toBe(0);
    expect(clusterOfWrite(w('Sign Ups/Basketball/3/NotPaid/oldB', null), MAP)).toBe(1);
    expect(clusterOfWrite(w('Sign Ups/Futsal/12/Paid/stranger'), MAP)).toBe(-1);
    expect(clusterOfWrite(w('Sign Ups/Futsal/12/Comments/oldA'), MAP)).toBe(-1);
  });

  it('labelOf names a sign-up leaf by person, side, league, season and status - never the uid or the value', () => {
    expect(labelOf('Sign Ups/Futsal/12/Paid/oldA', MAP)).toBe('Player A: old account #1 sign-up record, Futsal Season 12 (Paid)');
    expect(labelOf('Sign Ups/Basketball/3/NotPaid/keepB', MAP)).toBe('Player B: kept account sign-up record, Basketball Season 3 (NotPaid)');
    expect(labelOf('Sign Ups/Futsal/12/Paid/stranger', MAP)).toBe('an unrecognized path');
  });
});

describe('Task 2: dry run, apply and undo of the sign-up moves', () => {
  it('the dry run prints the moves and the counts by kind, writes nothing, and leaks no name, uid or comment', async () => {
    const db = new MemDb(moveFixture());
    const d = deps(db);
    const { plan, digest } = await dryRun(MAP, d);
    expect(plan.refusals).toEqual([]);
    expect(db.writes()).toEqual([]);
    const out = d.lines.join('\n');
    expect(out).toContain('Player A: move his Season 12 sign-up record (Futsal, Paid)');
    expect(out).toContain('Player A: move his Season 13 sign-up record (Futsal, Paid)');
    expect(out).toContain('Player B: move his Season 3 sign-up record (Basketball, NotPaid)');
    expect(out).toContain('Player A: relink Futsal Season 15, Ashur, "Player A Old" (fantasy test season - the market sync stands down)');
    expect(out).toMatch(/3 sign-up copies, 3 sign-up removes/);
    expect(out).toMatch(/sign-ups: 4 league season\(s\) listed/);
    expect(out).toContain(`--apply --expect-plan ${digest}`);
    expect(out).not.toMatch(SU_LEAK_RE);
    expect(out).not.toMatch(/keepA|oldA|keepB|oldB|stranger/);
    // the sign-up plan: copies before removes, per cluster
    const su = plan.writes.filter((w) => w.path.startsWith('Sign Ups/')).map((w) => `${w.after === null ? 'DEL' : 'PUT'} ${w.path}`);
    expect(su).toEqual([
      'PUT Sign Ups/Futsal/12/Paid/keepA', 'PUT Sign Ups/Futsal/13/Paid/keepA',
      'DEL Sign Ups/Futsal/12/Paid/oldA', 'DEL Sign Ups/Futsal/13/Paid/oldA',
      'PUT Sign Ups/Basketball/3/NotPaid/keepB', 'DEL Sign Ups/Basketball/3/NotPaid/oldB',
    ]);
    // never a read of Comments / Due / Info
    expect(db.calls.some((c) => /Comments|Due|Info/.test(c.path))).toBe(false);
  });

  it('apply writes the copy THEN the remove, in the cluster order, and backs up both', async () => {
    const root = moveFixture();
    const db = withMirror(new MemDb(root));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    expect(r.ok).toBe(true);
    expect(wr(db, 'Sign Ups/')).toEqual([
      'PUT Sign Ups/Futsal/12/Paid/keepA', 'PUT Sign Ups/Futsal/13/Paid/keepA',
      'DELETE Sign Ups/Futsal/12/Paid/oldA', 'DELETE Sign Ups/Futsal/13/Paid/oldA',
      'PUT Sign Ups/Basketball/3/NotPaid/keepB', 'DELETE Sign Ups/Basketball/3/NotPaid/oldB',
    ]);
    const su = db.root['Sign Ups'];
    expect(su.Futsal['12']).toEqual({
      Paid: { keepA: 'Zed Display', stranger: 'Hidden Stranger' }, Due: 25, Comments: { 'Zed Display': 'a private comment' },
    });
    expect(su.Futsal['13']).toEqual({ Paid: { keepA: ' Zed Display ' }, Info: { Note: 'x' } }); // byte for byte
    expect(su.Futsal['16']).toEqual(root['Sign Ups'].Futsal['16']); // the kept account's own record: untouched
    expect(su.Basketball['3']).toEqual({ NotPaid: { keepB: 'Yan Display' } });
    expect(db.root.Futsal['15']['Line Ups'].Ashur['Player A Old'].UID).toBe('keepA'); // test-season relink
    // every write touched exactly the planned leaf: nothing under Comments / Due / Info, no whole node
    expect(db.calls.some((c) => /^Sign Ups\/.*\/(Comments|Due|Info)/.test(c.path))).toBe(false);

    const backup = JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8'));
    const entry = (p: string) => backup.entries.find((e: { path: string }) => e.path === p);
    expect(entry('Sign Ups/Futsal/12/Paid/keepA')).toMatchObject({ before: null, after: 'Zed Display', attempted: true });
    expect(entry('Sign Ups/Futsal/12/Paid/oldA')).toMatchObject({ before: 'Zed Display', after: null, attempted: true });
    expect(entry('Sign Ups/Futsal/13/Paid/oldA')).toMatchObject({ before: ' Zed Display ', after: null, attempted: true });
    validateBackup(backup, 'production');
    expect(JSON.stringify(backup)).not.toMatch(RAW_EMAIL_RE);
  });

  it('a second apply writes nothing (the moved records are gone from the old accounts)', async () => {
    const db = withMirror(new MemDb(moveFixture()));
    await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    const n = db.writes().length;
    const r2 = await applyMerge(MAP, deps(db, { now: () => 1_762_400_100_000 }), {
      canary: true, expectPlan: await digestOf(MAP, db.root),
    });
    expect(r2.writes).toBe(0);
    expect(db.writes().length).toBe(n);
  });

  it('undo restores everything exactly: the old key is put back BEFORE the kept copy is removed', async () => {
    const before = moveFixture();
    const db = withMirror(new MemDb(moveFixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    const backup = JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8'));
    const n = db.writes().length;
    const und = await undoMerge(r.backupFile as string, deps(db));
    expect(und).toEqual({ ok: true, restored: backup.entries.length, alreadyBefore: 0, leftAlone: [] });
    expect(noPublic(db.root)).toEqual(noPublic(before));
    const undo = db.writes().slice(n).map((w) => `${w.method} ${w.path}`);
    const at = (s: string): number => undo.indexOf(s);
    for (const season of ['12', '13']) {
      const restore = at(`PUT Sign Ups/Futsal/${season}/Paid/oldA`);
      const drop = at(`DELETE Sign Ups/Futsal/${season}/Paid/keepA`);
      expect(restore, `${season} restore`).toBeGreaterThanOrEqual(0);
      expect(drop, `${season} drop`).toBeGreaterThan(restore);
    }
    expect(at('PUT Sign Ups/Basketball/3/NotPaid/oldB')).toBeGreaterThanOrEqual(0);
    expect(at('PUT Sign Ups/Basketball/3/NotPaid/oldB')).toBeLessThan(at('DELETE Sign Ups/Basketball/3/NotPaid/keepB'));
    expect(db.root['Sign Ups'].Futsal['13'].Paid.oldA).toBe(' Zed Display '); // byte for byte
  });

  // A crash between a copy and its remove (Review Focus 3).
  const crashAtFirstRemove = async (): Promise<{ db: MemDb; file: string; before: Record<string, any>; real: MemDb['del'] }> => {
    const before = moveFixture();
    const db = withMirror(new MemDb(moveFixture()));
    const digest = await digestOf(MAP, db.root);
    const real = db.del.bind(db);
    db.del = async (p: string) => {
      if (p === 'Sign Ups/Futsal/12/Paid/oldA') throw new Error('DELETE failed: network error');
      await real(p);
    };
    const d = deps(db);
    await expect(applyMerge(MAP, d, { canary: true, expectPlan: digest })).rejects.toThrow(/network error/);
    const file = /--undo "([^"]+)"/.exec(d.lines.join('\n'))?.[1] as string;
    expect(file).toBeTruthy();
    // the copies landed, the removes did not
    expect(db.root['Sign Ups'].Futsal['12'].Paid).toMatchObject({ keepA: 'Zed Display', oldA: 'Zed Display' });
    expect(db.root['Sign Ups'].Futsal['13'].Paid).toMatchObject({ keepA: ' Zed Display ', oldA: ' Zed Display ' });
    db.del = real;
    return { db, file, before, real };
  };

  it('a re-run after a crash between a copy and its remove plans only the removes and finishes the move', async () => {
    const { db } = await crashAtFirstRemove();
    const dry = deps(db, { now: () => 1_762_400_100_000 });
    const { plan, digest } = await dryRun(MAP, dry);
    expect(plan.refusals).toEqual([]);
    const futsal = plan.writes.filter((w) => w.path.startsWith('Sign Ups/Futsal/'));
    expect(futsal.map((w) => `${w.after === null ? 'DEL' : 'PUT'} ${w.path}`)).toEqual([
      'DEL Sign Ups/Futsal/12/Paid/oldA', 'DEL Sign Ups/Futsal/13/Paid/oldA', // no copy is planned again
    ]);
    expect(dry.lines.join('\n')).toContain('Player A: finish moving his Season 12 sign-up record (Futsal, Paid)');
    const r2 = await applyMerge(MAP, deps(db, { now: () => 1_762_400_100_000 }), { canary: true, expectPlan: digest });
    expect(r2.ok).toBe(true);
    expect(wr(db, 'Sign Ups/Futsal/').slice(-2)).toEqual([ // (the failed DELETE was never recorded)
      'DELETE Sign Ups/Futsal/12/Paid/oldA', 'DELETE Sign Ups/Futsal/13/Paid/oldA',
    ]);
    expect(db.root['Sign Ups'].Futsal['12'].Paid).toEqual({ keepA: 'Zed Display', stranger: 'Hidden Stranger' });
    expect(db.root['Sign Ups'].Futsal['13'].Paid).toEqual({ keepA: ' Zed Display ' });
  });

  it('undo after that partial apply removes the kept copies and leaves the old records', async () => {
    const { db, file, before } = await crashAtFirstRemove();
    const und = await undoMerge(file, deps(db));
    expect(und.ok).toBe(true);
    expect(und.alreadyBefore).toBe(1); // the remove that was sent but never landed
    expect(noPublic(db.root)).toEqual(noPublic(before));
    expect(db.root['Sign Ups'].Futsal['12'].Paid.oldA).toBe('Zed Display');
    expect(db.root['Sign Ups'].Futsal['12'].Paid.keepA).toBeUndefined();
  });

  it('a person the planner refused (the kept account holds another record) moves nothing; the rest still go', async () => {
    const root = moveFixture();
    root['Sign Ups'].Futsal['12'].NotPaid = { keepA: 'Zed Display' }; // the kept account: another status
    const db = withMirror(new MemDb(root));
    const d = deps(db);
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: await digestOf(MAP, root) });
    expect(r.refusedByPlan).toEqual(['Player A']);
    expect(r.applied).toEqual(['Player B', 'Player C']);
    expect(r.ok).toBe(false);
    expect(db.writes().some((w) => /keepA|oldA|^Futsal\/(11|15)\//.test(w.path))).toBe(false);
    expect(db.root['Sign Ups'].Futsal['12'].Paid.oldA).toBe('Zed Display');
    const out = d.lines.join('\n');
    expect(out).toMatch(/Player A: Futsal Season 12: the kept account already has a sign-up record there that differs/);
    expect(out).not.toMatch(SU_LEAK_RE);
  });

  it('the snapshot read always lists every league, so a CLI that skipped the scan cannot look like nothing to move', async () => {
    const root = fixture(); // no `Sign Ups` tree at all
    const db = new MemDb(root);
    const { snap } = await readMergeSnapshot(guardRest(db, { readOnly: true }), MAP, hints);
    for (const league of ['Futsal', 'Basketball', 'Flag Football']) {
      expect(`Sign Ups/${league}` in snap.nodes, league).toBe(true);
    }
    expect(db.calls.filter((c) => c.path.startsWith('Sign Ups/') && c.shallow).map((c) => c.path).sort())
      .toEqual(['Sign Ups/Basketball', 'Sign Ups/Flag Football', 'Sign Ups/Futsal']);
    const { plan } = await dryRun(MAP, deps(new MemDb(root)));
    expect(plan.refusals).toEqual([]);
    expect(plan.writes.some((w) => w.path.startsWith('Sign Ups/'))).toBe(false);
  });
});

describe('Task 2: what is re-checked right before a cluster is written', () => {
  let runs = 0;
  const refusedAtApply = async (
    mutate: (db: MemDb) => void, root: Record<string, any> = moveFixture(),
  ): Promise<{ db: MemDb; r: Awaited<ReturnType<typeof applyMerge>>; out: string; before: Record<string, any> }> => {
    const before = clone(root);
    const db = withMirror(new MemDb(root));
    const d = deps(db, { afterPlan: () => mutate(db), now: () => 1_762_400_000_000 + 1000 * ++runs }); // (a backup file per run)
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: await digestOf(MAP, clone(root)) });
    return { db, r, out: d.lines.join('\n'), before };
  };

  it('the TestFill marker cleared between the dry run and the apply refuses that cluster only, writes none of it, and says so (Review Focus 2)', async () => {
    const { db, r, out, before } = await refusedAtApply((m) => m.set('Fantasy/Futsal/15/TestFill', null));
    expect(r.ok).toBe(false);
    expect(r.refusedAtApply).toEqual(['Player A']);
    expect(r.applied).toEqual(['Player B', 'Player C']);
    expect(out).toContain('Player A: REFUSED at apply - changed since the plan: Futsal Season 15: the fantasy test-season marker is gone');
    // nothing of Player A was written: no roster, no Played, no sign-up, no stamp
    expect(db.writes().some((w) => /keepA|oldA|^Futsal\/(11|15)\//.test(w.path))).toBe(false);
    expect(db.root['Sign Ups'].Futsal).toEqual(before['Sign Ups'].Futsal);
    expect(db.root.Users.keepA).toEqual(before.Users.keepA);
    expect(db.root.Users.oldA).toEqual(before.Users.oldA);
    expect(db.root.Futsal['15']['Line Ups'].Ashur['Player A Old'].UID).toBe('oldA');
    // Player B went through, and the undo leaves the refused cluster alone
    expect(db.root.Basketball['3']).toEqual(before.Basketball['3']);
    expect(db.root['Sign Ups'].Basketball['3']).toEqual({ NotPaid: { keepB: 'Yan Display' } });
    const u = await undoMerge(r.backupFile as string, deps(db));
    expect(u).toMatchObject({ ok: true, leftAlone: [] });
    const expected = noPublic(before);
    delete expected.Fantasy.Futsal['15'].TestFill; // (the test itself cleared it)
    expect(noPublic(db.root)).toEqual(expected);
  });

  it('a TestFill that is still there lets the relink through (and a Config that appeared where there was none still refuses)', async () => {
    const ok = await refusedAtApply(() => undefined);
    expect(ok.r.ok).toBe(true);
    const fresh = await refusedAtApply((m) => m.set('Fantasy/Futsal/11/Config', { lockOverride: 'open' }));
    expect(fresh.r.refusedAtApply).toEqual(['Player A']);
    expect(fresh.out).toContain('Futsal Season 11 now has a fantasy Config');
  });

  const variants: Array<[string, (m: MemDb) => void, RegExp, ((root: Record<string, any>) => void)?]> = [
    ['the old record changed value', (m) => m.set('Sign Ups/Futsal/12/Paid/oldA', 'Someone Else'),
      /Player A: old account #1 sign-up record, Futsal Season 12 \(Paid\)/],
    ['the old record was removed by someone else', (m) => m.set('Sign Ups/Futsal/13/Paid/oldA', null),
      /old account #1 sign-up record, Futsal Season 13 \(Paid\)/],
    ['the kept account got a record in the same status (the copy is no longer a copy)', (m) => m.set('Sign Ups/Futsal/12/Paid/keepA', 'Zed Display'),
      /kept account sign-up record, Futsal Season 12 \(Paid\)/],
    ['the kept account got a record in the other status', (m) => m.set('Sign Ups/Futsal/12/NotPaid/keepA', 'Zed Display'),
      /kept account sign-up record, Futsal Season 12 \(NotPaid\)/],
    ['the old account got a second record in the other status', (m) => m.set('Sign Ups/Futsal/13/NotPaid/oldA', 'Zed Display'),
      /old account #1 sign-up record, Futsal Season 13 \(NotPaid\)/],
    ['the kept copy of a half-done move was removed', (m) => m.set('Sign Ups/Futsal/12/Paid/keepA', null),
      /kept account sign-up record, Futsal Season 12 \(Paid\)/,
      (root) => { root['Sign Ups'].Futsal['12'].Paid.keepA = 'Zed Display'; }],
    ['the kept copy of a half-done move changed value', (m) => m.set('Sign Ups/Futsal/12/Paid/keepA', 'Another Name'),
      /kept account sign-up record, Futsal Season 12 \(Paid\)/,
      (root) => { root['Sign Ups'].Futsal['12'].Paid.keepA = 'Zed Display'; }],
  ];
  it.each(variants)('%s since the plan: that cluster is refused, nothing of it written, the other goes', async (_n, mutate, label, seed) => {
    const root = moveFixture();
    seed?.(root);
    const { db, r, out } = await refusedAtApply(mutate, root);
    expect(r.refusedAtApply).toEqual(['Player A']);
    expect(r.applied).toEqual(['Player B', 'Player C']);
    expect(out).toMatch(label);
    expect(out).not.toMatch(SU_LEAK_RE);
    expect(out).not.toMatch(/keepA|oldA/);
    expect(db.writes().some((w) => /keepA|oldA|^Futsal\/(11|15)\//.test(w.path))).toBe(false);
  });
});

describe('Task 2: the plan digest and the backup cover the removes', () => {
  it('dropping a remove, or changing what it removes, changes the digest', async () => {
    const { plan, digest } = await dryRun(MAP, deps(new MemDb(moveFixture()), { log: () => undefined }));
    expect(planDigest(plan.writes)).toBe(digest);
    const removes = plan.writes.filter((w) => w.after === null);
    expect(removes.length).toBe(3);
    expect(planDigest(plan.writes.filter((w) => w.after !== null))).not.toBe(digest);
    expect(planDigest(plan.writes.filter((w) => w !== removes[0]))).not.toBe(digest);
    expect(planDigest(plan.writes.map((w) => (w === removes[1] ? { ...w, before: 'Zed Display!' } : w)))).not.toBe(digest);
    // an apply over the same data accepts exactly this code; another code refuses before any write
    const db = withMirror(new MemDb(moveFixture()));
    await expect(applyMerge(MAP, deps(db), { canary: true, expectPlan: planDigest(plan.writes.filter((w) => w.after !== null)) }))
      .rejects.toThrow(/plan digest is [0-9a-f]{16}, not the/);
    expect(db.writes()).toEqual([]);
  });

  describe('validateBackup on sign-up entries', () => {
    const base = async (): Promise<any> => {
      const db = withMirror(new MemDb(moveFixture()));
      const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
      return JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8'));
    };
    const withEntry = (b: any, e: Record<string, unknown>): any => ({ ...b, entries: [...b.entries, { who: 'Player A', attempted: true, ...e }] });
    it('accepts what apply wrote and refuses every other sign-up shape', async () => {
      const b = await base();
      expect(() => validateBackup(b, 'production')).not.toThrow();
      // a remove of a KEPT account's record, a copy onto an OLD account, a remove that is not a removal
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/16/Paid/keepA', before: 'Zed Display', after: null }), 'production'))
        .toThrow(/only an old account's sign-up record may be removed/);
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/9/Paid/oldA', before: null, after: 'Zed Display' }), 'production'))
        .toThrow(/a sign-up copy goes to the kept account/);
      // a copy with no matching remove in the same backup
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/9/Paid/keepA', before: null, after: 'Zed Display' }), 'production'))
        .toThrow(/no old record of this backup is being moved to it/);
      // a copy over an existing record, a blank or non-text value
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/12/NotPaid/keepA', before: 'x', after: 'Zed Display' }), 'production'))
        .toThrow(/a sign-up copy only fills an empty record/);
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/9/Paid/oldA', before: '   ', after: null }), 'production'))
        .toThrow(/the removed sign-up record is blank or not text/);
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/9/Paid/oldA', before: 7, after: null }), 'production'))
        .toThrow(/the removed sign-up record is blank or not text/);
      // an account that is in no cluster, and paths that are not league sign-up leaves
      expect(() => validateBackup(withEntry(b, { path: 'Sign Ups/Futsal/9/Paid/stranger', before: 'x', after: null }), 'production'))
        .toThrow(/not in this backup's clusters/);
      for (const p of ['Sign Ups/Futsal/12/Comments/Zed Display', 'Sign Ups/Futsal/12/Due', 'Sign Ups/Tournaments/9/Paid/oldA',
        'Sign Ups/Futsal/12/Paid']) {
        expect(() => validateBackup(withEntry(b, { path: p, before: 'x', after: null }), 'production'), p).toThrow(/no value written/);
        expect(() => validateBackup(withEntry(b, { path: p, before: null, after: 'x' }), 'production'), p).toThrow(/not a merge path/);
      }
      // a null `after` anywhere else is still "no value written"
      expect(() => validateBackup(withEntry(b, { path: 'Users/oldA/Played/Futsal/Season 11', before: 'Nineveh', after: null }), 'production'))
        .toThrow(/no value written/);
    });
  });
});

describe('Task 2: undo is careful with a record that changed since the merge', () => {
  it('an old key someone re-created with another value is left alone, and so is the kept copy (the record is never lost)', async () => {
    const db = withMirror(new MemDb(moveFixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    db.set('Sign Ups/Futsal/12/Paid/oldA', 'Re-created Name'); // the old key is back, with another value
    const d = deps(db);
    const u = await undoMerge(r.backupFile as string, d);
    expect(u.ok).toBe(false);
    expect([...u.leftAlone].sort()).toEqual([
      'Player A: kept account sign-up record, Futsal Season 12 (Paid)',
      'Player A: old account #1 sign-up record, Futsal Season 12 (Paid)',
    ]);
    expect(db.root['Sign Ups'].Futsal['12'].Paid).toEqual({ oldA: 'Re-created Name', keepA: 'Zed Display', stranger: 'Hidden Stranger' });
    expect(d.lines.join('\n')).toContain(
      'LEFT ALONE Player A: kept account sign-up record, Futsal Season 12 (Paid) (its old record changed since the merge)');
    // the other seasons were undone as usual
    expect(db.root['Sign Ups'].Futsal['13'].Paid).toEqual({ oldA: ' Zed Display ' });
    expect(db.root['Sign Ups'].Basketball['3'].NotPaid).toEqual({ oldB: 'Yan Display' });
  });

  it('a kept copy the player edited since the merge is left alone too (and the old record is still put back)', async () => {
    const db = withMirror(new MemDb(moveFixture()));
    const r = await applyMerge(MAP, deps(db), { canary: true, expectPlan: await digestOf(MAP, db.root) });
    db.set('Sign Ups/Futsal/13/Paid/keepA', 'Edited Name');
    const u = await undoMerge(r.backupFile as string, deps(db));
    expect(u.leftAlone).toEqual(['Player A: kept account sign-up record, Futsal Season 13 (Paid)']);
    expect(db.root['Sign Ups'].Futsal['13'].Paid).toEqual({ oldA: ' Zed Display ', keepA: 'Edited Name' });
  });
});

describe('Task 2 fix round 1: hardening before the first production removal', () => {
  /** Runs an apply over the move fixture with a hook that changes the database
   *  AFTER the cluster's re-check passed (so only the pre-DELETE check can see it). */
  const inTheGap = async (hook: (db: MemDb) => void, n: number) => {
    const db = withMirror(new MemDb(moveFixture()));
    hook(db);
    const d = deps(db, { now: () => 1_762_400_000_000 + n }); // (a backup file per run)
    const digest = await digestOf(MAP, moveFixture());
    const r = await applyMerge(MAP, d, { canary: true, expectPlan: digest });
    const backup = JSON.parse(fs.readFileSync(r.backupFile as string, 'utf8'));
    return { db, r, out: d.lines.join('\n'), backup };
  };
  const afterPut = (db: MemDb, path: string, then: () => void): void => {
    const prior = db.onPut;
    db.onPut = (p, v) => { prior?.(p, v); if (p === path) then(); };
  };
  const stopped = (x: Awaited<ReturnType<typeof inTheGap>>, ranOn: RegExp): void => {
    expect(x.r.ok).toBe(false); // -> exit code 1
    expect(x.r.stoppedMidCluster).toEqual(['Player A']);
    expect(x.r.applied).toEqual(['Player B', 'Player C']); // the other clusters carry on
    expect(x.r.refusedAtApply).toEqual([]);
    expect(x.out).toMatch(/Player A: STOPPED before a sign-up remove - /);
    expect(x.out).toMatch(ranOn);
    expect(x.out).toMatch(/Player A: STOPPED[^\n]*the rest of this cluster was not attempted/);
    expect(x.out).toMatch(/1 cluster\(s\) STOPPED before a sign-up remove: Player A/);
    expect(x.out).not.toMatch(SU_LEAK_RE);
    expect(x.out).not.toMatch(/keepA|oldA|Changed In The Gap/);
    expect(wr(x.db, 'Sign Ups/Basketball/')).toEqual([
      'PUT Sign Ups/Basketball/3/NotPaid/keepB', 'DELETE Sign Ups/Basketball/3/NotPaid/oldB',
    ]);
  };

  it('the old record changed in the gap: no DELETE, the rest of that cluster is not attempted, the others go', async () => {
    const x = await inTheGap((db) => afterPut(db, 'Sign Ups/Futsal/12/Paid/keepA', () => {
      db.set('Sign Ups/Futsal/12/Paid/oldA', 'Changed In The Gap');
    }), 1);
    stopped(x, /old account #1 sign-up record, Futsal Season 12 \(Paid\) changed/);
    expect(wr(x.db, 'Sign Ups/Futsal/')).toEqual([ // both copies landed, no remove was sent
      'PUT Sign Ups/Futsal/12/Paid/keepA', 'PUT Sign Ups/Futsal/13/Paid/keepA',
    ]);
    expect(x.db.root['Sign Ups'].Futsal['12'].Paid.oldA).toBe('Changed In The Gap');
    expect(x.db.root['Sign Ups'].Futsal['13'].Paid.oldA).toBe(' Zed Display ');
    expect(x.db.root.Users.oldA.MergedInto).toBeUndefined(); // no stamp: the cluster is not "done"
    const entry = (p: string) => x.backup.entries.find((e: { path: string }) => e.path === p);
    expect(entry('Sign Ups/Futsal/12/Paid/keepA').attempted).toBe(true);
    expect(entry('Sign Ups/Futsal/12/Paid/oldA').attempted).toBe(false);
    expect(entry('Sign Ups/Futsal/13/Paid/oldA').attempted).toBe(false);
    expect(entry('Users/oldA/MergedInto').attempted).toBe(false);
    // undo takes the kept copies off and leaves the old keys exactly as they are now
    const before = noPublic(moveFixture());
    before['Sign Ups'].Futsal['12'].Paid.oldA = 'Changed In The Gap';
    const u = await undoMerge(x.r.backupFile as string, deps(x.db));
    expect(u.ok).toBe(true);
    expect(noPublic(x.db.root)).toEqual(before);
  });

  it('the kept copy missing in the gap: no DELETE either', async () => {
    const x = await inTheGap((db) => afterPut(db, 'Sign Ups/Futsal/12/Paid/keepA', () => {
      db.set('Sign Ups/Futsal/12/Paid/keepA', null);
    }), 2);
    stopped(x, /kept account sign-up record, Futsal Season 12 \(Paid\) changed/);
    expect(wr(x.db, 'Sign Ups/Futsal/').some((w) => w.startsWith('DELETE'))).toBe(false);
    expect(x.db.root['Sign Ups'].Futsal['12'].Paid.oldA).toBe('Zed Display'); // the old record is still there
    expect(x.db.root['Sign Ups'].Futsal['13'].Paid.oldA).toBe(' Zed Display ');
    expect(x.db.root.Users.oldA.MergedInto).toBeUndefined();
    const u = await undoMerge(x.r.backupFile as string, deps(x.db));
    expect(u.ok).toBe(true);
    expect(noPublic(x.db.root)).toEqual(noPublic(moveFixture()));
  });

  it('a change after the FIRST remove stops at the second: the first stays done, the rest is not attempted', async () => {
    const x = await inTheGap((db) => {
      const real = db.del.bind(db);
      db.del = async (p: string) => {
        await real(p);
        if (p === 'Sign Ups/Futsal/12/Paid/oldA') db.set('Sign Ups/Futsal/13/Paid/oldA', 'Changed In The Gap');
      };
    }, 3);
    stopped(x, /old account #1 sign-up record, Futsal Season 13 \(Paid\) changed/);
    expect(wr(x.db, 'Sign Ups/Futsal/')).toEqual([
      'PUT Sign Ups/Futsal/12/Paid/keepA', 'PUT Sign Ups/Futsal/13/Paid/keepA', 'DELETE Sign Ups/Futsal/12/Paid/oldA',
    ]);
    expect(x.db.root['Sign Ups'].Futsal['12'].Paid.oldA).toBeUndefined();
    expect(x.db.root['Sign Ups'].Futsal['13'].Paid).toEqual({ oldA: 'Changed In The Gap', keepA: ' Zed Display ' });
    expect(x.db.root.Users.oldA.MergedInto).toBeUndefined();
    expect(x.backup.entries.find((e: { path: string }) => e.path === 'Sign Ups/Futsal/13/Paid/oldA').attempted).toBe(false);
    const before = noPublic(moveFixture());
    before['Sign Ups'].Futsal['13'].Paid.oldA = 'Changed In The Gap';
    const u = await undoMerge(x.r.backupFile as string, deps(x.db));
    expect(u.ok).toBe(true);
    expect(noPublic(x.db.root)).toEqual(before);
  });

  it('nothing changing in the gap: the extra reads cost no write and the apply is as before', async () => {
    const x = await inTheGap(() => undefined, 4);
    expect(x.r.ok).toBe(true);
    expect(x.r.stoppedMidCluster).toEqual([]);
    expect(wr(x.db, 'Sign Ups/Futsal/').filter((w) => w.startsWith('DELETE'))).toHaveLength(2);
  });

  it('the PUT guard refuses {} and [] as values (the REST API treats them as deletes)', async () => {
    const db = new MemDb(moveFixture());
    const w = guardRest(db, { readOnly: false, allowedWrites: new Set(['Sign Ups/Futsal/12/Paid/keepA']) });
    await expect(w.put('Sign Ups/Futsal/12/Paid/keepA', {})).rejects.toThrow(/never carries null, \{\} or \[\]/);
    await expect(w.put('Sign Ups/Futsal/12/Paid/keepA', [])).rejects.toThrow(/never carries null, \{\} or \[\]/);
    await expect(w.put('Sign Ups/Futsal/12/Paid/keepA', null)).rejects.toThrow(/never carries null, \{\} or \[\]/);
    expect(db.writes()).toEqual([]);
    await w.put('Sign Ups/Futsal/12/Paid/keepA', 'Zed Display'); // a value still goes
    await w.put('Sign Ups/Futsal/12/Paid/keepA', { Some: 1 }); // a non-empty node is not an empty one
    expect(db.writes()).toHaveLength(2);
  });

  it('reordering a remove changes the plan code', async () => {
    const { plan, digest } = await dryRun(MAP, deps(new MemDb(moveFixture()), { log: () => undefined }));
    const i = plan.writes.findIndex((w) => w.path === 'Sign Ups/Futsal/12/Paid/oldA');
    const j = plan.writes.findIndex((w) => w.path === 'Sign Ups/Futsal/13/Paid/oldA');
    expect(i).toBeGreaterThan(0);
    expect(j).toBe(i + 1);
    const swapped = [...plan.writes];
    [swapped[i], swapped[j]] = [swapped[j], swapped[i]];
    expect(planDigest(plan.writes)).toBe(digest);
    expect(planDigest(swapped)).not.toBe(digest);
    // and moving a remove ahead of its copy changes it too
    const early = [...plan.writes];
    const copy = early.findIndex((w) => w.path === 'Sign Ups/Futsal/12/Paid/keepA');
    [early[copy], early[i]] = [early[i], early[copy]];
    expect(planDigest(early)).not.toBe(digest);
  });
});
