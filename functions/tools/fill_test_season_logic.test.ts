// Pure logic of the Season 15 test-season fill tool (spec 2026-10-29 §9):
// the write plan, its path guard, the paused-engine guard and the
// deterministic fake managers. The CLI (fill_test_season.ts) and the replay
// (rehearse_s15.ts) are exercised by running them, not here.
import { describe, expect, it } from 'vitest';
import { FantasyPosition, futsalDefault } from '../src/lib/fantasy/fantasy_config';
import { FantasySquad, validateSquad } from '../src/lib/fantasy/squad';
import {
  assertEnginePaused, assertMarkerMatches, assertRequestAllowed, assertSafePaths, BACKUP_KIND,
  buildWritePlan, clearPlan, EXPECTED_NODES, fakeChildDeletes, fakeManagerDefs, fakeManagerRow,
  FillMarketEntry, StrategyTemplate, TEST_SEASON_ROOT,
} from './fill_test_season_logic';

const cfg = futsalDefault();
const ROOT = TEST_SEASON_ROOT;
const REAL = 'EsDzzsdVM9TASCyBmVbOviYZL4z1';
const REAL_NO_SQUAD = '7w3JtYKaUZYyABN1In9N5xf8qWr2';
const paused = { lockOverride: 'open', budgetTenths: 500 };

/** A small but realistic market: prices 4.0..15.0, a couple of guests. */
function market(): Record<string, FillMarketEntry> {
  const out: Record<string, FillMarketEntry> = {};
  const add = (pos: FantasyPosition, n: number) => {
    for (let i = 0; i < n; i++) {
      out[`${pos} Player ${String(i).padStart(2, '0')}`] = {
        position: pos, eligible: true, price: 40 + ((i * 35) % 115),
      };
    }
  };
  add('GK', 6);
  add('DEF', 14);
  add('ATT', 14);
  out['Guest Keeper'] = { position: 'GK', eligible: false, price: 40 };
  out['Guest Striker'] = { position: 'ATT', eligible: false, price: 40 };
  return out;
}

/** The rehearsal's persona shapes: one names players (re-targeted onto the
 *  seeded squad), one plays chips, one transfers. */
const templates: StrategyTemplate[] = [
  {
    persona: 'steady',
    weeks: { 6: { benchSwap: ['Someone Real', 'Someone Else'], captain: 'X', vice: 'Y' } },
  },
  { persona: 'chips', weeks: { 3: { chip: 'tripleCaptain' }, 4: { chip: null } } },
  { persona: 'churn', weeks: { 2: { transfers: 4 }, 6: { transfers: 3, undoOneNextDay: true } } },
];

function squadOf(
  initial: { picks: Array<[string, boolean]>; captain: string; vice: string },
  mkt: Record<string, FillMarketEntry>,
): FantasySquad {
  return {
    picks: initial.picks.map(([name, bench]) => ({
      playerId: name, position: mkt[name].position, priceTenths: mkt[name].price, bench,
    })),
    captainId: initial.captain,
    viceId: initial.vice,
    chip: null,
  };
}

