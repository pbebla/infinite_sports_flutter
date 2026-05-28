# Tournament Foundation — Plan 1 Implementation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate every crash path and performance bottleneck in the existing tournament feature, consolidate duplicate code, and set up the fake Test Tournament — so Plan 2 starts on a solid foundation.

**Architecture:** Pure refactoring of the existing user-app tournament code. No new Firebase paths, no new screens. We add a safe-parsing layer, replace magic numbers with enums, deduplicate widget patterns, add persistent image caching, and parallelize Firebase reads. Final step is importing a fake Test Tournament so subsequent plans have something to test against.

**Tech Stack:** Flutter 3.x, Dart 3.3.4, Firebase Realtime Database, Provider, cached_network_image (new), flutter_test (for unit tests on the new helpers).

**Scope (from spec sections 6.1, 6.2, and Appendix A):** 20 specific issues from the read-only code review, plus fake Test Tournament setup.

**Estimated duration:** Week 1 (~5 working days).

**Branch:** `zaya/tournament-enhance-app-manager` on `infinite_sports_flutter`. All work on this branch.

---

## File Structure

### New files
- `lib/misc/parse_helpers.dart` — Safe Firebase parsing helpers (pure functions)
- `lib/model/match_status.dart` — `MatchStatus` enum
- `lib/model/tournament_stage.dart` — `TournamentStage` enum
- `lib/widgets/team_logo.dart` — Unified team logo widget
- `lib/misc/tournament_colors.dart` — Centralized color constants for tournament screens
- `test/parse_helpers_test.dart` — Unit tests for parse helpers
- `test/match_status_test.dart` — Unit tests for MatchStatus
- `test/tournament_stage_test.dart` — Unit tests for TournamentStage

### Modified files
- `lib/model/tournament.dart` — Use parse helpers, drop dual-case noise
- `lib/model/tournamentmatch.dart` — Use parse helpers, remove 8 unused fields, use MatchStatus enum
- `lib/model/tournamentteam.dart` — Use parse helpers, pre-parse hex colors
- `lib/model/tournamentplayer.dart` — Use parse helpers, add `statByName` method
- `lib/misc/tournament_service.dart` — Parallel reads, parallel ProfileUrl fetches with cache
- `lib/tournamentdetail.dart` — Try/catch + error state, lazy roster fetch, forward loaded state
- `lib/tournamentteamdetail.dart` — Accept already-loaded data via constructor, parse hex colors via model
- `lib/tournamentplayerprofile.dart` — Guard against malformed Map, use shared player-history helper, use TeamLogo
- `lib/main.dart` — Wrap `TournamentsNavigation` in lazy builder
- `lib/tournamentspage.dart` — Use TeamLogo, use cached image
- `lib/tournament_match_detail.dart` — Remove duplicate `_formatDate`, use existing utility, use TeamLogo, use MatchStatus, use centralized colors
- `lib/tournament_tabs/fixtures_tab.dart` — Same as above, plus use `statByName`, move sorting out of build
- `lib/tournament_tabs/knockout_tab.dart` — TeamLogo, MatchStatus, centralized colors
- `lib/tournament_tabs/table_tab.dart` — TeamLogo, share qualification color helper
- `lib/tournament_tabs/teams_tab.dart` — TeamLogo
- `lib/tournament_tabs/teamstats_tab.dart` — TeamLogo, precompute stats outside build
- `lib/tournament_tabs/playerstats_tab.dart` — TeamLogo, use `statByName`, precompute sorting
- `lib/tournament_tabs/match_facts_tab.dart` — Remove duplicate `_formatDate`, use `statByName`
- `lib/tournament_tabs/match_h2h_tab.dart` — Same plus TeamLogo
- `lib/tournament_tabs/match_lineup_tab.dart` — TeamLogo, share position-order helper
- `lib/misc/utility.dart` — Add shared `getUserPlayedHistory(uid)` helper
- `pubspec.yaml` — Add `cached_network_image: ^3.4.1` dependency

### Files Zayaa will modify (Firebase export)
- The exported Firebase JSON (location chosen by Zayaa) — Claude adds a `test-tournament-2026` node and returns the modified file.

---

## Task 1: Safe Firebase parsing helpers

**Why:** Every model in the tournament code uses `data['X'] as bool?` or `(data['Y'] as num?)?.toInt()` style casts. If the Firebase value is the "wrong" Dart type (e.g. `"true"` string instead of `true` bool, common when humans edit Firebase by hand), the cast throws and the whole parse fails. We need defensive helpers that accept multiple input types and return safely.

**Files:**
- Create: `lib/misc/parse_helpers.dart`
- Create: `test/parse_helpers_test.dart`

- [ ] **Step 1.1: Write the failing tests first**

Create `test/parse_helpers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

void main() {
  group('parseBool', () {
    test('returns bool from bool', () {
      expect(parseBool(true), true);
      expect(parseBool(false), false);
    });

    test('returns bool from "true"/"false" string', () {
      expect(parseBool('true'), true);
      expect(parseBool('false'), false);
      expect(parseBool('TRUE'), true);
      expect(parseBool('False'), false);
    });

    test('returns bool from int 0/1', () {
      expect(parseBool(1), true);
      expect(parseBool(0), false);
    });

    test('returns default for unknown values', () {
      expect(parseBool(null), false);
      expect(parseBool('yes'), false);
      expect(parseBool('no'), false);
      expect(parseBool(2), false);
      expect(parseBool(null, defaultValue: true), true);
    });
  });

  group('parseInt', () {
    test('returns int from int', () {
      expect(parseInt(42), 42);
      expect(parseInt(0), 0);
    });

    test('returns int from double', () {
      expect(parseInt(3.7), 3);
      expect(parseInt(0.0), 0);
    });

    test('returns int from numeric string', () {
      expect(parseInt('42'), 42);
      expect(parseInt('-7'), -7);
    });

    test('returns default for non-numeric', () {
      expect(parseInt(null), 0);
      expect(parseInt('abc'), 0);
      expect(parseInt('1.5'), 0); // not a valid int string
      expect(parseInt(null, defaultValue: 99), 99);
    });
  });

  group('parseString', () {
    test('returns string from string', () {
      expect(parseString('hello'), 'hello');
      expect(parseString(''), '');
    });

    test('converts non-strings to strings', () {
      expect(parseString(42), '42');
      expect(parseString(true), 'true');
      expect(parseString(3.14), '3.14');
    });

    test('returns default for null', () {
      expect(parseString(null), '');
      expect(parseString(null, defaultValue: 'fallback'), 'fallback');
    });
  });

  group('parseMap', () {
    test('returns map from map', () {
      expect(parseMap({'a': 1}), {'a': 1});
    });

    test('returns empty for non-map', () {
      expect(parseMap(null), {});
      expect(parseMap('not a map'), {});
      expect(parseMap([1, 2, 3]), {});
    });
  });

  group('firstNonNull', () {
    test('returns first non-null value from a map for given keys', () {
      final data = {'Name': 'Alice', 'age': 30};
      expect(firstNonNull(data, ['name', 'Name']), 'Alice');
      expect(firstNonNull(data, ['Age', 'age']), 30);
      expect(firstNonNull(data, ['missing1', 'missing2']), null);
    });
  });
}
```

