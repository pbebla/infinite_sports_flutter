# Fantasy: season setup, mid-season players and schedule changes (design)

**Status:** owner-approved in chat 2026-11-05. Written for Fable review before any code.
**Repos:** fan repo `infinite_sports_flutter` (functions + fan app), Manager `InfiniteSportsManagerFlutter`; branch `zaya-fantasy` in both.

## Why

1. **A new season can't be set up properly today.** `tool/seed_fantasy.dart` (run by Claude from a laptop) writes `Fantasy/<sport>/<season>/{Config, Players}`. It prices players from the *same* season's games, so for Season 16 (no games yet) every player would open at the $6M rookie price. It also `PUT`s the whole Players node, so re-running it mid-season resets every price.
2. **Players who join a team mid-season never reach the market.** Nothing adds them.
3. **Schedule changes can scramble fantasy weeks.** Weeks are numbered by counting game days in order, and everything saved for a week is filed under that number. A game day rained out after its deadline (its games moved to a later date) makes the empty day vanish; later weeks shift down, and the next week is scored with the cancelled week's locked teams. Deleting a scored day renumbers finished weeks the same way.

## Owner decisions (verbatim intent)

- **Per-season setup is data, not code.** No Paul/Bronsin review per season. These changes include fan-app code, so they ship in the one fantasy store build that Paul and Bronsin review.
- **Prices carry over** ("go with that until we see some issue with it through fans' comments"):
  - A new season starts with each player's **final price from the previous fantasy season**.
  - A player who sat out comes back at their **last fantasy price**.
  - A **brand-new player** gets the **average price for their position**.
  - The owner sees a **preview** and changes only what they want.
  - Season 16 carries from Season 15 (whose prices were worked out from Season 15's real games).
- **Positions carry over**, including the owner's edits. New players get the position they picked at sign-up. The owner changes a player only when the player asks.
- **Mid-season joiners** join the market on their own within minutes, at the **average price for their position** and their sign-up position. Nobody else's price changes. The owner can still edit them.
- **Schedule:**
  - Games are once a week (Sundays now, maybe another weekday later). **No two-game weeks for now.**
  - Fantasy reads the season schedule by itself: each game day is one fantasy week.
  - Default deadline: the season's lock hour on game day.
  - The owner can **change any single week's deadline** and **cancel or bring back a week by hand** in the Manager.
  - **A cancelled week is skipped as if it never happened, even when cancelled after its deadline** (rain on the day):
    - fans keep the team they set; no points hit is charged; chips are not used up;
    - teams reopen until the next game day's deadline;
    - if the games moved a week later, that week is simply a week later; if they're gone, the next game day takes that week's number.
  - **Partial cancel:** the games played count that week; moved games count in the week they're played.
  - **Weeks already scored never change because of a schedule edit.** The Manager warns before deleting or moving a game that already counted.

## Design

### 1. Gameweeks: frozen once locked, derived after that

New server-written node **`Fantasy/<sport>/<season>/LockedWeeks/<n> = { Date: 'MMDDYYYY', LockAtUtc: <ms>, Scored?: true }`**:
- written once (set-if-absent) when week *n* locks, before any other lock snapshot;
- `Scored: true` added at week *n*'s first finalize.

Every gameweek list (server, fan app, Manager) comes from ONE pure function, twinned in TypeScript and Dart:

```
deriveGameweeks(matchDates, cfg, schedule) where schedule =
  { lockedWeeks, skippedDates, deadlineOverrides, firstKickoffUtc }
```

- **Weeks 1..L** = the contiguous frozen prefix of `lockedWeeks`, with their stored date and deadline. A schedule edit can't renumber them.
- **Weeks L+1..** = schedule dates strictly after the last frozen date, minus skipped dates, in date order.
  - Deadline = the owner's override for that date if set.
  - Otherwise: the lock hour on game day, pulled earlier to `deadlineMinutesBeforeKickoff` (default 60) before the day's first stored kickoff time when that is earlier.
- `opensUtc` and `currentGameweek` keep today's rules (open from midnight after the previous game day; "current" until 24 h after the deadline).
- A game on a date at or before the last frozen date that isn't a frozen week's date never becomes a week. Its games don't count, and the Manager warns.

**Owner overrides live in Config**, so the existing Config streams carry them:
- `Config/Deadlines/<MMDDYYYY> = <epoch ms>`
- `Config/SkippedDates/<MMDDYYYY> = true`
- `Config/deadlineMinutesBeforeKickoff` (int, default 60)

They are keyed by date, so a moved game day loses its override and falls back to the automatic deadline.

### 2. Cancelled after the deadline: rewind

The server checks for a rewind in three places:
- the 15-minute sweep, first thing;
- a new date-level schedule trigger that runs only when a date's set of games or a kickoff time changed (no reads otherwise, so live score writes cost nothing);
- a new trigger on `Fantasy/<sport>/<season>/Config` writes (no Config trigger exists today).

**When it rewinds:** the **latest** frozen week *n* has no History (and no `Scored`), AND one of these holds:
- its date has no games left in the schedule;
- its date is skipped;
- its deadline override now lies in the future (the owner extended a deadline that already passed).

**Why this works:** deleting `LockedWeeks/n` is what makes the rewind stick. The week list is derived from the frozen prefix plus the schedule, so once the frozen entry is gone the derived week *n* has a future deadline and the sweep no longer re-locks it.

**What a rewind does**, in this order (each step idempotent, `LockedWeeks/n` last, so a crash is retried):
1. Delete `PublishedPicks/n`, `LockedPositions/n`, `PriceHistory/n`, `TransferCosts/n` and `ReminderSent/n` (so the reminder fires again before the new deadline).
2. Delete `Live` if `Live/Meta.Gw == n`, and `LiveBase/n`.
3. Delete each `SquadAlerts/<uid>` with `Gw == n` and `Kind == 'invalid'` (the lock judge's).
4. Clear `TransferState/<uid>/ChipPlayed` for every uid in the deleted snapshot (nothing scored, so no chip was spent).
5. Restore `Baselines` to the week-*n* editing state. Re-publish from week *n−1* through a rewind-only bypass of the never-backwards guards; for *n* = 1, remove `Baselines` (none existed before the first lock).
6. Delete `LockedWeeks/n`, then write GwState for the new current week.

Managers get one push, claimed once per (*n*, cancelled date): **"GW{n} was called off — your team is open again until {deadline}."**

Untouched on purpose:
- `UsedThisGw`: the window is still week *n*, and the next save recounts it.
- `PreviewPushed/n`: no repeat over-budget push.
- `PendingPositionChanges`: these apply at reopen, as today.
- History, chips in `Squads`, the Free Hit restore and the free-transfer roll: none of them ran, because they only happen at finalize.

**What a rewind never does:**
- touch a week that has History;
- run when the schedule read fails;
- run when the season's schedule has no game days at all (it alerts instead);
- run while the lock override isn't `auto`.

### 3. Season start ("Start fantasy season", Manager)

Two admin-only callables share one server implementation, so the joiner trigger uses the same rules:

1. **`previewFantasySeason({sport, season})`** returns:
   - a row per non-guest roster player in `<Sport>/<Season>/Line Ups`: name, team, uid, position + where it came from, price + where it came from, photo;
   - the settings to copy;
   - blocking problems (no rosters; Config already exists; source season still holds test-fill data).
2. **`startFantasySeason({sport, season, edits, settings})`**:
   - recomputes the preview server-side;
   - applies the owner's edits (price snapped to step and clamped; position GK/DEF/ATT);
   - writes `Config` (create-only) then `Players`.

**Carry-over lookup per player:**
- Search earlier fantasy seasons of the same sport, newest first.
- Match by uid first (through that season's Line Ups uid→name), then by trimmed, case-insensitive name.
- **Found:** that season's `priceTenths` and `position`.
- **Not found:**
  - position = sign-up `Users/<uid>/Information/<sport>Position`, first listed (existing `mapRegistrationPosition`; missing → ATT);
  - price = **position average** = mean `priceTenths` of the season's other (eligible) players in that position, snapped to the price step and clamped. With nobody in that position, it's the rookie price.

**Settings:**
- Copied from the newest earlier fantasy season's Config, with `lockOverride` set to `auto`.
- Dropped: `lockOverrideUntil`, per-week `Deadlines`/`SkippedDates`, and `Access`.
- **Access isn't copied** because it's a per-season business choice, and Season 15's is a $5 test value. A new season starts free, and the preview reminds the owner to set the season pass in Access & payments.

**Blocking problems** (Start disabled):
- no rosters yet;
- no schedule yet (GW1 opens from launch until its first deadline, so the schedule must exist);
- Config already exists;
- the source season still holds test-fill data.

Players written by the new flow carry an optional `uid` field.

### 4. Mid-season joiners

New trigger on `<Sport>/<Season>/Line Ups` writes, for fantasy-enabled seasons (Config present, not a test-fill season). For each roster player not in the market:
- matched by uid against market entries' `uid`, then by name;
- adds `{position, priceTenths, eligible: true, teamName, uid?, photoUrl?}`;
- price = the position average (owner rule for joiners, even a returning player);
- position = their last fantasy position if any, else sign-up.

It never changes existing prices. A player who moved team gets `teamName` updated. A player removed from a roster stays in the market (owners keep them).

### 5. Reprice the morning after any game day

The weekly reprice runs **daily at 10:00 league time** (it runs Monday-only today).
- It reprices the newest finalized, un-repriced week whose game day is before today, and only while teams for the next week haven't reopened yet (before that week's deadline + 24 h).
- A week finalized later than that is not repriced. This matches today's effect: a late finalize simply misses Monday. The run records `Repriced/<gw> = {Skipped: 'late'}`, so the Manager can show it and the owner can still reprice by hand.
- On Sunday leagues this is exactly today's Monday 10:00.
- Copy saying "Monday" becomes "the morning after each game day".

### 6. Manager

- **Gameweeks page:** each row shows the date and deadline ("changed" when overridden), with actions:
  - **Change deadline** — a date-time picker limited to before the game day ends;
  - **Back to automatic**;
  - **Skip this week**, on unscored weeks;
  - a **Skipped days** list with **Bring back**.
- **Schedule Manager:**
  - deleting or moving a game whose date is a scored fantasy week warns that fantasy points change;
  - deleting or moving the last game of a locked, unscored week says fantasy will cancel that week and reopen teams.
- **Start fantasy season:** a card for any season with rosters and no Config. Preview table (grouped by position, editable price and position, source shown), a settings summary, and **Start**.

## Out of scope

Two game days in one week; renaming a market player; removing departed players; repricing rules; the S15 test-fill clear itself (an ops step with the owner's OK at launch).