/** A replayed final state, shaped like OverlayDb.get (RTDB-coerced arrays). */
function replayState(): Record<string, unknown> {
  const defs = fakeManagerDefs(2, market(), cfg, templates);
  return {
    Config: { lockOverride: 'auto', budgetTenths: 500 },
    News: { Drafts: { gw1dreamteam: { Title: 'x' } }, PushClaims: { a: 1 } },
    Voided: [null, null, true],
    Players: { 'GK Player 00': { position: 'GK', priceTenths: 45, eligible: true } },
    PlayerTotals: { 'GK Player 00': { points: 12 } },
    History: [null, { [REAL]: { TotalTenths: 30 }, 'test-01': { TotalTenths: 20 } }],
    GwState: { current: 12, status: 'finalized', lockAtUtc: 1, date: '10052026' },
    Repriced: [null, { At: 1 }],
    RecapSent: [null, { At: 1 }],
    ReminderSent: [null, { At: 1 }],
    NewsDrafted: [null, { At: 1 }],
    LockedPositions: [null, { 'GK Player 00': 'GK' }],
    TransferState: { [REAL]: { Free: 2 }, 'test-01': { Free: 3 } },
    // Client / owner inputs the replay's state also carries: never written.
    Watchlists: { [REAL]: { 'GK Player 00': true } },
    MiniLeagues: { abc: { Name: 'x' } },
    ScheduledPushes: { p1: { At: 1 } },
    Analytics: { opens: 3 },
    Managers: {
      [REAL]: { TeamName: 'Zaya.Arami', NameFlagged: false },
      'test-01': fakeManagerRow(defs[0]),
      'test-02': fakeManagerRow(defs[1]),
    },
    Squads: {
      [REAL]: { picks: [], captainId: 'a', viceId: 'b' },
      'test-01': { picks: [{ playerId: 'GK Player 00' }], captainId: 'a', viceId: 'b' },
      'test-02': { picks: [{ playerId: 'GK Player 01' }], captainId: 'a', viceId: 'b' },
    },
  };
}

const live = {
  config: paused,
  managers: {
    [REAL]: { TeamName: 'Zaya.Arami', NameFlagged: false },
    [REAL_NO_SQUAD]: { TeamName: 'Nimrud', NameFlagged: false },
  },
  squads: { [REAL]: { picks: [], captainId: 'a', viceId: 'b' } },
};

