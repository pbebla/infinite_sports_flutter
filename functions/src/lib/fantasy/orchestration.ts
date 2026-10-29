// Fantasy server jobs (P4 Phases B–D), database-injected and emulator-free:
// the 15-minute lifecycle sweep (gameweek state + lock snapshots + finalize
// backstop), the match-day finalize entry the RTDB trigger calls, and the
// Monday repricing job. All math lives in the pure engine
// (finalize_core.ts + the ported lib); this file only loads inputs through
// the FantasyDb seam, decides WHEN, and applies the outputs.
//
// NODES THIS FILE OWNS (all under Fantasy/<sport>/<season>):
//
// - GwState = { current:int, status:'open'|'locked'|'finalized',
//   lockAtUtc:int (epoch ms of the engine lock instant), date:'MMDDYYYY' }.
//   Server truth for the jobs — the fan countdown still derives locally from
//   the schedule stream; no client reads this node. Written only by the
//   sweep, only when a field actually changed (idempotent no-op otherwise).
//   'finalized' means the CURRENT gameweek is locked and its History exists;
//   when the next gameweek opens, current advances and status returns to
//   'open'. The engine's 'upcoming' can never be the current gameweek's
//   status (opens <= previous lock + 24h always), but is mapped to 'open'
//   defensively.
//
// - PublishedPicks/<gw> = verbatim Squads snapshot (uid -> squad map), the
//   spec §9 anti-copy reveal. Written ONCE via a set-if-absent claim the
//   first time the sweep sees the current gameweek locked — never
//   overwritten, so late sweeps after downtime still snapshot exactly once.
//
// - LockedPositions/<gw> = { <name>: 'GK'|'DEF'|'ATT' } — every market
//   player's position at the lock (spec §3 revision 2026-10-28: positions
//   are locked per gameweek). Written ONCE alongside the PublishedPicks
//   claim (set-if-absent; a FIRST finalize that outran every sweep claims
//   it too, from the positions at that moment). Finalize and the Monday
//   reprice of <gw> read positions from it, so a score-edit rerun of an old
//   week never uses a later position; weeks locked before this snapshot
//   existed fall back to the live Players positions. Public read.
//
// - Repriced/<gw> = { At:int, Manual?:true, Voided?:true } — the Monday
//   job's done-flag. Manual:true records "admin had set
//   PriceChanges/<gw>/Manual, the job stood down"; Voided:true records "the
//   week was owner-voided, the job skipped it" (un-voiding later does NOT
//   reprice retroactively — prices have moved on). PriceChanges/<gw> itself
//   holds only the client contract rows: <name>: { delta:int EFFECTIVE
//   tenths } (post-clamp; zero moves omitted — a ceiling-clamped riser is
//   not a riser).
//
// - PlayerWeeks/<gw>/<name> = int (functions-internal; see finalize_core.ts).
//
// - TransferState/<uid> = { Free:int, UsedThisGw:int, ChipPlayed?:string,
//   SavedGw?:int, RolledGw?:int } — the Phase E transfer ledger; the
//   field-by-field contract lives in transfer_state.ts. Written by the
//   Squads/<uid> trigger (recordSquadSave), the lock step (ChipPlayed
//   freeze) and the post-finalize rollover. Rules: read own + admin, no
//   client write (functions only).
//
// - TransferCosts/<gw>/<uid> = int points (functions-internal, like
//   PlayerWeeks): the week's transfer charge frozen at lock — the
//   transferCostPointsByUid seam's source on every finalize (re)run, so a
//   score-edit rerun recharges exactly what was charged the first time.
//
// - ReminderSent/<gw> = { At:int } and RecapSent/<gw> = { At:int }
//   (functions-internal): once-only claims for the Phase F pushes. Claimed
//   via writeIfAbsent BEFORE sending, and only when a pusher was injected —
//   a sweep without one (tests) leaves them unclaimed.
//
// - NewsDrafted/<gw> = { At:int } (functions-internal): once-only claim for
//   the Phase G news step (the Dream Team post + the AI drafts + the admin
//   heads-up push). The News/Drafts, News/Published and Config/NewsAutopilot
//   (legacy Config/DreamTeamPost) shapes live in news.ts.
//
// - Voided/<gw> = true (READ-only here; the Manager's "VOID week" toggle
//   writes true or removes it — spec §15). A voided week settles to zero
//   (finalize_core.ts VOIDED GAMEWEEKS), its transfer cost is waived (the
//   lock still freezes TransferCosts/<gw> so an un-void recharges exactly
//   that), chips played in it are refunded at later locks, the Free Hit
//   restore + rollover run as normal, the Monday job skips it, and its
//   news drafts never auto-publish while the flag stands. Its settle
//   claims RecapSent/<gw> and NewsDrafted/<gw> as { At, Voided:true }
//   WITHOUT sending or drafting — regardless of whether a pusher/news dep
//   was injected, since there is nothing to deliver. Toggling the flag
//   re-runs the finalize entry (resettleVoidToggle, fantasy_void.ts
//   trigger). DOCUMENTED CHOICE: un-voiding a week whose guards the void
//   path already claimed re-settles every score but sends NO late recap and
//   drafts NO late news — days-late "GW n" pushes after an owner flip-flop
//   are noise, and the guards are once-only by design.
//
// Finalize manager-source precedence (documented contract): the lock
// snapshot PublishedPicks/<gw> is the law; a rerun without one re-reads the
// squads stored in History/<gw> (deterministic reruns); only a FIRST run of
// the LATEST lock-passed gameweek may fall back to live Squads (so enabling
// fantasy mid-season can never fabricate history for weeks nobody played).
//
// Config.lockOverride: anything but absent/'auto' freezes the machine —
// sweep, finalize and repricing all stand down for that season (the owner's
// sandbox escape hatch; the H rehearsal flips a COPY season to 'auto').
// An optional Config.lockOverrideUntil (epoch ms) bounds it: every check
// reads the EFFECTIVE value at its job's now (lockOverrideOf), and the sweep
// reverts an expired override to 'auto' in the DB (spec §2 auto-return).

import {
  configFromMap, FANTASY_POSITIONS, FantasyConfig,
} from './fantasy_config';
import { FetchLike } from '../support';
import {
  computeGameweekFinalize, FinalizeGame, MarketPlayer,
} from './finalize_core';
import {
  currentGameweek, deriveGameweeks, Gameweek, gameweekStatusAt,
} from './gameweeks';
import {
  buildDreamTeamDraft, buildNewsStats, dreamTeamNames,
  formatLeagueWeekdayTime, generateNewsDrafts, newsAutopilotConfigFrom,
  nextLeagueWeekdayInstantUtc, publishedRowFromDraft, shouldAutoPublish,
} from './news';
import { buildPlayerCard, cardsNode, seasonGoalsAssists } from './news_cards';
import {
  allGamesFinal, childEntries, dateKeysOf, FantasyDb, fantasyRoot,
  fantasySeasonsOf, fullAttendance, gamesOfDate, isPlainMap,
  isServerSquadWrite, isVoidFlag, lockedPositionsOf, lockOverrideOf,
  marketPlayersOf, marketPricesOf, markServerSquadWrite, parseAbsentMap,
  positionsSnapshotOf, rosterNamesOf, SERVER_WRITE_KEY, toIntLoose,
  voidedWeeksOf, withLockedPositions,
} from './orchestration_db';
import { applyDelta, repriceDeltas } from './pricing';
import {
  adminUidsOf, FantasyPusher, fantasyPushData, fillReminderTemplate,
  formatDeadline, NEWS_READY_TITLE, newsReadyBody, RECAP_TITLE, recapBody,
  REMINDER_TITLE, reminderAudience, reminderConfigFrom, reminderInstantMs,
} from './pushes';
import {
  applyPendingPositionChanges, positionWindowOf,
} from './position_changes';
import {
  FantasySquad, squadFromMap, squadToMap, validateSquad,
} from './squad';
import { parseForfeitedBy } from './stats_mapper';
import {
  lockAccounting, parseTransferState, rolloverState, transferStateToNode,
  usedAfterFreeSwaps,
} from './transfer_state';

