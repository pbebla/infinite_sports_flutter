# Knockout FotMob Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Rebuild the fan Knockout tab to the FotMob look: boxed cards, connector lines, a Final hero card with trophy + champion theming, a Bronze-final card, kickoff times, tap-to-match.

**Architecture:** Rebuild `lib/tournament_tabs/knockout_tab.dart`. Chip selects a round; non-final rounds render boxed cards in a column with a connector-line CustomPainter to the next round; the Final chip renders a hero card (+ bronze). Uses existing `TournamentTeam.homeColor` for champion tint and `assets/trophy.png`. No schema change.

**Tech Stack:** Flutter (CustomPainter for connectors). Spec: `docs/superpowers/specs/2026-06-18-knockout-fotmob-design.md`.

## Ground rules
- Branch `zaya/knockout-redesign` (verify). Commits LOCAL. Stage exact paths; never `git add -A`; never stage PROJECT_REFERENCE.md/SoccerStats.png; `git restore pubspec.lock` if drifted.

### Task K1 — Knockout match card + Final hero + Bronze + champion theming
**Files:** rewrite/extend `lib/tournament_tabs/knockout_tab.dart`; test `test/knockout_tab_test.dart`.
- [ ] **Boxed match card** (`_KnockoutMatchCard`): venue (grey) + date/time; two team rows `[TeamLogo(24)] name … score`; loser struck-through+dimmed when finished, winner bold; TBD→shield+label; LIVE strip when live. Whole card `InkWell` → `Navigator.push(TournamentMatchDetailPage(match, teams, rosters:?, tournamentId, sport))`. (KnockoutTab currently lacks `rosters`/`sport` — add them as constructor params, default `const {}`/`''`, and have `tournamentdetail.dart` pass `_rosters` + the sport; confirm match-detail's required args and supply them.)
- [ ] **Final hero** (`_FinalHero`): full-width gradient card; row `[logo] score(pens) — Image.asset('assets/trophy.png', height 44) — score(pens) [logo]`; short names under logos; venue+date/time below. Champion tint: if finished, gradient from `winner.homeColor` (fallback `Color(0xFFFFB300)` gold). Penalties: only if `TournamentMatch` exposes them — READ the model; else omit.
- [ ] **Bronze card** (`_BronzeCard`): the `thirdPlace` match if present — compact card, both teams+scores, loser struck through. Omit if none.
- [ ] Tests: build a finished final `TournamentMatch` + `TournamentTeam`s (mirror `test/widget_test.dart`/knockout patterns) → hero renders both names + trophy; a boxed card shows score + struck-through loser. Keep green.
- [ ] `flutter analyze lib/tournament_tabs/knockout_tab.dart` clean; `flutter test` green. Commit (`knockout_tab.dart` + test + tournamentdetail.dart if changed).

### Task K2 — Bracket layout + connector lines
**Files:** `lib/tournament_tabs/knockout_tab.dart` (+ a `_BracketConnectorPainter`).
- [ ] Chip-driven body: **Final** chip → `_FinalHero` + `_BronzeCard` (scrollable, showcase). **Other** chips → the selected round's `_KnockoutMatchCard`s in a left column + the next round's cards faded on the right, with a **CustomPainter** drawing connector lines from each pair's right edge to the successor card's left edge (group matches by `bracketPosition`: matches 2k,2k+1 feed successor k). Use `dividerColor` for lines. If there is no next round, show just the column (no connectors).
- [ ] Keep TBD/elimination/live styling. Tap still → match detail.
- [ ] `flutter analyze` clean; `flutter test` green. Commit.

### Task K3 — Verify + build/install + surface
- [ ] `flutter test` + `flutter analyze lib/`; final review of the diff (light+dark readability, tap→match, champion tint, no schema/Watcher impact).
- [ ] Build + install fan APK on both devices. STOP and surface: open a tournament → Knockout → switch rounds (connectors), tap a card (match opens), Final chip (hero + bronze), finish the final (hero recolors to the winner's jersey). Ask light/dark feedback.

## Self-review
Covers spec §3 (chips, non-final bracket+connectors, final hero+bronze+champion, card styling), §4 edges (no-knockout, TBD, no-3rd, single-round, null homeColor), §5 tests. Penalties guarded behind a model check. Champion uses `TournamentTeam.homeColor`.
