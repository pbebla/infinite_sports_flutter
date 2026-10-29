// Message managers (spec 2026-10-28 §3) — the owner's custom fantasy push,
// sent now (the sendFantasyMessage callable, src/fantasy_messages.ts) or
// scheduled (a ScheduledPushes row the 15-minute sweep sends). Both paths
// share ONE core, sendManagerMessage. Pure TS behind the FantasyDb /
// FantasyPusher seams.
//
// AUDIENCES (audiences.ts / pushes.ts — the same rules as every other
// fantasy push):
//   'all'       every fantasy manager (Managers ∪ Squads) — the default
//   'unchanged' managers who have not saved a squad this gameweek
//               (pushes.ts reminderAudience); needs a current gameweek
//   'owners'    managers whose current squad holds [player] (any slot)
//
// TEXT: title + body trimmed and cut to 40 / 140 characters (grapheme
// clusters — the Manager's counters already stop there; this is the
// server's safety net, never a throw). An empty title throws; an empty body
// is a title-only push. Payload: fantasyPushData(sport, season, current
// gameweek or 0) — the fan app opens the fantasy hub.
//
// NODE (under Fantasy/<sport>/<season>; admin read/write per rules, written
// by the Manager):
//
//   ScheduledPushes/<id> = { Title, Body, Audience:'all'|'unchanged'|'owners',
//     Player?:string, SendAt:int (epoch ms), CreatedAt:int,
//     SentAt?:int, Sent?:int, Error?:string }
//
// The sweep (orchestration.ts sweepSeason step 0) sends every row whose
// numeric SendAt is due and that has no SentAt: claim SentAt via
// writeIfAbsent (the only sweep that finds it empty sends — at most once,
// ever), send, record Sent = delivered count. A send that throws (no
// player, no current gameweek for 'unchanged', an FCM outage) logs a
// warning and records Error — the SentAt claim stands, so a bad row is
// never retried forever. The Manager's Cancel removes a pending row. The
// step runs BEFORE the lock-override stand-down: owner messages are not
// engine jobs, so a paused engine still delivers "Match day postponed".

import { allManagers, ownersOf } from './audiences';
import { clampText, COPY_LIMITS } from './copywriter';
import { configFromMap } from './fantasy_config';
import { currentGameweek, deriveGameweeks } from './gameweeks';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, dateKeysOf, FantasyDb, fantasyRoot, isPlainMap,
} from './orchestration_db';
import { FantasyPusher, fantasyPushData, reminderAudience } from './pushes';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

/** Title / body limits — the copywriter's 'message' mode limits. */
export const MESSAGE_TITLE_MAX = COPY_LIMITS.message.title; // 40
export const MESSAGE_BODY_MAX = COPY_LIMITS.message.body; // 140

export type ManagerMessageAudience = 'all' | 'unchanged' | 'owners';

/** A stored or requested audience: absent = 'all' (the card's default);
 *  anything but the three audiences throws. */
export function managerMessageAudienceOf(raw: unknown): ManagerMessageAudience {
  if (raw === undefined || raw === null) return 'all';
  if (raw === 'all' || raw === 'unchanged' || raw === 'owners') return raw;
  throw new Error(`Unknown audience: ${String(raw)}`);
}

export interface ManagerMessageArgs {
  sport: string;
  season: string;
  title: string;
  body: string;
  audience: ManagerMessageAudience;
  /** Required for 'owners' (the player's market name). */
  player?: string;
  nowUtc: Date;
  log?: FantasyLogger;
}

/** The season's current gameweek number at [nowUtc]; hasConfig false when
 *  the season is not fantasy-enabled, gw null between/after gameweeks. */
async function currentGwOf(
  db: FantasyDb, sport: string, season: string, nowUtc: Date,
): Promise<{ hasConfig: boolean; gw: number | null }> {
  const configNode = await db.read(`${fantasyRoot(sport, season)}/Config`);
  if (!isPlainMap(configNode)) return { hasConfig: false, gw: null };
  const dates = dateKeysOf(await db.read(`${sport}/${season}/Date`));
  const current = currentGameweek(
    deriveGameweeks(dates, configFromMap(configNode)), nowUtc);
  return { hasConfig: true, gw: current?.number ?? null };
}

