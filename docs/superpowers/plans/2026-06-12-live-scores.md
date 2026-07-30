# Live Scores & Real-Time Match Experience — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the fan app's tournament screens update in real time (scores, tables, brackets, timelines) with a running match clock, score-flash, skeleton loading, a Happening-Now rail + Live filter, and an in-app goal toast — fed by a small new match-clock persistence in the Manager app.

**Architecture:** Manager writes a tiny `Clock` object per match (kickoff timestamp + pause accounting). Both apps share identical pure clock math. The fan app switches its tournament reads from one-shot `.get()` to `onValue` streams, enables RTDB disk persistence for instant cached renders, and adds focused presentation widgets.

**Tech Stack:** Flutter, Firebase Realtime Database (`firebase_database`), Riverpod (Manager only), vitest n/a (Dart `flutter test`). No new packages — shimmer is hand-rolled.

---

## Ground rules (every task)

- **Fan app:** `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, branch `zaya/live-scores`. Work in the main checkout (owner tests on-device). Verify branch with `git branch --show-current` before committing.
- **Manager app:** `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, branch `zaya-live-scores`. **Always use absolute paths**, e.g. `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && <cmd>`.
- All commits stay **LOCAL**. Never push unless the owner says so.
- **Fan app:** NEVER stage `PROJECT_REFERENCE.md` or `SoccerStats.png`. Stage exact paths only — never `git add -A`/`git add .`. If `pubspec.lock` shows modified after a flutter command, `git restore pubspec.lock`.
- Match the surrounding code's style. These screens are large; for wiring tasks, change ONLY the data source and insert the new widgets — do not reformat or restructure unrelated code.

### Verified schema & code facts
- Match nodes: `Tournaments/{tid}/Matches/{mid}/` with PascalCase `Status` (int 0 pending / 1 live / 2 finished), `Team1Score`/`Team2Score` (int), `Team1Id`/`Team2Id`, `Team{1|2}Activity/{minute}` (list of single-entry `{EventType: PlayerName}`), `MatchLocation`. Fan model: `lib/model/tournamentmatch.dart` (`TournamentMatch.fromFirebase`, tolerant PascalCase/camelCase + array-with-holes).
- **NEW** node this plan adds: `Tournaments/{tid}/Matches/{mid}/Clock/{StartedAt, PausedAccumMs, PausedAt}` (numbers; `PausedAt` absent while running).
- Manager scoring screen: `lib/ui/tournaments/live_scoring_page.dart`, state class `_ScoringPanelState` (a `ConsumerState`). Local clock fields: `DateTime? _runningSince`, `Duration _elapsedBefore`. Methods `_startClock/_pauseClock/_resumeClock/_stopClock`, `_fmtClock`, `_currentMinute`. Status writes go through `_setStatus(int)`. Service: `ref.read(tournamentServiceProvider)`.
- Manager service: `lib/services/firebase/tournament_service.dart` extends `FirebaseService` which exposes `DatabaseReference ref([String? path])` over `FirebaseDatabase.instance`. Paths in `lib/core/constants/firebase_paths.dart` (has `tournamentMatch(tid,mid)`).
- Fan service: `lib/misc/tournament_service.dart` — static methods using `FirebaseDatabase.instance.ref(...)` + `.get()`. Models built via `TournamentMatch.fromFirebase` etc.
- Fan brand red: `Color.fromARGB(255, 208, 0, 0)`. Tournament header navy used in cards: `Color(0xFF1A237E)`. Live green for clock: `#0A7D2C` (badge) / `#7CFC9A` (on-navy text).

---

## File structure

**Shared pure logic (one in each app — identical math, app-local copies):**
- Fan: `lib/misc/match_clock.dart` + `test/match_clock_test.dart`
- Manager: `lib/services/match_clock.dart` + `test/match_clock_test.dart`

**Manager changes:**
- `lib/core/constants/firebase_paths.dart` — add `tournamentMatchClock`
- `lib/services/firebase/tournament_service.dart` — add `startMatchClock` / `pauseMatchClock` / `resumeMatchClock` / `clearMatchClock`
- `lib/ui/tournaments/live_scoring_page.dart` — call those from the clock buttons; refactor local elapsed to use the shared helper

**Fan new widgets:**
- `lib/widgets/skeleton.dart`, `lib/widgets/score_text.dart`, `lib/widgets/live_clock.dart`, `lib/widgets/live_filter_bar.dart`, `lib/misc/goal_toast.dart`

**Fan changes:**
- `lib/model/tournamentmatch.dart` — parse `Clock` into a `MatchClock`
- `lib/misc/tournament_service.dart` — `watchMatches` / `watchMatch` / `watchTournament` streams
- `lib/main.dart` — `setPersistenceEnabled(true)`
- `lib/frontpage.dart`, `lib/tournamentdetail.dart`, `lib/tournament_match_detail.dart` — live data + widgets

---

## Task 1: Fan — pure MatchClock helper (TDD)

