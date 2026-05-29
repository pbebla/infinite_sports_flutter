# Matches Screen — Day-Driven Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the user app's home "Live Scores" screen into a "Matches" screen that shows one tab per active league and tournament, each limited to its current game day, with multiple tournaments supported, a centered tournament card, and the league-only shortcut buttons hidden on tournament tabs.

**Architecture:** A new pure helper computes the "current game day" from a list of Firebase `MMDDYYYY` date strings. `TournamentService` gains a method returning all not-finished tournaments. `frontpage.dart` loads each active tournament's data, filters its matches to the current game day, and renders one tab per competition (reusing the existing `FixturesTab` and `TournamentDetailPage`). Renames live in `frontpage.dart` and `main.dart`.

**Tech Stack:** Flutter / Dart, Firebase Realtime Database (read-only here), `flutter_test`.

**Repo / branch:** `infinite_sports_flutter` on `zaya/tournament-enhance-app-manager`. No admin-app or Firebase schema changes.

**Conventions:**
- All commits stay **local** — do NOT push.
- Run commands from the repo root: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`.

---

### Task 1: Current-game-day pure helper

**Files:**
- Create: `lib/misc/game_day.dart`
- Test: `test/game_day_test.dart`

This helper is intentionally dependency-free (no Firebase imports) so it unit-tests in isolation and loads fast. Its `MMDDYYYY` parsing mirrors `parseDatabaseDate` in `lib/misc/utility.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/game_day_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/game_day.dart';

