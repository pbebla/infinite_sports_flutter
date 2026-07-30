# Live Stats Everywhere — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the fan tournament Table, Player Stats, and Team Stats update live (mid-match) by deriving them from the live match stream, add a "playing now" highlight on the table, and order matches live → upcoming → finished.

**Architecture:** Port the Manager's pure `tournament_stats_engine.dart` into the fan app, with one change: count **live (status 1) AND finished (status 2)** matches so in-progress scores feed the table and player counters. `tournamentdetail.dart` already live-streams `_matches`; it computes `ComputedTournamentStats` each build and passes it to the three tabs, which read derived values instead of stored ones. Fixtures ordering becomes status-priority.

**Tech Stack:** Flutter/Dart, Firebase RTDB (already streaming), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-14-live-stats-everywhere-design.md`

---

## Ground rules (every task)
- Repo: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, branch `zaya/live-scores`, main checkout (NOT a worktree). Verify branch with `git branch --show-current`.
- All commits LOCAL. Never push.
- NEVER stage `PROJECT_REFERENCE.md` or `SoccerStats.png`. Stage exact paths only — never `git add -A`.
- If `pubspec.lock` shows modified after a flutter command, `git restore pubspec.lock`.
- Fan app = package `infinite_sports_flutter`.

## File structure
| File | Role |
|---|---|
| `lib/model/tournamentmatch.dart` — Modify | Parse `Team1Keeper`/`Team2Keeper` (for clean sheets) |
| `lib/misc/tournament_stats_engine.dart` — Create | Pure engine: standings + player counters from live+finished matches |
| `test/tournament_stats_engine_test.dart` — Create | Engine unit tests (incl. a live-match case) |
| `lib/tournamentdetail.dart` — Modify | Compute `ComputedTournamentStats` each build; pass to tabs |
| `lib/tournament_tabs/table_tab.dart` — Modify | Standings + playing-now from derived stats |
| `lib/tournament_tabs/playerstats_tab.dart` — Modify | Leaders from derived stats |
| `lib/tournament_tabs/teams_tab.dart` — Modify | W/D/L from derived stats |
| `lib/tournament_tabs/fixtures_tab.dart` — Modify | Status-priority ordering |

---

### Task 1: Parse keeper fields onto the fan match model

**Files:**
- Modify: `lib/model/tournamentmatch.dart`
- Test: `test/tournamentmatch_keeper_test.dart` (create)

Clean sheets need to know each team's keeper. The Manager writes `Team1Keeper`/`Team2Keeper` strings on the match; the fan model doesn't parse them yet.

- [ ] **Step 1: Write the failing test** — create `test/tournamentmatch_keeper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  test('parses Team1Keeper / Team2Keeper when present', () {
    final m = TournamentMatch.fromFirebase('M1', {
      'Team1Id': 'a', 'Team2Id': 'b',
      'Team1Score': 1, 'Team2Score': 0, 'Status': 2,
      'Team1Keeper': 'Sam Keeper', 'Team2Keeper': 'Lee Keeper',
    });
    expect(m.team1Keeper, 'Sam Keeper');
    expect(m.team2Keeper, 'Lee Keeper');
  });

  test('keepers are null when absent', () {
    final m = TournamentMatch.fromFirebase('M2', {
      'Team1Id': 'a', 'Team2Id': 'b',
      'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
    });
    expect(m.team1Keeper, isNull);
    expect(m.team2Keeper, isNull);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (`team1Keeper` getter not defined)

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test test/tournamentmatch_keeper_test.dart`

- [ ] **Step 3: Implement** — in `lib/model/tournamentmatch.dart`:

Add two fields after `final String? matchLocation;` (line ~20):
```dart
  final String? team1Keeper;
  final String? team2Keeper;
```
Add to the constructor (after `this.matchLocation,`):
```dart
    this.team1Keeper,
    this.team2Keeper,
```
In `fromFirebase`, add to the returned `TournamentMatch(...)` (after `matchLocation: ...,`):
```dart
      team1Keeper: firstNonNull(data, ['Team1Keeper', 'team1Keeper'])?.toString(),
      team2Keeper: firstNonNull(data, ['Team2Keeper', 'team2Keeper'])?.toString(),
```

- [ ] **Step 4: Run tests — expect PASS** (both keeper tests + full suite)

Run: `flutter test test/tournamentmatch_keeper_test.dart && flutter test`

- [ ] **Step 5: Commit**

```bash
git add lib/model/tournamentmatch.dart test/tournamentmatch_keeper_test.dart
git commit -m "feat: parse Team1Keeper/Team2Keeper onto TournamentMatch for clean sheets"
```

---

### Task 2: Pure fan stats engine (TDD)

**Files:**
- Create: `lib/misc/tournament_stats_engine.dart`
- Test: `test/tournament_stats_engine_test.dart`

Port of the Manager engine. **Key difference:** count `status == 1` (live) and `status == 2` (finished); skip `status == 0`. Adds helper accessors `standingFor` and `statByName` for the tabs.

- [ ] **Step 1: Write the failing tests** — create `test/tournament_stats_engine_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

TournamentMatch match({
  required String id,
  required int status,
  String t1 = 'A',
  String t2 = 'B',
  int s1 = 0,
  int s2 = 0,
  Map<String, dynamic>? a1,
  Map<String, dynamic>? a2,
  String? k1,
  String? k2,
}) =>
    TournamentMatch(
      id: id, stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Id: t1, team2Id: t2, team1Score: s1, team2Score: s2, status: status,
      team1Activity: a1, team2Activity: a2, team1Keeper: k1, team2Keeper: k2,
      bracketPosition: 0,
    );

TournamentPlayer player(String name, String teamId) => TournamentPlayer(
      name: name, teamId: teamId, teamName: teamId,
      goals: 0, assists: 0, saves: 0, dpl: 0, cleanSheets: 0,
      yellowCards: 0, redCards: 0,
    );

void main() {
  final rosters = {
    'A': [player('Sam', 'A'), player('Kai', 'A')],
    'B': [player('Lee', 'B')],
  };

  test('finished match: standings from score, 3 pts to winner', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 2, s1: 2, s2: 1)], rosters: rosters);
    expect(r.standingFor('A').pts, 3);
    expect(r.standingFor('A').w, 1);
    expect(r.standingFor('A').gd, 1);
    expect(r.standingFor('B').l, 1);
    expect(r.standingFor('B').pts, 0);
  });

  test('LIVE match (status 1) ALSO counts toward standings', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 1, s1: 1, s2: 0)], rosters: rosters);
    expect(r.standingFor('A').pts, 3);
    expect(r.standingFor('A').gp, 1);
    expect(r.standingFor('B').gc, 1);
  });

  test('upcoming match (status 0) is ignored', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 0, s1: 5, s2: 5)], rosters: rosters);
    expect(r.standingFor('A').gp, 0);
    expect(r.standingFor('A').pts, 0);
  });

  test('draw gives 1 pt each', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 2, s1: 1, s2: 1)], rosters: rosters);
    expect(r.standingFor('A').pts, 1);
    expect(r.standingFor('B').pts, 1);
    expect(r.standingFor('A').d, 1);
  });

  test('player counters from activity (goal, assist) live', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 1, s1: 1, s2: 0, a1: {
        '12': [
          {'goal': 'Sam'},
          {'assist': 'Kai'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 1);
    expect(r.statByName('A', 'Kai', 'assists'), 1);
  });

  test('activity bucket as index-keyed Map is tolerated', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 1, s2: 0, a1: {
        '5': {
          '0': {'goal': 'Sam'},
        },
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 1);
  });

  test('penalty goal counts as a goal; red/second-yellow as red card', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 1, s2: 0, a1: {
        '1': [
          {'penalty goal': 'Sam'},
          {'second yellow': 'Kai'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 1);
    expect(r.statByName('A', 'Kai', 'redCards'), 1);
  });

  test('clean sheet credited to keeper of team that conceded zero', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 3, s2: 0, k1: 'Sam')
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'cleanSheets'), 1);
  });

  test('substitution and foul produce no counter', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 0, s2: 0, a1: {
        '1': [
          {'substitution': 'Sam'},
          {'foul': 'Kai'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 0);
    expect(r.statByName('A', 'Kai', 'goals'), 0);
  });

  test('standingFor unknown team returns a zero row', () {
    final r = computeTournamentStats(matches: const [], rosters: rosters);
    expect(r.standingFor('Z').pts, 0);
    expect(r.standingFor('Z').gp, 0);
  });

  test('statByName goalsAndAssists sums both', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 1, s2: 0, a1: {
        '1': [
          {'goal': 'Sam'},
          {'assist': 'Sam'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goalsAndAssists'), 2);
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (file missing)

Run: `flutter test test/tournament_stats_engine_test.dart`

- [ ] **Step 3: Implement** — create `lib/misc/tournament_stats_engine.dart`:

```dart
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// Canonical event-type strings written to a match timeline. Kept in sync with
/// the Manager app's tournament_stats_engine.dart and the user-app icons.
class TournamentEvents {
  static const String goal = 'goal';
  static const String assist = 'assist';
  static const String save = 'save';
  static const String dpl = 'dpl';
  static const String yellowCard = 'yellow card';
  static const String redCard = 'red card';
  static const String secondYellow = 'second yellow';
  static const String ownGoal = 'own goal';
  static const String penaltyGoal = 'penalty goal';
  static const String penaltySaved = 'penalty saved';
  static const String penaltyMissed = 'penalty missed';
  static const String foul = 'foul';
  static const String substitution = 'substitution';
}

/// One team's standings row.
class TeamStanding {
  int gp = 0, w = 0, d = 0, l = 0, gs = 0, gc = 0, pts = 0;
  int get gd => gs - gc;
}

/// One player's counters.
class PlayerCounters {
  int goals = 0, assists = 0, saves = 0, dpl = 0, cleanSheets = 0,
      yellowCards = 0, redCards = 0;
}

/// Result of a recompute, with convenience accessors for the UI.
class ComputedTournamentStats {
  final Map<String, TeamStanding> standings; // teamId -> row
  final Map<String, Map<String, PlayerCounters>> players; // teamId -> name -> counters
  final Set<String> unknownPlayers;

  const ComputedTournamentStats({
    required this.standings,
    required this.players,
    required this.unknownPlayers,
  });

  /// Standing for a team, or a zero row if the team has no counted matches.
  TeamStanding standingFor(String teamId) =>
      standings[teamId] ?? TeamStanding();

  /// Derived stat value for a player by stat name (mirrors
  /// TournamentPlayer.statByName), reading the computed counters. 0 if unknown.
  int statByName(String teamId, String playerName, String stat) {
    final c = players[teamId]?[playerName];
    if (c == null) return 0;
    switch (stat) {
      case 'goals':
        return c.goals;
      case 'assists':
        return c.assists;
      case 'saves':
        return c.saves;
      case 'dpl':
        return c.dpl;
      case 'cleanSheets':
        return c.cleanSheets;
      case 'yellowCards':
        return c.yellowCards;
      case 'redCards':
        return c.redCards;
      case 'goalsAndAssists':
        return c.goals + c.assists;
      default:
        return 0;
    }
  }
}

/// Recomputes standings + player counters from LIVE (status 1) and FINISHED
/// (status 2) matches — so in-progress scores feed the table and leaders.
/// Upcoming (status 0) matches are ignored. Pure: no Firebase access.
ComputedTournamentStats computeTournamentStats({
  required List<TournamentMatch> matches,
  required Map<String, List<TournamentPlayer>> rosters,
}) {
  final standings = <String, TeamStanding>{};
  final players = <String, Map<String, PlayerCounters>>{};
  final unknown = <String>{};

  rosters.forEach((teamId, list) {
    standings.putIfAbsent(teamId, () => TeamStanding());
    final byName = players.putIfAbsent(teamId, () => {});
    for (final p in list) {
      byName.putIfAbsent(p.name, () => PlayerCounters());
    }
  });

  PlayerCounters? counterFor(String? teamId, String playerName) {
    if (teamId == null) return null;
    final byName = players[teamId];
    if (byName == null) {
      unknown.add('$teamId/$playerName');
      return null;
    }
    final c = byName[playerName];
    if (c == null) {
      unknown.add('$teamId/$playerName');
      return null;
    }
    return c;
  }

  void applyEvent(String? teamId, String type, String playerName) {
    final c = counterFor(teamId, playerName);
    if (c == null) return;
    switch (type.toLowerCase().trim()) {
      case TournamentEvents.goal:
      case TournamentEvents.penaltyGoal:
        c.goals++;
        break;
      case TournamentEvents.assist:
        c.assists++;
        break;
      case TournamentEvents.save:
      case TournamentEvents.penaltySaved:
        c.saves++;
        break;
      case TournamentEvents.dpl:
        c.dpl++;
        break;
      case TournamentEvents.yellowCard:
        c.yellowCards++;
        break;
      case TournamentEvents.redCard:
      case TournamentEvents.secondYellow:
        c.redCards++;
        break;
      // own goal, penalty missed, foul, substitution: timeline-only, no counter.
      default:
        break;
    }
  }

  for (final m in matches) {
    // KEY FAN DIFFERENCE vs Manager: include live (1) AND finished (2).
    if (m.status != 1 && m.status != 2) continue;
    final t1 = m.team1Id;
    final t2 = m.team2Id;
    if (t1 == null || t2 == null) continue;

    final st1 = standings.putIfAbsent(t1, () => TeamStanding());
    final st2 = standings.putIfAbsent(t2, () => TeamStanding());
    final s1 = m.team1Score;
    final s2 = m.team2Score;

    st1.gp++;
    st2.gp++;
    st1.gs += s1;
    st1.gc += s2;
    st2.gs += s2;
    st2.gc += s1;
    if (s1 > s2) {
      st1.w++;
      st1.pts += 3;
      st2.l++;
    } else if (s2 > s1) {
      st2.w++;
      st2.pts += 3;
      st1.l++;
    } else {
      st1.d++;
      st2.d++;
      st1.pts += 1;
      st2.pts += 1;
    }

    for (final e in _eventsFromActivity(m.team1Activity)) {
      applyEvent(t1, e.type, e.player);
    }
    for (final e in _eventsFromActivity(m.team2Activity)) {
      applyEvent(t2, e.type, e.player);
    }

    if (s2 == 0 && m.team1Keeper != null) {
      counterFor(t1, m.team1Keeper!)?.cleanSheets++;
    }
    if (s1 == 0 && m.team2Keeper != null) {
      counterFor(t2, m.team2Keeper!)?.cleanSheets++;
    }
  }

  return ComputedTournamentStats(
    standings: standings,
    players: players,
    unknownPlayers: unknown,
  );
}

/// Flattens a Team{N}Activity map into (type, player) records. Buckets may be
/// a List or an index-keyed Map; entries are {type: playerName}.
List<({String type, String player})> _eventsFromActivity(
    Map<String, dynamic>? activity) {
  final out = <({String type, String player})>[];
  if (activity == null) return out;

  void addFromEntry(dynamic entry) {
    if (entry is Map) {
      entry.forEach((k, v) {
        out.add((type: k.toString(), player: v.toString()));
      });
    }
  }

  activity.forEach((_, bucket) {
    if (bucket is List) {
      for (final entry in bucket) {
        addFromEntry(entry);
      }
    } else if (bucket is Map) {
      bucket.forEach((_, entry) => addFromEntry(entry));
    }
  });

  return out;
}
```

- [ ] **Step 4: Run — expect PASS** (all engine tests + full suite)

Run: `flutter test test/tournament_stats_engine_test.dart && flutter test`

- [ ] **Step 5: Commit**

```bash
git add lib/misc/tournament_stats_engine.dart test/tournament_stats_engine_test.dart
git commit -m "feat: fan-side live stats engine (live+finished matches feed standings/counters)"
```

---

### Task 3: Live standings + playing-now in the Table tab

**Files:**
- Modify: `lib/tournament_tabs/table_tab.dart`
- Modify: `lib/tournamentdetail.dart` (compute `stats`, pass to `TableTab`)

This task makes `TableTab` take the computed stats and read standings from them, adds the playing-now highlight, and wires the computation in `tournamentdetail`. After this task the Table tab is live; the other two tabs still use stored stats until Tasks 4–5 (they compile and work meanwhile).

- [ ] **Step 1: Add `stats` to `tournamentdetail.dart` and pass to TableTab**

Read `lib/tournamentdetail.dart` around the `build` method and the tab construction (the `TabBarView`/children list, ~lines 195–230). Add the import at the top:
```dart
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
```
In `build`, BEFORE returning the widget tree (where `_matches`/`_teams`/`_rosters` are in scope), compute:
```dart
    final stats = computeTournamentStats(matches: _matches, rosters: _rosters);
```
Then update the `TableTab(...)` constructor call to pass it:
```dart
                  TableTab(
                    teams: _teams,
                    matches: _matches,
                    tournamentId: widget.tournamentId,
                    stats: stats,
                  ),
```
(Leave `PlayerStatsTab` and `TeamsTab` calls unchanged for now.)

- [ ] **Step 2: Update `TableTab` to accept and use `stats`**

In `lib/tournament_tabs/table_tab.dart`:

Add import:
```dart
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
```

Add the field + constructor param:
```dart
  final ComputedTournamentStats stats;
```
```dart
  const TableTab({
    super.key,
    required this.teams,
    required this.matches,
    required this.stats,
    this.tournamentId,
  });
```

Replace `_sortGroup` so it sorts by the DERIVED standing (pts → gd → gs):
```dart
  List<TournamentTeam> _sortGroup(List<TournamentTeam> group) {
    return group
      ..sort((a, b) {
        final sa = stats.standingFor(a.id);
        final sb = stats.standingFor(b.id);
        if (sb.pts != sa.pts) return sb.pts.compareTo(sa.pts);
        if (sb.gd != sa.gd) return sb.gd.compareTo(sa.gd);
        return sb.gs.compareTo(sa.gs);
      });
  }
```

Add a helper to compute the set of teams currently playing (place it in the class):
```dart
  Set<String> get _liveTeamIds => matches
      .where((m) => m.status == 1)
      .expand((m) => [m.team1Id, m.team2Id])
      .whereType<String>()
      .toSet();
```

In `_teamRow`, read the derived standing and the live flag. At the top of `_teamRow`, after `final qualColor = ...;` add:
```dart
    final s = stats.standingFor(team.id);
    final isLive = _liveTeamIds.contains(team.id);
```
Replace the stored-field cells with the derived ones — change `'${team.gp}'`→`'${s.gp}'`, `'${team.wins}'`→`'${s.w}'`, `'${team.draws}'`→`'${s.d}'`, `'${team.losses}'`→`'${s.l}'`, `'${team.gs}'`→`'${s.gs}'`, `'${team.gc}'`→`'${s.gc}'`, the GD cell `team.gd`→`s.gd` (both the value and the color checks), and the Pts cell `'${team.points}'`→`'${s.pts}'`.

Add the live tint to the row `Container`'s `decoration` — change the `BoxDecoration(border: ...)` to also set a color when live:
```dart
        decoration: BoxDecoration(
          color: isLive ? const Color(0x1A0A7D2C) : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
```

Add the pulsing green dot before the team name. Find the team-name `Expanded(flex: 5, child: Text(team.name, ...))` and wrap the name in a Row with the dot when live:
```dart
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      if (isLive) ...[
                        const _LiveDot(),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          team.name,
                          style: const TextStyle(fontSize: 13),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
```

Add a small pulsing-dot widget at the bottom of `table_tab.dart` (mirrors the one in `live_filter_bar.dart`):
```dart
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
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: Color(0xFF0A7D2C), shape: BoxShape.circle),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze + test**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter analyze lib/tournament_tabs/table_tab.dart lib/tournamentdetail.dart && flutter test`
Expected: no new errors; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/tournament_tabs/table_tab.dart lib/tournamentdetail.dart
git commit -m "feat: live standings + playing-now highlight in Table tab"
```

---

### Task 4: Live leaders in the Player Stats tab

**Files:**
- Modify: `lib/tournament_tabs/playerstats_tab.dart`
- Modify: `lib/tournamentdetail.dart` (pass `stats` to `PlayerStatsTab`)

- [ ] **Step 1: Pass `stats` from tournamentdetail** — update the `PlayerStatsTab(...)` call (the `stats` local already exists from Task 3):
```dart
                  PlayerStatsTab(
                    rosters: _rosters,
                    teams: _teams,
                    tournamentId: widget.tournamentId,
                    stats: stats,
                  ),
```
(Keep whatever args were already there; just add `stats: stats,`. Read the current call first to preserve existing params like `tournamentId`.)

- [ ] **Step 2: Use derived stats in `playerstats_tab.dart`**

Add import:
```dart
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
```
Add the field + constructor param:
```dart
  final ComputedTournamentStats stats;
```
```dart
  const PlayerStatsTab({
    super.key,
    required this.rosters,
    required this.teams,
    required this.stats,
    this.tournamentId,
  });
```
Replace `_getSortedByAll` to read derived values (note: it's in the State class, so reach the widget via `widget.stats`):
```dart
  List<TournamentPlayer> _getSortedByAll(String stat) {
    final allPlayers = TournamentService.getAllPlayers(widget.rosters);
    int valueOf(TournamentPlayer p) =>
        widget.stats.statByName(p.teamId, p.name, stat);
    final filtered = allPlayers.where((p) => valueOf(p) > 0).toList();
    filtered.sort((a, b) => valueOf(b).compareTo(valueOf(a)));
    return filtered;
  }
```
In `build`, the row value currently is `final value = player.statByName(stat);` — change to:
```dart
                    final value = widget.stats.statByName(player.teamId, player.name, stat);
```

- [ ] **Step 3: Analyze + test**

Run: `flutter analyze lib/tournament_tabs/playerstats_tab.dart lib/tournamentdetail.dart && flutter test`
Expected: no new errors; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/tournament_tabs/playerstats_tab.dart lib/tournamentdetail.dart
git commit -m "feat: live player-stat leaders from derived stats"
```

---

### Task 5: Live W/D/L in the Teams tab

**Files:**
- Modify: `lib/tournament_tabs/teams_tab.dart`
- Modify: `lib/tournamentdetail.dart` (pass `stats` to `TeamsTab`)

- [ ] **Step 1: Pass `stats` from tournamentdetail** — update the `TeamsTab(...)` call:
```dart
                  TeamsTab(
                    teams: _teams,
                    matches: _matches,
                    rosters: _rosters,
                    tournamentId: widget.tournamentId,
                    stats: stats,
                  ),
```
(Preserve existing params; just add `stats: stats,`. Read the current call first.)

- [ ] **Step 2: Use derived W/D/L in `teams_tab.dart`**

Add import:
```dart
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
```
Add field + constructor param:
```dart
  final ComputedTournamentStats stats;
```
```dart
  const TeamsTab({
    super.key,
    required this.teams,
    required this.matches,
    required this.rosters,
    required this.tournamentId,
    required this.stats,
  });
```
Find where the team card shows record (the Explore report noted `team.wins`, `team.draws`, `team.losses` around line 120). Read that build section; replace the three reads with the derived standing. Right before they're used (inside the `itemBuilder` after `final team = teamList[index];`) add:
```dart
        final s = stats.standingFor(team.id);
```
and change `team.wins`→`s.w`, `team.draws`→`s.d`, `team.losses`→`s.l` in that card's record display.

- [ ] **Step 3: Analyze + test**

Run: `flutter analyze lib/tournament_tabs/teams_tab.dart lib/tournamentdetail.dart && flutter test`
Expected: no new errors; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/tournament_tabs/teams_tab.dart lib/tournamentdetail.dart
git commit -m "feat: live W/D/L in Teams tab from derived stats"
```

---

### Task 6: Status-priority match ordering

**Files:**
- Modify: `lib/tournament_tabs/fixtures_tab.dart`

Order matches **live (1) → upcoming (0) → finished (2)**; within each group keep date → time → bracket. No dimming.

- [ ] **Step 1: Read the current sort** in `lib/tournament_tabs/fixtures_tab.dart` (the `sortedMatches.sort((a, b) {...})` block, ~lines 325–335) to confirm exact variable names (`a.stage`, `a.date`, `a.bracketPosition`, optional `a.time`).

- [ ] **Step 2: Replace the comparator** with a status-priority sort. Add a top-level helper near the top of the file (after imports):
```dart
/// Display priority: live first, then upcoming, then finished.
int _statusRank(int status) {
  switch (status) {
    case 1: // live
      return 0;
    case 0: // upcoming
      return 1;
    default: // finished (2) and anything else
      return 2;
  }
}
```
Replace the body of the existing `sortedMatches.sort((a, b) { ... })` with:
```dart
    sortedMatches.sort((a, b) {
      final ra = _statusRank(a.status);
      final rb = _statusRank(b.status);
      if (ra != rb) return ra.compareTo(rb);
      final aDate = int.tryParse(a.date) ?? 0;
      final bDate = int.tryParse(b.date) ?? 0;
      if (aDate != bDate) return aDate.compareTo(bDate);
      final at = a.time ?? '';
      final bt = b.time ?? '';
      if (at != bt) return at.compareTo(bt);
      return a.bracketPosition.compareTo(b.bracketPosition);
    });
```
(If the current sort also factors `stage`/knockout order, preserve a stage tiebreak as the LAST comparison so knockout rounds still read in order — add `final stageCmp = TournamentStage.fromString(a.stage).sortOrder.compareTo(TournamentStage.fromString(b.stage).sortOrder); if (stageCmp != 0) return stageCmp;` immediately before the `bracketPosition` return, keeping the existing `TournamentStage` import.)

- [ ] **Step 3: Analyze + test**

Run: `flutter analyze lib/tournament_tabs/fixtures_tab.dart && flutter test`
Expected: no new errors; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/tournament_tabs/fixtures_tab.dart
git commit -m "feat: order matches live -> upcoming -> finished (no dimming)"
```

---

### Task 7: Full verification + finishing

**Files:** none (verification only)

- [ ] **Step 1: Full automated verification**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test`
Expected: all tests pass (existing + new keeper + engine tests).
Then `flutter analyze lib/misc/tournament_stats_engine.dart lib/model/tournamentmatch.dart lib/tournament_tabs/table_tab.dart lib/tournament_tabs/playerstats_tab.dart lib/tournament_tabs/teams_tab.dart lib/tournament_tabs/fixtures_tab.dart lib/tournamentdetail.dart` — no new errors.
If `pubspec.lock` shows modified: `git restore pubspec.lock`.

- [ ] **Step 2: On-device manual test (owner, plain language)**

In the fan app while a group match is scored live in the Manager:
1. Open the tournament → Table tab: the two playing teams show a green tint + pulsing dot; as goals are recorded the points/GD update and rows re-sort — no refresh.
2. Player Stats tab: scorers/assisters climb live.
3. Teams tab: W/D/L update live.
4. Matches/Fixtures list: the live match sits at the top; upcoming below by time; finished at the bottom (not greyed).

- [ ] **Step 3: Use superpowers:finishing-a-development-branch**

Tests verified in Step 1. Branch stays local. (This is Spec 1 of 3; do NOT merge — Spec 2 and Spec 3 continue on the same branch.) Report completion and surface to the owner for the on-device test before starting Spec 2.

---

## Self-review notes (done at plan time)
- **Spec coverage:** §2 engine → Task 2 (with keeper prereq Task 1); §2 wiring → Tasks 3–5; "playing now" → Task 3; player/team live → Tasks 4–5; ordering → Task 6; testing → Tasks 1,2 + 7. All spec sections mapped.
- **Type consistency:** `ComputedTournamentStats.standingFor`/`statByName`, `TeamStanding{gp,w,d,l,gs,gc,pts,gd}`, `PlayerCounters` fields are used identically in Tasks 3–5. Table reads `s.w/s.d/s.l` (standing) vs the model's `wins/draws/losses` — intentional.
- **Compile-safety:** Task 3 adds the `stats` local in tournamentdetail and the required `stats` param to TableTab together; Tasks 4–5 add the param to the other tabs and pass the already-existing `stats` local — every task leaves the app compiling.
- **No placeholders.** Engine + tests are complete code; tab edits give exact old→new snippets with instructions to read surrounding lines first (line numbers drift in large files).
