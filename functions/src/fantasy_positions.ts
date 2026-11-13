// Infinite Fantasy holder-protection trigger (spec §3 owner revision
// 2026-10-28). Thin: the whole decision (open window → relabel holders,
// alert + push the ones left with an illegal formation, grant the free
// swap; locked window → defer to PendingPositionChanges for the reopen
// sweep) lives pure in src/lib/fantasy/position_changes.ts, which also
// documents the SquadAlerts / PendingPositionChanges node shapes.
//
// One wildcard trigger covers every sport/season (fantasy_transfers.ts
// convention: the Fantasy/ prefix keeps the wildcard off the busy league
// paths). It fires for any write that changes a player's position — the
// Manager's position editor, or a whole-Players re-seed.
//
// Spec: docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md §3.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import {
  fantasyLogger, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { handlePositionWrite } from './lib/fantasy/position_changes';

export const onFantasyPositionWritten = onValueWritten(
  '/Fantasy/{sport}/{season}/Players/{name}/position',
  async (event) => {
    const before = event.data.before.val();
    const after = event.data.after.val();
    if (before === after) return; // no change of position: nothing to do
    // Same-instance root (matters in the emulator) — index.ts dbRoot parity.
    const root = event.data.before.ref.root as Reference;
    await handlePositionWrite(rtdbFantasyDb(root), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      name: String(event.params['name']),
      before,
      after,
      nowUtc: new Date(),
      log: fantasyLogger,
      pusher: rtdbFantasyPusher(root),
    });
  },
);
