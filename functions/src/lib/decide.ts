// Pure decision logic for the notification Watcher. No Firebase imports —
// everything here is unit-testable with plain objects.

import {
  vocabFor, findScorerAndPair, newestOwnGoal,
} from './league_decide';

export interface MatchContext {
  team1Id: string | null;
  team2Id: string | null;
  team1Score: number;
  team2Score: number;
  status: number; // 0 pending, 1 live, 2 finished
  team1Activity: Record<string, unknown> | null;
  team2Activity: Record<string, unknown> | null;
  matchLocation: string | null;
}

export interface Names { tournament: string; team1: string; team2: string }

export interface AlertDecision {
  kind: 'goal' | 'kickoff' | 'fulltime';
  dedupeKey: string;
  title: string;
  body: string;
  condition: string;
  /** Android accent color so each alert type is recognizable at a glance. */
  color: string;
  data: { type: string; tournamentId: string; matchId: string };
}

/** One consistent black disc for the small-icon logo on every alert —
 *  the title emoji (🟢/⚽/🏁) carries the alert type instead (owner choice). */
export const ALERT_COLORS = {
  goal: '#000000',
  kickoff: '#000000',
  fulltime: '#000000',
} as const;

// ---- topics (MUST stay in parity with lib/misc/notification_topics.dart) ----

export function sanitizeId(id: string): string {
  return id.replace(/[^A-Za-z0-9_-]/g, '_');
}

export function tournamentTopic(tournamentId: string): string {
  return `tournament_${sanitizeId(tournamentId)}`;
}

export function teamTopic(tournamentId: string, teamId: string): string {
  return `tournament_${sanitizeId(tournamentId)}_team_${sanitizeId(teamId)}`;
}

export function buildCondition(
  tid: string, team1Id: string | null, team2Id: string | null,
): string {
  const topics = [tournamentTopic(tid)];
  if (team1Id) topics.push(teamTopic(tid, team1Id));
  if (team2Id) topics.push(teamTopic(tid, team2Id));
  return topics.map((t) => `'${t}' in topics`).join(' || ');
}

// ---- parsing (tolerates PascalCase/camelCase and array-with-holes) ----

function firstNonNull(data: Record<string, unknown>, keys: string[]): unknown {
  for (const k of keys) {
    if (data[k] !== undefined && data[k] !== null) return data[k];
  }
  return null;
}

export function toInt(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function toStringOrNull(v: unknown): string | null {
  return v === null || v === undefined ? null : String(v);
}

/** RTDB returns near-contiguous int-keyed maps as arrays with null holes.
 *  Normalize to a minute->bucket record either way. */
function normalizeBuckets(raw: unknown): Record<string, unknown> | null {
  if (raw === null || raw === undefined) return null;
  if (Array.isArray(raw)) {
    const out: Record<string, unknown> = {};
    raw.forEach((v, i) => { if (v !== null && v !== undefined) out[String(i)] = v; });
    return Object.keys(out).length ? out : null;
  }
  if (typeof raw === 'object') return raw as Record<string, unknown>;
  return null;
}

export function parseMatch(raw: unknown): MatchContext {
  const d = (raw ?? {}) as Record<string, unknown>;
  return {
    team1Id: toStringOrNull(firstNonNull(d, ['Team1Id', 'team1Id'])),
    team2Id: toStringOrNull(firstNonNull(d, ['Team2Id', 'team2Id'])),
    team1Score: toInt(firstNonNull(d, ['Team1Score', 'team1Score'])),
    team2Score: toInt(firstNonNull(d, ['Team2Score', 'team2Score'])),
    status: toInt(firstNonNull(d, ['Status', 'status'])),
    team1Activity: normalizeBuckets(firstNonNull(d, ['Team1Activity', 'team1Activity'])),
    team2Activity: normalizeBuckets(firstNonNull(d, ['Team2Activity', 'team2Activity'])),
    matchLocation: toStringOrNull(firstNonNull(d, ['MatchLocation', 'matchLocation'])),
  };
}

// ---- P4: tournament activity spelling bridge ----------------------------
// Bridges the two legacy TOURNAMENT-only spaced spellings ('penalty goal',
// 'own goal') to the compact league token ('pengoal', 'owngoal') that the
// shared SPORT_VOCAB recognizes. New capture (Manager P2) already writes
// canonical spellings, and every other legacy spelling case-folds for free
// via findScorerAndPair's own lowercasing — only these two need bridging.

const LEGACY_TOURNAMENT_EVENT_SPELLINGS: Record<string, string> = {
  'penalty goal': 'pengoal',
  'own goal': 'owngoal',
};

function remapLeafKey(key: string): string {
  const lower = key.toLowerCase().trim();
  return LEGACY_TOURNAMENT_EVENT_SPELLINGS[lower] ?? key;
}

function remapLeaf(leaf: unknown): unknown {
  if (!leaf || typeof leaf !== 'object') return leaf;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(leaf as Record<string, unknown>)) {
    out[remapLeafKey(k)] = v;
  }
  return out;
}

