// Pure planner of the duplicate-account merge tool (plan 2026-11-06, Task 4;
// design D1-D6, D10, D14, D15). No database: fixtures are fake uids and
// fixtures shaped like the read-only audit (Hiram, Joseph, Carlo, Robert
// Tatari, the two name-variant clusters).
import { isDeepStrictEqual } from 'util';
import { describe, expect, it } from 'vitest';
import {
  afcUidPath, assertMergePaths, buildMergePlan, fantasyConfigPath, leagueUidPath, MergeCluster,
  MergeMap, MergeSnapshot, parseRosterUidPath, PlanWrite, playedPath, userPath,
} from './merge_accounts_logic';

const NOW = 1_800_000_000_000;
const HINT = 'ca••••••••@gmail.com';

/** A tiny in-memory database snapshot builder. */
class World {
  nodes: Record<string, unknown> = {};
  keptHints: Record<string, string> = {};

  user(uid: string, fields: Record<string, unknown> = { 'First Name': 'Fake' }): this {
    this.nodes[userPath(uid)] = fields;
    return this;
  }

  /** A league roster row (uid null = the row exists with no UID). The
   *  season's fantasy Config is recorded as absent unless fantasy() says so. */
  row(sport: string, season: string, team: string, name: string, uid: string | null): this {
    this.nodes[leagueUidPath(sport, season, team, name)] = uid;
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

  hint(keep: string, hint: string = HINT): this {
    this.keptHints[keep] = hint;
    return this;
  }

  snap(): MergeSnapshot {
    return { nodes: JSON.parse(JSON.stringify(this.nodes)), keptHints: { ...this.keptHints } };
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

/** Hiram-like: one old account, four Futsal rows across seasons, a profile
 *  photo only the old account has, and Information the keep lacks. */
function hiramWorld(): World {
  const w = new World()
    .user('keepH', { 'First Name': 'Hiram', Played: { Futsal: { 'Season 15': 'Zebras' } } })
    .user('oldH', {
      'First Name': 'Hiram', ProfileUrl: 'https://img.example/h.jpg',
      Played: { Futsal: { 'Season 9': 'Wolves' } },
    })
    .hint('keepH');
  w.row('Futsal', '9', 'Wolves', 'Hiram Alvarez', 'oldH');
  w.row('Futsal', '10', 'Nineveh', 'Hiram Alvarez', 'oldH');
  w.row('Futsal', '11', 'Nineveh', 'Hiram A', 'oldH');
  w.row('Futsal', '12', 'Bulls', 'Hiram Alvarez', 'oldH');
  w.row('Futsal', '13', 'Bulls', 'Someone Else', 'someoneElse'); // unrelated row
  return w;
}
const hiramMap = () => mapOf(cluster({ who: 'Hiram', keep: 'keepH', old: ['oldH'] }));

describe('path helpers', () => {
  it('build the exact database paths (note the space in "Line Ups")', () => {
    expect(userPath('u1')).toBe('Users/u1');
    expect(leagueUidPath('Futsal', '10', 'Nineveh', 'Robben Tatari')).toBe(
      'Futsal/10/Line Ups/Nineveh/Robben Tatari/UID',
    );
    expect(afcUidPath('Beyond the Game Turf Open Division 1 Spring 2025', 'Carlo G')).toBe(
      'AFC San Jose/Seasons/Beyond the Game Turf Open Division 1 Spring 2025/Roster/Carlo G/UID',
    );
    expect(playedPath('k', 'Flag Football', '3')).toBe('Users/k/Played/Flag Football/Season 3');
    expect(fantasyConfigPath('Futsal', '10')).toBe('Fantasy/Futsal/10/Config');
  });

  it('parseRosterUidPath understands league and AFC UID leaves and nothing else', () => {
    expect(parseRosterUidPath('Futsal/10/Line Ups/Nineveh/Robben Tatari/UID')).toEqual({
      kind: 'league', sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Robben Tatari',
    });
    expect(parseRosterUidPath('AFC San Jose/Seasons/Spring 2025/Roster/Carlo G/UID')).toEqual({
      kind: 'afc', season: 'Spring 2025', name: 'Carlo G',
    });
    expect(parseRosterUidPath('Futsal/10/Line Ups/Nineveh/Robben Tatari/Goals')).toBeNull();
    expect(parseRosterUidPath('Users/k/Played/Futsal/Season 10')).toBeNull();
    expect(parseRosterUidPath('Soccer/10/Line Ups/Nineveh/X/UID')).toBeNull();
  });
});

describe('buildMergePlan: Hiram-like cluster (D1, D3, D4, D5)', () => {
  const plan = buildMergePlan(hiramMap(), hiramWorld().snap(), NOW);
  const w = byPath(plan.writes);

  it('plans no refusals and exactly 12 leaf writes', () => {
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toHaveLength(12);
  });

  it('relinks the 4 Line Ups UID leaves to the kept uid and renames no roster key', () => {
    for (const [season, team, name] of [
      ['9', 'Wolves', 'Hiram Alvarez'], ['10', 'Nineveh', 'Hiram Alvarez'],
      ['11', 'Nineveh', 'Hiram A'], ['12', 'Bulls', 'Hiram Alvarez'],
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

  it('stamps the old account with exactly MergedInto, MergedAt, MergedHint (D5)', () => {
    const oldWrites = plan.writes.filter((x) => x.path.startsWith('Users/oldH/'));
    expect(oldWrites).toEqual([
      { path: 'Users/oldH/MergedInto', before: null, after: 'keepH' },
      { path: 'Users/oldH/MergedAt', before: null, after: NOW },
      { path: 'Users/oldH/MergedHint', before: null, after: HINT },
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
    expect(text).toContain('Hiram');
    expect(text).toContain('Nineveh');
    expect(text).toContain('Hiram A');
    expect(text).toMatch(/Season 11/);
    expect(text).not.toContain('keepH');
    expect(text).not.toContain('oldH');
    expect(text).not.toContain('img.example');
    expect(text).not.toContain('@');
  });
});

describe('buildMergePlan: ProfileUrl (D4)', () => {
  it('Joseph-like: a kept account that already has a ProfileUrl keeps it (never overwritten)', () => {
    const w = new World()
      .user('keepJ', { 'First Name': 'Joseph', ProfileUrl: 'https://img.example/keep.jpg' })
      .user('oldJ', { 'First Name': 'Joseph', ProfileUrl: 'https://img.example/old.jpg' })
      .hint('keepJ');
    w.row('Futsal', '11', 'Bulls', 'Joseph Baba', 'oldJ');
    const plan = buildMergePlan(mapOf(cluster({ who: 'Joseph', keep: 'keepJ', old: ['oldJ'] })), w.snap(), NOW);
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
  it('Carlo-like: 3 AFC roster rows relinked, and no Played entry for AFC', () => {
    const w = new World().user('keepC').user('oldC').hint('keepC');
    const seasons = ['Open Division 1 Spring 2025', 'Open Division 1 Fall 2025', 'Open Division 2 Spring 2026'];
    seasons.forEach((s) => w.afc(s, 'Carlo G', 'oldC'));
    w.afc('Open Division 1 Spring 2025', 'Teammate', 'someoneElse');
    const m = mapOf(cluster({ who: 'Carlo', keep: 'keepC', old: ['oldC'] }));
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    const afcWrites = plan.writes.filter((x) => x.path.startsWith('AFC San Jose/'));
    expect(afcWrites).toHaveLength(3);
    for (const s of seasons) {
      const p = afcUidPath(s, 'Carlo G');
      expect(byPath(plan.writes).get(p)).toEqual({ path: p, before: 'oldC', after: 'keepC' });
    }
    expect(paths(plan.writes).some((p) => p.includes('/Played'))).toBe(false);
    expect(plan.writes).toHaveLength(3 + 3); // 3 relinks + 3 stamps
    expect(() => assertMergePaths(plan.writes, m, w.snap())).not.toThrow();
  });
});

describe('buildMergePlan: Robert-Tatari-like (Review Focus 5)', () => {
  const world = () => {
    const w = new World()
      .user('keepT', { 'First Name': 'Robert' })
      .user('oldT1', { 'First Name': 'Robert' })
      .user('oldT2', { 'First Name': 'Robert' })
      .user('oldT3', { 'First Name': 'Robert' })
      .hint('keepT');
    w.row('Futsal', '11', 'Nineveh', 'Robert Tatari', 'oldT1');
    w.row('Futsal', '12', 'Nineveh', 'Robert Tatari', 'oldT2');
    w.row('Futsal', '13', 'Nineveh', 'Robert Tatari', 'oldT2');
    w.row('Futsal', '14', 'Rams', 'Robert Tatari', 'oldT3');
    return w;
  };
  const map = () =>
    mapOf(cluster({ who: 'Robert Tatari', keep: 'keepT', old: ['oldT1', 'oldT2', 'oldT3'] }));

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
  const tatariRow = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Robben Tatari' };
  const world = () => {
    const w = new World().user('keepR', { 'First Name': 'Roben' }).hint('keepR');
    w.row('Futsal', '10', 'Nineveh', 'Robben Tatari', null);
    return w;
  };
  const map = () =>
    mapOf(cluster({ who: 'Roben Tatari', keep: 'keepR', old: [], nameRows: [tatariRow] }));

  it('sets the row UID to the kept uid, adds Played Season 10, leaves the roster key alone, stamps nothing', () => {
    const plan = buildMergePlan(map(), world().snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toEqual([
      { path: 'Users/keepR/Played/Futsal/Season 10', before: null, after: 'Nineveh' },
      { path: 'Futsal/10/Line Ups/Nineveh/Robben Tatari/UID', before: null, after: 'keepR' },
    ]);
    expect(paths(plan.writes).some((p) => /Merged/.test(p))).toBe(false);
    expect(() => assertMergePaths(plan.writes, map(), world().snap())).not.toThrow();
  });

  it('refuses a name row that does not exist in the snapshot instead of creating a stray roster row', () => {
    const w = new World().user('keepR').hint('keepR'); // no roster row at all
    const plan = buildMergePlan(map(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].who).toBe('Roben Tatari');
    expect(plan.refusals[0].why).toContain('Robben Tatari');
  });

  it('a name row already linked to the kept account is a no-op', () => {
    const w = new World().user('keepR', { Played: { Futsal: { 'Season 10': 'Nineveh' } } }).hint('keepR');
    w.row('Futsal', '10', 'Nineveh', 'Robben Tatari', 'keepR');
    const plan = buildMergePlan(map(), w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toEqual([]);
  });

  it('D10: firstNameFix writes exactly one Users/<keep>/First Name; clusters without it write none', () => {
    const w = world();
    w.user('keepS', { 'First Name': 'Robbert' }).user('oldS', { 'First Name': 'Robbert' }).hint('keepS');
    w.row('Futsal', '12', 'Bulls', 'Robert Shamoelzadeh', 'oldS');
    const m = mapOf(
      cluster({ who: 'Robert Shamoeilzadeh', keep: 'keepS', old: ['oldS'], firstNameFix: 'Robert' }),
      cluster({ who: 'Roben Tatari', keep: 'keepR', old: [], nameRows: [tatariRow] }),
    );
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    const fixes = plan.writes.filter((x) => x.path.endsWith('/First Name'));
    expect(fixes).toEqual([{ path: 'Users/keepS/First Name', before: 'Robbert', after: 'Robert' }]);
    expect(() => assertMergePaths(plan.writes, m, w.snap())).not.toThrow();
  });

  it('D10: no write when the First Name is already the fix; an unsafe fix is refused', () => {
    const w = new World().user('k', { 'First Name': 'Robert' }).user('o').hint('k');
    const ok = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'], firstNameFix: 'Robert' })), w.snap(), NOW);
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
    const w = new World().user('k').user('o').hint('k').afc('Spring 2025', 'Carlo G', 'o');
    const plan = buildMergePlan(mapOf(cluster({ keep: 'k', old: ['o'] })), w.snap(), NOW);
    expect(plan.refusals).toEqual([]);
    expect(plan.writes).toHaveLength(1 + 3);
  });

  it('Review Focus 2: a name row holding a third, unrelated uid is refused and never overwritten', () => {
    const w = new World().user('k').hint('k').user('third');
    w.row('Futsal', '10', 'Nineveh', 'Robben Tatari', 'third');
    const m = mapOf(cluster({
      who: 'Roben Tatari', keep: 'k', old: [],
      nameRows: [{ sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Robben Tatari' }],
    }));
    const plan = buildMergePlan(m, w.snap(), NOW);
    expect(plan.writes).toEqual([]);
    expect(plan.refusals).toHaveLength(1);
    expect(plan.refusals[0].why).toContain('Robben Tatari');
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
    w.keptHints['keepA'] = 'carlo@gmail.com';
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
    const tatariRow = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Robben Tatari' };
    const w = hiramWorld();
    w.user('keepR', { 'First Name': 'Roben' }).hint('keepR').row('Futsal', '10', 'Nineveh', 'Robben Tatari', null);
    w.user('keepS', { 'First Name': 'Robbert' }).user('oldS', { ProfileUrl: 'https://img.example/s.jpg' }).hint('keepS');
    w.row('Futsal', '12', 'Bulls', 'Robert Shamoelzadeh', 'oldS');
    w.user('keepC').user('oldC').hint('keepC').afc('Spring 2025', 'Carlo G', 'oldC');
    const m = mapOf(
      cluster({ who: 'Hiram', keep: 'keepH', old: ['oldH'] }),
      cluster({ who: 'Roben Tatari', keep: 'keepR', old: [], nameRows: [tatariRow] }),
      cluster({ who: 'Robert S', keep: 'keepS', old: ['oldS'], firstNameFix: 'Robert' }),
      cluster({ who: 'Carlo', keep: 'keepC', old: ['oldC'] }),
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
      'Users/oldH/MergedInto', 'Users/oldH/MergedAt', 'Users/oldH/MergedHint',
    ]);
    expect(byPath(second.writes).get('Users/oldH/MergedAt')?.after).toBe(NOW + 5000);
  });

  it('a stamp that already exists is never re-written (MergedAt keeps its first time)', () => {
    const w = hiramWorld().user('oldH', {
      'First Name': 'Hiram', MergedInto: 'keepH', MergedAt: 111, Played: { Futsal: { 'Season 9': 'Wolves' } },
      ProfileUrl: 'https://img.example/h.jpg',
    });
    const plan = buildMergePlan(hiramMap(), w.snap(), NOW);
    expect(paths(plan.writes).filter((p) => p.startsWith('Users/oldH/'))).toEqual(['Users/oldH/MergedHint']);
  });
});

describe('assertMergePaths: the allowlist', () => {
  const tatariRow = { sport: 'Futsal', season: '10', team: 'Nineveh', name: 'Robben Tatari' };
  const world = () => {
    const w = hiramWorld();
    w.user('keepR', { 'First Name': 'Roben' }).hint('keepR').row('Futsal', '10', 'Nineveh', 'Robben Tatari', null);
    w.user('keepS', { 'First Name': 'Robbert' }).user('oldS', { 'First Name': 'Robbert', Token: 't' }).hint('keepS');
    w.row('Futsal', '12', 'Bulls', 'Robert Shamoelzadeh', 'oldS');
    w.user('keepF').user('oldF').hint('keepF').row('Futsal', '15', 'Zebras', 'Fan F', 'oldF').fantasy('Futsal', '15');
    return w;
  };
  const map = () =>
    mapOf(
      cluster({ who: 'Hiram', keep: 'keepH', old: ['oldH'] }),
      cluster({ who: 'Roben Tatari', keep: 'keepR', old: [], nameRows: [tatariRow] }),
      cluster({ who: 'Robert S', keep: 'keepS', old: ['oldS'], firstNameFix: 'Robert' }),
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
    reject([w('Users/keepH', { 'First Name': 'Hiram' }, { 'First Name': 'Hiram', X: 1 })]);
    reject([w('Users/oldH', { 'First Name': 'Hiram' }, null)]);
    reject([w('Users', null, { a: 1 })]);
    reject([w('Users/oldH/MergedInto', null, null)], /remov|null/i);
    reject([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'oldH', null)], /remov|null/i);
  });

  it('rejects any uid that is not in the map', () => {
    reject([w('Users/stranger/MergedInto', null, 'keepH')]);
    reject([w('Users/stranger/ProfileUrl', null, 'https://img.example/h.jpg')]);
    reject([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'oldH', 'stranger')], /kept account/);
  });

  it('D10: First Name only for the cluster that has firstNameFix, and only with that value', () => {
    expect(() => assertMergePaths([w('Users/keepS/First Name', 'Robbert', 'Robert')], map(), snap())).not.toThrow();
    reject([w('Users/keepH/First Name', 'Hiram', 'Robert')]);
    reject([w('Users/keepR/First Name', 'Roben', 'Robert')]);
    reject([w('Users/oldS/First Name', 'Robbert', 'Robert')]);
    reject([w('Users/keepS/First Name', 'Robbert', 'Roberto')]);
  });

  it('D2: rejects a relink in a fantasy season and one with no Config presence recorded', () => {
    reject([w('Futsal/15/Line Ups/Zebras/Fan F/UID', 'oldF', 'keepF'), w('Users/keepF/Played/Futsal/Season 15', null, 'Zebras')], /fantasy|Season 15/i);
    const s = snap();
    delete s.nodes[fantasyConfigPath('Futsal', '9')];
    expect(() =>
      assertMergePaths([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'oldH', 'keepH')], map(), s),
    ).toThrow(/Season 9/);
  });

  it('roster relinks: only old uid (or an empty name row) -> the same cluster\'s keep', () => {
    const ok = w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'oldH', 'keepH');
    expect(() => assertMergePaths([ok], map(), snap())).not.toThrow();
    // old uid of one cluster handed to another cluster's keep
    reject([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'oldH', 'keepS')]);
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
        w('Futsal/10/Line Ups/Nineveh/Robben Tatari/UID', null, 'keepR'),
        w('Users/keepR/Played/Futsal/Season 10', null, 'Nineveh'),
      ], map(), snap()),
    ).not.toThrow();
    // roster nodes other than the UID leaf
    reject([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez', { UID: 'oldH' }, { UID: 'keepH' })]);
    reject([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/Goals', null, 3)]);
  });

  it('a stale write (before differs from the snapshot) is rejected', () => {
    reject([w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'someoneNew', 'keepH')], /snapshot/);
    reject([w('Users/keepH/ProfileUrl', 'https://img.example/x.jpg', 'https://img.example/h.jpg')], /snapshot/);
  });

  it('Played: only for a kept account, only league sports, only with a matching relink, never over a value', () => {
    const relink = w('Futsal/9/Line Ups/Wolves/Hiram Alvarez/UID', 'oldH', 'keepH');
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
      'First Name': 'Hiram',
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
    reject([w('Users/oldH/MergedHint', null, 'carlo@gmail.com')]);
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

  it('a uid that is both kept and old in the map allows nothing', () => {
    const m = mapOf(cluster({ keep: 'dup', old: ['dup'] }));
    const s = new World().user('dup').hint('dup').snap();
    expect(() => assertMergePaths([w('Users/dup/MergedInto', null, 'dup')], m, s)).toThrow(/Refusing merge path/);
  });

  it('every planned write of a bigger fixture still passes after rebuilding with a different clock', () => {
    const plan = buildMergePlan(map(), snap(), NOW + 1);
    expect(() => assertMergePaths(plan.writes, map(), snap())).not.toThrow();
    expect(plan.writes.every((x) => !isDeepStrictEqual(x.before, x.after))).toBe(true);
  });
});