describe('buildWritePlan', () => {
  it('write plan never touches Config, News, or real managers', () => {
    const plan = buildWritePlan(replayState(), live, 1234);
    const paths = plan.map((e) => e.path);

    for (const p of paths) {
      expect(p.startsWith(`${ROOT}/`)).toBe(true);
      expect(p).not.toMatch(/\/(Config|News|Voided)(\/|$)/);
      expect(p).not.toContain(REAL);
      expect(p).not.toContain(REAL_NO_SQUAD);
    }
    // Managers / Squads only ever as fake-uid children, never whole.
    expect(paths).not.toContain(`${ROOT}/Managers`);
    expect(paths).not.toContain(`${ROOT}/Squads`);
    expect(paths.filter((p) => /\/(Managers|Squads)\//.test(p)).sort()).toEqual([
      `${ROOT}/Managers/test-01`, `${ROOT}/Managers/test-02`,
      `${ROOT}/Squads/test-01`, `${ROOT}/Squads/test-02`,
    ]);

    // Derived nodes + every done-marker.
    for (const node of ['Players', 'PlayerTotals', 'History', 'GwState', 'Repriced',
      'RecapSent', 'ReminderSent', 'NewsDrafted', 'LockedPositions', 'TransferState']) {
      expect(paths).toContain(`${ROOT}/${node}`);
    }
    // Client / owner inputs never.
    for (const node of ['Watchlists', 'MiniLeagues', 'ScheduledPushes', 'Analytics']) {
      expect(paths.some((p) => p.startsWith(`${ROOT}/${node}`)), node).toBe(false);
    }
    // Whole nodes are written in RTDB storage form (coerced arrays back to
    // index-keyed maps, no null holes).
    const history = plan.find((e) => e.path === `${ROOT}/History`)!.value;
    expect(history).toEqual({ 1: { [REAL]: { TotalTenths: 30 }, 'test-01': { TotalTenths: 20 } } });

    expect(plan.find((e) => e.path === `${ROOT}/TestFill`)!.value)
      .toEqual({ At: 1234, Managers: 2 });
  });

  it('badges: Badges + BadgePushClaims are written, the claims FIRST (the live trigger then pushes nothing)', () => {
    const state = {
      ...replayState(),
      Badges: {
        [REAL]: { champion_season: { Badge: 'champion', At: 1, Source: 'auto' } },
        'test-01': { topOfTheWeek_gw3: { Badge: 'topOfTheWeek', Gw: 3, At: 1, Source: 'auto' } },
      },
      BadgePushClaims: {
        [REAL]: { champion_season: { At: 1, Sent: 0 } },
        'test-01': { topOfTheWeek_gw3: { At: 1, Sent: 0 } },
      },
    };
    const paths = buildWritePlan(state, live, 1).map((e) => e.path);
    const claims = paths.indexOf(`${ROOT}/BadgePushClaims`);
    const badges = paths.indexOf(`${ROOT}/Badges`);
    expect(claims).toBeGreaterThan(0);
    expect(badges).toBeGreaterThan(claims);
    // Nothing outside the season: no trophy cabinet, no global catalog.
    expect(paths.every((p) => p.startsWith(`${ROOT}/`))).toBe(true);
    for (const outside of ['Users', 'BadgeCatalog']) {
      expect(() => buildWritePlan({ ...state, [outside]: { x: { y: 1 } } }, live, 1), outside)
        .toThrow(/allowlist/);
    }
    expect(() => assertSafePaths([{ path: 'Fantasy/BadgeCatalog/champion' }])).toThrow();
    expect(() => assertSafePaths([{ path: `Users/${REAL}/Awards/x` }])).toThrow();
  });

  it('FPL selling: Baselines, SquadAlerts and PreviewPushed are written, the push claims before the alerts', () => {
    const state = {
      ...replayState(),
      Baselines: {
        [REAL]: { ForGw: 13, RealizedTenths: 0, Prices: { 'GK Player 00': 45 } },
        'test-01': { ForGw: 13, RealizedTenths: -15, Prices: { 'GK Player 00': 45 } },
      },
      SquadAlerts: {
        'test-01': { Gw: 4, Kind: 'preview', Issues: ['overBudget'], OverTenths: 5, CreatedAt: 1 },
      },
      PreviewPushed: [null, null, null, null, { 'test-01': { At: 1 } }],
    };
    const plan = buildWritePlan(state, live, 1);
    const paths = plan.map((e) => e.path);
    for (const node of ['Baselines', 'SquadAlerts', 'PreviewPushed']) {
      expect(paths).toContain(`${ROOT}/${node}`);
      expect(EXPECTED_NODES).toContain(node);
    }
    expect(paths.indexOf(`${ROOT}/PreviewPushed`)).toBeLessThan(paths.indexOf(`${ROOT}/SquadAlerts`));
    // Gameweek-keyed claims go back to RTDB storage form.
    expect(plan.find((e) => e.path === `${ROOT}/PreviewPushed`)!.value)
      .toEqual({ 4: { 'test-01': { At: 1 } } });
    expect(plan.find((e) => e.path === `${ROOT}/Baselines`)!.value).toEqual(state.Baselines);
  });

  it('live: the finalize tombstone Live is written whole; the functions-only LiveBase is not on the allowlist', () => {
    // The replay's finalize runs end with the settled tombstone (live design
    // 2026-11-03 §4, Fable L5); a live run's LiveBase is removed by every
    // finalize, so a settled replay never ends holding one — refused.
    const state = { ...replayState(), Live: { Meta: { Gw: 12, State: 'settled', UpdatedAt: 1 } } };
    const plan = buildWritePlan(state, live, 1);
    expect(EXPECTED_NODES).toContain('Live');
    expect(EXPECTED_NODES).not.toContain('LiveBase');
    expect(plan.find((e) => e.path === `${ROOT}/Live`)!.value).toEqual(state.Live);
    expect(() => assertSafePaths([{ path: `${ROOT}/Live` }])).not.toThrow();
    expect(() => buildWritePlan({ ...state, LiveBase: { 12: { Gw: 12 } } }, live, 1))
      .toThrow(/LiveBase.*allowlist/);
    expect(() => assertSafePaths([{ path: `${ROOT}/LiveBase` }])).toThrow();
  });

  it('refuses to build a plan while the engine is on auto', () => {
    expect(() => buildWritePlan(replayState(), { ...live, config: { lockOverride: 'auto' } }, 1))
      .toThrow(/auto/i);
  });

  it('a node the replay produced that is NOT on the allowlist refuses the whole plan', () => {
    // Fail closed: a new engine guard must be added to EXPECTED_NODES on
    // purpose — never written (or later cleared) just because it showed up.
    expect(() => buildWritePlan({ ...replayState(), SomeFutureGuard: [null, { At: 1 }] }, live, 1))
      .toThrow(/SomeFutureGuard.*allowlist/);
  });
});

