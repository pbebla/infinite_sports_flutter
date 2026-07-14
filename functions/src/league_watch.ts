// League game watcher + league prediction scoring (League Experience P3).
// Orchestration only — every decision is pure in lib/league_decide.ts and
// lib/predict.ts. Semantics are copied from the tournament watcher in
// index.ts: 10s goal grace (assist entry), transactional dedupe claims,
// undo/reopen re-arms, claim release on send failure.

import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import { goalKeysToClear, toInt } from './lib/decide';
import {
  decideLeagueGoal, decideLeagueStatus, parseLeagueGame,
} from './lib/league_decide';
import { sendAlert } from './lib/fcm';
import { computeLeaderboardV2, FinalMatch, PredQuestion, QAnswer }
  from './lib/predict';
import { readUserName } from './lib/user_names';

const GOAL_GRACE_MS = 10_000; // scorekeeper enters the assist within ~10s

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Same-instance root (matters in the emulator) — index.ts parity. */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** Path-safe storage key for one league game. MUST stay in parity with fan
 *  lib/misc/league_adapters.dart leaguePredictionMatchKey ('#' is illegal
 *  in RTDB keys, so the in-memory '{date}#{index}' id becomes '{date}_{index}'). */
export function leagueMatchKey(dateKey: string, gameIndex: number | string): string {
  return `${dateKey}_${gameIndex}`;
}

function gamePath(sport: string, season: string, dateKey: string, gameIndex: string): string {
  return `${sport}/${season}/Date/${dateKey}/${gameIndex}`;
}

/** Dedupe meta lives under its own top-level node so league keys can never
 *  collide with tournament ids under NotificationsMeta. */
function metaPath(sport: string, season: string, dateKey: string, gameIndex: string): string {
  return `LeagueNotificationsMeta/${sport}/${season}/${dateKey}/${gameIndex}`;
}

/** Atomically claim a dedupe key (index.ts claimKey parity, incl. the raw
 *  '.sv' sentinel — admin.database.ServerValue is unavailable inside the
 *  emulator's transaction callback). */
async function claimLeagueKey(
  root: Reference, sport: string, season: string,
  dateKey: string, gameIndex: string, key: string,
): Promise<boolean> {
  const ref = root.child(`${metaPath(sport, season, dateKey, gameIndex)}/${key}`);
  const result = await ref.transaction((cur) =>
    cur === null ? { '.sv': 'timestamp' } : undefined);
  return result.committed;
}

// ---- alerts ------------------------------------------------------------------

async function handleLeagueScore(
  sport: string,
  teamTag: 1 | 2,
  event: DatabaseEvent<Change<DataSnapshot>>,
): Promise<void> {
  const season = String(event.params['season']);
  const dateKey = String(event.params['dateKey']);
  const gameIndex = String(event.params['gameIndex']);
  const before = toInt(event.data.before.val());
  const after = toInt(event.data.after.val());
  const root = dbRoot(event);
  const meta = root.child(metaPath(sport, season, dateKey, gameIndex));

  if (after < before) {
    // Undo: re-arm the cleared scores so a corrected goal alerts again.
    await Promise.all(goalKeysToClear(teamTag, before, after)
      .map((k) => meta.child(k).remove()));
    return;
  }
  if (after === before) return;

  // Guard on the state at the moment of the goal, BEFORE the grace window —
  // an "End game" tapped during the wait must not kill the alert. Friendlies
  // bail here, before any claim is burned.
  const gameRef = root.child(gamePath(sport, season, dateKey, gameIndex));
  const pre = parseLeagueGame((await gameRef.get()).val());
  if (pre.status !== 1) return;
  if (pre.stage === 'friendly') return;

  const dedupeKey = `goal_t${teamTag}_${after}`;
  if (!(await claimLeagueKey(root, sport, season, dateKey, gameIndex, dedupeKey))) return;

  try {
    await sleep(GOAL_GRACE_MS); // let the scorekeeper enter the assist

    // Re-read for fresh activity, keep the pre-grace live status.
    const game = parseLeagueGame((await gameRef.get()).val());
    game.status = 1;
    const decision = decideLeagueGoal({
      teamTag, before, after, game, sport, season, dateKey,
      gameIndex: toInt(gameIndex),
    });
    if (decision) {
      await sendAlert(decision);
    } else {
      logger.info('league goal decision was null after grace window',
        { sport, season, dateKey, gameIndex, teamTag, after });
    }
  } catch (err) {
    // Release the claim so a retry can deliver the lost alert.
    await meta.child(dedupeKey).remove().catch(() => undefined);
    throw err;
  }
}

