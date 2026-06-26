# Player Profile Redesign — Design Spec

**Date:** 2026-06-25
**Status:** Approved by owner (FotMob-style tabbed profile; gradient hero + boxed cards; sport/position-aware stats; context-aware sharing)
**App:** Fan (`infinite_sports_flutter`). Consumes the Trophy system (sub-project #1). No Manager changes here (Manager trophy-admin upgrades are a separate spec).
**Branch:** `zaya-profile-redesign` (off `zaya-trophies`). Commits local until owner says to push.
**Sub-project:** Player Profile epic — part 2 of 3 (1 = Trophy system ✅, 2 = this, 3 = extra delight).

---

## 1. Overview
Rebuild the fan player profile (`lib/playerpage.dart`) into a cohesive, FotMob-style **tabbed profile**: a fixed hero (photo, name, current team · sport · #number · position, position-ordered stat strip) over three tabs — **Profile**, **Stats**, **Career**. Tapping a player **anywhere in the app** opens their profile. Each tab can **share a branded image** (cabinet / season stats / career résumé) reusing the match-card share engine.

Identity is by Firebase Auth **uid** (already used by the current profile): league seasons aggregate by uid via `Users/{uid}/Played`; tournament appearances where the roster entry has a uid; trophies live at `Users/{uid}/Awards` (sub-project #1).

## 2. Fixed hero (all tabs)
- Back button; circular **profile photo** (`Users/{uid}/ProfileUrl`, placeholder fallback); **name**.
- **Current participation** line: team logo + **team · sport · #number · position**, read from the player's most recent **active** (not-finished) roster entry across leagues + tournaments (fallback: most recent of any). Sport label is one of **Futsal / Basketball / Flag Football / Soccer**, or **Tournament (<name>)** when the current stint is a tournament. A small **🧤 GOALIE** chip shows when the player is detected as a keeper (§4).
- **Stat strip:** the player's top **3 position-ordered stats for the current sport** (career totals in that sport) + a permanent **🏆 Trophies** count (all-time). Strip drops to fewer boxes if a stat isn't tracked.
- Gradient background tinted by the current team's color (fallback brand blue). Theme-independent enough to look good in light + dark.

## 3. Tabs
**Profile**
- **Info card (flexible):** known bio fields rendered when present — Height, Weight, Age/DOB, Preferred foot, Preferred hand, plus **any additional fields** found under `Users/{uid}/Information` (so new signup-form fields appear automatically without code changes; unknown keys are shown with a humanized label).
- **Trophy Cabinet** (from sub-project #1): boxed card, grid of trophies (icon in tier-colored ring + name); tap → detail sheet (where/when earned). Empty state encourages earning some.

**Stats**
- **Competition selector** (dropdown): each competition the player appears in — league sports (Futsal/Basketball/Flag Football) and each Tournament. Default = current.
- **Position-ordered stat list** for the selected competition (full list, not just the strip's 3). Career-in-that-competition totals; for a tournament it's that tournament's stats.

**Career**
- **Seasons & tournaments list**, newest first: each row = team logo + "{Sport/Tournament} · {year/season}" + that stint's key stats + 🏆 marker if a trophy was earned there. Tapping a row opens that stint's detail (the existing per-season/tournament stat view).

## 4. Position-priority stat config
A pure config maps **(sport, positionGroup) → ordered stat keys**. The hero strip shows the first 3 (that are tracked); the Stats tab shows all. Examples (final keys confirmed against the data at plan time):
- **Soccer/Futsal — GK:** Games, Clean Sheets, Saves, DPL
- **Soccer/Futsal — DEF:** Games, DPL, Assists, Goals
- **Soccer/Futsal — MID/FWD:** Games, Goals, Assists, DPL
- **Basketball — Guard:** Points, Assists*, 3-Pointers, Rebounds  · **Forward/Center:** Points, Rebounds, 3-Pointers  (*if Assists tracked; basketball league has no Assists key today — omit if absent)
- **Flag Football — QB:** Pass TDs, Completions, INTs-thrown · **WR/RB:** Rec/Rush TDs, Receptions, Flag Pulls · **DEF:** INTs, Flag Pulls, Sacks
- **Tournament (Soccer):** outfield → Goals, Assists, DPL · GK → Clean Sheets, Saves, DPL

**Goalie/position detection:** use the roster **Position** field when present (GK/Goalie → keeper; G/F/C, QB/WR/DEF, etc.). When position is missing/ambiguous, infer keeper if `saves + cleanSheets` clearly exceed `goals` for that stint. The detected position drives both the chip and the stat ordering.

## 5. Universal "tap a player → profile" navigation (Phase 2B)
A single shared entry point opens the profile for a given identity. A **player identity** is `{uid?, displayName, sourceContext}` — uid when known; without a uid the profile opens in a **limited state** showing the one context's info + a subtle "This player isn't linked to an account yet."

Wire taps into the player-listing surfaces: tournament rosters & match detail (lineups, scorers, leaders), league lineups/rosters, standings/tables, leaderboards, knockout cards. Each passes the player's uid (preferred) or name.

## 6. Context-aware sharing (Phase 2C)
A **Share** action in the profile AppBar generates a branded PNG for the **active tab**, reusing the match-card pipeline (`RepaintBoundary` → `toImage(pixelRatio 3)` → temp PNG via `path_provider` → `SharePlus.instance.share`):
- **Profile tab → Trophy Cabinet card:** photo + name + current team/sport + the trophy grid + "N trophies".
- **Stats tab → Stats card:** photo + name + the selected competition + its position-ordered stat line.
- **Career tab → Career card:** photo + name + headline totals (sports played, games, goals/scoring, 🏆 count) — a résumé flex.
All fixed-design (theme-independent), Infinite Sports logo footer (same asset as the match card). Logos/photo pre-loaded before capture.

## 7. Data & architecture
- **Pure helpers (unit-tested):** `profileStatPriority(sport, position)` → ordered keys; `detectKeeper(stats, position)`; `currentParticipation(...)` → the active team/sport/#/position; `careerHistory(...)` → ordered stints; share-card recipient/stat formatting. Kept separate from Firebase reads + widgets.
- **Reads (additive, no schema change):** `Users/{uid}` (bio, ProfileUrl, Played index), league `{sport}/{season}/Line Ups`, tournament `Tournaments/{id}/Rosters` + headers, `Users/{uid}/Awards`. The current profile already aggregates league career by uid — extend, don't replace.
- **File structure:** split the page into focused widgets — `profile/profile_page.dart` (scaffold + tabs + hero), `profile/profile_tab.dart`, `profile/stats_tab.dart`, `profile/career_tab.dart`, `profile/profile_hero.dart`, plus `misc/profile_stat_priority.dart` (pure) and `widgets/share_profile_card.dart`. (Today everything is in one `playerpage.dart`; this split keeps each file focused.)

## 8. Error / empty / edge states
- Unlinked player → limited profile (this context only) + "not linked" note; no crash.
- No trophies → friendly empty cabinet.
- A sport with no current active stint → hero shows the most recent stint; if none, a minimal header.
- Missing bio fields → simply omitted (no blanks).
- Share render/permission failure → "Couldn't create the card" snackbar (same as match card).

## 9. Testing
- **Unit:** stat-priority ordering per (sport, position); keeper detection; current-participation selection; career-history ordering; share-stat formatting.
- **Widget:** hero renders strip per sport/position; each tab builds for a linked + an unlinked player without overflow; cabinet empty + populated; share card builds per tab.
- **Manual:** open own profile; tap a player from a tournament, a league table, a leaderboard → profile opens; switch tabs; share each tab's card to WhatsApp.

## 10. Build phases
- **2A** — Tabbed profile (hero + Profile/Stats/Career), position-priority, flexible bio, cabinet display, career/history aggregation.
- **2B** — Universal player→profile navigation across surfaces.
- **2C** — Context-aware sharing (3 cards).

## 11. Out of scope (later)
- **Manager trophy-admin upgrades** (custom icon upload, retroactive structured assignment to past seasons/players, player→account linking) — separate companion spec.
- **Sub-project #3 delight:** auto-earned milestone badges, "Year in Review", compare-with-teammate, timeline animations.
- Self-serve "claim my profile" by players (admin linking covers it for now).

## 12. Review checklist (Paul)
- New `profile/` widget set replacing the monolithic `playerpage.dart`; pure stat-priority + participation helpers (tested); additive reads only (no schema change); reuses the share engine + `path_provider`; universal nav adds a shared route + taps wired across listing surfaces. Identity remains uid-based; unlinked players degrade gracefully.
