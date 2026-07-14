# Glass Bottom Nav + Search Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the docked Material NavigationBar with a floating frosted-glass pill (Matches, Leagues, Tournaments, Calendar) plus a detached round search button opening a new Search + Hub page; Around You moves into the hub; Calendar tab shows a temporary upcoming-events list.

**Architecture:** A reusable `GlassSurface` widget (BackdropFilter blur + theme-aware translucent tint) powers a new `GlassNavBar` placed in the Scaffold's `bottomNavigationBar` slot with `extendBody: true` so content scrolls and blurs underneath. A pure-Dart `SearchIndex` aggregates already-available data (team logos map, tournaments, users, events) for client-side search. No backend changes.

**Tech Stack:** Flutter (Dart 3.3.4), `dart:ui` ImageFilter (core, no new deps), Firebase RTDB reads via existing helpers in `lib/misc/utility.dart`.

**Spec:** `docs/superpowers/specs/2026-07-13-bottom-nav-glass-design.md`

**Base branch:** `origin/zaya-features` (NOT `zaya-league-exp` — that's a different epic under owner testing). Work happens in a dedicated worktree so the main checkout stays free for another session.

**Verified facts about the base branch (origin/zaya-features):**
- `lib/main.dart` is byte-identical to the version on `zaya-league-exp` described below.
- `TournamentDetailPage({required String tournamentId, required String tournamentName})` in `lib/tournamentdetail.dart`.
- `ShowLeaguePage({required this.sport, required this.season})` in `lib/showleague.dart`.
- `PlayerPage({required this.uid})` in `lib/playerpage.dart` (uid = Firebase Users uid; navbar.dart pushes it with `FirebaseAuth.instance.currentUser!.uid`).
- `TournamentService.getAllTournaments()` in `lib/misc/tournament_service.dart` returns `List<Tournament>`; `Tournament` has `id`, `name`, `sport`, `edition`, `logoUrl`.
- `teamLogos` global in `lib/misc/utility.dart` (line ~29), shape `teamLogos[sport][season][teamName] = url` for "Futsal" / "Basketball" / "Flag Football", PLUS a special key `teamLogos["AFC San Jose"]` whose value is a plain URL string (skip it when iterating).
- `getEvents()` (utility.dart ~1163) returns `List<Event>`; events are identified by list index; `EventPage({required this.index})`.
- `getAllUsers()` (utility.dart ~1201) returns `Map<String, MyUser>`; `MyUser` has `firstName`, `lastName`, `profileURL` (may be null), `uid`.
- `parseDatabaseDate(String)` exists in utility.dart and returns `DateTime?` from `MMDDYYYY` strings.
- `lib/model/event.dart` `Event.format()` converts `eventDate`/`date` to display strings in place.
- `.env` is gitignored — must be copied into the worktree or builds fail.
- There is no `league_team_detail.dart` on zaya-features (it's league-exp work) — team search results therefore open `ShowLeaguePage` for the team's sport+season.

---

### Task 0: Worktree + branch setup

**Files:** none (git only)

- [ ] **Step 1: Create the worktree on a new branch off zaya-features**

Run (from `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`):
```bash
git fetch origin zaya-features
git worktree add .claude/worktrees/zaya-nav-glass -b zaya-nav-glass origin/zaya-features
```
Expected: `Preparing worktree (new branch 'zaya-nav-glass')`.

- [ ] **Step 2: Bring the spec + plan docs onto the branch**

From the worktree directory `.claude/worktrees/zaya-nav-glass`:
```bash
git cherry-pick bcd836a
```
(Commit `bcd836a` is docs-only: the design spec. If the plan doc was committed on zaya-league-exp in a later commit, cherry-pick that sha too.)
Expected: clean cherry-pick, no conflicts (new file).

- [ ] **Step 3: Copy gitignored config into the worktree**

```bash
cp "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/.env" "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/.claude/worktrees/zaya-nav-glass/.env"
```

- [ ] **Step 4: Verify the app compiles in the worktree**

From the worktree:
```bash
flutter pub get
dart analyze lib --no-fatal-warnings
```
Expected: pub get succeeds; analyze reports pre-existing infos/warnings only, no new errors. (Note: full `flutter analyze` can hang in this repo — use `dart analyze`.)

**All remaining tasks run inside the worktree: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter\.claude\worktrees\zaya-nav-glass`**

---

### Task 1: GlassSurface widget

**Files:**
- Create: `lib/widgets/glass_surface.dart`
- Test: `test/widgets/glass_surface_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/glass_surface.dart';

void main() {
  testWidgets('GlassSurface renders its child', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GlassSurface(child: Text('hello'))),
    ));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('GlassSurface uses a dark tint in dark mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(body: GlassSurface(child: Text('x'))),
    ));
    final container = tester.widget<Container>(find.descendant(
      of: find.byType(GlassSurface), matching: find.byType(Container)).first);
    final color = (container.decoration as BoxDecoration).color!;
    expect(color.computeLuminance() < 0.5, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/glass_surface_test.dart`
Expected: FAIL — `glass_surface.dart` does not exist.

- [ ] **Step 3: Implement GlassSurface**

```dart
import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass surface: blurs whatever is painted behind it and lays a
/// translucent theme-aware tint plus hairline border on top. The app-wide
/// glass building block — the nav pill and search button use it first.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark
        ? Colors.black.withOpacity(0.38)
        : Colors.white.withOpacity(0.60);
    final edge = isDark
        ? Colors.white.withOpacity(0.16)
        : Colors.black.withOpacity(0.08);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: borderRadius,
            border: Border.all(color: edge, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/glass_surface_test.dart`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/glass_surface.dart test/widgets/glass_surface_test.dart
git commit -m "feat(nav-glass): reusable GlassSurface frosted widget"
```

---

### Task 2: GlassNavBar widget

**Files:**
- Create: `lib/widgets/glass_nav_bar.dart`
- Test: `test/widgets/glass_nav_bar_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';

Widget _host({required int selected, required void Function(int) onTab, required VoidCallback onSearch}) {
  return MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: const SizedBox.expand(),
      bottomNavigationBar: GlassNavBar(
        destinations: const [
          GlassNavDestination(icon: Icon(Icons.sports_soccer), label: 'Matches'),
          GlassNavDestination(icon: Icon(Icons.shield_outlined), label: 'Leagues'),
          GlassNavDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Tournaments'),
          GlassNavDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Calendar'),
        ],
        selectedIndex: selected,
        onDestinationSelected: onTab,
        onSearchTap: onSearch,
      ),
    ),
  );
}

void main() {
  testWidgets('tapping a destination reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(_host(selected: 0, onTab: (i) => tapped = i, onSearch: () {}));
    await tester.tap(find.text('Calendar'));
    expect(tapped, 3);
  });

  testWidgets('tapping the search circle fires onSearchTap', (tester) async {
    var searched = false;
    await tester.pumpWidget(_host(selected: 0, onTab: (_) {}, onSearch: () => searched = true));
    await tester.tap(find.byIcon(Icons.search));
    expect(searched, isTrue);
  });

  testWidgets('shows all four labels', (tester) async {
    await tester.pumpWidget(_host(selected: 0, onTab: (_) {}, onSearch: () {}));
    for (final label in ['Matches', 'Leagues', 'Tournaments', 'Calendar']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/glass_nav_bar_test.dart`
Expected: FAIL — `glass_nav_bar.dart` does not exist.

- [ ] **Step 3: Implement GlassNavBar**

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/widgets/glass_surface.dart';

class GlassNavDestination {
  const GlassNavDestination({required this.icon, this.selectedIcon, required this.label});
  final Widget icon;
  final Widget? selectedIcon;
  final String label;
}

/// Floating frosted pill of tab destinations plus a detached round search
/// button (FotMob-style). Designed for the Scaffold.bottomNavigationBar slot
/// with extendBody: true so page content scrolls and blurs underneath.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSearchTap,
  });

  final List<GlassNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSearchTap;

  static const double _barHeight = 62;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unselected = scheme.onSurface.withOpacity(0.65);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? bottomInset : 10),
      child: Row(
        children: [
          Expanded(
            child: GlassSurface(
              borderRadius: const BorderRadius.all(Radius.circular(31)),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  height: _barHeight,
                  child: Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.all(Radius.circular(31)),
                            onTap: () => onDestinationSelected(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconTheme(
                                  data: IconThemeData(
                                    size: 24,
                                    color: i == selectedIndex ? scheme.primary : unselected,
                                  ),
                                  child: (i == selectedIndex
                                          ? destinations[i].selectedIcon
                                          : null) ??
                                      destinations[i].icon,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  destinations[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == selectedIndex
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: i == selectedIndex ? scheme.primary : unselected,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(31)),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(31)),
                onTap: onSearchTap,
                child: SizedBox(
                  width: _barHeight,
                  height: _barHeight,
                  child: Icon(Icons.search, size: 26, color: scheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/glass_nav_bar_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/glass_nav_bar.dart test/widgets/glass_nav_bar_test.dart
git commit -m "feat(nav-glass): floating GlassNavBar pill with detached search button"
```

---

### Task 3: Event date parsing + upcoming-events helper

**Files:**
- Modify: `lib/model/event.dart`
- Create: `lib/misc/event_utils.dart`
- Test: `test/misc/event_utils_test.dart`

- [ ] **Step 1: Add a parsed DateTime to Event**

In `lib/model/event.dart`, add a field and set it in `format()` BEFORE the string conversion (raw `eventDate` is `MMDDYYYY`):

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

class Event {
  String? address;
  String? date;
  String? endTime;
  String? eventDate;
  String? imageUrl;
  String? info;
  String? location;
  String? startTime;
  String? title;
  List<Map<String, String>>? buttons;
  Map<String, String>? attendees;
  Image? imageSrc;
  DateTime? eventDateTime;

  void format() {
    eventDateTime = parseDatabaseDate(eventDate!);
    eventDate = convertDatabaseDateToFormatDate(eventDate!);
    date = convertDatabaseDateToFormatDate(date!);
    if (imageUrl != null) {
      imageSrc = Image.network(imageUrl!, errorBuilder:(context, error, stackTrace) => SizedBox(width: 0, height: 0));
    }
  }
}
```

(Verify `parseDatabaseDate` is public in utility.dart — it is referenced at line ~101. If it has a different exact name, use that name.)

- [ ] **Step 2: Write the failing test for upcomingEvents**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/model/event.dart';

Event _event(String title, DateTime? when) {
  final e = Event();
  e.title = title;
  e.eventDateTime = when;
  return e;
}

void main() {
  final now = DateTime(2026, 7, 13, 15, 30);

  test('keeps today and future events, drops past, sorts ascending', () {
    final events = [
      _event('past', DateTime(2026, 7, 1)),
      _event('later', DateTime(2026, 9, 1)),
      _event('today', DateTime(2026, 7, 13)),
      _event('soon', DateTime(2026, 7, 20)),
    ];
    final result = upcomingEvents(events, now);
    expect(result.map((e) => e.value.title).toList(), ['today', 'soon', 'later']);
  });

  test('preserves original list indexes for EventPage navigation', () {
    final events = [
      _event('past', DateTime(2026, 1, 1)),
      _event('future', DateTime(2026, 12, 1)),
    ];
    final result = upcomingEvents(events, now);
    expect(result.single.key, 1);
  });

  test('skips events with unparseable dates', () {
    final result = upcomingEvents([_event('broken', null)], now);
    expect(result, isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/misc/event_utils_test.dart`
Expected: FAIL — `event_utils.dart` does not exist.

- [ ] **Step 4: Implement upcomingEvents**

`lib/misc/event_utils.dart`:

```dart
import 'package:infinite_sports_flutter/model/event.dart';

/// Events happening today or later, soonest first, keyed by their original
/// index in the Events list (EventPage addresses events by list index).
List<MapEntry<int, Event>> upcomingEvents(List<Event> events, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final result = <MapEntry<int, Event>>[];
  for (var i = 0; i < events.length; i++) {
    final when = events[i].eventDateTime;
    if (when == null || when.isBefore(today)) continue;
    result.add(MapEntry(i, events[i]));
  }
  result.sort((a, b) => a.value.eventDateTime!.compareTo(b.value.eventDateTime!));
  return result;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/misc/event_utils_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/model/event.dart lib/misc/event_utils.dart test/misc/event_utils_test.dart
git commit -m "feat(nav-glass): Event.eventDateTime + upcomingEvents helper"
```

---

### Task 4: Calendar tab placeholder (upcoming events list)

**Files:**
- Create: `lib/calendar_tab.dart`

No practical widget test (depends on Firebase `getEvents()`); logic is already unit-tested via `upcomingEvents`. Manual verification in Task 8.

- [ ] **Step 1: Implement CalendarTab**

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/event.dart';

/// Temporary Calendar tab: a simple upcoming-events list backed by the
/// existing Events node. Swapped wholesale for the real calendar in the next
/// piece of the epic (see docs/superpowers/specs/2026-07-13-bottom-nav-glass-design.md).
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  Future<List<MapEntry<int, Event>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MapEntry<int, Event>>> _load() async {
    final events = await getEvents();
    return upcomingEvents(events, DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const ImageIcon(AssetImage('assets/profile.png')),
              onPressed: () {
                Scaffold.of(mainScaffoldContext!).openDrawer();
              },
            );
          },
        ),
        centerTitle: true,
        title: Image.asset('assets/infinitelarge_dark.png', height: 30),
        actions: [
          IconButton(
            onPressed: () => setState(() { _future = _load(); }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final upcoming = snapshot.data ?? const <MapEntry<int, Event>>[];
          if (upcoming.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month_outlined, size: 56,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  const Text('No upcoming events — stay tuned!'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: upcoming.length,
            itemBuilder: (context, i) {
              final event = upcoming[i].value;
              return ListTile(
                leading: event.imageSrc == null
                    ? const Icon(Icons.event)
                    : SizedBox(width: 48, height: 48,
                        child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: event.imageSrc!)),
                title: Text(event.title ?? ''),
                subtitle: Text('on ${event.eventDate}\nat ${event.location}\n${event.startTime} - ${event.endTime}'),
                isThreeLine: true,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) {
                    return EventPage(index: upcoming[i].key);
                  }));
                },
              );
            },
          );
        },
      ),
    );
  }
}
```

Note: `ListView.builder` is left with default padding on purpose — the ambient `MediaQuery` bottom padding (added by `extendBody: true`) keeps the last row scrollable above the glass bar.

- [ ] **Step 2: Analyze**

Run: `dart analyze lib/calendar_tab.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/calendar_tab.dart
git commit -m "feat(nav-glass): Calendar tab placeholder with upcoming events list"
```

---

### Task 5: SearchIndex (pure Dart, unit-tested)

**Files:**
- Create: `lib/misc/search_index.dart`
- Test: `test/misc/search_index_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/search_index.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';

void main() {
  SearchIndex build() {
    final index = SearchIndex();
    index.addTeamsAndLeagues({
      'Futsal': {
        '1': {'FC Barca': 'http://logo/barca1.png'},
        '2': {'FC Barca': 'http://logo/barca2.png', 'Inter': 'http://logo/inter.png'},
      },
      'AFC San Jose': 'http://logo/afc.png',
    });
    index.addTournaments([
      const Tournament(id: 't1', name: 'Summer Cup', sport: 'Soccer', edition: '2026', status: 'Live', finished: false),
    ]);
    index.addUsers({
      'uid1': MyUser('Zaya', 'Arami', '01012020', 'uid1'),
    });
    final e = Event();
    e.title = 'Futsal Finals Night';
    e.location = 'San Jose';
    index.addEvents([e]);
    return index;
  }

  test('finds teams case-insensitively, newest season wins, deduped', () {
    final hits = build().query('barca');
    expect(hits.length, 1);
    expect(hits.single.type, SearchResultType.team);
    expect(hits.single.season, '2');
  });

  test('skips the AFC San Jose string entry without crashing', () {
    expect(() => build().query('afc'), returnsNormally);
  });

  test('finds tournaments, players, events and groups by type order', () {
    final hits = build().query('u');
    final types = hits.map((h) => h.type).toList();
    expect(types, equals([...types]..sort((a, b) => a.index.compareTo(b.index))),
        reason: 'results must be grouped in enum order');
  });

  test('player results carry the uid', () {
    final hits = build().query('zaya');
    expect(hits.single.type, SearchResultType.player);
    expect(hits.single.uid, 'uid1');
  });

  test('event results carry the original list index', () {
    final hits = build().query('finals');
    expect(hits.single.type, SearchResultType.event);
    expect(hits.single.eventIndex, 0);
  });

  test('empty query returns nothing', () {
    expect(build().query('  '), isEmpty);
  });
}
```

(Check `MyUser`'s constructor signature in `lib/model/myuser.dart` before writing the test — the positional order used above matches `getAllUsers()` in utility.dart: firstName, lastName, dateJoined, uid, [profileURL].)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/misc/search_index_test.dart`
Expected: FAIL — `search_index.dart` does not exist.

- [ ] **Step 3: Implement SearchIndex**

```dart
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';

enum SearchResultType { team, league, tournament, player, event }

class SearchResult {
  const SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.sport,
    this.season,
    this.tournamentId,
    this.uid,
    this.eventIndex,
  });

  final SearchResultType type;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? sport;
  final String? season;
  final String? tournamentId;
  final String? uid;
  final int? eventIndex;
}

/// Client-side search over data the app already loads: the team-logos map,
/// tournaments, registered users, and events. Rebuilt each time the search
/// page opens — no persistence, no backend.
class SearchIndex {
  final List<SearchResult> _entries = [];

  /// teamLogos shape: {sport: {season: {teamName: url}}} — except the
  /// "AFC San Jose" key, whose value is a plain URL string (skipped here).
  void addTeamsAndLeagues(Map logos) {
    logos.forEach((sportKey, seasonsVal) {
      if (seasonsVal is! Map) return;
      final sport = sportKey.toString();
      final seasonEntries = seasonsVal.entries.toList()
        ..sort((a, b) => (int.tryParse(b.key.toString()) ?? 0)
            .compareTo(int.tryParse(a.key.toString()) ?? 0));
      final seenTeams = <String>{};
      for (final se in seasonEntries) {
        final season = se.key.toString();
        final teams = se.value;
        if (teams is! Map) continue;
        _entries.add(SearchResult(
          type: SearchResultType.league,
          title: '$sport Season $season',
          subtitle: 'League',
          sport: sport,
          season: season,
        ));
        teams.forEach((teamKey, url) {
          final team = teamKey.toString();
          if (!seenTeams.add(team.toLowerCase())) return;
          _entries.add(SearchResult(
            type: SearchResultType.team,
            title: team,
            subtitle: '$sport · Season $season',
            imageUrl: url?.toString(),
            sport: sport,
            season: season,
          ));
        });
      }
    });
  }

  void addTournaments(List<Tournament> tournaments) {
    for (final t in tournaments) {
      _entries.add(SearchResult(
        type: SearchResultType.tournament,
        title: t.name,
        subtitle: '${t.sport} · ${t.edition}'.trim(),
        imageUrl: t.logoUrl,
        tournamentId: t.id,
      ));
    }
  }

  void addUsers(Map<String, MyUser> users) {
    users.forEach((uid, user) {
      final name = '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim();
      if (name.isEmpty) return;
      _entries.add(SearchResult(
        type: SearchResultType.player,
        title: name,
        subtitle: 'Player',
        imageUrl: user.profileURL,
        uid: uid,
      ));
    });
  }

  void addEvents(List<Event> events) {
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if ((e.title ?? '').isEmpty) continue;
      _entries.add(SearchResult(
        type: SearchResultType.event,
        title: e.title!,
        subtitle: [e.eventDate, e.location]
            .where((s) => (s ?? '').isNotEmpty)
            .join(' · '),
        imageUrl: e.imageUrl,
        eventIndex: i,
      ));
    }
  }

  List<SearchResult> query(String q, {int limitPerType = 6}) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final byType = <SearchResultType, List<SearchResult>>{};
    for (final entry in _entries) {
      if (!entry.title.toLowerCase().contains(needle)) continue;
      final bucket = byType.putIfAbsent(entry.type, () => []);
      if (bucket.length < limitPerType) bucket.add(entry);
    }
    return [
      for (final type in SearchResultType.values) ...?byType[type],
    ];
  }
}
```

(Adjust `user.firstName ?? ''` if `MyUser` fields are non-nullable — check the model; if non-nullable drop the `?? ''`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/misc/search_index_test.dart`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/misc/search_index.dart test/misc/search_index_test.dart
git commit -m "feat(nav-glass): client-side SearchIndex over teams/leagues/tournaments/players/events"
```

---

### Task 6: Search + Hub page

**Files:**
- Create: `lib/search_hub_page.dart`

- [ ] **Step 1: Implement SearchHubPage**

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/aroundyou.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/search_index.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';

/// Search across the app plus the hub of extra sections (Around You today;
/// future sections each add one card here).
class SearchHubPage extends StatefulWidget {
  const SearchHubPage({super.key});

  @override
  State<SearchHubPage> createState() => _SearchHubPageState();
}

class _SearchHubPageState extends State<SearchHubPage> {
  final TextEditingController _controller = TextEditingController();
  Future<SearchIndex>? _indexFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _indexFuture = _buildIndex();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<SearchIndex> _buildIndex() async {
    final index = SearchIndex();
    try {
      await getAllTeamLogo();
      index.addTeamsAndLeagues(teamLogos);
    } catch (_) {}
    try {
      index.addTournaments(await TournamentService.getAllTournaments());
    } catch (_) {}
    try {
      index.addEvents(await getEvents());
    } catch (_) {}
    try {
      index.addUsers(await getAllUsers());
    } catch (_) {}
    return index;
  }

  void _open(SearchResult result) {
    switch (result.type) {
      case SearchResultType.team:
      case SearchResultType.league:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return ShowLeaguePage(sport: result.sport!, season: result.season!);
        }));
      case SearchResultType.tournament:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return TournamentDetailPage(
              tournamentId: result.tournamentId!, tournamentName: result.title);
        }));
      case SearchResultType.player:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return PlayerPage(uid: result.uid!);
        }));
      case SearchResultType.event:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return EventPage(index: result.eventIndex!);
        }));
    }
  }

  static const Map<SearchResultType, String> _sectionTitles = {
    SearchResultType.team: 'Teams',
    SearchResultType.league: 'Leagues',
    SearchResultType.tournament: 'Tournaments',
    SearchResultType.player: 'Players',
    SearchResultType.event: 'Events',
  };

  static const Map<SearchResultType, IconData> _fallbackIcons = {
    SearchResultType.team: Icons.shield_outlined,
    SearchResultType.league: Icons.format_list_numbered,
    SearchResultType.tournament: Icons.emoji_events_outlined,
    SearchResultType.player: Icons.person_outline,
    SearchResultType.event: Icons.event,
  };

  Widget _resultTile(SearchResult result) {
    return ListTile(
      leading: (result.imageUrl ?? '').isNotEmpty
          ? CircleAvatar(
              backgroundColor: Colors.transparent,
              foregroundImage: NetworkImage(result.imageUrl!),
              onForegroundImageError: (_, __) {},
              child: Icon(_fallbackIcons[result.type]),
            )
          : CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(_fallbackIcons[result.type]),
            ),
      title: Text(result.title),
      subtitle: result.subtitle.isEmpty ? null : Text(result.subtitle),
      onTap: () => _open(result),
    );
  }

  Widget _hub() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Explore', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const ImageIcon(AssetImage('assets/aroundyou.png'), size: 32),
            title: const Text('Around You'),
            subtitle: const Text('Businesses and events near you'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return const AroundYou();
              }));
            },
          ),
        ),
      ],
    );
  }

  Widget _results(SearchIndex index) {
    final hits = index.query(_query);
    if (hits.isEmpty) {
      return const Center(child: Text('No results'));
    }
    final children = <Widget>[];
    SearchResultType? lastType;
    for (final hit in hits) {
      if (hit.type != lastType) {
        lastType = hit.type;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(_sectionTitles[hit.type]!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
        ));
      }
      children.add(_resultTile(hit));
    }
    return ListView(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search teams, players, events...',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() { _query = value; }),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() { _query = ''; });
              },
            ),
        ],
      ),
      body: FutureBuilder(
        future: _indexFuture,
        builder: (context, snapshot) {
          if (_query.trim().isEmpty) {
            return _hub();
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return _results(snapshot.data!);
        },
      ),
    );
  }
}
```

Style note: the AppBar TextField inherits the AppBar's foreground styling. On this app AppBars are primary-red with white foreground — verify the hint/input text is legible in both modes on device; if not, set `style`/`hintStyle` with `Theme.of(context).appBarTheme` colors explicitly.

- [ ] **Step 2: Analyze**

Run: `dart analyze lib/search_hub_page.dart`
Expected: no errors. (If `ShowLeaguePage`'s file or ctor differs, fix the import/call to match `lib/showleague.dart` on this branch.)

- [ ] **Step 3: Commit**

```bash
git add lib/search_hub_page.dart
git commit -m "feat(nav-glass): search + hub page (search bar, grouped results, Around You card)"
```

---

### Task 7: AroundYou back button when pushed

**Files:**
- Modify: `lib/aroundyou.dart` (~line 144, AppBar `leading`)

AroundYou is now pushed from the hub instead of living in a tab. Its AppBar's profile button opens the root drawer, which would be hidden *behind* the pushed route — replace it with a back button when the page can pop.

- [ ] **Step 1: Modify the AppBar leading**

Replace:

```dart
          leading: Builder(
            builder: (context) {
              return IconButton(
                icon: const ImageIcon(AssetImage('assets/profile.png')),
                onPressed: () {
                  Scaffold.of(mainScaffoldContext!).openDrawer();
                },);
            },
          ),
