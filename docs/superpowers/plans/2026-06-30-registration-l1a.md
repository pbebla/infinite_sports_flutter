# Registration Redesign L1a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build phase L1a of the registration redesign: a data-driven registration engine (question model + templates), a Manager Registration Hub (open/close registrations with a switch, wizard, submissions view with Paid flip, template editor), and the fan-side individual registration flow (dynamic form, Venmo/Zelle payment screen, re-openable payment, status page) — all dual-writing the legacy `Sign Ups/...` buckets so every existing consumer (Manager Sign Ups page, Add-from-signups roster builder) keeps working unchanged.

**Architecture:** One pure model file (`RegQuestion` / `RegistrationConfig` / `RegSubmission` + input-hygiene and payment-owed helpers) is duplicated byte-for-byte in both repos (the apps share no code — precedent: trophy/tournament models duplicated per repo) and unit-tested with zero Firebase. Manager side: additive `FirebasePaths` entries, a `RegistrationService extends FirebaseService` whose `markPaid` also moves the legacy entry via the existing `SignUpService.moveToPaid/moveToNotPaid`, Riverpod providers, a shared drag-reorder question editor widget, and four hub pages behind a new `/registrations` route. Fan side: three form packages, a static-method `RegistrationService` (style of `lib/misc/tournament_service.dart`), a `flutter_form_builder`-based dynamic renderer in a new `lib/registration/` module, five flow screens, and two wiring edits (drawer tile + Matches banner). Team paths, join codes, and Stripe are later phases (L1b/L1c) — the `_JoinCodeDialog`/`_generateJoinCode` pattern in `manage_teams_page.dart` is referenced by the spec but NOT touched here.

**Tech Stack:** Flutter/Dart 3. Manager: Riverpod, go_router, Firebase RTDB via `FirebaseService`/`FirebasePaths`, package `infinite_app_manager`. Fan: stateful widgets + `Navigator.push(MaterialPageRoute(...))`, plain-function/static-class services, package `infinite_sports_flutter`, new deps `flutter_form_builder` + `form_builder_validators` + `mask_text_input_formatter`.

**Spec:** `docs/superpowers/specs/2026-06-30-registration-redesign-design.md` (fan repo, branch `zaya-registration`).

**Branches:** `zaya-registration` in BOTH repos, off `zaya-features`. The fan repo already has it checked out; the Manager repo is on `zaya-features` — Task 1 creates the branch there. All commits LOCAL (no push).

---

## Conventions for every task below

- **Repo roots:** `MANAGER` = `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, `FAN` = `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`. Every file path in a task is prefixed with the repo it belongs to.
- **Run flutter via PowerShell** (never rely on PATH):
  ```powershell
  $env:Path = "C:\src\flutter\bin;" + $env:Path
  Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"   # or the FAN root
  ```
- **Branch check before touching files** in a repo: `git rev-parse --abbrev-ref HEAD` must print `zaya-registration` (Manager Task 1 CREATES it off `zaya-features`; every later task just verifies).
- **Stage exact paths only** — never `git add -A` or `git add .`. In the FAN repo NEVER stage `PROJECT_REFERENCE.md`, `SoccerStats.png`, `.claude/`, or `docs/` files.
- **pubspec.lock:** if a task incidentally modifies it, run `git restore pubspec.lock` before committing — EXCEPT Task 7 (fan pubspec task), where `pubspec.lock` MUST be committed alongside `pubspec.yaml`.
- All commits stay local. Do not merge to `zaya-features`; the owner decides after on-device testing.
- Build/install one app at a time (never two Gradle builds in parallel). Device serial: `GN434J02403404RL`.
- The fan repo's full `flutter analyze` can be slow; analyze the touched paths first, then do one full pass in the verify task with a generous timeout.

---

## File Structure

**MANAGER (`InfiniteSportsManagerFlutter`):**
- **Create** `lib/models/registration_models.dart` — pure: `RegQuestion`, `RegistrationConfig`, `RegSubmission`, hygiene helpers, `paymentOwed`, `legacySignUpTarget`, `kDefaultRegQuestions`. No imports.
- **Create** `test/registration_models_test.dart` — unit tests for everything above.
- **Modify** `lib/core/constants/firebase_paths.dart` — `Registrations/...` + `FormTemplates/...` path helpers (additive).
- **Create** `lib/services/firebase/registration_service.dart` — `RegistrationService extends FirebaseService`; `markPaid` syncs legacy via `SignUpService`.
- **Create** `lib/providers/registration_provider.dart` — Riverpod providers.
- **Create** `lib/ui/registrations/widgets/question_list_editor.dart` — drag-reorder question list + add/edit dialog + delete-confirm (shared by wizard + template editor).
- **Create** `lib/ui/registrations/registrations_page.dart` — hub list (open/closed chips, Status switch).
- **Create** `lib/ui/registrations/open_registration_wizard_page.dart` — target picker, template/copy seed, question editor, fee/methods/paymentMode, creates registration OPEN.
- **Create** `lib/ui/registrations/registration_submissions_page.dart` — searchable submissions, answers sheet, Paid flip.
- **Create** `lib/ui/registrations/form_template_page.dart` — edits `FormTemplates/default`.
- **Modify** `lib/router/app_router.dart` — `/registrations` route tree.
- **Modify** `lib/ui/home/master_detail_shell.dart` — drawer entry next to Sign Ups.

**FAN (`infinite_sports_flutter`):**
- **Modify** `pubspec.yaml` (+ commit `pubspec.lock`) — add `flutter_form_builder`, `form_builder_validators`, `mask_text_input_formatter`.
- **Create** `lib/registration/registration_models.dart` — byte-identical duplicate of the Manager model file.
- **Create** `test/registration_models_test.dart` — same tests (import line differs).
- **Create** `lib/registration/registration_service.dart` — static-method service: open registrations, form, my submission, `submitIndividual` (new write + legacy dual-write + profile write-back), prefill.
- **Create** `lib/registration/dynamic_form.dart` — `DynamicRegistrationForm` renderer (all 11 question types, hygiene on save, required gating).
- **Create** `test/registration_form_test.dart` — widget tests: renders each type + required gating.
- **Create** `lib/registration/registration_entry_page.dart` — lists open registrations.
- **Create** `lib/registration/registration_path_page.dart` — "How are you registering?" (Individual active; team paths disabled "coming soon").
- **Create** `lib/registration/registration_form_page.dart` — loads form + prefill, renders, submits, routes to payment/status.
- **Create** `lib/registration/payment_screen.dart` — Venmo deep link + Zelle copy tile + fee/feeNote.
- **Create** `lib/registration/registration_status_page.dart` — submission state, Paid badge, persistent "Complete payment".
- **Modify** `lib/navbar.dart` — drawer "Sign Up List" routes to the new flow when any registration is open (legacy fallback preserved).
- **Modify** `lib/frontpage.dart` — registration banner on the Matches screen.

NOT deleted: `FAN lib/signup.dart` and `FAN lib/leagueform.dart` stay — external Form-URL sign-ups (AFC style) still use them; only native league sign-ups reroute.

---

# PHASE 1 — MANAGER

## Task 1: Manager branch + pure models + tests

**Files:**
- Create: `MANAGER lib/models/registration_models.dart`
- Create: `MANAGER test/registration_models_test.dart`

- [ ] **Step 1: Create the branch**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-features`. Then:
```powershell
git checkout -b zaya-registration
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`. (If the branch already exists from a partial run, `git checkout zaya-registration` instead.)

- [ ] **Step 2: Write the failing tests**

Create `MANAGER test/registration_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/models/registration_models.dart';

void main() {
  group('RegQuestion (de)serialization', () {
    test('round-trips through toMap/fromMap', () {
      const q = RegQuestion(
        key: 'positions',
        type: 'multiChoice',
        label: 'Positions',
        isRequired: true,
        visibility: 'individual',
        options: ['Defender', 'Striker'],
        hint: 'Pick all that apply',
      );
      final parsed = RegQuestion.fromMap(q.toMap());
      expect(parsed, isNotNull);
      expect(parsed!.key, 'positions');
      expect(parsed.type, 'multiChoice');
      expect(parsed.label, 'Positions');
      expect(parsed.isRequired, isTrue);
      expect(parsed.visibility, 'individual');
      expect(parsed.options, ['Defender', 'Striker']);
      expect(parsed.hint, 'Pick all that apply');
    });

    test('toMap omits empty options/hint, stores isRequired as "required"', () {
      const q = RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name');
      final map = q.toMap();
      expect(map.containsKey('options'), isFalse);
      expect(map.containsKey('hint'), isFalse);
      expect(map['required'], isFalse);
    });

    test('fromMap rejects malformed nodes', () {
      expect(RegQuestion.fromMap(null), isNull);
      expect(RegQuestion.fromMap('garbage'), isNull);
      expect(RegQuestion.fromMap({'type': 'shortText'}), isNull); // no key
      expect(RegQuestion.fromMap({'key': 'x', 'type': 'hologram'}), isNull); // bad type
    });

    test('fromMap defaults bad visibility to all, missing label to key', () {
      final q = RegQuestion.fromMap(
          {'key': 'x', 'type': 'shortText', 'visibility': 'martians'});
      expect(q!.visibility, 'all');
      expect(q.label, 'x');
      expect(q.isRequired, isFalse);
    });
  });

  group('visibleFor', () {
    test('all is visible to every path', () {
      const q = RegQuestion(key: 'x', type: 'shortText', label: 'X');
      expect(q.visibleFor('individual'), isTrue);
      expect(q.visibleFor('captain'), isTrue);
      expect(q.visibleFor('joiner'), isTrue);
    });

    test('path-scoped question only shows on its path', () {
      const q = RegQuestion(
          key: 'x', type: 'shortText', label: 'X', visibility: 'captain');
      expect(q.visibleFor('captain'), isTrue);
      expect(q.visibleFor('individual'), isFalse);
      expect(q.visibleFor('joiner'), isFalse);
    });
  });

  group('regQuestionsFromNode / regQuestionsToList', () {
    test('parses a List node in order, skipping malformed entries', () {
      final node = [
        {'key': 'a', 'type': 'shortText', 'label': 'A'},
        'garbage',
        {'key': 'b', 'type': 'yesNo', 'label': 'B'},
      ];
      final list = regQuestionsFromNode(node);
      expect(list.map((q) => q.key).toList(), ['a', 'b']);
    });

    test('parses an index-keyed Map node in numeric order', () {
      final node = {
        '10': {'key': 'late', 'type': 'shortText', 'label': 'Late'},
        '2': {'key': 'early', 'type': 'shortText', 'label': 'Early'},
      };
      expect(regQuestionsFromNode(node).map((q) => q.key).toList(),
          ['early', 'late']);
    });

    test('null / junk gives empty list', () {
      expect(regQuestionsFromNode(null), isEmpty);
      expect(regQuestionsFromNode('x'), isEmpty);
    });

    test('default template round-trips through regQuestionsToList', () {
      final round =
          regQuestionsFromNode(regQuestionsToList(kDefaultRegQuestions.toList()));
      expect(round.length, kDefaultRegQuestions.length);
      expect(round.first.key, 'firstName');
      expect(round.last.type, 'linkAcknowledge');
    });
  });

  group('input hygiene', () {
    test('capitalizeWords uppercases the first letter of each word', () {
      expect(capitalizeWords('john doe'), 'John Doe');
      expect(capitalizeWords('mary-jane o brien'), 'Mary-jane O Brien');
      expect(capitalizeWords(''), '');
    });

    test('collapseTrailingSpaces trims and collapses whitespace runs', () {
      expect(collapseTrailingSpaces('  john   doe  '), 'john doe');
      expect(collapseTrailingSpaces('one\t two'), 'one two');
    });

    test('normalizePhone keeps digits only', () {
      expect(normalizePhone('(408) 693-9436'), '4086939436');
      expect(normalizePhone('+1 408.693.9436'), '14086939436');
    });

    test('formatPhone renders 10 and 1+10 digit numbers, passes junk through', () {
      expect(formatPhone('4086939436'), '(408) 693-9436');
      expect(formatPhone('14086939436'), '(408) 693-9436');
      expect(formatPhone('123'), '123');
      expect(formatPhone(''), '');
    });

    test('suggestKeyFromLabel camelCases labels', () {
      expect(suggestKeyFromLabel('First Name'), 'firstName');
      expect(suggestKeyFromLabel('T-Shirt  Size!'), 'tshirtSize');
      expect(suggestKeyFromLabel('  '), '');
    });

    test('cleanAnswers applies type-aware hygiene and drops nulls', () {
      final questions = [
        const RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name'),
        const RegQuestion(key: 'comment', type: 'paragraph', label: 'Comment'),
        const RegQuestion(key: 'phone', type: 'phone', label: 'Phone'),
        const RegQuestion(key: 'age', type: 'number', label: 'Age'),
        const RegQuestion(key: 'birthday', type: 'date', label: 'Birthday'),
        const RegQuestion(key: 'waiver', type: 'linkAcknowledge', label: 'Waiver'),
      ];
      final cleaned = cleanAnswers(questions, {
        'firstName': '  john   doe ',
        'comment': '  keep Case here  ',
        'phone': '(408) 693-9436',
        'age': '25',
        'birthday': DateTime(2001, 3, 7),
        'waiver': true,
        'skipped': null,
      });
      expect(cleaned['firstName'], 'John Doe');
      expect(cleaned['comment'], 'keep Case here');
      expect(cleaned['phone'], '4086939436');
      expect(cleaned['age'], 25);
      expect(cleaned['birthday'], '03/07/2001');
      expect(cleaned['waiver'], true);
      expect(cleaned.containsKey('skipped'), isFalse);
    });
  });

  group('RegistrationConfig', () {
    test('round-trips league config through toFirebaseMap/fromFirebase', () {
      const config = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        status: 'open',
        fee: 120,
        feeNote: 'Due by week 1',
        paymentMode: 'perPlayer',
        venmo: true,
        zelle: true,
        stripe: false,
        createdAt: 1750000000000,
      );
      final parsed = RegistrationConfig.fromFirebase(config.toFirebaseMap());
      expect(parsed, isNotNull);
      expect(parsed!.targetType, 'league');
      expect(parsed.sport, 'Futsal');
      expect(parsed.season, '17');
      expect(parsed.isOpen, isTrue);
      expect(parsed.fee, 120);
      expect(parsed.feeNote, 'Due by week 1');
      expect(parsed.paymentMode, 'perPlayer');
      expect(parsed.venmo, isTrue);
      expect(parsed.zelle, isTrue);
      expect(parsed.stripe, isFalse);
      expect(parsed.createdAt, 1750000000000);
      expect(parsed.label, 'Futsal Season 17');
    });

    test('round-trips tournament config; label uses tournament name', () {
      const config = RegistrationConfig(
        targetType: 'tournament',
        sport: 'Soccer',
        tournamentId: 'summer-cup-2026',
        tournamentName: 'Summer Cup',
        status: 'closed',
        fee: 250,
        paymentMode: 'teamFee',
      );
      final parsed = RegistrationConfig.fromFirebase(config.toFirebaseMap());
      expect(parsed!.tournamentId, 'summer-cup-2026');
      expect(parsed.tournamentName, 'Summer Cup');
      expect(parsed.isOpen, isFalse);
      expect(parsed.paymentMode, 'teamFee');
      expect(parsed.label, 'Summer Cup');
    });

    test('fromFirebase rejects junk and unknown target types', () {
      expect(RegistrationConfig.fromFirebase(null), isNull);
      expect(RegistrationConfig.fromFirebase('x'), isNull);
      expect(RegistrationConfig.fromFirebase({'TargetType': 'raffle'}), isNull);
    });

    test('regIds', () {
      expect(leagueRegId('Futsal', '17'), 'Futsal-17');
      expect(tournamentRegId('summer-cup'), 'T-summer-cup');
      const league = RegistrationConfig(
          targetType: 'league', sport: 'Basketball', season: '9');
      const tourney = RegistrationConfig(
          targetType: 'tournament', sport: 'Soccer', tournamentId: 'cup1');
      expect(regIdFor(league), 'Basketball-9');
      expect(regIdFor(tourney), 'T-cup1');
    });

    test('legacySignUpTarget: league keeps Sport/Season; tournament uses name/id', () {
      const league = RegistrationConfig(
          targetType: 'league', sport: 'Futsal', season: '17');
      expect(legacySignUpTarget(league), (league: 'Futsal', season: '17'));
      const tourney = RegistrationConfig(
          targetType: 'tournament',
          sport: 'Soccer',
          tournamentId: 'cup1',
          tournamentName: 'Summer Cup');
      expect(legacySignUpTarget(tourney), (league: 'Summer Cup', season: 'cup1'));
      const anon = RegistrationConfig(
          targetType: 'tournament', sport: 'Soccer', tournamentId: 'cup1');
      expect(legacySignUpTarget(anon).league, 'cup1');
    });
  });

  group('RegSubmission', () {
    test('round-trips through toFirebaseMap/fromFirebase', () {
      const sub = RegSubmission(
        path: 'individual',
        answers: {'firstName': 'John', 'positions': ['Striker']},
        paid: false,
        displayName: 'John Doe',
        submittedAt: 1750000000000,
      );
      final parsed = RegSubmission.fromFirebase(sub.toFirebaseMap());
      expect(parsed!.path, 'individual');
      expect(parsed.answers['firstName'], 'John');
      expect(parsed.paid, isFalse);
      expect(parsed.displayName, 'John Doe');
      expect(parsed.submittedAt, 1750000000000);
      expect(parsed.teamId, '');
      expect(parsed.paidVia, '');
    });

    test('fromFirebase rejects junk', () {
      expect(RegSubmission.fromFirebase(null), isNull);
      expect(RegSubmission.fromFirebase({'Answers': {}}), isNull); // no Path
    });
  });

  group('paymentOwed', () {
    const perPlayer = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 120,
        paymentMode: 'perPlayer');
    const teamFee = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 500,
        paymentMode: 'teamFee');
    const free = RegistrationConfig(
        targetType: 'league', sport: 'Futsal', season: '17', fee: 0);

    RegSubmission sub(String path, {bool paid = false}) =>
        RegSubmission(path: path, answers: const {}, paid: paid);

    test('unpaid individual owes in both modes', () {
      expect(paymentOwed(config: perPlayer, submission: sub('individual')), isTrue);
      expect(paymentOwed(config: teamFee, submission: sub('individual')), isTrue);
    });

    test('paid submission owes nothing', () {
      expect(
          paymentOwed(config: perPlayer, submission: sub('individual', paid: true)),
          isFalse);
    });

    test('zero fee owes nothing', () {
      expect(paymentOwed(config: free, submission: sub('individual')), isFalse);
    });

    test('captain owes in both modes', () {
      expect(paymentOwed(config: perPlayer, submission: sub('captain')), isTrue);
      expect(paymentOwed(config: teamFee, submission: sub('captain')), isTrue);
    });

    test('joiner follows CodeWaivesPayment', () {
      expect(
          paymentOwed(
              config: teamFee, submission: sub('joiner'), codeWaivesPayment: true),
          isFalse);
      expect(
          paymentOwed(
              config: teamFee, submission: sub('joiner'), codeWaivesPayment: false),
          isTrue);
      expect(
          paymentOwed(
              config: perPlayer, submission: sub('joiner'), codeWaivesPayment: true),
          isFalse);
    });
  });

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

- [ ] **Step 3: Run tests to verify they fail**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
flutter test test/registration_models_test.dart
```
Expected: FAIL (compile error — `registration_models.dart` does not exist).