/** Injected logging seam (firebase-functions/logger in production, a spy or
 *  nothing in tests). */
export interface FantasyLogger {
  info(message: string, context?: Record<string, unknown>): void;
  warn(message: string, context?: Record<string, unknown>): void;
}

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

/** Impure capabilities injected into the jobs. Everything is optional: a
 *  caller without one (tests, a misconfigured deploy) skips that side
 *  effect — and its once-only guard stays unclaimed, so a later properly
 *  equipped run still delivers. */
export interface FantasyJobDeps {
  /** FCM (Phase F): deadline reminders + weekly recaps. */
  pusher?: FantasyPusher;
  /** Anthropic (Phase G): AI news drafting after finalize. A blank apiKey
   *  (or an API failure) skips the AI drafts with a log — the deterministic
   *  Dream Team post still builds, and finalize never blocks. */
  news?: { apiKey: string; fetchImpl?: FetchLike; timeoutMs?: number };
}

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

/** Map-shaped children only (a squad/history uid node must be a map). */
function mapChildren(node: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of childEntries(node)) {
    if (isPlainMap(v)) out[k] = v;
  }
  return out;
}

// ── Phase E: transfer accounting ───────────────────────────────────────────

/** Merge the lock-frozen effective chip into each manager's TransferState.
 *  Every other field survives; a no-chip week clears any stale ChipPlayed
 *  (so a crashed earlier lock can never leak a Free Hit restore). */
async function freezeChipPlayed(
  db: FantasyDb, root: string, cfg: FantasyConfig,
  chipPlayedByUid: Record<string, string | null>,
): Promise<void> {
  for (const [uid, chip] of Object.entries(chipPlayedByUid)) {
    const state = parseTransferState(
      await db.read(`${root}/TransferState/${uid}`), cfg);
    await db.write(`${root}/TransferState/${uid}`,
      transferStateToNode({ ...state, chipPlayed: chip }));
  }
}

/** The squad a manager effectively HELD coming out of gameweek [week]: the
 *  locked squad of [week] (PublishedPicks/<week>/<uid>, else
 *  History/<week>/<uid>) — except after a Free Hit week, whose squad lasts
 *  ONE week (spec §6): then it is the effective squad of the week before,
 *  recursively (a set-2 Free Hit right after a set-1 Free Hit still returns
 *  to the last real squad). A Free Hit with nothing before it (a GW1 Free
 *  Hit) keeps its own squad — there was nothing to restore. null = no locked
 *  squad for [week]. Voided chips were stripped from the snapshot at lock,
 *  so only an HONORED Free Hit ever redirects.
 *
 *  The ONE baseline shared by the Free Hit restore (what goes back into
 *  Squads/<uid>) and the transfer counter (what a save is compared
 *  against), so the two can never disagree — the S15 rehearsal's Bug 1 was
 *  exactly that disagreement (the counter compared against the Free Hit
 *  squad while the restore had already put the old squad back). */
async function effectiveSquadAfterWeek(
  db: FantasyDb, root: string, uid: string, week: number,
): Promise<Record<string, unknown> | null> {
  if (week <= 0) return null;
  const locked = (await db.read(`${root}/PublishedPicks/${week}/${uid}`)) ??
    (await db.read(`${root}/History/${week}/${uid}`));
  if (!isPlainMap(locked)) return null;
  if (locked['chip'] === 'freeHit') {
    return (await effectiveSquadAfterWeek(db, root, uid, week - 1)) ?? locked;
  }
  return locked;
}

/** Chips are ONE-WEEK (S15 rehearsal Bug 2, owner decision 2026-10-28):
 *  once a gameweek settles, whatever chip the live squad still carries is
 *  switched off (Squads/<uid>/chip removed), so next week starts chipless.
 *  A chip may still be played again in set 2 — by a FRESH activation; a
 *  forgotten chip can no longer sit armed and auto-fire at the first set-2
 *  lock. Every chip type, honored or voided at lock.
 *
 *  One guard for a DELAYED finalize (the next window already open and the
 *  manager already saved for it, SavedGw > gw): a live chip that differs
 *  from the one locked this week is a deliberate activation for next week
 *  and stays. (Documented limit: in that delayed case a chip that was
 *  VOIDED at this week's lock stays too — it is voided again at the next
 *  lock inside the same set.) */
async function switchOffSpentChip(
  db: FantasyDb, root: string, uid: string, gw: number,
  savedGw: number | null, nowMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  const live = await db.read(`${root}/Squads/${uid}`);
  if (!isPlainMap(live) || live['chip'] == null) return;
  const chip = live['chip'];
  if (savedGw !== null && savedGw > gw) {
    const locked = (await db.read(`${root}/PublishedPicks/${gw}/${uid}`)) ??
      (await db.read(`${root}/History/${gw}/${uid}`));
    const lockedChip = isPlainMap(locked) ? (locked['chip'] ?? null) : null;
    if (chip !== lockedChip) return; // a fresh activation for next week
  }
  // A server write, not a manager save (orchestration_db.ts SERVER_WRITE_KEY):
  // the marker lands first so the Squads trigger never stamps SavedGw.
  await markServerSquadWrite(db, root, uid, nowMs);
  await db.write(`${root}/Squads/${uid}/chip`, null);
  log.info('fantasy chips: spent chip switched off', { ...ctx, gw, uid, chip });
}

/** Once per gameweek, right after a finalize wrote History/<gw> (RolledGw is
 *  the guard — reruns from score/attendance edits never re-settle): restore
 *  a Free Hit manager's previous squad, switch off any chip still armed on
 *  the live squad (chips are one-week), then roll free transfers for next
 *  week. The restored squad is the engine round-trip of the manager's
 *  effective squad before the Free Hit (effectiveSquadAfterWeek(gw-1)) with
 *  NO chip — a restore never re-arms a chip. A GW1 Free Hit has nothing to
 *  restore (logged); its chip is still switched off. */
async function settleTransfersAfterFinalize(
  db: FantasyDb, root: string, cfg: FantasyConfig, gw: number,
  uids: string[], nowMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  for (const uid of uids) {
    const state = parseTransferState(
      await db.read(`${root}/TransferState/${uid}`), cfg);
    if (state.rolledGw !== null && state.rolledGw >= gw) continue;
    if (state.chipPlayed === 'freeHit') {
      const prevRaw = await effectiveSquadAfterWeek(db, root, uid, gw - 1);
      let restored: Record<string, unknown> | null = null;
      if (isPlainMap(prevRaw)) {
        try {
          restored = squadToMap({ ...squadFromMap(prevRaw), chip: null });
        } catch { /* unreadable previous squad — warn below */ }
      }
      if (restored !== null) {
        // Server-originated (SERVER_WRITE_KEY): the restore is not the
        // manager saving, so it must not satisfy the deadline reminder.
        await db.write(`${root}/Squads/${uid}`,
          { ...restored, [SERVER_WRITE_KEY]: nowMs });
        log.info('fantasy freeHit: previous squad restored', { ...ctx, gw, uid });
      } else {
        log.warn('fantasy freeHit: no previous locked squad to restore',
          { ...ctx, gw, uid });
      }
    }
    await switchOffSpentChip(db, root, uid, gw, state.savedGw, nowMs, log, ctx);
    await db.write(`${root}/TransferState/${uid}`,
      transferStateToNode(rolloverState(state, cfg, gw)));
  }
}

