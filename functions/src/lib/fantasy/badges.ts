// Infinite Fantasy achievement badges (spec
// docs/superpowers/specs/2026-10-30-fantasy-badges-design.md §2–§4): the
// starter catalog, the pure award rules, the rerun-exact reconcile, the
// trophy-cabinet copy of the podium badges, and the two database steps the
// orchestration calls (after every finalize; the sweep's season-end check).
// The push on award creation lives in badge_push.ts (+ the thin trigger
// src/fantasy_badges.ts).
//
// NODES (shapes are client contracts — the fan app streams Catalog +
// Badges, the Manager edits the catalog and gives/removes manual awards):
//
// - Fantasy/BadgeCatalog/<badgeId> (GLOBAL, all sports/seasons) =
//   { Name, Description, Icon, ImageUrl?, Kind:'auto'|'manual',
//     Rule?: '<ruleKey>', Repeatable: bool, Order: int, Active: bool }
//   Icon is a curated Material-icon key (the starter set below; the Flutter
//   pickers add star, local_fire_department, bolt, sports_soccer, verified,
//   celebration, favorite, thumb_up). The sweep seeds STARTER_CATALOG with
//   set-if-absent on every run (seedBadgeCatalog) — an owner edit is never
//   overwritten, and entries are never deleted (Active:false hides one).
//   An 'auto' entry is awarded by its Rule, which must be one of the
//   engine's rule keys (BADGE_RULES = the starter ids): an owner-made auto
//   badge on an existing rule is awarded alongside (under its own id); an
//   unknown Rule never auto-awards. Repeatable:false on a WEEKLY rule means
//   once a season: week N is skipped while the manager holds another auto
//   award of that badge (season rules are once per season by construction).
//   Every engine read merges the stored catalog OVER the starter set
//   (catalogOf), so a finalize that outruns the first seeding still awards.
//
// - Fantasy/<sport>/<season>/Badges/<uid>/<awardId> =
//   { Badge:<badgeId>, Gw?:int, At:int (epoch ms), Source:'auto'|'manual',
//     Note?:string, By?:<admin uid> }
//   Auto ids are deterministic — `<badgeId>_gw<N>` (weekly) or
//   `<badgeId>_season` — so reruns never duplicate; manual ids are the
//   Manager's push ids. The engine writes and removes CHILDREN only (never a
//   whole Badges/<uid> node) and never touches a manual row.
//
// RECONCILE (reconcileAwards — Review Focus 1): after every finalize of week
// N the engine recomputes week N's auto awards from that run's outputs and
// settles the difference: newly earned ids are created (set-if-absent — a
// row already stored at the id, whatever it holds, is kept as is, so At
// stays the FIRST award instant and a rerun with unchanged scores writes
// nothing), and stored auto awards of week N (Source 'auto', Gw N, id
// `<Badge>_gw<N>`) whose badge is an active auto badge on a weekly rule but
// which were not earned this time are removed. An INACTIVE badge's existing
// awards stay ("existing awards stay"); a VOIDED week removes every auto
// award of the week, inactive ones included (no badge for a voided week).
// The season reconcile is the same over `<badgeId>_season` ids.
//
// SEASON END (settleSeasonBadges): the league flag `<sport>/<season>/
// Finished === true` AND every gameweek of the fantasy season is finalized
// (History/<w> exists). The fantasy season = the scoreable gameweeks of the
// derived schedule FROM the first one with History: a match day with no
// scoreable game (friendlies only) can never finalize, and a week before
// the first History never will (fantasy switched on mid-season, or a week
// nobody had a squad for) — neither counts, for the end condition or for
// Ever Present. A lock-passed season week still missing while Finished is
// set is stuck: logged (warn) on every check. Checked after EVERY finalize
// (so a score correction after the end re-settles placements) and by the
// sweep; the sweep only settles a season that holds no auto season award
// yet, so a season badge the owner removed by hand stays removed until a
// week is re-scored (B3's "only lasts until that week is re-scored").
// Paused seasons (lockOverride open/locked) compute nothing — finalize and
// the sweep stand down before either step.
//
// SETTLED MARKER (D6, 2026-11-06): `<root>/SeasonBadgesSettledAt` = epoch ms
// (orchestration_db.ts SEASON_BADGES_SETTLED_NODE). It means: the season is
// OVER — every scoreable week finalized — AND its badges are settled. So it
// is set-if-absent only once the all-weeks-finalized check has passed: at the
// end of every completed settle (a settle that ends with zero season awards
// included; every season badge switched off included — nothing to award, but
// the weeks are still checked first) and when the sweep finds an auto season
// award that has no marker yet (an award only ever exists after that check
// passed). Never for 'notOver' (a Finished season with an unfinalized week,
// badges on or off) or 'testFill'.
// The sweep (onlyIfUnsettled) reads it right after the Finished flag and
// answers 'alreadySettled' WITHOUT reading Badges or History — a settled
// season no longer costs every badge of the season on every 15-minute sweep.
// An absent marker is the old path (it backfills the marker the first time
// it sees an auto season award, or stamps it when the full settle runs). A
// finalize rerun (onlyIfUnsettled false) ignores the marker and re-settles as
// ever. Every writer that takes season awards away deletes it first (a
// re-settle that removes awards: before its first removal; it is set again
// after, with the settle that stands). The weekly reconcile only ever removes
// `_gw<N>` awards, so it leaves the marker alone.
//
// TEST SEASONS (audit I5, 2026-10-31): a season carrying the TestFill marker
// (orchestration_db.ts TEST_FILL_NODE — tools/fill_test_season.ts) never
// settles season badges and NEVER writes a trophy cabinet: its History and
// Leaderboards are a replayed fake season that also holds the REAL
// managers' replayed squads, so a podium there must not reach
// Users/<uid>/Awards. settleSeasonBadges returns 'testFill' before any read
// of the season (the engine entry points stand down for it as well — this
// is the belt to that brace). Weekly awards are not gated here: they stay
// under Fantasy/<sport>/<season>/Badges, and finalize stands down anyway.
//
// TROPHY CABINET: every podium award (a badge on the champion / runnerUp /
// thirdPlace rule) also lands in Users/<uid>/Awards/<id> — the existing
// Award shape (lib/model/award.dart): TrophyId 'fantasy_<badgeId>', Name
// (catalog), Icon 'trophy_gold' (gold) / 'medal' (silver, bronze) from the
// builtin kTrophyIcons map, IconType 'builtin', Tier gold/silver/bronze,
// Sport, ScopeType 'fantasy', ScopeId '<sport>/<season>', Season, Edition
// '', Context 'Infinite Fantasy', Date (league-local MMDDYYYY), Source
// 'auto'; id = deterministicAwardId (the Manager award_engine.dart helper,
// ported 1:1). Written set-if-absent and ONLY for a uid with a Users/<uid>
// node (test-fill fake uids have none); a podium award the re-settle takes
// away also removes its cabinet copy — but only while that copy is still
// ours (Source 'auto' + the same TrophyId).

