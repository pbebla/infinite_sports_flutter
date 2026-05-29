# Matches Screen — Day-Driven Tabs Redesign

**Date:** 2026-05-29
**Repo:** `infinite_sports_flutter` (user-facing app)
**Branch:** `zaya/tournament-enhance-app-manager`

## Goal

Turn the home "Live Scores" screen into a consistent, day-driven **"Matches"**
screen that shows one tab per currently-active competition (each league and
each active tournament), where every tab shows only the matches for its
**current game day** — and rename the screen to "Matches".

## Background / Current Behavior

The home screen (`lib/frontpage.dart`) shows the first thing users see. Today it
builds tabs dynamically:

- An **"Infinite Sports"** tab for the current league sport, shown only when
  that season is not finished. Its game list comes from `LiveScorePage`, which
  shows all games for a single date — the "current game day" picked by
  `getCurrentDate(sport, season)` in `lib/misc/utility.dart`.
- An **"AFC San Jose"** tab, same pattern, shown only when the AFC season is not
  finished.
- A **"Tournament"** tab (added recently) that points at the single
  `/Tournaments/Current Tournament`. It embeds `FixturesTab`, which lists
  **every** match of the tournament regardless of status — including
  long-finished games. If both league seasons are finished the screen used to
  short-circuit to a "No Upcoming Games" card; the tournament tab now appears
  independently of that.

### The two problems

1. **Tournaments show finished matches forever.** The tournament tab dumps the
   entire fixture list. The user wants finished games to fall off the screen
   once their day passes, exactly like the leagues already behave.
2. **Only one tournament is supported.** The screen relies on the single
   `Current Tournament` pointer, but the user may run several tournaments at
   once and wants a tab for each.

Plus two smaller asks: the tournament header card's text isn't centered, and the
screen should be renamed from "Live Scores" to "Matches".

## Confirmed Requirements

1. **Day-driven visibility (the core rule).** A match is shown on this screen if
   and only if its date equals the competition's **current game day**:
   - "Current game day" = **today** if the competition has any match dated today;
     otherwise the **earliest future date** that has a match.
   - On that day, show **all** matches regardless of status — not-started, live,
     and games that started and ended *today*.
   - When the calendar day rolls over, that day's finished games disappear and
     the screen advances to the next day with matches.
   - This applies **consistently** to both leagues and tournaments.
2. **One tab per active competition.**
   - Current league sport tab — shown when its season is not finished.
   - AFC San Jose tab — shown when its season is not finished.
   - One tab **per active tournament** — every tournament whose `Finished` flag
     is false **and** which has a current game day (a match today or in the
     future). Supports multiple simultaneous tournaments.
3. **Header card.** Center the tournament card's text. Tapping the card opens the
   full competition page (tournament detail page for tournaments; season page
   for leagues). Tapping an individual game card opens that game's detail page.
4. **Rename "Live Scores" → "Matches"** in **both** the bottom navigation button
   (`lib/main.dart`) and the screen's app-bar title (`lib/frontpage.dart`).
5. **Hide league shortcut buttons on tournament tabs.** The app-bar table and
   leaderboard shortcut buttons are league-specific; hide them while a tournament
   tab is active (the tournament's own table/stats are reachable via the header
   card → full tournament page).

## Design

### Architecture overview

All changes are confined to the user app's home screen and its data loading:

- `lib/frontpage.dart` — builds the tabs, applies the day-driven filter, renders
  the centered tournament card, controls the app-bar shortcut buttons.
- `lib/main.dart` — bottom navigation label rename.
- A small **pure helper** for computing the current game day from a list of date
  strings, so the same logic the leagues use is applied to tournaments and is
  unit-testable in isolation.
- `lib/misc/tournament_service.dart` — a method to fetch the set of **active**
  tournaments (not finished), reusing existing `getTeams` / `getMatches` /
  `getRosters`.

No changes to the manager/admin app and no Firebase schema changes.

### Component 1 — Current game day helper

Add a pure function (no Firebase, fully testable):

```dart
/// Returns the "current game day" key from a set of MMDDYYYY date strings:
/// today if present, else the earliest future date, else null (all in past).
String? currentGameDay(Iterable<String> dates, {DateTime? now});
```

- Parses each `MMDDYYYY` string to a `DateTime` (reusing existing
  `parseDatabaseDate`).
- If any date is the same calendar day as `now` → return it.
- Else return the earliest date strictly after today.
- Else (every date is in the past) → return `null`.

