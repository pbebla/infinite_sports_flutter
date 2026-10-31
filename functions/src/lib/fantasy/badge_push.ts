// Badge push on award creation (spec 2026-10-30 §4) — pure TS behind the
// FantasyDb / FantasyPusher seams; the thin RTDB trigger lives in
// src/fantasy_badges.ts (onFantasyBadgeAwarded, a CREATE trigger on
// Fantasy/{sport}/{season}/Badges/{uid}/{awardId}). Award + catalog shapes:
// badges.ts.
//
// ONE PATH FOR EVERY AWARD: the engine's auto awards (finalize / season
// end) and the Manager's manual awards both land a Badges/<uid>/<awardId>
// row; the create trigger is the only thing that pushes.
//
//   claim  writeIfAbsent(BadgePushClaims/<uid>/<awardId>, { At: now ms }) —
//          only the writer that finds it empty sends, so a re-fired trigger,
//          or an award a rerun removed and later re-created, never pushes
//          twice (News/PushClaims parity)
//   send   one push to that manager: auto "You earned <Name> 🏅" (body:
//          "Gameweek N: <Description>" / "Season S: <Description>"), manual
//          "You received a badge: <Name>" (body: the owner's Note, else the
//          badge description); payload fantasyPushData(sport, season, Gw ?? 0)
//          + badge: awardId -> the fan router opens Fantasy
//   record BadgePushClaims/<uid>/<awardId> = { At, Sent }
//
// PAUSED SEASONS (lockOverride open/locked, effective now): the engine
// computes no auto awards there (spec §4), so an AUTO award showing up in a
// paused season is not the engine's — it is the S15 test fill (which also
// writes its replayed claims first) or an import. It is claimed as
// { At, Skipped:'paused' } and never pushes: test-season data must never
// reach a real manager's phone. A MANUAL award pushes normally whatever the
// engine state (Review Focus 4).
//
// NODE (functions-internal; rules: no client access):
//   BadgePushClaims/<uid>/<awardId> = { At:int, Sent?:int, Skipped?:'paused' }

import { BADGE_CATALOG_PATH, BadgeCatalog, catalogOf } from './badges';
import type { FantasyLogger } from './orchestration';
import {
  FantasyDb, fantasyRoot, isPlainMap, lockOverrideOf, toIntLoose,
} from './orchestration_db';
import { FantasyPusher, fantasyPushData } from './pushes';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

function trimmed(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

/** Title + body of one award's push (see the header). */
export function badgePushCopy(
  row: Record<string, unknown>, catalog: BadgeCatalog, season: string,
): { title: string; body: string } {
  const entry = catalog[String(row['Badge'] ?? '')];
  const name = entry?.Name ?? '';
  const desc = entry?.Description ?? '';
  if (row['Source'] === 'manual') {
    return {
      title: name ? `You received a badge: ${name}` : 'You received a badge',
      body: trimmed(row['Note']) || desc || 'Infinite Fantasy',
    };
  }
  const gw = toIntLoose(row['Gw']);
  const when = gw > 0 ? `Gameweek ${gw}` : `Season ${season}`;
  return {
    title: name ? `You earned ${name} 🏅` : 'You earned a badge 🏅',
    body: desc ? `${when}: ${desc}` : when,
  };
}

export interface PushBadgeArgs {
  sport: string;
  season: string;
  uid: string;
  awardId: string;
  nowUtc: Date;
  log?: FantasyLogger;
}

/** Pushes one award once (see the header). Null when nothing was sent: the
 *  row is gone, its claim already exists (pushed before, or another
 *  instance won), or it is an auto award in a paused season. */
export async function pushBadgeAward(
  db: FantasyDb, pusher: FantasyPusher, args: PushBadgeArgs,
): Promise<{ sent: number } | null> {
  const { sport, season, uid, awardId } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const claimPath = `${root}/BadgePushClaims/${uid}/${awardId}`;
  const nowMs = args.nowUtc.getTime();
  const ctx = { sport, season, uid, awardId };

  const row = await db.read(`${root}/Badges/${uid}/${awardId}`);
  if (!isPlainMap(row)) return null; // removed before we ran

  if (row['Source'] !== 'manual' &&
    lockOverrideOf(await db.read(`${root}/Config`), nowMs) !== 'auto') {
    if (await db.writeIfAbsent(claimPath, { At: nowMs, Skipped: 'paused' })) {
      log.info('fantasy badges: auto award in a paused season — not pushed', ctx);
    }
    return null;
  }

  if (!(await db.writeIfAbsent(claimPath, { At: nowMs }))) return null;

  const { title, body } = badgePushCopy(
    row, catalogOf(await db.read(BADGE_CATALOG_PATH)), season);
  const data = {
    ...fantasyPushData(sport, season, toIntLoose(row['Gw'])),
    badge: awardId,
  };
  const sent = await pusher.sendToUsers([{ uid, title, body, data }]);
  await db.write(claimPath, { At: nowMs, Sent: sent });
  log.info('fantasy badges: award pushed',
    { ...ctx, source: String(row['Source'] ?? ''), sent });
  return { sent };
}
