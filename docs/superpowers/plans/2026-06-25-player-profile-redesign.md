# Player Profile Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `lib/playerpage.dart` into a FotMob-style tabbed player profile (fixed hero + Profile/Stats/Career), tappable from anywhere, with context-aware sharing.

**Architecture:** Split the monolith into focused `lib/profile/` widgets driven by PURE, unit-tested helpers (`lib/misc/profile_stat_priority.dart`). Keep the existing uid-based league aggregation + Awards read; add tournament-by-uid history. Additive reads only. Reuse the trophy cabinet (sub-project #1) and the match-card share pipeline (RepaintBoundary → PNG → `path_provider` → `SharePlus`).

**Tech Stack:** Flutter/Dart, Firebase RTDB direct reads, share_plus + path_provider (already deps), existing `TrophyCabinet`/`Award`/`trophy_icons` + `ShareMatchCard`/`share_match_card_service`.

**Branch:** `zaya-profile-redesign` (off `zaya-trophies`, already created). All commits LOCAL.

**Spec:** `docs/superpowers/specs/2026-06-25-player-profile-redesign-design.md`

---

## Implementer pre-reqs (read before coding)
- `lib/playerpage.dart` (current monolith — the thing being split): `getPlayerData()` reads `Users/{uid}` → `First Name`/`Last Name`/`ProfileUrl`/`Information.{Height,Age,<Sport>Position}` + `Played` index → builds `tableEntries[sport][season] = (team, Color, Player)` via `extractPlayerStats`/`extractAFCStats`; reads `Users/{uid}/Awards` into `_awards`. Build = 125px header (photo+name) + `ListView` (index 0 `TrophyCabinet`, then per-sport `DataTable` + Career row).
- Player models `lib/model/{futsalplayer,basketballplayer,flagfootballplayer,soccerplayer}.dart` for stat field names (Futsal: goals/assists/saves; Basketball: total/rebounds/twoPoints/threePoints/onePoint/shotPercentage; FlagFootball: receptions/receivingTouchdowns/passBreakups/interceptions/passingTouchdowns/sacks/flagPulls; Soccer: goals/assists/saves). Position from `Information.<Sport>Position`.
- `lib/widgets/trophy_cabinet.dart` + `lib/model/award.dart` + `lib/misc/trophy_icons.dart` (reuse as-is).
- `lib/widgets/share_match_card.dart` + `lib/misc/share_match_card_service.dart` (copy the render+share pipeline + the `assets/infinitelarge_dark.png` footer logo).
- Tournament-by-uid history: `lib/misc/tournament_service.dart` (how tournaments + rosters are read; `TournamentPlayer.uid`).

---

# PHASE 2A — Tabbed profile

### Task 1: Pure profile helpers + tests

**Files:** Create `lib/misc/profile_stat_priority.dart`; Test `test/profile_stat_priority_test.dart`

- [ ] **Step 1: Failing test** `test/profile_stat_priority_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';

void main() {
  test('positionGroup classifies keepers/defenders/etc', () {
    expect(positionGroup('Futsal', 'GK'), 'GK');
    expect(positionGroup('Futsal', 'Goalkeeper'), 'GK');
    expect(positionGroup('Futsal', 'DEF'), 'DEF');
    expect(positionGroup('Futsal', 'Forward'), 'ATT');
    expect(positionGroup('Basketball', 'Guard'), 'GUARD');
    expect(positionGroup('Flag Football', 'QB'), 'QB');
    expect(positionGroup('Futsal', ''), 'ATT'); // default outfield
  });

  test('profileStatPriority orders by sport+position', () {
    expect(profileStatPriority('Futsal', 'GK').take(3).toList(),
        ['games', 'cleanSheets', 'saves']);
    expect(profileStatPriority('Futsal', 'DEF').take(3).toList(),
        ['games', 'dpl', 'assists']);
    expect(profileStatPriority('Futsal', 'ATT').take(2).toList(),
        ['games', 'goals']);
    expect(profileStatPriority('Basketball', 'GUARD').first, 'points');
  });

  test('detectKeeper uses position then stats', () {
    expect(detectKeeper({'saves': 1, 'goals': 0}, 'GK'), true);
    expect(detectKeeper({'saves': 10, 'goals': 1}, ''), true);  // stats dominate
    expect(detectKeeper({'saves': 0, 'goals': 5}, ''), false);
  });

  test('currentParticipation picks active, else most recent', () {
    final stints = [
      ParticipationStint(sport: 'Futsal', label: '2026', sortKey: 2026, team: 'Eagles', position: 'FWD', isActive: true),
      ParticipationStint(sport: 'Basketball', label: '2025', sortKey: 2025, team: 'Hawks', position: 'G', isActive: false),
    ];
    expect(currentParticipation(stints)!.sport, 'Futsal');
    final none = [stints[1]];
    expect(currentParticipation(none)!.sport, 'Basketball'); // fallback most recent
  });

  test('careerHistory sorts newest first', () {
    final stints = [
      ParticipationStint(sport: 'Basketball', label: '2025', sortKey: 2025, team: 'Hawks', position: 'G', isActive: false),
      ParticipationStint(sport: 'Futsal', label: '2026', sortKey: 2026, team: 'Eagles', position: 'FWD', isActive: true),
    ];
    expect(careerHistory(stints).first.sortKey, 2026);
  });
}
```

- [ ] **Step 2: Run — FAIL.** **Step 3: Implement `lib/misc/profile_stat_priority.dart`**

```dart
/// Pure helpers for the player profile. No Flutter imports.

/// A single competition the player took part in (league season or tournament).
class ParticipationStint {
  final String sport;       // 'Futsal' | 'Basketball' | 'Flag Football' | 'AFC San Jose' | 'Soccer'
  final String label;       // display year/season, e.g. '2026' or 'Season 5'
  final int sortKey;        // for ordering (year or season number; higher = newer)
  final String team;
  final String position;    // raw position string from data
  final bool isActive;      // season/tournament not finished
  final bool isTournament;
  final String scopeId;     // tournamentId or sport key (for tap-to-detail)

  ParticipationStint({
    required this.sport, required this.label, required this.sortKey,
    required this.team, required this.position, required this.isActive,
    this.isTournament = false, this.scopeId = '',
  });
}

/// Normalize a raw position string into a coarse group used for stat ordering.
String positionGroup(String sport, String position) {
  final p = position.toLowerCase().trim();
  final s = sport.toLowerCase();
  if (s.contains('basket')) {
    if (p.startsWith('g') || p.contains('guard')) return 'GUARD';
    return 'BIG'; // forward/center
  }
  if (s.contains('flag')) {
    if (p.contains('qb') || p.contains('quarter')) return 'QB';
    if (p.contains('wr') || p.contains('rb') || p.contains('recei') || p.contains('rush')) return 'SKILL';
    if (p.contains('def') || p.contains('db') || p.contains('lb')) return 'DEF';
    return 'SKILL';
  }
  // soccer / futsal
  if (p.contains('gk') || p.contains('keep') || p.contains('goalie')) return 'GK';
  if (p.contains('def') || p.contains('back')) return 'DEF';
  if (p.contains('mid')) return 'MID';
  return 'ATT';
}

const Map<String, Map<String, List<String>>> _priority = {
  'Futsal': {
    'GK': ['games', 'cleanSheets', 'saves', 'dpl'],
    'DEF': ['games', 'dpl', 'assists', 'goals'],
    'MID': ['games', 'goals', 'assists', 'dpl'],
    'ATT': ['games', 'goals', 'assists', 'dpl'],
  },
  'Basketball': {
    'GUARD': ['points', 'threePointers', 'rebounds', 'twoPointers', 'freeThrows'],
    'BIG': ['points', 'rebounds', 'threePointers', 'twoPointers', 'freeThrows'],
  },
  'Flag Football': {
    'QB': ['passTouchdowns', 'receptions', 'interceptions', 'flagPulls', 'sacks'],
    'SKILL': ['receivingTouchdowns', 'receptions', 'flagPulls', 'interceptions', 'sacks'],
    'DEF': ['interceptions', 'flagPulls', 'sacks', 'passBreakups'],
  },
};

/// Soccer/AFC + Tournament reuse the Futsal table (same stat vocabulary).
List<String> profileStatPriority(String sport, String group) {
  final table = _priority[sport] ?? _priority['Futsal']!;
  return table[group] ?? table.values.first;
}

/// True if the player should be treated as a keeper.
bool detectKeeper(Map<String, num> stats, String position) {
  if (positionGroup('Futsal', position) == 'GK') return true;
  final saves = stats['saves'] ?? 0;
  final cleanSheets = stats['cleanSheets'] ?? 0;
  final goals = stats['goals'] ?? 0;
  return (saves + cleanSheets) > goals && (saves + cleanSheets) > 0;
}

/// The player's current stint: an active one (highest sortKey), else the most
/// recent of any.
ParticipationStint? currentParticipation(List<ParticipationStint> stints) {
  if (stints.isEmpty) return null;
  final active = stints.where((s) => s.isActive).toList()
    ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  if (active.isNotEmpty) return active.first;
  final all = [...stints]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return all.first;
}

/// All stints newest-first.
List<ParticipationStint> careerHistory(List<ParticipationStint> stints) {
  final out = [...stints]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return out;
}
```

- [ ] **Step 4: Run — PASS.** **Step 5: Commit**

```bash
git add lib/misc/profile_stat_priority.dart test/profile_stat_priority_test.dart
git commit -m "feat(profile): pure stat-priority + participation helpers"
```

### Task 2: ProfileHero widget
**Files:** Create `lib/profile/profile_hero.dart`
- [ ] Build `ProfileHero` (StatelessWidget) taking: photoUrl, fullName, current `ParticipationStint?`, teamColor, the 3 headline stat values (label+value), trophy count, isKeeper. Gradient background tinted by teamColor (fallback brand). Circular photo (NetworkImage / `assets/portraitplaceholder.png` fallback). Name. Line "team · sport · #number · position" (number/position from the stint; for tournament show "Tournament (<name>)"). A 🧤 GOALIE chip when isKeeper. Below: the 4-box strip (3 stats + 🏆 trophy count). No data fetching — pure presentation.
- [ ] analyze clean. Commit `feat(profile): ProfileHero widget`.

### Task 3: Profile tab (bio + cabinet)
**Files:** Create `lib/profile/profile_tab.dart`
- [ ] `ProfileTab` takes the raw `Information` map + the `List<Award>`. Renders a **flexible info card**: render known fields in order if present — Height, Weight, Age, Preferred Foot (`Information['Foot']`/`PreferredFoot`), Preferred Hand — then render any **remaining** `Information` keys (excluding the per-sport `*Position` keys and ones already shown) with a humanized label (split camel/Pascal + spaces). Then `TrophyCabinet(awards: awards)`.
- [ ] analyze clean. Commit `feat(profile): Profile tab (flexible bio + cabinet)`.

### Task 4: Stats tab (competition selector + position-ordered stats)
**Files:** Create `lib/profile/stats_tab.dart`
- [ ] `StatsTab` takes a `Map<String, Map<String,num>>` of `competitionLabel → {statKey: value}` plus each competition's sport + position. A dropdown selects the competition (default first/current). Renders the selected competition's stats **ordered by `profileStatPriority(sport, positionGroup(sport, position))`**, mapping statKey → human label + the value; unknown/zero-but-tracked still shown. Use existing stat-name labels. (The page builds the map from `tableEntries` + tournament data in Task 6.)
- [ ] analyze clean. Commit `feat(profile): Stats tab`.

### Task 5: Career tab (history list)
**Files:** Create `lib/profile/career_tab.dart`
- [ ] `CareerTab` takes `List<ParticipationStint>` (already ordered via `careerHistory`) + a per-stint summary string + a hasTrophy flag + an onTap. Row: team logo (NetworkImage w/ fallback) + "{Sport/Tournament} · {label}" + summary stats + 🏆 marker. onTap → callback (Task 6 wires it to the existing per-season/tournament detail).
- [ ] analyze clean. Commit `feat(profile): Career tab`.

### Task 6: ProfilePage (assemble) + replace PlayerPage
**Files:** Create `lib/profile/profile_page.dart`; Modify `lib/playerpage.dart`
- [ ] Move `getPlayerData()`'s data-loading logic into `ProfilePage` (a `StatefulWidget` taking `uid`). Build, from the loaded data: the `List<ParticipationStint>` (one per sport-season + each AFC season + each tournament-by-uid); the `competition → stats` map for the Stats tab; the `Information` map; `_awards`. Determine `current = currentParticipation(stints)` and its teamColor; compute the hero's 3 headline stats from `profileStatPriority`.
- [ ] Scaffold: `AppBar('Profile')` + `TabBar(Profile/Stats/Career)` under the fixed `ProfileHero` (hero stays above the TabBarView). Body = `TabBarView` of the three tabs. Loading + (for an unlinked/empty player) a graceful "no data" state.
- [ ] Tournament-by-uid history: load tournaments and find rosters where a player has `uid == widget.uid` (reuse `tournament_service.dart`); add those as `ParticipationStint(isTournament: true)` + their stats.
- [ ] Make `PlayerPage` (existing public widget other screens call) a thin wrapper that returns `ProfilePage(uid: uid)` — so all current callers keep working.
- [ ] `flutter analyze lib/profile lib/playerpage.dart` clean; `flutter test`; commit `feat(profile): tabbed ProfilePage replaces monolithic profile`.

### Task 7 (2A close): verify + build/install
- [ ] analyze + full test green. Manual: open own profile → hero shows current sport/team/#/position + strip; Profile tab bio+cabinet; Stats tab competition switch; Career tab history + tap a row. Build/install fan app; surface to owner.

---

# PHASE 2B — Universal player → profile navigation

### Task 8: PlayerIdentity + openPlayerProfile helper
**Files:** Create `lib/profile/open_player_profile.dart`
- [ ] `class PlayerIdentity { final String? uid; final String displayName; }`. `void openPlayerProfile(BuildContext context, PlayerIdentity id)` → if `uid != null && uid.isNotEmpty` push `ProfilePage(uid: uid)`; else push `ProfilePage.limited(name: displayName)` (a constructor that shows the "not linked to an account yet" state with just the passed name). Add the `limited` path to `ProfilePage`.
- [ ] analyze clean. Commit `feat(profile): shared openPlayerProfile + limited state`.

### Task 9: Wire taps across surfaces
**Files:** Modify the player-listing widgets (confirm each by reading): tournament rosters/lineup tab, tournament match detail (scorers/leaders), `lib/tournament_tabs/*` player rows, league lineup/roster views, standings/tables, leaderboards, knockout cards.
- [ ] For each place a player name/row is shown, wrap it in an `InkWell`/`onTap` → `openPlayerProfile(context, PlayerIdentity(uid: <player uid if available>, displayName: <name>))`. Tournament players carry `uid`; league lineup entries carry `uid`; where only a name is available, pass uid: null.
- [ ] Do this surface-by-surface with a commit each (e.g. `feat(profile): tap player in <surface> → profile`). analyze after each.

### Task 10 (2B close): verify + build/install
- [ ] analyze + tests green. Manual: tap a player from a tournament roster, a league table, a leaderboard, a knockout card → profile opens (linked → full; unlinked → limited). Build/install; surface.

---

# PHASE 2C — Context-aware sharing

### Task 11: ShareProfileCard widgets
**Files:** Create `lib/widgets/share_profile_card.dart`
- [ ] Three fixed-size (e.g. 360×450) theme-independent cards mirroring `ShareMatchCard` style + the `assets/infinitelarge_dark.png` footer logo: `CabinetShareCard` (photo+name+current team/sport + trophy grid + "N trophies"); `StatsShareCard` (photo+name + selected competition + its position-ordered stat line); `CareerShareCard` (photo+name + headline totals: sports played, games, goals/scoring, 🏆 count).
- [ ] Widget test: each builds without overflow for a populated + empty case. Commit `feat(profile): share-card widgets (cabinet/stats/career)`.

### Task 12: Share service + AppBar button by active tab
**Files:** Create `lib/misc/share_profile_service.dart`; Modify `lib/profile/profile_page.dart`
- [ ] `shareProfile(BuildContext, {required Widget card, required String text})` — copy the render+share pipeline from `share_match_card_service.dart` (precache images → `RepaintBoundary.toImage(pixelRatio 3)` → temp PNG via `path_provider` → `SharePlus.instance.share(ShareParams(files,text))`), DRY by extracting the shared bits if practical.
- [ ] Add a Share `IconButton` to `ProfilePage`'s AppBar. On tap, pick the card by the current `TabController.index`: 0→`CabinetShareCard`, 1→`StatsShareCard(selected competition)`, 2→`CareerShareCard`. Build the appropriate share `text` (e.g. "Sam Stone — 5 trophies on Infinite Sports").
- [ ] analyze + tests green. Commit `feat(profile): context-aware share button`.

### Task 13 (2C close): full verify + build/install + surface
- [ ] Both `flutter analyze` + `flutter test` green. Manual: share each tab's card to WhatsApp; confirm the right card per tab. Build/install fan app; surface to owner. Do NOT merge to `zaya-features` until owner confirms; then (with the trophy + redesign work) merge the epic per the branch workflow.

---

## Self-Review
**Spec coverage:** hero (T2), Profile/bio+cabinet (T3), Stats+selector+priority (T4, T1), Career+history (T5, T1), assembly+replace monolith (T6), position-priority + keeper detect + current participation + career order (T1), universal nav + limited state (T8,T9), context-aware sharing (T11,T12), additive reads (T6). All spec sections mapped.
**Placeholder scan:** UI tasks (T2–T6, T9, T11) specify inputs + structure + reference the real `playerpage.dart`/`ShareMatchCard` patterns rather than full widget code — acceptable for UI built on an existing file the implementer reads first; pure/data (T1) is complete code.
**Type consistency:** `ParticipationStint`, `positionGroup`, `profileStatPriority`, `detectKeeper`, `currentParticipation`, `careerHistory`, `PlayerIdentity`, `openPlayerProfile` names consistent across tasks. Stat keys (`games/goals/assists/saves/cleanSheets/dpl/points/rebounds/...`) — implementer maps these to the actual Player model getters in T4/T6 (note: futsal league has no clean-sheet field today → GK 'cleanSheets' may be absent; show what's tracked, per spec).
