// Infinite Fantasy owner-void trigger (spec §15 "void-a-week"). Thin: the
// re-settle decision lives pure in src/lib/fantasy/orchestration.ts
// resettleVoidToggle, which hands the gameweek to the same match-day
// finalize entry the game trigger uses (all of its gates apply); the
// voided-week settle semantics are documented in finalize_core.ts (VOIDED
// GAMEWEEKS) and orchestration.ts (Voided/<gw>).
//
// The Manager's "VOID week" toggle writes Voided/<gw> = true or removes it.
// One wildcard trigger covers every sport/season (fantasy_transfers.ts
// convention: the Fantasy/ prefix keeps the wildcard off the busy league
// paths). The payload gate re-settles only on a real flip of voided-ness —
// any other write (e.g. a junk value replacing absent) changes nothing.
//
// Spec: docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md §15.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import {
  fantasyLogger, readAnthropicKey, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { resettleVoidToggle } from './lib/fantasy/orchestration';
import { isVoidFlag } from './lib/fantasy/orchestration_db';
import { anthropicApiKey } from './support_joke';

export const onFantasyVoidWritten = onValueWritten(
  {
    ref: '/Fantasy/{sport}/{season}/Voided/{gw}',
    // A re-settle is a full finalize run (fantasy_finalize.ts parity): if it
    // happens to be the week's FIRST settle and the week counts, it pushes
    // the recap and drafts the news like any other entry point.
    secrets: [anthropicApiKey],
  },
  async (event) => {
    const before = isVoidFlag(event.data.before.val());
    const after = isVoidFlag(event.data.after.val());
    if (before === after) return; // no flip of voided-ness: nothing to settle
    const gw = Number(event.params['gw']);
    if (!Number.isInteger(gw) || gw <= 0) return;
    // Same-instance root (matters in the emulator) — index.ts dbRoot parity.
    const root = event.data.before.ref.root as Reference;
    await resettleVoidToggle(rtdbFantasyDb(root), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      gw,
      nowUtc: new Date(),
      log: fantasyLogger,
      deps: {
        pusher: rtdbFantasyPusher(root),
        news: { apiKey: readAnthropicKey() },
      },
    });
  },
);
