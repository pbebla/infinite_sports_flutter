# Live Stats Everywhere — Design Spec (Cohesion Spec 1 of 3)

**Date:** 2026-06-14
**Status:** Approved by owner (brainstorm 2026-06-14, mockups approved)
**Branch:** `zaya/live-scores` (fan app only — no Manager change)
**Part of:** "Live Tournament Cohesion" wave. Spec 2 = match-card cohesion; Spec 3 = substitution in/out. Build order: this one first.

---

## 1. Overview & problem

Today the fan app's Table, Player Stats, and Team Stats screens read **stored** values (`TournamentTeam.points/wins/…`, `TournamentPlayer.goals/assists/…`) that the Manager only recomputes **when a match goes Final**, and the fan loads those once. So during a live match nothing moves. The owner wants **everything that shows scores/stats to update live** — table reorders by points as goals go in, stat leaders climb in real time — with no waiting for full-time, consistently across every tournament screen.

We already stream live matches (`TournamentService.watchMatches`). The fix: **derive standings and player/team stats on the fan side, live, from the streamed matches** — instead of reading stored values. This mirrors the Manager's existing `tournament_stats_engine.dart` logic, on the client, fed by live data.

### In scope (fan app only)
1. Pure fan-side stats engine (parity copy of the Manager's) computing standings + player counters from a list of matches + rosters.
2. Wire Table, Player Stats, Team Stats tabs to the **derived live** values.
3. "Playing now" indicator on the group table (the two teams in a `status==1` match: subtle green row tint + small pulsing green dot by their names).
4. Matches/fixtures ordering: **live first, then upcoming by date/time, then finished last** — NO dimming/greying of finished rows.

### Out of scope
- Substitution in/out (Spec 3) and location card / header (Spec 2).
- Any Manager change (the engine derives from data the Manager already writes).

---

## 2. Architecture

### New unit: `lib/misc/tournament_stats_engine.dart` (pure, parity copy)
A direct port of the Manager's `lib/services/tournament_stats_engine.dart` into the fan app. No Flutter imports. Public surface (mirrors Manager):

```
class TeamStanding { gp, w, d, l, gs, gc, pts; int get gd => gs - gc; }
class PlayerCounters { goals, assists, saves, dpl, cleanSheets, yellowCards, redCards; }
class ComputedTournamentStats {
  Map<String teamId, TeamStanding> standings;
  Map<String "teamId/playerName", PlayerCounters> players;
}
ComputedTournamentStats computeTournamentStats({
  required List<TournamentMatch> matches,
  required Map<String, List<TournamentPlayer>> rosters,
});
```

**Standings** are computed from match **scores** (W/D/L/GF/GA/Pts) — and a **live (`status==1`) match counts its current score** toward the table, so the table moves as goals go in. **Player counters** are computed from match **activity** (the timeline events), so goals/assists/saves/etc. tally live. (Substitutions contribute no counter — already true in the Manager engine; Spec 3 keeps that.)

Parity note: copy the Manager engine's event-type handling verbatim so fan/Manager never disagree at full-time. A unit test asserts the same fixtures the Manager engine is tested against.

### Wiring in `lib/tournamentdetail.dart`
`_matches` is already live-streamed; `_teams` and `_rosters` are loaded once (team/player **identities** don't change mid-match — only their stats do, and we now derive those). On each build, compute:
```dart
final stats = computeTournamentStats(matches: _matches, rosters: _rosters);
```
Pass `stats` (plus `_teams`, `_matches`, `_rosters`) into the three tabs. Because `_matches` updates trigger `setState`, the derived stats — and therefore every tab — update live.

### Tabs consume derived values (not stored)
- **`table_tab.dart`**: sort + display from `stats.standings[teamId]` (gp/w/d/l/gs/gc/gd/pts) instead of `team.points` etc. Group grouping still uses `team.group`.
- **`playerstats_tab.dart`**: leaders from `stats.players` (keyed `teamId/playerName`, joined to the roster `TournamentPlayer` for name/photo/team) instead of `player.statByName`.
- **`teams_tab.dart`**: team W/D/L from `stats.standings`.
- Fallback: if a team/player has no derived entry yet (no matches played), show zeros (not the stored value) — keeps it consistent.

### "Playing now" indicator (`table_tab.dart`)
Given `_matches`, build the set of team ids in any `status==1` match. A team row in that set gets: a light green background tint (`Color(0x1A0A7D2C)`) and a small pulsing green dot before the name (reuse the pulsing-dot widget pattern from `live_filter_bar.dart`). Both teams of the live match light up together (your Brazil/Morocco reference).

### Ordering (`fixtures_tab.dart`, used by `tournament_day_view.dart` & home)
Replace the current stage→date→bracket sort with a **status-priority** sort, no opacity change:
1. `status==1` (live) first,
2. then `status==0` (upcoming) by `date` then `time` then `bracketPosition`,
3. then `status==2` (finished) last (by date then bracket).
Knockout-stage ordering (bracket position) is preserved within each status group. Finished rows render normally (no dim).

---

## 3. Edge cases
- **No matches played** → empty/zero standings; tabs show their existing empty states.
- **Live match score decreasing (undo)** → standings recompute downward automatically (pure function of current scores).
- **Player in activity but not in roster** → engine already tracks "unknown players" set (kept from Manager parity); leaders list shows roster players only, consistent with today.
- **Tie-breaking** in standings sort: points, then GD, then GF (same as today's table) — keep identical so order is stable.
- **Finished tournament** → all matches `status==2`; table equals final standings; everything still derives correctly.

## 4. Testing
1. **Unit (pure):** `test/tournament_stats_engine_test.dart` — port the Manager engine's test fixtures: standings from finished + live scores, player counters from activity, GD/sort, unknown players. Assert parity with the Manager's expected outputs.
2. **Widget:** table reorders when a match's score changes; "playing now" tint+dot appears only for `status==1` teams; fixtures list orders live→upcoming→finished.
3. **Manual (owner):** start a group match in Manager, record goals → fan Table reorders live, Player Stats leaders climb, the two playing teams are tinted with a green dot, and the match sits at the top of the list until Final, then drops below upcoming.

## 5. Review checklist (Paul & Bronsin)
- New pure engine on the fan side mirrors the Manager engine — no behavioral divergence at Final.
- No Manager change; no new DB writes; no new dependencies.
- Tabs now derive from live matches; stored `team.points`/`player.goals` become display-fallback-free (derived is source of truth in the tournament UI).
