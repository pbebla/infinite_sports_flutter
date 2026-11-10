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
//   D10 optionally fix the kept account's First Name (owner request);
//   E2  move each old account's paid / not-paid sign-up records
//       (`Sign Ups/<league>/<S>/<Paid|NotPaid>/<uid>` - a text value, the
//       player's display name) to the kept account: a copy, then a remove of
//       the old key. The one and only removal this tool ever plans.
// Everything else on an old account (votes, Token, its Played...) is left
// exactly as it is (D14), and `Comments/<displayName>` is never touched.
//
// Snapshot contract (what the CLI must hand over, all keyed by full path):
//   `Users/<uid>`                    the user node of every keep and old uid
//                                    (a missing node -> the cluster is refused);
//   `<Sport>/<S>/Line Ups/<team>/<name>/UID` and
//   `AFC San Jose/Seasons/<S>/Roster/<name>/UID`
//                                    the UID leaf of every roster row that
//                                    holds an old uid (that is how old-uid
//                                    rows are found);
//   `<Sport>/<S>/Line Ups/<team>/<name>`
//                                    the roster row NODE itself (a map) of
//                                    every row a cluster's nameRows names -
//                                    READ THE PARENT ROW, not only the leaf.
//                                    A name row is planned only if this is a
//                                    map (absent or non-map = "roster row not
//                                    found": a write would create a stray
//                                    row); the relink write is still the
//                                    `.../UID` leaf and its `before` is
//                                    `row.UID ?? null`. If a UID leaf key is
//                                    also present it must agree with the row;
//   `Fantasy/<Sport>/<S>/Config`     for every league season a relink would
//                                    touch: any non-null value = the Config
//                                    exists, null = checked and absent, key
//                                    absent = not checked (refused: fail closed).
//   `Fantasy/<Sport>/<S>/TestFill`   (E1) for every league season a relink would
//                                    touch whose Config exists: any non-null value
//                                    = the fantasy TEST season (its fill is
//                                    applied, the roster trigger stands down),
//                                    null = checked and absent (a LIVE fantasy
//                                    season: refused), key absent = not checked
//                                    (refused: fail closed). No Config -> no
//                                    TestFill key is needed;
//   `Sign Ups/<League>`              (E2) for EVERY league sport (Futsal, Basketball,
//                                    Flag Football), whenever a cluster has an old
//                                    account and has not opted out: the shallow
//                                    season keys of that league's sign-ups ({season:
//                                    true}; null = the league has no sign-ups). A
//                                    missing key = "sign-ups were not scanned" and
//                                    refuses the cluster (a skipped scan must never
//                                    look like "nothing to move"). The seasons
//                                    checked are exactly the listed numeric keys;
//   `Sign Ups/<League>/<S>/<Paid|NotPaid>/<uid>`
//                                    (E2) for every LISTED season: BOTH statuses for
//                                    EVERY old uid and the kept uid of the cluster -
//                                    the text value, or null when absent. A leaf of a
//                                    listed season missing from the snapshot refuses
//                                    the cluster (fail closed); an old account's
//                                    value that is blank (or only whitespace) or not
//                                    text refuses it, and so does the kept account's
//                                    in a season where an old account has a record
//                                    (a season where only the kept account has one is
//                                    "nothing to do");
//   keptHints[keep]                  the kept email, ALREADY MASKED (maskEmail).
//
// Old-account data this tool does NOT move (a cluster with any is REFUSED, so
// it is moved by hand first; every check below fails closed - a snapshot that
// never made it is refused too, and none of it carries contents, only keys):
//   `Users/<old>/Awards`, `Users/<old>/TournamentsPlayed`
//                                    non-empty (they are in the Users node);
//   `Fantasy/<Sport>`                for every league sport: the shallow season
//                                    keys of that fantasy tree (null = none);
//   `Fantasy/<Sport>/<S>/Config`     (see above) must be present for EVERY
//                                    listed season, not only touched ones;
//   `Fantasy/<Sport>/<S>/Managers`   for every listed season whose Config
//                                    exists: the shallow manager uids ({uid:
//                                    true}, null = none). An old uid in it
//                                    refuses the cluster;
//   `Registrations`                  the shallow form ids (null = none);
//   `Registrations/<id>/Submissions` for every listed form: the shallow
//                                    submitter uids. An old uid in it refuses.
//
// Write order inside a cluster is deliberate: Played, profile fields, roster
// UID relinks, sign-up copies, sign-up removes, and the stamps LAST - and per
// old account MergedHint, then MergedAt, then MergedInto. A crash part-way
// leaves a state that a rerun finishes without duplicating anything
// (MergedInto is the "done" marker - it triggers the public-profile mirror and
// the app's notice, so it only appears once the other two stamps are there;
// the rows are only relinked after their Played entry exists; a sign-up record
// is only removed after its copy exists, and a crash between the two leaves a
// kept copy with the same value - a rerun plans only the remove). --undo is
// the reverse order.

import { isDeepStrictEqual } from 'util';
import { LEAGUE_SPORTS } from '../src/lib/account_deletion';
import { MASK_BULLET } from '../src/lib/mask_email';

