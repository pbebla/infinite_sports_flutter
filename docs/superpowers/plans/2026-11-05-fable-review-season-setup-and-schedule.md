# Fable review — Fantasy season setup + schedule changes (2026-11-05)

**Reviewed:** `docs/superpowers/plans/2026-11-05-fantasy-season-setup-and-schedule.md` (fan 167699f) and its spec `docs/superpowers/specs/2026-11-05-fantasy-season-setup-and-schedule-design.md`.
**Reviewer:** Fable 5.1, at the owner's request, after the plan was written by Opus 5.5.
**Verdict:** **Approve with 4 must-fixes.** The shape is right — freezing a week once it locks, deriving everything after it from the schedule, and one shared "price of a player entering the market" — and it matches every decision the owner made. The four must-fixes are not design changes; they close three ways the rewind can go wrong and one cost trap. Fold them into the plan before executing; nothing below needs the owner's decision except where marked.

## How I checked

I re-read the plan and spec cold, then read the server code every risky step leans on: the sale-baseline publisher and its never-backwards guards (`orchestration.ts:436-483`, `squad_integrity.ts:300-332`), the picks snapshot guard (`orchestration.ts:2060-2096`), the cron schedules (`fantasy_lifecycle.ts`), the Manager's roster stat writes (`lineup_service.dart:132-139`), the legacy kickoff fallback (`schedule_playoffs.dart:44-56`), and the fan season resolver. Findings 1–4 are confirmed against that code, not inferred.

## Must-fixes

### M1. A deadline moved after kickoff lets fans re-pick with the results known

The plan rewinds a locked week when its deadline override "now lies in the future", and Review Focus 4 even treats "games already live" as a case to support. The Manager's picker (Task 11) is bounded only by the end of the game day. Together: the owner extends a 4 PM deadline to 9 PM after the 6 PM games were played → the week is rewound, teams reopen, fans change their squads knowing the scores → the new lock snapshots those squads → the week finalizes on them.