describe('assertSafePaths', () => {
  it('assertSafePaths rejects anything outside Fantasy/Futsal/15', () => {
    const ok = [`${ROOT}/Players`, `${ROOT}/Managers/test-01`, `${ROOT}/TestFill`,
      `${ROOT}/History`];
    expect(() => assertSafePaths(ok.map((path) => ({ path })))).not.toThrow();

    const bad = [
      'Fantasy/Futsal/16/Players',
      'Fantasy/Futsal/150/Players', // prefix trick
      'Fantasy/Futsal/15', // the whole season root
      'Fantasy/Futsal/15/', // ditto
      'Futsal/15/Date',
      '/Fantasy/Futsal/15/Players',
      'Fantasy/Futsal/15/../16/Players',
      'Fantasy/Futsal/15/./Players',
      'Fantasy/Futsal/15//Players',
      'Fantasy/Futsal/15/Players.json',
      'Fantasy/Futsal/15/Config',
      'Fantasy/Futsal/15/News/Drafts',
      '',
    ];
    for (const path of bad) {
      expect(() => assertSafePaths([...ok.map((p) => ({ path: p })), { path }]), path).toThrow();
    }
  });

  it('assertSafePaths is an ALLOWLIST: the plan\'s nodes, fake managers and TestFill — nothing else', () => {
    const allowed = [
      ...EXPECTED_NODES.map((n) => `${ROOT}/${n}`),
      `${ROOT}/PlayerWeeks/3`, // inside an allowed node
      `${ROOT}/Managers/test-01`, `${ROOT}/Squads/test-20/picks/0`,
      `${ROOT}/TestFill`,
    ];
    for (const path of allowed) expect(() => assertSafePaths([{ path }]), path).not.toThrow();

    const rejected = [
      `${ROOT}/ScheduledPushes`, `${ROOT}/ScheduledPushes/p1`,
      `${ROOT}/Watchlists`, `${ROOT}/Watchlists/test-01`, `${ROOT}/Watchlists/${REAL}`,
      `${ROOT}/MiniLeagues`, `${ROOT}/MiniLeagues/abc`,
      `${ROOT}/Analytics`, `${ROOT}/News`, `${ROOT}/Config`, `${ROOT}/Voided`,
      `${ROOT}/SomeFutureGuard`, `${ROOT}/${REAL}`,
      // Engine nodes the replay never produces stay off the list.
      `${ROOT}/Access`, `${ROOT}/AccessClaims/${REAL}`, `${ROOT}/PendingPositionChanges`,
      `${ROOT}/TestFill/At`, // the marker is written / deleted whole only
    ];
    for (const path of rejected) {
      expect(() => assertSafePaths([{ path }]), path).toThrow(/Refusing unsafe path/);
    }
  });

  it('assertSafePaths rejects Voided', () => {
    for (const path of [`${ROOT}/Voided`, `${ROOT}/Voided/3`]) {
      expect(() => assertSafePaths([{ path }]), path).toThrow(/Voided/);
    }
  });

  it('assertSafePaths rejects whole Managers / Squads nodes', () => {
    for (const path of [`${ROOT}/Managers`, `${ROOT}/Squads`]) {
      expect(() => assertSafePaths([{ path }]), path).toThrow(/whole/);
    }
  });

  it('assertSafePaths rejects a real manager under Managers / Squads (and anything below)', () => {
    const bad = [
      `${ROOT}/Managers/${REAL}`, `${ROOT}/Squads/${REAL}`,
      `${ROOT}/Squads/${REAL}/picks/0`, `${ROOT}/Managers/${REAL_NO_SQUAD}/TeamName`,
      `${ROOT}/Squads/test-1`, `${ROOT}/Managers/test-001`, `${ROOT}/Squads/xtest-01`,
    ];
    for (const path of bad) {
      expect(() => assertSafePaths([{ path }]), path).toThrow(/test-NN/);
    }
    // Fake managers (and anything below them) stay writable.
    expect(() => assertSafePaths([`${ROOT}/Squads/test-01`, `${ROOT}/Managers/test-20`,
      `${ROOT}/Squads/test-07/picks`].map((path) => ({ path })))).not.toThrow();
  });
});

