// Manager callables that start a fantasy season (season setup + schedule plan
// 2026-11-05, Task 6). Both admin-gated exactly like the other Manager
// callables (fantasy_messages.ts requireAdmin: signed in -> /Admins/<uid> ===
// true). The logic lives pure in src/lib/fantasy/season_start.ts.
//
// previewFantasySeason — read-only; the Manager's Start page.
//   data: { sport:string, season:string|number }
//   -> SeasonPreview { sport, season, sourceSeason, rows:[{ name, team, uid,
//        position, positionFrom:'season'|'signup'|'default', priceTenths,
//        priceFrom:'season'|'average'|'rookie', fromSeason, photoUrl }],
//        settings:{ lockHour, copiedFrom }, access:{ Mode:'free'|'pass',
//        AmountDollars:number|null, Methods:{Venmo,Zelle,Card},
//        RegisteredPlayersFree }, problems:('noRosters'|'noSchedule'|
//        'alreadyStarted'|'sourceIsTestFill')[] }
//
// startFantasySeason — the Start button.
//   data: { sport, season, edits?:{ <name>:{ priceTenths?:int,
//           position?:'GK'|'DEF'|'ATT' } }, access:AccessDraft }
//   -> { players:int }
//   Errors: unauthenticated / permission-denied / invalid-argument (sport or
//   season; details.problem 'badAccess' = the season pass settings, 'badEdit'
//   = an unusable edit) / failed-precondition (details.problems = the codes
//   above; 'alreadyStarted' also when a concurrent Start won).

import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { requireAdmin } from './fantasy_messages';
import {
  AccessDraft, buildSeasonPreview, parseEditsArg, startSeason, StartSeasonError,
} from './lib/fantasy/season_start';

/** The sports that have a fantasy season. */
const FANTASY_SPORTS = ['Futsal', 'Basketball', 'Flag Football'];

/** The highest season number a Start accepts (a typo guard, far above any
 *  real season). */
const MAX_SEASON = 200;

function seasonOf(data: unknown): { sport: string; season: string } {
  const d = (data ?? {}) as Record<string, unknown>;
  const sport = typeof d['sport'] === 'string' ? d['sport'].trim() : '';
  const rawSeason = d['season'];
  const season = typeof rawSeason === 'string' || typeof rawSeason === 'number'
    ? String(rawSeason).trim() : '';
  if (!FANTASY_SPORTS.includes(sport)) {
    throw new HttpsError('invalid-argument', 'Unknown sport.');
  }
  // A season is its number: the carry-over reads every season below it, so a
  // slip like 2026 is refused rather than read 2025 times.
  if (!/^[1-9]\d{0,2}$/.test(season) || Number(season) > MAX_SEASON) {
    throw new HttpsError('invalid-argument', 'The season must be a number.');
  }
  return { sport, season };
}

/** The lib's StartSeasonError carries the HttpsError code and details. */
function asHttpsError(err: unknown): unknown {
  return err instanceof StartSeasonError
    ? new HttpsError(err.code, err.message, err.details)
    : err;
}

export const previewFantasySeason = onCall(async (request) => {
  await requireAdmin(request);
  const { sport, season } = seasonOf(request.data);
  try {
    return await buildSeasonPreview(
      rtdbFantasyDb(admin.database().ref()), sport, season);
  } catch (err) {
    throw asHttpsError(err);
  }
});

export const startFantasySeason = onCall(async (request) => {
  const uid = await requireAdmin(request);
  const { sport, season } = seasonOf(request.data);
  const data = (request.data ?? {}) as Record<string, unknown>;
  try {
    const edits = parseEditsArg(data['edits']);
    // startSeason checks the draft itself (after the problems, as the plan
    // orders it) — the raw value goes in.
    return await startSeason(
      rtdbFantasyDb(admin.database().ref()), sport, season, edits,
      data['access'] as AccessDraft, uid, Date.now(), fantasyLogger);
  } catch (err) {
    throw asHttpsError(err);
  }
});
