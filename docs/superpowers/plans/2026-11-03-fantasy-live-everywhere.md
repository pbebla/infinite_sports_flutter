# Fantasy Live Everywhere — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** written by Opus 2026-11-03 for a **Fable review before execution** (owner rule). Fable: the design choices are in the spec; "Decisions for review" below lists the ones most worth a second opinion.
>
> **Order:** execute AFTER `2026-11-03-fantasy-transfers-in-app.md`. That one must ship before Season 16's first rollover, and both edit `squad_builder.dart`, `fantasy_service.dart` and `fantasy_session.dart`.

**Goal:** While a gameweek's games are being played, every fantasy number in both apps moves live: player points, totals, form, manager week points, ranks and movement, Team of the Week, rank history and the orderings built on them. My Team's "live points coming here" placeholder becomes the live view.

**Architecture:** A new per-sport trigger recomputes the locked gameweek on every game write. It uses the finalize engine's own scoring stages (split out of `computeGameweekFinalize`) plus a cached "settled base", and publishes `Fantasy/<sport>/<season>/Live/*` in one guarded transaction. The fan and Manager data layers overlay `Live` onto the official nodes they already stream, so every screen goes live with small presentation changes. A contract test pins live == finalize once every game is Final, so the hand-over never jumps.

**Tech Stack:** TypeScript Cloud Functions v2 (vitest, FakeDb), Flutter/Dart fan app (flutter_test), Flutter Manager app (Riverpod), RTDB rules (both files).

**Spec:** `docs/superpowers/specs/2026-11-03-fantasy-live-design.md`. Read it first: it holds the provisional rules (pending players, provisional bonus, settled state) and the node shapes this plan implements.

## Decisions for review (Opus rulings, Fable please check)

- **D1. The server computes; phones overlay.** The alternative, each phone replaying every manager, was rejected: rank needs every squad, and phones would disagree mid-game. Cost: one function run per game write, about 1–3 s behind the scorer.
- **D2. Ordering is a single transaction on the whole `Live` node, guarded by `ReadAt`** (the instant the run read the games). Rejected alternative: `maxInstances: 1` serialisation (queued events back off for minutes under Eventarc). The node is about 40–60 KB for 200 managers.
- **D3. A pending player counts as "playing, 0 so far"** for armband and auto-sub decisions (spec §2). Without that, every player whose game hasn't started would be auto-subbed at kickoff of the first game.
- **D4. Provisional bonus is included in live totals and flagged.** It equals the finalize bonus the moment the game is Final.
- **D5. Overlay at the data layer, not per screen.** `watchLeaderboards`, `watchPlayerTotals`, `watchDreamTeams` and `watchPlayerWeekStatsFor` merge `Live` into their existing models, so mini-leagues, profile cards and share cards follow for free.
- **D6. Leaderboard rows that move get a short tint plus a rank cross-fade, not a sliding animation.** The list is lazy, and sliding rows inside a lazy `ListView` with a pinned own-row is fragile. Fable may prefer slides.
- **D7. News player cards stay frozen** (they are what the post said when written). Price risers/fallers stay Monday-only (owner).

## Global Constraints

