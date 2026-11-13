// Infinite Fantasy schedule trigger (season setup + schedule plan
// 2026-11-05, Task 4). Thin: the decision lives pure in
// src/lib/fantasy/schedule_rewind.ts (scheduleConfigChanged /
// refreshOpenGwState).
//
// The owner moves a deadline (Config/Deadlines/<date>), skips or brings back
// a game day (Config/SkippedDates/<date>), or changes the automatic deadline
// (deadlineMinutesBeforeKickoff, lockHour) in the Manager: an OPEN week's
// GwState — and with it the Squads save rules — follows at once instead of
// up to 15 minutes later. A locked week stays the sweep's job; this trigger
// never rewinds a called-off week (Fable M2: only the sweep does, before its
// lock step). One wildcard trigger covers every sport/season
// (fantasy_void.ts convention); the payload gate runs first with zero reads,
// so every other Config write (Reminder, NewsAutopilot, the sweep's own
// lockOverride revert…) costs nothing.

import { onValueWritten } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import {
  refreshOpenGwState, scheduleConfigChanged,
} from './lib/fantasy/schedule_rewind';

export const onFantasyConfigWritten = onValueWritten(
  { ref: '/Fantasy/{sport}/{season}/Config' },
  async (event) => {
    if (!scheduleConfigChanged(
      event.data.before.val(), event.data.after.val())) return;
    // Same-instance root (matters in the emulator) — index.ts dbRoot parity.
    const root = event.data.before.ref.root as Reference;
    await refreshOpenGwState(rtdbFantasyDb(root), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      nowUtc: new Date(),
      log: fantasyLogger,
    });
  },
);