- [ ] **Step 4: Write the implementation**

Create `MANAGER lib/models/registration_models.dart`:

```dart
/// Pure registration-engine models + helpers (Leagues epic L1, phase L1a).
///
/// NO Flutter/Firebase imports — unit-tested directly. This file is
/// intentionally DUPLICATED byte-for-byte in both repos (the apps share no
/// code; precedent: trophy/tournament models). Keep the copies identical:
///   Manager: lib/models/registration_models.dart
///   Fan:     lib/registration/registration_models.dart

// ---------------------------------------------------------------------------
// Question model
// ---------------------------------------------------------------------------

/// Every question type the dynamic form engine understands.
const List<String> kRegQuestionTypes = [
  'shortText',
  'paragraph',
  'number',
  'phone',
  'email',
  'date',
  'dropdown',
  'singleChoice',
  'multiChoice',
  'yesNo',
  'linkAcknowledge',
];

/// Types that carry an options list.
const List<String> kRegChoiceTypes = ['dropdown', 'singleChoice', 'multiChoice'];

/// Who sees a question: every path, or one specific registration path.
const List<String> kRegVisibilities = ['all', 'individual', 'captain', 'joiner'];

class RegQuestion {
  final String key; // stable id; well-known keys map to profile fields
  final String type; // one of kRegQuestionTypes
  final String label;
  final bool isRequired; // serialized under the map key 'required'
  final String visibility; // one of kRegVisibilities
  final List<String> options; // choice types only
  final String hint; // for linkAcknowledge this holds the URL to open

  const RegQuestion({
    required this.key,
    required this.type,
    required this.label,
    this.isRequired = false,
    this.visibility = 'all',
    this.options = const [],
    this.hint = '',
  });

  /// True when a registrant on [path] ('individual'|'captain'|'joiner')
  /// should see this question.
  bool visibleFor(String path) => visibility == 'all' || visibility == path;

  Map<String, dynamic> toMap() => {
        'key': key,
        'type': type,
        'label': label,
        'required': isRequired,
        'visibility': visibility,
        if (options.isNotEmpty) 'options': options,
        if (hint.isNotEmpty) 'hint': hint,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegQuestion? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key']?.toString() ?? '';
    final type = raw['type']?.toString() ?? '';
    if (key.isEmpty || !kRegQuestionTypes.contains(type)) return null;
    final rawOptions = raw['options'];
    final rawVisibility = raw['visibility']?.toString() ?? 'all';
    return RegQuestion(
      key: key,
      type: type,
      label: raw['label']?.toString() ?? key,
      isRequired: raw['required'] == true,
      visibility:
          kRegVisibilities.contains(rawVisibility) ? rawVisibility : 'all',
      options: rawOptions is List
          ? rawOptions.map((o) => o.toString()).toList()
          : const <String>[],
      hint: raw['hint']?.toString() ?? '',
    );
  }

  RegQuestion copyWith({
    String? key,
    String? type,
    String? label,
    bool? isRequired,
    String? visibility,
    List<String>? options,
    String? hint,
  }) =>
      RegQuestion(
        key: key ?? this.key,
        type: type ?? this.type,
        label: label ?? this.label,
        isRequired: isRequired ?? this.isRequired,
        visibility: visibility ?? this.visibility,
        options: options ?? this.options,
        hint: hint ?? this.hint,
      );
}

/// Parses a Form/FormTemplates node into an ordered question list. RTDB may
/// return a List OR a Map keyed by index strings; both are handled. Malformed
/// entries are skipped.
List<RegQuestion> regQuestionsFromNode(Object? raw) {
  final out = <RegQuestion>[];
  if (raw is List) {
    for (final item in raw) {
      final q = RegQuestion.fromMap(item);
      if (q != null) out.add(q);
    }
  } else if (raw is Map) {
    final entries = raw.entries.toList()
      ..sort((a, b) => (int.tryParse(a.key.toString()) ?? 0)
          .compareTo(int.tryParse(b.key.toString()) ?? 0));
    for (final e in entries) {
      final q = RegQuestion.fromMap(e.value);
      if (q != null) out.add(q);
    }
  }
  return out;
}

/// Serializes an ordered question list for a Form/FormTemplates node.
List<Map<String, dynamic>> regQuestionsToList(List<RegQuestion> questions) =>
    questions.map((q) => q.toMap()).toList();

// ---------------------------------------------------------------------------
// Input hygiene (engine-wide)
// ---------------------------------------------------------------------------

/// Uppercases the first letter of each whitespace-separated word, leaving the
/// rest of the word unchanged ("john doe" -> "John Doe").
String capitalizeWords(String input) {
  return input
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Trims and collapses every whitespace run to a single space
/// ("  a   b  " -> "a b").
String collapseTrailingSpaces(String input) =>
    input.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Keeps digits only ("(408) 693-9436" -> "4086939436"). Stored form.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

/// Displays a stored phone as (408) 693-9436. 11-digit numbers with a leading
/// 1 lose the country code; anything else is returned unchanged.
String formatPhone(String input) {
  var d = normalizePhone(input);
  if (d.length == 11 && d.startsWith('1')) d = d.substring(1);
  if (d.length != 10) return input;
  return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
}

/// Suggests a stable camelCase key from a label ("First Name" -> "firstName").
String suggestKeyFromLabel(String label) {
  final words = label
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final first = words.first.toLowerCase();
  final rest = words
      .skip(1)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase());
  return [first, ...rest].join();
}

/// Applies type-aware hygiene to raw form values before they are written:
/// shortText -> capitalize words + collapse spaces; paragraph -> collapse
/// spaces; phone -> digits only; number -> num when parseable; date
/// (DateTime) -> "MM/DD/YYYY" string. Null values are dropped. Keys without
/// a matching question pass through unchanged.
Map<String, dynamic> cleanAnswers(
    List<RegQuestion> questions, Map<String, dynamic> raw) {
  final byKey = {for (final q in questions) q.key: q};
  final out = <String, dynamic>{};
  raw.forEach((key, value) {
    if (value == null) return;
    final q = byKey[key];
    switch (q?.type) {
      case 'shortText':
        out[key] = capitalizeWords(collapseTrailingSpaces(value.toString()));
      case 'paragraph':
        out[key] = collapseTrailingSpaces(value.toString());
      case 'phone':
        out[key] = normalizePhone(value.toString());
      case 'number':
        out[key] = num.tryParse(value.toString()) ?? value.toString();
      case 'date':
        out[key] = value is DateTime
            ? '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}'
            : value.toString();
      default:
        out[key] = value;
    }
  });
  return out;
}

// ---------------------------------------------------------------------------
// Registration config
// ---------------------------------------------------------------------------

class RegistrationConfig {
  final String targetType; // 'league' | 'tournament'
  final String sport; // league sport key / tournament sport label
  final String season; // league season number as string; '' for tournament
  final String tournamentId; // '' for league targets
  final String tournamentName; // legacy dual-write bucket for tournaments
  final String status; // 'open' | 'closed'
  final num fee;
  final String feeNote;
  final String paymentMode; // 'perPlayer' | 'teamFee'
  final bool venmo;
  final bool zelle;
  final bool stripe;
  final int createdAt; // millisecondsSinceEpoch

  const RegistrationConfig({
    required this.targetType,
    required this.sport,
    this.season = '',
    this.tournamentId = '',
    this.tournamentName = '',
    this.status = 'closed',
    this.fee = 0,
    this.feeNote = '',
    this.paymentMode = 'perPlayer',
    this.venmo = true,
    this.zelle = true,
    this.stripe = false,
    this.createdAt = 0,
  });

  bool get isOpen => status == 'open';

  /// Human label, e.g. "Futsal Season 17" or the tournament's name.
  String get label => targetType == 'tournament'
      ? (tournamentName.isNotEmpty ? tournamentName : tournamentId)
      : '$sport Season $season';

  Map<String, dynamic> toFirebaseMap() => {
        'TargetType': targetType,
        'Sport': sport,
        if (season.isNotEmpty) 'Season': season,
        if (tournamentId.isNotEmpty) 'TournamentId': tournamentId,
        if (tournamentName.isNotEmpty) 'TournamentName': tournamentName,
        'Status': status,
        'Fee': fee,
        'FeeNote': feeNote,
        'PaymentMode': paymentMode,
        'Methods': {'venmo': venmo, 'zelle': zelle, 'stripe': stripe},
        'CreatedAt': createdAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegistrationConfig? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final targetType = raw['TargetType']?.toString() ?? '';
    if (targetType != 'league' && targetType != 'tournament') return null;
    final methods = raw['Methods'];
    bool method(String key, bool fallback) =>
        methods is Map ? methods[key] == true : fallback;
    return RegistrationConfig(
      targetType: targetType,
      sport: raw['Sport']?.toString() ?? '',
      season: raw['Season']?.toString() ?? '',
      tournamentId: raw['TournamentId']?.toString() ?? '',
      tournamentName: raw['TournamentName']?.toString() ?? '',
      status: raw['Status']?.toString() == 'open' ? 'open' : 'closed',
      fee: raw['Fee'] is num
          ? raw['Fee'] as num
          : num.tryParse(raw['Fee']?.toString() ?? '') ?? 0,
      feeNote: raw['FeeNote']?.toString() ?? '',
      paymentMode:
          raw['PaymentMode']?.toString() == 'teamFee' ? 'teamFee' : 'perPlayer',
      venmo: method('venmo', true),
      zelle: method('zelle', true),
      stripe: method('stripe', false),
      createdAt: int.tryParse(raw['CreatedAt']?.toString() ?? '') ?? 0,
    );
  }
}

/// regId for a league-season registration: "Futsal-17".
String leagueRegId(String sport, String season) => '$sport-$season';

/// regId for a tournament registration: "T-{tournamentId}".
String tournamentRegId(String tournamentId) => 'T-$tournamentId';

/// The regId a config lives under.
String regIdFor(RegistrationConfig c) => c.targetType == 'tournament'
    ? tournamentRegId(c.tournamentId)
    : leagueRegId(c.sport, c.season);

/// Where the legacy dual-write goes. Leagues keep the existing
/// Sign Ups/{Sport}/{Season}/... buckets; tournament targets write the
/// equivalent Sign Ups/{TournamentName}/{tournamentId}/... buckets (name
/// falls back to the id when unset).
({String league, String season}) legacySignUpTarget(RegistrationConfig c) =>
    c.targetType == 'tournament'
        ? (
            league:
                c.tournamentName.isNotEmpty ? c.tournamentName : c.tournamentId,
            season: c.tournamentId,
          )
        : (league: c.sport, season: c.season);

// ---------------------------------------------------------------------------
// Submission
// ---------------------------------------------------------------------------

class RegSubmission {
  final String path; // 'individual' | 'joiner' | 'captain'
  final Map<String, dynamic> answers;
  final String teamId; // '' until team paths land (L1b)
  final bool paid;
  final String paidVia; // '' | 'team code' | 'card' | ...
  final String displayName; // account display name at submit time
  final int submittedAt; // millisecondsSinceEpoch

  const RegSubmission({
    required this.path,
    required this.answers,
    this.teamId = '',
    this.paid = false,
    this.paidVia = '',
    this.displayName = '',
    this.submittedAt = 0,
  });

  Map<String, dynamic> toFirebaseMap() => {
        'Path': path,
        'Answers': answers,
        if (teamId.isNotEmpty) 'TeamId': teamId,
        'Paid': paid,
        if (paidVia.isNotEmpty) 'PaidVia': paidVia,
        'DisplayName': displayName,
        'SubmittedAt': submittedAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegSubmission? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['Path']?.toString() ?? '';
    if (path.isEmpty) return null;
    final rawAnswers = raw['Answers'];
    return RegSubmission(
      path: path,
      answers: rawAnswers is Map
          ? rawAnswers.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
      teamId: raw['TeamId']?.toString() ?? '',
      paid: raw['Paid'] == true,
      paidVia: raw['PaidVia']?.toString() ?? '',
      displayName: raw['DisplayName']?.toString() ?? '',
      submittedAt: int.tryParse(raw['SubmittedAt']?.toString() ?? '') ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Payment-owed logic
// ---------------------------------------------------------------------------

/// Whether this submission still owes a payment. Joiners are governed by
/// their team's CodeWaivesPayment flag (L1b passes it in; L1a's individual
/// path never sets it). Captains and individuals owe in both payment modes —
/// in teamFee mode an individual is not covered by any team's fee until an
/// admin moves them onto one.
bool paymentOwed({
  required RegistrationConfig config,
  required RegSubmission submission,
  bool codeWaivesPayment = false,
}) {
  if (submission.paid) return false;
  if (config.fee <= 0) return false;
  if (submission.path == 'joiner') return !codeWaivesPayment;
  return true;
}

// ---------------------------------------------------------------------------
// Profile mapping (well-known keys)
// ---------------------------------------------------------------------------

/// The Users/{uid}/Information field that holds positions for a sport.
/// '' means "don't write positions back" (unknown sport).
String positionsFieldForSport(String sport) {
  switch (sport) {
    case 'Basketball':
      return 'BasketballPosition';
    case 'Flag Football':
      return 'FlagFootballPosition';
    case 'Futsal':
    case 'Soccer':
      return 'FutsalPosition';
    default:
      return '';
  }
}

// ---------------------------------------------------------------------------
// Default template (seed when FormTemplates/default is empty)
// ---------------------------------------------------------------------------

const List<RegQuestion> kDefaultRegQuestions = [
  RegQuestion(
      key: 'firstName', type: 'shortText', label: 'First Name', isRequired: true),
  RegQuestion(
      key: 'lastName', type: 'shortText', label: 'Last Name', isRequired: true),
  RegQuestion(
      key: 'phone', type: 'phone', label: 'Phone Number', isRequired: true),
  RegQuestion(key: 'age', type: 'number', label: 'Age', isRequired: true),
  RegQuestion(
      key: 'height',
      type: 'shortText',
      label: "Height (e.g. 5'10)",
      isRequired: true),
  RegQuestion(
    key: 'positions',
    type: 'multiChoice',
    label: 'Positions',
    isRequired: true,
    options: ['Goal Keeper', 'Defender', 'Midfielder', 'Striker'],
  ),
  RegQuestion(key: 'comment', type: 'paragraph', label: 'Comment (optional)'),
  RegQuestion(
      key: 'rules',
      type: 'linkAcknowledge',
      label: 'Season Rules',
      isRequired: true),
  RegQuestion(
      key: 'waiver',
      type: 'linkAcknowledge',
      label: 'Waiver Conditions',
      isRequired: true),
];
```

