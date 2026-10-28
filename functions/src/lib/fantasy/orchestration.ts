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
// - Repriced/<gw> = { At:int, Manual?:true } — the Monday job's done-flag.
//   Manual:true records "admin had set PriceChanges/<gw>/Manual, the job
//   stood down". PriceChanges/<gw> itself holds only the client contract
//   rows: <name>: { delta:int EFFECTIVE tenths } (post-clamp; zero moves
//   omitted — a ceiling-clamped riser is not a riser).
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
// Finalize manager-source precedence (documented contract): the lock
// snapshot PublishedPicks/<gw> is the law; a rerun without one re-reads the
// squads stored in History/<gw> (deterministic reruns); only a FIRST run of
// the LATEST lock-passed gameweek may fall back to live Squads (so enabling
// fantasy mid-season can never fabricate history for weeks nobody played).
//
// Config.lockOverride: anything but absent/'auto' freezes the machine —
// sweep, finalize and repricing all stand down for that season (the owner's
// sandbox escape hatch; the H rehearsal flips a COPY season to 'auto').

import {
  configFromMap, FANTASY_POSITIONS, FantasyConfig,
} from './fantasy_config';
import {
  computeGameweekFinalize, FinalizeGame,
} from './finalize_core';
import {
  currentGameweek, deriveGameweeks, Gameweek, gameweekStatusAt,
} from './gameweeks';
import {
  allGamesFinal, childEntries, dateKeysOf, FantasyDb, fantasyRoot,
  fantasySeasonsOf, fullAttendance, gamesOfDate, isPlainMap, lockOverrideOf,
  marketPlayersOf, marketPricesOf, parseAbsentMap, rosterNamesOf, toIntLoose,
} from './orchestration_db';
import { applyDelta, repriceDeltas } from './pricing';
import { FantasySquad, squadFromMap, squadToMap } from './squad';
import {
  lockAccounting, parseTransferState, rolloverState, transferStateToNode,
  usedTransfers,
} from './transfer_state';

/** Injected logging seam (firebase-functions/logger in production, a spy or
 *  nothing in tests). */
export interface FantasyLogger {
  info(message: string, context?: Record<string, unknown>): void;
  warn(message: string, context?: Record<string, unknown>): void;
}

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

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

/** Once per gameweek, right after a finalize wrote History/<gw> (RolledGw is
 *  the guard — reruns from score/attendance edits never re-settle): restore
 *  a Free Hit manager's previous locked squad, then roll free transfers for
 *  next week. The restored squad is the engine round-trip of
 *  PublishedPicks/<gw-1> (else History/<gw-1>) with NO chip — a restore
 *  never re-arms a chip. A GW1 Free Hit has nothing to restore (logged). */
async function settleTransfersAfterFinalize(
  db: FantasyDb, root: string, cfg: FantasyConfig, gw: number,
  uids: string[], log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  for (const uid of uids) {
    const state = parseTransferState(
      await db.read(`${root}/TransferState/${uid}`), cfg);
    if (state.rolledGw !== null && state.rolledGw >= gw) continue;
    if (state.chipPlayed === 'freeHit') {
      const prevRaw =
        (await db.read(`${root}/PublishedPicks/${gw - 1}/${uid}`)) ??
        (await db.read(`${root}/History/${gw - 1}/${uid}`));
      let restored: Record<string, unknown> | null = null;
      if (isPlainMap(prevRaw)) {
        try {
          restored = squadToMap({ ...squadFromMap(prevRaw), chip: null });
        } catch { /* unreadable previous squad — warn below */ }
      }
      if (restored !== null) {
        await db.write(`${root}/Squads/${uid}`, restored);
        log.info('fantasy freeHit: previous squad restored', { ...ctx, gw, uid });
      } else {
        log.warn('fantasy freeHit: no previous locked squad to restore',
          { ...ctx, gw, uid });
      }
    }
    await db.write(`${root}/TransferState/${uid}`,
      transferStateToNode(rolloverState(state, cfg, gw)));
  }
}

export interface SquadSaveArgs {
  sport: string;
  season: string;
  uid: string;
  log?: FantasyLogger;
}

/** The Squads/<uid> trigger entry (Phase E): while the current gameweek is
 *  open, recompute the manager's used-transfer count against their previous
 *  locked squad (PublishedPicks/<gw-1>, else History/<gw-1>) and stamp
 *  SavedGw. Counting needs a baseline, so a first-ever squad (GW1, or a
 *  mid-season joiner) records UsedThisGw 0 — the initial build is free —
 *  but still stamps SavedGw so the deadline reminder knows the manager
 *  acted this week. Recomputed (not incremented) on every save: undoing a
 *  transfer before the deadline un-counts it. Saves while locked/frozen and
 *  squad deletions change nothing. */
export async function recordSquadSave(
  db: FantasyDb, args: SquadSaveArgs,
): Promise<void> {
  const { sport, season, uid } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, uid };

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  if (lockOverrideOf(configNode) !== 'auto') return; // frozen machine
  const cfg = configFromMap(configNode);

  const gwState = await db.read(`${root}/GwState`);
  if (!isPlainMap(gwState) || String(gwState['status'] ?? '') !== 'open') return;
  const gw = toIntLoose(gwState['current']);
  if (gw <= 0) return;

  const raw = await db.read(`${root}/Squads/${uid}`);
  if (!isPlainMap(raw)) return; // deletion: nothing to count
  let squad: FantasySquad;
  try {
    squad = squadFromMap(raw);
  } catch {
    log.warn('fantasy transfers: malformed squad save — not counted', ctx);
    return;
  }

  let used = 0;
  const prevRaw = (await db.read(`${root}/PublishedPicks/${gw - 1}/${uid}`)) ??
    (await db.read(`${root}/History/${gw - 1}/${uid}`));
  if (isPlainMap(prevRaw)) {
    try {
      used = usedTransfers(squad, squadFromMap(prevRaw));
    } catch {
      log.warn('fantasy transfers: unreadable previous squad — counted 0',
        { ...ctx, gw });
    }
  }

  const state = parseTransferState(
    await db.read(`${root}/TransferState/${uid}`), cfg);
  await db.write(`${root}/TransferState/${uid}`, transferStateToNode({
    ...state, usedThisGw: used, savedGw: gw,
  }));
  log.info('fantasy transfers: squad save counted', { ...ctx, gw, used });
}