function remapBucket(bucket: unknown): unknown {
  if (Array.isArray(bucket)) return bucket.map(remapLeaf);
  if (bucket && typeof bucket === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(bucket as Record<string, unknown>)) {
      out[k] = remapLeaf(v);
    }
    return out;
  }
  return bucket;
}

/** Pure, exported for direct unit testing. Preserves every other key
 *  (including `_t` insertion stamps) untouched. */
export function canonicalizeTournamentActivity(
  activity: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!activity) return activity;
  const out: Record<string, unknown> = {};
  for (const [minute, bucket] of Object.entries(activity)) {
    out[minute] = remapBucket(bucket);
  }
  return out;
}

// ---- decisions ----

export function decideGoal(args: {
  teamTag: 1 | 2; before: number; after: number;
  match: MatchContext; names: Names; tid: string; mid: string; sport: string;
}): AlertDecision | null {
  const { teamTag, before, after, match, names, tid, mid, sport } = args;
  if (after <= before) return null;
  if (match.status !== 1) return null;

  const scoringTeamName = teamTag === 1 ? names.team1 : names.team2;
  const rawActivity = teamTag === 1 ? match.team1Activity : match.team2Activity;
  const rawOpposing = teamTag === 1 ? match.team2Activity : match.team1Activity;
  const activity = canonicalizeTournamentActivity(rawActivity);
  const opposing = canonicalizeTournamentActivity(rawOpposing);

  const vocab = vocabFor(sport);
  const { scorer, pair } = findScorerAndPair(activity, vocab);

  let body = '';
  if (scorer) {
    body = `${scorer.player} (${scoringTeamName}) ${scorer.minute}'`;
    if (pair) body += ` · ${vocab.pairLabel}: ${pair.player}`;
  } else if (vocab.ownGoalFallback) {
    const og = newestOwnGoal(opposing);
    if (og) body = `Own goal · ${og.player} ${og.minute}'`;
  }

  const title =
    scorer && vocab.tdTitle && vocab.tdEvents.has(scorer.eventType)
      ? vocab.tdTitle(names.team1, match.team1Score, match.team2Score, names.team2)
      : vocab.goalTitle(names.team1, match.team1Score, match.team2Score, names.team2);

  return {
    kind: 'goal',
    dedupeKey: `goal_t${teamTag}_${after}`,
    title,
    body,
    condition: buildCondition(tid, match.team1Id, match.team2Id),
    color: ALERT_COLORS.goal,
    data: { type: 'goal', tournamentId: tid, matchId: mid },
  };
}

export function decideStatus(args: {
  before: number; after: number;
  match: MatchContext; names: Names; tid: string; mid: string; sport: string;
}): AlertDecision | null {
  const { before, after, match, names, tid, mid, sport } = args;
  if (before === after) return null;
  const condition = buildCondition(tid, match.team1Id, match.team2Id);
  const vocab = vocabFor(sport);

  if (before === 0 && after === 1) {
    return {
      kind: 'kickoff',
      dedupeKey: 'kickoff',
      title: `${vocab.kickoffPrefix} ${names.team1} vs ${names.team2}`,
      body: match.matchLocation
        ? `Now playing — ${match.matchLocation}`
        : 'Now playing — follow it live!',
      condition,
      color: ALERT_COLORS.kickoff,
      data: { type: 'kickoff', tournamentId: tid, matchId: mid },
    };
  }

  if (after === 2) {
    return {
      kind: 'fulltime',
      dedupeKey: 'fulltime',
      title: `${vocab.fulltimePrefix} ${names.team1} ${match.team1Score} – ${match.team2Score} ${names.team2}`,
      body: '',
      condition,
      color: ALERT_COLORS.fulltime,
      data: { type: 'fulltime', tournamentId: tid, matchId: mid },
    };
  }

  return null; // reopen (2->1), reset (1->0), or anything else: silence
}

/** Keys to delete when a score DECREASES, so a re-recorded goal alerts again.
 *  (teamTag: which team's counter, oldScore: score before the undo,
 *  newScore: score after the undo.) Returns keys for newScore+1..oldScore. */
export function goalKeysToClear(
  teamTag: 1 | 2, oldScore: number, newScore: number,
): string[] {
  const keys: string[] = [];
  for (let n = newScore + 1; n <= oldScore; n++) keys.push(`goal_t${teamTag}_${n}`);
  return keys;
}