**Files:**
- Create: `lib/misc/match_clock.dart`
- Test: `test/match_clock_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/match_clock_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';

void main() {
  group('MatchClock.elapsed', () {
    test('running: now - startedAt - pausedAccum', () {
      const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 0, pausedAtMs: null);
      expect(c.elapsedAt(61000), const Duration(seconds: 60));
    });
    test('subtracts accumulated pauses while running', () {
      const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 10000, pausedAtMs: null);
      expect(c.elapsedAt(61000), const Duration(seconds: 50));
    });
    test('frozen while paused: uses pausedAt, not now', () {
      const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 0, pausedAtMs: 31000);
      expect(c.elapsedAt(99999), const Duration(seconds: 30));
    });
    test('never negative', () {
      const c = MatchClock(startedAtMs: 5000, pausedAccumMs: 0, pausedAtMs: null);
      expect(c.elapsedAt(1000), Duration.zero);
    });
    test('isPaused reflects pausedAt presence', () {
      expect(const MatchClock(startedAtMs: 0, pausedAccumMs: 0, pausedAtMs: 5).isPaused, true);
      expect(const MatchClock(startedAtMs: 0, pausedAccumMs: 0, pausedAtMs: null).isPaused, false);
    });
  });

  group('labels', () {
    test('minuteLabel is 1-based, min 1', () {
      expect(minuteLabel(Duration.zero), "1'");
      expect(minuteLabel(const Duration(seconds: 59)), "1'");
      expect(minuteLabel(const Duration(seconds: 60)), "2'");
      expect(minuteLabel(const Duration(minutes: 36, seconds: 30)), "37'");
    });
    test('clockLabel is mm:ss zero-padded', () {
      expect(clockLabel(Duration.zero), '00:00');
      expect(clockLabel(const Duration(minutes: 47, seconds: 30)), '47:30');
      expect(clockLabel(const Duration(minutes: 5, seconds: 4)), '05:04');
    });
  });

  group('MatchClock.fromMap', () {
    test('reads PascalCase fields', () {
      final c = MatchClock.fromMap({'StartedAt': 1000, 'PausedAccumMs': 200, 'PausedAt': 3000});
      expect(c, isNotNull);
      expect(c!.startedAtMs, 1000);
      expect(c.pausedAccumMs, 200);
      expect(c.pausedAtMs, 3000);
    });
    test('missing PausedAt means running', () {
      final c = MatchClock.fromMap({'StartedAt': 1000});
      expect(c!.pausedAtMs, isNull);
      expect(c.pausedAccumMs, 0);
    });
    test('null/!map/absent StartedAt -> null (graceful, show LIVE without minute)', () {
      expect(MatchClock.fromMap(null), isNull);
      expect(MatchClock.fromMap('nope'), isNull);
      expect(MatchClock.fromMap({'PausedAccumMs': 5}), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (missing file)

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test test/match_clock_test.dart`
Expected: compile error / file not found.

- [ ] **Step 3: Implement `lib/misc/match_clock.dart`**

```dart
/// Pure match-clock math, shared in spirit with the Manager app's copy at
/// InfiniteSportsManagerFlutter/lib/services/match_clock.dart — keep both in
/// sync. No Flutter imports so it stays unit-testable.
///
/// Stored under Tournaments/{tid}/Matches/{mid}/Clock as:
///   StartedAt     ms timestamp at kickoff
///   PausedAccumMs total ms of COMPLETED pauses (default 0)
///   PausedAt      ms timestamp the current pause began, or absent while running
class MatchClock {
  final int startedAtMs;
  final int pausedAccumMs;
  final int? pausedAtMs;

  const MatchClock({
    required this.startedAtMs,
    required this.pausedAccumMs,
    required this.pausedAtMs,
  });

  bool get isPaused => pausedAtMs != null;

  /// Elapsed play time at wall-clock [nowMs]. Frozen at [pausedAtMs] while paused.
  Duration elapsedAt(int nowMs) {
    final end = pausedAtMs ?? nowMs;
    final ms = end - startedAtMs - pausedAccumMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Builds from the raw `Clock` map. Returns null when there's no usable
  /// StartedAt — callers then show LIVE with no minute.
  static MatchClock? fromMap(Object? raw) {
    if (raw is! Map) return null;
    if (raw['StartedAt'] == null && raw['startedAt'] == null) return null;
    return MatchClock(
      startedAtMs: _toInt(raw['StartedAt'] ?? raw['startedAt']),
      pausedAccumMs: _toInt(raw['PausedAccumMs'] ?? raw['pausedAccumMs']),
      pausedAtMs: (raw['PausedAt'] ?? raw['pausedAt']) == null
          ? null
          : _toInt(raw['PausedAt'] ?? raw['pausedAt']),
    );
  }
}

/// "37'" — 1-based, minimum 1.
String minuteLabel(Duration elapsed) => "${elapsed.inMinutes + 1}'";

/// "47:30" — zero-padded mm:ss.
String clockLabel(Duration elapsed) {
  final mm = elapsed.inMinutes.toString().padLeft(2, '0');
  final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `flutter test test/match_clock_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/misc/match_clock.dart test/match_clock_test.dart
git commit -m "feat: pure MatchClock helper (elapsed math + minute/clock labels)"
```

---

## Task 2: Manager — pure MatchClock helper (TDD, mirror)

**Files:**
- Create: `lib/services/match_clock.dart`
- Test: `test/match_clock_test.dart`

Work in `C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter`. The math MUST match Task 1 exactly (fan/Manager parity). Package name is `infinite_app_manager` (see existing imports).

- [ ] **Step 1: Write the failing test**

Create `test/match_clock_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/services/match_clock.dart';