export interface SquadSaveArgs {
  sport: string;
  season: string;
  uid: string;
  log?: FantasyLogger;
  /** Clock for the position-window check (default: real now). */
  nowUtc?: Date;
  /** The triggering write's after-value (event.data.after.val()) — WHO
   *  wrote is judged on it (SERVER_WRITE_KEY), so a manager save that races
   *  a server write is still counted. Absent (tests, the rehearsal's
   *  replay) = judged on the node as read now. */
  after?: unknown;
}

/** The Squads/<uid> trigger entry (Phase E + spec §3 holder protection).
 *
 *  1. Holder protection, on every save of a fantasy-enabled 'auto' season:
 *     - while position changes apply live (positionWindowOf 'open'), any
 *       pick whose label differs from the player's LIVE market position is
 *       re-labelled (child write) — so a save from a stale draft (an old
 *       app, or a draft dirty since before the change) can never quietly
 *       revert a position change or dodge its alert;
 *     - a standing SquadAlerts/<uid> is cleared once the (re-labelled)
 *       squad's formation is legal.
 *  2. Transfer counting, while the current gameweek is open: recompute the
 *     used-transfer count against the manager's EFFECTIVE previous squad
 *     (effectiveSquadAfterWeek(gw-1): the squad locked last week — or,
 *     after a Free Hit week, the squad the restore put back), minus any
 *     alerted player sold this week (FreeSwaps — free by spec §3), and
 *     stamp SavedGw. Counting needs a baseline, so a first-ever squad (GW1,
 *     or a mid-season joiner) records UsedThisGw 0 — the initial build is
 *     free — but still stamps SavedGw so the deadline reminder knows the
 *     manager acted this week. Recomputed (not incremented) on every save:
 *     undoing a transfer before the deadline un-counts it. Saves while
 *     locked/frozen and squad deletions are never counted.
 *     SERVER-ORIGINATED writes (the node carries SERVER_WRITE_KEY — chip
 *     switch-off, Free Hit restore, position re-labels, incl. this
 *     function's own) are recounted the same way but NEVER stamp SavedGw:
 *     only the manager's own save means "acted this week" for the deadline
 *     reminder. A SavedGw from an earlier manager save is kept as is. */
export async function recordSquadSave(
  db: FantasyDb, args: SquadSaveArgs,
): Promise<void> {
  const { sport, season, uid } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, uid };
  const nowMs = (args.nowUtc ?? new Date()).getTime();

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  if (lockOverrideOf(configNode, nowMs) !== 'auto') return; // frozen machine
  const cfg = configFromMap(configNode);

  const gwState = await db.read(`${root}/GwState`);
  const raw = await db.read(`${root}/Squads/${uid}`);
  if (!isPlainMap(raw)) return; // deletion: nothing to count
  const serverWrite =
    isServerSquadWrite(args.after !== undefined ? args.after : raw);
  let squad: FantasySquad;
  try {
    squad = squadFromMap(raw);
  } catch {
    log.warn('fantasy transfers: malformed squad save — not counted', ctx);
    return;
  }

  // ── 1. Holder protection ──
  if (positionWindowOf(gwState, nowMs) === 'open') {
    const market = marketPlayersOf(await db.read(`${root}/Players`));
    let relabels = 0;
    for (const [k, pick] of childEntries(raw['picks'])) {
      if (!isPlainMap(pick)) continue;
      const live = market[String(pick['playerId'] ?? '')]?.position;
      if (live !== undefined && pick['position'] !== live) {
        // Our own re-label is a server write: mark first (once), so its
        // trigger re-run never counts as a manager save.
        if (relabels === 0) await markServerSquadWrite(db, root, uid, nowMs);
        await db.write(`${root}/Squads/${uid}/picks/${k}/position`, live);
        relabels++;
      }
    }
    if (relabels > 0) {
      squad = {
        ...squad,
        picks: squad.picks.map((p) =>
          ({ ...p, position: market[p.playerId]?.position ?? p.position })),
      };
      log.info('fantasy positions: stale labels on a save re-labelled',
        { ...ctx, relabels });
    }
  }
  if ((await db.read(`${root}/SquadAlerts/${uid}`)) != null &&
    !validateSquad(squad, cfg).includes('formation')) {
    await db.write(`${root}/SquadAlerts/${uid}`, null);
    log.info('fantasy positions: formation legal — squad alert cleared', ctx);
  }

  // ── 2. Transfer counting (open gameweek only) ──
  if (!isPlainMap(gwState) || String(gwState['status'] ?? '') !== 'open') return;
  const gw = toIntLoose(gwState['current']);
  if (gw <= 0) return;

  const state = parseTransferState(
    await db.read(`${root}/TransferState/${uid}`), cfg);
  let used = 0;
  const prevRaw = await effectiveSquadAfterWeek(db, root, uid, gw - 1);
  if (isPlainMap(prevRaw)) {
    try {
      used = usedAfterFreeSwaps(squad, squadFromMap(prevRaw), state, gw);
    } catch {
      log.warn('fantasy transfers: unreadable previous squad — counted 0',
        { ...ctx, gw });
    }
  }

  await db.write(`${root}/TransferState/${uid}`, transferStateToNode({
    ...state, usedThisGw: used, savedGw: serverWrite ? state.savedGw : gw,
  }));
  log.info(serverWrite
    ? 'fantasy transfers: server squad write recounted (not a manager save)'
    : 'fantasy transfers: squad save counted', { ...ctx, gw, used });
}

// ── Phase C: finalization ──────────────────────────────────────────────────

/** The most recent PriceChanges rows at or before [gw] — the risers/fallers
 *  the managers are currently looking at (the news inputs; null = the
 *  season has not repriced yet). */
async function latestPriceChanges(
  db: FantasyDb, root: string, gw: number,
): Promise<unknown> {
  let best = -1;
  for (const [w] of childEntries(await db.read(`${root}/PriceChanges`))) {
    const week = Number(w);
    if (Number.isInteger(week) && week <= gw && week > best) best = week;
  }
  return best < 0 ? null : await db.read(`${root}/PriceChanges/${best}`);
}

export interface FinalizeArgs {
  sport: string;
  season: string;
  cfg: FantasyConfig;
  gw: Gameweek;
  nowUtc: Date;
  log?: FantasyLogger;
  deps?: FantasyJobDeps;
}

/** Loads one gameweek's inputs, runs the pure pipeline, writes every output
 *  node. Deterministic and rerunnable: whole-node sets of recomputed values
 *  (DreamTeam excepted — an admin-edited node is left alone). Returns a
 *  summary for the caller's log, or null when the date held no final games. */
