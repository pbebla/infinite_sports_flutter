import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import {
  decideGoal, decideStatus, goalKeysToClear, parseMatch, toInt,
} from './lib/decide';
import { loadNames } from './lib/names';
import { sendAlert } from './lib/fcm';
import { computeLeaderboardV2, FinalMatch, PredQuestion, QAnswer }
  from './lib/predict';

admin.initializeApp();

const GOAL_GRACE_MS = 10_000; // Scorekeepers typically enter the assist within ~10s of the goal; the alert waits so it can include the assist credit.

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Return the root of the database that fired this trigger.
 *  Using event.data.before.ref.root ensures we stay in the same RTDB instance
 *  and namespace, which matters in the emulator (demo project + custom ns). */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

async function readUserName(root: Reference, uid: string): Promise<string> {
  try {
    const [f, l] = await Promise.all([
      root.child(`Users/${uid}/First Name`).get(),
      root.child(`Users/${uid}/Last Name`).get(),
    ]);
    const name = `${f.val() ?? ''} ${l.val() ?? ''}`.trim();
    return name.length > 0 ? name : 'Player';
  } catch {
    return 'Player';
  }
}

async function recomputeLeaderboard(root: Reference, tid: string): Promise<void> {
  const cfgSnap = await root.child(`Tournaments/${tid}/PredictionConfig`).get();
  const cfg = (cfgSnap.val() ?? {}) as Record<string, unknown>;
  if (cfg['Open'] === false) {
    await root.child(`Tournaments/${tid}/Leaderboard`).remove();
    return;
  }

  // Build the list of final matches (Status==2 with a known kick-off time)
  const matchesSnap = await root.child(`Tournaments/${tid}/Matches`).get();
  const matches = (matchesSnap.val() ?? {}) as Record<string, any>;
  const finals: FinalMatch[] = [];
  for (const [mid, m] of Object.entries(matches)) {
    const status = Number(m?.Status ?? m?.status ?? 0);
    const startedAtMs = Number(m?.Clock?.StartedAt ?? m?.clock?.startedAt ?? 0);
    if (status === 2 && startedAtMs > 0) {
      finals.push({
        id: mid,
        team1Score: Number(m?.Team1Score ?? m?.team1Score ?? 0),
        team2Score: Number(m?.Team2Score ?? m?.team2Score ?? 0),
        startedAtMs,
      });
    }
  }

  // Read tournament-wide default questions once
  const tQSnap = await root.child(`Tournaments/${tid}/PredictionQuestions`).get();
  const tQRaw = (tQSnap.val() ?? {}) as Record<string, any>;
  const tournamentQuestions: PredQuestion[] = Object.entries(tQRaw).map(([qid, q]) => ({
    id: qid,
    type: (q?.Type ?? q?.type ?? 'custom') as PredQuestion['type'],
    points: Number(q?.Points ?? q?.points ?? 0),
    line: (q?.Line ?? q?.line) != null ? Number(q?.Line ?? q?.line) : null,
  }));

  // Build per-match question lists, results, and answers
  const questionsByMatch: Record<string, PredQuestion[]> = {};
  const resultsByMatch: Record<string, Record<string, string>> = {};
  const answersByMatch: Record<string, Record<string, Record<string, QAnswer>>> = {};

  await Promise.all(finals.map(async (f) => {
    // Per-match extra questions (merged with tournament defaults)
    const mQSnap = await root.child(`Tournaments/${tid}/Matches/${f.id}/PredictionQuestions`).get();
    const mQRaw = (mQSnap.val() ?? {}) as Record<string, any>;
    const matchQs: PredQuestion[] = Object.entries(mQRaw).map(([qid, q]) => ({
      id: qid,
      type: (q?.Type ?? q?.type ?? 'custom') as PredQuestion['type'],
      points: Number(q?.Points ?? q?.points ?? 0),
      line: (q?.Line ?? q?.line) != null ? Number(q?.Line ?? q?.line) : null,
    }));
    // Merge: tournament defaults first, then per-match extras (per-match overrides by id)
    const merged = new Map<string, PredQuestion>();
    for (const q of [...tournamentQuestions, ...matchQs]) merged.set(q.id, q);
    questionsByMatch[f.id] = Array.from(merged.values());

    // Owner-set results for custom questions: {qid: optionId}
    const resSnap = await root.child(`Tournaments/${tid}/Matches/${f.id}/PredictionResults`).get();
    const resRaw = (resSnap.val() ?? {}) as Record<string, any>;
    resultsByMatch[f.id] = Object.fromEntries(
      Object.entries(resRaw).map(([qid, opt]) => [qid, String(opt)]),
    );

    // Per-question answers: Predictions/{mid}/{uid}/{qid} = {Answer, UpdatedAt}
    const predSnap = await root.child(`Tournaments/${tid}/Predictions/${f.id}`).get();
    const predRaw = (predSnap.val() ?? {}) as Record<string, any>;
    const byUser: Record<string, Record<string, QAnswer>> = {};
    for (const [uid, byQ] of Object.entries(predRaw)) {
      if (!byQ || typeof byQ !== 'object') continue;
      byUser[uid] = {};
      for (const [qid, ans] of Object.entries(byQ as Record<string, any>)) {
        if (!ans || typeof ans !== 'object') continue;
        const val = ans?.Answer ?? ans?.answer;
        if (val == null) continue;
        byUser[uid][qid] = {
          value: String(val),
          updatedAt: Number(ans?.UpdatedAt ?? ans?.updatedAt ?? 0),
        };
      }
    }
    answersByMatch[f.id] = byUser;
  }));

  const totals = computeLeaderboardV2(finals, questionsByMatch, answersByMatch, resultsByMatch);

  const board: Record<string, { Name: string; Points: number; Exact: number }> = {};
  await Promise.all(Object.entries(totals).map(async ([uid, t]) => {
    board[uid] = { Name: await readUserName(root, uid), Points: t.points, Exact: t.exact };
  }));
  await root.child(`Tournaments/${tid}/Leaderboard`).set(board);
}

