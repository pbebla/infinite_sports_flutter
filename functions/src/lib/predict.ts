export interface PredScoring { matchWinner: number; exactScore: number }

export interface FinalMatch {
  id: string;
  team1Score: number;
  team2Score: number;
  startedAtMs: number; // kickoff; predictions must predate this to count
}

export interface UserPrediction {
  uid: string;
  team1: number;
  team2: number;
  updatedAt: number;
}

export interface PredResult { resultCorrect: boolean; exactCorrect: boolean; points: number }

export function predictionPoints(
  p1: number, p2: number, a1: number, a2: number, s: PredScoring,
): PredResult {
  const resultCorrect = Math.sign(p1 - p2) === Math.sign(a1 - a2);
  const exactCorrect = p1 === a1 && p2 === a2;
  const points = (resultCorrect ? s.matchWinner : 0) + (exactCorrect ? s.exactScore : 0);
  return { resultCorrect, exactCorrect, points };
}

/** Full recompute of a tournament's prediction leaderboard. Idempotent. */
export function computeLeaderboard(
  finals: FinalMatch[],
  predsByMatch: Record<string, UserPrediction[]>,
  scoring: PredScoring,
): Record<string, { points: number; exact: number }> {
  const out: Record<string, { points: number; exact: number }> = {};
  for (const m of finals) {
    const preds = predsByMatch[m.id] ?? [];
    for (const p of preds) {
      if (!(p.updatedAt < m.startedAtMs)) continue; // fairness: predate kickoff
      const r = predictionPoints(p.team1, p.team2, m.team1Score, m.team2Score, scoring);
      const cur = out[p.uid] ?? { points: 0, exact: 0 };
      cur.points += r.points;
      if (r.exactCorrect) cur.exact += 1;
      out[p.uid] = cur;
    }
  }
  return out;
}