- [ ] **Step 1.2: Run the test — it must fail**

Run from `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`:
```
flutter test test/parse_helpers_test.dart
```
Expected: FAIL with "Target of URI doesn't exist: 'package:infinite_sports_flutter/misc/parse_helpers.dart'"

- [ ] **Step 1.3: Implement the helpers**

Create `lib/misc/parse_helpers.dart`:

```dart
/// Safe Firebase Realtime Database parsing helpers.
///
/// Firebase returns dynamic values that may not match the declared Dart type
/// (e.g. an admin edits the console and writes "true" as a string instead of
/// a bool). These helpers accept multiple input types and degrade gracefully
/// to a default rather than throwing.

bool parseBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is int) {
    if (value == 1) return true;
    if (value == 0) return false;
  }
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
  }
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return defaultValue;
}

double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  return defaultValue;
}

String parseString(dynamic value, {String defaultValue = ''}) {
  if (value == null) return defaultValue;
  if (value is String) return value;
  return value.toString();
}

Map<dynamic, dynamic> parseMap(dynamic value) {
  if (value is Map) return value;
  return <dynamic, dynamic>{};
}

/// Returns the first non-null value from a map for any of the given keys.
/// Useful for handling both CamelCase and lowercase Firebase keys.
dynamic firstNonNull(Map data, List<String> keys) {
  for (final key in keys) {
    final v = data[key];
    if (v != null) return v;
  }
  return null;
}
```

- [ ] **Step 1.4: Run the test — it must pass**

Run:
```
flutter test test/parse_helpers_test.dart
```
Expected: All tests PASS.

- [ ] **Step 1.5: Commit**

```bash
git add lib/misc/parse_helpers.dart test/parse_helpers_test.dart
git commit -m "Add safe Firebase parsing helpers with tests

Defensive helpers (parseBool, parseInt, parseDouble, parseString,
parseMap, firstNonNull) that handle the bool/int/string type
confusion that Firebase Realtime Database manual edits can cause.
Foundation for migrating brittle as-casts in tournament models.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Migrate Tournament model to safe parsing

**Why:** `Tournament.fromFirebase` uses `data['Finished'] as bool?` which crashes if Firebase returns a string or int. We replace with `parseBool` from Task 1.

**Files:**
- Modify: `lib/model/tournament.dart`

- [ ] **Step 2.1: Read current tournament.dart to understand the structure**

Open `lib/model/tournament.dart` and review `fromFirebase`.

- [ ] **Step 2.2: Replace all brittle casts**

Replace every line in `Tournament.fromFirebase` that uses `as bool?`, `(... as num?)?.toInt()`, or `.toString()` with the corresponding parse helper.

Add `import 'package:infinite_sports_flutter/misc/parse_helpers.dart';` at the top.

Replace the field-extraction block with the pattern:

```dart
factory Tournament.fromFirebase(String id, dynamic raw) {
  final data = parseMap(raw);
  return Tournament(
    id: id,
    name: parseString(firstNonNull(data, ['Name', 'name']), defaultValue: id),
    sport: parseString(firstNonNull(data, ['Sport', 'sport']), defaultValue: 'Soccer'),
    edition: parseString(firstNonNull(data, ['Edition', 'edition'])),
    logoUrl: parseString(firstNonNull(data, ['LogoUrl', 'logoUrl'])),
    hostCity: parseString(firstNonNull(data, ['HostCity', 'hostCity'])),
    location: parseString(firstNonNull(data, ['Location', 'location'])),
    startDate: parseString(firstNonNull(data, ['StartDate', 'startDate'])),
    endDate: parseString(firstNonNull(data, ['EndDate', 'endDate'])),
    status: parseString(firstNonNull(data, ['Status', 'status'])),
    finished: parseBool(firstNonNull(data, ['Finished', 'finished'])),
    champion: parseString(firstNonNull(data, ['Champion', 'champion'])),
    runnerUp: parseString(firstNonNull(data, ['RunnerUp', 'runnerUp'])),
    goldenBoot: parseString(firstNonNull(data, ['GoldenBoot', 'goldenBoot'])),
    bestKeeper: parseString(firstNonNull(data, ['BestKeeper', 'bestKeeper'])),
    dplLeader: parseString(firstNonNull(data, ['DplLeader', 'dplLeader'])),
  );
}
```

(Match the actual existing field set — read the current file first.)

- [ ] **Step 2.3: Run flutter analyze to verify no errors**

```
flutter analyze lib/model/tournament.dart
```
Expected: No issues found.

- [ ] **Step 2.4: Commit**

```bash
git add lib/model/tournament.dart
git commit -m "Migrate Tournament model to safe parsing

Replaces brittle as-cast pattern with parse_helpers. Eliminates
crash path when Firebase 'Finished' field is stored as string or
int instead of bool. firstNonNull collapses the dual-case key
fallback (Name/name) into a clean call.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Migrate TournamentMatch model + remove unused fields

**Why:** `TournamentMatch.fromFirebase` has the same brittle-cast problem AND parses 8 fields the UI never reads (votes, direct byes, bracket cross-refs). Removing them eliminates 8 crash paths.

**Files:**
- Modify: `lib/model/tournamentmatch.dart`

- [ ] **Step 3.1: List the fields that ARE referenced in the UI**

Run from project root:
```
grep -rn "team1Vote\|team2Vote\|winnerGoesToMatchId\|winnerGoesToSlot\|team1DirectBye\|team2DirectBye\|fromMatchId1\|fromMatchId2" lib/ --include="*.dart"
```
Expected: Only references should be in `tournamentmatch.dart` itself. If grep finds usages anywhere else, those usages must be cleaned up before removing the fields.

- [ ] **Step 3.2: Remove the 8 unused fields**

In `lib/model/tournamentmatch.dart`:
- Remove the field declarations for `team1Vote`, `team2Vote`, `winnerGoesToMatchId`, `winnerGoesToSlot`, `team1DirectBye`, `team2DirectBye`, `fromMatchId1`, `fromMatchId2`
- Remove them from the constructor
- Remove their parsing lines from `fromFirebase`

- [ ] **Step 3.3: Replace remaining casts with parse helpers**

Apply the same pattern as Task 2 — every `as bool?`, `(... as num?)?.toInt()`, `.toString()` gets replaced with the appropriate parse helper. `firstNonNull` for dual-case keys.

Add the import at the top:
```dart
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';
```

- [ ] **Step 3.4: Run flutter analyze**

```
flutter analyze lib/model/tournamentmatch.dart
```
Expected: No issues found.

- [ ] **Step 3.5: Commit**

