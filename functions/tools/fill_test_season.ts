// Infinite Fantasy — fill the paused Season 15 TEST season with a replayed
// season, so every fantasy screen has real-looking data (spec 2026-10-29 §9).
//
// WHAT IT DOES
//   1. GETs a fresh snapshot (the rehearsal's READ_PATHS + the live
//      Fantasy/Futsal/15 Squads, Managers and TestFill) into
//      tools/rehearsal_out/fill_snapshot.json (--offline replays that cache).
//      Dry run AND --apply read with the same admin GETs (the firebase-tools
//      login), so the preview works under any read rules; the dry run's
//      client is read-only (it cannot PUT/DELETE). If no admin token can be
//      minted, a dry run falls back to public reads (behind the rehearsal's
//      GET-only network guard) and says so; a path that read is denied
//      refuses the run — no input is ever silently skipped.
//   2. Replays all of Season 15 in memory through the REAL pipeline
//      (rehearse_s15.ts runReplay): 20 made-up managers test-01..test-20 +
//      every real manager's saved squad held every week (a squad the client
//      path rejects is skipped and listed — never repaired).
//   3. Builds the write plan (fill_test_season_logic.ts buildWritePlan):
//      every node the replay produced (derived data + the engine's once-only
//      done-markers) whole, the fake managers' Managers/Squads children, and
//      the marker TestFill = { At, Managers: 20 }. Never Config, News,
//      Voided, or a real manager's Managers/Squads.
//
// MODES (run from functions/)
//   npm run fill:s15                          DRY RUN (default): prints every
//                                             path + JSON size + skipped
//                                             managers; writes NOTHING
//   npm run fill:s15 -- --offline             dry run from the cached snapshot
//   npm run fill:s15 -- --apply               backs up every target node to
//                                             rehearsal_out/fill_backup_<ISO>.json,
//                                             then PUTs the plan
//   npm run fill:s15 -- --clear <backupFile>  restores every backed-up node
//                                             (PUT original / DELETE if it was
//                                             absent), deletes Managers/test-*,
//                                             Squads/test-* and TestFill
//
// SAFETY
//   - Refuses unless the live engine is paused for good: lockOverride
//     'open'/'locked' and NO Config/lockOverrideUntil (re-checked with an
//     admin read right before writing or clearing).
//   - Every write/delete passes assertSafePaths (on the plan, on the backup
//     via clearPlan before any login, and again on every single REST call):
//     only children of Fantasy/Futsal/15/, never Config/News/Voided, and
//     Managers/Squads only under a fake test-NN uid.
//   - --apply refuses when the season is already filled (TestFill present),
//     when the replay broke an invariant or crashed, or when Config changed
//     since the snapshot.
//   - Writes use an OAuth access token minted from the firebase-tools login
//     (~/.config/configstore/firebase-tools.json). The token is never
//     printed, logged, or put in an error message.

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
  assertEnginePaused, assertRequestAllowed, assertSafePaths, BACKUP_KIND,
  buildWritePlan, clearPlan, EXPECTED_NODES, fakeChildDeletes, isFakeUid, LiveSeason,
  PlanEntry, realManagersOf, TEST_FILL_MARKER, TEST_SEASON_ROOT,
} from './fill_test_season_logic';
import {
  DB_URL, installNetworkGuard, loadSnapshot, READ_PATHS, runReplay, Snapshot,
} from './rehearse_s15';

/* eslint-disable @typescript-eslint/no-explicit-any */

const ROOT = TEST_SEASON_ROOT;
const MANAGER_COUNT = 20;
const OUT_DIR = path.join(process.cwd(), 'tools', 'rehearsal_out');
const SNAPSHOT_FILE = 'fill_snapshot.json';
const LIVE_PATHS = [`${ROOT}/Squads`, `${ROOT}/Managers`, `${ROOT}/TestFill`];
const MARKER = TEST_FILL_MARKER;
// The public firebase-tools "installed app" OAuth client (shipped in the
// firebase-tools source; not a secret) — what `firebase login` minted the
// refresh token for.
const OAUTH_CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const OAUTH_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const USAGE = 'Usage: npm run fill:s15 [-- --offline | -- --apply | -- --clear <backupFile>]';

function canon(v: unknown): string {
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
  return JSON.stringify(sortDeep(v));
}

function bytes(v: unknown): number {
  return Buffer.byteLength(JSON.stringify(v), 'utf8');
}

function human(n: number): string {
  return n < 1024 ? `${n} B` : `${(n / 1024).toFixed(1)} KB`;
}

/** sha256 of the plan minus the marker (its At is the wall clock), so two
 *  runs over the same snapshot can be compared. */
