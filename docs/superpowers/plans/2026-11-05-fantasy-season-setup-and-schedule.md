# Fantasy season setup + schedule changes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **STATUS:** Fable-reviewed 2026-11-05 (`2026-11-05-fable-review-season-setup-and-schedule.md`, approve with fixes). Must-fixes M1–M4 and should-fixes S1–S5 are folded into the tasks below (marked **[M1]** etc.). Executing.

**Goal:** A fantasy season starts from a Manager button with carried-over prices and positions; mid-season roster joiners enter the market by themselves; schedule changes (cancelled, moved, skipped days, per-week deadlines) never scramble fantasy weeks, and a day cancelled after its deadline is rewound as if it never happened.

**Architecture:** Locked weeks are frozen in a new server node `LockedWeeks/<n>`. Every gameweek list (server, fan app, Manager) comes from one pure twinned function: frozen prefix, then the schedule after it minus skipped dates, with per-date deadline overrides and a kickoff-aware automatic deadline. The 15-minute sweep — and only the sweep — rewinds the latest unscored locked week when its day disappears, is skipped, or (before any game started) has its deadline pushed into the future. Season start and joiners share one server module for "price and position of a player entering the market".

**Tech Stack:** Firebase RTDB + Cloud Functions v2 (TypeScript, vitest); Flutter fan app (Dart, flutter_test); Flutter Manager (Riverpod, flutter_test).

**Spec:** `docs/superpowers/specs/2026-11-05-fantasy-season-setup-and-schedule-design.md` (owner-approved 2026-11-05; read it first).

**Repos / branches:** fan repo `C:\Users\zayaa\StudioProjects\infinite_sports_flutter` (functions under `functions/`), Manager `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`. Both on `zaya-fantasy`. Commit locally only, never push. Flutter: `/c/src/flutter/bin/flutter`.

## Global Constraints

- No RTDB `.get()` in either app; client reads are `onValue` streams (a callable result is a one-shot action and is fine). The Manager guard test `test/no_rtdb_get_guard_test.dart` stays green.
- An error is not a fact: a failed or timed-out read never becomes "no weeks", "no games" or "cancelled". On the server a read that throws aborts the step (it never rewinds).
- Server jobs stand down for a TestFill season (`isTestFillSeason`) and for a non-`auto` lockOverride, as every existing fantasy job does.
- New server-only nodes get no `.write` rule. New Manager write paths (`Config/Deadlines/$date`, `Config/SkippedDates/$date`) get rows in `functions/src/rules_contract.test.ts`. Rules edits go into BOTH `database.rules.json` and `database.rules.stage1.json`.
- Twins stay twins: `lib/fantasy/engine/gameweeks.dart` and `league_time.dart` are byte-identical in the fan repo and the Manager; the TS port in `functions/src/lib/fantasy/gameweeks.ts` replays the same fixture JSON.
- Fix the bug class: every `deriveGameweeks(dateKeysOf(...))` call site and every deadline formatted from `cfg.lockHour` + a date is converted; a guard test keeps new ones out (Task 2).
- UI: light and dark mode via `Theme.of(context).colorScheme`; no overflow at 360 px; no pop-ins after the single reveal (new feeds join the existing reveal gates); "1 pt / N pts" via the shared formatter; tappable names never underlined; down/negative = bright down red.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Test files may be CRLF — preserve line endings.
- Deploy all fantasy functions + rules together, only in Task 14, and only with the owner's OK.

## Review Focus

1. **[M2] A stale sweep that read before a rewind writes no snapshot** for the cancelled week; a sweep that re-claims the old date after a rewind is rewound again by the next sweep, and the "called off" push still goes out once — pinned in Tasks 3 and 4.
2. **RTDB returns `LockedWeeks` as a JS Array / Dart List** (keys 1..n are small ints, index 0 null) — all three parsers accept List and Map — pinned in Tasks 1 and 10.
3. **A failed or empty schedule read never rewinds** (throwing read → no writes; whole schedule empty → stand down with a warn) — pinned in Task 4.
4. **[M1] A deadline override pushed into the future after a game of that day started does NOT rewind** (logged), and the Manager refuses the move; an abandoned day whose games were all moved away does rewind and clears `Live` + `LiveBase/n` — pinned in Tasks 4 and 11.
5. **[M4] Live stat writes under `Line Ups` cost zero reads**; team rename and "Create Lineup" re-saves add no duplicate market entries and never change an existing price — pinned in Task 7.

---

### Task 1: Pure schedule engine (TS + fan Dart twin + golden fixture)

**Files:**
- Modify: `functions/src/lib/fantasy/gameweeks.ts`, `functions/src/lib/fantasy/league_time.ts`, `functions/src/lib/fantasy/orchestration_db.ts` (parsers)
- Modify: `lib/fantasy/engine/gameweeks.dart`, `lib/fantasy/engine/league_time.dart`, `lib/fantasy/data/fantasy_parsers.dart` (parsers)
- Create: `test/fantasy/fixtures/golden_schedule.json`, `functions/src/lib/fantasy/golden_schedule.test.ts`
- Test: `test/fantasy/gameweeks_test.dart`, `test/fantasy/fantasy_parsers_test.dart`, `functions/src/lib/fantasy/gameweeks.test.ts`

**Interfaces (produces):**

Dart (`gameweeks.dart` / `league_time.dart`):
```dart
class LockedWeek { const LockedWeek({required this.date, required this.lockUtc, this.scored = false});
  final String date; final DateTime lockUtc; final bool scored; }
class GameweekSchedule { const GameweekSchedule({this.lockedWeeks = const {}, this.skippedDates = const {},
    this.deadlineOverrides = const {}, this.firstKickoffUtc = const {}, this.minutesBeforeKickoff = 60});
  final Map<int, LockedWeek> lockedWeeks; final Set<String> skippedDates;
  final Map<String, DateTime> deadlineOverrides; final Map<String, DateTime> firstKickoffUtc;
  final int minutesBeforeKickoff; }
// Gameweek gains `final bool frozen;` (named, default false).
List<Gameweek> deriveGameweeks(List<String> matchDates, FantasyConfig cfg,
    [GameweekSchedule schedule = const GameweekSchedule()]);
/// [S2] Legacy derived kickoff 'HH:00' for a game with no stored Time: season Start Time + index,
/// read as PM (h = start + index; if h < 12 then h += 12; if h > 23 then h = 23). startHour <= 0 → null.
/// Byte-for-byte the Manager's derivedStoredTime (schedule_playoffs.dart:49-54) semantics.
String? legacyKickoffHHmm(int startHour, int index);
DateTime leagueInstantUtc(String mmddyyyy, int hour, int minute);   // league_time.dart
```
`class ScheduleOverrides { const ScheduleOverrides({this.skippedDates = const {}, this.deadlineOverrides = const {}, this.minutesBeforeKickoff = 60}); final Set<String> skippedDates; final Map<String, DateTime> deadlineOverrides; final int minutesBeforeKickoff; }` with value equality — **lives in `gameweeks.dart`** (engine, so the Manager twin gets it byte-identical).

Dart parsers (`fantasy_parsers.dart`): `Map<int, LockedWeek> lockedWeeksFromNode(Object? node)`; `ScheduleOverrides scheduleOverridesFromConfigNode(Object? configNode)`; `Map<String, DateTime> firstKickoffByDateFromNode(Object? dateNode, {int startHour = 0})`.

