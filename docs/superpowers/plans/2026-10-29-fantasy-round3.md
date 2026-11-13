# Fantasy Round 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fantasy player profiles with weekly points/price history, a redesigned Players market and Leaderboards, a Fantasy tab on the Infinite profile, Manager "Fantasy profiles", and a replayed Season 15 test season to test it all on.

**Architecture:** The server's finalize/lock steps start saving per-player weekly records (`PlayerWeekStats`, `PriceHistory`, richer `PlayerTotals`); the fan app reads them through new parsers/streams and renders one shared full-screen player profile that every player tap opens. The Manager gets a new admin callable (`getUserContact`) plus per-manager streams. A tool built on the existing S15 rehearsal replay writes a full season into the paused test season.

**Tech Stack:** Flutter (fan: plain streams; Manager: Riverpod), Firebase RTDB, Cloud Functions v2 (TypeScript, vitest), url_launcher.

**Spec:** `docs/superpowers/specs/2026-10-29-fantasy-players-profiles-leaderboards-design.md` (+ mockups in `docs/superpowers/specs/assets/2026-10-29-fantasy-round3/`). Read both.

**Repos / branches:** fan `C:\Users\zayaa\StudioProjects\infinite_sports_flutter` (app + `functions/`), Manager `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`; both on `zaya-fantasy`, main checkouts (no worktrees). Commit locally; never push.

**Commands:** Flutter `C:\src\flutter\bin\flutter.bat`; functions tests `npm test` (vitest) from `functions/`; functions typecheck `npm run build` from `functions/`.

## Global Constraints

- No RTDB `.get()` in either Flutter app — streams (`onValue`) or `once()` only (Manager guard test `test/no_rtdb_get_guard_test.dart` must stay green).
- Every screen live: streams, not one-shot fetches (exception: `getUserContact` callable).
- Light + dark: colors from `Theme.of(context).colorScheme` or brightness-conditional pairs; no hard-coded light fills. Gold/green/red accents must read in both themes.
- Names wrap — never ellipsize, never underline (players, teams, managers).
- One fade reveal per screen when its data is ready; no piecemeal pop-in; session caches for instant revisits (follow existing `session*` static patterns).
- Destructive actions confirm. **Never delete a file** — if something becomes dead code, leave it and report it (the owner approves deletions).
- Email/phone never reach the fan app or any fan-readable node.
- Test fill: writes only under `Fantasy/Futsal/15/`; refuses unless effective lock override is `open`/`locked` AND `Config/lockOverrideUntil` is absent.
- Finalize reruns stay idempotent (same inputs → identical writes).
- No new chart package; bars are plain widgets.
- Commit message trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Two players with the same name on different teams** — the account link must match team + name; ambiguous → no "See full profile" (never the wrong person). Test in Task 4.
2. **A player with no games / a player added mid-season** — no weeks or zero games: PPG renders "—" (never NaN/"0.0"), form bars show only existing weeks, profile never crashes. Tests in Task 1 (`ppg` 0 when 0 games) and Task 5.
3. **A voided week in the middle of the season** — excluded from form (the 3 most recent NON-voided weeks), shown as "Week voided — 0" in Matches, price row still listed. Tests in Task 1 and Task 5.
4. **Long names at phone width (360 px)** — market rows, risers/fallers card and two-line leaderboard cells wrap without overflow in light and dark. Widget tests in Tasks 6 and 8.
5. **Fake test managers / users with no account data** — leaderboard shows team name alone; Manager profile shows "No account"; `getUserContact` on an unknown uid returns `{email: null, signInMethods: []}` instead of throwing. Tests in Tasks 2, 8, 11.

---

## Track A — fan repo (Tasks 1–9, sequential)

### Task 1: Per-player weekly records + richer PlayerTotals (functions)

**Files:**
- Modify: `functions/src/lib/fantasy/scoring.ts`, `lib/fantasy/engine/scoring.dart` (fan Dart twin)
- Modify: `functions/src/lib/fantasy/finalize_core.ts`, `functions/src/lib/fantasy/orchestration.ts` (finalize reads/writes, ~L540–673)
- Modify: `functions/src/lib/fantasy/stats_mapper.ts` (export the existing score reader)
- Test: `functions/src/lib/fantasy/finalize_core.test.ts`, `functions/src/lib/fantasy/scoring.test.ts`, `test/fantasy/scoring_test.dart`

