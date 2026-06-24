# Share Match Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-tap Share button to the fan match-detail page that renders a branded "Option B" match card (team-color halves, logos, score, 👑 winner, top-2 leaders in Goals/Assists/DPL/Saves, "Follow Infinite Sports" footer) as a PNG and opens the system share sheet.

**Architecture:** A pure helper computes per-team top-N leaders from existing match activity. A fixed-size `ShareMatchCard` widget draws the card with hard-coded brand colors (theme-independent). A service renders that widget offscreen via an `Overlay` + `RepaintBoundary.toImage`, writes a temp PNG (`path_provider`), and shares it via `share_plus`. A Share `IconButton` in the existing `SliverAppBar.actions` triggers it.

**Tech Stack:** Flutter, `share_plus ^12.0.1` (`SharePlus.instance.share(ShareParams(...))`), `path_provider`, `dart:ui` `toImage`.

**Branch:** `zaya-share-card` (already created off `zaya-features`). All commits LOCAL — do not push. Work in the main checkout (owner tests on-device), NOT a worktree.

**Conventions:** Stage exact file paths only — never `git add -A`; never stage `PROJECT_REFERENCE.md`, `SoccerStats.png`, `.claude/`, or `.superpowers/`. If `pubspec.lock` shows as modified unexpectedly after `pub get`, that's expected for Task 2 (commit it); otherwise `git restore pubspec.lock`.

---

## File Structure

- **Modify** `lib/misc/single_match_tallies.dart` — extract a per-activity scan and expose `playerTalliesForActivity(activity)` (additive; keeps existing behavior).
- **Create** `lib/misc/share_card_leaders.dart` — `LeaderEntry` + `topNForStat(match, team1, stat, n)` (pure).
- **Create** `test/share_card_leaders_test.dart` — unit tests for `topNForStat`.
- **Modify** `pubspec.yaml` — add `path_provider`.
- **Create** `lib/widgets/share_match_card.dart` — the fixed-size card widget.
- **Create** `test/share_match_card_test.dart` — widget render tests (each state, missing logo).
- **Create** `lib/misc/share_match_card_service.dart` — `buildShareText(...)` (pure) + `shareMatchCard(...)` (render+share).
- **Create** `test/share_text_test.dart` — unit tests for `buildShareText`.
- **Modify** `lib/tournament_match_detail.dart` — fetch tournament name; add Share `IconButton` to AppBar actions.

---

### Task 1: Per-team leaders helper (pure) + tests

**Files:**
- Modify: `lib/misc/single_match_tallies.dart`
- Create: `lib/misc/share_card_leaders.dart`
- Test: `test/share_card_leaders_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/share_card_leaders_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_card_leaders.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch _match() => const TournamentMatch(
      id: 'm',
      stage: 'Group Stage',
      label: 'x',
      date: '',
      team1Score: 3,
      team2Score: 1,
      status: 2,
      bracketPosition: 1,
      team1Activity: {
        '1': [
          {'goal': 'Sam'},
          {'assist': 'Drew'}
        ],
        '2': [
          {'goal': 'Sam'},
          {'goal': 'Cam'},
          {'save': 'Lee'},
          {'dpl': 'Avery'}
        ],
      },
      team2Activity: {
        '1': [
          {'goal': 'Chris'},
          {'assist': 'Bo'}
        ],
      },
    );

void main() {
  test('top goals for team1 are ordered by count then name, capped at n', () {
    final r = topNForStat(_match(), true, 'goals', n: 2);
    expect(r.map((e) => '${e.name}:${e.count}').toList(), ['Sam:2', 'Cam:1']);
  });

  test('team separation — team2 goals do not include team1 players', () {
    final r = topNForStat(_match(), false, 'goals');
    expect(r.map((e) => e.name).toList(), ['Chris']);
  });

  test('zero-count stat returns empty list', () {
    // team2 has no saves
    expect(topNForStat(_match(), false, 'saves'), isEmpty);
  });

  test('ties broken alphabetically by name', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 0,
      team2Score: 0, status: 2, bracketPosition: 1,
      team1Activity: {
        '1': [
          {'goal': 'Zed'},
          {'goal': 'Abe'}
        ]
      },
    );
    expect(topNForStat(m, true, 'goals').map((e) => e.name).toList(),
        ['Abe', 'Zed']);
  });

  test('assists and dpl tallies work', () {
    expect(topNForStat(_match(), true, 'assists').map((e) => e.name).toList(),
        ['Drew']);
    expect(topNForStat(_match(), true, 'dpl').map((e) => e.name).toList(),
        ['Avery']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/share_card_leaders_test.dart`
