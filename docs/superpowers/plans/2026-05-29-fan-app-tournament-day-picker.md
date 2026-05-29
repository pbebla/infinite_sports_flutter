# Tournament Day-Picker (Fan App, Matches Tab) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a swipeable date strip to each active tournament's section of the home Matches tab so fans can jump between match days, defaulting to the current game day.

**Architecture:** A new dependency-free helper (`lib/misc/match_days.dart`) computes the sorted list of distinct match days. A new stateful widget (`lib/tournament_tabs/tournament_day_view.dart`) stacks a horizontal day-pill strip on top of the existing `FixturesTab`, tracking the selected day in state. `lib/frontpage.dart` stops discarding non-current-day matches and hands the full match set plus the precomputed current day to the new widget. The shared `FixturesTab`, the tournament detail page, and the per-card status-badge logic are all untouched.

**Tech Stack:** Flutter / Dart, `intl` (`^0.20.2`) for date formatting, `flutter_test` for unit tests. Package name: `infinite_sports_flutter`.

---

## Spec Reference

Design spec: `docs/superpowers/specs/2026-05-29-fan-app-tournament-day-picker-design.md`

## Background the engineer needs

- Match dates are stored as 8-char `MMDDYYYY` strings (e.g. `"05292026"`). The
  existing `lib/misc/game_day.dart` is a dependency-free helper that parses these
  with a private `_parseMMDDYYYY` and exposes
  `String? currentGameDay(Iterable<String> dates, {DateTime? now})`.
- The home Matches screen is `lib/frontpage.dart`. It already loads **all** of a
  tournament's matches, then keeps only the current game day before handing them to
  `FixturesTab`. A tournament is only shown while `currentGameDay(...)` is non-null,
  so finished tournaments drop off the home screen. **Keep that rule.**
- `FixturesTab` (`lib/tournament_tabs/fixtures_tab.dart`) is a `StatelessWidget`
  that takes `matches`, `teams`, `rosters`, `tournamentId`, `sport`. It sorts and
  groups by date, renders a `"Saturday, May 31"`-style header per date, and draws
  each match card. It is **also used by the tournament detail page** — do not modify
  it.
- A match card's badge (Upcoming time / red LIVE / Final score) comes solely from
  the match's `Status` int via `MatchStatus`. The strip never changes that.
- `parseDatabaseDate(String)` lives in `lib/misc/utility.dart` (Flutter-coupled).
  `infiniteSportsPrimaryColor` is also exported from `utility.dart`. The pure helper
  must NOT import `utility.dart`; the widget may.

## File Structure

- **Create** `lib/misc/match_days.dart` — pure, dependency-free. One function:
  `List<String> sortedMatchDays(Iterable<String> dates)`.
- **Create** `test/match_days_test.dart` — unit tests for `sortedMatchDays`.
- **Create** `lib/tournament_tabs/tournament_day_view.dart` — `TournamentDayView`
  stateful widget (strip + `FixturesTab` for the selected day).
- **Modify** `lib/frontpage.dart` — `_ActiveTournamentTab` (keep all matches, add
  `initialDay`), `_loadActiveTournaments` (stop filtering), `_buildTournamentTab`
  (use `TournamentDayView`), imports.

---

## Task 1: Pure helper `sortedMatchDays` + tests

**Files:**
- Create: `lib/misc/match_days.dart`
- Test: `test/match_days_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/match_days_test.dart` with this exact content:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/match_days.dart';

