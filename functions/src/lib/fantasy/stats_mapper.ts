// Maps one real futsal game node (`Futsal/<season>/Date/<MMDDYYYY>/<i>`)
// into per-player PlayerGameStats for ONE team — the bridge between captured
// activities and the fantasy engine. Pure TS: takes already-decoded
// object/array values, no firebase imports.
//
// Faithful port of lib/fantasy/engine/stats_mapper.dart, with the leaf
// metadata-skipping semantics of lib/misc/activity_entry.dart inlined.
//
// Shape notes (mirrors the proven parsers — scorepage.populateActivities,
// single_match_tallies, tournament_stats_engine):
// - `team1activity`/`team2activity` are minute-keyed maps of leaf buckets,
//   but RTDB array coercion can hand EITHER level over as a (possibly
//   null-padded) array — both levels accept array or map here.
// - Each leaf is `{activityType: playerName}` plus optional metadata keys
//   (`_t` insertion stamps) that must be skipped.
// - Scores may be int or String (utility.dart tolerates both), with the
//   legacy `team1Score`/`team2Score` spelling as fallback.
//
// Counting rules (spec §7/§8, league conventions verified in
// league_sport_config.dart + tournament_stats_engine.dart):
// - goals = Goal + PenGoal (league statKeys pair PenGoal with Goals).
// - yellows = Yellow only; reds = Red + SecondYellow (the second yellow IS
//   the red — a 2nd-yellow player nets first Yellow + one red, never two
//   yellows).
// - PenSaved lives on the KEEPER'S OWN team list and credits the keeper;
//   the league pairs it with Saves, so it bumps BOTH penSaved and saves,
//   exactly like the match tally engines.
// - teamConceded = the opposing team's final score.
// - present comes from the attendance map (spec §8): a missing map or a
//   missing player entry defaults to present.
// - Foul, Substitution and unknown/legacy types (e.g. 'Blue') carry no
//   fantasy counter and are skipped — same as the tally engines.
// - forfeit comes from the game's `forfeitedBy` marker (see FORFEITS).
// - inGoal (spec §7 stand-in goalkeeper) is decided per player per game:
//   >=1 Save or PenSaved on his own team list (only a keeper makes saves in
//   futsal), OR his name keyed `true` in his side's `team{1,2}keepers`
//   marker (the Manager's attendance-step "In goal" switch — same name keys
//   as `team{1,2}attendance`, List/Map coercion tolerated, only a literal
//   `true` counts). The marker only flags players already in the result —
//   it never adds one. Position-blind: scoring ignores it for a listed GK.
//
// FORFEITS (spec §8a, owner Option B): a game carrying `forfeitedBy: 1|2`
// (parseForfeitedBy — the Manager's Forfeit button) maps every entry with
// forfeit 'won' (this team showed up) or 'lost' (this team forfeited), and
// its activity events are IGNORED ENTIRELY — stray stats recorded on a
// forfeited game never count, and a player known only from such an event
// is not in the result at all (nobody is inGoal: the keepers marker is
// ignored too — a forfeit scores the appearance point or nothing). The
// player set is then exactly the attendance keys, so CALLERS MUST PASS THE
// FULL ROSTER-COMPOSED ATTENDANCE (every rostered player -> true,
// absentees -> false: the finalizer's fullAttendance) — with no attendance
// map a forfeit yields no players and nobody gets the appearance point.

import { GameForfeit, PlayerGameStats } from './player_game_stats';

/** Game-node key for the forfeit marker (1 | 2). */
export const FORFEITED_BY_KEY = 'forfeitedBy';

/** Game-node key of one side's stand-in keeper marker
 *  (`team1keepers` / `team2keepers` = `{ <player name>: true }`). */
export function keepersKey(side: 1 | 2): string {
  return `team${side}keepers`;
}

/** The names marked in goal by a `team{1,2}keepers` node: keys whose value
 *  is exactly `true`. A Map is read by key; a List (RTDB coercion of
 *  numeric-name keys) by index; null padding, empty keys, any other value
 *  and any other shape are ignored. Dart twin: stats_mapper.dart
 *  parseKeepers. */
