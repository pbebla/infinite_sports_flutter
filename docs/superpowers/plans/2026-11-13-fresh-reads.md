# Fresh reads: no screen stays on the phone's saved copy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After any change in the database (a new season, a renamed player, a changed fee), every screen of the fan app shows the current data without an app update or reinstall, while screens still open instantly from the phone's saved copy.

**Architecture:** One small data-layer file, `lib/misc/fresh_read.dart`, with two read helpers built on live `onValue` listeners (never `get()`): a *refreshing* read for display data (answers at once from the saved copy and keeps listening briefly so the saved copy is renewed) and a *server-first* read for decisions (waits for the server's answer when online, falls back to the saved copy when offline). The season pointers become one live source. Every `once()` in `lib/` is routed through one of the two helpers, and a guard test keeps it that way.

**Tech stack:** Flutter fan app, Firebase Realtime Database with the on-disk cache ON (`enableRtdbPersistenceUnlessEmulator`, `lib/misc/rtdb_emulator.dart`). Branch `zaya-review-fixes` (add commits only; do not push).

**Spec:** this document plus the row-by-row inventory `docs/superpowers/plans/assets/2026-11-13-once-survey.md` (84 real `once()` calls: 20 GATE, 52 DISPLAY of which 10 are in dead functions, 6 OWN-WRITE, 6 STATIC; its lists A, B and C name the wrong-action risks, the session caches and the all-one-shot screens). Row numbers below (#N) refer to that table.

## What is known (measured on the emulator, 2026-11-13)

- A one-shot `once()` on a path the phone has loaded before answers from the saved copy. For `Futsal/15/Line Ups` (top-bar leaderboard) and `Logo Urls` it stayed stale across five cold starts and a device reboot while online.
- A live `onValue` listener that stays attached refreshes the saved copy: the Leagues season page (streams) showed renamed players at once, after which the one-shot leaderboard showed them too; the live logo stream (commit 8a62c40) made Season 16 crests appear on an install with a stale copy.
- NOT yet understood: the season pointer `Futsal Season` appeared fresh on the first cold start after it changed. Task 0 measures the real rules before anything is built on assumptions.

## Global constraints

- **No Realtime Database `.get()`** anywhere (iOS returns wrong data). `onValue` listeners and the two helpers only.
- A failed or timed-out read is not a fact: keep every existing error/loading state; a helper that cannot reach the server returns the saved copy (if there is one) and says so to callers that ask; it never invents "empty".
- Instant open is kept: no DISPLAY screen may wait for the network when a saved copy exists (owner rule: no slower loads, no pop-in, one reveal).
- Bounded: nothing waits longer than `kRevealReadTimeout` (8 s, `lib/misc/bounded_read.dart`) offline.
- Light and dark, 360 px, no `ios/` or `android/` edits.
- Behaviour of streams that already exist is untouched.

## Review focus

1. A fan who already registered is never sent back into the form by a stale "not registered" (#74), and is never shown or charged an old fee (#72, #76).
2. A phone that was last opened in Season 15 lands on Season 16 the first time it opens after the change, on every screen that depends on the pointers (Matches, top-bar Table and Leaderboard, calendar league days, Leagues list, profile, fantasy resolver).
3. No listener leak: lingering listeners are shared per path, always cancelled, and never outlive sign-out for per-user paths.
4. Offline cold start: every screen opens from the saved copy within the existing bounds; nothing hangs, nothing shows a false empty state.
5. No DISPLAY screen became slower to open on a warm phone.

---

### Task 0: Measure on a device (the gate for everything else)

**Files:** Create `tool/fresh_read_probe.dart` (a separate app entry point, NOT under `lib/`, run with `flutter build apk --debug -t tool/fresh_read_probe.dart`); create `docs/superpowers/plans/assets/2026-11-13-fresh-read-probe.md` (how to run it + a results table for the controller to fill).

The probe initialises Firebase exactly like the app (same options, same on-disk cache setting), needs no sign-in, and on each launch runs ONE phase chosen by a launch counter kept in `shared_preferences` (key `freshProbeLaunch`, 1-based; a `--dart-define=PROBE_RESET=1` build resets it). It reads only `SyncProbe/value` (a throwaway public test value the controller changes between launches) and never-loaded children of `SyncProbe/barrier/`. Every measurement is one logcat line `PROBE|<launch>|<step>|<value or ERR>|<ms since step start>`. It shows the same lines on screen. It writes nothing to the database.

Phases (the controller sets the server value before each launch; A, B, C… are the values):
1. `once()` → primes the saved copy.
2. `once()` at start (stale?) → wait 3 s → `once()` again → wait 3 s → `once()` again.
3. Wait until `.info/connected` is true, then `once()` (does being connected change it?) → 3 s → `once()`.
4. Attach `onValue`, log every event with its time for 6 s, cancel; then `once()`.
5. Linger test: attach `onValue`, cancel 300 ms after the first event; then `once()`. (Next launch's first `once()` shows whether the saved copy was renewed.)
6. `once()` first (baseline for phase 5's effect), then barrier test: attach `onValue` on the value; at the first event start `once()` on `SyncProbe/barrier/<random push id>`; log when the barrier returns and what the latest value event is at that moment; cancel.
7. Barrier with a FIXED child `SyncProbe/barrier/fixed` twice in a row (is the second one answered locally?).
8. (Controller turns airplane mode on.) Every variant above with an 8 s bound: log value or TIMEOUT and the time.

- [ ] Build the probe and the run sheet; `flutter analyze tool/fresh_read_probe.dart` clean; do not add it to any app code path; commit. The controller runs it and records the results before Task 1 starts; Task 1's constants and the choice of barrier come from those results.

### Task 1: The two helpers

**Files:** Create `lib/misc/fresh_read.dart`; test `test/fresh_read_test.dart` (fakes for the event stream and the barrier; no Firebase in tests).

**Interfaces (Produces):**
- `Future<DatabaseEvent> refreshingOnce(Query q)` — completes with the first event (the saved copy when there is one, so opening stays instant), then keeps ONE shared listener per path alive for `kLingerFor` (value from Task 0) so the server's version lands in the saved copy; if a different value arrives while lingering it is delivered to `onNewer` listeners registered with `FreshReads.onNewer(path, callback)` (used to drop session caches / repaint).
- `Future<FreshResult> serverFirstOnce(Query q, {Duration timeout = kRevealReadTimeout})` — when the database connection is up: the value the server has now (using the barrier Task 0 proved, else the settle window Task 0 measured); when it is not, or the bound passes: the saved copy with `fromServer: false`. `FreshResult { DataSnapshot snapshot; bool fromServer; }`. Never throws for a timeout when a saved copy exists; throws the existing `TimeoutException` when there is neither.
- Listeners are reference-counted per path string + query params; `FreshReads.cancelUserScoped()` cancels lingering listeners under `Users/<uid>` and other per-user paths at sign-out.

- [ ] Failing tests for: first event returned at once; linger renews and then cancels; two reads of one path share one listener; `onNewer` fires only for a changed value; server-first returns the server value after the barrier, the saved copy on timeout/offline with `fromServer: false`, and the error path; nothing fires after cancel. Implement; commit.

### Task 2: Season pointers are live

**Files:** `lib/misc/utility.dart` (`getCurrentSport`, `getCurrentSeason`, #37/#38), `lib/main.dart` (`headerNotifier` set at start), `lib/frontpage.dart` (`getFrontPageValues` fields), `lib/misc/calendar_sources.dart` (league-days season), `lib/fantasy/data/fantasy_season_resolver.dart` (`_readPointer`, `_lastResolved`, `_noSeasonAt`), the Leagues list; tests.

- One live source `SeasonPointers` (a `ValueListenable` of `{currentLeague, seasonBySport}`) fed by `onValue` on `Current League` and each `<Sport> Season`. The existing getter functions keep their signatures and answer from it (first event bounded as today).
- When a pointer changes while the app is open: `headerNotifier`, the Matches tab's league/season/date, the calendar's league days, the Leagues season list and the fantasy resolver memo all follow without a restart, in ONE coordinated update (no half-old half-new screen, no reload flash of unrelated tabs).

- [ ] Failing tests (pointer change → each consumer follows; first-event bound; error is not "no season"); implement; commit.

### Task 3: Decision reads wait for the server

Every GATE row uses `serverFirstOnce`, and each call site decides what to do with `fromServer: false`:
- Registration (#72 from the event page, #74, #76, #71, and the `watchMyInsider(...).first` read in `registration_form_page.dart`): when the answer is not from the server, do not let the fan submit or pay on it — show the existing "couldn't check, try again" state. #74 additionally: a submit must never overwrite an existing submission — verify the write path refuses when a submission exists (rules or a pre-write server-first check) and add the check if it is missing.
- Insider code checks (#15, #16, #17): not from the server → the code cannot be applied yet ("couldn't check the code").
- Onboarding (#6, #7, #8, #21, #22): not from the server → keep today's behaviour for a saved copy but never RE-ask a fan who already completed About You or the favorites prompt on the strength of a stale "not completed"; when unsure, do not block.
- Legacy sign-ups (#54, #58, #59, #63, #64): server-first; not from the server → today's display, and the sign-up action re-checks before writing.
- Fantasy resolver (#1, #2) follows Task 2's live pointers; the Config existence probe uses `serverFirstOnce`.
- Profile write-backs built from one-shot reads (#75, #57, #60): the write must be built from a server-first read, or write only the fields the fan actually changed.

- [ ] Failing tests per group (the wrong-action scenarios in the survey's list A, each made impossible); implement; commit per group.

### Task 4: Display reads refresh the saved copy

- Every DISPLAY and STATIC row calls `refreshingOnce` instead of `once()` (mechanical; the returned `DatabaseEvent` keeps `.snapshot`).
- Session caches from the survey's list B are dropped or refilled when `onNewer` reports a newer value: `futsalLineups` / `basketballLineups` / `flagFootballLineups`, `_careerCache`, both `_profileUrlCache`s (and call their `clear…` on sign-out), `FantasyLeaderboardsTab.profilesSession`, `_startHourSession`, `app_config` `_cached`.
- The most-opened all-one-shot screens (survey list C: top-bar Leaderboard, top-bar Table, the Matches tab's AFC San Jose section, the drawer, the player profile) repaint in place when `onNewer` fires while they are open (one `setState`, no reload flash, scroll kept).
- Fold in the three minor findings from the Season 16 fan review: the live logo stream re-subscribes after an error with the shared retry helper (`fantasy_schedule_feed.dart` retry) and a test covers it; `leaderboard.dart` and `table.dart` logo lookups are null-safe when the logo map is empty.
- OWN-WRITE rows: leave the read as is only where it is immediately followed by this client's own write of the same path and cannot act on a stale value; otherwise treat as GATE. List each decision in the report.
- The 10 dead functions: leave them, but route them through the helper so the guard passes.

- [ ] Failing tests for the cache-drop and repaint behaviour; implement in logical commits (by file group); full `flutter test`.

### Task 5: Guard

- [ ] `test/no_bare_once_guard_test.dart`: fails if any file under `lib/` other than `lib/misc/fresh_read.dart` calls `.once()` (same style as the existing no-`get()` guard), with a message naming the two helpers. Commit.

### Task 6: Rules for the barrier (only if Task 0 chose the barrier)

- [ ] Add the barrier node to BOTH `database.rules.stage1.json` and `database.rules.json` (public read of a node nobody can write), a rules-contract entry and a probe check in `functions/`. Do not deploy; the controller deploys with the owner's go. Remove the throwaway `SyncProbe` references from the plan's run sheet once the probe has been run.

## Out of scope

Converting the old one-shot screens into full stream screens (they repaint on newer data after this plan, which is the fan-visible goal); the Manager app.
