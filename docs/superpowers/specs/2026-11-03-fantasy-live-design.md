# Infinite Fantasy — Live During Games (design, 2026-11-03)

Written by Opus for a **Fable review**, then Opus executes. The plan that implements this design is `docs/superpowers/plans/2026-11-03-fantasy-live-everywhere.md`.

## The owner's ask (2026-11-03, in his words)

> "while the games are happening, i think we should see live points, total changing live and managers moving up and down based on points coming. i understand value of players is figured out later but unless there is an issue or reason we should live points forms, total points, placement of managers or placement of players changing LIVE anywhere that is possible or built for it. not just one or two places anywhere that we can see it, it should do it, plus the gap you found you can fix it"

**Prices stay out of scope.** They still move only on Monday at 10:00 (owner: "value of players is figured out later").

## Today

- Only the match page's Fantasy tab is live. It computes one game's raw points on the phone from the game node.
- Everything else (week points, season totals, form, ranks, movement arrows, Team of the Week, rank history, market sorts) settles once, when the server finalizes the gameweek after **all** of that day's games are Final (`maybeFinalizeGame`, `functions/src/lib/fantasy/orchestration.ts:1358`).
- My Team in a locked week shows a leftover placeholder, "Gameweek locked — live points coming here" (`_LockedLiveStrip`, `lib/fantasy/hub/squad_builder.dart:660`). The court never gets per-player points.

## Design

### 1. One source of truth: a server-computed `Live` node

The server recomputes the live gameweek on every write to a game of the locked week's date and publishes it. Every screen overlays it.

- **Why the server, not each phone:**
  - Ranks need every manager's team, so one computation keeps every phone identical.
  - It reuses the exact finalize math, which is pinned by the golden fixtures.
  - Phones stream a few small nodes instead of all picks plus all games.
- **Same math as finalize.** `computeGameweekFinalize` (`functions/src/lib/fantasy/finalize_core.ts:446`) is split:
  - Stages 1–4 (mapper → BPS/bonus → player weeks → squad weeks) become an exported `scoreWeekCore`. Finalize keeps calling it, byte-identical for finalize inputs; the goldens prove that.
  - A new `computeLiveWeek` calls the same core plus a small "settled base", so it never re-reads every past week on each tap.
- **The contract test.** When every game of the day is Final, `computeLiveWeek` must equal finalize on every published number:
  - week points, week board, Overall points/rank/movement;
  - player week points and lines;
  - season points, form, ppg, games, ownership;
  - Team of the Week players.
  
  This test is the reason the hand-off from live to official numbers never jumps.

### 2. Provisional rules (while games are still to come)

- **Games counted:** today's non-friendly games that have started (status 1 live, 2 final). A status 0 game counts nothing yet.
- **Pending player:** his team still has a not-started game today and he hasn't played yet. For team scoring a pending player counts as "playing, 0 so far". So:
  - no auto-sub happens for him yet;
  - a pending captain keeps the armband (the vice only takes over once the captain's game is under way and he's marked absent, or his games end without him);
  - a pending bench player stays on the bench.
  
  This mirrors how the Premier League game shows live points: subs only happen once it's certain.
- **Absent player:** marked absent in a started game, or every game of his team is Final without him. He is treated exactly like at finalize (auto-sub, vice armband).
- **Bonus:** the 3/2/1 bonus of an in-progress game is shown **provisionally**, as it would stand if the game ended now. It is included in live totals and marked "provisional" until that game is Final, at which point it is exactly the finalize bonus.
- **Transfer hits, chips, invalid squads, voided week:** all exactly as finalize. Hits are known at the lock (`TransferCosts/<gw>`), chips come from the lock snapshot, an Invalid squad stays 0, and a voided week shows 0 and "Voided".
- **Season totals and form of a pending player:** his settled numbers stay until his game starts. He doesn't drop to "0 this week" at the lock. After that, his totals include the live week, and his form uses the same 3-week window finalize uses, with this week as the newest.
- **Ownership** comes from this week's locked squads (finalize does the same).
- **Team of the Week (provisional):** best players so far among those who have played, in the configured formation.

### 3. What is live, where

