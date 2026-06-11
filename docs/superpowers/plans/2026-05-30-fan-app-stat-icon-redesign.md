# Fan-App Stat-Icon Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the match-timeline and fixtures leader-strip stat icons with the owner's custom flat icon set, and add a permanent "What the icons mean" legend to every match's Facts tab.

**Architecture:** Bundle 13 raster icons under `assets/stat_icons/`. Add one shared, single-responsibility file `lib/tournament_tabs/stat_icon.dart` exposing two pure mapping functions (`statIconAsset`, `statIconAssetForStat`) and a `StatIcon` widget that renders an asset on a white rounded chip (keeps dark line-art visible in dark mode). Both `match_facts_tab.dart` and `fixtures_tab.dart` consume this shared unit. No Firebase/manager-app changes; legacy league icons untouched.

**Tech Stack:** Flutter / Dart, `flutter_test`. Existing dependencies only — no new packages (we are *removing* a `font_awesome_flutter` usage from two files).

**Working directory / branch:** Repo `infinite_sports_flutter`, branch `zaya/tournament-enhance-app-manager`, work directly in the main checkout (NOT a worktree — the owner tests on-device from this directory). Keep all commits LOCAL; do not push unless the owner explicitly says so.

---

## File Structure

| File | Responsibility |
|---|---|
| `assets/stat_icons/*.png` (13) | The owner's icon artwork, bundled with the app. **New.** |
| `lib/tournament_tabs/stat_icon.dart` | Single source of truth: event-type → asset mapping + the white-chip `StatIcon` widget. **New.** |
| `test/stat_icon_test.dart` | Unit tests for the two pure mapping functions. **New.** |
| `lib/tournament_tabs/match_facts_tab.dart` | Timeline uses `StatIcon`; dead helpers removed; legend added. **Modify.** |
| `lib/tournament_tabs/fixtures_tab.dart` | Leader strip uses `StatIcon`. **Modify.** |
| `pubspec.yaml` | Register `assets/stat_icons/`. **Modify.** |

**Event-type → asset map (authoritative — used in code and tests):**

| eventType (lowercased) | asset |
|---|---|
| `goal` | `assets/stat_icons/goal.png` |
| `own goal` | `assets/stat_icons/own_goal.png` |
| `penalty goal` | `assets/stat_icons/goal_penalty.png` |
| `penalty missed` | `assets/stat_icons/penalty_missed.png` |
| `penalty saved` | `assets/stat_icons/penalty_saved.png` |
| `save` | `assets/stat_icons/save.png` |
| `assist` | `assets/stat_icons/assist.png` |
| `substitution` | `assets/stat_icons/substitution.png` |
| `yellow card` | `assets/stat_icons/yellow_card.png` |
| `red card` | `assets/stat_icons/red_card.png` |
| `second yellow` | `assets/stat_icons/second_yellow.png` |
| `foul` | `assets/stat_icons/foul.png` |
| `dpl` | `assets/stat_icons/dpl.png` |

**Fixtures stat-key → eventType (for `statIconAssetForStat`):** `goals`→`goal`, `assists`→`assist`, `saves`→`save`, `dpl`→`dpl`.

---

## Task 1: Bundle the icon assets and register them

The owner's 13 icons were already sliced (labels removed, verified clean) into the brainstorm scratch folder. They use `ic_*.png` names there; this task copies them into `assets/stat_icons/` with the final asset names from the map above, then registers the folder.

**Files:**
- Create: `assets/stat_icons/goal.png` … (13 files, see map)
- Modify: `pubspec.yaml` (assets list, around line 102-104)

- [ ] **Step 1: Create the asset folder and copy + rename the 13 sliced icons**

Run this PowerShell command (uses the verified-clean sliced icons from the brainstorm scratch dir):

```powershell
$src = "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\.superpowers\brainstorm\1648-1780173619\content"
$dst = "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\assets\stat_icons"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$map = @{
  "ic_goal.png"          = "goal.png"
  "ic_own_goal.png"      = "own_goal.png"
  "ic_goal_pen.png"      = "goal_penalty.png"
  "ic_pen_missed.png"    = "penalty_missed.png"
  "ic_pen_saved.png"     = "penalty_saved.png"
  "ic_save.png"          = "save.png"
  "ic_assist.png"        = "assist.png"
  "ic_sub.png"           = "substitution.png"
  "ic_yellow.png"        = "yellow_card.png"
  "ic_red.png"           = "red_card.png"
  "ic_second_yellow.png" = "second_yellow.png"
  "ic_foul.png"          = "foul.png"
  "ic_dpl.png"           = "dpl.png"
}
foreach ($k in $map.Keys) { Copy-Item (Join-Path $src $k) (Join-Path $dst $map[$k]) -Force }
Get-ChildItem $dst | Select-Object Name, Length
```

