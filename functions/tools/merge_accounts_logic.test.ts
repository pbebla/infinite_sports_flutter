// Pure planner of the duplicate-account merge tool (plan 2026-11-06, Task 4;
// design D1-D6, D10, D14, D15). No database: fixtures are fake uids and
// fixtures shaped like the read-only audit (a one-old-account person, a person
// whose kept account already has a photo, an AFC-roster person, a three-old-account
// person, and the two name-variant clusters) - all made-up names and addresses.
import { isDeepStrictEqual } from 'util';
import { describe, expect, it } from 'vitest';
import { maskEmail } from '../src/lib/mask_email';
import { configToMap, futsalDefault } from '../src/lib/fantasy/fantasy_config';
import { maybeSyncRoster } from '../src/lib/fantasy/roster_sync';
import { FakeDb } from '../src/lib/fantasy/test_support';
import {
  afcUidPath, assertMergePaths, buildMergePlan, fantasyConfigPath, fantasyTestFillPath, LEAGUE_SPORTS, leagueUidPath,
  looksMasked, MergeCluster, MergeMap, MergeSnapshot, parseRosterUidPath, parseSignUpPath, PlanWrite, playedPath,
  SIGN_UP_STATUSES, signUpPath, userPath,
} from './merge_accounts_logic';

const NOW = 1_800_000_000_000;
const HINT = 'te••••••••@example.test';

/** A tiny in-memory database snapshot builder. */
class World {
  nodes: Record<string, unknown> = {};
  keptHints: Record<string, string> = {};

  user(uid: string, fields: Record<string, unknown> = { 'First Name': 'Fake' }): this {
    this.nodes[userPath(uid)] = fields;
    return this;
  }

  /** A league roster row (uid null = the row exists with no UID). Carries
   *  the row NODE (name rows are read from it) and, when it holds a uid, the
   *  UID leaf (how old-uid rows are found). The season's fantasy Config is
   *  recorded as absent unless fantasy() says so. */
  row(sport: string, season: string, team: string, name: string, uid: string | null): this {
    const uidPath = leagueUidPath(sport, season, team, name);
    this.nodes[uidPath.slice(0, -'/UID'.length)] =
      uid === null ? { Position: 'Forward' } : { UID: uid, Position: 'Forward' };
    if (uid === null) delete this.nodes[uidPath];
    else this.nodes[uidPath] = uid;
    const cfg = fantasyConfigPath(sport, season);
    if (!(cfg in this.nodes)) this.nodes[cfg] = null;
    return this;
  }

  afc(season: string, name: string, uid: string | null): this {
    this.nodes[afcUidPath(season, name)] = uid;
    return this;
  }

  fantasy(sport: string, season: string): this {
    this.nodes[fantasyConfigPath(sport, season)] = { Meta: true };
    return this;
  }

  /** The fantasy TEST-season marker of a season (the fill is applied); its
   *  Config is recorded as existing. */
  testFill(sport: string, season: string): this {
    this.fantasy(sport, season);
    this.nodes[fantasyTestFillPath(sport, season)] = { At: 1, Managers: 20 };
    return this;
  }

  /** A sign-up record (the player's display name) of [uid] in a status. */
  signUp(league: string, season: string, status: 'Paid' | 'NotPaid', uid: string, value: string): this {
    this.nodes[signUpPath(league, season, status, uid)] = value;
    return this;
  }

  hint(keep: string, hint: string = HINT): this {
    this.keptHints[keep] = hint;
    return this;
  }

  /** A fantasy manager entry of [uid] in a fantasy season (the season's
   *  Config is recorded as existing). */
  manager(sport: string, season: string, uid: string): this {
    this.fantasy(sport, season);
    const key = `Fantasy/${sport}/${season}/Managers`;
    this.nodes[key] = { ...((this.nodes[key] as Record<string, true> | undefined) ?? {}), [uid]: true };
    return this;
  }

  /** A registration form with a submission of each of [uids] (keys only). */
  registration(id: string, uids: string[]): this {
    this.nodes[`Registrations/${id}/Submissions`] = Object.fromEntries(uids.map((u) => [u, true]));
    return this;
  }

  /** The snapshot a complete read would give: besides what the tests set, it
   *  lists the fantasy seasons per sport and the registration forms, records
   *  "no manager entries" for every fantasy season nobody was set on, and "no
   *  submissions" for every form - the markers the planner needs (fail closed). */
  snap(): MergeSnapshot {
    const nodes: Record<string, unknown> = JSON.parse(JSON.stringify(this.nodes));
    for (const sport of LEAGUE_SPORTS) {
      const listing: Record<string, true> = {};
      for (const [key, value] of Object.entries(nodes)) {
        const parts = key.split('/');
        if (parts.length !== 4 || parts[0] !== 'Fantasy' || parts[1] !== sport || parts[3] !== 'Config') continue;
        if (value === null || value === undefined) continue;
        listing[parts[2]] = true;
        const managers = `Fantasy/${sport}/${parts[2]}/Managers`;
        if (!(managers in nodes)) nodes[managers] = null;
      }
      if (!(`Fantasy/${sport}` in nodes)) nodes[`Fantasy/${sport}`] = Object.keys(listing).length > 0 ? listing : null;
    }
    // The TestFill marker is read for every season whose Config exists.
    for (const [key, value] of Object.entries(nodes)) {
      const parts = key.split('/');
      if (parts.length !== 4 || parts[0] !== 'Fantasy' || parts[3] !== 'Config') continue;
      if (value === null || value === undefined) continue;
      const marker = fantasyTestFillPath(parts[1], parts[2]);
      if (!(marker in nodes)) nodes[marker] = null;
    }
    // A complete sign-up read: every season that has a sign-up key lists both
    // statuses for every account of the world (null = no record).
    const accounts = Object.keys(nodes).filter((k) => /^Users\/[^/]+$/.test(k)).map((k) => k.slice('Users/'.length));
    const seasonsRead = new Set<string>();
    for (const key of Object.keys(nodes)) {
      const su = parseSignUpPath(key);
      if (su) seasonsRead.add(`${su.league}|${su.season}`);
    }
    for (const group of seasonsRead) {
      const [league, season] = group.split('|');
      for (const uid of accounts) {
        for (const status of SIGN_UP_STATUSES) {
          const p = signUpPath(league, season, status, uid);
          if (!(p in nodes)) nodes[p] = null;
        }
      }
    }
    const forms: Record<string, true> = {};
    for (const key of Object.keys(nodes)) {
      const parts = key.split('/');
      if (parts.length === 3 && parts[0] === 'Registrations' && parts[2] === 'Submissions') forms[parts[1]] = true;
    }
    if (!('Registrations' in nodes)) nodes['Registrations'] = Object.keys(forms).length > 0 ? forms : null;
    return { nodes, keptHints: { ...this.keptHints } };
  }
}

function cluster(over: Partial<MergeCluster> & Pick<MergeCluster, 'keep' | 'old'>): MergeCluster {
  return { who: 'Fake Person', nameRows: [], ...over };
}

function mapOf(...clusters: MergeCluster[]): MergeMap {
  return { clusters };
}

/** Apply a plan's writes to a snapshot the way the database would. */
function applyTo(snap: MergeSnapshot, writes: PlanWrite[]): MergeSnapshot {
  const nodes: Record<string, unknown> = JSON.parse(JSON.stringify(snap.nodes));
  for (const w of writes) {
    const m = /^Users\/([^/]+)\/(.+)$/.exec(w.path);
    if (!m) {
      nodes[w.path] = w.after;
      const rowPath = w.path.slice(0, -'/UID'.length);
      const row = nodes[rowPath];
      if (w.path.endsWith('/UID') && row && typeof row === 'object') {
        (row as Record<string, unknown>)['UID'] = w.after;
      }
      continue;
    }
    const node = (nodes[userPath(m[1])] ?? {}) as Record<string, unknown>;
    const segs = m[2].split('/');
    let cur = node;
    for (const s of segs.slice(0, -1)) {
      cur[s] = (cur[s] ?? {}) as Record<string, unknown>;
      cur = cur[s] as Record<string, unknown>;
    }
    const leaf = segs[segs.length - 1];
    if (w.after === null) delete cur[leaf];
    else cur[leaf] = w.after;
    nodes[userPath(m[1])] = node;
  }
  return { nodes, keptHints: { ...snap.keptHints } };
}

const byPath = (writes: PlanWrite[]) => new Map(writes.map((w) => [w.path, w]));
const paths = (writes: PlanWrite[]) => writes.map((w) => w.path);

/** Player-A-like: one old account, four Futsal rows across seasons, a profile
 *  photo only the old account has, and Information the keep lacks. */
function hiramWorld(): World {
  const w = new World()
    .user('keepH', { 'First Name': 'Player', Played: { Futsal: { 'Season 15': 'Zebras' } } })
    .user('oldH', {
      'First Name': 'Player', ProfileUrl: 'https://img.example/h.jpg',
      Played: { Futsal: { 'Season 9': 'Wolves' } },
    })
    .hint('keepH');
  w.row('Futsal', '9', 'Wolves', 'Player A', 'oldH');
  w.row('Futsal', '10', 'Nineveh', 'Player A', 'oldH');
  w.row('Futsal', '11', 'Nineveh', 'Player A2', 'oldH');
  w.row('Futsal', '12', 'Bulls', 'Player A', 'oldH');
  w.row('Futsal', '13', 'Bulls', 'Someone Else', 'someoneElse'); // unrelated row
  return w;
}
const hiramMap = () => mapOf(cluster({ who: 'Player A', keep: 'keepH', old: ['oldH'] }));

describe('path helpers', () => {
  it('build the exact database paths (note the space in "Line Ups")', () => {
    expect(userPath('u1')).toBe('Users/u1');
    expect(leagueUidPath('Futsal', '10', 'Nineveh', 'Player D')).toBe(
      'Futsal/10/Line Ups/Nineveh/Player D/UID',
    );
    expect(afcUidPath('Beyond the Game Turf Open Division 1 Spring 2025', 'Player B2')).toBe(
      'AFC San Jose/Seasons/Beyond the Game Turf Open Division 1 Spring 2025/Roster/Player B2/UID',
    );
    expect(playedPath('k', 'Flag Football', '3')).toBe('Users/k/Played/Flag Football/Season 3');
    expect(fantasyConfigPath('Futsal', '10')).toBe('Fantasy/Futsal/10/Config');
  });

  it('parseRosterUidPath understands league and AFC UID leaves and nothing else', () => {
    expect(parseRosterUidPath('Futsal/10/Line Ups/Nineveh/Player D/UID')).toEqual({
      kind: 'league', sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player D',
    });
    expect(parseRosterUidPath('AFC San Jose/Seasons/Spring 2025/Roster/Player B2/UID')).toEqual({
      kind: 'afc', season: 'Spring 2025', name: 'Player B2',
    });
    expect(parseRosterUidPath('Futsal/10/Line Ups/Nineveh/Player D/Goals')).toBeNull();
    expect(parseRosterUidPath('Users/k/Played/Futsal/Season 10')).toBeNull();
    expect(parseRosterUidPath('Soccer/10/Line Ups/Nineveh/X/UID')).toBeNull();
  });
});