- No RTDB `.get()` anywhere; every client read is an `onValue` stream. iOS parity, with an iOS check list in the PR.
- Every new client stream cache is registered in `lib/fantasy/data/fantasy_session.dart` so sign-out clears it.
- Light and dark mode. The LIVE pill dot and any "down" colour use the bright red pair (`fantasyDownRed` #FF5252 dark / #D32F2F light); "up" reuses the leaderboard's existing movement-up colour. No hard-coded light fills.
- Perceived performance: no number visibly flips after a screen's reveal. When `Live` is active the reveal gate waits for the live feed's first value too, bounded at 2 s.
- Money and points stay integers in tenths. Whole points truncate toward zero exactly like `wholePoints`.
- TS engine changes keep the golden fixtures byte-identical (`golden_replay`, `golden_forfeit_replay`, `golden_standin_replay` tests stay green untouched).
- Live never writes an official node (History, Leaderboards, PlayerTotals, PlayerWeeks, PlayerWeekStats, DreamTeam, TransferState, TransferCosts, PublishedPicks, Baselines, SquadAlerts).
- Live stands down exactly where finalize does: no Config, a lock override other than `auto`, a TestFill season, a date before the lock. It also stands down with no `PublishedPicks/<gw>` or no `LockedPositions/<gw>` (warn and skip).
- Both rules files change together; `functions/src/rules_contract.test.ts` pins them. Deploy order: rules → functions → apps. Never push.

## Review Focus

1. **The first game ends while the second hasn't started.** Players of the second game's teams must still be "pending": no auto-sub, captain keeps the armband. Pinned in Task 1.
2. **A run that read older games finishing after a newer run.** The stored `Live` must keep the newer numbers. Pinned in Task 3.
3. **A late game write after the week settled** (a score correction after finalize). `Live` must stay a `settled` tombstone, never come back to life, and phones must keep showing official numbers. Pinned in Task 3.
4. **The owner voids the live week mid-day.** Live shows 0 and "Voided", and `LiveBase` is rebuilt. Pinned in Task 3.
5. **A Manager write that doesn't touch scoring** (the kickoff clock, a livestream link, undo bookkeeping) must cost zero reads and no recompute (Fable L2). Pinned in Task 3.

> **Fable review folded in (2026-11-03, `2026-11-03-fable-review-live-and-transfers.md`):** L1 settled is a Meta-only tombstone, with no mirror and no `liveFromFinalize`; L2 trigger diff; L3 `St` priority; L4 void refreshes now; L5 fill-tool allowlist. Owner decisions: S1 steady order plus a refresh pill; S3 demo build (Task 8b). S2 match-tab footnote added. The spec was updated to match.

---

### Task 1: Split the finalize scoring stages; add the pending rule

**Files:**
- Modify: `functions/src/lib/fantasy/finalize_core.ts` (extract stages 1–4 of `computeGameweekFinalize`, line 446)
- Test: `functions/src/lib/fantasy/finalize_core.test.ts`, new `functions/src/lib/fantasy/week_core_pending.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export interface WeekCoreInput { cfg; gw; games: FinalizeGame[]; players; squadsByUid;
    transferCostPointsByUid?; voided: boolean; pendingTeams?: string[] }
  export interface WeekCoreOutput {
    week: Record<string, PlayerWeek>;          // REAL played flags (Dream Team, stats)
    playerWeeks: Record<string, number>;
    playerWeekStats: Record<string, PlayerWeekStatsEntry>;
    historyByUid: Record<string, Record<string, unknown>>; // incl. Breakdown
    weekTenthsByUid: Record<string, number>;
    holders: Record<string, number>; scoredValid: number; skippedSquadUids: string[];
    bonusProvisional: Set<string>;             // players with bonus from an unfinished game
  }
  export function scoreWeekCore(input: WeekCoreInput): WeekCoreOutput
  ```
- `computeGameweekFinalize` calls `scoreWeekCore` with no `pendingTeams` and keeps its stages 5–7 unchanged.
- **Pending rule (only when `pendingTeams` is non-empty):** a market player whose `teamName` is in `pendingTeams` and whose real week is not `played` enters squad scoring as `{points: <his points so far>, played: true}`. `week` (the real map) is untouched.
- `bonusProvisional` = players with a non-zero bonus from a game whose `status !== 2`.

- [ ] **Step 1: Failing tests** (`week_core_pending.test.ts`):
  - (a) Captain on a pending team, vice played 5 → armband stays on the captain; captain counts 0; vice counts 5×1.
  - (b) Pending DEF starter with a played DEF bench → no auto-sub; the bench player counts half.
  - (c) The same starter marked absent in a STARTED game → auto-sub happens (bench full).
  - (d) A team with no game today → not pending → auto-sub happens.
  - (e) `week[pending].played === false`, so `pickDreamTeam` never selects him.
  - (f) `bonusProvisional` holds a status-1 game's top BPS player and is empty once that game is status 2.
  - Plus: `computeGameweekFinalize` output is deep-equal before and after the refactor over every existing `finalize_core.test.ts` case. The three golden replay tests are unchanged and green.
- [ ] **Step 2: Run; expect FAIL** — `cd functions && npx vitest run src/lib/fantasy/week_core_pending.test.ts`.
- [ ] **Step 3: Implement** the extraction and the pending rule.
- [ ] **Step 4: Run** `npx vitest run` (all green) and `npx tsc --noEmit -p .`.
- [ ] **Step 5: Commit** — `refactor(fantasy): finalize scoring stages become scoreWeekCore; pending players for live`.

### Task 2: `computeLiveWeek` + `buildLiveBase` (pure) and the live == finalize contract

**Files:**
- Create: `functions/src/lib/fantasy/live_core.ts`
- Test: `functions/src/lib/fantasy/live_core.test.ts`

**Interfaces:**
- Consumes: `scoreWeekCore`, `competitionRanks`, `wholePoints`, `pickDreamTeam` (Task 1 / existing).
- Produces:
  ```ts
  export interface LiveBase {            // node LiveBase/<gw>, functions-only
    Gw: number;
    Managers: Record<string, { O: number }>;        // settled Overall whole points (voided weeks = 0)
    Players: Record<string, { P: number; G: number }>; // settled season points, games (non-voided)
    FormWeeks: Record<string, Record<string, number>>; // the 3 newest settled non-voided weeks < Gw: week -> name -> pts
  }
  export function buildLiveBase(args: { gw: number;
    historyTenthsByWeek; playerWeeksByWeek; playedGamesByWeek; voidedWeeks: number[] }): LiveBase
  export interface LiveInput extends WeekCoreInput { base: LiveBase;
    gameStatus: Record<string, { S: 0|1|2; T1: string; T2: string }>; readAtMs: number; nowMs: number }
  export interface LiveOutput {          // node Live (spec §5 shapes, exact field names)
    Meta: { Gw; State: 'live' | 'settled'; ReadAt; UpdatedAt; Games };
    Board: Record<string, { O; R; M?; W?; WR? }>;
    Players: Record<string, { Pts; St; Lines?; BonusProv?; Total; Form; Ppg; Games; Own }>;
    Squads: Record<string, { T; W; Slots: Array<{ p; c; x; s? }> }>;
    TeamOfWeek: Array<{ name; position; points }>;
  }
  export function computeLiveWeek(input: LiveInput): LiveOutput
  ```
- `St` priority (Fable L3), first match wins:
  1. present (not marked absent) in a status-1 game of his team → `'live'`;
  2. his team still has a status-0 game today and he hasn't played → `'pending'`;
  3. played → `'done'`;
  4. otherwise → `'out'`.
- `St` per player:
  - `'live'` if any of his team's games today has `S === 1`;
  - else `'pending'` if his team is in `pendingTeams` and he hasn't played;
  - else `'done'` if he played;
  - else `'out'`.
- **Pending players keep their settled numbers:** `Total = base.P`, `Games = base.G`, form over base weeks only, `Pts` 0.
- **Everyone else:**
  - `Total = base.P + Pts` (voided gw → `base.P`), `Games = base.G + GP`.
  - `Form` = round(10 × mean over the window: this gw (if not voided) plus the newest base weeks, 3 weeks in all; a missing player counts 0).
  - `Ppg` = `Games` 0 → 0, else round(10 × Total / Games).
- `Own` = round(100 × holders / scoredValid).
- **Board:**
  - `O = base.O + (voided ? 0 : W)`.
  - `R` = competition rank of `O` over base ∪ this week.
  - `M = rankOf(base.O) − R`, omitted for managers absent from the base.
  - `W`/`WR` only for managers scored this week (voided → `W` 0, so everyone ties at rank 1, as finalize does).

- [ ] **Step 1: Failing tests.**
  - **THE CONTRACT TEST:** for each scenario below, finalize the earlier weeks with `computeGameweekFinalize`, then build the base from their outputs and run `computeLiveWeek` with every game of gw at status 2 and no pending teams. Compare it directly to gw's own `computeGameweekFinalize` output, for every uid and every player:
    - `Board.W/WR` == `gameweekBoard`;
    - `Board.O/R/M` == `overallBoard`;
    - `Players.Pts/Lines` == `playerWeekStats.Pts/Lines`;
    - `Players.Total/Form/Ppg/Games/Own` == `playerTotals`;
    - `TeamOfWeek` == `dreamTeam.Players`;
    - `Squads[uid].T` == `History TotalTenths`, and `Slots` == `Breakdown`.
  - **Scenarios:** (i) the golden fixture as gw 1; (ii) a 4-week synthetic season with a transfer hit, a Triple Captain, a Bench Boost, an invalid squad and a manager who skips week 3; (iii) the same with week 2 voided; (iv) the same with gw itself voided.
  - **Plus unit cases:** a pending player keeps `Total`/`Form`; each `St` rule in priority order (an absent player in a live game is `'out'`, not `'live'`); a manager new this week has no `M`; ties share rank.
- [ ] **Step 2: Run; expect FAIL** — `npx vitest run src/lib/fantasy/live_core.test.ts`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npx vitest run` and `npx tsc --noEmit -p .`; green.
- [ ] **Step 5: Commit** — `feat(fantasy): live gameweek computation, pinned equal to finalize at full time`.

### Task 3: Live orchestration, trigger, settle hand-over, sweep backstop, rules

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration.ts`:
  - new `refreshLiveWeek`;
  - `finalizeGameweek` writes the settled tombstone and removes `LiveBase`;
  - `resettleVoidToggle` removes `LiveBase`, then refreshes the live week (L4);
  - `runLifecycleSweep` backstop step (new "2c" after 2b, line ~1704).
- Create: `functions/src/fantasy_live.ts` (`makeFantasyLiveTrigger(sport)`, same shape as `fantasy_finalize.ts`)
- Modify: `functions/src/index.ts` (add `onGameLive` to each sport's grouped export next to `onGameWritten`, line ~361)
- Modify: `database.rules.stage1.json`, `database.rules.json`
- Modify: `functions/tools/fill_test_season_logic.ts` (`EXPECTED_NODES` += `Live`, the finalize tombstone; Fable L5) + its shape test in `fill_test_season_logic.test.ts`
- Test: new `functions/src/lib/fantasy/live_orchestration.test.ts`, `functions/src/rules_contract.test.ts`

**Interfaces:**
- Produces: `refreshLiveWeek(db: FantasyDb, args: { sport; season; dateKey; eventAtMs: number; nowUtc: Date; log? }): Promise<'written'|'skipped'|'stale'|'settled'|'standDown'>`.
- **Reads (read-only):**
  - Config, TestFill marker, `Date` keys → gw, `Date/<dateKey>`;
  - `Line Ups` (attendance exactly as `finalizeGameweek` builds it);
  - `marketForGameweek(db, root, gw, false, …)`;
  - `PublishedPicks/<gw>`, `TransferCosts/<gw>`, `Voided`, `LiveBase/<gw>`, `Live/Meta`.
  - When `LiveBase/<gw>` is absent, it reads History, PlayerWeeks and PlayerWeekStats once, writes `LiveBase/<gw>` via `buildLiveBase`, and continues.
- **Coalescing:** if the stored `Live/Meta.ReadAt` ≥ `eventAtMs` and `Live/Meta.Gw === gw`, return `'stale'` before any heavy read.
- **Never resurrect a settled week (Fable L1):** if `PlayerWeeks/<gw>` exists (finalize's first write, about 2 KB), return `'settled'` before any heavy read. Ruling: this replaces Fable's `History/<gw>` check (same meaning, about 100× smaller read).
- **The write:** `db.transaction('Live', cur => …)`:
  - `cur` null → write;
  - `cur.Meta.Gw > gw` → abort (`'stale'`: a newer week owns `Live`);
  - `cur.Meta.Gw === gw && cur.Meta.State === 'settled'` → abort (`'settled'`);
  - `cur.Meta.Gw === gw && cur.Meta.ReadAt > readAtMs` → abort (`'stale'`);
  - else → write the `LiveOutput`.
  - The first run's null cache must never abort (the 2026-11-02 refund lesson; FakeDb runs transactions cold first).
- **No started game** (all status 0) → `'skipped'` (nothing written).
- **Settle (Fable L1: a tombstone, no mirror):** at the end of `finalizeGameweek` for gw, after every official write, run `db.transaction('Live', cur => …)`:
  - `cur` null or `cur.Meta.Gw <= gw` → replace the WHOLE node with `{ Meta: { Gw: gw, State: 'settled', UpdatedAt: now } }`;
  - `cur.Meta.Gw > gw` → leave it alone (a newer week owns `Live`).
  - Then remove the whole `LiveBase` node.
- **Older-week rerun while a newer week is live:** the tombstone rule leaves `Live` alone; `LiveBase` is removed (above); then call `refreshLiveWeek` for the live gw with `eventAtMs = now`, so the corrected Overall shows at once.
- **Trigger:** `onValueWritten` on `/${sport}/{season}/Date/{dateKey}/{gameIndex}`. It calls `refreshLiveWeek` with `eventAtMs = Date.parse(event.time)` (no secrets), but returns **with zero reads** unless both hold:
  - the after-status is 1 or 2, or the before-status was 1 (a reopen/undo);
  - **(Fable L2)** a scoring key changed between before and after. Deep-compare exactly the keys the mapper reads: `status`, `team1`, `team2`, `team1activity`, `team2activity`, `team1score`, `team2score`, `team1Score`, `team2Score`, `team1attendance`, `team2attendance`, `team1keepers`, `team2keepers`, `forfeitedBy`.
  - Put the diff in a pure exported `scoringKeysChanged(before, after): boolean` with its own test.
- **Sweep 2c:** when `GwState.status === 'locked'` and some game of its date has status 1, or every game is 2 but `Live/Meta.State !== 'settled'`, call `refreshLiveWeek` with `eventAtMs = now`.
- **Rules (both files):**
  - `Fantasy/$sport/$season/Live`: `.read: auth != null`, no `.write`.
  - `LiveBase`: `.read` admin only, no `.write`.

- [ ] **Step 1: Failing tests** (`live_orchestration.test.ts`, FakeDb, cold-first transactions):
  1. A goal at status 1 → `Live` written with the scorer's `Pts`, the owner's `Board.W`.
  2. A run with `readAt` older than the stored one → `'stale'`, numbers unchanged (Review Focus 2).
  3. The last game Final → the finalize trigger path settles → `Live` deep-equals `{ Meta: { Gw, State: 'settled', UpdatedAt } }` (no Board/Players/Squads). A later live run, or a score correction after settle (finalize reruns, live trigger fires) → `Live` is still the tombstone, and `PlayerWeeks/<gw>` makes the live run return `'settled'` before any heavy read (Review Focus 3). With `Live` deleted after settle, a correction write still never recreates it.
  3b. An older-week correction while the next week is live: `Live` stays the newer week's, `LiveBase` is removed, and the immediate refresh shows the corrected `Board.O`.
  4. `Voided/<gw>` set mid-day → the whole `LiveBase` removed and an immediate refresh shows `W` 0 with O = base, with no game write needed (Review Focus 4, Fable L4).
  4b. (Fable L2) A write that changes only `Clock` (or any non-scoring key) → zero reads, zero writes (Review Focus 5). `scoringKeysChanged` unit cases: each listed key flips it; `Clock`, a livestream link and an unknown key don't.
  5. Game 1 Final, game 2 status 0 → game 2's players `St 'pending'`, no auto-sub (Review Focus 1, end to end).
  6. Stand-downs: no Config; lockOverride `open`; TestFill; before lock; no `PublishedPicks/<gw>` → `'standDown'` and zero writes.
  7. Live never writes an official node: snapshot every official path before and after, deep-equal.
  8. Sweep 2c recomputes when a trigger was lost.
  9. `LiveBase` is built once, then reused (read count).
  - `rules_contract.test.ts`: the two new rules exactly.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npx vitest run`, `npx tsc --noEmit -p .`, `npx tsc --noEmit -p tools`, and the offline S15 rehearsal (`npm run rehearse:s15 -- --offline`, ALL PASS; it must not care about `Live`).
- [ ] **Step 5: LOCAL emulator rehearsal** (never live). Script `scratchpad/live/live_emulator_rehearsal.js`, reusing the selling rehearsal's harness. It drives the compiled engine through `rtdbFantasyDb`:
  - lock GW1 → write 20 game events across two games;
  - assert `Live` after each;
  - fire two runs out of order;
  - just before the last game goes Final, assert `Live`'s numbers equal what finalize then writes (contract, end to end); after finalize, assert `Live` is the `settled` tombstone;
  - a REST read of `Live` as a signed-in fan succeeds;
  - a REST write of `Live` is refused.
  - Save the full output.
- [ ] **Step 6: Commit** — `feat(fantasy): live gameweek trigger, settle hand-over and sweep backstop`.

### Task 4: Fan data layer — live feed and overlays

**Files:**
- Create: `lib/fantasy/data/fantasy_live.dart` (models + parsers + `FantasyLiveFeed`)
- Modify: `lib/fantasy/data/fantasy_service.dart`:
  - `watchLeaderboards` 542, `watchPlayerTotals` 145, `watchDreamTeams` 699, `watchPlayerWeekStatsFor` 217;
  - new `watchLiveSquad(sport, season, uid)`.
- Modify: `lib/fantasy/data/fantasy_parsers.dart`:
  - `FantasyLeaderboardEntry`, `FantasyPlayerTotals` and `FantasyDreamTeam` gain `final bool live`;
  - `FantasyLeaderboards.rankHistory` points gain a live flag;
  - new `historyBreakdownFromNode` for settled per-player points (History `Breakdown`, unread today).
- Modify: `lib/fantasy/data/player_week_stats.dart` (`PlayerWeekStats.live`, `bonusProvisional`)
- Modify: `lib/fantasy/data/fantasy_session.dart` (register `FantasyLiveFeed` caches)
- Test: new `test/fantasy/fantasy_live_test.dart`; extend `test/fantasy/leaderboard_parsers_test.dart`, `test/fantasy/fantasy_parsers_test.dart`, `test/fantasy/player_week_stats_test.dart`, `test/fantasy/fantasy_session_test.dart`

**Interfaces:**
- Produces:
  - `class LiveMeta { int gw; LiveState state; int readAt; Map<String, LiveGame> games; }` with `enum LiveState { live, settled }`;
  - `class LiveBoardRow { int o, r; int? m, w, wr; }`;
  - `class LivePlayer { int pts; LivePlayerStatus st; Map<String, ({int n, int p})> lines; bool bonusProv; int total, form, ppg, games, own; }` with `enum LivePlayerStatus { pending, live, done, out }`;
  - `class LiveSquad { int totalTenths, week; List<LiveSlot> slots; }` and `class LiveSlot { String playerId; int countedTenths, multiplier; bool autoSubbedIn; }`.
- Produces: `FantasyLiveFeed.watch(sport, season)` → `Stream<FantasyLiveState>` (Meta + Board + Players + TeamOfWeek; four `onValue` children, never the whole `Live` node, so phones don't download all squads). Session-cached.
- Produces the overlay rule as ONE pure function (Fable L1):
  ```dart
  bool liveAppliesTo({required LiveMeta? meta, required int week}) // meta?.gw == week && meta.state == LiveState.live
  ```
  - Anything else → the official nodes. A settled tombstone carries no numbers. Finalize writes every official node before it tombstones `Live`, and a phone receives them in that order on its one connection, so live numbers hand over to official ones with no gap.
- **Overlays** (each a pure `merge…` function, unit-tested; the stream wrappers just combine):
  - **Leaderboards:**
    - Overall rows = `LiveBoardRow.o/r/m` with `live: true`.
    - Gameweek `byWeek[gw]` = `w/wr` rows.
    - `rankHistory[uid][gw] = r` (live point).
  - **PlayerTotals:** `points/form/ppg/games/ownershipPct` from `LivePlayer.total/form/ppg/games/own`, `live: true`.
  - **DreamTeams:** `[gw]` = `TeamOfWeek`, `live: true`.
  - **PlayerWeekStats** for gw: `Pts`, `Lines`, `GP` (= `lines['plays'].n`), `Played` (`st == done || st == live`), `live: true`, `bonusProvisional`.

- [ ] **Step 1: Failing tests.**
  - Parser round-trips for every `Live` child, including the list-coerced shapes RTDB produces.
  - `liveAppliesTo`: meta null; other week; same week live (true); same week settled tombstone (false).
  - Each merge function: live rows replace, non-live weeks untouched, `live` flags set.
  - The tombstone parses (`Meta` only, no Board/Players) and overlays nothing.
  - Sign-out clears the live caches.
  - `historyBreakdownFromNode` parses `{playerId, countedTenths, multiplier, autoSubbedIn}`.
- [ ] **Step 2: Run; expect FAIL** — `flutter test test/fantasy/fantasy_live_test.dart`.
- [ ] **Step 3: Implement.** The `onValue` error path yields "no live" (the official numbers keep showing), never an empty board.
- [ ] **Step 4: Run** `flutter test test/fantasy/`; green. `flutter analyze lib/fantasy`: no new issues.
- [ ] **Step 5: Commit** — `feat(fantasy): the app streams the live gameweek and overlays it on every board`.

### Task 5: Fan — My Team live view (the placeholder gap) and the shared LIVE pill

**Files:**
- Create: `lib/fantasy/hub/live_pill.dart` (`FantasyLivePill`)
- Modify: `lib/fantasy/hub/squad_builder.dart`:
  - `_LockedLiveStrip` 660 becomes `_LockedWeekStrip(status)`;
  - pass `weekPointsFor` to `FantasyCourtView` at 465 while locked.
- Modify: `lib/fantasy/hub/player_chip.dart:202` (captain nameplate shows `×{captainMultiplierFor}`: ×3 under Triple Captain; bug found in the inventory)
- Create: `lib/fantasy/hub/live_logic.dart` (pure: strip text, chip text)
- Test: `test/fantasy/squad_builder_test.dart`, new `test/fantasy/live_logic_test.dart`

**Interfaces:**
- Consumes: Task 4 (`watchLiveSquad`, `FantasyLiveFeed`, `historyBreakdownFromNode`).
- **Produces `String lockedStripText(LockedWeekView v)`**, with this exact copy:
  - Before any game started: `Locked · waiting for kickoff`
  - Live: `{W} pts · #{R}` followed by ` ▲{m}` / ` ▼{m}` (the existing `movementLabel`) when m ≠ 0. The pill renders separately.
  - Settled, until editing reopens: `Final · {W} pts · #{R}`
  - Voided: `Voided · this week counts 0`
  - Invalid squad: `0 pts · this week didn't count`
- **Produces `String? chipWeekText(LiveSlot? slot, LivePlayerStatus st)`:**
  - `pending` → `Not started`
  - `live` → `{pts} pts · live`
  - `done` → `{pts} pts`
  - `out` → `Out`
  - `pts` = `countedTenths/10`, shown with one decimal only when not whole (bench half points: `2.5 pts`).
- `FantasyLivePill`: red dot + `LIVE`, with a 1.2 s pulse (static under reduced motion). Theme pair `fantasyDownRed`.
- **Data the locked My Team uses:**
  - **Live:** `Live/Squads/<uid>` + `Live/Players` + `Live/Board`.
  - **Settled:** `History/<gw>/<uid>` Breakdown + the official boards.
  - Never `Squads/<uid>` for points.

- [ ] **Step 1: Failing tests.**
  - Every `lockedStripText` and `chipWeekText` case, verbatim.
  - The widget shows the pill only while live.
  - The captain nameplate shows `×3` with Triple Captain and `×2` otherwise.
  - The court chips show the slot texts.
  - Dark mode and a 360 px width don't overflow.
  - No visible flip after the reveal: pump with live arriving 500 ms late → the first painted frame after the reveal already has live numbers.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/fantasy/`; green.
- [ ] **Step 5: Commit** — `feat(fantasy): My Team shows live points while the week is locked`.

### Task 6: Fan — leaderboards, Team of the Week, rank chart, share cards, banners

**Files:**
- Modify: `lib/fantasy/hub/leaderboards_tab.dart` (pill in the Overall and Gameweek headers and on the live week chip; summary card live)
- Modify: `lib/fantasy/hub/leaderboard_rows.dart` (`LeaderboardRowTile`: moved-row tint + rank cross-fade)
- Modify: `lib/fantasy/hub/dream_team_card.dart` (pill + subline)
- Modify: `lib/fantasy/hub/rank_history_chart.dart` (hollow live end point)
- Modify: `lib/fantasy/hub/fantasy_share.dart` (`RankStoryCard` and `TeamOfWeekStoryCard` tag)
- Modify: `lib/fantasy/hub/fantasy_banner.dart` (hub banner) and `lib/fantasy/hub/fantasy_home_banner.dart` (frontpage)
- Modify: `lib/profile/fantasy_profile_tab.dart:534-590` ("View team" passes `rankSeries`; inventory gap A6)
- Test: `test/fantasy/leaderboards_tab_test.dart`, `test/fantasy/dream_team_card_test.dart`, `test/fantasy/fantasy_share_test.dart`, `test/fantasy/fantasy_banner_test.dart`, `test/fantasy/fantasy_home_banner_test.dart`, `test/fantasy/manager_squad_viewer_test.dart`

**Copy (exact):**
- TOTW subline when live: `Can still change until the last game ends.`
- Share tag when live: `LIVE · GW{n} in progress`
- Hub banner and home banner while live: `GW{n} live · {W} pts · #{R}` (plus the pill). A manager with no squad this week sees the existing banner unchanged.

**Behaviour:**
- **Moved row:** a row whose rank changed since the previous emission tints for 800 ms (up: the existing up colour at 18 % alpha; down: `fantasyDownRed` at 18 %). Its rank number cross-fades over 250 ms. Under reduced motion both are instant.
- **Ordering** follows the merged board (rank asc, then points, then uid, as today), under the owner's steady-order rule (S1, "like ESPN and the Premier League: numbers move, rows don't jump"):
  - Numbers update in place the moment they arrive.
  - The list re-orders at once when it is scrolled to the top, when the tab is (re)opened, or when the user picks a sort or scope.
  - Otherwise, a pill `Order changed · tap to refresh` (accent colour, both themes) appears under the header and re-orders on tap, with the moved-row tint.
  - Never re-order under a moving finger.
  - The rule lives in one shared pure helper `lib/fantasy/hub/steady_order.dart` (`SteadyOrder<T>`: `applied`, `pending`, `update(newOrder, {required bool atTop})`, `refresh()`), with unit tests, reused by Task 7.
- **Rank chart:** the live point is drawn hollow (2 px stroke, no fill). The `#start → #now` label uses it.

- [ ] **Step 1: Failing widget tests:**
  - each pill shows only while live; the copy is verbatim;
  - the tint appears for a moved row only; reduced motion → no animation;
  - `SteadyOrder`: scrolled down + new order → rows unchanged + `Order changed · tap to refresh`; tap → re-ordered; at top → re-orders immediately; a sort change → re-orders immediately;
  - the hollow point; the profile's "View team" shows the chart; dark mode and 360 px.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/fantasy/ test/profile/`; green.
- [ ] **Step 5: Commit** — `feat(fantasy): leaderboards, Team of the Week, rank chart, shares and banners go live`.

### Task 7: Fan — squad viewer, market, player profile, profile tab, match tab

**Files:**
- Modify: `lib/fantasy/hub/manager_squad_viewer.dart:457` (court `weekPointsFor` for every week: live from `watchLiveSquad`, settled from History Breakdown; week total line `{W} pts` / `Final · {W} pts`)
- Modify: `lib/fantasy/hub/players_tab.dart` (LIVE pill by the sort bar while live; points and form update in place; ordering follows Task 6's `SteadyOrder` rule, so it re-sorts on a sort tap, at the top or on reopen, and otherwise shows `Order changed · tap to refresh`; rows keyed by player id)
- Modify: `lib/fantasy/profile/fantasy_player_profile_page.dart`, `profile_stat_strip.dart`, `profile_tabs.dart` (pill on the strip; the live week's bar hollow with a `LIVE` label; `bonus (provisional)` line text when `bonusProvisional`)
- Modify: `lib/profile/fantasy_profile_tab.dart` (pills on the player and manager cards while live)
- Modify: `lib/fantasy/match/match_fantasy_tab.dart` and `match_fantasy_logic.dart`:
  - (a) the header shows `LIVE` (pill) or `FINAL` from the game status (today live and final render identically);
  - (b) the viewer's squad for a game is that week's locked squad: `PublishedPicks/<gw>/<uid>`, else `History/<gw>/<uid>`; `Squads/<uid>` only for a not-yet-locked week. Today past games use the current saved squad;
  - (c) a strip under the header while live: `Your gameweek so far: {W} pts · #{R}`;
  - (d) (Fable S2) the tab's existing footnote gains the sentence `Bonus, captain and bench counting show on My Team.`
- Test: `test/fantasy/manager_squad_viewer_test.dart`, `test/fantasy/players_tab_test.dart`, `test/fantasy/fantasy_player_profile_page_test.dart`, `test/fantasy/match_fantasy_tab_test.dart`, `test/fantasy/match_fantasy_logic_test.dart`, `test/profile/` tab tests

- [ ] **Step 1: Failing tests:**
  - The viewer shows per-player points for a settled week (from Breakdown) and a live week.
  - Market scrolled down + a live totals emission → numbers change, row order unchanged, refresh pill shown; a sort tap re-sorts by the live numbers.
  - The match-tab footnote sentence, verbatim.
  - The profile bar for the live week is hollow and labelled.
  - The match tab picks the week's locked squad for a past game (regression test with a squad changed since).
  - `LIVE`/`FINAL` header; the week strip copy is verbatim.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full fan suite: `flutter test` green; `flutter analyze lib/` with no new issues.
- [ ] **Step 5: Commit** — `feat(fantasy): squad viewer, market, profiles and match tab go live`.

### Task 8: Manager app — live standings

**Files (Manager repo `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, branch zaya-fantasy):**
- Modify: `lib/services/firebase/fantasy_admin_service.dart` (new `watchLiveMeta`, `watchLiveBoard`)
- Modify: `lib/providers/fantasy_admin_provider.dart` (`fantasyLiveProvider`, plus `fantasyOverallProvider` consumers get a merged view)
- Modify: `lib/fantasy/data/fantasy_profile_models.dart` (pure `mergeLiveOverall`, `liveAppliesTo` twin)
- Modify: `lib/ui/fantasy/fantasy_team_names_page.dart` (row text `#{R} · {O} pts · LIVE` while live)
- Modify: `lib/ui/fantasy/fantasy_profile_detail_page.dart` (`_StandingCard` live label; `_WeeksCard` adds the live week row: `GW{n}` · `{W}` · Hit · Chip, with the note `live — settles after the last game`)
- Test: `test/fantasy/fantasy_profile_models_test.dart`, `test/fantasy/fantasy_widgets_test.dart`

- [ ] **Step 1: Failing tests:** the merge (live rows replace, rank order), the `liveAppliesTo` twin (same cases as Task 4), the row text and the live week row.
- [ ] **Step 2: Run; expect FAIL** — `flutter test test/fantasy/`.
- [ ] **Step 3: Implement.** Riverpod `StreamProvider` over `onValue`; no `.get()` (`test/no_rtdb_get_guard_test.dart` stays green).
- [ ] **Step 4: Run** the full Manager suite: `flutter test` green.
- [ ] **Step 5: Commit** — `feat(fantasy): Manager profiles show live standings during games`.

### Task 8b: Demo build — the real app against the local database (owner decision S3)

**Files:**
- Modify: the fan app's Firebase start-up (`lib/main.dart`, right after `Firebase.initializeApp`)
- Create: `lib/misc/rtdb_emulator.dart` (`bool get useRtdbEmulator => const bool.fromEnvironment('RTDB_EMULATOR')`, and `void connectRtdbEmulatorIfRequested(FirebaseDatabase db)` → `db.useDatabaseEmulator('10.0.2.2', 9000)` only when the define is set)
- Test: `test/misc/rtdb_emulator_test.dart`
- Create (not committed): `scratchpad/live/demo_feed.js`, which seeds the local emulator with a small season (8 managers, 2 games) and then plays 20 scripted events about 4 s apart through the real compiled engine (Task 3's harness)

- [ ] **Step 1: Failing test:** without the define, `connectRtdbEmulatorIfRequested` calls nothing on the database (a fake records calls); with `useRtdbEmulator` forced true, it calls `useDatabaseEmulator('10.0.2.2', 9000)` once.
- [ ] **Step 2: Run; expect FAIL. Step 3: implement. Step 4: run; pass.** Auth stays on the real project (the demo signs in as the owner's normal account; the emulator database runs with the stage-1 rules and `--project demo-live`).
- [ ] **Step 5: Record the demo.**
  - Start the database emulator.
  - `flutter run --dart-define=RTDB_EMULATOR=1` on emulator-5554.
  - Run `demo_feed.js`.
  - Screen-record (`adb shell screenrecord`) My Team, the leaderboards and the Players list as the goals land.
  - Send the video to the owner with SendUserFile.
  - Leave the emulator running so he can drive it.
- [ ] **Step 6: Commit** (the switch and its test only) — `feat(dev): demo switch points the app's database at the local emulator`.

### Task 9: Ship

- [ ] **Step 1:** Deploy rules (`database.rules.stage1.json`). Verify live == file with `node <scratchpad>/compare_live_rules.js database.rules.stage1.json https://infinite-sports-app.firebaseio.com` (expect `MATCH`).
- [ ] **Step 2:** Deploy every fantasy function, including the three new `fantasy<Sport>-onGameLive`. Check the logs show the S15 TestFill stand-down on a test write, not an error.
- [ ] **Step 3:** Build and install the fan APK (emulator-5554) and the Manager APK (emulator + tablet 10.0.0.146:5555).
- [ ] **Step 4:** Owner test path in plain language:
  - S15 is a test season, so the engine stands down there.
  - The owner sees live behaviour only on a real locked week, or in the local rehearsal video/screenshots I record from the emulator rehearsal (Task 3 Step 5) driving the real app against the local database.
- [ ] **Step 5:** iOS check list in the PR notes:
  - the pill pulse and reduced motion;
  - the market re-sort keeping its scroll position;
  - the share card tag;
  - the Manager live row.