**Fix.**
- Server (Task 4): the override-in-the-future reason rewinds **only when no game of that date has started** (every game `status == 0`). The two other reasons (date has no games left; date skipped) stay as written — a skipped date never scores, and a date with no games has nothing to score.
- Manager (Task 11): every deadline picker is bounded above by the date's **first kickoff** (stored `Time`, else the legacy fallback in S2 below), not the end of the day. On a locked week whose games have started, "Change deadline" is disabled with `Games have started — the deadline can't move.`
- Review Focus 4 flips: "Owner extends a passed deadline while a game is live → no rewind, logged; the Manager refuses it." Keep the "Live and LiveBase/n removed" assertion for the *day lost all games* case (an abandoned day whose games were moved).

### M2. Two writers on the same week: the rewind must run inside the sweep, not in triggers

The plan runs the rewind from the 15-minute sweep **and** from two new triggers (a date-level schedule trigger and a Config trigger). The sweep's lock step and a trigger's rewind can interleave: the sweep reads `LockedWeeks/L` (present), the rewind deletes the snapshots and `LockedWeeks/L`, then the sweep writes a fresh `PublishedPicks/L` from the live squads. That stale snapshot survives, and `snapshotPublishedPicks` returns early when the node exists (`orchestration.ts:2064`), so at the **real** lock of the new week L it is silently used as the week's picks — fans' later changes ignored, with no log line.

**Fix.**
- The rewind check runs **only in the sweep**, as its first step after the lockOverride and TestFill stand-downs, before `loadSeasonGameweeks` and the lock step. Owner-visible delay: up to 15 minutes, which is fine — the push says "called off", not "right now". Drop the date-level trigger entirely (it also would have fired on every live score write).
- Keep `onFantasyConfigWritten`, but it only calls `upsertGwState` for an **open** derived week (so a changed deadline reaches the rules' `GwState.lockAtUtc` at once). It never rewinds.
- Overlapping sweeps exist today (a slow sweep plus the next one). So the lock step, after claiming `LockedWeeks/L`, re-reads it **immediately before each snapshot write** and aborts the step when it is absent or its `Date` differs from the week it is locking. One small read per snapshot.
- Tests: replace "two reconciles in parallel" with "a stale sweep that read before a rewind writes no snapshot" (FakeDb: delete `LockedWeeks/L` between the sweep's read and its snapshot).

### M3. The money-baseline restore is lossy — stash the old node at lock instead

Task 4 restores `Baselines` after a rewind by re-publishing from week L−1 through a `rewindTo` bypass of the never-backwards guards. That recompute is **not** the pre-lock state for every manager: `baselineNodeOf` (`squad_integrity.ts:300-332`) carries `RealizedTenths` **from the stored node** whenever the manager has no parseable squad for the source week. A manager who sat out week L−1 (or joined at week L) and then sold players in week L's window would, after the rewind, keep week L's sales in their running total — a wrong budget at the real lock, and a possibly Invalid squad.

**Fix.** Make the restore exact and trivial:
- At the lock of week L, `publishSaleBaselines` (the lock-time call only) writes the node it is overwriting into `Baselines/<uid>/Prev` (`{ForGw, RealizedTenths, Prices}` of the old node; absent when there was none). Finalize-time publishes drop `Prev`.
- The rewind restores with one transaction per uid: `if node.Prev exists → node = Prev (and Prev removed); else if node.ForGw == L+1 → remove node; else leave`. Idempotent, so a retried rewind is a no-op.
- The `rewindTo` option on `publishSaleBaselines` is not needed; don't add it.
- `Prev` is server-only (no rule). The fan app's baseline parser must ignore the extra key — add a parser test.

### M4. The roster trigger fires on every goal — gate it purely

Task 7 listens on `Line Ups/{team}` and reads Config, the TestFill marker and Players on every fire. Live scoring writes `Line Ups/<team>/<player>/Goals|Assists|Saves|…` with `ServerValue.increment` (`lineup_service.dart:132-139`), so every scoring event on a game day fires it, with three reads each.

**Fix.** A pure gate first, zero reads otherwise: `rosterShapeChanged(before, after)` is true only when the set of player keys under the team changed or any player's `UID` changed. Stat, number and photo writes return before any read. Test it alongside the existing cases (score write → false; player added → true; UID linked → true).

## Should-fixes

### S1. The Start preview carries the season pass (owner-facing)

Plan ruling 1 starts every new season **free** and leaves the pass to Access & payments. The Free→Pass flip in the Manager asks whether existing managers keep free access (default yes — D4). If the owner starts Season 16, fans name teams for a few days, then he flips to the $N pass, the default keeps those early managers free for the season. Easy to miss.

**Fix.** The preview (Tasks 6 and 13) includes a **Season pass** row pre-filled from the source season's `Config/Access` (Mode, AmountDollars, Methods; the Cash flag stays Manager-only) and editable; `startSeason` writes `Config/Access` with the rest of Config. Season 15's $5 is a test value, so the owner edits it in the preview. This matches his "defaults on, pre-filled + editable" rule. Ruling 1 is withdrawn.

### S2. Kickoff fallback when games have no stored time

Season Builder games carry no `Time`; the apps render them at the legacy `Start Time` + index (PM). The plan's kickoff-aware deadline would never pull the deadline earlier for such a season. Use the same fallback the Manager already has (`derivedStoredTime(startHour, 0)`, `schedule_playoffs.dart:49-54`): a date with no stored times takes `Start Time` as its first kickoff. The fan twin needs the identical three-line helper; add it to the golden fixture (`Start Time 2`, no stored times, lockHour 16 → lock 1:00 PM).

### S3. Two small rewind leftovers

- Skipping an **open** week's date, or extending an open week's deadline, should clear `ReminderSent/L` (the reminder may already have fired for the old deadline). One delete.
- After a rewind that leaves **no later game day**, `upsertGwState` leaves GwState at `locked`. Write GwState `null` instead (the rules then allow saves; the app shows no current week). The push already says plain "GW{L} was called off."

### S4. Spec/plan drift

- Write order: the plan writes Players then Config (right — no half-visible season); the spec says Config then Players. Fix the spec.
- Spec §2 lists triggers for the rewind; after M2 it's the sweep. Fix the spec.
- Task 5 says a late week "can still be repriced by hand" — say what that is (per-player price edits on the Players page). A one-tap "Reprice now" for a `Skipped: 'late'` week is a nice add but optional.

### S5. New `uid` key on Players

Both apps' market parsers must ignore it (they read named keys, so they likely do) — pin it with a test in each repo so a future stricter parser can't drop these rows.

## Notes — no change needed

- **Rulings 2–5 stand.** Returning players who join mid-season at the position average is the owner's literal rule; Start needing the schedule is right (week 1's deadline comes from it); the reprice function keeps its deployed name; a game added on a date before the last locked week never counts, with a Manager warning.
- **"Moved a week later" onto an existing game day** means that day holds two rounds in one fantasy week (teams play twice). That is inherent in "one game day = one week" and is what the owner asked for. Worth one sentence in the Rules tab FAQ.
- **Launch order matters for fans.** The fan resolver falls back to the newest season with a Config, so between publishing Season 16 and pressing Start, fans see Season 15. Runbook: clear the S15 fill → build and publish S16 → Start fantasy right away → set the pass in the preview (S1).
- **No old builds to protect.** Fantasy isn't in the store yet, so there are no phones deriving weeks the old way. This work must ride the same store build as the rest of fantasy — the plan already says so.
- **Test counts to expect:** functions ≈ +60 cases (schedule golden, rewind, reprice, season start, roster sync, guard), fan ≈ +30, Manager ≈ +40.

## For the owner, in one breath

The plan does what you asked. Before building, four things get tightened: (1) a deadline can't be moved past kickoff, so nobody re-picks after seeing scores; (2) the "called off" rewind runs in the 15-minute engine pass only, so it can't collide with a lock; (3) each manager's money is saved before every lock and put back exactly on a rewind; (4) the mid-season joiner check ignores goals and assists and only wakes for roster changes. One choice for you: the Start preview will show the season pass price pre-filled, so you set it before fans arrive.
