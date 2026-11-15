# Fantasy Hub "League" Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** written 2026-11-15 on Opus 5.5. **Reviewed, amended and APPROVED by Fable 5.2 on 2026-11-15** (see "Fable review" at the end). Ready to build.

**Goal:** Give the Fantasy Hub a "League" tab that shows the associated league season's fixtures and standings table, so fantasy players can see who plays whom while picking players without leaving the Hub.

**Architecture:** A new `FantasyLeagueTab` shows the two existing league widgets (`LeagueFixturesTab`, `LeagueTableTab`) behind a Fixtures / Table switch. Its data comes from the Hub's shared-feed pattern (`lib/fantasy/data/fantasy_schedule_feed.dart`): the existing `FantasyLeagueGamesFeed` for games and a new sibling `FantasyLeagueTableFeed` for standings and crests. Games and teams open through shared route helpers. Because the Hub can now lead to pages that link back to Fantasy, "open Fantasy" from a page above an open Hub returns to that Hub instead of stacking a second one.

**Tech Stack:** Flutter/Dart, fan app `infinite_sports_flutter`, Firebase RTDB `onValue` streams, flutter_test.

**Spec:** the "Owner decisions" section below (support ticket 4 + chat, 2026-11-15).

## Owner decisions (the spec)

1. Support ticket 4, the owner's own suggestion, verbatim: "There should be a tab of the associated league in the fantasy so we can refer to it back and forth when selecting players. Because we wanna know who is playing who so we can pick the right players instead of leaving the fantasy hub and going into the associated league"
2. Owner chose "Fixtures + Table": the league's game days with the same game cards as the Leagues tab, where tapping a card opens the game, plus the standings table.
3. Owner chose "Right after Players". The tab row becomes My Team, Players, League, Leaderboards, News, Rules.
4. Standing rule from 2026-11-14: tapping anywhere on a game card opens the game, and team pages open from inside the game. In the table, a team row opens the team page, as it does on the league page today.

## Global Constraints

