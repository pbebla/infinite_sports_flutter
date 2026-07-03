# Registration Redesign L1b Implementation Plan (Team Paths + CSV Export)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build phase L1b of the registration redesign: the two team registration paths (captain registers a new team → admin approval queue issues a join code with a "code waives payment" rule → joiner enters the code in pin boxes and lands on the team, skipping payment when waived) plus a CSV export button on the Manager submissions page — all on top of the shipped L1a engine, still dual-writing the legacy `Sign Ups/...` buckets.

**Architecture:** The twin-synced pure model file gains `RegTeam` (pending|approved|rejected teams under `Registrations/{regId}/Teams/{teamId}`), join-code helpers (confusable-free alphabet, injectable `Random`, normalize/validate/match), and `amountOwed` (captains owe `teamFee`, everyone else `fee`). Manager is the source of truth; the fan copy is refreshed with `Copy-Item` + a `git diff --no-index` byte-identity check. Manager side: three additive `FirebasePaths` helpers, four `RegistrationService` team methods (approve/reject/setCode/setWaive — approving does NOT write rosters; L2 materializes teams later), one Riverpod provider, a new Teams page at `/registrations/:regId/teams` (peer page reached from an AppBar action on the existing submissions page — the submissions page is a plain single-list Scaffold, so a peer route matches the existing go_router structure with far less churn than converting it to tabs), and a Manager-only pure CSV builder (`lib/models/registration_csv.dart`, NOT twinned — the fan app never exports) shared via the same `Share.shareXFiles` + `getTemporaryDirectory` pattern the tournament bulk-import already uses. Fan side: `pin_code_fields` for code entry, two new service submits (`submitCaptain` pushes the pending team then the submission; `submitJoiner` is born Paid/`'team code'` when waived and legacy-writes the matching Paid/NotPaid bucket), a path-parametrized `RegistrationFormPage`, an `amount`-parametrized `PaymentScreen` (captains must see the TEAM fee, not the player fee), a `JoinCodePage`, path-page activation of both team tiles, and a status page that shows the captain's join code prominently with copy + `SharePlus.instance.share` once approved.

**Tech Stack:** Flutter 3.44 / Dart 3. Manager: Riverpod, go_router, `FirebaseService`/`FirebasePaths`, `share_plus ^10.1.4` + `path_provider ^2.1.5` (both already in the Manager pubspec — nothing to add), package `infinite_app_manager`. Fan: stateful widgets + `Navigator.push(MaterialPageRoute(...))`, static-method service, `share_plus ^12.0.1` (already present; v12 API is `SharePlus.instance.share(ShareParams(...))`), NEW dep `pin_code_fields ^8.0.1`, package `infinite_sports_flutter`.

**Spec:** `docs/superpowers/specs/2026-06-30-registration-redesign-design.md` (fan repo) — §4 team approvals, §5 fan flow (steps 2/4/6), §6 payments, §7 edge cases, §8 testing, §9 phase L1b. CSV export is an owner-approved L1b addition (not in the spec document).

**Branches:** `zaya-registration` in BOTH repos (both already checked out — verified). All commits LOCAL (no push). L1a + L1a.1 are DONE and committed on these branches.

---

## Conventions for every task below

- **Repo roots:** `MANAGER` = `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, `FAN` = `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`. Every file path in a task is prefixed with the repo it belongs to.
- **Run flutter via PowerShell** (never rely on PATH):
  ```powershell
  $env:Path = "C:\src\flutter\bin;" + $env:Path
  Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"   # or the FAN root
  ```
- **Branch check before touching files** in a repo: `git rev-parse --abbrev-ref HEAD` must print `zaya-registration` in BOTH repos. If it doesn't, STOP and ask — do not create branches in this phase.
- **Stage exact paths only** — never `git add -A` or `git add .`. In the FAN repo NEVER stage `PROJECT_REFERENCE.md`, `SoccerStats.png`, `.claude/`, or `docs/` files (this plan file itself lives under `docs/` — do not commit it; the controller reviews it separately).
- **pubspec.lock:** if a task incidentally modifies it, run `git restore pubspec.lock` before committing — EXCEPT Task 7 (fan pubspec task), where `pubspec.lock` MUST be committed alongside `pubspec.yaml`.
- All commits stay local. Do not merge to `zaya-features`; the owner decides after on-device testing.
- Build/install one app at a time (never two Gradle builds in parallel). Device serial: `GN434J02403404RL`.
- The fan repo's full `flutter analyze` can be slow; analyze the touched paths first, then do one full pass in the verify task with a generous timeout.
- **Repo lint gotchas (Flutter 3.44):** file-header comments use `//` (not `///`); `ListTile` needs a `Material` ancestor (`Card` provides one) — never a bare decorated `Container`; avoid `RadioListTile` and `DropdownButtonFormField` (use `ChoiceChip` rows and `InputDecorator`+`DropdownButton` instead — the in-repo wizard/trophy-editor pattern); `ReorderableListView` callbacks are `onReorderItem` (not touched in this phase).
- The twin model file (`MANAGER lib/models/registration_models.dart` ↔ `FAN lib/registration/registration_models.dart`) must stay byte-identical. Manager tasks edit ONLY the Manager copy; Task 7 syncs the fan copy with `Copy-Item` and verifies with `git diff --no-index`.

---

## File Structure

**MANAGER (`InfiniteSportsManagerFlutter`):**
- **Modify** `lib/models/registration_models.dart` — append `RegTeam` + `regTeamsFromNode` + `cleanTeamName`, join-code helpers (`kJoinCodeAlphabet`, `normalizeJoinCode`, `generateJoinCode`, `generateUniqueJoinCode`, `validateJoinCode`, `JoinCodeMatch`, `matchJoinCode`, `hasDuplicateTeamName`), `amountOwed`. Adds `import 'dart:math';` (pure Dart — still zero Flutter/Firebase).
- **Modify** `test/registration_models_test.dart` — new groups for all of the above.
- **Create** `lib/models/registration_csv.dart` — Manager-only pure CSV builder (`csvEscape`, `buildSubmissionsCsv`). NOT twinned to the fan repo.
- **Create** `test/registration_csv_test.dart` — escaping (commas/quotes/newlines), header, ordering, team/paid/date columns.
- **Modify** `lib/core/constants/firebase_paths.dart` — `registrationTeamStatus` / `registrationTeamJoinCode` / `registrationTeamWaive` helpers.
- **Modify** `lib/services/firebase/registration_service.dart` — `getTeams`, `approveTeam`, `rejectTeam`, `setTeamCode`, `setTeamWaive`.
- **Modify** `lib/providers/registration_provider.dart` — `registrationTeamsProvider`.
- **Create** `lib/ui/registrations/registration_teams_page.dart` — approval queue (pending/approved/rejected sections, approve dialog with generated code + waive question, code copy/regenerate, waive toggle).
- **Modify** `lib/router/app_router.dart` — `teams` sub-route under `/registrations/:regId`.
- **Modify** `lib/ui/registrations/registration_submissions_page.dart` — AppBar actions (Team approvals nav + Export CSV), team name in each row's subtitle.

**FAN (`infinite_sports_flutter`):**
- **Modify** `pubspec.yaml` (+ commit `pubspec.lock`) — add `pin_code_fields`.
- **Modify** `lib/registration/registration_models.dart` — `Copy-Item` refresh from the Manager copy (byte-identical).
- **Modify** `test/registration_models_test.dart` — `Copy-Item` refresh + one import-line swap.
- **Modify** `lib/registration/registration_service.dart` — `getTeams`, `getTeam`, `submitCaptain`, `submitJoiner`.
- **Modify** `lib/registration/registration_form_page.dart` — `path`/`teamName`/`team` parameters, per-path visibility + submit + payment routing (full-file rewrite).
- **Modify** `lib/registration/payment_screen.dart` — required `amount` parameter (card + Venmo deep link use it).
- **Create** `lib/registration/join_code_page.dart` — 6 pin boxes (auto-uppercase), live validation against approved teams, "Joining {team}" card, Continue.
- **Modify** `lib/registration/registration_path_page.dart` — activate both team tiles; captain tile asks the team name in a dialog (full-file rewrite).
- **Modify** `lib/registration/registration_status_page.dart` — loads the team; captain sees pending/rejected notices or the join code + copy + Share; joiner sees the team name + "covered by captain"; payment button passes `amountOwed` (full-file rewrite).
- **Modify** `lib/registration/registration_entry_page.dart` — dual-fee subtitle (`$X per player · $Y per team`).

**RTDB (additive only):** `Registrations/{regId}/Teams/{teamId} = {Name, CaptainUid, Status, JoinCode?, CodeWaivesPayment, CreatedAt}`. Joiner submissions gain `TeamId`/`PaidVia` values that the L1a model already parses. No schema removal; legacy `Sign Ups/...` dual-writes continue (joiners with a waiving code go straight to the `Paid` bucket).

---

# PHASE 1 — MANAGER

## Task 1: RegTeam model + join-code + amount-owed helpers (TDD)

**Files:**
- Modify: `MANAGER lib/models/registration_models.dart`
- Modify: `MANAGER test/registration_models_test.dart`

- [ ] **Step 1: Branch check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

- [ ] **Step 2: Write the failing tests**

In `MANAGER test/registration_models_test.dart`, first add the `dart:math` import. Find (line 1):

```dart
import 'package:flutter_test/flutter_test.dart';
```