describe('clearPlan (the --clear path set)', () => {
  const marker = { At: 1234, Managers: 20 };
  const backup = (entries: unknown[]) => ({ kind: BACKUP_KIND, root: ROOT, marker, entries });
  const good = [
    { path: `${ROOT}/TestFill`, existed: false, value: null },
    { path: `${ROOT}/Players`, existed: true, value: { 'GK Player 00': { priceTenths: 45 } } },
    { path: `${ROOT}/History`, existed: false, value: null },
    { path: `${ROOT}/Squads/test-01`, existed: false, value: null },
  ];

  it('restores existed nodes, deletes absent ones, leaves the marker for last', () => {
    expect(clearPlan(backup(good))).toEqual([
      { method: 'PUT', path: `${ROOT}/Players`, value: { 'GK Player 00': { priceTenths: 45 } } },
      { method: 'DELETE', path: `${ROOT}/History` },
      { method: 'DELETE', path: `${ROOT}/Squads/test-01` },
    ]);
  });

  it('a corrupted / hand-edited backup can never touch real managers, Voided, Config, News or another season', () => {
    const corrupt = [
      `${ROOT}/Squads`, `${ROOT}/Managers`, `${ROOT}/Squads/${REAL}`,
      `${ROOT}/Managers/${REAL}`, `${ROOT}/Voided`, `${ROOT}/Config`, `${ROOT}/News`,
      'Fantasy/Futsal/16/Players', `${ROOT}`,
      // Not on the allowlist either: a backup can't restore / delete them.
      `${ROOT}/ScheduledPushes`, `${ROOT}/Watchlists`, `${ROOT}/Watchlists/${REAL}`,
      `${ROOT}/MiniLeagues`, `${ROOT}/Analytics`, `${ROOT}/SomeOtherNode`,
    ];
    for (const path of corrupt) {
      for (const existed of [false, true]) {
        const entry = { path, existed, value: existed ? { x: 1 } : null };
        expect(() => clearPlan(backup([...good, entry])), `${path} existed=${existed}`)
          .toThrow(/Refusing unsafe path/);
      }
    }
  });

  it('rejects anything that is not a fill backup of this season', () => {
    expect(() => clearPlan(null)).toThrow(/fill backup/);
    expect(() => clearPlan({ kind: 'nope', root: ROOT, marker, entries: good })).toThrow(/fill backup/);
    expect(() => clearPlan({ kind: BACKUP_KIND, root: 'Fantasy/Futsal/16', marker, entries: good }))
      .toThrow(/fill backup/);
    expect(() => clearPlan({ kind: BACKUP_KIND, root: ROOT, marker, entries: 'x' })).toThrow(/fill backup/);
    expect(() => clearPlan(backup([{ path: `${ROOT}/Players`, existed: true, value: null }])))
      .toThrow(/Malformed/);
    expect(() => clearPlan(backup([{ path: `${ROOT}/Players`, existed: 'yes', value: {} }])))
      .toThrow(/Malformed/);
  });

  it('a backup without the TestFill marker it wrote is refused', () => {
    for (const bad of [undefined, null, 'x', 5, []]) {
      expect(() => clearPlan({ kind: BACKUP_KIND, root: ROOT, marker: bad, entries: good }), String(bad))
        .toThrow(/marker/);
    }
  });

  it('fakeChildDeletes only ever names test-NN children', () => {
    expect(fakeChildDeletes('Squads', [REAL, 'test-01', 'test-1', 'test-20'])).toEqual([
      { method: 'DELETE', path: `${ROOT}/Squads/test-01` },
      { method: 'DELETE', path: `${ROOT}/Squads/test-20` },
    ]);
    expect(fakeChildDeletes('Managers', [REAL_NO_SQUAD])).toEqual([]);
  });
});

