// A game day called off after its deadline (season setup + schedule plan
// 2026-11-05, Task 4; spec docs/superpowers/specs/2026-11-05-fantasy-season-
// setup-and-schedule-design.md §2). The owner's rule: "if a week is
// cancelled for any reason, fantasy should skip it like it never happened" —
// fans keep their team, transfers and chips as set, nobody takes a points
// hit, and teams reopen until the next game day's deadline, even when the day
// is called off after its deadline.
//
// THE REWIND (rewindCancelledWeek) runs ONLY in the 15-minute sweep, right
// after its lockOverride / TestFill stand-downs and before it loads the week
// list (Fable M2: a trigger-side rewind could interleave with a lock). It
// looks at the LATEST frozen week L (the highest key of the contiguous
// LockedWeeks prefix) and rewinds it when History/L is absent, it is not
// Scored, and its day is called off:
//   (a) Date/<L.date> holds no game (friendlies count as games here);
//   (b) Config/SkippedDates/<L.date> is true;
//   (c) [M1] Config/Deadlines/<L.date> now lies in the future AND no game of
//       that day has started (every status 0) — a started day is never
//       reopened (warned): nobody re-picks after seeing scores.
// An error is not a fact: a read that throws propagates (the sweep gives the
// season up for this run, nothing written), and a season whose whole Date
// node is empty stands the sweep down with a warn instead of rewinding.
//
// Steps (each idempotent; a crash is finished by the next sweep — ruling
// T3a: MARK first, delete the ledger entry LAST):
//   M. Transaction on LockedWeeks/L: `Rewinding: true`, only while it still
//      freezes L.date, is not Scored and carries no `Finalizing` stamp
//      younger than 10 minutes (final review I1: LockedWeeks/L is the lock
//      finalize and rewind share — the finalize stamps it, by transaction,
//      right before its first official write and refuses a marked entry,
//      so the two never overlap; an older stamp is a finalize that died and
//      is dropped by the mark). From here every lock-step write
//      refuses the week (orchestration.ts freezesWeek), each lock snapshot
//      deletes itself if it lands under the mark (guardedSnapshotClaim), and
//      finalize stands down for it. Then History/L is re-read: present = a
//      finalize won the race, the mark is removed and the week counts.
//      A sweep finding the entry already marked (a rewind that died) resumes
//      from step 0 without re-checking the reasons.
//   0. The uids of PublishedPicks/L.
//   4. TransferState/<uid>.ChipPlayed removed for each of them (nothing was
//      scored, so no chip was spent). DOCUMENTED ORDER: before step 1, which
//      deletes PublishedPicks/L — a crash in between must not lose the list.
//   1. PublishedPicks/L, LockedPositions/L, PriceHistory/L, TransferCosts/L
//      and ReminderSent/L removed (the reminder fires again before the new
//      deadline), and Voided/L (ruling T4b: the void named the cancelled
//      day — the next game day, which inherits number L, must not be zeroed;
//      onFantasyVoidWritten fires on the removal and settles nothing, since
//      finalize stands down for the marked week and later waits for the
//      reopened week's lock).
//   2. Live removed when Live/Meta.Gw == L; LiveBase/L removed.
//   3. SquadAlerts/<uid> removed where Gw == L and Kind == 'invalid' (the
//      lock judge's verdict; any other alert is left).
//   5. [M3] Every Baselines/<uid>: restoreBaselineAfterRewind in one
//      transaction (the lock-time Prev stash put back exactly).
//      Then History/L is re-read once more — a belt-and-braces check kept
//      from before the I1 lock (a finalize can no longer pass its stamp
//      under the mark): History present = the week counts (mark removed,
//      warned).
//   8. The push, BEFORE step 6 (DOCUMENTED ORDER: once LockedWeeks/L is gone
//      no later sweep knows a push is owed): when a pusher is injected and
//      the CalledOff/L/<L.date> claim lands set-if-absent — every manager
//      under Managers, "GW{L} was called off — your team is open again until
//      {deadline}." with the reopened week's deadline (derived as if L were
//      gone), or "GW{L} was called off." when no later game day reopens it
//      (or its deadline has already passed). A failed send is logged; the
//      claim keeps it once-only either way.
//   6. LockedWeeks/L removed (only while it is still our marked entry).
//   7. The weeks re-derived: GwState upserted for the current week, or
//      removed when there is none.
// The rest of that sweep then runs on a freshly loaded week list. A sweep
// that derived its weeks before a rewind may re-claim LockedWeeks/L with the
// old date (orchestration.ts claimLockedWeek) and lock it again; the next
// sweep rewinds it again, and the CalledOff claim keeps the push single.
//
// Untouched on purpose: UsedThisGw (the window is still week L; the next save
// recounts it), PreviewPushed/L, PendingPositionChanges (they apply at the
// reopen), History, chips in Squads, Free Hit restore, transfer roll (none of
// them ran — they belong to finalize).
//
// THE HEAL (healOpenWeek, rulings T3c/T3d) — every sweep, while the derived
// current week L is OPEN and not frozen: no lock of L ever stood, so nothing
// a lock writes can legitimately exist for it. A write that a stale sweep
// landed inside one round trip after a completed rewind (or a lock snapshot
// whose post-check crashed) is undone: PublishedPicks/L, LockedPositions/L,
// PriceHistory/L, TransferCosts/L removed (otherwise the real lock would
// ADOPT the cancelled day's picks); a Live node of week L removed (a live run
// in flight across the rewind); every Baselines/<uid> FOR L + 1 restored
// (otherwise it blocks that manager's Save for the whole reopened week).
// Each removal first re-reads LockedWeeks/L: once a lock of L has begun the
// heal keeps its hands off. Ruling T4d: it runs only when History/L is
// absent AND L is 1 or week L - 1 is frozen — in a season without the
// ledger a deleted past date renumbers the weeks, and the open week can then
// carry the number of a week that locked and scored (its snapshots and its
// finalize-written FOR L + 1 baselines are real).
//
// upsertGwState never writes 'locked' or 'finalized' unless LockedWeeks/<n>
// still freezes the week's date (ruling T4e): a sweep that passed its lock
// step before a rewind must not write its stale 'locked' over the reopened
// week.
//
// THE CONFIG TRIGGER (onFantasyConfigWritten, fantasy_schedule.ts →
// refreshOpenGwState): a deadline moved, a day skipped or the kickoff lead /
// lock hour changed on an OPEN week reaches GwState — and so the save rules
// — at once. A locked week stays the sweep's job; the trigger never rewinds
// (Fable M2).
//
// NODES (under Fantasy/<sport>/<season>):
// - CalledOff/<gw>/<MMDDYYYY> = { At:int } — the once-only claim of the
//   "called off" push per (week, cancelled date). Functions-internal: no
//   rules entry (server-only, like ReminderSent).
// - GwState: see orchestration.ts; also written by the rewind (step 7) and
//   the Config trigger, through upsertGwState.