/** The league sports whose rosters live under `<Sport>/<Season>/Line Ups`. */
export { LEAGUE_SPORTS };

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
  /** E2: move the old accounts' sign-up records to the kept account. Absent
   *  = true; `false` opts the cluster out; any other type refuses the map. */
  moveSignUps?: boolean;
}

export interface MergeMap {
  clusters: MergeCluster[];
}

export interface MergeSnapshot {
  nodes: Record<string, unknown>;
  keptHints: Record<string, string>;
}

/** One leaf write. `after: null` means "remove" - the merge plans exactly one
 *  kind of removal (an old account's sign-up record whose copy is on the kept
 *  account, E2); assertMergePaths refuses every other `after: null`. */
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

/** The fantasy TEST-season marker (written by the fill tool; presence = the
 *  fill is applied and the roster trigger stands down - E1). */
export const fantasyTestFillPath = (sport: string, season: string): string =>
  `Fantasy/${sport}/${season}/TestFill`;

export type SignUpStatus = 'Paid' | 'NotPaid';
export const SIGN_UP_STATUSES: readonly SignUpStatus[] = ['Paid', 'NotPaid'];

/** One sign-up leaf: its value is the player's display name (text). */
export const signUpPath = (league: string, season: string, status: string, uid: string): string =>
  `Sign Ups/${league}/${season}/${status}/${uid}`;

export type RosterRef =
  | { kind: 'league'; sport: string; season: string; team: string; name: string }
  | { kind: 'afc'; season: string; name: string };

const LEAGUE_UID_RE = new RegExp(
  `^(${LEAGUE_SPORTS.join('|')})/(\\d+)/Line Ups/([^/]+)/([^/]+)/UID$`,
);
const AFC_UID_RE = /^AFC San Jose\/Seasons\/([^/]+)\/Roster\/([^/]+)\/UID$/;
const SIGN_UP_RE = new RegExp(`^Sign Ups/(${LEAGUE_SPORTS.join('|')})/(\\d+)/(Paid|NotPaid)/([^/]+)$`);

export interface SignUpRef {
  league: string;
  season: string;
  status: SignUpStatus;
  uid: string;
}

/** A sign-up leaf path -> its parts, or null for any other path (only the
 *  league sports' numbered seasons; never the Due / Info / status nodes). */
export function parseSignUpPath(path: unknown): SignUpRef | null {
  if (typeof path !== 'string') return null;
  const m = SIGN_UP_RE.exec(path);
  return m ? { league: m[1], season: m[2], status: m[3] as SignUpStatus, uid: m[4] } : null;
}

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

/** Exactly the shape maskEmail produces: at most 2 visible characters, 1-8
 *  bullets, one `@`, then a domain with no `@` or whitespace. A raw email
 *  (no bullet) or `testplayer12•@example.test` (too much showing) fails. */
const MASKED_HINT_RE = new RegExp(`^[^@\\s${MASK_BULLET}]{0,2}${MASK_BULLET}{1,8}@[^@\\s]+$`, 'u');
export function looksMasked(hint: unknown): hint is string {
  return typeof hint === 'string' && MASKED_HINT_RE.test(hint);
}

/** D4: may this Information leaf/value be copied? Scalar values only and
 *  never a private-looking key (Token, email-like, phone...). */
export function isCopyableInformation(leaf: string, value: unknown): boolean {
  if (typeof leaf !== 'string' || !INFO_LEAF_RE.test(leaf) || SENSITIVE_LEAF_RE.test(leaf)) return false;
  if (typeof value === 'string') return value.trim().length > 0 && value.length <= 200;
  if (typeof value === 'number') return Number.isFinite(value);
  return typeof value === 'boolean';
}

/** D10's fix value: a plain name - no surrounding spaces, no control
 *  characters, none of `/ . # $ [ ]`. Shared by the planner and the allowlist. */
