# Trophy & Accomplishment System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An extensible trophy catalog the admin defines, awards (auto on "Mark Finished" + manual), stored per-player, shown in a profile cabinet.

**Architecture:** Additive Firebase nodes only — global `Trophies/` catalog and per-player `Users/{uid}/Awards/`. Pure, unit-tested recipient-computation helpers (team placement + stat leaders) are separated from Firebase writes. Auto-awards use deterministic ids for idempotency. Manager authors + auto-awards; Fan displays a read-only cabinet.

**Tech Stack:** Flutter/Dart. Manager: Riverpod + go_router + `FirebaseService`/`FirebasePaths`. Fan: RTDB direct reads. Firebase Realtime Database.

**Branches:** `zaya-trophies` off `zaya-features` in each repo. Fan branch already exists. All commits LOCAL.

**Spec:** `docs/superpowers/specs/2026-06-25-player-profile-trophies-design.md`

---

## File Structure

**MANAGER** (`InfiniteSportsManagerFlutter`):
- `lib/models/trophy.dart` — Trophy catalog model (NEW)
- `lib/models/award.dart` — Award record model (NEW)
- `lib/services/award_engine.dart` — PURE recipient computation (placements, stat leaders, deterministic ids) (NEW)
- `lib/services/firebase/trophy_service.dart` — catalog CRUD + manual assign + auto-award writes (NEW)
- `lib/core/constants/firebase_paths.dart` — add trophy/award path helpers (MODIFY)
- `lib/ui/trophies/trophy_catalog_page.dart` — catalog list + add/edit (NEW)
- `lib/ui/trophies/assign_trophy_page.dart` — manual assign with user picker (NEW)
- `lib/ui/trophies/trophy_icons.dart` — built-in icon key → IconData/asset map (NEW)
- `lib/router/app_router.dart` — register `/trophies` (MODIFY)
- `lib/ui/tournaments/tournament_dashboard_page.dart` — hook award engine into Mark-Finished + add "Recompute Awards" (MODIFY)
- `lib/models/my_user.dart` — add `profileUrl` to fromJson (MODIFY)
- `lib/services/league_standings_engine.dart` — PURE league standings + leaders (NEW, Phase 1C)
- Tests under `test/`

**FAN** (`infinite_sports_flutter`):
- `lib/model/award.dart` — Award read model (NEW)
- `lib/misc/trophy_icons.dart` — icon key → asset/IconData (NEW)
- `lib/widgets/trophy_cabinet.dart` — cabinet grid + detail sheet (NEW)
- `lib/playerpage.dart` — read `Users/{uid}/Awards`, render cabinet (MODIFY)
- `assets/trophies/` — ~9 icons (NEW); `pubspec.yaml` add the dir (MODIFY)
- Tests under `test/`

---

# PHASE 1A — Catalog + Manual Assign + Cabinet (end-to-end)

### Task 1: Manager branch + Trophy & Award models

**Files:**
- Create: `lib/models/trophy.dart`, `lib/models/award.dart`
- Test: `test/trophy_model_test.dart`

- [ ] **Step 1: Create the Manager branch**

```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git checkout zaya-features && git checkout -b zaya-trophies
```

- [ ] **Step 2: Write failing test** `test/trophy_model_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/models/trophy.dart';
import 'package:infinite_app_manager/models/award.dart';

void main() {
  test('Trophy round-trips through firebase map', () {
    const t = Trophy(id: 't1', name: 'Golden Boot', kind: 'auto',
        rule: 'goldenBoot', sport: 'Futsal', iconType: 'builtin',
        icon: 'boot', tier: 'gold', active: true, createdAt: 123);
    final m = t.toFirebaseMap();
    expect(m['Name'], 'Golden Boot');
    expect(m['Rule'], 'goldenBoot');
    final back = Trophy.fromMap('t1', m);
    expect(back.kind, 'auto');
    expect(back.tier, 'gold');
  });

  test('manual Trophy omits Rule', () {
    const t = Trophy(id: 't2', name: 'MVP', kind: 'manual', rule: null,
        sport: '', iconType: 'builtin', icon: 'star', tier: 'gold',
        active: true, createdAt: 1);
    expect(t.toFirebaseMap().containsKey('Rule'), false);
  });

  test('Award round-trips', () {
    const a = Award(id: 'a1', trophyId: 't1', name: 'Golden Boot',
        icon: 'boot', iconType: 'builtin', tier: 'gold', sport: 'Futsal',
        scopeType: 'tournament', scopeId: 'tid', season: '', edition: '2026',
        context: 'Summer Cup 2026', date: '08302026', source: 'auto');
    final back = Award.fromMap('a1', a.toFirebaseMap());
    expect(back.name, 'Golden Boot');
    expect(back.scopeType, 'tournament');
    expect(back.source, 'auto');
  });
}
```

