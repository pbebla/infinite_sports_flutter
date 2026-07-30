# Match-Card Cohesion Implementation Plan (Cohesion Spec 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the match card and make location/history cohesive: remove the date from the live header, move location into a tappable card under Match Leaders, make Match Leaders show THIS match's leaders, make the team-detail History row live for the current tournament, and give the Manager a reusable location library.

**Architecture:** Fan-side: pure helpers (location parse, maps URL, single-match tallies) + UI rewiring of `tournament_match_detail.dart`, `match_facts_tab.dart`, `tournamentteamdetail.dart`. Manager-side: a `TournamentLocation` model + library service methods + a dropdown in the match editor that writes a structured `Location` snapshot onto the match.

**Tech Stack:** Flutter, Firebase RTDB, `url_launcher` (already a dep). Spec: `docs/superpowers/specs/2026-06-14-match-card-cohesion-design.md`.

## Ground rules (every task)
- Fan app: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, branch `zaya/live-scores`. Manager app: `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, branch `zaya-live-scores` — ALWAYS use absolute paths (`cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && ...`); your default CWD is the fan app.
- All commits LOCAL. Stage exact paths only — NEVER `git add -A`. Fan app: never stage `PROJECT_REFERENCE.md` / `SoccerStats.png`. If `pubspec.lock` shows modified, `git restore pubspec.lock`.
- Verify branch with `git branch --show-current` before committing.

### File map
| File | App | Task |
|---|---|---|
| `lib/misc/match_location.dart` (Create) | fan | T1 — MatchLocationInfo + maps URL |
| `lib/misc/single_match_tallies.dart` (Create) | fan | T2 — this-match player tallies |
| `lib/model/tournamentmatch.dart` (Modify) | fan | T3 — parse Location into locationInfo |
| `lib/tournament_match_detail.dart` (Modify) | fan | T4 — remove date+location from live header |
| `lib/tournament_tabs/match_facts_tab.dart` (Modify) | fan | T5 location card, T6 this-match leaders |
| `lib/tournamentteamdetail.dart` (Modify) | fan | T7 — history current row live |
| `lib/models/tournament_location.dart` (Create) | mgr | T8 — model |
| `lib/core/constants/firebase_paths.dart`, `lib/services/firebase/tournament_service.dart` (Modify) | mgr | T9 — paths + service |
| `lib/ui/tournaments/manage_bracket_page.dart`, `lib/models/tournament_match.dart` (Modify) | mgr | T10 — editor dropdown + write Location |

---

### Task 1: Fan — MatchLocationInfo + maps URL helper (pure)

**Files:** Create `lib/misc/match_location.dart`; Test `test/match_location_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/match_location_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/match_location.dart';

void main() {
  group('MatchLocationInfo.fromMatch', () {
    test('parses structured Location map', () {
      final info = MatchLocationInfo.fromMatch(
        location: {'Venue': 'Pioneer High School', 'Address': '1290 Blossom Hill Rd', 'Field': 'Field 1 · Turf'},
        legacyString: null,
      );
      expect(info, isNotNull);
      expect(info!.venue, 'Pioneer High School');
      expect(info.address, '1290 Blossom Hill Rd');
      expect(info.field, 'Field 1 · Turf');
    });
    test('falls back to legacy string (venue only)', () {
      final info = MatchLocationInfo.fromMatch(location: null, legacyString: 'City Park — Field 2');
      expect(info, isNotNull);
      expect(info!.venue, 'City Park — Field 2');
      expect(info.address, isNull);
      expect(info.field, isNull);
    });
    test('null when no location at all', () {
      expect(MatchLocationInfo.fromMatch(location: null, legacyString: null), isNull);
      expect(MatchLocationInfo.fromMatch(location: null, legacyString: ''), isNull);
    });
  });

  group('mapsUrl', () {
    test('uses address when present, url-encoded', () {
      final info = MatchLocationInfo(venue: 'Pioneer HS', address: '1290 Blossom Hill Rd, San Jose', field: 'F1');
      expect(info.mapsUrl(),
          'https://www.google.com/maps/search/?api=1&query=1290%20Blossom%20Hill%20Rd%2C%20San%20Jose');
    });
    test('falls back to venue when no address', () {
      final info = MatchLocationInfo(venue: 'Pioneer HS', address: null, field: null);
      expect(info.mapsUrl(), 'https://www.google.com/maps/search/?api=1&query=Pioneer%20HS');
    });
  });
}
```

- [ ] **Step 2: Run, expect FAIL**
Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test test/match_location_test.dart`
Expected: FAIL (file not found).