**Interfaces:**
- Produces (TS): `type ScoreKey = 'plays'|'goals'|'assists'|'cleanSheet'|'saves'|'penSaved'|'penMissed'|'conceded'|'dpl'|'yellow'|'red'|'ownGoals'`; `ScoreLine { label; points; key: ScoreKey; count: number }`. Count: plays 1, goals `s.goals`, assists `s.assists`, cleanSheet 1, saves `s.saves`, penSaved `s.penSaved`, penMissed `s.penMissed`, conceded `s.teamConceded`, dpl `s.dpl`, yellow `s.yellows`, red `s.reds`, ownGoals `s.ownGoals`. Labels/points unchanged.
- Produces (Dart twin): `ScoreLine(this.label, this.points, {required this.key, required this.count})` with the same keys/counts.
- Produces (TS): `interface PlayerWeekStatsEntry { Pts: number; Played: boolean; GP: number; Games: Array<{Vs: string; For: number; Against: number; Forfeit?: 'won'|'lost'}>; Lines?: Record<string, {N: number; P: number}>; Voided?: true }` — `Lines` keys are the ScoreKeys plus `'bonus'` (N = P = bonus points); zero lines omitted; `GP` = games played (= `Lines.plays.N`, 0 when none). Voided week: no `Lines`, `Pts: 0`, `Voided: true`.
- `MarketPlayer` gains `teamName?: string` (orchestration fills it from `Players/<name>/teamName`). `Games` = this week's games where `team1`/`team2` == teamName; `For`/`Against` from that team's perspective via the mapper's score reader; `Forfeit` from `forfeitedBy`.
- `FinalizeInput` gains `playedGamesByWeek: Record<number, Record<string, number>>` (other weeks' `GP`, read from `PlayerWeekStats`). `FinalizeOutput` gains `playerWeekStats: Record<string, PlayerWeekStatsEntry>`; `playerTotals` entries become `{points, ownershipPct, form, ppg, games}`:
  - `form` (tenths) = round(10 × mean of Pts over the 3 highest-numbered NON-voided weeks in `playerWeeksByWeek ∪ {gw}`; a player missing from a week = 0; fewer than 3 weeks → mean of those; 0 weeks → 0).
  - `games` = Σ GP over non-voided weeks; `ppg` (tenths) = games == 0 ? 0 : round(10 × points / games).
- Orchestration writes `PlayerWeekStats/<gw>` (one `db.write` of the whole week node, next to the `PlayerWeeks/<gw>` write).

- [ ] **Step 1: Failing tests** — in `scoring.test.ts`: `it('every line carries a stable key and count')` (a game with goals 2, assists 1, yellows 1 → lines keyed `plays`(count 1), `goals`(2), `assists`(1), `yellow`(1)). In `finalize_core.test.ts`:
  - `it('PlayerWeekStats lines sum to Pts for every player in the golden week')` — replay `test/fantasy/fixtures/golden_gameweek.json`; for each player `Σ Lines.P === Pts === playerWeeks[name]`.
  - `it('PlayerWeekStats Games lists opponent and score from the player team view')` — team A 4–2 B: A player `Games[0] = {Vs:'B', For:4, Against:2}`.
  - `it('voided week writes Pts 0, Voided true, no Lines')`.
  - `it('player with no game this week: {Pts:0, Played:false, GP:0, Games:[]}')`.
  - `it('form averages the 3 latest non-voided weeks')` — weeks 1..5 Pts [2,4,6,8,10], week 4 voided → form = round(10×(10+6+4)/3) = 67.
  - `it('ppg is 0 when no games')` and `it('ppg = round(10 × points / games)')` — points 23, games 4 → 58.
  - `it('rerun is identical')` — run finalize twice on the same input, deep-equal outputs (existing helper if present).
- [ ] **Step 2:** `npm test` from `functions/` → new tests FAIL.
- [ ] **Step 3:** Implement per Interfaces (TS scoring + finalize_core + orchestration + Dart twin). Golden fixture comparisons: if they compare breakdown objects strictly, extend the expected data with `key`/`count` rather than loosening the comparison.
- [ ] **Step 4:** `npm test` and `npm run build` in `functions/` → all PASS; `flutter test test/fantasy` → PASS.
- [ ] **Step 5: Commit** `feat(fantasy-fn): per-player weekly records (PlayerWeekStats) + form/ppg/games on PlayerTotals`.

### Task 2: PriceHistory at lock, getUserContact callable, rules (functions)

**Files:**
- Modify: `functions/src/lib/fantasy/orchestration.ts` (`snapshotPublishedPicks` ~L1013 or the lock step that calls it)
- Create: `functions/src/user_contact.ts` (thin callable) + `functions/src/lib/user_contact.ts` (pure logic) + `functions/src/lib/user_contact.test.ts`
- Modify: `functions/src/fantasy_messages.ts` (export the existing admin gate so `user_contact.ts` reuses it), `functions/src/index.ts`
- Modify: `database.rules.stage1.json`, `database.rules.json`
- Test: `functions/src/lib/fantasy/orchestration.test.ts` (or the existing lifecycle test file)

**Interfaces:**
- Lock writes `PriceHistory/<gw>` = `{<name>: priceTenths}` for every `Players` entry via `db.writeIfAbsent` — its OWN once-only claim, done before the "no squads to snapshot" early return (a week with no squads still records prices).
- `getUserContactCore(auth: {getUser(uid): Promise<{email?: string; providerData: Array<{providerId: string}>}>}, uid: string) → Promise<{email: string|null; signInMethods: string[]}>`; user-not-found → `{email: null, signInMethods: []}`. `signInMethods` = providerIds (`'password'`, `'google.com'`, `'apple.com'`).
- Callable `getUserContact` (`onCall`, request `{uid: string}`), admin-gated (Admins/<auth.uid> === true), exported from `index.ts`.
- Rules (BOTH files, inside `Fantasy/$sport/$season`): `PlayerWeekStats` `.read: true`; `PriceHistory` `.read: true`; `Watchlists/$uid` `.read`/`.write` `auth.uid === $uid`, children `$name` validate `newData.val() === true && $name.length <= 60`; `TransferCosts` `.read` admin (same admin expression the file already uses).

- [ ] **Step 1: Failing tests** — `it('lock snapshots PriceHistory once, even with no squads')`; `it('PriceHistory is not overwritten by a later sweep after a price edit')`; `user_contact.test.ts`: `it('returns email and provider ids')`, `it('unknown uid returns null email and empty methods')`.
- [ ] **Step 2:** `npm test` → FAIL.
- [ ] **Step 3:** Implement; edit both rules files identically for these nodes.
- [ ] **Step 4:** `npm test`, `npm run build` → PASS; validate rules JSON parses (`node -e "JSON.parse(require('fs').readFileSync('database.rules.json'))"` and stage1).
- [ ] **Step 5: Commit** `feat(fantasy-fn): PriceHistory at lock, getUserContact admin callable, rules for new nodes`.

### Task 3: Test-season fill tool (functions/tools)

**Files:**
- Modify: `functions/tools/rehearse_s15.ts` (export the replay as a function; parameterize manager count; no behavior change for `rehearse:s15`)
- Create: `functions/tools/fill_test_season.ts`, `functions/tools/fill_test_season_logic.ts`, `functions/tools/fill_test_season_logic.test.ts` (ensure vitest picks it up, or place the test under `src/` importing from tools — builder's call, but it must run in `npm test`)
- Modify: `functions/package.json` (script `fill:s15`)

**Interfaces:**
- `export async function runReplay(opts: {offline: boolean; managerCount: number; extraManagers?: Record<string /*uid*/, unknown /*raw squad*/>}): Promise<{state: Record<string, unknown> /* final Fantasy/Futsal/15 subtree */; skippedManagers: Array<{uid: string; reason: string}>}>`. Existing `rehearse:s15` keeps 6 managers and its report unchanged.
- Fake managers: uids `test-01`…`test-20`, deterministic seeded squads/chips/transfers (reuse the rehearsal's strategies, cycling), team names from a fixed list of 20 fun names (≤ 30 chars), `Managers/<uid> = {TeamName, NameFlagged:false}`.
- Real managers: every uid in live `Squads` (today 1) with its saved squad held every week; rejected → listed in `skippedManagers` and printed.
- Pure logic (`fill_test_season_logic.ts`):
  - `buildWritePlan(state, live: {config, managers, squads}) → Array<{path: string; value: unknown}>` — whole-node writes for: Players, PlayerTotals, PlayerWeeks, PlayerWeekStats, PriceHistory, PriceChanges, Leaderboards, History, PublishedPicks, DreamTeam, TransferState, TransferCosts, GwState, LockedPositions, Repriced, RecapSent, NewsDrafted, ReminderSent, and any other once-only guard node present in `state`; child-level writes `Managers/test-NN`, `Squads/test-NN`; marker `TestFill = {At, Managers: 20}`. Never: `Config`, `News`, `Managers/<real>`, `Squads/<real>`.
  - `assertSafePaths(plan)` — throws unless every path starts with `Fantasy/Futsal/15/`.
  - `assertEnginePaused(config)` — throws unless `lockOverride` ∈ {open, locked} and `lockOverrideUntil` absent.
- CLI: default = dry run (prints each path + JSON size + skipped managers); `--apply` = backup every target node (GET) to `functions/tools/rehearsal_out/fill_backup_<ISO>.json` then PUT each; `--clear <backupFile>` = restore every backed-up node (PUT original, DELETE when it was absent) and DELETE `Managers/test-*`, `Squads/test-*`, `TestFill`. Auth: OAuth access token from the firebase-tools refresh token in `~/.config/configstore/firebase-tools.json` (same exchange as `rehearse_s15` docs / scratchpad pattern); never print the token.

- [ ] **Step 1: Failing tests** — `it('write plan never touches Config, News, or real managers')`; `it('assertSafePaths rejects anything outside Fantasy/Futsal/15')`; `it('assertEnginePaused rejects auto and rejects an auto-return time')`; `it('20 fake managers with deterministic team names')` (two runs → identical plan for Managers/Squads).
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `npm test`, `npm run build`, then `npm run rehearse:s15 -- --offline` still reports 17/17 invariants and `npm run fill:s15` (dry run, offline snapshot) prints a plan without writing.
- [ ] **Step 5: Commit** `feat(fantasy-tools): fill the paused test season with a replayed season (dry-run/apply/clear)`.

### Task 4: Fan data layer

**Files:**
- Create: `lib/fantasy/data/player_week_stats.dart`, `lib/fantasy/data/next_game.dart`, `lib/fantasy/data/player_account_link.dart`, `lib/fantasy/data/fantasy_season_resolver.dart`
- Modify: `lib/fantasy/data/fantasy_parsers.dart` (`playerTotalsFromNode` new fields), `lib/fantasy/data/fantasy_service.dart`
- Test: `test/fantasy/player_week_stats_test.dart`, `test/fantasy/next_game_test.dart`, `test/fantasy/player_account_link_test.dart`, `test/fantasy/fantasy_parsers_test.dart`

**Interfaces:**
- `class PlayerWeekStats {final int points; final bool played; final int gamesPlayed; final List<PlayerWeekGame> games; final Map<String, ScoreSourceLine> lines; final bool voided;}`; `class PlayerWeekGame {final String vs; final int goalsFor; final int goalsAgainst; final String? forfeit;}`; `class ScoreSourceLine {final int count; final int points;}`; `PlayerWeekStats? playerWeekStatsFromNode(Object? raw)` (tolerates List/Map coercion like other parsers).
- `String scoreSourceLabel(String key)`: plays "Played", goals "Goals", assists "Assists", cleanSheet "Clean sheets", saves "Saves", penSaved "Penalty saves", penMissed "Penalty misses", conceded "Goals conceded", dpl "Defensive plays", yellow "Yellow cards", red "Red cards", ownGoals "Own goals", bonus "Bonus"; unknown key → the key.
- `FantasyPlayerTotals` gains `int? formTenths, int? ppgTenths, int? games` (null when absent → UI shows "—").
- `FantasyService`: `watchPlayerWeekStatsFor(String sport, String season, String name, List<int> weeks) → Stream<Map<int, PlayerWeekStats>>` (one listener per week at `PlayerWeekStats/<gw>/<name>`, merged like `watchChipHistoryFor`); `watchPriceHistory(sport, season) → Stream<Map<int, Map<String, int>>>`; `watchAllPriceChanges(sport, season) → Stream<Map<int, Map<String, int>>>` (ignore the `Manual`/`Voided` flag keys); `watchWatchlist(sport, season, uid) → Stream<Set<String>>`; `Future<void> setWatchlisted(sport, season, uid, name, bool on)` (true → set `true`, false → remove).
- `class NextGame {final String opponent; final DateTime date; final String timeText; final bool placeholder;}`; `NextGame? nextGameForTeam(String team, List<TournamentMatch> matches, DateTime now)` — earliest non-final match on/after today's date involving `team`; `String formatNextGame(NextGame g)` → `"vs Nimrod · Sun 3 PM"` (time via the existing `gameTimeText` convention; placeholder opponents → `"Playoffs · Sun"`).
- `String? uidForFantasyPlayer(FantasyPlayer p, Map<String, List<TournamentPlayer>> rostersByTeam)` — roster entry with same team AND name; `'0'`/empty uid → null. `FantasyPlayer? fantasyPlayerForUid(String uid, List<FantasyPlayer> players, Map<String, List<TournamentPlayer>> rostersByTeam)` — null if 0 or >1 matches. (Use whatever team-keyed shape `LeagueService.watchRosters` already yields; adapt the parameter type to it.)
- `Future<({String sport, String season})?> resolveCurrentFantasySeason()` — the home banner / search hub resolution (current league's current season if it has a Fantasy `Config`), else the newest season under `Fantasy/<sport>` with a `Config`; `once()` reads only.

- [ ] **Step 1: Failing tests** — parser round-trips (incl. voided entry, missing Lines); `scoreSourceLabel` table; `nextGameForTeam` (skips finals, picks earliest future, placeholder); **Review Focus 1:** `test('same name on two teams links only the matching team')` and `test('ambiguous uid match returns null')`; `playerTotalsFromNode` reads form/ppg/games and leaves them null on old-shape nodes.
- [ ] **Step 2:** `flutter test test/fantasy` → FAIL. **Step 3:** implement. **Step 4:** PASS + `flutter analyze lib/fantasy` clean.
- [ ] **Step 5: Commit** `feat(fantasy): data layer for weekly records, price history, watchlist, next game, account link`.

### Task 5: Fantasy player profile page

**Files:**
- Create: `lib/fantasy/profile/fantasy_player_profile_logic.dart`, `lib/fantasy/profile/fantasy_player_profile_page.dart` (+ small widget files under `lib/fantasy/profile/` as needed: hero, stat strip, form bars, tabs)
- Test: `test/fantasy/fantasy_player_profile_logic_test.dart`, `test/fantasy/fantasy_player_profile_page_test.dart`

**Interfaces:**
- Consumes Task 4 types and `market_logic.dart` add availability (`MarketAddAvailability` + its reason text).
- `FantasyProfileModel buildProfileModel({required FantasyPlayer player, FantasyPlayerTotals? totals, required Map<int, PlayerWeekStats> weeks, required Map<int, Map<String, int>> priceHistory, required Map<int, Map<String, int>> priceChanges})` with: `int? latestMoveTenths` (from the highest gw in priceChanges; null when none — 0 means "No change" only if that week exists without an entry for him), `List<FormBar> formBars` (last 6 weeks present, oldest→newest, `{gw, points, voided}`), `List<SourceTotal> sourceTotals` (season Σ per key over non-voided weeks, sorted by |points| desc, zero-point keys dropped), `List<MatchRow> matchRows` (newest first: `{gw, opponentsText, points, seasonToDate, lines, voided}`; seasonToDate excludes voided weeks), `List<PriceRow> priceRows` (per gw in priceHistory: `{gw, priceTenths, moveAfterTenths?}`), `int? startPriceTenths, highTenths, lowTenths`.
- `class FantasyPlayerProfilePage extends StatefulWidget` — `({required String sport, required String season, required String playerName, SquadDraftController? draft, bool fromOutsideHub = false})` plus stream test seams following the hub's convention; `Future<void> openFantasyPlayerProfile(BuildContext context, {required String sport, required String season, required String playerName, SquadDraftController? draft, bool fromOutsideHub = false})`.
- Layout and copy per spec §4 and the profile mockup: hero (photo + gradient; initials over team colour without photo), team logo badge, star (watchlist; signed-out → hidden), stat strip (price + "▲ $0.5M this week" / "▼ $0.5M this week" / "No change" / nothing), tabs Overview · Stats · Matches · Price, bottom bar Add to Team / Remove (draft rules; reason line when unavailable) or **Open in Fantasy** when `fromOutsideHub`, plus **See full profile** (`openPlayerProfileById`) only when `uidForFantasyPlayer` returns a uid. Empty copy: before any finalized week "Points start after Gameweek 1"; Matches/Price friendly empty states. PPG/form "—" when `games` is 0/null.

- [ ] **Step 1: Failing tests** — logic: source totals sum; seasonToDate skips voided; formBars capped at 6; price rows high/low/start; **Review Focus 2:** `test('player with no weeks builds an empty model without errors')`; **Review Focus 3:** `test('voided week shows in match rows as voided and is excluded from totals')`. Page: renders name/price/tabs from seams; "See full profile" hidden without uid; Add button calls the draft; dark theme pumps without overflow at 360×780.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** `flutter test test/fantasy` PASS.
- [ ] **Step 5: Commit** `feat(fantasy): full-screen fantasy player profile (overview/stats/matches/price)`.

### Task 6: Players market redesign

**Files:**
- Modify: `lib/fantasy/hub/market_logic.dart`, `lib/fantasy/hub/players_tab.dart`
- Create: `lib/fantasy/hub/price_movers_card.dart`
- Test: `test/fantasy/market_logic_test.dart`, `test/fantasy/players_tab_test.dart`

**Interfaces:**
- `enum MarketSort { points, form, price, ownership }`; `composeMarket(...)` gains `required bool descending`, `Set<String> watchlist = const {}`, `bool watchlistOnly = false` (keep its other parameters); Total Pts is the default once totals exist, else Price; `sessionSort` + new `sessionDescending` statics; tapping the active sort flips direction. Name A–Z removed.
- `class PriceMovers {final Map<String /*GK|DEF|ATT*/, List<PriceMove>> risers; final Map<String, List<PriceMove>> fallers;}`; `PriceMovers computePriceMovers(Map<String, int> latestChanges, List<FantasyPlayer> players, Map<String, FantasyPlayerTotals>? totals, {String? position})` — top 2 per position by |delta|, ties by season points desc then name; `position` set → only that key.
- Row per spec §5 (photo 44, name wraps, "POS · Team", next game line, price over points, move icon over owned %, existing add control). `PriceMoversCard` (Price Risers | Price Fallers columns, grouped GK/DEF/ATT, "View all" sheet of every latest move); hidden without a reprice. ★ chip filters to the watchlist. Every row/mover tap → `openFantasyPlayerProfile`.

- [ ] **Step 1: Failing tests** — sorts (each key, both directions, ties by name); watchlist filter; `computePriceMovers` (per position top 2, ties, position filter); **Review Focus 4:** widget test 360 px wide, long name + long team, light and dark, `tester.takeException()` is null.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(fantasy): Players market — sorts, Price Risers/Fallers by position, watchlist, next game`.

### Task 7: Every player tap opens the profile

**Files:**
- Modify: `lib/fantasy/hub/fantasy_hub_page.dart` (`_openPlayerFromNews` → profile), `lib/fantasy/hub/news_player_card.dart` (unchanged callback contract), `lib/fantasy/hub/squad_picker_sheet.dart` (court chip action sheet: first item "Player profile"), `lib/fantasy/hub/manager_squad_viewer.dart` + `lib/fantasy/hub/dream_team_card.dart` (`onSlotTap` → profile), `lib/fantasy/match/match_fantasy_tab.dart` (`_PointsRow` tap → profile)
- Test: extend the existing tests for those widgets

**Interfaces:** Consumes `openFantasyPlayerProfile` (Task 5). `market_player_sheet.dart` stops being opened anywhere — **do not delete it**; report it as dead code.

- [ ] **Step 1: Failing tests** — one per entry point asserting the profile route is pushed for the tapped name (use the existing seams / a `profileOpener` injection where a widget has no seam).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(fantasy): every player tap in Fantasy opens the player profile`.

### Task 8: Leaderboards redesign

**Files:**
- Modify: `lib/fantasy/hub/leaderboard_logic.dart`, `lib/fantasy/hub/leaderboard_rows.dart`, `lib/fantasy/hub/leaderboards_tab.dart`, `lib/fantasy/hub/rules_tab.dart` (drop the mini-leagues "coming" FAQ copy)
- Test: `test/fantasy/leaderboard_logic_test.dart`, `test/fantasy/leaderboards_tab_test.dart`

**Interfaces:**
- Row data gains separate `String? realName` (PublicProfiles first + last) and `String? teamName` (unflagged TeamName); display: realName primary + teamName secondary; no realName → teamName alone; neither → "Unnamed manager".
- `const bool kShowMiniLeagues = false;` in `leaderboards_tab.dart` gates the "My Leagues" segment, its subscription and `_ready` condition; mini-league code stays.
- Podium removed: `RankedLeaderboardList` renders plain rows (rank, movement cell, avatar, two-line name, points); Overall movement cell: ▲n green / ▼n red / — muted (movement null or 0 → —); Gameweek scope has no movement cell. Own row gold highlight + existing pinned-row behaviour kept.

- [ ] **Step 1: Failing tests** — names (real+team, team only, flagged fallback); movement cell text/colour for +2/−1/0/null; segments are exactly Overall + Gameweek; **Review Focus 5:** fake manager (no PublicProfiles) shows team name only; **Review Focus 4:** 360 px long names light/dark no overflow.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(fantasy): leaderboards — movement column, manager + team names, mini-leagues hidden`.

### Task 9: Fantasy tab on the Infinite profile

**Files:**
- Modify: `lib/profile/profile_page.dart` (third tab when applicable)
- Create: `lib/profile/fantasy_profile_tab.dart`
- Test: `test/profile/fantasy_profile_tab_test.dart`

**Interfaces:** Consumes `resolveCurrentFantasySeason`, `fantasyPlayerForUid`, `buildProfileModel`, `openFantasyPlayerProfile(fromOutsideHub: true)`, `ManagerSquadViewerPage`. Tab shown only on full (uid) profiles when the uid is a fantasy player and/or a fantasy manager (`Managers/<uid>`) of the resolved season. Player section: price + move, total pts, form, owned %, last-6 bars, **Open in Fantasy**. Manager section: team name, overall rank + movement + points, **View team**.

- [ ] **Step 1: Failing tests** — tab absent when neither; player-only, manager-only and both render the right sections; limited profile has no tab.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** full `flutter test` PASS + `flutter analyze` clean (allow the known-slow analyzer).
- [ ] **Step 5: Commit** `feat(profile): Fantasy tab on the Infinite profile`.

---

## Track B — Manager repo (Tasks 10–11, sequential; may run in parallel with Track A)

### Task 10: Manager data for fantasy profiles

**Files:**
- Create: `lib/fantasy/data/fantasy_profile_models.dart`
- Modify: `lib/core/constants/fantasy_paths.dart`, `lib/services/firebase/fantasy_admin_service.dart`, `lib/providers/fantasy_admin_provider.dart`, `lib/providers/user_provider.dart` (single-user stream), `lib/services/firebase/user_service.dart`
- Test: `test/fantasy/fantasy_profile_models_test.dart`

**Interfaces:**
- `userStreamProvider = StreamProvider.family<MyUser?, String>` streaming `Users/<uid>` (null when absent).
- `class UserContact {final String? email; final List<String> signInMethods;}`; `FantasyAdminService.getUserContact(String uid) → Future<UserContact>` calling the `getUserContact` callable (Task 2: request `{uid}`, response `{email, signInMethods}`).
- Parsers (ported from the fan `fantasy_parsers.dart` shapes): `Map<String, OverallStanding> overallFromNode(Object? raw)` (`{points, rank, movement?}`); `ManagerSquadView? managerSquadFromNode(Object? raw)` → picks `{playerId, isCaptain, isVice, isBench}` + `chip?`; `List<ManagerWeekRow> managerWeeksFromHistory(Object? historyRaw, Object? costsRaw, String uid)` → `{gw, points (TotalTenths truncated /10), hitPoints, chip?, voided}` sorted by gw; `FantasyTransferState` full shape `{free, usedThisGw, chipPlayed?, savedGw?}`.
- Providers (`StreamProvider.family` keyed like the existing ones): `fantasyOverallProvider(FantasySeasonRef)`; `fantasyManagerWeeksProvider((FantasySeasonRef, String uid))` (streams `History` + `TransferCosts`); `fantasyManagerSquadProvider((FantasySeasonRef, String uid, int? gw))` (`PublishedPicks/<gw>/<uid>` when the current week is locked, else `Squads/<uid>`); `fantasyManagerTransferStateProvider((FantasySeasonRef, String uid))`.

- [ ] **Step 1: Failing tests** — each parser with real-shaped samples (incl. voided week, missing movement, chip, hit points); `managerWeeksFromHistory` ignores other uids.
- [ ] **Step 2:** FAIL. **Step 3:** implement (streams only; guard test stays green). **Step 4:** `flutter test` PASS.
- [ ] **Step 5: Commit** `feat(fantasy): Manager data for fantasy profiles (standings, weeks, squad, contact callable)`.

### Task 11: Manager "Fantasy profiles" UI

**Files:**
- Modify: `lib/ui/fantasy/fantasy_section_page.dart` (tile title "Fantasy profiles", subtitle "Who's playing — contact, squads, flag names"), `lib/ui/fantasy/fantasy_team_names_page.dart` (list), `lib/router/app_router.dart` (`names/:uid`)
- Create: `lib/ui/fantasy/fantasy_profile_detail_page.dart`
- Test: `test/fantasy/fantasy_widgets_test.dart` (extend), `test/ui/fantasy/fantasy_profile_detail_page_test.dart`

**Interfaces:** Consumes Task 10. List rows: photo (`NewsPlayerAvatar`-style fallback), real name, team name, `#rank · N pts`, flagged badge, Flag/Unflag button (existing confirm); search field (real or team name, case-insensitive); order flagged → overall rank → unranked by name. Detail per spec §8: header; Contact (email or "Not available", "Signs in with Google / Apple / email", phone, member since, **Call** `tel:`, **Text** `sms:`, **Email** `mailto:` — buttons disabled when the value is missing); Fantasy (rank, movement, points, this week's squad grouped GK/DEF/ATT with C/V and bench, weeks table, free transfers left, chips used, first gameweek played). No `Users` record → "No account" in Contact, everything else still renders.

- [ ] **Step 1: Failing tests** — list sort/search; tile renamed; detail renders contact from fakes; **Review Focus 5:** `testWidgets('fake test manager shows No account')`; Call/Email disabled without values; dark theme no overflow.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** full `flutter test` PASS (incl. guard test).
- [ ] **Step 5: Commit** `feat(fantasy): Manager Fantasy profiles — real person, contact, fantasy season at a glance`.

---

## Task 12: Ship to the test devices (controller, after both tracks)

- [ ] Functions: `npm test`, `npm run build`; deploy `npx --no-install firebase deploy --non-interactive --only functions:getUserContact,<fantasy functions touched>,database` from the fan repo (stage-1 rules file is what `firebase.json` points at). Check logs for errors.
- [ ] Confirm live `Fantasy/Futsal/15/Config` is Open/Locked with no `lockOverrideUntil`; run `npm run fill:s15` (dry run) → review plan; then `npm run fill:s15 -- --apply`; keep the backup file path for the S16 wipe.
- [ ] Build + install: fan debug APK → emulator-5554; Manager debug APK → tablet 10.0.0.146:5555.
- [ ] Update memory `infinite_fantasy_plan.md`; report to the owner with a plain test walkthrough + iOS verify list (url_launcher tel/sms/mailto, profile hero image, new ProfilePage tab, watchlist write) + the dead-code note for `market_player_sheet.dart`.