function planDigest(plan: PlanEntry[]): string {
  const body = plan.filter((e) => e.path !== MARKER);
  return crypto.createHash('sha256').update(canon(body)).digest('hex').slice(0, 16);
}

// ── admin REST (token never leaves this section) ───────────────────────────

let tokenOnce: Promise<string> | null = null;

/** One OAuth access token per run, minted on first use. */
function accessToken(): Promise<string> {
  return (tokenOnce ??= mintAccessToken());
}

async function mintAccessToken(): Promise<string> {
  const file = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(file)) {
    throw new Error('No firebase-tools login found — run `npx firebase-tools login` first.');
  }
  const refresh = JSON.parse(fs.readFileSync(file, 'utf8'))?.tokens?.refresh_token;
  if (typeof refresh !== 'string' || refresh.length === 0) {
    throw new Error('The firebase-tools login has no refresh token — run `npx firebase-tools login`.');
  }
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token', refresh_token: refresh,
      client_id: OAUTH_CLIENT_ID, client_secret: OAUTH_CLIENT_SECRET,
    }).toString(),
  });
  const json: any = await res.json().catch(() => null);
  if (!res.ok || typeof json?.access_token !== 'string') {
    throw new Error(`OAuth token exchange failed (HTTP ${res.status}${json?.error ? `, ${json.error}` : ''}).`);
  }
  return json.access_token;
}

interface AdminRest {
  get(p: string, shallow?: boolean): Promise<unknown>;
  put(p: string, value: unknown): Promise<void>;
  del(p: string): Promise<void>;
}

