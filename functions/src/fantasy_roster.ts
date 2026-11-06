// Infinite Fantasy mid-season roster trigger (season setup + schedule plan
// 2026-11-05, Task 7). Thin: the gate and the sync live pure in
// src/lib/fantasy/roster_sync.ts (rosterShapeChanged / maybeSyncRoster).
//
// A player added to a team mid-season joins the fantasy market by himself,
// within minutes, at his position's average price. The trigger watches one
// team's `Line Ups` node per sport (the sport baked into the path, grouped in
// index.ts next to the finalize and live triggers: fantasyFutsal-
// onLineupsWritten, ...). Live scoring writes a stat increment under this node
// on every goal, so the payload gate runs FIRST and the handler returns before
// a single database read unless a player key or a UID changed. It does not
// stand down for lockOverride (joiners are added even while paused); it does
// for a TestFill season and a season with no fantasy Config.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { maybeSyncRoster } from './lib/fantasy/roster_sync';

/** Same-instance root (matters in the emulator) — index.ts dbRoot parity. */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** The roster trigger for ONE sport (its database literal: 'Futsal',
 *  'Basketball', 'Flag Football'), merged into that sport's grouped index.ts
 *  export (fantasyFutsal-onLineupsWritten). */
export function makeFantasyRosterTrigger(sport: string) {
  return {
    onLineupsWritten: onValueWritten(
      { ref: `/${sport}/{season}/Line Ups/{team}` },
      async (event) => {
        await maybeSyncRoster(rtdbFantasyDb(dbRoot(event)), {
          sport,
          season: String(event.params['season']),
          team: String(event.params['team']),
          before: event.data.before.val(),
          after: event.data.after.val(),
          log: fantasyLogger,
        });
      },
    ),
  };
}