```bash
git add lib/model/tournamentmatch.dart
git commit -m "Migrate TournamentMatch to safe parsing, drop 8 unused fields

Removes team1Vote, team2Vote, winnerGoesToMatchId, winnerGoesToSlot,
team1DirectBye, team2DirectBye, fromMatchId1, fromMatchId2 — none
were read by any UI. Their brittle as-bool? casts were crash paths
for fields with no visible benefit. Remaining fields use parse_helpers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Migrate TournamentTeam model + pre-parse hex colors

**Why:** Same brittle-cast issue, plus the model stores `homeColor`/`awayColor`/`overrideColor` as raw hex strings. Every consumer then calls a local `_parseHex` helper. Move the parsing into the model so consumers get `Color?` directly.

**Files:**
- Modify: `lib/model/tournamentteam.dart`

- [ ] **Step 4.1: Add color fields and parsing**

Add a private helper at the top of the file (after the imports):

```dart
import 'dart:ui' show Color;
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

Color? _parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var clean = hex.trim();
  if (clean.startsWith('#')) clean = clean.substring(1);
  if (clean.length == 6) clean = 'FF$clean';
  if (clean.length != 8) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(value);
}
```

In the `TournamentTeam` class, change `homeColor`, `awayColor`, `overrideColor` from `String?` to `Color?`. In the constructor, accept `Color?`. In `fromFirebase`, parse the hex string via `_parseHexColor`.

- [ ] **Step 4.2: Replace remaining casts with parse helpers**

Same pattern as previous tasks. Every brittle cast becomes the parse helper. `firstNonNull` for dual-case keys.

- [ ] **Step 4.3: Update all consumers**

Search for usages of the old String color fields:
```
grep -rn "homeColor\|awayColor\|overrideColor" lib/ --include="*.dart"
```

For each consumer (likely `tournamentteamdetail.dart`):
- Remove their local `_parseHex` helper
- Remove the `.parseHex(...)` calls
- Use the `Color?` directly

- [ ] **Step 4.4: Run flutter analyze**

```
flutter analyze lib/model/tournamentteam.dart lib/tournamentteamdetail.dart
```
Expected: No issues found.

- [ ] **Step 4.5: Commit**

```bash
git add lib/model/tournamentteam.dart lib/tournamentteamdetail.dart
git commit -m "Migrate TournamentTeam to safe parsing, pre-parse hex colors

homeColor/awayColor/overrideColor change from String? to Color?,
parsed once in fromFirebase via a private _parseHexColor helper.
Consumers drop their duplicate parse-hex code. Brittle as-casts
replaced with parse_helpers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Migrate TournamentPlayer model + add `statByName` method

**Why:** Same brittle-cast issue. Plus, 5 different files duplicate a `getValue(player, stat)` switch statement to look up stats by name. Moving that into `TournamentPlayer.statByName` kills the duplication.

**Files:**
- Modify: `lib/model/tournamentplayer.dart`

- [ ] **Step 5.1: Replace casts with parse helpers**

Apply the same pattern. Add the import. Replace every brittle cast.

- [ ] **Step 5.2: Add `statByName` method**

Add this method to the `TournamentPlayer` class:

```dart
/// Returns the integer stat value for a given stat name.
/// Recognized names: 'goals', 'assists', 'saves', 'dpl',
/// 'cleanSheets', 'yellowCards', 'redCards'.
/// Returns 0 for unrecognized names.
int statByName(String stat) {
  switch (stat) {
    case 'goals':
      return goals;
    case 'assists':
      return assists;
    case 'saves':
      return saves;
    case 'dpl':
      return dpl;
    case 'cleanSheets':
      return cleanSheets;
    case 'yellowCards':
      return yellowCards;
    case 'redCards':
      return redCards;
    default:
      return 0;
  }
}
```

- [ ] **Step 5.3: Run flutter analyze**

```
flutter analyze lib/model/tournamentplayer.dart
```
Expected: No issues found.

- [ ] **Step 5.4: Commit**

```bash
git add lib/model/tournamentplayer.dart
git commit -m "Migrate TournamentPlayer to safe parsing, add statByName method

Replaces brittle as-casts with parse_helpers. Adds statByName method
that consolidates the 5 duplicate switch statements in fixtures_tab,
playerstats_tab, match_facts_tab, tournamentteamdetail.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: MatchStatus enum

**Why:** `TournamentMatch.status` is an `int` with magic values (0=pending, 1=live, 2=finished). Raw integer comparisons (`status == 1`) appear in 4+ files. We replace with a proper enum.

**Files:**
- Create: `lib/model/match_status.dart`
- Create: `test/match_status_test.dart`
- Modify: `lib/model/tournamentmatch.dart`

- [ ] **Step 6.1: Write the failing test**

Create `test/match_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/match_status.dart';

void main() {
  group('MatchStatus', () {
    test('fromInt maps 0 to pending', () {
      expect(MatchStatus.fromInt(0), MatchStatus.pending);
    });

    test('fromInt maps 1 to live', () {
      expect(MatchStatus.fromInt(1), MatchStatus.live);
    });

    test('fromInt maps 2 to finished', () {
      expect(MatchStatus.fromInt(2), MatchStatus.finished);
    });

    test('fromInt maps unknown ints to pending', () {
      expect(MatchStatus.fromInt(99), MatchStatus.pending);
      expect(MatchStatus.fromInt(-1), MatchStatus.pending);
    });

    test('toInt round-trips', () {
      for (final status in MatchStatus.values) {
        expect(MatchStatus.fromInt(status.toInt()), status);
      }
    });

    test('label returns human-readable text', () {
      expect(MatchStatus.pending.label, 'Upcoming');
      expect(MatchStatus.live.label, 'Live');
      expect(MatchStatus.finished.label, 'Final');
    });
  });
}
```

- [ ] **Step 6.2: Run test — must fail**

```
flutter test test/match_status_test.dart
```
Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 6.3: Create the enum**

Create `lib/model/match_status.dart`:

```dart
/// Represents the lifecycle state of a tournament match.
/// Stored as an int in Firebase for backwards compatibility:
/// 0 = pending, 1 = live, 2 = finished.
enum MatchStatus {
  pending(0, 'Upcoming'),
  live(1, 'Live'),
  finished(2, 'Final');

  final int _intValue;
  final String label;

  const MatchStatus(this._intValue, this.label);

  int toInt() => _intValue;

  static MatchStatus fromInt(int value) {
    for (final status in MatchStatus.values) {
      if (status._intValue == value) return status;
    }
    return MatchStatus.pending;
  }

  bool get isLive => this == MatchStatus.live;
  bool get isFinished => this == MatchStatus.finished;
  bool get isPending => this == MatchStatus.pending;
}
```

- [ ] **Step 6.4: Run test — must pass**

```
flutter test test/match_status_test.dart
```
Expected: All tests PASS.

- [ ] **Step 6.5: Use MatchStatus in TournamentMatch model**

In `lib/model/tournamentmatch.dart`:
- Add `import 'package:infinite_sports_flutter/model/match_status.dart';`
- Keep the existing `int status` field (so Firebase serialization continues working) but add a computed getter:

```dart
MatchStatus get matchStatus => MatchStatus.fromInt(status);
```

This keeps backward compatibility — the raw `int status` continues to write to Firebase as-is, but UI code can use `match.matchStatus` for type-safe checks.

- [ ] **Step 6.6: Commit**

```bash
git add lib/model/match_status.dart test/match_status_test.dart lib/model/tournamentmatch.dart
git commit -m "Add MatchStatus enum with tests

