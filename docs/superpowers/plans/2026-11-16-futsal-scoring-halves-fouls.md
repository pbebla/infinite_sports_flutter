# Futsal Scoring: Halves, Team Fouls, Man-Down, Clock Adjust, Jersey Numbers + Fan Clean-ups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** written 2026-11-16 on Opus 5.5. **Reviewed, amended and APPROVED by Fable 5.2 on 2026-11-16** (see "Fable review" at the end). Ready to build.

**Goal:** Give the scorekeeper halves, a clock they can correct, per-half team-foul tallies with the rulebook's warnings and man-down timers, and jersey numbers in every player list; show fans the half and the team fouls; clean up two fan-app screens; and make the fan app require the latest store version (Part D).

**Architecture:** The game node gains three new top-level fields (`Period`, `PeriodStarts`, `ManDown`). **Events themselves do not change**: no new keys and no new event types. An event's half is derived from the `_t` stamp it already carries, compared with the time the 2nd half started. Twin pure rule files in both apps (`futsal_periods.dart`) do that derivation and the foul counting, so the Manager and the fan app always agree. The Manager writes; the fan app only reads. Fan apps already in the store and the server functions ignore the new fields, so nothing changes for them.

Part D is separate from the scoring work: the fan app asks each store whether a newer version is available to this phone and, if so, shows a blocking "Update required" screen. It runs by itself. The owner's only control is a pause switch in the Manager that turns itself back on.

**Tech Stack:** Flutter/Dart — Manager `InfiniteSportsManagerFlutter`, fan app `infinite_sports_flutter`; Firebase RTDB; flutter_test. One new fan-app package for Part D: `in_app_update` (Google Play's official update check). No Cloud Functions change and no rules change (`AppConfig` is already readable by everyone and writable by admins in both rules files).

**Spec:** "Owner decisions" below (chat, 2026-11-15/16) + the Infinite Futsal League rulebook sections 8 and 10 (memory `futsal_rulebook.md`).

## Owner decisions (the spec)

1. Owner, verbatim: "include jersey numbers in the menu where you give the assist. so when you put score then assist page shows up to choose a player to grant assist we want player numbers there because sometimes you dont know their names so numbers help."
2. Owner, verbatim: "remove defense plays and saves from the timeline in the score page. its a very long stat facts. we should remove those. from the timeline in the fan app."
3. Owner, verbatim: "add ability to manually adjust clock in the manager app."
4. Owner, verbatim: "create tallies for team fouls that can be reset at halftime, as well as notify if foul count hits thresholds defined in rules. so like when a team commits 5 fouls give us a warning when we put the 5th foul so we can provide the warning to the team committing 5 fouls and the referee. and then on the 6th foul, notify us that is is the 6th foul and the team committing the 6th foul should be man down for a minute and the players can go back in after 1 minute is served. then 8th foul same thing, then 10th foul is 2 mins playing man down and every even number after that. but second half the fouls reset to zero for both teams so they start fresh. yellow cards dont reset 2nd half just making sure. i think we would need a way to know when 2nd half starts so whatever happens as far as yellow cards stats or fouls are happening in 2nd half or extra time."
5. Owner, verbatim: "i think we should retire/remove those buttons i circled red from the top now that we have futsal league tabs with all those details." (the Table and Stats icons at the top of the Home / Matches screen)
6. Owner's choices (2026-11-16, multiple choice):
   - 2nd half clock: **"Keep counting"**. The 2nd half continues from where the 1st half stopped, so minutes stay unique.
   - Man-down countdown: **"Fouls AND cards"**. A countdown for team-foul penalties, yellow (1:00) and red (2:00); a "player can return" alert; it ends early if that team concedes a goal (rulebook §8).
   - Fans see: **"Half + team fouls"** on the game page scoreboard.
   - Top buttons: **"Remove them"**.

7. Owner, verbatim (2026-11-16): "when we have fan app update, when people get on the app it forces them to go to their app store or google store and update the app so they can have the latest features and updates."

Rulebook facts used (section 8 "Fouls and Team Foul Accumulation", section 10 "Cards"):
- 1–5 fouls in a half: no penalty. 6th and 8th: one player down 1:00. 10th, 12th, 14th and every even number after: one player down 2:00. Odd fouls after the 5th: no penalty.
- The player who committed the penalty foul leaves; after the time any player may come on.
- Team fouls reset to 0 for both teams at the start of the 2nd half. Fan-conduct fouls count toward the team's total (section 12).
- Conceding ends a man-down: a team playing one player down that concedes a goal may bring its fifth player back on immediately. This applies to team fouls, yellow and red.
- Yellow: player off 1:00, team one down 1:00. Second yellow: player ejected, team one down 1:00, then a replacement. Straight red: ejected, team one down 2:00. A yellow-carded player may stay on when the team has no substitutes (section 10), so the scorekeeper must be able to remove a man-down.
- Yellow cards never reset by halves.
- The rulebook has no extra time. Extra time continues the 2nd half's foul count, as in FIFA futsal (reviewer's default; the owner can ask for a reset instead).

## Data contract (both apps)

Game node `<Sport>/<Season>/Date/<MMDDYYYY>/<index>`. All three fields are new, top-level, written only by the Manager, and cleared by a game Reset.

| Field | Shape | Absent means |
|---|---|---|
| `Period` | `'1H'`, `'HT'`, `'2H'` or `'ET'` | an old game: fans see no half and no team fouls; the Manager treats a live game as `1H` |
| `PeriodStarts` | `{'2H': <epoch ms>, 'ET': <epoch ms>}` | that half has not started |
| `ManDown/<pushId>` | `{Team: 1\|2, Reason: 'TeamFouls'\|'Yellow'\|'SecondYellow'\|'Red', Foul: <n, only for TeamFouls>, Player: <name>, DurationMs: 60000\|120000, StartElapsedMs: <game-clock elapsed ms when it started>, Ended: 'goal'\|'removed' (absent otherwise)}` | no man-downs |

Rules derived from it:

- **An event's half.** With `t` = the event's `_t`: `t >= PeriodStarts.ET` → extra time; else `t >= PeriodStarts.2H` → 2nd half; otherwise 1st half. A missing `_t` or a missing start counts as 1st half. So an event recorded during half time belongs to the 1st half.
- **Same clock for both stamps.** `_t` is written with the device clock (`DateTime.now()`, `game_service.dart:158`). `PeriodStarts` must use the same source, through one shared helper, so the two can never drift apart.
- **Team fouls** for a team = its `Foul` events (any player, including the team's `Guest` row) in the shown half. In `1H` and `HT` that is the 1st half; in `2H` the 2nd half; in `ET` the 2nd half plus extra time.
- **A fan-conduct or bench foul** is recorded as a `Foul` on the team's existing `Guest` row. It counts toward the tally and touches no player's stats (existing behavior). No new button or event type.
- **Penalty for a team's Nth foul in the half** (`foulPenaltyFor(n)`): `n < 5` → none; `n == 5` → warning; `n == 6 || n == 8` → man-down 1:00; `n >= 10 && n.isEven` → man-down 2:00; any other `n` → none.
- **A man-down is running** when it has no `Ended` and its remaining time is above 0. Remaining = `DurationMs − (clockElapsedMs − StartElapsedMs)`, clamped to `0..DurationMs`. It runs on the game clock, so pausing the clock pauses it. Nothing is written when it runs out.
- **Adjusting the clock never changes a running man-down's remaining time** (Task 8 shifts `StartElapsedMs` by the same amount).

## Global Constraints

- **Events are untouched.** A new Manager build writes exactly what today's build writes for an event: `{<Type>: <player>, _t: <ms>}`. No extra key, no new type. Reason: fan apps in the store turn every key except `_t` into a timeline row (`match_facts_tab.dart:90,120`), and the push server takes the first key that is not `_t` as the event type (`functions/src/lib/league_decide.ts:214`).
- Copy, exactly (Manager):
  - Period buttons: `End 1st half`, `Start 2nd half`, `Start extra time`. Correction menu item: `Correct the half`, with choices `1st half`, `Half time`, `2nd half`, `Extra time`.
  - Clock: button `Adjust clock`; dialog title `Adjust clock`; chips `−1:00`, `−0:10`, `+0:10`, `+1:00`; field label `Set time (mm:ss)`. The time never goes below `0:00`.
  - 5th foul: `<Team>: 5th team foul. Warn the team and the referee. The next foul is a penalty.`
  - 6th or 8th foul: `<Team>: <N>th team foul. One player down for 1:00. The player who committed it leaves the field.`
  - 10th and later even fouls: the same sentence with `2:00`.
  - Yellow or second yellow: `<Team>: one player down for 1:00.` Red: `<Team>: one player down for 2:00.`
  - Time up: `<Team>: man-down over. A player may come back on.`
  - Goal ends it: `<Team> conceded. Man-down over, a player may come back on.`
  - Man-down row buttons: `Remove`, `Undo`.
  - Tally on the scoring screen: `Fouls <n>` per team.
- Copy, exactly (fan app): half labels `1st half`, `Half time`, `2nd half`, `Extra time`; under each team `Fouls <n>`.
- Copy, exactly (Part D, fan app): title `Update required`; body `A new version of Infinite Sports is ready. Update to keep using the app.`; button `Update`; Android-only second button `Open Google Play`.
- Copy, exactly (Part D, Manager): switch `Require the latest version`, subtitle `Fans on an old version must update before they can use the app.`; pause dialog title `Pause forced updates?`, body `Fans will be able to keep using old versions. Forced updates turn back on by themselves in 7 days.`, buttons `Cancel` and `Pause`; banner while paused `Forced updates are paused until <date>.` with `Turn back on`.
- **Part D fails open.** The app blocks only on a positive, complete answer from the store. Any error, timeout, unreadable value or unknown case means the fan gets in. A forced update that cannot be obtained must never lock a fan out.
- Futsal only for halves, team fouls and man-down. Basketball and Flag Football scoring screens are unchanged. Jersey numbers and the timeline clean-up apply to every sport that uses the shared widgets.
- Team-foul alerts and man-down timers apply only while the game is live.
- No code, script or migration changes any existing game. A game without `Period` displays exactly as today.
- Fan app: real-time `onValue` streams only, no RTDB `get()`, no bare `.once()`.
- Light and dark mode for every new element (colorScheme or a brightness-conditional pair). Works at 360 px (fan) and on the owner's Kindle Fire tablet (Manager).
- Dialogs with text fields are StatefulWidgets that own and dispose their controllers. Never dispose right after `await showDialog`.
- iOS parity (fan app): nothing platform-specific. The PR gets "verify on iPhone simulator" lines.
- PII never in code, tests or commits. Made-up names.
- Branches: fan `zaya-scoring-halves` from `zaya-fantasy-league-tab` @ `6baff66`; Manager `zaya-scoring-halves` from `zaya-no-charge` @ `bbc3e50`.
- Do not push, deploy or install without the owner's go. Commit trailer: the executing model's own `Co-Authored-By` line.

## Review Focus

1. **Fan apps already in the store, and the push server, read a game scored by the new Manager.** They must see nothing new: no junk timeline rows, no missed goal push. And the new fan app reading an old game shows no half and no fouls. Tests in Tasks 6 and 9.
2. **A mis-tap.** `End 1st half` or `Start 2nd half` tapped by mistake can be put right with `Correct the half`, and the foul tallies follow. A goal recorded by mistake that ended a man-down can be undone with `Undo` on that man-down. Tests in Tasks 6 and 8.
3. **The clock is paused or adjusted during a man-down.** The countdown pauses with the clock, and an adjustment leaves its remaining time unchanged. Test in Task 8.
4. **A team with two running man-downs concedes.** Only the oldest one ends. Test in Task 8.
5. **The 2nd half starts.** Both tallies read 0, yellow cards are untouched, and a foul recorded during half time counts for the 1st half. A foul removed with the event editor makes the tally recount, and its man-down can be removed. Tests in Tasks 5, 7 and 8.
6. **(Part D) A fan is told to update but cannot.** The store check fails or times out; the new version needs a newer iOS than the phone has; the release is only minutes old and the store does not offer it yet; the app is a test build newer than the store; the app was not installed from Google Play. In every one of these the fan gets into the app. Tests in Task 10.

---

## Part A — fan app clean-ups

### Task 1: Remove the Home top-bar Table and Stats buttons

**Files (fan):** `lib/frontpage.dart:546-593` (the two `IconButton`s and the `ValueListenableBuilder` on `_onTournamentTab`), `lib/globalappbar.dart` (`tableWidget` / `leaderboardWidget` become optional; null = no action), tests that pump the Home app bar.

- [ ] **Step 1: failing tests.** `the Home app bar has no Table or Stats button` (no `assets/table.png` / `assets/leader.png` under the Home `GlobalAppBar`); `ShowLeaguePage still shows both buttons` (AFC San Jose keeps them).
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** remove the two buttons; make the `GlobalAppBar` params optional; delete only what nothing else uses (grep `_onTournamentTab`, `headerNotifier`, `followHeader` first). `TablePage` and `LeaderboardPage` stay: `showleague.dart` and `scorepage.dart` use them.
- [ ] **Step 4:** `flutter test` (whole suite), `flutter analyze` on changed files.
- [ ] **Step 5: commit** `feat(home): retire the old Table and Stats buttons from the Home top bar`

### Task 2: The game timeline hides saves and defense plays

**Files (fan):** `lib/misc/league_timeline_filter.dart`, `lib/tournament_tabs/match_facts_tab.dart:507-516` (today the filter runs only when `leagueSportKey != null`) and the Icons legend in the same file, tests.

**Interfaces:** `bool isHiddenTimelineActivity(String? sportKey, String type)` replaces `isHiddenLeagueTimelineActivity`. It hides `save` and `dpl` (case-insensitive) for every sport and for league and tournament matches, plus the existing Basketball `miss`. `PenSaved` / `penalty saved` stay visible.

- [ ] **Step 1: failing tests.** A league futsal match with Goal, Save, DPL, Foul → the timeline shows Goal and Foul only. A tournament match (`leagueSportKey == null`) → the same. `PenSaved` still shows. The Icons legend no longer lists Save or DPL.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement. The box score, player stats, Match Leaders and fantasy read counters and tallies, not the timeline: confirm with a grep and say so in the commit body.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(match): the game timeline no longer lists saves and defense plays`

## Part B — Manager: numbers and clock

### Task 3: Jersey numbers in every live-scoring player list

**Files (Manager):** `lib/ui/shared/league_capture_widgets.dart` (`showAssistPicker` :658, `showLeaguePlayerPicker` :600, `showKeeperPicker` :754, `_pickReassign` :433, `showThrownByPicker` :708), their callers in `lib/ui/futsal|basketball|flag_football/update_*_game_detail_page.dart`, `lib/ui/tournaments/live_scoring_page.dart` (its pickers, including the two substitution dialogs), tests.

**Interfaces:** every picker takes `Map<String, String> numbers` (player name → jersey number) next to its names. A row reads `#<number> · <name>` when the player has a number, else `<name>`. `''`, `'0'`, `'-'` and null mean no number. League numbers come from the lineup the page already loads (`FutsalPlayer.number` and its twins); tournament numbers from `TournamentPlayer.number`. Rows are sorted by number (numeric), then players without a number by name; `Guest` and `Skip` rows stay last as today.

- [ ] **Step 1: failing widget tests.** The assist picker shows `#10 · Alpha Player`; a player with no number shows the name only; rows are in number order; the top-bar picker, the keeper picker and the tournament substitution dialogs show numbers too.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement for every picker listed (fix the whole class).
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(scoring): jersey numbers in every live-scoring player list`

### Task 4: Adjust the game clock

**Files (Manager):** `lib/services/match_clock.dart`, `lib/services/firebase/game_service.dart` (next to `pauseGameClock` / `resumeGameClock`, :225-255), the clock card in the three `update_*_game_detail_page.dart` league pages, new `lib/ui/shared/adjust_clock_dialog.dart`, tests. Fan: `test/match_clock_test.dart` (one new case).

**Interfaces:**
- `int pausedAccumForElapsed({required int startedAtMs, required int? pausedAtMs, required int nowMs, required int targetElapsedMs})` (pure, in `match_clock.dart`): the `PausedAccumMs` for which `elapsedAt(now)` equals the target (target clamped to ≥ 0). The result may be negative when time is added beyond the wall-clock time since kickoff; that is valid.
- `Future<int> GameService.setGameClockElapsed(..., int targetElapsedMs)`: one transaction on the `Clock` node that writes only `PausedAccumMs`, using `serverNowMs()` as now. Returns the change in elapsed ms (new − old). **`StartedAt` is never changed**: the server uses it as the real kickoff time (`functions/src/league_watch.ts:222`, `index.ts:63`).
- `resumeGameClock` (and its tournament twin `TournamentService.resumeMatchClock`) switch from `DateTime.now()` to `serverNowMs()`. `PausedAt` is a server timestamp, so today each resume adds the tablet's clock error to the game clock.
- `AdjustClockDialog` (StatefulWidget that owns its controller): chips `−1:00`, `−0:10`, `+0:10`, `+1:00` change a preview; `Set time (mm:ss)` sets it; Confirm pops the target elapsed ms.

- [ ] **Step 1: failing tests.**
  - Pure function: running clock +60 s; paused clock −10 s; set to 25:00; clamp at 0; a target beyond the wall-clock time gives a negative value and `elapsedAt` still returns the target.
  - Fan `match_clock_test.dart`: `elapsedAt` with a negative `PausedAccumMs` returns the larger elapsed time (pins what store apps will show).
  - Dialog: chips move the preview; an invalid `mm:ss` disables Confirm; Confirm pops the value.
  - `resumeGameClock` folds the pause using the injected server now.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement. `Adjust clock` shows on the clock card only while a clock exists. Recorded events keep their minutes.
- [ ] **Step 4:** `flutter test` in the Manager; the one fan test file; `flutter analyze`.
- [ ] **Step 5: commit** (Manager) `feat(scoring): the scorekeeper can adjust the game clock`; (fan) `test(clock): a negative pause total still gives the right time`

## Part C — halves, team fouls, man-down (futsal)

### Task 5: Shared rules, twinned in both apps

**Files:** Manager `lib/models/futsal_periods.dart` + `test/futsal_periods_test.dart`; fan `lib/misc/futsal_periods.dart` + `test/futsal_periods_test.dart`. The two code files are twins apart from imports, and the two test files are identical apart from imports.

**Interfaces:**
- `enum FutsalPeriod { firstHalf, halfTime, secondHalf, extraTime }` with `String get key` (`'1H'`, `'HT'`, `'2H'`, `'ET'`) and `static FutsalPeriod? fromKey(Object? raw)` (null when absent or unknown).
- `class FutsalPeriodInfo { final FutsalPeriod? period; final int? secondHalfStartMs; final int? extraTimeStartMs; static FutsalPeriodInfo fromGame(Map<dynamic, dynamic> game) }` (reads `Period` and `PeriodStarts`; tolerant of missing or malformed values).
- `FutsalPeriod eventPeriod(int? t, FutsalPeriodInfo info)`: the rule in the Data contract. Never returns `halfTime`.
- `int teamFoulsShown(Object? teamActivity, FutsalPeriodInfo info)`: the team's fouls for `info.period` (1H and HT → 1st half; 2H → 2nd half; ET → 2nd half + extra time; null period → 0). It reads the same List-or-Map minute buckets as the existing activity parsers, finds the event with `activityEventOf` (never `keys.first`), and counts type `Foul` case-insensitively.
- `sealed class FoulPenalty` with `FoulNone`, `FoulWarning`, `FoulManDown(Duration duration)`; `FoulPenalty foulPenaltyFor(int nthFoul)`.
- `Duration? manDownForCard(String type)`: `Yellow` / `SecondYellow` → 1:00; `Red` → 2:00; anything else null.
- `int manDownRemainingMs({required int durationMs, required int startElapsedMs, required int clockElapsedMs})`, clamped to `0..durationMs`.

- [ ] **Step 1: failing tests** (identical in both repos):
  - `foulPenaltyFor` for 1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14.
  - `eventPeriod`: before the 2H start; exactly at it; after the ET start; null `_t`; no starts at all.
  - `teamFoulsShown`: 1H counts only 1st-half fouls; HT shows the 1st-half count; a foul stamped during half time counts for the 1st half (Review Focus 5); 2H starts at 0 and counts only 2nd-half fouls; ET = 2nd half + extra time; a `Guest` foul counts; Yellow, Save and Goal do not; a null period gives 0; a List bucket and a Map bucket give the same answer.
  - `manDownForCard`, and `manDownRemainingMs` at start, mid-way, past the end and with a negative difference.
- [ ] **Step 2:** run in both repos, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run both test files.
- [ ] **Step 5: commit** in each repo `feat(futsal): shared half, team-foul and man-down rules`

### Task 6: Manager — halves on the game

**Files (Manager):** `lib/services/firebase/game_service.dart` (new `setGamePeriod`; a shared `activityStampNowMs()` used by `addActivity` and by the period stamps), `lib/core/constants/firebase_paths.dart`, `lib/models/game.dart` (parse `Period` / `PeriodStarts` into a `FutsalPeriodInfo`), `lib/services/game_finalize.dart` (`resetLeagueGame` also clears `Period`, `PeriodStarts`, `ManDown`), `lib/ui/futsal/update_futsal_game_detail_page.dart` (clock card), tests.

**Interfaces:**
- `Future<void> GameService.setGamePeriod(..., FutsalPeriod period)`: one update that writes `Period` and maintains `PeriodStarts`:
  - to `1H` or `HT`: remove `PeriodStarts`.
  - to `2H`: keep an existing `2H` stamp, else stamp now; remove the `ET` stamp.
  - to `ET`: keep or stamp `2H`; keep an existing `ET` stamp, else stamp now.
- Kickoff (`_startGame`) writes `Period: '1H'`.
- Clock card buttons, one at a time by the current period (a live game with no `Period` counts as `1H`):
  - `End 1st half` (in 1H): pauses the clock, then `setGamePeriod(halfTime)`.
  - `Start 2nd half` (in HT): `setGamePeriod(secondHalf)`, then resumes the clock. The clock keeps counting.
  - `Start extra time` (in 2H, only while the clock is paused): `setGamePeriod(extraTime)`, then resumes.
- `Correct the half` (in the card's menu): a dialog with the four choices that calls `setGamePeriod` only. It does not touch the clock.

- [ ] **Step 1: failing tests.**
  - Each button shows only in its period; `End 1st half` pauses and writes `HT`; `Start 2nd half` writes `2H` with a stamp and resumes.
  - `setGamePeriod` stamp rules: all four targets, including going back from `2H` to `HT` (stamps removed) and `2H` → `2H` (stamp kept).
  - **Review Focus 1:** an event recorded in the 2nd half is written as exactly `{<Type>: <player>, _t: <ms>}`, with no other key.
  - **Review Focus 2:** after `Start 2nd half` by mistake, `Correct the half` → `Half time` makes `teamFoulsShown` return the 1st-half count again.
  - Reset clears `Period`, `PeriodStarts` and `ManDown`.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement (futsal page only).
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(futsal): halves on the scoring screen`

### Task 7: Manager — team foul tally and the rulebook's alerts

**Files (Manager):** `lib/ui/futsal/update_futsal_game_detail_page.dart` (`_recordEvent`, the single write path, around :560-690; the tally next to each team's score), `lib/services/firebase/game_service.dart` (a one-shot read of one team's activity), tests.

**Interfaces:**
- Tally: `Fouls <n>` per team from `teamFoulsShown(...)` on the page's game. It is hidden when the game has no period.
- After `_recordEvent` has awaited its writes for a `Foul` while the game is live: count with `teamFoulsShown` on a **fresh read** of that team's activity (never the page's cached game, which may not include the new foul yet), then act on `foulPenaltyFor(n)`:
  - `FoulWarning` → the 5th-foul dialog.
  - `FoulManDown` → the man-down dialog, and Task 8's `startManDown` (Reason `TeamFouls`, `Foul: n`, `Player`: the fouling player).