- [ ] **Step 3: Run test — expect FAIL** (`flutter test test/trophy_model_test.dart` → compile error, models missing)

- [ ] **Step 4: Implement `lib/models/trophy.dart`**

```dart
class Trophy {
  final String id;
  final String name;
  final String kind;     // 'auto' | 'manual'
  final String? rule;    // ruleKey when kind == 'auto'
  final String sport;    // '' = any
  final String iconType; // 'builtin' | 'url'
  final String icon;     // builtin key or url
  final String tier;     // 'gold' | 'silver' | 'bronze'
  final bool active;
  final int createdAt;

  const Trophy({
    required this.id, required this.name, required this.kind, this.rule,
    required this.sport, required this.iconType, required this.icon,
    required this.tier, required this.active, required this.createdAt,
  });

  factory Trophy.fromMap(String id, Map<dynamic, dynamic> m) => Trophy(
        id: id,
        name: (m['Name'] ?? '').toString(),
        kind: (m['Kind'] ?? 'manual').toString(),
        rule: m['Rule']?.toString(),
        sport: (m['Sport'] ?? '').toString(),
        iconType: (m['IconType'] ?? 'builtin').toString(),
        icon: (m['Icon'] ?? 'trophy_gold').toString(),
        tier: (m['Tier'] ?? 'gold').toString(),
        active: m['Active'] == null ? true : m['Active'] == true,
        createdAt: (m['CreatedAt'] is int) ? m['CreatedAt'] as int : 0,
      );

  Map<String, dynamic> toFirebaseMap() => {
        'Name': name, 'Kind': kind,
        if (kind == 'auto' && rule != null) 'Rule': rule,
        'Sport': sport, 'IconType': iconType, 'Icon': icon, 'Tier': tier,
        'Active': active, 'CreatedAt': createdAt,
      };
}
```

- [ ] **Step 5: Implement `lib/models/award.dart`**

```dart
class Award {
  final String id;
  final String trophyId;
  final String name;
  final String icon;
  final String iconType;
  final String tier;
  final String sport;
  final String scopeType; // 'tournament' | 'league'
  final String scopeId;
  final String season;
  final String edition;
  final String context;
  final String date;      // MMDDYYYY
  final String source;    // 'auto' | 'manual'

  const Award({
    required this.id, required this.trophyId, required this.name,
    required this.icon, required this.iconType, required this.tier,
    required this.sport, required this.scopeType, required this.scopeId,
    required this.season, required this.edition, required this.context,
    required this.date, required this.source,
  });

  factory Award.fromMap(String id, Map<dynamic, dynamic> m) => Award(
        id: id,
        trophyId: (m['TrophyId'] ?? '').toString(),
        name: (m['Name'] ?? '').toString(),
        icon: (m['Icon'] ?? 'trophy_gold').toString(),
        iconType: (m['IconType'] ?? 'builtin').toString(),
        tier: (m['Tier'] ?? 'gold').toString(),
        sport: (m['Sport'] ?? '').toString(),
        scopeType: (m['ScopeType'] ?? '').toString(),
        scopeId: (m['ScopeId'] ?? '').toString(),
        season: (m['Season'] ?? '').toString(),
        edition: (m['Edition'] ?? '').toString(),
        context: (m['Context'] ?? '').toString(),
        date: (m['Date'] ?? '').toString(),
        source: (m['Source'] ?? 'manual').toString(),
      );

  Map<String, dynamic> toFirebaseMap() => {
        'TrophyId': trophyId, 'Name': name, 'Icon': icon, 'IconType': iconType,
        'Tier': tier, 'Sport': sport, 'ScopeType': scopeType, 'ScopeId': scopeId,
        'Season': season, 'Edition': edition, 'Context': context, 'Date': date,
        'Source': source,
      };
}
```

- [ ] **Step 6: Run test — expect PASS.** **Step 7: Commit**

```bash
git add lib/models/trophy.dart lib/models/award.dart test/trophy_model_test.dart
git commit -m "feat(trophies): Trophy + Award models"
```

---

### Task 2: FirebasePaths additions

**Files:** Modify `lib/core/constants/firebase_paths.dart`

- [ ] **Step 1: Add constants** (after the tournament block, ~line 98):

```dart
  // -- Trophies / Awards --
  static const String trophies = 'Trophies';
  static String trophy(String trophyId) => '$trophies/$trophyId';
  static String userAwards(String uid) => '$users/$uid/Awards';
  static String userAward(String uid, String awardId) =>
      '$users/$uid/Awards/$awardId';
```