import { FantasyConfig } from './fantasy_config';
import { leagueWallClock } from './news';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, FantasyDb, fantasyRoot, gamesOfDate, isPlainMap,
  isTestFillSeason, loadSeasonGameweeks, SEASON_BADGES_SETTLED_NODE, toIntLoose,
} from './orchestration_db';
import { FantasySquad, squadFromMap } from './squad';
import { isInvalidRow } from './squad_integrity';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

// ── Rules + catalog ─────────────────────────────────────────────────────────

export const WEEKLY_RULES = [
  'captainGenius', 'crystalBall', 'benchBoss', 'hiddenGem', 'topOfTheWeek',
] as const;
export const SEASON_RULES = [
  'everPresent', 'champion', 'runnerUp', 'thirdPlace',
] as const;
export type WeeklyRule = typeof WEEKLY_RULES[number];
export type SeasonRule = typeof SEASON_RULES[number];
export type BadgeRule = WeeklyRule | SeasonRule;
export const BADGE_RULES: readonly BadgeRule[] = [...WEEKLY_RULES, ...SEASON_RULES];

/** Hidden Gem thresholds (spec §2): >= 10 raw points, owned by < 10%. */
export const HIDDEN_GEM_MIN_POINTS = 10;
export const HIDDEN_GEM_MAX_OWNERSHIP_PCT = 10;
/** Crystal Ball: at least this many Team of the Week players held. */
export const CRYSTAL_BALL_MIN = 3;

export interface CatalogEntry {
  Name: string;
  Description: string;
  Icon: string;
  ImageUrl?: string;
  Kind: 'auto' | 'manual';
  Rule?: BadgeRule;
  Repeatable: boolean;
  Order: number;
  Active: boolean;
}

export type BadgeCatalog = Record<string, CatalogEntry>;

export const BADGE_CATALOG_PATH = 'Fantasy/BadgeCatalog';

function starter(
  rule: BadgeRule, Name: string, Description: string, Icon: string,
  Order: number,
): CatalogEntry {
  return {
    Name, Description, Icon, Kind: 'auto', Rule: rule,
    Repeatable: (WEEKLY_RULES as readonly string[]).includes(rule),
    Order, Active: true,
  };
}

/** The starter set (spec §2 table order; icon keys agreed with the fan +
 *  Manager tasks). Seeded set-if-absent by every sweep. */
