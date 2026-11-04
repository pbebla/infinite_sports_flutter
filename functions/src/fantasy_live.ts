// Infinite Fantasy live gameweek trigger (live design 2026-11-03 §4). Thin:
// the gate, the recompute and the guarded publish live pure in
// src/lib/fantasy/orchestration.ts (maybeRefreshLive / refreshLiveWeek) and
// src/lib/fantasy/live_core.ts (liveWriteMatters / computeLiveWeek).
//
// One onValueWritten per sport on the WHOLE game node — the same path as
// the finalize trigger (fantasy_finalize.ts), grouped next to it in
// index.ts (deploys as e.g. fantasyFutsal-onGameLive). Every write to a game
// of the locked week's date recomputes the live week and publishes
// Fantasy/<sport>/<season>/Live in one guarded transaction. The payload
// gate keeps everything else free: unless the game counts or counted
// (live or Final, before or after the write) AND a key the scorer reads
// changed (a clock tick, a livestream link, undo bookkeeping change none),
// the handler returns without a single database read. No secrets: a live
// run never pushes nor drafts. The event's own time is the coalescing
// stamp (a run whose event an earlier-started run already read past stands
// down before any heavy read).
//
// Spec: docs/superpowers/specs/2026-11-03-fantasy-live-design.md §4–§5.
// Plan: docs/superpowers/plans/2026-11-03-fantasy-live-everywhere.md Task 3.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { maybeRefreshLive } from './lib/fantasy/orchestration';
import { writeTimeOf } from './lib/fantasy/orchestration_db';

/** Same-instance root (matters in the emulator) — index.ts dbRoot parity. */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** The live trigger for ONE sport, merged into that sport's grouped
 *  index.ts export next to onGameWritten (fantasyFutsal-onGameLive). */
export function makeFantasyLiveTrigger(sport: string) {
  return {
    onGameLive: onValueWritten(
      { ref: `/${sport}/{season}/Date/{dateKey}/{gameIndex}` },
      async (event) => {
        const nowUtc = new Date();
        // maybeRefreshLive gates on the payload first: zero reads unless
        // the write can move a live number.
        await maybeRefreshLive(rtdbFantasyDb(dbRoot(event)), {
          sport,
          season: String(event.params['season']),
          dateKey: String(event.params['dateKey']),
          before: event.data.before.val(),
          after: event.data.after.val(),
          eventAtMs: writeTimeOf(event.time, nowUtc).getTime(),
          nowUtc,
          log: fantasyLogger,
        });
      },
    ),
  };
}
