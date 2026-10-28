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

import { PlayerGameStats } from './player_game_stats';

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

  toStats(teamConceded: number, present: boolean): PlayerGameStats {
    return {
      goals: this.goals, assists: this.assists, saves: this.saves,
      penSaved: this.penSaved, penMissed: this.penMissed,
      ownGoals: this.ownGoals, yellows: this.yellows, reds: this.reds,
      dpl: this.dpl, teamConceded, present,
    };
  }
}

/** Per-player stats for [teamName]'s side of [gameNode]. The player set is
 *  everyone who has an activity event PLUS everyone keyed in [attendance]
 *  (so a present player with zero events still earns the appearance point,
 *  and the attendance step can list the full roster). Throws when
 *  [teamName] is neither team1 nor team2. */
export function mapGameToStats(
  gameNode: Record<string, unknown>,
  args: { teamName: string; attendance?: Record<string, boolean> | null },
): Record<string, PlayerGameStats> {
  const { teamName, attendance } = args;
  let ownActivity: unknown;
  let conceded: number;
  if (gameNode['team1'] != null && teamName === String(gameNode['team1'])) {
    ownActivity = gameNode['team1activity'];
    conceded = score(gameNode['team2score'] ?? gameNode['team2Score']);
  } else if (gameNode['team2'] != null &&
    teamName === String(gameNode['team2'])) {
    ownActivity = gameNode['team2activity'];
    conceded = score(gameNode['team1score'] ?? gameNode['team1Score']);
  } else {
    throw new Error(
      `teamName "${teamName}" is neither team1 nor team2 of this game node`);
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
  const out: Record<string, PlayerGameStats> = {};
  for (const name of names) {
    out[name] = (tallies.get(name) ?? new Tally()).toStats(
      conceded,
      attendance?.[name] ?? true, // spec §8 default: present
    );
  }
  return out;
}