- Tab label, exactly: `League`. Switch labels, exactly: `Fixtures` and `Table`.
- Error copy, exactly: `Couldn't load the league` with a `Try again` button (the Hub's existing wording style).
- Tab order, exactly: `['My Team', 'Players', 'League', 'Leaderboards', 'News', 'Rules']`. `FantasyHubTab` gains `league` between `players` and `leaderboards`, because the enum order is the tab position (`lib/fantasy/hub/fantasy_hub_route.dart:22`).
- Real-time `onValue` streams only. No RTDB `get()`, no bare `.once()` (`test/no_bare_once_guard_test.dart` enforces this). The only one-shot is the existing bounded start-hour read inside `FantasyLeagueGamesFeed`.
- An error is not a fact: a failed read never shows "No fixtures available" or an empty table. It shows the error copy, and the last good data stays on screen when there is some.
- One reveal: the tab shows a skeleton until both feeds have answered or failed, then reveals once. A revisit paints at once from the feeds' session caches. Crests never pop in after the cards.
- New feed code follows the shared rules in the header of `lib/fantasy/data/fantasy_schedule_feed.dart`: every stream has an error handler, failures are logged with `debugPrint`, the last good value is kept, and a stream that cannot even be created (no Firebase app in a widget test) degrades the same way.
- Light and dark mode: use the existing widgets' colors and `colorScheme`. No new hardcoded light-palette colors. Everything works at 360 px wide.
- Tappable team and player names are never underlined.
- iOS parity: nothing platform-specific. The PR gets "verify on iPhone simulator" lines (listed under Rollout).
- Branch: `zaya-fantasy-league-tab` from `zaya-review-fixes` @ `24a6a70`. Fan test baseline is 3438 passing.
- PII never goes into code, tests or commits. Use made-up team and player names.
- Do not push, deploy or install without the owner's go.
- Commit trailer: the executing model's own `Co-Authored-By` line.

## Review Focus

1. **"Open Fantasy" on a game opened from the Hub.** Before kickoff, a game's Fantasy tab is mostly an "open Fantasy" button, so fans will tap it. It must return to the Hub they came from, on the tab they left, with their unsaved picks intact. It must not push a second Hub. Tests in Task 3.
2. **The Hub is re-shown for another sport or season** (the old cross-competition bleed bug). The League tab must drop the old league's games and table and load the new ones. Test in Task 4.
3. **A read fails.** Games fail and nothing was ever loaded → Fixtures shows `Couldn't load the league` with `Try again`, never "No fixtures available". Standings fail → the same on Table while Fixtures keeps working. Try again re-subscribes. Tests in Tasks 2 and 4.
4. **Pick a day, look at the Table, come back; or open a game and come back.** The picked day and the Fixtures / Table choice are still there. Tests in Tasks 4 and 5.
5. **A team with no crest or no standings row yet** (a fresh season, a seeded playoff game). Its card shows the team's name, never `Seed #N`. Test in Task 1.

---

### Task 1: Shared league route helpers and card teams

**Files:**
- Create: `lib/misc/league_navigation.dart`
- Modify:
  - `lib/misc/league_adapters.dart`: add `leagueCardTeams` next to `leagueTeamsById` (line ~318).
  - `lib/league_detail_page.dart:296-324` and `:407-417`: `_openMatch` / `_openTeam` use the helpers; the Fixtures tab gets `teams: leagueCardTeams(matches, _standings ?? const [], _logos)`. `_teamsById` stays for the other tabs.
  - `lib/widgets/league_day_view.dart`: the league-engine branch of `_openMatch` uses the helper (the legacy `ScorePage` branch stays), and the inline stub loop in `build` becomes one `leagueCardTeams(matches, const [], _logos)` call.
- Test: `test/league_navigation_test.dart` (new), `test/league_adapters_test.dart` (extend)

**Interfaces:**
- Produces:
  - `MaterialPageRoute<void>? leagueMatchRoute({required String sport, required String season, required TournamentMatch match})`. Returns null when `parseLeagueGameId(match.id)` is null. Otherwise the route builds `LeagueMatchDetailPage(sport:, season:, dateKey:, gameIndex:, initialMatch: match)`.
  - `MaterialPageRoute<void> leagueTeamRoute({required String sport, required String season, required String teamName})`. The route builds `LeagueTeamDetailPage(sport:, season:, teamName:)`.
  - `bool openLeagueMatch(BuildContext context, {required String sport, required String season, required TournamentMatch match})`: pushes `leagueMatchRoute` with `Navigator.push(context, …)`; returns false and pushes nothing when the route is null.
  - `void openLeagueTeam(BuildContext context, {required String sport, required String season, required String teamName})`.
  - `Map<String, TournamentTeam> leagueCardTeams(List<TournamentMatch> matches, List<TournamentTeam> standings, Map<String, String> logoUrls)`: `leagueTeamsById(standings, logoUrls)` plus a `leagueTeamStub(name, null)` for every real team name in `matches` (`team1Id` / `team2Id`, non-empty, not `isPlaceholderTeam`) that is still missing.
  - Callers keep the context they push with today: `context` in `LeagueDetailPage`, `mainContext!` in `LeagueDayView`.

- [ ] **Step 1: Write the failing tests.**
  - In `league_navigation_test.dart`. These pages need Firebase, so never mount them: get a `BuildContext` from a pumped `Builder`, call `route.builder(context)`, and assert on the returned widget.
    - `leagueMatchRoute builds LeagueMatchDetailPage with the game's date key and index` (make the match with `leagueMatchesFromDateNode`)
    - `leagueMatchRoute is null for an id that is not a league game id`
    - `leagueTeamRoute builds LeagueTeamDetailPage for that team`
  - In `league_adapters_test.dart`:
    - `leagueCardTeams adds a stub for a team with no standings row and no crest` (Review Focus 5): matches `Alpha FC` vs `Beta FC`, empty standings, empty logos → both keys present with those names.
    - `leagueCardTeams skips placeholders` (`Winner of SF1` is absent)
    - `leagueCardTeams keeps a standings row and its crest unchanged`
- [ ] **Step 2:** Run `flutter test test/league_navigation_test.dart test/league_adapters_test.dart`. Expected: FAIL (names undefined).
- [ ] **Step 3:** Implement and switch the callers. Behavior is unchanged except Review Focus 5 on the league page's Fixtures tab.
- [ ] **Step 4:** Run the two test files, then `flutter test` (whole suite). Expected: all pass.
- [ ] **Step 5: Commit** `refactor(league): one shared way to open a league game or team, and to name the teams on a card`

### Task 2: Feeds for the League tab

**Files:**
- Modify: `lib/fantasy/data/fantasy_schedule_feed.dart`: extend `FantasyLeagueGamesFeed` (line ~578) and add `FantasyLeagueTableFeed` after it. It lives in this file because the logged-listen helpers are private to it. Add one line for it to the file header.
- Test: `test/fantasy/fantasy_schedule_feed_test.dart` (extend)

**Interfaces:**
- Produces, on `FantasyLeagueGamesFeed`:
  - `bool get failed`: true when the latest games answer was an error and no games were ever loaded, in this object or the session cache. Any data clears it. An error after good data leaves it false, and the last good games stay.
  - `void retry()`: clears `failed`, puts the feed back to not ready, and re-subscribes with the hour it has. A no-op when disposed.
  - The Players tab's use is unchanged.
- Produces `class FantasyLeagueTableFeed`:
  - Constructor: `FantasyLeagueTableFeed({required String sport, required String season, required String owner, required VoidCallback onChanged, Stream<List<TournamentTeam>> Function(Map<String, String> logos)? standingsFor, VoidCallback Function(void Function(Map<String, String> logos) onLogos)? watchLogos})`.
    - `standingsFor` replaces `LeagueService.watchStandings(sport, season, logos)`.
    - `watchLogos` replaces `watchSeasonLogos(sport, season, onLogos)` and returns the stop function.
  - `void start()`, `void dispose()`, `void retry()`.
  - `List<TournamentTeam> get standings`, `Map<String, String> get logos`.
  - `bool get ready`: the logos have reported once AND the standings have answered or failed.
  - `bool get failed`: same rule as the games feed, for standings.
  - `static void clearSessionCache()`. The session cache is per `<sport>|<season>` and holds the last standings and logos, so a revisit is ready at once.
  - When the logos change, standings re-subscribe with the new map, as `LeagueDetailPage._loadDisplaySeeds` does today. The rows on screen stay until the new answer arrives.

- [ ] **Step 1: Write the failing tests** (seams only, no Firebase):
  - Games feed:
    - `an error before any games sets failed, and ready opens`
    - `retry re-subscribes and data clears failed` (use the `gamesFor` seam with a counter)
    - `an error after good games keeps the games and failed stays false`
  - Table feed:
    - `ready only after logos AND standings have answered`
    - `a standings error before any data sets failed; retry re-subscribes; data clears it`
    - `a logo change re-subscribes standings with the new map and keeps the old rows meanwhile`
    - `a second feed for the same season is ready at once from the session cache`
    - `dispose stops the logos watcher and the standings listener` (the stop function was called; a later event causes no `onChanged`)
- [ ] **Step 2:** Run `flutter test test/fantasy/fantasy_schedule_feed_test.dart`. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement with the file's `_listenLogged` helper and its existing conventions.
- [ ] **Step 4:** Run the file, then `flutter test test/fantasy`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(fantasy): league games feed reports a failed read; a table feed for standings and crests`

### Task 3: "Open Fantasy" above an open Hub returns to that Hub

**Files:**
- Modify:
  - `lib/fantasy/hub/fantasy_hub_page.dart`: add `openFantasyHub` next to `fantasyHubPageRoute` (line ~103); `_FantasyHubPageState` registers itself.
  - The four in-app "open Fantasy" defaults call `openFantasyHub` instead of pushing: `lib/fantasy/match/match_fantasy_tab.dart:457-470`, `lib/fantasy/profile/fantasy_player_profile_page.dart:559`, `lib/profile/fantasy_profile_tab.dart:461`, `lib/league_tabs/league_fantasy_tab.dart:28`.
  - Unchanged: the Home banner, the Search card and notification taps keep pushing as today.
- Test: `test/fantasy/fantasy_hub_page_test.dart` (extend)

**Interfaces:**
- Produces: `void openFantasyHub(BuildContext context, FantasyHubRoute route, {Route<void> Function(FantasyHubRoute route)? routeFor})`.
  - `routeFor` defaults to `fantasyHubPageRoute`. It is the test seam for the push branch.
  - **Return branch.** It applies when a Hub for the same `sport` and `season` is mounted, its own route is active, and that route belongs to `Navigator.of(context)`. With several such Hubs, use the one registered last. Then:
    1. `Navigator.of(context).popUntil((r) => identical(r, hubRoute))`.
    2. If `route.initialPlayerName` is set, the Hub opens that player's profile through its existing `_openPlayerProfile` (the one with the Hub's shared draft).
    3. The Hub's current tab does not change.
  - **Push branch.** Otherwise `Navigator.push(context, routeFor(route))`.
  - The registry is a private static list on `_FantasyHubPageState`. A Hub adds itself, with its `ModalRoute.of(context)`, in `didChangeDependencies` (once) and removes itself in `dispose`. Compare routes by identity, never by name.

- [ ] **Step 1: Write the failing tests** with the existing `pumpHub`. From the Hub's context, push a plain test page that has a button calling `openFantasyHub` from its own context:
  - `open Fantasy above the same season's Hub pops back to it: one Hub, same tab, draft untouched` (Review Focus 1). Open the Hub on Players first. Assert the test page is gone, exactly one `FantasyHubPage` exists, and the Players tab is still showing.
  - `with a player name it pops back and opens that player's profile once` (assert through the `profileOpener` seam)
  - `a different season pushes a new route` (pass a `routeFor` that returns a plain test route; assert it was pushed and the first Hub is still below)
  - `with no Hub open it pushes`
  - `after the Hub is disposed it pushes` (pop the Hub, call again from a root page)
- [ ] **Step 2:** Run `flutter test test/fantasy/fantasy_hub_page_test.dart`. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement. Keep each call site's existing seam (`onOpenHub`, `openInFantasy`) working: a seam that is set still wins.
- [ ] **Step 4:** Run `flutter test test/fantasy` (it includes `league_fantasy_tab_test.dart`). Expected: all pass.
- [ ] **Step 5: Commit** `fix(fantasy): opening Fantasy from a page above the Hub returns to that Hub`

### Task 4: `FantasyLeagueTab`

**Files:**
- Create: `lib/fantasy/hub/fantasy_league_tab.dart`
- Modify: `lib/league_tabs/league_fixtures_tab.dart` (two optional parameters)
- Test: `test/fantasy/fantasy_league_tab_test.dart` (new), `test/league_fixtures_tab_test.dart` (extend)

**Interfaces:**
- Consumes: `openLeagueMatch`, `openLeagueTeam`, `leagueCardTeams` (Task 1); `FantasyLeagueGamesFeed` with `failed` / `retry`, and `FantasyLeagueTableFeed` (Task 2).
- Produces, on `LeagueFixturesTab`: optional `String? pickedDay` and `ValueChanged<String>? onDayPicked`. When `onDayPicked` is set the owner holds the picked day: the tab uses `pickedDay` in place of its own state and calls `onDayPicked` on a tap. When it is null the tab behaves exactly as today.
- Produces `class FantasyLeagueSeams` with a const constructor and these optional fields:
  - `Stream<List<TournamentMatch>>? gamesStates`
  - `Stream<List<TournamentMatch>> Function(int startHour)? leagueGamesFor`
  - `Future<int> Function()? loadStartHour`
  - `Stream<List<TournamentTeam>> Function(Map<String, String> logos)? standingsFor`
  - `VoidCallback Function(void Function(Map<String, String> logos) onLogos)? watchLogos`
  - `void Function(BuildContext context, TournamentMatch match)? openMatch`
  - `void Function(BuildContext context, String teamName)? openTeam`
- Produces `class FantasyLeagueTab extends StatefulWidget` with constructor `FantasyLeagueTab({required String sport, required String season, FantasyLeagueSeams seams = const FantasyLeagueSeams(), DateTime? now})`.
  - Its State owns one games feed and one table feed (owner `'FantasyLeagueTab'`). It starts them in `initState` and disposes them in `dispose`. In `didUpdateWidget`, on a `sport` or `season` change, it disposes both, clears the picked day, and creates and starts new ones.
  - One reveal gate: skeleton until `games.ready && table.ready`.
  - A `SegmentedButton` with `Fixtures` / `Table`, Fixtures first. Only the chosen view is mounted. Two lists in one Hub tab would feed `CollapsingTabShell`'s header logic conflicting scroll metrics.
  - Fixtures: `LeagueFixturesTab(matches: games.games, teams: leagueCardTeams(games.games, table.standings, table.logos), rosters: const {}, sport:, predictionsOpen: false, pickedDay:, onDayPicked:, now:)`, with `onMatchTap` → `seams.openMatch` or `openLeagueMatch`. When `games.failed`, the error copy with Try again → `games.retry()`.
  - Table: `LeagueTableTab(sport:, standings: table.standings)`, with `onOpenTeam` → `seams.openTeam` or `openLeagueTeam`. When `table.failed`, the error copy with Try again → `table.retry()`.
  - The picked day and the Fixtures / Table choice live in the tab's State, so they survive the switch and, because Hub tabs are kept alive, a trip to a game and back.
  - No on-screen gating of the feeds (`CollapsingTabShell.isTabOnScreen`) is needed: both are small, and the games listener is the same database listener the Players tab already holds.

- [ ] **Step 1: Write the failing tests** (seams only; pump inside `MaterialApp(home: Scaffold(body: …))`):
  - `league_fixtures_tab_test.dart`:
    - `with onDayPicked the owner holds the day: a tap calls it and the shown day follows pickedDay`
    - `without onDayPicked a tapped day sticks as before`
  - `fantasy_league_tab_test.dart`:
    - `skeleton until games AND table have answered, then one reveal with crests` (no card before; cards and the day strip after)
    - `tapping a card calls openMatch with that game`
    - `Table shows the standings, and a row calls openTeam with the team's name`
    - `pick a day, switch to Table and back: the same day is selected` (Review Focus 4)
    - `games fail with nothing loaded: "Couldn't load the league", never "No fixtures available"; Try again re-subscribes` (Review Focus 3)
    - `standings fail: the Table shows the error while Fixtures still works` (Review Focus 3)
    - `no games and an empty table show the existing empty states, never a skeleton`
    - `a new season drops the old games and table and loads the new ones` (Review Focus 2): pump with season `'15'`, emit a game, re-pump with season `'16'`. Assert the season-15 game is gone and the seams were called again.
    - `360 px, light and dark: no overflow`
- [ ] **Step 2:** Run `flutter test test/fantasy/fantasy_league_tab_test.dart test/league_fixtures_tab_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. Follow `lib/fantasy/hub/players_tab.dart` for how a Hub tab owns shared feeds and builds its reveal gate.
- [ ] **Step 4:** Run the two files and `flutter test test/league_table_tab_test.dart`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(fantasy): a League tab widget with the league's fixtures and table`

### Task 5: The Hub shows the League tab after Players

**Files:**
- Modify: `lib/fantasy/hub/fantasy_hub_route.dart:22` (enum), `lib/fantasy/hub/fantasy_hub_page.dart` (constructor seam; the tabs list and children at `:1159-1291`)
- Test: `test/fantasy/fantasy_hub_page_test.dart`, `test/fantasy/fantasy_hub_route_test.dart`, `test/fantasy/fantasy_home_banner_test.dart`. Grep the folder for `FantasyHubTab.` and for the tab labels before editing: a test that depends on tab position has to be re-pointed (the 360 px label list near `:2630` is one).

**Interfaces:**
- Consumes: `FantasyLeagueTab`, `FantasyLeagueSeams` (Task 4).
- Produces: `enum FantasyHubTab { myTeam, players, league, leaderboards, news, rules }`; `FantasyHubPage({…, FantasyLeagueSeams? leagueSeams})`, where null means production.
- No route code changes: every route picks its tab by enum value, and `initialTab.index` (`fantasy_hub_page.dart:1160`) is the only place the position is used.

- [ ] **Step 1: Write the failing tests** in `fantasy_hub_page_test.dart`:
  - `the tab row reads My Team, Players, League, Leaderboards, News, Rules`
  - `opening the Hub on FantasyHubTab.league shows the League tab`
  - `on the League tab: pick a day, tap a card, come back: still League, same day` (Review Focus 4). Pass `leagueSeams` whose `openMatch` pushes a plain test page.
  - extend the 360 px label test to the six labels, none ellipsized
  - every existing test that opens Leaderboards, News or Rules still lands on the tab it means
- [ ] **Step 2:** Run `flutter test test/fantasy/fantasy_hub_page_test.dart`. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement the enum, the tabs list, the child and the seam. Existing Hub tests that never open the League tab need no seam: without Firebase the feeds degrade and log, as the Players tab's games feed already does in those tests.
- [ ] **Step 4:** Run `flutter test` (whole suite) and `flutter analyze` on the changed files. Expected: all pass, no new issues.
- [ ] **Step 5: Commit** `feat(fantasy): the Hub gets a League tab after Players, with fixtures and table`

---

## Rollout (each step needs the owner's go)

1. Install on the emulator for the owner to try.
2. Merge into `zaya-review-fixes` so it rides the same store release as PR #18. iPhone simulator checks for the PR:
   - League tab → Fixtures and Table show; tap a card → the game; back → same tab and day.
   - From that game's Fantasy tab, the open-Fantasy button returns to the same Hub. Back from the Hub then leaves Fantasy; it does not show the game again.
   - On a small iPhone, the cards are comfortably visible under the header, tab row, switch and day strip.

## Not in this plan

- No Predict banner inside the Hub's League tab (`predictionsOpen: false`).
- No "fixture difficulty" colors or opponent badges on player cards.
- No pre-selection of the gameweek's day: the default (a live day, else today or the next game day) already lands there.
- Notification taps, the Home banner and the Search card still push a Hub as today, even if another Hub is open underneath.
- Ticket 3 (a player's position) is a data change the owner makes in the Manager, not code.

## Fable review (2026-11-15)

Verified against the code on `zaya-review-fixes` @ `24a6a70`. Verdict: **approved with the amendments below, all of which are written into the tasks above.**

1. **Stacked Hubs (added Task 3).** A game's Fantasy tab and the player profiles push a new Hub (`match_fantasy_tab.dart:457-470`, `fantasy_player_profile_page.dart:559`). Until now nothing inside the Hub led to those pages. The League tab does, and before kickoff the game's Fantasy tab is mostly that button. A second Hub has its own squad draft, so unsaved picks in the first one could later overwrite a save made in the second.
2. **A failed games read would have read as "no fixtures" (Task 2).** The draft named `FantasyLeagueGamesFeed` as the source but specified plain streams, and that feed swallows errors by design for the Players tab's next-game lines. It now reports `failed` and can `retry`. Standings get a sibling feed with a session cache, so a revisit is instant.
3. **Fixtures / Table switch (Task 4).** Only the chosen view is mounted, and the picked day is held by the tab. The draft kept both alive, which would have fed the collapsing header two lists' scroll metrics, or else lost the picked day on every switch.
4. **Team names on cards (Task 1).** One helper, `leagueCardTeams`, so a team with no crest or standings row shows its name. This also closes the same gap on the league page's own Fixtures tab, which the game-card review flagged yesterday.
5. **Tests that would have needed Firebase (Tasks 1, 4, 5).** The pushed pages cannot be mounted in widget tests. Route builders are tested without mounting, and the tab takes opener seams.
6. **Checked and left as written:** inserting `league` into the enum is safe (routes use enum values; position is read in one place); six tab labels fit because the tab row already scrolls; no walkthrough or notification code depends on a tab number.