Replaces magic int values (0=pending, 1=live, 2=finished). New
TournamentMatch.matchStatus getter returns the typed enum.
Field-level status int kept for Firebase serialization
compatibility.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: TournamentStage enum

**Why:** Stage names ('group stage', 'ro16', 'qf', 'sf', 'final', '3rd place') appear as raw lowercased strings in 5+ files, each with its own switch over them for sorting and rendering. One typo and stages don't sort right. Replace with an enum.

**Files:**
- Create: `lib/model/tournament_stage.dart`
- Create: `test/tournament_stage_test.dart`

- [ ] **Step 7.1: Write the failing test**

Create `test/tournament_stage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';

void main() {
  group('TournamentStage', () {
    test('fromString recognizes group stage', () {
      expect(TournamentStage.fromString('Group Stage'), TournamentStage.group);
      expect(TournamentStage.fromString('group stage'), TournamentStage.group);
      expect(TournamentStage.fromString('GROUPS'), TournamentStage.group);
    });

    test('fromString recognizes round of 16', () {
      expect(TournamentStage.fromString('Round of 16'), TournamentStage.roundOf16);
      expect(TournamentStage.fromString('ro16'), TournamentStage.roundOf16);
      expect(TournamentStage.fromString('R16'), TournamentStage.roundOf16);
    });

    test('fromString recognizes quarterfinals', () {
      expect(TournamentStage.fromString('Quarterfinal'), TournamentStage.quarterFinal);
      expect(TournamentStage.fromString('QF'), TournamentStage.quarterFinal);
      expect(TournamentStage.fromString('quarter-final'), TournamentStage.quarterFinal);
    });

    test('fromString recognizes semifinals', () {
      expect(TournamentStage.fromString('Semifinal'), TournamentStage.semiFinal);
      expect(TournamentStage.fromString('SF'), TournamentStage.semiFinal);
    });

    test('fromString recognizes final', () {
      expect(TournamentStage.fromString('Final'), TournamentStage.finalStage);
      expect(TournamentStage.fromString('F'), TournamentStage.finalStage);
    });

    test('fromString recognizes third place', () {
      expect(TournamentStage.fromString('Third Place'), TournamentStage.thirdPlace);
      expect(TournamentStage.fromString('3rd Place'), TournamentStage.thirdPlace);
    });

    test('fromString returns unknown for unrecognized', () {
      expect(TournamentStage.fromString('Mystery'), TournamentStage.unknown);
      expect(TournamentStage.fromString(''), TournamentStage.unknown);
    });

    test('sortOrder orders stages chronologically', () {
      final stages = [
        TournamentStage.finalStage,
        TournamentStage.group,
        TournamentStage.thirdPlace,
        TournamentStage.semiFinal,
        TournamentStage.quarterFinal,
        TournamentStage.roundOf16,
      ];
      stages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(stages.first, TournamentStage.group);
      expect(stages.last, TournamentStage.finalStage);
    });

    test('isKnockout identifies knockout stages', () {
      expect(TournamentStage.group.isKnockout, false);
      expect(TournamentStage.roundOf16.isKnockout, true);
      expect(TournamentStage.finalStage.isKnockout, true);
      expect(TournamentStage.thirdPlace.isKnockout, true);
    });
  });
}
```

- [ ] **Step 7.2: Run test — must fail**

```
flutter test test/tournament_stage_test.dart
```
Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 7.3: Create the enum**

Create `lib/model/tournament_stage.dart`:

```dart
/// Represents the bracket stage of a tournament match.
/// Stored as a free-form string in Firebase for flexibility;
/// this enum normalizes parsing and ordering.
enum TournamentStage {
  group(0, 'Group Stage', false),
  roundOf16(1, 'Round of 16', true),
  quarterFinal(2, 'Quarterfinal', true),
  semiFinal(3, 'Semifinal', true),
  thirdPlace(4, 'Third Place', true),
  finalStage(5, 'Final', true),
  unknown(99, 'Other', false);

  final int sortOrder;
  final String label;
  final bool isKnockout;

  const TournamentStage(this.sortOrder, this.label, this.isKnockout);

  /// Parse a raw stage string from Firebase into the enum.
  /// Tolerant of common variants (case, hyphens, abbreviations).
  static TournamentStage fromString(String? raw) {
    if (raw == null || raw.isEmpty) return TournamentStage.unknown;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (normalized.contains('group') || normalized == 'groups') {
      return TournamentStage.group;
    }
    if (normalized == 'ro16' ||
        normalized == 'r16' ||
        normalized.contains('roundof16')) {
      return TournamentStage.roundOf16;
    }
    if (normalized == 'qf' ||
        normalized.contains('quarter')) {
      return TournamentStage.quarterFinal;
    }
    if (normalized == 'sf' ||
        normalized.contains('semi')) {
      return TournamentStage.semiFinal;
    }
    if (normalized.contains('third') ||
        normalized.contains('3rdplace') ||
        normalized == '3rd') {
      return TournamentStage.thirdPlace;
    }
    if (normalized == 'f' ||
        normalized == 'final' ||
        normalized.contains('finals')) {
      return TournamentStage.finalStage;
    }
    return TournamentStage.unknown;
  }
}
```

- [ ] **Step 7.4: Run test — must pass**

```
flutter test test/tournament_stage_test.dart
```
Expected: All tests PASS.

- [ ] **Step 7.5: Commit**

```bash
git add lib/model/tournament_stage.dart test/tournament_stage_test.dart
git commit -m "Add TournamentStage enum with tests

Centralizes parsing and ordering of tournament bracket stages.
Tolerant of casing, hyphens, abbreviations (QF, R16, SF, F).
Provides sortOrder for chronological sorting and isKnockout
for filtering knockout-stage matches.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Migrate UI files to use MatchStatus + TournamentStage

**Why:** Replace every raw `status == 1` and `stage == 'qf'` style check with the typed enums.

**Files:**
- Modify: `lib/tournament_match_detail.dart`
- Modify: `lib/tournament_tabs/fixtures_tab.dart`
- Modify: `lib/tournament_tabs/knockout_tab.dart`
- Modify: `lib/tournament_tabs/match_h2h_tab.dart`
- Modify: `lib/misc/tournament_service.dart`

- [ ] **Step 8.1: Find every magic-number status check**

```
grep -rn "status == [012]\|status==[012]" lib/ --include="*.dart"
```

For each line, replace with the typed check:
- `match.status == 1` → `match.matchStatus.isLive`
- `match.status == 2` → `match.matchStatus.isFinished`
- `match.status == 0` → `match.matchStatus.isPending`

- [ ] **Step 8.2: Find every raw stage string comparison**

```
grep -rn "stage\.toLowerCase()\|stage == '\|stage==" lib/ --include="*.dart"
```

For each file with a local `_stageOrder()` or `_isKnockout()` switch:
- Add `import 'package:infinite_sports_flutter/model/tournament_stage.dart';`
- Replace the local switch with `TournamentStage.fromString(match.stage).sortOrder` or `.isKnockout`
- Delete the local helper

- [ ] **Step 8.3: Run flutter analyze on all modified files**

```
flutter analyze lib/tournament_match_detail.dart lib/tournament_tabs/fixtures_tab.dart lib/tournament_tabs/knockout_tab.dart lib/tournament_tabs/match_h2h_tab.dart lib/misc/tournament_service.dart
```
Expected: No issues found.

- [ ] **Step 8.4: Commit**

```bash
git add lib/tournament_match_detail.dart lib/tournament_tabs/fixtures_tab.dart lib/tournament_tabs/knockout_tab.dart lib/tournament_tabs/match_h2h_tab.dart lib/misc/tournament_service.dart
git commit -m "Migrate tournament UI to MatchStatus and TournamentStage enums