const isValidFirstName = (v: unknown): v is string =>
  typeof v === 'string' &&
  v.trim() === v &&
  v.length > 0 &&
  v.length <= MAX_FIRST_NAME &&
  !/[\u0000-\u001f\u007f/.#$[\]]/.test(v);

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

const present = (v: unknown): boolean => v !== undefined && v !== null;
const keysOf = (v: unknown): string[] => (isPlainMap(v) ? Object.keys(v) : []);

/** Problems that make a whole map unfit to apply (checked independently by
 *  assertMergePaths, whatever the planner did): every uid a plain database
 *  key, none used twice (in one cluster or across clusters, as keep or old),
 *  valid name rows, at most one cluster with a firstNameFix, that fix a
 *  plain name, and `moveSignUps` (when present) a boolean. */
function mapProblems(map: MergeMap): string[] {
  const out: string[] = [];
  if (!map || !Array.isArray(map.clusters)) return ['the map has no clusters list'];
  const firstUse = new Map<string, number>();
  let fixes = 0;
  map.clusters.forEach((c, i) => {
    const tag = `cluster #${i + 1}`;
    if (!isPlainMap(c)) {
      out.push(`${tag} is not an object`);
      return;
    }
    const uids: string[] = [];
    if (isUid(c.keep)) uids.push(c.keep);
    else out.push(`${tag}: the kept uid is not a valid database key`);
    if (!Array.isArray(c.old)) out.push(`${tag}: "old" must be a list of uids`);
    else {
      for (const o of c.old) {
        if (isUid(o)) uids.push(o);
        else out.push(`${tag}: an old uid is not a valid database key`);
      }
    }
    const own = new Set<string>();
    for (const u of uids) {
      if (own.has(u)) out.push(`${tag}: a uid is listed twice (or is both kept and old)`);
      own.add(u);
    }
    for (const u of own) {
      const first = firstUse.get(u);
      if (first !== undefined) out.push(`${tag}: a uid also appears in cluster #${first + 1}`);
      else firstUse.set(u, i);
    }
    validNameRows(c, (why) => out.push(`${tag}: ${why}`));
    if (c.firstNameFix !== undefined) {
      fixes++;
      if (!isValidFirstName(c.firstNameFix)) out.push(`${tag}: firstNameFix is not a plain name`);
    }
    if (c.moveSignUps !== undefined && typeof c.moveSignUps !== 'boolean') {
      out.push(`${tag}: moveSignUps must be true or false`);
    }
  });
  if (fixes > 1) out.push('more than one cluster has a firstNameFix (D10 allows exactly one)');
  return out;
}

const rowPathOf = (uidPath: string): string => uidPath.slice(0, -'/UID'.length);

/** True when [v] holds something: a non-blank string, a number or boolean, or
 *  a non-empty map or list (RTDB never stores an empty one, but be exact). */
function hasContent(v: unknown): boolean {
  if (v === undefined || v === null) return false;
  if (typeof v === 'string') return v.trim() !== '';
  if (Array.isArray(v)) return v.length > 0;
  if (isPlainMap(v)) return Object.keys(v).length > 0;
  return true;
}

/** Old-account data this tool does NOT move (final-review fix 4): Awards,
 *  TournamentsPlayed, a fantasy manager entry in any fantasy season, a
 *  registration submission. Merging the account would leave it behind on an
 *  account nobody signs in to any more, so the cluster is refused (plain
 *  reasons - never a value, a form id or a uid) and the owner moves it by
 *  hand first. Fail closed: a snapshot that never checked is refused too. */
function unmovedDataReasons(oldNodes: ReadonlyArray<Record<string, unknown>>, snap: MergeSnapshot, olds: readonly string[]): string[] {
  const out: string[] = [];
  for (const node of oldNodes) {
    if (hasContent(node['Awards'])) out.push('an old account has Awards, which this tool does not move');
    if (hasContent(node['TournamentsPlayed'])) out.push('an old account has TournamentsPlayed, which this tool does not move');
  }
  const heldBy = (listing: unknown): boolean => keysOf(listing).some((k) => olds.includes(k));
  for (const sport of LEAGUE_SPORTS) {
    const listPath = `Fantasy/${sport}`;
    if (!hasOwn(snap.nodes, listPath)) {
      out.push(`${sport}: the snapshot has no fantasy season listing`);
      continue;
    }
    for (const season of keysOf(snap.nodes[listPath]).filter((k) => SEASON_RE.test(k)).sort()) {
      const label = `${sport} Season ${season}`;
      const cfg = fantasyConfigPath(sport, season);
      if (!hasOwn(snap.nodes, cfg)) {
        out.push(`${label}: the snapshot has no fantasy Config check for this season`);
        continue;
      }
      if (snap.nodes[cfg] === null || snap.nodes[cfg] === undefined) continue; // no fantasy there
      const managers = `${cfg.slice(0, -'/Config'.length)}/Managers`;
      if (!hasOwn(snap.nodes, managers)) out.push(`${label}: the snapshot has no fantasy manager check for this season`);
      else if (heldBy(snap.nodes[managers])) {
        out.push(`${label}: an old account has a fantasy manager entry in this season, which this tool does not move`);
      }
    }
  }
  if (!hasOwn(snap.nodes, 'Registrations')) {
    out.push('the snapshot has no registration check');
  } else {
    for (const id of keysOf(snap.nodes['Registrations'])) {
      const subs = `Registrations/${id}/Submissions`;
      if (!hasOwn(snap.nodes, subs)) out.push('the snapshot has no registration check for one of the forms');
      else if (heldBy(snap.nodes[subs])) out.push('an old account has a registration submission, which this tool does not move');
    }
  }
  return out;
}

type RowUid = { kind: 'absent' } | { kind: 'conflict' } | { kind: 'value'; value: unknown };

/** What the snapshot says a roster row's UID is: the row node's `UID` (when
 *  the row node is a map) and/or the UID leaf key (when present). When both
 *  are there they must agree, else 'conflict'. */
function readRowUid(snap: MergeSnapshot, uidPath: string): RowUid {
  const row = snap.nodes[rowPathOf(uidPath)];
  const leafPresent = hasOwn(snap.nodes, uidPath);
  if (!isPlainMap(row) && !leafPresent) return { kind: 'absent' };
  const fromRow = isPlainMap(row) ? row['UID'] ?? null : undefined;
  const fromLeaf = leafPresent ? snap.nodes[uidPath] ?? null : undefined;
  if (fromRow !== undefined && fromLeaf !== undefined && !isDeepStrictEqual(fromRow, fromLeaf)) {
    return { kind: 'conflict' };
  }
  return { kind: 'value', value: fromRow !== undefined ? fromRow : fromLeaf };
}

// ------------------------------------------------------- sign-up records (E2)

interface SignUpRecord {
  uid: string;
  status: SignUpStatus;
  value: string;
}

interface SignUpGroup {
  league: string;
  season: string;
  /** The records the cluster's OLD accounts hold in this season (either status). */
  olds: SignUpRecord[];
  /** The record(s) the KEPT account holds in this season (either status). */
  kept: SignUpRecord[];
  /** Why the snapshot cannot be used for this season (a leaf missing, or an
   *  old account's value that is blank / not text). */
  problem?: string;
  /** The kept account's value is blank / not text: it only matters in a season
   *  where an old account has a record to move (decideSignUps). */
  keptProblem?: string;
}

const signUpLabel = (league: string, season: string): string => `${league} Season ${season}`;

/** A sign-up value that can be moved: text with something in it. (A value with
 *  trailing spaces is fine and is copied byte for byte; blank or whitespace-only
 *  is "blank" - refused, the same as everywhere else in this tool.) */
const isSignUpText = (v: unknown): v is string => typeof v === 'string' && v.trim().length > 0;

/** The seasons that hold sign-ups for one league sport, from its listing
 *  (`Sign Ups/<League>` = {season: true}, null = none). A listing that was never
 *  read (key absent) or is not a map is a problem - "sign-ups were not scanned". */
function signUpListing(snap: MergeSnapshot, league: string): { seasons: string[] } | { problem: string } {
  const key = `Sign Ups/${league}`;
  if (!hasOwn(snap.nodes, key)) {
    return { problem: `${league}: sign-ups were not scanned (the snapshot has no sign-up listing for this league)` };
  }
  const listing = snap.nodes[key];
  if (listing === null || listing === undefined) return { seasons: [] };
  if (!isPlainMap(listing)) return { problem: `${league}: the sign-up listing is not a list of seasons` };
  return {
    seasons: Object.keys(listing).filter((k) => SEASON_RE.test(k)).sort((a, b) => Number(a) - Number(b)),
  };
}

/** The leaves of one LISTED league season the planner and the allowlist rely
 *  on: BOTH statuses for every old uid and the kept uid. A leaf that is missing
 *  from the snapshot (never read) is a `problem` - fail closed; so is an old
 *  account's value that is blank or not text. The kept account's own bad value is
 *  a `keptProblem` (only matters when an old account has a record there). */
function readSignUpGroup(
  snap: MergeSnapshot,
  keep: string,
  olds: readonly string[],
  league: string,
  season: string,
): SignUpGroup {
  const group: SignUpGroup = { league, season, olds: [], kept: [] };
  const label = signUpLabel(league, season);
  const notText = `${label}: a sign-up record there is blank or not text, so it cannot be moved`;
  for (const uid of [...olds, keep]) {
    for (const status of SIGN_UP_STATUSES) {
      const path = signUpPath(league, season, status, uid);
      if (!hasOwn(snap.nodes, path)) {
        group.problem ??= `${label}: the snapshot has no sign-up check for this season`;
        continue;
      }
      const value = snap.nodes[path];
      if (value === null || value === undefined) continue;
      if (!isSignUpText(value)) {
        if (uid === keep) group.keptProblem ??= notText;
        else group.problem ??= notText;
        continue;
      }
      (uid === keep ? group.kept : group.olds).push({ uid, status, value });
    }
  }
  return group;
}

type SignUpDecision =
  | { kind: 'none' }
  /** The kept account has no record: copy it, then remove every old copy. */
  | { kind: 'move'; status: SignUpStatus; value: string }
  /** The kept account already holds exactly that record: only the removes. */
  | { kind: 'finish'; status: SignUpStatus; value: string }
  | { kind: 'refuse'; why: string };

/** E2's three-way rule for one league season (a group without a `problem`). */
function decideSignUps(g: SignUpGroup): SignUpDecision {
  if (g.olds.length === 0) return { kind: 'none' }; // nothing to move (kept may hold its own)
  if (g.keptProblem !== undefined) return { kind: 'refuse', why: g.keptProblem };
  const label = signUpLabel(g.league, g.season);
  const combos = new Set(g.olds.map((r) => `${r.status}\u0000${r.value}`));
  if (combos.size > 1) {
    return {
      kind: 'refuse',
      why: `${label}: the old accounts hold sign-up records there that disagree (another name or payment status), so none were moved`,
    };
  }
  const { status, value } = g.olds[0];
  if (g.kept.length === 0) return { kind: 'move', status, value };
  if (g.kept.length === 1 && g.kept[0].status === status && g.kept[0].value === value) {
    return { kind: 'finish', status, value };
  }
  return {
    kind: 'refuse',
    why: `${label}: the kept account already has a sign-up record there that differs from the old one (another name or payment status), so none were moved`,
  };
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

interface MapContext {
  uidUse: Map<string, number>;
  fixClusters: number;
}

function planCluster(
  c: MergeCluster,
  who: string,
  snap: MergeSnapshot,
  nowMs: number,
  ctx: MapContext,
): ClusterPlan {
  const reasons: string[] = [];
  const refuse = (why: string): void => {
    if (!reasons.includes(why)) reasons.push(why);
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
  if ([keep, ...olds].some((u) => (ctx.uidUse.get(u) ?? 0) > 1)) {
    refuse('an account in this cluster also appears in another cluster');
  }
  const nameRows = validNameRows(c, refuse);
  const fix = c.firstNameFix;
  if (fix !== undefined && !isValidFirstName(fix)) {
    refuse(
      `firstNameFix must be 1-${MAX_FIRST_NAME} characters, no surrounding spaces and none of / . # $ [ ]`,
    );
  }
  if (fix !== undefined && ctx.fixClusters > 1) {
    refuse('more than one cluster has a firstNameFix (only one owner name fix is allowed)');
  }
  if (c.moveSignUps !== undefined && typeof c.moveSignUps !== 'boolean') {
    refuse('moveSignUps must be true or false');
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
    // Stamp leaves: absent/null = missing; a good existing value = already
    // stamped; anything else (blank, wrong type) is refused so `before`
    // stays exact and an undo is exact.
    const into = node['MergedInto'];
    if (present(into)) {
      if (typeof into !== 'string' || into.trim() === '') {
        refuse('an old account has an unexpected MergedInto value (blank or not text)');
      } else if (into !== keep) refuse('an old account is already merged into a different account');
    }
    const at = node['MergedAt'];
    if (present(at) && !(typeof at === 'number' && Number.isFinite(at) && at > 0)) {
      refuse('an old account has an unexpected MergedAt value (not a positive number)');
    }
    const oldHint = node['MergedHint'];
    if (present(oldHint) && !(typeof oldHint === 'string' && oldHint.trim() !== '')) {
      refuse('an old account has an unexpected MergedHint value (blank or not text)');
    }
    oldNodes.push(node);
  }
  // Old-account data the merge would leave behind (Awards, tournaments,
  // fantasy manager entries, registration submissions): refuse the cluster.
  if (olds.length > 0) for (const why of unmovedDataReasons(oldNodes, snap, olds)) refuse(why);
  const hintRaw = snap.keptHints?.[keep];
  const hint = hintRaw === undefined || hintRaw === null || hintRaw === '' ? null : hintRaw;
  if (hint !== null && !looksMasked(hint)) refuse('the kept email hint is not masked');
  if (reasons.length > 0 || !isPlainMap(keepNode)) return done();

  // ---- roster rows to relink: every row holding an old uid, plus name rows
  const oldSet = new Set(olds);
  const targets = new Map<string, RelinkTarget>();
  for (const path of Object.keys(snap.nodes).sort()) {
    const ref = parseRosterUidPath(path);
    if (!ref) continue;
    const leaf = snap.nodes[path];
    const rowNode = snap.nodes[rowPathOf(path)];
    const viaRow = isPlainMap(rowNode) ? rowNode['UID'] : undefined;
    const isOurs = (v: unknown): boolean => typeof v === 'string' && oldSet.has(v);
    if (!isOurs(leaf) && !isOurs(viaRow)) continue;
    if (readRowUid(snap, path).kind === 'conflict') {
      refuse(`roster row ${rowLabel(ref)}: the snapshot disagrees with itself about its UID`);
      continue;
    }
    targets.set(path, { path, ref, before: leaf as string });
  }
  for (const r of nameRows) {
    const path = leagueUidPath(r.sport, r.season, r.team, r.name);
    const ref: RosterRef = { kind: 'league', ...r };
    // The row NODE must be in the snapshot (and be a map): a UID write to a
    // row that does not exist would create a stray roster row.
    if (!isPlainMap(snap.nodes[rowPathOf(path)])) {
      refuse(`roster row ${rowLabel(ref)} was not found in the snapshot (roster row not found)`);
      continue;
    }
    const got = readRowUid(snap, path);
    if (got.kind === 'conflict') {
      refuse(`roster row ${rowLabel(ref)}: the snapshot disagrees with itself about its UID`);
      continue;
    }
    const value = got.kind === 'value' ? got.value : null;
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

  // ---- D2 / E1: never relink in a LIVE fantasy season. A season whose fantasy
  // Config exists qualifies only when it is the fantasy TEST season (its
  // TestFill marker exists): the roster trigger stands down there before it
  // reads the market, while in any other fantasy season it would add every
  // roster name missing from the market. A snapshot that never checked fails
  // closed.
  const seasonsChecked = new Set<string>();
  const testSeasons: string[] = [];
  for (const t of leagueTargets) {
    if (t.ref.kind !== 'league') continue;
    const label = `${t.ref.sport} Season ${t.ref.season}`;
    if (seasonsChecked.has(label)) continue;
    seasonsChecked.add(label);
    const cfg = fantasyConfigPath(t.ref.sport, t.ref.season);
    if (!hasOwn(snap.nodes, cfg)) {
      refuse(`${label}: the snapshot has no fantasy Config check for this season`);
    } else if (snap.nodes[cfg] !== null && snap.nodes[cfg] !== undefined) {
      const fill = fantasyTestFillPath(t.ref.sport, t.ref.season);
      if (!hasOwn(snap.nodes, fill)) {
        refuse(`${label}: the snapshot has no fantasy TestFill check for this season`);
      } else if (snap.nodes[fill] === null || snap.nodes[fill] === undefined) {
        refuse(
          `${label} is a live fantasy season (its fantasy Config exists and it is not the test season), ` +
            'so its roster rows must not be relinked',
        );
      } else {
        testSeasons.push(label);
      }
    }
  }

  // ---- D3: Played entries, refusing a clash with a different team
  const played: Array<{ write: PlanWrite; sport: string; season: string; team: string }> = [];
  const plannedTeam = new Map<string, string>();
  const keepPlayedRaw = keepNode['Played'];
  const keepPlayed = isPlainMap(keepPlayedRaw) ? keepPlayedRaw : {};
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
    // A Played (or Played/<Sport>) that exists but is not a map would be
    // wiped by a leaf write under it: refuse instead of planning that.
    if (present(keepPlayedRaw) && !isPlainMap(keepPlayedRaw)) {
      refuse("the kept account's Played value is not a map, so seasons played cannot be added without wiping it");
      continue;
    }
    const bySport = keepPlayed[sport];
    if (present(bySport) && !isPlainMap(bySport)) {
      refuse(`the kept account's Played/${sport} value is not a map, so seasons played cannot be added without wiping it`);
      continue;
    }
    const existing = isPlainMap(bySport) ? bySport[`Season ${season}`] : undefined;
    if (existing === undefined || existing === null) {
      played.push({ write: { path: playedPath(keep, sport, season), before: null, after: team }, sport, season, team });
    } else if (existing !== team) {
      const had = typeof existing === 'string' ? `"${existing}"` : 'another value';
      refuse(`${label}: the kept account already has ${had} for that season but the old row says "${team}"`);
    }
  }

  // D4 Information: the leaves an old account has that are safe to copy.
  const chosen = new Map<string, unknown>();
  for (const node of oldNodes) {
    const info = node['Information'];
    if (!isPlainMap(info)) continue;
    for (const [leaf, value] of Object.entries(info)) {
      if (isCopyableInformation(leaf, value)) chosen.set(leaf, value);
    }
  }
  const keepInfoRaw = keepNode['Information'];
  if (chosen.size > 0 && present(keepInfoRaw) && !isPlainMap(keepInfoRaw)) {
    refuse("the kept account's Information value is not a map, so missing fields cannot be copied without wiping it");
  }

  // ---- E2: sign-up records move - a copy on the kept account, then a remove of
  // each old key. Per league season, the three-way rule (decideSignUps).
  const signCopies: PlanWrite[] = [];
  const signRemoves: PlanWrite[] = [];
  const signLines: string[] = [];
  if (c.moveSignUps !== false && olds.length > 0) {
    for (const league of LEAGUE_SPORTS) {
      // The seasons come from the league's LISTING, never from whatever leaves
      // the snapshot happens to hold; no listing = the scan was skipped = refuse.
      const listing = signUpListing(snap, league);
      if ('problem' in listing) {
        refuse(listing.problem);
        continue;
      }
      for (const season of listing.seasons) {
        const group = readSignUpGroup(snap, keep, olds, league, season);
        if (group.problem !== undefined) {
          refuse(group.problem);
          continue;
        }
        const decision = decideSignUps(group);
        if (decision.kind === 'refuse') {
          refuse(decision.why);
          continue;
        }
        if (decision.kind === 'none') continue;
        if (decision.kind === 'move') {
          signCopies.push({ path: signUpPath(league, season, decision.status, keep), before: null, after: decision.value });
        }
        for (const r of group.olds) {
          signRemoves.push({ path: signUpPath(league, season, r.status, r.uid), before: r.value, after: null });
        }
        signLines.push(
          `${who}: ${decision.kind === 'move' ? 'move' : 'finish moving'} his Season ${season} sign-up record ` +
            `(${league}, ${decision.status})`,
        );
      }
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
  const keepInfo = isPlainMap(keepInfoRaw) ? keepInfoRaw : {};
  const copied: string[] = [];
  for (const leaf of [...chosen.keys()].sort()) {
    if (!lacks(keepInfo[leaf])) continue;
    profile.push({ path: `${userPath(keep)}/Information/${leaf}`, before: keepInfo[leaf] ?? null, after: chosen.get(leaf) });
    copied.push(leaf);
  }
  if (copied.length > 0) summary.push(`${who}: copy missing Information fields (${copied.join(', ')})`);
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
    // Only absent/null counts as missing (anything else was validated above).
    // Order: MergedHint, MergedAt, then MergedInto LAST - MergedInto is the
    // "done" marker (it triggers the public-profile mirror and is what the
    // app's notice reads), so it only appears once the other two are there.
    if (!present(node['MergedHint'])) {
      if (hint !== null) stamps.push({ path: `${base}/MergedHint`, before: node['MergedHint'] ?? null, after: hint });
      else missingHint = true;
    }
    if (!present(node['MergedAt'])) {
      stamps.push({ path: `${base}/MergedAt`, before: node['MergedAt'] ?? null, after: nowMs });
    }
    if (!present(node['MergedInto'])) {
      stamps.push({ path: `${base}/MergedInto`, before: node['MergedInto'] ?? null, after: keep });
    }
    if (stamps.length > before) stamped++;
  }
  if (stamped > 0) summary.push(`${who}: stamp ${stamped} old account(s) as merged`);
  if (missingHint) summary.push(`${who}: no kept-email hint available - the notice will say "your other email"`);

  // ---- assemble in the crash-safe order
  const roster: PlanWrite[] = ordered.map((t) => ({ path: t.path, before: t.before, after: keep }));
  const rowLines = ordered.map(
    (t) =>
      `${who}: relink ${rowLabel(t.ref)}` +
      (t.ref.kind === 'league' && testSeasons.includes(`${t.ref.sport} Season ${t.ref.season}`)
        ? ' (fantasy test season - the market sync stands down)'
        : ''),
  );
  // One line per Played write that is really planned (not for a kept account
  // that already has the team, and once per season).
  const playedLines = played.map(
    (p) => `${who}: add ${p.sport} Season ${p.season} (${p.team}) to seasons played`,
  );
  const writes = [...played.map((p) => p.write), ...profile, ...roster, ...signCopies, ...signRemoves, ...stamps];
  const lines =
    writes.length === 0
      ? [`${who}: already merged - nothing to do`]
      : [...rowLines, ...playedLines, ...signLines, ...summary];
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
  const fixClusters = map.clusters.filter((c) => c?.firstNameFix !== undefined).length;
  const ctx: MapContext = { uidUse, fixClusters };
  const out: MergePlan = { writes: [], refusals: [], summary: [] };
  map.clusters.forEach((c, i) => {
    const who = typeof c?.who === 'string' && c.who.trim() !== '' ? c.who.trim() : `cluster #${i + 1}`;
    const plan = planCluster(c, who, snap, nowMs, ctx);
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
 *  D4 / D5 / D10 / E1 / E2 leaves for a cluster of the map, with a `before`
 *  that still matches the snapshot, or the whole list is refused (throws). It
 *  never allows a whole `Users/<uid>` node, a Token or any private leaf, a uid
 *  outside the map, a roster key, or a relink in a LIVE fantasy season (a
 *  fantasy TEST season is allowed, E1). The only removal it allows is E2's: an
 *  old account's sign-up record whose identical copy is on the kept account -
 *  earlier in the same list, or already there. */
export function assertMergePaths(
  writes: ReadonlyArray<PlanWrite>,
  map: MergeMap,
  snap: MergeSnapshot,
): void {
  // The map is validated here too, whatever the planner did with it.
  const problems = mapProblems(map);
  if (problems.length > 0) throw new Error(`Refusing merge map: ${problems.join('; ')}`);

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

  // Where each path sits in the list (a sign-up remove must come after its copy).
  const position = new Map<string, number>();
  writes.forEach((x, i) => {
    if (isPlainMap(x) && typeof x.path === 'string' && !position.has(x.path)) position.set(x.path, i);
  });

  const seen = new Set<string>();
  for (const w of writes) {
    const path = isPlainMap(w) ? w.path : undefined;
    const fail: (reason: string) => never = (reason) => {
      throw new Error(`Refusing merge path ${JSON.stringify(path)}: ${reason}`);
    };
    if (typeof path !== 'string' || path.length === 0) return fail('the path is not a string');
    if (seen.has(path)) fail('it is written twice in one plan');
    seen.add(path);
    const signUp = parseSignUpPath(path);
    // A removal is only ever an old account's sign-up record (checked below).
    if (w.after === undefined || (w.after === null && !signUp)) fail('a merge never removes data (after is null)');
    const ref = parseRosterUidPath(path);
    let current: unknown;
    if (ref) {
      const got = readRowUid(snap, path);
      if (got.kind === 'conflict') fail("the snapshot disagrees with itself about this row's UID");
      current = got.kind === 'value' ? got.value ?? null : null;
    } else {
      current = snapshotValue(snap, path);
    }
    if (!isDeepStrictEqual(w.before ?? null, current)) fail('its before value no longer matches the snapshot');

    // ---- sign-up records (E2): a copy to the kept account, a remove of the old key
    if (signUp) {
      const owner = keepOf.get(signUp.uid) ?? oldOf.get(signUp.uid);
      if (!owner) return fail('the uid is not in the merge map');
      if (owner.moveSignUps === false) fail('this cluster does not move sign-up records');
      // The season must be one the snapshot's listing names (a skipped scan allows nothing).
      const listing = signUpListing(snap, signUp.league);
      if ('problem' in listing) fail(listing.problem);
      if (!(listing as { seasons: string[] }).seasons.includes(signUp.season)) {
        fail(`${signUpLabel(signUp.league, signUp.season)} is not in the snapshot's sign-up listing`);
      }
      const group = readSignUpGroup(snap, owner.keep, Array.isArray(owner.old) ? owner.old : [], signUp.league, signUp.season);
      if (group.problem !== undefined) fail(group.problem);
      const decision = decideSignUps(group);
      if (decision.kind === 'refuse') fail(decision.why);
      if (decision.kind === 'none') fail('there is no sign-up record of an old account to move here');
      if (decision.status !== signUp.status) {
        fail("the sign-up status does not match the old account's record");
      }
      if (w.after === null) {
        // The remove: an OLD account's key, holding exactly the value being moved.
        if (!oldOf.has(signUp.uid)) fail("only an old account's sign-up record may be removed");
        if (w.before !== decision.value) fail('the removed sign-up record is not the one being moved');
        if (decision.kind === 'move') {
          const copyPath = signUpPath(signUp.league, signUp.season, signUp.status, owner.keep);
          const at = position.get(copyPath);
          const copy = at === undefined ? undefined : writes[at];
          const mine = position.get(path) as number;
          if (!copy || (copy.before ?? null) !== null || copy.after !== decision.value || (at as number) > mine) {
            fail('its copy on the kept account is not in the plan before it');
          }
        }
      } else {
        // The copy: only to the kept account, only when it has no record, byte-identical.
        if (!keepOf.has(signUp.uid)) fail('a sign-up record is only copied to the kept account');
        if (decision.kind !== 'move') fail('the kept account already has this sign-up record');
        if (w.before !== null && w.before !== undefined) fail('a sign-up copy never overwrites a record');
        if (w.after !== decision.value) fail("the copied sign-up value is not exactly the old account's value");
      }
      continue;
    }

    // ---- roster UID leaves (D1, D2, E1)
    if (ref) {
      const cluster = typeof w.after === 'string' ? keepOf.get(w.after) : undefined;
      if (!cluster || oldOf.has(w.after as string)) fail('the new UID is not a kept account of the map');
      const c = cluster as MergeCluster;
      const before = w.before ?? null;
      const fromOld = typeof before === 'string' && (c.old ?? []).includes(before);
      const emptyNameRow =
        (before === null || before === '') && nameRowPaths(c).has(path) && isPlainMap(snap.nodes[rowPathOf(path)]);
      if (!fromOld && !emptyNameRow) {
        fail('the row is neither held by an old account of this cluster nor one of its listed name rows');
      }
      if (ref.kind === 'league') {
        const label = `${ref.sport} Season ${ref.season}`;
        const cfg = fantasyConfigPath(ref.sport, ref.season);
        if (!hasOwn(snap.nodes, cfg)) fail(`${label}: no fantasy Config check in the snapshot`);
        if (snap.nodes[cfg] !== null && snap.nodes[cfg] !== undefined) {
          // E1: only the fantasy TEST season (its TestFill marker exists).
          const fill = fantasyTestFillPath(ref.sport, ref.season);
          if (!hasOwn(snap.nodes, fill)) fail(`${label}: no fantasy TestFill check in the snapshot`);
          if (snap.nodes[fill] === null || snap.nodes[fill] === undefined) {
            fail(`${label} is a live fantasy season (its fantasy Config exists and it has no TestFill marker)`);
          }
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
    const keepNode = snap.nodes[userPath(uid)];
    const keepFields = isPlainMap(keepNode) ? keepNode : {};
    const played = /^Played\/([^/]+)\/Season (\d+)$/.exec(rest);
    if (played) {
      const [, sport, season] = played;
      if (!LEAGUE_SPORTS.includes(sport)) fail('Played is only written for league sports');
      if (typeof w.after !== 'string' || w.after.length === 0) fail('a Played value is a team name');
      if (w.before !== null && w.before !== undefined) fail('a Played entry is never written over a value');
      if (!relinks.has(`${uid}|${sport}|${season}|${w.after}`)) {
        fail('there is no matching roster relink in this plan for this Played entry');
      }
      // A leaf write under a scalar Played / Played/<Sport> would wipe it.
      const playedRaw = keepFields['Played'];
      if (present(playedRaw) && !isPlainMap(playedRaw)) fail("the kept account's Played is not a map");
      if (isPlainMap(playedRaw) && present(playedRaw[sport]) && !isPlainMap(playedRaw[sport])) {
        fail(`the kept account's Played/${sport} is not a map`);
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
      const infoRaw = keepFields['Information'];
      if (present(infoRaw) && !isPlainMap(infoRaw)) fail("the kept account's Information is not a map");
    } else if (rest === 'First Name') {
      if (c.firstNameFix === undefined || w.after !== c.firstNameFix) {
        fail('First Name is only written for the cluster with a firstNameFix, and only to that value');
      }
    } else {
      fail('this leaf of a kept account is not on the allowlist');
    }
  }
}
