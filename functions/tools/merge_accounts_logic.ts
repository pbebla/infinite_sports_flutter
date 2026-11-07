// Duplicate-account merge tool - PURE planner and allowlist (plan
// 2026-11-06-merge-duplicate-accounts, Task 4; design D1-D6, D10, D14, D15).
// No I/O here: the CLI (merge_accounts.ts) reads production into a
// MergeSnapshot, calls buildMergePlan, prints the summary + refusals, and
// sends every write it applies through assertMergePaths.
//
// What a merge does, per cluster (a person with one kept account and 0-3
// old accounts):
//   D1  relink roster rows by the `UID` leaf only (never a roster key);
//   D3  add `Users/<keep>/Played/<Sport>/Season <S> = <team>` per league row;
//   D4  copy ProfileUrl and missing Information leaves - nothing private;
//   D5  stamp each old account with MergedInto / MergedAt / MergedHint and
//       change nothing else on it;
//   D10 optionally fix the kept account's First Name (owner request).
// Everything else on an old account (Sign Ups, votes, Token, its Played...)
// is left exactly as it is (D14).
//
// Snapshot contract (what the CLI must hand over, all keyed by full path):
//   `Users/<uid>`                    the user node of every keep and old uid
//                                    (a missing node -> the cluster is refused);
//   `<Sport>/<S>/Line Ups/<team>/<name>/UID` and
//   `AFC San Jose/Seasons/<S>/Roster/<name>/UID`
//                                    the UID leaf of every roster row that
//                                    holds an old uid, plus every row a
//                                    cluster's nameRows names. For a nameRow:
//                                    string = linked, null = the row exists
//                                    with no UID, KEY ABSENT = no such row
//                                    (refused: a write would create a stray row);
//   `Fantasy/<Sport>/<S>/Config`     for every league season a relink would
//                                    touch: any non-null value = the Config
//                                    exists, null = checked and absent, key
//                                    absent = not checked (refused: fail closed).
//   keptHints[keep]                  the kept email, ALREADY MASKED (maskEmail).
//
// Write order inside a cluster is deliberate: Played, profile fields, roster
// UID relinks, and the stamps LAST. A crash part-way leaves a state that a
// rerun finishes without duplicating anything (the stamps are the "done"
// marker; the rows are only relinked after their Played entry exists).

import { isDeepStrictEqual } from 'util';
import { MASK_BULLET } from '../src/lib/mask_email';

/** The league sports whose rosters live under `<Sport>/<Season>/Line Ups`. */
export const LEAGUE_SPORTS: readonly string[] = ['Futsal', 'Basketball', 'Flag Football'];

export interface MergeNameRow {
  sport: string;
  season: string;
  team: string;
  /** The roster key, exactly as stored (variants of the person's name). */
  name: string;
}

export interface MergeCluster {
  /** Display name for summaries and refusals - never an email. */
  who: string;
  keep: string;
  old: string[];
  nameRows?: MergeNameRow[];
  firstNameFix?: string;
}

export interface MergeMap {
  clusters: MergeCluster[];
}

export interface MergeSnapshot {
  nodes: Record<string, unknown>;
  keptHints: Record<string, string>;
}

/** One leaf write. `after: null` would mean "remove" - the merge never
 *  removes anything, and assertMergePaths refuses it. */
export interface PlanWrite {
  path: string;
  before: unknown;
  after: unknown;
}

export interface MergePlan {
  writes: PlanWrite[];
  refusals: Array<{ who: string; why: string }>;
  summary: string[];
}

// ---------------------------------------------------------------- paths

export const userPath = (uid: string): string => `Users/${uid}`;

export const leagueUidPath = (sport: string, season: string, team: string, name: string): string =>
  `${sport}/${season}/Line Ups/${team}/${name}/UID`;

export const afcUidPath = (season: string, name: string): string =>
  `AFC San Jose/Seasons/${season}/Roster/${name}/UID`;