describe('buildMergePlan: Player-A-like cluster (D1, D3, D4, D5)', () => {
  const plan = buildMergePlan(hiramMap(), hiramWorld().snap(), NOW);
  const w = byPath(plan.writes);

  it('plans no refusals and exactly 12 leaf writes', () => {
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toHaveLength(12);
  });

  it('relinks the 4 Line Ups UID leaves to the kept uid and renames no roster key', () => {
    for (const [season, team, name] of [
      ['9', 'Wolves', 'Player A'], ['10', 'Nineveh', 'Player A'],
      ['11', 'Nineveh', 'Player A2'], ['12', 'Bulls', 'Player A'],
    ]) {
      const p = leagueUidPath('Futsal', season, team, name);
      expect(w.get(p)).toEqual({ path: p, before: 'oldH', after: 'keepH' });
    }
    // The unrelated row (a different account) is never touched.
    expect(w.has(leagueUidPath('Futsal', '13', 'Bulls', 'Someone Else'))).toBe(false);
    // Only UID leaves are written under a roster: no key is renamed or created.
    const rosterWrites = plan.writes.filter((x) => !x.path.startsWith('Users/'));
    expect(rosterWrites).toHaveLength(4);
    for (const x of rosterWrites) expect(x.path).toMatch(/^Futsal\/\d+\/Line Ups\/[^/]+\/[^/]+\/UID$/);
  });

  it('adds the 4 Played entries to the kept account (D3 shape: team name)', () => {
    for (const [season, team] of [['9', 'Wolves'], ['10', 'Nineveh'], ['11', 'Nineveh'], ['12', 'Bulls']]) {
      const p = playedPath('keepH', 'Futsal', season);
      expect(p).toBe(`Users/keepH/Played/Futsal/Season ${season}`);
      expect(w.get(p)).toEqual({ path: p, before: null, after: team });
    }
  });

  it('copies the missing ProfileUrl to the kept account (D4)', () => {
    expect(w.get('Users/keepH/ProfileUrl')).toEqual({
      path: 'Users/keepH/ProfileUrl', before: null, after: 'https://img.example/h.jpg',
    });
  });

  it('stamps the old account with exactly MergedHint, MergedAt, then MergedInto LAST (D5; MergedInto is the "done" marker)', () => {
    const oldWrites = plan.writes.filter((x) => x.path.startsWith('Users/oldH/'));
    expect(oldWrites).toEqual([
      { path: 'Users/oldH/MergedHint', before: null, after: HINT },
      { path: 'Users/oldH/MergedAt', before: null, after: NOW },
      { path: 'Users/oldH/MergedInto', before: null, after: 'keepH' },
    ]);
    // ...its Played (and everything else) is untouched, and no whole-node write exists.
    expect(plan.writes.some((x) => x.path.startsWith('Users/oldH/Played'))).toBe(false);
    expect(plan.writes.some((x) => /^Users\/[^/]+$/.test(x.path))).toBe(false);
  });

  it('orders the writes so a crash midway is retried cleanly: Played, profile, roster, stamps last', () => {
    const idx = (pred: (p: string) => boolean) => paths(plan.writes).findIndex(pred);
    const last = (pred: (p: string) => boolean) => paths(plan.writes).map(pred).lastIndexOf(true);
    expect(last((p) => p.includes('/Played/'))).toBeLessThan(idx((p) => p.endsWith('/UID')));
    expect(last((p) => p.endsWith('/UID'))).toBeLessThan(idx((p) => p.startsWith('Users/oldH/Merged')));
  });

  it('every planned write passes the allowlist', () => {
    expect(() => assertMergePaths(plan.writes, hiramMap(), hiramWorld().snap())).not.toThrow();
  });

  it('summary names person, season, team and roster name - never a uid or a photo link', () => {
    const text = plan.summary.join('\n');
    expect(text).toContain('Player A');
    expect(text).toContain('Nineveh');
    expect(text).toContain('Player A2');
    expect(text).toMatch(/Season 11/);
    expect(text).not.toContain('keepH');
    expect(text).not.toContain('oldH');
    expect(text).not.toContain('img.example');
    expect(text).not.toContain('@');
  });
});

describe('buildMergePlan: ProfileUrl (D4)', () => {
  it('Player-J-like: a kept account that already has a ProfileUrl keeps it (never overwritten)', () => {
    const w = new World()
      .user('keepJ', { 'First Name': 'Player', ProfileUrl: 'https://img.example/keep.jpg' })
      .user('oldJ', { 'First Name': 'Player', ProfileUrl: 'https://img.example/old.jpg' })
      .hint('keepJ');
    w.row('Futsal', '11', 'Bulls', 'Player J', 'oldJ');
    const plan = buildMergePlan(mapOf(cluster({ who: 'Player J', keep: 'keepJ', old: ['oldJ'] })), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(paths(plan.writes)).not.toContain('Users/keepJ/ProfileUrl');
    expect(plan.writes).toHaveLength(1 + 1 + 3);
  });

  it('an empty ProfileUrl on the kept account counts as lacking', () => {
    const w = new World()
      .user('k', { ProfileUrl: '  ' })
      .user('o', { ProfileUrl: 'https://img.example/o.jpg' })
      .hint('k');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(byPath(plan.writes).get('Users/k/ProfileUrl')).toEqual({
      path: 'Users/k/ProfileUrl', before: '  ', after: 'https://img.example/o.jpg',
    });
  });

  it('with several old accounts the LAST listed one that has a ProfileUrl wins', () => {
    const w = new World()
      .user('k', { 'First Name': 'K' })
      .user('o1', { ProfileUrl: 'https://img.example/oldest.jpg' })
      .user('o2', { ProfileUrl: 'https://img.example/newest.jpg' })
      .user('o3', { 'First Name': 'No photo' })
      .hint('k');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o1', 'o2', 'o3'] })), w.snap(), NOW);
    expect(byPath(plan.writes).get('Users/k/ProfileUrl')?.after).toBe('https://img.example/newest.jpg');
  });

  it('writes no ProfileUrl when no old account has one', () => {
    const w = new World().user('k').user('o').hint('k');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(paths(plan.writes).some((p) => p.endsWith('/ProfileUrl'))).toBe(false);
  });
});

describe('buildMergePlan: AFC rows (D1, D3)', () => {
  it('Player-B-like: 3 AFC roster rows relinked, and no Played entry for AFC', () => {
    const w = new World().user('keepC').user('oldC').hint('keepC');
    const seasons = ['Open Division 1 Spring 2025', 'Open Division 1 Fall 2025', 'Open Division 2 Spring 2026'];
    seasons.forEach((s) => w.afc(s, 'Player B2', 'oldC'));
    w.afc('Open Division 1 Spring 2025', 'Teammate', 'someoneElse');
    const m = mapOf(cluster({ who: 'Player', keep: 'keepC', old: ['oldC'] }));
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    const afcWrites = plan.writes.filter((x) => x.path.startsWith('AFC San Jose/'));
    expect(afcWrites).toHaveLength(3);
    for (const s of seasons) {
      const p = afcUidPath(s, 'Player B2');
      expect(byPath(plan.writes).get(p)).toEqual({ path: p, before: 'oldC', after: 'keepC' });
    }
    expect(paths(plan.writes).some((p) => p.includes('/Played'))).toBe(false);
    expect(plan.writes).toHaveLength(3 + 3); // 3 relinks + 3 stamps
    expect(() => assertMergePaths(plan.writes, m, w.snap())).not.toThrow();
  });
});

describe('buildMergePlan: Player-E-like (Review Focus 5)', () => {
  const world = () => {
    const w = new World()
      .user('keepT', { 'First Name': 'Player' })
      .user('oldT1', { 'First Name': 'Player' })
      .user('oldT2', { 'First Name': 'Player' })
      .user('oldT3', { 'First Name': 'Player' })
      .hint('keepT');
    w.row('Futsal', '11', 'Nineveh', 'Player E', 'oldT1');
    w.row('Futsal', '12', 'Nineveh', 'Player E', 'oldT2');
    w.row('Futsal', '13', 'Nineveh', 'Player E', 'oldT2');
    w.row('Futsal', '14', 'Rams', 'Player E', 'oldT3');
    return w;
  };
  const map = () =>
    mapOf(cluster({ who: 'Player E', keep: 'keepT', old: ['oldT1', 'oldT2', 'oldT3'] }));

  it('relinks all rows of all three old accounts to the one kept uid', () => {
    const plan = buildMergePlan(map(), world().snap(), NOW);
    expect(plan.refusals).toEqual([]);
    const rosterWrites = plan.writes.filter((x) => !x.path.startsWith('Users/'));
    expect(rosterWrites).toHaveLength(4);
    expect(new Set(rosterWrites.map((x) => x.after))).toEqual(new Set(['keepT']));
    expect(new Set(rosterWrites.map((x) => x.before))).toEqual(new Set(['oldT1', 'oldT2', 'oldT3']));
  });

  it('Played gets S11, S12, S13, S14 and ProfileUrl stays absent', () => {
    const plan = buildMergePlan(map(), world().snap(), NOW);
    const played = plan.writes.filter((x) => x.path.startsWith('Users/keepT/Played/'));
    expect(played.map((x) => [x.path, x.after])).toEqual([
      ['Users/keepT/Played/Futsal/Season 11', 'Nineveh'],
      ['Users/keepT/Played/Futsal/Season 12', 'Nineveh'],
      ['Users/keepT/Played/Futsal/Season 13', 'Nineveh'],
      ['Users/keepT/Played/Futsal/Season 14', 'Rams'],
    ]);
    expect(paths(plan.writes)).not.toContain('Users/keepT/ProfileUrl');
  });

  it('stamps all three old accounts with the same kept uid and hint', () => {
    const plan = buildMergePlan(map(), world().snap(), NOW);
    const w = byPath(plan.writes);
    for (const o of ['oldT1', 'oldT2', 'oldT3']) {
      expect(w.get(`Users/${o}/MergedInto`)?.after).toBe('keepT');
      expect(w.get(`Users/${o}/MergedAt`)?.after).toBe(NOW);
      expect(w.get(`Users/${o}/MergedHint`)?.after).toBe(HINT);
    }
    expect(plan.writes).toHaveLength(4 + 4 + 9);
    expect(() => assertMergePaths(plan.writes, map(), world().snap())).not.toThrow();
  });
});

describe('buildMergePlan: name-variant rows (D1) and the name fix (D10)', () => {
  const tatariRow = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player D' };
  const world = () => {
    const w = new World().user('keepR', { 'First Name': 'Playen' }).hint('keepR');
    w.row('Futsal', '10', 'Nineveh', 'Player D', null);
    return w;
  };
  const map = () =>
    mapOf(cluster({ who: 'Player D2', keep: 'keepR', old: [], nameRows: [tatariRow] }));

  it('sets the row UID to the kept uid, adds Played Season 10, leaves the roster key alone, stamps nothing', () => {
    const plan = buildMergePlan(map(), world().snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toEqual([
      { path: 'Users/keepR/Played/Futsal/Season 10', before: null, after: 'Nineveh' },
      { path: 'Futsal/10/Line Ups/Nineveh/Player D/UID', before: null, after: 'keepR' },
    ]);
    expect(paths(plan.writes).some((p) => /Merged/.test(p))).toBe(false);
    expect(() => assertMergePaths(plan.writes, map(), world().snap())).not.toThrow();
  });

  it('refuses a name row that does not exist in the snapshot instead of creating a stray roster row', () => {
    const w = new World().user('keepR').hint('keepR'); // no roster row at all
    const plan = buildMergePlan(map(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].who).toBe('Player D2');
    expect(plan.refusals[0].why).toContain('Player D');
  });

  it('a name row already linked to the kept account is a no-op', () => {
    const w = new World().user('keepR', { Played: { Futsal: { 'Season 10': 'Nineveh' } } }).hint('keepR');
    w.row('Futsal', '10', 'Nineveh', 'Player D', 'keepR');
    const plan = buildMergePlan(map(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toEqual([]);
  });

  it('D10: firstNameFix writes exactly one Users/<keep>/First Name; clusters without it write none', () => {
    const w = world();
    w.user('keepS', { 'First Name': 'Plyer' }).user('oldS', { 'First Name': 'Plyer' }).hint('keepS');
    w.row('Futsal', '12', 'Bulls', 'Player C Variant', 'oldS');
    const m = mapOf(
      cluster({ who: 'Player C', keep: 'keepS', old: ['oldS'], firstNameFix: 'Player' }),
      cluster({ who: 'Player D2', keep: 'keepR', old: [], nameRows: [tatariRow] }),
    );
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    const fixes = plan.writes.filter((x) => x.path.endsWith('/First Name'));
    expect(fixes).toEqual([{ path: 'Users/keepS/First Name', before: 'Plyer', after: 'Player' }]);
    expect(() => assertMergePaths(plan.writes, m, w.snap())).not.toThrow();
  });

  it('D10: no write when the First Name is already the fix; an unsafe fix is refused', () => {
    const w = new World().user('k', { 'First Name': 'Player' }).user('o').hint('k');
    const ok = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'], firstNameFix: 'Player' })), w.snap(), NOW);
    expect(paths(ok.writes).some((p) => p.endsWith('/First Name'))).toBe(false);
    for (const bad of ['', '   ', 'a'.repeat(60), 'Bob\u0000']) {
      const r = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'], firstNameFix: bad })), w.snap(), NOW);
      expect(r.writes).toEqual([]);
      expect(r.refusals.length).toBeGreaterThan(0);
    }
  });
});

describe('buildMergePlan: Information and private fields (D4)', () => {
  const world = () =>
    new World()
      .user('k', { 'First Name': 'K', Information: { BasketballPosition: 'Center', Age: 30 } })
      .user('o', {
        'First Name': 'O',
        Token: 'secret-device-token',
        Email: 'old.person@example.com',
        'Phone Number': '5551230000',
        DOB: '01011990',
        Information: {
          FutsalPosition: 'Defender', BasketballPosition: 'Guard', Age: 29, Height: "5'10",
          Token: 'secret-info-token', Email: 'someone@example.com', 'Phone Number': '5559990000',
          Nested: { a: 1 }, Empty: '',
        },
      })
      .hint('k');

  it('copies only the Information leaves the kept account lacks', () => {
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), world().snap(), NOW);
    const info = plan.writes.filter((x) => x.path.startsWith('Users/k/Information/'));
    expect(info.map((x) => [x.path, x.before, x.after])).toEqual([
      ['Users/k/Information/FutsalPosition', null, 'Defender'],
      ['Users/k/Information/Height', null, "5'10"],
    ]);
  });

  it('never writes a Token, email, phone, DOB or any other private field - anywhere', () => {
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), world().snap(), NOW);
    const text = JSON.stringify(plan.writes);
    for (const secret of ['secret-device-token', 'secret-info-token', 'example.com', '5551230000', '5559990000', '01011990']) {
      expect(text).not.toContain(secret);
    }
    for (const p of paths(plan.writes)) expect(p).not.toMatch(/Token|Email|Phone|DOB|Nested|Empty/i);
    expect(() => assertMergePaths(plan.writes, mapOf(cluster({ keep: 'k', old: ['o'] })), world().snap())).not.toThrow();
  });

  it('with several old accounts the last listed value of a leaf wins', () => {
    const w = new World()
      .user('k', { 'First Name': 'K' })
      .user('o1', { Information: { FutsalPosition: 'Keeper' } })
      .user('o2', { Information: { FutsalPosition: 'Striker' } })
      .hint('k');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o1', 'o2'] })), w.snap(), NOW);
    expect(byPath(plan.writes).get('Users/k/Information/FutsalPosition')?.after).toBe('Striker');
  });
});

