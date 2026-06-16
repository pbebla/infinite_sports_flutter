export interface PredQuestion {
  id: string;
  type: 'matchWinner' | 'correctScore' | 'totalGoals' | 'custom';
  points: number;
  line: number | null;
}
export interface QAnswer { value: string; updatedAt: number }
export interface QScore { correct: boolean; points: number; isExactScore: boolean }

export function questionPoints(
  q: PredQuestion, answer: string, a1: number, a2: number, customResult: string | null,
): QScore {
  let correct = false, exact = false;
  switch (q.type) {
    case 'matchWinner': {
      const res = a1 > a2 ? 'team1' : a1 < a2 ? 'team2' : 'draw';
      correct = answer === res; break;
    }
    case 'correctScore':
      correct = answer === `${a1}-${a2}`; exact = correct; break;
    case 'totalGoals': {
      const line = q.line ?? 2.5;
      correct = answer === ((a1 + a2) > line ? 'over' : 'under'); break;
    }
    case 'custom':
      correct = customResult != null && answer === customResult; break;
  }
  return { correct, points: correct ? q.points : 0, isExactScore: exact };
}

export function computeLeaderboardV2(
  finals: FinalMatch[],
  questionsByMatch: Record<string, PredQuestion[]>,
  answersByMatch: Record<string, Record<string, Record<string, QAnswer>>>,
  resultsByMatch: Record<string, Record<string, string>>,
): Record<string, { points: number; exact: number }> {
  const out: Record<string, { points: number; exact: number }> = {};
  for (const m of finals) {
    const qs = questionsByMatch[m.id] ?? [];
    const users = answersByMatch[m.id] ?? {};
    const results = resultsByMatch[m.id] ?? {};
    for (const [uid, byQ] of Object.entries(users)) {
      for (const q of qs) {
        const ans = byQ[q.id];
        if (!ans || !(ans.updatedAt < m.startedAtMs)) continue;
        const r = questionPoints(q, ans.value, m.team1Score, m.team2Score, results[q.id] ?? null);
        if (r.points === 0 && !r.correct) continue;
        const cur = out[uid] ?? { points: 0, exact: 0 };
        cur.points += r.points;
        if (r.isExactScore) cur.exact += 1;
        out[uid] = cur;
      }
    }
  }
  for (const uid of Object.keys(out)) if (out[uid].points === 0) delete out[uid];
  return out;
}

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
  // Leaderboard shows scorers only: drop users who qualified but earned nothing
  // (also clears users whose total dropped to 0 after a score correction/reopen).
  for (const uid of Object.keys(out)) {
    if (out[uid].points === 0) delete out[uid];
  }
  return out;
}