void main() {
  group('sortedMatchDays', () {
    test('returns distinct days in ascending calendar order', () {
      final result = sortedMatchDays(['06012026', '05202026', '05292026']);
      expect(result, ['05202026', '05292026', '06012026']);
    });

    test('collapses duplicate days', () {
      final result =
          sortedMatchDays(['05292026', '05292026', '06012026']);
      expect(result, ['05292026', '06012026']);
    });

    test('ignores unparseable or wrong-length dates', () {
      final result =
          sortedMatchDays(['05292026', 'bad', '', '123', '06012026']);
      expect(result, ['05292026', '06012026']);
    });

    test('orders correctly across month and year boundaries', () {
      final result = sortedMatchDays(['01012027', '12312026', '12012026']);
      expect(result, ['12012026', '12312026', '01012027']);
    });

    test('returns an empty list for empty input', () {
      expect(sortedMatchDays([]), isEmpty);
    });

    test('returns a single day unchanged', () {
      expect(sortedMatchDays(['05292026']), ['05292026']);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/match_days_test.dart`
Expected: FAIL — compile error, `match_days.dart` / `sortedMatchDays` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/misc/match_days.dart` with this exact content:

```dart
/// Pure, dependency-free helpers for working with a tournament's set of match
/// days. Dates are Firebase MMDDYYYY strings (e.g. "05292026"). Kept free of
/// Flutter/Firebase imports (like game_day.dart) so it can be unit-tested in
/// isolation; the parsing mirrors _parseMMDDYYYY in game_day.dart.
DateTime? _parseMMDDYYYY(String value) {
  if (value.length != 8) return null;
  final m = int.tryParse(value.substring(0, 2));
  final d = int.tryParse(value.substring(2, 4));
  final y = int.tryParse(value.substring(4, 8));
  if (m == null || d == null || y == null) return null;
  return DateTime(y, m, d);
}

/// Returns the distinct, valid match-day keys from [dates] in ascending
/// calendar order. Duplicate strings are collapsed and any value that is not a
/// valid 8-char MMDDYYYY date is ignored.
List<String> sortedMatchDays(Iterable<String> dates) {
  final seen = <String>{};
  final valid = <MapEntry<String, DateTime>>[];
  for (final raw in dates) {
    if (seen.contains(raw)) continue;
    final parsed = _parseMMDDYYYY(raw);
    if (parsed == null) continue;
    seen.add(raw);
    valid.add(MapEntry(raw, parsed));
  }
  valid.sort((a, b) => a.value.compareTo(b.value));
  return [for (final e in valid) e.key];
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/match_days_test.dart`
Expected: PASS — all 6 tests green.

- [ ] **Step 5: Verify analyzer is clean on the new files**

Run: `flutter analyze lib/misc/match_days.dart test/match_days_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/misc/match_days.dart test/match_days_test.dart
git commit -m "feat: add sortedMatchDays pure helper for tournament day strip"
```

---

## Task 2: `TournamentDayView` widget (strip + FixturesTab)

**Files:**
- Create: `lib/tournament_tabs/tournament_day_view.dart`

This widget has no unit test (it composes Flutter widgets and the Firebase-backed
`FixturesTab`); it is verified by the analyzer here and by the manual device check
in Task 3.

- [ ] **Step 1: Create the widget**

Create `lib/tournament_tabs/tournament_day_view.dart` with this exact content:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_days.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:intl/intl.dart';

/// Home-tab tournament view: a swipeable strip of day pills on top of the
/// shared [FixturesTab]. [matches] is the tournament's FULL match list;
/// [initialDay] (MMDDYYYY) is the day to open on (the current game day computed
/// by the caller). Only the selected day's matches are passed to [FixturesTab],
/// matching the existing home-tab behavior.
class TournamentDayView extends StatefulWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;
  final String tournamentId;
  final String sport;
  final String initialDay;

  const TournamentDayView({
    super.key,
    required this.matches,
    required this.teams,
    required this.rosters,
    required this.tournamentId,
    required this.sport,
    required this.initialDay,
  });

  @override
  State<TournamentDayView> createState() => _TournamentDayViewState();
}

class _TournamentDayViewState extends State<TournamentDayView> {
  // Pill box (52) + horizontal margin (4 each side) = 60 logical px per pill.
  static const double _pillExtent = 60;

  late final List<String> _days;
  late String _selectedDay;
  final ScrollController _stripController = ScrollController();

  @override
  void initState() {
    super.initState();
    _days = sortedMatchDays(widget.matches.map((m) => m.date));
    // Open on the provided day when it is a real match day; otherwise fall back
    // to the first day (defensive — initialDay is normally present).
    _selectedDay = _days.contains(widget.initialDay)
        ? widget.initialDay
        : (_days.isNotEmpty ? _days.first : widget.initialDay);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollSelectedIntoView());
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  void _scrollSelectedIntoView() {
    if (!_stripController.hasClients) return;
    final index = _days.indexOf(_selectedDay);
    if (index < 0) return;
    final viewport = _stripController.position.viewportDimension;
    final target = (index * _pillExtent) - (viewport / 2) + (_pillExtent / 2);
    final max = _stripController.position.maxScrollExtent;
    _stripController.jumpTo(target.clamp(0.0, max).toDouble());
  }

  List<TournamentMatch> get _matchesForSelectedDay =>
      widget.matches.where((m) => m.date == _selectedDay).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildStrip(context),
        Expanded(
          child: FixturesTab(
            matches: _matchesForSelectedDay,
            teams: widget.teams,
            rosters: widget.rosters,
            tournamentId: widget.tournamentId,
            sport: widget.sport,
          ),
        ),
      ],
    );
  }

  Widget _buildStrip(BuildContext context) {
    // Nothing to switch between when there is a single day.
    if (_days.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _days.length,
        itemBuilder: (context, index) => _buildPill(context, _days[index]),
      ),
    );
  }

  Widget _buildPill(BuildContext context, String day) {
    final selected = day == _selectedDay;
    final dt = parseDatabaseDate(day);
    final dow = dt != null ? DateFormat('EEE').format(dt).toUpperCase() : '';
    final dayNumber = dt != null ? DateFormat('d').format(dt) : day;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        if (day == _selectedDay) return;
        setState(() => _selectedDay = day);
      },
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? infiniteSportsPrimaryColor
              : Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dow,
              style: TextStyle(
                fontSize: 10,
                color:
                    selected ? Colors.white : onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dayNumber,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the analyzer is clean on the new widget**

Run: `flutter analyze lib/tournament_tabs/tournament_day_view.dart`
Expected: "No issues found!"

(If the analyzer reports an unused import, remove only that import line. All listed
imports are referenced: `match_days.dart` → `sortedMatchDays`; `utility.dart` →
`parseDatabaseDate` and `infiniteSportsPrimaryColor`; the model imports → the typed
fields; `fixtures_tab.dart` → `FixturesTab`; `intl` → `DateFormat`.)

- [ ] **Step 3: Commit**

```bash
git add lib/tournament_tabs/tournament_day_view.dart
git commit -m "feat: add TournamentDayView day-strip widget for home Matches tab"
```

---

## Task 3: Wire `TournamentDayView` into the home Matches screen

**Files:**
- Modify: `lib/frontpage.dart`

- [ ] **Step 1: Update the `_ActiveTournamentTab` doc comment and add `initialDay`**

In `lib/frontpage.dart`, the class currently reads (around lines 18-31):

```dart
/// One active tournament's data for the home screen, with [matches] already
/// filtered down to the tournament's current game day.
class _ActiveTournamentTab {
  final Tournament tournament;
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final Map<String, List<TournamentPlayer>> rosters;
  const _ActiveTournamentTab({
    required this.tournament,
    required this.teams,
    required this.matches,
    required this.rosters,
  });
}
```

Replace it with:

```dart
/// One active tournament's data for the home screen. [matches] holds ALL of the
/// tournament's matches (the day strip filters per selected day); [initialDay]
/// is the day to open on — the current game day computed at load time.
class _ActiveTournamentTab {
  final Tournament tournament;
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final Map<String, List<TournamentPlayer>> rosters;
  final String initialDay;
  const _ActiveTournamentTab({
    required this.tournament,
    required this.teams,
    required this.matches,
    required this.rosters,
    required this.initialDay,
  });
}
```

- [ ] **Step 2: Stop filtering matches in `_loadActiveTournaments`**

The method currently reads (around lines 87-111):

```dart
  /// Loads every active (not-finished) tournament that has a current game day,
  /// keeping only that day's matches. Tournaments whose games are all in the
  /// past (or that have none) are skipped, so finished games fall off the home
  /// screen the same way a finished league season does.
  Future<void> _loadActiveTournaments() async {
    final tournaments = await TournamentService.getActiveTournaments();
    final bundles = await Future.wait(tournaments.map((t) async {
      final teams = await TournamentService.getTeams(t.id);
      final matches = await TournamentService.getMatches(t.id);
      final day = currentGameDay(matches.map((m) => m.date));
      if (day == null) return null;
      final dayMatches = matches.where((m) => m.date == day).toList();
      final rosters = await TournamentService.getRosters(t.id, teams);
      return _ActiveTournamentTab(
        tournament: t,
        teams: teams,
        matches: dayMatches,
        rosters: rosters,
      );
    }));
    activeTournaments = [
      for (final b in bundles)
        if (b != null) b,
    ];
  }
```

Replace it with (keeps the `day == null` skip rule; keeps ALL matches; passes
`initialDay`):

```dart
  /// Loads every active (not-finished) tournament that has a current game day,
  /// keeping ALL of its matches so the home-tab day strip can switch between
  /// days. Tournaments whose games are all in the past (or that have none) are
  /// skipped, so finished games fall off the home screen the same way a
  /// finished league season does.
  Future<void> _loadActiveTournaments() async {
    final tournaments = await TournamentService.getActiveTournaments();
    final bundles = await Future.wait(tournaments.map((t) async {
      final teams = await TournamentService.getTeams(t.id);
      final matches = await TournamentService.getMatches(t.id);
      final day = currentGameDay(matches.map((m) => m.date));
      if (day == null) return null;
      final rosters = await TournamentService.getRosters(t.id, teams);
      return _ActiveTournamentTab(
        tournament: t,
        teams: teams,
        matches: matches,
        rosters: rosters,
        initialDay: day,
      );
    }));
    activeTournaments = [
      for (final b in bundles)
        if (b != null) b,
    ];
  }
```

- [ ] **Step 3: Use `TournamentDayView` in `_buildTournamentTab`**

In `_buildTournamentTab`, the matches are currently rendered (around lines 373-383)
as:

```dart
      Divider(color: Theme.of(context).dividerColor),
      Expanded(
        child: FixturesTab(
          matches: data.matches,
          teams: data.teams,
          rosters: data.rosters,
          tournamentId: data.tournament.id,
          sport: sport,
        ),
      ),
    ]);
```

Replace that `Expanded(...)` with:

```dart
      Divider(color: Theme.of(context).dividerColor),
      Expanded(
        child: TournamentDayView(
          matches: data.matches,
          teams: data.teams,
          rosters: data.rosters,
          tournamentId: data.tournament.id,
          sport: sport,
          initialDay: data.initialDay,
        ),
      ),
    ]);
```

- [ ] **Step 4: Fix imports**

At the top of `lib/frontpage.dart`, the line:

```dart
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
```

is now unused (frontpage no longer references `FixturesTab` directly). Replace that
single line with:

```dart
import 'package:infinite_sports_flutter/tournament_tabs/tournament_day_view.dart';
```

- [ ] **Step 5: Run the analyzer on the changed file**

Run: `flutter analyze lib/frontpage.dart`
Expected: "No issues found!" (in particular, no "unused import" for `fixtures_tab`
and no "missing required argument `initialDay`").

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS — all tests green (the new `match_days_test.dart` plus the existing
`game_day_test.dart`, `match_status_test.dart`, `parse_helpers_test.dart`,
`tournament_stage_test.dart`, `tournamentmatch_activity_test.dart`,
`widget_test.dart`).

- [ ] **Step 7: Commit**

```bash
git add lib/frontpage.dart
git commit -m "feat: show tournament day strip on home Matches tab"
```

---

## Task 4: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole package (touched areas clean)**

Run: `flutter analyze`
Expected: No NEW issues in `lib/misc/match_days.dart`,
`lib/tournament_tabs/tournament_day_view.dart`, or `lib/frontpage.dart`. (Pre-existing
issues elsewhere are out of scope — note them but do not fix them here.)

- [ ] **Step 2: Run the full test suite once more**

Run: `flutter test`
Expected: PASS — all tests green.

- [ ] **Step 3: Manual device/emulator check**

Run: `flutter run`
Verify on the Matches tab:
1. Each active tournament shows a horizontal day strip above its match list.
2. The strip opens with the current game day highlighted (app red), and that pill
   is scrolled into view when there are many days.
3. Swiping/scrolling left to a past day shows that day's matches with **Final**
   scores; scrolling right to an upcoming day shows **kickoff times**.
4. Tapping a pill switches the list to that day; the date header above the cards
   matches the selected pill.
5. A tournament with only one match day shows no strip (just the day's matches).
6. Tapping the tournament header card still opens the full tournament detail page,
   and that page's fixture list is unchanged (all days, no strip).
7. A finished tournament (all matches in the past) does not appear on the Matches
   tab.

- [ ] **Step 4: Complete the development branch**

Announce: "I'm using the finishing-a-development-branch skill to complete this work."
**REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch. Keep commits
local unless the owner explicitly asks to push.

---

## Self-Review (completed by plan author)

**1. Spec coverage:**
- Strip location = home tab only → Task 3 (`_buildTournamentTab` only; `FixturesTab`
  and detail page untouched). ✓
- Swipeable day-pill strip, primary-color highlight, weekday + day number,
  auto-scroll selected into view → Task 2. ✓
- All match days, ascending → Task 1 (`sortedMatchDays`). ✓
- Default = current game day, computed via `currentGameDay` → Task 3 passes
  `initialDay`; Task 2 selects it. ✓
- Active-tournament skip rule unchanged (`day == null` guard kept) → Task 3 Step 2. ✓
- Only selected day's matches to `FixturesTab` (no regression) → Task 2
  (`_matchesForSelectedDay`). ✓
- Full date header disambiguates months → reused from unchanged `FixturesTab`. ✓
- Badge logic unchanged → no edits to `fixtures_tab.dart` / `match_status.dart`. ✓
- Single-day edge case → Task 2 (`_days.length <= 1` → no strip). ✓
- Tests for helper + analyze + manual → Tasks 1 and 4. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/vague steps; every code step
shows complete code and every run step shows the exact command + expected output.

**3. Type consistency:** `sortedMatchDays(Iterable<String>) -> List<String>` is
defined in Task 1 and consumed in Task 2. `TournamentDayView`'s constructor params
(`matches`, `teams`, `rosters`, `tournamentId`, `sport`, `initialDay`) defined in
Task 2 match the call site in Task 3. `_ActiveTournamentTab.initialDay` added in
Task 3 Step 1 is supplied in Step 2 and read in Step 3. `parseDatabaseDate` and
`infiniteSportsPrimaryColor` come from `utility.dart` as used elsewhere in the repo.
