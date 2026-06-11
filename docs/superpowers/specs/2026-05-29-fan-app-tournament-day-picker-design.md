# Tournament Day-Picker (Fan App, Matches Tab) — Design

**Date:** 2026-05-29
**Repo:** `infinite_sports_flutter` (user-facing / fan app)
**Branch:** `zaya/tournament-enhance-app-manager`
**Status:** Approved design, ready for implementation plan

## Goal

On the home **Matches** tab, give each active tournament a swipeable **date strip**
so fans can jump between match days without leaving the home screen. Today a
tournament's section shows only its *current game day* with no way to see other
days; the strip exposes every match day (past results, today, and upcoming) while
keeping the current day as the default landing spot.

## Scope

- **One area:** the per-tournament section of the home Matches tab
  (`lib/frontpage.dart` → `_buildTournamentTab`).
- **Fan app only.** No changes to the manager app, no Firebase schema changes.
- **The full tournament detail page (`TournamentDetailPage`) is intentionally left
  unchanged.** It already shows the complete fixture list across all days, so it
  needs no strip.
- **No change to how a match card decides its badge.** Upcoming / Live / Final is
  driven solely by each match's Firebase `Status` (0/1/2) inside `FixturesTab`. The
  strip only changes *which day's* cards are displayed; a game never appears "live"
  just because its date is today.

## Decisions (locked during brainstorming)

1. **Location:** home Matches tab only — not the tournament detail page.
2. **Style:** a horizontal, swipeable strip of day pills (ESPN/FotMob style), not a
   pop-up month calendar.
3. **Days shown:** every day the tournament has at least one match — past days
   (with final scores), today, and upcoming.
4. **Default day on open:** the existing "current game day" (today if there are
   matches today, otherwise the next upcoming match day).
5. **Active-tournament rule is unchanged:** a tournament appears on the home tab
   only while it has a current game day. Once all its matches are in the past it
   drops off the home screen, exactly like a finished league season. "Swipe back to
   past days" therefore means past days *within* a still-active tournament.

## Behavior Specification

### The date strip

- A horizontal, scrollable `Row`/`ListView` of day pills rendered at the top of the
  tournament's section, between the tappable tournament header card and the match
  list.
- **One pill per distinct match day**, in calendar order (earliest → latest).
- Each pill shows the **weekday abbreviation + day number** (e.g. `SAT` / `31`).
- The **selected** pill is highlighted with the app's primary color
  (`infiniteSportsPrimaryColor`); unselected pills use a muted background.
- On first build the strip **auto-scrolls** so the selected (default) pill is
  visible, even when there are many days.
- Tapping a pill selects that day and refreshes the match list below
  (`setState`). No Firebase calls — all matches are already in memory.

### Default selected day

- Equals the tournament's current game day, computed exactly as today via
  `currentGameDay(matches.map((m) => m.date))` in `lib/misc/game_day.dart`.
- Because a tournament is only shown when its current game day is non-null, the
  default day is always present in the strip and always one of the pills.

### The match list (per selected day)

- The matches for the selected day are rendered by the **existing `FixturesTab`**
  widget, unchanged, so the cards look identical to today.
- `FixturesTab` is given **only the selected day's matches** — this matches the
  current home-tab behavior (today it is already handed a single day's matches), so
  there is no regression. In particular, the eliminated-team strike-through is
  computed from the visible day's matches, same as now.
- `FixturesTab` already renders the full date as a section header
  (`"Saturday, May 31"` via `DateFormat('EEEE, MMMM d')`). This stays, so the full
  month/day is always unambiguous even though pills show only the day number — this
  is the agreed resolution for tournaments that cross month boundaries.
- Badges per card are unchanged: Upcoming shows the kickoff time, Live shows the red
  LIVE badge + score, Final shows the final score (all from `match.Status`).

### Data loading (frontpage.dart)

- `_loadActiveTournaments()` currently loads **all** matches via
  `TournamentService.getMatches(t.id)` and then keeps only the current day
  (`dayMatches`). The change: **keep all matches** and additionally remember the
  computed current game day as the strip's initial day.
- The `day == null` guard is **unchanged** — tournaments with no current game day
  are still skipped, so finished tournaments fall off the home screen.

## File Structure

- **New pure helper:** `lib/misc/match_days.dart` (mirrors the dependency-free
  `lib/misc/game_day.dart` — no Flutter/Firebase imports, unit-testable):
  - `List<String> sortedMatchDays(Iterable<String> dates)` — returns the distinct,
    **valid** MMDDYYYY day keys in ascending calendar order; duplicates removed and
    unparseable dates ignored. Reuses the same MMDDYYYY parsing approach as
    `game_day.dart`.
- **New widget:** `lib/tournament_tabs/tournament_day_view.dart`
  - `TournamentDayView` — a `StatefulWidget` that takes the full match list, the
    teams/rosters maps, `tournamentId`, `sport`, and an `initialDay` (MMDDYYYY).
  - State holds the selected day (initialized to `initialDay`).
  - `build` returns a `Column`: the day strip on top, then
    `Expanded(child: FixturesTab(matches: <selected day's matches>, ...))`.
  - Computes the pill list once via `sortedMatchDays`; formats each pill's
    weekday/day with `intl` + the existing `parseDatabaseDate` helper.
- **New test:** `test/match_days_test.dart` — covers `sortedMatchDays`: ascending
  order, duplicate days collapsed, unparseable/invalid dates ignored, empty input →
  empty list, single day.
- **Modified:** `lib/frontpage.dart`
  - `_ActiveTournamentTab` keeps the **full** match list and gains an
    `initialDay` field (the precomputed current game day).
  - `_loadActiveTournaments` stops filtering to `dayMatches`; passes all matches +
    `initialDay`.
  - `_buildTournamentTab` replaces the direct `FixturesTab` with
    `TournamentDayView`.

## Edge Cases

- **Tournament crossing months:** pills show only the day number, but the
  `FixturesTab` date header (`"Saturday, June 7"`) disambiguates the selected day.
- **Two matches same day, different stages:** `FixturesTab` already sorts within a
  day by stage then bracket position; unchanged.
- **A team eliminated on an earlier day, viewing a later day:** strike-through is
  scoped to the visible day's matches — identical to today's home-tab behavior (not
  a regression).
- **Only one match day:** the strip shows a single pill (already selected); the list
  shows that day. Harmless.
- **No current game day / no matches:** the tournament is skipped upstream and never
  reaches `TournamentDayView` — same as today.

## Testing

- Unit tests for `sortedMatchDays` (`test/match_days_test.dart`) — TDD, written
  first.
- `flutter analyze` clean for touched files.
- Manual check on device: open the Matches tab, confirm each active tournament shows
  a day strip; the current game day is selected and scrolled into view; swiping back
  shows past days with final scores and forward shows upcoming days with kickoff
  times; tapping the tournament header still opens the detail page; the detail page's
  fixture list is unchanged.

## Out of Scope (future rounds)

- Tournament logo with trophy fallback on the home tab (separate spec → plan →
  build cycle).
- Any date-picker for the league ("Infinite Sports") or AFC San Jose tabs — they
  keep their existing single current-day view.
- A pop-up month calendar or month dividers in the strip.
- Changing how matches are sorted or how badges are derived.