This mirrors the intent of `getCurrentDate` but operates on an in-memory list and
returns `null` when nothing is current/upcoming (so a competition with only past
matches shows nothing rather than its last finished day). Leagues continue to use
their existing `getCurrentDate`; this helper is for the tournament tabs (and is a
clean target for the league logic later if we choose to converge them).

### Component 2 — Active tournaments loader

Add to `TournamentService`:

```dart
/// Returns headers for all tournaments whose Finished flag is false,
/// sorted active-first / newest edition first (reuses getAllTournaments).
static Future<List<Tournament>> getActiveTournaments();
```

`getAllTournaments()` already reads `/Tournaments` and parses headers; filter to
`!finished`. For each active tournament, the home screen loads `getTeams`,
`getMatches`, and `getRosters` (rosters power the tap-through match detail). These
loads run in parallel across tournaments via `Future.wait`.

A tournament earns a tab only if `currentGameDay(matchDates)` is non-null — i.e.
it has a game today or upcoming. Active tournaments with only past matches show no
tab (consistent with the day-driven rule).

### Component 3 — frontpage.dart tab assembly

`getFrontPageValues()` additionally loads the active tournaments and, for each,
its teams/matches/rosters and computed current game day. State holds a list of
per-tournament bundles rather than the single-tournament fields used today.

In `build`:
- League tabs unchanged (they already show their current game day via
  `LiveScorePage`).
- For each active tournament with a current game day, add a tab labeled with the
  tournament name. The tab is a `Column`: centered header card (→ full tournament
  page) + `FixturesTab` fed a **pre-filtered** match list (only matches whose date
  equals that tournament's current game day). Because the list is a single day,
  `FixturesTab` renders one date group; ended-today games still show their score
  and leaders strip.
- The screen shows tabs when **any** league or tournament tab exists; otherwise
  the existing "No Upcoming Games" card.
- The `TabBar` becomes `isScrollable: true` to accommodate a variable number of
  tabs.

### Component 4 — Centered tournament card

In the tournament header card, center the contents (e.g. `mainAxisAlignment:
MainAxisAlignment.center` on the row / centered text alignment), keeping the
trophy icon. League cards are left unchanged unless the user later asks to match.

### Component 5 — Rename to "Matches"

- `lib/main.dart`: the `NavigationDestination` label `'Live Scores'` → `'Matches'`
  and the `_liveScoresTitle` default `"Live Scores"` → `"Matches"`.
- `lib/frontpage.dart`: the `GlobalAppBar` title text `"Live Scores"` → `"Matches"`.

### Component 6 — App-bar shortcut buttons on tournament tabs

Track the selected tab. When the active tab is a tournament tab, hide the table
and leaderboard `IconButton`s in `GlobalAppBar` (render nothing). When a league
tab is active, keep them and keep updating `headerNotifier` as today.

## Data Flow

1. `getFrontPageValues()` loads league current values (unchanged) **and** active
   tournaments + their teams/matches/rosters + current game day.
2. `build` assembles league tabs (unchanged) and a tab per qualifying tournament.
3. Each tournament tab filters its matches to the current game day and hands them
   to `FixturesTab`.
4. Tapping a game card → existing match detail page (data passed through).
5. Tapping a header card → full competition page.
6. Pull-to-refresh / the refresh button re-runs `getFrontPageValues()`.

## Edge Cases

- **No active competitions at all:** show the existing "No Upcoming Games" card.
- **Active tournament, no current game day (only past matches):** no tab for it.
- **Tournament with games today, all finished:** today is the current game day →
  they still show until the day rolls over.
- **Many active competitions:** scrollable tab bar; data loads in parallel. If it
  ever feels slow, a later optimization is to load a tournament's data lazily when
  its tab is first opened (out of scope now).
- **Long tournament names:** scrollable tabs avoid overflow; names may be
  truncated with ellipsis in the tab label.

## Testing

- **Unit test the `currentGameDay` helper** (pure, no Firebase): today present →
  returns today; only future dates → earliest future; only past dates → null;
  empty → null; mixed → correct pick. Use an injected `now`.
- `flutter analyze` clean on changed files.
- Manual: verify tournament tab shows only the current day's games, finished-today
  games linger, multiple tournaments produce multiple tabs, the card text is
  centered, the screen and bottom button read "Matches", and the table/leaderboard
  buttons hide on tournament tabs.

## Out of Scope

- Any manager/admin app changes.
- Firebase schema changes (the single `Current Tournament` pointer remains for
  other features; this screen derives "active" from the `Finished` flag).
- Converging the league `getCurrentDate` onto the new helper.
- Lazy per-tab loading (possible future optimization).
- Restyling league header cards.
