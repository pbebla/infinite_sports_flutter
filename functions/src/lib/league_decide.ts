// Pure decision logic for the LEAGUE notification watcher (League Experience
// P3). No Firebase imports — unit-testable with plain objects. Mirrors
// lib/decide.ts (tournaments); the league differences:
//  - game teams are NAMES on the node (team1/team2), possibly bracket
//    placeholders ('Winner of SF1') that nobody can follow;
//  - score/status keys are lowercase (team1score/team2score/status);
//  - activity minute keys carry a trailing apostrophe ("12'") and every
//    entry carries a `_t` insertion stamp that is NOT the event type;
//  - exhibition games (Stage 'friendly') must stay silent for EVERY kind.

import { sanitizeId, toInt } from './decide';

export interface LeagueGameContext {
  team1: string | null;
  team2: string | null;
  team1Score: number;
  team2Score: number;
  status: number; // 0 pending, 1 live, 2 finished
  stage: string;  // '' regular season; 'friendly' never alerts
  team1Activity: Record<string, unknown> | null;
  team2Activity: Record<string, unknown> | null;
  location: string | null; // Location/Venue when present
}

export interface LeagueAlertDecision {
  kind: 'goal' | 'kickoff' | 'fulltime';
  dedupeKey: string;
  title: string;
  body: string;
  condition: string;
  color: string;
  data: {
    type: string; sport: string; season: string;
    dateKey: string; gameIndex: string;
  };
}

const ALERT_COLOR = '#000000'; // one black disc, tournament parity

// ---- topics ----------------------------------------------------------------
// MUST stay in parity with fan lib/misc/notification_topics.dart
// leagueTeamTopic (P2): 'league_{sport}_{season}_team_{team}' and
// leagueSeasonTopic (P3.3): 'league_{sport}_{season}', each part through the
// same sanitizer the tournament topics use.

export function leagueSeasonTopic(sport: string, season: string): string {
  return `league_${sanitizeId(sport)}_${sanitizeId(season)}`;
}

export function leagueTeamTopic(
  sport: string, season: string, teamName: string,
): string {
  return `league_${sanitizeId(sport)}_${sanitizeId(season)}_team_${sanitizeId(teamName)}`;
}

/** Bracket placeholder names — nobody can follow these. Parity with fan
 *  lib/misc/schedule_display.dart isPlaceholderTeam. */
export function isPlaceholderTeam(name: string): boolean {
  return name.startsWith('Winner of ') || name.startsWith('Loser of ');
}

/** FCM condition: the season-wide topic (P3.3 league follow bell) plus each
 *  followable team topic — 3 terms max, well under FCM's 5-term limit.
 *
 *  P3.3 silence-rule change: the season topic alone justifies sending, so a
 *  game whose teams are both bracket placeholders STILL alerts season
 *  followers (it is a real game whose names lag data entry). Returns null —
 *  callers stay silent — ONLY for a malformed node with no team names at
 *  all. (Friendlies are gated separately by the decide functions.) */
export function buildLeagueCondition(
  sport: string, season: string,
  team1: string | null, team2: string | null,
): string | null {
  const named = [team1, team2].filter(
    (t): t is string => !!t && t.trim().length > 0);
  if (!named.length) return null; // malformed: not a real game
  const topics: string[] = [leagueSeasonTopic(sport, season)];
  for (const t of named) {
    if (!isPlaceholderTeam(t)) topics.push(leagueTeamTopic(sport, season, t));
  }
  return topics.map((t) => `'${t}' in topics`).join(' || ');
}

// ---- parsing ----------------------------------------------------------------

function str(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const s = String(v);
  return s.length ? s : null;
}

function normalizeActivity(raw: unknown): Record<string, unknown> | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'object' && !Array.isArray(raw)) {
    return Object.keys(raw as object).length
      ? (raw as Record<string, unknown>) : null;
  }
  // League activity is minute-KEYED ("12'"), so arrays only appear when a
  // node is empty/malformed — treat as no activity.
  return null;
}

function parseLocationVenue(raw: unknown): string | null {
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return str((raw as Record<string, unknown>)['Venue']
      ?? (raw as Record<string, unknown>)['venue']);
  }
  return null;
}

export function parseLeagueGame(raw: unknown): LeagueGameContext {
  const d = (raw ?? {}) as Record<string, unknown>;
  return {
    team1: str(d['team1']),
    team2: str(d['team2']),
    team1Score: toInt(d['team1score'] ?? d['team1Score']),
    team2Score: toInt(d['team2score'] ?? d['team2Score']),
    status: toInt(d['status']),
    stage: (d['Stage'] ?? '').toString().trim().toLowerCase(),
    team1Activity: normalizeActivity(d['team1activity']),
    team2Activity: normalizeActivity(d['team2activity']),
    location: parseLocationVenue(d['Location']),
  };
}

// ---- scorer / assist pairing -------------------------------------------------

// League scorer spellings (league_sport_config vocabulary, lowercased).
const SCORER_EVENTS = new Set(['goal', 'pengoal']);

interface MinuteEvent { minute: number; eventType: string; player: string }