/** The seasons-played index leaf (the shape the Manager's linkLeaguePlayer writes). */
export const playedPath = (keep: string, sport: string, season: string): string =>
  `Users/${keep}/Played/${sport}/Season ${season}`;

export const fantasyConfigPath = (sport: string, season: string): string =>
  `Fantasy/${sport}/${season}/Config`;

export type RosterRef =
  | { kind: 'league'; sport: string; season: string; team: string; name: string }
  | { kind: 'afc'; season: string; name: string };

const LEAGUE_UID_RE = new RegExp(
  `^(${LEAGUE_SPORTS.join('|')})/(\\d+)/Line Ups/([^/]+)/([^/]+)/UID$`,
);
const AFC_UID_RE = /^AFC San Jose\/Seasons\/([^/]+)\/Roster\/([^/]+)\/UID$/;

/** A roster row's UID leaf path -> its parts, or null for any other path. */
export function parseRosterUidPath(path: string): RosterRef | null {
  if (typeof path !== 'string') return null;
  const l = LEAGUE_UID_RE.exec(path);
  if (l) return { kind: 'league', sport: l[1], season: l[2], team: l[3], name: l[4] };
  const a = AFC_UID_RE.exec(path);
  if (a) return { kind: 'afc', season: a[1], name: a[2] };
  return null;
}

