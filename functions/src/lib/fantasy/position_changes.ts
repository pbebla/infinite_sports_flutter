// Holder protection on a fantasy position change (spec §3, owner revision
// 2026-10-28): "When a change applies, every squad holding the player is
// re-labelled; if its formation becomes illegal the owner gets an alert in
// the hub + a push, and swapping that player out that week costs no
// transfer." Database-injected through the FantasyDb seam like
// orchestration.ts; the thin RTDB trigger lives in src/fantasy_positions.ts.
//
// WHEN A CHANGE APPLIES (the Players/<name>/position trigger):
// - Editing window OPEN (GwState.status 'open' and its lock instant still
//   ahead), or no GwState yet (pre-season, before the first sweep): now.
// - Otherwise (locked / finalized / season over): DEFERRED to the next
//   reopen — the locked week keeps scoring the position it locked with
//   (LockedPositions/<gw>), and its squads must not change under it.
//
// NODES THIS FILE OWNS (all under Fantasy/<sport>/<season>):
//
// - SquadAlerts/<uid> = { Gw:int, Changes:[{player, from, to}],
//   CreatedAt:int } — "your formation is illegal because of these
//   position changes; rearrange before gameweek Gw's deadline". Written
//   only when the relabelled squad fails the engine's formation check;
//   merged per player while the alert stays on the same Gw. Cleared by
//   recordSquadSave on the next squad save whose formation is valid (and
//   here, when a later change makes the formation valid again). Rules:
//   read own uid + admin, no client write.
//
// - PendingPositionChanges/<name> = { from, to } — a change made while the
//   window was locked. `from` stays the label holders still carry (a
//   second change while locked keeps the first `from`; a change back to it
//   removes the entry). The sweep applies every entry the moment it sees
//   the window reopen — relabel, alert, push, exactly like a live change,
//   with `to` re-read from the live market (the source of truth). Rules:
//   admin read only.
//
// - TransferState/<uid>.FreeSwaps / FreeSwapsGw — the alerted players,
//   free to sell in gameweek Gw (transfer_state.ts usedAfterFreeSwaps).
//
// Relabel writes are child writes (Squads/<uid>/picks/<k>/position) so a
// concurrent client edit of any other field is never clobbered; they fire
// the Squads/<uid> trigger like any save (recordSquadSave recounts — the
// player ids did not change, so nothing is charged). They are stamped as
// SERVER writes first (orchestration_db.ts SERVER_WRITE_KEY), so that
// re-run never stamps SavedGw: a re-label is not the manager acting and
// must not silence their deadline reminder.

import {
  configFromMap, FantasyConfig, FantasyPosition, parsePosition,
} from './fantasy_config';
import { currentGameweek, deriveGameweeks } from './gameweeks';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, dateKeysOf, FantasyDb, fantasyRoot, isPlainMap,
  lockOverrideOf, markServerSquadWrite, toIntLoose,
} from './orchestration_db';
import {
  FantasyPusher, FantasyUserPush, fantasyPushData, formatDeadline,
} from './pushes';
import { squadFromMap, validateSquad } from './squad';
import { parseTransferState, transferStateToNode } from './transfer_state';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

export interface PositionChange {
  player: string;
  from: FantasyPosition;
  to: FantasyPosition;
}

export interface SquadAlert {
  gw: number;
  changes: PositionChange[];
  createdAt: number;
}

/** Tolerant position parse: anything but GK/DEF/ATT is null. */
export function positionOrNull(v: unknown): FantasyPosition | null {
  try {
    return parsePosition(String(v ?? ''));
  } catch {
    return null;
  }
}

/** Whether a position change applies NOW ('open') or waits for the next
 *  reopen ('locked'). No GwState = pre-season / before the first sweep =
 *  open. An 'open' GwState whose lock instant has passed (the sweep simply
 *  hasn't flipped it yet) is already locked. */
export function positionWindowOf(gwState: unknown, nowMs: number): 'open' | 'locked' {
  if (!isPlainMap(gwState)) return 'open';
  if (String(gwState['status'] ?? '') !== 'open') return 'locked';
  const lockAt = toIntLoose(gwState['lockAtUtc']);
  return lockAt > 0 && nowMs >= lockAt ? 'locked' : 'open';
}

export function parseSquadAlert(raw: unknown): SquadAlert | null {
  if (!isPlainMap(raw)) return null;
  const changes: PositionChange[] = [];
  for (const [, c] of childEntries(raw['Changes'])) {
    if (!isPlainMap(c)) continue;
    const from = positionOrNull(c['from']);
    const to = positionOrNull(c['to']);
    const player = c['player'];
    if (typeof player !== 'string' || player.length === 0 || !from || !to) continue;
    changes.push({ player, from, to });
  }
  return { gw: toIntLoose(raw['Gw']), changes, createdAt: toIntLoose(raw['CreatedAt']) };
}

export function squadAlertToNode(a: SquadAlert): Record<string, unknown> {
  return {
    Gw: a.gw,
    Changes: a.changes.map((c) => ({ player: c.player, from: c.from, to: c.to })),
    CreatedAt: a.createdAt,
  };
}