/** "12'" -> 12. Tolerates plain integer keys too. */
function leagueMinute(key: string): number {
  return toInt(key.replace(/'/g, ''));
}

function bucketEvents(bucket: unknown, minute: number): MinuteEvent[] {
  const list = Array.isArray(bucket)
    ? bucket
    : (bucket && typeof bucket === 'object' ? Object.values(bucket) : []);
  const out: MinuteEvent[] = [];
  for (const ev of list) {
    if (!ev || typeof ev !== 'object') continue;
    // Each entry is {EventType: PlayerName, _t: insertionStamp} — take the
    // first NON-_t entry (key order is not guaranteed, so never entries[0]).
    for (const [type, player] of Object.entries(ev as Record<string, unknown>)) {
      if (type === '_t') continue;
      out.push({ minute, eventType: type.toLowerCase().trim(), player: String(player) });
      break;
    }
  }
  return out;
}

function allEvents(activity: Record<string, unknown> | null): MinuteEvent[] {
  if (!activity) return [];
  return Object.entries(activity)
    .map(([k, v]) => ({ minute: leagueMinute(k), bucket: v }))
    .sort((a, b) => a.minute - b.minute)
    .flatMap(({ minute, bucket }) => bucketEvents(bucket, minute));
}

/** Newest scorer-type event, plus an assist in the same or next minute
 *  (the Manager's chained "Assisted by?" writes land in the same clock
 *  minute; the +1 tolerance mirrors the tournament watcher). */
function findScorerAndAssist(activity: Record<string, unknown> | null):
    { scorer: MinuteEvent | null; assist: MinuteEvent | null } {
  const events = allEvents(activity);
  const scorer = [...events].reverse()
    .find((e) => SCORER_EVENTS.has(e.eventType)) ?? null;
  if (!scorer) return { scorer: null, assist: null };
  const assist = [...events].reverse().find((e) =>
    e.eventType === 'assist' &&
    (e.minute === scorer.minute || e.minute === scorer.minute + 1)) ?? null;
  return { scorer, assist };
}

function newestOwnGoal(activity: Record<string, unknown> | null): MinuteEvent | null {
  return [...allEvents(activity)].reverse()
    .find((e) => e.eventType === 'owngoal') ?? null;
}

// ---- decisions ----------------------------------------------------------------

export function decideLeagueGoal(args: {
  teamTag: 1 | 2; before: number; after: number;
  game: LeagueGameContext;
  sport: string; season: string; dateKey: string; gameIndex: number;
}): LeagueAlertDecision | null {
  const { teamTag, before, after, game, sport, season, dateKey, gameIndex } = args;
  if (after <= before) return null;
  if (game.status !== 1) return null;
  if (game.stage === 'friendly') return null; // exhibitions never alert
  const condition = buildLeagueCondition(sport, season, game.team1, game.team2);
  if (!condition) return null;

  const scoringTeamName = teamTag === 1 ? (game.team1 ?? 'Team 1') : (game.team2 ?? 'Team 2');
  const activity = teamTag === 1 ? game.team1Activity : game.team2Activity;
  const opposing = teamTag === 1 ? game.team2Activity : game.team1Activity;

  const { scorer, assist } = findScorerAndAssist(activity);
  let body = '';
  if (scorer) {
    body = `${scorer.player} (${scoringTeamName}) ${scorer.minute}'`;
    if (assist) body += ` · Assist: ${assist.player}`;
  } else {
    // An own goal scores for THIS team but its event sits on the opponent.
    const og = newestOwnGoal(opposing);
    if (og) body = `Own goal · ${og.player} ${og.minute}'`;
  }

  return {
    kind: 'goal',
    dedupeKey: `goal_t${teamTag}_${after}`,
    title: `⚽ GOAL! ${game.team1 ?? 'Team 1'} ${game.team1Score} – ${game.team2Score} ${game.team2 ?? 'Team 2'}`,
    body,
    condition,
    color: ALERT_COLOR,
    data: {
      type: 'goal', sport, season, dateKey, gameIndex: String(gameIndex),
    },
  };
}

export function decideLeagueStatus(args: {
  before: number; after: number;
  game: LeagueGameContext;
  sport: string; season: string; dateKey: string; gameIndex: number;
}): LeagueAlertDecision | null {
  const { before, after, game, sport, season, dateKey, gameIndex } = args;
  if (before === after) return null;
  if (game.stage === 'friendly') return null; // exhibitions never alert
  const condition = buildLeagueCondition(sport, season, game.team1, game.team2);
  if (!condition) return null;

  const n1 = game.team1 ?? 'Team 1';
  const n2 = game.team2 ?? 'Team 2';

  if (before === 0 && after === 1) {
    return {
      kind: 'kickoff',
      dedupeKey: 'kickoff',
      title: `🟢 Kickoff: ${n1} vs ${n2}`,
      body: game.location
        ? `Now playing — ${game.location}`
        : 'Now playing — follow it live!',
      condition,
      color: ALERT_COLOR,
      data: { type: 'kickoff', sport, season, dateKey, gameIndex: String(gameIndex) },
    };
  }

  if (after === 2) {
    return {
      kind: 'fulltime',
      dedupeKey: 'fulltime',
      title: `🏁 Full time: ${n1} ${game.team1Score} – ${game.team2Score} ${n2}`,
      body: '',
      condition,
      color: ALERT_COLOR,
      data: { type: 'fulltime', sport, season, dateKey, gameIndex: String(gameIndex) },
    };
  }

  return null; // reopen (2->1), reset (->0), or anything else: silence
}
