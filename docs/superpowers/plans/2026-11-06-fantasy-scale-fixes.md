# Fantasy Scale Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the fantasy server jobs and the fan squad viewer from downloading whole multi-manager nodes when they only need to know whether something exists, a list of keys, or one manager's rows, so cost stays flat as managers and seasons pile up.

**Architecture:** Two new primitives on the server's `FantasyDb` seam: a required `exists(path)` (admin SDK `orderByKey().limitToFirst(1)` — at most one child crosses the wire) for every "is week N scored yet?" check, and an optional `childKeys(path)` (Realtime Database REST `?shallow=true`, full-read fallback) used only to discover seasons. The daily reprice finds the latest scored week from `LockedWeeks`. A finished, settled season stands down by itself; the open-week over-budget pass runs only when prices changed. The fan squad viewer swaps its two whole-node streams for one per-week feed.

**Tech Stack:** TypeScript Cloud Functions (firebase-admin 13, Node 22 global `fetch`), vitest; Flutter/Dart fan app (firebase_database `onValue`), flutter_test.

**Spec:** this document's "Design" section (owner request 2026-11-06: "make that engine fix and run the 1,000-manager test"; owner note: "i dont think we will ever have 1000 fantasy managers" — the fix is justified by cost that grows with *seasons*, not just managers). **Revision 2 (2026-11-06):** Fable's review (`docs/superpowers/plans/2026-11-06-fable-review-scale-and-merge.md`) folded in — M1, M2, S1–S4 and minors; owner: "lets do all the recommendation and fixes".

---

## Design

### What the load test measured (2026-11-06, local replay, nothing written anywhere)

The whole of Season 15 was replayed through the real engine (`tools/rehearse_s15.ts` `runReplay`, offline snapshot) with N made-up managers, and every read made by every 15-minute sweep (11,329 sweeps) was counted by path.

| Managers | Crashes / broken checks | Season data | Per manager |
|---|---|---|---|
| 20 | 0 / 0 | 0.7 MB | 34 KB |
| 250 | 0 / 0 | 6.6 MB | 26 KB |
| 1,000 | 0 / 0 | 26 MB | 26 KB |