export function parseKeepers(raw: unknown): Set<string> {
  const out = new Set<string>();
  const add = (key: string, value: unknown) => {
    if (key.length > 0 && value === true) out.add(key);
  };
  if (Array.isArray(raw)) {
    raw.forEach((v, i) => add(String(i), v));
  } else if (isPlainMap(raw)) {
    for (const [k, v] of Object.entries(raw)) add(k, v);
  }
  return out;
}

/** `forfeitedBy` as 1 or 2; null for absent / junk / any other number.
 *  Port of lib/misc/forfeit.dart parseForfeitedBy (= the Manager's):
 *  ints and whole doubles count, a String is trimmed then parsed as a
 *  signed decimal integer (the same gate as this file's score(); Dart's
 *  int.tryParse would also take a 0x-hex string, a shape no writer ever
 *  produces); everything else is not a forfeit. */
export function parseForfeitedBy(raw: unknown): 1 | 2 | null {
  let v: number | null = null;
  if (typeof raw === 'number') {
    if (Number.isFinite(raw) && Number.isInteger(raw)) v = raw;
  } else if (typeof raw === 'string') {
    const s = raw.trim();
    if (/^[+-]?\d+$/.test(s)) v = Number(s);
  }
  return v === 1 || v === 2 ? v : null;
}

/** Plain object — arrays (RTDB integer-key coercion) are NOT maps,
 *  matching Dart's `is Map` on a List. */
function isPlainMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

/** lib/misc/activity_entry.dart isActivityMetadataKey: reserved
 *  underscore-prefixed keys (e.g. `_t`) — never event types. */
export function isActivityMetadataKey(key: unknown): boolean {
  return String(key).startsWith('_');
}

/** lib/misc/activity_entry.dart activityEventOf: the event
 *  `{type: player}` of one leaf, skipping metadata keys. null when the
 *  leaf holds no event (empty or metadata-only). */
export function activityEventOf(
  entry: Record<string, unknown>,
): { key: string; value: unknown } | null {
  for (const [key, value] of Object.entries(entry)) {
    if (isActivityMetadataKey(key)) continue;
    return { key, value };
  }
  return null;
}

/** Dart `int.tryParse(v?.toString().trim() ?? '') ?? 0` for scores that may
 *  be int or String. int.tryParse accepts only a full optionally-signed
 *  decimal integer — '2x' is null, so this regex-gates before Number. */
function score(v: unknown): number {
  if (typeof v === 'number') return Math.trunc(v); // Dart num.toInt()
  const s = String(v ?? '').trim();
  return /^[+-]?\d+$/.test(s) ? Number(s) : 0;
}

/** Both final scores of a game node as ints: `team1score`/`team2score`
 *  (int or String) with the legacy `team1Score`/`team2Score` spelling as the
 *  fallback — the ONE reader mapGameToStats (teamConceded) and the
 *  PlayerWeekStats Games lists share. */
export function gameScores(
  gameNode: Record<string, unknown>,
): { team1: number; team2: number } {
  return {
    team1: score(gameNode['team1score'] ?? gameNode['team1Score']),
    team2: score(gameNode['team2score'] ?? gameNode['team2Score']),
  };
}

/** Walks every activity leaf, tolerating RTDB array coercion at BOTH levels
 *  (activity -> buckets, bucket -> leaves) and null padding at either. */
function forEachLeaf(
  activity: unknown, fn: (leaf: Record<string, unknown>) => void,
): void {
  const eachBucket = (bucket: unknown): void => {
    if (Array.isArray(bucket)) {
      for (const leaf of bucket) {
        if (isPlainMap(leaf)) fn(leaf);
      }
    } else if (isPlainMap(bucket)) {
      for (const leaf of Object.values(bucket)) {
        if (isPlainMap(leaf)) fn(leaf);
      }
    }
  };

  if (Array.isArray(activity)) {
    activity.forEach(eachBucket);
  } else if (isPlainMap(activity)) {
    Object.values(activity).forEach(eachBucket);
  }
}

class Tally {
  goals = 0; assists = 0; saves = 0; penSaved = 0; penMissed = 0;
  ownGoals = 0; yellows = 0; reds = 0; dpl = 0;