Replaces magic-number status checks (status == 1) and raw stage
string switches with typed enum methods. Removes 4 duplicate
_stageOrder() and _isKnockout() helpers across tab files.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Error handling on TournamentDetailPage

**Why:** `TournamentDetailPage._loadData` has no try/catch. Any Firebase error leaves `_isLoading = true` forever — user stuck on a spinner.

**Files:**
- Modify: `lib/tournamentdetail.dart`

- [ ] **Step 9.1: Add error state field and UI**

Modify `_TournamentDetailPageState`:

Add field:
```dart
String? _loadError;
```

Modify `_loadData()` to wrap the awaits in try/catch:

```dart
Future<void> _loadData() async {
  try {
    final results = await Future.wait([
      TournamentService.getTournamentHeader(widget.tournamentId),
      TournamentService.getTeams(widget.tournamentId),
      TournamentService.getMatches(widget.tournamentId),
    ]);
    final header = results[0] as Tournament?;
    final teams = results[1] as Map<String, TournamentTeam>;
    final matches = results[2] as List<TournamentMatch>;

    // Rosters only fetched lazily by tabs that need them
    if (!mounted) return;
    setState(() {
      _header = header;
      _teams = teams;
      _matches = matches;
      _isLoading = false;
      _loadError = null;
    });
  } catch (e, st) {
    debugPrint('TournamentDetailPage._loadData error: $e\n$st');
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadError = 'Could not load tournament. Pull to retry.';
    });
  }
}
```

In the `build` method, after the `_isLoading` check, add an error branch:

```dart
if (_loadError != null) {
  return Scaffold(
    appBar: AppBar(title: const Text('Tournament')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _loadError = null;
                });
                _loadData();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 9.2: Same pattern for tournamentteamdetail.dart and tournamentplayerprofile.dart**

Apply equivalent try/catch + error state to:
- `_TournamentTeamDetailPageState._loadData` in `tournamentteamdetail.dart` (it does have a fallback but improve it)
- `tournamentplayerprofile.dart:38` add `if (snap.value is! Map) return [];` before the cast

- [ ] **Step 9.3: Run flutter analyze**

```
flutter analyze lib/tournamentdetail.dart lib/tournamentteamdetail.dart lib/tournamentplayerprofile.dart
```
Expected: No issues found.

- [ ] **Step 9.4: Commit**

```bash
git add lib/tournamentdetail.dart lib/tournamentteamdetail.dart lib/tournamentplayerprofile.dart
git commit -m "Fix infinite-spinner trap with try/catch + retry UI

TournamentDetailPage now catches Firebase errors and shows a
'Could not load tournament. Pull to retry.' message with retry
button. Same pattern for team detail. Player profile guards
against malformed /Users/{uid}/Played data with is-Map check.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Consolidate date formatters

**Why:** Three duplicate `_formatDate(MMDDYYYY)` helpers across tournament files. `utility.dart:58-63` already has `convertDatabaseDateToFormatDate`.

**Files:**
- Modify: `lib/tournament_match_detail.dart`
- Modify: `lib/tournament_tabs/fixtures_tab.dart`
- Modify: `lib/tournament_tabs/match_h2h_tab.dart`
- Modify: `lib/tournament_tabs/match_facts_tab.dart`

- [ ] **Step 10.1: Find every duplicate `_formatDate` function**

```
grep -rn "_formatDate" lib/tournament_match_detail.dart lib/tournament_tabs/
```

- [ ] **Step 10.2: Remove the duplicates**

For each file with a local `_formatDate(String)` function:
- Delete the function
- Replace call sites with `convertDatabaseDateToFormatDate(date)` from utility.dart
- Ensure `import 'package:infinite_sports_flutter/misc/utility.dart';` is present

If a call site needed a different format (e.g. "MMM d" instead of full date), keep that as inline `DateFormat` for now — but note it in the commit message.

- [ ] **Step 10.3: Run flutter analyze**

```
flutter analyze lib/tournament_match_detail.dart lib/tournament_tabs/
```
Expected: No issues found.

- [ ] **Step 10.4: Commit**

```bash
git add lib/tournament_match_detail.dart lib/tournament_tabs/fixtures_tab.dart lib/tournament_tabs/match_h2h_tab.dart lib/tournament_tabs/match_facts_tab.dart
git commit -m "Remove duplicate _formatDate helpers, use utility.dart

Three near-identical MMDDYYYY parse-and-format functions in
tournament files replaced with the existing convertDatabaseDateToFormatDate
helper in utility.dart. Call sites that needed alternate date
formats keep an inline DateFormat (noted for future consolidation).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Use statByName in tournament tabs

**Why:** Four files duplicate a `getValue(player, stat)` switch. Replace each with `player.statByName(stat)`.

**Files:**
- Modify: `lib/tournament_tabs/fixtures_tab.dart`
- Modify: `lib/tournament_tabs/playerstats_tab.dart`
- Modify: `lib/tournament_tabs/match_facts_tab.dart`
- Modify: `lib/tournamentteamdetail.dart`

- [ ] **Step 11.1: Find every getValue switch**

```
grep -rn "case 'goals':" lib/tournament_tabs/ lib/tournamentteamdetail.dart
```

- [ ] **Step 11.2: Replace each switch**

For each file with a `int getValue(TournamentPlayer p, String stat)` or `_statValue` helper:
- Delete the function
- Replace every call site with `player.statByName(stat)`

- [ ] **Step 11.3: Run flutter analyze**

```
flutter analyze lib/tournament_tabs/fixtures_tab.dart lib/tournament_tabs/playerstats_tab.dart lib/tournament_tabs/match_facts_tab.dart lib/tournamentteamdetail.dart
```
Expected: No issues found.

- [ ] **Step 11.4: Commit**

```bash
git add lib/tournament_tabs/fixtures_tab.dart lib/tournament_tabs/playerstats_tab.dart lib/tournament_tabs/match_facts_tab.dart lib/tournamentteamdetail.dart
git commit -m "Replace 5 duplicate stat-lookup switches with player.statByName

Removes the case 'goals': return p.goals; ... pattern from 4 files
(5 instances total). All call sites now use the method added to
TournamentPlayer in an earlier task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Add cached_network_image + TeamLogo widget

**Why:** ~15 places use bare `Image.network` with no disk caching — every cold launch re-downloads every logo. Plus, the "circle avatar with image and Icons.shield fallback" pattern is duplicated 12+ times.

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/widgets/team_logo.dart`

- [ ] **Step 12.1: Add the dependency**

In `pubspec.yaml`, find the `dependencies:` section and add:

```yaml
  cached_network_image: ^3.4.1