```

With:

```dart
          leading: Navigator.canPop(context)
              ? const BackButton()
              : Builder(
                  builder: (context) {
                    return IconButton(
                      icon: const ImageIcon(AssetImage('assets/profile.png')),
                      onPressed: () {
                        Scaffold.of(mainScaffoldContext!).openDrawer();
                      },);
                  },
                ),
```

- [ ] **Step 2: Analyze and commit**

Run: `dart analyze lib/aroundyou.dart`
Expected: no new errors.

```bash
git add lib/aroundyou.dart
git commit -m "feat(nav-glass): AroundYou shows back button when pushed from hub"
```

---

### Task 8: Wire the new nav into main.dart

**Files:**
- Modify: `lib/main.dart` (imports; `widgetOptions` ~line 177; `Scaffold` ~line 206; `_onItemTapped` ~line 244)

- [ ] **Step 1: Update imports**

Remove `import 'package:infinite_sports_flutter/aroundyou.dart';` and add:

```dart
import 'package:infinite_sports_flutter/calendar_tab.dart';
import 'package:infinite_sports_flutter/search_hub_page.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';
```

- [ ] **Step 2: Swap the 4th tab in widgetOptions**

Replace `const AroundYou(),` (in the `widgetOptions` list) with:

```dart
      const CalendarTab(),
