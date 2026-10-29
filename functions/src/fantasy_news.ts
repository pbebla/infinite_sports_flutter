// Infinite Fantasy news push on publish (spec 2026-10-28 §4.5). Thin: the
// whole decision (claim PushedAt, resolve the audience, send, record
// PushSent) lives pure in src/lib/fantasy/news_push.ts, which also
// documents the row shape.
//
// One wildcard trigger covers every sport/season (fantasy_transfers.ts
// convention: the Fantasy/ prefix keeps the wildcard off the busy league
// paths) and every way a post goes live — Manager publish, draft publish,
// autopilot publish. It re-fires on its own PushedAt/PushSent writes and on
// Manager edits; the event's after-value already shows PushedAt then, so
// those return before any database read.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import {
  fantasyLogger, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { needsNewsPush, pushPublishedPost } from './lib/fantasy/news_push';

export const onFantasyNewsPublished = onValueWritten(
  { ref: '/Fantasy/{sport}/{season}/News/Published/{postId}' },
  async (event) => {
    if (!event.data.after.exists()) return; // a delete: nothing to push
    if (!needsNewsPush(event.data.after.val())) return; // no Push / pushed
    // Same-instance root (matters in the emulator) — index.ts dbRoot parity.
    const root = event.data.after.ref.root as Reference;
    await pushPublishedPost(rtdbFantasyDb(root), rtdbFantasyPusher(root), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      postId: String(event.params['postId']),
      nowUtc: new Date(),
      log: fantasyLogger,
    });
  },
);