(A first 1,000 run showed crashes: the replay tool spaces each fake manager's save 3 simulated minutes apart, so managers past ~#920 saved after the GW1 deadline. Tool artifact, fixed in Task 8.)

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
3. **The daily reprice** (`orchestration.ts:3015`) reads every season's whole `History` six times a day just to find the largest finalized week number (review M2).
4. **Season-end badges** — `settleSeasonBadges(onlyIfUnsettled: true)` (`badges.ts:664`) reads the whole `Badges` node every sweep, forever, once the league season is `Finished`, just to learn the season was already settled.
5. **Open-week over-budget preview** — step 3c (`previewOverBudget`, `orchestration.ts:614`) reads every saved squad every sweep while the week is open, although prices move only at the reprice or an owner edit (review S2).
6. **Fan squad viewer** — tapping a manager on the leaderboard: `FantasyService.watchPublishedPicksFor` / `watchHistoryFor` (`lib/fantasy/data/fantasy_service.dart:711-723`) stream the whole `PublishedPicks` and `History` (every manager, every week) and keep one uid. ~22 KB per manager per season, re-sent on every finalize.

### Decisions

- **D1. Existence by a one-child query (review M1).** `FantasyDb.exists(path): Promise<boolean>` is a **required** member. Production (`rtdbFantasyDb`): `root.child(path).orderByKey().limitToFirst(1).get()` → `snapshot.exists()` — at most one child is downloaded, over the connection the engine already holds. The four implementations — `rtdbFantasyDb` (`functions/src/fantasy_adapter.ts`), `FakeDb` (`functions/src/lib/fantasy/test_support.ts`), the local `FakeDb` in `functions/src/lib/fantasy/orchestration.test.ts`, and `OverlayDb` (`functions/tools/rehearse_s15.ts:342`) — the last three implement it as "read, then non-null" so tests and the replay stay exact.
- **D2. Keys-only reads for season discovery only.** Optional `FantasyDb.childKeys?(path): Promise<string[]>`. Production: `GET <databaseURL>/<encoded path>.json?shallow=true` with an admin OAuth token from `admin.app().options.credential.getAccessToken()` (`Authorization: Bearer` header; token never logged), `AbortSignal.timeout(10_000)`, throws on non-2xx (status only in the message). Under the RTDB emulator (`FIREBASE_DATABASE_EMULATOR_HOST` set): `http://<host>/<path>.json?ns=<namespace>&shallow=true` with `Authorization: Bearer owner`, where `<namespace>` is the subdomain of `databaseURL` (`infinite-sports-app` — review minor; never the project id). Helper `childKeysOf(db, path, log)`: `childKeys` when present, else / on any failure one `warn` (`'fantasy keys: shallow read failed'`) and `childEntries(await db.read(path)).map(([k]) => k)` — worst case is exactly today. Shallow bodies come in both RTDB shapes: object `{k: true}` and list-coerced array (null holes dropped) — `shallowKeysOf`.
  *Why not an index node:* it must be written by every path that creates a season and can drift; a season missing from it would be silently skipped. Keys are derived from the truth.
- **D3. Season discovery** = `childKeysOf('Fantasy')` → for each sport key except `BadgeCatalog`, `childKeysOf('Fantasy/<sport>')` → read each `Fantasy/<sport>/<season>/Config`; a season counts iff that Config is a plain map (exactly `fantasySeasonsOf`'s rule). Order: sport keys, then season keys, in the order the keys come back. The badge catalog seed reads `Fantasy/BadgeCatalog` directly. Used by `runLifecycleSweep` and `runMondayReprice`.
- **D4. Every "is week N scored / snapshotted?" check uses `db.exists`, at the same position in its function** (several are race guards and must stay fresh): `orchestration.ts:1618` (History) and `:1619` (PublishedPicks) in `mayFinalizeFirstRun`, `:2469` (`snapshotPublishedPicks` guard), `:2650` (backstop loop — one `exists` per lock-passed week), `:2765` (lost-settle heal); `schedule_rewind.ts:196` (`upsertGwState` — it only tests `!= null`), `:302`, `:387`, `:512`.
- **D5. Reprice finds the latest scored week without History (review M2).** `runMondayReprice` reads `<root>/LockedWeeks` (a few hundred bytes) and takes the largest `n` whose entry has `Scored === true`. Only when no entry is scored (a season locked before the ledger existed) does it fall back to `childKeysOf(<root>/History)` and take the largest integer key. Everything after that line is unchanged.
- **D6. Season-end badge marker.** `settleSeasonBadges` writes `<root>/SeasonBadgesSettledAt = <ms>` whenever it finds or creates an auto season award. With `onlyIfUnsettled`, it reads that marker first and returns `'alreadySettled'` when present, before reading `Badges`. Absent marker = today's path (which backfills the marker the first time it sees `hasAutoSeasonAward`). Finalize reruns (`onlyIfUnsettled: false`) re-settle exactly as today. Every write that removes season awards (rewind, `--clear`, owner tools — the implementer greps `Badges` deletes and lists them) deletes the marker alongside.
- **D7. A finished, settled season stands down by itself (review S1).** In `sweepSeason`, right after the lockOverride and TestFill stand-downs and before step 0c: when `<sport>/<season>/Finished === true` **and** `<root>/SeasonBadgesSettledAt` exists **and** no `LockedWeeks/<n>` carries a `Finalizing` or `Rewinding` stamp, run only step 2b (news auto-publish) and step 2d (lost-settle heal), log `fantasy sweep: season over — standing down` at info, and return. Step 0b (scheduled messages) already runs before this point. Extract 2b and 2d into named functions so both paths call the same code.
- **D8. Over-budget preview only when prices changed (review S2).** Step 3c runs its full pass (whole `Squads`) only when the open week's price fingerprint differs from the stored one **or** any preview alert is standing in `SquadAlerts`. Fingerprint = sha1 hex of the sorted `name:priceTenths` lines of `Players`. After each full pass write `<root>/SquadAlertsCheck = {Gw, PricesHash}`. A new week (`Gw` differs) always runs.
- **D9. Fan squad viewer: one per-week feed (review S3).** The squad sheet streams `PublishedPicks/<gw>/<uid>` and `History/<gw>/<uid>` per week through `perWeekStream` over **every gameweek number in `widget.gameweeks`** (future weeks answer null; a week that locks while the sheet is open appears live). The History feed parses each week node **once** into both the squad (`squadFromNode`) and the week's points (`HistoryWeek`), replacing the separate `_settledSubs` listeners in `_syncSettledWeeks`. The viewer resubscribes when the set of gameweek numbers changes (`didUpdateWidget`). Session caches keyed `<root>|<uid>`.
- **D10. Out of scope (measured, small at league size; listed in the deferred follow-ups doc):** Manager-app owner screens that stream whole `History`/`TransferCosts`/`Squads`/`TransferState` (one device); fans' whole `Leaderboards` stream; the once-per-week whole reads that need the contents (finalize `:1175`, lock snapshot `:2482`, `liveBaseFor` `:1842`, `publishSaleBaselines` `:514`, `settleSeasonBadges` when it actually settles) — leave them.

## Global Constraints

- Never push; local commits on `zaya-fantasy` only. Nothing deployed until the owner's final review.
- Server: no behavior change beyond D5–D8 — same seasons swept, same weeks finalized, same order, same logs except the new fallback warning and the stand-down info line. Every existing functions test stays green (1657 today).
- The REST token and the firebase-tools login are never printed, logged, or put in an error message or URL.
- Fan app: real-time `onValue` streams only, never `get()`; no piecemeal pop-ins (perWeekStream's all-answered rule); iOS parity (pure Dart change); light and dark unaffected; existing fan tests stay green (2841 today).
- No change to the twinned gameweek engine, the golden fixture, Firebase rules, or the Manager app.

## Review Focus

1. **The shallow season-discovery call fails in production** (token, network, 5xx, timeout): the sweep and reprice behave exactly as today via the fallback, with one warning — never skip a season. Test pins it (Task 1).
2. **List-coerced nodes**: season keys `15`, `16` under `Fantasy/Futsal` can come back as an array — shallow arrays yield the same keys as `childEntries`. Test pins it (Task 1).
3. **A week finalized moments ago in the same sweep**: finalizing week N inside the backstop loop must not re-finalize N or touch an unlocked later week. Test pins it (Task 3).
4. **A finished season that still needs work** (a week stuck `Finalizing`, a `Rewinding` stamp, badges not yet settled, or a lost live hand-over): it must NOT stand down until that is resolved; the live heal still runs. Tests pin it (Task 5).
5. **Fan viewer opened before a week locks, left open across the lock**: the locked week's squad appears without reopening. Test pins it (Task 7).

---

### Task 1: `exists` and `childKeys` primitives

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration_db.ts` (interface + helpers)
- Modify: `functions/src/fantasy_adapter.ts` (`rtdbFantasyDb.exists`, `.childKeys`)
- Modify: `functions/src/lib/fantasy/test_support.ts` (`FakeDb.exists`, `.childKeys`, `reads: string[]`)
- Modify: `functions/src/lib/fantasy/orchestration.test.ts` (its local `FakeDb.exists`)
- Modify: `functions/tools/rehearse_s15.ts` (`OverlayDb.exists`)
- Test: `functions/src/lib/fantasy/child_keys.test.ts`

**Interfaces:**
- Produces: `FantasyDb.exists(path: string): Promise<boolean>` (required); `FantasyDb.childKeys?(path: string): Promise<string[]>`; `export function shallowKeysOf(body: unknown): string[]`; `export async function childKeysOf(db: FantasyDb, path: string, log: FantasyLogger): Promise<string[]>`; `FakeDb.reads: string[]` — every `read`, `exists` and `childKeys` call recorded as `read:<path>` / `exists:<path>` / `keys:<path>`, in order.

- [ ] **Step 1: Failing tests** — `shallowKeysOf({ '15': true, '16': true })` → `['15','16']`; `shallowKeysOf([null, true, true])` → `['1','2']`; `shallowKeysOf(null)` / `shallowKeysOf(true)` → `[]`. `childKeysOf` with a working `childKeys` returns its keys and records no `read:`; with a throwing `childKeys` returns the full-read keys, logs exactly one warn containing `'fantasy keys: shallow read failed'`, and records `read:<path>`; with no `childKeys` member returns the full-read keys with no warning. `FakeDb.exists` → true for a present node, false for absent and for an empty map.
- [ ] **Step 2: Run** `cd functions && npx vitest run src/lib/fantasy/child_keys.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** per D1/D2. `npx tsc --noEmit -p .` and `npx tsc --noEmit -p tools/tsconfig.json` must both compile (all four implementations).
- [ ] **Step 4: Run** the test file and `npx vitest run` — Expected: PASS, full suite green.
- [ ] **Step 5: Emulator probe (local only)** — with the RTDB emulator running (`JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"`, its `bin` on PATH in POSIX form), seed `Fantasy/Futsal/15/History/1/u1` and call `rtdbFantasyDb(admin.database().ref())` `.childKeys('Fantasy/Futsal/15/History')` → `['1']`, `.exists('Fantasy/Futsal/15/History/1')` → true, `.exists('Fantasy/Futsal/15/History/2')` → false, from a throwaway script under `functions/tools/rehearsal_out/`. Record the output in the report.
- [ ] **Step 6: Commit** `feat(fantasy-fn): exists + keys-only reads for the engine`.

### Task 2: Season discovery and the reprice's latest week

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration_db.ts` (`listFantasySeasons`, `latestScoredWeek`)
- Modify: `functions/src/lib/fantasy/orchestration.ts` (`runLifecycleSweep` `:2867-2890`, `runMondayReprice` `:2996-3020`)
- Test: `functions/src/lib/fantasy/list_fantasy_seasons.test.ts`

**Interfaces:**
- Consumes: `childKeysOf` (Task 1).
- Produces: `listFantasySeasons(db: FantasyDb, log: FantasyLogger): Promise<FantasySeasonRef[]>`; `latestScoredWeek(db: FantasyDb, root: string, log: FantasyLogger): Promise<number | null>`.

- [ ] **Step 1: Failing tests** — fixture `{Fantasy: {BadgeCatalog: {...}, Futsal: {'14': {Players: {...}}, '15': {Config: {a: 1}}, '16': {Config: 'junk'}}, Basketball: {}}}`: `listFantasySeasons` deep-equals `fantasySeasonsOf(fixture.Fantasy)`; `db.reads` contains no `read:Fantasy` and contains `read:Fantasy/Futsal/15/Config`. `latestScoredWeek`: `LockedWeeks {1:{Scored:true}, 2:{Scored:true}, 3:{}}` → 2 with no `read:<root>/History`; no scored entry but History keys 1..4 → 4; neither → null. `runLifecycleSweep` and `runMondayReprice` on existing fixtures produce the same writes as before (reuse an existing sweep test's and reprice test's assertions) and their read logs never contain `read:Fantasy` or `read:<root>/History`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** per D3 and D5; update both doc comments (the "Fantasy node it reads anyway" sentence).
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): sweep and reprice stop reading every season's data`.

### Task 3: "Is week N scored?" with `exists`

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration.ts` (lines 1618-1619, 2469, 2650, 2765)
- Modify: `functions/src/lib/fantasy/schedule_rewind.ts` (lines 196, 302, 387, 512)
- Test: extend the backstop's existing test file and `schedule_rewind.test.ts`

**Interfaces:** Consumes `FantasyDb.exists` (Task 1).

- [ ] **Step 1: Failing tests** — a season with weeks 1–5 finalized, swept 3 times: the read log has no `read:` matching `/\/(History|PublishedPicks)\/\d+$/` and does have `exists:` entries for them; finalize count unchanged. Review Focus 3: weeks 1–2 finalized, week 3 lock-passed with all games final and no History → one sweep writes `History/3` exactly once and leaves week 4 (not locked) untouched. Every existing rewind/heal/GwState test passes unchanged.
- [ ] **Step 2: Run** — Expected: FAIL on the read-log assertion.
- [ ] **Step 3: Implement** per D4 — a mechanical swap, each at its original position.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): scored-week checks download one row, not every manager's week`.

### Task 4: Season-end badge marker

**Files:** Modify `functions/src/lib/fantasy/badges.ts` (`settleSeasonBadges`) and each award-removing writer the grep finds; Test: extend `functions/src/lib/fantasy/badges.test.ts`.

**Interfaces:** Produces node `Fantasy/<sport>/<season>/SeasonBadgesSettledAt = number (ms)`.

- [ ] **Step 1: Failing tests** — (a) settled once, then `settleSeasonBadges({onlyIfUnsettled: true})` again: `'alreadySettled'`, no `read:<root>/Badges` or `read:<root>/History`. (b) an auto season award but no marker: first call `'alreadySettled'` and writes the marker; second call reads no `Badges`. (c) `onlyIfUnsettled: false` re-settles and ignores the marker. (d) each award-removing path also deletes the marker.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** per D6; list the award-removing writers in the report.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): settled seasons stop re-reading every badge each sweep`.

### Task 5: Finished seasons stand down by themselves

**Files:** Modify `functions/src/lib/fantasy/orchestration.ts` (`sweepSeason`; extract steps 2b and 2d into `publishDueNewsDrafts` and `healLostLiveSettle`); Test: extend the sweep tests.

**Interfaces:** Consumes the D6 marker (Task 4).

- [ ] **Step 1: Failing tests** — a season with league `Finished: true`, the marker, every week scored, no stamps: one sweep logs `fantasy sweep: season over — standing down`, reads no `Date`, `Squads`, `History` or `Players`, and still publishes a due news draft and heals a stale `Live/Meta` (two sub-cases). Review Focus 4: the same season with (i) no marker, (ii) a `Finalizing` stamp, (iii) a `Rewinding` stamp → the full sweep runs as today.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** per D7 (pure extraction of 2b/2d first, then the early return).
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): a finished, settled season stands down by itself`.

### Task 6: Over-budget preview only when prices changed

**Files:** Modify `functions/src/lib/fantasy/orchestration.ts` (`previewOverBudget` and step 3c); Test: extend the preview tests.

**Interfaces:** Produces `export function pricesFingerprint(playersNode: unknown): string`; node `<root>/SquadAlertsCheck = {Gw: number, PricesHash: string}`.

- [ ] **Step 1: Failing tests** — `pricesFingerprint` is order-independent and changes when any `priceTenths` changes. Three sweeps in an open week with no price change and no standing preview: `read:<root>/Squads` happens once. A price change between sweeps → the next sweep runs the full pass. A standing preview alert → the full pass runs every sweep (so a fixed squad's alert clears). A new `Gw` → full pass.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** per D8 (Node `crypto.createHash('sha1')`).
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(fantasy-fn): over-budget preview re-checks squads only after a price move`.

### Task 7: Fan squad viewer reads one manager's weeks only

**Files:**
- Modify: `lib/fantasy/data/fantasy_service.dart:708-723` (`watchPublishedPicksFor`, `watchHistoryFor` gain `List<int> weeks`; the History feed yields squad + `HistoryWeek`)
- Modify: `lib/fantasy/hub/manager_squad_viewer.dart` (`initState` feeds, `_syncSettledWeeks` removed or reduced, `didUpdateWidget`)
- Test: `test/fantasy/manager_squad_viewer_feeds_test.dart` (new) and the viewer's existing tests

**Interfaces:**
- Consumes: `perWeekStream` (`lib/fantasy/data/per_week_stream.dart`), `squadFromNode` (`fantasy_parsers.dart:122`), the existing `HistoryWeek` parser behind `FantasyService.watchHistoryWeek`.
- Produces: `static Stream<Map<int, FantasySquad>> watchPublishedPicksFor(String sport, String season, String uid, List<int> weeks)`; `static Stream<Map<int, ManagerHistoryWeek>> watchHistoryFor(String sport, String season, String uid, List<int> weeks)` where `class ManagerHistoryWeek { final FantasySquad? squad; final HistoryWeek? week; }` (or the closest existing pairing type); session caches keyed `'$root|$uid'`.

- [ ] **Step 1: Failing tests** — through a `watchWeek` seam: weeks [1,2,3] open exactly `…/PublishedPicks/1/u`, `/2/u`, `/3/u` and never `…/PublishedPicks`; same for History; the History map carries both the squad and the points from one listener per week; a week that answers null first and a squad later (the lock) appears in a later emission (Review Focus 5). Widget test: `gameweeks` growing from 3 to 4 weeks adds one listener per feed and keeps the shown squad (no blank frame). Existing viewer tests (injecting `publishedStates`/`historyStates`/`historyWeekFor`) are updated to the new seams and pass.
- [ ] **Step 2: Run** `/c/src/flutter/bin/flutter test test/fantasy/manager_squad_viewer_feeds_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** per D9. Delete `squadsByWeekForUid` if nothing else uses it (say which in the report).
- [ ] **Step 4: Run** `/c/src/flutter/bin/flutter test` and `/c/src/flutter/bin/flutter analyze lib/fantasy` — Expected: all pass, no new analyzer issues.
- [ ] **Step 5: Commit** `fix(fantasy): manager squad sheet streams that manager's weeks, not everyone's`.

### Task 8: Repeatable load test

**Files:**
- Modify: `functions/tools/rehearse_s15.ts` (client save spacing ~line 1505 → `saveSpacingMs`)
- Modify: `functions/tools/fill_test_season_logic.ts` (`fakeManagerDefs` optional `names` + `uidOf`)
- Create: `functions/tools/load_test.ts`; Modify `functions/tools/tsconfig.json` (include), `functions/package.json` (`"loadtest"` script)
- Test: `functions/tools/fill_test_season_logic.test.ts` (extend)

**Interfaces:**
- Produces: `export function saveSpacingMs(count: number): number` = `Math.min(3 * MIN, Math.floor(24 * HOUR / count))` (pure, exported); `fakeManagerDefs(count, market, formation, templates, opts?: { names?: readonly string[]; uidOf?: (i: number) => string })`; `npm run loadtest -- <N> [--offline]` printing `{managers, crashes, invariantFailures, sweeps, wholeFantasyReads, perSweepMB: {median, p95, max}, topPaths}`, exit code 1 when `crashes > 0 || invariantFailures > 0 || wholeFantasyReads > 0`.

- [ ] **Step 1: Failing tests** — `saveSpacingMs(n) === 3 * 60_000` for every `n` in 1..480 (review S4: the proof the S15 fill timeline is unchanged); `saveSpacingMs(1000) === 86_400`; `fakeManagerDefs` with `uidOf: (i) => 'load-' + String(i + 1).padStart(4, '0')` yields `load-0001`… and `FAKE_UID_PATTERN` is untouched (`isFakeUid('load-0001') === false`).
- [ ] **Step 2: Run** `npx vitest run tools/fill_test_season_logic.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement**; `load_test.ts` wraps `runLifecycleSweep`'s db with a counting proxy (bytes = `JSON.stringify` length, paths with week numbers collapsed to `<n>`; `read:Fantasy` counted as a whole-Fantasy read; `exists` counted as ~1 KB).
- [ ] **Step 4: Run** `npm run loadtest -- 250 --offline` then `-- 1000 --offline` — Expected for both: `wholeFantasyReads: 0`, `crashes: 0`, `invariantFailures: 0`, median per-sweep MB well under the 4.25 MB baseline (record both runs' numbers in the report next to this plan's Design table).
- [ ] **Step 5: Commit** `test(fantasy-fn): repeatable load test (npm run loadtest)`.

### Task 9: Deferred notes + final check

- [ ] **Step 1:** Append the D10 items, with the measured sizes, to `docs/superpowers/plans/2026-11-04-fantasy-deferred-follow-ups.md`.
- [ ] **Step 2:** Full runs: `cd functions && npx vitest run && npx tsc --noEmit`; `/c/src/flutter/bin/flutter test`. Expected: all green.
- [ ] **Step 3:** Commit `docs(fantasy): scale follow-ups deferred`. Do not deploy — deploy waits for the owner's final review.
