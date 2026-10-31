// Infinite Fantasy badge push (spec 2026-10-30 §4). Thin: the whole decision
// (the BadgePushClaims/<uid>/<awardId> once-only claim, the paused-season
// rule for auto awards, the copy, the send) lives pure in
// src/lib/fantasy/badge_push.ts, which also documents the shapes; the awards
// themselves come from badges.ts (engine) and the Manager (manual).
//
// A CREATE trigger on one award row, wildcard over every sport/season
// (fantasy_transfers.ts convention: the Fantasy/ prefix keeps the wildcard
// off the busy league paths). The engine creates and removes award rows one
// child at a time, so a rerun that keeps an award fires nothing; a row that
// was removed and later re-created fires again and is stopped by the claim.

import { onValueCreated } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import {
  fantasyLogger, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { pushBadgeAward } from './lib/fantasy/badge_push';

export const onFantasyBadgeAwarded = onValueCreated(
  { ref: '/Fantasy/{sport}/{season}/Badges/{uid}/{awardId}' },
  async (event) => {
    // Same-instance root (matters in the emulator) — index.ts dbRoot parity.
    const root = event.data.ref.root as Reference;
    await pushBadgeAward(rtdbFantasyDb(root), rtdbFantasyPusher(root), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      uid: String(event.params['uid']),
      awardId: String(event.params['awardId']),
      nowUtc: new Date(),
      log: fantasyLogger,
    });
  },
);