// ── Phase C: finalization ──────────────────────────────────────────────────

export interface FinalizeArgs {
  sport: string;
  season: string;
  cfg: FantasyConfig;
  gw: Gameweek;
  nowUtc: Date;
  log?: FantasyLogger;
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
        log.warn('fantasy finalize: no roster for team — scoring activity ' +
          'players only', { ...ctx, team });
      }
      attendance[team] =
        fullAttendance(roster, parseAbsentMap(node[`team${i + 1}attendance`]));
    });
    return { node, attendance };
  });

  const players = marketPlayersOf(await db.read(`${root}/Players`));

  // Manager squads: PublishedPicks (the lock snapshot) -> History (squad
  // part, for deterministic reruns) -> live Squads (first-run fallback; the
  // callers gate WHICH gameweeks may use it).
  const historyRaw = await db.read(`${root}/History`);
  const historyThisGw = childEntries(historyRaw)
    .find(([w]) => Number(w) === gw.number)?.[1] ?? null;
  const firstRun = historyThisGw == null;
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
  } else {
    log.info('fantasy finalize: DreamTeam admin-edited — preserved', ctx);
  }

  // Phase E epilogue: Free Hit squad restore + free-transfer rollover,
  // once per gameweek (RolledGw-guarded — score-edit reruns skip it).
  if (Object.keys(out.historyByUid).length > 0) {
    await settleTransfersAfterFinalize(
      db, root, cfg, gw.number, Object.keys(out.historyByUid), log, ctx);
  }

  const managers = Object.keys(out.historyByUid).length;
  log.info('fantasy gameweek finalized', {
    ...ctx, source, managers, games: gameNodes.length,
    skipped: out.skippedSquadUids.length,
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
  if (lockOverrideOf(configNode) !== 'auto') {
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
  await finalizeGameweek(db, { sport, season, cfg, gw, nowUtc: args.nowUtc, log });
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
  nowUtc: Date, log: FantasyLogger,
): Promise<void> {
  const { sport, season } = ref;
  const ctx = { sport, season };
  if (lockOverrideOf(ref.configNode) !== 'auto') {
    log.info('fantasy sweep: lockOverride frozen — standing down', ctx);
    return;
  }
  const cfg = configFromMap(ref.configNode);
  const root = fantasyRoot(sport, season);

  const dates = dateKeysOf(await db.read(`${sport}/${season}/Date`));
  const gws = deriveGameweeks(dates, cfg);
  const current = currentGameweek(gws, nowUtc);

  // 1. Lock snapshot for the current gameweek, before any finalize can need
  //    it. Existence-guarded rather than transition-edge-triggered, so a
  //    sweep that was down at the lock instant still publishes exactly once.
  if (current && gameweekStatusAt(current, nowUtc) === 'locked') {
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
    await finalizeGameweek(db, { sport, season, cfg, gw, nowUtc, log });
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
}

/** The 15-minute scheduled sweep over every fantasy-enabled season. One
 *  season's failure never starves the others. */
export async function runLifecycleSweep(
  db: FantasyDb, nowUtc: Date, log: FantasyLogger = silent,
): Promise<void> {
  const seasons = fantasySeasonsOf(await db.read('Fantasy'));
  for (const ref of seasons) {
    try {
      await sweepSeason(db, ref, nowUtc, log);
    } catch (err) {
      log.warn('fantasy sweep: season failed', {
        sport: ref.sport, season: ref.season, error: String(err),
      });
    }
  }
}

// ── Phase D: Monday repricing ──────────────────────────────────────────────

/** Monday 10:00 league time: reprice the most recent FINALIZED gameweek not
 *  yet repriced. Per position, repriceDeltas over ALL eligible market
 *  players (a player with no PlayerWeeks entry scored 0 that week — absent
 *  and no-game players included at their real score), applyDelta onto
 *  Players/<name>/priceTenths, PriceChanges/<gw> rows for the client's
 *  risers & fallers strip, then the Repriced/<gw> done-flag. An admin
 *  PriceChanges/<gw>/Manual == true makes the job stand down for that week
 *  (flagged done with Manual:true so it never re-evaluates). */
export async function runMondayReprice(
  db: FantasyDb, nowUtc: Date, log: FantasyLogger = silent,
): Promise<void> {
  const seasons = fantasySeasonsOf(await db.read('Fantasy'));
  for (const ref of seasons) {
    const { sport, season } = ref;
    const ctx = { sport, season };
    try {
      if (lockOverrideOf(ref.configNode) !== 'auto') {
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
      if (await db.read(`${root}/PriceChanges/${gw}/Manual`) === true) {
        await db.write(`${root}/Repriced/${gw}`,
          { At: nowUtc.getTime(), Manual: true });
        log.info('fantasy reprice: admin Manual flag — standing down',
          { ...ctx, gw });
        continue;
      }

      const playersNode = await db.read(`${root}/Players`);
      const players = marketPlayersOf(playersNode);
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