async function handleLeagueStatus(
  sport: string,
  event: DatabaseEvent<Change<DataSnapshot>>,
): Promise<void> {
  const season = String(event.params['season']);
  const dateKey = String(event.params['dateKey']);
  const gameIndex = String(event.params['gameIndex']);
  const before = toInt(event.data.before.val());
  const after = toInt(event.data.after.val());
  if (before === after) return;
  const root = dbRoot(event);
  const meta = root.child(metaPath(sport, season, dateKey, gameIndex));

  // Corrections re-arm the one-shot alerts (index.ts onMatchStatus parity):
  // reopen (2 -> 1) re-arms fulltime; reset (-> 0, incl. L3.2 Reset game)
  // re-arms both. The correction itself stays silent.
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

  const gameRef = root.child(gamePath(sport, season, dateKey, gameIndex));
  const game = parseLeagueGame((await gameRef.get()).val());
  if (game.stage === 'friendly') return; // bail before burning the claim

  if (!(await claimLeagueKey(root, sport, season, dateKey, gameIndex, kind))) return;

  try {
    const decision = decideLeagueStatus({
      before, after, game, sport, season, dateKey, gameIndex: toInt(gameIndex),
    });
    if (decision) await sendAlert(decision);
  } catch (err) {
    await meta.child(kind).remove().catch(() => undefined);
    throw err;
  }
}

// ---- prediction scoring --------------------------------------------------------

/** {qid: raw} -> PredQuestion[] (index.ts recomputeLeaderboard parity). */
function toQuestions(raw: unknown): PredQuestion[] {
  const m = (raw ?? {}) as Record<string, any>;
  return Object.entries(m).map(([qid, q]) => ({
    id: qid,
    type: (q?.Type ?? q?.type ?? 'custom') as PredQuestion['type'],
    points: Number(q?.Points ?? q?.points ?? 0),
    line: (q?.Line ?? q?.line) != null ? Number(q?.Line ?? q?.line) : null,
    stat: q?.Stat ?? q?.stat ?? null,
  }));
}

/** Full idempotent recompute of one league season's prediction leaderboard.
 *  Reuses computeLeaderboardV2 (Predict2 A7) with league paths:
 *  finals = status 2 + Clock.StartedAt > 0 + NOT friendly; questions =
 *  season defaults merged with per-game extras (per-game wins on id clash);
 *  answers under {sport}/{season}/Predictions/{matchKey}. */