- [ ] **Step 3: Implement** — `lib/misc/match_location.dart`:
```dart
/// Structured match location (venue + optional address + field), parsed from
/// the per-match `Location` snapshot the Manager writes, with a fallback to
/// the legacy free-text `matchLocation` string. Pure — no Flutter imports.
class MatchLocationInfo {
  final String venue;
  final String? address;
  final String? field;

  const MatchLocationInfo({required this.venue, this.address, this.field});

  /// Builds from the match's `Location` map (preferred) or the legacy string.
  /// Returns null when there is no usable location.
  static MatchLocationInfo? fromMatch({
    required Object? location,
    required String? legacyString,
  }) {
    if (location is Map) {
      final venue = (location['Venue'] ?? location['venue'])?.toString();
      if (venue != null && venue.trim().isNotEmpty) {
        String? str(Object? v) {
          final s = v?.toString();
          return (s == null || s.trim().isEmpty) ? null : s;
        }
        return MatchLocationInfo(
          venue: venue,
          address: str(location['Address'] ?? location['address']),
          field: str(location['Field'] ?? location['field']),
        );
      }
    }
    if (legacyString != null && legacyString.trim().isNotEmpty) {
      return MatchLocationInfo(venue: legacyString);
    }
    return null;
  }

  /// Google Maps search URL — opens the OS map-app chooser. Uses the address
  /// when available, otherwise the venue name.
  String mapsUrl() {
    final query = Uri.encodeComponent((address != null && address!.trim().isNotEmpty)
        ? address!
        : venue);
    return 'https://www.google.com/maps/search/?api=1&query=$query';
  }
}
```

- [ ] **Step 4: Run, expect PASS**
Run: `flutter test test/match_location_test.dart` → all pass. Then `flutter test` → all pass.

- [ ] **Step 5: Commit**
```bash
git add lib/misc/match_location.dart test/match_location_test.dart
git commit -m "feat: MatchLocationInfo parse + Google Maps URL helper"
```

---

### Task 2: Fan — single-match player tallies (pure)

**Files:** Create `lib/misc/single_match_tallies.dart`; Test `test/single_match_tallies_test.dart`.

Reuses the Spec-1 engine's event mapping but scoped to ONE match's activity, returning per-player {goals, assists, saves, dpl} keyed by player name.

- [ ] **Step 1: Write the failing test** — `test/single_match_tallies_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch m(Map<String, dynamic>? a1, Map<String, dynamic>? a2) =>
    TournamentMatch(
      id: 'M', stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Id: 'A', team2Id: 'B', team1Score: 0, team2Score: 0, status: 1,
      team1Activity: a1, team2Activity: a2, bracketPosition: 0,
    );

void main() {
  test('tallies goals/assists/saves/dpl across both teams', () {
    final t = singleMatchPlayerTallies(m(
      {
        '12': [
          {'goal': 'Sam'},
          {'assist': 'Kai'},
        ],
        '20': [
          {'penalty goal': 'Sam'},
        ],
      },
      {
        '5': [
          {'save': 'Gary'},
          {'dpl': 'Gary'},
        ],
      },
    ));
    expect(t['Sam']!.goals, 2); // goal + penalty goal
    expect(t['Kai']!.assists, 1);
    expect(t['Gary']!.saves, 1);
    expect(t['Gary']!.dpl, 1);
  });

  test('non-counter events ignored; empty when no activity', () {
    final t = singleMatchPlayerTallies(m({
      '1': [
        {'foul': 'Sam'},
        {'substitution': 'Kai'},
        {'yellow card': 'Sam'},
      ],
    }, null));
    expect(t['Sam']?.goals ?? 0, 0);
    expect(t['Sam']?.saves ?? 0, 0);
    expect(singleMatchPlayerTallies(m(null, null)), isEmpty);
  });

  test('index-keyed Map bucket tolerated', () {
    final t = singleMatchPlayerTallies(m({
      '5': {
        '0': {'goal': 'Sam'},
      },
    }, null));
    expect(t['Sam']!.goals, 1);
  });
}
```

