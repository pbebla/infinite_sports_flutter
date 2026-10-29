// Infinite Fantasy scheduled jobs (P4 Phases B + D + F). Thin: both
// handlers just hand the admin root (and the FCM pusher seam) to the pure
// orchestration (src/lib/fantasy/orchestration.ts), which documents every
// node shape.
//
// - fantasyLifecycleSweep (every 15 minutes): per fantasy-enabled season in
//   'auto', derive gameweeks from the real schedule, persist GwState when it
//   changed, snapshot Squads -> PublishedPicks/<gw> once at lock (spec §9,
//   with the Phase E chip-void/cost freeze riding it), finalize any locked
//   gameweek whose match day completed while the match-day trigger was down
//   (fantasy_finalize.ts is the fast path), and push the once-per-gameweek
//   deadline reminder to unchanged squads (spec §12). Also sends the
//   owner's due scheduled manager messages (ScheduledPushes, messages.ts) —
//   even for a season whose lockOverride freezes the engine.
//
// - fantasyMondayReprice (Mondays 10:00 America/Los_Angeles — league time,
//   spec §4/§5): reprice the most recent finalized gameweek not yet
//   repriced; position-relative deltas from the week's bonus-inclusive
//   points, applied to Players/<name>/priceTenths with floor/ceiling, logged
//   to PriceChanges/<gw> for the risers & fallers strip. Admin-manual weeks
//   (PriceChanges/<gw>/Manual == true) are skipped.
//
// Spec: docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md §4, §5,
// §9. Plan: docs/superpowers/plans/2026-10-28-fantasy-p4-functions.md B + D.

import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import {
  fantasyLogger, readAnthropicKey, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { runLifecycleSweep, runMondayReprice } from './lib/fantasy/orchestration';
import { anthropicApiKey } from './support_joke';

export const fantasyLifecycleSweep = onSchedule(
  { schedule: 'every 15 minutes', secrets: [anthropicApiKey] },
  async () => {
    const root = admin.database().ref();
    await runLifecycleSweep(rtdbFantasyDb(root), new Date(), fantasyLogger, {
      pusher: rtdbFantasyPusher(root),
      news: { apiKey: readAnthropicKey() }, // backstop finalizes draft news
    });
  },
);

export const fantasyMondayReprice = onSchedule(
  { schedule: 'every monday 10:00', timeZone: 'America/Los_Angeles' },
  async () => {
    const root = admin.database().ref();
    await runMondayReprice(rtdbFantasyDb(root), new Date(), fantasyLogger);
  },
);