export async function recomputeLeagueLeaderboard(
  root: Reference, sport: string, season: string,
): Promise<void> {
  const cfgSnap = await root.child(`${sport}/${season}/PredictionConfig`).get();
  const cfg = (cfgSnap.val() ?? {}) as Record<string, unknown>;
  // Leagues default CLOSED (legacy seasons have no config node) — note the
  // difference from tournaments, which treat an absent config as open.
  if (cfg['Open'] !== true) {
    await root.child(`${sport}/${season}/Leaderboard`).remove();
    return;
  }

  const seasonQSnap = await root.child(`${sport}/${season}/PredictionQuestions`).get();
  const seasonQuestions = toQuestions(seasonQSnap.val());

  const datesSnap = await root.child(`${sport}/${season}/Date`).get();
  const dates = (datesSnap.val() ?? {}) as Record<string, unknown>;

  const finals: FinalMatch[] = [];
  const questionsByMatch: Record<string, PredQuestion[]> = {};
  const resultsByMatch: Record<string, Record<string, string>> = {};

  for (const [dateKey, node] of Object.entries(dates)) {
    // Date nodes hold Lists (normal) or index-keyed Maps (hole collapsing).
    const games: Array<[number, any]> = [];
    if (Array.isArray(node)) {
      node.forEach((g, i) => { if (g) games.push([i, g]); });
    } else if (node && typeof node === 'object') {
      for (const [k, g] of Object.entries(node as Record<string, any>)) {
        const i = Number(k);
        if (Number.isInteger(i) && g) games.push([i, g]);
      }
    }
    for (const [index, g] of games) {
      const status = toInt(g?.status);
      const stage = String(g?.Stage ?? '').trim().toLowerCase();
      const startedAtMs = Number(g?.Clock?.StartedAt ?? 0);
      if (status !== 2 || startedAtMs <= 0 || stage === 'friendly') continue;
      const mid = leagueMatchKey(dateKey, index);
      finals.push({
        id: mid,
        team1Score: toInt(g?.team1score ?? g?.team1Score),
        team2Score: toInt(g?.team2score ?? g?.team2Score),
        startedAtMs,
        team1Activity: g?.team1activity ?? null,
        team2Activity: g?.team2activity ?? null,
      });
      // Season defaults first, then per-game extras (per-game wins by id) —
      // the same merge direction the fan Prediction Room renders.
      const merged = new Map<string, PredQuestion>();
      for (const q of [...seasonQuestions, ...toQuestions(g?.PredictionQuestions)]) {
        merged.set(q.id, q);
      }
      questionsByMatch[mid] = Array.from(merged.values());
      resultsByMatch[mid] = Object.fromEntries(
        Object.entries((g?.PredictionResults ?? {}) as Record<string, any>)
          .map(([qid, opt]) => [qid, String(opt)]));
    }
  }

  const answersByMatch: Record<string, Record<string, Record<string, QAnswer>>> = {};
  const predsSnap = await root.child(`${sport}/${season}/Predictions`).get();
  const predsRaw = (predsSnap.val() ?? {}) as Record<string, any>;
  for (const [mid, byUser] of Object.entries(predsRaw)) {
    if (!byUser || typeof byUser !== 'object') continue;
    const users: Record<string, Record<string, QAnswer>> = {};
    for (const [uid, byQ] of Object.entries(byUser as Record<string, any>)) {
      if (!byQ || typeof byQ !== 'object') continue;
      users[uid] = {};
      for (const [qid, ans] of Object.entries(byQ as Record<string, any>)) {
        const val = ans?.Answer ?? ans?.answer;
        if (val == null) continue;
        users[uid][qid] = {
          value: String(val),
          updatedAt: Number(ans?.UpdatedAt ?? ans?.updatedAt ?? 0),
        };
      }
    }
    answersByMatch[mid] = users;
  }

  const totals = computeLeaderboardV2(finals, questionsByMatch, answersByMatch, resultsByMatch);

  const board: Record<string, { Name: string; Points: number; Exact: number }> = {};
  await Promise.all(Object.entries(totals).map(async ([uid, t]) => {
    board[uid] = { Name: await readUserName(root, uid), Points: t.points, Exact: t.exact };
  }));
  await root.child(`${sport}/${season}/Leaderboard`).set(board);
}

// ---- trigger factory ------------------------------------------------------------

/** All league triggers for ONE sport, ready for a grouped export from
 *  index.ts (deploys as e.g. leagueFutsal-onTeam1Score). P4 adds
 *  basketball / flag football with one export line each. */
export function makeLeagueTriggers(sport: string) {
  const base = `/${sport}/{season}/Date/{dateKey}/{gameIndex}`;
  const recompute = async (event: DatabaseEvent<Change<DataSnapshot>>) => {
    await recomputeLeagueLeaderboard(dbRoot(event), sport, String(event.params['season']));
  };
  return {
    // Watcher (pushes)
    onTeam1Score: onValueWritten(`${base}/team1score`, (e) => handleLeagueScore(sport, 1, e)),
    onTeam2Score: onValueWritten(`${base}/team2score`, (e) => handleLeagueScore(sport, 2, e)),
    onStatus: onValueWritten(`${base}/status`, (e) => handleLeagueStatus(sport, e)),
    // Prediction scoring (leaderboard recompute) — tournament onPredict* parity
    onPredictStatus: onValueWritten(`${base}/status`, recompute),
    onPredictScore1: onValueWritten(`${base}/team1score`, recompute),
    onPredictScore2: onValueWritten(`${base}/team2score`, recompute),
    onPredictResult: onValueWritten(`${base}/PredictionResults/{qid}`, recompute),
    onPredictMatchQuestion: onValueWritten(`${base}/PredictionQuestions/{qid}`, recompute),
    onPredictQuestion: onValueWritten(`/${sport}/{season}/PredictionQuestions/{qid}`, recompute),
  };
}