export async function finalizeGameweek(
  db: FantasyDb, args: FinalizeArgs,
): Promise<{ managers: number; source: string } | null> {
  const { sport, season, cfg, gw } = args;
  const log = args.log ?? silent;
  const ctx = { sport, season, gw: gw.number, date: gw.date };
  const root = fantasyRoot(sport, season);

  const dateNode = await db.read(`${sport}/${season}/Date/${gw.date}`);
  const gameNodes = gamesOfDate(dateNode)
    .filter((g) => toIntLoose(g['status']) === 2);
  if (gameNodes.length === 0) {
    log.warn('fantasy finalize: no final games on date', ctx);
    return null;
  }

  // Attendance: roster-derived full maps (spec §8 default-present) with the
  // absent-only team{n}attendance node applied on top.
  const lineups = await db.read(`${sport}/${season}/Line Ups`);
  const games: FinalizeGame[] = gameNodes.map((node) => {
    const attendance: Record<string, Record<string, boolean> | null> = {};
    (['team1', 'team2'] as const).forEach((key, i) => {
      const team = node[key];
      if (typeof team !== 'string' || team.length === 0) return;
      const roster = rosterNamesOf(lineups, team);
      if (roster.length === 0) {
        // On a forfeit (spec §8a) events are ignored, so a missing roster
        // means nobody on this team gets the appearance point — say so.
        log.warn('fantasy finalize: no roster for team — scoring activity ' +
          'players only', {
          ...ctx, team, forfeit: parseForfeitedBy(node['forfeitedBy']) !== null,
        });
      }
      attendance[team] =
        fullAttendance(roster, parseAbsentMap(node[`team${i + 1}attendance`]));
    });
    return { node, attendance };
  });

  // Owner voids (spec §15): this week and every other voided week resum as
  // zero; chips from voided weeks are refunded in the lock accounting.
  const voidedWeeks = voidedWeeksOf(await db.read(`${root}/Voided`));
  const voided = voidedWeeks.includes(gw.number);

  // Manager squads: PublishedPicks (the lock snapshot) -> History (squad
  // part, for deterministic reruns) -> live Squads (first-run fallback; the
  // callers gate WHICH gameweeks may use it).
  const historyRaw = await db.read(`${root}/History`);
  const historyThisGw = childEntries(historyRaw)
    .find(([w]) => Number(w) === gw.number)?.[1] ?? null;
  const firstRun = historyThisGw == null;

  // The market at this week's LOCKED positions (LockedPositions/<gw>); a
  // first run that outran every sweep claims the snapshot itself.
  const players = await marketForGameweek(db, root, gw.number, firstRun, log, ctx);
  let source = 'publishedPicks';
  let squadsByUid = mapChildren(await db.read(`${root}/PublishedPicks/${gw.number}`));
  if (Object.keys(squadsByUid).length === 0) {
    squadsByUid = mapChildren(historyThisGw);
    source = 'history';
  }
  if (Object.keys(squadsByUid).length === 0) {
    squadsByUid = mapChildren(await db.read(`${root}/Squads`));
    source = 'squadsFallback';
  }

  // ── Phase E: the week's frozen transfer costs. The lock step persisted
  // TransferCosts/<gw>; a FIRST finalize that outran every sweep (or the
  // live-Squads first run of a mid-season enablement) does the lock
  // accounting now, over whatever squad source resolved above, and persists
  // it so reruns stay deterministic. Reruns of weeks with no persisted
  // costs (pre-accounting weeks) read zeros, exactly as they settled. ──
  let costsRaw = await db.read(`${root}/TransferCosts/${gw.number}`);
  if (costsRaw == null && firstRun) {
    const acc = lockAccounting({
      squadsByUid,
      statesByUid: mapChildren(await db.read(`${root}/TransferState`)),
      historyRaw,
      cfg,
      gw: gw.number,
      voidedWeeks,
    });
    squadsByUid = acc.cleanSquads;
    for (const v of acc.voided) {
      log.warn('fantasy lock: chip voided — already used in this set',
        { ...ctx, ...v });
    }
    if (Object.keys(acc.costPointsByUid).length > 0) {
      await db.write(`${root}/TransferCosts/${gw.number}`, acc.costPointsByUid);
    }
    await freezeChipPlayed(db, root, cfg, acc.chipPlayedByUid);
    costsRaw = acc.costPointsByUid;
  }
  const transferCostPointsByUid: Record<string, number> = {};
  for (const [u, v] of childEntries(costsRaw)) {
    transferCostPointsByUid[u] = toIntLoose(v);
  }

  // Other weeks' stored results (this week's are replaced by the compute).
  const playerWeeksByWeek: Record<number, Record<string, number>> = {};
  for (const [w, byName] of childEntries(await db.read(`${root}/PlayerWeeks`))) {
    const week = Number(w);
    if (!Number.isInteger(week) || week === gw.number) continue;
    const m: Record<string, number> = {};
    for (const [name, v] of childEntries(byName)) m[name] = toIntLoose(v);
    playerWeeksByWeek[week] = m;
  }
  const historyTenthsByWeek: Record<number, Record<string, number>> = {};
  for (const [w, byUid] of childEntries(historyRaw)) {
    const week = Number(w);
    if (!Number.isInteger(week) || week === gw.number) continue;
    const m: Record<string, number> = {};
    for (const [uid, entry] of childEntries(byUid)) {
      if (isPlainMap(entry)) m[uid] = toIntLoose(entry['TotalTenths']);
    }
    historyTenthsByWeek[week] = m;
  }

  // Ownership is a "right now" figure: a rerun of an OLDER week (a late
  // score correction) keeps PlayerTotals ownership on the latest finalized
  // week's squads (S15 rehearsal 2.5c) — History holds them squad-shaped.
  let ownershipSquadsByUid: Record<string, unknown> | undefined;
  const laterWeeks = childEntries(historyRaw)
    .map(([w]) => Number(w))
    .filter((w) => Number.isInteger(w) && w > gw.number);
  if (laterWeeks.length > 0) {
    const latest = Math.max(...laterWeeks);
    ownershipSquadsByUid = mapChildren(childEntries(historyRaw)
      .find(([w]) => Number(w) === latest)?.[1] ?? null);
  }

  const dreamRaw = await db.read(`${root}/DreamTeam/${gw.number}`);
  const dreamTeamAuto = dreamRaw == null
    ? null
    : isPlainMap(dreamRaw) && dreamRaw['Auto'] === true;

  const out = computeGameweekFinalize({
    cfg,
    gw: gw.number,
    games,
    players,
    squadsByUid,
    transferCostPointsByUid,
    playerWeeksByWeek,
    historyTenthsByWeek,
    dreamTeamAuto,
    voidedWeeks,
    ownershipSquadsByUid,
    nowMs: args.nowUtc.getTime(),
  });

  for (const uid of out.skippedSquadUids) {
    log.warn('fantasy finalize: malformed squad skipped', { ...ctx, uid, source });
  }

  if (Object.keys(out.playerWeeks).length > 0) {
    await db.write(`${root}/PlayerWeeks/${gw.number}`, out.playerWeeks);
  }
  if (Object.keys(out.historyByUid).length > 0) {
    await db.write(`${root}/History/${gw.number}`, out.historyByUid);
    await db.write(`${root}/Leaderboards/Gameweek/${gw.number}`, out.gameweekBoard);
    await db.write(`${root}/Leaderboards/Overall`, out.overallBoard);
  } else {
    log.warn('fantasy finalize: no manager squads to score', { ...ctx, source });
  }
  if (Object.keys(out.playerTotals).length > 0) {
    await db.write(`${root}/PlayerTotals`, out.playerTotals);
  }
  if (out.dreamTeam !== null) {
    await db.write(`${root}/DreamTeam/${gw.number}`, out.dreamTeam);
  } else if (out.removeAutoDreamTeam) {
    await db.write(`${root}/DreamTeam/${gw.number}`, null);
    log.info('fantasy finalize: voided week — auto DreamTeam removed', ctx);
  } else if (dreamTeamAuto === false) {
    log.info('fantasy finalize: DreamTeam admin-edited — preserved', ctx);
  }

  // Phase E epilogue: Free Hit squad restore + free-transfer rollover,
  // once per gameweek (RolledGw-guarded — score-edit reruns skip it).
  if (Object.keys(out.historyByUid).length > 0) {
    await settleTransfersAfterFinalize(
      db, root, cfg, gw.number, Object.keys(out.historyByUid),
      args.nowUtc.getTime(), log, ctx);
  }

  // Owner-voided week: claim both once-only guards WITHOUT pushing or
  // drafting (pusher or not — nothing to deliver), so neither fires later,
  // not even after an un-void (documented choice; see header).
  if (voided) {
    for (const guard of ['RecapSent', 'NewsDrafted']) {
      const path = `${root}/${guard}/${gw.number}`;
      if ((await db.read(path)) != null) continue;
      if (await db.writeIfAbsent(path,
        { At: args.nowUtc.getTime(), Voided: true })) {
        log.info('fantasy finalize: voided week — guard claimed, nothing sent',
          { ...ctx, guard });
      }
    }
  }

  // Phase F: weekly recap push, once per gameweek (RecapSent-guarded — the
  // recap tells the FIRST settle's story; score-edit reruns never re-push).
  const pusher = args.deps?.pusher;
  if (!voided && pusher && Object.keys(out.historyByUid).length > 0 &&
    (await db.read(`${root}/RecapSent/${gw.number}`)) == null) {
    const won = await db.writeIfAbsent(`${root}/RecapSent/${gw.number}`,
      { At: args.nowUtc.getTime() });
    if (won) {
      const topScore = Math.max(
        ...Object.values(out.gameweekBoard).map((r) => r.points));
      const data = fantasyPushData(sport, season, gw.number);
      const messages = Object.keys(out.historyByUid).sort().map((uid) => ({
        uid,
        title: RECAP_TITLE,
        body: recapBody({
          gw: gw.number,
          points: out.gameweekBoard[uid]?.points ?? 0,
          rank: out.overallBoard[uid]?.rank ?? 0,
          topScore,
        }),
        data,
      }));
      const sent = await pusher.sendToUsers(messages);
      log.info('fantasy recap pushed',
        { ...ctx, managers: messages.length, sent });
    }
  }

  // Phase G: news drafts, once per gameweek (NewsDrafted-guarded). The
  // Dream Team post always builds — deterministic, from the SAME stored
  // DreamTeam node the hub reads — while the 2–4 AI drafts land only when
  // the Anthropic call succeeds: an API failure or blank key writes NOTHING
  // (logged) and never blocks the finalize (spec §13). News desk 2.0 (spec
  // 2026-10-28 §4.4): every draft carries player-card snapshots of the
  // players it tags, the autopilot (ON unless Config/NewsAutopilot says
  // Enabled:false) schedules every draft, and the admins get one heads-up.
  if (!voided && (await db.read(`${root}/NewsDrafted/${gw.number}`)) == null) {
    const wonNews = await db.writeIfAbsent(`${root}/NewsDrafted/${gw.number}`,
      { At: args.nowUtc.getTime() });
    if (wonNews) {
      const nowMs = args.nowUtc.getTime();
      const dreamTeamRaw =
        out.dreamTeam ?? await db.read(`${root}/DreamTeam/${gw.number}`);
      const autopilot = newsAutopilotConfigFrom(
        await db.read(`${root}/Config/NewsAutopilot`),
        await db.read(`${root}/Config/DreamTeamPost`));
      const publishAt = autopilot.enabled
        ? nextLeagueWeekdayInstantUtc(
          args.nowUtc, autopilot.weekday, autopilot.hour)
        : null;
      const schedule = publishAt !== null
        ? { AutoPublishAt: publishAt.getTime() } : {};

      // Card sources, read fresh: finalize wrote PlayerWeeks/PlayerTotals
      // above; goals/assists tally the whole season's Date node once.
      const cardSources = {
        playersRaw: await db.read(`${root}/Players`),
        playerTotalsRaw: await db.read(`${root}/PlayerTotals`),
        playerWeeksRaw: await db.read(`${root}/PlayerWeeks`),
        priceChangesRaw: await db.read(`${root}/PriceChanges`),
        goalsAssists: seasonGoalsAssists(
          await db.read(`${sport}/${season}/Date`)),
      };
      const cardsFor = (names: string[]) =>
        names.map((name) => buildPlayerCard(name, cardSources));

      let drafted = 0;
      const dtDraft = buildDreamTeamDraft({
        gw: gw.number,
        dreamTeamRaw,
        nowMs,
        autoPublishAtMs: publishAt?.getTime() ?? null,
        cards: cardsFor(dreamTeamNames(dreamTeamRaw)),
      });
      if (dtDraft !== null) {
        await db.write(`${root}/News/Drafts/gw${gw.number}dreamteam`, dtDraft);
        drafted++;
        log.info('fantasy news: dream team post drafted', ctx);
      }

      const news = args.deps?.news;
      if (news?.apiKey) {
        const drafts = await generateNewsDrafts({
          stats: buildNewsStats({
            gw: gw.number,
            playerWeeksThisGw: out.playerWeeks,
            playerWeeksPrevGw: playerWeeksByWeek[gw.number - 1] ?? null,
            players,
            dreamTeamRaw,
            priceChangesRaw: await latestPriceChanges(db, root, gw.number),
          }),
          apiKey: news.apiKey,
          fetchImpl: news.fetchImpl,
          timeoutMs: news.timeoutMs,
        });
        if (drafts === null) {
          log.info('fantasy news: AI drafting skipped — API failure or ' +
            'unusable reply', ctx);
        } else {
          for (let i = 0; i < drafts.length; i++) {
            // Only market players become cards (unknown names drop out).
            const tagged = cardsNode(cardsFor(drafts[i].players));
            await db.write(`${root}/News/Drafts/gw${gw.number}ai${i + 1}`, {
              Title: drafts[i].title,
              Body: drafts[i].body,
              Gw: gw.number,
              CreatedAt: nowMs,
              Source: 'ai',
              Template: 'ai',
              ...(tagged !== null ? { Players: tagged } : {}),
              ...schedule,
            });
            drafted++;
          }
          log.info('fantasy news: AI drafts queued',
            { ...ctx, drafts: drafts.length });
        }
      } else {
        log.info('fantasy news: no Anthropic key — AI drafting skipped', ctx);
      }

      // Admin heads-up (spec §4.4): once per gameweek — inside this claim —
      // and only when something was drafted. The Manager has no FCM token,
      // so it lands in each admin's fan app.
      if (drafted > 0 && pusher) {
        const admins = adminUidsOf(await db.read('Admins'));
        if (admins.length > 0) {
          const body = newsReadyBody(drafted,
            publishAt !== null ? formatLeagueWeekdayTime(publishAt) : null);
          const data = fantasyPushData(sport, season, gw.number);
          const sent = await pusher.sendToUsers(admins.map((uid) => ({
            uid, title: NEWS_READY_TITLE, body, data,
          })));
          log.info('fantasy news: admin heads-up pushed',
            { ...ctx, admins: admins.length, sent, drafted });
        }
      }
    }
  }

  const managers = Object.keys(out.historyByUid).length;
  log.info('fantasy gameweek finalized', {
    ...ctx, source, managers, games: gameNodes.length,
    skipped: out.skippedSquadUids.length, voided,
  });
  return { managers, source };
}