export const STARTER_CATALOG: Readonly<Record<BadgeRule, CatalogEntry>> = {
  captainGenius: starter('captainGenius', 'Captain Genius',
    'Your captain outscored (or tied) every other starter in your team that gameweek.',
    'military_tech', 10),
  crystalBall: starter('crystalBall', 'Crystal Ball',
    'At least 3 of the Team of the Week were in your squad.',
    'auto_awesome', 20),
  benchBoss: starter('benchBoss', 'Bench Boss',
    'Nobody on your bench outscored a starter in the same position (not in a Bench Boost week).',
    'event_seat', 30),
  hiddenGem: starter('hiddenGem', 'Hidden Gem',
    'One of your starters scored 10+ points while fewer than 10% of managers owned him.',
    'diamond', 40),
  topOfTheWeek: starter('topOfTheWeek', 'Top of the Week',
    'Highest score of the gameweek.',
    'emoji_events', 50),
  everPresent: starter('everPresent', 'Ever Present',
    'You had a team in every gameweek of the season.',
    'calendar_month', 60),
  champion: starter('champion', 'Champion',
    'Finished the season 1st overall.',
    'workspace_premium', 70),
  runnerUp: starter('runnerUp', 'Runner-up',
    'Finished the season 2nd overall.',
    'looks_two', 80),
  thirdPlace: starter('thirdPlace', 'Third place',
    'Finished the season 3rd overall.',
    'looks_3', 90),
};

function isRule(v: unknown): v is BadgeRule {
  return typeof v === 'string' && (BADGE_RULES as readonly string[]).includes(v);
}