describe('assertMarkerMatches (--clear only undoes the fill its backup came from)', () => {
  const backup = { kind: BACKUP_KIND, root: ROOT, marker: { At: 1234, Managers: 20 }, entries: [] };

  it('the live marker must exist and equal the backup\'s (key order aside)', () => {
    expect(() => assertMarkerMatches({ Managers: 20, At: 1234 }, backup)).not.toThrow();
  });

  it('refuses when the live marker is missing (never filled, or already cleared)', () => {
    expect(() => assertMarkerMatches(null, backup)).toThrow(/no TestFill marker/);
    expect(() => assertMarkerMatches(undefined, backup)).toThrow(/no TestFill marker/);
  });

  it('refuses when the live marker belongs to ANOTHER fill', () => {
    expect(() => assertMarkerMatches({ At: 9999, Managers: 20 }, backup)).toThrow(/does not match/);
    expect(() => assertMarkerMatches({ At: 1234, Managers: 19 }, backup)).toThrow(/does not match/);
    expect(() => assertMarkerMatches({ At: 1234, Managers: 20, Extra: 1 }, backup)).toThrow(/does not match/);
  });

  it('refuses a backup that carries no marker at all', () => {
    expect(() => assertMarkerMatches({ At: 1234, Managers: 20 }, { ...backup, marker: undefined }))
      .toThrow(/marker/);
  });
});

describe('assertRequestAllowed (every REST call the CLI makes)', () => {
  const reads = ['Futsal/15/Date'];

  it('a read-only (dry run) client can GET but never PUT or DELETE', () => {
    expect(() => assertRequestAllowed('GET', `${ROOT}/Squads`, { readOnly: true, readPaths: reads })).not.toThrow();
    expect(() => assertRequestAllowed('GET', 'Futsal/15/Date', { readOnly: true, readPaths: reads })).not.toThrow();
    for (const method of ['PUT', 'DELETE', 'PATCH', 'POST']) {
      expect(() => assertRequestAllowed(method, `${ROOT}/Players`, { readOnly: true, readPaths: reads }), method)
        .toThrow(/read-only/);
    }
  });

  it('reads stay inside the test season + the replay inputs; writes go through assertSafePaths', () => {
    expect(() => assertRequestAllowed('GET', 'Users', { readOnly: false, readPaths: reads })).toThrow();
    expect(() => assertRequestAllowed('GET', 'Fantasy/Futsal/16/Squads', { readOnly: false, readPaths: reads })).toThrow();
    expect(() => assertRequestAllowed('PUT', `${ROOT}/Players`, { readOnly: false, readPaths: reads })).not.toThrow();
    expect(() => assertRequestAllowed('DELETE', `${ROOT}/Squads/${REAL}`, { readOnly: false, readPaths: reads })).toThrow();
    expect(() => assertRequestAllowed('PUT', 'Futsal/15/Date', { readOnly: false, readPaths: reads })).toThrow();
    expect(() => assertRequestAllowed('PATCH', `${ROOT}/Players`, { readOnly: false, readPaths: reads })).toThrow();
  });
});

