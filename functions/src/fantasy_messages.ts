// Manager callables for News desk 2.0 + Message managers (spec 2026-10-28
// §3, §4.5). Both admin-gated exactly like sendFantasyReminderNow
// (fantasy_push.ts): signed in -> /Admins/<uid> === true. The logic lives
// pure in src/lib/fantasy/copywriter.ts and messages.ts.
//
// writeFantasyCopy — AI copy for a post, a post's push or a manager message.
//   data: { sport:string, season:string|number,
//           mode:'post'|'push'|'message',
//           template?:string, players?:string[] (market names, max 5 used),
//           title?:string, body?:string, hint?:string }
//   -> { title:string, body:string }   (post 60/400, push 40/110,
//                                       message 40/140 characters)
//   The server builds the players' stat cards itself (Players, PlayerTotals,
//   PlayerWeeks, PriceChanges, <sport>/<season>/Date); the model sees
//   nothing else. Errors: unauthenticated / permission-denied /
//   invalid-argument (sport, season or mode) / unavailable 'Could not write
//   copy' (no key, API failure, timeout, unusable reply, nothing to write
//   from) — the Manager shows "Couldn't write it right now — try again."
//
// sendFantasyMessage — the Message-managers card's Send now.
//   data: { sport:string, season:string|number, title:string, body?:string,
//           audience?:'all'|'unchanged'|'owners' (absent = 'all'),
//           player?:string (required for 'owners') }
//   -> { audience:int (recipients), sent:int (delivered) }
//   Errors: unauthenticated / permission-denied / invalid-argument (sport,
//   season or an unknown audience) / failed-precondition (empty title,
//   'owners' without a player, 'unchanged' with no fantasy Config or no
//   current gameweek — the message text says which).

import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import {
  fantasyLogger, readAnthropicKey, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { isCopyMode, loadCopyCards, writeCopy } from './lib/fantasy/copywriter';
import {
  ManagerMessageAudience, managerMessageAudienceOf, sendManagerMessage,
} from './lib/fantasy/messages';
import { anthropicApiKey } from './support_joke';

function asTrimmedString(v: unknown): string {
  return typeof v === 'string' || typeof v === 'number' ? String(v).trim() : '';
}

function optString(v: unknown): string | undefined {
  return typeof v === 'string' ? v : undefined;
}

/** Signed-in admin (/Admins/<uid> === true) or an HttpsError; the uid.
 *  Exported for the other Manager callables (user_contact.ts) — index.ts
 *  re-exports only the callables by name, so this is not deployed itself. */
export async function requireAdmin(request: CallableRequest): Promise<string> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  const adminSnap = await admin.database().ref(`Admins/${uid}`).get();
  if (adminSnap.val() !== true) {
    throw new HttpsError('permission-denied', 'Admins only.');
  }
  return uid;
}

function seasonOf(data: unknown): { sport: string; season: string } {
  const d = (data ?? {}) as Record<string, unknown>;
  const sport = asTrimmedString(d['sport']);
  const season = asTrimmedString(d['season']);
  if (!sport || !season) {
    throw new HttpsError('invalid-argument', 'Missing sport/season.');
  }
  return { sport, season };
}

export const writeFantasyCopy = onCall(
  { secrets: [anthropicApiKey] },
  async (request) => {
    const uid = await requireAdmin(request);
    const { sport, season } = seasonOf(request.data);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const mode = data['mode'];
    if (!isCopyMode(mode)) {
      throw new HttpsError(
        'invalid-argument', 'mode must be post, push or message.');
    }
    const names = Array.isArray(data['players'])
      ? data['players'].filter((n): n is string => typeof n === 'string')
      : [];

    const root = admin.database().ref();
    const cards = await loadCopyCards(rtdbFantasyDb(root), { sport, season, names });
    const apiKey = readAnthropicKey();
    if (!apiKey) {
      fantasyLogger.warn('writeFantasyCopy: ANTHROPIC_API_KEY not configured');
    }
    const copy = await writeCopy({
      mode,
      template: optString(data['template']),
      cards,
      title: optString(data['title']),
      body: optString(data['body']),
      hint: optString(data['hint']),
      apiKey,
    });
    if (copy === null) {
      fantasyLogger.warn('writeFantasyCopy: no usable copy',
        { uid, sport, season, mode, players: cards.length });
      throw new HttpsError('unavailable', 'Could not write copy');
    }
    fantasyLogger.info('writeFantasyCopy',
      { uid, sport, season, mode, players: cards.length });
    return copy; // { title, body }
  },
);

export const sendFantasyMessage = onCall(async (request) => {
  const uid = await requireAdmin(request);
  const { sport, season } = seasonOf(request.data);
  const data = (request.data ?? {}) as Record<string, unknown>;
  let audience: ManagerMessageAudience;
  try {
    audience = managerMessageAudienceOf(data['audience']);
  } catch (err) {
    throw new HttpsError('invalid-argument', String((err as Error).message));
  }

  const root = admin.database().ref();
  try {
    const res = await sendManagerMessage(
      rtdbFantasyDb(root), rtdbFantasyPusher(root), {
        sport,
        season,
        title: optString(data['title']) ?? '',
        body: optString(data['body']) ?? '',
        audience,
        player: optString(data['player']),
        nowUtc: new Date(),
        log: fantasyLogger,
      });
    fantasyLogger.info('sendFantasyMessage', { uid, sport, season, ...res });
    return res; // { audience, sent }
  } catch (err) {
    throw new HttpsError('failed-precondition',
      err instanceof Error ? err.message : String(err));
  }
});