- [ ] **Step 5: Run tests to verify they pass**

```powershell
flutter test test/registration_models_test.dart
```
Expected: PASS (all tests in the file). Then:
```powershell
flutter analyze lib/models/registration_models.dart test/registration_models_test.dart
```
Expected: No issues found.

- [ ] **Step 6: Commit**

```powershell
git add lib/models/registration_models.dart test/registration_models_test.dart
git commit -m "feat(registration): pure question/config/submission models + hygiene helpers + tests"
```

---

## Task 2: Manager RTDB paths + RegistrationService + providers

**Files:**
- Modify: `MANAGER lib/core/constants/firebase_paths.dart`
- Create: `MANAGER lib/services/firebase/registration_service.dart`
- Create: `MANAGER lib/providers/registration_provider.dart`

All additive — no existing caller changes, so the build stays green.

- [ ] **Step 1: Add the path helpers**

In `MANAGER lib/core/constants/firebase_paths.dart`, the class currently ends with (lines 157-160):

```dart
  static String userAwards(String uid) => '$users/$uid/Awards';
  static String userAward(String uid, String awardId) =>
      '$users/$uid/Awards/$awardId';
}
```

Replace that exact block with:

```dart
  static String userAwards(String uid) => '$users/$uid/Awards';
  static String userAward(String uid, String awardId) =>
      '$users/$uid/Awards/$awardId';

  // -------- Registrations (registration redesign L1) --------
  static const String registrations = 'Registrations';
  static const String formTemplates = 'FormTemplates';

  static String registration(String regId) => '$registrations/$regId';
  static String registrationConfig(String regId) =>
      '$registrations/$regId/Config';
  static String registrationStatus(String regId) =>
      '$registrations/$regId/Config/Status';
  static String registrationForm(String regId) => '$registrations/$regId/Form';
  static String registrationSubmissions(String regId) =>
      '$registrations/$regId/Submissions';
  static String registrationSubmission(String regId, String uid) =>
      '$registrations/$regId/Submissions/$uid';
  static String registrationSubmissionPaid(String regId, String uid) =>
      '$registrations/$regId/Submissions/$uid/Paid';
  static String registrationTeams(String regId) =>
      '$registrations/$regId/Teams';
  static String registrationTeam(String regId, String teamId) =>
      '$registrations/$regId/Teams/$teamId';
  static String formTemplate(String id) => '$formTemplates/$id';
}
```

(`registrationTeams`/`registrationTeam` have no L1a caller — they pin the schema for L1b.)

- [ ] **Step 2: Create the service**

Create `MANAGER lib/services/firebase/registration_service.dart`:

```dart
import 'package:infinite_app_manager/core/constants/firebase_paths.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/services/firebase/firebase_service.dart';
import 'package:infinite_app_manager/services/firebase/sign_up_service.dart';

/// CRUD for the new Registrations/FormTemplates schema. Mark-Paid also moves
/// the legacy Sign Ups entry (via SignUpService) so the existing Sign Ups
/// page and the Add-from-signups roster picker keep working unchanged.
class RegistrationService extends FirebaseService {
  final SignUpService _signUps = SignUpService();

  /// Writes Config + Form. Submissions (if any) are untouched.
  Future<void> createRegistration(String regId, RegistrationConfig config,
      List<RegQuestion> form) async {
    await ref(FirebasePaths.registrationConfig(regId))
        .set(config.toFirebaseMap());
    await ref(FirebasePaths.registrationForm(regId))
        .set(regQuestionsToList(form));
  }

  Future<void> setStatus(String regId, bool open) async {
    await ref(FirebasePaths.registrationStatus(regId))
        .set(open ? 'open' : 'closed');
  }

  Future<RegistrationConfig?> getConfig(String regId) async {
    final map = await getMap(FirebasePaths.registrationConfig(regId));
    return RegistrationConfig.fromFirebase(map);
  }

  /// {regId: config} for every registration, newest first.
  Future<Map<String, RegistrationConfig>> getAll() async {
    final root = await getMap(FirebasePaths.registrations);
    final out = <String, RegistrationConfig>{};
    root.forEach((regId, value) {
      if (value is! Map) return;
      final config = RegistrationConfig.fromFirebase(value['Config']);
      if (config != null) out[regId] = config;
    });
    final entries = out.entries.toList()
      ..sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
    return Map.fromEntries(entries);
  }

  Future<List<RegQuestion>> getForm(String regId) async {
    final snapshot = await ref(FirebasePaths.registrationForm(regId)).get();
    return regQuestionsFromNode(snapshot.value);
  }

  Future<List<RegQuestion>> getTemplate(String id) async {
    final snapshot = await ref(FirebasePaths.formTemplate(id)).get();
    return regQuestionsFromNode(snapshot.value);
  }

  Future<void> saveTemplate(String id, List<RegQuestion> form) async {
    await ref(FirebasePaths.formTemplate(id)).set(regQuestionsToList(form));
  }

  /// {uid: submission}, malformed entries skipped.
  Future<Map<String, RegSubmission>> getSubmissions(String regId) async {
    final map = await getMap(FirebasePaths.registrationSubmissions(regId));
    final out = <String, RegSubmission>{};
    map.forEach((uid, value) {
      final sub = RegSubmission.fromFirebase(value);
      if (sub != null) out[uid] = sub;
    });
    return out;
  }

  /// Flips Paid on the new node AND moves the legacy Sign Ups entry
  /// (NotPaid <-> Paid) so every legacy consumer stays correct. League
  /// targets sync Sign Ups/{Sport}/{Season}/...; tournament targets sync
  /// Sign Ups/{TournamentName}/{tournamentId}/... equivalently.
  Future<void> markPaid(String regId, String uid, bool paid) async {
    await ref(FirebasePaths.registrationSubmissionPaid(regId, uid)).set(paid);
    final config = await getConfig(regId);
    if (config == null) return;
    final subMap =
        await getMap(FirebasePaths.registrationSubmission(regId, uid));
    final sub = RegSubmission.fromFirebase(subMap);
    final name =
        (sub != null && sub.displayName.isNotEmpty) ? sub.displayName : uid;
    final target = legacySignUpTarget(config);
    if (paid) {
      await _signUps.moveToPaid(uid, name, target.league, target.season);
    } else {
      await _signUps.moveToNotPaid(uid, name, target.league, target.season);
    }
  }
}
```

- [ ] **Step 3: Create the providers**

Create `MANAGER lib/providers/registration_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/services/firebase/registration_service.dart';

final registrationServiceProvider =
    Provider<RegistrationService>((ref) => RegistrationService());

/// {regId: config} for every registration, newest first.
final registrationListProvider =
    FutureProvider<Map<String, RegistrationConfig>>((ref) {
  return ref.watch(registrationServiceProvider).getAll();
});

final registrationConfigProvider =
    FutureProvider.family<RegistrationConfig?, String>((ref, regId) {
  return ref.watch(registrationServiceProvider).getConfig(regId);
});

final registrationFormProvider =
    FutureProvider.family<List<RegQuestion>, String>((ref, regId) {
  return ref.watch(registrationServiceProvider).getForm(regId);
});

final registrationSubmissionsProvider =
    FutureProvider.family<Map<String, RegSubmission>, String>((ref, regId) {
  return ref.watch(registrationServiceProvider).getSubmissions(regId);
});

final formTemplateProvider =
    FutureProvider.family<List<RegQuestion>, String>((ref, id) {
  return ref.watch(registrationServiceProvider).getTemplate(id);
});

/// Call after a write that changes the registration list.
void refreshRegistrations(WidgetRef ref) {
  ref.invalidate(registrationListProvider);
}
```