/** Sends one manager message (see the header). Returns the audience size
 *  and the delivered count. Throws — the callable maps it to
 *  failed-precondition, the sweep records it as Error — on an empty title,
 *  an unknown audience, 'owners' without a player, and 'unchanged' on a
 *  season without fantasy Config or without a current gameweek
 *  (sendReminderNow's messages). An empty audience sends nothing. */
export async function sendManagerMessage(
  db: FantasyDb, pusher: FantasyPusher, args: ManagerMessageArgs,
): Promise<{ audience: number; sent: number }> {
  const { sport, season } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);

  const title = clampText(args.title.trim(), MESSAGE_TITLE_MAX);
  if (!title) throw new Error('A message needs a title');
  const body = clampText(args.body.trim(), MESSAGE_BODY_MAX);
  const audience = managerMessageAudienceOf(args.audience);
  const player = (args.player ?? '').trim();
  if (audience === 'owners' && !player) {
    throw new Error('Pick a player for the owners audience');
  }

  const { hasConfig, gw } = await currentGwOf(db, sport, season, args.nowUtc);
  if (audience === 'unchanged') {
    if (!hasConfig) throw new Error(`No fantasy Config for ${sport}/${season}`);
    if (gw === null) throw new Error(`No current gameweek for ${sport}/${season}`);
  }

  const squadsRaw = await db.read(`${root}/Squads`);
  let uids: string[];
  if (audience === 'owners') {
    uids = ownersOf(squadsRaw, [player]);
  } else if (audience === 'unchanged') {
    uids = reminderAudience({
      managersRaw: await db.read(`${root}/Managers`),
      squadsRaw,
      transferStateRaw: await db.read(`${root}/TransferState`),
      gw: gw!,
    });
  } else {
    uids = allManagers(await db.read(`${root}/Managers`), squadsRaw);
  }

  const data = fantasyPushData(sport, season, gw ?? 0);
  const sent = uids.length === 0 ? 0 : await pusher.sendToUsers(
    uids.map((uid) => ({ uid, title, body, data })));
  log.info('fantasy message sent', {
    sport, season, gw: gw ?? 0, mode: audience,
    ...(audience === 'owners' ? { player } : {}),
    audience: uids.length, sent,
  });
  return { audience: uids.length, sent };
}

/** Whether a ScheduledPushes row is due: a map with a numeric SendAt at or
 *  before [nowMs] and no SentAt claim yet. */
export function isScheduledMessageDue(row: unknown, nowMs: number): boolean {
  if (!isPlainMap(row) || row['SentAt'] != null) return false;
  const at = row['SendAt'];
  return typeof at === 'number' && Number.isFinite(at) && at <= nowMs;
}

function stringOf(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

/** The sweep's scheduled-message step (see the header): claims + sends
 *  every due row of the season once. Returns how many rows this call
 *  claimed (sent or failed). */
export async function sendDueScheduledMessages(
  db: FantasyDb, pusher: FantasyPusher,
  args: { sport: string; season: string; nowUtc: Date; log?: FantasyLogger },
): Promise<number> {
  const { sport, season, nowUtc } = args;
  const log = args.log ?? silent;
  const ctx = { sport, season };
  const nowMs = nowUtc.getTime();
  const base = `${fantasyRoot(sport, season)}/ScheduledPushes`;

  let handled = 0;
  for (const [id, raw] of childEntries(await db.read(base))) {
    if (!isScheduledMessageDue(raw, nowMs)) continue;
    const path = `${base}/${id}`;
    if (!(await db.writeIfAbsent(`${path}/SentAt`, nowMs))) continue;
    handled++;
    const row = raw as Record<string, unknown>;
    try {
      const res = await sendManagerMessage(db, pusher, {
        sport,
        season,
        title: stringOf(row['Title']),
        body: stringOf(row['Body']),
        audience: managerMessageAudienceOf(row['Audience']),
        ...(typeof row['Player'] === 'string' ? { player: row['Player'] } : {}),
        nowUtc,
        log,
      });
      await db.write(`${path}/Sent`, res.sent);
      log.info('fantasy message: scheduled message sent', { ...ctx, id, ...res });
    } catch (err) {
      const error = err instanceof Error ? err.message : String(err);
      log.warn('fantasy message: scheduled message failed', { ...ctx, id, error });
      await db.write(`${path}/Error`, error);
    }
  }
  return handled;
}