function text(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

/** One stored catalog entry, tolerant: a field missing from a starter id's
 *  entry falls back to the starter's value, from any other id to the
 *  generic defaults (manual, repeatable, active). A Rule that is not an
 *  engine rule key reads as none. Null for a non-map. */
export function parseCatalogEntry(id: string, raw: unknown): CatalogEntry | null {
  if (!isPlainMap(raw)) return null;
  const base: CatalogEntry = (STARTER_CATALOG as Record<string, CatalogEntry>)[id] ?? {
    Name: id, Description: '', Icon: 'military_tech', Kind: 'manual',
    Repeatable: true, Order: 1000, Active: true,
  };
  const rule = 'Rule' in raw ? (isRule(raw['Rule']) ? raw['Rule'] : undefined) : base.Rule;
  const image = text(raw['ImageUrl']);
  return {
    Name: text(raw['Name']) || base.Name,
    Description: typeof raw['Description'] === 'string'
      ? raw['Description'].trim() : base.Description,
    Icon: text(raw['Icon']) || base.Icon,
    ...(image ? { ImageUrl: image } : {}),
    Kind: raw['Kind'] === 'auto' || raw['Kind'] === 'manual' ? raw['Kind'] : base.Kind,
    ...(rule !== undefined ? { Rule: rule } : {}),
    Repeatable: typeof raw['Repeatable'] === 'boolean' ? raw['Repeatable'] : base.Repeatable,
    Order: raw['Order'] != null ? toIntLoose(raw['Order']) : base.Order,
    Active: typeof raw['Active'] === 'boolean' ? raw['Active'] : base.Active,
  };
}

/** The effective catalog: the stored Fantasy/BadgeCatalog entries OVER the
 *  starter set (an unseeded database behaves exactly like a seeded one). */
export function catalogOf(storedRaw: unknown): BadgeCatalog {
  const out: BadgeCatalog = { ...STARTER_CATALOG };
  for (const [id, raw] of childEntries(storedRaw)) {
    const e = parseCatalogEntry(id, raw);
    if (e !== null) out[id] = e;
  }
  return out;
}

/** Active auto badges whose rule is one of [rules]: [badgeId, rule] pairs in
 *  catalog order (Order, then id). */
function autoBadges(
  catalog: BadgeCatalog, rules: readonly string[],
): Array<[string, BadgeRule]> {
  return Object.entries(catalog)
    .filter(([, e]) => e.Active && e.Kind === 'auto' &&
      e.Rule !== undefined && rules.includes(e.Rule))
    .sort(([a, x], [b, y]) => x.Order - y.Order || (a < b ? -1 : a > b ? 1 : 0))
    .map(([id, e]) => [id, e.Rule as BadgeRule]);
}

function evaluated(entry: CatalogEntry | undefined, rules: readonly string[]): boolean {
  return entry !== undefined && entry.Active && entry.Kind === 'auto' &&
    entry.Rule !== undefined && rules.includes(entry.Rule);
}

// ── Award rows ──────────────────────────────────────────────────────────────

export interface AwardRow {
  Badge: string;
  Gw?: number;
  At: number;
  Source: 'auto' | 'manual';
  Note?: string;
  By?: string;
}

/** uid -> awardId -> row. */
export type AwardsByUid = Record<string, Record<string, AwardRow>>;

export function weeklyAwardId(badgeId: string, gw: number): string {
  return `${badgeId}_gw${gw}`;
}

export function seasonAwardId(badgeId: string): string {
  return `${badgeId}_season`;
}

function addAward(out: AwardsByUid, uid: string, id: string, row: AwardRow): void {
  (out[uid] ??= {})[id] = row;
}

// ── Weekly rules ────────────────────────────────────────────────────────────

export interface WeeklyAwardsInput {
  gw: number;
  /** uid -> the squad that SCORED this week (History/<gw>/<uid>: picks,
   *  captainId, viceId, the honored chip — Free Hit already applied). */
  squadsByUid: Record<string, unknown>;
  /** name -> raw bonus-inclusive week points (PlayerWeeks/<gw>), before
   *  any armband multiplier or bench factor. Missing = 0. */
  playerWeeks: Record<string, number>;
  /** name -> played this week (PlayerWeekStats/<gw>/<name>.Played). */
  playedByName: Record<string, boolean>;
  /** The week's Team of the Week (DreamTeam/<gw> as stored — an admin edit
   *  included). */
  dreamTeamNames: string[];
  /** Leaderboards/Gameweek/<gw>. */
  gameweekBoard: Record<string, { points: number; rank: number }>;
  voided: boolean;
  catalog: BadgeCatalog;
  nowMs: number;
}

/** Each weekly rule's winners (sorted uids). Squads that fail squadFromMap
 *  are skipped (finalize logged them already), and so are squads judged
 *  INVALID at the lock (History `Invalid` — squad_integrity.ts): a team
 *  that scored zero for breaking the squad rules earns nothing, nor counts
 *  toward Hidden Gem ownership. Starters = picks with bench
 *  false (the named starting five; an auto-subbed-in bench player is still
 *  bench for the rules). */
export function weeklyRuleWinners(
  input: WeeklyAwardsInput,
): Record<WeeklyRule, string[]> {
  const pts = (id: string) => input.playerWeeks[id] ?? 0;
  const played = (id: string) => input.playedByName[id] === true;
  const squads: Array<[string, FantasySquad]> = [];
  for (const [uid, raw] of Object.entries(input.squadsByUid)) {
    if (!isPlainMap(raw) || isInvalidRow(raw)) continue;
    try {
      squads.push([uid, squadFromMap(raw)]);
    } catch {
      // malformed: no awards
    }
  }
  squads.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));

  // Ownership over THIS week's scored squads (all picks, bench included —
  // the finalize "holders" count), compared exactly: holders/managers < 10%
  // <=> holders * 100 < 10 * managers (never a rounded percent).
  const holders: Record<string, number> = {};
  for (const [, s] of squads) {
    for (const p of s.picks) holders[p.playerId] = (holders[p.playerId] ?? 0) + 1;
  }
  const managers = squads.length;
  const dream = new Set(input.dreamTeamNames);

  const out: Record<WeeklyRule, string[]> = {
    captainGenius: [], crystalBall: [], benchBoss: [], hiddenGem: [], topOfTheWeek: [],
  };
  for (const [uid, s] of squads) {
    const starters = s.picks.filter((p) => !p.bench);
    const bench = s.picks.filter((p) => p.bench);

    // Captain Genius: the NAMED captain's raw points >= every other
    // starter's (ties count) and > 0. An absent captain scores 0 raw.
    if (starters.some((p) => p.playerId === s.captainId)) {
      const cap = pts(s.captainId);
      if (cap > 0 && starters.every((p) => p.playerId === s.captainId || pts(p.playerId) <= cap)) {
        out.captainGenius.push(uid);
      }
    }

    // Crystal Ball: >= 3 Team of the Week players anywhere in the squad.
    if (s.picks.filter((p) => dream.has(p.playerId)).length >= CRYSTAL_BALL_MIN) {
      out.crystalBall.push(uid);
    }

    // Bench Boss: never in a Bench Boost week; at least one bench player
    // played; no played bench player outscored (raw) a PLAYED starter of
    // the same position.
    const benchPlayed = bench.filter((b) => played(b.playerId));
    if (s.chip !== 'benchBoost' && benchPlayed.length > 0 &&
      benchPlayed.every((b) => starters
        .filter((st) => st.position === b.position && played(st.playerId))
        .every((st) => pts(b.playerId) <= pts(st.playerId)))) {
      out.benchBoss.push(uid);
    }

    // Hidden Gem: a starter with >= 10 raw points held by < 10% of the
    // week's managers.
    if (starters.some((p) => pts(p.playerId) >= HIDDEN_GEM_MIN_POINTS &&
      (holders[p.playerId] ?? 0) * 100 < HIDDEN_GEM_MAX_OWNERSHIP_PCT * managers)) {
      out.hiddenGem.push(uid);
    }

    // Top of the Week: gameweek rank 1 (ties all win).
    if (input.gameweekBoard[uid]?.rank === 1) out.topOfTheWeek.push(uid);
  }
  return out;
}

