import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import {
  decideGoal, decideStatus, goalKeysToClear, parseMatch, toInt,
} from './lib/decide';
import { loadNames } from './lib/names';
import { sendAlert } from './lib/fcm';

admin.initializeApp();

const GOAL_GRACE_MS = 10_000; // Scorekeepers typically enter the assist within ~10s of the goal; the alert waits so it can include the assist credit.

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Atomically claim a dedupe key. Returns false if someone already claimed it. */
async function claimKey(tid: string, mid: string, key: string): Promise<boolean> {
  const ref = admin.database().ref(`NotificationsMeta/${tid}/${mid}/${key}`);
  const result = await ref.transaction((cur) =>
    cur === null ? admin.database.ServerValue.TIMESTAMP : undefined);
  return result.committed;
}

async function handleScore(
  teamTag: 1 | 2,
  event: DatabaseEvent<Change<DataSnapshot>>,
): Promise<void> {
  const tid = event.params['tid'];
  const mid = event.params['mid'];
  const before = toInt(event.data.before.val());
  const after = toInt(event.data.after.val());

  if (after < before) {
    // Undo: re-arm the cleared scores so a corrected goal alerts again.
    const meta = admin.database().ref(`NotificationsMeta/${tid}/${mid}`);
    await Promise.all(goalKeysToClear(teamTag, before, after)
      .map((k) => meta.child(k).remove()));
    return;
  }
  if (after === before) return;

  // Guard on the match state at the moment of the goal, BEFORE the grace
  // window — an "End match" tapped during the wait must not kill the alert.
  const matchRef = admin.database().ref(`Tournaments/${tid}/Matches/${mid}`);
  const preMatch = parseMatch((await matchRef.get()).val());
  if (preMatch.status !== 1) return;

  const dedupeKey = `goal_t${teamTag}_${after}`;
  if (!(await claimKey(tid, mid, dedupeKey))) return;

  try {
    await sleep(GOAL_GRACE_MS); // let the scorekeeper enter the assist

    // Re-read for fresh activity (scorer + assist), keep pre-grace live status.
    const match = parseMatch((await matchRef.get()).val());
    match.status = 1;
    const names = await loadNames(tid, match);
    const decision = decideGoal({ teamTag, before, after, match, names, tid, mid });
    if (decision) {
      await sendAlert(decision);
    } else {
      logger.info('goal decision was null after grace window', { tid, mid, teamTag, after });
    }
  } catch (err) {
    // Release the claim so a retry can deliver the lost alert.
    await admin.database().ref(`NotificationsMeta/${tid}/${mid}/${dedupeKey}`)
      .remove().catch(() => undefined);
    throw err;
  }
}

export const onTeam1Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team1Score',
  (event) => handleScore(1, event),
);

export const onTeam2Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team2Score',
  (event) => handleScore(2, event),
);

export const onMatchStatus = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Status',
  async (event) => {
    const tid = event.params['tid'];
    const mid = event.params['mid'];
    const before = toInt(event.data.before.val());
    const after = toInt(event.data.after.val());
    if (before === after) return;

    const kind = before === 0 && after === 1 ? 'kickoff' : after === 2 ? 'fulltime' : null;
    if (!kind) return;
    if (!(await claimKey(tid, mid, kind))) return;

    try {
      const matchRef = admin.database().ref(`Tournaments/${tid}/Matches/${mid}`);
      const match = parseMatch((await matchRef.get()).val());
      const names = await loadNames(tid, match);
      const decision = decideStatus({ before, after, match, names, tid, mid });
      if (decision) await sendAlert(decision);
    } catch (err) {
      // Release the claim so a retry can deliver the lost alert.
      await admin.database().ref(`NotificationsMeta/${tid}/${mid}/${kind}`)
        .remove().catch(() => undefined);
      throw err;
    }
  },
);