import { configFromMap, FantasyConfig } from './fantasy_config';
import { currentGameweek, Gameweek, gameweekStatusAt } from './gameweeks';
import {
  childEntries, dateKeysOf, FantasyDb, finalizingFresh, fantasyRoot,
  freezesWeekDate, isPlainMap, isRewinding,
  isTestFillSeason, loadSeasonGameweeks, lockedWeeksOf, lockOverrideOf,
  scheduleOverridesOf, TEST_FILL_STAND_DOWN, toIntLoose, updateIfPresent,
} from './orchestration_db';
import type { FantasyLogger } from './orchestration';
import { FantasyPusher, fantasyPushData, formatDeadlineInstant } from './pushes';
import { baselineForGwOf } from './squad_integrity';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

/** The "called off" push title — league news, not a deadline nag. */
export const CALLED_OFF_TITLE = 'Infinite Fantasy';

/** The "called off" push body; [deadline] null = nothing reopens. */
export function calledOffBody(gw: number, deadline: string | null): string {
  return deadline === null
    ? `GW${gw} was called off.`
    : `GW${gw} was called off — your team is open again until ${deadline}.`;
}

/** [M3] What a rewind of gameweek [week] does to one stored
 *  Baselines/<uid> node (pure; the transaction's update):
 *  - a node FOR week + 1 (written by week's lock) carrying a readable Prev
 *    (squad_integrity.ts THE PREV STASH) → that Prev node, exactly — WITH
 *    its own Prev (ruling T4c, THE CHAIN: one rewind pops exactly one
 *    level, so a second called-off week right before it restores too);
 *  - a node FOR week + 1 without one (the manager had no baseline before
 *    that lock) → null (removed: "first squad, ready");
 *  - anything else → undefined (left alone).
 *  DOCUMENTED CHOICE: the Prev is put back only from a node FOR week + 1. A
 *  node still FOR week may carry the stash of the lock BEFORE (week - 1's,
 *  kept while that week had no History) — restoring it would undo a lock
 *  that still counts. */
