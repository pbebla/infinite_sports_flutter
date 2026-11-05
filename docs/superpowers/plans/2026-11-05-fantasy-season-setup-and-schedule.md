# Fantasy season setup + schedule changes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **STATUS: Fable-reviewed 2026-11-05 — approved with 4 must-fixes (M1–M4) and 5 should-fixes.** See `2026-11-05-fable-review-season-setup-and-schedule.md`. Fold M1–M4 and S1–S5 into the tasks below before executing; ruling 1 (Access not copied) is withdrawn in favour of S1.

**Goal:** A fantasy season starts from a Manager button with carried-over prices and positions; mid-season roster joiners enter the market by themselves; schedule changes (cancelled, moved, skipped days, per-week deadlines) never scramble fantasy weeks, and a day cancelled after its deadline is rewound as if it never happened.

**Architecture:**
- Locked weeks are frozen in a new server node `LockedWeeks/<n>`. Every gameweek list (server, fan app, Manager) comes from one pure twinned function: the frozen prefix, then the schedule after it, minus skipped dates, with per-date deadline overrides and a kickoff-aware automatic deadline.
- A server reconcile step rewinds the latest unscored locked week when its day disappears, is skipped, or has its deadline pushed into the future.
- Season start and joiners share one server module for "price and position of a player entering the market".

**Tech Stack:**
- Firebase RTDB + Cloud Functions v2 (TypeScript, vitest).
- Flutter fan app (Dart, flutter_test); Flutter Manager (Riverpod, flutter_test).

**Spec:** `docs/superpowers/specs/2026-11-05-fantasy-season-setup-and-schedule-design.md` (owner-approved 2026-11-05; read it first).

**Repos / branches:**
- Fan repo `C:\Users\zayaa\StudioProjects\infinite_sports_flutter` (functions under `functions/`).
- Manager `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`.
- Both on `zaya-fantasy`. Commit locally only, never push.

## Global Constraints

**Data access**
- No RTDB `.get()` in either app. Client reads are `onValue` streams; the Manager guard test `test/no_rtdb_get_guard_test.dart` must stay green. A callable result is a one-shot action and is fine.
- An error is not a fact: a failed or timed-out read never becomes "no weeks", "no games" or "cancelled". On the server, a read that throws aborts the step (it never rewinds).

**Server behaviour**
- Server jobs stand down for a TestFill season (`isTestFillSeason`) and for a non-`auto` lockOverride, as every existing fantasy job does.
- New server-only nodes get no `.write` rule.
- New Manager write paths (`Config/Deadlines/$date`, `Config/SkippedDates/$date`) get rows in `functions/src/rules_contract.test.ts`. Rules edits go into BOTH `database.rules.json` and `database.rules.stage1.json`.

**Twins and parity**
- Twins stay twins: `lib/fantasy/engine/gameweeks.dart` and `league_time.dart` are byte-identical in the fan repo and the Manager. The TS port in `functions/src/lib/fantasy/gameweeks.ts` replays the same fixture JSON.
- Fix the bug class: every `deriveGameweeks(dateKeysOf(...))` call site and every deadline formatted from `cfg.lockHour` + a date is converted. A guard test keeps new ones out (Task 3).

**UI**
- Light and dark mode via `Theme.of(context).colorScheme`. No overflow at 360 px. No pop-ins after the single reveal; new feeds join the existing reveal gates.

**Copy rules**
- Use the shared "1 pt / N pts" formatter.
- Tappable names are never underlined.
- Down/negative indicators use the bright down red.

**Commits and deploys**
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Test files may be CRLF; preserve line endings.
- Deploy all fantasy functions + rules together, and only in Task 14.

## Review Focus

1. **Two reconciles at once** (sweep + trigger, or two triggers) on the same cancelled week must end in the same state: one push, Baselines restored once, no re-lock. Pinned in Task 4.
2. **RTDB returns `LockedWeeks` as a JS Array / Dart List** (keys 1..n are small ints, index 0 null). All three parsers must accept List and Map. Pinned in Tasks 1 and 9.
3. **A failed or empty schedule read never rewinds.** Throwing read → no writes; whole schedule empty → stand down with a warn. Pinned in Task 4.
4. **Owner extends a deadline that passed while games were already live** (status 1): the rewind clears `Live` and `LiveBase/n`, and the fan app leaves the live state. Pinned in Task 4.
5. **Team rename and "Create Lineup" re-saves** fire the Line Ups trigger with whole-team rewrites. They must add no duplicate market entries, never change an existing price, and only update `teamName`. Pinned in Task 7.

---

### Task 1: Pure schedule engine (TS + fan Dart twin + golden fixture)

**Files:**
- Modify: `functions/src/lib/fantasy/gameweeks.ts`, `functions/src/lib/fantasy/league_time.ts`, `functions/src/lib/fantasy/orchestration_db.ts` (parsers)
- Modify: `lib/fantasy/engine/gameweeks.dart`, `lib/fantasy/engine/league_time.dart`, `lib/fantasy/data/fantasy_parsers.dart` (parsers)
- Create: `test/fantasy/fixtures/golden_schedule.json`, `functions/src/lib/fantasy/golden_schedule.test.ts`
- Test: `test/fantasy/gameweeks_test.dart`, `test/fantasy/fantasy_parsers_test.dart`, `functions/src/lib/fantasy/gameweeks.test.ts`

**Interfaces (produces):**

