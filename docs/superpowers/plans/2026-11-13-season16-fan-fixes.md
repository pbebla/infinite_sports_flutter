# Season 16 fan-app fixes: logos that refresh, seed placeholders, a bracket with byes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three things Futsal Season 16 (live since 2026-11-13) needs from the fan app, to ride the next store build: new team logos show on phones that already have the app; "3rd Place"-style seed placeholders behave like the existing "Winner of QF1" placeholders; the league Playoffs tab draws a 6-team bracket (1st and 2nd skip the quarterfinals) without overlapping cards.

**Architecture:** Small, separate changes behind existing seams: the team-logo cache in `lib/misc/utility.dart` / `lib/misc/league_service.dart`, the placeholder predicate in `lib/misc/schedule_display.dart`, and the bracket layout in `lib/tournament_tabs/knockout_tab.dart` fed by the league `Playoffs/Slots` wiring already parsed in `lib/misc/league_playoffs_view.dart`.

**Tech stack:** Flutter fan app. Branch `zaya-review-fixes` (add commits only; do not push).

**Spec:** this document. Live data it must render (do not change data): `Futsal/16/Playoffs` = `{Format: 8, ThirdPlace: false, Slots: {qf1: {team1Seed: 3, team2Seed: 6, gameRef: {date: '01312027', index: 1}, winnerTo: 'sf1'}, qf2: {team1Seed: 4, team2Seed: 5, gameRef: {date: '01312027', index: 2}, winnerTo: 'sf2'}, sf1: {team2Seed: 2, gameRef: {date: '02072027', index: 0}, winnerTo: 'f1'}, sf2: {team2Seed: 1, gameRef: {date: '02072027', index: 1}, winnerTo: 'f1'}, f1: {gameRef: {date: '02142027', index: 0}}}}`. Games: Jan 31 `1st Place v 2nd Place` (Stage `friendly`), `3rd Place v 6th Place` (quarterfinal, qf1), `4th Place v 5th Place` (quarterfinal, qf2); Feb 7 `Winner of QF1 v 2nd Place` (sf1), `Winner of QF2 v 1st Place` (sf2); Feb 14 `Winner of SF1 v Winner of SF2` (f1). The Manager fills team1 of a game from its feeder and replaces "Nth Place" with the real team once the regular season is complete.

## Global constraints

- Live screens use `onValue` streams or `once()`. **No Realtime Database `.get()`** (iOS returns wrong data).
- A failed read is not a fact; keep the existing loading and error states.
- Light AND dark from `Theme.of(context).colorScheme`; layouts hold at 360 px; text scale 1.3; no pop-in; tappable team names are never underlined.
- Tournament brackets (the other user of `KnockoutTab`) must look and behave exactly as today.
- Do not touch `ios/` or `android/`.

## Review focus

1. A phone whose saved copy of `Logo Urls` predates Season 16 shows the Season 16 crests after this change without reinstalling (first open may show shields once; they must fill in without a restart).
2. A standard 4-team and 8-team bracket lays out pixel-for-pixel as before.
3. In the 6-team bracket no two cards overlap at 360 px, each semifinal is level with its single feeder quarterfinal, and each connector joins only real feeder pairs.
4. "3rd Place" is not tappable into a team page and gets the neutral placeholder icon wherever "Winner of QF1" does; a real team that merely contains the word "Place" (e.g. "Park Place FC") is still a real team.
5. Logo refresh never blocks first paint and never throws when offline.

---

### Task 1: Team logos refresh on existing installs

**Problem:** `getAllTeamLogo()` (`lib/misc/utility.dart` ~846) reads `Logo Urls` once with `once()` and memoises it in the global `teamLogos` for the session. With the on-disk database cache on (`enableRtdbPersistenceUnlessEmulator`, `lib/misc/rtdb_emulator.dart`), `once()` answers from the phone's saved copy and never refreshes it; nothing streams `Logo Urls`. Proven on the emulator 2026-11-13: Season 16 crests stay blank shields across cold starts although `Logo Urls/Futsal/16` exists.

**Files:** `lib/misc/utility.dart`, `lib/misc/league_service.dart` (`leagueLogoUrls`), any widget that reads `teamLogos` / `leagueLogoUrls` and must repaint; tests under `test/`.