void main() {
  test('running elapsed', () {
    const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 0, pausedAtMs: null);
    expect(c.elapsedAt(61000), const Duration(seconds: 60));
  });
  test('subtracts pauses', () {
    const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 10000, pausedAtMs: null);
    expect(c.elapsedAt(61000), const Duration(seconds: 50));
  });
  test('frozen while paused', () {
    const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 0, pausedAtMs: 31000);
    expect(c.elapsedAt(99999), const Duration(seconds: 30));
  });
  test('never negative', () {
    const c = MatchClock(startedAtMs: 5000, pausedAccumMs: 0, pausedAtMs: null);
    expect(c.elapsedAt(1000), Duration.zero);
  });
  test('minuteLabel 1-based', () {
    expect(minuteLabel(const Duration(seconds: 60)), "2'");
  });
  test('clockLabel mm:ss', () {
    expect(clockLabel(const Duration(minutes: 47, seconds: 30)), '47:30');
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test test/match_clock_test.dart`
Expected: file not found.

- [ ] **Step 3: Implement `lib/services/match_clock.dart`** — copy Task 1's `match_clock.dart` body verbatim (the class + `minuteLabel` + `clockLabel`), changing only the doc comment's cross-reference to point at the fan file. No other differences.

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/match_clock_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git add lib/services/match_clock.dart test/match_clock_test.dart
git commit -m "feat: pure MatchClock helper (Manager copy, parity with fan app)"
```

---

## Task 3: Manager — persist the clock + use the helper

**Files:**
- Modify: `lib/core/constants/firebase_paths.dart` (after `tournamentMatchKeeper`, ~line 119)
- Modify: `lib/services/firebase/tournament_service.dart` (add clock methods)
- Modify: `lib/ui/tournaments/live_scoring_page.dart` (call them from clock buttons; refactor `_elapsed`)

Work in `C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter`.

- [ ] **Step 1: Add the path constant**

In `firebase_paths.dart`, add after the `tournamentMatchKeeper` method:

```dart
  static String tournamentMatchClock(String tournamentId, String matchId) =>
      '$tournaments/$tournamentId/Matches/$matchId/Clock';
```

- [ ] **Step 2: Add clock write methods to `TournamentService`**

In `lib/services/firebase/tournament_service.dart`, add these methods inside the class (near `appendMatchActivity`). Uses the inherited `ref(path)` and the RTDB server-timestamp sentinel + a transaction for resume:

```dart
  /// Starts the persisted match clock at kickoff (fans compute the live
  /// minute from this). Server timestamp keeps every device in agreement.
  Future<void> startMatchClock(String tournamentId, String matchId) async {
    final path = FirebasePaths.tournamentMatchClock(tournamentId, matchId);
    await ref(path).set({
      'StartedAt': ServerValue.timestamp,
      'PausedAccumMs': 0,
      'PausedAt': null,
    });
  }

  /// Marks the clock paused now (fans freeze the minute at this instant).
  Future<void> pauseMatchClock(String tournamentId, String matchId) async {
    final path = FirebasePaths.tournamentMatchClock(tournamentId, matchId);
    await ref(path).child('PausedAt').set(ServerValue.timestamp);
  }

  /// Resumes: folds the just-finished pause into PausedAccumMs and clears
  /// PausedAt, in one transaction so concurrent writers can't corrupt it.
  Future<void> resumeMatchClock(String tournamentId, String matchId) async {
    final path = FirebasePaths.tournamentMatchClock(tournamentId, matchId);
    await ref(path).runTransaction((current) {
      final map = current == null
          ? <String, Object?>{}
          : Map<String, Object?>.from(current as Map);
      final pausedAt = map['PausedAt'];
      if (pausedAt is int) {
        final accum = (map['PausedAccumMs'] is int) ? map['PausedAccumMs'] as int : 0;
        // Use device now for the delta; small skew vs server time is fine.
        map['PausedAccumMs'] = accum + (DateTime.now().millisecondsSinceEpoch - pausedAt);
      }
      map['PausedAt'] = null;
      return Transaction.success(map);
    });
  }

  /// Removes the clock entirely (match reset to upcoming).
  Future<void> clearMatchClock(String tournamentId, String matchId) async {
    final path = FirebasePaths.tournamentMatchClock(tournamentId, matchId);
    await ref(path).remove();
  }
```

Confirm `ServerValue` and `Transaction` resolve from the existing `package:firebase_database/firebase_database.dart` import already present in this file (it is — `appendMatchActivity` uses `ref`). Add the import if the analyzer flags it.

- [ ] **Step 3: Call the clock methods from the scoring buttons**

In `lib/ui/tournaments/live_scoring_page.dart`, the clock methods currently only manage local state. Make each also persist (the service is `ref.read(tournamentServiceProvider)`; `widget.tournamentId` and `widget.match.id` are in scope). Update the four methods:

```dart
  void _startClock() {
    setState(() {
      _elapsedBefore = Duration.zero;
      _runningSince = DateTime.now();
    });
    _ensureTicker();
    ref.read(tournamentServiceProvider)
        .startMatchClock(widget.tournamentId, widget.match.id);
  }

  void _pauseClock() {
    setState(() {
      _elapsedBefore = _elapsed;
      _runningSince = null;
    });
    _ticker?.cancel();
    _ticker = null;
    ref.read(tournamentServiceProvider)
        .pauseMatchClock(widget.tournamentId, widget.match.id);
  }

  void _resumeClock() {
    setState(() {
      _runningSince = DateTime.now();
    });
    _ensureTicker();
    ref.read(tournamentServiceProvider)
        .resumeMatchClock(widget.tournamentId, widget.match.id);
  }

  void _stopClock() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _elapsedBefore = _elapsed;
      _runningSince = null;
    });
    // Leave the Clock node intact; fans stop ticking because status != 1.
  }
```

If a "reset match to upcoming" action exists (sets status to 0), call `clearMatchClock(...)` there too. Search the file for where status is set to 0; if none exists, skip (no reset path to wire). Report which you found.

- [ ] **Step 4: Verify analyze + tests**

Run: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter analyze lib/services/firebase/tournament_service.dart lib/ui/tournaments/live_scoring_page.dart lib/core/constants/firebase_paths.dart && flutter test`
Expected: no new errors; all tests pass (58+ existing + 6 new from Task 2).

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git add lib/core/constants/firebase_paths.dart lib/services/firebase/tournament_service.dart lib/ui/tournaments/live_scoring_page.dart
git commit -m "feat: persist match Clock (StartedAt/PausedAccumMs/PausedAt) on start/pause/resume"
```

---

## Task 4: Fan — parse the Clock node into the match model

**Files:**
- Modify: `lib/model/tournamentmatch.dart`

Work in the fan app.

- [ ] **Step 1: Add the field + parsing**

In `lib/model/tournamentmatch.dart`: add the import at top:

```dart
import 'package:infinite_sports_flutter/misc/match_clock.dart';
```

Add a field to the class (near `status`):

```dart
  final MatchClock? clock;
```

Add it to the constructor parameter list:

```dart
    this.clock,
```

In `TournamentMatch.fromFirebase`, before the `return TournamentMatch(`, read the Clock node, then pass it:

```dart
    final clock = MatchClock.fromMap(firstNonNull(data, ['Clock', 'clock']));
```

and add `clock: clock,` to the returned constructor call. (`firstNonNull` is already used throughout this factory.)

- [ ] **Step 2: Verify analyze + existing tests**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter analyze lib/model/tournamentmatch.dart && flutter test test/tournamentmatch_activity_test.dart`
Expected: no errors; existing match-parsing tests still pass (clock is optional, defaults null).

- [ ] **Step 3: Commit**

```bash
git add lib/model/tournamentmatch.dart
git commit -m "feat: parse match Clock node into TournamentMatch.clock"
```

---

## Task 5: Fan — real-time stream methods on TournamentService

**Files:**
- Modify: `lib/misc/tournament_service.dart`

Add stream variants alongside the existing `get*` methods. They reuse the same model builders. Keep all existing methods unchanged.

- [ ] **Step 1: Add the imports + streams**

At the top of `lib/misc/tournament_service.dart`, ensure `dart:async` is available (add `import 'dart:async';` if not present).

Add these static methods to the `TournamentService` class:

```dart
  /// Live stream of all matches in a tournament. Emits immediately from
  /// RTDB's local cache (if any) then on every change.
  static Stream<List<TournamentMatch>> watchMatches(String tournamentId) {
    final ref = FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Matches');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <TournamentMatch>[];
      final out = <TournamentMatch>[];
      value.forEach((key, v) {
        if (v is Map) {
          try {
            out.add(TournamentMatch.fromFirebase(key.toString(), v));
          } catch (_) {}
        }
      });
      return out;
    });
  }

  /// Live stream of one match.
  static Stream<TournamentMatch?> watchMatch(String tournamentId, String matchId) {
    final ref = FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Matches/$matchId');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      try {
        return TournamentMatch.fromFirebase(matchId, value);
      } catch (_) {
        return null;
      }
    });
  }

  /// Live stream of the tournament header (status/champion/etc.).
  static Stream<Tournament?> watchTournament(String tournamentId) {
    final ref = FirebaseDatabase.instance.ref('/Tournaments/$tournamentId');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      try {
        return Tournament.fromFirebase(tournamentId, value);
      } catch (_) {
        return null;
      }
    });
  }
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/misc/tournament_service.dart`
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add lib/misc/tournament_service.dart
git commit -m "feat: real-time watchMatches/watchMatch/watchTournament streams"
```