Replace with:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
```

Then find the END of the file (the `positionsFieldForSport` group followed by main's closing brace — currently lines 456-465):

```dart
  group('positionsFieldForSport', () {
    test('maps sports to Information fields', () {
      expect(positionsFieldForSport('Futsal'), 'FutsalPosition');
      expect(positionsFieldForSport('Soccer'), 'FutsalPosition');
      expect(positionsFieldForSport('Basketball'), 'BasketballPosition');
      expect(positionsFieldForSport('Flag Football'), 'FlagFootballPosition');
      expect(positionsFieldForSport('Cricket'), '');
    });
  });
}
```

Replace with (same group, then the new L1b groups, then the closing brace):

```dart
  group('positionsFieldForSport', () {
    test('maps sports to Information fields', () {
      expect(positionsFieldForSport('Futsal'), 'FutsalPosition');
      expect(positionsFieldForSport('Soccer'), 'FutsalPosition');
      expect(positionsFieldForSport('Basketball'), 'BasketballPosition');
      expect(positionsFieldForSport('Flag Football'), 'FlagFootballPosition');
      expect(positionsFieldForSport('Cricket'), '');
    });
  });

  group('RegTeam', () {
    test('round-trips through toFirebaseMap/fromNode', () {
      const team = RegTeam(
        id: 'team1',
        name: 'Red Dragons',
        captainUid: 'cap-uid',
        status: 'approved',
        joinCode: 'ABC234',
        codeWaivesPayment: true,
        createdAt: 1750000000000,
      );
      final parsed = RegTeam.fromNode('team1', team.toFirebaseMap());
      expect(parsed, isNotNull);
      expect(parsed!.id, 'team1');
      expect(parsed.name, 'Red Dragons');
      expect(parsed.captainUid, 'cap-uid');
      expect(parsed.status, 'approved');
      expect(parsed.isApproved, isTrue);
      expect(parsed.joinCode, 'ABC234');
      expect(parsed.codeWaivesPayment, isTrue);
      expect(parsed.createdAt, 1750000000000);
    });

    test('defaults: new team is pending, no code, no waive', () {
      const team = RegTeam(id: 't', name: 'X', captainUid: 'u');
      expect(team.isPending, isTrue);
      expect(team.isApproved, isFalse);
      expect(team.isRejected, isFalse);
      expect(team.joinCode, '');
      expect(team.codeWaivesPayment, isFalse);
      final map = team.toFirebaseMap();
      expect(map.containsKey('JoinCode'), isFalse); // omitted while empty
    });

    test('fromNode rejects junk', () {
      expect(RegTeam.fromNode('t', null), isNull);
      expect(RegTeam.fromNode('t', 'garbage'), isNull);
      expect(RegTeam.fromNode('t', {'CaptainUid': 'u'}), isNull); // no Name
      expect(RegTeam.fromNode('', {'Name': 'X'}), isNull); // no id
    });

    test('fromNode defaults a bad status to pending', () {
      final parsed =
          RegTeam.fromNode('t', {'Name': 'X', 'Status': 'vaporized'});
      expect(parsed!.status, 'pending');
    });

    test('copyWith overrides only the given fields', () {
      const team = RegTeam(id: 't', name: 'X', captainUid: 'u');
      final approved = team.copyWith(status: 'approved', joinCode: 'ZZZZ99');
      expect(approved.id, 't');
      expect(approved.name, 'X');
      expect(approved.status, 'approved');
      expect(approved.joinCode, 'ZZZZ99');
      expect(approved.codeWaivesPayment, isFalse);
    });
  });

  group('regTeamsFromNode', () {
    test('parses a map of teams, skipping malformed entries', () {
      final node = {
        'a': {'Name': 'Team A', 'CaptainUid': 'u1'},
        'bad': 'garbage',
        'b': {'Name': 'Team B', 'CaptainUid': 'u2', 'Status': 'approved'},
      };
      final teams = regTeamsFromNode(node);
      expect(teams.keys.toSet(), {'a', 'b'});
      expect(teams['a']!.isPending, isTrue);
      expect(teams['b']!.isApproved, isTrue);
    });

    test('null / junk gives an empty map', () {
      expect(regTeamsFromNode(null), isEmpty);
      expect(regTeamsFromNode('x'), isEmpty);
      expect(regTeamsFromNode([1, 2]), isEmpty);
    });
  });

  group('cleanTeamName', () {
    test('collapses whitespace and capitalizes words', () {
      expect(cleanTeamName('  the   boys '), 'The Boys');
      expect(cleanTeamName('LA galaxy'), 'LA Galaxy'); // capitals preserved
      expect(cleanTeamName('   '), '');
    });
  });

  group('join codes', () {
    test('alphabet is confusable-free', () {
      expect(kJoinCodeAlphabet.contains('I'), isFalse);
      expect(kJoinCodeAlphabet.contains('O'), isFalse);
      expect(kJoinCodeAlphabet.contains('0'), isFalse);
      expect(kJoinCodeAlphabet.contains('1'), isFalse);
      expect(kJoinCodeAlphabet.length, 32);
    });

    test('generateJoinCode makes 6-char codes from the alphabet', () {
      final rand = Random(42);
      for (var i = 0; i < 100; i++) {
        final code = generateJoinCode(rand);
        expect(code.length, 6);
        for (final ch in code.split('')) {
          expect(kJoinCodeAlphabet.contains(ch), isTrue,
              reason: '$ch not in alphabet');
        }
      }
    });

    test('generateJoinCode honors length', () {
      expect(generateJoinCode(Random(1), length: 8).length, 8);
    });

    test('generateUniqueJoinCode skips taken codes', () {
      // Same seed => the first internal attempt IS `first`; it must be
      // skipped and a different code returned.
      final first = generateJoinCode(Random(7));
      final unique = generateUniqueJoinCode(Random(7), {first});
      expect(unique, isNot(first));
      expect(unique.length, 6);
    });

    test('normalizeJoinCode uppercases and trims', () {
      expect(normalizeJoinCode('  abC234 '), 'ABC234');
    });

    test('validateJoinCode enforces length, charset, uniqueness', () {
      expect(validateJoinCode('ABC234'), isNull);
      expect(validateJoinCode('abc234'), isNull); // normalized first
      expect(validateJoinCode('AB'), isNotNull); // too short
      expect(validateJoinCode('ABCDEFGHJKLMN'), isNotNull); // 13 chars
      expect(validateJoinCode('ABC 23'), isNotNull); // space
      expect(validateJoinCode('ABC234', taken: {'abc234'}), isNotNull);
      expect(validateJoinCode('ABC234', taken: {'XYZ789'}), isNull);
    });
  });

  group('matchJoinCode', () {
    const approved = RegTeam(
        id: 'a',
        name: 'Approved FC',
        captainUid: 'u1',
        status: 'approved',
        joinCode: 'GOOD22');
    const pending = RegTeam(
        id: 'p',
        name: 'Pending FC',
        captainUid: 'u2',
        status: 'pending',
        joinCode: 'WAIT33');
    final teams = {'a': approved, 'p': pending};

    test('finds an approved team case-insensitively', () {
      final m = matchJoinCode(teams, ' good22 ');
      expect(m.status, 'ok');
      expect(m.team!.id, 'a');
    });

    test('flags a non-approved team as notApproved', () {
      final m = matchJoinCode(teams, 'WAIT33');
      expect(m.status, 'notApproved');
      expect(m.team!.id, 'p');
    });

    test('unknown or empty input is notFound', () {
      expect(matchJoinCode(teams, 'NOPE99').status, 'notFound');
      expect(matchJoinCode(teams, '').status, 'notFound');
      expect(matchJoinCode(const {}, 'GOOD22').status, 'notFound');
    });

    test('an approved team wins over a pending one holding the same code', () {
      const shadow = RegTeam(
          id: 's',
          name: 'Shadow',
          captainUid: 'u3',
          status: 'pending',
          joinCode: 'GOOD22');
      final m = matchJoinCode({'s': shadow, 'a': approved}, 'GOOD22');
      expect(m.status, 'ok');
      expect(m.team!.id, 'a');
    });
  });

  group('hasDuplicateTeamName', () {
    final teams = {
      'a': const RegTeam(id: 'a', name: 'Red Dragons', captainUid: 'u1'),
      'b': const RegTeam(id: 'b', name: 'red dragons ', captainUid: 'u2'),
      'c': const RegTeam(id: 'c', name: 'Blue Sharks', captainUid: 'u3'),
    };

    test('true when another team shares the name (case/space-insensitive)',
        () {
      expect(hasDuplicateTeamName(teams, 'a', 'Red Dragons'), isTrue);
    });

    test('false when the name is unique (own entry ignored)', () {
      expect(hasDuplicateTeamName(teams, 'c', 'Blue Sharks'), isFalse);
    });
  });

  group('amountOwed', () {
    const both = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 20,
        teamFee: 300,
        paymentMode: 'both');
    const teamFee = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 20,
        teamFee: 300,
        paymentMode: 'teamFee');

    RegSubmission sub(String path, {bool paid = false}) =>
        RegSubmission(path: path, answers: const {}, paid: paid);

    test('captain owes the TEAM fee, not the player fee', () {
      expect(amountOwed(config: both, submission: sub('captain')), 300);
      expect(amountOwed(config: teamFee, submission: sub('captain')), 300);
    });

    test('individual owes the player fee under perPlayer/both, 0 under teamFee',
        () {
      expect(amountOwed(config: both, submission: sub('individual')), 20);
      expect(amountOwed(config: teamFee, submission: sub('individual')), 0);
    });

    test('joiner owes the player fee unless the code waives it', () {
      expect(amountOwed(config: teamFee, submission: sub('joiner')), 20);
      expect(
          amountOwed(
              config: teamFee,
              submission: sub('joiner'),
              codeWaivesPayment: true),
          0);
    });

    test('anything already paid owes 0', () {
      expect(
          amountOwed(config: both, submission: sub('captain', paid: true)), 0);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter test test/registration_models_test.dart
```
Expected: FAIL to compile — `RegTeam`, `regTeamsFromNode`, `cleanTeamName`, `kJoinCodeAlphabet`, `generateJoinCode`, `generateUniqueJoinCode`, `normalizeJoinCode`, `validateJoinCode`, `matchJoinCode`, `hasDuplicateTeamName`, `amountOwed` are undefined.

- [ ] **Step 4: Implement in the models file**

Three edits to `MANAGER lib/models/registration_models.dart`.

**Edit A — header comment (line 1).** Find:

```dart
// Pure registration-engine models + helpers (Leagues epic L1, phase L1a).
```

Replace with:

```dart
// Pure registration-engine models + helpers (Leagues epic L1, phases L1a-L1b).
```

**Edit B — add the dart:math import (pure Dart, allowed).** Find (lines 6-11):

```dart
//   Manager: lib/models/registration_models.dart
//   Fan:     lib/registration/registration_models.dart

// ---------------------------------------------------------------------------
// Question model
// ---------------------------------------------------------------------------
```

Replace with:

```dart
//   Manager: lib/models/registration_models.dart
//   Fan:     lib/registration/registration_models.dart

import 'dart:math';

// ---------------------------------------------------------------------------
// Question model
// ---------------------------------------------------------------------------
```

**Edit C — append the L1b section at the very END of the file** (after the `kDefaultRegQuestions` list's closing `];`, currently the last line):

```dart

// ---------------------------------------------------------------------------
// Teams (Registrations/{regId}/Teams/{teamId}) — L1b
// ---------------------------------------------------------------------------

/// Valid RegTeam.status values.
const List<String> kRegTeamStatuses = ['pending', 'approved', 'rejected'];

class RegTeam {
  final String id;
  final String name;
  final String captainUid;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String joinCode; // '' until approved
  final bool codeWaivesPayment; // joiners with this code skip payment
  final int createdAt; // millisecondsSinceEpoch

  const RegTeam({
    required this.id,
    required this.name,
    required this.captainUid,
    this.status = 'pending',
    this.joinCode = '',
    this.codeWaivesPayment = false,
    this.createdAt = 0,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  Map<String, dynamic> toFirebaseMap() => {
        'Name': name,
        'CaptainUid': captainUid,
        'Status': status,
        if (joinCode.isNotEmpty) 'JoinCode': joinCode,
        'CodeWaivesPayment': codeWaivesPayment,
        'CreatedAt': createdAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegTeam? fromNode(String id, Object? raw) {
    if (raw is! Map) return null;
    final name = raw['Name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final rawStatus = raw['Status']?.toString() ?? 'pending';
    return RegTeam(
      id: id,
      name: name,
      captainUid: raw['CaptainUid']?.toString() ?? '',
      status: kRegTeamStatuses.contains(rawStatus) ? rawStatus : 'pending',
      joinCode: raw['JoinCode']?.toString() ?? '',
      codeWaivesPayment: raw['CodeWaivesPayment'] == true,
      createdAt: int.tryParse(raw['CreatedAt']?.toString() ?? '') ?? 0,
    );
  }

  RegTeam copyWith({
    String? name,
    String? captainUid,
    String? status,
    String? joinCode,
    bool? codeWaivesPayment,
    int? createdAt,
  }) =>
      RegTeam(
        id: id,
        name: name ?? this.name,
        captainUid: captainUid ?? this.captainUid,
        status: status ?? this.status,
        joinCode: joinCode ?? this.joinCode,
        codeWaivesPayment: codeWaivesPayment ?? this.codeWaivesPayment,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// Parses a Registrations/{regId}/Teams node into {teamId: team}, skipping
/// malformed entries. {} for null/junk.
Map<String, RegTeam> regTeamsFromNode(Object? raw) {
  final out = <String, RegTeam>{};
  if (raw is Map) {
    raw.forEach((id, value) {
      final team = RegTeam.fromNode(id.toString(), value);
      if (team != null) out[id.toString()] = team;
    });
  }
  return out;
}

/// Team-name hygiene: trim/collapse whitespace + capitalize each word
/// ("  the   boys " -> "The Boys"). Existing capitals are preserved
/// ("LA galaxy" -> "LA Galaxy").
String cleanTeamName(String input) =>
    capitalizeWords(collapseTrailingSpaces(input));

// ---------------------------------------------------------------------------
// Join codes
// ---------------------------------------------------------------------------

/// Confusable-free code alphabet (no I/O/0/1) — the same one the tournament
/// join-code dialog uses (Manager lib/ui/tournaments/manage_teams_page.dart).
const String kJoinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// The uppercased/trimmed form every code is stored and compared in.
String normalizeJoinCode(String input) => input.trim().toUpperCase();

/// A random [length]-char code. [random] is injected so tests can seed it;
/// UI callers pass Random.secure().
String generateJoinCode(Random random, {int length = 6}) => List.generate(
        length, (_) => kJoinCodeAlphabet[random.nextInt(kJoinCodeAlphabet.length)])
    .join();

/// A random code not present in [taken] (compared normalized). Retries up to
/// 100 times, then falls back to a longer code so the function stays total —
/// collisions over the 32^6 space are practically impossible.
String generateUniqueJoinCode(Random random, Set<String> taken,
    {int length = 6}) {
  final normalizedTaken = taken.map(normalizeJoinCode).toSet();
  for (var i = 0; i < 100; i++) {
    final code = generateJoinCode(random, length: length);
    if (!normalizedTaken.contains(code)) return code;
  }
  return generateJoinCode(random, length: length + 2);
}

/// null when [code] is usable, else the problem to show. Mirrors the
/// tournament dialog's 4-12 rule; [taken] holds every OTHER team's code in
/// the same registration (any casing) for the per-registration uniqueness
/// check.
String? validateJoinCode(String code, {Set<String> taken = const {}}) {
  final c = normalizeJoinCode(code);
  if (c.length < 4 || c.length > 12) return 'Code must be 4-12 characters.';
  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(c)) return 'Letters and numbers only.';
  if (taken.map(normalizeJoinCode).contains(c)) {
    return 'That code is already used by another team.';
  }
  return null;
}

/// Outcome of matching an entered code against a registration's teams.
/// status: 'ok' (approved team found — [team] set), 'notApproved' (the code
/// belongs to a pending/rejected team — [team] set), 'notFound'.
class JoinCodeMatch {
  final String status;
  final RegTeam? team;
  const JoinCodeMatch(this.status, [this.team]);
}

/// Finds the team whose JoinCode matches [input] (compared normalized).
/// An approved team always wins over a non-approved one with the same code.
JoinCodeMatch matchJoinCode(Map<String, RegTeam> teams, String input) {
  final code = normalizeJoinCode(input);
  if (code.isEmpty) return const JoinCodeMatch('notFound');
  RegTeam? nonApproved;
  for (final team in teams.values) {
    if (team.joinCode.isEmpty) continue;
    if (normalizeJoinCode(team.joinCode) != code) continue;
    if (team.isApproved) return JoinCodeMatch('ok', team);
    nonApproved ??= team;
  }
  return nonApproved != null
      ? JoinCodeMatch('notApproved', nonApproved)
      : const JoinCodeMatch('notFound');
}

/// True when another team in [teams] (any status, any id but [teamId])
/// carries [name] modulo case/outer whitespace — the approval dialog warns
/// on duplicates (spec section 7).
bool hasDuplicateTeamName(
    Map<String, RegTeam> teams, String teamId, String name) {
  final needle = name.trim().toLowerCase();
  return teams.entries
      .any((e) => e.key != teamId && e.value.name.trim().toLowerCase() == needle);
}

// ---------------------------------------------------------------------------
// Amount owed
// ---------------------------------------------------------------------------

/// The dollar amount a submission owes right now — 0 whenever [paymentOwed]
/// says nothing is owed. Captains owe [RegistrationConfig.teamFee]; everyone
/// else owes [RegistrationConfig.fee]. The payment screen shows THIS number
/// (a captain must never be shown the per-player fee).
num amountOwed({
  required RegistrationConfig config,
  required RegSubmission submission,
  bool codeWaivesPayment = false,
}) {
  if (!paymentOwed(
      config: config,
      submission: submission,
      codeWaivesPayment: codeWaivesPayment)) {
    return 0;
  }
  return submission.path == 'captain' ? config.teamFee : config.fee;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
flutter test test/registration_models_test.dart
```
Expected: All tests pass (the pre-existing groups plus the new RegTeam / regTeamsFromNode / cleanTeamName / join codes / matchJoinCode / hasDuplicateTeamName / amountOwed groups).

- [ ] **Step 6: Commit**

```powershell
git add lib/models/registration_models.dart test/registration_models_test.dart
git commit -m "feat(registration): RegTeam model, join-code helpers, amountOwed (L1b)"
```

---

## Task 2: Manager pure CSV builder (TDD)

**Files:**
- Create: `MANAGER lib/models/registration_csv.dart`
- Create: `MANAGER test/registration_csv_test.dart`

This file is Manager-only and deliberately NOT part of the twin-synced model file: the fan app never exports CSVs, and keeping export logic out of the twin keeps the byte-identity contract small. It is still pure (no Flutter/Firebase imports) so it unit-tests directly.

- [ ] **Step 1: Write the failing tests**

Create `MANAGER test/registration_csv_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/models/registration_csv.dart';
import 'package:infinite_app_manager/models/registration_models.dart';

void main() {
  group('csvEscape', () {
    test('passes plain values through untouched', () {
      expect(csvEscape('John Doe'), 'John Doe');
      expect(csvEscape(''), '');
    });

    test('quotes values containing commas', () {
      expect(csvEscape('Doe, John'), '"Doe, John"');
    });

    test('doubles embedded quotes and wraps', () {
      expect(csvEscape('The "Best" Team'), '"The ""Best"" Team"');
    });

    test('quotes values containing newlines', () {
      expect(csvEscape('line1\nline2'), '"line1\nline2"');
      expect(csvEscape('line1\r\nline2'), '"line1\r\nline2"');
    });
  });

  group('buildSubmissionsCsv', () {
    const questions = [
      RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name'),
      RegQuestion(key: 'phone', type: 'phone', label: 'Phone'),
      RegQuestion(
          key: 'positions',
          type: 'multiChoice',
          label: 'Positions',
          options: ['GK', 'DEF']),
      RegQuestion(key: 'comment', type: 'paragraph', label: 'Comment'),
    ];

    test('is header-only when there are no submissions', () {
      final csv = buildSubmissionsCsv(
          questions: questions, submissions: const {}, teams: const {});
      expect(csv,
          'Name,Path,Team,Paid,Paid Via,Submitted,First Name,Phone,Positions,Comment');
    });

    test('renders rows sorted by name with team/paid/date + escaped answers',
        () {
      final submissions = {
        'uid-b': RegSubmission(
          path: 'joiner',
          answers: const {
            'firstName': 'Zoe',
            'phone': '4086939436',
            'positions': ['GK', 'DEF'],
            'comment': 'Hi, "coach"\nsee you',
          },
          teamId: 'team1',
          paid: true,
          paidVia: 'team code',
          displayName: 'Zoe A',
          submittedAt: DateTime(2026, 7, 1).millisecondsSinceEpoch,
        ),
        'uid-a': const RegSubmission(
          path: 'individual',
          answers: {'firstName': 'Amy'},
          displayName: 'Amy B',
        ),
      };
      final teams = {
        'team1': const RegTeam(
            id: 'team1', name: 'The Comma, Kids', captainUid: 'cap'),
      };
      final csv = buildSubmissionsCsv(
          questions: questions, submissions: submissions, teams: teams);
      final lines = csv.split('\r\n');
      expect(lines, hasLength(3));
      // Amy sorts first; unanswered questions are empty cells.
      expect(lines[1], 'Amy B,individual,,No,,,Amy,,,');
      // Zoe: team name escaped (comma), phone formatted, list joined with
      // '; ', comment quoted (comma + quote + newline).
      expect(
          lines[2],
          'Zoe A,joiner,"The Comma, Kids",Yes,team code,07/01/2026,Zoe,(408) 693-9436,GK; DEF,"Hi, ""coach""\nsee you"');
    });

    test('falls back to the uid when displayName is empty', () {
      final csv = buildSubmissionsCsv(
        questions: const [],
        submissions: {
          'uid-1': const RegSubmission(path: 'individual', answers: {}),
        },
        teams: const {},
      );
      expect(csv.split('\r\n')[1], 'uid-1,individual,,No,,');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
flutter test test/registration_csv_test.dart
```
Expected: FAIL to compile — `package:infinite_app_manager/models/registration_csv.dart` does not exist.

- [ ] **Step 3: Implement the CSV builder**

Create `MANAGER lib/models/registration_csv.dart`:

```dart
// Pure CSV export for registration submissions (L1b). Manager-only — the
// fan app never exports, so this file is NOT part of the twin-synced model
// file. No Flutter/Firebase imports — unit-tested directly.

import 'package:infinite_app_manager/models/registration_models.dart';

/// RFC 4180-style escaping: wrap in quotes when the value contains a comma,
/// a quote, or a newline; double any quotes inside.
String csvEscape(String value) {
  final mustQuote = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!mustQuote) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// MM/DD/YYYY, or '' when the timestamp is missing/zero.
String _csvDate(int millis) {
  if (millis <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
}

/// One answer cell: lists join with '; ', booleans become Yes/No, phones are
/// display-formatted, everything else stringifies. Missing answers are ''.
String _answerText(RegQuestion q, Object? value) {
  if (value == null) return '';
  if (value is List) return value.map((v) => v.toString()).join('; ');
  if (value is bool) return value ? 'Yes' : 'No';
  if (q.type == 'phone') return formatPhone(value.toString());
  return value.toString();
}

/// Builds the submissions CSV: the fixed columns (Name, Path, Team, Paid,
/// Paid Via, Submitted) then one column per form question in form order.
/// Rows are sorted by display name (case-insensitive; uid fallback) so
/// exports are stable. CRLF line endings per RFC 4180. Answers whose keys
/// are no longer on the form are not exported.
String buildSubmissionsCsv({
  required List<RegQuestion> questions,
  required Map<String, RegSubmission> submissions,
  required Map<String, RegTeam> teams,
}) {
  final header = [
    'Name',
    'Path',
    'Team',
    'Paid',
    'Paid Via',
    'Submitted',
    ...questions.map((q) => q.label),
  ];
  String nameOf(String uid, RegSubmission sub) =>
      sub.displayName.isNotEmpty ? sub.displayName : uid;
  final entries = submissions.entries.toList()
    ..sort((a, b) => nameOf(a.key, a.value)
        .toLowerCase()
        .compareTo(nameOf(b.key, b.value).toLowerCase()));
  final lines = <String>[header.map(csvEscape).join(',')];
  for (final entry in entries) {
    final sub = entry.value;
    final row = [
      nameOf(entry.key, sub),
      sub.path,
      teams[sub.teamId]?.name ?? '',
      sub.paid ? 'Yes' : 'No',
      sub.paidVia,
      _csvDate(sub.submittedAt),
      ...questions.map((q) => _answerText(q, sub.answers[q.key])),
    ];
    lines.add(row.map(csvEscape).join(','));
  }
  return lines.join('\r\n');
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test/registration_csv_test.dart
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/models/registration_csv.dart test/registration_csv_test.dart
git commit -m "feat(registration): pure CSV builder for submissions export"
```

---

## Task 3: Manager RTDB paths + service team methods + provider

**Files:**
- Modify: `MANAGER lib/core/constants/firebase_paths.dart`
- Modify: `MANAGER lib/services/firebase/registration_service.dart`
- Modify: `MANAGER lib/providers/registration_provider.dart`

- [ ] **Step 1: Add the team-field path helpers**

In `MANAGER lib/core/constants/firebase_paths.dart`, find (lines 177-182 — `registrationTeams`/`registrationTeam` already exist from L1a):

```dart
  static String registrationTeams(String regId) =>
      '$registrations/$regId/Teams';
  static String registrationTeam(String regId, String teamId) =>
      '$registrations/$regId/Teams/$teamId';
  static String formTemplate(String id) => '$formTemplates/$id';
  static String formTemplateName(String id) => '$formTemplates/$id/Name';
```

Replace with:

```dart
  static String registrationTeams(String regId) =>
      '$registrations/$regId/Teams';
  static String registrationTeam(String regId, String teamId) =>
      '$registrations/$regId/Teams/$teamId';
  static String registrationTeamStatus(String regId, String teamId) =>
      '$registrations/$regId/Teams/$teamId/Status';
  static String registrationTeamJoinCode(String regId, String teamId) =>
      '$registrations/$regId/Teams/$teamId/JoinCode';
  static String registrationTeamWaive(String regId, String teamId) =>
      '$registrations/$regId/Teams/$teamId/CodeWaivesPayment';
  static String formTemplate(String id) => '$formTemplates/$id';
  static String formTemplateName(String id) => '$formTemplates/$id/Name';
```

- [ ] **Step 2: Add the service methods**

In `MANAGER lib/services/firebase/registration_service.dart`, find the END of the class (the `deleteSubmission` method's tail, lines 123-133):

```dart
  Future<void> deleteSubmission(String regId, String uid) async {
    final config = await getConfig(regId);
    await ref(FirebasePaths.registrationSubmission(regId, uid)).remove();
    if (config == null) return;
    final target = legacySignUpTarget(config);
    await ref('${FirebasePaths.signUpNotPaid(target.league, target.season)}/$uid')
        .remove();
    await ref('${FirebasePaths.signUpPaid(target.league, target.season)}/$uid')
        .remove();
  }
}
```

Replace with:

```dart
  Future<void> deleteSubmission(String regId, String uid) async {
    final config = await getConfig(regId);
    await ref(FirebasePaths.registrationSubmission(regId, uid)).remove();
    if (config == null) return;
    final target = legacySignUpTarget(config);
    await ref('${FirebasePaths.signUpNotPaid(target.league, target.season)}/$uid')
        .remove();
    await ref('${FirebasePaths.signUpPaid(target.league, target.season)}/$uid')
        .remove();
  }

  // -------- Teams (L1b) --------

  /// {teamId: team} for a registration, malformed entries skipped.
  Future<Map<String, RegTeam>> getTeams(String regId) async {
    final map = await getMap(FirebasePaths.registrationTeams(regId));
    return regTeamsFromNode(map);
  }

  /// Approves a pending (or rejected) team: Status + JoinCode +
  /// CodeWaivesPayment in one update. The code is stored normalized
  /// (uppercased/trimmed); the CALLER (approve dialog) is responsible for
  /// the per-registration uniqueness check. Approving does NOT write any
  /// roster — teams stay under Registrations/{regId}/Teams until L2.
  Future<void> approveTeam(String regId, String teamId, String joinCode,
      bool codeWaivesPayment) async {
    await ref(FirebasePaths.registrationTeam(regId, teamId)).update({
      'Status': 'approved',
      'JoinCode': normalizeJoinCode(joinCode),
      'CodeWaivesPayment': codeWaivesPayment,
    });
  }

  Future<void> rejectTeam(String regId, String teamId) async {
    await ref(FirebasePaths.registrationTeamStatus(regId, teamId))
        .set('rejected');
  }

  /// Replaces an approved team's code (manual edit or regenerate). Stored
  /// normalized; caller validates uniqueness first.
  Future<void> setTeamCode(String regId, String teamId, String joinCode) async {
    await ref(FirebasePaths.registrationTeamJoinCode(regId, teamId))
        .set(normalizeJoinCode(joinCode));
  }

  Future<void> setTeamWaive(String regId, String teamId, bool waive) async {
    await ref(FirebasePaths.registrationTeamWaive(regId, teamId)).set(waive);
  }
}
```

- [ ] **Step 3: Add the teams provider**

In `MANAGER lib/providers/registration_provider.dart`, find (lines 24-27):

```dart
final registrationSubmissionsProvider =
    FutureProvider.family<Map<String, RegSubmission>, String>((ref, regId) {
  return ref.watch(registrationServiceProvider).getSubmissions(regId);
});
```

Replace with:

```dart
final registrationSubmissionsProvider =
    FutureProvider.family<Map<String, RegSubmission>, String>((ref, regId) {
  return ref.watch(registrationServiceProvider).getSubmissions(regId);
});

/// {teamId: team} for one registration (L1b team approvals).
final registrationTeamsProvider =
    FutureProvider.family<Map<String, RegTeam>, String>((ref, regId) {
  return ref.watch(registrationServiceProvider).getTeams(regId);
});
```

- [ ] **Step 4: Analyze the touched files**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/core/constants/firebase_paths.dart lib/services/firebase/registration_service.dart lib/providers/registration_provider.dart
```
Expected: No issues found.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/constants/firebase_paths.dart lib/services/firebase/registration_service.dart lib/providers/registration_provider.dart
git commit -m "feat(registration): team paths, service approve/reject/code methods, teams provider"
```

---

## Task 4: Manager team approvals page + route + submissions-page link

**Files:**
- Create: `MANAGER lib/ui/registrations/registration_teams_page.dart`
- Modify: `MANAGER lib/router/app_router.dart`
- Modify: `MANAGER lib/ui/registrations/registration_submissions_page.dart`

Placement decision: the Teams page is a PEER page at `/registrations/:regId/teams`, reached from an AppBar action on the submissions page. The submissions page is a plain single-list Scaffold and the registrations route tree already nests this way (`templates/:templateId`), so a peer route is the smallest change that fits the existing structure — no TabBar conversion.

- [ ] **Step 1: Create the teams page**

Create `MANAGER lib/ui/registrations/registration_teams_page.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:intl/intl.dart';

/// Team approvals for one registration (spec section 4). Pending queue
/// (Approve opens the code + waive dialog; Reject confirms), approved teams
/// (code display + copy + regenerate + waive toggle), rejected teams
/// (re-approvable). Approving NEVER writes rosters — teams stay under
/// Registrations/{regId}/Teams until L2 materializes them.
class RegistrationTeamsPage extends ConsumerStatefulWidget {
  final String regId;
  const RegistrationTeamsPage({super.key, required this.regId});

  @override
  ConsumerState<RegistrationTeamsPage> createState() =>
      _RegistrationTeamsPageState();
}

class _RegistrationTeamsPageState
    extends ConsumerState<RegistrationTeamsPage> {
  void _refresh() => ref.invalidate(registrationTeamsProvider(widget.regId));

  /// Every OTHER team's code, normalized — for uniqueness checks.
  Set<String> _otherCodes(Map<String, RegTeam> teams, String teamId) => {
        for (final e in teams.entries)
          if (e.key != teamId && e.value.joinCode.isNotEmpty)
            normalizeJoinCode(e.value.joinCode),
      };

  Future<void> _approve(RegTeam team, Map<String, RegTeam> teams) async {
    final config =
        ref.read(registrationConfigProvider(widget.regId)).valueOrNull;
    final result = await showDialog<({String code, bool waive})>(
      context: context,
      builder: (ctx) => _ApproveTeamDialog(
        team: team,
        taken: _otherCodes(teams, team.id),
        duplicateName: hasDuplicateTeamName(teams, team.id, team.name),
        initialWaive: config?.paymentMode == 'teamFee',
      ),
    );
    if (result == null) return;
    try {
      await ref
          .read(registrationServiceProvider)
          .approveTeam(widget.regId, team.id, result.code, result.waive);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${team.name} approved — join code ${result.code}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to approve: $e')));
      }
    }
  }

  Future<void> _reject(RegTeam team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject team?'),
        content: Text(
            'Reject "${team.name}"? The captain sees this on their status screen. Their own registration stays in Submissions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(registrationServiceProvider)
          .rejectTeam(widget.regId, team.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to reject: $e')));
      }
    }
  }

  Future<void> _editCode(RegTeam team, Map<String, RegTeam> teams) async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => _TeamCodeDialog(
        teamName: team.name,
        initialCode: team.joinCode,
        taken: _otherCodes(teams, team.id),
      ),
    );
    if (code == null) return;
    try {
      await ref
          .read(registrationServiceProvider)
          .setTeamCode(widget.regId, team.id, code);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Join code set to $code.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save code: $e')));
      }
    }
  }

  Future<void> _setWaive(RegTeam team, bool waive) async {
    try {
      await ref
          .read(registrationServiceProvider)
          .setTeamWaive(widget.regId, team.id, waive);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Join code copied — text it to the captain.')));
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(registrationTeamsProvider(widget.regId));
    final subsAsync =
        ref.watch(registrationSubmissionsProvider(widget.regId));
    final title = ref
            .watch(registrationConfigProvider(widget.regId))
            .valueOrNull
            ?.label ??
        widget.regId;

    return Scaffold(
      appBar: AppBar(title: Text('Teams — $title')),
      body: teamsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (teams) {
          if (teams.isEmpty) {
            return const Center(
                child:
                    Text('No teams yet — captains register on the fan app.'));
          }
          final subs = subsAsync.valueOrNull ?? const {};
          String captainName(RegTeam t) {
            final name = subs[t.captainUid]?.displayName ?? '';
            return name.isNotEmpty ? name : t.captainUid;
          }

          final pending = teams.values.where((t) => t.isPending).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final approved = teams.values.where((t) => t.isApproved).toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          final rejected = teams.values.where((t) => t.isRejected).toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (pending.isNotEmpty) ...[
                _header('Pending approval (${pending.length})'),
                for (final t in pending)
                  Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.hourglass_top,
                          color: Colors.orange),
                      title: Text(t.name),
                      subtitle: Text([
                        'Captain: ${captainName(t)}',
                        if (t.createdAt > 0)
                          DateFormat('MM/dd/yyyy').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  t.createdAt)),
                      ].join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _reject(t),
                            child: const Text('Reject',
                                style: TextStyle(color: Colors.red)),
                          ),
                          FilledButton(
                            onPressed: () => _approve(t, teams),
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (approved.isNotEmpty) ...[
                _header('Approved (${approved.length})'),
                for (final t in approved)
                  Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Column(
                      children: [
                        ListTile(
                          leading:
                              const Icon(Icons.verified, color: Colors.green),
                          title: Text(t.name),
                          subtitle: Text('Captain: ${captainName(t)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.joinCode,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy code',
                                onPressed: () => _copyCode(t.joinCode),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Edit / regenerate code',
                                onPressed: () => _editCode(t, teams),
                              ),
                            ],
                          ),
                        ),
                        ListTile(
                          dense: true,
                          title: const Text(
                              'Code skips payment (captain covers the team)'),
                          trailing: Switch(
                            value: t.codeWaivesPayment,
                            onChanged: (v) => _setWaive(t, v),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (rejected.isNotEmpty) ...[
                _header('Rejected (${rejected.length})'),
                for (final t in rejected)
                  Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.block, color: Colors.red),
                      title: Text(t.name),
                      subtitle: Text('Captain: ${captainName(t)}'),
                      trailing: TextButton(
                        onPressed: () => _approve(t, teams),
                        child: const Text('Approve instead'),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Approve dialog: a pre-generated, editable join code (Generate re-rolls;
/// uniqueness enforced against every other team in the registration) plus
/// the owner's question — do players joining with this code skip payment
/// (captain covers) or pay individually? Defaults to "skip" when the
/// registration's paymentMode is 'teamFee', otherwise "pay individually".
class _ApproveTeamDialog extends StatefulWidget {
  final RegTeam team;
  final Set<String> taken;
  final bool duplicateName;
  final bool initialWaive;

  const _ApproveTeamDialog({
    required this.team,
    required this.taken,
    required this.duplicateName,
    required this.initialWaive,
  });

  @override
  State<_ApproveTeamDialog> createState() => _ApproveTeamDialogState();
}

class _ApproveTeamDialogState extends State<_ApproveTeamDialog> {
  late final TextEditingController _controller;
  late bool _waive;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: generateUniqueJoinCode(Random.secure(), widget.taken));
    _waive = widget.initialWaive;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(
        ClipboardData(text: normalizeJoinCode(_controller.text)));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied.')));
  }

  void _submit() {
    final code = normalizeJoinCode(_controller.text);
    final problem = validateJoinCode(code, taken: widget.taken);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, (code: code, waive: _waive));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Approve ${widget.team.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.duplicateName)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Warning: another team in this registration has the same name.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                TextInputFormatter.withFunction((oldV, newV) =>
                    newV.copyWith(text: newV.text.toUpperCase())),
              ],
              maxLength: 12,
              decoration: InputDecoration(
                labelText: 'Join code',
                helperText:
                    'Keep it to 6 characters — the fan app entry has 6 boxes.',
                errorText: _error,
                suffixIcon: TextButton(
                  onPressed: () {
                    _controller.text =
                        generateUniqueJoinCode(Random.secure(), widget.taken);
                    setState(() => _error = null);
                  },
                  child: const Text('Generate'),
                ),
              ),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3),
            ),
            const SizedBox(height: 12),
            const Text('Players joining with this code:'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Skip payment (captain covers)'),
                  selected: _waive,
                  onSelected: (_) => setState(() => _waive = true),
                ),
                ChoiceChip(
                  label: const Text('Pay individually'),
                  selected: !_waive,
                  onSelected: (_) => setState(() => _waive = false),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _copy, child: const Text('Copy')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Approve')),
      ],
    );
  }
}

/// Edit/regenerate the code of an already-approved team. Same rules as the
/// approve dialog (4-12 chars, unique in this registration), no waive
/// question (the list's toggle handles that).
class _TeamCodeDialog extends StatefulWidget {
  final String teamName;
  final String initialCode;
  final Set<String> taken;

  const _TeamCodeDialog({
    required this.teamName,
    required this.initialCode,
    required this.taken,
  });

  @override
  State<_TeamCodeDialog> createState() => _TeamCodeDialogState();
}

class _TeamCodeDialogState extends State<_TeamCodeDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: normalizeJoinCode(widget.initialCode));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final code = normalizeJoinCode(_controller.text);
    final problem = validateJoinCode(code, taken: widget.taken);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.teamName} — Join Code'),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
          TextInputFormatter.withFunction((oldV, newV) =>
              newV.copyWith(text: newV.text.toUpperCase())),
        ],
        maxLength: 12,
        decoration: InputDecoration(
          labelText: 'Join code',
          helperText:
              'Keep it to 6 characters — the fan app entry has 6 boxes.',
          errorText: _error,
          suffixIcon: TextButton(
            onPressed: () {
              _controller.text =
                  generateUniqueJoinCode(Random.secure(), widget.taken);
              setState(() => _error = null);
            },
            child: const Text('Generate'),
          ),
        ),
        style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(
                ClipboardData(text: normalizeJoinCode(_controller.text)));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied.')));
          },
          child: const Text('Copy'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
```

- [ ] **Step 2: Register the route**

In `MANAGER lib/router/app_router.dart`, two edits.

**Edit A — import.** Find (line 17):

```dart
import 'package:infinite_app_manager/ui/registrations/registration_submissions_page.dart';
```

Replace with:

```dart
import 'package:infinite_app_manager/ui/registrations/registration_submissions_page.dart';
import 'package:infinite_app_manager/ui/registrations/registration_teams_page.dart';
```

**Edit B — the `teams` sub-route.** Find (lines 149-155, inside the `/registrations` route tree):

```dart
              GoRoute(
                path: ':regId',
                builder: (context, state) {
                  final regId = state.pathParameters['regId']!;
                  return RegistrationSubmissionsPage(regId: regId);
                },
              ),
```

Replace with:

```dart
              GoRoute(
                path: ':regId',
                builder: (context, state) {
                  final regId = state.pathParameters['regId']!;
                  return RegistrationSubmissionsPage(regId: regId);
                },
                routes: [
                  GoRoute(
                    path: 'teams',
                    builder: (context, state) {
                      final regId = state.pathParameters['regId']!;
                      return RegistrationTeamsPage(regId: regId);
                    },
                  ),
                ],
              ),
```

(The `templates` route is declared before `:regId` in the existing tree, so `'templates'` still wins over the parameter — unchanged.)

- [ ] **Step 3: Link from the submissions page + show team names on rows**

In `MANAGER lib/ui/registrations/registration_submissions_page.dart`, three edits.

**Edit A — import go_router.** Find (lines 1-5):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:intl/intl.dart';
```

Replace with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:intl/intl.dart';
```

**Edit B — AppBar action + teams watch.** Find (lines 116-124):

```dart
  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(registrationConfigProvider(widget.regId));
    final subsAsync =
        ref.watch(registrationSubmissionsProvider(widget.regId));
    final formAsync = ref.watch(registrationFormProvider(widget.regId));
    final title = configAsync.valueOrNull?.label ?? widget.regId;

    return Scaffold(
      appBar: AppBar(title: Text('Submissions — $title')),
```

Replace with:

```dart
  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(registrationConfigProvider(widget.regId));
    final subsAsync =
        ref.watch(registrationSubmissionsProvider(widget.regId));
    final formAsync = ref.watch(registrationFormProvider(widget.regId));
    final teamsAsync = ref.watch(registrationTeamsProvider(widget.regId));
    final title = configAsync.valueOrNull?.label ?? widget.regId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Submissions — $title'),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Team approvals',
            onPressed: () => context.go(
                '/registrations/${Uri.encodeComponent(widget.regId)}/teams'),
          ),
        ],
      ),
```

**Edit C — team name in the row subtitle.** Find (lines 143-144 and the subtitle a bit below; the two fragments below are one contiguous region starting at `data: (subs) {`):

```dart
              data: (subs) {
                final form = formAsync.valueOrNull ?? const <RegQuestion>[];
```

Replace with:

```dart
              data: (subs) {
                final form = formAsync.valueOrNull ?? const <RegQuestion>[];
                final teams =
                    teamsAsync.valueOrNull ?? const <String, RegTeam>{};
```

Then find (lines 176-177):

```dart
                        subtitle: Text(
                            [sub.path, if (when.isNotEmpty) when].join(' · ')),
```

Replace with:

```dart
                        subtitle: Text([
                          sub.path,
                          if (teams[sub.teamId] != null)
                            teams[sub.teamId]!.name,
                          if (when.isNotEmpty) when,
                        ].join(' · ')),
```

(`sub.teamId` is `''` for individuals and `teams['']` is never populated, so individuals show no team.)

- [ ] **Step 4: Analyze + full test run**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/ui/registrations lib/router/app_router.dart
flutter test
```
Expected: analyze — no issues; tests — all pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/registrations/registration_teams_page.dart lib/router/app_router.dart lib/ui/registrations/registration_submissions_page.dart
git commit -m "feat(registration): team approvals page (approve/reject, join codes, waive toggle)"
```

---

## Task 5: Manager CSV export button

**Files:**
- Modify: `MANAGER lib/ui/registrations/registration_submissions_page.dart`

Approach: build the CSV with Task 2's pure `buildSubmissionsCsv`, write it to a temp file via `path_provider`, and open the OS share sheet via `Share.shareXFiles` — the exact pattern `lib/services/tournament_bulk_import_io.dart` already uses (both packages are already in the Manager pubspec: `share_plus ^10.1.4`, `path_provider ^2.1.5`). A file share (not share-as-text) is chosen so the owner can send a real `.csv` into Sheets/Excel/Drive.

- [ ] **Step 1: Add imports**

In `MANAGER lib/ui/registrations/registration_submissions_page.dart`, find (the import block as left by Task 4):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:intl/intl.dart';
```

Replace with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/models/registration_csv.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
```

- [ ] **Step 2: Add the export method**

In the same file, find (start of the `_deleteSubmission` method):

```dart
  Future<void> _deleteSubmission(String uid, String name) async {
```

Insert BEFORE it (i.e. replace with):

```dart
  /// Builds the CSV (fixed columns + one column per form question in form
  /// order) and opens the OS share sheet with the file. Fresh reads (not the
  /// providers) so the export never shares stale data.
  Future<void> _exportCsv() async {
    try {
      final service = ref.read(registrationServiceProvider);
      final form = await service.getForm(widget.regId);
      final subs = await service.getSubmissions(widget.regId);
      final teams = await service.getTeams(widget.regId);
      final csv = buildSubmissionsCsv(
          questions: form, submissions: subs, teams: teams);
      final safeId = widget.regId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/registration_$safeId.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
          text: 'Registration submissions — ${widget.regId}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _deleteSubmission(String uid, String name) async {
```

- [ ] **Step 3: Add the AppBar button**

Find (the actions list Task 4 added):

```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Team approvals',
            onPressed: () => context.go(
                '/registrations/${Uri.encodeComponent(widget.regId)}/teams'),
          ),
        ],
```

Replace with:

```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Team approvals',
            onPressed: () => context.go(
                '/registrations/${Uri.encodeComponent(widget.regId)}/teams'),
          ),
        ],
```

- [ ] **Step 4: Analyze**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/ui/registrations/registration_submissions_page.dart
```
Expected: No issues found.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/registrations/registration_submissions_page.dart
git commit -m "feat(registration): CSV export from the submissions page"
```

---

## Task 6: Manager full verify + build/install

**Files:** none (verification only). No commit.

- [ ] **Step 1: Branch check + full analyze**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
git rev-parse --abbrev-ref HEAD
flutter analyze
```
Expected: `zaya-registration`; no NEW issues beyond the pre-existing baseline. Zero errors/warnings in any file touched by Tasks 1-5.

- [ ] **Step 2: Full test run**

```powershell
flutter test
```
Expected: All tests pass (previous suite + the extended `registration_models_test.dart` + new `registration_csv_test.dart`).

- [ ] **Step 3: Build + install to the phone (ONE app at a time)**

Ensure no other Flutter/Gradle build is running, then:

```powershell
flutter build apk --debug
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s GN434J02403404RL install -r "build\app\outputs\flutter-apk\app-debug.apk"
```
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk` then `Success`.

- [ ] **Step 4: Smoke check on device (Manager)**

Drawer → Registrations → tap an open registration → new AppBar icons appear (Export CSV + Team approvals) → Team approvals opens ("No teams yet — captains register on the fan app.") → back → Export CSV opens the share sheet with a `.csv` (header row only if no submissions; cancel the share). Fan-side team rows arrive in Task 14's end-to-end run.

---

# PHASE 2 — FAN

## Task 7: Fan pubspec (pin_code_fields) + model/test twin sync

**Files:**
- Modify: `FAN pubspec.yaml` (+ commit `pubspec.lock`)
- Modify: `FAN lib/registration/registration_models.dart` (Copy-Item from Manager)
- Modify: `FAN test/registration_models_test.dart` (Copy-Item + one import swap)

- [ ] **Step 1: Branch check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

- [ ] **Step 2: Add pin_code_fields**

In `FAN pubspec.yaml`, find (lines 70-72):

```yaml
  flutter_form_builder: ^10.2.0
  form_builder_validators: ^11.2.0
  mask_text_input_formatter: ^2.9.0
```

Replace with:

```yaml
  flutter_form_builder: ^10.2.0
  form_builder_validators: ^11.2.0
  mask_text_input_formatter: ^2.9.0
  pin_code_fields: ^8.0.1
```

Then:

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter pub get
```
Expected: `Got dependencies!` with `pin_code_fields 8.0.x` added to `pubspec.lock`. If resolution fails against the installed toolchain, run `flutter pub add pin_code_fields` instead (it picks the latest compatible release and rewrites the pubspec entry) and keep whatever constraint it writes.

- [ ] **Step 3: Sync the model twin from the Manager (source of truth)**

```powershell
Copy-Item "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\lib\models\registration_models.dart" "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\lib\registration\registration_models.dart" -Force
git diff --no-index "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\lib\models\registration_models.dart" "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\lib\registration\registration_models.dart"
```
Expected: the `git diff --no-index` prints NOTHING (byte-identical; ignore any CRLF warning lines). The model file has no package imports (only `dart:math`), so the copy compiles unchanged in both repos.

- [ ] **Step 4: Sync the test twin (one import line differs)**

```powershell
$src = "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\test\registration_models_test.dart"
$dst = "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\test\registration_models_test.dart"
$t = [System.IO.File]::ReadAllText($src).Replace("package:infinite_app_manager/models/registration_models.dart", "package:infinite_sports_flutter/registration/registration_models.dart")
[System.IO.File]::WriteAllText($dst, $t)
```
(`[System.IO.File]::WriteAllText` writes UTF-8 without BOM — do NOT use `Set-Content -Encoding utf8`, which adds a BOM in PowerShell 5.1.)

- [ ] **Step 5: Run the fan model tests**

```powershell
flutter test test/registration_models_test.dart
```
Expected: All tests pass (same suite as the Manager's, including the new L1b groups).

- [ ] **Step 6: Commit (pubspec.lock MUST be included in this task)**

```powershell
git add pubspec.yaml pubspec.lock lib/registration/registration_models.dart test/registration_models_test.dart
git commit -m "feat(registration): pin_code_fields dep + L1b model/test twin sync"
```

---

## Task 8: Fan service — team reads + captain/joiner submits

**Files:**
- Modify: `FAN lib/registration/registration_service.dart`

- [ ] **Step 1: Update the class doc comment**

Find (lines 5-8):

```dart
/// Fan-side reads/writes for the new registration engine (L1a: individual
/// path only). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — only
/// the Manager's markPaid does.
```

Replace with:

```dart
/// Fan-side reads/writes for the new registration engine (L1a individual
/// path + L1b team paths). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — with
/// ONE exception: a joiner whose team code waives payment is born
/// Paid/'team code' (spec section 5); everything else is the Manager's
/// markPaid.
```

- [ ] **Step 2: Add the team reads and the two submits**

Find the END of the file (the tail of `_writeBackProfile`, lines 152-159):

```dart
    final age = int.tryParse(answers['age']?.toString() ?? '');
    if (age != null) infoUpdates['Age'] = age;
    final height = answers['height'];
    if (height is String && height.isNotEmpty) infoUpdates['Height'] = height;
    if (infoUpdates.isNotEmpty) await root.child('Information').update(infoUpdates);
  }
}
```

Replace with:

```dart
    final age = int.tryParse(answers['age']?.toString() ?? '');
    if (age != null) infoUpdates['Age'] = age;
    final height = answers['height'];
    if (height is String && height.isNotEmpty) infoUpdates['Height'] = height;
    if (infoUpdates.isNotEmpty) await root.child('Information').update(infoUpdates);
  }

  // -------- Teams (L1b) --------

  /// {teamId: team} for a registration ({} on error). The joiner code page
  /// matches entered codes against this map (matchJoinCode).
  static Future<Map<String, RegTeam>> getTeams(String regId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Teams')
          .get();
      return regTeamsFromNode(snap.value);
    } catch (_) {
      return {};
    }
  }

  /// One team, or null (missing / malformed / error).
  static Future<RegTeam?> getTeam(String regId, String teamId) async {
    if (teamId.isEmpty) return null;
    try {
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Teams/$teamId')
          .get();
      return RegTeam.fromNode(teamId, snap.value);
    } catch (_) {
      return null;
    }
  }

  /// Captain-path submit:
  ///  1. pushes the pending Team under Registrations/{regId}/Teams
  ///     {Name (hygiene-cleaned), CaptainUid, Status:'pending',
  ///      CodeWaivesPayment:false, CreatedAt}
  ///  2. writes Submission{Path:'captain', TeamId, Paid:false}
  ///  3. legacy dual-write Sign Ups NotPaid + profile write-back — exactly
  ///     like submitIndividual.
  /// Returns false when signed out or any write throws.
  static Future<bool> submitCaptain({
    required String regId,
    required RegistrationConfig config,
    required String teamName,
    required Map<String, dynamic> answers,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final displayName = collapseTrailingSpaces(user.displayName ?? '');
    try {
      final teamNode =
          FirebaseDatabase.instance.ref('Registrations/$regId/Teams').push();
      final teamId = teamNode.key!;
      final team = RegTeam(
        id: teamId,
        name: cleanTeamName(teamName),
        captainUid: user.uid,
        status: 'pending',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await teamNode.set(team.toFirebaseMap());
      final submission = RegSubmission(
        path: 'captain',
        answers: answers,
        teamId: teamId,
        paid: false,
        displayName: displayName,
        submittedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/${user.uid}')
          .set(submission.toFirebaseMap());
      final target = legacySignUpTarget(config);
      await FirebaseDatabase.instance
          .ref('Sign Ups/${target.league}/${target.season}/NotPaid/${user.uid}')
          .set(displayName);
      await _writeBackProfile(user.uid, config.sport, answers);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Joiner-path submit. When [team].codeWaivesPayment the submission is
  /// born Paid ('team code') and the legacy dual-write goes straight to the
  /// Paid bucket; otherwise it lands in NotPaid exactly like an individual.
  /// Returns false when signed out or any write throws.
  static Future<bool> submitJoiner({
    required String regId,
    required RegistrationConfig config,
    required RegTeam team,
    required Map<String, dynamic> answers,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final displayName = collapseTrailingSpaces(user.displayName ?? '');
    try {
      final waived = team.codeWaivesPayment;
      final submission = RegSubmission(
        path: 'joiner',
        answers: answers,
        teamId: team.id,
        paid: waived,
        paidVia: waived ? 'team code' : '',
        displayName: displayName,
        submittedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/${user.uid}')
          .set(submission.toFirebaseMap());
      final target = legacySignUpTarget(config);
      final bucket = waived ? 'Paid' : 'NotPaid';
      await FirebaseDatabase.instance
          .ref('Sign Ups/${target.league}/${target.season}/$bucket/${user.uid}')
          .set(displayName);
      await _writeBackProfile(user.uid, config.sport, answers);
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 3: Analyze the touched file**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/registration/registration_service.dart
```
Expected: No issues found.

- [ ] **Step 4: Commit**

```powershell
git add lib/registration/registration_service.dart
git commit -m "feat(registration): captain + joiner submit paths in the fan service"
```

---

## Task 9: Fan path-aware form page + payment amount parameter

**Files:**
- Modify: `FAN lib/registration/payment_screen.dart`
- Modify: `FAN lib/registration/registration_form_page.dart` (full-file rewrite)
- Modify: `FAN lib/registration/registration_status_page.dart` (one call site — full rewrite comes in Task 12)

The payment screen currently shows `config.fee` everywhere. Captains owe `config.teamFee`, so the screen takes an explicit `amount` and every caller computes it with the pure `amountOwed` helper. This task updates BOTH existing call sites so the repo compiles green.

- [ ] **Step 1: Parametrize the payment screen**

Four edits in `FAN lib/registration/payment_screen.dart`.

**Edit A — field.** Find (lines 21-22):

```dart
  final String regId;
  final RegistrationConfig config;
```

Replace with:

```dart
  final String regId;
  final RegistrationConfig config;

  /// The dollar amount THIS registrant owes — captains owe config.teamFee,
  /// individuals/joiners config.fee. Callers compute it with [amountOwed].
  final num amount;
```

**Edit B — constructor.** Find (lines 29-34):

```dart
  const PaymentScreen({
    super.key,
    required this.regId,
    required this.config,
    this.fromSubmission = false,
  });
```

Replace with:

```dart
  const PaymentScreen({
    super.key,
    required this.regId,
    required this.config,
    required this.amount,
    this.fromSubmission = false,
  });
```

**Edit C — Venmo deep link.** Find (lines 42-43):

```dart
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=${config.fee}&note=$note');
```

Replace with:

```dart
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=$amount&note=$note');
```

**Edit D — fee card.** Find (lines 75-76):

```dart
              title: Text('\$${config.fee}',
                  style: Theme.of(context).textTheme.headlineSmall),
```

Replace with:

```dart
              title: Text('\$$amount',
                  style: Theme.of(context).textTheme.headlineSmall),
```

- [ ] **Step 2: Rewrite the form page (path/teamName/team parameters)**

Replace the ENTIRE contents of `FAN lib/registration/registration_form_page.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

/// Loads the registration's form + the player's profile prefill, renders the
/// questions visible on [path] ('individual' | 'captain' | 'joiner'),
/// submits through the matching service call, then routes to the payment
/// screen (when a payment is owed — captains owe the TEAM fee) or straight
/// to the status page.
class RegistrationFormPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;
  final String path; // 'individual' | 'captain' | 'joiner'
  final String teamName; // captain path: the new team's cleaned name
  final RegTeam? team; // joiner path: the approved team being joined

  const RegistrationFormPage({
    super.key,
    required this.regId,
    required this.config,
    this.path = 'individual',
    this.teamName = '',
    this.team,
  });

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage> {
  late Future<(List<RegQuestion>, Map<String, dynamic>)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<(List<RegQuestion>, Map<String, dynamic>)> _loadAll() async {
    final form = await RegistrationService.getForm(widget.regId);
    final prefill = await RegistrationService.getPrefill(widget.config.sport);
    final visible = form.where((q) => q.visibleFor(widget.path)).toList();
    return (visible, prefill);
  }

  Future<bool> _submitForPath(Map<String, dynamic> answers) {
    switch (widget.path) {
      case 'captain':
        return RegistrationService.submitCaptain(
          regId: widget.regId,
          config: widget.config,
          teamName: widget.teamName,
          answers: answers,
        );
      case 'joiner':
        return RegistrationService.submitJoiner(
          regId: widget.regId,
          config: widget.config,
          team: widget.team!,
          answers: answers,
        );
      default:
        return RegistrationService.submitIndividual(
          regId: widget.regId,
          config: widget.config,
          answers: answers,
        );
    }
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    final ok = await _submitForPath(answers);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Something went wrong — try again, and contact us if it keeps failing.')));
      return;
    }
    // Mirror of what the service just wrote — enough for the owed check.
    final waived = widget.team?.codeWaivesPayment ?? false;
    final bornPaid = widget.path == 'joiner' && waived;
    final submission = RegSubmission(
      path: widget.path,
      answers: answers,
      teamId: widget.team?.id ?? '',
      paid: bornPaid,
      paidVia: bornPaid ? 'team code' : '',
      submittedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (paymentOwed(
        config: widget.config,
        submission: submission,
        codeWaivesPayment: waived)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => PaymentScreen(
                regId: widget.regId,
                config: widget.config,
                amount: amountOwed(
                    config: widget.config,
                    submission: submission,
                    codeWaivesPayment: waived),
                fromSubmission: true)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => RegistrationStatusPage(
                regId: widget.regId, config: widget.config)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.config.label),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          final (questions, prefill) =
              snapshot.data ?? (const <RegQuestion>[], const <String, dynamic>{});
          if (questions.isEmpty) {
            return const Center(
                child: Text(
                    'This registration has no form yet — please try again later.'));
          }
          return DynamicRegistrationForm(
            questions: questions,
            initialValues: prefill,
            submitLabel: 'Register',
            onSubmit: _onSubmit,
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Fix the status page call site (keeps the build green)**

In `FAN lib/registration/registration_status_page.dart`, find (lines 120-127):

```dart
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                    regId: widget.regId,
                                    config: widget.config)),
                          ).then((_) => _refresh());
                        },
```

Replace with:

```dart
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                    regId: widget.regId,
                                    config: widget.config,
                                    amount: amountOwed(
                                        config: widget.config,
                                        submission: sub))),
                          ).then((_) => _refresh());
                        },
