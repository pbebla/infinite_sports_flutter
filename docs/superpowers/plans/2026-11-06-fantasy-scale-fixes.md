# Fantasy Scale Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the fantasy server jobs and the fan squad viewer from downloading whole multi-manager nodes when they only need a list of keys or one manager's rows, so cost stays flat as managers and seasons pile up.

**Architecture:** One new optional capability on the server's `FantasyDb` seam: `childKeys(path)`, backed in production by a Realtime Database REST `?shallow=true` read (keys only, no values) and falling back to today's full read on any failure. Season discovery and every "is week N scored yet?" check move onto it. A small marker stops finished seasons from re-reading every badge each sweep. The fan squad viewer swaps its two whole-node streams for the existing one-listener-per-week helper.

**Tech Stack:** TypeScript Cloud Functions (firebase-admin 13, Node 22 global `fetch`), vitest; Flutter/Dart fan app (firebase_database `onValue`), flutter_test.

**Spec:** this document's "Design" section (owner request 2026-11-06: "make that engine fix and run the 1,000-manager test"; owner note: "i dont think we will ever have 1000 fantasy managers" — the fix is justified by cost that grows with *seasons*, not just managers).

---

## Design

### What the load test measured (2026-11-06, local replay, nothing written anywhere)

The whole of Season 15 was replayed through the real engine (`tools/rehearse_s15.ts` `runReplay`, offline snapshot) with N made-up managers, and every read made by every 15-minute sweep (11,329 sweeps) was counted by path.

| Managers | Crashes / broken checks | Season data | Per manager |
|---|---|---|---|
| 20 | 0 / 0 | 0.7 MB | 34 KB |
| 250 | 0 / 0 | 6.6 MB | 26 KB |
| 1,000 | 0 / 0 | 26 MB | 26 KB |