  toStats(
    teamConceded: number, present: boolean, forfeit: GameForfeit = 'none',
    markedInGoal = false,
  ): PlayerGameStats {
    return {
      goals: this.goals, assists: this.assists, saves: this.saves,
      penSaved: this.penSaved, penMissed: this.penMissed,
      ownGoals: this.ownGoals, yellows: this.yellows, reds: this.reds,
      dpl: this.dpl, teamConceded, present, forfeit,
      // Only a keeper makes saves (PenSaved bumps saves too).
      inGoal: this.saves > 0 || this.penSaved > 0 || markedInGoal,
    };
  }
}

/** Per-player stats for [teamName]'s side of [gameNode]. The player set is
 *  everyone who has an activity event PLUS everyone keyed in [attendance]
 *  (so a present player with zero events still earns the appearance point,
 *  and the attendance step can list the full roster) — on a FORFEITED game
 *  only the [attendance] keys (see FORFEITS above). Throws when [teamName]
 *  is neither team1 nor team2. */
export function mapGameToStats(
  gameNode: Record<string, unknown>,
  args: { teamName: string; attendance?: Record<string, boolean> | null },
): Record<string, PlayerGameStats> {
  const { teamName, attendance } = args;
  const scores = gameScores(gameNode);
  let ownActivity: unknown;
  let conceded: number;
  let side: 1 | 2;
  if (gameNode['team1'] != null && teamName === String(gameNode['team1'])) {
    ownActivity = gameNode['team1activity'];
    conceded = scores.team2;
    side = 1;
  } else if (gameNode['team2'] != null &&
    teamName === String(gameNode['team2'])) {
    ownActivity = gameNode['team2activity'];
    conceded = scores.team1;
    side = 2;
  } else {
    throw new Error(
      `teamName "${teamName}" is neither team1 nor team2 of this game node`);
  }

  const forfeitedBy = parseForfeitedBy(gameNode[FORFEITED_BY_KEY]);
  if (forfeitedBy !== null) {
    const forfeit: GameForfeit = forfeitedBy === side ? 'lost' : 'won';
    const out: Record<string, PlayerGameStats> = {};
    for (const name of attendance ? Object.keys(attendance) : []) {
      out[name] = new Tally().toStats(
        conceded, attendance?.[name] ?? true, forfeit);
    }
    return out;
  }

  const tallies = new Map<string, Tally>();
  forEachLeaf(ownActivity, (leaf) => {
    const event = activityEventOf(leaf);
    if (event === null) return;
    const player = event.value == null ? '' : String(event.value);
    if (player.length === 0) return;
    let t = tallies.get(player);
    if (!t) {
      t = new Tally();
      tallies.set(player, t);
    }
    // Case-insensitive like single_match_tallies, with the legacy spaced
    // tournament spellings accepted alongside the canonical league ones.
    switch (event.key.toLowerCase().trim()) {
      case 'goal': case 'pengoal': case 'penalty goal':
        t.goals++; break;
      case 'assist':
        t.assists++; break;
      case 'save':
        t.saves++; break;
      case 'pensaved': case 'penalty saved':
        t.penSaved++;
        t.saves++; // league pairing: a penalty save is also a save
        break;
      case 'penmissed': case 'penalty missed':
        t.penMissed++; break;
      case 'owngoal': case 'own goal':
        t.ownGoals++; break;
      case 'dpl':
        t.dpl++; break;
      case 'yellow': case 'yellow card':
        t.yellows++; break;
      case 'secondyellow': case 'second yellow': case 'red': case 'red card':
        t.reds++; break;
      default:
        break; // Foul, Substitution, unknown/legacy: no fantasy counter
    }
  });

  const names = new Set<string>([
    ...tallies.keys(),
    ...(attendance ? Object.keys(attendance) : []),
  ]);
  const keepers = parseKeepers(gameNode[keepersKey(side)]);
  const out: Record<string, PlayerGameStats> = {};
  for (const name of names) {
    out[name] = (tallies.get(name) ?? new Tally()).toStats(
      conceded,
      attendance?.[name] ?? true, // spec §8 default: present
      'none',
      // Stand-in keeper (spec §7): the Manager's "In goal" marker (a save or
      // penalty save also puts him in goal — see toStats).
      keepers.has(name),
    );
  }
  return out;
}