```

- [ ] **Step 3: Replace the Scaffold's bottom bar and enable extendBody**

Replace the whole `bottomNavigationBar: NavigationBar(...)` block (lines ~218-240) and add `extendBody`:

```dart
    return Scaffold(
      drawer: const NavBar(),
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Builder(
        builder: (context) {
          mainScaffoldContext = context;
          return IndexedStack(
              index: _selectedIndex,
              children: widgetOptions
          );
        }
      ),
      bottomNavigationBar: GlassNavBar(
        destinations: const [
          GlassNavDestination(
            icon: ImageIcon(AssetImage('assets/scores.png')),
            label: 'Matches'),
          GlassNavDestination(
            icon: ImageIcon(AssetImage('assets/leagues.png')),
            label: 'Leagues'),
          GlassNavDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Tournaments'),
          GlassNavDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar'),
        ],
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        onSearchTap: _openSearchHub,
      )
    );
```

- [ ] **Step 4: Add _openSearchHub and update _onItemTapped title**

Add to `_MyHomePageState`:

```dart
  void _openSearchHub() {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return const SearchHubPage();
    }));
  }
```

In `_onItemTapped`, change `case 3: { _title = 'Around You'; }` to `case 3: { _title = 'Calendar'; }`. (Keep the `index == 2` lazy-tournaments logic untouched.)

- [ ] **Step 5: Analyze + run all new tests**

```bash
dart analyze lib/main.dart
flutter test test/widgets/ test/misc/
```
Expected: analyze clean; all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "feat(nav-glass): wire GlassNavBar, Calendar tab, search hub into app shell"
```