```

(Add it under the existing entries, in alphabetical order if the file follows that convention.)

- [ ] **Step 12.2: Install the package**

```
flutter pub get
```
Expected: Successful resolution, no version conflicts.

- [ ] **Step 12.3: Create the TeamLogo widget**

Create `lib/widgets/team_logo.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Unified team logo widget. Replaces the 12+ duplicated
/// CircleAvatar/ClipOval + Image.network + errorBuilder patterns
/// across tournament screens.
class TeamLogo extends StatelessWidget {
  final String? url;
  final double size;
  final IconData fallbackIcon;
  final Color? fallbackBackground;

  const TeamLogo({
    super.key,
    required this.url,
    this.size = 32,
    this.fallbackIcon = Icons.shield_outlined,
    this.fallbackBackground,
  });

  @override
  Widget build(BuildContext context) {
    final bg = fallbackBackground ?? Theme.of(context).colorScheme.surfaceContainerHighest;

    if (url == null || url!.isEmpty) {
      return _fallback(bg);
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        placeholder: (context, url) => _fallback(bg),
        errorWidget: (context, url, error) => _fallback(bg),
      ),
    );
  }

  Widget _fallback(Color bg) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(fallbackIcon, size: size * 0.6, color: Colors.grey.shade600),
    );
  }
}
```

- [ ] **Step 12.4: Run flutter analyze**

```
flutter analyze lib/widgets/team_logo.dart
```
Expected: No issues found.

- [ ] **Step 12.5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/widgets/team_logo.dart
git commit -m "Add cached_network_image + TeamLogo unified widget

cached_network_image: ^3.4.1 dependency provides persistent
disk caching (Image.network only caches in memory and re-downloads
on cold launch). TeamLogo widget consolidates the 12+ duplicate
ClipOval + Image.network + Icons.shield fallback patterns into
one reusable widget with explicit memory cache sizing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: Migrate all team-logo usages to TeamLogo

**Why:** Now that TeamLogo exists, kill the duplicates.

**Files:** All files that use `Image.network` for a logo. Run `grep -rn "Image.network" lib/` to find them. The 12+ tournament-file occurrences from the code review:
- `lib/tournamentspage.dart`
- `lib/tournamentdetail.dart`
- `lib/tournamentteamdetail.dart` (several)
- `lib/tournamentplayerprofile.dart`
- `lib/tournament_match_detail.dart`
- `lib/tournament_tabs/fixtures_tab.dart`
- `lib/tournament_tabs/knockout_tab.dart`
- `lib/tournament_tabs/table_tab.dart`
- `lib/tournament_tabs/teams_tab.dart`
- `lib/tournament_tabs/teamstats_tab.dart`
- `lib/tournament_tabs/playerstats_tab.dart`
- `lib/tournament_tabs/match_h2h_tab.dart`
- `lib/tournament_tabs/match_lineup_tab.dart`

- [ ] **Step 13.1: For each file, replace the local logo widget**

Pattern to replace:
```dart
// OLD
ClipOval(
  child: Image.network(
    url,
    width: 32,
    height: 32,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const Icon(Icons.shield),
  ),
)
```

With:
```dart
// NEW
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

TeamLogo(url: url, size: 32)
```

For each file:
- Add the import for `team_logo.dart`
- Replace every local logo widget with `TeamLogo(...)` and the correct size

- [ ] **Step 13.2: Delete the now-unused local `_teamLogo`/`_smallLogo` helpers**

In each tab file that had a local helper, delete it.

- [ ] **Step 13.3: Run flutter analyze on the whole lib/ tree**

```
flutter analyze lib/
```
Expected: No issues found.

- [ ] **Step 13.4: Smoke test in app**

Run on emulator:
```
flutter run
```
Open the existing tournament feature. Navigate through Fixtures, Knockout, Table, Teams, Team detail, Player profile. **Verify:**
- All logos still load (or show fallback)
- No layout breakage
- App doesn't crash

- [ ] **Step 13.5: Commit**

```bash
git add lib/
git commit -m "Replace 12+ duplicate logo widgets with TeamLogo

Every CircleAvatar + Image.network + errorBuilder pattern across
tournamentspage, tournamentdetail, tournamentteamdetail,
tournament_match_detail, tournamentplayerprofile and all 9 tab
files now uses TeamLogo. Disk caching via cached_network_image
means cold launches no longer re-download every logo.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Parallel reads + ProfileUrl caching in tournament_service

**Why:** `getRosters()` makes N+1 sequential per-player ProfileUrl fetches (~120 calls per tournament). `getTeams` makes two sequential queries. Both should be parallel. Plus a session-level cache prevents re-fetching the same ProfileUrls.

**Files:**
- Modify: `lib/misc/tournament_service.dart`

- [ ] **Step 14.1: Add a static ProfileUrl cache to TournamentService**

In `lib/misc/tournament_service.dart`, add at the class level:

```dart
/// Session cache for /Users/{uid}/ProfileUrl lookups.
/// Cleared by clearProfileUrlCache() if needed.
static final Map<String, String?> _profileUrlCache = {};

static void clearProfileUrlCache() => _profileUrlCache.clear();
```

- [ ] **Step 14.2: Parallelize getTeams**

Change `getTeams` from sequential awaits to parallel:

```dart
static Future<Map<String, TournamentTeam>> getTeams(String tournamentId) async {
  try {
    final ref = FirebaseDatabase.instance.ref('Tournaments/$tournamentId');
    final results = await Future.wait([
      ref.child('Teams').get(),
      ref.child('Table').get(),
    ]);
    final teamsSnap = results[0];
    final tableSnap = results[1];
    final teamsData = parseMap(teamsSnap.value);
    final tableData = parseMap(tableSnap.value);

    final teams = <String, TournamentTeam>{};
    for (final entry in teamsData.entries) {
      final teamId = entry.key.toString();
      final teamData = parseMap(entry.value);
      final tableData2 = parseMap(tableData[teamId]);
      final mergedData = {...teamData, ...tableData2};
      teams[teamId] = TournamentTeam.fromFirebase(teamId, mergedData);
    }
    return teams;
  } catch (e) {
    debugPrint('getTeams error: $e');
    return {};
  }
}
```

(Adapt the actual merging logic to match the current implementation — the key change is `Future.wait([...])`.)

- [ ] **Step 14.3: Parallelize getRosters ProfileUrl fetches**

In `getRosters`, the inner loop currently does:
```dart
// OLD - sequential
for (...) {
  if (uid != null && photoUrl == null) {
    final snap = await FirebaseDatabase.instance.ref('Users/$uid/ProfileUrl').get();
    photoUrl = parseString(snap.value, defaultValue: '');
  }
}
```

