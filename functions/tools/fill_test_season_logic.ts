// Infinite Fantasy — pure logic of the Season 15 TEST-SEASON FILL tool
// (spec 2026-10-29 §9; the CLI is fill_test_season.ts, the replay is
// rehearse_s15.ts runReplay). No I/O here: everything is unit-tested in
// fill_test_season_logic.test.ts.
//
// - buildWritePlan: which nodes of the replayed Fantasy/Futsal/15 subtree go
//   to the live test season, and how (whole node vs fake-manager child).
// - assertSafePaths / assertEnginePaused: the two refusals that make the
//   tool safe to point at production.
// - fakeManagerDefs: the 20 deterministic made-up managers (test-01..test-20)
//   that play the client role in the replay.

import { lockOverrideOf } from '../src/lib/fantasy/orchestration_db';

/** The ONLY subtree this tool may ever write. */
export const TEST_SEASON_ROOT = 'Fantasy/Futsal/15';

/** test-01 … test-99: the fake managers' uids (real Firebase uids are
 *  28-character random strings, so the two can never collide). */
export const FAKE_UID_PATTERN = /^test-\d{2}$/;

export function fakeUid(index: number): string {
  return `test-${String(index + 1).padStart(2, '0')}`;
}

export function isFakeUid(uid: string): boolean {
  return FAKE_UID_PATTERN.test(uid);
}

/** Fun team names for the fake managers (3–30 chars: the Managers rule). */
export const FAKE_TEAM_NAMES: readonly string[] = [
  'Nutmeg Ninjas', 'Top Bins FC', 'Panenka Pandas', 'Rabona Rebels',
  'Toe Poke Titans', 'Clean Sheet Club', 'Offside Trappers', 'Hat Trick Heroes',
  'Bench Warmers United', 'Golden Boot Camp', 'Sweeper Keepers', 'Mid Table Mafia',
  'Volley Llamas', 'Through Ball Wizards', 'Dribble Dynasty', 'Counter Attack Cats',
  'Back Of The Net', 'Futsal Fanatics', 'Post And Bar FC', 'Late Winner Legends',
];

/** Top-level nodes that are never written whole: owner/client inputs and
 *  the news desk. Managers/Squads are written only as fake-uid children. */
export const NEVER_WRITTEN_WHOLE: readonly string[] = [
  'Config', 'News', 'Managers', 'Squads', 'Voided', 'TestFill',
  'Watchlists', 'MiniLeagues', 'ScheduledPushes', 'Analytics',
];

/** Nodes the spec expects the replay to produce (the dry run warns when one
 *  is missing — any OTHER pipeline-produced node is written too).
 *
 *  Badges + BadgePushClaims (spec 2026-10-30 §4): the replay's auto awards
 *  and the stub pusher's once-only claims for every one of them. The plan
 *  writes whole nodes in sorted key order, so BadgePushClaims ('P' < 's')
 *  lands BEFORE Badges: when the live badge trigger fires for the created
 *  award rows, every claim already exists and nothing is pushed (and the
 *  trigger never pushes an auto award in a paused season anyway). The
 *  global Fantasy/BadgeCatalog the replay's sweep seeds and any trophy
 *  cabinet copy (Users/<uid>/Awards — never produced: the replay has no
 *  Users node) are outside this season and never part of the plan. */
export const EXPECTED_NODES: readonly string[] = [
  'Players', 'PlayerTotals', 'PlayerWeeks', 'PlayerWeekStats', 'PriceHistory',
  'PriceChanges', 'Leaderboards', 'History', 'PublishedPicks', 'DreamTeam',
  'TransferState', 'TransferCosts', 'GwState', 'LockedPositions', 'Repriced',
  'RecapSent', 'NewsDrafted', 'ReminderSent', 'Badges', 'BadgePushClaims',
];

export interface PlanEntry {
  path: string;
  value: unknown;
}

/** What the tool read from the live test season before replaying. */
export interface LiveSeason {
  config: unknown;
  managers: unknown;
  squads: unknown;
}

function isMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function keysOf(node: unknown): string[] {
  if (Array.isArray(node)) {
    return node.map((v, i) => (v === null || v === undefined ? null : String(i)))
      .filter((k): k is string => k !== null);
  }
  return isMap(node) ? Object.keys(node).filter((k) => node[k] != null) : [];
}

