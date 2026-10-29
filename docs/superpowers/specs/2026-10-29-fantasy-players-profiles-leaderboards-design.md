# Infinite Fantasy — Player profiles, market, leaderboards, Manager profiles

**Status:** described to and approved by the owner in chat 2026-10-29 ("go ahead");
this document awaits his read. Extends `2026-10-26-infinite-fantasy-design.md` and
`2026-10-28-fantasy-automation-newsdesk-design.md`. Owner reference mockups (the visual
target for §4–§6; follow their look, the text below wins where they differ):
`assets/2026-10-29-fantasy-round3/mockup-players-market.webp`,
`mockup-player-profile.webp`, `mockup-leaderboards.webp`.

Repos/branches: fan repo `infinite_sports_flutter` (app + `functions/`) and Manager
`InfiniteSportsManagerFlutter`, both on `zaya-fantasy`. House rules apply everywhere:
no RTDB `get()` in Flutter clients (streams / `once()` only; Manager guard test
enforces it), real-time streams on every screen, light + dark via colorScheme (no
hard-coded light fills), names wrap — never ellipsize, never underline, one fade
reveal instead of piecemeal loading pops, session caches for instant revisits,
destructive actions confirm, iOS parity (anything iOS-risky gets a "verify on
simulator" line in the PR).

---

## 1. Why

The owner wants Fantasy to feel like the Premier League's fantasy game: when a fan taps
a player they should see how he has actually done week by week (points, where they came
from, how his price moved), the market should make picking easy (sort by points / form /
price, see who is rising and falling), and the standings should show who is climbing.
On the admin side, a fantasy team name alone is not enough — the owner needs to know who
the real person behind a team is and be able to contact them.

Today: tapping a player opens a bottom sheet with his price, season totals and league
stats, but no weekly points and no price history; the server computes each player's
points-by-source during finalize and throws the breakdown away; the Leaderboards tab is
a podium + list with a "My Leagues" scope the owner doesn't want; the Manager's "Team
names" page lists team name + raw uid only. On the live Season 15 test season the engine
has never run (lock override is Open), so Leaderboards / PlayerTotals / PriceChanges are
empty and the owner cannot see any of these screens with data.

## 2. Goals, non-goals, anti-goals

**Goals**
1. A full-screen **fantasy player profile** reachable from every player tap in Fantasy.
2. Per-player **weekly points with a breakdown by source** and **weekly price moves**,
   saved by the server, readable by fans.
3. A redesigned **Players market** (photo rows, sorts, Price Risers / Price Fallers by
   position, watchlist).
4. A **Fantasy tab on the real Infinite profile**.
5. A redesigned **Leaderboards** tab (Overall / Gameweek with rank movement), mini-leagues
   hidden.
6. Manager **Fantasy profiles**: who each fantasy manager really is + their fantasy
   season at a glance.
7. **Test data**: the Season 15 test season filled with a replayed season so every new
   screen can be tested with real-looking numbers.

**Non-goals:** mini-leagues (hidden, code kept), minutes played (not tracked), injury /
availability status, pushing a message to a single manager, price predictions, a points
view inside the manager squad viewer (beyond tapping a player to open his profile).

**Anti-goals (would be failures even if it "works"):**
- Email or phone ever reaching the fan app or any fan-readable node.
- Test-fill writing anything outside `Fantasy/Futsal/15/`, or running while the engine
  is on Auto.
- Breaking finalize idempotency (reruns must still produce identical results).
- Screens that pop in piece by piece, or that show "0" where the truth is "no data yet".

## 3. Server: per-player weekly records (functions)

### 3.1 `PlayerWeekStats/<gw>/<name>` (new, public read)

Written by finalize for every market player, one `set` of the whole `<gw>` node (same
cadence/idempotency as `PlayerWeeks/<gw>`; reruns overwrite identically):

```
PlayerWeekStats/<gw>/<name> = {
  Pts:    int,                 // bonus-inclusive week points (== PlayerWeeks/<gw>/<name>)
  Played: bool,                // played in at least one game this week
  Games:  [ { Vs: "<team>", For: int, Against: int, Forfeit?: "won"|"lost" } ],
  Lines:  { <key>: { N: int, P: int } }   // week totals by source, zero lines omitted
}
```

- Line keys (stable, client maps them to labels): `plays`, `goals`, `assists`,
  `cleanSheet`, `saves`, `penSaved`, `penMissed`, `conceded`, `dpl`, `yellow`, `red`,
  `ownGoals`, `bonus`. `N` = count (games for `plays`/`cleanSheet`; bonus points for
  `bonus`), `P` = points. Lines sum across the week's games.
- To get stable keys, `ScoreLine` (TS `scoring.ts` and its Dart twin) gains a `key`
  field alongside the existing display `label`; labels and points are unchanged, so the
  golden fixtures and the match tab keep working (golden files get the extra field
  only if their comparison is strict — builder's call).
- A voided week writes `{Pts: 0, Played, Games, Voided: true}` (no `Lines`), matching
  how voided weeks score zero everywhere else. `PlayerWeeks` keeps real points as today.
- Players with no game that week: `{Pts: 0, Played: false, Games: []}`.

### 3.2 `PriceHistory/<gw>/<name> = int` (new, public read)

The price (tenths) each player had **during** gameweek `<gw>`, snapshotted once at that
week's lock, in the same once-only step that writes `PublishedPicks/<gw>`. This captures
owner manual price edits too. The move after a week stays where it is today:
`PriceChanges/<gw>/<name>` (Monday reprice delta, zeros omitted).

### 3.3 `PlayerTotals/<name>` gains fields (still public read)

```
{ points, ownershipPct,             // existing
  form:  int,   // tenths: average of the last 3 non-voided finalized weeks' Pts (a missed week counts 0)
  ppg:   int,   // tenths: season points ÷ games played (0 when no games)
  games: int }  // games played this season (sum of Played games across PlayerWeekStats)
```

Recomputed in the same stage that writes `PlayerTotals` today, so the market reads one
node for points / form / ownership instead of all weekly records.

### 3.4 Admin callable `getUserContact` (new)

`onCall({uid}) → {email: string|null, signInMethods: string[]}` — caller must exist in
`Admins/<auth.uid>`; reads Firebase Auth (`getUser`). Emails are not in RTDB; this is
the only way the Manager gets them. Never writes anything.

### 3.5 Rules

Both `database.rules.stage1.json` (live) and `database.rules.json` (stage 2):
`PlayerWeekStats` and `PriceHistory` public read, no client write;
`Watchlists/<uid>` read/write own uid only (value `true` per player name, keys
validated as strings ≤ 60); `TransferCosts` admin read (Manager profile needs it under
stage 2). Deploy with the functions.

### 3.6 Rollout / no backfill

These nodes only exist from deployment onward, and price history can't be rebuilt
exactly after the fact (manual price edits leave no record). No backfill tool: Fantasy
has never scored a real week, so this ships (functions + rules deployed) **before Season
16 Gameweek 1 locks** — a hard step in the launch checklist. Season 15 gets its data from
the test fill (§9).

## 4. Fan: fantasy player profile (new full page)

Replaces `market_player_sheet.dart` everywhere. Opened from: market rows, Price
Risers/Fallers rows and "View all", News "View player" and compact rows, the My Team
court chip's action sheet (new first item "Player profile"), the manager squad viewer
court, the Dream Team card, and match Fantasy tab rows. The squad picker's row tap still
picks (unchanged).

**Layout (owner mockup):**
- **Hero:** large photo with a dark gradient (initials over the team colour when no
  photo), team logo badge, name (wraps), "Team · Position". Star (watchlist) top-right.
- **Stat strip:** Price with this week's move underneath ("▲ $0.5M this week" green,
  "▼ $0.5M" red, "No change" muted; nothing before the first reprice), Total pts, PPG,
  Owned %.
- **Tabs:**
  - **Overview** — recent form bars (last 6 gameweeks, value on top, tap a bar to see that
    week's breakdown), next game ("Next: vs Nimrod · Sun 3 PM"), season stats grid from
    league stats (Goals, Assists, Saves, DPL, Clean sheets, Cards — no Minutes; a dash
    where the data doesn't exist).
  - **Stats** — "Where his points came from": season totals per source (e.g. "Goals ×13 —
    52 pts"), plus games played, PPG, form.
  - **Matches** — one row per gameweek, newest first: GW, opponent(s) and score, week
    points, season total to date; tap to expand the week's breakdown lines. Voided weeks
    show "Week voided — 0".
  - **Price** — starting price, current price, season high/low, then per gameweek: price
    that week + the move after it (green/red).
- **Bottom bar:** **Add to Team / Remove** (same availability rules and reasons as the
  market control; edits the shared draft — saving stays on My Team) and **See full
  profile** → `openPlayerProfileById` (hidden when the player has no linked account).
  Opened from outside the hub (Infinite profile tab) the primary button is
  **Open in Fantasy** instead.
- Before any finalized week: header + Overview with "Points start after Gameweek 1"
  copy; Matches/Price tabs show friendly empty states.

**Data:** Players, PlayerTotals, PriceChanges, PriceHistory/<gw>/<name> and
PlayerWeekStats/<gw>/<name> (one listener per finalized gameweek, like
`watchChipHistoryFor`), league rosters (season stats + uid link), league games (next
game). Name → account: runtime join via `LeagueService.watchRosters` (`TournamentPlayer.uid`),
matched on team + name; no uid is stored on fantasy Players.

## 5. Fan: Players market redesign

- **Rows:** 44px photo, name (wraps) with "POS · Team" under it; right side: price over
  total points, price-move icon (▲ green / ▼ red / — muted, latest week) over owned %;
  then the existing +/✓/greyed control. Unaffordable price stays red. Ineligible guests
  stay last, dimmed.
- **Sorts:** Total Pts (default once totals exist), Form, Price, Ownership; tapping the
  active sort flips direction (arrow shows it). Name A–Z is dropped. Choice remembered
  for the session.
- **Filters:** All / GK / DEF / ATT / ★ Watchlist chips + search (name or team), as today.
- **Price Risers / Price Fallers card** (replaces the chip strip, hidden until a reprice
  exists): two columns, rows with photo + short name + move. Position filter All →
  grouped GK / DEF / ATT, top 2 risers and top 2 fallers each; a position filter →
  that position's top 2 each. Ties broken by season points. Rows open the profile.
  **View all** → a sheet listing every move from the latest reprice.
- **Watchlist:** star on the profile toggles `Watchlists/<uid>/<name>`; the ★ chip filters
  the market to starred players.
- **Next game** shown under the team line on each row ("vs Nimrod · Sun").

## 6. Fan: Leaderboards redesign

- Scopes: **Overall | Gameweek** (week chips as today). "My Leagues" hidden behind a
  single constant; mini-league code, rules and data stay. Rules FAQ copy about
  mini-leagues "coming soon" removed.
- Podium removed. Each row: rank, movement (Overall only: green ▲n, red ▼n, muted —;
  "—" when no earlier week), avatar, **manager real name** with **team name** under it
  (both wrap), points. No real name available → team name alone. Flagged team names
  never shown (existing fallback).
- Own row: gold highlight; pinned at the bottom when off-screen (existing behaviour).
- Row tap → manager squad viewer (existing); player chips in the viewer open the
  player profile.

## 7. Fan: Fantasy tab on the Infinite profile

`ProfilePage(uid)` gets a third tab **Fantasy** when, for the current fantasy season,
the uid maps to a fantasy player (rosters join) and/or is a fantasy manager
(`Managers/<uid>`). Otherwise no tab. Content:
- As a player: price + move, total pts, form, owned %, last 6 weeks' bars, **Open in
  Fantasy** (opens the hub on that player's profile).
- As a manager: team name, overall rank + movement + points, **View team** (squad viewer).
Limited (unlinked) profiles get no Fantasy tab.

"Current fantasy season" = the same resolver the home banner / search hub use (the
current league's current season, only if it has a Fantasy `Config`), falling back to
the newest season that has a Fantasy `Config`. Today that is Futsal 15 (the only
Fantasy season; "Futsal Season" = 15), so the tab is testable on the filled test season.

## 8. Manager: Fantasy profiles

- Drawer tile and page renamed **Fantasy profiles** (subtitle "Who's playing — contact,
  squads, flag names"). List rows: photo, real name, team name, overall rank + points,
  flagged badge; Flag/Unflag button stays on the row. Search by real name or team name.
  Flagged first, then by overall rank, unranked last by name.
- Tap → detail page `/fantasy/names/:uid`, all live streams:
  - **Header:** photo, real name, team name, flagged state + Flag/Unflag (existing
    confirm dialog).
  - **Contact:** email (from `getUserContact`, "Not available" when none, plus "Signs in
    with Google/Apple/email"), phone (`Users/<uid>/Phone Number`), buttons **Call**,
    **Text**, **Email** (url_launcher `tel:` / `sms:` / `mailto:`), member since
    (`Date Joined`).
  - **Fantasy:** overall rank, movement, points; this week's squad as a simple list
    grouped GK / DEF / ATT with captain/vice markers and bench (published picks once
    locked, else the saved draft); a weeks table (GW, points net of hits, transfer hit,
    chip); free transfers left; chips used; first gameweek played.
- New Manager reads: single-user `Users/<uid>` stream, `Leaderboards`, `PublishedPicks`,
  per-uid `History`, `TransferCosts`, full `TransferState/<uid>`, `Squads/<uid>`. Parsers
  ported from the fan repo where they exist (`leaderboardsFromNode`, `squadFromNode`,
  `chipHistoryEntryFromNode`).
- Fake test managers (§9) show "No account" in Contact.

## 9. Test data: replay Season 15 into the test season

A tool in `functions/tools/` (built on the existing `rehearse_s15.ts` replay, which runs
the real sweep / finalize / reprice code against an in-memory copy) that:
1. Refreshes the snapshot, replays all of Season 15 with **20 made-up managers**
   (uids `test-01`…`test-20`, fun team names, deterministic seeded squads/chips/transfers)
   plus the two real managers' current saved squads held as their picks every week (if a
   real squad is rejected, that manager is skipped and the tool says so).
2. Writes the replay's derived nodes to the live `Fantasy/Futsal/15/` only: Players
   (end-of-season prices), PlayerTotals, PlayerWeeks, PlayerWeekStats, PriceHistory,
   PriceChanges, Leaderboards, History, PublishedPicks, DreamTeam, TransferState,
   TransferCosts, plus `Managers` and `Squads` for the 20 fake uids only — **and the
   engine's own done-markers the replay produced** (`GwState`, `LockedPositions`,
   `Repriced`, `RecapSent`, `NewsDrafted`, `ReminderSent` and any other once-only guard
   the replay wrote), so the season looks fully processed: if it ever returns to Auto,
   nothing reprices twice, re-sends recaps or re-drafts news, and the Manager's
   Gameweeks page shows every week locked + repriced. It never touches the real
   managers' `Squads`/`Managers`, `Config`, or `News` (the replay's AI news drafts are
   not written).
3. Refuses to run unless the effective lock override is Open or Locked **with no
   auto-return time** (`lockOverrideUntil` absent — "Never (testing)"), refuses any path
   outside `Fantasy/Futsal/15/`, saves a local backup of every node it replaces, and
   writes a marker `Fantasy/Futsal/15/TestFill = {At, Managers: 20}`.
4. `--clear` restores the backup and removes everything it wrote (marker, fake managers,
   done-markers) — used by the Season 16 prep wipe.
Admin writes use the established REST + OAuth token pattern. Real users can't see any of
it (Fantasy is not in the store build).

## 10. Decisions made by Claude (owner can veto)

- Form = average of the last 3 finalized weeks, missed week = 0.
- Default market sort = Total Pts; Name A–Z sort dropped; tap active sort to flip.
- Risers/Fallers ties broken by season points; "View all" lists every move.
- Profile tabs keep the mockup's four (Overview / Stats / Matches / Price); Minutes tile
  replaced by what we track.
- Watchlist stored per season in the database (syncs across devices).
- Leaderboard shows real name with team name underneath (instead of two side-by-side
  columns, so long names wrap on phones); podium removed.
- "See full profile" hidden for unlinked players; unlinked profiles get no Fantasy tab.
- Manager squad shown as a grouped list, not the fan court graphic.
- 20 test managers; the two real managers included with their saved squads.
- Test fill writes the engine's done-markers and requires a pause with no auto-return.
- Profile Fantasy tab uses the home-banner season resolver (fallback: newest season
  with a Fantasy Config).
- No backfill tool; deploy before Season 16 Gameweek 1 locks.

## 11. Left to the builder

File/widget decomposition, chart drawing (plain widgets, no new chart package unless
clearly simpler), exact copy for empty states, the Dart `ScoreLine.key` twin mechanics,
how the test-fill tool reuses the rehearsal internals, test seams (follow existing
stream-seam conventions).

## 12. Testing

- Functions (vitest): PlayerWeekStats lines sum to Pts for every player in the golden
  week; voided week shape; PriceHistory once-only at lock; PlayerTotals form/ppg/games;
  `getUserContact` admin gate; rerun idempotency unchanged.
- Fan: parsers, market sort/filter/risers-fallers logic, profile tabs (data, empty,
  voided), leaderboard rows (movement, names, own row), profile Fantasy tab visibility;
  light + dark, phone width.
- Manager: profile list sort/search, detail page with fakes (incl. no-account user),
  guard test stays green.
- Owner device test on the filled Season 15 test season (tablet + emulator).
- iOS verify list: url_launcher sms/mailto/tel, profile hero image, new tab on
  ProfilePage, watchlist write.