---

## Task 6: Fan — enable RTDB disk persistence

**Files:**
- Modify: `lib/main.dart` (just after `Firebase.initializeApp`)

- [ ] **Step 1: Add the import + enable persistence**

In `lib/main.dart`, add the import:

```dart
import 'package:firebase_database/firebase_database.dart';
```

Immediately AFTER the `await Firebase.initializeApp(...)` call and BEFORE any other database usage, add:

```dart
  // Cache RTDB on disk so tournament pages render instantly from the last
  // known data, then stream fresh updates. Must run before any DB access.
  FirebaseDatabase.instance.setPersistenceEnabled(true);
```

- [ ] **Step 2: Verify it still builds + tests pass**

Run: `flutter analyze lib/main.dart && flutter test`
Expected: no new errors; all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: enable RTDB disk persistence for instant cached renders"
```

---

## Task 7: Fan — Skeleton shimmer widget

**Files:**
- Create: `lib/widgets/skeleton.dart`

No package — a self-animating shimmer box plus prebuilt shapes.

- [ ] **Step 1: Implement `lib/widgets/skeleton.dart`**

```dart
import 'package:flutter/material.dart';

/// A shimmering grey placeholder block. Animates on its own; drop several into
/// a column shaped like the real content while data loads.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.white12
        : Colors.black12;
    final hi = Theme.of(context).brightness == Brightness.dark
        ? Colors.white24
        : Colors.black26;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * _c.value, 0),
                end: Alignment(1 - 2 * _c.value, 0),
                colors: [base, hi, base],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A skeleton placeholder shaped like a match-list row.