---

### Task 9: Bottom-padding audit for content under the glass bar

With `extendBody: true`, Flutter adds the bar's height to the body's ambient `MediaQuery` bottom padding. Scrollables that pass `padding: EdgeInsets.zero` (or a padding without a bottom component) strip that inset, leaving their last row stuck under the glass.

**Files:** to be discovered by grep; likely `lib/livescore.dart`, `lib/leagues.dart`, `lib/tournamentspage.dart` and other tab-root screens.

- [ ] **Step 1: Find offenders reachable from the four tabs**

```bash
grep -rn "EdgeInsets.zero" lib --include=*.dart
```

For each hit, decide: is this scrollable visible inside one of the 4 tabs (not in a pushed full-screen page, not in a bottom sheet)? Only those need fixing. (Pushed pages sit above the bar-less route so they're unaffected; `aroundyou.dart`'s sheet lists are no longer under the bar at all.)

- [ ] **Step 2: Fix each offender**

For a tab-visible scrollable using `padding: EdgeInsets.zero`, replace with:

```dart
padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
```

For scrollables with custom padding lacking a bottom component, add `+ MediaQuery.paddingOf(context).bottom` to their bottom value. Leave non-tab scrollables untouched.

- [ ] **Step 3: Analyze changed files, commit**

```bash
dart analyze lib
git add -A lib
git commit -m "fix(nav-glass): keep tab content scrollable above the floating glass bar"
```