- A foul on the `Guest` row counts like any other (fan-conduct and bench fouls).
- A foul that also draws a card starts two man-downs (one for the foul count, one for the card). The scorekeeper removes one if the referee rules it a single penalty.

- [ ] **Step 1: failing tests.** At kickoff both tallies read `Fouls 0`. The 5th foul shows the warning copy. The 6th shows the 1:00 copy and starts a man-down. The 7th shows nothing. The 10th shows the 2:00 copy. After `Start 2nd half` both tallies read `Fouls 0` and the yellow-card counts are unchanged (Review Focus 5). A `Guest` foul counts. Removing a foul with the event editor lowers the tally (Review Focus 5). No alert when the game is Final.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(futsal): per-half team fouls with the rulebook's warnings`

### Task 8: Manager — man-down timers

**Files (Manager):** `lib/services/firebase/game_service.dart` (`startManDown`, `endManDown`, `undoManDownEnd`; `setGameClockElapsed` from Task 4 gains the shift below), `lib/models/game.dart` (parse `ManDown`), new `lib/ui/futsal/man_down_panel.dart`, `lib/ui/futsal/update_futsal_game_detail_page.dart`, tests.

**Interfaces:**
- `Future<void> startManDown(..., {required int team, required String reason, int? foul, required String player, required int durationMs, required int startElapsedMs})` pushes under `ManDown`.
- `Future<void> endManDown(..., String id, String ended)` writes `Ended` (`'goal'` or `'removed'`). `Future<void> undoManDownEnd(..., String id)` removes `Ended`.
- `setGameClockElapsed` also adds its returned change to `StartElapsedMs` of every man-down that has no `Ended`, so an adjustment leaves each remaining time as it was.
- `ManDownPanel` under the clock, driven by the page's 1-second ticker:
  - A running man-down: `<Team> · <reason> · <player> · m:ss` with `Remove`.
  - One ended by `'goal'` or `'removed'` whose time would not have run out yet: shown dimmed with `Undo`.
  - Anything else is not listed.
