// Infinite Fantasy transfer-accounting trigger (P4 Phase E). Thin: the
// counting rule (used transfers vs the previous locked squad, SavedGw stamp,
// open-gameweek gate) lives pure in src/lib/fantasy/orchestration.ts
// recordSquadSave; the TransferState node contract is documented in
// src/lib/fantasy/transfer_state.ts.
//
// One wildcard trigger covers every sport/season — the Fantasy/ prefix keeps
// the wildcard off the busy league paths (unlike the per-sport Date
// triggers, which must bake the sport into a top-level path).
//
// Spec: docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md §5, §6.
// Plan: docs/superpowers/plans/2026-10-28-fantasy-p4-functions.md Phase E.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { recordSquadSave } from './lib/fantasy/orchestration';

export const onFantasySquadWritten = onValueWritten(
  '/Fantasy/{sport}/{season}/Squads/{uid}',
  async (event) => {
    // Deletions carry nothing to count; recordSquadSave re-checks anyway.
    if (event.data.after.val() == null) return;
    // Same-instance root (matters in the emulator) — index.ts dbRoot parity.
    const root = event.data.before.ref.root as Reference;
    await recordSquadSave(rtdbFantasyDb(root), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      uid: String(event.params['uid']),
      log: fantasyLogger,
      // Who wrote is judged on THIS event's value: a server write
      // (ServerWriteAt) never stamps SavedGw, a manager save always does.
      after: event.data.after.val(),
    });
  },
);