```

(`amountOwed` is safe without `codeWaivesPayment` here: a waived joiner is born Paid, so this button never renders for them.)

- [ ] **Step 4: Analyze the touched files**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
flutter analyze lib/registration
```
Expected: No issues found.

- [ ] **Step 5: Commit**

```powershell
git add lib/registration/payment_screen.dart lib/registration/registration_form_page.dart lib/registration/registration_status_page.dart
git commit -m "feat(registration): path-aware form page + payment amount parameter"
```

---

## Task 10: Fan join-code entry page (pin boxes)

**Files:**
- Create: `FAN lib/registration/join_code_page.dart`

Nothing routes here yet (Task 11 wires the path page), but the file compiles standalone.

- [ ] **Step 1: Create the page**

Create `FAN lib/registration/join_code_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

/// Joiner-path code entry: 6 pin boxes, auto-uppercased, checked against
/// this registration's teams on every keystroke (matchJoinCode). An approved
/// match shows "Joining {team}" + Continue; a pending/rejected team's code
/// and unknown codes get friendly errors (spec section 7). Admin-edited
/// codes shorter than 6 characters still match because the check runs on
/// every change, not only on completion.
class JoinCodePage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const JoinCodePage({super.key, required this.regId, required this.config});

  @override
  State<JoinCodePage> createState() => _JoinCodePageState();
}

class _JoinCodePageState extends State<JoinCodePage> {
  final TextEditingController _controller = TextEditingController();
  Map<String, RegTeam>? _teams; // null while loading
  RegTeam? _match;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await RegistrationService.getTeams(widget.regId);
    if (!mounted) return;
    setState(() => _teams = teams);
    _check();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    final teams = _teams;
    if (teams == null) return; // still loading
    final entered = _controller.text.trim();
    final result = matchJoinCode(teams, entered);
    setState(() {
      if (result.status == 'ok') {
        _match = result.team;
        _error = null;
      } else if (result.status == 'notApproved') {
        _match = null;
        _error =
            'That team is still awaiting approval — ask your captain to check back soon.';
      } else {
        _match = null;
        // Only complain once all six boxes are filled; partial input just
        // clears the state.
        _error = entered.length >= 6
            ? "That code doesn't match any team in this registration."
            : null;
      }
    });
  }

  void _continue() {
    final team = _match;
    if (team == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationFormPage(
          regId: widget.regId,
          config: widget.config,
          path: 'joiner',
          team: team);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final loading = _teams == null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.config.label),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Enter your team code',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 15),
            child: Text(
                'Your captain got a 6-character code when the team was approved.',
                textAlign: TextAlign.center),
          ),
          PinCodeTextField(
            appContext: context,
            length: 6,
            controller: _controller,
            autoDisposeControllers: false,
            enabled: !loading,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            animationType: AnimationType.fade,
            backgroundColor: Colors.transparent,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              TextInputFormatter.withFunction((oldV, newV) =>
                  newV.copyWith(text: newV.text.toUpperCase())),
            ],
            textStyle:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            pinTheme: PinTheme(
              shape: PinCodeFieldShape.box,
              borderRadius: BorderRadius.circular(8),
              fieldHeight: 52,
              fieldWidth: 44,
              activeColor: Theme.of(context).colorScheme.primary,
              selectedColor: Theme.of(context).colorScheme.primary,
              inactiveColor: Theme.of(context).dividerColor,
            ),
            onChanged: (_) => _check(),
            onCompleted: (_) => _check(),
          ),
          if (loading)
            Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_match != null) ...[
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.verified, color: Colors.green),
                title: Text('Joining ${_match!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_match!.codeWaivesPayment
                    ? 'Your captain covers the team fee — no payment needed.'
                    : "You'll pay the \$${widget.config.fee} player fee after registering."),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _continue,
                child: const Text('Continue', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze the new file**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/registration/join_code_page.dart
```
Expected: No issues found. (If `pin_code_fields 8.x` surfaces a parameter mismatch on Flutter 3.44 — e.g. `textCapitalization` unsupported — drop that single named argument; the two `inputFormatters` already force uppercase on their own.)