Expected: 13 files listed (goal.png, own_goal.png, goal_penalty.png, penalty_missed.png, penalty_saved.png, save.png, assist.png, substitution.png, yellow_card.png, red_card.png, second_yellow.png, foul.png, dpl.png), each non-zero length.

If the source dir `1648-1780173619` no longer exists, substitute the newest `*/content` folder under `.superpowers\brainstorm\` that contains `ic_goal.png` (e.g. `1679-1780177606`).

- [ ] **Step 2: Register the folder in `pubspec.yaml`**

Find the assets list (around lines 102-104):

```yaml
  assets:
     - assets/
     - .env
```

Change it to:

```yaml
  assets:
     - assets/
     - assets/stat_icons/
     - .env
```

(Flutter does not recurse into subfolders automatically, so the subfolder must be listed explicitly.)

- [ ] **Step 3: Fetch packages so the asset manifest regenerates**

Run: `flutter pub get`
Expected: completes without error (`Got dependencies!`).

- [ ] **Step 4: Commit**

```bash
git add assets/stat_icons pubspec.yaml
git commit -m "feat: bundle custom stat icons under assets/stat_icons"
```

---

## Task 2: Shared `stat_icon.dart` helper + unit tests (TDD)

**Files:**
- Create: `lib/tournament_tabs/stat_icon.dart`
- Test: `test/stat_icon_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/stat_icon_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

