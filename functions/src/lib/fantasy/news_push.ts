// News push on publish (spec 2026-10-28 §4.5) — pure TS behind the
// FantasyDb / FantasyPusher seams; the thin RTDB trigger lives in
// src/fantasy_news.ts (onFantasyNewsPublished).
//
// ONE PATH FOR EVERY PUBLISH: the Manager's Publish now, a draft publish and
// the sweep's autopilot publish all land a News/Published/<id> row, and the
// trigger on that row is the only thing that pushes. A row pushes when it
// carries a `Push` map ({Title, Body, Audience}) and no `PushedAt`:
//
//   claim  writeIfAbsent(News/Published/<id>/PushedAt, now ms) — the only
//          writer that finds it empty sends (at most once, ever)
//   send   Audience 'managers' -> every fantasy manager (Managers ∪ Squads)
//                    'owners'   -> managers whose current squad holds ANY
//                                  tagged player (Players/<k>.name)
//                    'everyone' -> FCM topic all_users (campaign parity)
//                    unknown    -> 'managers'
//   record PushSent = the delivered count (topic send: 1)
//
// The trigger re-fires on its own PushedAt / PushSent writes and on every
// later Manager edit — the PushedAt guard turns those into no-ops (edits
// never re-push; spec §5: no re-push on edit). A row without Push (legacy
// posts, AI drafts) never pushes and is never written to.
//
// Payload: fantasyPushData(sport, season, Gw ?? 0) + postId — the fan
// router opens the hub's News tab on that post.

import { allManagers, ownersOf } from './audiences';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, FantasyDb, fantasyRoot, isPlainMap, toIntLoose,
} from './orchestration_db';
import { FantasyPusher, fantasyPushData } from './pushes';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

/** The FCM topic every app install subscribes to (lib/campaigns.ts
 *  audienceTopic 'all'). */
export const EVERYONE_TOPIC = 'all_users';

/** Last-resort push title when both the push and the post title are blank —
 *  a notification must never arrive empty. */
export const NEWS_PUSH_FALLBACK_TITLE = 'Fantasy news';

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

/** Pushes one published post once (see the header). Null when there is
 *  nothing to do: the row is absent, has no Push map, already carries
 *  PushedAt, or another instance won the PushedAt claim. */
export async function pushPublishedPost(
  db: FantasyDb, pusher: FantasyPusher, args: PushPublishedPostArgs,
): Promise<{ sent: number } | null> {
  const { sport, season, postId } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const path = `${root}/News/Published/${postId}`;

  const post = await db.read(path);
  if (!needsNewsPush(post)) return null;
  const row = post as Record<string, unknown>;
  const push = row['Push'] as Record<string, unknown>;

  if (!(await db.writeIfAbsent(`${path}/PushedAt`, args.nowUtc.getTime()))) {
    return null; // another instance claimed it first
  }

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

  await db.write(`${path}/PushSent`, sent);
  log.info('fantasy news: post pushed', {
    sport, season, postId, audience, recipients, sent,
  });
  return { sent };
}