- [ ] **Step 3: Commit**

```powershell
git add lib/registration/join_code_page.dart
git commit -m "feat(registration): join-code entry page (pin boxes)"
```

---

## Task 11: Fan path page — activate both team tiles

**Files:**
- Modify: `FAN lib/registration/registration_path_page.dart` (full-file rewrite)

- [ ] **Step 1: Rewrite the page**

Replace the ENTIRE contents of `FAN lib/registration/registration_path_page.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/join_code_page.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// "How are you registering?" — all three paths are live as of L1b:
/// individual, join a team with a code (joiner), register a new team
/// (captain — asks the team name first, hygiene-cleaned and non-empty).
class RegistrationPathPage extends StatelessWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationPathPage(
      {super.key, required this.regId, required this.config});

  Future<void> _startCaptain(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your team name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Team name',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final cleaned = cleanTeamName(controller.text);
              if (cleaned.isEmpty) return; // require a non-empty name
              Navigator.pop(ctx, cleaned);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationFormPage(
          regId: regId, config: config, path: 'captain', teamName: name);
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(config.label),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('How are you registering?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center),
          ),
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Register as an individual',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("We'll place you on a team"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) {
                  return RegistrationFormPage(regId: regId, config: config);
                }));
              },
            ),
          ),
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Join a team with a code',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Enter the code your captain sent you'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) {
                  return JoinCodePage(regId: regId, config: config);
                }));
              },
            ),
          ),
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.groups),
              title: const Text('Register a new team (captain)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Name your team — an admin approves it and you get a join code'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _startCaptain(context),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze the touched file**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/registration/registration_path_page.dart
```
Expected: No issues found.