TS: same names camelCase — `deriveGameweeks(matchDates, cfg, schedule?: Partial<GameweekSchedule>)` with `lockedWeeks: Record<number, LockedWeek>`, `skippedDates: Set<string>`; `legacyKickoffHHmm(startHour, index)`; `leagueInstantUtc(date, hour, minute)`; in `orchestration_db.ts`: `lockedWeeksOf`, `scheduleOverridesOf`, `firstKickoffByDateOf(dateNode, startHour = 0)`.

**Node shapes:** `LockedWeeks/<n> = {Date: 'MMDDYYYY', LockAtUtc: <ms>, Scored?: true}`; `Config/SkippedDates/<MMDDYYYY> = true` (only literal `true` counts); `Config/Deadlines/<MMDDYYYY> = <epoch ms number>`; `Config/deadlineMinutesBeforeKickoff = int` (default 60; clamp 0..240). A game's kickoff = its `Time` `'HH:mm'` (24 h) in league time when valid; **[S2]** otherwise `legacyKickoffHHmm(startHour, gameIndex)` when `startHour > 0`; otherwise none. A date's first kickoff = the earliest over its games. Game index = List position, or the numeric key of an index-keyed Map.

**Algorithm** (both twins, verbatim semantics):
```
frozen  = lockedWeeks entries 1..L while every key 1..L is present (stop at the first gap; ignore the rest)
weeks 1..L = (number n, date, lockUtc = stored LockAtUtc, frozen = true)
last    = L > 0 ? frozen[L].date : null
future  = distinct matchDates, sorted by calendar date, keep d if !skipped(d) && (last == null || d > last)
for each d (numbered L+1, L+2, …):
  auto = lockInstantUtc(d, cfg.lockHour)
  k = firstKickoffUtc[d]; if k != null && k − minutesBeforeKickoff < auto: auto = k − minutesBeforeKickoff
  lockUtc = deadlineOverrides[d] ?? auto
opensUtc (all weeks) = league midnight after the PREVIOUS week's date (frozen or not); null for week 1
currentGameweek / statusAt: unchanged
```

- [ ] **Step 1: Write `golden_schedule.json`** — `{cases:[{name, dates, lockHour, schedule?, dateNode?, startHour?, expected:[{number,date,lockUtc,opensUtc,frozen}]}]}`, ISO instants. When a case carries `dateNode`, both twins compute `firstKickoffUtc` with `firstKickoffByDate*(dateNode, startHour)` and merge it into the schedule. Dates are Sundays in Oct 2026 (PDT, UTC−7), `lockHour 16`:
  - `plain`: dates 10042026, 10112026, 10182026 → GW1/2/3 locks `2026-10-04T23:00:00Z`, `2026-10-11T23:00:00Z`, `2026-10-18T23:00:00Z`; GW2 opens `2026-10-05T07:00:00Z`; GW1 opensUtc null.
  - `skipped`: plain + skipped 10112026 → 2 weeks: 10042026 (GW1), 10182026 (GW2).
  - `override`: plain + Deadlines 10112026 = `2026-10-11T20:30:00Z` → GW2 lock `2026-10-11T20:30:00Z`.
  - `early kickoff`: plain + firstKickoff 10112026 = `2026-10-11T22:30:00Z`, minutes 60 → GW2 lock `2026-10-11T21:30:00Z`.
  - `late kickoff`: plain + firstKickoff 10112026 = `2026-10-12T01:00:00Z` → GW2 lock `2026-10-11T23:00:00Z` (unchanged).
  - `frozen, day gone`: lockedWeeks {1: 10042026 @ `2026-10-04T23:00:00Z`}, dates 10112026, 10182026 → GW1 10042026 frozen, GW2 10112026, GW3 10182026.
  - `frozen, past day inserted`: lockedWeeks {1: 10042026, 2: 10112026}, dates 10042026, 10072026, 10112026, 10182026 → 3 weeks; 10072026 ignored; GW3 = 10182026.
  - `gap in frozen`: lockedWeeks {2: 10112026} only → identical to `plain`.
  - `override beats kickoff`: early kickoff + Deadlines 10112026 = `2026-10-11T23:30:00Z` → GW2 lock `2026-10-11T23:30:00Z`.
  - **[S2]** `legacy start time`: plain dates as a `dateNode` whose games carry no `Time` (e.g. `[{"team1":"A","team2":"B","status":0}]` per date), `startHour 2` → every lock 1:00 PM PDT: `2026-10-04T20:00:00Z`, `2026-10-11T20:00:00Z`, `2026-10-18T20:00:00Z`.