/** RTDB storage form: arrays (RTDB's coerced read shape) back to
 *  index-keyed maps, null/undefined children dropped, empty containers
 *  become null (RTDB would treat {} as a removal anyway). */
export function storageForm(v: unknown): unknown {
  if (v === null || v === undefined) return null;
  if (Array.isArray(v)) {
    const o: Record<string, unknown> = {};
    v.forEach((x, i) => {
      const s = storageForm(x);
      if (s !== null) o[String(i)] = s;
    });
    return Object.keys(o).length > 0 ? o : null;
  }
  if (typeof v === 'object') {
    const o: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
      const s = storageForm(x);
      if (s !== null) o[k] = s;
    }
    return Object.keys(o).length > 0 ? o : null;
  }
  return v;
}

/** Throws unless the season's engine is paused for good: the EFFECTIVE
 *  lock override (the engine's own reading, orchestration_db.lockOverrideOf)
 *  is 'open' or 'locked' AND there is no auto-return time — a
 *  Config/lockOverrideUntil would hand the season back to the engine. */
export function assertEnginePaused(config: unknown): void {
  if (!isMap(config)) {
    throw new Error('Refusing: the test season has no Config.');
  }
  const until = config['lockOverrideUntil'];
  if (until !== undefined && until !== null) {
    throw new Error('Refusing: Config/lockOverrideUntil is set — the engine ' +
      'would return to Auto on its own. Pause it with "Never (testing)" first.');
  }
  const effective = lockOverrideOf(config);
  if (effective !== 'open' && effective !== 'locked') {
    throw new Error(`Refusing: the engine is on ${effective} ` +
      `(lockOverride ${JSON.stringify(config['lockOverride'] ?? null)}); ` +
      'the test season must be paused (Open or Locked).');
  }
}