/** First-run guard: without a lock snapshot or existing History, only the
 *  LATEST lock-passed gameweek may finalize from live Squads — enabling
 *  fantasy mid-season must never fabricate history for earlier weeks. */
async function mayFinalizeFirstRun(
  db: FantasyDb, root: string, gws: Gameweek[], gw: Gameweek, nowUtc: Date,
): Promise<boolean> {
  if (await db.read(`${root}/History/${gw.number}`) != null) return true;
  if (await db.read(`${root}/PublishedPicks/${gw.number}`) != null) return true;
  const lockPassed = gws
    .filter((g) => g.lockUtc.getTime() <= nowUtc.getTime());
  return lockPassed.length > 0 &&
    lockPassed[lockPassed.length - 1].number === gw.number;
}

export interface MaybeFinalizeArgs {
  sport: string;
  season: string;
  dateKey: string;
  nowUtc: Date;
  log?: FantasyLogger;
  deps?: FantasyJobDeps;
}

/** The trigger entry: a game under <sport>/<season>/Date/<dateKey> was
 *  written while Final. Finalizes (or re-finalizes) that date's gameweek
 *  when the season is fantasy-enabled and auto, the gameweek's lock has
 *  passed (History is public — finalizing a pre-lock final would leak
 *  picks), every non-friendly game of the date is Final, and the first-run
 *  guard allows it. Reruns on later edits recompute everything downstream —
 *  idempotence IS the debounce. */
