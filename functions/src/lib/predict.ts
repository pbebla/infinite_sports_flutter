export interface PredQuestion {
  id: string;
  type: 'matchWinner' | 'correctScore' | 'totalGoals' | 'custom' | 'playerAward';
  points: number;
  line: number | null;
  stat?: 'goals' | 'assists' | 'saves' | 'dpl' | string;
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

/** Per-player derived counters for ONE match, mirroring
 *  lib/misc/single_match_tallies.dart's MatchPlayerTally exactly (same
 *  event-type tokens, same Catch % >=3-target gate). [sport] defaults to
 *  'Soccer' so every existing (3-arg) call site keeps behaving unchanged. */
export function matchStatLeaders(
  team1Activity: unknown, team2Activity: unknown, stat: string,
  sport = 'Soccer',
): string[] {
  const counts: Record<string, Record<string, number>> = {};
  const bumpKey = (player: string, key: string, by = 1) => {
    const c = counts[player] ?? (counts[player] = {});
    c[key] = (c[key] ?? 0) + by;
  };

  const applyEvent = (type: string, player: string) => {
    const t = type.toLowerCase().trim();
    switch (sport) {
      case 'Basketball':
        switch (t) {
          case 'onepointer': bumpKey(player, 'points', 1); break;
          case 'twopointer': bumpKey(player, 'points', 2); break;
          case 'threepointer': bumpKey(player, 'points', 3); break;
          case 'rebound': bumpKey(player, 'rebounds'); break;
          case 'assist': bumpKey(player, 'assists'); break;
          case 'steal': bumpKey(player, 'steals'); break;
          case 'block': bumpKey(player, 'blocks'); break;
          default: break;
        }
        return;
      case 'Flag Football':
        switch (t) {
          case 'receiving td':
          case 'rushing td':
          case 'int td':
            bumpKey(player, 'touchdowns');
            break;
          case 'pass td': bumpKey(player, 'passTouchdowns'); break;
          case 'rec': bumpKey(player, 'receptions'); break;
          case 'recmiss': bumpKey(player, 'recMisses'); break;
          case 'interception': bumpKey(player, 'interceptions'); break;
          case 'fp': bumpKey(player, 'flagPulls'); break;
          case 'sack': bumpKey(player, 'sacks'); break;
          default: break;
        }
        return;
      default: { // Soccer / Futsal — unchanged mapping.
        let key: string | null = null;
        if (t === 'goal' || t === 'penalty goal' || t === 'pengoal') key = 'goals';
        else if (t === 'assist') key = 'assists';
        else if (t === 'save' || t === 'penalty saved' || t === 'pensaved') key = 'saves';
        else if (t === 'dpl') key = 'dpl';
        if (key) bumpKey(player, key);
      }
    }
  };

  const addEntry = (entry: unknown) => {
    if (entry && typeof entry === 'object') {
      for (const [k, v] of Object.entries(entry as Record<string, unknown>)) {
        if (k === '_t') continue;
        applyEvent(k, String(v));
      }
    }
  };
  const scan = (activity: unknown) => {
    if (!activity || typeof activity !== 'object') return;
    for (const bucket of Object.values(activity as Record<string, unknown>)) {
      if (Array.isArray(bucket)) bucket.forEach(addEntry);
      else if (bucket && typeof bucket === 'object') Object.values(bucket as Record<string, unknown>).forEach(addEntry);
    }
  };
  scan(team1Activity);
  scan(team2Activity);

  const valueFor = (player: string): number => {
    const c = counts[player] ?? {};
    if (stat === 'catchPercentage') {
      const rec = c['receptions'] ?? 0;
      const miss = c['recMisses'] ?? 0;
      const targets = rec + miss;
      if (targets < 3) return 0; // gated — mirrors the Dart minTargets:3
      return Math.round((rec / targets) * 100);
    }
    return c[stat] ?? 0;
  };

  let max = 0;
  for (const player of Object.keys(counts)) {
    const v = valueFor(player);
    if (v > max) max = v;
  }
  if (max === 0) return [];
  return Object.keys(counts).filter((p) => valueFor(p) === max);
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
        if (q.type === 'playerAward') {
          const leaders = matchStatLeaders(
            m.team1Activity, m.team2Activity, q.stat ?? 'goals', m.sport ?? 'Soccer');
          if (leaders.includes(ans.value)) {
            const cur = out[uid] ?? { points: 0, exact: 0 };
            cur.points += q.points;
            out[uid] = cur;
          }
          continue;
        }
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
  team1Activity?: unknown;
  team2Activity?: unknown;
  sport?: string;
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