Every place that shows any of these numbers overlays the live node while the week is live: player week points, season points, form, ppg, manager week points, Overall points, ranks, movement arrows, rank-history chart, Team of the Week, and market or leaderboard orderings by points or form. The plan lists every screen by file (from a full inventory of both apps).

- **One shared "LIVE" pill** (red dot + "LIVE") marks live numbers. When the week settles the pill disappears and the official numbers take over.
- **Rows move, steadily (owner decision: "like ESPN and the Premier League — numbers move, rows don't jump").** Numbers update in place at once. A sorted list (leaderboards, the Players market) re-orders immediately when it is at the top, when it is opened, or when the user picks a sort. Otherwise it shows `Order changed · tap to refresh` and re-orders on tap. A row that moved tints briefly (up colour or bright red) and its rank number cross-fades; under reduced motion both are instant.
- **The rank-history chart** adds this week's live rank as a hollow end point, solid once settled.
- **My Team** in a locked week:
  - The placeholder becomes a live strip: LIVE pill + `34 pts · #5 ▲2` (week points, Overall rank, movement), `Final · 34 pts · #5` when settled, and `Locked · waiting for kickoff` before any game starts.
  - Each court chip shows that player's counted points (×2 captain), plus a small status: not started, playing, done, or out and auto-subbed.

### 4. When the week is live

- `Live/Meta.State`:
  - `'live'` from the first started game of the locked gameweek;
  - `'settled'`: a **tombstone** `{ Meta: { Gw, State: 'settled', UpdatedAt } }` with no numbers (Fable review L1). The finalize run writes it after every official node, replacing `Live` when it holds this week or an older one;
  - a new week's first live run replaces a settled one.
- Phones overlay `Live` only while `Live/Meta.Gw` is the week on screen **and** the state is `'live'`; anything else shows the official nodes. Finalize writes every official node before the tombstone, and a phone receives them in that order on its one connection, so the hand-over has no gap.
- A live run never resurrects a settled week: it stands down when `PlayerWeeks/<gw>` exists, and the transaction aborts on a tombstone or a newer week.
- A finalize rerun of an **older** week while a newer week is live removes `LiveBase` and refreshes the live week at once.
- Writes that don't touch scoring (clock, livestream link, undo bookkeeping) cost nothing: the trigger compares only the keys the scorer uses.
- Concurrency: every run stamps the time it read the games (`ReadAt`) and writes only if that is newer than the stored one. Out-of-order runs can never leave older numbers on top. A run whose event is older than the stored `ReadAt` skips its work entirely.
- **Backstop:** the existing 15-minute sweep recomputes live when a locked week has started games that aren't all Final, in case a trigger was lost.
- **Stands down** exactly like finalize: no fantasy Config, a frozen lock override, a TestFill season, or no lock snapshot (`PublishedPicks/<gw>`).

### 5. Node shapes (`Fantasy/<sport>/<season>/…`)

- `Live/Meta = { Gw:int, State:'live'|'settled', ReadAt:int, UpdatedAt:int, Games:{<gameKey>:{S:0|1|2, T1, T2}} }`
- `Live/Board/<uid> = { W:int week pts, WR:int week rank, O:int overall pts, R:int overall rank, M?:int movement }`
- `Live/Players/<name> = { Pts:int, St:'pending'|'live'|'done'|'out', Lines?:{key:{N,P}}, BonusProv?:true, Total:int, Form:int(tenths), Ppg:int(tenths), Games:int, Own:int }`
- `Live/Squads/<uid> = { T:int net tenths, W:int, Slots:[{p, c:int tenths, x:int, s?:true}] }`
- `Live/TeamOfWeek = [{name, position, points}]`
- `LiveBase/<gw>` (functions-only, never client-read): settled per-manager Overall points, per-player settled points and games, and the three newest settled non-voided weeks' points (the form window). It is built on the first live run of a week. The whole `LiveBase` node is removed by every finalize run and every void toggle.
- **Reads:** signed-in users may read `Live/**`; nobody but the Admin SDK writes. `LiveBase` is admin-read only. Both rules files change.

### 6. Out of scope

Prices, pushes for live events, mini-leagues (hidden today), and an iOS/Android widget.