/** Week N's auto awards: { uid: { '<badgeId>_gw<N>': { Badge, Gw, At,
 *  Source:'auto' } } } for every active auto catalog badge on a weekly
 *  rule. A voided week awards nothing. */
export function weeklyAutoAwards(input: WeeklyAwardsInput): AwardsByUid {
  if (input.voided) return {};
  const winners = weeklyRuleWinners(input);
  const out: AwardsByUid = {};
  for (const [badgeId, rule] of autoBadges(input.catalog, WEEKLY_RULES)) {
    for (const uid of winners[rule as WeeklyRule]) {
      addAward(out, uid, weeklyAwardId(badgeId, input.gw),
        { Badge: badgeId, Gw: input.gw, At: input.nowMs, Source: 'auto' });
    }
  }
  return out;
}

// ── Season rules ────────────────────────────────────────────────────────────

export interface SeasonAwardsInput {
  /** Leaderboards/Overall ranks (competition style: ties share). */
  overallBoard: Record<string, { rank: number }>;
  /** uid -> the gameweeks he has a History entry (a scored team) for. */
  historyWeeksByUid: Record<string, number[]>;
  /** Every gameweek of the season (scoreable match days). */
  allWeeks: number[];
  catalog: BadgeCatalog;
  nowMs: number;
}

const PLACEMENT_RANK: Partial<Record<SeasonRule, number>> = {
  champion: 1, runnerUp: 2, thirdPlace: 3,
};

export function seasonRuleWinners(
  input: SeasonAwardsInput,
): Record<SeasonRule, string[]> {
  const out: Record<SeasonRule, string[]> = {
    everPresent: [], champion: [], runnerUp: [], thirdPlace: [],
  };
  const byId = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  if (input.allWeeks.length > 0) {
    for (const [uid, weeks] of Object.entries(input.historyWeeksByUid)) {
      const have = new Set(weeks);
      if (input.allWeeks.every((w) => have.has(w))) out.everPresent.push(uid);
    }
  }
  for (const [uid, row] of Object.entries(input.overallBoard)) {
    for (const rule of ['champion', 'runnerUp', 'thirdPlace'] as const) {
      if (row.rank === PLACEMENT_RANK[rule]) out[rule].push(uid);
    }
  }
  for (const list of Object.values(out)) list.sort(byId);
  return out;
}

/** The season's auto awards: { uid: { '<badgeId>_season': { Badge, At,
 *  Source:'auto' } } }. */
export function seasonAutoAwards(input: SeasonAwardsInput): AwardsByUid {
  const winners = seasonRuleWinners(input);
  const out: AwardsByUid = {};
  for (const [badgeId, rule] of autoBadges(input.catalog, SEASON_RULES)) {
    for (const uid of winners[rule as SeasonRule]) {
      addAward(out, uid, seasonAwardId(badgeId),
        { Badge: badgeId, At: input.nowMs, Source: 'auto' });
    }
  }
  return out;
}

// ── Reconcile ───────────────────────────────────────────────────────────────

export type ReconcileScope =
  | { kind: 'week'; gw: number; voided: boolean }
  | { kind: 'season' };

export interface AwardChanges {
  writes: Array<{ uid: string; awardId: string; row: AwardRow }>;
  removes: Array<{ uid: string; awardId: string; badge: string }>;
}

/** Badges node -> uid -> awardId -> row (map rows only). */
export function badgesByUidOf(
  raw: unknown,
): Record<string, Record<string, Record<string, unknown>>> {
  const out: Record<string, Record<string, Record<string, unknown>>> = {};
  for (const [uid, byId] of childEntries(raw)) {
    for (const [id, row] of childEntries(byId)) {
      if (isPlainMap(row)) (out[uid] ??= {})[id] = row;
    }
  }
  return out;
}

/** Whether a stored award is this run's to remove (see RECONCILE). */
function owned(
  awardId: string, row: Record<string, unknown>, catalog: BadgeCatalog,
  scope: ReconcileScope,
): boolean {
  if (row['Source'] !== 'auto') return false;
  const badge = String(row['Badge'] ?? '');
  if (scope.kind === 'season') {
    return awardId === seasonAwardId(badge) && evaluated(catalog[badge], SEASON_RULES);
  }
  return toIntLoose(row['Gw']) === scope.gw &&
    awardId === weeklyAwardId(badge, scope.gw) &&
    (scope.voided || evaluated(catalog[badge], WEEKLY_RULES));
}

/** The writes + removals that make the stored auto awards of [scope] equal
 *  [desired] — never touching a manual row, another week's awards, or an
 *  inactive badge's awards (a voided week's excepted). Pure; deterministic
 *  order (uid, then award id). */