---

### Task 10: Full verification + device build

- [ ] **Step 1: Run the whole new test suite**

```bash
flutter test test/widgets/ test/misc/
```
Expected: all PASS. (Skip `test/widget_test.dart` — pre-existing placeholder that boots Firebase and was failing before this work; do not fix it in this branch.)

- [ ] **Step 2: Analyze the whole lib**

```bash
dart analyze lib
```
Expected: no NEW errors/warnings versus the Task 0 baseline.

- [ ] **Step 3: Build and install on the owner's phone**

```bash
flutter build apk --debug
flutter install
```
(Use the same install flow previous pieces used — device connected over USB.)

- [ ] **Step 4: Manual test matrix (walk through with the owner)**

- All 4 tabs open and work; Tournaments still lazy-loads on first tap.
- Content scrolls UNDER the pill and blurs through it; last rows of each tab list remain reachable.
- Dark mode AND light mode: pill legible, active tab red, no unreadable text.
- Calendar tab: shows upcoming events soonest-first, taps into event page, empty state if no future events, refresh works.
- Search: finds a known team, league season, tournament, player, and event; each result opens the right page; clear button works; hub shows when the field is empty.
- Around You from hub: map, sheet, businesses, events all work; back button returns to hub; drawer button gone on pushed page.
- Drawer still opens from Matches/Leagues/Tournaments/Calendar app bars; login/profile/settings unaffected.
- A match push notification (or the goal toast) still deep-links to the match page.

- [ ] **Step 5: STOP for owner sign-off**

Do NOT merge to `zaya-features` until the owner approves on-device. After approval, merge per the standard workflow and remove the worktree.

---

## Self-review notes

- Spec coverage: floating pill + search button (Tasks 1-2, 8), temp Calendar tab (Tasks 3-4), search+hub with Around You card (Tasks 5-6), Around You off the bar (Tasks 7-8), reusable glass (Task 1), padding/error handling (Tasks 4, 6, 9), test matrix from spec (Task 10). AFC San Jose team search is skipped in v1 (string entry in teamLogos; noted in SearchIndex doc comment) — acceptable, AFC has its own seasons UI.
- Type consistency: `GlassNavDestination(icon, selectedIcon, label)` used identically in Tasks 2 and 8; `SearchResult` fields match between Tasks 5 and 6; `upcomingEvents` returns `List<MapEntry<int, Event>>` consumed identically in Task 4.
- Known checks left to executors on purpose: exact `parseDatabaseDate` visibility (Task 3), `MyUser` field nullability (Task 5), AppBar TextField legibility (Task 6) — each has an explicit in-task instruction.
