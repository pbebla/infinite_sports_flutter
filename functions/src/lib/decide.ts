// Pure decision logic for the notification Watcher. No Firebase imports —
// everything here is unit-testable with plain objects.

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

/** One consistent brand tint for the small-icon logo on every alert —
 *  the title emoji (🟢/⚽/🏁) carries the alert type instead (owner choice). */
export const ALERT_COLORS = {
  goal: '#D00000',
  kickoff: '#D00000',
  fulltime: '#D00000',
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

// ---- scorer / assist pairing ----

const SCORER_EVENTS = new Set(['goal', 'penalty goal']);

interface MinuteEvent { minute: number; eventType: string; player: string }

function bucketEvents(bucket: unknown, minute: number): MinuteEvent[] {
  const list = Array.isArray(bucket)
    ? bucket
    : (bucket && typeof bucket === 'object' ? Object.values(bucket) : []);
  const out: MinuteEvent[] = [];
  for (const ev of list) {
    if (!ev || typeof ev !== 'object') continue;
    const entries = Object.entries(ev as Record<string, unknown>);
    if (!entries.length) continue;
    // The Manager app writes each activity event as a single-entry {EventType: PlayerName}
    // map, so only the first entry is meaningful.
    const [type, player] = entries[0];
    out.push({ minute, eventType: type.toLowerCase().trim(), player: String(player) });
  }
  return out;
}

function allEvents(activity: Record<string, unknown> | null): MinuteEvent[] {
  if (!activity) return [];
  return Object.entries(activity)
    .map(([k, v]) => ({ minute: toInt(k), bucket: v }))
    .sort((a, b) => a.minute - b.minute)
    .flatMap(({ minute, bucket }) => bucketEvents(bucket, minute));
}

/** Newest goal-type event, plus an assist in the same or next minute. */
function findScorerAndAssist(activity: Record<string, unknown> | null):
    { scorer: MinuteEvent | null; assist: MinuteEvent | null } {
  const events = allEvents(activity);
  const scorer = [...events].reverse().find((e) => SCORER_EVENTS.has(e.eventType)) ?? null;
  if (!scorer) return { scorer: null, assist: null };
  const assist = [...events].reverse().find((e) =>
    e.eventType === 'assist' &&
    (e.minute === scorer.minute || e.minute === scorer.minute + 1)) ?? null;
  return { scorer, assist };
}

// ---- decisions ----

export function decideGoal(args: {
  teamTag: 1 | 2; before: number; after: number;
  match: MatchContext; names: Names; tid: string; mid: string;
}): AlertDecision | null {
  const { teamTag, before, after, match, names, tid, mid } = args;
  if (after <= before) return null;
  if (match.status !== 1) return null;

  const scoringTeamName = teamTag === 1 ? names.team1 : names.team2;
  const activity = teamTag === 1 ? match.team1Activity : match.team2Activity;
  const { scorer, assist } = findScorerAndAssist(activity);

  let body = '';
  if (scorer) {
    body = `${scorer.player} (${scoringTeamName}) ${scorer.minute}'`;
    if (assist) body += ` · Assist: ${assist.player}`;
  }

  return {
    kind: 'goal',
    dedupeKey: `goal_t${teamTag}_${after}`,
    title: `⚽ GOAL! ${names.team1} ${match.team1Score} – ${match.team2Score} ${names.team2}`,
    body,
    condition: buildCondition(tid, match.team1Id, match.team2Id),
    color: ALERT_COLORS.goal,
    data: { type: 'goal', tournamentId: tid, matchId: mid },
  };
}

export function decideStatus(args: {
  before: number; after: number;
  match: MatchContext; names: Names; tid: string; mid: string;
}): AlertDecision | null {
  const { before, after, match, names, tid, mid } = args;
  if (before === after) return null;
  const condition = buildCondition(tid, match.team1Id, match.team2Id);

  if (before === 0 && after === 1) {
    return {
      kind: 'kickoff',
      dedupeKey: 'kickoff',
      title: `🟢 Kickoff: ${names.team1} vs ${names.team2}`,
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
      title: `🏁 Full time: ${names.team1} ${match.team1Score} – ${match.team2Score} ${names.team2}`,
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