- Triggers:
  - Task 7 (team fouls).
  - Recording `Yellow` or `SecondYellow` (1:00) or `Red` (2:00), through `manDownForCard`, while the game is live.
  - **Time up:** when a listed man-down's remaining time reaches 0, the time-up dialog shows once (the page remembers which ids it has announced). Nothing is written.
  - **Conceding:** when `_recordEvent` raises a team's score (`scorePoints > 0`; the scoring side is the page's existing `target`), the other team's **oldest** running man-down ends with `'goal'` and the conceded dialog shows.
  - **A removed foul:** when the event editor removes a `Foul` and a running `TeamFouls` man-down for that team has a `Foul` number above the team's new count, that man-down ends with `'removed'`.

- [ ] **Step 1: failing tests.**
  - The 6th foul creates a 1:00 row; a yellow 1:00; a red 2:00.
  - Pausing the clock freezes the countdown. `Adjust clock` by +1:00 and by −1:00 leaves the remaining time unchanged (Review Focus 3).
  - Reaching 0 shows the time-up copy exactly once and writes nothing.
  - A goal against a team with two running man-downs ends only the oldest (Review Focus 4). An own goal against the penalized team ends one too.
  - `Undo` on a goal-ended man-down makes it run again with the time it would have had (Review Focus 2); `Undo` is gone once that time has passed.
  - Removing the 6th foul ends its man-down (Review Focus 5).
  - No man-down starts when the game is not live.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(futsal): man-down timers for team fouls and cards`

### Task 9: Fan app — the half and team fouls on the game page

**Files (fan):** `lib/misc/league_adapters.dart` (`leagueMatchFromGameMap`, :75-129), `lib/model/tournamentmatch.dart` (a nullable `periodInfo`), the score header in `lib/league_match_detail.dart` (around the `LIVE` chip and `MatchClockText`, :228-250), tests.

**Interfaces:** `TournamentMatch.periodInfo` (`FutsalPeriodInfo?`, set only for a futsal league game whose node has a `Period`). In the header of a **live** futsal league game with a `periodInfo`: the half label under the clock, and `Fouls <n>` (`teamFoulsShown`) under each team. Nothing is added when the game is upcoming or Final, or when `periodInfo` is null.

- [ ] **Step 1: failing tests.**
  - Live, 1st half, 3 fouls for team 1 → `1st half`, `Fouls 3` and `Fouls 0`.
  - Half time → `Half time` with the 1st-half counts. 2nd half → `2nd half` with only 2nd-half fouls.
  - Final → no half label and no fouls.
  - **Review Focus 1:** a game without `Period` → the header is exactly as today. A game with `Period`, `PeriodStarts` and `ManDown` → the timeline shows only its real events.
  - A Basketball game → unchanged.
  - 360 px, light and dark: no overflow.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement. Read-only, on the stream the page already has.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(match): fans see the half and each team's fouls this half`