export function reconcileAwards(args: {
  existing: Record<string, Record<string, Record<string, unknown>>>;
  desired: AwardsByUid;
  catalog: BadgeCatalog;
  scope: ReconcileScope;
}): AwardChanges {
  const { existing, desired, catalog, scope } = args;
  const byId = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  const removes: AwardChanges['removes'] = [];
  for (const uid of Object.keys(existing).sort(byId)) {
    for (const id of Object.keys(existing[uid]).sort(byId)) {
      const row = existing[uid][id];
      if (owned(id, row, catalog, scope) && desired[uid]?.[id] === undefined) {
        removes.push({ uid, awardId: id, badge: String(row['Badge'] ?? '') });
      }
    }
  }
  const removed = new Set(removes.map((r) => `${r.uid}/${r.awardId}`));
  const writes: AwardChanges['writes'] = [];
  for (const uid of Object.keys(desired).sort(byId)) {
    const mine = existing[uid] ?? {};
    for (const id of Object.keys(desired[uid]).sort(byId)) {
      if (mine[id] !== undefined) continue; // stored: kept as is
      const row = desired[uid][id];
      if (scope.kind === 'week' && catalog[row.Badge]?.Repeatable === false &&
        Object.entries(mine).some(([otherId, other]) => otherId !== id &&
          other['Badge'] === row.Badge && other['Source'] === 'auto' &&
          !removed.has(`${uid}/${otherId}`))) {
        continue; // once a season: he already holds one
      }
      writes.push({ uid, awardId: id, row });
    }
  }
  return { writes, removes };
}

// ── Trophy cabinet ──────────────────────────────────────────────────────────

/** Port of the Manager's award_engine.dart deterministicAwardId: a stable,
 *  RTDB-key-safe id so re-awarding overwrites instead of duplicating. */