void main() {
  group('statIconAsset', () {
    test('maps all 13 known event types to their asset', () {
      expect(statIconAsset('goal'), 'assets/stat_icons/goal.png');
      expect(statIconAsset('own goal'), 'assets/stat_icons/own_goal.png');
      expect(statIconAsset('penalty goal'), 'assets/stat_icons/goal_penalty.png');
      expect(statIconAsset('penalty missed'), 'assets/stat_icons/penalty_missed.png');
      expect(statIconAsset('penalty saved'), 'assets/stat_icons/penalty_saved.png');
      expect(statIconAsset('save'), 'assets/stat_icons/save.png');
      expect(statIconAsset('assist'), 'assets/stat_icons/assist.png');
      expect(statIconAsset('substitution'), 'assets/stat_icons/substitution.png');
      expect(statIconAsset('yellow card'), 'assets/stat_icons/yellow_card.png');
      expect(statIconAsset('red card'), 'assets/stat_icons/red_card.png');
      expect(statIconAsset('second yellow'), 'assets/stat_icons/second_yellow.png');
      expect(statIconAsset('foul'), 'assets/stat_icons/foul.png');
      expect(statIconAsset('dpl'), 'assets/stat_icons/dpl.png');
    });

    test('is case-insensitive and trims surrounding whitespace', () {
      expect(statIconAsset('GOAL'), 'assets/stat_icons/goal.png');
      expect(statIconAsset('  Yellow Card  '), 'assets/stat_icons/yellow_card.png');
    });

    test('returns null for unknown or empty event types', () {
      expect(statIconAsset('teleport'), isNull);
      expect(statIconAsset(''), isNull);
    });
  });

  group('statIconAssetForStat', () {
    test('maps fixtures stat keys to the matching icon asset', () {
      expect(statIconAssetForStat('goals'), 'assets/stat_icons/goal.png');
      expect(statIconAssetForStat('assists'), 'assets/stat_icons/assist.png');
      expect(statIconAssetForStat('saves'), 'assets/stat_icons/save.png');
      expect(statIconAssetForStat('dpl'), 'assets/stat_icons/dpl.png');
    });

    test('returns null for unknown stat keys', () {
      expect(statIconAssetForStat('rebounds'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/stat_icon_test.dart`
Expected: FAIL — compile error, `Target of URI doesn't exist: 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart'`.

- [ ] **Step 3: Create the implementation**

Create `lib/tournament_tabs/stat_icon.dart`:

```dart
import 'package:flutter/material.dart';

/// Maps a stored event-type string (case-insensitive) to the owner's custom
/// icon asset path. Returns null for unknown event types.
String? statIconAsset(String eventType) {
  switch (eventType.toLowerCase().trim()) {
    case 'goal':
      return 'assets/stat_icons/goal.png';
    case 'own goal':
      return 'assets/stat_icons/own_goal.png';
    case 'penalty goal':
      return 'assets/stat_icons/goal_penalty.png';
    case 'penalty missed':
      return 'assets/stat_icons/penalty_missed.png';
    case 'penalty saved':
      return 'assets/stat_icons/penalty_saved.png';
    case 'save':
      return 'assets/stat_icons/save.png';
    case 'assist':
      return 'assets/stat_icons/assist.png';
    case 'substitution':
      return 'assets/stat_icons/substitution.png';
    case 'yellow card':
      return 'assets/stat_icons/yellow_card.png';
    case 'red card':
      return 'assets/stat_icons/red_card.png';
    case 'second yellow':
      return 'assets/stat_icons/second_yellow.png';
    case 'foul':
      return 'assets/stat_icons/foul.png';
    case 'dpl':
      return 'assets/stat_icons/dpl.png';
    default:
      return null;
  }
}

/// Maps a fixtures leader-strip stat key to the matching icon asset, so the
/// strip reuses the same artwork as the timeline. Returns null if unknown.
String? statIconAssetForStat(String statName) {
  switch (statName.toLowerCase().trim()) {
    case 'goals':
      return statIconAsset('goal');
    case 'assists':
      return statIconAsset('assist');
    case 'saves':
      return statIconAsset('save');
    case 'dpl':
      return statIconAsset('dpl');
    default:
      return null;
  }
}

/// Renders a stat icon on a white rounded chip so the dark line-art stays
/// readable in both light and dark themes. Pass a resolved asset path (e.g.
/// from [statIconAsset]); if it is null, a neutral fallback icon is shown so
/// an unexpected event type never crashes or shows a broken image.
class StatIcon extends StatelessWidget {
  final String? asset;
  final double size;

  const StatIcon({super.key, required this.asset, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: asset == null
          ? Icon(Icons.sports, size: size * 0.62, color: Colors.grey)
          : Image.asset(asset!, fit: BoxFit.contain),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/stat_icon_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/tournament_tabs/stat_icon.dart test/stat_icon_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/tournament_tabs/stat_icon.dart test/stat_icon_test.dart
git commit -m "feat: add shared StatIcon widget + event-type asset mapping"
```

---

## Task 3: Use the new icons in the match timeline (`match_facts_tab.dart`)

Swap the timeline icon rendering to `StatIcon`, delete the now-dead helpers, and drop the `font_awesome_flutter` import. This also removes the "(P)" penalty tag (the dedicated penalty icons replace it) and the special-case `⚽` emoji / `shoePrints` / second-yellow `Stack`.

**Files:**
- Modify: `lib/tournament_tabs/match_facts_tab.dart` (imports line 2; delete lines 70-134; replace `_eventIcon` lines 136-203)

- [ ] **Step 1: Swap imports**

In `lib/tournament_tabs/match_facts_tab.dart`, replace line 2:

```dart
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
```

with:

```dart
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
```

- [ ] **Step 2: Delete the dead `_iconForEvent` and `_colorForEvent` methods**

Delete the entire `_iconForEvent` method (currently lines 70-101) and the entire `_colorForEvent` method (currently lines 103-134). Both are only referenced inside `_eventIcon`, which is replaced in the next step, so they become unused.

- [ ] **Step 3: Replace the `_eventIcon` method**

Replace the entire `_eventIcon` method (currently lines 136-203, the big block with the `⚽` emoji, `FaIcon`, second-yellow `Stack`, and `(P)` branches) with this:

```dart
  Widget _eventIcon(String eventType) {
    return StatIcon(asset: statIconAsset(eventType), size: 24);
  }
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/tournament_tabs/match_facts_tab.dart`
Expected: `No issues found!` (in particular, no "unused element" warnings for the deleted methods and no unused-import warning — `StatIcon` and `statIconAsset` are now used; `font_awesome_flutter` is gone).

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_tabs/match_facts_tab.dart
git commit -m "feat: render match timeline with custom StatIcon set"
```

---

## Task 4: Add the icon legend to the Facts tab (`match_facts_tab.dart`)

Add a `_buildIconLegend` method and show it at the bottom of the Facts tab on every match — including the empty-state path.

**Files:**
- Modify: `lib/tournament_tabs/match_facts_tab.dart` (add method before `build`; edit the empty-state early return; append legend to the main `Column`)

- [ ] **Step 1: Add the `_buildIconLegend` method**

Insert this method immediately before the `@override\n  Widget build(BuildContext context) {` line (currently around line 360):

```dart
  Widget _buildIconLegend(BuildContext context) {
    // [eventType, label] for all 13 icons, in approved order.
    const items = <List<String>>[
      ['goal', 'Goal'],
      ['own goal', 'Own goal'],
      ['penalty goal', 'Goal by penalty'],
      ['penalty missed', 'Missed penalty'],
      ['penalty saved', 'Saved penalty'],
      ['save', 'Save (goalkeeper)'],
      ['assist', 'Assist'],
      ['substitution', 'Substitution'],
      ['yellow card', 'Yellow card'],
      ['red card', 'Red card'],
      ['second yellow', 'Second yellow (= red)'],
      ['foul', 'Foul'],
      ['dpl', 'DPL — Defensive Play (Tackle, Steal, Block)'],
    ];

    Widget cell(List<String> item, {required bool rightColumn}) {
      return Padding(
        // Right column is nudged toward the middle, away from the left line.
        padding: EdgeInsets.only(left: rightColumn ? 14 : 0, bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StatIcon(asset: statIconAsset(item[0]), size: 30),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item[1],
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
          ],
        ),
      );
    }

    // Two columns running downward: pair items (left, right). A trailing odd
    // item occupies the left column only.
    final List<Widget> rows = [];
    for (int i = 0; i < items.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cell(items[i], rightColumn: false)),
          Expanded(
            child: (i + 1 < items.length)
                ? cell(items[i + 1], rightColumn: true)
                : const SizedBox.shrink(),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            'What the icons mean',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(children: rows),
        ),
      ],
    );
  }
```

- [ ] **Step 2: Show the legend in the empty-state early return**

Find the early-return block in `build` (currently lines 374-383):

```dart
    if (allEvents.isEmpty && team1Players.isEmpty && team2Players.isEmpty) {
      return Center(
        child: Text(
          match.matchStatus.isPending ? 'Match not started yet' : 'No activity recorded',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }
```

Replace it with (wrap the message in a scroll view and append the legend so it shows on every match):

```dart
    if (allEvents.isEmpty && team1Players.isEmpty && team2Players.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  match.matchStatus.isPending ? 'Match not started yet' : 'No activity recorded',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            _buildIconLegend(context),
          ],
        ),
      );
    }
```

- [ ] **Step 3: Append the legend to the main `Column`**

Find the main return's `Column` children, ending with `_buildMatchLeaders(context),` (currently line 428):

```dart
          else
            ...allEvents.map((e) => _buildEventRow(context, e)),
          _buildMatchLeaders(context),
        ],
      ),
    );
```

Add `_buildIconLegend(context),` after `_buildMatchLeaders(context),`:

```dart
          else
            ...allEvents.map((e) => _buildEventRow(context, e)),
          _buildMatchLeaders(context),
          _buildIconLegend(context),
        ],
      ),
    );
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/tournament_tabs/match_facts_tab.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_tabs/match_facts_tab.dart
git commit -m "feat: add icon legend to bottom of match Facts tab"
```

---

## Task 5: Use the new icons in the fixtures leader strip (`fixtures_tab.dart`)

**Files:**
- Modify: `lib/tournament_tabs/fixtures_tab.dart` (remove FA import line 3; add stat_icon import; replace `statDefs`+chip-icon block in `_buildLeadersStrip` lines 76-118)

- [ ] **Step 1: Swap imports**

In `lib/tournament_tabs/fixtures_tab.dart`, delete line 3:

```dart
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
```

and add this import (keep imports alphabetical-ish; place after the `model/tournamentteam.dart` import on line 8):

```dart
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
```

- [ ] **Step 2: Replace the stat definitions and chip-icon rendering**

In `_buildLeadersStrip`, replace this block (currently lines 76-118 — the `statDefs` list through the end of the `for (final def in statDefs)` loop):

```dart
    final statDefs = [
      {'label': 'G', 'icon': null, 'faIcon': null, 'emoji': '⚽', 'color': Colors.green, 'stat': 'goals'},
      {'label': 'A', 'icon': null, 'faIcon': FontAwesomeIcons.shoePrints, 'emoji': null, 'color': Colors.black87, 'stat': 'assists'},
      {'label': 'S', 'icon': Icons.back_hand, 'faIcon': null, 'emoji': null, 'color': Colors.purple, 'stat': 'saves'},
      {'label': 'DPL', 'icon': Icons.sports_kabaddi, 'faIcon': null, 'emoji': null, 'color': Colors.teal, 'stat': 'dpl'},
    ];

    final chips = <Widget>[];
    for (final def in statDefs) {
      final stat = def['stat'] as String;
      final sorted = allPlayers
          .where((p) => p.statByName(stat) > 0)
          .toList()
        ..sort((a, b) => b.statByName(stat).compareTo(a.statByName(stat)));
      if (sorted.isEmpty) continue;
      final top = sorted.first;
      final value = top.statByName(stat);
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (def['emoji'] != null)
                Text(def['emoji'] as String, style: const TextStyle(fontSize: 12))
              else if (def['faIcon'] != null)
                FaIcon(def['faIcon'] as FaIconData, size: 12, color: def['color'] as Color)
              else
                Icon(def['icon'] as IconData, size: 12, color: def['color'] as Color),
              const SizedBox(width: 3),
              Text(
                '${top.name} $value',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
```

with:

```dart
    const stats = ['goals', 'assists', 'saves', 'dpl'];

    final chips = <Widget>[];
    for (final stat in stats) {
      final sorted = allPlayers
          .where((p) => p.statByName(stat) > 0)
          .toList()
        ..sort((a, b) => b.statByName(stat).compareTo(a.statByName(stat)));
      if (sorted.isEmpty) continue;
      final top = sorted.first;
      final value = top.statByName(stat);
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatIcon(asset: statIconAssetForStat(stat), size: 18),
              const SizedBox(width: 4),
              Text(
                '${top.name} $value',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/tournament_tabs/fixtures_tab.dart`
Expected: `No issues found!` (no unused `font_awesome_flutter` import; `StatIcon`/`statIconAssetForStat` are used).

- [ ] **Step 4: Commit**

```bash
git add lib/tournament_tabs/fixtures_tab.dart
git commit -m "feat: render fixtures leader strip with custom StatIcon set"
```

---

## Task 6: Full verification + finishing

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: all tests pass (includes the new `test/stat_icon_test.dart` and the existing suite).

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: `No issues found!` If `flutter analyze` times out (a known issue in this repo per CLAUDE.md), re-run scoped to the touched files: `flutter analyze lib/tournament_tabs test/stat_icon_test.dart`.

- [ ] **Step 3: Owner on-device manual check (fan app)**

Ask the owner to run the **fan app** on their device/emulator and confirm:
1. Open a tournament match → **Facts** tab. Timeline events show the new icons on white chips, each row reading **icon + full player name** (no "— Goal" text, no "(P)" tag).
2. Scroll to the bottom of the Facts tab: the **"What the icons mean"** legend appears below Match Leaders, two columns running downward (left flush, right nudged toward the middle), all 13 icons with correct labels (DPL row reads "DPL — Defensive Play (Tackle, Steal, Block)").
3. Toggle **dark mode** (drawer/settings): icons stay clearly visible on their white chips.
4. Go to the **fixtures list**; on a **finished** match card the leader strip pills (G/A/S/DPL) show the new icons.
5. Confirm the legacy **Futsal / Basketball / Flag Football** league pages look unchanged.

- [ ] **Step 4: Finish the development branch**

Announce: "I'm using the finishing-a-development-branch skill to complete this work."
**REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch.
Note: this branch is the shared working branch in the main checkout (not a worktree) and commits stay LOCAL — do NOT push or merge unless the owner explicitly chooses that option.

---

## Notes for the implementer

- **Non-coder owner:** all device-verification requests must be in plain language and must name the app ("the fan app").
- **Do not** modify the manager app, Firebase schema, or the legacy league icon assets (`assets/goal.png`, `assets/assist.png`, `assets/foul.png`, `assets/yellow.png`, `assets/red.png`).
- **Do not** push to remote or merge without explicit owner confirmation. Keep commits local.
- There is a pre-existing uncommitted change to `test/widget_test.dart` from earlier work; leave it alone (do not stage it in these commits).
- `StatIcon` sizes (24 timeline / 18 fixtures / 30 legend) are starting values; the owner may want them nudged after seeing them on-device — that's a one-line tweak per call site, not a redesign.