- [ ] **Step 2: Run** `flutter analyze lib/core/constants/firebase_paths.dart` → No issues. **Step 3: Commit**

```bash
git add lib/core/constants/firebase_paths.dart
git commit -m "feat(trophies): firebase path helpers"
```

---

### Task 3: Deterministic award id helper (PURE) + test

**Files:** Create `lib/services/award_engine.dart`; Test `test/award_engine_test.dart`

- [ ] **Step 1: Failing test** `test/award_engine_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/services/award_engine.dart';

void main() {
  test('deterministic id is stable + sanitized', () {
    final a = deterministicAwardId('t1', 'tournament', 'summer cup/2026', '2026');
    final b = deterministicAwardId('t1', 'tournament', 'summer cup/2026', '2026');
    expect(a, b);
    expect(a.contains('/'), false);
    expect(a.contains(' '), false);
  });

  test('different scope -> different id', () {
    expect(deterministicAwardId('t1', 'tournament', 'a', '1'),
        isNot(deterministicAwardId('t1', 'tournament', 'b', '1')));
  });
}
```

- [ ] **Step 2: Run — FAIL.** **Step 3: Implement** (start the file):

```dart
/// Pure award-recipient computation. No Firebase imports.

/// Stable, RTDB-key-safe id for an auto-award so re-finishing overwrites
/// instead of duplicating. RTDB keys cannot contain . # $ [ ] /.
String deterministicAwardId(
    String trophyId, String scopeType, String scopeId, String seasonOrEdition) {
  final raw = '${trophyId}_${scopeType}_${scopeId}_$seasonOrEdition';
  return raw.replaceAll(RegExp(r'[.#$\[\]/\s]'), '_');
}
```

- [ ] **Step 4: Run — PASS. Step 5: Commit**

```bash
git add lib/services/award_engine.dart test/award_engine_test.dart
git commit -m "feat(trophies): deterministic award id helper"
```

---

### Task 4: TrophyService — catalog CRUD + manual assign/remove

**Files:** Create `lib/services/firebase/trophy_service.dart`; provider in the same file.

- [ ] **Step 1: Implement** (no unit test — thin Firebase wrapper; covered by manual + analyze). Follow `TournamentService` patterns (extends `FirebaseService`).

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/core/constants/firebase_paths.dart';
import 'package:infinite_app_manager/models/award.dart';
import 'package:infinite_app_manager/models/trophy.dart';
import 'package:infinite_app_manager/services/firebase/firebase_service.dart';