Expected: FAIL — `share_card_leaders.dart` / `topNForStat` does not exist (compile error).

- [ ] **Step 3: Refactor `single_match_tallies.dart` to expose a per-activity scan**

Replace the whole body of `lib/misc/single_match_tallies.dart` with this (keeps `singleMatchPlayerTallies` and `matchStatLeaders` behavior identical, adds `playerTalliesForActivity`):

```dart
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Per-player counters for ONE match (Match Leaders = this game).
class MatchPlayerTally {
  int goals = 0, assists = 0, saves = 0, dpl = 0;
  int byStat(String stat) {
    switch (stat) {
      case 'goals':
        return goals;
      case 'assists':
        return assists;
      case 'saves':
        return saves;
      case 'dpl':
        return dpl;
      default:
        return 0;
    }
  }
}

void _applyEvent(Map<String, MatchPlayerTally> out, String type, String player) {
  final t = out.putIfAbsent(player, () => MatchPlayerTally());
  switch (type.toLowerCase().trim()) {
    case 'goal':
    case 'penalty goal':
      t.goals++;
      break;
    case 'assist':
      t.assists++;
      break;
    case 'save':
    case 'penalty saved':
      t.saves++;
      break;
    case 'dpl':
      t.dpl++;
      break;
    default:
      break;
  }
}

void _scanInto(Map<String, MatchPlayerTally> out, Map<String, dynamic>? activity) {
  if (activity == null) return;
  void addEntry(dynamic entry) {
    if (entry is Map) {
      entry.forEach((k, v) => _applyEvent(out, k.toString(), v.toString()));
    }
  }
  activity.forEach((_, bucket) {
    if (bucket is List) {
      for (final e in bucket) {
        addEntry(e);
      }
    } else if (bucket is Map) {
      bucket.forEach((_, e) => addEntry(e));
    }
  });
}

/// Per-player tallies for a SINGLE team's activity map (keyed by player name).
/// Mirrors the event mapping (goal/penalty goal -> goals, assist -> assists,
/// save/penalty saved -> saves, dpl -> dpl). Pure.
Map<String, MatchPlayerTally> playerTalliesForActivity(
    Map<String, dynamic>? activity) {
  final out = <String, MatchPlayerTally>{};
  _scanInto(out, activity);
  return out;
}

/// Tallies goals/assists/saves/dpl from BOTH teams' activity, keyed by player
/// name. Pure.
Map<String, MatchPlayerTally> singleMatchPlayerTallies(TournamentMatch match) {
  final out = <String, MatchPlayerTally>{};
  _scanInto(out, match.team1Activity);
  _scanInto(out, match.team2Activity);
  return out;
}

/// Player name(s) leading [stat] ('goals'|'assists'|'saves'|'dpl') in this match.
/// Returns the set of names sharing the max (ties included). Empty if nobody has any.
Set<String> matchStatLeaders(TournamentMatch match, String stat) {
  final tallies = singleMatchPlayerTallies(match);
  int max = 0;
  for (final t in tallies.values) {
    final v = t.byStat(stat);
    if (v > max) max = v;
  }
  if (max == 0) return <String>{};
  return {
    for (final e in tallies.entries)
      if (e.value.byStat(stat) == max) e.key
  };
}
```

- [ ] **Step 4: Create `lib/misc/share_card_leaders.dart`**

```dart
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// A single player's count for one stat on the share card.
class LeaderEntry {
  final String name;
  final int count;
  const LeaderEntry(this.name, this.count);
}

/// Top [n] players for [stat] ('goals'|'assists'|'saves'|'dpl') on ONE team's
/// side of [match]. [team1] true → team1Activity, else team2Activity.
/// Sorted by count descending, then name ascending. Zero-count players excluded.
/// Pure.
List<LeaderEntry> topNForStat(
  TournamentMatch match,
  bool team1,
  String stat, {
  int n = 2,
}) {
  final activity = team1 ? match.team1Activity : match.team2Activity;
  final tallies = playerTalliesForActivity(activity);
  final entries = <LeaderEntry>[
    for (final e in tallies.entries)
      if (e.value.byStat(stat) > 0) LeaderEntry(e.key, e.value.byStat(stat))
  ]..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  return entries.take(n).toList();
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/share_card_leaders_test.dart`
Expected: PASS (5 tests).
Then run the existing tallies test if present: `flutter test test/single_match_tallies_test.dart` (if the file exists) — Expected: PASS (refactor preserved behavior). If the file does not exist, skip.

