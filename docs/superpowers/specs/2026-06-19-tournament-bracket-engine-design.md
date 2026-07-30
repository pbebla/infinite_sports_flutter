# Tournament Bracket Engine + Continuous Knockout — Design Spec

**Date:** 2026-06-19
**Status:** Approved by owner (FotMob refs; "winners auto-advance"; "drag from any round to the final")
**Branches:** Manager `zaya-predictions` (feeders + resolver), fan `zaya/knockout-redesign` (continuous bracket). Data setup via Firebase CLI.
**Apps:** Manager (authoring + resolution) · Fan (bracket UI). No Cloud Function (resolution runs Manager-side, where games are scored).

---

## 1. Overview
Make knockout brackets self-populating: when a group finishes or a knockout game ends, winners **auto-advance** into the next round — no manual placing. The fan sees one **continuous, finger-draggable bracket** (Round of 16 → QF → SF → Final) connected by lines, with the Final as a hero card and 3rd-place beneath it. Plus a 16-team test tournament to verify it end-to-end.

## 2. Data model — bracket "feeders"
Each knockout `Tournaments/{tid}/Matches/{mid}` may carry feeder sources instead of fixed teams:
- `Team1Source` / `Team2Source` (strings):
  - `"G:<group>:<rank>"` — that group's Nth-placed team, e.g. `"G:A:1"` (Group A winner), `"G:B:2"` (Group B runner-up).
  - `"W:<matchId>"` — winner of a prior match.
  - `"L:<matchId>"` — loser of a prior match (3rd-place feeders = `L:` of the two semis).
- Resolved `Team1Id`/`Team2Id` are written by the resolver once a source is decided. A fixed `Team1Id` with no source is honored as-is (manual placement still works).

## 3. Resolver (Manager-side, pure helper + service call)
Pure `bracket_resolver.dart`: `resolveBracketAssignments(matches, groupStandings) → Map<matchId, {team1Id?, team2Id?}>`.
- **Group source `G:<grp>:<rank>`** resolves only when ALL of that group's matches are finished; value = the team at that rank in the group's standings (rank by Pts → GD → GS, the existing standings order).
- **`W:<mid>` / `L:<mid>`** resolve when match `mid` is finished (winner/loser).
- Returns only newly-resolvable assignments (idempotent; re-running is safe).
Wire-up: after the Manager writes a match result (end match / score edit / undo), call `resolveBracket(tid)` → compute group standings (reuse the Manager stats engine) → `resolveBracketAssignments` → write the resolved `Team1Id`/`Team2Id`. This also re-resolves correctly if an edit flips a group position.

## 4. Manager UI — feeder authoring
In the Manage Bracket match editor, for knockout matches each team slot can be: a **fixed team** (as today) OR a **source**:
- "Group {X} — {1st/2nd/…}" (from the tournament's groups), or
- "Winner of {match label}" / "Loser of {match label}" (from earlier knockout matches).
Saving writes `Team1Source`/`Team2Source`. (When building the standard bracket, QF slots use group sources, SF use `W:` of QFs, Final uses `W:` of SFs, 3rd uses `L:` of SFs.)

## 5. Fan UI — continuous draggable bracket (`knockout_tab.dart`)
Replace the chip-only switching with ONE horizontally-scrollable bracket spanning all rounds, finger-draggable end-to-end:
- Each round is a column of boxed cards; **connector lines** join each pair to its successor in the next column; the **Semifinal connects into the Final**.
- The **Final** renders as the hero card (blue gradient / champion home-color tint + trophy) at the right end of the scroll.
- **3rd place** sits **below the Final**, smaller (FotMob-style) — NOT connected by a bracket line.
- Round chips remain as quick-jumps (scroll-to via a ScrollController) but dragging reaches every round including the Final.
- Unresolved slots show the **feeder placeholder** ("Group A 1st", "Winner QF1") with a shield, until the resolver fills the real team.
- Cards: solid dark-grey box (dark) / light card (light); NO inner divider line; venue + date/time shown only while **upcoming/live** (hidden once finished); tap a card → that match's detail page.

## 6. 16-team test tournament (data setup, CLI) + RESET
Wipe & rebuild `test-tournament-2026` from scratch (owner-approved, destructive):
- Clear all match scores/activity/status/clocks, `Predictions`, `Leaderboard`.
- 16 teams (with `HomeColor` for champion theming) in 4 groups A–D (4 each); rosters so player-award questions resolve.
- Group fixtures: round-robin (6 per group = 24). Knockout: 4 QF (`G:A:1 vs G:B:2`, `G:C:1 vs G:D:2`, `G:B:1 vs G:A:2`, `G:D:1 vs G:C:2`), 2 SF (`W:qf*`), Final (`W:sf*`), 3rd (`L:sf*`).
- Keep `PredictionConfig.Open=true` + the seeded q_winner/q_score so predictions/teaser work. Reset = fresh, unplayed (Status 0), no predictions — owner can play + predict from scratch.

## 7. Testing
- **Pure (Manager):** `resolveBracketAssignments` — group source resolves only when group complete; W/L resolve on finish; ties/standings order; idempotency; manual-fixed teams untouched.
- **Manager:** feeder editor round-trips `Team1Source`/`Team2Source`; ending a match advances the dependent slot.
- **Fan widget:** bracket renders placeholders for unresolved feeders; final hero + bronze; tap → match detail.
- **Manual:** play out the 16-team tournament — group tables rank 1–4; finishing all group games seeds the QFs automatically; QF/SF winners advance; champion tints the final; drag across all rounds; predict each game.

## 8. Review checklist (Paul/Bronsin)
- New additive fields `Matches/{mid}/Team1Source|Team2Source`; resolver writes `Team1Id/Team2Id` (no destructive overwrite of a manually-set id without a source). Manager-side resolution (no new Cloud Function). Fan bracket is a `knockout_tab.dart` rework + connector painter across N columns.