- [ ] **Step 4: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/core/constants/firebase_paths.dart lib/services/firebase/registration_service.dart lib/providers/registration_provider.dart
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All tests pass (previous total + Task 1's).

- [ ] **Step 5: Commit**

```powershell
git add lib/core/constants/firebase_paths.dart lib/services/firebase/registration_service.dart lib/providers/registration_provider.dart
git commit -m "feat(registration): RTDB paths + RegistrationService (legacy Sign Ups sync) + providers"
```

---

## Task 3: Manager question editor widget

**Files:**
- Create: `MANAGER lib/ui/registrations/widgets/question_list_editor.dart`

Shared by the template editor (Task 5) and the wizard (Task 4). Additive (no caller yet) — green. Dialog style matches `_TrophyEditorDialog` in `lib/ui/trophies/trophy_catalog_page.dart` (InputDecorator + DropdownButton, NOT DropdownButtonFormField/RadioListTile — those carry deprecation warnings on current Flutter).

- [ ] **Step 1: Create the file**

Create `MANAGER lib/ui/registrations/widgets/question_list_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_app_manager/models/registration_models.dart';

/// Friendly names for the question-type dropdown.
const Map<String, String> kRegTypeLabels = {
  'shortText': 'Short text',
  'paragraph': 'Paragraph',
  'number': 'Number',
  'phone': 'Phone',
  'email': 'Email',
  'date': 'Date',
  'dropdown': 'Dropdown',
  'singleChoice': 'Single choice',
  'multiChoice': 'Multiple choice',
  'yesNo': 'Yes / No',
  'linkAcknowledge': 'Link acknowledge (rules/waiver)',
};

/// Friendly names for the visibility dropdown.
const Map<String, String> kRegVisibilityLabels = {
  'all': 'Everyone',
  'individual': 'Individual only',
  'captain': 'Captain only',
  'joiner': 'Joiner only',
};

/// Drag-reorderable question list with add/edit/delete. Shared by the
/// template editor and the open-registration wizard. The caller owns the
/// list; every change comes back through [onChanged].
class QuestionListEditor extends StatelessWidget {
  final List<RegQuestion> questions;
  final ValueChanged<List<RegQuestion>> onChanged;

  const QuestionListEditor({
    super.key,
    required this.questions,
    required this.onChanged,
  });

  Future<void> _add(BuildContext context) async {
    final q = await showDialog<RegQuestion>(
      context: context,
      builder: (ctx) => const _QuestionEditorDialog(),
    );
    if (q == null) return;
    onChanged([...questions, q]);
  }

  Future<void> _edit(BuildContext context, int index) async {
    final q = await showDialog<RegQuestion>(
      context: context,
      builder: (ctx) => _QuestionEditorDialog(existing: questions[index]),
    );
    if (q == null) return;
    final next = [...questions];
    next[index] = q;
    onChanged(next);
  }

  Future<void> _delete(BuildContext context, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete question?'),
        content: Text('Remove "${questions[index].label}" from the form?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final next = [...questions]..removeAt(index);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (questions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No questions yet — add one below.',
                textAlign: TextAlign.center),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              final next = [...questions];
              if (newIndex > oldIndex) newIndex -= 1;
              final item = next.removeAt(oldIndex);
              next.insert(newIndex, item);
              onChanged(next);
            },
            children: [
              for (int i = 0; i < questions.length; i++)
                ListTile(
                  key: ObjectKey(questions[i]),
                  title: Text(questions[i].label),
                  subtitle: Text([
                    kRegTypeLabels[questions[i].type] ?? questions[i].type,
                    if (questions[i].isRequired) 'required',
                    if (questions[i].visibility != 'all')
                      kRegVisibilityLabels[questions[i].visibility] ??
                          questions[i].visibility,
                  ].join(' · ')),
                  onTap: () => _edit(context, i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Delete',
                        onPressed: () => _delete(context, i),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        OutlinedButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: const Text('Add question'),
        ),
      ],
    );
  }
}

class _QuestionEditorDialog extends StatefulWidget {
  final RegQuestion? existing;
  const _QuestionEditorDialog({this.existing});

  @override
  State<_QuestionEditorDialog> createState() => _QuestionEditorDialogState();
}

class _QuestionEditorDialogState extends State<_QuestionEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _keyController;
  late final TextEditingController _optionsController;
  late final TextEditingController _hintController;
  late String _type;
  late bool _isRequired;
  late String _visibility;
  bool _keyEdited = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelController = TextEditingController(text: e?.label ?? '');
    _keyController = TextEditingController(text: e?.key ?? '');
    _optionsController =
        TextEditingController(text: e?.options.join('\n') ?? '');
    _hintController = TextEditingController(text: e?.hint ?? '');
    _type = e?.type ?? 'shortText';
    _isRequired = e?.isRequired ?? false;
    _visibility = e?.visibility ?? 'all';
    _keyEdited = e != null; // editing keeps the existing key stable
  }

  @override
  void dispose() {
    _labelController.dispose();
    _keyController.dispose();
    _optionsController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelController.text.trim();
    final key = _keyController.text.trim();
    if (label.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Label and key are required.')),
      );
      return;
    }
    final options = _optionsController.text
        .split('\n')
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    if (kRegChoiceTypes.contains(_type) && options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choice questions need at least one option.')),
      );
      return;
    }
    Navigator.pop(
      context,
      RegQuestion(
        key: key,
        type: _type,
        label: label,
        isRequired: _isRequired,
        visibility: _visibility,
        options: kRegChoiceTypes.contains(_type) ? options : const [],
        hint: _hintController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isChoice = kRegChoiceTypes.contains(_type);
    final isLink = _type == 'linkAcknowledge';
    return AlertDialog(
      title: Text(isEdit ? 'Edit Question' : 'Add Question'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(labelText: 'Label'),
              onChanged: (value) {
                if (!_keyEdited) {
                  _keyController.text = suggestKeyFromLabel(value);
                }
              },
            ),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Key (stable id, e.g. firstName)',
                helperText:
                    'Known keys (firstName, lastName, phone, positions, age, height) pre-fill from and write back to the player profile',
                helperMaxLines: 3,
              ),
              onChanged: (_) => _keyEdited = true,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _type,
                  isExpanded: true,
                  items: kRegQuestionTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(kRegTypeLabels[t] ?? t),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? 'shortText'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Visible to',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _visibility,
                  isExpanded: true,
                  items: kRegVisibilities
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(kRegVisibilityLabels[v] ?? v),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _visibility = v ?? 'all'),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Required'),
              value: _isRequired,
              onChanged: (v) => setState(() => _isRequired = v),
            ),
            if (isChoice)
              TextField(
                controller: _optionsController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Options (one per line)',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _hintController,
              decoration: InputDecoration(
                labelText: isLink
                    ? 'Link URL (must be opened before the box checks)'
                    : 'Hint (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(isEdit ? 'Save' : 'Add')),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/ui/registrations/widgets/question_list_editor.dart
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All pass.

- [ ] **Step 3: Commit**

```powershell
git add lib/ui/registrations/widgets/question_list_editor.dart
git commit -m "feat(registration): drag-reorder question editor widget"
```

---

## Task 4: Manager Registration Hub — list page + wizard + route + nav entry

**Files:**
- Create: `MANAGER lib/ui/registrations/registrations_page.dart`
- Create: `MANAGER lib/ui/registrations/open_registration_wizard_page.dart`
- Modify: `MANAGER lib/router/app_router.dart`
- Modify: `MANAGER lib/ui/home/master_detail_shell.dart`

Note: the list page's tap-through (`/registrations/:regId`) and the Template button (`/registrations/template`) route to pages that land in Task 5 — those two routes are registered there. Everything in this task compiles green; only those two taps are dead until Task 5.

- [ ] **Step 1: Create the hub list page**

Create `MANAGER lib/ui/registrations/registrations_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';

class RegistrationsPage extends ConsumerWidget {
  const RegistrationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(registrationListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrations'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/registrations/template'),
            icon: const Icon(Icons.description),
            label: const Text('Template'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/registrations/new'),
        icon: const Icon(Icons.add),
        label: const Text('Open registration'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (regs) {
          if (regs.isEmpty) {
            return const Center(
                child:
                    Text('No registrations yet. Tap "Open registration".'));
          }
          final entries = regs.entries.toList();
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final regId = entries[i].key;
              final config = entries[i].value;
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: Chip(
                    label: Text(config.isOpen ? 'OPEN' : 'CLOSED'),
                    backgroundColor: config.isOpen
                        ? Colors.green.shade100
                        : Colors.grey.shade300,
                  ),
                  title: Text(config.label),
                  subtitle: Text(
                      'Fee \$${config.fee} · ${config.paymentMode == 'teamFee' ? 'Team fee' : 'Per player'}'),
                  trailing: Switch(
                    value: config.isOpen,
                    onChanged: (open) async {
                      await ref
                          .read(registrationServiceProvider)
                          .setStatus(regId, open);
                      refreshRegistrations(ref);
                    },
                  ),
                  onTap: () => context
                      .go('/registrations/${Uri.encodeComponent(regId)}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Create the wizard page**

Create `MANAGER lib/ui/registrations/open_registration_wizard_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/core/constants/sport_type.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/league_provider.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';
import 'package:infinite_app_manager/ui/registrations/widgets/question_list_editor.dart';

/// "Open registration" wizard: pick target -> tweak questions (seeded from
/// FormTemplates/default or copied from a past registration) -> fee/methods/
/// payment mode -> creates the registration with Status open.
class OpenRegistrationWizardPage extends ConsumerStatefulWidget {
  const OpenRegistrationWizardPage({super.key});

  @override
  ConsumerState<OpenRegistrationWizardPage> createState() =>
      _OpenRegistrationWizardPageState();
}

class _OpenRegistrationWizardPageState
    extends ConsumerState<OpenRegistrationWizardPage> {
  String _targetType = 'league';
  SportType _sport = SportType.futsal;
  int? _nextSeason;
  String? _tournamentId;
  List<RegQuestion> _questions = [];
  bool _seeded = false;
  final _feeController = TextEditingController();
  final _feeNoteController = TextEditingController();
  bool _venmo = true;
  bool _zelle = true;
  String _paymentMode = 'perPlayer';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSeed();
    _loadNextSeason();
  }

  @override
  void dispose() {
    _feeController.dispose();
    _feeNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadSeed() async {
    final template =
        await ref.read(registrationServiceProvider).getTemplate('default');
    if (!mounted) return;
    setState(() {
      _questions = template.isNotEmpty ? template : [...kDefaultRegQuestions];
      _seeded = true;
    });
  }

  Future<void> _loadNextSeason() async {
    final publicSeason =
        await ref.read(seasonServiceProvider).getPublicSeason(_sport);
    if (!mounted) return;
    setState(() => _nextSeason = publicSeason + 1);
  }

  Future<void> _copyLastRegistration() async {
    final regs = await ref.read(registrationServiceProvider).getAll();
    if (!mounted) return;
    if (regs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous registrations to copy.')));
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Copy questions from'),
        children: [
          for (final e in regs.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value.label),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final form = await ref.read(registrationServiceProvider).getForm(picked);
    if (!mounted) return;
    if (form.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That registration has no saved form.')));
      return;
    }
    setState(() => _questions = form);
  }

  String? get _regId {
    if (_targetType == 'league') {
      if (_nextSeason == null) return null;
      return leagueRegId(_sport.firebaseKey, _nextSeason.toString());
    }
    if (_tournamentId == null) return null;
    return tournamentRegId(_tournamentId!);
  }

  Future<void> _open() async {
    final regId = _regId;
    if (regId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a target competition first.')));
      return;
    }
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one question.')));
      return;
    }
    final feeText = _feeController.text.trim();
    final fee = num.tryParse(feeText.isEmpty ? '0' : feeText);
    if (fee == null || fee < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid fee (0 = free).')));
      return;
    }
    if (fee > 0 && !_venmo && !_zelle) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Enable at least one payment method for a paid registration.')));
      return;
    }
    final service = ref.read(registrationServiceProvider);
    final existing = await service.getConfig(regId);
    if (!mounted) return;
    if (existing != null) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registration already exists'),
          content: Text(
              'A registration for ${existing.label} already exists. Overwrite its config and form? Submissions are kept.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Overwrite')),
          ],
        ),
      );
      if (overwrite != true) return;
      if (!mounted) return;
    }
    String sportLabel = _sport.firebaseKey;
    String tournamentName = '';
    if (_targetType == 'tournament') {
      final tournaments = ref.read(tournamentListProvider).valueOrNull ?? [];
      final matches =
          tournaments.where((t) => t.id == _tournamentId).toList();
      sportLabel = matches.isNotEmpty ? matches.first.sport : '';
      tournamentName =
          matches.isNotEmpty ? matches.first.name : _tournamentId!;
    }
    setState(() => _saving = true);
    final config = RegistrationConfig(
      targetType: _targetType,
      sport: sportLabel,
      season: _targetType == 'league' ? _nextSeason.toString() : '',
      tournamentId: _targetType == 'tournament' ? _tournamentId! : '',
      tournamentName: tournamentName,
      status: 'open',
      fee: fee,
      feeNote: _feeNoteController.text.trim(),
      paymentMode: _paymentMode,
      venmo: _venmo,
      zelle: _zelle,
      stripe: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await service.createRegistration(regId, config, _questions);
      refreshRegistrations(ref);
      ref.invalidate(registrationConfigProvider(regId));
      ref.invalidate(registrationFormProvider(regId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${config.label} registration is OPEN.')));
        context.go('/registrations');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to open: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournamentsAsync = ref.watch(tournamentListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Open Registration')),
      body: !_seeded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Target competition',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  ChoiceChip(
                    label: const Text('League (next season)'),
                    selected: _targetType == 'league',
                    onSelected: (_) => setState(() => _targetType = 'league'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Tournament'),
                    selected: _targetType == 'tournament',
                    onSelected: (_) =>
                        setState(() => _targetType = 'tournament'),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_targetType == 'league') ...[
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Sport',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<SportType>(
                        value: _sport,
                        isExpanded: true,
                        items: SportType.values
                            .map((s) => DropdownMenuItem(
                                value: s, child: Text(s.firebaseKey)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _sport = v;
                            _nextSeason = null;
                          });
                          _loadNextSeason();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_nextSeason == null
                      ? 'Loading next season...'
                      : 'Opens ${_sport.firebaseKey} Season $_nextSeason (current public season + 1).'),
                ] else ...[
                  tournamentsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error loading tournaments: $e'),
                    data: (tournaments) {
                      if (tournaments.isEmpty) {
                        return const Text('No tournaments found.');
                      }
                      return InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tournament',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _tournamentId,
                            isExpanded: true,
                            hint: const Text('Pick a tournament'),
                            items: tournaments
                                .map((t) => DropdownMenuItem(
                                      value: t.id,
                                      child:
                                          Text('${t.name} ${t.edition}'.trim()),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _tournamentId = v),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                        child: Text('Form questions',
                            style: Theme.of(context).textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: _copyLastRegistration,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy last registration'),
                    ),
                  ],
                ),
                QuestionListEditor(
                  questions: _questions,
                  onChanged: (qs) => setState(() => _questions = qs),
                ),
                const Divider(height: 32),
                Text('Payment',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _feeController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fee',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _feeNoteController,
                  decoration: const InputDecoration(
                    labelText: 'Fee note (e.g. "Due by the first game")',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Venmo'),
                  value: _venmo,
                  onChanged: (v) => setState(() => _venmo = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Zelle'),
                  value: _zelle,
                  onChanged: (v) => setState(() => _zelle = v),
                ),
                const SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Card (Stripe)'),
                  subtitle: Text('Coming soon — lands with phase L1c'),
                  value: false,
                  onChanged: null,
                ),
                const SizedBox(height: 8),
                Text('Payment mode',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Row(children: [
                  ChoiceChip(
                    label: const Text('Per player'),
                    selected: _paymentMode == 'perPlayer',
                    onSelected: (_) =>
                        setState(() => _paymentMode = 'perPlayer'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Team fee'),
                    selected: _paymentMode == 'teamFee',
                    onSelected: (_) =>
                        setState(() => _paymentMode = 'teamFee'),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  _paymentMode == 'perPlayer'
                      ? 'Every registrant owes the fee.'
                      : 'The team captain owes the fee; players joining with a code follow its waive rule (L1b).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _open,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Open registration'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
```

- [ ] **Step 3: Register the routes**

In `MANAGER lib/router/app_router.dart`, add these two imports after the line `import 'package:infinite_app_manager/ui/notifications/notification_page.dart';`:

```dart
import 'package:infinite_app_manager/ui/registrations/open_registration_wizard_page.dart';
import 'package:infinite_app_manager/ui/registrations/registrations_page.dart';
```

Then find (lines 117-120):

```dart
          GoRoute(
            path: '/signups',
            builder: (context, state) => const SignUpsPage(),
          ),
```

and replace with:

```dart
          GoRoute(
            path: '/signups',
            builder: (context, state) => const SignUpsPage(),
          ),
          GoRoute(
            path: '/registrations',
            builder: (context, state) => const RegistrationsPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const OpenRegistrationWizardPage(),
              ),
            ],
          ),
```

- [ ] **Step 4: Add the drawer entry**

In `MANAGER lib/ui/home/master_detail_shell.dart`, find (lines 71-76):

```dart
            _DrawerItem(
              icon: Icons.how_to_reg,
              label: 'Sign Ups',
              color: AppColors.signUps,
              onTap: () => _navigate(context, '/signups'),
            ),
```

and replace with:

```dart
            _DrawerItem(
              icon: Icons.how_to_reg,
              label: 'Sign Ups',
              color: AppColors.signUps,
              onTap: () => _navigate(context, '/signups'),
            ),
            _DrawerItem(
              icon: Icons.app_registration,
              label: 'Registrations',
              color: AppColors.signUps,
              onTap: () => _navigate(context, '/registrations'),
            ),
```

- [ ] **Step 5: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/ui/registrations lib/router/app_router.dart lib/ui/home/master_detail_shell.dart
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/registrations/registrations_page.dart lib/ui/registrations/open_registration_wizard_page.dart lib/router/app_router.dart lib/ui/home/master_detail_shell.dart
git commit -m "feat(registration): Registration Hub list + open-registration wizard + route/nav"
```

---

## Task 5: Manager submissions page + template editor page

**Files:**
- Create: `MANAGER lib/ui/registrations/registration_submissions_page.dart`
- Create: `MANAGER lib/ui/registrations/form_template_page.dart`
- Modify: `MANAGER lib/router/app_router.dart`

- [ ] **Step 1: Create the submissions page**

Create `MANAGER lib/ui/registrations/registration_submissions_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:intl/intl.dart';

/// Searchable submissions list for one registration: tap for the answers
/// detail sheet, flip Paid/Not-Paid (markPaid also moves the legacy
/// Sign Ups entry).
class RegistrationSubmissionsPage extends ConsumerStatefulWidget {
  final String regId;
  const RegistrationSubmissionsPage({super.key, required this.regId});

  @override
  ConsumerState<RegistrationSubmissionsPage> createState() =>
      _RegistrationSubmissionsPageState();
}

class _RegistrationSubmissionsPageState
    extends ConsumerState<RegistrationSubmissionsPage> {
  String _query = '';

  String _displayValue(RegQuestion? q, Object? value) {
    if (value is List) return value.map((v) => v.toString()).join(', ');
    if (value is bool) return value ? 'Yes' : 'No';
    if (q?.type == 'phone') return formatPhone(value?.toString() ?? '');
    return value?.toString() ?? '';
  }

  void _showAnswers(String uid, RegSubmission sub, List<RegQuestion> form) {
    final byKey = {for (final q in form) q.key: q};
    final orderedKeys = [
      ...form.map((q) => q.key).where(sub.answers.containsKey),
      ...sub.answers.keys.where((k) => !byKey.containsKey(k)),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Text(
                sub.displayName.isNotEmpty ? sub.displayName : uid,
                style: Theme.of(ctx).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(registrationConfigProvider(widget.regId));
    final subsAsync =
        ref.watch(registrationSubmissionsProvider(widget.regId));
    final formAsync = ref.watch(registrationFormProvider(widget.regId));
    final title = configAsync.valueOrNull?.label ?? widget.regId;

    return Scaffold(
      appBar: AppBar(title: Text('Submissions — $title')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or answer',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: subsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (subs) {
                final form = formAsync.valueOrNull ?? const <RegQuestion>[];
                final entries = subs.entries.where((e) {
                  if (_query.isEmpty) return true;
                  final name = e.value.displayName.toLowerCase();
                  final answerText = e.value.answers.values
                      .map((v) => v.toString().toLowerCase())
                      .join(' ');
                  return name.contains(_query) || answerText.contains(_query);
                }).toList()
                  ..sort((a, b) => a.value.displayName
                      .toLowerCase()
                      .compareTo(b.value.displayName.toLowerCase()));
                if (entries.isEmpty) {
                  return const Center(child: Text('No submissions yet.'));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final uid = entries[i].key;
                    final sub = entries[i].value;
                    final when = sub.submittedAt > 0
                        ? DateFormat('MM/dd/yyyy').format(
                            DateTime.fromMillisecondsSinceEpoch(
                                sub.submittedAt))
                        : '';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        title: Text(sub.displayName.isNotEmpty
                            ? sub.displayName
                            : uid),
                        subtitle: Text(
                            [sub.path, if (when.isNotEmpty) when].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sub.paid ? 'Paid' : 'Not paid',
                              style: TextStyle(
                                color:
                                    sub.paid ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Switch(
                              value: sub.paid,
                              onChanged: (v) async {
                                await ref
                                    .read(registrationServiceProvider)
                                    .markPaid(widget.regId, uid, v);
                                ref.invalidate(
                                    registrationSubmissionsProvider(
                                        widget.regId));
                              },
                            ),
                          ],
                        ),
                        onTap: () => _showAnswers(uid, sub, form),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create the template editor page**

Create `MANAGER lib/ui/registrations/form_template_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/registration_models.dart';
import 'package:infinite_app_manager/providers/registration_provider.dart';
import 'package:infinite_app_manager/ui/registrations/widgets/question_list_editor.dart';

/// Maintains FormTemplates/default — the question list every new
/// registration starts from.
class FormTemplatePage extends ConsumerStatefulWidget {
  const FormTemplatePage({super.key});

  @override
  ConsumerState<FormTemplatePage> createState() => _FormTemplatePageState();
}

class _FormTemplatePageState extends ConsumerState<FormTemplatePage> {
  List<RegQuestion>? _questions;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(registrationServiceProvider)
          .saveTemplate('default', _questions!);
      ref.invalidate(formTemplateProvider('default'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templateAsync = ref.watch(formTemplateProvider('default'));
    return Scaffold(
      appBar: AppBar(title: const Text('Form Template')),
      body: templateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (template) {
          _questions ??=
              template.isNotEmpty ? template : [...kDefaultRegQuestions];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Every new registration starts from these questions.'),
              const SizedBox(height: 12),
              QuestionListEditor(
                questions: _questions!,
                onChanged: (qs) => setState(() => _questions = qs),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save template'),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Register the remaining routes**

In `MANAGER lib/router/app_router.dart`, add these two imports after the line `import 'package:infinite_app_manager/ui/registrations/open_registration_wizard_page.dart';` (added in Task 4):

```dart
import 'package:infinite_app_manager/ui/registrations/form_template_page.dart';
import 'package:infinite_app_manager/ui/registrations/registration_submissions_page.dart';
```

Then find the block added in Task 4:

```dart
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const OpenRegistrationWizardPage(),
              ),
            ],
          ),
```

and replace with (static routes MUST stay declared before the `:regId` parameter route):

```dart
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const OpenRegistrationWizardPage(),
              ),
              GoRoute(
                path: 'template',
                builder: (context, state) => const FormTemplatePage(),
              ),
              GoRoute(
                path: ':regId',
                builder: (context, state) {
                  final regId = state.pathParameters['regId']!;
                  return RegistrationSubmissionsPage(regId: regId);
                },
              ),
            ],
          ),
```

(go_router percent-decodes path parameters, so the `Uri.encodeComponent(regId)` from the list page round-trips regIds containing spaces, e.g. `Flag Football-9`.)

- [ ] **Step 4: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/ui/registrations lib/router/app_router.dart
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/registrations/registration_submissions_page.dart lib/ui/registrations/form_template_page.dart lib/router/app_router.dart
git commit -m "feat(registration): submissions view (Paid flip + legacy sync) + template editor"
```

---

## Task 6: Manager full verify + build/install

**Files:** none (verification only). No commit.

- [ ] **Step 1: Full analyze**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
flutter analyze
```
Expected: No NEW issues beyond the pre-existing baseline (compare against `git stash`-free `zaya-features` if unsure). Zero errors/warnings in any file touched by Tasks 1-5.

- [ ] **Step 2: Full test run**

```powershell
flutter test
```
Expected: All tests pass (previous suite + `registration_models_test.dart`).

- [ ] **Step 3: Build + install to the phone (ONE app at a time)**

Ensure no other Flutter/Gradle build is running, then:

```powershell
flutter build apk --debug
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s GN434J02403404RL install -r "build\app\outputs\flutter-apk\app-debug.apk"
```
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk` then `Success`.

- [ ] **Step 4: Smoke check on device (Manager)**

Drawer → Registrations → Template loads (seeds the 9 default questions) → Open registration → League + Futsal shows "Season N+1" → add/edit/reorder/delete a question works → set Fee 1, venmo+zelle on, Per player → Open → list shows the OPEN chip → Status switch flips to CLOSED and back → tap the registration → empty submissions list ("No submissions yet."). Delete the test registration from the Firebase console afterwards OR leave it for the fan-side end-to-end test in Task 13 (recommended: leave it OPEN).

---

# PHASE 2 — FAN

## Task 7: Fan branch check + pubspec deps + pure models + tests

**Files:**
- Modify: `FAN pubspec.yaml` (and commit the regenerated `pubspec.lock`)
- Create: `FAN lib/registration/registration_models.dart`
- Create: `FAN test/registration_models_test.dart`

- [ ] **Step 1: Verify the branch**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration` (already checked out — do NOT create it).

- [ ] **Step 2: Add the form packages to pubspec.yaml**

In `FAN pubspec.yaml`, find (lines 68-69, end of the dependencies block):

```yaml
  font_awesome_flutter: ^11.0.0
  cached_network_image: ^3.4.1
```

and replace with:

```yaml
  font_awesome_flutter: ^11.0.0
  cached_network_image: ^3.4.1
  flutter_form_builder: ^10.2.0
  form_builder_validators: ^11.2.0
  mask_text_input_formatter: ^2.9.0
```

Version rationale: the repo's environment is `sdk: '>=3.3.4 <4.0.0'` and the installed toolchain resolves at Dart >=3.11 / Flutter >=3.38 (see `pubspec.lock` `sdks:` footer), so these pins (which need Dart >=3.4 at most) resolve cleanly. The carets let pub pick the newest compatible 10.x/11.x/2.x.

- [ ] **Step 3: Fetch dependencies**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter pub get
```
Expected: ends with `Got dependencies!` (or `Changed N dependencies!`).
FALLBACK if version solving fails (e.g. a listed major no longer resolves against the installed SDK): run
```powershell
flutter pub add flutter_form_builder form_builder_validators mask_text_input_formatter
```
which writes pins pub itself chose, and keep those pins. Either way `pubspec.lock` must end up regenerated and IS committed in this task (exception to the restore rule).

- [ ] **Step 4: Create the pure model file (byte-identical duplicate of the Manager copy)**

Create `FAN lib/registration/registration_models.dart` with EXACTLY this content (same as `MANAGER lib/models/registration_models.dart` from Task 1 — the file has no imports, so the copies must stay byte-identical; change both together in the future):

```dart
/// Pure registration-engine models + helpers (Leagues epic L1, phase L1a).
///
/// NO Flutter/Firebase imports — unit-tested directly. This file is
/// intentionally DUPLICATED byte-for-byte in both repos (the apps share no
/// code; precedent: trophy/tournament models). Keep the copies identical:
///   Manager: lib/models/registration_models.dart
///   Fan:     lib/registration/registration_models.dart

// ---------------------------------------------------------------------------
// Question model
// ---------------------------------------------------------------------------

/// Every question type the dynamic form engine understands.
const List<String> kRegQuestionTypes = [
  'shortText',
  'paragraph',
  'number',
  'phone',
  'email',
  'date',
  'dropdown',
  'singleChoice',
  'multiChoice',
  'yesNo',
  'linkAcknowledge',
];

/// Types that carry an options list.
const List<String> kRegChoiceTypes = ['dropdown', 'singleChoice', 'multiChoice'];

/// Who sees a question: every path, or one specific registration path.
const List<String> kRegVisibilities = ['all', 'individual', 'captain', 'joiner'];

class RegQuestion {
  final String key; // stable id; well-known keys map to profile fields
  final String type; // one of kRegQuestionTypes
  final String label;
  final bool isRequired; // serialized under the map key 'required'
  final String visibility; // one of kRegVisibilities
  final List<String> options; // choice types only
  final String hint; // for linkAcknowledge this holds the URL to open

  const RegQuestion({
    required this.key,
    required this.type,
    required this.label,
    this.isRequired = false,
    this.visibility = 'all',
    this.options = const [],
    this.hint = '',
  });

  /// True when a registrant on [path] ('individual'|'captain'|'joiner')
  /// should see this question.
  bool visibleFor(String path) => visibility == 'all' || visibility == path;

  Map<String, dynamic> toMap() => {
        'key': key,
        'type': type,
        'label': label,
        'required': isRequired,
        'visibility': visibility,
        if (options.isNotEmpty) 'options': options,
        if (hint.isNotEmpty) 'hint': hint,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegQuestion? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key']?.toString() ?? '';
    final type = raw['type']?.toString() ?? '';
    if (key.isEmpty || !kRegQuestionTypes.contains(type)) return null;
    final rawOptions = raw['options'];
    final rawVisibility = raw['visibility']?.toString() ?? 'all';
    return RegQuestion(
      key: key,
      type: type,
      label: raw['label']?.toString() ?? key,
      isRequired: raw['required'] == true,
      visibility:
          kRegVisibilities.contains(rawVisibility) ? rawVisibility : 'all',
      options: rawOptions is List
          ? rawOptions.map((o) => o.toString()).toList()
          : const <String>[],
      hint: raw['hint']?.toString() ?? '',
    );
  }

  RegQuestion copyWith({
    String? key,
    String? type,
    String? label,
    bool? isRequired,
    String? visibility,
    List<String>? options,
    String? hint,
  }) =>
      RegQuestion(
        key: key ?? this.key,
        type: type ?? this.type,
        label: label ?? this.label,
        isRequired: isRequired ?? this.isRequired,
        visibility: visibility ?? this.visibility,
        options: options ?? this.options,
        hint: hint ?? this.hint,
      );
}

/// Parses a Form/FormTemplates node into an ordered question list. RTDB may
/// return a List OR a Map keyed by index strings; both are handled. Malformed
/// entries are skipped.
List<RegQuestion> regQuestionsFromNode(Object? raw) {
  final out = <RegQuestion>[];
  if (raw is List) {
    for (final item in raw) {
      final q = RegQuestion.fromMap(item);
      if (q != null) out.add(q);
    }
  } else if (raw is Map) {
    final entries = raw.entries.toList()
      ..sort((a, b) => (int.tryParse(a.key.toString()) ?? 0)
          .compareTo(int.tryParse(b.key.toString()) ?? 0));
    for (final e in entries) {
      final q = RegQuestion.fromMap(e.value);
      if (q != null) out.add(q);
    }
  }
  return out;
}

/// Serializes an ordered question list for a Form/FormTemplates node.
List<Map<String, dynamic>> regQuestionsToList(List<RegQuestion> questions) =>
    questions.map((q) => q.toMap()).toList();

// ---------------------------------------------------------------------------
// Input hygiene (engine-wide)
// ---------------------------------------------------------------------------

/// Uppercases the first letter of each whitespace-separated word, leaving the
/// rest of the word unchanged ("john doe" -> "John Doe").
String capitalizeWords(String input) {
  return input
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Trims and collapses every whitespace run to a single space
/// ("  a   b  " -> "a b").
String collapseTrailingSpaces(String input) =>
    input.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Keeps digits only ("(408) 693-9436" -> "4086939436"). Stored form.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

/// Displays a stored phone as (408) 693-9436. 11-digit numbers with a leading
/// 1 lose the country code; anything else is returned unchanged.
String formatPhone(String input) {
  var d = normalizePhone(input);
  if (d.length == 11 && d.startsWith('1')) d = d.substring(1);
  if (d.length != 10) return input;
  return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
}

/// Suggests a stable camelCase key from a label ("First Name" -> "firstName").
String suggestKeyFromLabel(String label) {
  final words = label
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final first = words.first.toLowerCase();
  final rest = words
      .skip(1)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase());
  return [first, ...rest].join();
}

/// Applies type-aware hygiene to raw form values before they are written:
/// shortText -> capitalize words + collapse spaces; paragraph -> collapse
/// spaces; phone -> digits only; number -> num when parseable; date
/// (DateTime) -> "MM/DD/YYYY" string. Null values are dropped. Keys without
/// a matching question pass through unchanged.
Map<String, dynamic> cleanAnswers(
    List<RegQuestion> questions, Map<String, dynamic> raw) {
  final byKey = {for (final q in questions) q.key: q};
  final out = <String, dynamic>{};
  raw.forEach((key, value) {
    if (value == null) return;
    final q = byKey[key];
    switch (q?.type) {
      case 'shortText':
        out[key] = capitalizeWords(collapseTrailingSpaces(value.toString()));
      case 'paragraph':
        out[key] = collapseTrailingSpaces(value.toString());
      case 'phone':
        out[key] = normalizePhone(value.toString());
      case 'number':
        out[key] = num.tryParse(value.toString()) ?? value.toString();
      case 'date':
        out[key] = value is DateTime
            ? '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}'
            : value.toString();
      default:
        out[key] = value;
    }
  });
  return out;
}

// ---------------------------------------------------------------------------
// Registration config
// ---------------------------------------------------------------------------

class RegistrationConfig {
  final String targetType; // 'league' | 'tournament'
  final String sport; // league sport key / tournament sport label
  final String season; // league season number as string; '' for tournament
  final String tournamentId; // '' for league targets
  final String tournamentName; // legacy dual-write bucket for tournaments
  final String status; // 'open' | 'closed'
  final num fee;
  final String feeNote;
  final String paymentMode; // 'perPlayer' | 'teamFee'
  final bool venmo;
  final bool zelle;
  final bool stripe;
  final int createdAt; // millisecondsSinceEpoch

  const RegistrationConfig({
    required this.targetType,
    required this.sport,
    this.season = '',
    this.tournamentId = '',
    this.tournamentName = '',
    this.status = 'closed',
    this.fee = 0,
    this.feeNote = '',
    this.paymentMode = 'perPlayer',
    this.venmo = true,
    this.zelle = true,
    this.stripe = false,
    this.createdAt = 0,
  });

  bool get isOpen => status == 'open';

  /// Human label, e.g. "Futsal Season 17" or the tournament's name.
  String get label => targetType == 'tournament'
      ? (tournamentName.isNotEmpty ? tournamentName : tournamentId)
      : '$sport Season $season';

  Map<String, dynamic> toFirebaseMap() => {
        'TargetType': targetType,
        'Sport': sport,
        if (season.isNotEmpty) 'Season': season,
        if (tournamentId.isNotEmpty) 'TournamentId': tournamentId,
        if (tournamentName.isNotEmpty) 'TournamentName': tournamentName,
        'Status': status,
        'Fee': fee,
        'FeeNote': feeNote,
        'PaymentMode': paymentMode,
        'Methods': {'venmo': venmo, 'zelle': zelle, 'stripe': stripe},
        'CreatedAt': createdAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegistrationConfig? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final targetType = raw['TargetType']?.toString() ?? '';
    if (targetType != 'league' && targetType != 'tournament') return null;
    final methods = raw['Methods'];
    bool method(String key, bool fallback) =>
        methods is Map ? methods[key] == true : fallback;
    return RegistrationConfig(
      targetType: targetType,
      sport: raw['Sport']?.toString() ?? '',
      season: raw['Season']?.toString() ?? '',
      tournamentId: raw['TournamentId']?.toString() ?? '',
      tournamentName: raw['TournamentName']?.toString() ?? '',
      status: raw['Status']?.toString() == 'open' ? 'open' : 'closed',
      fee: raw['Fee'] is num
          ? raw['Fee'] as num
          : num.tryParse(raw['Fee']?.toString() ?? '') ?? 0,
      feeNote: raw['FeeNote']?.toString() ?? '',
      paymentMode:
          raw['PaymentMode']?.toString() == 'teamFee' ? 'teamFee' : 'perPlayer',
      venmo: method('venmo', true),
      zelle: method('zelle', true),
      stripe: method('stripe', false),
      createdAt: int.tryParse(raw['CreatedAt']?.toString() ?? '') ?? 0,
    );
  }
}

/// regId for a league-season registration: "Futsal-17".
String leagueRegId(String sport, String season) => '$sport-$season';

/// regId for a tournament registration: "T-{tournamentId}".
String tournamentRegId(String tournamentId) => 'T-$tournamentId';

/// The regId a config lives under.
String regIdFor(RegistrationConfig c) => c.targetType == 'tournament'
    ? tournamentRegId(c.tournamentId)
    : leagueRegId(c.sport, c.season);

/// Where the legacy dual-write goes. Leagues keep the existing
/// Sign Ups/{Sport}/{Season}/... buckets; tournament targets write the
/// equivalent Sign Ups/{TournamentName}/{tournamentId}/... buckets (name
/// falls back to the id when unset).
({String league, String season}) legacySignUpTarget(RegistrationConfig c) =>
    c.targetType == 'tournament'
        ? (
            league:
                c.tournamentName.isNotEmpty ? c.tournamentName : c.tournamentId,
            season: c.tournamentId,
          )
        : (league: c.sport, season: c.season);

// ---------------------------------------------------------------------------
// Submission
// ---------------------------------------------------------------------------

class RegSubmission {
  final String path; // 'individual' | 'joiner' | 'captain'
  final Map<String, dynamic> answers;
  final String teamId; // '' until team paths land (L1b)
  final bool paid;
  final String paidVia; // '' | 'team code' | 'card' | ...
  final String displayName; // account display name at submit time
  final int submittedAt; // millisecondsSinceEpoch

  const RegSubmission({
    required this.path,
    required this.answers,
    this.teamId = '',
    this.paid = false,
    this.paidVia = '',
    this.displayName = '',
    this.submittedAt = 0,
  });

  Map<String, dynamic> toFirebaseMap() => {
        'Path': path,
        'Answers': answers,
        if (teamId.isNotEmpty) 'TeamId': teamId,
        'Paid': paid,
        if (paidVia.isNotEmpty) 'PaidVia': paidVia,
        'DisplayName': displayName,
        'SubmittedAt': submittedAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegSubmission? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['Path']?.toString() ?? '';
    if (path.isEmpty) return null;
    final rawAnswers = raw['Answers'];
    return RegSubmission(
      path: path,
      answers: rawAnswers is Map
          ? rawAnswers.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
      teamId: raw['TeamId']?.toString() ?? '',
      paid: raw['Paid'] == true,
      paidVia: raw['PaidVia']?.toString() ?? '',
      displayName: raw['DisplayName']?.toString() ?? '',
      submittedAt: int.tryParse(raw['SubmittedAt']?.toString() ?? '') ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Payment-owed logic
// ---------------------------------------------------------------------------

/// Whether this submission still owes a payment. Joiners are governed by
/// their team's CodeWaivesPayment flag (L1b passes it in; L1a's individual
/// path never sets it). Captains and individuals owe in both payment modes —
/// in teamFee mode an individual is not covered by any team's fee until an
/// admin moves them onto one.
bool paymentOwed({
  required RegistrationConfig config,
  required RegSubmission submission,
  bool codeWaivesPayment = false,
}) {
  if (submission.paid) return false;
  if (config.fee <= 0) return false;
  if (submission.path == 'joiner') return !codeWaivesPayment;
  return true;
}

// ---------------------------------------------------------------------------
// Profile mapping (well-known keys)
// ---------------------------------------------------------------------------

/// The Users/{uid}/Information field that holds positions for a sport.
/// '' means "don't write positions back" (unknown sport).
String positionsFieldForSport(String sport) {
  switch (sport) {
    case 'Basketball':
      return 'BasketballPosition';
    case 'Flag Football':
      return 'FlagFootballPosition';
    case 'Futsal':
    case 'Soccer':
      return 'FutsalPosition';
    default:
      return '';
  }
}

// ---------------------------------------------------------------------------
// Default template (seed when FormTemplates/default is empty)
// ---------------------------------------------------------------------------

const List<RegQuestion> kDefaultRegQuestions = [
  RegQuestion(
      key: 'firstName', type: 'shortText', label: 'First Name', isRequired: true),
  RegQuestion(
      key: 'lastName', type: 'shortText', label: 'Last Name', isRequired: true),
  RegQuestion(
      key: 'phone', type: 'phone', label: 'Phone Number', isRequired: true),
  RegQuestion(key: 'age', type: 'number', label: 'Age', isRequired: true),
  RegQuestion(
      key: 'height',
      type: 'shortText',
      label: "Height (e.g. 5'10)",
      isRequired: true),
  RegQuestion(
    key: 'positions',
    type: 'multiChoice',
    label: 'Positions',
    isRequired: true,
    options: ['Goal Keeper', 'Defender', 'Midfielder', 'Striker'],
  ),
  RegQuestion(key: 'comment', type: 'paragraph', label: 'Comment (optional)'),
  RegQuestion(
      key: 'rules',
      type: 'linkAcknowledge',
      label: 'Season Rules',
      isRequired: true),
  RegQuestion(
      key: 'waiver',
      type: 'linkAcknowledge',
      label: 'Waiver Conditions',
      isRequired: true),
];
```

After creating it, verify the duplication is exact:

```powershell
git diff --no-index "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\lib\models\registration_models.dart" "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\lib\registration\registration_models.dart"
```
Expected: no output (files identical).

- [ ] **Step 5: Create the test file**

Create `FAN test/registration_models_test.dart` with EXACTLY the content of `MANAGER test/registration_models_test.dart` (Task 1 Step 2), with ONE change — the import line at the top becomes:

```dart
import 'package:infinite_sports_flutter/registration/registration_models.dart';
```

(Everything else — every `group`, `test`, and `expect` — is identical to Task 1 Step 2. Copy the Manager file and swap that single line; do not retype it.)

```powershell
Copy-Item "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\test\registration_models_test.dart" "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\test\registration_models_test.dart"
```
Then edit the copied file's line 2 from
`import 'package:infinite_app_manager/models/registration_models.dart';`
to
`import 'package:infinite_sports_flutter/registration/registration_models.dart';`

- [ ] **Step 6: Run tests to verify they pass**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
flutter test test/registration_models_test.dart
```
Expected: PASS (all tests).
```powershell
flutter analyze lib/registration test/registration_models_test.dart
```
Expected: No issues found.

- [ ] **Step 7: Commit (pubspec.lock INCLUDED this once)**

```powershell
git add pubspec.yaml pubspec.lock lib/registration/registration_models.dart test/registration_models_test.dart
git commit -m "feat(registration): form-builder deps + pure registration models + tests"
```
(Do NOT stage `PROJECT_REFERENCE.md`, `SoccerStats.png`, `.claude/`, or `docs/`.)

---

## Task 8: Fan registration service

**Files:**
- Create: `FAN lib/registration/registration_service.dart`

Static-method class, matching the repo's `TournamentService` style (`lib/misc/tournament_service.dart`): direct `FirebaseDatabase.instance.ref(...)` reads, try/catch with safe defaults. Additive — green.

- [ ] **Step 1: Create the file**

Create `FAN lib/registration/registration_service.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// Fan-side reads/writes for the new registration engine (L1a: individual
/// path only). Static-method style matching TournamentService
/// (lib/misc/tournament_service.dart). The fan app NEVER sets Paid — only
/// the Manager's markPaid does.
class RegistrationService {
  /// {regId: config} for every registration whose Status is "open".
  static Future<Map<String, RegistrationConfig>> getOpenRegistrations() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('Registrations').get();
      if (snap.value is! Map) return {};
      final out = <String, RegistrationConfig>{};
      (snap.value as Map).forEach((regId, value) {
        if (value is! Map) return;
        final config = RegistrationConfig.fromFirebase(value['Config']);
        if (config != null && config.isOpen) out[regId.toString()] = config;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// The ordered question list for a registration ([] on error).
  static Future<List<RegQuestion>> getForm(String regId) async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('Registrations/$regId/Form').get();
      return regQuestionsFromNode(snap.value);
    } catch (_) {
      return [];
    }
  }

  /// The signed-in user's submission, or null (not signed in / none / error).
  static Future<RegSubmission?> getMySubmission(String regId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await FirebaseDatabase.instance
          .ref('Registrations/$regId/Submissions/$uid')
          .get();
      return RegSubmission.fromFirebase(snap.value);
    } catch (_) {
      return null;
    }
  }

  /// Pre-fills well-known keys from Users/{uid} (First Name, Last Name,
  /// Phone Number) and Users/{uid}/Information (Age, Height, positions for
  /// [sport]). Returns {} when signed out or on error.
  static Future<Map<String, dynamic>> getPrefill(String sport) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    try {
      final snap = await FirebaseDatabase.instance.ref('Users/$uid').get();
      if (snap.value is! Map) return {};
      final user = snap.value as Map;
      final out = <String, dynamic>{};
      if (user['First Name'] != null) {
        out['firstName'] = user['First Name'].toString();
      }
      if (user['Last Name'] != null) {
        out['lastName'] = user['Last Name'].toString();
      }
      if (user['Phone Number'] != null) {
        out['phone'] = user['Phone Number'].toString();
      }
      final info = user['Information'];
      if (info is Map) {
        if (info['Age'] != null) out['age'] = info['Age'].toString();
        if (info['Height'] != null) out['height'] = info['Height'].toString();
        final posField = positionsFieldForSport(sport);
        final positions = posField.isEmpty ? null : info[posField];
        if (positions is String && positions.isNotEmpty) {
          out['positions'] = positions.split(';');
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Individual-path submit:
  ///  1. writes Registrations/{regId}/Submissions/{uid}
  ///     {Path:'individual', Answers, Paid:false, DisplayName, SubmittedAt}
  ///  2. legacy dual-write Sign Ups/{league}/{season}/NotPaid/{uid} =
  ///     displayName (same shape utility.dart's signUpToPlay writes, so the
  ///     Manager Sign Ups page + Add-from-signups picker keep working)
  ///  3. profile write-back for well-known keys.
  /// Returns false when signed out or any write throws.
  static Future<bool> submitIndividual({
    required String regId,
    required RegistrationConfig config,
    required Map<String, dynamic> answers,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final displayName = user.displayName ?? '';
    try {
      final submission = RegSubmission(
        path: 'individual',
        answers: answers,
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

  /// Writes well-known answer keys back to the profile, using update() so
  /// unrelated fields are never clobbered (same nodes createDatabaseLocation
  /// and addUpdateInfo in lib/misc/utility.dart write).
  static Future<void> _writeBackProfile(
      String uid, String sport, Map<String, dynamic> answers) async {
    final root = FirebaseDatabase.instance.ref('Users/$uid');
    final rootUpdates = <String, Object?>{};
    final firstName = answers['firstName'];
    if (firstName is String && firstName.isNotEmpty) {
      rootUpdates['First Name'] = firstName;
    }
    final lastName = answers['lastName'];
    if (lastName is String && lastName.isNotEmpty) {
      rootUpdates['Last Name'] = lastName;
    }
    final phone = answers['phone'];
    if (phone != null && normalizePhone(phone.toString()).isNotEmpty) {
      rootUpdates['Phone Number'] = normalizePhone(phone.toString());
    }
    if (rootUpdates.isNotEmpty) await root.update(rootUpdates);

    final infoUpdates = <String, Object?>{};
    final positions = answers['positions'];
    final posField = positionsFieldForSport(sport);
    if (positions is List && positions.isNotEmpty && posField.isNotEmpty) {
      infoUpdates[posField] = positions.map((p) => p.toString()).join(';');
    }
    final age = int.tryParse(answers['age']?.toString() ?? '');
    if (age != null) infoUpdates['Age'] = age;
    final height = answers['height'];
    if (height is String && height.isNotEmpty) infoUpdates['Height'] = height;
    if (infoUpdates.isNotEmpty) await root.child('Information').update(infoUpdates);
  }
}
```

- [ ] **Step 2: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/registration
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All pass.

- [ ] **Step 3: Commit**

```powershell
git add lib/registration/registration_service.dart
git commit -m "feat(registration): fan RegistrationService (submit + legacy dual-write + profile write-back)"
```

---

## Task 9: Fan dynamic form renderer + widget tests

**Files:**
- Create: `FAN lib/registration/dynamic_form.dart`
- Create: `FAN test/registration_form_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `FAN test/registration_form_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final allTypes = <RegQuestion>[
    const RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name'),
    const RegQuestion(key: 'bio', type: 'paragraph', label: 'About You'),
    const RegQuestion(key: 'age', type: 'number', label: 'Age'),
    const RegQuestion(key: 'phone', type: 'phone', label: 'Phone Number'),
    const RegQuestion(key: 'email', type: 'email', label: 'Email Address'),
    const RegQuestion(key: 'birthday', type: 'date', label: 'Birthday'),
    const RegQuestion(
        key: 'shirt', type: 'dropdown', label: 'Shirt Size', options: ['S', 'M', 'L']),
    const RegQuestion(
        key: 'foot',
        type: 'singleChoice',
        label: 'Preferred Foot',
        options: ['Left', 'Right']),
    const RegQuestion(
        key: 'positions',
        type: 'multiChoice',
        label: 'Positions',
        options: ['Defender', 'Striker']),
    const RegQuestion(key: 'played', type: 'yesNo', label: 'Played Before?'),
    const RegQuestion(
        key: 'waiver', type: 'linkAcknowledge', label: 'Waiver Conditions'),
  ];

  testWidgets('renders every question type', (tester) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: allTypes,
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    for (final q in allTypes) {
      expect(find.text(q.label), findsOneWidget,
          reason: 'missing field for type ${q.type}');
    }
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('required text question gates submission; hygiene applied',
      (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(
            key: 'firstName',
            type: 'shortText',
            label: 'First Name',
            isRequired: true),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (a) async => submitted = a,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNull, reason: 'empty required field must block submit');

    await tester.enterText(find.byType(TextField).first, '  john   doe ');
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!['firstName'], 'John Doe');
  });

  testWidgets('required linkAcknowledge blocks until opened', (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(
            key: 'waiver',
            type: 'linkAcknowledge',
            label: 'Waiver Conditions',
            isRequired: true),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (a) async => submitted = a,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNull, reason: 'unread acknowledgement must block');

    // Empty-URL acknowledge (as in the default template before the admin
    // sets a URL): tapping the tile marks it read without opening a webview.
    await tester.tap(find.text('Waiver Conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!['waiver'], true);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
flutter test test/registration_form_test.dart
```
Expected: FAIL (compile error — `dynamic_form.dart` does not exist).

- [ ] **Step 3: Write the renderer**

Create `FAN lib/registration/dynamic_form.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders an ordered [RegQuestion] list with flutter_form_builder fields.
/// Required questions gate submission (validation on press); the answers map
/// passed to [onSubmit] has input hygiene applied (see [cleanAnswers]:
/// capitalized/trimmed names, digits-only phone, MM/DD/YYYY dates).
class DynamicRegistrationForm extends StatefulWidget {
  final List<RegQuestion> questions;
  final Map<String, dynamic> initialValues;
  final String submitLabel;
  final Future<void> Function(Map<String, dynamic> answers) onSubmit;

  const DynamicRegistrationForm({
    super.key,
    required this.questions,
    required this.initialValues,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<DynamicRegistrationForm> createState() =>
      _DynamicRegistrationFormState();
}

class _DynamicRegistrationFormState extends State<DynamicRegistrationForm> {
  final GlobalKey<FormBuilderState> _formKey = GlobalKey<FormBuilderState>();
  bool _submitting = false;

  InputDecoration _decoration(RegQuestion q) => InputDecoration(
        border: const OutlineInputBorder(),
        labelText: q.label,
        hintText:
            (q.type == 'linkAcknowledge' || q.hint.isEmpty) ? null : q.hint,
      );

  Widget _buildField(RegQuestion q) {
    switch (q.type) {
      case 'shortText':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          textCapitalization: TextCapitalization.words,
          decoration: _decoration(q),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'paragraph':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: _decoration(q),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'number':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          keyboardType: TextInputType.number,
          decoration: _decoration(q),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return q.isRequired ? 'This field is required' : null;
            }
            return num.tryParse(value.trim()) == null ? 'Enter a number' : null;
          },
        );
      case 'phone':
        final initialPhone =
            formatPhone(widget.initialValues[q.key]?.toString() ?? '');
        return FormBuilderTextField(
          name: q.key,
          initialValue: initialPhone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            MaskTextInputFormatter(
              mask: '(###) ###-####',
              filter: {'#': RegExp(r'[0-9]')},
              initialText: initialPhone,
            ),
          ],
          decoration: _decoration(q),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return q.isRequired ? 'This field is required' : null;
            }
            return normalizePhone(value).length == 10
                ? null
                : 'Enter a 10-digit phone number';
          },
        );
      case 'email':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration(q),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return q.isRequired ? 'This field is required' : null;
            }
            return FormBuilderValidators.email()(value);
          },
        );
      case 'date':
        return FormBuilderDateTimePicker(
          name: q.key,
          inputType: InputType.date,
          decoration: _decoration(q),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'dropdown':
        final initial = widget.initialValues[q.key];
        return FormBuilderDropdown<String>(
          name: q.key,
          initialValue:
              (initial is String && q.options.contains(initial)) ? initial : null,
          decoration: _decoration(q),
          items: q.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'singleChoice':
        final initial = widget.initialValues[q.key];
        return FormBuilderRadioGroup<String>(
          name: q.key,
          initialValue:
              (initial is String && q.options.contains(initial)) ? initial : null,
          decoration: _decoration(q),
          orientation: OptionsOrientation.vertical,
          options: q.options
              .map((o) => FormBuilderFieldOption(value: o, child: Text(o)))
              .toList(),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'multiChoice':
        final initial = widget.initialValues[q.key];
        return FormBuilderCheckboxGroup<String>(
          name: q.key,
          initialValue: initial is List
              ? initial
                  .map((o) => o.toString())
                  .where(q.options.contains)
                  .toList()
              : null,
          decoration: _decoration(q),
          orientation: OptionsOrientation.vertical,
          options: q.options
              .map((o) => FormBuilderFieldOption(value: o, child: Text(o)))
              .toList(),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'yesNo':
        return FormBuilderRadioGroup<String>(
          name: q.key,
          decoration: _decoration(q),
          orientation: OptionsOrientation.horizontal,
          options: const [
            FormBuilderFieldOption(value: 'Yes', child: Text('Yes')),
            FormBuilderFieldOption(value: 'No', child: Text('No')),
          ],
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'linkAcknowledge':
        return _LinkAcknowledgeField(question: q);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _submit() async {
    final state = _formKey.currentState;
    if (state == null || !state.saveAndValidate()) return;
    final answers =
        cleanAnswers(widget.questions, Map<String, dynamic>.from(state.value));
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(answers);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormBuilder(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          for (final q in widget.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: _buildField(q),
            ),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.submitLabel,
                      style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Waiver/rules acknowledgement: a tile that must be tapped — opening its URL
/// (stored in the question's hint) in an in-app web view — before its checkbox
/// reads true. Required questions block submission until read. With an empty
/// URL, tapping simply marks it read.
class _LinkAcknowledgeField extends StatelessWidget {
  final RegQuestion question;
  const _LinkAcknowledgeField({required this.question});

  @override
  Widget build(BuildContext context) {
    return FormBuilderField<bool>(
      name: question.key,
      initialValue: false,
      validator: (value) => (question.isRequired && value != true)
          ? 'Please open and read this first'
          : null,
      builder: (field) {
        final read = field.value == true;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            title: Text(question.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: field.errorText != null
                ? Text(field.errorText!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))
                : Text(read ? 'Read — thank you!' : 'Tap to open and read'),
            trailing: Checkbox(value: read, onChanged: null),
            onTap: () async {
              final url = question.hint.trim();
              if (url.isNotEmpty) {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (context) {
                  final controller = WebViewController()
                    ..loadRequest(Uri.parse(url));
                  return Scaffold(
                    appBar: AppBar(
                      centerTitle: true,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      title: Text(question.label),
                    ),
                    body: WebViewStack(controller: controller),
                  );
                }));
              }
              field.didChange(true);
            },
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
flutter test test/registration_form_test.dart
```
Expected: PASS (3 tests).
```powershell
flutter analyze lib/registration test/registration_form_test.dart
```
Expected: No issues found.
(If a `FormBuilderValidators.required()` type-inference error appears on the DateTime picker with the resolved package version, change that one call site to `FormBuilderValidators.required<DateTime>()` — same for the `List<String>` checkbox group with `FormBuilderValidators.required<List<String>>()`.)

- [ ] **Step 5: Commit**

```powershell
git add lib/registration/dynamic_form.dart test/registration_form_test.dart
git commit -m "feat(registration): dynamic form renderer (11 question types) + widget tests"
```

---

## Task 10: Fan flow screens — entry, path, form, payment, status

**Files:**
- Create: `FAN lib/registration/payment_screen.dart`
- Create: `FAN lib/registration/registration_status_page.dart`
- Create: `FAN lib/registration/registration_form_page.dart`
- Create: `FAN lib/registration/registration_path_page.dart`
- Create: `FAN lib/registration/registration_entry_page.dart`

Create in this order (payment + status first — the later pages import them). `payment_screen.dart` and `registration_status_page.dart` import each other (Dart allows the cycle). All additive — green; wiring happens in Task 11.

- [ ] **Step 1: Create the payment screen**

Create `FAN lib/registration/payment_screen.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Zelle account's registered number (shown + copyable).
const String kZelleNumber = '408-693-9436';

/// PLACEHOLDER — the OWNER must replace this with the exact recipient name
/// Zelle displays for 408-693-9436 BEFORE this phase ships (spec section 5:
/// "owner to supply name before L1a ships"). Everything else works without
/// it; the payment screen just shows this literal text until then.
const String kZelleDisplayName = 'OWNER-SET-ZELLE-RECIPIENT-NAME';

/// Venmo handle for the business profile.
const String kVenmoHandle = 'infinite-sports';

/// Payment screen (L1a: Venmo + Zelle only; Stripe lands in L1c). Nothing
/// auto-confirms — the admin flips Paid in the Manager. Re-openable from the
/// status page until Paid.
class PaymentScreen extends StatelessWidget {
  final String regId;
  final RegistrationConfig config;

  /// True when reached straight from a fresh submission (the status page is
  /// not underneath us) — the exit button pushes the status page instead of
  /// popping.
  final bool fromSubmission;

  const PaymentScreen({
    super.key,
    required this.regId,
    required this.config,
    this.fromSubmission = false,
  });

  /// venmo.com profile links open the Venmo app when it is installed
  /// (Android App Links / iOS Universal Links); otherwise the browser loads
  /// the profile page. txn=pay + amount + note pre-fill the payment.
  Uri get _venmoUri {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final note = Uri.encodeComponent('$regId - $name');
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=${config.fee}&note=$note');
  }

  void _exit(BuildContext context) {
    if (fromSubmission) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                RegistrationStatusPage(regId: regId, config: config)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payment'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.attach_money),
              title: Text('\$${config.fee}',
                  style: Theme.of(context).textTheme.headlineSmall),
              subtitle: Text([
                config.label,
                if (config.feeNote.isNotEmpty) config.feeNote,
              ].join(' — ')),
            ),
          ),
          const SizedBox(height: 15),
          if (config.venmo) ...[
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008CFF),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Pay with Venmo',
                    style: TextStyle(fontSize: 18)),
                onPressed: () async {
                  await launchUrl(_venmoUri,
                      mode: LaunchMode.externalApplication);
                },
              ),
            ),
            const SizedBox(height: 15),
          ],
          if (config.zelle) ...[
            Card(
              elevation: 2,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_balance),
                    title: const Text('Zelle',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(kZelleNumber,
                        style: TextStyle(fontSize: 18)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy number',
                      onPressed: () {
                        Clipboard.setData(
                            const ClipboardData(text: kZelleNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Zelle number copied.')),
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(15, 0, 15, 12),
                    child: Text(
                        'Before sending, confirm the recipient name shows "$kZelleDisplayName".'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
          ],
          const Text(
            'Nothing confirms automatically yet — an admin marks you Paid once your payment arrives. You can reopen this screen from your registration status any time until then.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          OutlinedButton(
            onPressed: () => _exit(context),
            child: const Text('View my registration'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create the status page**

Create `FAN lib/registration/registration_status_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

/// The player's registration state: Paid badge, submitted answers, and a
/// persistent "Complete payment" button (reopening the payment screen) while
/// unpaid.
class RegistrationStatusPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationStatusPage(
      {super.key, required this.regId, required this.config});

  @override
  State<RegistrationStatusPage> createState() => _RegistrationStatusPageState();
}

class _RegistrationStatusPageState extends State<RegistrationStatusPage> {
  late Future<(RegSubmission?, List<RegQuestion>)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<(RegSubmission?, List<RegQuestion>)> _loadAll() async {
    final sub = await RegistrationService.getMySubmission(widget.regId);
    final form = await RegistrationService.getForm(widget.regId);
    return (sub, form);
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
          final (sub, form) = snapshot.data ?? (null, const <RegQuestion>[]);
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
                        subtitle: Text('Registered as: ${sub.path}'),
                        trailing: Chip(
                          label:
                              Text(sub.paid ? 'Paid' : 'Payment pending'),
                          backgroundColor: sub.paid
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                        ),
                      ),
                    ),
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
                                    config: widget.config)),
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

- [ ] **Step 3: Create the form page**

Create `FAN lib/registration/registration_form_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

/// Loads the registration's form + the player's profile prefill, renders the
/// individual-path questions, submits, then routes to the payment screen
/// (when a payment is owed) or straight to the status page.
class RegistrationFormPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationFormPage(
      {super.key, required this.regId, required this.config});

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
    final visible = form.where((q) => q.visibleFor('individual')).toList();
    return (visible, prefill);
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    final ok = await RegistrationService.submitIndividual(
      regId: widget.regId,
      config: widget.config,
      answers: answers,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Something went wrong — try again, and contact us if it keeps failing.')));
      return;
    }
    final submission = RegSubmission(
      path: 'individual',
      answers: answers,
      paid: false,
      submittedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (paymentOwed(config: widget.config, submission: submission)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => PaymentScreen(
                regId: widget.regId,
                config: widget.config,
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

- [ ] **Step 4: Create the path selector page**

Create `FAN lib/registration/registration_path_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// "How are you registering?" — L1a ships the individual path only; the two
/// team paths are visible but disabled until L1b.
class RegistrationPathPage extends StatelessWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationPathPage(
      {super.key, required this.regId, required this.config});

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
          const Card(
            elevation: 2,
            child: ListTile(
              enabled: false,
              leading: Icon(Icons.group),
              title: Text('Join a team with a code',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Coming soon'),
            ),
          ),
          const Card(
            elevation: 2,
            child: ListTile(
              enabled: false,
              leading: Icon(Icons.groups),
              title: Text('Register a new team (captain)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Coming soon'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Create the entry page**

Create `FAN lib/registration/registration_entry_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

/// Lists every open registration. Tapping one shows the player's existing
/// submission (status page) or starts the path selector. Registering twice
/// for the same registration is therefore impossible — the status page opens
/// instead (spec section 7).
class RegistrationEntryPage extends StatefulWidget {
  const RegistrationEntryPage({super.key});

  @override
  State<RegistrationEntryPage> createState() => _RegistrationEntryPageState();
}

class _RegistrationEntryPageState extends State<RegistrationEntryPage> {
  late Future<Map<String, RegistrationConfig>> _openRegs;

  @override
  void initState() {
    super.initState();
    _openRegs = RegistrationService.getOpenRegistrations();
  }

  Future<void> _openRegistration(
      String regId, RegistrationConfig config) async {
    final existing = await RegistrationService.getMySubmission(regId);
    if (!mounted) return;
    if (existing != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) {
        return RegistrationStatusPage(regId: regId, config: config);
      }));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) {
        return RegistrationPathPage(regId: regId, config: config);
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Registration'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: _openRegs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          final regs = snapshot.data ?? {};
          if (regs.isEmpty) {
            return const Center(
                child: Text('No registrations are open right now.'));
          }
          final entries = regs.entries.toList();
          return ListView.separated(
            separatorBuilder: (context, index) =>
                Divider(color: Theme.of(context).dividerColor),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final regId = entries[index].key;
              final config = entries[index].value;
              return ListTile(
                enabled: signedIn,
                leading: const Icon(Icons.how_to_reg),
                title: Text(config.label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(signedIn
                    ? (config.fee > 0
                        ? 'Fee: \$${config.fee}${config.feeNote.isNotEmpty ? ' — ${config.feeNote}' : ''}'
                        : 'Free')
                    : 'Log in to register'),
                onTap: () => _openRegistration(regId, config),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/registration
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All pass.

- [ ] **Step 7: Commit**

```powershell
git add lib/registration/payment_screen.dart lib/registration/registration_status_page.dart lib/registration/registration_form_page.dart lib/registration/registration_path_page.dart lib/registration/registration_entry_page.dart
git commit -m "feat(registration): individual flow — entry, path, form, payment (Venmo/Zelle), status"
```

---

## Task 11: Fan wiring — drawer tile + Matches banner

**Files:**
- Modify: `FAN lib/navbar.dart`
- Modify: `FAN lib/frontpage.dart`

DO NOT delete or edit `lib/signup.dart` / `lib/leagueform.dart` — external Form-URL sign-ups (the AFC-style entries under `Sign Ups/*/Form URL`) still flow through them, and they remain the fallback when only the legacy `Sign Ups/Sign Up Status` int says open.

- [ ] **Step 1: Reroute the drawer "Sign Up List" tile**

In `FAN lib/navbar.dart`:

1a. Add three imports. Find:

```dart
import 'package:infinite_sports_flutter/playerpage.dart';
```

replace with:

```dart
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:infinite_sports_flutter/registration/registration_entry_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
```

1b. Add the state field. Find (lines 35-37):

```dart
  String nextleague = "";
  String season = "";
  bool signUpsOpen = false;
```

replace with:

```dart
  String nextleague = "";
  String season = "";
  Map<String, RegistrationConfig> openRegistrations = {};
  bool signUpsOpen = false;
```

1c. Prefer new-style registrations in `setUp()`. Find (lines 60-88):

```dart
  Future<void> setUp() async {
    var status  = await getSignUpStatus();
    switch (status) {
```

replace with:

```dart
  Future<void> setUp() async {
    // New-style registrations (registration redesign L1a) win when any is
    // open; the legacy Sign Up Status int stays as the fallback below.
    openRegistrations = await RegistrationService.getOpenRegistrations();
    if (openRegistrations.isNotEmpty) {
      signUpDetail = openRegistrations.length == 1
          ? "Sign Up for ${openRegistrations.values.first.label}"
          : "Sign Ups Open";
      signUpsOpen = true;
      return;
    }
    var status  = await getSignUpStatus();
    switch (status) {
```

(The `switch (status)` cases 0/1/2/3/default from lines 62-87 stay exactly as they are.)

1d. Route the tile. Find (inside the Sign Up List `ListTile`, lines 244-248):

```dart
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Signup(nextleague: nextleague, season: season);
                  },));
                },
```

replace with:

```dart
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    if (openRegistrations.isNotEmpty) {
                      return const RegistrationEntryPage();
                    }
                    return Signup(nextleague: nextleague, season: season);
                  },));
                },
```

- [ ] **Step 2: Add the Matches-screen banner**

In `FAN lib/frontpage.dart`:

2a. Add imports. Find:

```dart
import 'package:infinite_sports_flutter/misc/utility.dart';
```

replace with:

```dart
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/registration_entry_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
```

2b. Add the state field. Find (lines 63-64):

```dart
  // Active tournaments (not finished, each having a current game day).
  List<_ActiveTournamentTab> activeTournaments = [];
```

replace with:

```dart
  // Active tournaments (not finished, each having a current game day).
  List<_ActiveTournamentTab> activeTournaments = [];

  // Open new-style registrations (regId -> config) for the sign-up banner.
  Map<String, RegistrationConfig> openRegistrations = {};
```

2c. Load them with the other front-page values. Find (in `getFrontPageValues()`, lines 90-91):

```dart
    await _loadActiveTournaments();
    return 1;
```

replace with:

```dart
    await _loadActiveTournaments();
    openRegistrations = await RegistrationService.getOpenRegistrations();
    return 1;
```

2d. Add the banner builder method. Find (end of `getSportIcon`, lines 129-132):

```dart
      default:
        return Icon(Icons.sports);
    }
  }
```

replace with:

```dart
      default:
        return Icon(Icons.sports);
    }
  }

  /// Banner card shown while any new-style registration is open; tapping it
  /// opens the registration entry page.
  Widget _registrationBanner(BuildContext context) {
    final config = openRegistrations.values.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 4, 19, 0),
      child: Card(
        color: Theme.of(context).colorScheme.primary,
        child: ListTile(
          leading: const Icon(Icons.how_to_reg, color: Colors.white),
          title: Text(
            openRegistrations.length == 1
                ? 'Registration open: ${config.label}'
                : 'Registrations are open',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text('Tap to sign up',
              style: TextStyle(color: Colors.white70)),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) {
              return const RegistrationEntryPage();
            }));
          },
        ),
      ),
    );
  }
```

2e. Show the banner at the top of the league tab. Find (lines 200-203):

```dart
              if (!isCurrentFinished) {
                tabNames.add(Tab(text: "Infinite Sports"));
                tabIsTournament.add(false);
                tabs.add(Column(children: [
```

replace with:

```dart
              if (!isCurrentFinished) {
                tabNames.add(Tab(text: "Infinite Sports"));
                tabIsTournament.add(false);
                tabs.add(Column(children: [
                  if (openRegistrations.isNotEmpty)
                    _registrationBanner(context),
```

2f. Also show it on the no-games empty state (registration is usually open BETWEEN seasons, when there are no tabs). Find (lines 314-326):

```dart
              return Center(
                child: Card(
                  elevation: 2,
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
```

replace with:

```dart
              return Column(children: [
                if (openRegistrations.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _registrationBanner(context),
                  ),
                Expanded(
                  child: Center(
                    child: Card(
                      elevation: 2,
                      child: SizedBox(
                        width: 350,
                        height: 70,
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          child: const Text("No Upcoming Games,\nStay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
```

- [ ] **Step 3: Verify it compiles + tests still pass**

```powershell
flutter analyze lib/navbar.dart lib/frontpage.dart lib/registration
```
Expected: No issues found.
```powershell
flutter test
```
Expected: All pass.

- [ ] **Step 4: Commit**

```powershell
git add lib/navbar.dart lib/frontpage.dart
git commit -m "feat(registration): drawer + Matches banner route to the new registration flow"
```

---

## Task 12: Fan full verify + build/install

**Files:** none (verification only). No commit.

- [ ] **Step 1: Full analyze (fan analyze can be slow — allow up to 10 minutes)**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
flutter analyze
```
Expected: No NEW issues beyond the repo's pre-existing baseline. Zero errors/warnings in `lib/registration/`, `lib/navbar.dart`, `lib/frontpage.dart`, or the new tests.

- [ ] **Step 2: Full test run**

```powershell
flutter test
```
Expected: All tests pass (existing suite + `registration_models_test.dart` + `registration_form_test.dart`).

- [ ] **Step 3: Build + install to the phone (ONE app at a time — make sure the Manager build from Task 6 has finished)**

```powershell
flutter build apk --debug
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s GN434J02403404RL install -r "build\app\outputs\flutter-apk\app-debug.apk"
```
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk` then `Success`.

---

## Task 13: End-to-end owner test (both apps on the phone)

**Files:** none. No commit. Requires the OPEN test registration from Task 6 Step 4 (or open a fresh one now).

Tell the owner to run this script (individual path only — team paths are L1b):

- [ ] 1. **Manager:** drawer → Registrations → confirm the Futsal registration shows an OPEN chip. (If none: Open registration → League → Futsal → fee `120`, fee note `Due by the first game`, Venmo+Zelle on, Per player → Open.) Optional: edit `Season Rules` / `Waiver Conditions` questions and paste real URLs into their Link URL field.
- [ ] 2. **Fan app (signed in):** open the drawer → "Sign Up List" now reads "Sign Up for Futsal Season N" → tap → the new Registration page lists it (not the old web list). Also check the Matches tab shows the red "Registration open" banner.
- [ ] 3. Tap the registration → "How are you registering?" → confirm the two team options are visible but greyed out ("Coming soon") → Register as an individual.
- [ ] 4. Form: First/Last name, phone, age, height, positions pre-filled from your profile where they exist. Phone types with the `(408) 693-9436` mask. Try Register with a required field empty → it blocks with an error. Open Season Rules + Waiver (checkboxes tick after opening). Register.
- [ ] 5. Payment screen: fee `$120` + note show. "Pay with Venmo" opens the Venmo app (venmo.com links open the app when installed) with amount + note `Futsal-N - {your name}` pre-filled — do NOT actually send. Zelle tile: copy button copies `408-693-9436`; the recipient-name line still shows the placeholder — **owner: supply the real Zelle display name and it goes into `kZelleDisplayName` in `lib/registration/payment_screen.dart` before release**.
- [ ] 6. "View my registration" → status page shows "Payment pending" + your answers + a persistent "Complete payment" button; tap it → payment screen reopens. Back out; reopen the drawer entry → it now goes straight to your status (no double registration possible).
- [ ] 7. **Manager:** Registrations → tap the registration → your submission appears (name, `individual`, date) → tap for the answers sheet → flip the Paid switch ON.
- [ ] 8. **Verify legacy sync:** Manager → Sign Ups → Futsal Season N → you appear under **Paid** (moved from NotPaid). Then Futsal Manager → Create Lineup → Add from sign-ups → you appear tagged Paid. This proves the dual-write + markPaid legacy sync end to end.
- [ ] 9. **Fan:** reopen My Registration → badge now reads "Paid", the Complete-payment button is gone.
- [ ] 10. **Manager:** flip the registration's Status switch to CLOSED → fan drawer (after reopening it) falls back to the legacy state ("Sign Ups Closed" unless the legacy int is set) and the Matches banner disappears on refresh. Flip back OPEN if sign-ups should continue.
- [ ] 11. Cleanup: if this was a throwaway test, delete `Registrations/Futsal-N` and your test entries under `Sign Ups/Futsal/N/(Paid|NotPaid)` in the Firebase console, and remove the profile changes if you entered junk data.

Do NOT merge `zaya-registration` into `zaya-features` — the owner decides after Paul/Bronsin review. Commits stay local.

---

## Self-Review

**1. Spec coverage (L1a scope only):**
- Spec section 2 — form engine: all 11 question types modeled (Task 1) and rendered (Task 9); per-question `key/type/label/required/visibility/options/hint` (Task 1); input hygiene — `TextCapitalization.words` + `capitalizeWords`/`collapseTrailingSpaces` on submit, phone mask + digits-stored/formatted-displayed, email format-validation, number/date keyboards+picker, required gating (Tasks 1, 9). Packages `flutter_form_builder`/`form_builder_validators`/`mask_text_input_formatter` added (Task 7); `pin_code_fields`/`qr_flutter` deliberately NOT added — they are for L1b's join-code entry per spec section 2. ✓
- Spec section 3 — data model: `Registrations/{regId}/Config|Form|Submissions/{uid}` + `FormTemplates/{id}` paths in both repos (Task 2 helpers; fan uses inline paths in its service, matching its house style); regId `"{Sport}-{Season}"` / `"T-{tournamentId}"` (Task 1 `leagueRegId`/`tournamentRegId`); `Teams/{teamId}` path helpers pinned for L1b (Task 2). Additive fields beyond the spec: `TournamentName` on Config (needed for the spec's `Sign Ups/{TournamentName}/...` dual-write) and `DisplayName` on Submission (needed so markPaid can move the legacy entry by name) — both additive, nothing removed. ✓
- Spec section 3 — legacy compatibility: fan submit dual-writes `Sign Ups/{Sport}/{Season}/NotPaid/{uid} = displayName` (Task 8), Manager `markPaid` moves NotPaid<->Paid via the existing `SignUpService.moveToPaid/moveToNotPaid` (Task 2), drawer "open" state derives from open registrations with the legacy int as fallback (Task 11). ✓
- Spec section 4 — Manager hub: `/registrations` route + nav entry (Task 4), list w/ open-closed chips + Status switch (Task 4), wizard w/ target picker + template seed + "copy last registration" + drag-reorder editor + fee/feeNote + method toggles (stripe disabled "coming soon") + paymentMode → creates OPEN (Tasks 3-4), template editor (Task 5), submissions view w/ search + answers sheet + Paid flip updating both paths (Task 5). Team approvals are L1b (spec section 9) — not planned here. ✓
- Spec section 5 — fan flow: drawer entry + Matches banner (Task 11); path question with Individual active and both team paths disabled "coming soon" (Task 10); dynamic form per visibility + profile pre-fill + write-back (Tasks 8-10); submit writes submission + legacy dual-write (Task 8); payment screen with Venmo deep link (`txn=pay&amount&note`, venmo.com opens the app when installed) + Zelle number/copy/`kZelleDisplayName` + fee/feeNote (Task 10); re-openable payment + persistent "Complete payment" until Paid (Task 10). ✓
- Spec section 6 — payments L1a: Venmo/Zelle manual flip only; per-registration Fee/Methods/PaymentMode; `teamFee` owed-logic in `paymentOwed` incl. the `CodeWaivesPayment` parameter L1b will use (Task 1). Stripe = disabled toggle only. ✓
- Spec section 7 — edge cases in scope: double-register blocked (entry page shows status instead, Task 10); closing keeps submissions payable (Status only gates listing; status/payment pages still reachable from the drawer fallback? — closing hides the entry list, but the submission + Paid flow remain intact in Manager; fan re-entry to a CLOSED registration's status requires it to be open in L1a — acceptable, admin flips Paid regardless); malformed reads guarded everywhere (`fromMap`/`fromFirebase` return null; services return empty). Code-collision/team cases are L1b. ✓
- Spec section 8 — testing: unit tests for (de)serialization, visibility filter, formatters, payment-owed, legacy mapping (`legacySignUpTarget`) in BOTH repos (Tasks 1, 7); widget tests render-each-type + required gating (Task 9); owner script (Task 13). Join-code generation tests are L1b. ✓
- Prompt-specific ordering honored: Manager model→paths/service→editor→hub/wizard→submissions/template→verify, then Fan pubspec/model→service→renderer→flow→wiring→verify→end-to-end. Each task is additive-first and compiles green (Task 4's two dead route taps land in Task 5 and are called out there).

**2. Placeholder scan:** No TBD/TODO in any code block; every new file ships full contents; every modification is an exact find/replace pair verified against the current files (navbar.dart lines 35-37/60-88/244-248, frontpage.dart lines 63-64/90-91/129-132/200-203/314-326, app_router.dart lines 117-120, master_detail_shell.dart lines 71-76, firebase_paths.dart lines 157-160, pubspec.yaml lines 68-69). Two deliberate non-placeholders: (a) `kZelleDisplayName = 'OWNER-SET-ZELLE-RECIPIENT-NAME'` is REQUIRED by the spec ("owner to supply name before L1a ships") and is clearly marked at the constant and in the owner script; (b) Task 7 Step 5 builds the fan test file with an exact `Copy-Item` command + a single specified line swap rather than retyping 300 identical lines — the content is fully determined by Task 1 Step 2 plus that one line, with a `git diff --no-index` check for the model twin. ✓

**3. Type consistency:** `RegQuestion{key,type,label,isRequired,visibility,options,hint}` identical in Task 1 and Task 7 and consumed with those exact names in Tasks 3, 5, 9, 10 (`isRequired` chosen over the reserved-adjacent `required`; serialized as `'required'` per spec). `RegistrationConfig` field set identical across both copies; `label`/`isOpen` getters used by hub list, wizard, entry, banner, payment, status. `RegSubmission{path,answers,teamId,paid,paidVia,displayName,submittedAt}` used by Manager submissions page and fan status page with the same accessors. `paymentOwed(config:, submission:, codeWaivesPayment:)` signature identical at its three call sites (form page, status page, tests). `legacySignUpTarget` returns the record `({String league, String season})` consumed by both `markPaid` and `submitIndividual`. Service signatures match their callers: `createRegistration(String, RegistrationConfig, List<RegQuestion>)`, `setStatus(String, bool)`, `markPaid(String, String, bool)`, `getTemplate/saveTemplate('default', ...)`, fan `submitIndividual({regId, config, answers})`. Provider names (`registrationServiceProvider`, `registrationListProvider`, `registrationConfigProvider`, `registrationFormProvider`, `registrationSubmissionsProvider`, `formTemplateProvider`) match every watch/read/invalidate in Tasks 4-5. ✓

**4. Implementer caveats:**
- Package pins (`flutter_form_builder ^10.2.0`, `form_builder_validators ^11.2.0`, `mask_text_input_formatter ^2.9.0`) were chosen against the installed Dart >=3.11 toolchain; Task 7 Step 3 has an exact `flutter pub add` fallback if resolution fails, and Task 9 Step 4 notes the one plausible generic-inference fix (`FormBuilderValidators.required<T>()`).
- Deprecation-hygiene: the Manager wizard/editor intentionally use ChoiceChip + InputDecorator/DropdownButton (the in-repo trophy-editor pattern) instead of RadioListTile/DropdownButtonFormField, which are deprecation-flagged on current Flutter.
- go_router regIds contain spaces (`Flag Football-9`); the list page encodes with `Uri.encodeComponent` and go_router decodes the path parameter.
- `Registrations` node reads are guarded, so pre-existing junk under that path (there should be none — the schema is new) cannot crash either app.