export function restoreBaselineAfterRewind(stored: unknown, week: number): unknown {
  if (baselineForGwOf(stored) !== week + 1) return undefined;
  const prev = (stored as Record<string, unknown>)['Prev'];
  if (isPlainMap(prev) && baselineForGwOf(prev) !== null) return { ...prev };
  return null;
}

// ── GwState ────────────────────────────────────────────────────────────────

export interface GwStateNode {
  current: number;
  status: 'open' | 'locked' | 'finalized';
  lockAtUtc: number;
  date: string;
}

function gwStateEquals(existing: unknown, desired: GwStateNode): boolean {
  if (!isPlainMap(existing)) return false;
  return toIntLoose(existing['current']) === desired.current &&
    String(existing['status'] ?? '') === desired.status &&
    toIntLoose(existing['lockAtUtc']) === desired.lockAtUtc &&
    String(existing['date'] ?? '') === desired.date;
}

/** The sweep's step 3 (orchestration.ts), shared with the rewind and the
 *  Config trigger: GwState for [current] — 'open' before its lock, 'locked'
 *  after it, 'finalized' once History/<n> exists — written only when a
 *  field changed. No current week = season over: GwState left as-is.
 *  [T4e] 'locked'/'finalized' is written only while LockedWeeks/<n> still
 *  freezes the week's date (re-read right before; logged and skipped
 *  otherwise — the next sweep, on a fresh week list, decides).
 *  [S3] When the stored node is the SAME week, open both before and after,
 *  and the deadline moved LATER or the date changed, ReminderSent/<n> goes
 *  first (before GwState, so a crash in between re-arms it on the next run):
 *  the reminder fires again for the new deadline. */
export async function upsertGwState(
  db: FantasyDb, root: string, current: Gameweek | null, nowUtc: Date,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  if (!current) {
    log.info('fantasy sweep: season over — GwState left as-is', ctx);
    return;
  }
  let status: GwStateNode['status'];
  if (gameweekStatusAt(current, nowUtc) === 'locked') {
    const history = await db.read(`${root}/History/${current.number}`);
    status = history != null ? 'finalized' : 'locked';
  } else {
    // 'upcoming' is unreachable for the current gw (orchestration.ts header).
    status = 'open';
  }
  const desired: GwStateNode = {
    current: current.number,
    status,
    lockAtUtc: current.lockUtc.getTime(),
    date: current.date,
  };
  const existing = await db.read(`${root}/GwState`);
  if (gwStateEquals(existing, desired)) return;
  // Ruling T4e: 'locked'/'finalized' only while the ledger still freezes
  // this week's date — a sweep whose week list predates a rewind (or a
  // re-dated lock) must not write its stale 'locked' over the reopened week.
  if (status !== 'open' && !freezesWeekDate(
    await db.read(`${root}/LockedWeeks/${current.number}`), current.date)) {
    log.info('fantasy sweep: week no longer frozen — GwState not marked locked',
      { ...ctx, gw: current.number, date: current.date, status });
    return;
  }
  if (isPlainMap(existing) && status === 'open' &&
    existing['status'] === 'open' &&
    toIntLoose(existing['current']) === desired.current &&
    (desired.lockAtUtc > toIntLoose(existing['lockAtUtc']) ||
      String(existing['date'] ?? '') !== desired.date)) {
    await db.write(`${root}/ReminderSent/${desired.current}`, null);
    log.info('fantasy sweep: open week\'s deadline moved — reminder re-armed', {
      ...ctx, gw: desired.current, lockAtUtc: desired.lockAtUtc, date: desired.date,
    });
  }
  await db.write(`${root}/GwState`, desired);
  log.info('fantasy sweep: GwState updated', { ...ctx, ...desired });
}