void main() {
  final now = DateTime(2026, 5, 29); // reference "today"

  group('currentGameDay', () {
    test('returns today when a match is scheduled today', () {
      final result =
          currentGameDay(['05202026', '05292026', '06012026'], now: now);
      expect(result, '05292026');
    });

    test('returns the earliest future date when nothing is today', () {
      final result =
          currentGameDay(['06152026', '06012026', '05202026'], now: now);
      expect(result, '06012026');
    });

    test('returns null when every date is in the past', () {
      final result = currentGameDay(['05202026', '05012026'], now: now);
      expect(result, isNull);
    });

    test('returns null for an empty list', () {
      expect(currentGameDay(const [], now: now), isNull);
    });

    test('ignores malformed date strings but still finds a valid one', () {
      final result = currentGameDay(['', 'abc', '123', '06012026'], now: now);
      expect(result, '06012026');
    });

    test('today wins even when listed after a future date', () {
      final result = currentGameDay(['06012026', '05292026'], now: now);
      expect(result, '05292026');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/game_day_test.dart`
Expected: FAIL — compile error, `game_day.dart` / `currentGameDay` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/misc/game_day.dart`:

```dart
/// Computes the "current game day" for a competition from its match dates.
///
/// Dates are Firebase MMDDYYYY strings (e.g. "05292026"). This file is kept
/// dependency-free (no Firebase) so it can be unit-tested in isolation; the
/// parsing mirrors parseDatabaseDate in utility.dart.
DateTime? _parseMMDDYYYY(String value) {
  if (value.length != 8) return null;
  final m = int.tryParse(value.substring(0, 2));
  final d = int.tryParse(value.substring(2, 4));
  final y = int.tryParse(value.substring(4, 8));
  if (m == null || d == null || y == null) return null;
  return DateTime(y, m, d);
}

/// Returns the current game-day key (MMDDYYYY) from [dates]:
/// - today, if any date is today;
/// - otherwise the earliest future date;
/// - otherwise null (all dates in the past, or none valid).
///
/// [now] defaults to DateTime.now(); inject it in tests.
String? currentGameDay(Iterable<String> dates, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);

  String? earliestFutureKey;
  DateTime? earliestFutureDate;

  for (final raw in dates) {
    final parsed = _parseMMDDYYYY(raw);
    if (parsed == null) continue;
    final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
    if (dateOnly == today) return raw;
    if (dateOnly.isAfter(today)) {
      if (earliestFutureDate == null || dateOnly.isBefore(earliestFutureDate)) {
        earliestFutureDate = dateOnly;
        earliestFutureKey = raw;
      }
    }
  }
  return earliestFutureKey;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/game_day_test.dart`
Expected: PASS — all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/misc/game_day.dart test/game_day_test.dart
git commit -m "feat: add currentGameDay helper for day-driven match views"
```

---

### Task 2: Active-tournaments service method

**Files:**
- Modify: `lib/misc/tournament_service.dart` (add a method to the `TournamentService` class)

`getAllTournaments()` already reads `/Tournaments`, parses headers, and sorts active-first. The new method is a thin filter to "not finished". (No unit test: it wraps a Firebase read like the other service methods; verified via analyze + manual run.)

- [ ] **Step 1: Add the method**

In `lib/misc/tournament_service.dart`, immediately after the `getCurrentTournamentId()` method (which ends with its closing `}` before `getTournamentHeader`), insert:

```dart
  /// Returns headers for all tournaments whose Finished flag is false.
  /// Order follows getAllTournaments (active-first, newest edition first).
  static Future<List<Tournament>> getActiveTournaments() async {
    final all = await getAllTournaments();
    return all.where((t) => !t.finished).toList();
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/misc/tournament_service.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/misc/tournament_service.dart
git commit -m "feat: add getActiveTournaments to TournamentService"
```

---

### Task 3: Rework frontpage.dart into the day-driven Matches screen

**Files:**
- Modify (full rewrite): `lib/frontpage.dart`

This single task replaces the whole file so it stays compilable at the commit point. It: (a) loads every active tournament with a current game day and keeps only that day's matches; (b) renders one tab per league + one per active tournament; (c) makes the `TabBar` scrollable; (d) centers the tournament card; (e) renames the app-bar title to "Matches"; (f) hides the table/leaderboard shortcut buttons while a tournament tab is selected (via a `ValueNotifier<bool>` updated on tab tap).

> **Known limitation (intended):** the shortcut-button hiding and the league `headerNotifier` update both fire on tab **tap**, not on swipe — this matches the existing code's behavior. Swiping (rather than tapping) to a tab won't update them until the next tap. Acceptable for now.

- [ ] **Step 1: Replace the entire file**

Overwrite `lib/frontpage.dart` with exactly:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/game_day.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/table.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';

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

class FrontPage extends StatefulWidget {
  const FrontPage({super.key, required this.onTitleSelect});
  final Function(String) onTitleSelect;

  @override
  State<FrontPage> createState() => _FrontPageState();
}

class _FrontPageState extends State<FrontPage> {
  String currentSport = "";
  String currentSeason = "";
  String currentAFCSeason = "";
  String currentDate = "";
  String currentAFCDate = "";
  bool isCurrentFinished = false;
  bool isCurrentAFCFinished = false;
  late Future<int> _loadingPage;
  List<Widget> tabs = List.empty(growable: true);
  List<Tab> tabNames = List.empty(growable: true);

  // Parallel to [tabNames]: true when the tab at that index is a tournament tab.
  List<bool> tabIsTournament = List.empty(growable: true);

  // Active tournaments (not finished, each having a current game day).
  List<_ActiveTournamentTab> activeTournaments = [];

  // Drives whether the app-bar table/leaderboard shortcut buttons are hidden
  // (they are league-only and make no sense on a tournament tab).
  final ValueNotifier<bool> _onTournamentTab = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadingPage = getFrontPageValues();
  }

  @override
  void dispose() {
    _onTournamentTab.dispose();
    super.dispose();
  }

  Future<int> getFrontPageValues() async {
    currentSport = await getCurrentSport();
    currentSeason = await getCurrentSeason(currentSport);
    currentAFCSeason = await getAFCCurrentSeason();
    currentDate = await getCurrentDate(currentSport, currentSeason);
    currentAFCDate = await getCurrentDate("AFC San Jose", currentAFCSeason);
    isCurrentFinished = await isSeasonFinished(currentSport, currentSeason);
    isCurrentAFCFinished = await isAFCSeasonFinished(currentAFCSeason);
    await _loadActiveTournaments();
    return 1;
  }

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

  Widget getSportIcon(String sport) {
    switch (sport) {
      case "Futsal":
        return ImageIcon(AssetImage('assets/FutsalLeague.png'), size: windowsDefaultIconSize.toDouble());
      case "Basketball":
        return ImageIcon(AssetImage('assets/BasketLeague.png'), size: windowsDefaultIconSize.toDouble());
      case "Flag Football":
        return ImageIcon(AssetImage('assets/FlagFootballLeague.png'), size: windowsDefaultIconSize.toDouble());
      default:
        return Icon(Icons.sports);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: GlobalAppBar(
          title: Text("Matches"),
          height: AppBar().preferredSize.height,
          tableWidget: ValueListenableBuilder<bool>(
            valueListenable: _onTournamentTab,
            builder: (context, onTournament, _) {
              if (onTournament) return const SizedBox.shrink();
              return ValueListenableBuilder(
                valueListenable: headerNotifier,
                builder: (context, value, child) {
                  return IconButton(
                    onPressed: () {
                      Navigator.push(mainContext!, MaterialPageRoute(builder: (_) => Overlay(
                        initialEntries: [OverlayEntry(
                            builder: (context) {
                              return TablePage(sport: value[0], season: value[1]);
                            })],
                      )));
                    },
                    icon: const ImageIcon(AssetImage('assets/table.png')),
                  );
                },
              );
            },
          ),
          leaderboardWidget: ValueListenableBuilder<bool>(
            valueListenable: _onTournamentTab,
            builder: (context, onTournament, _) {
              if (onTournament) return const SizedBox.shrink();
              return ValueListenableBuilder(
                valueListenable: headerNotifier,
                builder: (context, value, child) {
                  return IconButton(
                    onPressed: () {
                      Navigator.push(mainContext!, MaterialPageRoute(builder: (_) => Overlay(
                        initialEntries: [OverlayEntry(
                            builder: (context) {
                              return LeaderboardPage(sport: value[0], season: value[1]);
                            })],
                      )));
                    },
                    icon: const ImageIcon(AssetImage('assets/leader.png')),
                  );
                },
              );
            },
          ),
        ),
        body: FutureBuilder(
            future: _loadingPage,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    )
                );
              }
              tabs.clear();
              tabNames.clear();
              tabIsTournament.clear();
              if (!isCurrentFinished) {
                tabNames.add(Tab(text: "Infinite Sports"));
                tabIsTournament.add(false);
                tabs.add(Column(children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) {
                            return ShowLeaguePage(sport: currentSport, season: currentSeason);
                          },));
                        },
                        child: Card(
                            elevation: 2,
                            child: SizedBox(
                                width: constraints.maxWidth - 38,
                                height: 70,
                                child: Container(
                                  padding: const EdgeInsets.all(13),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text("Assyrian $currentSport League Season $currentSeason", style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const Spacer(),
                                      getSportIcon(currentSport),
                                    ],
                                  ),
                                )
                            )
                        ),
                      );
                    },
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  Center(child: Text(convertDatabaseDateToFormatDate(currentDate), style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: LiveScorePage(sport: currentSport, season: currentSeason, date: currentDate, onTitleSelect: (String value) { widget.onTitleSelect(value); })
                  )
                ]));
              }
              if (!isCurrentAFCFinished) {
                tabNames.add(Tab(text: "AFC San Jose"));
                tabIsTournament.add(false);
                tabs.add(Column(children: [
                  LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) {
                              return ShowLeaguePage(sport: "AFC San Jose", season: currentAFCSeason);
                            },));
                          },
                          child: Card(
                              elevation: 2,
                              child: SizedBox(
                                  width: constraints.maxWidth - 38,
                                  height: 70,
                                  child: Container(
                                      padding: const EdgeInsets.all(13),
                                      child: Row(
                                        children: [
                                          Flexible(child: Text(currentAFCSeason, style: const TextStyle(fontWeight: FontWeight.bold))),
                                          ImageIcon(AssetImage('assets/FutsalLeague.png'), size: windowsDefaultIconSize.toDouble()),
                                        ],
                                      )
                                  )
                              )
                          ),
                        );
                      }
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  Text(convertDatabaseDateToFormatDate(currentAFCDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                      child: LiveScorePage(sport: "AFC San Jose", season: currentAFCSeason, date: currentAFCDate, onTitleSelect: (String value) {widget.onTitleSelect(value);})
                  )
                ]));
              }
              for (final data in activeTournaments) {
                tabNames.add(Tab(text: data.tournament.name));
                tabIsTournament.add(true);
                tabs.add(_buildTournamentTab(context, data));
              }
              if (tabs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) => executeAfterBuild());
                return DefaultTabController(
                    length: tabs.length,
                    child: Scaffold(
                      appBar: AppBar(
                        leading: IconButton(
                            onPressed: () async {
                              await _refreshData();
                            },
                            icon: const Icon(Icons.refresh)
                        ),
                        title: TabBar(
                          isScrollable: true,
                          tabs: tabNames,
                          onTap: (value) {
                            _onTournamentTab.value = tabIsTournament[value];
                            if (tabNames[value].text == "Infinite Sports") {
                              headerNotifier.value = [currentSport, currentSeason];
                            } else if (tabNames[value].text == "AFC San Jose") {
                              headerNotifier.value = ["AFC San Jose", currentAFCSeason];
                            }
                          },
                        ),
                      ),
                      body: TabBarView(
                        children: tabs,
                      ),
                    )
                );
              }
              return Center(
                child: Card(
                  elevation: 2,
                  shadowColor: Colors.black,
                  color: Colors.white,
                  child: SizedBox(
                    width: 350,
                    height: 70,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      child: const Text("No Upcoming Games,\nStay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  ),
                ),
              );
            }
        )
    );
  }

  /// Builds a home-screen tournament tab: a centered, tappable header card that
  /// opens the full tournament page, followed by that tournament's current
  /// game-day matches (reusing the shared FixturesTab).
  Widget _buildTournamentTab(BuildContext context, _ActiveTournamentTab data) {
    final name = data.tournament.name;
    final sport = data.tournament.sport;
    return Column(children: [
      LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return TournamentDetailPage(
                  tournamentId: data.tournament.id,
                  tournamentName: name,
                );
              }));
            },
            child: Card(
              elevation: 2,
              child: SizedBox(
                width: constraints.maxWidth - 38,
                height: 70,
                child: Container(
                  padding: const EdgeInsets.all(13),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
  }

  Future<void> _refreshData() async {
    _loadingPage = getFrontPageValues();
    await _loadingPage;
    setState(() {});
  }

  void executeAfterBuild() {
    if (tabNames.isEmpty) return;
    _onTournamentTab.value =
        tabIsTournament.isNotEmpty ? tabIsTournament[0] : false;
    if (tabNames[0].text == "Infinite Sports") {
      headerNotifier.value = [currentSport, currentSeason];
    } else if (tabNames[0].text == "AFC San Jose") {
      headerNotifier.value = ["AFC San Jose", currentAFCSeason];
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/frontpage.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/frontpage.dart
git commit -m "feat: day-driven per-competition tabs on Matches screen"
```

---

### Task 4: Rename "Live Scores" → "Matches" in the bottom navigation

**Files:**
- Modify: `lib/main.dart`

The app-bar title was already renamed in Task 3 (`frontpage.dart`). This task covers the two remaining spots in `main.dart`: the screen's default title field and the bottom-nav button label.

- [ ] **Step 1: Rename the default title field**

In `lib/main.dart`, change:

```dart
  String _liveScoresTitle = "Live Scores";
```

to:

```dart
  String _liveScoresTitle = "Matches";
```

- [ ] **Step 2: Rename the bottom-nav label**

In `lib/main.dart`, inside the `NavigationDestination` for the scores tab, change:

```dart
            label: 'Live Scores'),
```

to:

```dart
            label: 'Matches'),
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/main.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: rename Live Scores bottom tab to Matches"
```

---

### Task 5: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: All tests pass **except** the pre-existing `test/widget_test.dart` "Counter increments smoke test", which fails with a `ProviderNotFoundException` / missing counter. That is a stock template test unrelated to this work — leave it. The new `test/game_day_test.dart` and the existing tournament tests must pass.

- [ ] **Step 2: Run analyze on changed files**

Run: `flutter analyze lib/misc/game_day.dart lib/misc/tournament_service.dart lib/frontpage.dart lib/main.dart`
Expected: "No issues found!"

- [ ] **Step 3: Manual verification checklist (on a device/emulator with live data)**

Run: `flutter run`
Confirm:
- The bottom tab and the screen title both read **"Matches"**.
- An active tournament with a game today/upcoming shows its own tab; its header card text is **centered**; tapping the card opens the full tournament page; tapping a game opens that game's detail.
- The tournament tab shows **only the current game day's** matches — finished-today games still appear, long-finished games do not.
- Running two active tournaments produces **two** tournament tabs; the tab bar scrolls sideways when tabs overflow.
- On a tournament tab, the **table and leaderboard** buttons in the title bar are hidden; on a league tab they reappear.
- League tabs (Futsal/Basketball/AFC) behave exactly as before.

- [ ] **Step 4: No commit** (verification only). Report results.

---

## Notes for the implementer

- **Do not push.** All commits remain local until the user explicitly approves a push.
- **Do not delete any files** without confirming with the user first.
- `FixturesTab`, `TournamentDetailPage`, `TournamentService.getTeams/getMatches/getRosters`, and `Tournament`/`TournamentMatch`/`TournamentTeam`/`TournamentPlayer` models already exist and are unchanged by this plan.
- The single `/Tournaments/Current Tournament` pointer is intentionally left untouched; this screen derives "active" from each tournament's `Finished` flag instead.