/** Atomically claim a dedupe key. Returns false if someone already claimed it. */
async function claimKey(
  root: Reference, tid: string, mid: string, key: string,
): Promise<boolean> {
  const ref = root.child(`NotificationsMeta/${tid}/${mid}/${key}`);
  // Use the raw sentinel object instead of admin.database.ServerValue.TIMESTAMP
  // because the emulator shims admin.database and the property is not available
  // inside a transaction callback (it resolves to undefined in that context).
  const result = await ref.transaction((cur) =>
    cur === null ? { '.sv': 'timestamp' } : undefined);
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
  const root = dbRoot(event);

  if (after < before) {
    // Undo: re-arm the cleared scores so a corrected goal alerts again.
    const meta = root.child(`NotificationsMeta/${tid}/${mid}`);
    await Promise.all(goalKeysToClear(teamTag, before, after)
      .map((k) => meta.child(k).remove()));
    return;
  }
  if (after === before) return;

  // Guard on the match state at the moment of the goal, BEFORE the grace
  // window — an "End match" tapped during the wait must not kill the alert.
  const matchRef = root.child(`Tournaments/${tid}/Matches/${mid}`);
  const preMatch = parseMatch((await matchRef.get()).val());
  if (preMatch.status !== 1) return;

  const dedupeKey = `goal_t${teamTag}_${after}`;
  if (!(await claimKey(root, tid, mid, dedupeKey))) return;

  try {
    await sleep(GOAL_GRACE_MS); // let the scorekeeper enter the assist

    // Re-read for fresh activity (scorer + assist), keep pre-grace live status.
    const match = parseMatch((await matchRef.get()).val());
    match.status = 1;
    const names = await loadNames(root, tid, match);
    const decision = decideGoal({ teamTag, before, after, match, names, tid, mid });
    if (decision) {
      await sendAlert(decision);
    } else {
      logger.info('goal decision was null after grace window', { tid, mid, teamTag, after });
    }
  } catch (err) {
    // Release the claim so a retry can deliver the lost alert.
    await root.child(`NotificationsMeta/${tid}/${mid}/${dedupeKey}`)
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
    const root = dbRoot(event);

    // Corrections re-arm the one-shot alerts, mirroring the goal re-arm on
    // score undo: reopening a finished match (2 -> 1) re-arms full time, and
    // resetting to pending (-> 0) re-arms both, so the eventual real kickoff
    // and full time still alert. The correction itself stays silent.
    const meta = root.child(`NotificationsMeta/${tid}/${mid}`);
    if (before === 2 && after === 1) {
      await meta.child('fulltime').remove();
      return;
    }
    if (after === 0) {
      await Promise.all([
        meta.child('kickoff').remove(),
        meta.child('fulltime').remove(),
      ]);
      return;
    }

    const kind = before === 0 && after === 1 ? 'kickoff' : after === 2 ? 'fulltime' : null;
    if (!kind) return;
    if (!(await claimKey(root, tid, mid, kind))) return;

    try {
      const matchRef = root.child(`Tournaments/${tid}/Matches/${mid}`);
      const match = parseMatch((await matchRef.get()).val());
      const names = await loadNames(root, tid, match);
      const decision = decideStatus({ before, after, match, names, tid, mid });
      if (decision) await sendAlert(decision);
    } catch (err) {
      // Release the claim so a retry can deliver the lost alert.
      await root.child(`NotificationsMeta/${tid}/${mid}/${kind}`)
        .remove().catch(() => undefined);
      throw err;
    }
  },
);

export const onPredictMatchStatus = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Status',
  async (event) => {
    await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string);
  },
);

export const onPredictTeam1Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team1Score',
  async (event) => {
    await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string);
  },
);

export const onPredictTeam2Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team2Score',
  async (event) => {
    await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string);
  },
);

export const onPredictResult = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/PredictionResults/{qid}',
  async (event) => { await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string); },
);

export const onPredictQuestion = onValueWritten(
  '/Tournaments/{tid}/PredictionQuestions/{qid}',
  async (event) => { await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string); },
);