// ── The rewind ─────────────────────────────────────────────────────────────

export type RewindResult = 'none' | 'rewound' | 'standDown';

export interface RewindArgs {
  sport: string;
  season: string;
  cfg: FantasyConfig;
  /** The raw Config node (SkippedDates, Deadlines — scheduleOverridesOf). */
  configNode: Record<string, unknown>;
  nowUtc: Date;
  log?: FantasyLogger;
  /** No pusher (tests, dry runs) = no CalledOff claim, no push. */
  pusher?: FantasyPusher;
}

/** Why a frozen week's day is called off; 'kickedOff' = a deadline moved
 *  into the future after a game of the day started (never reopened). */
type RewindReason = 'noGames' | 'skipped' | 'deadlineMoved' | 'kickedOff';

/** Every game node of one date — friendlies too (a day with only a friendly
 *  left is still a game day). */
function gamesOfDay(dayNode: unknown): Record<string, unknown>[] {
  return childEntries(dayNode)
    .map(([, g]) => g)
    .filter((g): g is Record<string, unknown> => isPlainMap(g));
}

function rewindReasonOf(
  games: Record<string, unknown>[], date: string,
  configNode: Record<string, unknown>, nowMs: number,
): RewindReason | null {
  if (games.length === 0) return 'noGames';
  const overrides = scheduleOverridesOf(configNode);
  if (overrides.skippedDates.has(date)) return 'skipped';
  const deadline = overrides.deadlineOverrides[date];
  if (deadline === undefined || deadline.getTime() <= nowMs) return null;
  return games.every((g) => toIntLoose(g['status']) === 0)
    ? 'deadlineMoved' : 'kickedOff';
}

/** The lock judge's Invalid verdict for gameweek [gw] (squad_integrity.ts
 *  invalidAlertNode). */
function isWeekInvalidAlert(node: unknown, gw: number): boolean {
  return isPlainMap(node) && node['Kind'] === 'invalid' &&
    toIntLoose(node['Gw']) === gw;
}

/** [I1] The mark's refusal while a finalize is writing the week. */
const FINALIZING_REFUSED =
  'fantasy rewind: a finalize is scoring the week — the next sweep decides';

/** Removes the rewind's mark again (a finalize won: the week counts). */
async function unmarkWeek(
  db: FantasyDb, root: string, n: number, date: string,
): Promise<void> {
  await updateIfPresent(db, `${root}/LockedWeeks/${n}`, (cur) => {
    if (cur['Rewinding'] !== true || cur['Date'] !== date) return undefined;
    const next = { ...cur };
    delete next['Rewinding'];
    return next;
  });
}