class TrophyService extends FirebaseService {
  Future<List<Trophy>> getCatalog() async {
    final map = await getMap(FirebasePaths.trophies);
    final list = map.entries
        .where((e) => e.value is Map)
        .map((e) => Trophy.fromMap(e.key, Map<dynamic, dynamic>.from(e.value)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Create (push) or update (existing id) a catalog trophy. Returns id.
  Future<String> saveTrophy(Trophy t) async {
    final base = ref(FirebasePaths.trophies);
    final node = t.id.isEmpty ? base.push() : base.child(t.id);
    await node.set(t.toFirebaseMap());
    return node.key ?? t.id;
  }

  Future<void> deleteTrophy(String trophyId) async =>
      ref(FirebasePaths.trophy(trophyId)).remove();

  /// Manual assignment: writes one Award under the user (push id).
  Future<void> assignAward(String uid, Award award) async {
    final node = ref(FirebasePaths.userAwards(uid)).push();
    await node.set(award.toFirebaseMap());
  }

  Future<void> removeAward(String uid, String awardId) async =>
      ref(FirebasePaths.userAward(uid, awardId)).remove();

  Future<List<Award>> getUserAwards(String uid) async {
    final map = await getMap(FirebasePaths.userAwards(uid));
    return map.entries
        .where((e) => e.value is Map)
        .map((e) => Award.fromMap(e.key, Map<dynamic, dynamic>.from(e.value)))
        .toList();
  }
}

final trophyServiceProvider = Provider((ref) => TrophyService());
final trophyCatalogProvider =
    FutureProvider<List<Trophy>>((ref) => ref.watch(trophyServiceProvider).getCatalog());
```

- [ ] **Step 2: Run** `flutter analyze lib/services/firebase/trophy_service.dart` → No issues. **Step 3: Commit**

```bash
git add lib/services/firebase/trophy_service.dart
git commit -m "feat(trophies): TrophyService catalog CRUD + assign"
```

---

### Task 5: Built-in trophy icon map (Manager)

**Files:** Create `lib/ui/trophies/trophy_icons.dart`

- [ ] **Step 1: Implement** — map built-in keys to Material icons (Manager UI uses icons, not assets, to keep it light) + tier colors.

```dart
import 'package:flutter/material.dart';

const Map<String, IconData> kTrophyIcons = {
  'trophy_gold': Icons.emoji_events,
  'medal': Icons.military_tech,
  'boot': Icons.sports_soccer,
  'gloves': Icons.sports_handball,
  'shield': Icons.shield,
  'star': Icons.star,
  'basketball': Icons.sports_basketball,
  'football': Icons.sports_football,
  'cup': Icons.emoji_events_outlined,
};

const List<String> kTrophyIconKeys = [
  'trophy_gold', 'medal', 'boot', 'gloves', 'shield', 'star',
  'basketball', 'football', 'cup',
];

Color tierColor(String tier) {
  switch (tier) {
    case 'silver': return const Color(0xFFB0B6BF);
    case 'bronze': return const Color(0xFFCD7F32);
    default: return const Color(0xFFFFC107); // gold
  }
}

IconData trophyIconData(String key) => kTrophyIcons[key] ?? Icons.emoji_events;
```

- [ ] **Step 2: analyze → clean. Step 3: Commit**

```bash
git add lib/ui/trophies/trophy_icons.dart
git commit -m "feat(trophies): built-in icon map + tier colors"
```

---

### Task 6: Trophy Catalog page (list + add/edit/delete)

**Files:** Create `lib/ui/trophies/trophy_catalog_page.dart`

- [ ] **Step 1: Implement** a `ConsumerWidget` reading `trophyCatalogProvider`. List each trophy (`Icon(trophyIconData(t.icon), color: tierColor(t.tier))`, title `t.name`, subtitle `'${t.kind == 'auto' ? 'Auto · ${t.rule}' : 'Manual'}${t.sport.isEmpty ? '' : ' · ${t.sport}'}'`). FAB → `_TrophyEditorDialog`. Long-press / trailing delete → confirm → `deleteTrophy`. The editor dialog fields:
  - Name `TextField`.
  - Kind `SegmentedButton`/dropdown: Auto | Manual.
  - If Auto: Rule dropdown filtered by sport — valid rules: `champion, runnerUp, thirdPlace, goldenBoot, mostAssists, bestGoalie, defensivePlayer` (the engine's `kRuleKeys`, Task 11). Show only rules whose sport applies (see `ruleSports` in Task 11) or all when sport == ''.
  - Sport dropdown: `['', 'Futsal', 'Soccer', 'Basketball', 'Flag Football']` ('' shown as "Any").
  - Icon picker: a `Wrap` of `kTrophyIconKeys` rendering each `Icon`, selected highlighted.
  - Tier: 3 chips gold/silver/bronze.
  - Save → `Trophy(id: existing?.id ?? '', ..., createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch)` → `trophyService.saveTrophy` → `ref.invalidate(trophyCatalogProvider)`.

  Follow the existing dialog style in `manage_rosters_page.dart` `_PlayerEditorDialog` and tiles in `manage_venues_page.dart`. Use `ScaffoldMessenger` for save feedback.

- [ ] **Step 2: Run** `flutter analyze lib/ui/trophies/trophy_catalog_page.dart` → No issues. **Step 3: Commit**

```bash
git add lib/ui/trophies/trophy_catalog_page.dart
git commit -m "feat(trophies): catalog list + editor dialog"
```

---

### Task 7: Add `profileUrl` to MyUser + user-picker; Assign Trophy page

**Files:** Modify `lib/models/my_user.dart`; Create `lib/ui/trophies/assign_trophy_page.dart`

- [ ] **Step 1: Add `profileUrl`** to `MyUser` — add field, constructor param, and `profileUrl: json['ProfileUrl']` in `fromJson` (so the picker can show avatars). Keep existing fields.

- [ ] **Step 2: Implement `assign_trophy_page.dart`** (`ConsumerStatefulWidget`):
  - Read `trophyCatalogProvider` (pick a trophy) and `usersProvider` (`Map<String, MyUser>`).
  - Step 1 of the form: choose a trophy (list/dropdown of catalog).
  - Step 2: **searchable user picker** — `TextField` filtering `users.values` by `fullName.toLowerCase().contains(query)` (copy `users_page.dart:50–58`); show `CircleAvatar` from `profileUrl` + name; select one (capture its uid = map key).
  - Step 3: `Context` `TextField` (e.g. "Futsal · Season 5" or "Summer Cup 2026").
  - Submit → build `Award(id:'', trophyId: t.id, name: t.name, icon: t.icon, iconType: t.iconType, tier: t.tier, sport: t.sport, scopeType: 'tournament', scopeId: '', season: '', edition: '', context: contextText, date: _todayMMDDYYYY(), source: 'manual')` → `trophyService.assignAward(uid, award)` → success snackbar.
  - Add a `_todayMMDDYYYY()` helper using `DateFormat('MMddyyyy')` (intl).

- [ ] **Step 3: analyze both files → clean. Step 4: Commit**

```bash
git add lib/models/my_user.dart lib/ui/trophies/assign_trophy_page.dart
git commit -m "feat(trophies): MyUser.profileUrl + Assign Trophy page with user picker"
```

---

### Task 8: Register `/trophies` route + dashboard/menu entry

**Files:** Modify `lib/router/app_router.dart`; add a menu/nav entry.

- [ ] **Step 1: Add route** as a peer of `/users` inside the `ShellRoute.routes`:

```dart
GoRoute(
  path: '/trophies',
  builder: (context, state) => const TrophyCatalogPage(),
  routes: [
    GoRoute(
      path: 'assign',
      builder: (context, state) => const AssignTrophyPage(),
    ),
  ],
),
```
Import both pages. In `TrophyCatalogPage` add an AppBar action / button that does `context.go('/trophies/assign')`.

- [ ] **Step 2: Add a nav entry** to reach `/trophies` — find where `/users` is surfaced in the master menu (the `MasterDetailShell` nav list) and add a "Trophies" item (`Icons.emoji_events`) navigating to `/trophies`, matching the existing items.

- [ ] **Step 3: Run** `flutter analyze` (whole app) → no new errors. **Step 4: Commit**

```bash
git add lib/router/app_router.dart lib/ui/**/master_detail_shell.dart
git commit -m "feat(trophies): /trophies + /trophies/assign routes + nav entry"
```

---

### Task 9: FAN — Award model + trophy icon map + assets

**Files:** Fan repo. Create `lib/model/award.dart`, `lib/misc/trophy_icons.dart`; add `assets/trophies/`; modify `pubspec.yaml`. Confirm on branch `zaya-trophies`.

- [ ] **Step 1: Confirm fan branch** (`git rev-parse --abbrev-ref HEAD` → `zaya-trophies`).

- [ ] **Step 2: Create `lib/model/award.dart`** — identical shape to the Manager `Award.fromMap` (Step 5, Task 1), same field names. (Read-only here; `toFirebaseMap` optional.)

- [ ] **Step 3: Create `lib/misc/trophy_icons.dart`** — same key→IconData map + `tierColor` as Manager Task 5 (Fan can use Material icons; built-in keys match). Also expose `String? trophyAssetFor(String key)` returning `'assets/trophies/$key.png'` for the bundled set if you prefer image assets; the cabinet (Task 10) uses IconData by default for parity and zero new art dependency.

- [ ] **Step 4: Bundle assets** — create `assets/trophies/` with a placeholder `.gitkeep` (the built-in icons render via IconData, so no PNGs are strictly required for 1A; the folder + pubspec line are added now for the "custom upload / image icon" path later). Add to `pubspec.yaml` assets:

```yaml
  assets:
     - assets/
     - assets/trophies/
     - .env
```

- [ ] **Step 5: Run** `flutter pub get` then `flutter analyze lib/model/award.dart lib/misc/trophy_icons.dart` → clean. **Step 6: Commit**

```bash
git add lib/model/award.dart lib/misc/trophy_icons.dart pubspec.yaml assets/trophies/.gitkeep
git commit -m "feat(trophies): fan Award model + icon map + assets dir"
```

---

### Task 10: FAN — Trophy Cabinet widget + wire into profile

**Files:** Create `lib/widgets/trophy_cabinet.dart`; Modify `lib/playerpage.dart`. Test `test/trophy_cabinet_test.dart`.

- [ ] **Step 1: Failing widget test** `test/trophy_cabinet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/widgets/trophy_cabinet.dart';

void main() {
  testWidgets('renders awards + empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrophyCabinet(awards: []))));
    expect(find.textContaining('No trophies'), findsOneWidget);

    const a = Award(id: 'a', trophyId: 't', name: 'Golden Boot', icon: 'boot',
        iconType: 'builtin', tier: 'gold', sport: 'Futsal', scopeType: 'tournament',
        scopeId: 'x', season: '', edition: '2026', context: 'Summer Cup 2026',
        date: '08302026', source: 'auto');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrophyCabinet(awards: [a]))));
    expect(find.text('Golden Boot'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — FAIL.** **Step 3: Implement `lib/widgets/trophy_cabinet.dart`** — a grid of trophy chips (icon in a tier-colored circle + name + context); empty state Text "No trophies yet — go win some! 🏆"; tap a trophy → `showModalBottomSheet` with name, sport, context, date. Use `trophyIconData`/`tierColor` from `lib/misc/trophy_icons.dart`.

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Wire into `lib/playerpage.dart`** — in `getPlayerData()` add `awards = await newClient.child("Users/${widget.uid}/Awards").get()` → parse into `List<Award>` (guard null/Map). Add `"Trophies"` handling: render `TrophyCabinet(awards: awards)` as a section in the profile (insertion point: the `ListView.builder` "else" branch / a new section per the reference). Place the cabinet near the top (above the per-sport stat tables) since it's the headline.

- [ ] **Step 6: Run** `flutter test test/trophy_cabinet_test.dart` + `flutter analyze lib/playerpage.dart lib/widgets/trophy_cabinet.dart` → clean. **Step 7: Commit**

```bash
git add lib/widgets/trophy_cabinet.dart lib/playerpage.dart test/trophy_cabinet_test.dart
git commit -m "feat(trophies): fan trophy cabinet on profile"
```

---

### Task 11 (Phase 1A close): Manual end-to-end verify

- [ ] Manager: `flutter analyze` + `flutter test` clean. Fan: same.
- [ ] Manual: define a "MVP" (manual, star, gold) trophy in `/trophies`; Assign it to a linked user; open that user's profile in the fan app → trophy appears in the cabinet. Build/install both apps to the device for the owner to confirm.

---

# PHASE 1B — Auto-awards on tournament Mark-Finished

### Task 12: Award engine — tournament placements + stat leaders (PURE) + tests

**Files:** Extend `lib/services/award_engine.dart`; Test `test/award_engine_test.dart`

- [ ] **Step 1: Add failing tests** for placements + leaders:

```dart
// placements: final winner=champion, loser=runnerUp; third-place match winner=third
// stat leaders: max value wins; ties share; zero excluded; bestGoalie uses (cleanSheets, saves)
```
Write concrete cases using `TournamentMatch` and `TournamentPlayer` test fixtures (team1Score/team2Score; player.goals/assists/saves/dpl/cleanSheets + uid).

- [ ] **Step 2: Implement** in `award_engine.dart`:

```dart
import 'package:infinite_app_manager/models/tournament_match.dart';
import 'package:infinite_app_manager/models/tournament_player.dart';

const List<String> kRuleKeys = [
  'champion','runnerUp','thirdPlace','goldenBoot','mostAssists','bestGoalie','defensivePlayer',
];
// which sports each rule is valid for ('' rules apply to any)
const Map<String, List<String>> ruleSports = {
  'champion': [], 'runnerUp': [], 'thirdPlace': [],
  'goldenBoot': ['Futsal','Soccer'], 'mostAssists': ['Futsal','Soccer','Basketball'],
  'bestGoalie': ['Futsal','Soccer'], 'defensivePlayer': ['Futsal','Soccer'],
};

class Placements { final String? champion, runnerUp, third;
  const Placements({this.champion, this.runnerUp, this.third}); }

String? _winner(TournamentMatch m) {
  if (m.status != 2) return null;
  if (m.team1Score > m.team2Score) return m.team1Id;
  if (m.team2Score > m.team1Score) return m.team2Id;
  return null;
}
String? _loser(TournamentMatch m) {
  if (m.status != 2) return null;
  if (m.team1Score > m.team2Score) return m.team2Id;
  if (m.team2Score > m.team1Score) return m.team1Id;
  return null;
}

Placements resolveTournamentPlacements(List<TournamentMatch> matches) {
  TournamentMatch? byStage(String s) {
    for (final m in matches) { if (m.stage == s) return m; }
    return null;
  }
  final fin = byStage('Final');
  final tp = byStage('Third Place');
  return Placements(
    champion: fin != null ? _winner(fin) : null,
    runnerUp: fin != null ? _loser(fin) : null,
    third: tp != null ? _winner(tp) : null,
  );
}

/// uids (non-empty) of players on [teamId].
List<String> teamPlayerUids(Map<String, List<TournamentPlayer>> rosters, String? teamId) {
  if (teamId == null) return const [];
  return [
    for (final p in (rosters[teamId] ?? const <TournamentPlayer>[]))
      if ((p.uid ?? '').isNotEmpty) p.uid!
  ];
}

/// uids of stat leaders for [rule] across all rostered players (ties shared).
List<String> statLeaderUids(Map<String, List<TournamentPlayer>> rosters, String rule) {
  final all = rosters.values.expand((l) => l).toList();
  int score(TournamentPlayer p) {
    switch (rule) {
      case 'goldenBoot': return p.goals;
      case 'mostAssists': return p.assists;
      case 'defensivePlayer': return p.dpl;
      case 'bestGoalie': return p.cleanSheets * 1000 + p.saves; // CS primary, saves tiebreak
      default: return 0;
    }
  }
  var max = 0;
  for (final p in all) { final s = score(p); if (s > max) max = s; }
  if (max <= 0) return const [];
  return [for (final p in all) if (score(p) == max && (p.uid ?? '').isNotEmpty) p.uid!];
}
```
(Confirm `TournamentPlayer` exposes `goals/assists/saves/dpl/cleanSheets/uid` — per exploration it does. Adjust names to the actual model.)

- [ ] **Step 3: Run — PASS. Step 4: Commit**

```bash
git add lib/services/award_engine.dart test/award_engine_test.dart
git commit -m "feat(trophies): pure tournament placements + stat-leader helpers"
```

---

### Task 13: TrophyService.awardForTournament + wire into Mark-Finished

**Files:** Modify `lib/services/firebase/trophy_service.dart`, `lib/ui/tournaments/tournament_dashboard_page.dart`

- [ ] **Step 1: Implement `awardForTournament`** in `TrophyService` — orchestrates (reads catalog + tournament data, computes via engine, writes deterministic awards). It needs tournament matches, rosters (as `Map<teamId, List<TournamentPlayer>>`), and header (sport, edition, name). Reuse `TournamentService.getMatches/getRosters/getTournament` (inject or instantiate). Pseudocode:

```dart
Future<int> awardForTournament(String tournamentId) async {
  try {
    final ts = TournamentService();
    final t = await ts.getTournament(tournamentId);
    if (t == null) return 0;
    final matches = await ts.getMatches(tournamentId);
    final rosters = await ts.getRosters(tournamentId); // Map<teamId, List<TournamentPlayer>>
    final catalog = (await getCatalog()).where((x) =>
        x.active && x.kind == 'auto' &&
        (x.sport.isEmpty || x.sport == t.sport)).toList();
    final placements = resolveTournamentPlacements(matches);
    final ctx = '${t.name} ${t.edition}'.trim();
    final date = _todayMMDDYYYY();
    int written = 0;
    for (final tr in catalog) {
      List<String> uids;
      switch (tr.rule) {
        case 'champion': uids = teamPlayerUids(rosters, placements.champion); break;
        case 'runnerUp': uids = teamPlayerUids(rosters, placements.runnerUp); break;
        case 'thirdPlace': uids = teamPlayerUids(rosters, placements.third); break;
        default: uids = statLeaderUids(rosters, tr.rule ?? ''); break;
      }
      for (final uid in uids) {
        final id = deterministicAwardId(tr.id, 'tournament', tournamentId, t.edition);
        final award = Award(id: id, trophyId: tr.id, name: tr.name, icon: tr.icon,
            iconType: tr.iconType, tier: tr.tier, sport: t.sport,
            scopeType: 'tournament', scopeId: tournamentId, season: '',
            edition: t.edition, context: ctx, date: date, source: 'auto');
        await ref(FirebasePaths.userAward(uid, id)).set(award.toFirebaseMap());
        written++;
      }
    }
    return written;
  } catch (e) { return 0; }
}
```
Add `_todayMMDDYYYY()` (intl). Confirm `getRosters` returns the needed shape; if it returns players keyed differently, adapt.

- [ ] **Step 2: Hook into Mark-Finished** — in `tournament_dashboard_page.dart` `SwitchListTile.onChanged`, after `await service.setTournamentFinished(tournamentId, val);` add: `if (val) { await ref.read(trophyServiceProvider).awardForTournament(tournamentId); }` with a snackbar "Awards distributed."

- [ ] **Step 3: Add a "Recompute Awards" ListTile** (copy the "Recalculate Stats" tile) → calls `awardForTournament` + snackbar with count.

- [ ] **Step 4: analyze → clean. Step 5: Commit**

```bash
git add lib/services/firebase/trophy_service.dart lib/ui/tournaments/tournament_dashboard_page.dart
git commit -m "feat(trophies): auto-award on tournament finish + Recompute Awards"
```

---

### Task 14 (Phase 1B close): Verify tournament automation

- [ ] Manager `flutter analyze` + `flutter test` clean.
- [ ] Manual: in the 16-team test tournament, define auto trophies (Champion gold-cup, Golden Boot, Best Goalie); ensure some roster players have a `uid`; Mark Finished → confirm those linked players' fan profiles show the trophies. Re-toggle Finished → no duplicates. Build/install both apps.

---

# PHASE 1C — Auto-awards on league-season finish

### Task 15: League standings + leaders engine (PURE) + tests

**Files:** Create `lib/services/league_standings_engine.dart`; Test `test/league_standings_engine_test.dart`

- [ ] **Step 1: Failing tests** — given a season's games (team1/team2 + scores) compute W/D/L/Pts standings and rank 1/2/3; given Line Ups (player stat maps per sport) compute the leader uids for a rule.

- [ ] **Step 2: Implement** pure functions:
  - `List<TeamRecord> leagueStandings(List<GameResult> games)` → sorted by Pts→GD→GS (futsal/soccer: 3/1/0; basketball/flag football: by wins, or points-for — match the league's existing convention; if none, use wins then point-diff). `TeamRecord{team, w,d,l,pf,pa,pts}`.
  - `leagueLeaderUids(Map<playerName, Map<statKey,num>> players, Map<playerName,String?> uids, String rule, String sport)` — per-sport stat key mapping:
    - Futsal: `goldenBoot`→Goals, `mostAssists`→Assists, `bestGoalie`→Saves.
    - Basketball: `mostPoints`→Total points (1*One+2*Two+3*Three), `mostRebounds`→Rebounds, `mostThreePointers`→ThreePoints, `mostAssists`→Assists(if present).
    - Flag Football: `mostTouchdowns`→Rush+Rec+Pass TDs, `mostInterceptions`→Interceptions.
  - Add the basketball/flag rules to `kRuleKeys`/`ruleSports` (Task 12) so the catalog editor offers them for those sports.
- [ ] **Step 3: Run — PASS. Step 4: Commit**

```bash
git add lib/services/league_standings_engine.dart test/league_standings_engine_test.dart
git commit -m "feat(trophies): pure league standings + per-sport leaders"
```

---

### Task 16: awardForLeagueSeason + wire into season-finish

**Files:** Modify `lib/services/firebase/trophy_service.dart`; the league season-finish UI (where `season_service.updateSeasonStatus(...true)` is called).

- [ ] **Step 1: Implement `awardForLeagueSeason(SportType sport, int season)`** — read the season's Line Ups (rosters w/ UID + stats) and Date/ games; compute standings (rank 1/2/3 → team players' uids) + per-sport stat leaders; write deterministic awards with `scopeType:'league'`, `scopeId: sport key`, `season: '$season'`, `context: '${sportLabel} · Season $season'`. Idempotent (deterministic id includes season). Reads use `SeasonService`/`lineup` helpers.

- [ ] **Step 2: Hook** — find where a league season is marked finished (`season_service.updateSeasonStatus(sport, season, true)`); after it, call `awardForLeagueSeason(sport, season)` + snackbar. Add a "Recompute Awards" affordance for leagues too.

- [ ] **Step 3: analyze → clean. Step 4: Commit**

```bash
git add lib/services/firebase/trophy_service.dart lib/ui/**/*season*.dart
git commit -m "feat(trophies): auto-award on league season finish"
```

---

### Task 17 (Phase 1C close): Verify league automation + full finish

- [ ] Both apps `flutter analyze` + `flutter test` clean.
- [ ] Manual: finish a league season with linked players → champion + per-sport leaders appear in cabinets; idempotent on recompute.
- [ ] Build/install both apps. Surface to owner. Do NOT merge to `zaya-features` until owner confirms on-device (per workflow). Then merge each repo's `zaya-trophies` → `zaya-features` (local), delete the feature branches.

---

## Self-Review

**Spec coverage:** Catalog (T6), auto/manual kinds + rules (T1,T6,T12,T15), extensible icons+tiers (T5,T9), manual assign + user picker (T7), `Users/{uid}/Awards` storage (T4), auto on Mark-Finished tournament (T13) + league (T16), idempotent ids (T3,T12), identity/uid skip (T12 `teamPlayerUids`/`statLeaderUids` filter non-empty uid), fan cabinet (T10), additive paths (T2), assets (T9). All spec sections mapped.

**Placeholder scan:** UI tasks (T6, T7, T8, T16 hook) describe widgets via concrete field lists + reference existing patterns rather than full widget code — acceptable for UI glue; the implementer reads the named reference file first. Pure/data/service tasks have complete code.

**Type consistency:** `Trophy`/`Award` field names identical across Manager+Fan; `deterministicAwardId` signature stable T3→T12→T13→T16; rule keys centralized in `kRuleKeys`/`ruleSports`; `Placements`, `teamPlayerUids`, `statLeaderUids` signatures consistent T12→T13.

**Note for implementers:** verify exact `TournamentPlayer` getter names (`goals/assists/saves/dpl/cleanSheets/uid`) and `TournamentService.getRosters` return shape before T12/T13; adapt names if the model differs. Confirm the league season-finish call site before T16 (may need a small UI addition if no finish toggle exists yet).