/** [readOnly] (the dry run): every PUT/DELETE throws before any network. */
function adminRest(token: string, opts: { readOnly: boolean }): AdminRest {
  const call = async (method: string, p: string, body?: unknown, shallow = false): Promise<unknown> => {
    // Reads: the test season or the replay's inputs; writes: assertSafePaths.
    assertRequestAllowed(method, p, { readOnly: opts.readOnly, readPaths: READ_PATHS });
    const url = `${DB_URL}/${p.split('/').map(encodeURIComponent).join('/')}.json` +
      `?access_token=${encodeURIComponent(token)}${shallow ? '&shallow=true' : ''}`;
    let res: Response;
    try {
      res = await fetch(url, {
        method,
        ...(body === undefined ? {} : {
          headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
        }),
      });
    } catch (err) {
      // Never surface the URL (it carries the token) — path + reason only.
      throw new Error(`${method} ${p} failed: ${(err as Error)?.message ?? 'network error'}`);
    }
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${p} -> HTTP ${res.status}: ${text.slice(0, 200)}`);
    return text.length > 0 ? JSON.parse(text) : null;
  };
  return {
    get: (p, shallow) => call('GET', p, undefined, shallow),
    put: async (p, value) => { await call('PUT', p, value); },
    del: async (p) => { await call('DELETE', p); },
  };
}

// ── fill (dry run / apply) ─────────────────────────────────────────────────

/** The replay's inputs + the live test season. Live: admin GETs (dry run
 *  and --apply alike — the preview must work under any read rules); the dry
 *  run's client is read-only. No admin token: a dry run falls back to the
 *  public reads (GET-only network guard) and says so; --apply refuses. Any
 *  path that could not be read refuses the run — every input matters (a
 *  skipped Voided or Squads would silently change what gets written). */
async function takeSnapshot(apply: boolean, offline: boolean): Promise<Snapshot> {
  if (offline) return loadSnapshot(true, { file: SNAPSHOT_FILE });
  let token: string | null = null;
  try {
    token = await accessToken();
  } catch (err) {
    if (apply) throw err;
    console.log(`  admin login unavailable (${(err as Error).message}) — ` +
      'dry run falls back to PUBLIC reads');
  }
  let snap: Snapshot;
  if (token !== null) {
    const db = adminRest(token, { readOnly: !apply });
    const values: Record<string, unknown> = {};
    for (const p of [...READ_PATHS, ...LIVE_PATHS]) values[p] = await db.get(p);
    snap = { fetchedAt: new Date().toISOString(), source: `${DB_URL} (admin read)`, values, skipped: [] };
    fs.mkdirSync(OUT_DIR, { recursive: true });
    fs.writeFileSync(path.join(OUT_DIR, SNAPSHOT_FILE), JSON.stringify(snap, null, 1));
    console.log(`  read with the admin login (${apply ? 'apply' : 'read-only dry run'})`);
  } else {
    const restoreNetwork = installNetworkGuard();
    try {
      snap = await loadSnapshot(false, { file: SNAPSHOT_FILE, extraPaths: LIVE_PATHS });
    } finally {
      restoreNetwork();
    }
  }
  if (snap.skipped.length > 0) {
    throw new Error('Refusing: could not read ' +
      `${snap.skipped.map((s) => `${s.path} (HTTP ${s.status})`).join(', ')} — ` +
      'fix the firebase-tools login (`npx firebase-tools login`) so the run can read as admin.');
  }
  return snap;
}

async function fill(apply: boolean, offline: boolean): Promise<void> {
  console.log(`Infinite Fantasy — fill the ${ROOT} test season (${apply ? 'APPLY' : 'DRY RUN'})`);

  // 1. Snapshot.
  const snap = await takeSnapshot(apply, offline);
  console.log(`  snapshot ${snap.fetchedAt} (${offline ? 'offline cache' : snap.source})`);
  if (snap.skipped.length > 0) {
    throw new Error(`Refusing: the cached snapshot could not read ${snap.skipped.map((s) => s.path).join(', ')}.`);
  }
  const live: LiveSeason = {
    config: snap.values[`${ROOT}/Config`] ?? null,
    managers: snap.values[`${ROOT}/Managers`] ?? null,
    squads: snap.values[`${ROOT}/Squads`] ?? null,
  };
  assertEnginePaused(live.config);
  console.log(`  engine paused: lockOverride ${JSON.stringify((live.config as any).lockOverride)}, no auto-return`);

  const liveMarker = snap.values[MARKER] ?? null;
  const liveFakes = Object.keys((live.squads as Record<string, unknown>) ?? {}).filter(isFakeUid);
  if (liveMarker !== null || liveFakes.length > 0) {
    const msg = `the test season is ALREADY FILLED (TestFill ${JSON.stringify(liveMarker)}, ` +
      `${liveFakes.length} fake squads live) — its Players already hold end-of-season prices, ` +
      'so this replay starts from the wrong prices. Run --clear <backupFile> first.';
    if (apply) throw new Error(`Refusing: ${msg}`);
    console.log(`  WARNING: ${msg}`);
  } else {
    console.log('  live TestFill marker: absent (not filled yet)');
  }

  // 2. Replay (network closed for the whole replay).
  const real = realManagersOf(live);
  const result = await runReplay({
    offline, managerCount: MANAGER_COUNT, extraManagers: real.squads, snapshot: snap,
  });
  const skipped = [
    ...result.skippedManagers,
    ...real.withoutSquad.map((uid) => ({ uid, reason: 'Managers row but no saved squad in live Squads — nothing to replay' })),
  ];

  // 3. Plan.
  const plan = buildWritePlan(result.state, live);
  assertSafePaths(plan);

  const fakes = result.managerUids.filter(isFakeUid);
  const realReplayed = result.managerUids.filter((u) => !isFakeUid(u));
  const invFails = Object.entries(result.invariantFailures).filter(([, f]) => f.length > 0);
  console.log(`  managers replayed: ${fakes.length} fake (${fakes[0]}..${fakes[fakes.length - 1]})` +
    ` + ${realReplayed.length} real${realReplayed.length ? ` (${realReplayed.join(', ')})` : ''}`);
  console.log(`  skipped managers: ${skipped.length === 0 ? 'none' : skipped.length}`);
  for (const s of skipped) console.log(`    - ${s.uid}: ${s.reason}`);
  console.log(`  replay checks: invariants ${invFails.length === 0 ? 'ALL PASS' : 'FAIL ' + invFails.map(([k, f]) => `${k}(${f.length})`).join(' ')}` +
    `; crashes ${result.crashes.length}; expected-ledger mismatches ${result.managerLedgerMismatches}` +
    `; stub pushes recorded ${result.pushesRecorded} (none sent)` +
    `; seeded transfer weeks capped by budget ${result.transfersCapped}`);
  for (const [k, f] of invFails) for (const m of f.slice(0, 3)) console.log(`    ! ${k}: ${m}`);
  for (const c of result.crashes.slice(0, 3)) console.log(`    ! crash ${c.at} ${c.job}: ${c.error.split('\n')[0]}`);

  const total = plan.reduce((a, e) => a + bytes(e.value), 0);
  console.log(`  write plan: ${plan.length} PUTs, ${human(total)} total`);
  const width = Math.max(...plan.map((e) => e.path.length));
  for (const e of plan) console.log(`    PUT ${e.path.padEnd(width)}  ${human(bytes(e.value)).padStart(9)}`);
  const written = new Set(plan.map((e) => e.path.slice(ROOT.length + 1).split('/')[0]));
  const missing = EXPECTED_NODES.filter((n) => !written.has(n));
  console.log(`  spec nodes the replay did not produce: ${missing.length ? missing.join(', ') : 'none'}`);
  const extra = [...written].filter((n) => !EXPECTED_NODES.includes(n) && !['TestFill', 'Managers', 'Squads'].includes(n));
  console.log(`  other pipeline nodes written (guards/derived): ${extra.length ? extra.join(', ') : 'none'}`);
  console.log(`  never written: Config, News, Voided, Managers/<real uid>, Squads/<real uid>`);
  const digest = planDigest(plan);
  console.log(`  plan digest (marker excluded): ${digest}`);

  if (!apply) {
    console.log('DRY RUN — nothing was written. Re-run with -- --apply to write.');
    return;
  }

  // 4. Apply.
  if (invFails.length > 0 || result.crashes.length > 0) {
    throw new Error('Refusing to apply: the replay broke an invariant or crashed (see above).');
  }
  const db = adminRest(await accessToken(), { readOnly: false });
  const configNow = await db.get(`${ROOT}/Config`);
  assertEnginePaused(configNow);
  if (canon(configNow) !== canon(live.config)) {
    throw new Error('Refusing: Config changed since the snapshot — re-run the fill.');
  }
  if ((await db.get(MARKER)) !== null) {
    throw new Error('Refusing: TestFill appeared since the snapshot — already filled.');
  }

  const entries: Array<{ path: string; existed: boolean; value: unknown }> = [];
  for (const e of plan) {
    const value = await db.get(e.path);
    entries.push({ path: e.path, existed: value !== null, value });
  }
  const createdAt = new Date().toISOString();
  const backupFile = path.join(OUT_DIR, `fill_backup_${createdAt.replace(/[:.]/g, '-')}.json`);
  const backup = { kind: BACKUP_KIND, root: ROOT, createdAt, planDigest: digest, entries };
  clearPlan(backup); // the backup must be one --clear will accept, before any write
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(backupFile, JSON.stringify(backup, null, 1));
  console.log(`  backup of ${entries.length} target nodes (${entries.filter((e) => e.existed).length} existed): ${backupFile}`);

  for (const e of plan) {
    await db.put(e.path, e.value);
    console.log(`    wrote ${e.path}`);
  }
  console.log(`DONE — ${plan.length} nodes written under ${ROOT}/.`);
  console.log(`Undo: npm run fill:s15 -- --clear "${backupFile}"`);
}

// ── clear ──────────────────────────────────────────────────────────────────

async function clear(file: string): Promise<void> {
  console.log(`Infinite Fantasy — clear the ${ROOT} test-season fill`);
  // The backup is untrusted input: clearPlan validates it and runs every
  // path through assertSafePaths BEFORE any login or network call.
  const ops = clearPlan(JSON.parse(fs.readFileSync(path.resolve(file), 'utf8')));

  const db = adminRest(await accessToken(), { readOnly: false });
  assertEnginePaused(await db.get(`${ROOT}/Config`));

  for (const op of ops) {
    if (op.method === 'PUT') {
      await db.put(op.path, op.value);
      console.log(`    restored ${op.path}`);
    } else {
      await db.del(op.path);
      console.log(`    deleted  ${op.path} (absent before the fill)`);
    }
  }
  for (const node of ['Managers', 'Squads'] as const) {
    const keys = Object.keys((await db.get(`${ROOT}/${node}`, true) as Record<string, unknown>) ?? {});
    for (const op of fakeChildDeletes(node, keys)) {
      await db.del(op.path);
      console.log(`    deleted  ${op.path}`);
    }
  }
  await db.del(MARKER);
  console.log(`    deleted  ${MARKER}`);
  console.log('CLEARED — the test season is back to its pre-fill state.');
}

// ── entry ──────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  if (!fs.existsSync(path.join(process.cwd(), 'tools', 'fill_test_season.ts'))) {
    throw new Error('Run from functions/ (npm run fill:s15).');
  }
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const offline = args.includes('--offline');
  const clearAt = args.indexOf('--clear');
  const known = new Set(['--apply', '--offline', '--clear']);
  const stray = args.filter((a, i) => !known.has(a) && !(clearAt >= 0 && i === clearAt + 1));
  if (stray.length > 0) throw new Error(`Unknown argument(s) ${stray.join(' ')}. ${USAGE}`);
  if (clearAt >= 0) {
    const file = args[clearAt + 1];
    if (apply || offline || !file || file.startsWith('--')) throw new Error(USAGE);
    await clear(file);
    return;
  }
  if (apply && offline) throw new Error('--apply always replays a fresh snapshot — drop --offline.');
  await fill(apply, offline);
}

main().catch((err) => {
  // Every error this tool raises names a path, never a URL (the token).
  console.error((err as Error)?.stack ?? String(err));
  process.exitCode = 1;
});