/** History/<n> landed while the week was marked: keep the week. */
async function scoredMeanwhile(
  db: FantasyDb, root: string, n: number, date: string,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<boolean> {
  if ((await db.read(`${root}/History/${n}`)) == null) return false;
  await unmarkWeek(db, root, n, date);
  log.warn('fantasy rewind: the week was scored meanwhile — kept', ctx);
  return true;
}

/** Step 8: the once-only "called off" push (see the header). Every read
 *  happens before the claim, so a failed read leaves the claim free for the
 *  resumed rewind; a failed send is logged and never stops the rewind. */
async function pushCalledOff(
  db: FantasyDb, args: RewindArgs, pusher: FantasyPusher, n: number,
  date: string, log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  const { sport, season, nowUtc } = args;
  const root = fantasyRoot(sport, season);
  const { gws } = await loadSeasonGameweeks(
    db, sport, season, args.cfg, args.configNode, { withoutLockedFrom: n });
  const reopened = gws.find((g) => g.number === n);
  const deadline = reopened !== undefined &&
    reopened.lockUtc.getTime() > nowUtc.getTime()
    ? formatDeadlineInstant(reopened.lockUtc.getTime()) : null;
  const audience = childEntries(await db.read(`${root}/Managers`))
    .map(([uid]) => uid).sort();
  if (!(await db.writeIfAbsent(`${root}/CalledOff/${n}/${date}`,
    { At: nowUtc.getTime() }))) {
    return; // an earlier rewind of this day already told everyone
  }
  const body = calledOffBody(n, deadline);
  const data = fantasyPushData(sport, season, n);
  try {
    const sent = await pusher.sendToUsers(audience.map((uid) => ({
      uid, title: CALLED_OFF_TITLE, body, data,
    })));
    log.info('fantasy rewind: called-off push sent',
      { ...ctx, audience: audience.length, sent });
  } catch (err) {
    log.warn('fantasy rewind: called-off push failed',
      { ...ctx, error: String(err) });
  }
}

/** Rewinds the latest frozen week when its game day was called off (see the
 *  header for the rule and every step). Called only by the sweep
 *  (orchestration.ts sweepSeason), right after its lockOverride and TestFill
 *  stand-downs and before it loads the week list. 'rewound' = the week is
 *  open again (or gone, with no later game day); 'standDown' = the season
 *  holds no game day at all — the sweep stands the season down (warned);
 *  'none' = nothing to do (or a race decided against it). A read that throws
 *  propagates: nothing is written. */
export async function rewindCancelledWeek(
  db: FantasyDb, args: RewindArgs,
): Promise<RewindResult> {
  const { sport, season, nowUtc } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const nowMs = nowUtc.getTime();

  const lockedNode = await db.read(`${root}/LockedWeeks`);
  const frozen = lockedWeeksOf(lockedNode);
  let n = 0;
  while (frozen[n + 1] !== undefined) n++;
  if (n === 0) return 'none';
  const week = frozen[n];
  const raw = childEntries(lockedNode).find(([k]) => k === String(n))?.[1];
  const resuming = isRewinding(raw);
  if (!resuming && week.scored === true) return 'none';
  const ctx = { sport, season, gw: n, date: week.date };

  const games = gamesOfDay(await db.read(`${sport}/${season}/Date/${week.date}`));
  if (games.length === 0 &&
    dateKeysOf(await db.read(`${sport}/${season}/Date`)).length === 0) {
    log.warn('fantasy rewind: the season has no game days at all — standing down',
      ctx);
    return 'standDown';
  }

  if (resuming) {
    log.warn('fantasy rewind: resuming an unfinished rewind', ctx);
  } else {
    const reason = rewindReasonOf(games, week.date, args.configNode, nowMs);
    if (reason === null) return 'none';
    if (reason === 'kickedOff') {
      log.warn('fantasy rewind: deadline moved after kickoff — not reopened', ctx);
      return 'none';
    }
    if ((await db.read(`${root}/History/${n}`)) != null) return 'none';
    // M. The mark — only while the entry still freezes this date, unscored,
    //    and no finalize is writing the week right now ([I1]: a Finalizing
    //    stamp younger than FINALIZING_STALE_MS — the two exclude each other
    //    on this one node; an older stamp is a finalize that died, dropped).
    let finalizing = false;
    const marked = await updateIfPresent(db, `${root}/LockedWeeks/${n}`, (cur) => {
      finalizing = false; // every (re-)run decides afresh
      if (cur['Date'] !== week.date || cur['Scored'] === true) return undefined;
      if (finalizingFresh(cur, nowMs)) {
        finalizing = true;
        return undefined;
      }
      const next: Record<string, unknown> = { ...cur, Rewinding: true };
      delete next['Finalizing'];
      return next;
    });
    if (marked === null) {
      log.info((finalizing as boolean)
        ? FINALIZING_REFUSED
        : 'fantasy rewind: the ledger entry changed meanwhile — the next ' +
          'sweep decides', ctx);
      return 'none';
    }
    log.warn('fantasy rewind: game day called off — rewinding the week',
      { ...ctx, reason });
  }
  if (await scoredMeanwhile(db, root, n, week.date, log, ctx)) return 'none';

  // 0. Who was snapshotted, then 4. their chips (before 1 — see header).
  const uids = childEntries(await db.read(`${root}/PublishedPicks/${n}`))
    .map(([uid]) => uid);
  for (const uid of uids) {
    await updateIfPresent(db, `${root}/TransferState/${uid}`, (cur) => {
      if (cur['ChipPlayed'] == null) return undefined;
      const next = { ...cur };
      delete next['ChipPlayed'];
      return next;
    });
  }
  // 1. The lock snapshots, the reminder claim and the owner's void of the
  //    cancelled day (ruling T4b).
  for (const node of ['PublishedPicks', 'LockedPositions', 'PriceHistory',
    'TransferCosts', 'ReminderSent', 'Voided']) {
    await db.write(`${root}/${node}/${n}`, null);
  }
  // 2. The live week (an abandoned live day) and its settled base.
  const liveMeta = await db.read(`${root}/Live/Meta`);
  if (isPlainMap(liveMeta) && toIntLoose(liveMeta['Gw']) === n) {
    await db.transaction(`${root}/Live`, (cur) => {
      if (cur === null || cur === undefined) return null; // see FantasyDb
      const meta = isPlainMap(cur) ? cur['Meta'] : null;
      return isPlainMap(meta) && toIntLoose(meta['Gw']) === n ? null : undefined;
    });
  }
  if ((await db.read(`${root}/LiveBase/${n}`)) != null) {
    await db.write(`${root}/LiveBase/${n}`, null);
  }
  // 3. The lock judge's Invalid verdicts for this week.
  for (const [uid, alert] of childEntries(await db.read(`${root}/SquadAlerts`))) {
    if (!isWeekInvalidAlert(alert, n)) continue;
    await db.transaction(`${root}/SquadAlerts/${uid}`, (cur) => {
      if (cur === null || cur === undefined) return null; // see FantasyDb
      return isWeekInvalidAlert(cur, n) ? null : undefined;
    });
  }
  // 5. [M3] The money baselines, exactly as before the lock.
  for (const [uid, stored] of childEntries(await db.read(`${root}/Baselines`))) {
    if (restoreBaselineAfterRewind(stored, n) === undefined) continue;
    await db.transaction(`${root}/Baselines/${uid}`, (cur) =>
      cur === null || cur === undefined
        ? null // see FantasyDb
        : restoreBaselineAfterRewind(cur, n));
  }
  // The last word for a finalize that passed its check before the mark.
  if (await scoredMeanwhile(db, root, n, week.date, log, ctx)) return 'none';

  // 8. The push (before 6 — see header).
  if (args.pusher) {
    await pushCalledOff(db, args, args.pusher, n, week.date, log, ctx);
  }
  // 6. The ledger entry — only while it is still our marked one.
  await db.transaction(`${root}/LockedWeeks/${n}`, (cur) => {
    if (cur === null || cur === undefined) return null; // see FantasyDb
    return isRewinding(cur) && (cur as Record<string, unknown>)['Date'] === week.date
      ? null : undefined;
  });
  // 7. GwState for the week list as it now is.
  const { gws } = await loadSeasonGameweeks(
    db, sport, season, args.cfg, args.configNode);
  const current = currentGameweek(gws, nowUtc);
  if (current) {
    await upsertGwState(db, root, current, nowUtc, log, { sport, season });
  } else {
    await db.write(`${root}/GwState`, null);
  }
  log.info('fantasy rewind: week rewound', {
    ...ctx, snapshotted: uids.length,
    reopened: current !== null && current.number === n ? current.date : null,
  });
  return 'rewound';
}

// ── The heal (rulings T3c, T3d) ────────────────────────────────────────────

/** Every lock snapshot of a week — none can stand for a week never locked. */
const LOCK_SNAPSHOTS = ['PublishedPicks', 'LockedPositions', 'PriceHistory',
  'TransferCosts'];

/** The sweep's heal step (see the header) for [week], the derived current
 *  week of [gws] — the CALLER runs it only while that week is open and not
 *  frozen. Ruling T4d: nothing happens unless week n - 1 is frozen in [gws]
 *  (or n is 1) and History/<n> is absent. Cheap when nothing is wrong: one
 *  small read for History/<n>, one per snapshot node, Live/Meta and the
 *  Baselines node. Before each removal LockedWeeks/<n> is re-read: once a
 *  lock of the week has begun (its claim is the lock's first write), the
 *  heal stops. */
export async function healOpenWeek(
  db: FantasyDb, root: string, week: Gameweek, gws: Gameweek[],
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  const n = week.number;
  const wctx = { ...ctx, gw: n, date: week.date };
  if (week.frozen) return;
  if (n > 1 && gws.find((g) => g.number === n - 1)?.frozen !== true) return;
  if ((await db.read(`${root}/History/${n}`)) != null) return;
  const unlocked = async (): Promise<boolean> =>
    (await db.read(`${root}/LockedWeeks/${n}`)) == null;

  for (const node of LOCK_SNAPSHOTS) {
    const path = `${root}/${node}/${n}`;
    if ((await db.read(path)) == null) continue;
    if (!(await unlocked())) return;
    await db.write(path, null);
    log.warn('fantasy heal: orphan lock snapshot of the open week removed',
      { ...wctx, node });
  }

  const liveMeta = await db.read(`${root}/Live/Meta`);
  if (isPlainMap(liveMeta) && toIntLoose(liveMeta['Gw']) === n) {
    if (!(await unlocked())) return;
    await db.transaction(`${root}/Live`, (cur) => {
      if (cur === null || cur === undefined) return null; // see FantasyDb
      const meta = isPlainMap(cur) ? cur['Meta'] : null;
      return isPlainMap(meta) && toIntLoose(meta['Gw']) === n ? null : undefined;
    });
    log.warn('fantasy heal: live node of the open week removed', wctx);
  }

  for (const [uid, stored] of childEntries(await db.read(`${root}/Baselines`))) {
    if (baselineForGwOf(stored) !== n + 1) continue;
    if (!(await unlocked())) return;
    const res = await db.transaction(`${root}/Baselines/${uid}`, (cur) =>
      cur === null || cur === undefined
        ? null // see FantasyDb
        : restoreBaselineAfterRewind(cur, n));
    if (res.committed) {
      log.warn('fantasy heal: a baseline written for a lock that never stood — ' +
        'restored', { ...wctx, uid });
    }
  }
}

// ── The Config trigger ─────────────────────────────────────────────────────

/** The Config keys that move a deadline or a game day. */
const SCHEDULE_KEYS = [
  'Deadlines', 'SkippedDates', 'deadlineMinutesBeforeKickoff', 'lockHour',
];

/** Key-order-independent JSON of an RTDB value (absent = null). */
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (isPlainMap(v)) {
    return `{${Object.keys(v).sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v ?? null);
}

/** The Config trigger's zero-read gate: true when Deadlines, SkippedDates,
 *  deadlineMinutesBeforeKickoff or lockHour differ between the trigger's
 *  before and after values (Config created or removed counts). */
export function scheduleConfigChanged(before: unknown, after: unknown): boolean {
  const b = isPlainMap(before) ? before : {};
  const a = isPlainMap(after) ? after : {};
  return SCHEDULE_KEYS.some((k) => canonical(b[k]) !== canonical(a[k]));
}

/** The Config trigger's body (fantasy_schedule.ts): an OPEN current week's
 *  GwState follows the owner's schedule edit at once (upsertGwState — a
 *  later deadline re-arms the reminder). Stands down without Config, for a
 *  TestFill season and under a non-auto lockOverride, like every job; a
 *  locked current week (or none) is left to the sweep. Never rewinds. */
export async function refreshOpenGwState(
  db: FantasyDb,
  args: { sport: string; season: string; nowUtc: Date; log?: FantasyLogger },
): Promise<void> {
  const { sport, season, nowUtc } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season };

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  if (lockOverrideOf(configNode, nowUtc.getTime()) !== 'auto') {
    log.info('fantasy schedule: lockOverride frozen — standing down', ctx);
    return;
  }
  if (await isTestFillSeason(db, root)) {
    log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'schedule' });
    return;
  }
  const { gws } = await loadSeasonGameweeks(
    db, sport, season, configFromMap(configNode), configNode);
  const current = currentGameweek(gws, nowUtc);
  if (!current || gameweekStatusAt(current, nowUtc) === 'locked') return;
  await upsertGwState(db, root, current, nowUtc, log, ctx);
}