Replace with parallel collect-then-await:
```dart
// NEW - parallel + cached
final uidsToFetch = <String>{};
for (final entry in teamRoster.entries) {
  final playerData = parseMap(entry.value);
  final uid = parseString(firstNonNull(playerData, ['UID', 'uid']));
  if (uid.isNotEmpty && !_profileUrlCache.containsKey(uid)) {
    uidsToFetch.add(uid);
  }
}

if (uidsToFetch.isNotEmpty) {
  final futures = uidsToFetch.map((uid) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('Users/$uid/ProfileUrl').get();
      _profileUrlCache[uid] = parseString(snap.value, defaultValue: '');
    } catch (_) {
      _profileUrlCache[uid] = '';
    }
  });
  await Future.wait(futures);
}

// Then use _profileUrlCache[uid] when building TournamentPlayer instances.
```

- [ ] **Step 14.4: Run flutter analyze**

```
flutter analyze lib/misc/tournament_service.dart
```
Expected: No issues found.

- [ ] **Step 14.5: Smoke test**

Run on emulator. Open a tournament with a roster. Note in console output (if you added debugPrint) that fetches happen in parallel. The page should load noticeably faster (especially on slower networks).

- [ ] **Step 14.6: Commit**

```bash
git add lib/misc/tournament_service.dart
git commit -m "Parallelize Firebase reads + cache player ProfileUrls

getTeams now fetches Teams + Table in parallel via Future.wait
(was sequential). getRosters collects all uids that need
ProfileUrl, fetches them in parallel via Future.wait, and caches
the results in a session-scoped Map so subsequent reads are
instant. Cuts initial roster load from ~120 sequential round-trips
to a single parallel batch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Lazy Tournaments tab + state forwarding

**Why:** `IndexedStack` in `main.dart` eagerly instantiates all 4 tabs at app launch, including TournamentsNavigation. That triggers `getAllTournaments()` (a heavy Firebase read) for every user who opens the app, even if they never tap Tournaments. Plus, `TournamentTeamDetailPage` re-fetches teams + rosters that the parent already loaded.

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/tournamentteamdetail.dart`
- Modify: `lib/tournamentdetail.dart`

- [ ] **Step 15.1: Wrap TournamentsNavigation in a lazy builder in main.dart**

Locate where `_views` is built (around line 154). The tab list currently is:

```dart
_views = [
  Builder(builder: ...),     // index 0: live scores
  const LeaguesNavigation(),  // index 1
  const TournamentsNavigation(), // index 2  ← eager
  const AroundYou(),          // index 3
];
```

Change index 2 to lazy:

```dart
// Lazy state — only build TournamentsNavigation the first time the user taps Tournaments
bool _tournamentsTabBuilt = false;

// In _views builder:
_tournamentsTabBuilt
  ? const TournamentsNavigation()
  : const SizedBox.shrink(),
```

In `_onItemTapped`, mark the flag when the user first taps Tournaments:

```dart
void _onItemTapped(int index) {
  setState(() {
    _selectedIndex = index;
    if (index == 2 && !_tournamentsTabBuilt) {
      _tournamentsTabBuilt = true;
    }
    // ... existing title logic
  });
}
```

- [ ] **Step 15.2: Add optional already-loaded parameters to TournamentTeamDetailPage**

In `lib/tournamentteamdetail.dart`, add optional constructor parameters:

```dart
const TournamentTeamDetailPage({
  super.key,
  required this.tournamentId,
  required this.teamId,
  this.preloadedTeams,
  this.preloadedRosters,
});

final String tournamentId;
final String teamId;
final Map<String, TournamentTeam>? preloadedTeams;
final Map<String, List<TournamentPlayer>>? preloadedRosters;
```

In `_loadData()`, use the preloaded data if provided:

```dart
Future<void> _loadData() async {
  try {
    final teams = widget.preloadedTeams ??
        await TournamentService.getTeams(widget.tournamentId);
    final rosters = widget.preloadedRosters ??
        await TournamentService.getRosters(widget.tournamentId, teams);

    if (!mounted) return;
    setState(() {
      _team = teams[widget.teamId];
      _roster = rosters[widget.teamId] ?? [];
      _isLoading = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
  }
}
```

- [ ] **Step 15.3: Update push-to-TournamentTeamDetailPage call sites**

Find every place that pushes to `TournamentTeamDetailPage` and forward the loaded state when available:

```
grep -rn "TournamentTeamDetailPage(" lib/
```

For each push from `TournamentDetailPage` or its tabs, pass `preloadedTeams: _teams, preloadedRosters: _rosters` where the data is available.

- [ ] **Step 15.4: Run flutter analyze**

```
flutter analyze lib/main.dart lib/tournamentteamdetail.dart lib/tournamentdetail.dart
```
Expected: No issues found.

- [ ] **Step 15.5: Commit**

```bash
git add lib/main.dart lib/tournamentteamdetail.dart lib/tournamentdetail.dart lib/tournament_tabs/
git commit -m "Lazy-build Tournaments tab; forward loaded state to children

TournamentsNavigation no longer instantiated at app launch — only
when the user first taps the Tournaments tab. Users who never
open Tournaments no longer trigger getAllTournaments() at startup.

TournamentTeamDetailPage now accepts preloadedTeams/preloadedRosters
so taps from the parent tournament page don't re-fetch what the
parent already loaded.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: Centralize tournament colors + player history fetch dedup

**Why:** `Color(0xFF1A237E)` (navy) is hardcoded in 10+ places, inconsistent with the rest of the app's brand red. `tournamentplayerprofile.dart` duplicates the `/Users/{uid}/Played` fetch that `playerpage.dart` already does.

**Files:**
- Create: `lib/misc/tournament_colors.dart`
- Modify: `lib/misc/utility.dart`
- Modify: `lib/tournamentplayerprofile.dart`
- Modify: All files using `Color(0xFF1A237E)` or `Color(0xFFFFD700)` literals

- [ ] **Step 16.1: Create tournament_colors.dart**

Create `lib/misc/tournament_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Centralized color constants for tournament screens.
/// Replaces hardcoded literals scattered across 10+ files.
class TournamentColors {
  TournamentColors._();

  /// Header accent — navy, used for app bars and headers in tournament screens.
  static const Color headerAccent = Color(0xFF1A237E);

  /// Gold — used for champion badges, trophy icons, prize highlights.
  static const Color gold = Color(0xFFFFD700);
}
```

- [ ] **Step 16.2: Replace literals**

```
grep -rn "Color(0xFF1A237E)\|Color(0xFFFFD700)" lib/
```

For each match, replace with `TournamentColors.headerAccent` or `TournamentColors.gold`. Add the import.

- [ ] **Step 16.3: Add shared player-history helper to utility.dart**

Add to `lib/misc/utility.dart`:

```dart
/// Fetches the list of seasons / tournaments a user has played in.
/// Reads from /Users/{uid}/Played. Returns an empty list on error.
Future<List<Map<String, dynamic>>> getUserPlayedHistory(String uid) async {
  try {
    final ref = FirebaseDatabase.instance.ref('Users/$uid/Played');
    final snap = await ref.get();
    if (snap.value is! Map) return [];
    final data = snap.value as Map;
    final result = <Map<String, dynamic>>[];
    data.forEach((sportKey, sportValue) {
      if (sportValue is Map) {
        sportValue.forEach((seasonKey, teamValue) {
          result.add({
            'sport': sportKey.toString(),
            'season': seasonKey.toString(),
            'team': teamValue?.toString() ?? '',
          });
        });
      }
    });
    return result;
  } catch (e) {
    debugPrint('getUserPlayedHistory error: $e');
    return [];
  }
}
```

- [ ] **Step 16.4: Use the helper in tournamentplayerprofile.dart**

In `lib/tournamentplayerprofile.dart`, replace the inline `/Users/{uid}/Played` fetch (around line 32-53) with a call to `getUserPlayedHistory(uid)`.

- [ ] **Step 16.5: Run flutter analyze**

```
flutter analyze lib/misc/tournament_colors.dart lib/misc/utility.dart lib/tournamentplayerprofile.dart
flutter analyze lib/tournamentdetail.dart lib/tournament_match_detail.dart lib/tournamentteamdetail.dart lib/tournament_tabs/
```
Expected: No issues found.

- [ ] **Step 16.6: Commit**

```bash
git add lib/misc/tournament_colors.dart lib/misc/utility.dart lib/tournamentplayerprofile.dart lib/tournamentdetail.dart lib/tournament_match_detail.dart lib/tournamentteamdetail.dart lib/tournament_tabs/
git commit -m "Centralize tournament colors; share player history fetcher