class SkeletonMatchRow extends StatelessWidget {
  const SkeletonMatchRow({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          const SkeletonBox(width: 30, height: 30, radius: 15),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 120, height: 11),
                SizedBox(height: 7),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
          const SkeletonBox(width: 26, height: 26),
        ],
      ),
    );
  }
}

/// A column of [count] skeleton match rows separated by dividers.
class SkeletonMatchList extends StatelessWidget {
  final int count;
  const SkeletonMatchList({super.key, this.count = 6});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 1),
          child: SkeletonMatchRow(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/widgets/skeleton.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/skeleton.dart
git commit -m "feat: skeleton shimmer placeholders"
```

---

## Task 8: Fan — ScoreText (flash on increase) (TDD-lite widget test)

**Files:**
- Create: `lib/widgets/score_text.dart`
- Test: `test/score_text_test.dart`

- [ ] **Step 1: Write the widget test**

Create `test/score_text_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/score_text.dart';

Widget _host(int value) => MaterialApp(home: Scaffold(body: Center(child: ScoreText(value: value))));

void main() {
  testWidgets('renders the score value', (tester) async {
    await tester.pumpWidget(_host(2));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('updates when the value changes', (tester) async {
    await tester.pumpWidget(_host(1));
    expect(find.text('1'), findsOneWidget);
    await tester.pumpWidget(_host(2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('2'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (missing file)

Run: `flutter test test/score_text_test.dart`
Expected: file not found.

- [ ] **Step 3: Implement `lib/widgets/score_text.dart`**

```dart
import 'package:flutter/material.dart';

/// A score number that briefly flashes brand red and scales up when its value
/// INCREASES (a goal). Decreases (corrections) and the first build are silent.
class ScoreText extends StatefulWidget {
  final int value;
  final double fontSize;
  final Color baseColor;
  const ScoreText({
    super.key,
    required this.value,
    this.fontSize = 16,
    this.baseColor = const Color(0xFF111111),
  });

  @override
  State<ScoreText> createState() => _ScoreTextState();
}

class _ScoreTextState extends State<ScoreText>
    with SingleTickerProviderStateMixin {
  static const _flash = Color.fromARGB(255, 208, 0, 0);
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late int _shown = widget.value;

  @override
  void didUpdateWidget(covariant ScoreText old) {
    super.didUpdateWidget(old);
    if (widget.value > old.value) {
      _c.forward(from: 0);
    }
    _shown = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // 0 -> 1 -> 0 pulse curve.
        final t = (1 - (2 * _c.value - 1).abs()).clamp(0.0, 1.0);
        final color = Color.lerp(widget.baseColor, _flash, t)!;
        final scale = 1.0 + 0.35 * t;
        return Transform.scale(
          scale: scale,
          child: Text(
            '$_shown',
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/score_text_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/score_text.dart test/score_text_test.dart
git commit -m "feat: ScoreText flashes red and scales on score increase"
```

---

## Task 9: Fan — LiveClock widgets (MinuteBall + MatchClockText)

**Files:**
- Create: `lib/widgets/live_clock.dart`

Both widgets take the match's `MatchClock?` and the live status, run a 1-second ticker only while live & unpaused, and render via the Task 1 helpers.

- [ ] **Step 1: Implement `lib/widgets/live_clock.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';

mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  void startTicking(bool active) {
    _timer?.cancel();
    if (active) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Green circle showing the live minute (e.g. "37'") for match-list rows.
/// If [clock] is null (older matches) it shows "LIVE".
class MinuteBall extends StatefulWidget {
  final MatchClock? clock;
  const MinuteBall({super.key, required this.clock});

  @override
  State<MinuteBall> createState() => _MinuteBallState();
}

class _MinuteBallState extends State<MinuteBall> with _Ticking {
  static const _green = Color(0xFF0A7D2C);

  @override
  void initState() {
    super.initState();
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  void didUpdateWidget(covariant MinuteBall old) {
    super.didUpdateWidget(old);
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    final label = clock == null
        ? 'LIVE'
        : minuteLabel(clock.elapsedAt(DateTime.now().millisecondsSinceEpoch));
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: label == 'LIVE' ? 8 : 11,
        ),
      ),
    );
  }
}

/// Green mm:ss clock text for the game-card header. Hidden (shrinks to nothing)
/// if [clock] is null.
class MatchClockText extends StatefulWidget {
  final MatchClock? clock;
  const MatchClockText({super.key, required this.clock});

  @override
  State<MatchClockText> createState() => _MatchClockTextState();
}

class _MatchClockTextState extends State<MatchClockText> with _Ticking {
  static const _green = Color(0xFF7CFC9A);

  @override
  void initState() {
    super.initState();
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  void didUpdateWidget(covariant MatchClockText old) {
    super.didUpdateWidget(old);
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    if (clock == null) return const SizedBox.shrink();
    final label =
        clockLabel(clock.elapsedAt(DateTime.now().millisecondsSinceEpoch));
    return Text(
      label,
      style: const TextStyle(
        color: _green,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/widgets/live_clock.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/live_clock.dart
git commit -m "feat: MinuteBall + MatchClockText live clock widgets"
```

---

## Task 10: Fan — Live filter bar (Happening Now rail + Live pill)

**Files:**
- Create: `lib/widgets/live_filter_bar.dart`
- Test: `test/live_filter_test.dart`

Pure filter logic is unit-tested; the widgets are simple presenters.

- [ ] **Step 1: Write the failing test for the filter helper**

Create `test/live_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/live_filter_bar.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch _m(int status) => TournamentMatch(
      id: 's$status', stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Score: 0, team2Score: 0, status: status, bracketPosition: 0,
    );

void main() {
  test('liveOnly keeps status==1 only', () {
    final all = [_m(0), _m(1), _m(2), _m(1)];
    expect(liveMatches(all).length, 2);
    expect(liveMatches(all).every((m) => m.status == 1), true);
  });
  test('liveMatches empty when none live', () {
    expect(liveMatches([_m(0), _m(2)]), isEmpty);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/live_filter_test.dart`
Expected: file not found.

- [ ] **Step 3: Implement `lib/widgets/live_filter_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/widgets/live_clock.dart';

/// Pure helper: the live (status==1) subset, preserving order.
List<TournamentMatch> liveMatches(List<TournamentMatch> all) =>
    all.where((m) => m.status == 1).toList();

/// Grey-dot/green-dot "Live" pill for the top of the Matches tab.
class LivePill extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const LivePill({super.key, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF27E07C);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!on),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEAFAF0) : Colors.transparent,
          border: Border.all(color: on ? green : Colors.grey),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  color: on ? green : Colors.grey, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('Live',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? const Color(0xFF0A7D2C) : Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

/// Horizontal "Happening now" rail of live matches. Renders nothing if empty.
/// [onTapMatch] opens the match. Each chip shows "ABBR s-s" + live minute.
class HappeningNowRail extends StatelessWidget {
  final List<TournamentMatch> live;
  final String Function(String teamId) abbr;
  final void Function(TournamentMatch) onTapMatch;
  const HappeningNowRail({
    super.key,
    required this.live,
    required this.abbr,
    required this.onTapMatch,
  });

  @override
  Widget build(BuildContext context) {
    if (live.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            _LiveDot(),
            SizedBox(width: 5),
            Text('HAPPENING NOW',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Color(0xFFFF1F1F))),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: live.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final m = live[i];
                final t1 = m.team1Id == null ? '?' : abbr(m.team1Id!);
                final t2 = m.team2Id == null ? '?' : abbr(m.team2Id!);
                return InkWell(
                  onTap: () => onTapMatch(m),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$t1 ${m.team1Score}–${m.team2Score} $t2',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        const SizedBox(height: 3),
                        _RailMinute(clock: m.clock),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RailMinute extends StatelessWidget {
  final MatchClock? clock;
  const _RailMinute({required this.clock});
  @override
  Widget build(BuildContext context) {
    final label = clock == null
        ? 'LIVE'
        : minuteLabel(clock!.elapsedAt(DateTime.now().millisecondsSinceEpoch));
    return Text(label,
        style: const TextStyle(
            color: Color(0xFF7CFC9A), fontWeight: FontWeight.w700, fontSize: 11));
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(
            color: Color(0xFFFF1F1F), shape: BoxShape.circle),
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/live_filter_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/live_filter_bar.dart test/live_filter_test.dart
git commit -m "feat: live filter — Happening Now rail + Live pill (+ liveMatches helper)"
```

---

## Task 11: Fan — in-app goal toast

**Files:**
- Create: `lib/misc/goal_toast.dart`

Shows a slide-down overlay when a *followed* match's score increases while the app is foregrounded and the user isn't already on that match. Reuses `FollowStore` (follow topics) and `notification_router.dart` (open match). Driven by the Matches screen's existing live stream (wired in Task 12), so this file only provides the overlay + a dedupe controller.

- [ ] **Step 1: Implement `lib/misc/goal_toast.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';
import 'package:infinite_sports_flutter/misc/notification_router.dart';

/// Watches a stream of (tournamentId, match) score snapshots and pops a
/// slide-down toast when a FOLLOWED match's total score increases. Call
/// [onScores] whenever fresh matches arrive; it diffs against the last seen
/// totals and shows at most one toast per goal.
class GoalToastController {
  final FollowStore _store = FollowStore();
  final Map<String, int> _lastTotal = {};
  bool _primed = false;

  /// [matches] is a list of records describing currently-known matches.
  /// Show a toast for any whose total score went up since last call, the match
  /// is live, and the user follows the tournament or one of the two teams.
  Future<void> onScores(
    BuildContext context,
    String tournamentId,
    List<GoalToastMatch> matches,
  ) async {
    final follows = (await _store.follows()).map((c) => c.topic).toSet();
    final masterOn = await _store.masterEnabled();
    for (final m in matches) {
      final total = m.team1Score + m.team2Score;
      final prev = _lastTotal[m.matchId];
      _lastTotal[m.matchId] = total;
      if (!_primed || prev == null) continue; // don't toast on first load
      if (total <= prev) continue; // decrease/no-change = silent
      if (m.status != 1) continue;
      if (!masterOn) continue;
      final followed = follows.contains(tournamentTopic(tournamentId)) ||
          (m.team1Id != null && follows.contains(teamTopic(tournamentId, m.team1Id!))) ||
          (m.team2Id != null && follows.contains(teamTopic(tournamentId, m.team2Id!)));
      if (!followed) continue;
      if (context.mounted) {
        _show(context, tournamentId, m);
      }
    }
    _primed = true;
  }

  void _show(BuildContext context, String tournamentId, GoalToastMatch m) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _GoalToast(
        title: 'GOAL! ${m.team1Name} ${m.team1Score} – ${m.team2Score} ${m.team2Name}',
        onTap: () {
          entry.remove();
          openMatchFromNotification({'tournamentId': tournamentId, 'matchId': m.matchId});
        },
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class GoalToastMatch {
  final String matchId;
  final String? team1Id;
  final String? team2Id;
  final String team1Name;
  final String team2Name;
  final int team1Score;
  final int team2Score;
  final int status;
  const GoalToastMatch({
    required this.matchId,
    required this.team1Id,
    required this.team2Id,
    required this.team1Name,
    required this.team2Name,
    required this.team1Score,
    required this.team2Score,
    required this.status,
  });
}

class _GoalToast extends StatefulWidget {
  final String title;
  final VoidCallback onTap;
  final VoidCallback onDone;
  const _GoalToast({required this.title, required this.onTap, required this.onDone});

  @override
  State<_GoalToast> createState() => _GoalToastState();
}

class _GoalToastState extends State<_GoalToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 280))
    ..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 6;
    return Positioned(
      top: top,
      left: 8,
      right: 8,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  const Text('⚽', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${widget.title}\nTap to watch',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/misc/goal_toast.dart`
Expected: no new errors (it references existing `notification_topics.dart`, `follow_store.dart`, `notification_router.dart`).

- [ ] **Step 3: Commit**

```bash
git add lib/misc/goal_toast.dart
git commit -m "feat: in-app goal toast controller + slide-down overlay for followed matches"
```

---

## Task 12: Fan — wire live data into the Matches screen (frontpage.dart)

**Files:**
- Modify: `lib/frontpage.dart`

**First read the whole file** to understand its current structure (it builds the day-driven Matches screen via `TournamentDayView` and loads matches once). Integrate without changing the day-picker logic or layout — only swap the data source and add the new pieces.

- [ ] **Step 1: Make the match list live**

Replace the one-shot match fetch (`TournamentService.getMatches(...)` inside a `FutureBuilder` / `initState`) with a `StreamBuilder<List<TournamentMatch>>` fed by `TournamentService.watchMatches(tournamentId)`. While `!snapshot.hasData` AND no cached data, show `SkeletonMatchList()` (import `lib/widgets/skeleton.dart`); once data exists, render the existing day-grouped list. Cancel nothing manually — `StreamBuilder` handles subscription lifecycle.

- [ ] **Step 2: Live row leading + score flash**

In each match row builder: when `match.status == 1`, show `MinuteBall(clock: match.clock)` (import `lib/widgets/live_clock.dart`) as the leading element instead of the scheduled time; for `status == 0` keep the scheduled time; for `status == 2` show `FT`. Render each score with `ScoreText(value: match.team1Score)` / `team2Score` (import `lib/widgets/score_text.dart`) so goals flash.

- [ ] **Step 3: Add the Live pill + Happening Now rail**

Add a `bool _liveOnly = false;` to the screen state. In the Matches tab header row, add `LivePill(on: _liveOnly, onChanged: (v) => setState(() => _liveOnly = v))` (import `lib/widgets/live_filter_bar.dart`). Above the day list, add `HappeningNowRail(live: liveMatches(allMatches), abbr: <team abbr fn>, onTapMatch: <open match>)`. When `_liveOnly` is true, filter the displayed list to `liveMatches(...)`. For `abbr`, derive a 3-letter uppercase abbreviation from the team name already available in the loaded teams map (e.g. first 3 letters uppercased); if no teams map is handy in this screen, pass `(id) => id` — acceptable fallback (report which you used).

- [ ] **Step 4: Wire the goal toast**

Create a `final GoalToastController _goalToast = GoalToastController();` in the state (import `lib/misc/goal_toast.dart`). In the `StreamBuilder` builder, after you have the fresh `matches`, call (not awaited inside build — schedule it post-frame):

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _goalToast.onScores(
    context,
    tournamentId,
    matches.map((m) => GoalToastMatch(
      matchId: m.id, team1Id: m.team1Id, team2Id: m.team2Id,
      team1Name: teamName(m.team1Id), team2Name: teamName(m.team2Id),
      team1Score: m.team1Score, team2Score: m.team2Score, status: m.status,
    )).toList(),
  );
});
```

`teamName(...)` should look up the loaded teams map (fallback to `'?'`).

- [ ] **Step 5: Verify analyze + tests + a quick run**

Run: `flutter analyze lib/frontpage.dart && flutter test`
Expected: no new errors; all tests pass. (Manual on-device check happens in Task 15.)

- [ ] **Step 6: Commit**

```bash
git add lib/frontpage.dart
git commit -m "feat: live Matches screen — streaming list, minute ball, score flash, rail+pill, goal toast"
```

---

## Task 13: Fan — live tournament detail tabs (Fixtures / Table / Knockout)

**Files:**
- Modify: `lib/tournamentdetail.dart`

**Read the file first.** It loads `getMatches` / `getTeams` once in `_loadData` and passes them to the Fixtures, Table, and Knockout tab widgets.

- [ ] **Step 1: Stream the matches into the tabs**

Wrap the tab body content in a `StreamBuilder<List<TournamentMatch>>` using `TournamentService.watchMatches(widget.tournamentId)`. Seed it with the already-loaded `_matches` as `initialData` so there's no flicker, and feed fresh emissions to the existing Fixtures/Table/Knockout tab widgets (they already accept a match list — pass the streamed list instead of the static `_matches`). Tables/brackets recompute from matches, so they update for free. If a tab computes the table from matches inline, keep that logic; just feed it live matches.

- [ ] **Step 2: Live indicators in the Fixtures list rows**

In the Fixtures tab rows (in this file or `lib/tournament_tabs/fixtures_tab.dart` if that's where rows are built — read to confirm), apply the same row treatment as Task 12: `MinuteBall` for live, `ScoreText` for scores. Reuse the imports.

- [ ] **Step 3: Verify analyze + tests**

Run: `flutter analyze lib/tournamentdetail.dart lib/tournament_tabs/fixtures_tab.dart && flutter test`
Expected: no new errors; tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/tournamentdetail.dart lib/tournament_tabs/fixtures_tab.dart
git commit -m "feat: live-updating Fixtures/Table/Knockout tabs + live row indicators"
```

---

## Task 14: Fan — live match detail (header clock + score flash + live timeline)

**Files:**
- Modify: `lib/tournament_match_detail.dart`

**Read the file first.** `_buildScoreboardHeader` builds the navy header; the Facts tab builds the timeline from `widget.match` activity.

- [ ] **Step 1: Make the page live**

Convert the page to drive off `TournamentService.watchMatch(widget.tournamentId, widget.match.id)` with a `StreamBuilder<TournamentMatch?>` using `initialData: widget.match`. Use the streamed match (fall back to `widget.match`) everywhere the header/timeline currently reads `widget.match`. This makes the score, status, clock, and timeline all update live.

- [ ] **Step 2: Header — clock placement + score flash**

In `_buildScoreboardHeader`, for the live state: keep the score (render with `ScoreText`, fontSize 28-ish, baseColor white), keep the red `LIVE` badge, then directly BELOW the badge add `MatchClockText(clock: match.clock)`, then the day/date and location below that (push them down — they already sit under the score block; just ensure order is score → LIVE → clock → date → location). Imports: `lib/widgets/live_clock.dart`, `lib/widgets/score_text.dart`.

- [ ] **Step 3: Live timeline**

The Facts/timeline list is built from the match activity; since the page now rebuilds on every change, new goal/card rows appear automatically. Wrap the timeline list so a newly-added row animates in: use an `AnimatedSwitcher` or simply `ListView` with a subtle `TweenAnimationBuilder` fade on the newest item. Keep it tasteful (200ms fade). If this risks destabilizing the existing list, a plain rebuild is acceptable for v1 — report your choice.

- [ ] **Step 4: Verify analyze + tests**

Run: `flutter analyze lib/tournament_match_detail.dart && flutter test`
Expected: no new errors; tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_match_detail.dart
git commit -m "feat: live match detail — streaming header clock, score flash, live timeline"
```

---

## Task 15: Full verification + on-device sign-off + finishing

**Files:** none (verification only)

- [ ] **Step 1: Automated verification — both apps**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test
```
Expected: all pass in both. Then `flutter analyze` in each (per CLAUDE.md it can time out; if so analyze just the files this plan touched). In the fan app, if `pubspec.lock` shows modified: `git restore pubspec.lock`.

- [ ] **Step 2: On-device manual test (owner, plain language)**

Have BOTH apps running (fan on the emulator, Manager on the iPad/another device).
1. Manager: **Start** a match → fan Matches list shows a **green minute ticking** and the card header shows **mm:ss**.
2. Manager: **Pause** → fan clock **freezes**; **Resume** → it continues.
3. Manager: record a **goal** → fan score **flashes red**; if you follow that match and are on another tab, the **goal toast** slides down.
4. Fan: tap the **Live** pill → only live matches show; the **Happening now** rail shows live matches at the top.
5. Tables/brackets change **without** pressing refresh.
6. Close and reopen the fan app → tournament pages appear **instantly** from cache.

- [ ] **Step 3: Finishing**

Announce: "I'm using the finishing-a-development-branch skill to complete this work." Then follow superpowers:finishing-a-development-branch for EACH app (fan `zaya/live-scores`, Manager `zaya-live-scores`). Tests must pass first. Branches stay **local**; the owner pushes only on their say-so, then Paul & Bronsin review/merge (the fan branch stacks on `zaya/push-notifications`, so that one merges first).

---

## Self-review notes (done at plan time)

- **Spec coverage:** §1 real-time → T5/T6/T12-14; clock → T1-4 + T9; score flash → T8; skeleton → T7; rail+pill (Both) → T10/T12; goal toast → T11/T12; Manager clock persistence → T2/T3; testing → T1/T2/T8/T10/T15; review notes carried in spec. Match-Day Delight (celebration + MOTM) intentionally deferred to the next spec — not in this plan.
- **Parity:** fan `MatchClock` (T1) and Manager `MatchClock` (T2) share identical math; the resume transaction (T3) maintains the `PausedAccumMs`/`PausedAt` invariants the helper assumes.
- **Names/signatures consistent:** `MatchClock.fromMap`, `elapsedAt(int)`, `minuteLabel`, `clockLabel`, `watchMatches/watchMatch/watchTournament`, `MinuteBall`, `MatchClockText`, `ScoreText(value:)`, `liveMatches`, `LivePill`, `HappeningNowRail`, `GoalToastController.onScores`, `GoalToastMatch` — used identically across tasks.
- **Wiring tasks (12-14)** require reading large existing files; they prescribe the exact data-source swap and widget insertions rather than guessing line numbers, and tell the implementer to preserve existing layout. This is deliberate, not a placeholder.