describe('assertEnginePaused', () => {
  it('assertEnginePaused rejects auto and rejects an auto-return time', () => {
    expect(() => assertEnginePaused({ lockOverride: 'open' })).not.toThrow();
    expect(() => assertEnginePaused({ lockOverride: 'locked' })).not.toThrow();

    expect(() => assertEnginePaused({ lockOverride: 'auto' })).toThrow();
    expect(() => assertEnginePaused({})).toThrow(); // absent = auto
    expect(() => assertEnginePaused({ lockOverride: 'Open' })).toThrow(); // engine reads it as auto
    expect(() => assertEnginePaused(null)).toThrow();
    expect(() => assertEnginePaused({ lockOverride: 'open', lockOverrideUntil: 1893456000000 }))
      .toThrow(/lockOverrideUntil/);
    expect(() => assertEnginePaused({ lockOverride: 'locked', lockOverrideUntil: 'junk' }))
      .toThrow(/lockOverrideUntil/);
  });
});

describe('fakeManagerDefs', () => {
  it('20 fake managers with deterministic team names', () => {
    const a = fakeManagerDefs(20, market(), cfg, templates);
    const b = fakeManagerDefs(20, market(), cfg, templates);
    expect(a).toEqual(b);

    expect(a.map((d) => d.uid)).toEqual(
      Array.from({ length: 20 }, (_, i) => `test-${String(i + 1).padStart(2, '0')}`));
    const names = a.map((d) => d.name);
    expect(new Set(names).size).toBe(20);
    for (const n of names) {
      expect(n.trim().length).toBeGreaterThanOrEqual(3);
      expect(n.length).toBeLessThanOrEqual(30);
    }
    for (const d of a) expect(fakeManagerRow(d)).toEqual({ TeamName: d.name, NameFlagged: false });

    // Seeded, not cloned: the squads differ between managers.
    expect(new Set(a.map((d) => d.initial.picks.map(([n]) => n).sort().join('|'))).size)
      .toBeGreaterThan(15);

    // Strategies cycle through the templates.
    expect(a[0].persona).toContain('steady');
    expect(a[3].persona).toContain('steady');
    expect(a[4].weeks).toEqual(templates[1].weeks);
    expect(a[5].weeks).toEqual(templates[2].weeks);

    const mkt = market();
    for (const d of a) {
      const s = squadOf(d.initial, mkt);
      expect(validateSquad(s, cfg), d.uid).toEqual([]);
      for (const p of s.picks) expect(mkt[p.playerId].eligible).toBe(true);
      // Named steps are re-targeted onto this manager's own squad and keep
      // it legal (armband swap + a same-position bench swap).
      const wk6 = d.weeks[6];
      if (d.persona.includes('steady')) {
        expect(wk6.captain).toBe(d.initial.vice);
        expect(wk6.vice).toBe(d.initial.captain);
        const [inName, outName] = wk6.benchSwap!;
        const swapped: FantasySquad = {
          ...s,
          picks: s.picks.map((p) => (p.playerId === inName || p.playerId === outName
            ? { ...p, bench: !p.bench } : p)),
          captainId: wk6.captain!,
          viceId: wk6.vice!,
        };
        expect(validateSquad(swapped, cfg), d.uid).toEqual([]);
      }
    }

    // Two runs -> identical Managers/Squads part of the plan.
    const stateFor = () => ({
      Players: {},
      Managers: Object.fromEntries(a.map((d) => [d.uid, fakeManagerRow(d)])),
      Squads: Object.fromEntries(a.map((d) => [d.uid, { initial: d.initial }])),
    });
    const fakePart = (plan: Array<{ path: string; value: unknown }>) =>
      plan.filter((e) => /\/(Managers|Squads)\//.test(e.path));
    const p1 = fakePart(buildWritePlan(stateFor(), live, 1));
    const p2 = fakePart(buildWritePlan(stateFor(), live, 2));
    expect(p1).toHaveLength(40);
    expect(p1).toEqual(p2);
  });
});
