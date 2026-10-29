// News push on publish (spec 2026-10-28 §4.5) — pure TS behind the
// FantasyDb / FantasyPusher seams; the thin RTDB trigger lives in
// src/fantasy_news.ts (onFantasyNewsPublished).
//
// ONE PATH FOR EVERY PUBLISH: the Manager's Publish now, a draft publish and
// the sweep's autopilot publish all land a News/Published/<id> row, and the
// trigger on that row is the only thing that pushes. A row is a candidate
// when it carries a `Push` map ({Title, Body, Audience}) and no `PushedAt`:
//
//   stale  a row whose numeric At is more than NEWS_PUSH_STALE_MS (60 min)
//          before now is claimed as { At, Skipped:'stale' } and never
//          pushes (a post published before this trigger existed, or a
//          failed trigger re-fired days later by an edit)
//   claim  writeIfAbsent(News/PushClaims/<id>, { At: now ms }) — the only
//          writer that finds it empty sends (at most once, ever)
//   send   Audience 'managers' -> every fantasy manager (Managers ∪ Squads)
//                    'owners'   -> managers whose current squad holds ANY
//                                  tagged player (Players/<k>.name)
//                    'everyone' -> FCM topic all_users (campaign parity)
//                    unknown    -> 'managers'
//   record PushClaims/<id> = { At, Sent } (Sent = the delivered count; a
//          topic send counts 1)
//
// NODE (functions-internal; no client reads it — the rules give it no read
// rule, the News .write admin rule covers it):
//
//   News/PushClaims/<postId> = { At:int, Sent?:int, Skipped?:'stale' }
//
// WHY A SEPARATE NODE (review 2026-10-28): the claim used to live IN the row
// (PushedAt), so any whole-row set — the Manager's publish multi-path
// update, a sweep republishing a duplicate draft — wiped it and the trigger
// pushed the post a second time. A rewritten row can never re-push now.
//
// DISPLAY STAMPS: PushedAt (at the claim) and PushedAt + PushSent (after the
// send) are still stamped onto the row for the Manager's "Pushed to N" and
// as the trigger's read-free echo gate — through updateIfPresent, so a post
// the owner deleted meanwhile is never recreated as a stub. A stale skip
// stamps nothing (it was never pushed).
//
// The trigger re-fires on its own stamps and on every later Manager edit —
// the PushedAt gate (or, on a rewritten row, the claim) turns those into
// no-ops (edits never re-push; spec §5: no re-push on edit). A row without
// Push (legacy posts, AI drafts) never pushes and is never written to.
//
// Payload: fantasyPushData(sport, season, Gw ?? 0) + postId — the fan
// router opens the hub's News tab on that post.

import { allManagers, ownersOf } from './audiences';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, FantasyDb, fantasyRoot, isPlainMap, toIntLoose,
  updateIfPresent,
} from './orchestration_db';
import { FantasyPusher, fantasyPushData } from './pushes';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

/** The FCM topic every app install subscribes to (lib/campaigns.ts
 *  audienceTopic 'all'). */
export const EVERYONE_TOPIC = 'all_users';

/** Last-resort push title when both the push and the post title are blank —
 *  a notification must never arrive empty. */
export const NEWS_PUSH_FALLBACK_TITLE = 'Fantasy news';

/** A post first seen by the trigger more than this long after its `At` is
 *  stale and never pushes (see the header). */
export const NEWS_PUSH_STALE_MS = 60 * 60_000;

export type NewsPushAudience = 'managers' | 'owners' | 'everyone';

/** Push.Audience; anything unknown/absent reads as 'managers'. */
export function newsPushAudienceOf(raw: unknown): NewsPushAudience {
  return raw === 'owners' || raw === 'everyone' ? raw : 'managers';
}

/** Whether a Published row still owes its push: a map row with a Push map
 *  and no PushedAt. Also the trigger's read-free gate on the event value. */
export function needsNewsPush(postNode: unknown): boolean {
  return isPlainMap(postNode) && isPlainMap(postNode['Push']) &&
    postNode['PushedAt'] == null;
}

/** The tagged players' names, from the post's Players snapshot node
 *  ({"0": card, ...} — or the list it coerces to). */
export function taggedPlayerNames(playersNode: unknown): string[] {
  const out: string[] = [];
  for (const [, c] of childEntries(playersNode)) {
    if (!isPlainMap(c)) continue;
    const name = typeof c['name'] === 'string' ? c['name'].trim() : '';
    if (name.length > 0) out.push(name);
  }
  return out;
}

function trimmed(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

export interface PushPublishedPostArgs {
  sport: string;
  season: string;
  postId: string;
  nowUtc: Date;
  log?: FantasyLogger;
}

/** Pushes one published post once (see the header). Null when nothing was
 *  sent: the row is absent, has no Push map, already carries PushedAt, is
 *  stale (claimed as skipped), or its PushClaims entry already exists
 *  (pushed before — even if the row was rewritten since — or another
 *  instance won the claim). */
export async function pushPublishedPost(
  db: FantasyDb, pusher: FantasyPusher, args: PushPublishedPostArgs,
): Promise<{ sent: number } | null> {
  const { sport, season, postId } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const path = `${root}/News/Published/${postId}`;
  const claimPath = `${root}/News/PushClaims/${postId}`;
  const nowMs = args.nowUtc.getTime();
  const ctx = { sport, season, postId };

  const post = await db.read(path);
  if (!needsNewsPush(post)) return null;
  const row = post as Record<string, unknown>;
  const push = row['Push'] as Record<string, unknown>;

  const publishedAt = row['At'];
  if (typeof publishedAt === 'number' && Number.isFinite(publishedAt) &&
    nowMs - publishedAt > NEWS_PUSH_STALE_MS) {
    if (await db.writeIfAbsent(claimPath, { At: nowMs, Skipped: 'stale' })) {
      log.warn('fantasy news: stale post — push skipped',
        { ...ctx, publishedAt });
    }
    return null;
  }

  if (!(await db.writeIfAbsent(claimPath, { At: nowMs }))) {
    return null; // pushed before, or another instance claimed it first
  }
  await updateIfPresent(db, path, (cur) => ({ ...cur, PushedAt: nowMs }));

  const title = trimmed(push['Title']) || trimmed(row['Title']) ||
    NEWS_PUSH_FALLBACK_TITLE;
  const body = trimmed(push['Body']);
  const data = {
    ...fantasyPushData(sport, season, toIntLoose(row['Gw'])),
    postId,
  };
  const audience = newsPushAudienceOf(push['Audience']);

  let recipients: number;
  let sent: number;
  if (audience === 'everyone') {
    recipients = 1;
    sent = await pusher.sendToTopic(EVERYONE_TOPIC, title, body, data);
  } else {
    const squadsRaw = await db.read(`${root}/Squads`);
    const uids = audience === 'owners'
      ? ownersOf(squadsRaw, taggedPlayerNames(row['Players']))
      : allManagers(await db.read(`${root}/Managers`), squadsRaw);
    recipients = uids.length;
    sent = uids.length === 0 ? 0 : await pusher.sendToUsers(
      uids.map((uid) => ({ uid, title, body, data })));
  }

  await db.write(claimPath, { At: nowMs, Sent: sent });
  // Both stamps again: a rewrite during the send would have wiped PushedAt.
  await updateIfPresent(db, path,
    (cur) => ({ ...cur, PushedAt: nowMs, PushSent: sent }));
  log.info('fantasy news: post pushed', {
    ...ctx, audience, recipients, sent,
  });
  return { sent };
}