- [ ] **Step 3: Commit**

```powershell
git add lib/registration/registration_path_page.dart
git commit -m "feat(registration): activate captain + joiner paths on the path page"
```

---

## Task 12: Fan status page team card + share, dual-fee entry list

**Files:**
- Modify: `FAN lib/registration/registration_status_page.dart` (full-file rewrite)
- Modify: `FAN lib/registration/registration_entry_page.dart`

- [ ] **Step 1: Rewrite the status page**

Replace the ENTIRE contents of `FAN lib/registration/registration_status_page.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:share_plus/share_plus.dart';

/// The player's registration state: Paid badge, team state (captain sees
/// "pending approval" / a rejection notice / the join code prominently with
/// copy + Share once approved; a joiner sees their team name), the submitted
/// answers, and a persistent "Complete payment" button (reopening the
/// payment screen with the right amount) while unpaid.
class RegistrationStatusPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationStatusPage(
      {super.key, required this.regId, required this.config});

  @override
  State<RegistrationStatusPage> createState() => _RegistrationStatusPageState();
}

class _RegistrationStatusPageState extends State<RegistrationStatusPage> {
  late Future<(RegSubmission?, List<RegQuestion>, RegTeam?)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<(RegSubmission?, List<RegQuestion>, RegTeam?)> _loadAll() async {
    final sub = await RegistrationService.getMySubmission(widget.regId);
    final form = await RegistrationService.getForm(widget.regId);
    final team = (sub == null || sub.teamId.isEmpty)
        ? null
        : await RegistrationService.getTeam(widget.regId, sub.teamId);
    return (sub, form, team);
  }

  void _refresh() {
    setState(() => _load = _loadAll());
  }

  String _displayValue(RegQuestion? q, Object? value) {
    if (value is List) return value.map((v) => v.toString()).join(', ');
    if (value is bool) return value ? 'Yes' : 'No';
    if (q?.type == 'phone') return formatPhone(value?.toString() ?? '');
    return value?.toString() ?? '';
  }

  String _pathLabel(String path) {
    switch (path) {
      case 'captain':
        return 'Team captain';
      case 'joiner':
        return 'Team member';
      default:
        return 'Individual';
    }
  }

  void _copyCode(RegTeam team) {
    Clipboard.setData(ClipboardData(text: team.joinCode));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Join code copied.')));
  }

  void _shareCode(RegTeam team) {
    SharePlus.instance.share(ShareParams(
        text:
            'Join my team "${team.name}" for ${widget.config.label}! Open the Infinite Sports app, go to Registration, pick "Join a team with a code" and enter: ${team.joinCode}'));
  }

  Widget? _teamCard(RegSubmission sub, RegTeam? team) {
    if (sub.teamId.isEmpty) return null;
    if (team == null) {
      return const Card(
        elevation: 2,
        child: ListTile(
          leading: Icon(Icons.group),
          title: Text('Team'),
          subtitle:
              Text("Couldn't load your team right now — go back and retry."),
        ),
      );
    }
    if (sub.path == 'captain') {
      if (team.isPending) {
        return Card(
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.hourglass_top, color: Colors.orange),
            title: Text(team.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                "Team pending approval — you'll get your join code here once an admin approves it. Check back soon."),
          ),
        );
      }
      if (team.isRejected) {
        return Card(
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text(team.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                "Your team wasn't approved. Your own registration still counts — contact us and we'll sort it out."),
          ),
        );
      }
      // Approved: the join code, prominently, with copy + share.
      return Card(
        elevation: 2,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.verified, color: Colors.green),
              title: Text(team.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Approved! Teammates join with this code.'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(team.joinCode,
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6)),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy code',
                  onPressed: () => _copyCode(team),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Share code'),
                  onPressed: () => _shareCode(team),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Joiner.
    return Card(
      elevation: 2,
      child: ListTile(
        leading: const Icon(Icons.group),
        title: Text(team.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub.paidVia == 'team code'
            ? "You're on the team — payment covered by your captain."
            : "You're on the team."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('My Registration'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          final (sub, form, team) =
              snapshot.data ?? (null, const <RegQuestion>[], null);
          if (sub == null) {
            return const Center(
                child: Text('No registration found for your account.'));
          }
          final byKey = {for (final q in form) q.key: q};
          final orderedKeys = [
            ...form.map((q) => q.key).where(sub.answers.containsKey),
            ...sub.answers.keys.where((k) => !byKey.containsKey(k)),
          ];
          final owes = paymentOwed(config: widget.config, submission: sub);
          final teamCard = _teamCard(sub, team);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(15),
                  children: [
                    Card(
                      elevation: 2,
                      child: ListTile(
                        title: Text(widget.config.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'Registered as: ${_pathLabel(sub.path)}'),
                        trailing: Chip(
                          label: Text(sub.paid
                              ? (sub.paidVia == 'team code'
                                  ? 'Paid via team code'
                                  : 'Paid')
                              : 'Payment pending'),
                          backgroundColor: sub.paid
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                        ),
                      ),
                    ),
                    if (teamCard != null) ...[
                      const SizedBox(height: 8),
                      teamCard,
                    ],
                    const SizedBox(height: 8),
                    for (final key in orderedKeys)
                      ListTile(
                        dense: true,
                        title: Text(byKey[key]?.label ?? key),
                        subtitle:
                            Text(_displayValue(byKey[key], sub.answers[key])),
                      ),
                  ],
                ),
              ),
              if (owes)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                    regId: widget.regId,
                                    config: widget.config,
                                    amount: amountOwed(
                                        config: widget.config,
                                        submission: sub))),
                          ).then((_) => _refresh());
                        },
                        child: const Text('Complete payment',
                            style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Dual-fee subtitle on the entry list**

In `FAN lib/registration/registration_entry_page.dart`, find (lines 72-92, inside `itemBuilder`):

```dart
              // L1a only offers the individual path, so show what an
              // individual registrant would owe: config.fee under
              // 'perPlayer'/'both', but nothing under 'teamFee' — that fee
              // belongs to a captain (not offered here), and an individual
              // owes nothing until an admin places them on a team.
              final individualFee =
                  config.paymentMode == 'teamFee' ? 0 : config.fee;
              return ListTile(
                enabled: signedIn,
                leading: const Icon(Icons.how_to_reg),
                title: Text(config.label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(signedIn
                    ? (individualFee > 0
                        ? 'Fee: \$$individualFee${config.feeNote.isNotEmpty ? ' — ${config.feeNote}' : ''}'
                        : 'Free')
                    : 'Log in to register'),
                onTap: () => _openRegistration(regId, config),
              );
```

Replace with:

```dart
              // All three paths are live (L1b): show the per-player fee
              // and/or the team fee this registration is configured with.
              final feeParts = <String>[
                if (config.paymentMode != 'teamFee' && config.fee > 0)
                  '\$${config.fee} per player',
                if (config.paymentMode != 'perPlayer' && config.teamFee > 0)
                  '\$${config.teamFee} per team',
              ];
              final feeText = feeParts.isEmpty
                  ? 'Free'
                  : 'Fee: ${feeParts.join(' · ')}${config.feeNote.isNotEmpty ? ' — ${config.feeNote}' : ''}';
              return ListTile(
                enabled: signedIn,
                leading: const Icon(Icons.how_to_reg),
                title: Text(config.label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(signedIn ? feeText : 'Log in to register'),
                onTap: () => _openRegistration(regId, config),
              );
```

- [ ] **Step 3: Analyze the touched files**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/registration
```
Expected: No issues found.

- [ ] **Step 4: Commit**

```powershell
git add lib/registration/registration_status_page.dart lib/registration/registration_entry_page.dart
git commit -m "feat(registration): status page team card + code share, dual-fee entry list"
```

---

## Task 13: Fan full verify + build/install

**Files:** none (verification only). No commit.

- [ ] **Step 1: Branch check + full analyze (fan analyze can be slow — allow up to 10 minutes)**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
flutter analyze
```
Expected: `zaya-registration`; no NEW issues beyond the repo's pre-existing baseline. Zero errors/warnings in `lib/registration/` or `test/registration_models_test.dart`.

- [ ] **Step 2: Full test run**

```powershell
flutter test
```
Expected: All tests pass (existing suite + the twin-synced `registration_models_test.dart` with the new L1b groups + the existing `registration_form_test.dart`).

- [ ] **Step 3: Build + install to the phone (ONE app at a time — make sure the Manager build from Task 6 has finished)**

```powershell
flutter build apk --debug
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s GN434J02403404RL install -r "build\app\outputs\flutter-apk\app-debug.apk"
```
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk` then `Success`.

- [ ] **Step 4: Working-tree check**

```powershell
git status --porcelain
```
Expected: nothing staged/modified except untracked files this plan never touches (`PROJECT_REFERENCE.md`, `SoccerStats.png`, `.claude/`, `docs/...`). If `pubspec.lock` shows modified here, something re-resolved after Task 7 — run `git diff pubspec.lock` and either commit the delta with a `chore:` commit (if pin_code_fields moved) or `git restore pubspec.lock`.

---

## Task 14: End-to-end owner script (both apps on the phone)

**Files:** none. No commit. Needs an OPEN registration whose paymentMode exercises both fees — if the L1a test registration is still around, edit it, otherwise open a fresh one.

Tell the owner to run this script:

- [ ] 1. **Manager:** Registrations → confirm a Futsal registration shows an OPEN chip and uses paymentMode **Both** with fee `20` and team fee `300` (open a new registration with those numbers if needed — wizard: League → Futsal → fee 20 / team fee 300 → Venmo+Zelle on → Both → Open).
- [ ] 2. **Fan app (main account, signed in):** drawer → Sign Up entry → the registration's subtitle now reads `Fee: $20 per player · $300 per team` → tap → "How are you registering?" now shows all three options ACTIVE.
- [ ] 3. **Captain path:** tap "Register a new team (captain)" → team name dialog (try Continue with it empty — it refuses) → type `red dragons  ` → Continue → the form shows the captain-visible questions → Register → **payment screen shows $300** (the TEAM fee, not $20 — this is the key L1b payment check) with the Venmo amount pre-filled at 300 → "View my registration" → status shows "Registered as: Team captain" + a "Red Dragons" card reading **Team pending approval**.
- [ ] 4. **Manager:** Registrations → the registration → the submission row shows `captain · Red Dragons` → AppBar groups icon → Teams page: "Red Dragons" sits under **Pending approval** with your captain name → **Approve** → the dialog shows a pre-generated 6-char code (letters/digits only, no I/O/0/1), tap **Generate** to re-roll, then answer "Players joining with this code:" with **Skip payment (captain covers)** → Approve → the team moves to **Approved** with the code, a copy button, a regenerate button, and the "Code skips payment" toggle ON.
- [ ] 5. **Fan (captain account):** reopen My Registration → the team card now shows **the join code in large type** + copy + **Share code** (share sheet opens with the invite text — cancel it). The "Complete payment" button still shows $300 until you're marked Paid.
- [ ] 6. **Joiner path (second account — or first delete your own submission in Manager → Submissions → tap row → Remove registration):** drawer → registration → "I have a team code" → pin boxes: type a wrong 6-char code → "doesn't match any team" error → type the real code (watch it uppercase as you type) → **Joining Red Dragons** card says the captain covers payment → Continue → joiner form → Register → **no payment screen** — straight to status: "Registered as: Team member", chip **Paid via team code**, team card "payment covered by your captain".
- [ ] 7. **Legacy sync check:** Manager → Sign Ups → Futsal Season N → the joiner appears under **Paid** (waived) and the captain under **NotPaid**. Add-from-signups roster picker shows both.
- [ ] 8. **Waive OFF variant (optional but recommended):** Teams page → toggle "Code skips payment" OFF → a THIRD account joins with the same code → the join card now says "$20 player fee after registering" → after Register the **payment screen shows $20** → status shows "Payment pending" + Complete payment.
- [ ] 9. **Pending-team code check:** Manager → reject nothing, but note a pending team's code cannot exist yet — instead: open a second captain registration from another account, then have someone type THAT team's (nonexistent) code → "doesn't match"; approve the team, regenerate its code, and confirm the OLD code now errors while the NEW one matches.
- [ ] 10. **CSV export:** Manager → Submissions → share icon → share the `.csv` to yourself (email/Drive) → open it: columns `Name, Path, Team, Paid, Paid Via, Submitted` + one column per form question in form order; the joiner row shows `Yes` / `team code` / the team name; any comma/quote answers stay in one cell.
- [ ] 11. **Reject flow:** Teams page → a pending team (create one more from a spare account if none left) → Reject → confirm → fan captain's status page shows the "wasn't approved" notice; the captain's row is still in Submissions.
- [ ] 12. **Cleanup:** if this was throwaway data, delete `Registrations/Futsal-N/Teams`, the test submissions, and the matching `Sign Ups/Futsal/N/(Paid|NotPaid)` entries in the Firebase console (or via Remove registration in the Manager, which cleans both legacy buckets automatically).

Do NOT merge `zaya-registration` into `zaya-features` — the owner decides after Paul/Bronsin review. Commits stay local.

---

## Self-Review

**1. Spec coverage (L1b scope):**
- **Owner scope 1 — models:** `RegTeam{id, name, captainUid, status pending|approved|rejected, joinCode, codeWaivesPayment, createdAt}` with defensive `fromNode`/`toFirebaseMap` (Task 1); pure injectable-Random generator on the confusable-free alphabet + normalize/validate helpers + `matchJoinCode` + `hasDuplicateTeamName` + `cleanTeamName` + `amountOwed`, all unit-tested (Task 1); twin kept byte-identical via Manager-source `Copy-Item` + `git diff --no-index` (Task 7). Lint gotchas honored: `//` file headers, `ListTile` always inside `Card`/`Material`, `ChoiceChip` + plain `Switch` instead of RadioListTile/SwitchListTile/DropdownButtonFormField, no reorder widgets touched. ✓
- **Owner scope 2 — Manager approvals:** `getTeams`/`approveTeam(regId, teamId, joinCode, codeWaivesPayment)` (sets status+code+waive in one update)/`rejectTeam`/`setTeamCode`/`setTeamWaive` (Task 3); Teams page as a peer route `/registrations/:regId/teams` off the submissions page's AppBar (placement justified in Task 4 — the submissions page is a single-list Scaffold and the route tree already nests this way); pending section with the approve dialog (generated editable code, Generate re-roll, per-registration uniqueness via `validateJoinCode(taken:)`, duplicate-name warning, the exact "skip payment (captain covers) or pay individually?" question as ChoiceChips defaulting from paymentMode); approved section with code display/copy/regenerate/waive toggle; rejected section with re-approve; approving writes NO rosters (doc-commented, L2 note). ✓
- **Owner scope 3 — captain path:** path tile active → team-name dialog (non-empty validated, `cleanTeamName` hygiene) → form filtered to `visibleFor('captain')` ('captain' + 'all') → `submitCaptain` writes Submission{path:'captain', teamId} + pending Team + legacy NotPaid dual-write + profile write-back (Task 8, 11); status page shows "Team pending approval", then the code prominently with copy + Share (`SharePlus.instance.share` — the fan repo's v12 API, matching `share_profile_service.dart`) once approved, and the rejection notice (Task 12); payment screen parametrized with `amount` so the captain sees `teamFee` under teamFee/both — verified by `amountOwed` unit tests and E2E step 3 (Tasks 1, 9). ✓
- **Owner scope 4 — joiner path:** tile active → `pin_code_fields` entry (added to fan pubspec with `pubspec.lock` committed in Task 7), 6 boxes auto-uppercase, validated within THIS registration's teams via `matchJoinCode` ("Joining {team}" card, pending-team and no-match friendly errors) → form filtered to `visibleFor('joiner')` → `submitJoiner` writes Submission{path:'joiner', teamId, paid: codeWaivesPayment, paidVia: 'team code' when waived} + legacy dual-write to Paid when waived / NotPaid otherwise (Tasks 8, 10, 11); status shows team name + paid state (Task 12). ✓
- **Owner scope 5 — CSV export:** pure `buildSubmissionsCsv(questions:, submissions:, teams:)` in a Manager-only pure file (choice justified: keeps the twin contract small; the fan app never exports), unit-tested including comma/quote/newline escaping, ordering, team/paid/date columns (Task 2); submissions-page button shares a real temp `.csv` via `path_provider` + `Share.shareXFiles` (both deps already in the Manager pubspec — checked), full code shown (Task 5). ✓
- **Owner scope 6 — verify/build:** Manager analyze+test+build+install to `GN434J02403404RL` (Task 6), fan the same with builds explicitly sequential (Task 13), owner E2E script covering captain→approve(code+waive)→joiner-skips-payment→CSV (Task 14). ✓
- **Spec §7 edge cases:** double-register still blocked by the entry page (untouched); pending/rejected-team code → "awaiting approval" error (`matchJoinCode 'notApproved'`); malformed team nodes → `fromNode` null + guarded service reads; duplicate team names → approve-dialog warning; code collision → `generateUniqueJoinCode` retry + manual-edit validation.
- **Deliberately deferred / not covered (named explicitly):** (a) **reject note** — spec §4 says "Reject with optional note", but the owner's L1b model spec (`RegTeam{...}`) has no note field, and the prompt says to honor that flow exactly; the captain still sees a rejection notice. (b) **QR code for the captain's code** — spec §5 marks it optional (`qr_flutter`); Share-as-text ships instead. (c) **join codes longer than 6 chars can't be typed in the fan pin boxes** — Manager still allows 4-12 (pattern parity with tournaments); 4-5-char codes DO match (checks run on every keystroke), and both Manager dialogs carry helper text "Keep it to 6 characters". (d) **CSV columns are form-order questions only** — answers whose keys were later removed from the form are not exported (doc-commented in the builder). (e) **fan-side "already on a team roster" guard** — rosters don't exist until L2.

**2. Placeholder scan:** No TBD/TODO/"similar to Task N"/"add validation" anywhere; every created file ships complete contents; every modification is an exact find/replace pair verified against the current files on `zaya-registration` (models file tail `];` at line 522, models test tail lines 456-465, firebase_paths lines 177-182, registration_service tail lines 123-133, provider lines 24-27, app_router lines 17 + 149-155, submissions page lines 1-5/116-124/143-144/176-177 + the Task-4-produced actions block consumed by Task 5, fan pubspec lines 70-72, fan service lines 5-8 + 152-159, payment screen lines 21-22/29-34/42-43/75-76, status page lines 120-127 (Task 9) then full rewrite (Task 12), entry page lines 72-92, path page + form page full rewrites). The only conditional instruction is the flagged fallback if `pin_code_fields ^8.0.1` fails to resolve/compile on Flutter 3.44 (Task 7 Step 2 / Task 10 Step 2) — called out as a package-version risk, with the exact alternative command given.

**3. Type consistency:** `RegTeam{id, name, captainUid, status, joinCode, codeWaivesPayment, createdAt}` + `isPending/isApproved/isRejected` defined once (Task 1) and consumed with those exact names in Tasks 2 (CSV), 3 (service), 4 (teams page), 8 (fan service), 10 (join page), 12 (status page). `regTeamsFromNode(Object?) → Map<String, RegTeam>` used by both services. `generateUniqueJoinCode(Random, Set<String>, {length})` / `validateJoinCode(String, {Set<String> taken})` / `normalizeJoinCode(String)` used identically in both Manager dialogs; `matchJoinCode(Map<String, RegTeam>, String) → JoinCodeMatch{status, team}` used by the join page with statuses `'ok'|'notApproved'|'notFound'`. `amountOwed({config, submission, codeWaivesPayment}) → num` matches its three call sites (form page, status page, tests). Service signatures match callers: Manager `approveTeam(String, String, String, bool)` ← approve dialog's `({String code, bool waive})` record; `setTeamCode(String, String, String)`; `setTeamWaive(String, String, bool)`; fan `submitCaptain({regId, config, teamName, answers})` / `submitJoiner({regId, config, team, answers})` ← `_submitForPath`. `PaymentScreen(regId:, config:, amount:, fromSubmission:)` matches both remaining call sites after Task 9 (the Task 12 rewrite preserves the `amount:` argument). Provider `registrationTeamsProvider` (family by regId) matches every watch/read/invalidate in Tasks 4-5. `buildSubmissionsCsv(questions:, submissions:, teams:)` matches Task 5's call. ✓

**4. Implementer caveats:**
- `pin_code_fields ^8.0.1` is the one new dependency; it is mature but not recently updated — if pub resolution or compilation fails on Flutter 3.44, Task 7 Step 2 gives the `flutter pub add` fallback and Task 10 Step 2 names the one plausible API nit (`textCapitalization`) and its safe removal (the inputFormatters already uppercase).
- Manager `share_plus` is v10 (`Share.shareXFiles` — same call the tournament bulk-import uses today); fan `share_plus` is v12 (`SharePlus.instance.share(ShareParams(...))`). Do not swap the APIs between repos.
- The approve dialog reads `registrationConfigProvider(...).valueOrNull` for the waive default; the page build watches the same provider (for the title), so it is loaded by the time the dialog opens — and a null just defaults the chips to "pay individually".
- go_router regIds can contain spaces (`Flag Football-9`); the submissions page re-encodes with `Uri.encodeComponent` when navigating to the nested `teams` route, mirroring the hub list's pattern.