TournamentColors constants replace 10+ hardcoded navy/gold literals
across tournament screens. utility.dart gains a getUserPlayedHistory
helper that tournamentplayerprofile.dart now uses instead of its
inline fetch (the same data shape playerpage.dart reads).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: Set up the fake Test Tournament 2026

**Why:** From now on, every feature is built and tested against `test-tournament-2026` rather than risking real tournament data.

**Files:**
- This task involves Zayaa exporting + re-importing Firebase JSON. No code commit; just a one-time data setup.

- [ ] **Step 17.1: Claude asks Zayaa to export Firebase JSON**

When this task starts, Claude posts in chat:

> **Time to export Firebase JSON.** Go to Firebase Console → Realtime Database → click the ⋮ menu → "Export JSON" → save the file somewhere (e.g. Downloads). Then share the file path with me (drag and drop, or tell me the path). I'll add the fake Test Tournament 2026 node and give you the modified file to re-import.

- [ ] **Step 17.2: Zayaa exports and shares the JSON**

Zayaa performs the export and shares the file with Claude.

- [ ] **Step 17.3: Claude adds the test-tournament-2026 node**

Claude reads the JSON, adds under `Tournaments`:

```json
"test-tournament-2026": {
  "Name": "Test Tournament 2026",
  "Sport": "Soccer",
  "Edition": "Test",
  "StartDate": "08272026",
  "EndDate": "08302026",
  "HostCity": "Test City",
  "Location": "Test Field",
  "Status": "Active",
  "Finished": false,
  "Teams": { /* 8 fake teams */ },
  "Matches": { /* group stage + knockout fixtures */ },
  "Rosters": { /* 10 players per team */ },
  "Table": { /* initial standings, all zeros */ },
  "PredictionConfig": {
    "Open": true,
    "AwardsLockTime": "2026-08-27T12:00:00Z",
    "Scoring": {
      "Champion": 10,
      "RunnerUp": 5,
      "ThirdPlace": 3,
      "GoldenBoot": 8,
      "MostAssists": 8,
      "MostCleanSheets": 6,
      "BestDefender": 6,
      "MatchWinner": 1,
      "ExactScoreBonus": 3
    },
    "Categories": {
      "Champion": true,
      "RunnerUp": true,
      "ThirdPlace": true,
      "GoldenBoot": true,
      "MostAssists": true,
      "MostCleanSheets": true,
      "BestDefender": true,
      "MatchWinner": true,
      "ExactScoreBonus": true
    }
  }
}
```

(Full fake data is generated by Claude — 8 teams with placeholder logos, full bracket, ~80 players.)

Claude saves the modified JSON and tells Zayaa the file path.

- [ ] **Step 17.4: Zayaa imports the JSON**

Zayaa goes to Firebase Console → Realtime Database → ⋮ menu → "Import JSON" → selects the modified file → confirms import.

- [ ] **Step 17.5: Verify the test tournament exists**

In the Firebase Console, navigate to `/Tournaments/test-tournament-2026/`. Confirm all the fake data is present.

- [ ] **Step 17.6: No commit needed**

This is data-only work. Nothing to commit in the repo.

---

## Task 18: Final smoke verification

**Why:** Before declaring Plan 1 done, run a full sanity check on the device against the fake Test Tournament.

**Files:** None to modify. This is verification only.

- [ ] **Step 18.1: Pull latest code**

```bash
git -C "C:\Users\zayaa\StudioProjects\infinite_sports_flutter" pull
```

- [ ] **Step 18.2: Run the app**

Open Android Studio. Open the project. Press Play to run on emulator or connected device.

- [ ] **Step 18.3: Open Test Tournament 2026 and navigate every screen**

In the running app:
1. Sign in
2. Tap Tournaments tab
3. Find "Test Tournament 2026" in the list
4. Open it
5. Navigate every tab: Fixtures, Knockout, Table, Teams, Team Stats, Player Stats
6. Tap into a team — open its detail
7. Tap into a player — open their profile
8. Go back, tap into a match — open its detail
9. Navigate H2H, Match Facts, Match Lineup tabs within the match detail
10. Verify no crashes, no spinners that don't resolve, all logos load, no obvious visual breakage

- [ ] **Step 18.4: Verify performance**

- App startup feels normal — no obvious delay from loading tournaments
- Opening Test Tournament 2026 happens in <2 seconds
- Logos load quickly (cached after first load)

- [ ] **Step 18.5: Zayaa reports back**

In chat:
> "Plan 1 verification done. App opens. Test Tournament 2026 loads in [N] seconds. [Any issues you noticed.]"

- [ ] **Step 18.6: Push the branch**

```bash
git -C "C:\Users\zayaa\StudioProjects\infinite_sports_flutter" push
```

---

## Plan 1 done

All 20 bug-review issues addressed. Fake Test Tournament running. Branch pushed. Ready for Plan 2 (Admin Tournament CRUD).

---

## Self-Review Checklist (Claude runs at end)

**1. Spec coverage:** Every Appendix-A issue from the design spec has a task above. ✓

**2. Placeholder scan:** No "TODO", "TBD", or "fill in" patterns in the plan. Every code block contains the actual code to write. ✓

**3. Type consistency:**
- `parseBool`, `parseInt`, `parseString`, `parseMap`, `firstNonNull` used consistently across all model tasks ✓
- `MatchStatus.fromInt`, `.toInt()`, `.isLive`, `.isFinished`, `.isPending`, `.label` are all defined in Task 6 and used consistently in Task 8 ✓
- `TournamentStage.fromString`, `.sortOrder`, `.isKnockout`, `.label` defined in Task 7 and used in Task 8 ✓
- `TeamLogo(url:, size:, fallbackIcon:, fallbackBackground:)` defined in Task 12 and used in Task 13 ✓
- `TournamentColors.headerAccent`, `.gold` defined in Task 16 ✓
- `getUserPlayedHistory(uid)` defined in Task 16 ✓
- `clearProfileUrlCache()` defined in Task 14 ✓

**4. No dangling references.** ✓