- [ ] **Step 6: Commit**

```bash
git add lib/misc/single_match_tallies.dart lib/misc/share_card_leaders.dart test/share_card_leaders_test.dart
git commit -m "feat: per-team top-N leaders helper for share card"
```

---

### Task 2: Add `path_provider` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, directly below the `share_plus:` line, add:

```yaml
  path_provider: ^2.1.5
```

- [ ] **Step 2: Resolve packages**

Run: `flutter pub get`
Expected: completes with "Got dependencies!" (or "Changed N dependencies!"). `pubspec.lock` updates.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add path_provider for share-card temp file"
```

---

### Task 3: `ShareMatchCard` widget + widget test

**Files:**
- Create: `lib/widgets/share_match_card.dart`
- Test: `test/share_match_card_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/share_match_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/share_match_card.dart';

TournamentTeam _team(String id, String name) => TournamentTeam(
      id: id,
      name: name,
      qualification: 'Qualified',
      gp: 0, wins: 0, draws: 0, losses: 0, gs: 0, gc: 0, gd: 0, points: 0,
      homeColor: const Color(0xFF0066CC),
    );

Future<void> _pump(WidgetTester tester, TournamentMatch m) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ShareMatchCard(
        match: m,
        team1: _team('eagles', 'Eagles'),
        team2: _team('lions', 'Lions'),
        tournamentName: 'Test Tournament 2026',
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('finished card renders score, FINAL, follow, no overflow',
      (tester) async {
    const m = TournamentMatch(
      id: 'm', stage: 'Quarterfinal', label: 'QF', date: '08272026',
      time: '10:00 AM', team1Id: 'eagles', team2Id: 'lions',
      team1Score: 4, team2Score: 3, status: 2, bracketPosition: 1,
      team1Activity: {
        '1': [
          {'goal': 'Sam'},
          {'assist': 'Drew'}
        ]
      },
    );
    await _pump(tester, m);
    expect(tester.takeException(), isNull);
    expect(find.text('Eagles'), findsOneWidget);
    expect(find.text('Lions'), findsOneWidget);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.textContaining('Follow Infinite Sports'), findsOneWidget);
  });

  testWidgets('upcoming card shows kickoff and no FINAL', (tester) async {
    const m = TournamentMatch(
      id: 'm', stage: 'Quarterfinal', label: 'QF', date: '08272026',
      time: '10:00 AM', team1Id: 'eagles', team2Id: 'lions',
      team1Score: 0, team2Score: 0, status: 0, bracketPosition: 1,
    );
    await _pump(tester, m);
    expect(tester.takeException(), isNull);
    expect(find.text('FINAL'), findsNothing);
  });

  testWidgets('live card renders without overflow', (tester) async {
    const m = TournamentMatch(
      id: 'm', stage: 'Quarterfinal', label: 'QF', date: '08272026',
      team1Id: 'eagles', team2Id: 'lions', team1Score: 1, team2Score: 0,
      status: 1, bracketPosition: 1,
    );
    await _pump(tester, m);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/share_match_card_test.dart`
Expected: FAIL — `share_match_card.dart` / `ShareMatchCard` does not exist.

- [ ] **Step 3: Create `lib/widgets/share_match_card.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_card_leaders.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

/// Fixed-size, theme-independent match card rendered to a PNG for sharing.
/// Logical size 360x450; capture at pixelRatio 3 -> 1080x1350.
class ShareMatchCard extends StatelessWidget {
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final String tournamentName;

  const ShareMatchCard({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.tournamentName,
  });

  static const double kWidth = 360;
  static const double kHeight = 450;
  static const Color _primary = Color(0xFFD00000);
  static const Color _default1 = Color(0xFF1565C0);
  static const Color _default2 = Color(0xFFC62828);
  static const Color _footer = Color(0xFF111111);

  static const _statIcons = <String, String>{
    'goals': 'assets/goal.png',
    'assists': 'assets/assist.png',
    'dpl': 'assets/dpl.png',
    'saves': 'assets/save.png',
  };

  @override
  Widget build(BuildContext context) {
    final finished = match.matchStatus.isFinished;
    final live = match.matchStatus.isLive;
    final showStats = finished || live;
    final winnerId = match.winnerTeamId; // '' if draw or not finished
    final name1 = team1?.name ?? match.team1Id ?? 'TBD';
    final name2 = team2?.name ?? match.team2Id ?? 'TBD';
    final c1 = team1?.homeColor ?? _default1;
    final c2 = team2?.homeColor ?? _default2;
    final header = tournamentName.isNotEmpty
        ? '$tournamentName · ${match.stage}'
        : match.stage;

    return SizedBox(
      width: kWidth,
      height: kHeight,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: _half(
                  name: name1,
                  score: match.team1Score,
                  color: c1,
                  team1: true,
                  showStats: showStats,
                  isWinner:
                      winnerId.isNotEmpty && winnerId == (match.team1Id ?? '#'),
                  logoUrl: team1?.logoUrl,
                ),
              ),
              Expanded(
                child: _half(
                  name: name2,
                  score: match.team2Score,
                  color: c2,
                  team1: false,
                  showStats: showStats,
                  isWinner:
                      winnerId.isNotEmpty && winnerId == (match.team2Id ?? '#'),
                  logoUrl: team2?.logoUrl,
                ),
              ),
            ],
          ),
          // Header overlay
          Positioned(
            top: 12,
            left: 10,
            right: 10,
            child: Text(
              header.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
              ),
            ),
          ),
          // Center pill
          Align(alignment: const Alignment(0, -0.36), child: _centerPill(finished, live)),
          // Footer
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: _footer,
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '▶ Follow '),
                    TextSpan(
                        text: 'Infinite Sports',
                        style: TextStyle(color: Color(0xFFFF5A5A))),
                    TextSpan(text: ' for live scores'),
                  ],
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _half({
    required String name,
    required int score,
    required Color color,
    required bool team1,
    required bool showStats,
    required bool isWinner,
    required String? logoUrl,
  }) {
    return Container(
      color: color,
      padding: const EdgeInsets.fromLTRB(10, 34, 10, 52),
      child: Column(
        mainAxisAlignment:
            showStats ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          _logo(logoUrl),
          const SizedBox(height: 6),
          Text(name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          if (showStats) ...[
            Text('$score',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    height: 1.1,
                    fontWeight: FontWeight.w800)),
            SizedBox(
              height: 16,
              child: isWinner
                  ? Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(7)),
                      child: Text('👑 WINNERS',
                          style: TextStyle(
                              color: color,
                              fontSize: 8,
                              fontWeight: FontWeight.w800)))
                  : null,
            ),
            const SizedBox(height: 8),
            _statRow('goals', team1),
            _statRow('assists', team1),
            _statRow('dpl', team1),
            _statRow('saves', team1),
          ],
        ],
      ),
    );
  }

  Widget _logo(String? url) {
    const double size = 44;
    final shield = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
          color: Colors.white24, shape: BoxShape.circle),
      child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
    );
    if (url == null || url.isEmpty) return shield;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => shield,
      ),
    );
  }

  Widget _statRow(String stat, bool team1) {
    final list = topNForStat(match, team1, stat);
    final text =
        list.isEmpty ? '—' : list.map((e) => '${e.name} ${e.count}').join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Image.asset(_statIcons[stat]!, width: 13, height: 13),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 9, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _centerPill(bool finished, bool live) {
    String label;
    if (finished) {
      label = 'FINAL';
    } else if (live) {
      label = 'LIVE  ${match.team1Score}-${match.team2Score}';
    } else {
      final t = match.time;
      label = t != null && t.isNotEmpty ? 'KICKOFF\n$t' : 'UPCOMING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)]),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: live ? _primary : const Color(0xFF111111),
              fontSize: 9,
              height: 1.3,
              fontWeight: FontWeight.w800)),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/share_match_card_test.dart`
Expected: PASS (3 tests). Network logos error to the shield via `errorBuilder` in tests — that is expected and must not throw (`takeException()` is null).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/share_match_card.dart test/share_match_card_test.dart
git commit -m "feat: ShareMatchCard widget (Option B + leaders + states)"
```

---

### Task 4: Render + share service (`buildShareText` tested; render manual)

**Files:**
- Create: `lib/misc/share_match_card_service.dart`
- Test: `test/share_text_test.dart`

- [ ] **Step 1: Write the failing test for `buildShareText`**

Create `test/share_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  test('finished/live text uses score', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 4,
      team2Score: 3, status: 2, bracketPosition: 1,
    );
    expect(
      buildShareText(
          match: m,
          team1Name: 'Eagles',
          team2Name: 'Lions',
          tournamentName: 'Test Tournament 2026'),
      'Eagles 4–3 Lions · Test Tournament 2026 — follow live on Infinite Sports.',
    );
  });

  test('upcoming text uses vs', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 0,
      team2Score: 0, status: 0, bracketPosition: 1,
    );
    expect(
      buildShareText(
          match: m,
          team1Name: 'Eagles',
          team2Name: 'Lions',
          tournamentName: 'Test Tournament 2026'),
      'Eagles vs Lions · Test Tournament 2026 — follow live on Infinite Sports.',
    );
  });

  test('empty tournament name omits the middle dot segment', () {
    const m = TournamentMatch(
      id: 'm', stage: 's', label: 'x', date: '', team1Score: 1,
      team2Score: 0, status: 2, bracketPosition: 1,
    );
    expect(
      buildShareText(
          match: m, team1Name: 'A', team2Name: 'B', tournamentName: ''),
      'A 1–0 B — follow live on Infinite Sports.',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/share_text_test.dart`
Expected: FAIL — `share_match_card_service.dart` / `buildShareText` does not exist.

- [ ] **Step 3: Create `lib/misc/share_match_card_service.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/share_match_card.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Caption text shared alongside the image. Pure.
String buildShareText({
  required TournamentMatch match,
  required String team1Name,
  required String team2Name,
  required String tournamentName,
}) {
  final mid = tournamentName.isNotEmpty ? ' · $tournamentName' : '';
  final s = match.matchStatus;
  if (s.isFinished || s.isLive) {
    return '$team1Name ${match.team1Score}–${match.team2Score} $team2Name$mid'
        ' — follow live on Infinite Sports.';
  }
  return '$team1Name vs $team2Name$mid — follow live on Infinite Sports.';
}

/// Renders [ShareMatchCard] offscreen to a PNG and opens the system share sheet.
/// Never throws; shows a SnackBar on failure.
Future<void> shareMatchCard(
  BuildContext context, {
  required TournamentMatch match,
  required TournamentTeam? team1,
  required TournamentTeam? team2,
  required String tournamentName,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    // Pre-load stat icons + team logos so they paint into the captured frame.
    await Future.wait([
      precacheImage(const AssetImage('assets/goal.png'), context),
      precacheImage(const AssetImage('assets/assist.png'), context),
      precacheImage(const AssetImage('assets/dpl.png'), context),
      precacheImage(const AssetImage('assets/save.png'), context),
    ]);
    for (final url in [team1?.logoUrl, team2?.logoUrl]) {
      if (url != null && url.isNotEmpty && context.mounted) {
        try {
          await precacheImage(NetworkImage(url), context);
        } catch (_) {/* logo will fall back to shield */}
      }
    }
    if (!context.mounted) return;

    final bytes = await _capture(
      context,
      ShareMatchCard(
        match: match,
        team1: team1,
        team2: team2,
        tournamentName: tournamentName,
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/match_card_${match.id}.png');
    await file.writeAsBytes(bytes);

    final text = buildShareText(
      match: match,
      team1Name: team1?.name ?? match.team1Id ?? 'TBD',
      team2Name: team2?.name ?? match.team2Id ?? 'TBD',
      tournamentName: tournamentName,
    );

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't create the share card.")),
    );
  }
}

Future<Uint8List> _capture(BuildContext context, Widget card) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000, // offscreen but laid out + painted
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(key: key, child: card),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // Let the offscreen subtree lay out and paint before capturing.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 32));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/share_text_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/misc/share_match_card_service.dart test/share_text_test.dart
git commit -m "feat: share-card render+share service with tested caption builder"
```

---

### Task 5: Wire Share button into the match-detail AppBar

**Files:**
- Modify: `lib/tournament_match_detail.dart`

- [ ] **Step 1: Add the service import**

At the top of `lib/tournament_match_detail.dart`, with the other `package:infinite_sports_flutter/...` imports, add:

```dart
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
```

- [ ] **Step 2: Add a tournament-name field and fetch it in initState**

In `_TournamentMatchDetailPageState`, add the field next to `_predictionConfig`:

```dart
  String _tournamentName = '';
```

In `initState`, after the existing `getPredictionConfig(...)` block, add:

```dart
    TournamentService.getTournamentHeader(widget.tournamentId).then((t) {
      if (mounted && t != null) setState(() => _tournamentName = t.name);
    });
```

(If the `Tournament` model's display-name getter is not `name`, use the correct one — verify by reading `lib/model/tournament.dart`.)

- [ ] **Step 3: Add the Share IconButton to the AppBar actions**

In `build`, the `SliverAppBar`'s `actions:` list currently contains only the conditional stream button. Add the Share button as the FIRST action (so it always shows). Replace:

```dart
                actions: [
                  if (_match.link != null && _match.link!.isNotEmpty)
```

with:

```dart
                actions: [
                  IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Share match',
                    onPressed: () => shareMatchCard(
                      context,
                      match: _match,
                      team1: team1,
                      team2: team2,
                      tournamentName: _tournamentName,
                    ),
                  ),
                  if (_match.link != null && _match.link!.isNotEmpty)
```

(`team1` and `team2` are already computed at the top of `build` — lines ~255-256 — so they are in scope here.)

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/tournament_match_detail.dart lib/misc/share_match_card_service.dart lib/widgets/share_match_card.dart lib/misc/share_card_leaders.dart`
Expected: No errors (info/warnings about pre-existing issues are acceptable; none in these files).

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_match_detail.dart
git commit -m "feat: Share button in match detail AppBar"
```

---

### Task 6: Full verification + build/install + finishing

**Files:** none (verification only)

- [ ] **Step 1: Analyze + full test suite**

Run: `flutter analyze`
Expected: no NEW errors in the share-card files.
Run: `flutter test`
Expected: full suite green (includes the new leaders / card / share-text tests).

- [ ] **Step 2: Build + install on the owner's device**

```bash
flutter build apk --debug
```
Then install (PowerShell): `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s GN434J02403404RL install -r build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 3: Surface the manual test recipe to the owner**

Tell the owner: open Feeder Test 2026 (or Test Tournament 2026) → tap a match → tap the **Share** icon (top-right). Verify: (a) a finished match shows scorers/assists/DPL/saves per side + 👑 on the winner; (b) the image opens in WhatsApp/Instagram with the caption; (c) an upcoming match shares the fixture version. Confirm logos appear (teams with a logo) and shields show otherwise.

- [ ] **Step 4: After owner sign-off — merge into `zaya-features`**

Per the project branch workflow, once the owner confirms it works:

```bash
git checkout zaya-features
git merge --no-ff zaya-share-card -m "merge: share match card feature"
git checkout zaya-share-card   # (optional) stay ready for follow-up tweaks
```

Keep everything LOCAL — do not push unless the owner says so.

---

## Self-Review

**1. Spec coverage:**
- Card visual (Option B, leaders, 👑, follow, states) → Task 3. ✅
- Stat icons from app assets → Task 3 `_statIcons`. ✅
- Top-2 per category per team (goals/assists/dpl/saves) → Task 1 `topNForStat` + Task 3 `_statRow`. ✅
- Upcoming + live + finished states → Task 3 `showStats`/`_centerPill`. ✅
- Render offscreen → temp PNG → share_plus → Task 4. ✅
- `path_provider` added → Task 2. ✅
- Share button in match-detail AppBar → Task 5. ✅
- Error handling (snackbar, shield fallback) → Task 3 `_logo`, Task 4 try/catch. ✅
- Testing (unit leaders, widget states, share text, manual) → Tasks 1, 3, 4, 6. ✅
- No Manager changes / no Firebase schema changes. ✅

**2. Placeholder scan:** No TBD/TODO; every code step has full code. ✅

**3. Type consistency:** `topNForStat(match, team1, stat, {n})` and `LeaderEntry(name, count)` defined in Task 1 and used identically in Task 3. `buildShareText({match, team1Name, team2Name, tournamentName})` defined in Task 4 and tested with the same shape. `shareMatchCard(context, {match, team1, team2, tournamentName})` defined in Task 4 and called with the same args in Task 5. `ShareMatchCard({match, team1, team2, tournamentName})` consistent across Tasks 3, 4. ✅

**One assumption to verify during Task 5:** the fan `Tournament` model exposes its display name as `.name` (used in `_tournamentName = t.name`). If different, adjust to the correct getter — the rest of the feature is unaffected (empty name simply shows the stage only).