// ----------------------------------------------------------- validators

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
// Database keys cannot hold . # $ [ ] / or control characters.
const SAFE_KEY_RE = /^[^\u0000-\u001f\u007f/.#$[\]]{1,200}$/;
const SEASON_RE = /^\d{1,4}$/;
const INFO_LEAF_RE = /^[A-Za-z][A-Za-z0-9 _-]{0,39}$/;
// D4: never copy a token, email, phone, name, date of birth or address.
const SENSITIVE_LEAF_RE = /token|mail|phone|birth|dob|passw|secret|ssn|address|zip|uid|name/i;
const MAX_FIRST_NAME = 40;

const hasOwn = (o: object, k: string): boolean => Object.prototype.hasOwnProperty.call(o, k);

function isPlainMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

const isUid = (v: unknown): v is string => typeof v === 'string' && UID_RE.test(v);
const isSafeKey = (v: unknown): v is string =>
  typeof v === 'string' && SAFE_KEY_RE.test(v) && v.trim().length > 0;
const nonEmptyString = (v: unknown): v is string => typeof v === 'string' && v.length > 0;

/** An absent value or a blank string: the account "lacks" it (D4). */
const lacks = (v: unknown): boolean => v === undefined || v === null || (typeof v === 'string' && v.trim() === '');

/** A masked hint: one `@`, at least one bullet, no spaces (never a whole email). */
export function looksMasked(hint: unknown): hint is string {
  return (
    typeof hint === 'string' &&
    hint.length <= 80 &&
    !/\s/.test(hint) &&
    hint.includes(MASK_BULLET) &&
    hint.split('@').length === 2
  );
}

/** D4: may this Information leaf/value be copied? Scalar values only and
 *  never a private-looking key (Token, email-like, phone...). */
export function isCopyableInformation(leaf: string, value: unknown): boolean {
  if (typeof leaf !== 'string' || !INFO_LEAF_RE.test(leaf) || SENSITIVE_LEAF_RE.test(leaf)) return false;
  if (typeof value === 'string') return value.trim().length > 0 && value.length <= 200;
  if (typeof value === 'number') return Number.isFinite(value);
  return typeof value === 'boolean';
}

const isValidFirstName = (v: unknown): v is string =>
  typeof v === 'string' && v.trim() === v && v.length > 0 && v.length <= MAX_FIRST_NAME && !/[\u0000-\u001f\u007f]/.test(v);

function validNameRows(c: MergeCluster, refuse: (why: string) => void): MergeNameRow[] {
  const raw = c.nameRows ?? [];
  if (!Array.isArray(raw)) {
    refuse('"nameRows" must be a list');
    return [];
  }
  const rows: MergeNameRow[] = [];
  raw.forEach((r, i) => {
    const n = i + 1;
    if (!isPlainMap(r)) return refuse(`name row #${n} is not an object`);
    if (typeof r.sport !== 'string' || !LEAGUE_SPORTS.includes(r.sport)) {
      return refuse(`name row #${n}: sport must be one of ${LEAGUE_SPORTS.join(', ')}`);
    }
    if (typeof r.season !== 'string' || !SEASON_RE.test(r.season)) {
      return refuse(`name row #${n}: season must be a season number`);
    }
    if (!isSafeKey(r.team)) return refuse(`name row #${n}: team is not a valid database key`);
    if (!isSafeKey(r.name)) return refuse(`name row #${n}: name is not a valid database key`);
    rows.push({ sport: r.sport, season: r.season, team: r.team, name: r.name });
  });
  return rows;
}

// ---------------------------------------------------------------- planner

interface RelinkTarget {
  path: string;
  ref: RosterRef;
  /** The UID leaf's current value: an old uid, or null/'' for a name row. */
  before: string | null;
}

const rowLabel = (ref: RosterRef): string =>
  ref.kind === 'league'
    ? `${ref.sport} Season ${ref.season}, ${ref.team}, "${ref.name}"`
    : `AFC San Jose "${ref.season}", "${ref.name}"`;

interface ClusterPlan {
  writes: PlanWrite[];
  summary: string[];
  reasons: string[];
}

function planCluster(
  c: MergeCluster,
  who: string,
  snap: MergeSnapshot,
  nowMs: number,
  uidUse: Map<string, number>,
): ClusterPlan {
  const reasons: string[] = [];
  const refuse = (why: string): void => {
    reasons.push(why);
  };
  const done = (writes: PlanWrite[] = [], summary: string[] = []): ClusterPlan => ({ writes, summary, reasons });

  // ---- shape of the map entry (nothing is read from the snapshot yet)
  const keep = c.keep;
  const olds: string[] = Array.isArray(c.old) ? c.old : [];
  if (!Array.isArray(c.old)) refuse('"old" must be a list of uids');
  if (!isUid(keep)) refuse('the kept uid is missing or not a valid database key');
  if (olds.some((o) => !isUid(o))) refuse('an old uid is missing or not a valid database key');
  if (new Set(olds).size !== olds.length) refuse('an old uid is listed twice');
  if (olds.includes(keep)) refuse('the kept uid is also listed as old');
  if ([keep, ...olds].some((u) => (uidUse.get(u) ?? 0) > 1)) {
    refuse('an account in this cluster also appears in another cluster');
  }
  const nameRows = validNameRows(c, refuse);
  const fix = c.firstNameFix;
  if (fix !== undefined && !isValidFirstName(fix)) {
    refuse(`firstNameFix must be 1-${MAX_FIRST_NAME} printable characters with no surrounding spaces`);
  }
  if (reasons.length > 0) return done();

  // ---- the accounts
  const keepNode = snap.nodes[userPath(keep)];
  if (!isPlainMap(keepNode)) refuse('the kept account has no Users node in the snapshot');
  else if (nonEmptyString(keepNode['MergedInto'])) {
    refuse('the kept account is itself merged into another account');
  }
  const oldNodes: Array<Record<string, unknown>> = [];
  for (const o of olds) {
    const node = snap.nodes[userPath(o)];
    if (!isPlainMap(node)) {
      refuse('an old account has no Users node in the snapshot');
      continue;
    }
    const into = node['MergedInto'];
    if (nonEmptyString(into) && into !== keep) {
      refuse('an old account is already merged into a different account');
    }
    oldNodes.push(node);
  }
  const hintRaw = snap.keptHints?.[keep];
  const hint = hintRaw === undefined || hintRaw === null || hintRaw === '' ? null : hintRaw;
  if (hint !== null && !looksMasked(hint)) refuse('the kept email hint is not masked');
  if (reasons.length > 0 || !isPlainMap(keepNode)) return done();

  // ---- roster rows to relink: every row holding an old uid, plus name rows
  const oldSet = new Set(olds);
  const targets = new Map<string, RelinkTarget>();
  for (const path of Object.keys(snap.nodes).sort()) {
    const ref = parseRosterUidPath(path);
    const value = snap.nodes[path];
    if (ref && typeof value === 'string' && oldSet.has(value)) {
      targets.set(path, { path, ref, before: value });
    }
  }
  for (const r of nameRows) {
    const path = leagueUidPath(r.sport, r.season, r.team, r.name);
    const ref: RosterRef = { kind: 'league', ...r };
    if (!hasOwn(snap.nodes, path)) {
      refuse(`roster row ${rowLabel(ref)} was not found in the snapshot`);
      continue;
    }
    const value = snap.nodes[path];
    if (value === null || value === undefined || value === '') {
      targets.set(path, { path, ref, before: value === '' ? '' : null });
    } else if (value === keep || (typeof value === 'string' && oldSet.has(value))) {
      // already linked to the kept account / collected by the scan above
    } else {
      refuse(`roster row ${rowLabel(ref)} already belongs to a different account`);
    }
  }
  const ordered = [...targets.values()].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  const leagueTargets = ordered.filter((t) => t.ref.kind === 'league');

  // ---- D2: never relink in a fantasy season
  const seasonsChecked = new Set<string>();
  for (const t of leagueTargets) {
    if (t.ref.kind !== 'league') continue;
    const label = `${t.ref.sport} Season ${t.ref.season}`;
    if (seasonsChecked.has(label)) continue;
    seasonsChecked.add(label);
    const cfg = fantasyConfigPath(t.ref.sport, t.ref.season);
    if (!hasOwn(snap.nodes, cfg)) {
      refuse(`${label}: the snapshot has no fantasy Config check for this season`);
    } else if (snap.nodes[cfg] !== null && snap.nodes[cfg] !== undefined) {
      refuse(`${label} is a fantasy season (its fantasy Config exists), so its roster rows must not be relinked`);
    }
  }

  // ---- D3: Played entries, refusing a clash with a different team
  const played: PlanWrite[] = [];
  const plannedTeam = new Map<string, string>();
  const keepPlayed = isPlainMap(keepNode['Played']) ? keepNode['Played'] : {};
  for (const t of leagueTargets) {
    if (t.ref.kind !== 'league') continue;
    const { sport, season, team } = t.ref;
    const key = `${sport}|${season}`;
    const label = `${sport} Season ${season}`;
    const prior = plannedTeam.get(key);
    if (prior !== undefined) {
      if (prior !== team) refuse(`${label}: old accounts were on two different teams ("${prior}" and "${team}")`);
      continue;
    }
    plannedTeam.set(key, team);
    const bySport = keepPlayed[sport];
    const existing = isPlainMap(bySport) ? bySport[`Season ${season}`] : undefined;
    if (existing === undefined || existing === null) {
      played.push({ path: playedPath(keep, sport, season), before: null, after: team });
    } else if (existing !== team) {
      const had = typeof existing === 'string' ? `"${existing}"` : 'another value';
      refuse(`${label}: the kept account already has ${had} for that season but the old row says "${team}"`);
    }
  }
  if (reasons.length > 0) return done();

  // ---- D4: profile photo link and missing Information leaves
  const profile: PlanWrite[] = [];
  const summary: string[] = [];
  if (lacks(keepNode['ProfileUrl'])) {
    // Rulings: the LAST listed old account that has a ProfileUrl wins
    // (the map lists old accounts oldest -> newest).
    for (let i = oldNodes.length - 1; i >= 0; i--) {
      const url = oldNodes[i]['ProfileUrl'];
      if (typeof url === 'string' && url.trim() !== '') {
        profile.push({ path: `${userPath(keep)}/ProfileUrl`, before: keepNode['ProfileUrl'] ?? null, after: url });
        summary.push(`${who}: copy the profile photo link from an old account`);
        break;
      }
    }
  }
  const keepInfoRaw = keepNode['Information'];
  if (keepInfoRaw === undefined || keepInfoRaw === null || isPlainMap(keepInfoRaw)) {
    const keepInfo = isPlainMap(keepInfoRaw) ? keepInfoRaw : {};
    const chosen = new Map<string, unknown>();
    for (const node of oldNodes) {
      const info = node['Information'];
      if (!isPlainMap(info)) continue;
      for (const [leaf, value] of Object.entries(info)) {
        if (isCopyableInformation(leaf, value)) chosen.set(leaf, value);
      }
    }
    const copied: string[] = [];
    for (const leaf of [...chosen.keys()].sort()) {
      if (!lacks(keepInfo[leaf])) continue;
      profile.push({ path: `${userPath(keep)}/Information/${leaf}`, before: keepInfo[leaf] ?? null, after: chosen.get(leaf) });
      copied.push(leaf);
    }
    if (copied.length > 0) summary.push(`${who}: copy missing Information fields (${copied.join(', ')})`);
  }
  if (fix !== undefined && keepNode['First Name'] !== fix) {
    profile.push({ path: `${userPath(keep)}/First Name`, before: keepNode['First Name'] ?? null, after: fix });
    summary.push(`${who}: fix the kept account's first name (owner request)`);
  }

  // ---- D5: stamp each old account (only leaves it does not have yet)
  const stamps: PlanWrite[] = [];
  let stamped = 0;
  let missingHint = false;
  for (let i = 0; i < olds.length; i++) {
    const node = oldNodes[i];
    const base = userPath(olds[i]);
    const before = stamps.length;
    if (!nonEmptyString(node['MergedInto'])) stamps.push({ path: `${base}/MergedInto`, before: null, after: keep });
    if (node['MergedAt'] === undefined || node['MergedAt'] === null) {
      stamps.push({ path: `${base}/MergedAt`, before: null, after: nowMs });
    }
    if (lacks(node['MergedHint'])) {
      if (hint !== null) stamps.push({ path: `${base}/MergedHint`, before: null, after: hint });
      else missingHint = true;
    }
    if (stamps.length > before) stamped++;
  }
  if (stamped > 0) summary.push(`${who}: stamp ${stamped} old account(s) as merged`);
  if (missingHint) summary.push(`${who}: no kept-email hint available - the notice will say "your other email"`);

  // ---- assemble in the crash-safe order
  const roster: PlanWrite[] = ordered.map((t) => ({ path: t.path, before: t.before, after: keep }));
  const rowLines = ordered.map((t) =>
    `${who}: relink ${rowLabel(t.ref)}${t.ref.kind === 'league' ? ' and add it to seasons played' : ''}`,
  );
  const writes = [...played, ...profile, ...roster, ...stamps];
  const lines = writes.length === 0 ? [`${who}: already merged - nothing to do`] : [...rowLines, ...summary];
  return done(writes, lines);
}

/** Plan every cluster of the map against the snapshot. A refusal blocks
 *  that whole cluster (no write of it is planned) and nothing else. */
export function buildMergePlan(map: MergeMap, snap: MergeSnapshot, nowMs: number): MergePlan {
  if (!Number.isInteger(nowMs) || nowMs <= 0) {
    throw new Error('buildMergePlan: nowMs must be a positive integer (epoch milliseconds)');
  }
  if (!map || !Array.isArray(map.clusters)) throw new Error('buildMergePlan: the map has no clusters list');
  const uidUse = new Map<string, number>();
  for (const c of map.clusters) {
    const uids = new Set<string>([c?.keep, ...(Array.isArray(c?.old) ? c.old : [])].filter(isUid));
    for (const u of uids) uidUse.set(u, (uidUse.get(u) ?? 0) + 1);
  }
  const out: MergePlan = { writes: [], refusals: [], summary: [] };
  map.clusters.forEach((c, i) => {
    const who = typeof c?.who === 'string' && c.who.trim() !== '' ? c.who.trim() : `cluster #${i + 1}`;
    const plan = planCluster(c, who, snap, nowMs, uidUse);
    if (plan.reasons.length > 0) {
      for (const why of plan.reasons) out.refusals.push({ who, why });
      out.summary.push(`${who}: REFUSED - nothing planned (see refusals)`);
      return;
    }
    out.writes.push(...plan.writes);
    out.summary.push(...plan.summary);
  });
  return out;
}

// -------------------------------------------------------------- allowlist

/** The snapshot's value at a path (undefined -> null). `Users/<uid>/...`
 *  leaves are read inside the carried `Users/<uid>` node. */
function snapshotValue(snap: MergeSnapshot, path: string): unknown {
  const m = /^Users\/([^/]+)\/(.+)$/.exec(path);
  if (!m) return hasOwn(snap.nodes, path) ? snap.nodes[path] ?? null : null;
  let cur: unknown = snap.nodes[userPath(m[1])];
  for (const seg of m[2].split('/')) {
    if (!isPlainMap(cur)) return null;
    cur = cur[seg];
  }
  return cur ?? null;
}

const STAMP_LEAVES = ['MergedInto', 'MergedAt', 'MergedHint'];

/** The allowlist: every write of a merge must be one of the D1 / D2 / D3 /
 *  D4 / D5 / D10 leaves for a cluster of the map, with a `before` that still
 *  matches the snapshot, or the whole list is refused (throws). It never
 *  allows a whole `Users/<uid>` node, a removal, a Token or any private
 *  leaf, a uid outside the map, a roster key, or a fantasy-season relink. */
export function assertMergePaths(
  writes: ReadonlyArray<PlanWrite>,
  map: MergeMap,
  snap: MergeSnapshot,
): void {
  const keepOf = new Map<string, MergeCluster>();
  const oldOf = new Map<string, MergeCluster>();
  for (const c of map.clusters) {
    if (typeof c.keep === 'string') keepOf.set(c.keep, c);
    for (const o of Array.isArray(c.old) ? c.old : []) oldOf.set(o, c);
  }
  const nameRowPaths = (c: MergeCluster): Set<string> =>
    new Set(
      (Array.isArray(c.nameRows) ? c.nameRows : [])
        .filter((r) => isPlainMap(r) && [r.sport, r.season, r.team, r.name].every((x) => typeof x === 'string'))
        .map((r) => leagueUidPath(r.sport, r.season, r.team, r.name)),
    );

  // Every league relink in the list, so a Played entry can be matched to one.
  const relinks = new Set<string>();
  for (const w of writes) {
    const ref = isPlainMap(w) ? parseRosterUidPath(w.path) : null;
    if (ref && ref.kind === 'league' && typeof w.after === 'string') {
      relinks.add(`${w.after}|${ref.sport}|${ref.season}|${ref.team}`);
    }
  }

  const seen = new Set<string>();
  for (const w of writes) {
    const path = isPlainMap(w) ? w.path : undefined;
    const fail: (reason: string) => never = (reason) => {
      throw new Error(`Refusing merge path ${JSON.stringify(path)}: ${reason}`);
    };
    if (typeof path !== 'string' || path.length === 0) return fail('the path is not a string');
    if (seen.has(path)) fail('it is written twice in one plan');
    seen.add(path);
    if (w.after === null || w.after === undefined) fail('a merge never removes data (after is null)');
    const current = snapshotValue(snap, path);
    if (!isDeepStrictEqual(w.before ?? null, current)) fail('its before value no longer matches the snapshot');

    // ---- roster UID leaves (D1, D2)
    const ref = parseRosterUidPath(path);
    if (ref) {
      const cluster = typeof w.after === 'string' ? keepOf.get(w.after) : undefined;
      if (!cluster || oldOf.has(w.after as string)) fail('the new UID is not a kept account of the map');
      const c = cluster as MergeCluster;
      const before = w.before ?? null;
      const fromOld = typeof before === 'string' && (c.old ?? []).includes(before);
      const emptyNameRow = (before === null || before === '') && nameRowPaths(c).has(path) && hasOwn(snap.nodes, path);
      if (!fromOld && !emptyNameRow) {
        fail('the row is neither held by an old account of this cluster nor one of its listed name rows');
      }
      if (ref.kind === 'league') {
        const label = `${ref.sport} Season ${ref.season}`;
        const cfg = fantasyConfigPath(ref.sport, ref.season);
        if (!hasOwn(snap.nodes, cfg)) fail(`${label}: no fantasy Config check in the snapshot`);
        if (snap.nodes[cfg] !== null && snap.nodes[cfg] !== undefined) {
          fail(`${label} is a fantasy season (its fantasy Config exists)`);
        }
      }
      continue;
    }

    // ---- Users/<uid>/<leaf>
    const m = /^Users\/([^/]+)\/(.+)$/.exec(path);
    if (!m) return fail('it is outside the merge allowlist');
    const [, uid, rest] = m;
    const isKeep = keepOf.has(uid);
    const isOld = oldOf.has(uid);
    if (isKeep && isOld) fail('the uid is both a kept and an old account in the map');
    if (!isKeep && !isOld) fail('the uid is not in the merge map');

    if (isOld) {
      const c = oldOf.get(uid) as MergeCluster;
      if (!STAMP_LEAVES.includes(rest)) fail('only MergedInto, MergedAt and MergedHint may be written on an old account');
      if (w.before !== null && w.before !== undefined) fail('a stamp may only fill a leaf that is empty');
      if (rest === 'MergedInto' && w.after !== c.keep) fail('MergedInto must be the kept account of this cluster');
      if (rest === 'MergedAt' && !(typeof w.after === 'number' && Number.isInteger(w.after) && w.after > 0)) {
        fail('MergedAt must be a positive epoch-millisecond number');
      }
      if (rest === 'MergedHint') {
        if (!looksMasked(w.after) || w.after !== snap.keptHints?.[c.keep]) {
          fail('MergedHint must be exactly the masked hint of the kept account');
        }
      }
      continue;
    }

    const c = keepOf.get(uid) as MergeCluster;
    const oldNodes = (c.old ?? []).map((o) => snap.nodes[userPath(o)]).filter(isPlainMap);
    const played = /^Played\/([^/]+)\/Season (\d+)$/.exec(rest);
    if (played) {
      const [, sport, season] = played;
      if (!LEAGUE_SPORTS.includes(sport)) fail('Played is only written for league sports');
      if (typeof w.after !== 'string' || w.after.length === 0) fail('a Played value is a team name');
      if (w.before !== null && w.before !== undefined) fail('a Played entry is never written over a value');
      if (!relinks.has(`${uid}|${sport}|${season}|${w.after}`)) {
        fail('there is no matching roster relink in this plan for this Played entry');
      }
    } else if (rest === 'ProfileUrl') {
      if (typeof w.after !== 'string' || w.after.trim() === '') fail('ProfileUrl must be a non-empty string');
      if (!lacks(w.before)) fail('ProfileUrl is only copied when the kept account lacks one');
      if (!oldNodes.some((n) => n['ProfileUrl'] === w.after)) {
        fail('ProfileUrl may only be copied from an old account of this cluster');
      }
    } else if (rest.startsWith('Information/')) {
      const leaf = rest.slice('Information/'.length);
      if (leaf.includes('/') || !isCopyableInformation(leaf, w.after)) fail('this Information leaf may not be copied');
      if (!lacks(w.before)) fail('an Information leaf is only copied when the kept account lacks it');
      if (!oldNodes.some((n) => isPlainMap(n['Information']) && isDeepStrictEqual(n['Information'][leaf], w.after))) {
        fail('an Information leaf may only be copied from an old account of this cluster');
      }
    } else if (rest === 'First Name') {
      if (c.firstNameFix === undefined || w.after !== c.firstNameFix) {
        fail('First Name is only written for the cluster with a firstNameFix, and only to that value');
      }
    } else {
      fail('this leaf of a kept account is not on the allowlist');
    }
  }
}