// eslint-disable-next-line no-control-regex
const BAD_SEGMENT = /[.#$[\]\u0000-\u001F\u007F]/;
const FORBIDDEN_TOP = new Set(['Config', 'News', 'Voided']);
const FAKE_ONLY_TOP = new Set(['Managers', 'Squads']);
const MARKER_NODE = 'TestFill';
/** The derived + done-marker nodes the plan writes whole (and nothing else). */
const ALLOWED_WHOLE = new Set(EXPECTED_NODES);

/** The guard EVERY write and delete passes (the plan, the --clear set, and
 *  each single REST call) — an ALLOWLIST. Throws unless the path is a real
 *  child of Fantasy/Futsal/15/ (no other season — Fantasy/Futsal/150
 *  included —, never the season root itself, no empty / dot / RTDB-illegal
 *  segments) AND is one of:
 *    - an [EXPECTED_NODES] node (the replay's derived data and the engine's
 *      done-markers), or anything inside one;
 *    - Managers/<test-NN> or Squads/<test-NN> (or below) — never the whole
 *      node, never a real uid;
 *    - the TestFill marker itself.
 *  Everything else — Config, News, Voided, Watchlists, MiniLeagues,
 *  ScheduledPushes, Analytics, a real uid, any node nobody listed — is
 *  refused, so neither the plan nor a hand-edited backup can reach it. */
export function assertSafePaths(plan: ReadonlyArray<{ path: string }>): void {
  const prefix = `${TEST_SEASON_ROOT}/`;
  for (const { path } of plan) {
    const why = (reason: string) =>
      new Error(`Refusing unsafe path ${JSON.stringify(path)}: ${reason}`);
    if (typeof path !== 'string' || !path.startsWith(prefix)) {
      throw why(`outside ${prefix}`);
    }
    const rest = path.slice(prefix.length).split('/');
    if (rest.length === 0 || rest.some((s) => s.length === 0 || BAD_SEGMENT.test(s))) {
      throw why('empty or illegal segment');
    }
    const top = rest[0];
    if (FORBIDDEN_TOP.has(top)) throw why(`${top} is never written`);
    if (FAKE_ONLY_TOP.has(top)) {
      if (rest.length === 1) throw why(`${top} is never written whole`);
      if (!isFakeUid(rest[1])) throw why(`${top} only for fake managers (test-NN)`);
      continue;
    }
    if (top === MARKER_NODE) {
      if (rest.length !== 1) throw why('the TestFill marker is only written / deleted whole');
      continue;
    }
    if (!ALLOWED_WHOLE.has(top)) {
      throw why(`${top} is not on the fill allowlist ` +
        '(EXPECTED_NODES, Managers|Squads/test-NN, TestFill)');
    }
  }
}

/** Deterministic JSON (object keys sorted, arrays in order) — for comparing
 *  RTDB values whose key order is not guaranteed. */
export function canonicalJson(v: unknown): string {
  const sortDeep = (x: unknown): unknown => {
    if (Array.isArray(x)) return x.map(sortDeep);
    if (x !== null && typeof x === 'object') {
      const o: Record<string, unknown> = {};
      for (const k of Object.keys(x as Record<string, unknown>).sort()) {
        o[k] = sortDeep((x as Record<string, unknown>)[k]);
      }
      return o;
    }
    return x;
  };
  return JSON.stringify(sortDeep(v)) ?? 'undefined';
}

/** One REST call the CLI is about to make. Reads: the test season or the
 *  replay's own input paths [readPaths]. A read-only client (the dry run)
 *  can never PUT/DELETE; a writing client only PUTs/DELETEs paths that
 *  pass assertSafePaths. */
export function assertRequestAllowed(
  method: string, path: string, opts: { readOnly: boolean; readPaths: readonly string[] },
): void {
  if (method === 'GET') {
    if (!path.startsWith(`${TEST_SEASON_ROOT}/`) && !opts.readPaths.includes(path)) {
      throw new Error(`Refusing GET of ${path}`);
    }
    return;
  }
  if (opts.readOnly) throw new Error(`Refusing ${method} ${path}: read-only client (dry run)`);
  if (method !== 'PUT' && method !== 'DELETE') throw new Error(`Refusing ${method} ${path}`);
  assertSafePaths([{ path }]);
}

// ── --clear ────────────────────────────────────────────────────────────────

export const BACKUP_KIND = 'fantasy-test-fill-backup';
export const TEST_FILL_MARKER = `${TEST_SEASON_ROOT}/TestFill`;

export interface ClearOp {
  method: 'PUT' | 'DELETE';
  path: string;
  value?: unknown;
}

/** The TestFill marker value a backup recorded at --apply time (the value
 *  that fill wrote); throws when the backup carries none. */
function backupMarker(backup: Record<string, unknown>): Record<string, unknown> {
  const marker = backup['marker'];
  if (!isMap(marker)) {
    throw new Error('The backup has no TestFill marker of its own — it cannot prove which ' +
      'fill it belongs to, so --clear will not use it.');
  }
  return marker;
}

/** --clear only undoes the fill its backup came from: the LIVE TestFill
 *  marker must exist (absent = never filled, or already cleared — nothing
 *  for this backup to undo) and equal the marker the backup recorded at
 *  --apply time (another value = a different fill, whose nodes this
 *  backup's "before" values would wrongly overwrite). */
export function assertMarkerMatches(liveMarker: unknown, backup: unknown): void {
  if (!isMap(backup)) throw new Error(`Not a ${TEST_SEASON_ROOT} fill backup.`);
  const recorded = backupMarker(backup);
  if (liveMarker === null || liveMarker === undefined) {
    throw new Error(`Refusing --clear: the live test season has no TestFill marker ` +
      '(never filled, or already cleared) — nothing for this backup to undo.');
  }
  if (canonicalJson(liveMarker) !== canonicalJson(recorded)) {
    throw new Error(`Refusing --clear: the live TestFill marker ${canonicalJson(liveMarker)} ` +
      `does not match this backup's ${canonicalJson(recorded)} — the season holds a ` +
      'different fill than the one this backup was taken for.');
  }
}

/** The restore half of --clear, from a backup file's parsed JSON: PUT every
 *  node that existed before the fill, DELETE every one that was absent —
 *  the marker excluded (the CLI deletes it last). The backup is untrusted
 *  input: wrong kind/season, no recorded TestFill marker, malformed
 *  entries, or ANY path failing assertSafePaths throws before a single op is
 *  returned. */
export function clearPlan(backup: unknown): ClearOp[] {
  if (!isMap(backup) || backup['kind'] !== BACKUP_KIND || backup['root'] !== TEST_SEASON_ROOT ||
    !Array.isArray(backup['entries'])) {
    throw new Error(`Not a ${TEST_SEASON_ROOT} fill backup.`);
  }
  backupMarker(backup);
  const entries = backup['entries'] as unknown[];
  for (const e of entries) {
    if (!isMap(e) || typeof e['path'] !== 'string' || typeof e['existed'] !== 'boolean' ||
      (e['existed'] === true && (e['value'] === null || e['value'] === undefined))) {
      throw new Error(`Malformed backup entry ${JSON.stringify(e)?.slice(0, 120)}.`);
    }
  }
  const typed = entries as Array<{ path: string; existed: boolean; value: unknown }>;
  assertSafePaths(typed);
  return typed.filter((e) => e.path !== TEST_FILL_MARKER).map((e) => (e.existed
    ? { method: 'PUT' as const, path: e.path, value: e.value }
    : { method: 'DELETE' as const, path: e.path }));
}

/** --clear's sweep of leftover fake managers: DELETE Managers|Squads/<uid>
 *  for the live child keys that are fake (test-NN) — never anything else. */
export function fakeChildDeletes(node: 'Managers' | 'Squads', liveKeys: readonly string[]): ClearOp[] {
  const ops = [...liveKeys].filter(isFakeUid).sort()
    .map((uid) => ({ method: 'DELETE' as const, path: `${TEST_SEASON_ROOT}/${node}/${uid}` }));
  assertSafePaths(ops);
  return ops;
}

/** The fill's writes, in order: the TestFill marker first (so a partial
 *  apply is visibly marked), then every top-level node the replay produced
 *  — derived data AND the engine's once-only done-markers, all of them on
 *  the [EXPECTED_NODES] allowlist — whole, then the fake managers'
 *  Managers/Squads children. Never Config, News, Voided, the other client /
 *  owner inputs ([NEVER_WRITTEN_WHOLE]), or anything of a real manager's
 *  Managers/Squads. A replayed node on NEITHER list refuses the whole plan
 *  (fail closed: a new engine guard is added to EXPECTED_NODES on purpose,
 *  never written just because it showed up). */
export function buildWritePlan(
  state: Record<string, unknown>, live: LiveSeason, nowMs: number = Date.now(),
): PlanEntry[] {
  assertEnginePaused(live.config);
  const root = TEST_SEASON_ROOT;
  const fakeUids = [...new Set([...keysOf(state['Managers']), ...keysOf(state['Squads'])])]
    .filter(isFakeUid).sort();

  const plan: PlanEntry[] = [
    { path: `${root}/${MARKER_NODE}`, value: { At: nowMs, Managers: fakeUids.length } },
  ];
  const never = new Set(NEVER_WRITTEN_WHOLE);
  for (const key of Object.keys(state).sort()) {
    if (never.has(key)) continue;
    const value = storageForm(state[key]);
    if (value === null) continue;
    if (!ALLOWED_WHOLE.has(key)) {
      throw new Error(`Refusing: the replay produced ${key}, which is not on the fill ` +
        'allowlist (EXPECTED_NODES). If it is derived data or an engine done-marker, add ' +
        'it to EXPECTED_NODES in fill_test_season_logic.ts; nothing was written.');
    }
    plan.push({ path: `${root}/${key}`, value });
  }
  for (const node of ['Managers', 'Squads']) {
    const parent = state[node];
    for (const uid of fakeUids) {
      const value = storageForm(isMap(parent) ? parent[uid] : null);
      if (value !== null) plan.push({ path: `${root}/${node}/${uid}`, value });
    }
  }

  // Belt and braces: a real manager's Managers/Squads entry is never a path.
  const real = [...keysOf(live.managers), ...keysOf(live.squads)].filter((u) => !isFakeUid(u));
  for (const e of plan) {
    for (const uid of real) {
      if (e.path === `${root}/Managers/${uid}` || e.path === `${root}/Squads/${uid}`) {
        throw new Error(`Refusing: the plan would write a real manager (${e.path}).`);
      }
    }
  }
  assertSafePaths(plan);
  return plan;
}

/** Real managers in the live test season: every non-fake uid with a saved
 *  squad (replayed), and the ones with a Managers row but no squad (nothing
 *  to replay — reported). */
export function realManagersOf(live: LiveSeason): {
  squads: Record<string, unknown>; withoutSquad: string[];
} {
  const squads: Record<string, unknown> = {};
  for (const uid of keysOf(live.squads).filter((u) => !isFakeUid(u)).sort()) {
    squads[uid] = (live.squads as Record<string, unknown>)[uid];
  }
  const withoutSquad = keysOf(live.managers)
    .filter((u) => !isFakeUid(u) && !(u in squads)).sort();
  return { squads, withoutSquad };
}

// ═════════════════════════════════════════════════════════════════════════
// Fake managers
// ═════════════════════════════════════════════════════════════════════════

export type FillPosition = 'GK' | 'DEF' | 'ATT';

export interface FillMarketEntry {
  position: FillPosition;
  eligible: boolean;
  price: number;
}

export interface FillFormation {
  startersGk: number;
  startersDef: number;
  startersAtt: number;
  benchDef: number;
  benchAtt: number;
  budgetTenths: number;
}

/** Same shape as rehearse_s15.ts WeekPlan (one week of a manager's script). */
export interface FillWeekPlan {
  transfers?: number;
  rebuild?: 'freeHit' | 'wildcard';
  chip?: string | null;
  benchSwap?: [string, string];
  captain?: string;
  vice?: string;
  undoOneNextDay?: boolean;
}

/** A rehearsal persona's script, reused (cycled) by the fake managers. */
export interface StrategyTemplate {
  persona: string;
  weeks: Record<number, FillWeekPlan>;
}

/** Same shape as rehearse_s15.ts ManagerDef. */
export interface FakeManagerDef {
  uid: string;
  name: string;
  persona: string;
  initial: { picks: Array<[string, boolean]>; captain: string; vice: string };
  weeks: Record<number, FillWeekPlan>;
}

export function fakeManagerRow(def: FakeManagerDef): { TeamName: string; NameFlagged: false } {
  return { TeamName: def.name, NameFlagged: false };
}

/** FNV-1a 32-bit — a stable seed from a string. */
function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** mulberry32: a tiny deterministic PRNG in [0, 1). */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const byName = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/** A legal, affordable 7-a-side squad drawn from the ELIGIBLE market with a
 *  PRNG seeded by [seedKey]: slots filled in a fixed order, each with the
 *  first player of a seeded shuffle that still leaves room for the cheapest
 *  fill of every remaining slot. Bench = the cheapest pick(s) of each bench
 *  position; captain/vice = the two priciest starters. */
export function seededInitialSquad(
  market: Record<string, FillMarketEntry>, f: FillFormation, seedKey: string,
): FakeManagerDef['initial'] {
  const rng = mulberry32(fnv1a(seedKey));
  const pool = (pos: FillPosition) => {
    const list = Object.entries(market)
      .filter(([, p]) => p.eligible && p.position === pos)
      .sort(([a], [b]) => byName(a, b))
      .map(([name, p]) => ({ name, price: p.price }));
    for (let i = list.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [list[i], list[j]] = [list[j], list[i]];
    }
    return list;
  };
  const pools: Record<FillPosition, Array<{ name: string; price: number }>> =
    { GK: pool('GK'), DEF: pool('DEF'), ATT: pool('ATT') };
  const slots: FillPosition[] = [
    ...Array<FillPosition>(f.startersGk).fill('GK'),
    ...Array<FillPosition>(f.startersDef + f.benchDef).fill('DEF'),
    ...Array<FillPosition>(f.startersAtt + f.benchAtt).fill('ATT'),
  ];
  const taken = new Set<string>();
  const reserveFor = (rest: FillPosition[], skip: Set<string>): number => {
    let sum = 0;
    for (const pos of ['GK', 'DEF', 'ATT'] as FillPosition[]) {
      const need = rest.filter((p) => p === pos).length;
      if (need === 0) continue;
      const prices = pools[pos].filter((c) => !skip.has(c.name)).map((c) => c.price)
        .sort((a, b) => a - b);
      if (prices.length < need) return Infinity;
      for (let i = 0; i < need; i++) sum += prices[i];
    }
    return sum;
  };
  const chosen: Array<{ name: string; pos: FillPosition; price: number }> = [];
  let spent = 0;
  slots.forEach((pos, i) => {
    const rest = slots.slice(i + 1);
    const pick = pools[pos].find((c) => !taken.has(c.name) &&
      spent + c.price + reserveFor(rest, new Set([...taken, c.name])) <= f.budgetTenths);
    if (!pick) throw new Error(`seededInitialSquad(${seedKey}): no affordable ${pos}`);
    taken.add(pick.name);
    chosen.push({ name: pick.name, pos, price: pick.price });
    spent += pick.price;
  });

  const cheapestFirst = (a: { name: string; price: number }, b: { name: string; price: number }) =>
    a.price - b.price || byName(a.name, b.name);
  const bench = new Set<string>();
  for (const [pos, n] of [['DEF', f.benchDef], ['ATT', f.benchAtt]] as Array<[FillPosition, number]>) {
    chosen.filter((c) => c.pos === pos).sort(cheapestFirst).slice(0, n)
      .forEach((c) => bench.add(c.name));
  }
  const starters = chosen.filter((c) => !bench.has(c.name))
    .sort((a, b) => b.price - a.price || byName(a.name, b.name));
  return {
    picks: chosen.map((c) => [c.name, bench.has(c.name)] as [string, boolean]),
    captain: starters[0].name,
    vice: starters[1].name,
  };
}

/** A template's named steps (bench swap, armband change) name the
 *  rehearsal persona's own players, so they are re-targeted onto this
 *  manager's squad: the armband swaps captain <-> vice, the bench swap
 *  trades a bench pick with a same-position starter that holds no armband.
 *  Only while the squad is still the initial one — after a transfer the
 *  names are unknown in advance, so the step is dropped. */
function retargetWeeks(
  weeks: Record<number, FillWeekPlan>, initial: FakeManagerDef['initial'],
  market: Record<string, FillMarketEntry>,
): Record<number, FillWeekPlan> {
  const out: Record<number, FillWeekPlan> = {};
  let rebuilt = false;
  for (const gw of Object.keys(weeks).map(Number).sort((a, b) => a - b)) {
    const plan: FillWeekPlan = { ...weeks[gw] };
    if (plan.transfers || plan.rebuild) rebuilt = true;
    const wantSwap = plan.benchSwap !== undefined;
    const wantArmband = plan.captain !== undefined || plan.vice !== undefined;
    delete plan.benchSwap;
    delete plan.captain;
    delete plan.vice;
    if (!rebuilt && wantArmband) {
      plan.captain = initial.vice;
      plan.vice = initial.captain;
    }
    if (!rebuilt && wantSwap) {
      const armbands = new Set([plan.captain ?? initial.captain, plan.vice ?? initial.vice]);
      for (const [benchName, isBench] of initial.picks) {
        if (!isBench) continue;
        const pos = market[benchName]?.position;
        const starter = initial.picks.find(([n, b]) =>
          !b && market[n]?.position === pos && !armbands.has(n));
        if (starter) {
          plan.benchSwap = [starter[0], benchName];
          break;
        }
      }
    }
    out[gw] = plan;
  }
  return out;
}

/** [count] fake managers test-01.. with fixed fun names, seeded squads and
 *  the rehearsal's strategies cycled (manager i plays template i % n). */
export function fakeManagerDefs(
  count: number, market: Record<string, FillMarketEntry>, formation: FillFormation,
  templates: readonly StrategyTemplate[],
): FakeManagerDef[] {
  if (count > FAKE_TEAM_NAMES.length) {
    throw new Error(`At most ${FAKE_TEAM_NAMES.length} fake managers (asked ${count}).`);
  }
  if (templates.length === 0) throw new Error('No strategy templates.');
  const out: FakeManagerDef[] = [];
  for (let i = 0; i < count; i++) {
    const uid = fakeUid(i);
    const t = templates[i % templates.length];
    const initial = seededInitialSquad(market, formation, `fantasy-test-fill/${uid}`);
    out.push({
      uid,
      name: FAKE_TEAM_NAMES[i],
      persona: `cycled from: ${t.persona}`,
      initial,
      weeks: retargetWeeks(t.weeks, initial, market),
    });
  }
  return out;
}