## Part D — the fan app requires the latest store version

How it works, in plain terms:
- **Android:** the app asks Google Play (its official in-app update check) whether an update is available to this phone. Play only says yes when this phone can really get it, staged rollouts included.
- **iPhone:** the app asks Apple's public lookup for the app's current store version. It requires the update when that version is newer than the installed one, was released at least 24 hours ago (Apple can take up to a day to offer a new release everywhere), and runs on this phone's iOS.
- **Pause switch:** `AppConfig/ForceUpdate/PausedUntil` (epoch ms). While now is before it, nobody is blocked. Absent or past means forced updates are on. The Manager sets it 7 days ahead, so a forgotten pause ends by itself.
- **It starts with this release.** Versions already in the stores have no update screen, so the first update that can be forced is the one after this.

### Task 10: Fan app — the update check and the "Update required" screen

**Files (fan):**
- Create `lib/update/update_decision.dart` (pure rules), `lib/update/store_update_check.dart` (the two store checks), `lib/update/update_gate.dart` (`UpdateGate`, `UpdateRequiredPage`).
- Modify `lib/main.dart` (read the cached block before `runApp`, next to the existing `SharedPreferences` read at :101; `MaterialApp(builder:)` wraps the app in `UpdateGate`), `pubspec.yaml` (`in_app_update`, the newest version that resolves with this project's Flutter and Android setup).
- Tests: `test/update/update_decision_test.dart`, `test/update/update_gate_test.dart`.

**Interfaces:**
- `bool isNewerVersion(String store, String installed)`: numeric compare of dotted versions (`5.10.0` is newer than `5.9.9`; `5.1` equals `5.1.0`; a `+build` suffix is ignored). Anything unparseable → false.
- `class IosStoreInfo { final String version; final DateTime? releasedAt; final String? minimumOsVersion; final String? storeUrl; static IosStoreInfo? fromLookupJson(String body); }` reads `results[0]` of Apple's lookup (`version`, `currentVersionReleaseDate`, `minimumOsVersion`, `trackViewUrl`); null when there is no result or the JSON is malformed.
- `const Duration kIosUpdateGrace = Duration(hours: 24);`
- `bool iosUpdateRequired({required String installedVersion, required String? deviceOsVersion, required IosStoreInfo? store, required DateTime now})`: true only when all of these hold: `store != null`; `isNewerVersion(store.version, installedVersion)`; `store.releasedAt != null` and `now − releasedAt >= kIosUpdateGrace`; and `store.minimumOsVersion` is null or `deviceOsVersion` is readable and not lower than it.
- `String? osVersionFrom(String platformVersionString)`: the first dotted number in `Platform.operatingSystemVersion` (e.g. `Version 17.5 (Build 21F79)` → `17.5`); null when there is none.
- `bool forceUpdatePaused(Object? forceUpdateNode, int nowMs)`: true only when the node is a Map whose `PausedUntil` is a number greater than `nowMs`.
- `class UpdateNeed { final bool required; final String? storeUrl; }` and `abstract class StoreUpdateChecker { Future<UpdateNeed> check(); Future<void> startUpdate(UpdateNeed need); }`.
  - `IosStoreUpdateChecker`: GET `https://itunes.apple.com/lookup?bundleId=<PackageInfo.packageName>&country=us` with `dart:io` `HttpClient` and a 5-second limit. If that has no result, it retries once with `id=<the digits after /id in StoreLinks.ios>`. Only the app's bundle id or store id is sent. `startUpdate` opens `need.storeUrl`, else `StoreLinks.ios` (`lib/misc/app_config.dart`), else `https://apps.apple.com/app/id1449327079`, in the external App Store app.
  - `AndroidStoreUpdateChecker`: `InAppUpdate.checkForUpdate()`. Required when `updateAvailability` is `updateAvailable` and `immediateUpdateAllowed`, or when an update this app started is in progress. `startUpdate` runs `InAppUpdate.performImmediateUpdate()`; if that throws, it opens `StoreLinks.android`.
  - Every exception and timeout in either checker → `UpdateNeed(required: false)`.
- `UpdateGate({required Widget child, required StoreUpdateChecker checker, required String installedBuild, String? cachedBlockedBuild, Stream<Object?>? pauseStates, DateTime Function()? now})`:
  - Blocked and not paused → shows `UpdateRequiredPage` in place of `child`. Otherwise shows `child`. The check never delays the first frame.
  - `cachedBlockedBuild == installedBuild` → starts blocked (a fan who was already told to update sees the screen at once, not the app first). The first check then confirms or clears it.
  - Checks at start and when the app comes back to the foreground: every time while blocked, otherwise at most once every 30 minutes.
  - When a check requires an update it saves `forceUpdate.blockedBuild` = the installed `version+build` in `shared_preferences`; when a check does not, it removes it. After the fan updates, the installed build differs, so the saved value no longer matches.
  - `pauseStates` defaults to the live `AppConfig/ForceUpdate` `onValue` stream. A stream error counts as not paused.
- `UpdateRequiredPage({required VoidCallback onUpdate, VoidCallback? onOpenStore})`: the app logo, the title, the body, `Update`, and on Android `Open Google Play`. No back or close control. It sits above the Navigator, so it must not use anything that needs one (no dialogs, no tooltips).

- [ ] **Step 1: failing tests.**
  - `update_decision_test.dart`:
    - `isNewerVersion`: `5.1.0` vs `5.0.0` true; `5.10.0` vs `5.9.9` true; `5.1` vs `5.1.0` false; `5.0.0` vs `5.0.0+30` false; `abc` vs `5.0.0` false.
    - `iosUpdateRequired` (Review Focus 6): newer and released 25 h ago → true; newer and released 2 h ago → false; same version → false; store older than installed → false; minimum iOS above the phone's → false; minimum iOS present but the phone's version unreadable → false; no release date → false; null store → false.
    - `IosStoreInfo.fromLookupJson`: a real-shaped body parses; `resultCount: 0` → null; malformed → null.
    - `forceUpdatePaused`: future → true; past → false; absent → false; not a number → false.
  - `update_gate_test.dart` (fake checker, injected streams):
    - required → the Update screen shows and the child is not in the tree; not required → the child shows.
    - the checker throws → the child shows (Review Focus 6).
    - paused while required → the child shows; the pause ends → the Update screen shows.
    - `Update` calls `startUpdate`.
    - coming back to the foreground re-checks, and the screen goes away when an update is no longer required.
    - `cachedBlockedBuild == installedBuild` → the Update screen is in the first frame; a different cached build → the child is.
    - 360 px, light and dark: no overflow. No back button on the screen.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement. Pick the checker by platform in `main.dart` (`Platform.isIOS` / `Platform.isAndroid`; any other platform gets a checker that never requires an update).
- [ ] **Step 4:** `flutter test` (whole suite), `flutter analyze`, and `flutter build apk --debug` once to prove the new package builds.
- [ ] **Step 5: commit** `feat(update): the app requires the latest store version`

### Task 11: Manager — the pause switch

**Files (Manager):** `lib/ui/settings/app_links_page.dart` (a card above the store links), a small pure helper next to it or in `lib/models/`, tests.

**Interfaces:**
- `bool forceUpdatePaused(Object? node, int nowMs)` (the twin of Task 10's) and `int forceUpdatePauseUntil(int nowMs)` → `nowMs + 7 days`.
- The card streams `AppConfig/ForceUpdate` live. Switch `Require the latest version` is ON when not paused.
  - Turning it OFF shows the pause dialog; `Pause` writes `PausedUntil` (from `serverNowMs()`).
  - While paused, the banner shows the date with `Turn back on`, which removes `AppConfig/ForceUpdate`.
  - Turning the switch ON does the same as `Turn back on`.

- [ ] **Step 1: failing tests.** No node → the switch is ON and no banner shows. OFF → the dialog with the exact copy; `Cancel` writes nothing; `Pause` writes a `PausedUntil` 7 days ahead. A paused node → the switch is OFF and the banner shows the date. `Turn back on` removes the node. A `PausedUntil` in the past → the switch is ON. Light and dark, no overflow on the tablet width.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(settings): a pause switch for the fan app's forced updates`

## Part E — owner feedback after the emulator trial (2026-11-16)

> **Status:** written 2026-11-16 on Opus 5.5 for **Fable review before any code is written** (owner chose "Fable reviews first"). Tasks 1–11 above are built and reviewed; Part E changes the Manager only (fan app untouched: fans never see man-downs).

### Owner decisions (Part E spec)

1. Owner, verbatim: "we want numbers under attendance as well"
2. Owner, verbatim: "when we end a first half or second half if there is a clock on a player down whether it is 1 minute or 2 mins, it should get removed automatically. i like that we have the remove button but i want it to remove automatically when we click end first half or end second half"
3. Owner, verbatim: "for goal situation with the other man down it gives the notification but it doesnt remove the countdown from the top part. it should remove it." (Today an ended man-down stays in the panel, dimmed, with `Undo`, until its time would have run out.)
4. Owner, verbatim: "we should have 10 second added to 1 min and 2 mins. so 2:10 or 1:10 because it takes time to communicate that to the referee and player leaving the field ... same goes for yellow card 1:10 and red card 2:10"
5. Owner, verbatim: "if a player commits 6th or 8th foul and receives a yellow card, the player is out for 1 min for committing the foul but the team is down a player for 2 mins because it is 1 min for the yellow and 1 min for 6th or 8th foul. now if the player commits the 10th, 12th, 14th, 16th, 18th the player is out for a minute but the team is down a player for 3 minutes, 1 min for the yellow card and 2 mins for committing 10 or more fouls in one half. obviously this resets for the 2nd half. if a player receives a straight red on 6th or 8th foul, the team is down a player 3 mins and obviously the player is completely out for the game. the player who received the yellow and out for a min can substitute to come in after serving one min but the team remains down a player for another minute. remember to add 10 second buffer."
6. Owner's choices (2026-11-16, multiple choice):
   - Red on the 10th+ foul: **4:10** (the times add up, 2 + 2, buffer once).
   - Buffer when a foul and a card stack: **one buffer** (2:10, 3:10, 4:10).
   - What counts as one incident: **the same player, within 1 minute** of game time, in either order (foul then card, or card then foul).
7. Owner, on fantasy (answered, no change): a yellow is −1 and a red −3 for every position in the live Season 16 config; a second yellow counts as a red.

### Data contract additions (Manager only)

`ManDown/<pushId>` gains two optional fields; old entries without them keep working:

| Field | Shape | Meaning |
|---|---|---|
| `Card` | `'Yellow'`, `'SecondYellow'` or `'Red'` | A card that is part of this man-down (alone, or stacked on a team-foul penalty). |
| `PlayerOutMs` | number | How long the penalized player must sit, from `StartElapsedMs`. Absent = the whole `DurationMs` (a foul-only man-down: "any player may come on in that spot" when it ends). For `Red` / `SecondYellow` the player is out for the game; `PlayerOutMs` is then absent and the row says so. |

`Ended` gains `'half'` (cleared by `End 1st half`, `Start extra time` or ending the game). `Reason` keeps meaning "what started it" (`'TeamFouls'`, `'Yellow'`, `'SecondYellow'`, `'Red'`).

Durations (rule time + one 10-second buffer per man-down, `kManDownBufferMs = 10000`):

| Incident | Team down (`DurationMs`) | Player out (`PlayerOutMs`) |
|---|---|---|
| 6th or 8th foul | 1:10 | (whole time) |
| 10th, 12th, … foul | 2:10 | (whole time) |
| Yellow | 1:10 | 1:10 |
| Second yellow | 1:10 | out for the game |
| Red | 2:10 | out for the game |
| 6th/8th foul + yellow | 2:10 | 1:10 |
| 10th+ foul + yellow | 3:10 | 1:10 |
| 6th/8th foul + second yellow | 2:10 | out for the game |
| 10th+ foul + second yellow | 3:10 | out for the game |
| 6th/8th foul + red | 3:10 | out for the game |
| 10th+ foul + red | 4:10 | out for the game |

**Stacking rule:** when a card is recorded for player P of team T (or a penalty foul for P), and T has a running man-down for the same P, started at most 60 seconds of game clock ago, that is not already stacked (it has a foul but no card, or a card but no foul), the new penalty is merged into it: `DurationMs` grows by the new penalty's rule time (no second buffer), `Foul` / `Card` are filled in, and `PlayerOutMs` is set from the table. One combined dialog replaces the two separate ones. Otherwise the new penalty starts its own man-down, as today.

**Conceding a goal** ends the whole man-down, stacked or not (rulebook §8: the team "may bring its fifth player back on"), and its countdown leaves the panel at once. **Owner confirmed 2026-11-16:** "yes when goal is scored the other team can bring a player in and time goes away plus the thing i mentioned on the top showing the count down."

### Global constraints (Part E additions)

- Copy, exactly (Manager):
  - Man-down row: `<Team> · <what> · #<n> <Player> · m:ss`, where `<what>` is `6th foul`, `Yellow`, `6th foul + yellow`, `10th foul + red`, etc. While the player's own time runs and is shorter than the team's, a second line: `Player can be replaced in m:ss`; for red / second yellow: `Player is out for the game`.
  - Stacked dialog (one dialog for the whole incident): `<Team>: one player down for <m:ss>. <Player> is out for <m:ss>.` or, for red / second yellow, `<Team>: one player down for <m:ss>. <Player> is out for the game.` The time shown is the countdown time (with the buffer).
  - Player's time up (only when it ends before the team's): `<Team>: <Player> can be replaced. Still one player down for <m:ss>.`
  - Undo after a man-down ends: a SnackBar `Man-down ended` with action `Undo`, shown for 8 seconds. Half-end clear: `Man-downs cleared` with `Undo`.
- The existing single-penalty dialog copy keeps the rule time (`One player down for 1:00.`); the countdown includes the buffer.
- Ended man-downs leave the panel immediately (no dimmed rows).

### Review Focus (Part E)

1. **The yellow is recorded 50 seconds after the 6th foul** (still one incident) and **70 seconds after** (two separate man-downs). Test in Task 14.
2. **The card comes first, then the 6th foul** for the same player within a minute: one stacked man-down. Test in Task 14.
3. **A goal against a team with a stacked man-down** ends the whole thing, and `Undo` brings back the whole stacked man-down with its remaining time. Test in Task 15.
4. **`End 1st half` with two running man-downs**, one of them stacked: both cleared, one SnackBar, `Undo` restores both. Test in Task 15.
5. **A clock adjust in the middle of a stacked man-down** moves both the team's and the player's countdowns together. Test in Task 14.

### Task 12: Jersey numbers on the attendance list

**Files (Manager):** `lib/ui/shared/attendance_widgets.dart` (`_AttendanceSheet`), its callers in the three `update_*_game_detail_page.dart` pages, tests.

**Interfaces:** the sheet takes `Map<String, String> numbers` like the Task 3 pickers and reuses Task 3's `jerseyLabel` / `sortByJersey` / `jerseyNumberOrNull` (`#<n> · <name>`, number order, unknown last).

- [ ] Step 1: failing tests: the sheet shows `#10 · Alpha Player`; no number → name only; number order; the attendance toggle still records by name.
- [ ] Step 2: run, expect FAIL. Step 3: implement for all three sports. Step 4: `flutter test`, `flutter analyze`.
- [ ] Step 5: commit `feat(scoring): jersey numbers on the attendance list`

### Task 13: The 10-second buffer

**Files (Manager):** `lib/models/futsal_periods.dart` (constant + a helper), the man-down start paths in `lib/ui/futsal/update_futsal_game_detail_page.dart`, tests.

**Interfaces:** `const int kManDownBufferMs = 10000;` and `int manDownDurationMs(Duration ruleTime)` = rule time + buffer. `foulPenaltyFor` / `manDownForCard` keep returning the RULE time (the fan twin is unchanged except for the new constant and helper, copied to keep the files twins).

- [ ] Step 1: failing tests: 6th foul → `DurationMs` 70000; 10th → 130000; yellow 70000; second yellow 70000; red 130000; the dialog copy still says `1:00` / `2:00`.
- [ ] Step 2–4 as usual (Manager + the fan twin copy, imports only).
- [ ] Step 5: commit `feat(futsal): man-downs get a 10-second buffer`

### Task 14: A foul and a card for the same player stack

**Files (Manager):** `lib/models/futsal_periods.dart` (pure stacking rules), `lib/models/game.dart` (`ManDownEntry` gains `card`, `playerOutMs`), `lib/services/firebase/game_service.dart` (a `stackManDown` update), `lib/ui/futsal/man_down_panel.dart`, the futsal page, tests.

**Interfaces:**
- `ManDownStack? stackTarget(List<ManDownEntry> running, {required int team, required String player, required bool isCard, required int clockElapsedMs})`: the entry to merge into, per the stacking rule, or null.
- `({int durationMs, int? playerOutMs}) stackedTimes({int? foulN, String? card})`: the table above (buffer once).
- `Future<void> GameService.stackManDown(..., String id, {int? foul, String? card, required int durationMs, int? playerOutMs})`: one update on that entry.
- The panel shows the second line from `PlayerOutMs`, and the player's time-up alert fires once per entry per device, writing nothing.
- A clock adjust already shifts `StartElapsedMs`, so both countdowns move together; no change needed beyond a test.

- [ ] Step 1: failing tests: every row of the durations table; card 50 s after the foul → stacked; 70 s → separate; card first then foul → stacked; a second card on an already-stacked entry → its own man-down; the player time-up alert at 1:10 on a 2:10 stack shows the copy once; red stack row says `Player is out for the game`; clock adjust mid-stack keeps both remaining times.
- [ ] Step 2–4 as usual. Step 5: commit `feat(futsal): a foul and a card for the same player stack into one man-down`

### Task 15: Ended man-downs leave the panel; halves clear them

**Files (Manager):** `lib/ui/futsal/man_down_panel.dart`, the futsal page (`End 1st half`, `Start extra time`, ending the game, conceding, `Remove`), `lib/services/firebase/game_service.dart` (end several in one update), tests.

**Interfaces:**
- The panel lists running man-downs only.
- `Remove`, conceding and half-end show the SnackBar with `Undo` for 8 seconds; `Undo` calls `undoManDownEnd` for each id it ended.
- `Future<void> GameService.endManDowns(..., List<String> ids, String ended)`: one multi-path update.
- `End 1st half`, `Start extra time` and ending the game end every running man-down with `'half'`.

- [ ] Step 1: failing tests: after a goal the countdown is gone from the panel and the SnackBar shows; `Undo` brings it back with the time it would have had; `End 1st half` clears two running ones in one update and one SnackBar, `Undo` restores both; ending the game clears them; `Start extra time` clears them; `Remove` behaves the same way.
- [ ] Step 2–4 as usual. Step 5: commit `feat(futsal): ended man-downs leave the panel; ending a half clears them`

---

## Rollout (each step needs the owner's go)

1. Manager build on the emulator for the owner to try on a test game (a friendly, or a game he resets afterwards). Never first on a real league game.
2. Manager on the tablet.
3. Fan app: merge into `zaya-review-fixes` with the League tab, No charge and the game-card fix, for Bronsin's store release. iPhone simulator checks:
   - the timeline without saves and defense plays;
   - the half and `Fouls n` on a live futsal game;
   - the Home top bar without the two buttons.
4. Order does not matter for safety. Until the new Manager is on the tablet, games have no `Period` and every fan app shows them as today. Once it is, store fan apps ignore the new fields.
5. Part D checks that need the real stores (they cannot be tested on the emulator or the iPhone simulator). For Bronsin, in the PR:
   - Android: install this build from a Play internal-testing track with a lower version than the live one. The Update screen shows, and `Update` runs Google Play's update.
   - iPhone: a TestFlight build with a lower version number than the App Store's shows the Update screen, and `Update` opens the App Store page. A build with the same or a higher number goes straight in.
   - Every store release must have a higher version number than the last.

## Not in this plan

- Tournament live scoring gets jersey numbers (Task 3) but not halves, team fouls or man-down. A follow-up can reuse Task 5's rules.
- Basketball and Flag Football halves or quarters.
- Editing the minute of an already-recorded event.
- Fans seeing man-down countdowns, and pushes about fouls or halves.
- Season-long yellow-card suspension tracking (6 yellows → 1-game ban).
- Part D: a softer "update available" reminder that can be dismissed; choosing a specific minimum version by hand; forcing Manager updates (the Manager is installed by hand on the owner's tablet).

## Fable review (2026-11-16)

Checked against both repos (fan `zaya-fantasy-league-tab` @ `6baff66`, Manager `zaya-no-charge` @ `bbc3e50`) and the server functions. Verdict: **approved with the amendments below, all written into the plan above.**

1. **The per-event half tag is gone (was the main defect).** The draft added a `_p` key to every event. Fan apps in the store turn every key except `_t` into a timeline row (`match_facts_tab.dart:90,120`), so each event would have grown a junk row reading "1H" or "2H" on every phone until it updated. The push server takes the first key that is not `_t` as the event type (`league_decide.ts:214`), so goal pushes could have misfired. The half is now derived from the `_t` stamp events already carry and a `PeriodStarts` stamp on the game. Reassigning an event keeps its `_t` (`game_service.dart:576`), so edits keep their half.
2. **No `Team foul` event type.** A new type would also show as an unknown row in store apps. The team's existing `Guest` row already records a foul without touching player stats, and it counts toward the tally.
3. **Adjusting the clock no longer changes penalty time.** In the draft a +1:00 correction would have ended a 1:00 man-down on the spot. Running man-downs now shift with the adjustment.
4. **Mistakes can be undone.** `Correct the half` fixes a wrong half button, and `Undo` restores a man-down ended by a mis-recorded goal or a wrong `Remove`.
5. **Simpler man-down bookkeeping.** Nothing is written when a man-down runs out, which removes the two-device double-write case. Its state is computed from the clock.
6. **Foul count read fresh.** The page's game is a cached read refreshed after each event, so the 5th/6th-foul check reads the team's events again after the write. Otherwise it could be one short.
7. **Clock details confirmed and tightened.** Adjusting through `PausedAccumMs` is right: the server treats `StartedAt` as the real kickoff time. Negative totals work in both apps' `elapsedAt`. `resumeGameClock` mixes the tablet's clock with server timestamps today; it now uses server time, in the league and tournament services.
8. **Fan header only while live.** The draft would have shown "2nd half" on a finished game.
9. **Extra time** continues the 2nd half's foul count (FIFA futsal). The rulebook has no extra time, so this is a default the owner can change.
10. **Checked and left as written:** the database rules let admins write anywhere under the sport node, so no rules change is needed; `ManDown` and period writes re-trigger the game functions, which compare scores and status and do nothing new; jersey numbers exist on league and tournament rosters (40 of 55 Season 16 players have one).
11. **Part D added on the owner's request (written by Fable, 2026-11-16).** Design choices:
    - The stores are the source of truth, so it runs with no step for the owner. A "minimum version" typed in by hand could lock everyone out if it were set before the store had the release.
    - It fails open everywhere, and iPhone waits 24 hours after a release, because the worst outcome of this feature is a fan who is told to update and cannot.
    - The only owner control is a pause that ends by itself after 7 days.
    - `AppConfig` already exists, is world-readable and admin-writable in both rules files, and already holds the store links (`AppConfig/StoreLinks`, App Store id 1449327079), so no rules or server change is needed.
    - The installed version comes from the running app (`PackageInfo`), not `pubspec.yaml`, because store builds carry their own version numbers.