export function deterministicAwardId(
  trophyId: string, scopeType: string, scopeId: string, seasonOrEdition: string,
): string {
  const raw = `${trophyId}_${scopeType}_${scopeId}_${seasonOrEdition}`;
  return raw.replace(/[.#$[\]/\s]/g, '_');
}

const CABINET: Partial<Record<BadgeRule, { tier: string; icon: string }>> = {
  champion: { tier: 'gold', icon: 'trophy_gold' },
  runnerUp: { tier: 'silver', icon: 'medal' },
  thirdPlace: { tier: 'bronze', icon: 'medal' },
};

export const CABINET_SCOPE_TYPE = 'fantasy';
export const CABINET_CONTEXT = 'Infinite Fantasy';

/** League-local calendar date (MMDDYYYY) of an instant. */
export function leagueDateKey(nowUtc: Date): string {
  const d = leagueWallClock(nowUtc);
  return `${String(d.getUTCMonth() + 1).padStart(2, '0')}` +
    `${String(d.getUTCDate()).padStart(2, '0')}${d.getUTCFullYear()}`;
}

/** The cabinet copy of a podium badge (null for any other rule). */
export function cabinetAwardFor(args: {
  badgeId: string; entry: CatalogEntry; sport: string; season: string;
  dateKey: string;
}): { id: string; row: Record<string, string> } | null {
  const look = args.entry.Rule !== undefined ? CABINET[args.entry.Rule] : undefined;
  if (look === undefined) return null;
  const trophyId = `fantasy_${args.badgeId}`;
  const scopeId = `${args.sport}/${args.season}`;
  return {
    id: deterministicAwardId(trophyId, CABINET_SCOPE_TYPE, scopeId, args.season),
    row: {
      TrophyId: trophyId,
      Name: args.entry.Name,
      Icon: look.icon,
      IconType: 'builtin',
      Tier: look.tier,
      Sport: args.sport,
      ScopeType: CABINET_SCOPE_TYPE,
      ScopeId: scopeId,
      Season: args.season,
      Edition: '',
      Context: CABINET_CONTEXT,
      Date: args.dateKey,
      Source: 'auto',
    },
  };
}

// ── Database steps ──────────────────────────────────────────────────────────

/** Seeds every missing starter entry (set-if-absent), given the stored
 *  Fantasy/BadgeCatalog node the caller already read. Returns how many it
 *  wrote (0 on every run after the first). */
export async function seedBadgeCatalog(
  db: FantasyDb, storedRaw: unknown, log: FantasyLogger = silent,
): Promise<number> {
  const stored = new Set(childEntries(storedRaw).map(([id]) => id));
  let seeded = 0;
  for (const [id, entry] of Object.entries(STARTER_CATALOG)) {
    if (stored.has(id)) continue;
    if (await db.writeIfAbsent(`${BADGE_CATALOG_PATH}/${id}`, entry)) seeded++;
  }
  if (seeded > 0) log.info('fantasy badges: starter catalog seeded', { seeded });
  return seeded;
}

async function applyChanges(
  db: FantasyDb, root: string, changes: AwardChanges,
): Promise<{ written: number; removed: number }> {
  for (const r of changes.removes) {
    await db.write(`${root}/Badges/${r.uid}/${r.awardId}`, null);
  }
  let written = 0;
  for (const w of changes.writes) {
    // Set-if-absent: a concurrent run (trigger + backstop) never doubles.
    if (await db.writeIfAbsent(`${root}/Badges/${w.uid}/${w.awardId}`, w.row)) written++;
  }
  return { written, removed: changes.removes.length };
}

export interface WeeklyBadgesArgs {
  sport: string;
  season: string;
  gw: number;
  squadsByUid: Record<string, unknown>;
  playerWeeks: Record<string, number>;
  playedByName: Record<string, boolean>;
  dreamTeamNames: string[];
  gameweekBoard: Record<string, { points: number; rank: number }>;
  voided: boolean;
  nowMs: number;
  log?: FantasyLogger;
}

/** Week N's auto awards settled against the stored Badges (the finalize
 *  hook; see RECONCILE). */
export async function settleWeeklyBadges(
  db: FantasyDb, args: WeeklyBadgesArgs,
): Promise<{ written: number; removed: number }> {
  const log = args.log ?? silent;
  const root = fantasyRoot(args.sport, args.season);
  const catalog = catalogOf(await db.read(BADGE_CATALOG_PATH));
  const existing = badgesByUidOf(await db.read(`${root}/Badges`));
  const desired = weeklyAutoAwards({ ...args, catalog });
  const changes = reconcileAwards({
    existing, desired, catalog,
    scope: { kind: 'week', gw: args.gw, voided: args.voided },
  });
  const res = await applyChanges(db, root, changes);
  if (res.written > 0 || res.removed > 0) {
    log.info('fantasy badges: gameweek awards settled', {
      sport: args.sport, season: args.season, gw: args.gw, ...res,
      voided: args.voided,
    });
  }
  return res;
}

export interface SeasonBadgesArgs {
  sport: string;
  season: string;
  cfg: FantasyConfig;
  nowUtc: Date;
  log?: FantasyLogger;
  /** The sweep's mode: settle only a season that holds no auto season
   *  award yet (see SEASON END). */
  onlyIfUnsettled?: boolean;
}

function hasAutoSeasonAward(
  existing: Record<string, Record<string, Record<string, unknown>>>,
): boolean {
  return Object.values(existing).some((byId) => Object.entries(byId)
    .some(([id, row]) => row['Source'] === 'auto' &&
      id === seasonAwardId(String(row['Badge'] ?? ''))));
}

/** Stamps the settled marker (see SETTLED MARKER), set-if-absent: a rerun
 *  that changes nothing writes nothing, and the stamp keeps the instant of
 *  the settle that made it. */
async function markSeasonSettled(
  db: FantasyDb, root: string, nowUtc: Date,
): Promise<void> {
  await db.writeIfAbsent(`${root}/${SEASON_BADGES_SETTLED_NODE}`, nowUtc.getTime());
}

/** The season-end step (see SEASON END + TROPHY CABINET + SETTLED MARKER).
 *  'notOver' when the league has not flagged Finished or a gameweek is not
 *  finalized yet; 'alreadySettled' in sweep mode once the settled marker or
 *  a season award exists; 'testFill' for a TestFill season (see TEST
 *  SEASONS): no season award, no Users/* write, nothing read beyond the
 *  marker. */
export async function settleSeasonBadges(
  db: FantasyDb, args: SeasonBadgesArgs,
): Promise<'notOver' | 'alreadySettled' | 'settled' | 'testFill'> {
  const { sport, season, cfg } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season };

  if (await isTestFillSeason(db, root)) {
    log.info('fantasy badges: TestFill season — season badges and trophy ' +
      'cabinet skipped', ctx);
    return 'testFill';
  }
  if ((await db.read(`${sport}/${season}/Finished`)) !== true) return 'notOver';
  // The marker is a number, so it is read (`!= null`), never `exists()`.
  if (args.onlyIfUnsettled &&
    (await db.read(`${root}/${SEASON_BADGES_SETTLED_NODE}`)) != null) {
    return 'alreadySettled';
  }
  const existing = badgesByUidOf(await db.read(`${root}/Badges`));
  if (args.onlyIfUnsettled && hasAutoSeasonAward(existing)) {
    await markSeasonSettled(db, root, args.nowUtc); // backfill: settled before the marker
    return 'alreadySettled';
  }
  const catalog = catalogOf(await db.read(BADGE_CATALOG_PATH));

  const configNode = await db.read(`${root}/Config`);
  const { gws, dateNode } = await loadSeasonGameweeks(
    db, sport, season, cfg, isPlainMap(configNode) ? configNode : {});
  const dates = new Map(childEntries(dateNode));
  const scoreable = gws.filter((g) => gamesOfDate(dates.get(g.date)).length > 0);

  const finalized = new Set<number>();
  const historyWeeksByUid: Record<string, number[]> = {};
  for (const [w, byUid] of childEntries(await db.read(`${root}/History`))) {
    const week = Number(w);
    if (!Number.isInteger(week)) continue;
    finalized.add(week);
    for (const [uid, entry] of childEntries(byUid)) {
      // A week judged invalid (scored zero for breaking the squad rules) is
      // not a scored team for Ever Present.
      if (isPlainMap(entry) && !isInvalidRow(entry)) {
        (historyWeeksByUid[uid] ??= []).push(week);
      }
    }
  }
  // The fantasy season starts at its FIRST finalized gameweek: earlier
  // weeks can never get History (fantasy switched on mid-season — the
  // first-run guard never fabricates them — or a week nobody had a squad
  // for), so they are not part of it, neither for the end condition nor
  // for Ever Present. Nothing finalized at all = nothing to award.
  const scored = scoreable.filter((g) => finalized.has(g.number));
  if (scored.length === 0) return 'notOver';
  const start = Math.min(...scored.map((g) => g.number));
  const seasonWeeks = scoreable.filter((g) => g.number >= start);
  const missing = seasonWeeks.filter((g) => !finalized.has(g.number));
  if (missing.length > 0) {
    // A missing week whose lock has passed is stuck (games never all Final,
    // or settled without squads); one still ahead just has not been played.
    const overdue = missing
      .filter((g) => g.lockUtc.getTime() <= args.nowUtc.getTime())
      .map((g) => g.number);
    if (overdue.length > 0) {
      log.warn('fantasy badges: season Finished but gameweeks not finalized — ' +
        'season badges wait', { ...ctx, missing: overdue });
    }
    return 'notOver';
  }
  // Every season badge switched off: nothing to award or take away (an
  // inactive badge's awards stay) — skip the boards. The season is settled
  // all the same, but only now: the marker means the season is OVER (every
  // scoreable week finalized) AND settled, never just "no badge to award".
  if (autoBadges(catalog, SEASON_RULES).length === 0) {
    await markSeasonSettled(db, root, args.nowUtc);
    return 'settled';
  }
  const allWeeks = seasonWeeks.map((g) => g.number);

  const overallBoard: Record<string, { rank: number }> = {};
  for (const [uid, row] of childEntries(await db.read(`${root}/Leaderboards/Overall`))) {
    if (isPlainMap(row)) overallBoard[uid] = { rank: toIntLoose(row['rank']) };
  }
  const desired = seasonAutoAwards({
    overallBoard, historyWeeksByUid, allWeeks, catalog, nowMs: args.nowUtc.getTime(),
  });
  const changes = reconcileAwards({ existing, desired, catalog, scope: { kind: 'season' } });
  // A re-settle that takes season awards away drops the marker FIRST: until
  // the settle below completes (and sets it again) nothing vouches for the
  // half-changed awards — a crash in between leaves the sweep to look.
  if (changes.removes.length > 0) {
    await db.write(`${root}/${SEASON_BADGES_SETTLED_NODE}`, null);
  }
  const res = await applyChanges(db, root, changes);

  // Trophy cabinet: every podium award now held gets its copy (set-if-
  // absent, real users only); a podium award taken away loses its copy
  // while that copy is still ours. Never reached for a TestFill season (the
  // early return above): fake podiums never touch Users/*.
  const dateKey = leagueDateKey(args.nowUtc);
  let cabinet = 0;
  for (const uid of Object.keys(desired).sort()) {
    for (const row of Object.values(desired[uid])) {
      const award = cabinetAwardFor({
        badgeId: row.Badge, entry: catalog[row.Badge], sport, season, dateKey,
      });
      if (award === null) continue;
      const path = `Users/${uid}/Awards/${award.id}`;
      if ((await db.read(path)) != null) continue;
      if ((await db.read(`Users/${uid}`)) == null) continue; // no real user
      if (await db.writeIfAbsent(path, award.row)) cabinet++;
    }
  }
  for (const r of changes.removes) {
    const entry = catalog[r.badge];
    if (entry === undefined) continue;
    const award = cabinetAwardFor({ badgeId: r.badge, entry, sport, season, dateKey });
    if (award === null) continue;
    const path = `Users/${r.uid}/Awards/${award.id}`;
    const stored = await db.read(path);
    if (isPlainMap(stored) && stored['Source'] === 'auto' &&
      stored['TrophyId'] === award.row['TrophyId']) {
      await db.write(path, null);
      cabinet++;
    }
  }

  if (res.written > 0 || res.removed > 0 || cabinet > 0) {
    log.info('fantasy badges: season awards settled', { ...ctx, ...res, cabinet });
  }
  // Last, after the cabinet, on EVERY completed settle — one that ends with
  // zero season awards included, or the season would re-run this whole
  // settle on every sweep for ever. A failing stamp loses nothing but the
  // shortcut (the next sweep settles or backfills again).
  await markSeasonSettled(db, root, args.nowUtc);
  return 'settled';
}
