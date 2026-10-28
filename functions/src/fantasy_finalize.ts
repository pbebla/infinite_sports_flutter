// Infinite Fantasy match-day finalization trigger (P4 Phase C). Thin: the
// decision of WHEN and the whole pipeline live pure in
// src/lib/fantasy/orchestration.ts (maybeFinalizeGame / finalizeGameweek).
//
// One onValueWritten per sport on the WHOLE game node (league_watch.ts
// makeLeagueTriggers factory convention: sport baked into the path, grouped
// export from index.ts). Watching the node rather than seven leaf paths
// means EVERY post-final edit — status flip to Final, a score correction, an
// attendance toggle, a late assist in the activity list — re-fires the same
// handler, and finalization recomputes everything downstream (History,
// leaderboards, PlayerTotals, DreamTeam-unless-admin-edited). The payload
// gate keeps live games free: any write while status != 2 returns without a
// single database read, and idempotent recomputation is the debounce.
//
// Spec: docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md §7, §9.
// Plan: docs/superpowers/plans/2026-10-28-fantasy-p4-functions.md Phase C.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { maybeFinalizeGame } from './lib/fantasy/orchestration';
import { isPlainMap, toIntLoose } from './lib/fantasy/orchestration_db';

/** Same-instance root (matters in the emulator) — index.ts dbRoot parity. */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** All fantasy finalize triggers for ONE sport, for a grouped index.ts
 *  export (deploys as e.g. fantasyFutsal-onGameWritten). */
export function makeFantasyFinalizeTrigger(sport: string) {
  return {
    onGameWritten: onValueWritten(
      `/${sport}/{season}/Date/{dateKey}/{gameIndex}`,
      async (event) => {
        const after = event.data.after.val();
        // Payload-only gate: nothing to settle unless the written game is
        // Final right now (reopen/undo edits re-settle on the re-final).
        if (!isPlainMap(after) || toIntLoose(after['status']) !== 2) return;
        await maybeFinalizeGame(rtdbFantasyDb(dbRoot(event)), {
          sport,
          season: String(event.params['season']),
          dateKey: String(event.params['dateKey']),
          nowUtc: new Date(),
          log: fantasyLogger,
        });
      },
    ),
  };
}