**Interfaces (Produces):**
- A single live subscription to `Logo Urls` (and `AFC San Jose/Logo URL`), started once (first call to `getAllTeamLogo()` or app start) and kept for the app's lifetime, that replaces the global `teamLogos` on every event and bumps a `ValueNotifier<int> teamLogosVersion` (or equivalent `Listenable`).
- `getAllTeamLogo()` keeps its signature and completes as soon as the FIRST event arrives (the saved copy, as today), bounded by the existing read timeout convention (`lib/misc/bounded_read.dart`); it never throws for a timeout (empty map, as today's failure path).
- Crest-showing league widgets (fixtures/day view, match page header, standings, the playoffs bracket team rows via the teams map) rebuild when `teamLogosVersion` changes, so a crest that was a shield fills in without a restart. Find every reader with `grep -rn "teamLogos\|leagueLogoUrls" lib` and cover them all or justify in the report.

- [ ] Failing tests first: a fake logo source emits an old map (no season 16) then a new one; a widget showing a Season 16 crest shows the shield, then the image, with no restart; `getAllTeamLogo()` resolves on the first event; a source that errors or never answers leaves shields and no exception.
- [ ] Implement; full `flutter test`; commit.

### Task 2: Seed placeholders are placeholders

**Files:** `lib/misc/schedule_display.dart` (`isPlaceholderTeam`), its tests.

- `isPlaceholderTeam(name)` also returns true for an ordinal place name: exactly `^\d{1,2}(st|nd|rd|th) Place$` (trimmed, case-insensitive). Nothing else changes; every existing caller (`league_day_view.dart`, `league_match_detail.dart`, `livescore.dart`, `scorepage.dart`, `fantasy/data/next_game.dart`) then treats "3rd Place" like "Winner of QF1".
- Check each caller still does something sensible for the new names (neutral icon, no team page, no logo lookup, predictions on a placeholder game behave as they do for "Winner of …" games) and list what you verified.

- [ ] Failing tests (the predicate table incl. "Park Place FC", "1st Place", "12th place ", "Winner of QF1", ""), implement, commit.

### Task 3: League bracket layout that follows the real wiring

**Problem:** `KnockoutTab._computeCenters` and the connector painter pair cards by index (`2k`, `2k+1` of the previous round). The Season 16 bracket has 2 quarterfinals and 2 semifinals, each semifinal fed by ONE quarterfinal (the other side is a seeded team with a bye), so the second semifinal is drawn on top of the first.

**Files:** `lib/tournament_tabs/knockout_tab.dart`, `lib/league_tabs/league_playoffs_tab.dart`, `lib/misc/league_playoffs_view.dart` (expose `winnerTo` per slot), tests.

**Interfaces:**
- `LeaguePlayoffSlot` gains `winnerTo` (String, '' when absent), parsed from `Slots/<id>/winnerTo`.
- `KnockoutTab` gains an optional `Map<String, List<String>>? feeders` — match id → the ids of the previous-round matches whose winners feed it. The league tab builds it from the slots (`winnerTo` + `gameRef` → league game ids). Tournaments pass nothing.
- Layout rule when `feeders` is given: first round evenly spaced as today; a later-round card with two feeders sits midway between them (as today); with ONE feeder it sits level with that feeder; with none it takes the next free row below the lowest card of its column. After placement, any two cards in a column closer than `_slotH + _slotGap` are pushed apart downward (and the push is carried to dependants) so cards never overlap. Connectors are drawn only from real feeders (one straight elbow for a single feeder).
- When `feeders` is null the code path is today's, unchanged.

- [ ] Failing tests: (a) Season 16 shape (2 QF, 2 SF, final) at 360 px: no card rectangles intersect, each SF centre equals its feeder QF centre, the final sits midway between the semifinals, exactly four connectors; (b) standard 8 and 4 with `feeders` given produce the same centres as without; (c) a tournament bracket (no `feeders`) golden positions unchanged; (d) the bye side shows "Seed #2" / "Seed #1" and the feeder side "Winner of QF1".
- [ ] Implement; full `flutter test`; analyzer clean on touched files; commit.

## Out of scope (recorded in the follow-up list)

The app-wide sweep of the remaining one-shot `once()` reads (88 call sites) — its own plan.