describe('buildMergePlan: refusals block only that cluster', () => {
  const okWorld = () => {
    const w = new World().user('keepA', { 'First Name': 'A' }).user('oldA').hint('keepA');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'oldA');
    return w;
  };
  const okCluster = () => cluster({ who: 'Ann A', keep: 'keepA', old: ['oldA'] });

  it('D2: a relink in a season whose fantasy Config exists refuses the cluster and names the season', () => {
    const w = new World().user('keepB').user('oldB').hint('keepB').user('keepA').user('oldA').hint('keepA');
    w.row('Futsal', '15', 'Zebras', 'Bob B', 'oldB').fantasy('Futsal', '15');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'oldA');
    const m = mapOf(
      cluster({ who: 'Bob B', keep: 'keepB', old: ['oldB'] }),
      cluster({ who: 'Ann A', keep: 'keepA', old: ['oldA'] }),
    );
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].who).toBe('Bob B');
    expect(plan.refusals[0].why).toContain('Futsal Season 15');
    expect(plan.refusals[0].why).toMatch(/fantasy/i);
    // Nothing for the refused cluster, everything for the other one.
    expect(plan.writes.some((x) => x.path.includes('keepB') || x.path.includes('oldB') || x.path.includes('/15/'))).toBe(false);
    expect(plan.writes.some((x) => x.path.includes('keepA'))).toBe(true);
    expect(plan.summary.join('\n')).toMatch(/Bob B.*REFUSED/);
  });

  it('D2 fails closed: a snapshot with no Config presence for a touched season refuses', () => {
    const s = okWorld().snap();
    delete s.nodes[fantasyConfigPath('Futsal', '9')];
    const plan = buildMergePlan(mapOf(okCluster()), s, NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toContain('Futsal Season 9');
  });

  it('D2 does not apply to AFC rows (no fantasy there)', () => {
    const w = new World().user('k').user('o').hint('k').afc('Spring 2025', 'Player B2', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toHaveLength(1 + 3);
  });

  it('Review Focus 2: a name row holding a third, unrelated uid is refused and never overwritten', () => {
    const w = new World().user('k').hint('k').user('third');
    w.row('Futsal', '10', 'Nineveh', 'Player D', 'third');
    const m = mapOf(cluster({
      who: 'Player D2', keep: 'k', old: [],
      nameRows: [{ sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player D' }],
    }));
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toContain('Player D');
    expect(plan.refusals[0].why).toMatch(/different account/);
    expect(plan.refusals[0].why).not.toContain('third');
  });

  it('D3: the kept account already has a different team for that sport/season -> refused', () => {
    const w = new World()
      .user('k', { Played: { Futsal: { 'Season 9': 'Rams' } } }).user('o').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    const plan = buildMergePlan(mapOf(cluster({ who: 'Ann A', keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toContain('Futsal Season 9');
    expect(plan.refusals[0].why).toContain('Rams');
    expect(plan.refusals[0].why).toContain('Wolves');
  });

  it('D3: the kept account already has the SAME team -> no Played write, the relink still happens', () => {
    const w = new World()
      .user('k', { Played: { Futsal: { 'Season 9': 'Wolves' } } }).user('o').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(paths(plan.writes).some((p) => p.includes('/Played/'))).toBe(false);
    expect(paths(plan.writes)).toContain('Futsal/9/Line Ups/Wolves/Ann A/UID');
  });

  it('two old accounts on different teams in the same season would clash in Played -> refused', () => {
    const w = new World().user('k').user('o1').user('o2').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o1');
    w.row('Futsal', '9', 'Bulls', 'Ann A', 'o2');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o1', 'o2'] })), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toContain('Futsal Season 9');
  });

  it('refuses when a listed account has no Users node, when the keep is itself merged, or merged elsewhere', () => {
    const noOld = okWorld();
    delete noOld.nodes[userPath('oldA')];
    expect(buildMergePlan(mapOf(okCluster()), noOld.snap(), NOW).refusals).toHaveLength(1);

    const noKeep = okWorld();
    delete noKeep.nodes[userPath('keepA')];
    expect(buildMergePlan(mapOf(okCluster()), noKeep.snap(), NOW).refusals.length).toBeGreaterThan(0);

    const keepMerged = okWorld().user('keepA', { MergedInto: 'someoneNew' });
    const r1 = buildMergePlan(mapOf(okCluster()), keepMerged.snap(), NOW);
    expect(r1.writes).toEqual([]);
    expect(r1.refusals[0].why).toMatch(/itself merged/);

    const oldElsewhere = okWorld().user('oldA', { MergedInto: 'someoneNew' });
    const r2 = buildMergePlan(mapOf(okCluster()), oldElsewhere.snap(), NOW);
    expect(r2.writes).toEqual([]);
    expect(r2.refusals[0].why).toMatch(/already merged into a different account/);
  });

  it('refuses a malformed map entry: keep listed as old, duplicate old, unsafe uid or name', () => {
    const w = okWorld();
    const cases: MergeCluster[] = [
      cluster({ who: 'X', keep: 'keepA', old: ['keepA'] }),
      cluster({ who: 'X', keep: 'keepA', old: ['oldA', 'oldA'] }),
      cluster({ who: 'X', keep: 'keep/A', old: ['oldA'] }),
      cluster({ who: 'X', keep: 'keepA', old: ['old.A'] }),
      cluster({ who: 'X', keep: '', old: ['oldA'] }),
      cluster({
        who: 'X', keep: 'keepA', old: [],
        nameRows: [{ sport: 'Futsal', season: '9', team: 'Wolves', name: 'a/b' }],
      }),
      cluster({
        who: 'X', keep: 'keepA', old: [],
        nameRows: [{ sport: 'Hockey', season: '9', team: 'Wolves', name: 'Ann A' }],
      }),
      cluster({
        who: 'X', keep: 'keepA', old: [],
        nameRows: [{ sport: 'Futsal', season: 'nine', team: 'Wolves', name: 'Ann A' }],
      }),
    ];
    for (const c of cases) {
      const plan = buildMergePlan(mapOf(c), w.snap(), NOW);
      expect(plan.writes, JSON.stringify(c)).toEqual([]);
      expect(plan.refusals.length, JSON.stringify(c)).toBeGreaterThan(0);
    }
  });

  it('a uid used by two clusters refuses both (no account is merged twice)', () => {
    const w = okWorld().user('keepZ').user('oldA2').hint('keepZ');
    const m = mapOf(
      okCluster(),
      cluster({ who: 'Zed', keep: 'keepZ', old: ['oldA'] }),
    );
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals.map((r) => r.who).sort()).toEqual(['Ann A', 'Zed']);
  });

  it('a missing kept hint writes no MergedHint (the fan notice falls back) but still plans the rest', () => {
    const w = okWorld();
    delete w.keptHints['keepA'];
    const plan = buildMergePlan(mapOf(okCluster()), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(paths(plan.writes)).toContain('Users/oldA/MergedInto');
    expect(paths(plan.writes)).toContain('Users/oldA/MergedAt');
    expect(paths(plan.writes)).not.toContain('Users/oldA/MergedHint');
  });

  it('a kept hint that is not masked is refused (an email must never reach the database)', () => {
    const w = okWorld();
    w.keptHints['keepA'] = 'player@example.test';
    const plan = buildMergePlan(mapOf(okCluster()), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toMatch(/not masked/);
    expect(JSON.stringify(plan.refusals)).not.toContain('carlo');
  });

  it('rejects a nowMs that is not a positive integer', () => {
    for (const bad of [0, -1, 1.5, NaN, Infinity]) {
      expect(() => buildMergePlan(mapOf(okCluster()), okWorld().snap(), bad)).toThrow(/nowMs/);
    }
  });
});

describe('buildMergePlan: running twice (Review Focus 3)', () => {
  it('after the writes land, a second plan has zero writes and zero refusals', () => {
    const tatariRow = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player D' };
    const w = hiramWorld();
    w.user('keepR', { 'First Name': 'Playen' }).hint('keepR').row('Futsal', '10', 'Nineveh', 'Player D', null);
    w.user('keepS', { 'First Name': 'Plyer' }).user('oldS', { ProfileUrl: 'https://img.example/s.jpg' }).hint('keepS');
    w.row('Futsal', '12', 'Bulls', 'Player C Variant', 'oldS');
    w.user('keepC').user('oldC').hint('keepC').afc('Spring 2025', 'Player B2', 'oldC');
    const m = mapOf(
      cluster({ who: 'Player A', keep: 'keepH', old: ['oldH'] }),
      cluster({ who: 'Player D2', keep: 'keepR', old: [], nameRows: [tatariRow] }),
      cluster({ who: 'Player C2', keep: 'keepS', old: ['oldS'], firstNameFix: 'Player' }),
      cluster({ who: 'Player', keep: 'keepC', old: ['oldC'] }),
    );
    const first = buildMergePlan(m, w.snap(), NOW);
    expect(first.refusals).toEqual([]);
    expect(first.writes.length).toBeGreaterThan(20);
    assertMergePaths(first.writes, m, w.snap());

    const after = applyTo(w.snap(), first.writes);
    const second = buildMergePlan(m, after, NOW + 60_000);
    expect(second.refusals).toEqual([]);
    expect(second.writes).toEqual([]);
    expect(second.summary.join('\n')).toMatch(/already merged|nothing to do/i);
  });

  it('a crash after Played/profile/roster but before the stamps is finished by a rerun, never duplicated', () => {
    const w = hiramWorld();
    const m = hiramMap();
    const first = buildMergePlan(m, w.snap(), NOW);
    const withoutStamps = first.writes.filter((x) => !x.path.startsWith('Users/oldH/Merged'));
    const crashed = applyTo(w.snap(), withoutStamps);
    const second = buildMergePlan(m, crashed, NOW + 5000);
    expect(second.refusals).toEqual([]);
    expect(paths(second.writes)).toEqual([
      'Users/oldH/MergedHint', 'Users/oldH/MergedAt', 'Users/oldH/MergedInto',
    ]);
    expect(byPath(second.writes).get('Users/oldH/MergedAt')?.after).toBe(NOW + 5000);
  });

  it('a stamp that already exists is never re-written (MergedAt keeps its first time)', () => {
    const w = hiramWorld().user('oldH', {
      'First Name': 'Player', MergedInto: 'keepH', MergedAt: 111, Played: { Futsal: { 'Season 9': 'Wolves' } },
      ProfileUrl: 'https://img.example/h.jpg',
    });
    const plan = buildMergePlan(hiramMap(), w.snap(), NOW);
    expect(paths(plan.writes).filter((p) => p.startsWith('Users/oldH/'))).toEqual(['Users/oldH/MergedHint']);
  });
});

describe('assertMergePaths: the allowlist', () => {
  const tatariRow = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player D' };
  const world = () => {
    const w = hiramWorld();
    w.user('keepR', { 'First Name': 'Playen' }).hint('keepR').row('Futsal', '10', 'Nineveh', 'Player D', null);
    w.user('keepS', { 'First Name': 'Plyer' }).user('oldS', { 'First Name': 'Plyer', Token: 't' }).hint('keepS');
    w.row('Futsal', '12', 'Bulls', 'Player C Variant', 'oldS');
    w.user('keepF').user('oldF').hint('keepF').row('Futsal', '15', 'Zebras', 'Fan F', 'oldF').fantasy('Futsal', '15');
    return w;
  };
  const map = () =>
    mapOf(
      cluster({ who: 'Player A', keep: 'keepH', old: ['oldH'] }),
      cluster({ who: 'Player D2', keep: 'keepR', old: [], nameRows: [tatariRow] }),
      cluster({ who: 'Player C2', keep: 'keepS', old: ['oldS'], firstNameFix: 'Player' }),
      cluster({ who: 'Fan F', keep: 'keepF', old: ['oldF'] }),
    );
  const snap = () => world().snap();
  const w = (path: string, before: unknown, after: unknown): PlanWrite => ({ path, before, after });
  const reject = (writes: PlanWrite[], why?: RegExp) =>
    expect(() => assertMergePaths(writes, map(), snap())).toThrow(why ?? /Refusing merge path/);

  it('accepts what the planner produced for every non-refused cluster', () => {
    const plan = buildMergePlan(map(), snap(), NOW);
    expect(plan.refusals.map((r) => r.who)).toEqual(['Fan F']);
    expect(() => assertMergePaths(plan.writes, map(), snap())).not.toThrow();
  });

  it('rejects Users/<keep>/Token and any private leaf of a kept or old account', () => {
    reject([w('Users/keepH/Token', null, 'x')]);
    for (const leaf of ['Email', 'Phone Number', 'DOB', 'Last Name', 'Played/Futsal/Season 99', 'MergedInto']) {
      reject([w(`Users/keepH/${leaf}`, null, 'x')]);
    }
    for (const leaf of ['Token', 'ProfileUrl', 'Played/Futsal/Season 9', 'First Name', 'Information/Age']) {
      reject([w(`Users/oldH/${leaf}`, null, 'x')]);
    }
  });

  it('rejects any whole-node Users/<uid> write or delete, and any removal', () => {
    reject([w('Users/keepH', { 'First Name': 'Player' }, { 'First Name': 'Player', X: 1 })]);
    reject([w('Users/oldH', { 'First Name': 'Player' }, null)]);
    reject([w('Users', null, { a: 1 })]);
    reject([w('Users/oldH/MergedInto', null, null)], /remov|null/i);
    reject([w('Futsal/9/Line Ups/Wolves/Player A/UID', 'oldH', null)], /remov|null/i);
  });

  it('rejects any uid that is not in the map', () => {
    reject([w('Users/stranger/MergedInto', null, 'keepH')]);
    reject([w('Users/stranger/ProfileUrl', null, 'https://img.example/h.jpg')]);
    reject([w('Futsal/9/Line Ups/Wolves/Player A/UID', 'oldH', 'stranger')], /kept account/);
  });

  it('D10: First Name only for the cluster that has firstNameFix, and only with that value', () => {
    expect(() => assertMergePaths([w('Users/keepS/First Name', 'Plyer', 'Player')], map(), snap())).not.toThrow();
    reject([w('Users/keepH/First Name', 'Player', 'Player')]);
    reject([w('Users/keepR/First Name', 'Playen', 'Player')]);
    reject([w('Users/oldS/First Name', 'Plyer', 'Player')]);
    reject([w('Users/keepS/First Name', 'Plyer', 'Players')]);
  });

  it('D2: rejects a relink in a fantasy season and one with no Config presence recorded', () => {
    reject([w('Futsal/15/Line Ups/Zebras/Fan F/UID', 'oldF', 'keepF'), w('Users/keepF/Played/Futsal/Season 15', null, 'Zebras')], /fantasy|Season 15/i);
    const s = snap();
    delete s.nodes[fantasyConfigPath('Futsal', '9')];
    expect(() =>
      assertMergePaths([w('Futsal/9/Line Ups/Wolves/Player A/UID', 'oldH', 'keepH')], map(), s),
    ).toThrow(/Season 9/);
  });

  it('roster relinks: only old uid (or an empty name row) -> the same cluster\'s keep', () => {
    const ok = w('Futsal/9/Line Ups/Wolves/Player A/UID', 'oldH', 'keepH');
    expect(() => assertMergePaths([ok], map(), snap())).not.toThrow();
    // old uid of one cluster handed to another cluster's keep
    reject([w('Futsal/9/Line Ups/Wolves/Player A/UID', 'oldH', 'keepS')]);
    // a third uid is never overwritten (the snapshot value would also differ)
    reject([w('Futsal/13/Line Ups/Bulls/Someone Else/UID', 'someoneElse', 'keepH')]);
    // an empty row that is not a listed name row
    const s = snap();
    s.nodes[leagueUidPath('Futsal', '9', 'Wolves', 'Nobody')] = null;
    expect(() =>
      assertMergePaths([w('Futsal/9/Line Ups/Wolves/Nobody/UID', null, 'keepH')], map(), s),
    ).toThrow(/Refusing merge path/);
    // the listed name row is fine
    expect(() =>
      assertMergePaths([
        w('Futsal/10/Line Ups/Nineveh/Player D/UID', null, 'keepR'),
        w('Users/keepR/Played/Futsal/Season 10', null, 'Nineveh'),
      ], map(), snap()),
    ).not.toThrow();
    // roster nodes other than the UID leaf
    reject([w('Futsal/9/Line Ups/Wolves/Player A', { UID: 'oldH' }, { UID: 'keepH' })]);
    reject([w('Futsal/9/Line Ups/Wolves/Player A/Goals', null, 3)]);
  });

  it('a stale write (before differs from the snapshot) is rejected', () => {
    reject([w('Futsal/9/Line Ups/Wolves/Player A/UID', 'someoneNew', 'keepH')], /snapshot/);
    reject([w('Users/keepH/ProfileUrl', 'https://img.example/x.jpg', 'https://img.example/h.jpg')], /snapshot/);
  });

  it('Played: only for a kept account, only league sports, only with a matching relink, never over a value', () => {
    const relink = w('Futsal/9/Line Ups/Wolves/Player A/UID', 'oldH', 'keepH');
    expect(() => assertMergePaths([relink, w('Users/keepH/Played/Futsal/Season 9', null, 'Wolves')], map(), snap())).not.toThrow();
    reject([w('Users/keepH/Played/Futsal/Season 9', null, 'Wolves')], /relink/i);
    reject([relink, w('Users/keepH/Played/Futsal/Season 9', null, 'Bulls')], /relink/i);
    reject([relink, w('Users/keepH/Played/Hockey/Season 9', null, 'Wolves')]);
    reject([relink, w('Users/keepH/Played/AFC San Jose/Season 9', null, 'Wolves')]);
    reject([relink, w('Users/keepH/Played/Futsal/Season 15', 'Zebras', 'Wolves')]);
  });

  it('ProfileUrl: only a missing one, only a value an old account of the cluster has', () => {
    expect(() => assertMergePaths([w('Users/keepH/ProfileUrl', null, 'https://img.example/h.jpg')], map(), snap())).not.toThrow();
    reject([w('Users/keepH/ProfileUrl', null, 'https://evil.example/x.jpg')]);
    reject([w('Users/keepH/ProfileUrl', null, 42)]);
    // oldS has no ProfileUrl, so nothing can be copied to keepS
    reject([w('Users/keepS/ProfileUrl', null, 'https://img.example/h.jpg')]);
  });

  it('Information: only safe leaves whose value an old account has; never Token or email-like keys', () => {
    const s = snap();
    s.nodes[userPath('oldH')] = {
      'First Name': 'Player',
      Information: { FutsalPosition: 'Defender', Token: 'abc', EmailAddress: 'a@b.co', 'Phone Number': '1' },
    };
    const ok = w('Users/keepH/Information/FutsalPosition', null, 'Defender');
    expect(() => assertMergePaths([ok], map(), s)).not.toThrow();
    for (const leaf of ['Token', 'EmailAddress', 'Phone Number']) {
      const v = (s.nodes[userPath('oldH')] as { Information: Record<string, unknown> }).Information[leaf];
      expect(() => assertMergePaths([w(`Users/keepH/Information/${leaf}`, null, v)], map(), s)).toThrow(/Refusing merge path/);
    }
    expect(() => assertMergePaths([w('Users/keepH/Information/FutsalPosition', null, 'Keeper')], map(), s)).toThrow(/Refusing/);
    expect(() => assertMergePaths([w('Users/keepH/Information', null, { FutsalPosition: 'Defender' })], map(), s)).toThrow(/Refusing/);
  });

  it('stamps: MergedInto is the cluster keep, MergedAt a number, MergedHint exactly the masked hint', () => {
    expect(() =>
      assertMergePaths([
        w('Users/oldH/MergedInto', null, 'keepH'), w('Users/oldH/MergedAt', null, NOW), w('Users/oldH/MergedHint', null, HINT),
      ], map(), snap()),
    ).not.toThrow();
    reject([w('Users/oldH/MergedInto', null, 'keepS')]);
    reject([w('Users/oldH/MergedAt', null, '1800000000000')]);
    reject([w('Users/oldH/MergedAt', null, -5)]);
    reject([w('Users/oldH/MergedHint', null, 'player@example.test')]);
    reject([w('Users/oldH/MergedHint', null, 'xx••@gmail.com')]);
    reject([w('Users/oldH/MergedInto', 'keepH', 'keepH')], /snapshot|before/i);
  });

  it('rejects a path written twice, a non-string path and an unrelated node', () => {
    const a = w('Users/oldH/MergedInto', null, 'keepH');
    reject([a, { ...a }], /twice/);
    reject([{ path: 42 as unknown as string, before: null, after: 'x' }]);
    for (const p of ['PublicProfiles/oldH', 'Fantasy/Futsal/15/Config', 'MergeNotices/oldH', 'Campaigns/x', 'Sign Ups/y', 'Users/oldH/Played']) {
      reject([w(p, null, 'x')]);
    }
  });

  it('a uid that is both kept and old in the map allows nothing (the map itself is refused)', () => {
    const m = mapOf(cluster({ keep: 'dup', old: ['dup'] }));
    const s = new World().user('dup').hint('dup').snap();
    expect(() => assertMergePaths([w('Users/dup/MergedInto', null, 'dup')], m, s)).toThrow(/Refusing merge map/);
  });

  it('every planned write of a bigger fixture still passes after rebuilding with a different clock', () => {
    const plan = buildMergePlan(map(), snap(), NOW + 1);
    expect(() => assertMergePaths(plan.writes, map(), snap())).not.toThrow();
    expect(plan.writes.every((x) => !isDeepStrictEqual(x.before, x.after))).toBe(true);
  });
});

// ===================================================================
// Fix round 1 (controller rulings 1-6 on the Task 4 review)
// ===================================================================

describe('fix 1: exact stamp before-values; only absent/null counts as missing', () => {
  const stampWorld = (oldFields: Record<string, unknown>) => {
    const w = new World().user('k').user('o', { 'First Name': 'O', ...oldFields }).hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    return w;
  };
  const planFor = (oldFields: Record<string, unknown>) =>
    buildMergePlan(mapOf(cluster({ who: 'Ann A', keep: 'k', old: ['o'] })), stampWorld(oldFields).snap(), NOW);

  it('a fresh old account gets the three stamps with before null', () => {
    const stamps = planFor({}).writes.filter((x) => x.path.startsWith('Users/o/'));
    expect(stamps).toEqual([
      { path: 'Users/o/MergedHint', before: null, after: HINT },
      { path: 'Users/o/MergedAt', before: null, after: NOW },
      { path: 'Users/o/MergedInto', before: null, after: 'k' },
    ]);
  });

  it('MergedInto is the LAST write of every old account, and a crash before it leaves only a harmless partial state a re-run finishes', () => {
    const w = new World().user('k').user('o1').user('o2').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o1');
    const m = mapOf(cluster({ who: 'Ann A', keep: 'k', old: ['o1', 'o2'] }));
    const plan = buildMergePlan(m, w.snap(), NOW);
    for (const o of ['o1', 'o2']) {
      const mine = paths(plan.writes).filter((p) => p.startsWith(`Users/${o}/`));
      expect(mine, o).toEqual([`Users/${o}/MergedHint`, `Users/${o}/MergedAt`, `Users/${o}/MergedInto`]);
    }
    // Stamps are the end of the cluster, after every relink and Played write.
    const firstStamp = paths(plan.writes).findIndex((p) => p.includes('/Merged'));
    expect(paths(plan.writes).slice(firstStamp).every((p) => p.includes('/Merged'))).toBe(true);
    // Crash after the hint and the time but before MergedInto: no 'done' marker yet.
    const partial = applyTo(w.snap(), plan.writes.filter((x) => !x.path.endsWith('/MergedInto')));
    const rerun = buildMergePlan(m, partial, NOW + 9000);
    expect(rerun.refusals).toEqual([]);
    expect(paths(rerun.writes)).toEqual(['Users/o1/MergedInto', 'Users/o2/MergedInto']);
  });

  it('non-empty existing stamps count as already stamped and are left alone', () => {
    const plan = planFor({ MergedInto: 'k', MergedAt: 123, MergedHint: 'zz••@old.example' });
    expect(plan.refusals).toEqual([]);
    expect(paths(plan.writes).filter((p) => p.startsWith('Users/o/'))).toEqual([]);
  });

  it('a blank or non-string stamp value refuses the cluster with a plain reason', () => {
    const bad: Array<Record<string, unknown>> = [
      { MergedInto: '' }, { MergedInto: '   ' }, { MergedInto: 5 }, { MergedInto: { a: 1 } },
      { MergedAt: '' }, { MergedAt: '1800000000000' }, { MergedAt: 0 }, { MergedAt: -4 }, { MergedAt: { a: 1 } },
      { MergedHint: '' }, { MergedHint: '  ' }, { MergedHint: 7 }, { MergedHint: ['x'] },
    ];
    for (const fields of bad) {
      const plan = planFor(fields);
      expect(plan.writes, JSON.stringify(fields)).toEqual([]);
      expect(plan.refusals, JSON.stringify(fields)).toHaveLength(1);
      expect(plan.refusals[0].why).toMatch(/unexpected (MergedInto|MergedAt|MergedHint) value/);
    }
  });

  it('a stamp over a blank value is never allowlisted (before must still be empty)', () => {
    const s = stampWorld({ MergedHint: '' }).snap();
    const m = mapOf(cluster({ who: 'Ann A', keep: 'k', old: ['o'] }));
    expect(() => assertMergePaths([{ path: 'Users/o/MergedHint', before: '', after: HINT }], m, s)).toThrow(/Refusing merge path/);
  });
});

describe('fix 2: looksMasked is exactly what maskEmail produces', () => {
  it('every maskEmail output of a valid email passes', () => {
    const emails = [
      'testplayer12@example.test', 'ab@x.org', 'a@x.org', 'abc@x.org', 'abcd@x.org',
      'abcdefghij@x.org', 'abcdefghijk@x.org', 'jo@Mail.Example.CO.uk', '😀😀😀😀@x.org',
      '@x.org', 'first.last+tag@sub.domain.co.uk', 'x_y-z@a.b',
    ];
    for (const e of emails) {
      const hint = maskEmail(e);
      expect(looksMasked(hint), hint).toBe(true);
    }
  });

  it('a raw email, an over-long visible part, too many bullets or a bad shape fails', () => {
    for (const bad of [
      'testplayer12@example.test', 'testplayer12•@example.test', 'testp•@example.test', 'ab@x.org', 'a@x.org',
      '•••••••••@x.org', 'ca•••••••••@x.org', 'ca••@', 'ca••@x@y.org', 'ca••@x y.org', ' ca••@x.org',
      '••••••', 'ca••@x.org\n', 'c•a••@x.org', '', 'ca••••••••', 42, null, undefined, {},
    ]) {
      expect(looksMasked(bad), String(bad)).toBe(false);
    }
  });

  it('the planner refuses an almost-masked hint', () => {
    const w = new World().user('k').user('o').hint('k', 'testplayer12•@example.test');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toMatch(/not masked/);
  });
});

describe('fix 3: the summary says what will actually happen', () => {
  const playedLines = (summary: string[]) => summary.filter((l) => /seasons played/.test(l));

  it('one seasons-played line per planned Played write, naming the season and team', () => {
    const plan = buildMergePlan(hiramMap(), hiramWorld().snap(), NOW);
    const lines = playedLines(plan.summary);
    expect(lines).toHaveLength(4);
    expect(lines.join('\n')).toMatch(/Futsal Season 11 \(Nineveh\)/);
    expect(plan.summary.filter((l) => /relink/.test(l))).toHaveLength(4);
    expect(plan.summary.filter((l) => /relink/.test(l)).some((l) => /seasons played/.test(l))).toBe(false);
  });

  it('no seasons-played line when the kept account already has that team', () => {
    const w = new World().user('k', { Played: { Futsal: { 'Season 9': 'Wolves' } } }).user('o').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.summary.some((l) => /relink Futsal Season 9, Wolves, "Ann A"/.test(l))).toBe(true);
    expect(playedLines(plan.summary)).toEqual([]);
  });

  it('two old rows in one season on the same team: two relinks, ONE seasons-played line', () => {
    const w = new World().user('k').user('o1').user('o2').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o1');
    w.row('Futsal', '9', 'Wolves', 'Ann Alt', 'o2');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o1', 'o2'] })), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.summary.filter((l) => /relink/.test(l))).toHaveLength(2);
    expect(playedLines(plan.summary)).toHaveLength(1);
    expect(plan.writes.filter((x) => x.path.includes('/Played/'))).toHaveLength(1);
  });

  it('AFC rows never claim a seasons-played entry', () => {
    const w = new World().user('k').user('o').hint('k').afc('Spring 2025', 'Player B2', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.summary.some((l) => /relink AFC San Jose "Spring 2025", "Player B2"/.test(l))).toBe(true);
    expect(playedLines(plan.summary)).toEqual([]);
  });

  it('an already-merged or refused cluster mentions no seasons played', () => {
    const refused = new World().user('k', { Played: { Futsal: { 'Season 9': 'Rams' } } }).user('o').hint('k');
    refused.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), refused.snap(), NOW);
    expect(playedLines(plan.summary)).toEqual([]);
  });
});

describe('fix 4: name rows are read from the row NODE', () => {
  const row = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Player D' };
  const rowNodePath = 'Futsal/10/Line Ups/Nineveh/Player D';
  const m = () => mapOf(cluster({ who: 'Player D2', keep: 'keepR', old: [], nameRows: [row] }));
  const base = () => new World().user('keepR', { 'First Name': 'Playen' }).hint('keepR');

  it('refuses when only the UID leaf is in the snapshot (the row node is absent)', () => {
    const w = base();
    w.nodes[leagueUidPath('Futsal', '10', 'Nineveh', 'Player D')] = null;
    w.nodes[fantasyConfigPath('Futsal', '10')] = null;
    const plan = buildMergePlan(m(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toMatch(/not found/);
    expect(plan.refusals[0].why).toContain('Player D');
  });

  it('refuses when the row node is not a map', () => {
    for (const bad of ['oops', 5, true, ['UID'], null]) {
      const w = base();
      w.row('Futsal', '10', 'Nineveh', 'Player D', null);
      w.nodes[rowNodePath] = bad;
      const plan = buildMergePlan(m(), w.snap(), NOW);
      expect(plan.writes, JSON.stringify(bad)).toEqual([]);
      expect(plan.refusals[0].why).toMatch(/not found/);
    }
  });

  it('the relink write stays the UID leaf and its before is row.UID ?? null', () => {
    const w = base();
    w.row('Futsal', '10', 'Nineveh', 'Player D', null);
    const none = buildMergePlan(m(), w.snap(), NOW);
    expect(none.writes.find((x) => x.path.endsWith('/UID'))).toEqual({
      path: `${rowNodePath}/UID`, before: null, after: 'keepR',
    });
    w.nodes[rowNodePath] = { UID: '', Position: 'Forward' };
    const blank = buildMergePlan(m(), w.snap(), NOW);
    expect(blank.writes.find((x) => x.path.endsWith('/UID'))).toEqual({
      path: `${rowNodePath}/UID`, before: '', after: 'keepR',
    });
    expect(() => assertMergePaths(blank.writes, m(), w.snap())).not.toThrow();
  });

  it('a row node holding a third uid is refused even if the leaf key is absent', () => {
    const w = base();
    w.nodes[rowNodePath] = { UID: 'someoneNew' };
    w.nodes[fantasyConfigPath('Futsal', '10')] = null;
    const plan = buildMergePlan(m(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toMatch(/different account/);
  });

  it('a snapshot whose row node and UID leaf disagree is refused', () => {
    const w = base();
    w.row('Futsal', '10', 'Nineveh', 'Player D', null);
    w.nodes[leagueUidPath('Futsal', '10', 'Nineveh', 'Player D')] = 'oldX';
    const plan = buildMergePlan(m(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toMatch(/disagrees/);
  });

  it('assertMergePaths also needs the row node, and rejects a row/leaf disagreement', () => {
    const w = base();
    w.row('Futsal', '10', 'Nineveh', 'Player D', null);
    const plan = buildMergePlan(m(), w.snap(), NOW);
    expect(() => assertMergePaths(plan.writes, m(), w.snap())).not.toThrow();
    const noRow = w.snap();
    delete noRow.nodes[rowNodePath];
    expect(() => assertMergePaths(plan.writes, m(), noRow)).toThrow(/Refusing merge path/);
    const split = w.snap();
    split.nodes[`${rowNodePath}/UID`] = 'oldX';
    expect(() => assertMergePaths(plan.writes, m(), split)).toThrow(/disagrees|snapshot/);
  });
});

describe('fix 5: assertMergePaths validates the map it is given', () => {
  const okCluster = (over: Partial<MergeCluster> = {}) =>
    cluster({ who: 'A', keep: 'keepA', old: ['oldA'], ...over });
  const s = () => new World().user('keepA').user('oldA').hint('keepA').snap();
  const bad = (m: MergeMap) => expect(() => assertMergePaths([], m, s())).toThrow(/Refusing merge map/);

  it('accepts a sound map (even with no writes)', () => {
    expect(() => assertMergePaths([], mapOf(okCluster()), s())).not.toThrow();
    expect(() =>
      assertMergePaths([], mapOf(okCluster(), cluster({ who: 'B', keep: 'keepB', old: [], firstNameFix: 'Player' })), s()),
    ).not.toThrow();
  });

  it('rejects uids that are not plain database keys', () => {
    for (const uid of ['', 'a/b', 'a.b', 'a#b', 'a$b', 'a[b', 'a b', 'ünï', 'x'.repeat(200)]) {
      bad(mapOf(okCluster({ keep: uid })));
      bad(mapOf(okCluster({ old: [uid] })));
    }
    bad(mapOf(okCluster({ old: 'oldA' as unknown as string[] })));
    bad({ clusters: 'nope' } as unknown as MergeMap);
  });

  it('rejects a uid in two clusters, listed twice, or as both keep and old', () => {
    bad(mapOf(okCluster(), cluster({ who: 'B', keep: 'keepB', old: ['oldA'] })));
    bad(mapOf(okCluster(), cluster({ who: 'B', keep: 'keepA', old: [] })));
    bad(mapOf(okCluster(), cluster({ who: 'B', keep: 'keepB', old: ['keepA'] })));
    bad(mapOf(okCluster({ old: ['keepA'] })));
    bad(mapOf(okCluster({ old: ['oldA', 'oldA'] })));
  });

  it('rejects more than one cluster with a firstNameFix', () => {
    bad(mapOf(
      okCluster({ firstNameFix: 'Player' }),
      cluster({ who: 'B', keep: 'keepB', old: [], firstNameFix: 'Players' }),
    ));
  });

  it('rejects a firstNameFix that is empty or holds / . # $ [ ] (or control characters)', () => {
    for (const fix of ['', ' ', 'Rob/ert', 'Rob.ert', 'Rob#ert', 'Rob$ert', 'Rob[ert', 'Rob]ert', 'Rob\u0001', 'x'.repeat(50)]) {
      bad(mapOf(okCluster({ firstNameFix: fix })));
    }
  });

  it('rejects a malformed name row', () => {
    bad(mapOf(okCluster({ nameRows: [{ sport: 'Hockey', season: '1', team: 'T', name: 'N' }] })));
    bad(mapOf(okCluster({ nameRows: [{ sport: 'Futsal', season: 'x', team: 'T', name: 'N' }] })));
    bad(mapOf(okCluster({ nameRows: [{ sport: 'Futsal', season: '1', team: 'T/U', name: 'N' }] })));
    bad(mapOf(okCluster({ nameRows: [{ sport: 'Futsal', season: '1', team: 'T', name: '' }] })));
  });

  it('a bad map throws even when the writes themselves look fine', () => {
    const w = hiramWorld();
    const m = mapOf(
      cluster({ who: 'Player A', keep: 'keepH', old: ['oldH'] }),
      cluster({ who: 'Dup', keep: 'keepZ', old: ['oldH'] }),
    );
    const good = buildMergePlan(hiramMap(), w.snap(), NOW);
    expect(() => assertMergePaths(good.writes, hiramMap(), w.snap())).not.toThrow();
    expect(() => assertMergePaths(good.writes, m, w.snap())).toThrow(/Refusing merge map/);
  });

  it('the planner agrees: a firstNameFix with banned characters, or two fixes, is refused', () => {
    const w = new World().user('k').user('o').user('k2').user('o2').hint('k').hint('k2');
    const one = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'], firstNameFix: 'Rob.ert' })), w.snap(), NOW);
    expect(one.writes).toEqual([]);
    expect(one.refusals).toHaveLength(1);
    const two = buildMergePlan(
      mapOf(
        cluster({ who: 'One', keep: 'k', old: ['o'], firstNameFix: 'Player' }),
        cluster({ who: 'Two', keep: 'k2', old: ['o2'], firstNameFix: 'Players' }),
      ),
      w.snap(),
      NOW,
    );
    expect(two.writes).toEqual([]);
    expect(two.refusals.map((r) => r.who).sort()).toEqual(['One', 'Two']);
  });
});

describe('fix 6: a scalar Played / Information parent refuses the cluster (never wiped)', () => {
  const withKeep = (fields: Record<string, unknown>) => {
    const w = new World().user('k', { 'First Name': 'K', ...fields }).user('o', {
      'First Name': 'O', Information: { FutsalPosition: 'Defender' },
    }).hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    return w;
  };
  const m = () => mapOf(cluster({ who: 'Ann A', keep: 'k', old: ['o'] }));

  it('Played that exists but is not a map is refused', () => {
    for (const played of ['x', 5, true, ['a']]) {
      const plan = buildMergePlan(m(), withKeep({ Played: played, Information: { FutsalPosition: 'Keeper' } }).snap(), NOW);
      expect(plan.writes, JSON.stringify(played)).toEqual([]);
      expect(plan.refusals).toHaveLength(1);
      expect(plan.refusals[0].why).toMatch(/Played/);
    }
  });

  it('Played/<Sport> that exists but is not a map is refused', () => {
    const plan = buildMergePlan(m(), withKeep({ Played: { Futsal: 'x' }, Information: { FutsalPosition: 'Keeper' } }).snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toMatch(/Played.*Futsal|Futsal.*Played/);
  });

  it('a scalar elsewhere under Played, or null/absent parents, do not refuse', () => {
    const fine = [{ Played: { Basketball: 'x' } }, { Played: null }, {}, { Played: { Futsal: null } }];
    for (const f of fine) {
      const plan = buildMergePlan(m(), withKeep({ ...f, Information: { FutsalPosition: 'Keeper' } }).snap(), NOW);
      expect(plan.refusals, JSON.stringify(f)).toEqual([]);
      expect(paths(plan.writes)).toContain('Users/k/Played/Futsal/Season 9');
    }
  });

  it('a scalar Played does not matter when no Played write is planned (AFC only)', () => {
    const w = new World().user('k', { Played: 'x' }).user('o').hint('k').afc('Spring 2025', 'Player B2', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toHaveLength(1 + 3);
  });

  it('Information that exists but is not a map is refused when there is something to copy', () => {
    for (const info of ['x', 5, ['a']]) {
      const plan = buildMergePlan(m(), withKeep({ Information: info }).snap(), NOW);
      expect(plan.writes, JSON.stringify(info)).toEqual([]);
      expect(plan.refusals).toHaveLength(1);
      expect(plan.refusals[0].why).toMatch(/Information/);
    }
    const nothing = new World().user('k', { Information: 'x' }).user('o').hint('k');
    nothing.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    expect(buildMergePlan(m(), nothing.snap(), NOW).refusals).toEqual([]);
  });

  it('assertMergePaths refuses the same writes independently', () => {
    const relink = { path: 'Futsal/9/Line Ups/Wolves/Ann A/UID', before: 'o', after: 'k' };
    const played = { path: 'Users/k/Played/Futsal/Season 9', before: null, after: 'Wolves' };
    for (const fields of [{ Played: 'x' }, { Played: { Futsal: 'x' } }]) {
      expect(() => assertMergePaths([played, relink], m(), withKeep(fields).snap())).toThrow(/Refusing merge path/);
    }
    const info = { path: 'Users/k/Information/FutsalPosition', before: null, after: 'Defender' };
    expect(() => assertMergePaths([info], m(), withKeep({ Information: 'x' }).snap())).toThrow(/Refusing merge path/);
    expect(() => assertMergePaths([played, relink, info], m(), withKeep({}).snap())).not.toThrow();
  });
});

describe('final fix 4: refuse a cluster when an old account has data the merge would not move', () => {
  const m = () => mapOf(cluster({ who: 'Ann A', keep: 'k', old: ['o'] }));
  const base = (oldFields: Record<string, unknown> = {}) => {
    const w = new World().user('k', { 'First Name': 'K' }).user('o', { 'First Name': 'O', ...oldFields }).hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    return w;
  };
  const refusedOnce = (snap: MergeSnapshot, why: RegExp) => {
    const plan = buildMergePlan(m(), snap, NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toMatch(why);
    return plan;
  };

  it('a clean old account is planned exactly as before', () => {
    const plan = buildMergePlan(m(), base().snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.writes.length).toBeGreaterThan(0);
  });

  it('refuses an old account with non-empty Awards (reason has no values)', () => {
    for (const awards of [{ a1: { Tier: 'gold-secret' } }, 'x', 5, true, ['a']]) {
      const plan = refusedOnce(base({ Awards: awards }).snap(), /Awards/);
      expect(plan.refusals[0].why).not.toContain('gold-secret');
    }
  });

  it('refuses an old account with non-empty TournamentsPlayed', () => {
    for (const t of [{ t1: 'Cup' }, 'x', 7, ['a']]) refusedOnce(base({ TournamentsPlayed: t }).snap(), /TournamentsPlayed/);
  });

  it('empty or absent Awards / TournamentsPlayed do not refuse, and the KEPT account may have them', () => {
    for (const v of [undefined, null, '', '  ', {}, []]) {
      const plan = buildMergePlan(m(), base({ Awards: v, TournamentsPlayed: v }).snap(), NOW);
      expect(plan.refusals, JSON.stringify(v)).toEqual([]);
    }
    const w = new World().user('k', { Awards: { a: { Tier: 'gold' } }, TournamentsPlayed: { t: 'Cup' } }).user('o').hint('k');
    w.row('Futsal', '9', 'Wolves', 'Ann A', 'o');
    expect(buildMergePlan(m(), w.snap(), NOW).refusals).toEqual([]);
  });

  it('refuses a fantasy manager entry of an old account in ANY season with a Config (even one the merge does not touch)', () => {
    const plan = refusedOnce(base().manager('Futsal', '15', 'o').snap(), /fantasy manager/);
    expect(plan.refusals[0].why).toMatch(/Futsal Season 15/);
  });

  it('a manager entry of ANOTHER account, or a manager entry in a season with no Config, does not refuse', () => {
    expect(buildMergePlan(m(), base().manager('Futsal', '15', 'someoneElse').snap(), NOW).refusals).toEqual([]);
    const w = base();
    w.nodes['Fantasy/Futsal'] = { '14': true };
    w.nodes['Fantasy/Futsal/14/Config'] = null;
    w.nodes['Fantasy/Futsal/14/Managers'] = { o: true };
    expect(buildMergePlan(m(), w.snap(), NOW).refusals).toEqual([]);
  });

  it('refuses a registration submission of an old account (reason names no form and no value)', () => {
    const plan = refusedOnce(base().registration('Futsal-16', ['o', 'x']).snap(), /registration/);
    expect(plan.refusals[0].why).not.toContain('Futsal-16');
    // A submission of another account or of the kept account is not ours to refuse.
    expect(buildMergePlan(m(), base().registration('Futsal-16', ['x', 'k']).snap(), NOW).refusals).toEqual([]);
  });

  it('fails closed: a snapshot that never checked fantasy managers or registrations refuses the cluster', () => {
    const noListing = base().snap();
    delete noListing.nodes['Fantasy/Futsal'];
    refusedOnce(noListing, /fantasy season listing/);

    const noConfig = base().manager('Futsal', '15', 'someoneElse').snap();
    delete noConfig.nodes['Fantasy/Futsal/15/Config'];
    refusedOnce(noConfig, /fantasy Config check/);

    const noManagers = base().manager('Futsal', '15', 'someoneElse').snap();
    delete noManagers.nodes['Fantasy/Futsal/15/Managers'];
    refusedOnce(noManagers, /fantasy manager check/);

    const noRegistrations = base().snap();
    delete noRegistrations.nodes['Registrations'];
    refusedOnce(noRegistrations, /registration check/);

    const noSubmissions = base().registration('Futsal-16', ['x']).snap();
    delete noSubmissions.nodes['Registrations/Futsal-16/Submissions'];
    refusedOnce(noSubmissions, /registration check/);
  });

  it('a refused cluster blocks only itself; a cluster with no old account needs none of these checks', () => {
    const w = base({ Awards: { a: 1 } }).user('k2', { 'First Name': 'K2' }).hint('k2');
    w.row('Futsal', '10', 'Bulls', 'Row Name', null);
    const map = mapOf(
      cluster({ who: 'Ann A', keep: 'k', old: ['o'] }),
      cluster({ who: 'Row Person', keep: 'k2', old: [], nameRows: [{ sport: 'Futsal', season: '10', team: 'Bulls', name: 'Row Name' }] }),
    );
    const snap = w.snap();
    const plan = buildMergePlan(map, snap, NOW);
    expect(plan.refusals.map((r) => r.who)).toEqual(['Ann A']);
    expect(plan.writes.some((x) => x.after === 'k2')).toBe(true);

    const bare = new World().user('k2', { 'First Name': 'K2' }).hint('k2');
    bare.row('Futsal', '10', 'Bulls', 'Row Name', null);
    const s2 = bare.snap();
    delete s2.nodes['Registrations'];
    for (const sp of LEAGUE_SPORTS) delete s2.nodes[`Fantasy/${sp}`];
    const solo = mapOf(cluster({ who: 'Row Person', keep: 'k2', old: [], nameRows: [{ sport: 'Futsal', season: '10', team: 'Bulls', name: 'Row Name' }] }));
    expect(buildMergePlan(solo, s2, NOW).refusals).toEqual([]);
  });
});

// ===================================================================
// Merge extension (Parlevino) - Task 1: E1 relinks in the fantasy TEST season,
// E2 old sign-up records move to the kept account.
// ===================================================================

/** A Parlevino-like person: one old account on four Futsal rosters (Season 15
 *  is the fantasy test season), a Paid sign-up record for each of Seasons 12-15
 *  under the old account, and a Season 16 record on the kept account. */
function parleWorld(): World {
  const w = new World()
    .user('keepP', { 'First Name': 'Paul' })
    .user('oldP', { 'First Name': 'Paul' })
    .hint('keepP');
  w.row('Futsal', '12', 'Nineveh', 'Paul P', 'oldP');
  w.row('Futsal', '13', 'Hakkari', 'Paul P', 'oldP');
  w.row('Futsal', '14', 'Nimrod', 'Paul P', 'oldP');
  w.row('Futsal', '15', 'Ishtar', 'Paul P', 'oldP');
  w.testFill('Futsal', '15');
  for (const s of ['12', '13', '14', '15']) w.signUp('Futsal', s, 'Paid', 'oldP', 'Paul P');
  w.signUp('Futsal', '16', 'Paid', 'keepP', 'Paul P');
  return w;
}
const parleMap = (over: Partial<MergeCluster> = {}) =>
  mapOf(cluster({ who: 'Paul P', keep: 'keepP', old: ['oldP'], ...over }));
const signUpWrites = (writes: PlanWrite[]) => writes.filter((x) => x.path.startsWith('Sign Ups/'));
const suOld = (s: string, status: 'Paid' | 'NotPaid' = 'Paid') => signUpPath('Futsal', s, status, 'oldP');
const suKeep = (s: string, status: 'Paid' | 'NotPaid' = 'Paid') => signUpPath('Futsal', s, status, 'keepP');
const ISHTAR_UID = leagueUidPath('Futsal', '15', 'Ishtar', 'Paul P');

describe('E1: relinks in the fantasy test season only (Review Focus 1)', () => {
  it('Config + TestFill -> the Season 15 relink and its Played entry are planned, and the allowlist accepts them', () => {
    const snap = parleWorld().snap();
    const plan = buildMergePlan(parleMap(), snap, NOW);
    expect(plan.refusals).toEqual([]);
    expect(byPath(plan.writes).get(ISHTAR_UID)).toEqual({ path: ISHTAR_UID, before: 'oldP', after: 'keepP' });
    expect(byPath(plan.writes).get(playedPath('keepP', 'Futsal', '15'))?.after).toBe('Ishtar');
    expect(() => assertMergePaths(plan.writes, parleMap(), snap)).not.toThrow();
    expect(plan.summary.join('\n')).toMatch(/relink Futsal Season 15, Ishtar.*test season/);
  });

  it('Config WITHOUT TestFill -> refused whatever Finished or lockOverride say; the allowlist refuses it too', () => {
    const variants: Array<Record<string, unknown>> = [
      { Meta: true },
      { lockOverride: 'auto' },
      { lockOverride: 'locked', Finished: true },
      { lockOverride: 'open', Finished: false },
    ];
    for (const cfg of variants) {
      const w = parleWorld();
      delete w.nodes[fantasyTestFillPath('Futsal', '15')];
      w.nodes[fantasyConfigPath('Futsal', '15')] = cfg;
      const snap = w.snap();
      expect(snap.nodes[fantasyTestFillPath('Futsal', '15')]).toBeNull();
      const plan = buildMergePlan(parleMap(), snap, NOW);
      expect(plan.writes, JSON.stringify(cfg)).toEqual([]);
      expect(plan.refusals).toHaveLength(1);
      expect(plan.refusals[0].why).toContain('Futsal Season 15');
      expect(plan.refusals[0].why).toMatch(/live fantasy season/);
      // A hand-built relink for the same season is refused by the allowlist alone.
      expect(() =>
        assertMergePaths([{ path: ISHTAR_UID, before: 'oldP', after: 'keepP' }], parleMap(), snap),
      ).toThrow(/Season 15.*fantasy/);
    }
  });

  it('the TestFill check is per season: a test season elsewhere does not open Season 14', () => {
    const w = parleWorld();
    w.fantasy('Futsal', '14'); // a live fantasy season (Config, no TestFill)
    const plan = buildMergePlan(parleMap(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    const why = plan.refusals.map((r) => r.why).join('\n');
    expect(why).toContain('Futsal Season 14');
    expect(why).not.toContain('Futsal Season 15');
  });

  it('fails closed: Config exists but the snapshot never checked TestFill -> refused (planner and allowlist)', () => {
    const snap = parleWorld().snap();
    delete snap.nodes[fantasyTestFillPath('Futsal', '15')];
    const plan = buildMergePlan(parleMap(), snap, NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toMatch(/Futsal Season 15.*TestFill check/);
    expect(() =>
      assertMergePaths([{ path: ISHTAR_UID, before: 'oldP', after: 'keepP' }], parleMap(), snap),
    ).toThrow(/TestFill check/);
  });

  it('no Config at all needs no TestFill key (unchanged behaviour)', () => {
    const snap = parleWorld().snap();
    expect(fantasyTestFillPath('Futsal', '12') in snap.nodes).toBe(false);
    expect(buildMergePlan(parleMap(), snap, NOW).refusals).toEqual([]);
  });

  it('the unmoved-data refusals still apply in a test season (an old fantasy manager entry refuses)', () => {
    const w = parleWorld();
    w.nodes['Fantasy/Futsal/15/Managers'] = { oldP: true, 'test-01': true };
    const plan = buildMergePlan(parleMap(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals.map((r) => r.why).join('\n')).toMatch(/fantasy manager entry/);
    // ...and a manager entry of the fill's own test uids does not.
    const ok = parleWorld();
    ok.nodes['Fantasy/Futsal/15/Managers'] = { 'test-01': true, 'test-02': true };
    expect(buildMergePlan(parleMap(), ok.snap(), NOW).refusals).toEqual([]);
  });

  it('never writes the market: no Fantasy/... path anywhere in the plan', () => {
    const plan = buildMergePlan(parleMap(), parleWorld().snap(), NOW);
    expect(plan.writes.some((x) => x.path.startsWith('Fantasy/'))).toBe(false);
  });
});

describe('E1 pin: the real roster sync stands down on a TestFill season (a relinked UID changes nothing)', () => {
  const ishtar = (uid: string) => ({
    'Paul P': { UID: uid, Goals: 2, number: 7 },
    'Other One': { UID: 'someoneElse', Goals: 1 },
  });
  const market = () => ({
    'Paul P': { position: 'DEF', priceTenths: 60, eligible: true, teamName: 'Ishtar' },
    'Other One': { position: 'ATT', priceTenths: 90, eligible: true, teamName: 'Ishtar' },
  });
  const seed = (testFill: boolean) => ({
    Fantasy: { Futsal: { 15: {
      Config: { ...configToMap(futsalDefault()), lockOverride: 'auto' },
      Players: market(),
      ...(testFill ? { TestFill: { At: 1, Managers: 20 } } : {}),
    } } },
  });
  const args = { sport: 'Futsal', season: '15', team: 'Ishtar', before: ishtar('oldP'), after: ishtar('keepP') };

  it('a roster that differs only in one UID: zero writes and no market read on a TestFill season', async () => {
    const db = new FakeDb(seed(true));
    const res = await maybeSyncRoster(db, args);
    // The gate passed (a UID changed) and the sync stood down at the marker.
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes).toEqual([]);
    expect(db.reads.filter((r) => r.includes('/Players') || r.includes('Users/'))).toEqual([]);
    expect(db.reads.some((r) => r.endsWith('/TestFill'))).toBe(true); // it really looked at the marker
  });

  it('control: the same relink on a LIVE fantasy season does reach the market (so the pin means something)', async () => {
    const db = new FakeDb(seed(false));
    await maybeSyncRoster(db, args);
    expect(db.reads.some((r) => r.includes('/Players'))).toBe(true);
  });
});

describe('E2: sign-up records move to the kept account', () => {
  it('old holds S12-S15 Paid, kept has none -> 4 copies then 4 removes, each remove after its copy', () => {
    const snap = parleWorld().snap();
    const plan = buildMergePlan(parleMap(), snap, NOW);
    expect(plan.refusals).toEqual([]);
    expect(signUpWrites(plan.writes)).toHaveLength(8);
    const idx = (p: string) => paths(plan.writes).indexOf(p);
    for (const s of ['12', '13', '14', '15']) {
      expect(plan.writes[idx(suKeep(s))]).toEqual({ path: suKeep(s), before: null, after: 'Paul P' });
      expect(plan.writes[idx(suOld(s))]).toEqual({ path: suOld(s), before: 'Paul P', after: null });
      expect(idx(suKeep(s))).toBeGreaterThanOrEqual(0);
      expect(idx(suKeep(s))).toBeLessThan(idx(suOld(s)));
    }
    // Write order: Played / relinks, then every copy, then every remove, stamps last.
    const where = (f: (x: PlanWrite) => boolean) => plan.writes.map((x, i) => (f(x) ? i : -1)).filter((i) => i >= 0);
    const relinks = where((x) => parseRosterUidPath(x.path) !== null);
    const copies = where((x) => x.path.startsWith('Sign Ups/') && x.after !== null);
    const removes = where((x) => x.after === null);
    expect(Math.max(...relinks)).toBeLessThan(Math.min(...copies));
    expect(Math.max(...copies)).toBeLessThan(Math.min(...removes));
    expect(Math.max(...removes)).toBeLessThan(idx('Users/oldP/MergedHint'));
    expect(idx('Users/oldP/MergedInto')).toBe(plan.writes.length - 1);
    // The only removals in the whole plan are the four sign-up removes of the old uid.
    expect(removes).toHaveLength(4);
    expect(plan.writes.filter((x) => x.after === null).every((x) => parseSignUpPath(x.path)?.uid === 'oldP')).toBe(true);
    expect(() => assertMergePaths(plan.writes, parleMap(), snap)).not.toThrow();
    expect(plan.summary.join('\n')).toMatch(/Paul P: move his Season 12 sign-up record/);
    expect(plan.summary.join('\n')).toMatch(/Paul P: move his Season 15 sign-up record/);
  });

  it('after the writes land, a second plan has zero writes and zero refusals', () => {
    const snap = parleWorld().snap();
    const first = buildMergePlan(parleMap(), snap, NOW);
    const after = applyTo(snap, first.writes);
    expect(after.nodes[suKeep('13')]).toBe('Paul P');
    expect(after.nodes[suOld('13')]).toBeNull();
    const second = buildMergePlan(parleMap(), after, NOW + 1000);
    expect(second.refusals).toEqual([]);
    expect(second.writes).toEqual([]);
  });

  it('a crash between a copy and its remove: the re-run plans only the removes (Review Focus 3)', () => {
    const snap = parleWorld().snap();
    const first = buildMergePlan(parleMap(), snap, NOW);
    // Everything up to and including all four copies landed; no remove, no stamp.
    const crashedWrites = first.writes.filter((x) => x.after !== null && !x.path.startsWith('Users/oldP/Merged'));
    const crashed = applyTo(snap, crashedWrites);
    const second = buildMergePlan(parleMap(), crashed, NOW + 5000);
    expect(second.refusals).toEqual([]);
    expect(signUpWrites(second.writes)).toHaveLength(4);
    expect(signUpWrites(second.writes).every((x) => x.after === null)).toBe(true);
    expect(paths(second.writes).filter((p) => p.startsWith('Users/'))).toEqual([
      'Users/oldP/MergedHint', 'Users/oldP/MergedAt', 'Users/oldP/MergedInto',
    ]);
    expect(second.summary.join('\n')).toMatch(/finish moving his Season 13 sign-up record/);
    expect(second.summary.join('\n')).not.toMatch(/Paul P: move his Season/);
    expect(() => assertMergePaths(second.writes, parleMap(), crashed)).not.toThrow();

    // A crash after only SOME copies: the rest are copied, then all are removed.
    const partial = applyTo(snap, first.writes.filter((x) => x.path === suKeep('12') || x.path === suKeep('13')));
    const third = buildMergePlan(parleMap(), partial, NOW + 6000);
    expect(third.refusals).toEqual([]);
    const thirdSu = signUpWrites(third.writes);
    expect(thirdSu.filter((x) => x.after !== null).map((x) => x.path)).toEqual([suKeep('14'), suKeep('15')]);
    expect(thirdSu.filter((x) => x.after === null)).toHaveLength(4);
    expect(() => assertMergePaths(third.writes, parleMap(), partial)).not.toThrow();
  });

  it('kept already has S13 Paid with the same value -> only the S13 remove (Review Focus 3)', () => {
    const snap = parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Paul P').snap();
    const plan = buildMergePlan(parleMap(), snap, NOW);
    expect(plan.refusals).toEqual([]);
    const su = signUpWrites(plan.writes);
    expect(su.filter((x) => x.after !== null).map((x) => x.path)).toEqual([suKeep('12'), suKeep('14'), suKeep('15')]);
    expect(su.filter((x) => x.after === null).map((x) => x.path)).toEqual([suOld('12'), suOld('13'), suOld('14'), suOld('15')]);
    expect(plan.summary.join('\n')).toMatch(/finish moving his Season 13 sign-up record/);
    expect(() => assertMergePaths(plan.writes, parleMap(), snap)).not.toThrow();
  });

  it('kept has the record and old has none -> nothing to do (not even a refusal)', () => {
    const w = new World().user('keepP').user('oldP').hint('keepP').signUp('Futsal', '16', 'Paid', 'keepP', 'Paul P');
    w.row('Futsal', '9', 'Wolves', 'Paul P', 'oldP');
    const plan = buildMergePlan(parleMap(), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(signUpWrites(plan.writes)).toEqual([]);
  });

  it('kept has S13 NotPaid (old has Paid) -> the person is refused, zero writes, no values in the reason (Review Focus 4)', () => {
    const plan = buildMergePlan(parleMap(), parleWorld().signUp('Futsal', '13', 'NotPaid', 'keepP', 'Paul P').snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toContain('Futsal Season 13');
    expect(plan.refusals[0].why).toMatch(/sign-up record/);
    expect(plan.refusals[0].why).not.toContain('Paul');
    expect(plan.summary.join('\n')).toMatch(/Paul P: REFUSED/);
  });

  it('kept has S13 Paid with ANOTHER value -> refused, zero writes (Review Focus 4)', () => {
    const plan = buildMergePlan(parleMap(), parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Somebody Else').snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toContain('Futsal Season 13');
    expect(plan.refusals[0].why).not.toContain('Somebody');
  });

  it('a refused person does not block the next person', () => {
    const w = parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Somebody Else');
    w.user('keepQ').user('oldQ').hint('keepQ');
    w.row('Futsal', '9', 'Wolves', 'Quin Q', 'oldQ').signUp('Futsal', '9', 'NotPaid', 'oldQ', 'Quin Q');
    const m = mapOf(
      cluster({ who: 'Paul P', keep: 'keepP', old: ['oldP'] }),
      cluster({ who: 'Quin Q', keep: 'keepQ', old: ['oldQ'] }),
    );
    const snap = w.snap();
    const plan = buildMergePlan(m, snap, NOW);
    expect(plan.refusals.map((r) => r.who)).toEqual(['Paul P']);
    expect(signUpWrites(plan.writes).map((x) => x.path)).toEqual([
      signUpPath('Futsal', '9', 'NotPaid', 'keepQ'), signUpPath('Futsal', '9', 'NotPaid', 'oldQ'),
    ]);
    expect(() => assertMergePaths(plan.writes, m, snap)).not.toThrow();
  });

  it('the value is copied byte-identical, odd whitespace included (Review Focus 5)', () => {
    for (const value of ['Paul P ', ' Paul  P', 'Paul P\t', 'Pa ul P  ']) {
      const snap = parleWorld().signUp('Futsal', '12', 'Paid', 'oldP', value).snap();
      const plan = buildMergePlan(parleMap(), snap, NOW);
      expect(plan.refusals, JSON.stringify(value)).toEqual([]);
      const copy = byPath(plan.writes).get(suKeep('12'));
      expect(copy?.after).toBe(value);
      expect(byPath(plan.writes).get(suOld('12'))).toEqual({ path: suOld('12'), before: value, after: null });
      expect(() => assertMergePaths(plan.writes, parleMap(), snap)).not.toThrow();
      // a trimmed copy is NOT the old value: the allowlist refuses it
      const trimmed = plan.writes.map((x) => (x.path === suKeep('12') ? { ...x, after: value.trim() } : x));
      expect(() => assertMergePaths(trimmed, parleMap(), snap)).toThrow(/value|copy/i);
    }
  });
});

describe('E2: the opt-out, the map field and the edge cases', () => {
  it('moveSignUps: false -> no sign-up writes and no sign-up refusal; the allowlist refuses a hand-built move', () => {
    const snap = parleWorld().signUp('Futsal', '13', 'NotPaid', 'keepP', 'Paul P').snap(); // would refuse if moving
    const m = parleMap({ moveSignUps: false });
    const plan = buildMergePlan(m, snap, NOW);
    expect(plan.refusals).toEqual([]);
    expect(signUpWrites(plan.writes)).toEqual([]);
    expect(plan.writes.some((x) => x.path.startsWith('Users/oldP/Merged'))).toBe(true);
    expect(() => assertMergePaths(plan.writes, m, snap)).not.toThrow();
    const cleanSnap = parleWorld().snap();
    const move = buildMergePlan(parleMap(), cleanSnap, NOW).writes;
    expect(() => assertMergePaths(move, m, cleanSnap)).toThrow(/sign-up|move/i);
    // an explicit true is the default
    expect(buildMergePlan(parleMap({ moveSignUps: true }), cleanSnap, NOW).writes).toEqual(move);
  });

  it('moveSignUps must be a boolean: the planner refuses the cluster and the allowlist the whole map', () => {
    const snap = parleWorld().snap();
    for (const bad of ['yes', 1, 0, null, {}, []]) {
      const m = parleMap({ moveSignUps: bad as unknown as boolean });
      const plan = buildMergePlan(m, snap, NOW);
      expect(plan.writes, JSON.stringify(bad)).toEqual([]);
      expect(plan.refusals[0].why).toMatch(/moveSignUps/);
      expect(() => assertMergePaths([], m, snap)).toThrow(/Refusing merge map.*moveSignUps/);
    }
    expect(() => assertMergePaths([], parleMap({ moveSignUps: false }), snap)).not.toThrow();
    expect(() => assertMergePaths([], parleMap({ moveSignUps: true }), snap)).not.toThrow();
  });

  it('two old accounts with the same record: copied once, both removed; different records refuse', () => {
    const base = () => {
      const w = new World().user('keepM').user('old1').user('old2').hint('keepM');
      w.row('Futsal', '9', 'Wolves', 'Mo M', 'old1');
      return w;
    };
    const m = mapOf(cluster({ who: 'Mo M', keep: 'keepM', old: ['old1', 'old2'] }));
    const sameSnap = base().signUp('Futsal', '9', 'Paid', 'old1', 'Mo M').signUp('Futsal', '9', 'Paid', 'old2', 'Mo M').snap();
    const plan = buildMergePlan(m, sameSnap, NOW);
    expect(plan.refusals).toEqual([]);
    expect(signUpWrites(plan.writes).map((x) => [x.path, x.after])).toEqual([
      [signUpPath('Futsal', '9', 'Paid', 'keepM'), 'Mo M'],
      [signUpPath('Futsal', '9', 'Paid', 'old1'), null],
      [signUpPath('Futsal', '9', 'Paid', 'old2'), null],
    ]);
    expect(() => assertMergePaths(plan.writes, m, sameSnap)).not.toThrow();

    for (const [status, value] of [['Paid', 'Mo Different'], ['NotPaid', 'Mo M']] as const) {
      const w = base().signUp('Futsal', '9', 'Paid', 'old1', 'Mo M').signUp('Futsal', '9', status, 'old2', value);
      const refused = buildMergePlan(m, w.snap(), NOW);
      expect(refused.writes, `${status}/${value}`).toEqual([]);
      expect(refused.refusals[0].why).toContain('Futsal Season 9');
    }
  });

  it('an old account with records in BOTH statuses of one season is refused', () => {
    const plan = buildMergePlan(parleMap(), parleWorld().signUp('Futsal', '12', 'NotPaid', 'oldP', 'Paul P').snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals[0].why).toContain('Futsal Season 12');
  });

  it('Basketball and Flag Football records move too; other trees and non-numeric seasons are never touched', () => {
    const w = parleWorld();
    w.signUp('Basketball', '3', 'NotPaid', 'oldP', 'Paul P').signUp('Flag Football', '2', 'Paid', 'oldP', 'Paul P');
    w.nodes['Sign Ups/Some Cup/abc123/Paid/oldP'] = 'Paul P';
    w.nodes['Sign Ups/Futsal/12/Due'] = 25;
    const snap = w.snap();
    const plan = buildMergePlan(parleMap(), snap, NOW);
    expect(plan.refusals).toEqual([]);
    const su = signUpWrites(plan.writes).map((x) => x.path);
    expect(su).toContain(signUpPath('Basketball', '3', 'NotPaid', 'keepP'));
    expect(su).toContain(signUpPath('Flag Football', '2', 'Paid', 'oldP'));
    expect(su.some((p) => p.includes('Some Cup') || p.includes('Due'))).toBe(false);
    expect(() => assertMergePaths(plan.writes, parleMap(), snap)).not.toThrow();
  });

  it('fails closed: a leaf of a scanned season missing from the snapshot, or a value that is not text, refuses the person', () => {
    for (const p of [suOld('13', 'NotPaid'), suKeep('14'), suKeep('14', 'NotPaid'), suOld('15')]) {
      const snap = parleWorld().snap();
      delete snap.nodes[p];
      const plan = buildMergePlan(parleMap(), snap, NOW);
      expect(plan.writes, p).toEqual([]);
      expect(plan.refusals[0].why, p).toMatch(/sign-up check/);
    }
    for (const bad of [5, true, { a: 1 }, ['x'], '']) {
      const snap = parleWorld().snap();
      snap.nodes[suOld('13')] = bad;
      const plan = buildMergePlan(parleMap(), snap, NOW);
      expect(plan.writes, JSON.stringify(bad)).toEqual([]);
      expect(plan.refusals[0].why).toContain('Futsal Season 13');
    }
    const keptBad = parleWorld().snap();
    keptBad.nodes[suKeep('13')] = 7;
    expect(buildMergePlan(parleMap(), keptBad, NOW).refusals).toHaveLength(1);
  });

  it('a cluster refused for another reason plans no sign-up write either', () => {
    const w = parleWorld();
    w.user('oldP', { 'First Name': 'Paul', Awards: { a1: { Tier: 'gold' } } });
    const plan = buildMergePlan(parleMap(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals.map((r) => r.why).join('\n')).toMatch(/Awards/);
  });

  it('a cluster with no old account never looks at sign-ups', () => {
    const w = new World().user('k').hint('k');
    w.row('Futsal', '10', 'Bulls', 'Row Name', null);
    const m = mapOf(cluster({ who: 'Row', keep: 'k', old: [], nameRows: [{ sport: 'Futsal', season: '10', team: 'Bulls', name: 'Row Name' }] }));
    expect(buildMergePlan(m, w.snap(), NOW).refusals).toEqual([]);
  });
});

describe('assertMergePaths: the one allowed removal (a sign-up record, after its copy)', () => {
  const map = () => parleMap();
  const snap = () => parleWorld().snap();
  const w = (path: string, before: unknown, after: unknown): PlanWrite => ({ path, before, after });
  const reject = (writes: PlanWrite[], why?: RegExp, s: MergeSnapshot = snap(), m: MergeMap = map()) =>
    expect(() => assertMergePaths(writes, m, s)).toThrow(why ?? /Refusing merge path/);

  it('accepts a copy then its remove, and nothing else may be removed', () => {
    expect(() => assertMergePaths([w(suKeep('12'), null, 'Paul P'), w(suOld('12'), 'Paul P', null)], map(), snap())).not.toThrow();
    reject([w('Users/oldP/Played/Futsal/Season 9', 'Wolves', null)], /remov|null/i);
    reject([w('Users/oldP/MergedInto', 'keepP', null)], /remov|null/i);
    reject([w(ISHTAR_UID, 'oldP', null)], /remov|null/i);
    reject([w('Comments/Paul P', 'x', null)], /remov|null|allowlist/i);
    reject([w('Sign Ups/Futsal/12/Paid', { oldP: 'Paul P' }, null)], /remov|null|allowlist/i);
    reject([w('Sign Ups/Futsal/12/Due', 25, null)], /remov|null|allowlist/i);
    reject([w(suOld('12'), 'Paul P', undefined)], /remov|null/i);
  });

  it('rejects a remove of the KEPT account\'s key (even with a matching value)', () => {
    const s = parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Paul P').snap();
    reject([w(suKeep('13'), 'Paul P', null)], /old account/i, s);
    reject([w(suKeep('16'), 'Paul P', null)], /old account/i);
  });

  it('rejects a remove with no copy in the plan (unless the kept copy already exists with that value)', () => {
    reject([w(suOld('12'), 'Paul P', null)], /copy/i);
    // the copy comes AFTER the remove
    reject([w(suOld('12'), 'Paul P', null), w(suKeep('12'), null, 'Paul P')], /copy/i);
    // the copy in the plan is for another season
    reject([w(suKeep('13'), null, 'Paul P'), w(suOld('12'), 'Paul P', null)], /copy/i);
    // the kept copy already exists with the same value: the remove stands alone
    const s = parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Paul P').snap();
    expect(() => assertMergePaths([w(suOld('13'), 'Paul P', null)], map(), s)).not.toThrow();
    // ...but not when the kept value differs or sits in the other status
    reject([w(suOld('13'), 'Paul P', null)], undefined, parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Somebody').snap());
    reject([w(suOld('13'), 'Paul P', null)], undefined, parleWorld().signUp('Futsal', '13', 'NotPaid', 'keepP', 'Paul P').snap());
  });

  it('rejects a copy whose value differs from the old value, or whose status/season does not match an old record', () => {
    reject([w(suKeep('12'), null, 'Paul Q'), w(suOld('12'), 'Paul P', null)], /value|copy/i);
    reject([w(suKeep('12'), null, 'Paul P '), w(suOld('12'), 'Paul P', null)], /value|copy/i);
    reject([w(suKeep('12', 'NotPaid'), null, 'Paul P'), w(suOld('12'), 'Paul P', null)], /value|copy|status/i);
    reject([w(signUpPath('Futsal', '11', 'Paid', 'keepP'), null, 'Paul P')]);
    reject([w(suKeep('12'), null, 5)]);
    reject([w(suKeep('12'), null, '')]);
  });

  it('rejects a copy over an existing kept record, a copy to an old uid, and a copy when the kept record already matches', () => {
    const s = parleWorld().signUp('Futsal', '13', 'Paid', 'keepP', 'Paul P').snap();
    reject([w(suKeep('13'), 'Paul P', 'Paul P')], undefined, s);
    reject([w(suKeep('13'), null, 'Paul P')], /before/i, s);
    reject([w(suOld('12'), 'Paul P', 'Paul Q')]);
  });

  it('rejects any uid outside the map and a path outside the league sports / numbered seasons / two statuses', () => {
    const s = parleWorld().signUp('Futsal', '12', 'Paid', 'stranger', 'Paul P').snap();
    reject([w(signUpPath('Futsal', '12', 'Paid', 'stranger'), 'Paul P', null)], /not in the merge map/, s);
    reject([w(signUpPath('Futsal', '12', 'Paid', 'stranger'), null, 'x')]);
    for (const p of [
      'Sign Ups/Some Cup/abc123/Paid/oldP', 'Sign Ups/Futsal/Season 12/Paid/oldP', 'Sign Ups/Futsal/12/Pending/oldP',
      'Sign Ups/Futsal/12/Paid/oldP/extra', 'Sign Ups/y', 'Sign Ups/Futsal/12/Due/Info',
    ]) {
      reject([w(p, null, 'x')]);
    }
  });

  it('a snapshot missing a leaf of the season is not enough to allow the write (fail closed)', () => {
    const s = snap();
    delete s.nodes[suOld('12', 'NotPaid')];
    reject([w(suKeep('12'), null, 'Paul P'), w(suOld('12'), 'Paul P', null)], /sign-up check/i, s);
    const s2 = snap();
    delete s2.nodes[suKeep('12')]; // the kept leaf was never read
    reject([w(suKeep('12'), null, 'Paul P')], /sign-up check/i, s2);
  });

  it('a stale write (before differs from the snapshot) is rejected', () => {
    reject([w(suKeep('12'), null, 'Paul P'), w(suOld('12'), 'Someone', null)], /snapshot/);
  });

  it('rejects the "remove" of an old key that holds no record (nothing to move)', () => {
    const m = mapOf(cluster({ who: 'Mo M', keep: 'keepM', old: ['old1', 'old2'] }));
    const s = new World().user('keepM').user('old1').user('old2').hint('keepM')
      .signUp('Futsal', '9', 'Paid', 'old1', 'Mo M').snap();
    const copy = w(signUpPath('Futsal', '9', 'Paid', 'keepM'), null, 'Mo M');
    const real = w(signUpPath('Futsal', '9', 'Paid', 'old1'), 'Mo M', null);
    expect(() => assertMergePaths([copy, real], m, s)).not.toThrow();
    reject([copy, w(signUpPath('Futsal', '9', 'Paid', 'old2'), null, null)], /Refusing merge path/, s, m);
    reject([copy, w(signUpPath('Futsal', '9', 'NotPaid', 'old1'), null, null)], /Refusing merge path/, s, m);
  });

  it('a person the planner would refuse cannot be moved by hand-built writes (kept NotPaid / two old records)', () => {
    const notPaid = parleWorld().signUp('Futsal', '13', 'NotPaid', 'keepP', 'Paul P').snap();
    reject([w(suKeep('13'), null, 'Paul P'), w(suOld('13'), 'Paul P', null)], undefined, notPaid);
    const both = parleWorld().signUp('Futsal', '12', 'NotPaid', 'oldP', 'Paul P').snap();
    reject([w(suKeep('12'), null, 'Paul P'), w(suOld('12'), 'Paul P', null)], undefined, both);
  });

  it('every planned write of the bigger Parlevino plan passes the allowlist', () => {
    const writes = buildMergePlan(map(), snap(), NOW).writes;
    expect(writes).toHaveLength(4 + 4 + 8 + 3); // 4 relinks, 4 Played, 4 copies + 4 removes, 3 stamps
    expect(() => assertMergePaths(writes, map(), snap())).not.toThrow();
  });
});
