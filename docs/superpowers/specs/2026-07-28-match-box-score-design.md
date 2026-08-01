# Match Box Score (per-team game stats tabs) — Design

**Date:** 2026-07-28 · **Owner-approved decisions inline** · **Scope:** fan app, all sports, league AND tournament match pages, current and future competitions.

## Problem

The match page shows individual events in Summary and the roster in Lineup, but there is no
place to see **everyone's stats for that game** at a glance (the old app had this; FotMob's
box score is the reference).

## Decision summary (owner)

1. **Hide the Lineup tab** (do not delete `match_lineup_tab.dart` — future work will bring it
   back with players positioned on the field).
2. Match page tabs become **Summary | \<Team 1 name\> | \<Team 2 name\>** — one tab per team,
   each showing that team's players and their stats **for this match only**.
3. **Row identity stays frozen** while stat columns scroll horizontally: player photo
   (FotMob-style, initials fallback), name, jersey number pinned left.
4. **No "see more" button** — stat columns are always horizontally swipeable, ordered
   most-important-first.
5. **Auto-hide empty columns**: a stat column renders only if at least one player on either
   team recorded it in this match (consistent columns across both team tabs). If the match
   has no recorded stats at all, show the roster rows with a "No stats recorded yet" note —
   never a blank tab.
6. **Default sort: best performers first** (sport's primary stat, descending). **Tapping any
   column header sorts** by that stat, toggling desc/asc; tapping the name header sorts
   alphabetically.
7. Tapping a player row opens their profile (standard `openPlayerProfileById`).
8. **Live**: tallies recompute from the existing live match-activity streams during games.

## Per-sport columns (importance order, left → right)

| Sport | Columns |
|---|---|
| Soccer / Futsal | Goals, Assists, DPL, Saves, Fouls*, Yellow, Red |
| Basketball | PTS (derived FT + 2×2PT + 3×3PT), REB, AST, 3PM, 2PM, FTM, STL, BLK, TO, Fouls |
| Flag Football | TD, Pass TD, REC, INT, Flag Pulls, Sacks, Fouls*, Catch % (derived; only when targets exist) |

*Owner addition ("fun to have"): a Fouls column for EVERY sport whose match capture
records foul events — verify per sport against the stats-engine event types; where a
sport never records fouls the column is simply not defined (auto-hide covers partial
cases regardless).

## Architecture

- **One shared widget** `TeamBoxScoreTab` (new, `lib/match_tabs/team_box_score_tab.dart`)
  consumed by BOTH `tournament_match_detail.dart` and `league_match_detail.dart` — no
  per-surface forks. Inputs: the team's roster (players w/ photo, number), the match's
  per-player tallies, the sport's column defs, `onOpenPlayer`.
- **Pure column/tally layer** (`lib/match_tabs/box_score_columns.dart`): per-sport column
  definitions + a `visibleColumns(tallies)` filter (auto-hide) + sort helper. Reuses the
  existing single-match tally computation that already powers Match Leaders — extended where
  a sport records stats the leaders strip doesn't surface (cards, fouls, turnovers…).
- Frozen-left + horizontal-scroll built the same way the repo's existing sticky tables do.
- Theme-safe light+dark; Builder-wrapped rows (itemBuilder staleness rule); team-name tabs
  rely on the existing scrollable TabBar.

## Out of scope (explicit)

- Lineup-on-field with positioned player heads (future epic, noted in backlog).
- Season/tournament totals (already covered by Player Stats tabs).
- Manager app changes: none needed — all data already recorded per match.