export const SQUAD_ALERT_TITLE = 'Fantasy squad alert';

/** "<Name> moved to DEF — rearrange your team before <deadline>" (spec §3);
 *  several changes join as "A moved to DEF and B moved to ATT". */
export function squadAlertBody(changes: PositionChange[], deadline: string): string {
  const parts = changes.map((c) => `${c.player} moved to ${c.to}`);
  const head = parts.length <= 1
    ? parts.join('')
    : `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;
  return `${head} — rearrange your team before ${deadline}`;
}

/** The gameweek an alert is for: the current gameweek per GwState, else
 *  (no GwState yet) the schedule's current/first gameweek. */
export interface AlertTarget {
  gw: number;
  /** Match date (MMDDYYYY) for the deadline text; null = unknown. */
  date: string | null;
}

async function alertTargetOf(
  db: FantasyDb, sport: string, season: string, cfg: FantasyConfig,
  gwState: unknown, nowUtc: Date,
): Promise<AlertTarget> {
  if (isPlainMap(gwState) && toIntLoose(gwState['current']) > 0) {
    const date = String(gwState['date'] ?? '');
    return { gw: toIntLoose(gwState['current']), date: date.length === 8 ? date : null };
  }
  const gws = deriveGameweeks(
    dateKeysOf(await db.read(`${sport}/${season}/Date`)), cfg);
  const g = currentGameweek(gws, nowUtc) ?? gws[0];
  return g ? { gw: g.number, date: g.date } : { gw: 1, date: null };
}

export interface ApplyPositionChangesArgs {
  sport: string;
  season: string;
  cfg: FantasyConfig;
  changes: PositionChange[];
  target: AlertTarget;
  nowUtc: Date;
  log?: FantasyLogger;
  pusher?: FantasyPusher;
}

/** Applies position changes to every holder NOW: re-label their picks,
 *  re-check the formation (engine validateSquad on a fresh read), then
 *  alert + free-swap + push when it is illegal, or clear a standing alert
 *  when it is legal again. Pushes go out in one batch, one per manager. */
export async function applyPositionChanges(
  db: FantasyDb, args: ApplyPositionChangesArgs,
): Promise<{ relabelled: string[]; alerted: string[] }> {
  const { sport, season, cfg, target } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, gw: target.gw };
  const byPlayer = new Map(args.changes.map((c) => [c.player, c]));
  const relabelled: string[] = [];
  const alerted: string[] = [];
  const messages: FantasyUserPush[] = [];
  const deadline = target.date !== null
    ? formatDeadline(target.date, cfg.lockHour) : 'the deadline';

  for (const [uid, raw] of childEntries(await db.read(`${root}/Squads`))) {
    if (!isPlainMap(raw)) continue;
    // This manager's view of each change: `from` is the label the pick
    // actually carried (falls back to the change's own when already moved).
    const mine: PositionChange[] = [];
    let marked = false;
    for (const [k, pick] of childEntries(raw['picks'])) {
      if (!isPlainMap(pick)) continue;
      const change = byPlayer.get(String(pick['playerId'] ?? ''));
      if (!change) continue;
      const label = positionOrNull(pick['position']);
      mine.push({
        player: change.player,
        from: label !== null && label !== change.to ? label : change.from,
        to: change.to,
      });
      if (pick['position'] !== change.to) {
        // A server write, not a manager save: the marker lands first so
        // the Squads trigger never stamps SavedGw (orchestration_db.ts
        // SERVER_WRITE_KEY) — a re-label must not silence the reminder.
        if (!marked) {
          await markServerSquadWrite(db, root, uid, args.nowUtc.getTime());
          marked = true;
        }
        await db.write(`${root}/Squads/${uid}/picks/${k}/position`, change.to);
      }
    }
    if (mine.length === 0) continue; // not a holder
    relabelled.push(uid);

    const fresh = await db.read(`${root}/Squads/${uid}`);
    let formationOk: boolean;
    try {
      formationOk = isPlainMap(fresh) &&
        !validateSquad(squadFromMap(fresh), cfg).includes('formation');
    } catch {
      log.warn('fantasy positions: malformed squad — relabelled, not checked',
        { ...ctx, uid });
      continue;
    }

    const alertPath = `${root}/SquadAlerts/${uid}`;
    const existing = parseSquadAlert(await db.read(alertPath));
    if (formationOk) {
      if (existing !== null) {
        await db.write(alertPath, null);
        log.info('fantasy positions: formation legal again — alert cleared',
          { ...ctx, uid });
      }
      continue;
    }

    // Illegal: alert (merged per player on the same Gw), free swaps, push.
    const kept = existing !== null && existing.gw === target.gw
      ? existing.changes.filter((c) => !byPlayer.has(c.player)) : [];
    const merged = [
      ...kept,
      ...mine.map((c) => {
        const prior = existing?.gw === target.gw
          ? existing.changes.find((e) => e.player === c.player) : undefined;
        return prior ? { ...c, from: prior.from } : c; // keep the original label
      }),
    ].filter((c) => c.from !== c.to); // a change straight back is no change
    await db.write(alertPath, squadAlertToNode({
      gw: target.gw, changes: merged, createdAt: args.nowUtc.getTime(),
    }));

    const state = parseTransferState(
      await db.read(`${root}/TransferState/${uid}`), cfg);
    const swaps = new Set(state.freeSwaps?.gw === target.gw
      ? state.freeSwaps.players : []);
    for (const c of mine) swaps.add(c.player);
    await db.write(`${root}/TransferState/${uid}`, transferStateToNode({
      ...state, freeSwaps: { gw: target.gw, players: [...swaps].sort() },
    }));

    alerted.push(uid);
    messages.push({
      uid,
      title: SQUAD_ALERT_TITLE,
      body: squadAlertBody(mine, deadline),
      data: fantasyPushData(sport, season, target.gw),
    });
  }

  let sent = 0;
  if (args.pusher && messages.length > 0) {
    sent = await args.pusher.sendToUsers(messages);
  }
  log.info('fantasy positions: change applied to holders', {
    ...ctx, players: args.changes.map((c) => `${c.player} ${c.from}->${c.to}`),
    holders: relabelled.length, alerted: alerted.length, pushed: sent,
  });
  return { relabelled, alerted };
}

export interface PositionWriteArgs {
  sport: string;
  season: string;
  /** The Players/<name> key whose position was written. */
  name: string;
  before: unknown;
  after: unknown;
  nowUtc: Date;
  log?: FantasyLogger;
  pusher?: FantasyPusher;
}

/** The Players/<name>/position trigger entry. Creation, deletion, junk and
 *  no-op writes change nothing; a frozen machine (lockOverride not 'auto')
 *  stands down like every other fantasy job. Open window: applied to the
 *  holders now. Locked: recorded in PendingPositionChanges for the reopen
 *  sweep. Returns what happened, for the caller's log/tests. */
export async function handlePositionWrite(
  db: FantasyDb, args: PositionWriteArgs,
): Promise<'ignored' | 'frozen' | 'applied' | 'deferred'> {
  const { sport, season, name } = args;
  const log = args.log ?? silent;
  const from = positionOrNull(args.before);
  const to = positionOrNull(args.after);
  if (from === null || to === null || from === to) return 'ignored';

  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, player: name, from, to };
  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return 'ignored'; // not fantasy-enabled
  if (lockOverrideOf(configNode) !== 'auto') {
    log.info('fantasy positions: lockOverride frozen — standing down', ctx);
    return 'frozen';
  }
  const cfg = configFromMap(configNode);
  const gwState = await db.read(`${root}/GwState`);
  const pendingPath = `${root}/PendingPositionChanges/${name}`;

  if (positionWindowOf(gwState, args.nowUtc.getTime()) === 'locked') {
    const pending = await db.read(pendingPath);
    const heldLabel = positionOrNull(isPlainMap(pending) ? pending['from'] : null) ?? from;
    if (heldLabel === to) {
      await db.write(pendingPath, null);
      log.info('fantasy positions: changed back while locked — nothing pending', ctx);
    } else {
      await db.write(pendingPath, { from: heldLabel, to });
      log.info('fantasy positions: window locked — change deferred to the reopen', ctx);
    }
    return 'deferred';
  }

  // A live change supersedes anything still pending for this player.
  if ((await db.read(pendingPath)) != null) await db.write(pendingPath, null);
  await applyPositionChanges(db, {
    sport, season, cfg,
    changes: [{ player: name, from, to }],
    target: await alertTargetOf(db, sport, season, cfg, gwState, args.nowUtc),
    nowUtc: args.nowUtc, log, pusher: args.pusher,
  });
  return 'applied';
}

/** The sweep's reopen step: apply every deferred change (to = the LIVE
 *  market position — a later edit wins; an entry whose player is back on
 *  the held label, or left the market, just clears). */
export async function applyPendingPositionChanges(
  db: FantasyDb, args: {
    sport: string; season: string; cfg: FantasyConfig; target: AlertTarget;
    nowUtc: Date; log?: FantasyLogger; pusher?: FantasyPusher;
  },
): Promise<number> {
  const root = fantasyRoot(args.sport, args.season);
  const pending = childEntries(await db.read(`${root}/PendingPositionChanges`));
  if (pending.length === 0) return 0;
  const playersNode = await db.read(`${root}/Players`);
  const changes: PositionChange[] = [];
  for (const [name, entry] of pending) {
    const from = positionOrNull(isPlainMap(entry) ? entry['from'] : null);
    const live = isPlainMap(playersNode) && isPlainMap(playersNode[name])
      ? positionOrNull(playersNode[name]['position']) : null;
    if (from !== null && live !== null && from !== live) {
      changes.push({ player: name, from, to: live });
    }
  }
  if (changes.length > 0) {
    await applyPositionChanges(db, {
      sport: args.sport, season: args.season, cfg: args.cfg, changes,
      target: args.target, nowUtc: args.nowUtc, log: args.log, pusher: args.pusher,
    });
  }
  for (const [name] of pending) {
    await db.write(`${root}/PendingPositionChanges/${name}`, null);
  }
  return changes.length;
}