- [ ] **Step 2: Run, expect FAIL**
Run: `flutter test test/single_match_tallies_test.dart` → FAIL (missing file).

- [ ] **Step 3: Implement** — `lib/misc/single_match_tallies.dart`:
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

/// Tallies goals/assists/saves/dpl from a single match's activity, keyed by
/// player name. Mirrors the Spec-1 engine's event mapping (goal/penalty goal
/// -> goals, assist -> assists, save/penalty saved -> saves, dpl -> dpl); all
/// other events are timeline-only. Pure.
Map<String, MatchPlayerTally> singleMatchPlayerTallies(TournamentMatch match) {
  final out = <String, MatchPlayerTally>{};

  void apply(String type, String player) {
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

  void scan(Map<String, dynamic>? activity) {
    if (activity == null) return;
    void addEntry(dynamic entry) {
      if (entry is Map) {
        entry.forEach((k, v) => apply(k.toString(), v.toString()));
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

  scan(match.team1Activity);
  scan(match.team2Activity);
  return out;
}
```

- [ ] **Step 4: Run, expect PASS**
Run: `flutter test test/single_match_tallies_test.dart` → pass. Then `flutter test` → all pass.

- [ ] **Step 5: Commit**
```bash
git add lib/misc/single_match_tallies.dart test/single_match_tallies_test.dart
git commit -m "feat: single-match player tallies helper (this-match leaders)"
```

---

### Task 3: Fan — parse structured Location onto the match model

**Files:** Modify `lib/model/tournamentmatch.dart`; Test `test/tournamentmatch_location_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/tournamentmatch_location_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  test('parses structured Location into locationInfo', () {
    final m = TournamentMatch.fromFirebase('M1', {
      'Team1Id': 'a', 'Team2Id': 'b', 'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
      'Location': {'Venue': 'Pioneer HS', 'Address': '1290 Blossom Hill Rd', 'Field': 'Field 1'},
    });
    expect(m.locationInfo, isNotNull);
    expect(m.locationInfo!.venue, 'Pioneer HS');
    expect(m.locationInfo!.field, 'Field 1');
  });

  test('falls back to MatchLocation string', () {
    final m = TournamentMatch.fromFirebase('M2', {
      'Team1Id': 'a', 'Team2Id': 'b', 'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
      'MatchLocation': 'City Park',
    });
    expect(m.locationInfo!.venue, 'City Park');
    expect(m.locationInfo!.address, isNull);
  });

  test('locationInfo null when no location', () {
    final m = TournamentMatch.fromFirebase('M3', {
      'Team1Id': 'a', 'Team2Id': 'b', 'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
    });
    expect(m.locationInfo, isNull);
  });
}
```

- [ ] **Step 2: Run, expect FAIL**
Run: `flutter test test/tournamentmatch_location_test.dart` → FAIL (getter not defined).

- [ ] **Step 3: Implement** — in `lib/model/tournamentmatch.dart`:
  - Add import at top: `import 'package:infinite_sports_flutter/misc/match_location.dart';`
  - Add field after `final String? matchLocation;`: `final MatchLocationInfo? locationInfo;`
  - Add constructor param after `this.matchLocation,`: `this.locationInfo,`
  - In `fromFirebase`, before the `return TournamentMatch(`, add:
```dart
    final locationInfo = MatchLocationInfo.fromMatch(
      location: firstNonNull(data, ['Location', 'location']),
      legacyString: firstNonNull(data, ['MatchLocation', 'matchLocation'])?.toString(),
    );
```
  - Add to the returned constructor (after `matchLocation:`): `locationInfo: locationInfo,`

- [ ] **Step 4: Run, expect PASS**
Run: `flutter test test/tournamentmatch_location_test.dart` → pass. Then `flutter test` → all pass.

- [ ] **Step 5: Commit**
```bash
git add lib/model/tournamentmatch.dart test/tournamentmatch_location_test.dart
git commit -m "feat: parse structured Location into TournamentMatch.locationInfo"
```

---

### Task 4: Fan — remove date + location from the LIVE header

**Files:** Modify `lib/tournament_match_detail.dart` (the `isLive` branch of `_buildScoreboardHeader`, ~lines 109-129).

- [ ] **Step 1: Make the change** — In the `if (isLive)` branch, the `scoreWidget` Column currently ends with: `MatchClockText`, a `SizedBox(height: 10)`, the date `Text(_formatDate(_match.date), ...)`, and a location `if (...) [...]` block. Delete everything AFTER `MatchClockText(clock: _match.clock),` up to (but not including) the closing `],` of that Column — i.e. remove the trailing `const SizedBox(height: 10)`, the date `Text`, and the entire `if (_match.matchLocation != null ...) [...]` block. The live `scoreWidget` Column must end:
```dart
          const SizedBox(height: 4),
          MatchClockText(clock: _match.clock),
        ],
      );
```
Leave the `isFinished` and scheduled (`else`) branches UNCHANGED. Do not touch the team columns/Row.

- [ ] **Step 2: Analyze + test**
Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter analyze lib/tournament_match_detail.dart && flutter test`
Expected: no new errors (a now-unused `_formatDate` is still used by other branches — confirm; if the analyzer flags it as unused, it means no other branch uses it, in which case leave it — it IS referenced in finished/scheduled date display elsewhere; if truly unused, prefix with `// ignore: unused_element` ONLY if analyze errors). All tests pass.

- [ ] **Step 3: Commit**
```bash
git add lib/tournament_match_detail.dart
git commit -m "feat: drop date + location from live match header (cleaner, location moves to card)"
```

---

### Task 5: Fan — Location card under Match Leaders

**Files:** Modify `lib/tournament_tabs/match_facts_tab.dart`.

The Facts build renders the timeline then calls `_buildMatchLeaders(context)` (which starts with a `Divider` + "Match Leaders" header). Insert a location card method and render it immediately BEFORE `_buildMatchLeaders` in the build list.

- [ ] **Step 1: Add imports** at top of `match_facts_tab.dart`:
```dart
import 'package:url_launcher/url_launcher.dart';
import 'package:infinite_sports_flutter/misc/match_location.dart';
```

- [ ] **Step 2: Add the location-card builder** as a method on the State (near `_buildMatchLeaders`):
```dart
  Widget _buildLocationCard(BuildContext context) {
    final info = widget.match.locationInfo;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final ok = await launchUrl(Uri.parse(info.mapsUrl()),
                  mode: LaunchMode.externalApplication);
              if (!ok) {
                messenger.showSnackBar(
                    const SnackBar(content: Text("Couldn't open maps.")));
              }
            } catch (_) {
              messenger.showSnackBar(
                  const SnackBar(content: Text("Couldn't open maps.")));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.venue,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (info.field != null) ...[
                        const SizedBox(height: 2),
                        Text(info.field!,
                            style: const TextStyle(
                                color: Color(0xFF1A237E), fontSize: 13)),
                      ],
                      if (info.address != null) ...[
                        const SizedBox(height: 3),
                        Text(info.address!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 12)),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.directions, size: 14, color: Color(0xFF1A237E)),
                          SizedBox(width: 4),
                          Text('Get directions',
                              style: TextStyle(
                                  color: Color(0xFF1A237E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
```
(If the State exposes the match as a different name than `widget.match`, use the actual reference — read the file; the timeline already reads the match's activity, so the field exists.)

- [ ] **Step 3: Render it** — in the Facts `build`, find where `_buildMatchLeaders(context)` is added to the children list and insert `_buildLocationCard(context),` immediately BEFORE it.

- [ ] **Step 4: Analyze + test**
Run: `flutter analyze lib/tournament_tabs/match_facts_tab.dart && flutter test` → no new errors; all pass.

- [ ] **Step 5: Commit**
```bash
git add lib/tournament_tabs/match_facts_tab.dart
git commit -m "feat: tappable location card under Match Leaders (opens maps)"
```

---

### Task 6: Fan — Match Leaders = THIS match (Goals/Assists/Saves/DPL)

**Files:** Modify `lib/tournament_tabs/match_facts_tab.dart` (`_buildMatchLeaders`).

- [ ] **Step 1: Make the change** — In `_buildMatchLeaders`:
  - Add at the top of the method: `final tallies = singleMatchPlayerTallies(widget.match);`
  - Change the `categories` list to drop Yellow Cards (owner: Goals/Assists/Saves/DPL only):
```dart
    final categories = [
      {'label': 'Goals', 'stat': 'goals'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Saves', 'stat': 'saves'},
      {'label': 'DPL', 'stat': 'dpl'},
    ];
```
  - Replace `int getValue(TournamentPlayer p, String stat) => p.statByName(stat);` with:
```dart
    int getValue(TournamentPlayer p, String stat) =>
        tallies[p.name]?.byStat(stat) ?? 0;
```
  - Add import at top: `import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';`
  Everything else (the row rendering, the "Match Leaders" header, empty-state `SizedBox.shrink`) stays.

- [ ] **Step 2: Analyze + test**
Run: `flutter analyze lib/tournament_tabs/match_facts_tab.dart && flutter test` → no new errors; all pass.

- [ ] **Step 3: Commit**
```bash
git add lib/tournament_tabs/match_facts_tab.dart
git commit -m "feat: Match Leaders shows this-match goals/assists/saves/DPL"
```

---

### Task 7: Fan — team-detail Tournament History: current row live

**Files:** Modify `lib/tournamentteamdetail.dart` (the `FutureBuilder` rendering the history list, ~lines 392-430).

The history list comes from `getTeamTournamentHistory` (stored Table per tournament). Each `entry` is a `Map<String,dynamic>` that includes the tournament name + record fields and (per the service) a tournament key/id. The page already computes `computeTournamentStats(matches: _matches, rosters: _rosters)` in Spec 1 for the Record card.

- [ ] **Step 1: Read** `getTeamTournamentHistory` in `lib/misc/tournament_service.dart` to confirm what identifies each entry's tournament (it iterates `/Tournaments`; ensure each result map carries the tournament KEY — if it does not, add a `'tournamentId': tourneyKey.toString()` to each result map in the service so the UI can match the current tournament; commit that tiny service change as part of this task). Confirm the record field names in each entry (e.g. `W`,`D`,`L`,`Pts` or `wins`,...).

- [ ] **Step 2: Override the current tournament's row** — In the history `itemBuilder`/`map`, where each `entry` is rendered, compute the live standing for the current tournament and substitute its W/D/L/etc. values:
```dart
              final isCurrent = entry['tournamentId']?.toString() == widget.tournamentId;
              final s = isCurrent
                  ? computeTournamentStats(matches: _matches, rosters: _rosters)
                      .standingFor(widget.teamId)
                  : null;
              final w = s?.w ?? (entry['W'] ?? entry['wins'] ?? 0);
              final d = s?.d ?? (entry['D'] ?? entry['draws'] ?? 0);
              final l = s?.l ?? (entry['L'] ?? entry['losses'] ?? 0);
              final pts = s?.pts ?? (entry['Pts'] ?? entry['points'] ?? 0);
```
Use `w`/`d`/`l`/`pts` (and `s?.gd`/`s?.gs`/`s?.gc` if those are shown) in the row's display instead of the raw `entry[...]` reads. Match the exact field names the history row currently displays (read them first). The `computeTournamentStats` import already exists on this page from Spec 1.

- [ ] **Step 3: Analyze + test**
Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter analyze lib/tournamentteamdetail.dart lib/misc/tournament_service.dart && flutter test` → no new errors; all pass.

- [ ] **Step 4: Commit**
```bash
git add lib/tournamentteamdetail.dart lib/misc/tournament_service.dart
git commit -m "feat: team-detail history shows live record for the current tournament"
```

---

### Task 8: Manager — TournamentLocation model (pure)

**Files (Manager, absolute paths):** Create `lib/models/tournament_location.dart`; Test `test/tournament_location_test.dart`.

- [ ] **Step 1: Write the failing test** — `C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter/test/tournament_location_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/models/tournament_location.dart';

void main() {
  test('round-trips through firebase map', () {
    const loc = TournamentLocation(
      id: 'L1', name: 'Pioneer HS', address: '1290 Blossom Hill Rd',
      fields: ['Field 1 · Turf', 'Field 2 · Grass'],
    );
    final map = loc.toFirebaseMap();
    expect(map['Name'], 'Pioneer HS');
    expect(map['Address'], '1290 Blossom Hill Rd');
    expect(map['Fields'], ['Field 1 · Turf', 'Field 2 · Grass']);
    final back = TournamentLocation.fromFirebase('L1', map);
    expect(back.id, 'L1');
    expect(back.name, 'Pioneer HS');
    expect(back.fields.length, 2);
  });

  test('fromFirebase tolerates missing fields list', () {
    final back = TournamentLocation.fromFirebase('L2', {'Name': 'City Park'});
    expect(back.name, 'City Park');
    expect(back.address, '');
    expect(back.fields, isEmpty);
  });
}
```

- [ ] **Step 2: Run, expect FAIL**
Run: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test test/tournament_location_test.dart` → FAIL.

- [ ] **Step 3: Implement** — `C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter/lib/models/tournament_location.dart`:
```dart
/// A reusable venue saved per tournament (location library). Picked from a
/// dropdown in the match editor so venues/fields aren't re-typed per game.
class TournamentLocation {
  final String id;
  final String name;
  final String address;
  final List<String> fields;

  const TournamentLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.fields,
  });

  Map<String, dynamic> toFirebaseMap() => {
        'Name': name,
        'Address': address,
        'Fields': fields,
      };

  factory TournamentLocation.fromFirebase(String id, Map data) {
    final rawFields = data['Fields'] ?? data['fields'];
    final fields = <String>[];
    if (rawFields is List) {
      for (final f in rawFields) {
        if (f != null) fields.add(f.toString());
      }
    } else if (rawFields is Map) {
      rawFields.forEach((_, v) {
        if (v != null) fields.add(v.toString());
      });
    }
    return TournamentLocation(
      id: id,
      name: (data['Name'] ?? data['name'] ?? '').toString(),
      address: (data['Address'] ?? data['address'] ?? '').toString(),
      fields: fields,
    );
  }
}
```

- [ ] **Step 4: Run, expect PASS**
Run: `flutter test test/tournament_location_test.dart` → pass. Then `flutter test` → all pass.

- [ ] **Step 5: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git add lib/models/tournament_location.dart test/tournament_location_test.dart
git commit -m "feat: TournamentLocation model for the location library"
```

---

### Task 9: Manager — location paths + service methods

**Files (Manager):** Modify `lib/core/constants/firebase_paths.dart`, `lib/services/firebase/tournament_service.dart`.

- [ ] **Step 1: Add the path** — in `firebase_paths.dart`, after `tournamentMatchClock(...)`:
```dart
  static String tournamentLocations(String tournamentId) =>
      '$tournaments/$tournamentId/Locations';
```

- [ ] **Step 2: Add service methods** — in `tournament_service.dart` (it has `ref(path)` from FirebaseService; import the model + FirebasePaths if not present — read the file to confirm imports):
```dart
  /// All saved venues for a tournament (the location library).
  Future<List<TournamentLocation>> getLocations(String tournamentId) async {
    final snap = await ref(FirebasePaths.tournamentLocations(tournamentId)).get();
    final val = snap.value;
    if (val is! Map) return [];
    final out = <TournamentLocation>[];
    val.forEach((k, v) {
      if (v is Map) out.add(TournamentLocation.fromFirebase(k.toString(), v));
    });
    return out;
  }

  /// Saves (creates or overwrites) a venue; returns its id.
  Future<String> saveLocation(String tournamentId, TournamentLocation loc) async {
    final base = ref(FirebasePaths.tournamentLocations(tournamentId));
    final node = loc.id.isEmpty ? base.push() : base.child(loc.id);
    await node.set(loc.toFirebaseMap());
    return node.key ?? loc.id;
  }

  /// Appends a new field label to an existing venue.
  Future<void> addFieldToLocation(
      String tournamentId, String locId, String field) async {
    final node =
        ref('${FirebasePaths.tournamentLocations(tournamentId)}/$locId/Fields');
    final snap = await node.get();
    final list = <String>[];
    final val = snap.value;
    if (val is List) {
      for (final f in val) {
        if (f != null) list.add(f.toString());
      }
    } else if (val is Map) {
      val.forEach((_, v) {
        if (v != null) list.add(v.toString());
      });
    }
    if (!list.contains(field)) list.add(field);
    await node.set(list);
  }
```

- [ ] **Step 3: Analyze + test**
Run: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter analyze lib/services/firebase/tournament_service.dart lib/core/constants/firebase_paths.dart && flutter test` → no new errors; all pass.

- [ ] **Step 4: Commit**
```bash
git add lib/core/constants/firebase_paths.dart lib/services/firebase/tournament_service.dart
git commit -m "feat: location library paths + service methods (get/save/addField)"
```

---

### Task 10: Manager — match editor venue/field dropdown + write structured Location

**Files (Manager):** Modify `lib/ui/tournaments/manage_bracket_page.dart` (`_MatchEditorDialog`), `lib/models/tournament_match.dart` (`toFirebaseMap`).

Read `_MatchEditorDialog` fully first (it's a stateful dialog with `_locationController`; the dialog has access to `widget.tournamentId` or similar — confirm the field name).

- [ ] **Step 1: Load the library + dialog state** — In `_MatchEditorDialogState`, add fields:
```dart
  List<TournamentLocation> _locations = [];
  TournamentLocation? _selectedVenue;
  String? _selectedField;
```
In `initState`, load the library (use the existing service access pattern in this file — likely `ref.read(tournamentServiceProvider)`):
```dart
    ref.read(tournamentServiceProvider).getLocations(widget.tournamentId).then((locs) {
      if (!mounted) return;
      setState(() {
        _locations = locs;
        // Pre-select from the editing match's existing structured location if present.
      });
    });
```

- [ ] **Step 2: Replace the free-text field** — Replace the single "Match location / field" `TextField` (the one bound to `_locationController`) with:
  - A `DropdownButtonFormField<TournamentLocation?>` labeled "Venue" whose items are `_locations` (display `loc.name`) plus a sentinel "➕ Add new venue" entry. Selecting the sentinel opens `_addVenueDialog()` (below). On select, set `_selectedVenue` and reset `_selectedField` to the venue's first field (or null).
  - A `DropdownButtonFormField<String?>` labeled "Field" populated from `_selectedVenue?.fields`, plus a "➕ Add field" sentinel that prompts for a new field string, calls `addFieldToLocation`, appends locally, and selects it. Disabled/empty when no venue selected.
  Keep the dialog usable: if there are no saved venues, the Venue dropdown shows only "➕ Add new venue".

- [ ] **Step 3: Add-venue dialog** — add a method:
```dart
  Future<void> _addVenueDialog() async {
    final nameC = TextEditingController();
    final addrC = TextEditingController();
    final fieldC = TextEditingController();
    final saved = await showDialog<TournamentLocation>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add venue'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Venue name')),
          TextField(controller: addrC, decoration: const InputDecoration(labelText: 'Address')),
          TextField(controller: fieldC, decoration: const InputDecoration(labelText: 'First field (e.g. Field 1 · Turf)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameC.text.trim().isEmpty) return;
              Navigator.pop(
                ctx,
                TournamentLocation(
                  id: '', name: nameC.text.trim(), address: addrC.text.trim(),
                  fields: fieldC.text.trim().isEmpty ? [] : [fieldC.text.trim()],
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final id = await ref.read(tournamentServiceProvider)
        .saveLocation(widget.tournamentId, saved);
    final withId = TournamentLocation(
        id: id, name: saved.name, address: saved.address, fields: saved.fields);
    if (!mounted) return;
    setState(() {
      _locations = [..._locations, withId];
      _selectedVenue = withId;
      _selectedField = withId.fields.isNotEmpty ? withId.fields.first : null;
    });
  }
```

- [ ] **Step 4: Write the structured Location on save** — Where the dialog builds the result `TournamentMatch` (currently sets `matchLocation: _locationController.text...`), replace with structured data derived from the selections. Add to the Manager `TournamentMatch` model: a `Map<String,dynamic>? locationStructured` field (Venue/Address/Field) OR pass venue/address/field through. Simplest: in `toFirebaseMap` of the Manager `lib/models/tournament_match.dart`, also emit a `Location` map when venue info is present. Concretely:
  - Give the Manager `TournamentMatch` optional fields `venue`, `address`, `field` (Strings) OR reuse `matchLocation` for the human string and add a `Map? location`. Pick the minimal approach: add `final String? venue, address, field;` to the Manager model; in the editor result construct with those from `_selectedVenue`/`_selectedField`; set `matchLocation` to `"${venue} — ${field}"` (or venue alone) for back-compat.
  - In `toFirebaseMap`, add:
```dart
        if (venue != null && venue!.isNotEmpty)
          'Location': {
            'Venue': venue,
            if (address != null) 'Address': address,
            if (field != null) 'Field': field,
          },
        if (matchLocation != null) 'MatchLocation': matchLocation,
```
  - Update the model's `fromFirebase` to read back `Location`/`venue`/`address`/`field` so editing an existing match repopulates the dropdowns (best-effort; if the match has only the legacy string, leave venue null and the dropdown unselected).

- [ ] **Step 5: Analyze + test**
Run: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter analyze lib/ui/tournaments/manage_bracket_page.dart lib/models/tournament_match.dart && flutter test`
Expected: no new errors; all tests pass. (Report any test that referenced the old single-string behavior and adapt it.)

- [ ] **Step 6: Commit**
```bash
git add lib/ui/tournaments/manage_bracket_page.dart lib/models/tournament_match.dart
git commit -m "feat: match editor venue/field dropdown + structured Location write"
```

---

### Task 11: Full verification both apps + finishing (SURFACE TO OWNER)

**Files:** none (verification only).

- [ ] **Step 1: Fan verification**
Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test` (all pass) and `flutter analyze lib/` (note only pre-existing warnings; no NEW errors). `git restore pubspec.lock` if modified.

- [ ] **Step 2: Manager verification**
Run: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test` (all pass) and `flutter analyze lib/` (no NEW errors).

- [ ] **Step 3: Final whole-feature review** — dispatch a final reviewer over `git diff` on both branches for this spec; confirm: live header has no date/location; location card opens maps; Match Leaders is this-match Goals/Assists/Saves/DPL; team-detail history current row live; Manager dropdown saves+reuses venues and writes structured `Location`; back-compat for legacy `MatchLocation` string.

- [ ] **Step 4: STOP — surface to owner.** Do NOT merge or finish the branches (Spec 3 substitutions still to come on `zaya/live-scores` + `zaya-live-scores`). Build/install both apps on the owner's devices and present the on-device test recipe:
  - Manager: add a venue once, reuse it on another match via the dropdown.
  - Fan: open a match → location card under Match Leaders → tap → maps opens; Match Leaders shows this game's goals/assists/saves/DPL; start the match → date disappears from the header; team page → history row for the current tournament matches the live Record.

---

## Self-review notes (done at plan time)
- Spec coverage: header date/align → T4; structured location parse → T3; maps URL → T1; location card → T5; Match Leaders this-match → T2+T6; team-detail history live → T7; Manager library model/paths/service → T8+T9; editor dropdown + structured write + back-compat → T10; verification/surface → T11. All §In-scope items mapped.
- Type consistency: `MatchLocationInfo` (venue/address/field, `mapsUrl()`) used in T1/T3/T5; `singleMatchPlayerTallies` → `MatchPlayerTally.byStat` used in T2/T6; `TournamentLocation` (id/name/address/fields, toFirebaseMap/fromFirebase) used in T8/T9/T10; `computeTournamentStats(...).standingFor(...)` reused in T7 (defined in Spec 1).
- Manager `TournamentMatch` gains optional venue/address/field; `toFirebaseMap` emits `Location` + keeps `MatchLocation` for back-compat (T10) — fan reads either (T1/T3).
- No placeholders: pure helpers + model have full code/tests; UI tasks give exact insertion points anchored to real line ranges and require reading the file for surrounding names.