export async function maybeFinalizeGame(
  db: FantasyDb, args: MaybeFinalizeArgs,
): Promise<void> {
  const { sport, season, dateKey, nowUtc } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  const ctx = { sport, season, dateKey };
  if (lockOverrideOf(configNode, nowUtc.getTime()) !== 'auto') {
    log.info('fantasy finalize: lockOverride frozen — standing down', ctx);
    return;
  }
  const cfg = configFromMap(configNode);

  const dates = dateKeysOf(await db.read(`${sport}/${season}/Date`));
  const gws = deriveGameweeks(dates, cfg);
  const gw = gws.find((g) => g.date === dateKey);
  if (!gw) return;
  if (gw.lockUtc.getTime() > nowUtc.getTime()) {
    log.info('fantasy finalize: date final before lock — waiting for lock',
      { ...ctx, gw: gw.number });
    return;
  }
  const games = gamesOfDate(await db.read(`${sport}/${season}/Date/${dateKey}`));
  if (!allGamesFinal(games)) return; // another game still running
  if (!(await mayFinalizeFirstRun(db, root, gws, gw, nowUtc))) {
    log.warn('fantasy finalize: old gameweek without a lock snapshot — ' +
      'skipped (no fabricated history)', { ...ctx, gw: gw.number });
    return;
  }
  await finalizeGameweek(db, {
    sport, season, cfg, gw, nowUtc: args.nowUtc, log, deps: args.deps,
  });
}

export interface VoidToggleArgs {
  sport: string;
  season: string;
  /** The gameweek number whose Voided/<gw> flag flipped. */
  gw: number;
  nowUtc: Date;
  log?: FantasyLogger;
  deps?: FantasyJobDeps;
}

/** The Voided/<gw> trigger entry (spec §15 owner void): the flag flipped
 *  (voided <-> counts), so re-settle that gameweek through the SAME
 *  match-day finalize entry — every gate applies unchanged (frozen
 *  lockOverride stands down, pre-lock waits, an incomplete match day waits,
 *  the first-run guard holds). finalize re-reads the flag itself, so voiding
 *  and un-voiding are both just a deterministic rerun. A flip on a week that
 *  has not settled yet changes nothing now: its eventual finalize reads the
 *  flag. Rollover/Free Hit restore stay RolledGw-guarded (never re-run). */
export async function resettleVoidToggle(
  db: FantasyDb, args: VoidToggleArgs,
): Promise<void> {
  const { sport, season } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, gw: args.gw };

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  if (lockOverrideOf(configNode, args.nowUtc.getTime()) !== 'auto') {
    log.info('fantasy void: lockOverride frozen — standing down', ctx);
    return;
  }
  // The finalize entry is keyed by match date; map the gameweek onto it.
  const dates = dateKeysOf(await db.read(`${sport}/${season}/Date`));
  const gw = deriveGameweeks(dates, configFromMap(configNode))
    .find((g) => g.number === args.gw);
  if (!gw) {
    log.warn('fantasy void: gameweek not in the schedule — nothing to settle',
      ctx);
    return;
  }
  const voided = isVoidFlag(await db.read(`${root}/Voided/${args.gw}`));
  log.info('fantasy void: flag flipped — re-settling',
    { ...ctx, date: gw.date, voided });
  await maybeFinalizeGame(db, {
    sport, season, dateKey: gw.date, nowUtc: args.nowUtc, log, deps: args.deps,
  });
}

// ── Positions locked per gameweek (spec §3 revision 2026-10-28) ────────────

/** Claims LockedPositions/<gw> from the live market positions, exactly once
 *  (set-if-absent, like PublishedPicks). Returns the snapshot now stored
 *  (ours or a concurrent winner's), null when the market is empty. */