- [ ] **Step 2: Write failing tests** — `golden_schedule.test.ts` loads the fixture FROM THE REPO like `golden_replay.test.ts`; Dart `gameweeks_test.dart` group `golden_schedule` loads the same file; each case asserts number, date, lockUtc, opensUtc, frozen. Parser tests in both twins: `lockedWeeksFromNode([null, {'Date':'10042026','LockAtUtc':1791154800000}])` (= `2026-10-04T23:00:00Z`) → `{1: LockedWeek(...)}` (List shape) and Map shape `{'1': {...}}` equal; junk skipped; `scheduleOverridesFromConfigNode({'SkippedDates': {'10112026': true, '10182026': 'yes'}})` → skipped `{'10112026'}`; `Deadlines` non-number ignored; minutes 999 → 240; `firstKickoffByDateFromNode` takes the earliest valid `Time`, ignores `'25:00'`/`'7pm'`, falls back per game to `legacyKickoffHHmm(startHour, index)` only when `startHour > 0`, and accepts the List and index-keyed Map game shapes; `legacyKickoffHHmm(5, 0) == '17:00'`, `(2, 1) == '15:00'`, `(11, 2) == '13:00'` (13 is not < 12, so no +12), `(10, 15) == '23:00'` (25 → clamp), `(0, 0) == null`; `lockInstantUtc(d, h) == leagueInstantUtc(d, h, 0)`.
- [ ] **Step 3: Run and verify they fail** — `cd functions && npx vitest run src/lib/fantasy/golden_schedule.test.ts src/lib/fantasy/gameweeks.test.ts` → FAIL; `/c/src/flutter/bin/flutter test test/fantasy/gameweeks_test.dart test/fantasy/fantasy_parsers_test.dart` → FAIL.
- [ ] **Step 4: Implement both twins** (`leagueInstantUtc` reuses `lockInstantUtc`'s DST rule with minute precision).
- [ ] **Step 5: Run full suites** — `cd functions && npm test`; `/c/src/flutter/bin/flutter test` → all green (existing tests constructing `Gameweek(` still compile — `frozen` is optional).
- [ ] **Step 6: Commit** — `feat(fantasy): gameweeks freeze once locked and honour skips, deadline overrides and kickoff times`

### Task 2: Server reads the real schedule everywhere

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration.ts` (call sites ~1532, 1591, 1810, 1926, 2185, 2485; deadline text ~561, 2412, 2501), `functions/src/lib/fantasy/badges.ts:688`, `functions/src/lib/fantasy/messages.ts:92`, `functions/src/lib/fantasy/position_changes.ts:153,186`, `functions/src/lib/fantasy/pushes.ts:101-107`, `functions/src/lib/fantasy/orchestration_db.ts`
- Create: `functions/src/lib/fantasy/schedule_guard.test.ts`

**Interfaces:**
- Consumes: Task 1 parsers + `deriveGameweeks`.
- Produces: `loadSeasonGameweeks(db: FantasyDb, sport: string, season: string, cfg: FantasyConfig, configNode: Record<string, unknown>): Promise<{ gws: Gameweek[]; dateNode: unknown }>` in `orchestration_db.ts` — reads `${sport}/${season}/Date`, `Fantasy/${sport}/${season}/LockedWeeks` and **[S2]** `${sport}/${season}/Start Time` (`toIntLoose`; ≤ 0 → no legacy kickoff); a throw propagates. `formatDeadlineInstant(lockUtcMs: number): string` in `pushes.ts` — league-time `"Sun, Oct 11 · 4:00 PM"` (minutes always shown, e.g. `1:30 PM`); replaces `formatDeadline(date, hour)`, which is deleted.

- [ ] **Step 1: Write failing guard test** `schedule_guard.test.ts`: greps `functions/src/**/*.ts` (non-test) and fails when `deriveGameweeks(` appears outside `gameweeks.ts` and `orchestration_db.ts`, when `formatDeadline(` appears anywhere, or when `cfg.lockHour` appears outside `gameweeks.ts`, `fantasy_config.ts` and `news.ts` (news uses its own publish slot). Plus unit tests: `formatDeadlineInstant(Date.UTC(2026,9,4,23))` → `Sun, Oct 4 · 4:00 PM`; `2026-10-11T20:30:00Z` → `Sun, Oct 11 · 1:30 PM`; Nov 1 2026 (fall-back day) 16:00 PST instant `2026-11-02T00:00:00Z` → `Sun, Nov 1 · 4:00 PM`.
- [ ] **Step 2: Run** `npx vitest run src/lib/fantasy/schedule_guard.test.ts` → FAIL (lists the call sites).
- [ ] **Step 3: Convert every call site** to `loadSeasonGameweeks` and every deadline string to `formatDeadlineInstant(gw.lockUtc.getTime())` (`position_changes.ts` takes its target week's deadline from `GwState.lockAtUtc`). Reminder / preview / send-now bodies keep their templates' `{deadline}` token.
- [ ] **Step 4: Run** `cd functions && npm test` → all green (golden/rehearsal replays unchanged — an empty `LockedWeeks` behaves exactly as today).
- [ ] **Step 5: Commit** — `refactor(fantasy-fn): one schedule loader for every job; deadlines formatted from the real instant`

### Task 3: Server freezes weeks at lock, guards the lock step, stashes money baselines

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration.ts` (sweep step 1 ~2193; the three snapshot functions; first-finalize claim path `marketForGameweek` ~2006; `finalizeGameweek` after the History write; `publishSaleBaselines` ~436), `functions/src/lib/fantasy/squad_integrity.ts` (`sameBaselineNode`, baseline node type)
- Modify: `database.rules.json`, `database.rules.stage1.json`, `functions/src/rules_contract.test.ts`, `functions/tools/fill_test_season_logic.ts` (`'LockedWeeks'` in `EXPECTED_NODES`)
- Test: `functions/src/lib/fantasy/orchestration.test.ts`

**Behaviour:**
- **Freeze:** at lock, `writeIfAbsent(`${root}/LockedWeeks/${gw.number}`, {Date: gw.date, LockAtUtc: gw.lockUtc.getTime()})` is the FIRST lock write, before `snapshotLockedPositions`. If the claim is lost, read the node: a different `Date` aborts the lock step for this sweep (`log.warn`). The first-finalize path claims the same way.
- **[M2] Lock-step guard:** immediately before each snapshot write (`LockedPositions/<n>`, `PriceHistory/<n>`, and the `PublishedPicks/<n>` `writeIfAbsent` inside `snapshotPublishedPicks`), re-read `LockedWeeks/<n>`; if it is absent or its `Date` ≠ the week being locked, write nothing and return (`log.warn('fantasy lock: week no longer frozen — snapshot skipped')`). One small read per snapshot.
- **Finalize:** after History lands, `updateIfPresent(LockedWeeks/<n>, add Scored: true)`; if absent (pre-feature season), write the full node with `Scored: true`.
- **[M3] Baseline stash:** `publishSaleBaselines(..., opts?: { stashPrev?: boolean })`. The lock-time call (from `snapshotPublishedPicks`, ~2111-2116) passes `stashPrev: true`: the proposed node gets `Prev: {ForGw, RealizedTenths, Prices}` copied from the stored node when the stored node is a baseline with `ForGw < forGw` (no stored node → no `Prev`). Finalize-time calls write nodes without `Prev` (dropping any). `sameBaselineNode` compares ForGw/RealizedTenths/Prices and — only for calls without `stashPrev` — also requires the stored node to carry no `Prev`. Every reader of `Baselines` ignores `Prev`.
- **Rules:** `LockedWeeks` — `.read: "auth != null"`, no `.write`. Contract rows: `Config/Deadlines/$date` and `Config/SkippedDates/$date` admin write allowed / fan denied; `LockedWeeks` client write denied.

- [ ] **Step 1: Failing tests** in `orchestration.test.ts`: "the lock writes LockedWeeks/1 before PublishedPicks" (FakeDb write-order log; `LockedWeeks/1 = {Date:'10042026', LockAtUtc:<lock>}`); "a second sweep never rewrites LockedWeeks"; "a lost claim with a different Date aborts the lock step"; **[M2]** "a stale sweep whose LockedWeeks/1 is deleted between its claim and its snapshot writes no PublishedPicks/1" (FakeDb hook deletes the node after the claim); "finalize marks Scored"; "pre-feature season gets the full node at finalize"; "the week list stays frozen when the locked day disappears: lock GW1, remove `Date/10042026` → `loadSeasonGameweeks` still returns GW1 = 10042026 (frozen, old lock) and GW2 = the next date" (assert through `loadSeasonGameweeks`, not a sweep — Task 4's rewind changes what the sweep does next); **[M3]** "the lock stashes the previous baseline as Prev", "no previous baseline → no Prev", "finalize drops Prev", "a concurrent second lock-time publish writes nothing".
- [ ] **Step 2:** `npx vitest run src/lib/fantasy/orchestration.test.ts src/rules_contract.test.ts` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `cd functions && npm test` → green; `npm run rehearse:s15 -- --offline` → ALL PASS.
- [ ] **Step 5: Commit** — `feat(fantasy-fn): freeze each gameweek when it locks; guard the lock step; stash money baselines`

### Task 4: The sweep rewinds a cancelled locked week; Config trigger keeps open deadlines live

**Files:**
- Create: `functions/src/lib/fantasy/schedule_rewind.ts`, `functions/src/lib/fantasy/schedule_rewind.test.ts`, `functions/src/fantasy_schedule.ts`
- Modify: `functions/src/lib/fantasy/orchestration.ts` (`sweepSeason` calls the rewind first; extract step 3 to `upsertGwState`), `functions/src/index.ts` (export `onFantasyConfigWritten`)

**Interfaces (produces):**
- `rewindCancelledWeek(db: FantasyDb, args: {sport: string; season: string; cfg: FantasyConfig; configNode: Record<string, unknown>; nowUtc: Date; log?: FantasyLogger; pusher?: FantasyPusher}): Promise<'none' | 'rewound' | 'standDown'>` — **[M2] called only by `sweepSeason`**, right after its lockOverride and TestFill stand-downs, before `loadSeasonGameweeks` and the lock step.
- `restoreBaselineAfterRewind(stored: unknown, week: number): unknown` — pure: stored has `Prev` → the `Prev` node (`{ForGw, RealizedTenths, Prices}`); else stored `ForGw === week + 1` → `null` (remove); else `undefined` (leave).
- `upsertGwState(db, root, current: Gameweek | null, nowUtc: Date, log, ctx): Promise<void>` — the extracted sweep step 3, unchanged behaviour plus **[S3]**: when the stored GwState has the same `current`, stored and new status are both `'open'`, and the new `lockAtUtc` is later than the stored one or the `date` differs, also write `ReminderSent/<current>` null (the reminder fires again for the new deadline).
- `refreshOpenGwState(db, args: {sport: string; season: string; nowUtc: Date; log?: FantasyLogger}): Promise<void>` — the Config trigger's body: stand down for no Config / TestFill / non-auto lockOverride; `loadSeasonGameweeks`; if the current week's status is `'open'` → `upsertGwState`; otherwise nothing (locked status stays the sweep's job). **Never rewinds.**
- `scheduleConfigChanged(before: unknown, after: unknown): boolean` — true when `Deadlines`, `SkippedDates`, `deadlineMinutesBeforeKickoff` or `lockHour` changed.
- Trigger `onFantasyConfigWritten` on `/Fantasy/{sport}/{season}/Config`, gated by `scheduleConfigChanged`, calls `refreshOpenGwState`. **No date-level schedule trigger.**

**Rewind rule:** L = highest key of the contiguous frozen prefix (none → `'none'`). Requires `History/L` absent and `LockedWeeks/L/Scored` not true. Reasons:
- (a) `Date/<L.date>` holds no games;
- (b) L.date is skipped;
- (c) **[M1]** `Deadlines[L.date] > now` **and every game of that date has `status` 0** — if a game has status ≥ 1, `log.warn('fantasy rewind: deadline moved after kickoff — not reopened')` and return `'none'`.

Whole `Date` node empty → `'standDown'` + warn. Any read that throws propagates.

**Rewind steps** (in order; each idempotent; a crash is retried by the next sweep) — **Ruling T3a (mark first, delete the ledger last):**
- M. Transaction on `LockedWeeks/L`: set `Rewinding: true` only when the node exists, its `Date == L.date` and it is not `Scored` (otherwise return `'none'`). Task 3 already makes every lock-step write refuse a marked node (`freezesWeek`), and makes each snapshot write delete itself if the week turned un-frozen right after it landed. Then re-read `History/L`: present → remove `Rewinding` and return `'none'` (a finalize won the race; the week counts).
- A sweep that finds `LockedWeeks/L` already marked `Rewinding` (a rewind that crashed mid-way) resumes the rewind from step 0 without re-checking the reasons.
- `maybeFinalizeGame` and the sweep's finalize backstop stand down for a week whose `LockedWeeks` node is marked `Rewinding`.
0. Read `PublishedPicks/L` and keep its uids.
1. Delete `PublishedPicks/L`, `LockedPositions/L`, `PriceHistory/L`, `TransferCosts/L`, `ReminderSent/L`.
2. If `Live/Meta.Gw == L` delete `Live`; delete `LiveBase/L`.
3. Delete every `SquadAlerts/<uid>` with `Gw == L` and `Kind == 'invalid'`.
4. For each uid from step 0: `updateIfPresent(TransferState/<uid>, remove ChipPlayed)`.
5. **[M3]** For every uid under `Baselines`: one transaction applying `restoreBaselineAfterRewind(stored, L)` (undefined = abort/leave).
6. Write `LockedWeeks/L` null.
7. Re-derive (`loadSeasonGameweeks`); if a current week exists → `upsertGwState`; **[S3]** else write `GwState` null.
8. Push if a pusher is present and `writeIfAbsent(CalledOff/L/<L.date>, {At})` wins: audience every uid under `Managers`; title `Infinite Fantasy`; body `GW{L} was called off — your team is open again until {formatDeadlineInstant(newL.lockUtc)}.` or `GW{L} was called off.` when no later week exists; data `fantasyPushData(sport, season, L)`.

A sweep that derived before another sweep's rewind may re-claim `LockedWeeks/L` with the old date (Task 3's claim); the next sweep then rewinds again, and the `CalledOff` claim keeps the push single.

**Ruling T3c — heal what a stale write can still leave behind** (a post-claim write can land inside one round trip after a completed rewind):
- The lock step always writes `TransferCosts/<n>` — the cost map, or `null` when nobody owes anything — so a stale node can never survive a re-lock and be charged at finalize.
- Sweep heal step (after the rewind check, while the derived current week L is `open` and not frozen): every `Baselines/<uid>` whose `ForGw === L + 1` gets `restoreBaselineAfterRewind(stored, L)` in a transaction. Otherwise a stale node would block every affected manager's Save for the whole reopened week.
- **Ruling T3d:** the same heal step deletes orphan lock snapshots of the open, unfrozen week L — `PublishedPicks/L`, `LockedPositions/L`, `PriceHistory/L`, `TransferCosts/L` — because no lock snapshot can legitimately exist for a week that hasn't locked (a crash between a snapshot write and its post-check would otherwise let the real lock adopt the cancelled day's picks). And when the sweep's lock step stops on an un-frozen week (Task 3's `'unfrozen'`), the sweep skips its GwState upsert for that run so a stale derivation never re-writes `locked` over a rewind.

- [ ] **Step 1: Failing tests** (`schedule_rewind.test.ts`, FakeDb with cold-first transactions; start state: GW2 locked with snapshots, its games deleted after the deadline, next date one week later):
  - "rewinds the latest unscored week; GW2 reopens with the next date's deadline" (snapshot nodes gone; `LockedWeeks/2` gone; `GwState = {current:2, status:'open', date:<next>, lockAtUtc:<next lock>}`; one push with the exact body);
  - **[M3]** "a manager who sat out GW1 and sold players in GW2's window gets the pre-lock baseline back exactly (from Prev)"; "a manager with no Prev and ForGw 3 loses the node; ForGw 2 is left";
  - "games moved one week later → GW2 is the new date"; "skipping the date by Config rewinds the same way";
  - **[M1]** "an override pushed into the future rewinds when no game started"; "the same override with a game at status 1 → no rewind, warn logged"; "an override still in the past → no rewind";
  - "partial cancel: one Final game left on the date → no rewind";
  - "never rewinds a scored week (History present) or a Scored marker";
  - "never rewinds when the schedule read throws" (FakeDb read rejects → promise rejects, zero writes); "stands down when the whole schedule is empty";
  - **[M2]** "a stale re-claim of the old date is rewound again by the next sweep; exactly one push";
  - **(T3a)** "the mark refuses when History appeared after the reasons check → Rewinding removed, nothing deleted"; "a crashed rewind (node left marked) is resumed by the next sweep"; "a finalize trigger for a marked week stands down";
  - **(T3c)** "a re-lock with no costs writes TransferCosts/<n> null over a stale node"; "a stale ForGw L+1 baseline found while week L is open is restored from Prev (or removed) by the next sweep; a correct ForGw L node is left alone";
  - **(T3d)** "orphan PublishedPicks/LockedPositions/PriceHistory/TransferCosts of the open unfrozen week are deleted by the heal step"; "a sweep whose lock step stopped as unfrozen writes no GwState";
  - "an abandoned live day (games status 1, then all moved away): Live and LiveBase/2 removed";
  - **[S3]** "no later game day → GwState null, push says plain 'GW2 was called off.'"; "upsertGwState clears ReminderSent when the open week's deadline moved later; keeps it when unchanged";
  - `refreshOpenGwState`: "a Deadlines change on the open week updates GwState.lockAtUtc"; "a locked week is left alone"; "TestFill / lockOverride 'open' → nothing";
  - `scheduleConfigChanged`: `Reminder` edit → false; `Deadlines` edit → true.
- [ ] **Step 2:** `npx vitest run src/lib/fantasy/schedule_rewind.test.ts` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `cd functions && npm test` and `npm run rehearse:s15 -- --offline` → green / ALL PASS.
- [ ] **Step 5: Commit** — `feat(fantasy-fn): a game day called off after its deadline is rewound as if it never happened`

### Task 5: Reprice the morning after any game day

**Files:**
- Modify: `functions/src/fantasy_lifecycle.ts:45-47`, `functions/src/lib/fantasy/orchestration.ts` (`runMondayReprice` ~2530)
- Test: `functions/src/lib/fantasy/orchestration.test.ts`

**Behaviour:** schedule `'every day 10:00'`, timeZone `America/Los_Angeles`; keep the exported name `fantasyMondayReprice` (renaming a deployed function deletes and recreates it — a comment says why). `runMondayReprice` still picks the newest History week `gw`, then needs its `Gameweek` (from `loadSeasonGameweeks`, frozen entry). It reprices only if the week's date is before today (league time) AND `now < gw.lockUtc + 24h`. Otherwise: if `now >= lockUtc + 24h` → `writeIfAbsent(Repriced/<gw>, {Skipped:'late', At})` + warn (the owner can still adjust prices by hand per player on the Manager Players page); if the date is today → nothing (tomorrow's run).

- [ ] **Step 1: Failing tests** — "Sunday game, Monday 10:00 → repriced (unchanged behaviour)"; "Wednesday game, Thursday 10:00 → repriced"; "finalized after the reopen → Repriced {Skipped:'late'}, no price change"; "same-day 10:00 → nothing".
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** green.
- [ ] **Step 5: Commit** — `feat(fantasy-fn): prices move the morning after each game day, whatever the weekday`

### Task 6: Season start callables (carry-over prices and positions, season pass pre-filled)

**Files:**
- Create: `functions/src/lib/fantasy/market_entry.ts`, `functions/src/lib/fantasy/market_entry.test.ts`, `functions/src/lib/fantasy/season_start.ts`, `functions/src/lib/fantasy/season_start.test.ts`, `functions/src/fantasy_season.ts`
- Modify: `functions/src/lib/fantasy/pricing.ts` (export `snapPrice` = the existing private `snap`), `functions/src/index.ts`

**Interfaces (produces):**
```ts
// market_entry.ts
export type FantasyPosition = 'GK' | 'DEF' | 'ATT';
export function mapRegistrationPosition(raw: unknown): FantasyPosition;          // port of tool/seed_fantasy_logic.dart:62-81
export function signupPositionField(sport: string): string;                        // 'Futsal'→'FutsalPosition', 'Basketball'→'BasketballPosition', 'Flag Football'→'FlagFootballPosition'
export function positionAveragePrice(players: Record<string, MarketEntry>, position: FantasyPosition,
  cfg: FantasyConfig, excludeName?: string): number;                               // eligible entries of that position; mean → snapPrice; none → cfg.rookiePriceTenths
export interface CarryOver { priceTenths: number; position: FantasyPosition; season: string }
export async function loadCarryOver(db: FantasyDb, sport: string, season: string):
  Promise<(name: string, uid: string | null) => CarryOver | null>;
// For s = season-1 down to 1: if Fantasy/<sport>/<s>/Players exists, read it + <sport>/<s>/Line Ups.
// Match by uid (that season's Line Ups uid→name, or a Players `uid` field), else trimmed-lowercase name. Newest season wins.
export interface RosterPlayer { name: string; team: string; uid: string | null }
export function rosterOf(lineupsNode: unknown): RosterPlayer[];                   // port of parseLineups; 'Guest' (case-insensitive) excluded; UID ''/'0' → null

// season_start.ts
export interface PreviewRow { name: string; team: string; uid: string | null; position: FantasyPosition;
  positionFrom: 'season' | 'signup' | 'default'; priceTenths: number; priceFrom: 'season' | 'average' | 'rookie';
  fromSeason: string | null; photoUrl: string | null }
export type StartProblem = 'noRosters' | 'noSchedule' | 'alreadyStarted' | 'sourceIsTestFill';
export interface AccessDraft { Mode: 'free' | 'pass'; AmountDollars: number | null;
  Methods: { Venmo: boolean; Zelle: boolean; Card: boolean }; RegisteredPlayersFree: boolean }
export interface SeasonPreview { sport: string; season: string; sourceSeason: string | null;
  rows: PreviewRow[]; settings: { lockHour: number; copiedFrom: string | null }; access: AccessDraft;
  problems: StartProblem[] }
export async function buildSeasonPreview(db: FantasyDb, sport: string, season: string): Promise<SeasonPreview>;
export async function startSeason(db: FantasyDb, sport: string, season: string,
  edits: Record<string, { priceTenths?: number; position?: FantasyPosition }>, access: AccessDraft,
  byUid: string, nowMs: number): Promise<{ players: number }>;
```

**Rules pinned:**
- Returning players: price + position from their newest earlier fantasy season (`priceFrom 'season'`, `positionFrom 'season'`).
- New players: position = sign-up `Users/<uid>/Information/<signupPositionField>` (`'signup'`), else ATT (`'default'`); price = `positionAveragePrice` over the RETURNING players' preview rows of that position (`'average'`), else rookie (`'rookie'`). Photo: the same PublicProfiles lookup `tool/seed_fantasy.dart:85-116` uses.
- Config: copy of the newest earlier season's Config minus `lockOverride`, `lockOverrideUntil`, `Access`, `Deadlines`, `SkippedDates`, plus `lockOverride: 'auto'`, plus `Access` from the `access` argument; no earlier season → the TS twin of `FantasyConfig.futsalDefault` `toMap()` + `'auto'`.
- **[S1]** `access` in the preview is pre-filled from the source season's `Config/Access` (`Mode`, `AmountDollars`, `Methods.Venmo/Zelle/Card`, `RegisteredPlayersFree`; `Cash` is never copied — it is Manager-only); no source Access → `{Mode:'free', AmountDollars:null, Methods:{Venmo:true, Zelle:true, Card:true}, RegisteredPlayersFree:false}`. `startSeason` validates it: `Mode 'pass'` needs `AmountDollars` > 0, whole or .50, ≤ 1000, and at least one method → else `invalid-argument` with `details: {problem:'badAccess'}`. The written `Config/Access` node has exactly the keys and shape the Manager's own writer produces (read `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\lib\services\firebase\fantasy_access_service.dart:71-110` and match it, including `ChangedAt`/`ChangedBy`).
- Problems: `noRosters` (no `rosterOf` rows), `noSchedule` (`<sport>/<season>/Date` empty), `alreadyStarted` (Config exists), `sourceIsTestFill` (source season has the TestFill node).
- **`startSeason` order:** recompute the preview → throw `failed-precondition` with the problem codes if any; validate `access`; apply edits (price snapped + clamped; position validated; unknown names ignored and counted in the log); `writeIfAbsent(${root}/StartedAt, {At, By})` → lost → `alreadyStarted`; write `Players` (rows → `{position, priceTenths, eligible:true, teamName, uid?, photoUrl?}`); then write `Config`. On failure after the claim: delete `Players` and `StartedAt`, rethrow.
- Callables `previewFantasySeason` / `startFantasySeason` in `fantasy_season.ts`: admin-gated with the same helper as `fantasy_messages.ts:49-60`; `invalid-argument` for a bad sport/season or bad access; `failed-precondition` carries `details: {problems}`.

- [ ] **Step 1: Failing tests** — "returning player keeps last season's final price and position (owner edit included)"; "a player who sat out S15 comes back at their S14 price"; "uid match beats a renamed roster entry"; "new player: sign-up 'Defender;Striker' → DEF at the DEF average of returning players, snapped (e.g. 63 → 65)"; "no returning players in a position → rookie 60"; "guests excluded"; "Config copied minus Access/overrides, lockOverride auto"; **[S1]** "access pre-filled from source Access (Cash dropped)"; "no source Access → free defaults"; "pass with $0 / $12.30 / $1001 / no method → badAccess"; "Config/Access written in the Manager's shape"; "every problem code"; "edits applied and clamped (price 200 → 150; position 'MID' rejected)"; "second start → alreadyStarted, nothing overwritten"; "failed Players write rolls back StartedAt".
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** green.
- [ ] **Step 5: Commit** — `feat(fantasy-fn): start a fantasy season with last season's prices, positions and season pass`

### Task 7: Mid-season joiners enter the market automatically

**Files:**
- Create: `functions/src/fantasy_roster.ts`, `functions/src/lib/fantasy/roster_sync.ts`, `functions/src/lib/fantasy/roster_sync.test.ts`
- Modify: `functions/src/index.ts` (add `onLineupsWritten` to the three sport groups `fantasyFutsal` / `fantasyBasketball` / `fantasyFlagFootball`)

**Interfaces:**
- Consumes: Task 6 `rosterOf`, `positionAveragePrice`, `loadCarryOver`, `mapRegistrationPosition`, `signupPositionField`.
- Produces: **[M4]** `rosterShapeChanged(before: unknown, after: unknown): boolean` — pure: true only when the set of player keys under the team changed or any player's `UID` changed (team node created or deleted counts as a key-set change). `syncRosterIntoMarket(db: FantasyDb, args: {sport: string; season: string; team: string; teamNode: unknown; log?: FantasyLogger}): Promise<{added: string[]; teamUpdated: string[]}>`. Trigger `onLineupsWritten` on `/${sport}/{season}/Line Ups/{team}` (sport literal per group): **the gate runs first and returns before ANY read** when `rosterShapeChanged` is false; then it runs only when Config exists and the season is not TestFill (it does NOT stand down for lockOverride — joiners are added even while paused).

**Behaviour:** for each `rosterOf({[team]: teamNode})` player: already in the market (by name, or a market entry with the same `uid`) → only set `teamName` if different (`updateIfPresent`, never touch price/position); missing → position = carry-over position, else sign-up, else ATT; price = `positionAveragePrice(current market, position, cfg)` (owner rule: joiners pay the average even when returning); `writeIfAbsent(Players/<name>, {position, priceTenths, eligible:true, teamName: team, uid?, photoUrl?})`. A removed player stays in the market. `teamNode` null → nothing.

- [ ] **Step 1: Failing tests** — **[M4]** `rosterShapeChanged`: Goals increment → false; `number` edit → false; player added → true; player removed → true; UID linked → true; team node created → true. "the trigger handler with an unchanged shape performs zero reads" (FakeDb read counter). "joiner added at the DEF average, eligible, team and uid"; "existing player's price/position never change"; "team rename (old node deleted + new written) → teamName updated, no duplicate"; "Create Lineup re-save of the same names → no writes"; "same uid under a new name → no duplicate, logged"; "TestFill → nothing"; "no Config → nothing"; "concurrent triggers for two teams adding the same name → one entry".
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** green.
- [ ] **Step 5: Commit** — `feat(fantasy-fn): players added to a roster mid-season join the market at their position's average price`

### Task 8: Seed tool can no longer reset a live market

**Files:** Modify `tool/seed_fantasy.dart`, `tool/seed_fantasy_logic.dart`; Test `test/fantasy/seed_logic_test.dart`.

**Behaviour:** `String? seedRefusal({required Object? existingPlayers, required Object? existingConfig, required bool force})` returns a message unless both nodes are absent or `force`; `seed_fantasy.dart` reads both before writing and exits non-zero with that message; flag `--force-reseed`. Header comment points at the Manager's Start flow for real seasons.

- [ ] **Step 1:** failing test for the three cases (absent/absent → null; Players present → message; present + force → null).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** `/c/src/flutter/bin/flutter test test/fantasy/seed_logic_test.dart` → green.
- [ ] **Step 5: Commit** — `fix(fantasy): the seed tool refuses to overwrite a season that already has a market`

### Task 9: Fan app follows frozen weeks, overrides and kickoffs; copy

**Files:**
- Modify: `lib/fantasy/data/fantasy_parsers.dart` (`FantasyConfigState` gains `final ScheduleOverrides schedule;` parsed in `configStateFromNode`), `lib/fantasy/data/fantasy_service.dart:933-941` (`watchGameweeks`), `lib/fantasy/data/fantasy_schedule_feed.dart:157,272-283` (resubscribe predicate), `lib/fantasy/data/fantasy_format.dart:45-55` (offset from `lockUtc`, not `gw.date`), `lib/fantasy/hub/deadline_chip.dart:135`, `lib/fantasy/hub/rules_tab.dart:144-148,221-222,254-256,299-301`, `lib/fantasy/hub/fantasy_walkthrough.dart:62-64`
- Test: `test/fantasy/fantasy_schedule_feed_test.dart`, `test/fantasy/deadline_chip_test.dart`, `test/fantasy/rules_tab_test.dart`, `test/fantasy/fantasy_walkthrough_test.dart`, `test/fantasy/fantasy_parsers_test.dart`

**Interfaces:** Consumes Task 1. Produces `static Stream<List<Gameweek>> watchGameweeks(String sport, String season, FantasyConfig config, ScheduleOverrides overrides)` — combines the `/<sport>/<season>/Date` stream, the `/Fantasy/<sport>/<season>/LockedWeeks` stream and **[S2]** the `/<sport>/<season>/Start Time` stream (int; non-int or ≤ 0 → 0) and emits only after ALL THREE have answered; an error on any is forwarded as an error (the feed's existing error path applies). The feed resubscribes when `lockHour` OR `overrides` change (value equality on `ScheduleOverrides`).

**Copy (exact):**
- Rules → Deadlines: `Each game day is one gameweek. Your team locks at {lockHour} league time (America/Los_Angeles) on game day — or {margin} before that day's first game if it starts earlier — and reopens 24 hours later. The league can move a deadline; the countdown always shows the real one. Late joiners start scoring from their first completed gameweek.` where `{margin}` = `an hour` for 60, else `{n} minutes`.
- Rules → prices: `Every Monday prices move on performance:` → `The morning after each game day, prices move on performance:`
- Rules → selling note: `Prices change on Monday morning.` → `Prices change the morning after each game day.`
- Rules → FAQ: the cancelled-day sentence becomes `If a whole game day is called off, that gameweek is skipped as if it never happened: your team, transfers and chips stay as you set them, no points hit is charged, and teams reopen until the next game day's deadline. If only some games are played, those count that week and the rest count in the week they're played. If games move onto a day that already has games, that gameweek has both rounds — those teams play twice.` (keep the existing voided-week sentences).
- Walkthrough: `Your squad locks at {lockHour} league time on game day and reopens for changes the next day. Make your moves before the whistle.`
- Deadline chip: `GW{n} opens Monday` → `GW{n} opens {weekday}` with `{weekday}` the league-time weekday of `opensUtc` (e.g. `Monday`).

- [ ] **Step 1: Failing tests** — "LockedWeeks entry keeps GW1 frozen after its date leaves the schedule"; "an override moves the countdown"; "a skipped date drops out and later weeks renumber"; "List-shaped LockedWeeks node parses"; "the feed waits for all three streams; no reveal on Date alone"; **[S2]** "games without stored Time use Start Time for the kickoff deadline"; "Config change of Deadlines resubscribes"; "deadline text on Nov 1 2026 (fall-back) shows 4:00 PM for a 16:00 PST lockUtc"; "chip says opens Thursday for a Wednesday game day"; **[M3]** "the sale-baseline parser ignores a `Prev` child" (find the fan app's `Baselines` parser and add the case there); **[S5]** "the market player parser ignores a `uid` key" (`lib/fantasy/data/fantasy_player.dart`); rules + walkthrough exact strings, light/dark at 360 px.
- [ ] **Step 2:** `/c/src/flutter/bin/flutter test test/fantasy/` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** full suite `/c/src/flutter/bin/flutter test` → green; `/c/src/flutter/bin/flutter analyze lib test` → no new issues.
- [ ] **Step 5: Commit** — `feat(fantasy): the app follows frozen weeks, moved deadlines and skipped days`

### Task 10: Manager engine twin + schedule-aware gameweeks provider

**Files (Manager repo):**
- Modify: `lib/fantasy/engine/gameweeks.dart`, `lib/fantasy/engine/league_time.dart` (byte-identical copies of the fan files after Task 1)
- Modify: `lib/fantasy/data/fantasy_admin_models.dart` (twin parsers `lockedWeeksFromNode`, `scheduleOverridesFromConfigNode`, `firstKickoffByDateFromNode` — same code as the fan parsers)
- Modify: `lib/services/firebase/fantasy_admin_service.dart` (`watchLockedWeeks`, `watchSeasonStartHour` stream of `<sport>/<season>/Start Time`), `lib/providers/fantasy_admin_provider.dart:480-487` (new `fantasyLockedWeeksProvider` and `fantasyStartHourProvider`, both `StreamProvider.family<…, FantasySeasonRef>`; `fantasyGameweeksProvider` passes `GameweekSchedule`; emits null until Date, LockedWeeks, Start Time and Config have all answered). Tasks 11–12 consume these providers plus the existing `fantasyDateNodeProvider`.
- Modify (bug class — whole-hour `formatDeadline` → `formatLeagueInstant(lockUtc)` wherever a week's deadline shows): `lib/ui/fantasy/fantasy_gameweeks_page.dart:152`, `lib/ui/fantasy/fantasy_section_page.dart:169,204,218-228`
- Create: `test/fantasy/fixtures/golden_schedule.json` (byte copy of the fan fixture), `test/fantasy/schedule_twin_test.dart`

- [ ] **Step 1: Failing twin test** — replays every `golden_schedule.json` case and asserts the fixture file's SHA-256 equals the fan repo's (hash pinned as a constant; the comment says how to refresh); the Task 1 parser cases incl. the List shape and the legacy Start Time fallback; **[S5]** `playersFromNode` ignores a `uid` key.
- [ ] **Step 2:** `flutter test test/fantasy/schedule_twin_test.dart` → FAIL.
- [ ] **Step 3:** copy the engine files; implement parsers, streams and provider.
- [ ] **Step 4:** full Manager suite + `flutter analyze lib test` → green.
- [ ] **Step 5: Commit** — `feat(fantasy): Manager gameweeks follow frozen weeks, deadline overrides and skipped days`

### Task 11: Manager Gameweeks page — change deadline, back to automatic, skip, bring back

**Files (Manager):** Modify `lib/ui/fantasy/fantasy_gameweeks_page.dart`, `lib/services/firebase/fantasy_admin_service.dart`, `lib/ui/fantasy/news/news_schedule_picker.dart` (optional upper bound). Test `test/fantasy/fantasy_widgets_test.dart`, `test/fantasy/news_templates_test.dart`.

**Interfaces:** `Future<void> setDeadlineOverride(SportType sport, String season, String date, int? epochMs)` (null removes `Config/Deadlines/<date>`); `Future<void> setDateSkipped(SportType sport, String season, String date, bool skipped)` (false removes the key); `showNewsScheduleDialog(..., int? latestMs, String? latestError)` — Schedule disabled past `latestMs`, inline error `latestError`.

**UI (exact copy):**
- Row deadline line: `Locks {formatLeagueInstant(gw.lockUtc)}` + a `changed` chip when the date has an override.
- Actions (none on frozen + scored weeks):
  - `Change deadline` — **[M1]** picker bounded to [max(now, the game day's 00:00 league time), first kickoff of the date] (**Ruling T9a:** never before the game day itself — teams reopen 24 h after the deadline, so a deadline a day or more early would reopen the next week while this week's games are still on) using the Task 10 kickoff parser (stored Time, else legacy Start Time); with no kickoff known, bounded to the game day's 23:59 league time. `latestError` = `Pick a time before the first game starts.` (kickoff bound) or `Pick a time before the end of game day.` (23:59 bound). Title `GW{n} deadline`; footnote `Fans see the new deadline right away. If GW{n} is already locked and no game has started, a later time reopens it.` **[M1]** On a week where any game of its date has `status` ≥ 1 the action is disabled with the text `Games have started — the deadline can't move.`
  - `Back to automatic` (only when overridden).
  - `Skip this week` — confirm title `Skip GW{n} ({date})?`, body `Fantasy treats this game day as cancelled. If its deadline has passed, teams reopen and nothing from it counts. Games played on this day won't score in fantasy.`
- New section `Skipped days`: one row per skipped date with `Bring back`; disabled with the note `A later week has already locked, so this day can't come back.` when the date is at or before the last locked week's date.
- `Repriced: skipped (late)` badge when `Repriced/<gw>/Skipped == 'late'`.

- [ ] **Step 1: Failing widget tests** (fake service like `fantasy_widgets_test.dart:25-71`): each action calls the service with exact args; frozen-scored rows show no actions; **[M1]** "a started week disables Change deadline with the exact text"; "the picker's upper bound is the first kickoff"; bring-back disabled state; picker refuses after `latestMs`; 360 px light/dark no overflow.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** suite + analyze green.
- [ ] **Step 5: Commit** — `feat(fantasy): change a week's deadline or skip a game day from the Gameweeks page`

### Task 12: Manager schedule edits warn about fantasy

**Files (Manager):** Create `lib/fantasy/logic/schedule_warnings.dart`, `test/fantasy/schedule_warnings_test.dart`. Modify `lib/ui/seasons/schedule_manager_page.dart` (`_deleteGame` warnings buffer `:631-649`; a new confirm in `_editGame` after the form returns when `result.dateKey != dateKey`, before `:580`; `_addGame :97-154`), `lib/ui/seasons/manage_league_teams_page.dart:146-161` (team delete), the playoffs replace dialog `schedule_manager_page.dart:930-953`.

**Interfaces:** `String? fantasyScheduleWarning({required List<Gameweek>? gws, required Set<int> scoredWeeks, required String fromDate, required int gamesLeftOnFromDateAfterEdit, required FantasyEditKind kind})` with `enum FantasyEditKind { removeOrMove, addToDate }` — null when `gws` is null (no fantasy) or nothing applies.

**Copy (exact):** scored date → `Fantasy week {n} already counted this game day. Changing its games re-scores week {n}.`; locked unscored date losing its last game → `Fantasy week {n} is locked. Moving or deleting the last game of this day cancels week {n}: teams reopen until the next game day's deadline.`; adding to a date at or before the last frozen week's date that is not itself a week → `Fantasy has already locked a later week, so games on this day won't count in fantasy.` Scored weeks from the existing `fantasyHistoryCountsProvider`; weeks from Task 10's provider for `(sport, '$season')`.

- [ ] **Step 1: Failing tests** — pure function: each message; null cases (no fantasy, open week, games left on the date); widget: delete dialog shows the line; date change shows the new confirm; Cancel aborts the move.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** suite + analyze green.
- [ ] **Step 5: Commit** — `feat(schedule): warn before a schedule edit changes fantasy`

### Task 13: Manager "Start fantasy season"

**Files (Manager):** Create `lib/ui/fantasy/fantasy_start_season_page.dart`, `lib/fantasy/data/fantasy_season_start_models.dart`, `test/fantasy/fantasy_start_season_test.dart`. Modify `lib/services/firebase/fantasy_admin_service.dart` (`previewFantasySeason`, `startFantasySeason`), `lib/providers/fantasy_admin_provider.dart` (`fantasyStartableSeasonProvider(SportType)` = the `Current Season` pointer when that season has no Config, else null), `lib/ui/fantasy/fantasy_season_bar.dart` (start card in the "No fantasy seasons" state and above the bar when a startable season exists), `lib/router/app_router.dart` (`/fantasy/start/:sport/:season`).

**Interfaces:** models parse the Task 6 shapes defensively (`SeasonPreview.fromData(Object?)`, `PreviewRow`, `StartProblem`, `AccessDraft`); `previewFantasySeason` → `SeasonPreview`; `startFantasySeason(sport, season, Map<String, ({int? priceTenths, String? position})> edits, AccessDraft access)` → player count; `failed-precondition` → `FantasyStartRefused(List<StartProblem>)` and `invalid-argument` `badAccess` → `FantasyStartRefused` with a `badAccess` flag (follow the `sendFantasyMessage` translation, `fantasy_admin_service.dart:398-427`).

**UI (exact copy):**
- Card: `Start fantasy for {Sport} Season {N}` / `Prices and positions carry over from last season. You'll see everything before it goes live.` / button `Preview`.
- Page title `Start {Sport} Season {N} fantasy`. Problems block, one line each: `noRosters` → `Build the season's teams first.`; `noSchedule` → `Add the season's game days first — week 1's deadline comes from the schedule.`; `alreadyStarted` → `This season's fantasy has already started.`; `sourceIsTestFill` → `Last season still holds test data. Ask Claude to clear it, then preview again.`
- **[S1]** `Season pass` section, pre-filled from `preview.access`: a Free / Season pass toggle; amount field using the Manager's strict `parseAmountDollars`; Venmo / Zelle / Card switches; `Registered players play free` switch; helper `Pre-filled from Season {M}. Fans see this before they can name a team.` (`{M}` = `sourceSeason`; no source → `Starts free.`). Start is disabled with `Season pass needs a price and at least one payment method.` while invalid.
- Rows grouped GK / DEF / ATT: name, team, price chip (reuse the players page stepper dialog `fantasy_players_page.dart:279-353`), position chip, source line (`S{n} price` / `average {pos} price` / `new-player price`; `S{n} position` / `sign-up position` / `no sign-up position — set to ATT`).
- Settings summary `Settings copied from Season {M}: lock {hour}.`; button `Start fantasy`; confirm `Start {Sport} Season {N} fantasy with {count} players?`; success → snackbar `Fantasy started` + navigate to the season's Fantasy overview. Retry on a failed preview; no stale preview after an error.

- [ ] **Step 1: Failing tests** — model parsing incl. junk; card shows only when startable; problems disable Start; an edit and the access draft reach the service call; invalid pass disables Start with the exact text; refused start shows the problem lines; 360 px light/dark.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** suite + analyze green.
- [ ] **Step 5: Commit** — `feat(fantasy): start a fantasy season from the Manager with carried-over prices`

### Task 14: Deploy, install, owner checks (owner's OK before any outward step)

- [ ] **Step 1:** full suites: functions `npm test`, fan `flutter test`, Manager `flutter test`; offline rehearsal `npm run rehearse:s15 -- --offline` ALL PASS.
- [ ] **Step 2 (owner OK):** deploy all fantasy functions + the new ones (sport groups incl. `onLineupsWritten`, `onFantasyConfigWritten`, `previewFantasySeason`, `startFantasySeason`) + database rules together; verify live rules == stage1 file via REST as before.
- [ ] **Step 3:** rules probe on the LOCAL RTDB emulator only: `LockedWeeks` client write denied; Config `Deadlines`/`SkippedDates` admin allowed, fan denied.
- [ ] **Step 4:** install the Manager on the emulator (and tablet if adb is up); install the fan debug APK on `emulator-5554`.
- [ ] **Step 5: Launch runbook for the owner** (not executed here): (1) owner OK → `npm run fill:s15 -- --clear <latest backup>`; (2) S16 teams and schedule built in the Manager; (3) publish S16 and start fantasy right away (Manager → Fantasy → Start fantasy for Futsal Season 16 → set the season pass in the preview → Start) — the fan app falls back to the newest season with a Config, so the gap between publishing S16 and Start should be short.

## Rulings (plan author + Fable review)

1. ~~Access not copied~~ — **withdrawn (Fable S1):** the Start preview carries the season pass pre-filled from the source season, editable, written with Config. *Cost if wrong:* none beyond one more preview row.
2. Mid-season joiners pay the position average even if they played before (owner's literal rule); position still carries over. *Cost if wrong:* a returning star is cheap for one season.
3. Start requires a schedule (week 1's deadline comes from it). *Cost if wrong:* the owner waits for the schedule before starting.
4. The reprice job keeps its deployed name `fantasyMondayReprice` while running daily. *Cost if wrong:* a misleading name in the console.
5. A game added on a day before the last locked week never counts in fantasy; the Manager warns. *Cost if wrong:* a forgotten past game must be entered on its real date before the next lock.
6. Friendly-only dates stay weeks (unchanged); no two-game weeks — both out of scope per the owner.
7. **(Fable M2)** The rewind runs only in the 15-minute sweep; the Config trigger only refreshes an open week's GwState. *Cost if wrong:* up to 15 minutes before a "called off" reopen.
8. **(Fable M1)** A deadline can't be moved (or a week reopened by a deadline move) once a game of that day has started. *Cost if wrong:* the owner skips the day instead if it really must reopen.