(A first 1,000 run showed crashes: the replay tool spaces each fake manager's save 3 simulated minutes apart, so managers past ~#920 saved after the GW1 deadline. Tool artifact, fixed in Task 6.)

Per-sweep reads at 250 managers: the whole `Fantasy` node (median 3.4 MB, every season ever played) **plus** a median 4.25 MB of other reads, dominated by `History/<gw>` (20 GB over the season) and `History` whole (19 GB; partly a replay artifact — the snapshot's season is already `Finished`, so the season-end badge check re-ran every sweep until awards landed).

### Where the bytes go (code)

1. **Season discovery** — `runLifecycleSweep` (`functions/src/lib/fantasy/orchestration.ts:2871`) and `runMondayReprice` (`:2999`) call `db.read('Fantasy')` and pass it to `fantasySeasonsOf` (`orchestration_db.ts:228`), which only needs `<sport>/<season>/Config`. Every season's History, PublishedPicks, Badges… is downloaded 96 times a day, forever, and old seasons never drop off.
2. **"Is week N scored?" existence checks** that read the whole week node for every manager (`!= null`):
   - sweep step 2 finalize backstop, once per lock-passed week per sweep — `orchestration.ts:2650`;
   - `mayFinalizeFirstRun` — `:1618` (History) and `:1619` (PublishedPicks);
   - lost-settle heal 2d — `:2765`;
   - `snapshotPublishedPicks` guard — `:2469`;
   - `upsertGwState` — `schedule_rewind.ts:196`;
   - rewind/heal guards — `schedule_rewind.ts:302, 387, 512`.
   A finished season left on `auto` keeps running the backstop loop over all its weeks every 15 minutes forever.
3. **Season-end badges** — `settleSeasonBadges(onlyIfUnsettled: true)` (`badges.ts:664`) reads the whole `Badges` node every sweep, forever, once the league season is `Finished`, just to learn the season was already settled.
4. **Fan squad viewer** — tapping a manager on the leaderboard: `FantasyService.watchPublishedPicksFor` / `watchHistoryFor` (`lib/fantasy/data/fantasy_service.dart:711-723`) stream the whole `PublishedPicks` and `History` (every manager, every week) and keep one uid. ~22 KB per manager per season, re-sent on every finalize.

### Decisions

- **D1. Keys-only reads via REST shallow, with a safe fallback.** Add `childKeys?(path): Promise<string[]>` to `FantasyDb` (optional, so the rehearsal's `OverlayDb` and any other implementation keep compiling and simply fall back). Production (`rtdbFantasyDb`) does `GET <databaseURL>/<encoded path>.json?shallow=true` with an admin OAuth token from `admin.app().options.credential.getAccessToken()` (an `Authorization: Bearer` header; token never logged), 10 s timeout. Under the RTDB emulator (`FIREBASE_DATABASE_EMULATOR_HOST` set) it calls `http://<host>/<path>.json?ns=<namespace>&shallow=true` with `Authorization: Bearer owner`. One shared helper `childKeysOf(db, path, log)` returns the keys, and on a missing method or any thrown/non-200 result logs one warning and returns `childEntries(await db.read(path)).map(([k]) => k)` — so the worst case is exactly today's behavior, never a skipped season or week. Shallow results are handled in both RTDB shapes: object `{k: true}` and list-coerced array (null holes dropped), mirroring `childEntries`.
  *Why not an index node:* an index must be written by every path that creates a season or a week and can drift; a season or week missing from it would be silently skipped. Shallow keys are derived from the truth.
- **D2. Season discovery** = `childKeysOf('Fantasy')` → for each sport key except `BadgeCatalog`, `childKeysOf('Fantasy/<sport>')` → read each `Fantasy/<sport>/<season>/Config`; a season counts iff that Config is a plain map (exactly `fantasySeasonsOf`'s rule). Order: sport keys then season keys in the order the keys come back (RTDB key order, same as `childEntries` today). The badge catalog seed reads `Fantasy/BadgeCatalog` directly.
- **D3. Existence checks** use `historyWeeks(db, root, log): Promise<Set<number>>` = integer keys of `childKeysOf(<root>/History)` (and the same for `PublishedPicks` where `mayFinalizeFirstRun` checks it). The step-2 backstop fetches the set once per sweep before its loop. Places that need the week's *contents* keep their full read.
- **D4. Season-end badge marker.** `settleSeasonBadges` writes `<root>/SeasonBadgesSettledAt = <ms>` (plain write) whenever it finds or creates an auto season award. With `onlyIfUnsettled`, it reads that marker first and returns `'alreadySettled'` when present, before reading `Badges`. Absent marker = today's path (which backfills the marker the first time it sees `hasAutoSeasonAward`). The marker is only consulted on the sweep's `onlyIfUnsettled` path; finalize reruns still re-settle exactly as today (badges.ts SEASON END comment). `--clear`/rewind paths that wipe season awards (if any) also delete the marker — the implementer greps `Badges` deletes and lists them in the report.
- **D5. Fan squad viewer** streams `PublishedPicks/<gw>/<uid>` and `History/<gw>/<uid>` per week through `perWeekStream` (`lib/fantasy/data/per_week_stream.dart`) over **every gameweek number in `widget.gameweeks`** (future weeks simply answer null; a week that locks while the sheet is open appears live). The viewer resubscribes when the set of gameweek numbers changes (`didUpdateWidget`). Session caches keyed `<root>|<uid>` like `watchChipHistoryFor`.
- **D6. Out of scope (measured, small at league size, listed in the deferred follow-ups doc):** Manager-app owner screens that stream whole `History`/`TransferCosts`/`Squads`/`TransferState` (one device); sweep step 3c `previewOverBudget` whole `Squads`; per-sweep league `Date` read; fans' whole `Leaderboards` stream.

## Global Constraints

- Never push; local commits on `zaya-fantasy` only. Nothing deployed until the owner's final review.
- Server: no behavior change — same seasons swept, same weeks finalized, same order, same logs except the new fallback warning. Every existing functions test stays green (1657 today).
- The REST token and the firebase-tools login are never printed, logged, or put in an error message or URL.
- Fan app: real-time `onValue` streams only, never `get()`; no piecemeal pop-ins (perWeekStream's all-answered rule); iOS parity (pure Dart change, no platform code); existing fan tests stay green (2841 today).
- No change to the twinned gameweek engine, the golden fixture, Firebase rules, or the Manager app.

## Review Focus

1. **Shallow call fails in production** (token, network, 5xx, timeout): the sweep must behave exactly as today via the fallback, with one warning — never skip a season or week. Test pins it (Task 1).
2. **List-coerced nodes**: `History` with keys 1..12 comes back from RTDB as an array (index = week, holes = null) — shallow result arrays must yield the same weeks as `childEntries`. Test pins it (Task 1).
3. **A week finalized moments ago in the same sweep**: the backstop's key set is fetched once before the loop; finalizing week N inside the loop must not make a later iteration think week N is unscored (it only checks later weeks) and must not re-finalize. Test pins it (Task 3).
4. **Season with a `Config` that is not a map, or a sport key with no seasons, or `BadgeCatalog`**: skipped exactly as `fantasySeasonsOf` skips today. Test pins it (Task 2).
5. **Fan viewer opened before a week locks, left open across the lock**: the locked week's squad appears without reopening. Test pins it (Task 5).

---

### Task 1: `childKeys` capability + `childKeysOf` helper

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration_db.ts` (interface + helper)
- Modify: `functions/src/fantasy_adapter.ts` (`rtdbFantasyDb.childKeys`)
- Modify: `functions/src/lib/fantasy/test_support.ts` (`FakeDb.childKeys`, `FakeDb.reads: string[]` read log)
- Test: `functions/src/lib/fantasy/child_keys.test.ts`

**Interfaces:**
- Produces: `FantasyDb.childKeys?(path: string): Promise<string[]>`; `export async function childKeysOf(db: FantasyDb, path: string, log: FantasyLogger): Promise<string[]>`; `export function shallowKeysOf(body: unknown): string[]` (pure: `{k:true}` → keys; array → indices of non-null entries; anything else → `[]`); `FakeDb.reads: string[]` (every `read` path, in order).

- [ ] **Step 1: Write the failing tests** — `shallowKeysOf({ '15': true, '16': true })` → `['15','16']`; `shallowKeysOf([null, true, true])` → `['1','2']`; `shallowKeysOf(null)` / `shallowKeysOf(true)` → `[]`. `childKeysOf` on a FakeDb with `childKeys` returns its keys and `db.reads` stays empty; on a db whose `childKeys` throws it returns the full-read keys, logs exactly one `warn` containing `'fantasy keys: shallow read failed'`, and `db.reads` equals `[path]`; on a db without `childKeys` it returns the full-read keys with no warning.
- [ ] **Step 2: Run** `cd functions && npx vitest run src/lib/fantasy/child_keys.test.ts` — Expected: FAIL (not defined).
- [ ] **Step 3: Implement** the interface member, `shallowKeysOf`, `childKeysOf`, `FakeDb.childKeys` (keys of `childEntries(await this.read(path))` without logging the read — write a private `peek`) and `FakeDb.reads`. In `rtdbFantasyDb`, `childKeys` builds the URL from `admin.app().options.databaseURL` (or the emulator host + `ns` from `process.env.FIREBASE_CONFIG`/`GCLOUD_PROJECT`), `encodeURIComponent` per path segment, `AbortSignal.timeout(10_000)`, throws on non-2xx (status only in the message), returns `shallowKeysOf(await res.json())`.
- [ ] **Step 4: Run** the test file and `npx vitest run` — Expected: PASS, full suite green.
- [ ] **Step 5: Emulator probe (local only)** — with the RTDB emulator running (`JAVA_HOME` = Android Studio jbr, see project memory), seed `Fantasy/Futsal/15/Config` and `…/History/1`, call `rtdbFantasyDb(admin.database().ref()).childKeys('Fantasy/Futsal/15/History')` from a throwaway script under `tools/rehearsal_out/` → `['1']`. Record the output in the report.
- [ ] **Step 6: Commit** `feat(fantasy-fn): keys-only reads (childKeys) with full-read fallback`.

### Task 2: Season discovery without reading the whole `Fantasy` node

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration_db.ts` (`listFantasySeasons`)
- Modify: `functions/src/lib/fantasy/orchestration.ts:2867-2890` (`runLifecycleSweep`), `:2996-3000` (`runMondayReprice`)
- Test: `functions/src/lib/fantasy/list_fantasy_seasons.test.ts`

**Interfaces:**
- Consumes: `childKeysOf` (Task 1).
- Produces: `export async function listFantasySeasons(db: FantasyDb, log: FantasyLogger): Promise<FantasySeasonRef[]>`; `export const BADGE_CATALOG_KEY = 'BadgeCatalog'` (or reuse the existing constant behind `BADGE_CATALOG_PATH`).

- [ ] **Step 1: Failing tests** — on a fixture `{Fantasy: {BadgeCatalog: {...}, Futsal: {'14': {Players: {...}}, '15': {Config: {a: 1}}, '16': {Config: 'junk'}}, Basketball: {}}}`: `listFantasySeasons` deep-equals `fantasySeasonsOf(fixture.Fantasy)` (one ref, Futsal/15, same `configNode`); `db.reads` never contains `'Fantasy'` and contains `'Fantasy/Futsal/15/Config'`. `runLifecycleSweep` on the existing sweep fixtures produces the same writes as before (reuse an existing sweep test's assertions) and `db.reads` never contains `'Fantasy'`; same for `runMondayReprice`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `listFantasySeasons` per D2; `runLifecycleSweep` reads `Fantasy/BadgeCatalog` for `seedBadgeCatalog` and iterates `listFantasySeasons`; `runMondayReprice` iterates `listFantasySeasons`. Update both doc comments (the "Fantasy node it reads anyway" sentence).
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS, full suite green.
- [ ] **Step 5: Commit** `fix(fantasy-fn): sweep and reprice find seasons by keys, not the whole Fantasy node`.

### Task 3: "Is week N scored?" by keys

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration_db.ts` (`historyWeeks`, `publishedWeeks`)
- Modify: `functions/src/lib/fantasy/orchestration.ts` (lines 1618-1619, 2469, 2648-2650, 2765)
- Modify: `functions/src/lib/fantasy/schedule_rewind.ts` (lines 196, 302, 387, 512)
- Test: extend `functions/src/lib/fantasy/orchestration.test.ts` (or the backstop's existing test file) and `schedule_rewind.test.ts`

**Interfaces:**
- Consumes: `childKeysOf` (Task 1).
- Produces: `export async function historyWeeks(db: FantasyDb, root: string, log: FantasyLogger): Promise<Set<number>>` and `publishedWeeks(...)` (integer keys only).

- [ ] **Step 1: Failing tests** — a season with weeks 1–5 finalized and the sweep run 3 times: `db.reads` contains no path matching `/History\/\d+$/` or `/PublishedPicks\/\d+$/`; finalize count unchanged vs today. Review Focus 3: a season with weeks 1–2 finalized, week 3 lock-passed with all games final and no History: one sweep finalizes week 3 exactly once (one `History/3` write) and week 4 (not yet locked) is untouched. Every existing rewind/heal/GwState test passes unchanged.
- [ ] **Step 2: Run** — Expected: FAIL on the read-log assertion.
- [ ] **Step 3: Implement** per D3: the backstop fetches `historyWeeks` once before its loop; `mayFinalizeFirstRun` takes the sets as parameters (or fetches them itself when called elsewhere); each remaining `read(History/<n>) != null` / `== null` becomes a membership test on a fresh `historyWeeks` call at that point (keep each check at the same position in its function — several are race guards and must stay fresh, not cached across awaits that write). `schedule_rewind.ts:196` keeps reading contents only if it uses them; it only tests `!= null`, so convert it.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): scored-week checks read week numbers, not every manager's week`.

### Task 4: Season-end badge marker

**Files:**
- Modify: `functions/src/lib/fantasy/badges.ts` (`settleSeasonBadges`)
- Test: extend `functions/src/lib/fantasy/badges.test.ts`

**Interfaces:**
- Produces: node `Fantasy/<sport>/<season>/SeasonBadgesSettledAt = number (ms)`.

- [ ] **Step 1: Failing tests** — (a) a finished season settled once, then `settleSeasonBadges(onlyIfUnsettled: true)` called again: returns `'alreadySettled'` and `db.reads` contains neither `<root>/Badges` nor `<root>/History`. (b) a season with an auto season award but no marker (pre-existing data): first call returns `'alreadySettled'` and writes the marker; second call reads no `Badges`. (c) `onlyIfUnsettled: false` (finalize rerun) still re-settles and ignores the marker.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** per D4; grep every write that removes season awards (`Badges` deletes, rewind, `--clear`) and delete the marker alongside each — list them in the report.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): settled seasons stop re-reading every badge each sweep`.

### Task 5: Fan squad viewer reads one manager's weeks only

**Files:**
- Modify: `lib/fantasy/data/fantasy_service.dart:708-723` (`watchPublishedPicksFor`, `watchHistoryFor` gain `List<int> weeks`)
- Modify: `lib/fantasy/hub/manager_squad_viewer.dart:244-262` (pass week numbers; resubscribe in `didUpdateWidget` when the set changes)
- Test: `test/fantasy/manager_squad_viewer_feeds_test.dart` (new) and the viewer's existing tests

**Interfaces:**
- Consumes: `perWeekStream` (`lib/fantasy/data/per_week_stream.dart`), `squadFromNode` (`fantasy_parsers.dart:122`).
- Produces: `static Stream<Map<int, FantasySquad>> watchPublishedPicksFor(String sport, String season, String uid, List<int> weeks)` and the same signature for `watchHistoryFor`; session caches `_publishedPicksForCache`, `_historyForCache` keyed `'$root|$uid'`.

- [ ] **Step 1: Failing tests** — through a `watchWeek` seam (path → stream): for weeks [1,2,3] the service opens exactly the paths `…/PublishedPicks/1/u`, `/2/u`, `/3/u` and never `…/PublishedPicks`; the emitted map holds only non-null weeks; a week that answers null first and a squad later (the lock) appears in a later emission (Review Focus 5). Widget test: changing `gameweeks` from 3 to 4 weeks adds one listener and keeps the shown squad (no blank frame). Existing viewer tests (which inject `publishedStates`/`historyStates`) pass unchanged.
- [ ] **Step 2: Run** `/c/src/flutter/bin/flutter test test/fantasy/manager_squad_viewer_feeds_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** per D5. Keep `squadsByWeekForUid` (still used by its parser tests) or delete it if nothing else uses it — say which in the report.
- [ ] **Step 4: Run** `/c/src/flutter/bin/flutter test` and `/c/src/flutter/bin/flutter analyze lib/fantasy` — Expected: all pass, no new analyzer issues.
- [ ] **Step 5: Commit** `fix(fantasy): manager squad sheet streams that manager's weeks, not everyone's`.

### Task 6: Repeatable load test

**Files:**
- Modify: `functions/tools/rehearse_s15.ts` (client save spacing ~line 1505)
- Create: `functions/tools/load_test.ts`; Modify: `functions/tools/tsconfig.json` (include it), `functions/package.json` (`"loadtest"` script)
- Modify: `functions/tools/fill_test_season_logic.ts` (allow > 20 fake managers for the load test only)

**Interfaces:**
- Consumes: `runReplay`, `loadSnapshot` (rehearse_s15.ts), `fakeManagerDefs`.
- Produces: `npm run loadtest -- <N> [--offline]` printing `{managers, crashes, invariantFailures, sweeps, wholeFantasyReads, perSweepMB: {median, p95, max}, topPaths}`; exit code 1 when `crashes > 0`, `invariantFailures > 0`, or `wholeFantasyReads > 0`.

- [ ] **Step 1:** Spacing: `const t = openAt + 2 * HOUR + 7 * MIN + mi * Math.min(3 * MIN, Math.floor(SPREAD_MS / managers.length))` with `SPREAD_MS = 24 * HOUR`, so N ≤ 480 keeps today's exact 3-minute timeline (the S15 fill output is unchanged — prove it: `npm run fill:s15 -- --offline` dry-run byte sizes identical before/after) and larger N fits before the deadline.
- [ ] **Step 2:** `fakeManagerDefs` gains an optional `names?: readonly string[]` (default `FAKE_TEAM_NAMES`); the load test passes generated names. The `test-NN` uid pattern and every fill safety allowlist stay untouched (the load test never writes).
- [ ] **Step 3:** `load_test.ts` wraps `runLifecycleSweep` reads with a counting `FantasyDb` proxy (bytes = `JSON.stringify` length, keyed by path with week numbers collapsed to `<n>`), runs the replay, prints the summary above.
- [ ] **Step 4: Run** `npm run loadtest -- 250 --offline` (Tasks 1–4 already applied) and record the numbers in the report next to this plan's Design baseline: expected `wholeFantasyReads: 0`, `crashes: 0`, `invariantFailures: 0`, and median per-sweep MB well under the 4.25 MB baseline. Then `npm run loadtest -- 1000 --offline`, same expectations.
- [ ] **Step 5: Commit** `test(fantasy-fn): repeatable load test (npm run loadtest)`.

### Task 7: Deferred notes + final check

- [ ] **Step 1:** Append the D6 items, with the measured sizes, to `docs/superpowers/plans/2026-11-04-fantasy-deferred-follow-ups.md`.
- [ ] **Step 2:** Full runs: `cd functions && npx vitest run && npx tsc --noEmit`; `/c/src/flutter/bin/flutter test`. Expected: all green.
- [ ] **Step 3:** Commit `docs(fantasy): scale follow-ups deferred`. Do not deploy — deploy waits for the owner's final review.