async function snapshotLockedPositions(
  db: FantasyDb, root: string, gw: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<unknown> {
  const path = `${root}/LockedPositions/${gw}`;
  const existing = await db.read(path);
  if (existing != null) return existing;
  const snap = positionsSnapshotOf(marketPlayersOf(await db.read(`${root}/Players`)));
  if (Object.keys(snap).length === 0) return null;
  if (await db.writeIfAbsent(path, snap)) {
    log.info('fantasy lock: positions locked',
      { ...ctx, gw, players: Object.keys(snap).length });
    return snap;
  }
  return await db.read(path);
}

/** The market as gameweek [gw] is scored: live membership/eligibility with
 *  positions from LockedPositions/<gw>. [claim] (a first finalize) takes
 *  the snapshot when the lock sweep never did; otherwise a week without a
 *  snapshot (locked before this existed) falls back to live positions. */
async function marketForGameweek(
  db: FantasyDb, root: string, gw: number, claim: boolean,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<Record<string, MarketPlayer>> {
  const players = marketPlayersOf(await db.read(`${root}/Players`));
  const locked = claim
    ? await snapshotLockedPositions(db, root, gw, log, ctx)
    : await db.read(`${root}/LockedPositions/${gw}`);
  return withLockedPositions(players, lockedPositionsOf(locked));
}

// ── Phase B: lifecycle sweep ───────────────────────────────────────────────

/** Snapshot every saved squad into PublishedPicks/<gw>, exactly once (spec
 *  §9). The existence check keeps rereads cheap; the set-if-absent claim is
 *  what actually guarantees once-only under concurrent sweeps. Phase E's
 *  lock accounting rides the same claim: a chip replayed within its set is
 *  VOIDED (stripped from the snapshot itself, so finalize and the public
 *  reveal agree), the effective chip is frozen into
 *  TransferState.ChipPlayed, and the week's transfer cost points are
 *  persisted to TransferCosts/<gw> for finalize. */
async function snapshotPublishedPicks(
  db: FantasyDb, root: string, cfg: FantasyConfig, gw: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  if (await db.read(`${root}/PublishedPicks/${gw}`) != null) return;
  const squads = mapChildren(await db.read(`${root}/Squads`));
  if (Object.keys(squads).length === 0) {
    log.info('fantasy lock: no squads to snapshot', { ...ctx, gw });
    return;
  }
  const acc = lockAccounting({
    squadsByUid: squads,
    statesByUid: mapChildren(await db.read(`${root}/TransferState`)),
    historyRaw: await db.read(`${root}/History`),
    cfg,
    gw,
    // Chips from owner-voided weeks are refunded (spec §15).
    voidedWeeks: voidedWeeksOf(await db.read(`${root}/Voided`)),
  });
  const won = await db.writeIfAbsent(`${root}/PublishedPicks/${gw}`, acc.cleanSquads);
  if (!won) return; // a concurrent sweep won the claim and did the rest
  for (const v of acc.voided) {
    log.warn('fantasy lock: chip voided — already used in this set',
      { ...ctx, gw, ...v });
  }
  if (Object.keys(acc.costPointsByUid).length > 0) {
    await db.write(`${root}/TransferCosts/${gw}`, acc.costPointsByUid);
  }
  await freezeChipPlayed(db, root, cfg, acc.chipPlayedByUid);
  log.info('fantasy lock: picks published', {
    ...ctx, gw, managers: Object.keys(acc.cleanSquads).length,
  });
}

async function sweepSeason(
  db: FantasyDb,
  ref: { sport: string; season: string; configNode: Record<string, unknown> },
  nowUtc: Date, log: FantasyLogger, deps?: FantasyJobDeps,
): Promise<void> {
  const { sport, season } = ref;
  const ctx = { sport, season };
  const root = fantasyRoot(sport, season);
  const nowMs = nowUtc.getTime();

  // 0. Lock-override auto-return (spec §2): an open/locked override whose
  //    Config.lockOverrideUntil has passed is reverted in the DB (back to
  //    'auto', until removed) and the season then runs normally in THIS
  //    sweep, on a config copy that reads 'auto'.
  let configNode = ref.configNode;
  if (lockOverrideOf(configNode) !== 'auto' &&
    lockOverrideOf(configNode, nowMs) === 'auto') {
    await db.write(`${root}/Config/lockOverride`, 'auto');
    await db.write(`${root}/Config/lockOverrideUntil`, null);
    log.info('fantasy sweep: lock override expired — back to auto', ctx);
    configNode = { ...configNode, lockOverride: 'auto' };
    delete configNode['lockOverrideUntil'];
  }
  if (lockOverrideOf(configNode, nowMs) !== 'auto') {
    log.info('fantasy sweep: lockOverride frozen — standing down', ctx);
    return;
  }
  const cfg = configFromMap(configNode);

  const dates = dateKeysOf(await db.read(`${sport}/${season}/Date`));
  const gws = deriveGameweeks(dates, cfg);
  const current = currentGameweek(gws, nowUtc);

  // 1. Lock snapshots for the current gameweek (positions, then picks),
  //    before any finalize can need them. Existence-guarded rather than
  //    transition-edge-triggered, so a sweep that was down at the lock
  //    instant still snapshots exactly once.
  if (current && gameweekStatusAt(current, nowUtc) === 'locked') {
    await snapshotLockedPositions(db, root, current.number, log, ctx);
    await snapshotPublishedPicks(db, root, cfg, current.number, log, ctx);
  }

  // 2. Finalize backstop: any lock-passed gameweek whose match day is
  //    complete but lacks History (first-run guard applies).
  for (const gw of gws) {
    if (gw.lockUtc.getTime() > nowUtc.getTime()) break;
    if (await db.read(`${root}/History/${gw.number}`) != null) continue;
    if (!(await mayFinalizeFirstRun(db, root, gws, gw, nowUtc))) continue;
    const games = gamesOfDate(await db.read(`${sport}/${season}/Date/${gw.date}`));
    if (!allGamesFinal(games)) continue;
    log.info('fantasy sweep: backstop finalize', { ...ctx, gw: gw.number });
    await finalizeGameweek(db, { sport, season, cfg, gw, nowUtc, log, deps });
  }

  // 2b. News draft auto-publish (spec 2026-10-28 §4.4): ANY draft — autopilot
  //     'dreamteam'/'ai' or an owner-scheduled 'owner' post — whose
  //     AutoPublishAt is due publishes itself to News/Published (the §4.1
  //     post fields, news.ts publishedRowFromDraft) and leaves the queue. A
  //     draft without AutoPublishAt waits for the owner (autopilot off or
  //     the Manager's Auto-publish switch off); a discard deleted it. Before
  //     the season-over return, so the last gameweek's posts still ship. A
  //     draft for an owner-VOIDED week is held (never deleted — it is the
  //     owner's queue): its week no longer counts; an un-void releases it.
  const voidedNow = voidedWeeksOf(await db.read(`${root}/Voided`));
  for (const [key, draft] of childEntries(await db.read(`${root}/News/Drafts`))) {
    if (!shouldAutoPublish(draft, nowUtc.getTime())) continue;
    const d = draft as Record<string, unknown>;
    if (voidedNow.includes(toIntLoose(d['Gw']))) continue;
    await db.write(`${root}/News/Published/${key}`,
      publishedRowFromDraft(d, nowUtc.getTime()));
    await db.write(`${root}/News/Drafts/${key}`, null);
    log.info('fantasy news: draft auto-published',
      { ...ctx, key, source: String(d['Source'] ?? '') });
  }

  // 3. GwState upsert, after the backstop so a finalize lands as 'finalized'
  //    in the same sweep.
  if (!current) {
    log.info('fantasy sweep: season over — GwState left as-is', ctx);
    return;
  }
  const engine = gameweekStatusAt(current, nowUtc);
  let status: GwStateNode['status'];
  if (engine === 'locked') {
    const history = await db.read(`${root}/History/${current.number}`);
    status = history != null ? 'finalized' : 'locked';
  } else {
    status = 'open'; // 'upcoming' is unreachable for the current gw; see header
  }
  const desired: GwStateNode = {
    current: current.number,
    status,
    lockAtUtc: current.lockUtc.getTime(),
    date: current.date,
  };
  const existing = await db.read(`${root}/GwState`);
  if (!gwStateEquals(existing, desired)) {
    await db.write(`${root}/GwState`, desired);
    log.info('fantasy sweep: GwState updated', { ...ctx, ...desired });
  }

  // 3b. Position changes deferred while the window was locked (spec §3
  //     holder protection) apply the moment it reopens: relabel holders,
  //     alert + push the ones left with an illegal formation (free swap
  //     this gameweek). position_changes.ts owns the nodes.
  if (status === 'open') {
    const applied = await applyPendingPositionChanges(db, {
      sport, season, cfg,
      target: { gw: current.number, date: current.date },
      nowUtc, log, pusher: deps?.pusher,
    });
    if (applied > 0) {
      log.info('fantasy sweep: deferred position changes applied',
        { ...ctx, gw: current.number, applied });
    }
  }

  // 4. Deadline reminder (Phase F): fires once per gameweek when a sweep
  //    first crosses the reminder instant while the week is still open.
  //    Audience = signed-up managers with UNCHANGED squads (spec §12; the
  //    measurable rule is pushes.ts reminderAudience). The ReminderSent
  //    claim lands BEFORE the send so concurrent sweeps can never
  //    double-push; a sweep without a pusher claims nothing.
  const pusher = deps?.pusher;
  if (pusher && status === 'open') {
    const rCfg = reminderConfigFrom(configNode['Reminder']);
    if (rCfg.enabled &&
      nowUtc.getTime() >= reminderInstantMs(current.lockUtc.getTime(), rCfg) &&
      (await db.read(`${root}/ReminderSent/${current.number}`)) == null) {
      const won = await db.writeIfAbsent(
        `${root}/ReminderSent/${current.number}`, { At: nowUtc.getTime() });
      if (won) {
        const audience = reminderAudience({
          managersRaw: await db.read(`${root}/Managers`),
          squadsRaw: await db.read(`${root}/Squads`),
          transferStateRaw: await db.read(`${root}/TransferState`),
          gw: current.number,
        });
        const body = fillReminderTemplate(
          rCfg.template, formatDeadline(current.date, cfg.lockHour));
        const data = fantasyPushData(sport, season, current.number);
        const sent = await pusher.sendToUsers(audience.map((uid) => ({
          uid, title: REMINDER_TITLE, body, data,
        })));
        log.info('fantasy reminder pushed',
          { ...ctx, gw: current.number, audience: audience.length, sent });
      }
    }
  }
}

/** The 15-minute scheduled sweep over every fantasy-enabled season. One
 *  season's failure never starves the others. */
export async function runLifecycleSweep(
  db: FantasyDb, nowUtc: Date, log: FantasyLogger = silent,
  deps?: FantasyJobDeps,
): Promise<void> {
  const seasons = fantasySeasonsOf(await db.read('Fantasy'));
  for (const ref of seasons) {
    try {
      await sweepSeason(db, ref, nowUtc, log, deps);
    } catch (err) {
      log.warn('fantasy sweep: season failed', {
        sport: ref.sport, season: ref.season, error: String(err),
      });
    }
  }
}

// ── Phase F: send-now callable core ────────────────────────────────────────

export interface ReminderNowArgs {
  sport: string;
  season: string;
  /** 'unchanged' (default) = the scheduled reminder's audience;
   *  'all' = every signed-up manager. */
  audience?: 'all' | 'unchanged';
  nowUtc: Date;
  log?: FantasyLogger;
}

/** The sendFantasyReminderNow callable's core: an admin's manual push to
 *  the reminder audience. A deliberate action, so it ignores
 *  Reminder.Enabled, the frozen-machine lockOverride and the ReminderSent
 *  guard, and it marks nothing — the scheduled reminder still fires on its
 *  own clock. Throws when the season is not fantasy-enabled or has no
 *  current gameweek (the callable maps that to failed-precondition). */
export async function sendReminderNow(
  db: FantasyDb, pusher: FantasyPusher, args: ReminderNowArgs,
): Promise<{ gw: number; audience: number; sent: number }> {
  const { sport, season } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) {
    throw new Error(`No fantasy Config for ${sport}/${season}`);
  }
  const cfg = configFromMap(configNode);
  const dates = dateKeysOf(await db.read(`${sport}/${season}/Date`));
  const current = currentGameweek(deriveGameweeks(dates, cfg), args.nowUtc);
  if (!current) {
    throw new Error(`No current gameweek for ${sport}/${season}`);
  }

  const uids = reminderAudience({
    managersRaw: await db.read(`${root}/Managers`),
    squadsRaw: await db.read(`${root}/Squads`),
    // null state disables the unchanged filter = everyone (see pushes.ts).
    transferStateRaw: args.audience === 'all'
      ? null
      : await db.read(`${root}/TransferState`),
    gw: current.number,
  });
  const rCfg = reminderConfigFrom(configNode['Reminder']);
  const body = fillReminderTemplate(
    rCfg.template, formatDeadline(current.date, cfg.lockHour));
  const data = fantasyPushData(sport, season, current.number);
  const sent = await pusher.sendToUsers(uids.map((uid) => ({
    uid, title: REMINDER_TITLE, body, data,
  })));
  log.info('fantasy reminder sent now', {
    sport, season, gw: current.number,
    audience: uids.length, sent, mode: args.audience ?? 'unchanged',
  });
  return { gw: current.number, audience: uids.length, sent };
}

// ── Phase D: Monday repricing ──────────────────────────────────────────────

/** Monday 10:00 league time: reprice the most recent FINALIZED gameweek not
 *  yet repriced. Per position, repriceDeltas over ALL eligible market
 *  players (a player with no PlayerWeeks entry scored 0 that week — absent
 *  and no-game players included at their real score), applyDelta onto
 *  Players/<name>/priceTenths, PriceChanges/<gw> rows for the client's
 *  risers & fallers strip, then the Repriced/<gw> done-flag. An admin
 *  PriceChanges/<gw>/Manual == true makes the job stand down for that week
 *  (flagged done with Manual:true so it never re-evaluates); an
 *  owner-voided week (Voided/<gw> == true) is skipped the same way
 *  (flagged Voided:true). */
export async function runMondayReprice(
  db: FantasyDb, nowUtc: Date, log: FantasyLogger = silent,
): Promise<void> {
  const seasons = fantasySeasonsOf(await db.read('Fantasy'));
  for (const ref of seasons) {
    const { sport, season } = ref;
    const ctx = { sport, season };
    try {
      if (lockOverrideOf(ref.configNode, nowUtc.getTime()) !== 'auto') {
        log.info('fantasy reprice: lockOverride frozen — standing down', ctx);
        continue;
      }
      const cfg = configFromMap(ref.configNode);
      const root = fantasyRoot(sport, season);

      const weeks = childEntries(await db.read(`${root}/History`))
        .map(([k]) => Number(k))
        .filter((w) => Number.isInteger(w));
      if (weeks.length === 0) continue; // nothing finalized yet
      const gw = Math.max(...weeks);

      if (await db.read(`${root}/Repriced/${gw}`) != null) continue; // done
      if (isVoidFlag(await db.read(`${root}/Voided/${gw}`))) {
        // An owner-voided week moves no prices (spec §15); flagged done so
        // it never re-evaluates.
        await db.write(`${root}/Repriced/${gw}`,
          { At: nowUtc.getTime(), Voided: true });
        log.info('fantasy reprice: voided week — skipped', { ...ctx, gw });
        continue;
      }
      if (await db.read(`${root}/PriceChanges/${gw}/Manual`) === true) {
        await db.write(`${root}/Repriced/${gw}`,
          { At: nowUtc.getTime(), Manual: true });
        log.info('fantasy reprice: admin Manual flag — standing down',
          { ...ctx, gw });
        continue;
      }

      const playersNode = await db.read(`${root}/Players`);
      // Peers are grouped at the week's LOCKED positions — the positions
      // its PlayerWeeks were scored at (a change made after the lock moves
      // the player's peer group from the next repriced week on).
      const players = withLockedPositions(marketPlayersOf(playersNode),
        lockedPositionsOf(await db.read(`${root}/LockedPositions/${gw}`)));
      const prices = marketPricesOf(playersNode);

      const weekPointsRaw = await db.read(`${root}/PlayerWeeks/${gw}`);
      if (weekPointsRaw == null) {
        log.warn('fantasy reprice: PlayerWeeks missing — repricing from ' +
          'zeros', { ...ctx, gw });
      }
      const weekPoints: Record<string, number> = {};
      for (const [name, v] of childEntries(weekPointsRaw)) {
        weekPoints[name] = toIntLoose(v);
      }

      const changes: Record<string, { delta: number }> = {};
      for (const pos of FANTASY_POSITIONS) {
        const group: Record<string, number> = {};
        for (const [name, p] of Object.entries(players)) {
          if (p.eligible && p.position === pos) {
            group[name] = weekPoints[name] ?? 0;
          }
        }
        const deltas = repriceDeltas(group, cfg);
        for (const [name, delta] of Object.entries(deltas)) {
          if (delta === 0) continue;
          const oldPrice = prices[name] ?? 0;
          const newPrice = applyDelta(oldPrice, delta, cfg);
          const effective = newPrice - oldPrice;
          if (effective === 0) continue; // clamped at floor/ceiling
          await db.write(`${root}/Players/${name}/priceTenths`, newPrice);
          changes[name] = { delta: effective };
        }
      }
      if (Object.keys(changes).length > 0) {
        await db.write(`${root}/PriceChanges/${gw}`, changes);
      }
      await db.write(`${root}/Repriced/${gw}`, { At: nowUtc.getTime() });
      log.info('fantasy gameweek repriced', {
        ...ctx, gw, moves: Object.keys(changes).length,
      });
    } catch (err) {
      log.warn('fantasy reprice: season failed', { ...ctx, error: String(err) });
    }
  }
}