Dart (`gameweeks.dart`, `league_time.dart`):
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
DateTime leagueInstantUtc(String mmddyyyy, int hour, int minute);   // league_time.dart
```
Dart parsers (`fantasy_parsers.dart`):
- `Map<int, LockedWeek> lockedWeeksFromNode(Object? node)`
- `ScheduleOverrides scheduleOverridesFromConfigNode(Object? configNode)`, where `ScheduleOverrides { Set<String> skippedDates; Map<String, DateTime> deadlineOverrides; int minutesBeforeKickoff; }`
- `Map<String, DateTime> firstKickoffByDateFromNode(Object? dateNode)`

TS: the same names in camelCase.
- `deriveGameweeks(matchDates, cfg, schedule?: Partial<GameweekSchedule>)`, with `lockedWeeks: Record<number, LockedWeek>` and `skippedDates: Set<string>`.
- `leagueInstantUtc(date, hour, minute)`.
- In `orchestration_db.ts`: `lockedWeeksOf`, `scheduleOverridesOf`, `firstKickoffByDateOf`.

**Node shapes:**
- `LockedWeeks/<n> = {Date: 'MMDDYYYY', LockAtUtc: <ms>, Scored?: true}`
- `Config/SkippedDates/<MMDDYYYY> = true` (only a literal `true` counts)
- `Config/Deadlines/<MMDDYYYY> = <epoch ms number>`
- `Config/deadlineMinutesBeforeKickoff = int` (default 60; clamp 0..240)
- A game's kickoff is its `Time` `'HH:mm'` (24 h) in league time. Games without a valid `Time` contribute nothing. A date's first kickoff is the earliest valid one.

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

- [ ] **Step 1: Write `golden_schedule.json`.** It has `{cases:[{name, dates, lockHour, schedule, expected:[{number,date,lockUtc,opensUtc,frozen}]}]}` with ISO instants. The dates are Sundays in Oct 2026 (PDT, UTC−7) and every case uses `lockHour 16`:

| case | input | expected |
|---|---|---|
| plain | dates 10042026, 10112026, 10182026 | GW1/2/3 locks `2026-10-04T23:00:00Z`, `…11T23:00Z`, `…18T23:00Z`; GW2 opens `2026-10-05T07:00:00Z`; GW1 opensUtc null |
| skipped | plain + skipped 10112026 | 2 weeks: 10042026 (GW1), 10182026 (GW2) |
| override | plain + Deadlines 10112026 = `2026-10-11T20:30:00Z` | GW2 lock `2026-10-11T20:30:00Z` |
| early kickoff | plain + firstKickoff 10112026 = `2026-10-11T22:30:00Z`, minutes 60 | GW2 lock `2026-10-11T21:30:00Z` |
| late kickoff | plain + firstKickoff 10112026 = `2026-10-12T01:00:00Z` | GW2 lock `2026-10-11T23:00:00Z` (unchanged) |
| frozen, day gone | lockedWeeks {1: 10042026 @ `…04T23:00Z`}, dates 10112026, 10182026 | GW1 10042026 frozen, GW2 10112026, GW3 10182026 |
| frozen, past day inserted | lockedWeeks {1: 10042026, 2: 10112026}, dates 10042026, 10072026, 10112026, 10182026 | 3 weeks; 10072026 ignored; GW3 = 10182026 |
| gap in frozen | lockedWeeks {2: 10112026} | identical to `plain` |
| override beats kickoff | early kickoff + Deadlines 10112026 = `2026-10-11T23:30:00Z` | GW2 lock `2026-10-11T23:30:00Z` |

- [ ] **Step 2: Write failing tests.**
  - `golden_schedule.test.ts` loads the fixture FROM THE REPO, like `golden_replay.test.ts`. The Dart test `gameweeks_test.dart` group `golden_schedule` loads the same file. Each case asserts number, date, lockUtc, opensUtc and frozen.
  - Parser tests in both twins:
    - `lockedWeeksFromNode([null, {'Date':'10042026','LockAtUtc':1791241200000}])` equals `{1: LockedWeek(...)}` (List shape).
    - The Map shape `{'1': {...}}` is equal.
    - Junk entries are skipped.
    - `scheduleOverridesFromConfigNode({'SkippedDates': {'10112026': true, '10182026': 'yes'}})` returns skipped `{'10112026'}`.
    - `Deadlines` with a non-number is ignored.
    - Minutes 999 clamps to 240.
    - `firstKickoffByDateFromNode` takes the earliest valid `Time`, ignores `'25:00'`/`'7pm'`/missing, and accepts both the List and index-keyed Map game shapes.
- [ ] **Step 3: Run and verify they fail.**
  - `cd functions && npx vitest run src/lib/fantasy/golden_schedule.test.ts src/lib/fantasy/gameweeks.test.ts` → FAIL.
  - `/c/src/flutter/bin/flutter test test/fantasy/gameweeks_test.dart test/fantasy/fantasy_parsers_test.dart` → FAIL.
- [ ] **Step 4: Implement both twins.** `leagueInstantUtc` reuses `lockInstantUtc`'s DST rule with minute precision. `lockInstantUtc(date, hour)` must equal `leagueInstantUtc(date, hour, 0)`; add that as a test.
- [ ] **Step 5: Run the full suites.**
  - `cd functions && npm test`
  - `/c/src/flutter/bin/flutter test`
  - Expected: all green. The 20 existing Dart tests constructing `Gameweek(` still compile because `frozen` is optional.
- [ ] **Step 6: Commit.** `feat(fantasy): gameweeks freeze once locked and honour skips, deadline overrides and kickoff times`

### Task 2: Server reads the real schedule everywhere

**Files:**
- Modify:
  - `functions/src/lib/fantasy/orchestration.ts` (call sites ~1532, 1591, 1810, 1926, 2185, 2485; deadline text ~561, 2412, 2501)
  - `functions/src/lib/fantasy/badges.ts:688`
  - `functions/src/lib/fantasy/messages.ts:92`
  - `functions/src/lib/fantasy/position_changes.ts:153,186`
  - `functions/src/lib/fantasy/pushes.ts:101-107`
- Create: `functions/src/lib/fantasy/schedule_guard.test.ts`

**Interfaces:**
- Consumes: Task 1 parsers and `deriveGameweeks`.
- Produces:
  - `loadSeasonGameweeks(db: FantasyDb, sport: string, season: string, cfg: FantasyConfig, configNode: Record<string, unknown>): Promise<{ gws: Gameweek[]; dateNode: unknown }>` in `orchestration_db.ts`. It reads `${sport}/${season}/Date` and `${root}/LockedWeeks`; a throw propagates.
  - `formatDeadlineInstant(lockUtcMs: number): string` in `pushes.ts`: league-time `"Sun, Oct 11 · 4:00 PM"`, with minutes shown when non-zero (`"2:30 PM"`). It replaces `formatDeadline(date, hour)`, which is deleted.

- [ ] **Step 1: Write the failing guard test** `schedule_guard.test.ts`. It greps `functions/src/**/*.ts` (non-test) and fails when:
  - `deriveGameweeks(` appears outside `gameweeks.ts` and `orchestration_db.ts`;
  - `formatDeadline(` appears anywhere;
  - `cfg.lockHour` appears outside `gameweeks.ts`, `fantasy_config.ts` and `news.ts` (news uses its own publish slot).

  Plus unit tests for `formatDeadlineInstant`:
  - `1791241200000` → `Sun, Oct 4 · 4:00 PM`;
  - `2026-10-11T20:30:00Z` → `Sun, Oct 11 · 1:30 PM`;
  - a Nov 1 2026 (fall-back day) 16:00 PST instant → `Sun, Nov 1 · 4:00 PM`.
- [ ] **Step 2: Run** `npx vitest run src/lib/fantasy/schedule_guard.test.ts` → FAIL (lists the call sites).
- [ ] **Step 3: Convert every call site** to `loadSeasonGameweeks` and every deadline string to `formatDeadlineInstant(gw.lockUtc.getTime())`.
  - `position_changes.ts` gets its target week's deadline from `GwState.lockAtUtc`.
  - The reminder, preview and send-now bodies keep their templates' `{deadline}` token.
- [ ] **Step 4: Run** `cd functions && npm test` → all green. The golden/rehearsal replays are unchanged, because an empty `LockedWeeks` behaves exactly as today.
- [ ] **Step 5: Commit.** `refactor(fantasy-fn): one schedule loader for every job; deadlines formatted from the real instant`

### Task 3: Server writes `LockedWeeks` (lock + first finalize + Scored) and the rules

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration.ts` (sweep step 1 ~2193; first-finalize claim path `marketForGameweek` ~2006; `finalizeGameweek` after the History write)
- Modify: `database.rules.json`, `database.rules.stage1.json`, `functions/src/rules_contract.test.ts`, `functions/tools/fill_test_season_logic.ts` (add `'LockedWeeks'` to `EXPECTED_NODES`)
- Test: `functions/src/lib/fantasy/orchestration.test.ts`

**Behaviour:**
- **At lock:** `writeIfAbsent(`${root}/LockedWeeks/${gw.number}`, {Date: gw.date, LockAtUtc: gw.lockUtc.getTime()})` is the FIRST lock write, before `snapshotLockedPositions`. The first-finalize path claims the same.
- **Finalize:** after History lands, `updateIfPresent(LockedWeeks/<n>, add Scored: true)`. If the node is absent (a pre-feature season), write the full node with `Scored: true`.
- **Rules:** `LockedWeeks` gets `.read: "auth != null"` and no `.write` (server only).
- **Contract rows:**
  - `Config/Deadlines/$date` and `Config/SkippedDates/$date`: admin write allowed, fan write denied (already covered by the Config admin rule).
  - `LockedWeeks`: client write denied.

- [ ] **Step 1: Failing tests** in `orchestration.test.ts`:
  - "the lock writes LockedWeeks/1 before PublishedPicks": FakeDb write-order log, `LockedWeeks/1 = {Date:'10042026', LockAtUtc:<lock>}`.
  - "a second sweep never rewrites LockedWeeks".
  - "finalize marks Scored".
  - "a pre-feature season (History exists, no LockedWeeks) gets the full node at finalize".
  - "the week list stays frozen when the locked day disappears": lock GW1, remove `Date/10042026`, run a sweep. Expect GwState stays `{current:1, status:'locked'}` (Task 4 handles the rewind; this task alone must not renumber).
- [ ] **Step 2:** `npx vitest run src/lib/fantasy/orchestration.test.ts src/rules_contract.test.ts` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `cd functions && npm test` → green.
- [ ] **Step 5: Commit.** `feat(fantasy-fn): freeze each gameweek's date and deadline when it locks`

### Task 4: Rewind a cancelled locked week + schedule/Config triggers + "called off" push

**Files:**
- Create: `functions/src/lib/fantasy/schedule_rewind.ts`, `functions/src/lib/fantasy/schedule_rewind.test.ts`, `functions/src/fantasy_schedule.ts`
- Modify:
  - `functions/src/lib/fantasy/orchestration.ts`: `sweepSeason` calls reconcile first; step 3 is extracted to `upsertGwState`; `publishSaleBaselines` gains a rewind option.
  - `functions/src/index.ts`: export the new triggers inside the existing `fantasyFutsal`, `fantasyBasketball` and `fantasyFlagFootball` groups, plus `onFantasyConfigWritten`.

**Interfaces (produces):**
- `reconcileSchedule(db: FantasyDb, args: {sport: string; season: string; nowUtc: Date; log?: FantasyLogger; pusher?: FantasyPusher}): Promise<'none' | 'rewound' | 'standDown'>`
  - It runs the rewind check below, then `upsertGwState` only when the derived current week is `open` (a locked status stays the sweep's job, so the snapshot-before-status ordering at `orchestration.ts:2056-59` holds).
- `upsertGwState(db, root, current: Gameweek | null, nowUtc): Promise<void>`: the extracted sweep step 3, unchanged behaviour.
- `scheduleShapeChanged(before: unknown, after: unknown): boolean`: true when the date node appeared or disappeared, its set of game keys changed, or any game's `Time` changed. Pure; zero reads.
- `scheduleConfigChanged(before: unknown, after: unknown): boolean`: true when `Deadlines`, `SkippedDates`, `deadlineMinutesBeforeKickoff` or `lockHour` changed.
- Triggers:
  - `onScheduleDateWritten` on `/${sport}/{season}/Date/{dateKey}`, per sport literal like the existing game triggers. Gate: `scheduleShapeChanged`.
  - `onFantasyConfigWritten` on `/Fantasy/{sport}/{season}/Config`. Gate: `scheduleConfigChanged`.
  - Both call `reconcileSchedule`.
- `publishSaleBaselines(..., opts?: { rewindTo?: number })`. With `rewindTo: n`, it skips the two never-backwards guards (`orchestration.ts:449` and `:468`) only for nodes whose stored `ForGw === n + 1`.

**Rewind rule:**
- Let L be the highest key in the contiguous frozen prefix.
- Rewind iff all hold: `History/L` absent, `LockedWeeks/L/Scored` not true, and one of:
  - `Date/<L.date>` holds no games;
  - L.date is skipped;
  - `Deadlines[L.date] > now`.
- Stand down (no writes, `log.warn`) when the whole `Date` node is empty.
- Any read that throws propagates.

**Rewind steps** (in order; each idempotent):
0. Read `PublishedPicks/L` and keep its uids; step 4 needs them after the delete.
1. Delete `PublishedPicks/L`, `LockedPositions/L`, `PriceHistory/L`, `TransferCosts/L` and `ReminderSent/L`.
2. If `Live/Meta.Gw == L`, delete `Live`. Delete `LiveBase/L`.
3. Delete every `SquadAlerts/<uid>` whose `Gw == L` and `Kind == 'invalid'`.
4. For every uid that was in the deleted `PublishedPicks/L`: `updateIfPresent(TransferState/<uid>, remove ChipPlayed)`.
5. Baselines:
   - L == 1: write `Baselines` null.
   - Otherwise: call `publishSaleBaselines` exactly as `finalizeGameweek` calls it for week L−1 (`orchestration.ts:~1249`), with `{rewindTo: L}`.
6. Write `LockedWeeks/L` null.
7. Re-derive and call `upsertGwState`. The new week L is open.
8. Push, if a pusher is present and `writeIfAbsent(CalledOff/L/<L.date>, {At})` wins:
   - audience: every uid under `Managers`;
   - title `Infinite Fantasy`;
   - body `GW{L} was called off — your team is open again until {formatDeadlineInstant(newL.lockUtc)}.`, or `GW{L} was called off.` when no later week exists;
   - data `fantasyPushData(sport, season, L)`.

- [ ] **Step 1: Failing tests** (`schedule_rewind.test.ts`, FakeDb with the cold-first transaction behaviour). Start state for every case: GW2 locked with snapshots, all its games deleted after the deadline, next date one week later.
  - "rewinds the latest unscored week; GW2 reopens with the next date's deadline".
    - Snapshot nodes gone; `LockedWeeks/2` gone.
    - `GwState = {current:2, status:'open', date:<next>, lockAtUtc:<next lock>}`.
    - `Baselines/<uid>/ForGw == 2` and equal to what week-1 finalize wrote.
    - One push with the exact body.
  - "games moved one week later → GW2 is the new date".
  - "skipping the date by Config rewinds the same way".
  - "an override pushed into the future rewinds; an override still in the past does not".
  - "partial cancel: one Final game left on the date → no rewind; the week finalizes with that game".
  - "never rewinds a scored week (History present) or a Scored marker".
  - "never rewinds when the schedule read throws" (FakeDb read rejects → promise rejects, zero writes).
  - "stands down when the whole schedule is empty".
  - "two reconciles in parallel → identical end state, exactly one push" (Review Focus 1).
  - "a live week cancelled: Live and LiveBase/2 removed" (Review Focus 4).
  - "TestFill season / lockOverride 'open' → standDown, no writes".
  - `scheduleShapeChanged`:
    - score-only edit → false;
    - game added → true;
    - game removed → true;
    - `Time` changed → true;
    - node deleted → true.
  - `scheduleConfigChanged`:
    - `Reminder` edit → false;
    - `Deadlines` edit → true.
- [ ] **Step 2:** `npx vitest run src/lib/fantasy/schedule_rewind.test.ts` → FAIL.
- [ ] **Step 3: Implement.** The sweep calls `reconcileSchedule` right after its lockOverride and TestFill stand-downs, before `loadSeasonGameweeks`.
- [ ] **Step 4:** `cd functions && npm test` and the offline rehearsal `npm run rehearse:s15 -- --offline` → green / ALL PASS.
- [ ] **Step 5: Commit.** `feat(fantasy-fn): a game day called off after its deadline is rewound as if it never happened`

### Task 5: Reprice the morning after any game day

**Files:**
- Modify: `functions/src/fantasy_lifecycle.ts:45-47`, `functions/src/lib/fantasy/orchestration.ts` (`runMondayReprice` ~2530)
- Test: `functions/src/lib/fantasy/orchestration.test.ts`

**Behaviour:**
- **Schedule:** `'every day 10:00'`, timeZone `America/Los_Angeles`. Keep the exported name `fantasyMondayReprice`: renaming a deployed function deletes and recreates it. A comment says why.
- **Target:** `runMondayReprice` still picks the newest History week `gw`. It then needs that week's `Gameweek`, from `loadSeasonGameweeks` (frozen entry). It reprices only if both hold:
  - the week's date is before today in league time;
  - `now < gw.lockUtc + 24h`.
- **Otherwise:**
  - If `now >= lockUtc + 24h`: `writeIfAbsent(Repriced/<gw>, {Skipped:'late', At})` plus a warn.
  - If the date is today: do nothing (tomorrow's run handles it).

- [ ] **Step 1: Failing tests.**
  - "Sunday game, Monday 10:00 → repriced (unchanged behaviour)".
  - "Wednesday game, Thursday 10:00 → repriced".
  - "finalized after the reopen → Repriced {Skipped:'late'}, no price change".
  - "same-day 10:00 → nothing".
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** green.
- [ ] **Step 5: Commit.** `feat(fantasy-fn): prices move the morning after each game day, whatever the weekday`

### Task 6: Season start callables (carry-over prices and positions)

**Files:**
- Create: `functions/src/lib/fantasy/market_entry.ts`, `functions/src/lib/fantasy/market_entry.test.ts`, `functions/src/lib/fantasy/season_start.ts`, `functions/src/lib/fantasy/season_start.test.ts`, `functions/src/fantasy_season.ts`
- Modify: `functions/src/lib/fantasy/pricing.ts` (export `snapPrice`, the existing private `snap`), `functions/src/index.ts`

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
// For s = season-1 down to 1: if Fantasy/<sport>/<s>/Players exists, read it plus <sport>/<s>/Line Ups.
// Match by uid (that season's Line Ups uid→name, or a Players `uid` field), else by trimmed lowercase name. Newest season wins.
export interface RosterPlayer { name: string; team: string; uid: string | null }
export function rosterOf(lineupsNode: unknown): RosterPlayer[];                   // port of parseLineups; 'Guest' (case-insensitive) excluded; UID ''/'0' → null
```

```ts
// season_start.ts
export interface PreviewRow { name: string; team: string; uid: string | null; position: FantasyPosition;
  positionFrom: 'season' | 'signup' | 'default'; priceTenths: number; priceFrom: 'season' | 'average' | 'rookie';
  fromSeason: string | null; photoUrl: string | null }
export type StartProblem = 'noRosters' | 'noSchedule' | 'alreadyStarted' | 'sourceIsTestFill';
export interface SeasonPreview { sport: string; season: string; sourceSeason: string | null;
  rows: PreviewRow[]; settings: { lockHour: number; copiedFrom: string | null }; problems: StartProblem[] }
export async function buildSeasonPreview(db: FantasyDb, sport: string, season: string): Promise<SeasonPreview>;
export async function startSeason(db: FantasyDb, sport: string, season: string,
  edits: Record<string, { priceTenths?: number; position?: FantasyPosition }>, byUid: string, nowMs: number):
  Promise<{ players: number }>;
```

**Rules pinned:**
- **Returning players** take the price and position from their newest earlier fantasy season (`priceFrom 'season'`, `positionFrom 'season'`).
- **New players:**
  - position = sign-up `Users/<uid>/Information/<signupPositionField>` (`positionFrom 'signup'`), else ATT (`'default'`);
  - price = `positionAveragePrice` over the RETURNING players' preview rows of that position (`'average'`), else rookie (`'rookie'`).
- **Photo:** the same PublicProfiles lookup `tool/seed_fantasy.dart:85-116` uses.
- **Config:**
  - copied from the newest earlier season that has a Config, minus `lockOverride`, `lockOverrideUntil`, `Access`, `Deadlines` and `SkippedDates`, plus `lockOverride: 'auto'`;
  - with no earlier season: `FantasyConfig.futsalDefault` `toMap()` (TS twin of the defaults) plus `'auto'`.
- **Problems:**
  - `noRosters`: no `rosterOf` rows.
  - `noSchedule`: `<sport>/<season>/Date` empty.
  - `alreadyStarted`: Config exists.
  - `sourceIsTestFill`: the source season has the TestFill node.
- **`startSeason` order:**
  1. Recompute the preview and throw `failed-precondition` with the problem codes if any exist.
  2. Apply edits: price snapped and clamped, position validated, unknown names ignored and counted in the log.
  3. `writeIfAbsent(${root}/StartedAt, {At, By})`. If it loses, throw `alreadyStarted`.
  4. Write `Players` = rows → `{position, priceTenths, eligible:true, teamName, uid?, photoUrl?}`.
  5. Write `Config`.
  6. On failure after step 3: delete `Players` and `StartedAt`, then rethrow.
- **Callables** `previewFantasySeason` and `startFantasySeason` in `fantasy_season.ts`:
  - admin-gated with the same helper as `fantasy_messages.ts:49-60`;
  - `invalid-argument` for a bad sport or season;
  - `failed-precondition` carries `details: {problems}`.

- [ ] **Step 1: Failing tests.**
  - "a returning player keeps last season's final price and position (owner edit included)".
  - "a player who sat out S15 comes back at their S14 price".
  - "uid match beats a renamed roster entry".
  - "a new player: sign-up 'Defender;Striker' → DEF at the DEF average of returning players, snapped (e.g. 63 → 65)".
  - "no returning players in a position → rookie 60".
  - "guests excluded".
  - "Config copied minus Access/overrides, lockOverride auto".
  - "every problem code".
  - "edits applied and clamped (price 200 → 150; position 'MID' rejected)".
  - "second start → alreadyStarted, nothing overwritten".
  - "a failed Players write rolls back StartedAt".
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** green.
- [ ] **Step 5: Commit.** `feat(fantasy-fn): start a fantasy season with last season's prices and positions`

### Task 7: Mid-season joiners enter the market automatically

**Files:**
- Create: `functions/src/fantasy_roster.ts`, `functions/src/lib/fantasy/roster_sync.ts`, `functions/src/lib/fantasy/roster_sync.test.ts`
- Modify: `functions/src/index.ts` (add `onLineupsWritten` to the three sport groups)

**Interfaces:**
- Consumes: Task 6 `rosterOf`, `positionAveragePrice`, `loadCarryOver`, `mapRegistrationPosition`, `signupPositionField`.
- Produces: `syncRosterIntoMarket(db: FantasyDb, args: {sport: string; season: string; team: string; teamNode: unknown; log?: FantasyLogger}): Promise<{added: string[]; teamUpdated: string[]}>`.
- Trigger: `onLineupsWritten` on `/${sport}/{season}/Line Ups/{team}`. It runs only when Config exists and the season is not TestFill (it does NOT stand down for a lockOverride: joiners are added even while paused).

**Behaviour:** for each `rosterOf({[team]: teamNode})` player:
- **Already in the market** (by name, or by a market entry with the same `uid`): only set `teamName` when it differs. Use `updateIfPresent`, and never touch price or position.
- **Missing:**
  - position = carry-over position, else sign-up, else ATT;
  - price = `positionAveragePrice(current market, position, cfg)` (owner rule: joiners pay the average even when returning);
  - `writeIfAbsent(Players/<name>, {position, priceTenths, eligible:true, teamName: team, uid?, photoUrl?})`.
- A removed player stays in the market.
- A deleted team node (`teamNode` null) does nothing.

- [ ] **Step 1: Failing tests.**
  - "a joiner is added at the DEF average, eligible, with team and uid".
  - "an existing player's price/position never change".
  - "team rename: the old node deleted + new node written → teamName updated, no duplicate" (Review Focus 5).
  - "Create Lineup re-save of the same names → no writes".
  - "same uid under a new name → no duplicate, logged".
  - "TestFill → nothing".
  - "no Config → nothing".
  - "concurrent triggers for two teams adding the same name → one entry" (`writeIfAbsent`).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** green.
- [ ] **Step 5: Commit.** `feat(fantasy-fn): players added to a roster mid-season join the market at their position's average price`

### Task 8: Seed tool can no longer reset a live market

**Files:**
- Modify: `tool/seed_fantasy.dart`, `tool/seed_fantasy_logic.dart`
- Test: `test/fantasy/seed_logic_test.dart`

**Behaviour:**
- `String? seedRefusal({required Object? existingPlayers, required Object? existingConfig, required bool force})` returns a message unless both nodes are absent or `force`.
- `seed_fantasy.dart` reads both before writing and exits non-zero with that message; the flag is `--force-reseed`.
- The header comment points at the Manager's Start flow for real seasons.

- [ ] **Step 1: Failing test** for the three cases (absent/absent → null; Players present → message; present + force → null).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `/c/src/flutter/bin/flutter test test/fantasy/seed_logic_test.dart` → green.
- [ ] **Step 5: Commit.** `fix(fantasy): the seed tool refuses to overwrite a season that already has a market`

### Task 9: Fan app follows the frozen weeks, overrides and kickoffs; copy

**Files:**
- Modify:
  - `lib/fantasy/data/fantasy_parsers.dart`: `FantasyConfigState` gains `final ScheduleOverrides schedule;`, parsed in `configStateFromNode`.
  - `lib/fantasy/data/fantasy_service.dart:933-941` (`watchGameweeks`)
  - `lib/fantasy/data/fantasy_schedule_feed.dart:157,272-283` (resubscribe predicate)
  - `lib/fantasy/data/fantasy_format.dart:45-55` (offset from `lockUtc`, not `gw.date`)
  - `lib/fantasy/hub/deadline_chip.dart:135`
  - `lib/fantasy/hub/rules_tab.dart:144-148,221-222,254-256,299-301`
  - `lib/fantasy/hub/fantasy_walkthrough.dart:62-64`
- Test: `test/fantasy/fantasy_schedule_feed_test.dart`, `test/fantasy/deadline_chip_test.dart`, `test/fantasy/rules_tab_test.dart`, `test/fantasy/fantasy_walkthrough_test.dart`, `test/fantasy/fantasy_parsers_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces: `static Stream<List<Gameweek>> watchGameweeks(String sport, String season, FantasyConfig config, ScheduleOverrides overrides)`. It combines the `/<sport>/<season>/Date` stream and the `/Fantasy/<sport>/<season>/LockedWeeks` stream and emits only after BOTH have answered. An error on either is forwarded as an error; the feed's existing error path applies.
- The feed resubscribes when `lockHour` OR `overrides` change (value equality on `ScheduleOverrides`).

**Copy (exact):**
- **Rules → Deadlines:** `Each game day is one gameweek. Your team locks at {lockHour} league time (America/Los_Angeles) on game day — or {margin} before that day's first game if it starts earlier — and reopens 24 hours later. The league can move a deadline; the countdown always shows the real one. Late joiners start scoring from their first completed gameweek.`
  - `{margin}` = `an hour` for 60, else `{n} minutes`.
- **Rules → prices:** `Every Monday prices move on performance:` → `The morning after each game day, prices move on performance:`
- **Rules → selling note:** `Prices change on Monday morning.` → `Prices change the morning after each game day.`
- **Rules → FAQ:** the cancelled-day sentence becomes `If a whole game day is called off, that gameweek is skipped as if it never happened: your team, transfers and chips stay as you set them, no points hit is charged, and teams reopen until the next game day's deadline. If only some games are played, those count that week and the rest count in the week they're played.` Keep the existing voided-week sentences.
- **Walkthrough:** `Your squad locks at {lockHour} league time on game day and reopens for changes the next day. Make your moves before the whistle.`
- **Deadline chip:** `GW{n} opens Monday` → `GW{n} opens {weekday}`, with `{weekday}` the league-time weekday of `opensUtc` (e.g. `Monday`).

- [ ] **Step 1: Failing tests.**
  - "a LockedWeeks entry keeps GW1 frozen after its date leaves the schedule".
  - "an override moves the countdown".
  - "a skipped date drops out and later weeks renumber".
  - "a List-shaped LockedWeeks node parses" (Review Focus 2).
  - "the feed waits for both streams; no reveal on Date alone".
  - "Config change of Deadlines resubscribes".
  - "deadline text on Nov 1 2026 (fall-back) shows 4:00 PM for a 16:00 PST lockUtc".
  - "chip says opens Thursday for a Wednesday game day".
  - Rules and walkthrough exact strings, light/dark at 360 px.
- [ ] **Step 2:** `/c/src/flutter/bin/flutter test test/fantasy/` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Full suite `/c/src/flutter/bin/flutter test` → green. `flutter analyze lib test` → no new issues.
- [ ] **Step 5: Commit.** `feat(fantasy): the app follows frozen weeks, moved deadlines and skipped days`

### Task 10: Manager engine twin + schedule-aware gameweeks provider

**Files (Manager repo):**
- Modify: `lib/fantasy/engine/gameweeks.dart`, `lib/fantasy/engine/league_time.dart` (byte-identical copies of the fan files after Task 1)
- Modify: `lib/fantasy/data/fantasy_admin_models.dart` (twin parsers `lockedWeeksFromNode`, `scheduleOverridesFromConfigNode`, `firstKickoffByDateFromNode`, same code as the fan parsers)
- Modify: `lib/services/firebase/fantasy_admin_service.dart` (`watchLockedWeeks`), `lib/providers/fantasy_admin_provider.dart:480-487` (`fantasyGameweeksProvider` passes `GameweekSchedule`)
- Modify (bug class: whole-hour `formatDeadline` → `formatLeagueInstant(lockUtc)`): `lib/ui/fantasy/fantasy_gameweeks_page.dart:152`, `lib/ui/fantasy/fantasy_section_page.dart:169,204,218-228` where they show a week's deadline
- Create: `test/fantasy/fixtures/golden_schedule.json` (byte-copy of the fan fixture), `test/fantasy/schedule_twin_test.dart`

- [ ] **Step 1: Failing twin test.** It replays every `golden_schedule.json` case and asserts the fixture file's SHA-256 equals the fan repo's (the hash is pinned as a constant; the test comment says how to refresh). Also the parser cases from Task 1, including the List shape.
- [ ] **Step 2:** `flutter test test/fantasy/schedule_twin_test.dart` → FAIL.
- [ ] **Step 3: Copy the engine files and implement the provider.** It emits null until Date, LockedWeeks and Config have all answered.
- [ ] **Step 4:** Full Manager suite + `flutter analyze lib test` → green.
- [ ] **Step 5: Commit.** `feat(fantasy): Manager gameweeks follow frozen weeks, deadline overrides and skipped days`

### Task 11: Manager Gameweeks page — change deadline, back to automatic, skip, bring back

**Files (Manager):**
- Modify: `lib/ui/fantasy/fantasy_gameweeks_page.dart`, `lib/services/firebase/fantasy_admin_service.dart`, `lib/ui/fantasy/news/news_schedule_picker.dart` (optional `latestMs`)
- Test: `test/fantasy/fantasy_widgets_test.dart`, `test/fantasy/news_templates_test.dart` (picker bound)

**Interfaces:**
- `Future<void> setDeadlineOverride(SportType sport, String season, String date, int? epochMs)`: null removes `Config/Deadlines/<date>`.
- `Future<void> setDateSkipped(SportType sport, String season, String date, bool skipped)`: false removes the key.
- `showNewsScheduleDialog(..., int? latestMs)`: Schedule disabled past `latestMs`, with the inline error `Pick a time before the end of game day.`

**UI (exact copy):**
- **Row deadline line:** `Locks {formatLeagueInstant(gw.lockUtc)}`, plus a `changed` chip when the date has an override.
- **Actions** (frozen + scored weeks get none of these):
  - `Change deadline`: picker bounded to [now, game day 23:59 league]. Title `GW{n} deadline`. Footnote `Fans see the new deadline right away. If GW{n} is already locked, choosing a later time reopens it.`
  - `Back to automatic`: shown only when overridden.
  - `Skip this week`: confirm title `Skip GW{n} ({date})?`, body `Fantasy treats this game day as cancelled. If its deadline has passed, teams reopen and nothing from it counts. Games played on this day won't score in fantasy.`
- **New section `Skipped days`:** one row per skipped date with `Bring back`. If the date is at or before the last locked week's date, the button is disabled with the note `A later week has already locked, so this day can't come back.`
- **Badge:** `Repriced: skipped (late)` when `Repriced/<gw>/Skipped == 'late'`.

- [ ] **Step 1: Failing widget tests** (fake service, like `fantasy_widgets_test.dart:25-71`):
  - each action calls the service with the exact args;
  - frozen-scored rows show no actions;
  - the bring-back disabled state;
  - the picker refuses after `latestMs`;
  - 360 px light/dark, no overflow.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Suite + analyze green.
- [ ] **Step 5: Commit.** `feat(fantasy): change a week's deadline or skip a game day from the Gameweeks page`

### Task 12: Manager schedule edits warn about fantasy

**Files (Manager):**
- Create: `lib/fantasy/logic/schedule_warnings.dart`, `test/fantasy/schedule_warnings_test.dart`
- Modify:
  - `lib/ui/seasons/schedule_manager_page.dart`: `_deleteGame` warnings buffer `:631-649`; a new confirm in `_editGame` after the form returns, when `result.dateKey != dateKey`, before `:580`; `_addGame :97-154`.
  - `lib/ui/seasons/manage_league_teams_page.dart:146-161` (team delete).
  - The playoffs replace dialog `schedule_manager_page.dart:930-953`.

**Interfaces:**
`String? fantasyScheduleWarning({required List<Gameweek>? gws, required Set<int> scoredWeeks, required String fromDate, required int gamesLeftOnFromDateAfterEdit, required FantasyEditKind kind})`, with `enum FantasyEditKind { removeOrMove, addToDate }`. It returns null when `gws` is null (no fantasy) or nothing applies.

**Copy (exact):**
- **Scored date:** `Fantasy week {n} already counted this game day. Changing its games re-scores week {n}.`
- **Locked, unscored, last game leaving:** `Fantasy week {n} is locked. Moving or deleting the last game of this day cancels week {n}: teams reopen until the next game day's deadline.`
- **Adding to a date at or before the last frozen week's date that is not itself a week:** `Fantasy has already locked a later week, so games on this day won't count in fantasy.`

Scored weeks come from the existing `fantasyHistoryCountsProvider`. Weeks come from Task 10's provider for `(sport, '$season')`.

- [ ] **Step 1: Failing tests.**
  - The pure function: each message; null cases (no fantasy, an open week, games left on the date).
  - Widget tests: the delete dialog shows the line; a date change shows the new confirm; Cancel aborts the move.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Suite + analyze green.
- [ ] **Step 5: Commit.** `feat(schedule): warn before a schedule edit changes fantasy`

### Task 13: Manager "Start fantasy season"

**Files (Manager):**
- Create: `lib/ui/fantasy/fantasy_start_season_page.dart`, `lib/fantasy/data/fantasy_season_start_models.dart`, `test/fantasy/fantasy_start_season_test.dart`
- Modify:
  - `lib/services/firebase/fantasy_admin_service.dart` (`previewFantasySeason`, `startFantasySeason`)
  - `lib/providers/fantasy_admin_provider.dart` (`fantasyStartableSeasonProvider(SportType)` = the `Current Season` pointer when that season has no Config, else null)
  - `lib/ui/fantasy/fantasy_season_bar.dart` (start card in the "No fantasy seasons" state and above the bar when a startable season exists)
  - `lib/router/app_router.dart` (`/fantasy/start/:sport/:season`)

**Interfaces:**
- Models parse the Task 6 shapes defensively: `SeasonPreview.fromData(Object?)`, `PreviewRow`, `StartProblem`.
- `previewFantasySeason` returns `SeasonPreview`.
- `startFantasySeason(sport, season, Map<String, ({int? priceTenths, String? position})> edits)` returns the player count.
- `failed-precondition` → `FantasyStartRefused(List<StartProblem>)`, following the `sendFantasyMessage` translation at `fantasy_admin_service.dart:398-427`.

**UI (exact copy):**
- **Card:** `Start fantasy for {Sport} Season {N}` / `Prices and positions carry over from last season. You'll see everything before it goes live.` / button `Preview`.
- **Page:**
  - Title `Start {Sport} Season {N} fantasy`.
  - Problems block, one line each:
    - `noRosters` → `Build the season's teams first.`
    - `noSchedule` → `Add the season's game days first — week 1's deadline comes from the schedule.`
    - `alreadyStarted` → `This season's fantasy has already started.`
    - `sourceIsTestFill` → `Last season still holds test data. Ask Claude to clear it, then preview again.`
  - Rows grouped GK / DEF / ATT: name; team; price chip (reuse the players page stepper dialog `fantasy_players_page.dart:279-353`); position chip; a source line:
    - `S{n} price` / `average {pos} price` / `new-player price`;
    - `S{n} position` / `sign-up position` / `no sign-up position — set to ATT`.
  - Settings summary: `Settings copied from Season {M}: lock {hour}. Season pass: free — set it in Access & payments after starting.`
  - Button `Start fantasy`. Confirm `Start {Sport} Season {N} fantasy with {count} players?`. On success, the snackbar `Fantasy started` and navigation to the season's Fantasy overview.
- Retry on a failed preview; no stale preview shown after an error.

- [ ] **Step 1: Failing tests.**
  - Model parsing, including junk.
  - The card shows only when startable.
  - Problems disable Start.
  - An edit reaches the service call.
  - A refused start shows the problem lines.
  - 360 px light/dark.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Suite + analyze green.
- [ ] **Step 5: Commit.** `feat(fantasy): start a fantasy season from the Manager with carried-over prices`

### Task 14: Deploy, install, owner checks (with the owner's OK at each outward step)

- [ ] **Step 1:** Full suites: functions `npm test`, fan `flutter test`, Manager `flutter test`; offline rehearsal `npm run rehearse:s15 -- --offline` ALL PASS.
- [ ] **Step 2: Deploy** all fantasy functions + the new ones (`fantasyFutsal` / `fantasyBasketball` / `fantasyFlagFootball` groups, `onFantasyConfigWritten`, `previewFantasySeason`, `startFantasySeason`) plus database rules, together. Then verify live rules == stage1 file via REST, as before.
- [ ] **Step 3: Rules probe** on the LOCAL RTDB emulator only: `LockedWeeks` client write denied; Config `Deadlines`/`SkippedDates` admin allowed, fan denied.
- [ ] **Step 4:** Install the Manager on the emulator (and the tablet if adb is up); install the fan debug APK on `emulator-5554`.
- [ ] **Step 5: Launch runbook** for the owner (not executed here):
  1. Owner OK → `npm run fill:s15 -- --clear <latest backup>`.
  2. S16 schedule and teams built in the Manager.
  3. Manager → Fantasy → Start fantasy for Futsal Season 16 → review → Start.
  4. Set the season pass in Access & payments if wanted.

## Rulings made while writing this plan (for Fable)

1. **Access is not copied** to a new season: it's a per-season business choice, and S15's $5 is a test value. *Cost if wrong:* the owner sets the pass once per season.
2. **Mid-season joiners pay the position average even if they played before.** That's the owner's literal rule; the position still carries over. *Cost if wrong:* a returning star is cheap for one season.
3. **Start requires a schedule.** GW1's deadline comes from it. *Cost if wrong:* the owner waits for the schedule before starting.
4. **The reprice job keeps its deployed name `fantasyMondayReprice`** while running daily. *Cost if wrong:* a misleading name in the console.
5. **A game added on a day before the last locked week never counts in fantasy.** The Manager warns. *Cost if wrong:* a forgotten past game must be entered on its real date before the next lock.
6. **Friendly-only dates stay weeks (unchanged).** No two-game weeks either; both are out of scope per the owner.
7. **The trigger only updates the GwState of an `open` week.** Locked status stays the sweep's job, preserving the snapshot-before-status ordering. *Cost if wrong:* up to 15 minutes before a locked status shows server-side (the app already derives it).
