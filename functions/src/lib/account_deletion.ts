// Account deletion — the PURE planner and its applier (plan
// docs/superpowers/plans/2026-11-09-account-deletion.md, Task 1; design
// D1, D2, D5). No firebase imports: the callables (Task 2) hand in the
// FantasyDb adapter and an ObjectStore over the Storage bucket.
//
//   readAccountDeletionSnapshot(db, uid)   bounded reads of every place the
//                                          uid lives (keys-only discovery,
//                                          per-uid nodes read by path);
//   planAccountDeletion(snapshot, uid, s)  pure: the ordered steps + Storage
//                                          objects, or a refusal (D5);
//   applyAccountDeletion(db, store, plan)  the database steps in order, then
//                                          Storage, DeletedAccounts/<uid>
//                                          last and only when nothing failed.
//
// What happens to each place (D1 + the controller's rulings):
//   DELETED   Users/<uid>, PublicProfiles/<uid>, Storage
//             Users/<uid>/profileimage.jpg; per fantasy season
//             Squads, TransferState, Baselines, SquadAlerts, AccessClaims,
//             Watchlists, Badges, BadgePushClaims, Live/Squads (all /<uid>)
//             and PreviewPushed/<gw>/<uid>; MiniLeagues/<id>/Members/<uid>;
//             Support/Tickets/<n> whose Uid is the person (+ Storage
//             support/<n>/img_0..4.jpg) and Support/UserTickets/<uid>;
//             EventsV2/<id>/Attendees|Reminders/<uid>,
//             Events/<id>/Attendees/<uid>; MergeNotices/<uid>,
//             Insiders/<uid>, InsiderCodes/<code> when it points at the uid;
//             the ReferredName leaf of the person's own referral row;
//             Sign Ups/<league>/<S>/NotPaid/<uid> (M11: an unpaid sign-up,
//             the value is just the name) and every
//             Sign Ups/<league>/<S>/Comments/<displayName> whose value is
//             "<uid>:<text>" (I3) - leagues and seasons found keys-only.
//   UID LEAF  `UID`/`uid` removed, the row kept (a league record): league
//             Line Ups, AFC San Jose rosters, tournament rosters (found
//             through Users/<uid>/TournamentsPlayed) — with the row's
//             `PhotoUrl`/`photoUrl` — and the fantasy market row
//             Players/<name> (its copied `photoUrl` too). The photo urls
//             point at the deleted profile photo.
//   ANONYMISED (ledgers: everyone else's rank stays true) History/<gw>/<uid>,
//             PublishedPicks/<gw>/<uid>, Leaderboards/Gameweek/<gw>/<uid>,
//             Leaderboards/Overall/<uid>, Leaderboards/RankHistory/<uid>,
//             Live/Board/<uid>: string Name/TeamName/ManagerName/DisplayName
//             -> 'Deleted manager', PhotoUrl/ProfileUrl removed, every
//             number/boolean kept. Today's engine rows carry no names, so
//             this is usually "nothing to do".
//   MANAGER   <root>/Managers/<uid> is kept (the engine still scores the
//             week rows it owns) but anonymised: TeamName 'Deleted
//             manager', Deleted: true, Name/ManagerName/DisplayName/
//             PhotoUrl/ProfileUrl removed, every other key untouched — the
//             fan app's leaderboard names the row from it.
//   SCRUBBED  (payment records, kept for accounting) Fantasy Access/<uid>
//             and Registrations/<id>/Submissions/<uid>: only the
//             allow-listed keys stay, plus `Deleted: true`. A submission
//             with `Paid !== true` also gets DisplayName 'Deleted player'
//             (M11: nothing was paid, so the name is not kept).
//   KEPT      Sign Ups/<league>/<S>/Paid/<uid>, TransferCosts/<gw>/<uid>,
//             LiveBase/<gw>/Managers/<uid>, ReferredUsers/<uid> (the
//             referral guard a later refund void needs).
//   WRITTEN   DeletedAccounts/<uid> = {At, Provider, By?,
//             PendingStorage?} — last, whenever every database step landed. PendingStorage
//             lists the Storage objects whose delete failed (opaque paths:
//             uid / ticket number only); the next run plans them again and
//             its stamp drops the key once they are gone. A retry keeps the
//             first At/Provider and any By (an old Reason key is dropped).
//             No free text in the stamp: `DeletedAccounts` is readable by any client while the stage-1 rules keep the root read open.
//   MERGED    (C1) Users/<uid>/MergedFrom/<old> = true (written by the merge
//             tool): each old account that points back (Users/<old>/
//             MergedInto, or its own DeletedAccounts/<old>/MergedInto once
//             its Users node is gone) gets its own full per-uid plan - the
//             same discovery and steps as above - plus DeletedAccounts/<old>
//             = {At, Provider: 'merged', MergedInto: <uid>} right before
//             Users/<old>; all of it before Users/<uid>. The first step writes
//             DeletedAccounts/<uid>/PendingAuth = [old uids] (the closing
//             stamp keeps it) so a rerun still knows which Auth users are
//             left; the callable deletes `authUidsToDelete` and settles the
//             list (settlePendingAuth). Not subject to the already-merged
//             refusal when reached this way; `allowMerged` (admin) plans an
//             old account on its own.
//   NOTE     Baselines/<uid> and Live/Squads/<uid> regrow after the next
//             lock while the account still exists; a later rerun deletes
//             them again.
//
// Order is what makes a rerun safe (Review Focus 3): everything found
// THROUGH another node is removed before that node (tournament rows before
// Users, tickets before UserTickets, the insider code before Insiders), and
// Users/<uid> is the last delete. Every step is planned only while it still
// has work to do, so a rerun after a crash plans exactly the remainder.

import { isDeepStrictEqual } from 'util';
import type { FantasyLogger } from './fantasy/orchestration';
import {
  childEntries, childKeysOf, FantasyDb, fantasyRoot, isPlainMap,
  listFantasySeasons,
} from './fantasy/orchestration_db';

export const DELETED_MANAGER = 'Deleted manager';
/** M11: the DisplayName an UNPAID registration submission keeps. */
export const DELETED_PLAYER = 'Deleted player';

/** The league sports whose rosters live under `<Sport>/<Season>/Line Ups`
 *  (tools/merge_accounts_logic.ts imports this one copy). */
export const LEAGUE_SPORTS: readonly string[] = ['Futsal', 'Basketball', 'Flag Football'];
const AFC_SEASONS = 'AFC San Jose/Seasons';
const SEASON_RE = /^\d{1,4}$/;
const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
// Database keys cannot hold . # $ [ ] / or control characters.
const SAFE_KEY_RE = /^[^\u0000-\u001f\u007f/.#$[\]]{1,200}$/;
/** support_models.dart kMaxScreenshots; uploads are `support/<n>/img_<i>.jpg`
 *  with i the PICKED index, so every slot is planned (not-found is fine). */
const MAX_SCREENSHOTS = 5;

/** Per-uid fantasy nodes deleted whole: `<root>/<name>/<uid>`. */
const FANTASY_UID_NODES: readonly string[] = [
  'Squads', 'TransferState', 'Baselines', 'SquadAlerts',
  'AccessClaims', 'Watchlists', 'Badges', 'BadgePushClaims', 'Live/Squads',
];
/** Per-gameweek ledgers holding a `<gw>/<uid>` row (anonymised). */
const FANTASY_WEEK_LEDGERS: readonly string[] = [
  'History', 'PublishedPicks', 'Leaderboards/Gameweek',
];
/** Single-level ledgers holding a `<uid>` row (anonymised). */
const FANTASY_UID_LEDGERS: readonly string[] = [
  'Leaderboards/Overall', 'Leaderboards/RankHistory', 'Live/Board',
];

const NAME_KEYS: readonly string[] = ['Name', 'TeamName', 'ManagerName', 'DisplayName'];
const PHOTO_KEYS: readonly string[] = ['PhotoUrl', 'ProfileUrl'];
const ROSTER_UID_KEYS: readonly string[] = ['UID', 'uid'];
/** Photo leaves a roster row may carry (tournamentplayer.dart reads both). */
const ROSTER_PHOTO_KEYS: readonly string[] = ['PhotoUrl', 'photoUrl'];
/** Managers/<uid> keys removed by the anonymiser (TeamName is rewritten). */
const MANAGER_DROP: readonly string[] = [
  'Name', 'ManagerName', 'DisplayName', 'NameFlagged', ...PHOTO_KEYS,
];
/** The only object paths a PendingStorage list may name. */
const PENDING_OBJECT_RE = /^(Users\/[A-Za-z0-9_-]{1,128}\/profileimage\.jpg|support\/\d{1,12}\/img_\d\.jpg)$/;

/** Fantasy Access/<uid> keys that are the payment record (access.ts). */
const ACCESS_KEEP: ReadonlySet<string> = new Set([
  'Status', 'Via', 'AmountCents', 'PaidAt', 'By', 'StripePaymentIntent',
  'RefundedAt', 'RevokedBy', 'Deleted',
]);
/** Registration submission keys kept: the payment record (Paid* are what
 *  stripeWebhook / the Manager write: PaidVia, PaidAmount), the fee it was
 *  computed from, the display name and the team it paid into. An explicit
 *  allow-list — everything else (answers, phone, free text) goes. */
const SUBMISSION_KEEP: ReadonlySet<string> = new Set([
  'Paid', 'PaidVia', 'PaidAmount', 'DisplayName', 'Status', 'TeamId', 'TeamName',
  'PaidAt', 'AmountCents', 'AmountDollars', 'StripePaymentIntent',
  'StripeCheckoutSession', 'RefundedAt', 'RefundAmountCents', 'Method', 'Waived',
  'AdjustedFee', 'EligibleFee', 'DiscountPct', 'DiscountSource', 'SubmittedAt', 'Deleted',
]);

// ── Types ───────────────────────────────────────────────────────────────────

/** The Storage seam (Task 2 wraps `bucket().file(p).delete({ignoreNotFound})`).
 *  A missing object counts as success: it must resolve, not throw. */
export interface ObjectStore {
  deleteObject(path: string): Promise<void>;
}

export interface DeletionStep {
  path: string;
  action: 'delete' | 'write';
  after?: unknown;
  /** A hand-over write (mini-league Owner), counted as `handoffs`. */
  handoff?: boolean;
  /** A DeletedAccounts bookkeeping write (an old account's stamp, the
   *  PendingAuth marker) - not counted in the summary. */
  stamp?: boolean;
}

export interface DeletionPlan {
  refused?: undefined;
  uid: string;
  /** In apply order; the last one is always the DeletedAccounts write. */
  steps: DeletionStep[];
  storagePaths: string[];
  /** C1: every Firebase Auth user the callable deletes once the database
   *  steps landed - [uid, ...old accounts combined into it]. */
  authUidsToDelete: string[];
}

/** C1: what the admin path may do that the user path may not. */
export interface DeletionOptions {
  /** Plan an old account of a completed merge on its own (adminDeleteAccount)
   *  instead of refusing it with 'already-merged'. */
  allowMerged?: boolean;
}

/** D5: an old account of a completed merge is never deleted itself. */
export interface DeletionRefusal {
  refused: 'already-merged';
  /** The kept account's masked email hint (Users/<uid>/MergedHint), or ''. */
  keepHint: string;
}

export type AccountDeletionPlanning = DeletionPlan | DeletionRefusal;

export interface DeletionStamp {
  nowMs: number;
  /** The sign-in provider id ('password', 'google.com', 'apple.com', ...). */
  provider: string;
  /** The admin who deleted the account (adminDeleteAccount only). */
  by?: string;
}

export interface DeletionSummary {
  deleted: number;
  anonymised: number;
  /** Ownership hand-overs (mini-league Owner), not anonymisations. */
  handoffs: number;
  /** True when the closing DeletedAccounts stamp landed (every DB step done). */
  stamped: boolean;
  storageDeleted: number;
  errors: string[];
}

interface FoundNode {
  path: string;
  value: unknown;
}

interface UidLeafRow {
  /** The row node's path; the leaves removed are `<path>/<key>`. */
  path: string;
  row: unknown;
  /** Leaves removed (before the uid leaf) whenever the row is the person's. */
  alsoRemove: string[];
}

interface ScrubRow extends FoundNode {
  kind: 'fantasy-access' | 'registration' | 'fantasy-manager';
}

/** Everything the planner needs, read by readAccountDeletionSnapshot. Paths
 *  are full RTDB paths; a value of null = read and absent. */
export interface AccountDeletionSnapshot {
  uid: string;
  user: unknown;
  /** Roster and market rows that hold the uid. */
  uidLeafRows: UidLeafRow[];
  ledgerRows: FoundNode[];
  scrubRows: ScrubRow[];
  /** `MiniLeagues/<id>` nodes the person owns or belongs to. */
  miniLeagues: FoundNode[];
  /** The person's own referral row (via ReferredUsers/<uid>), if any. */
  referral: FoundNode | null;
  /** Ticket numbers from Support/UserTickets/<uid>, with each ticket's Uid. */
  tickets: Array<{ num: string; owner: unknown }>;
  /** I3: `Sign Ups/<league>/<S>/Comments` nodes ({displayName: "<uid>:<text>"}). */
  signUpComments: FoundNode[];
  /** Nodes deleted whole when present, in delete order (Users/<uid> last). */
  wholeNodes: FoundNode[];
  /** DeletedAccounts/<uid> as an earlier run left it (null = none). */
  previousStamp: unknown;
  /** C1: the old accounts combined into this one (Users/<uid>/MergedFrom),
   *  each verified to point back here, with their own per-uid snapshot. */
  merged: AccountDeletionSnapshot[];
}

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

// ── Snapshot (bounded reads) ────────────────────────────────────────────────

async function readAll(db: FantasyDb, paths: string[]): Promise<FoundNode[]> {
  return Promise.all(paths.map(async (path) => ({ path, value: await db.read(path) })));
}

async function readFantasySeason(
  db: FantasyDb, uid: string, root: string, snap: AccountDeletionSnapshot,
  log: FantasyLogger,
): Promise<void> {
  const ledgerPaths = FANTASY_UID_LEDGERS.map((l) => `${root}/${l}/${uid}`);
  for (const ledger of FANTASY_WEEK_LEDGERS) {
    for (const gw of await childKeysOf(db, `${root}/${ledger}`, log)) {
      ledgerPaths.push(`${root}/${ledger}/${gw}/${uid}`);
    }
  }
  snap.ledgerRows.push(...await readAll(db, ledgerPaths));

  const wholePaths = FANTASY_UID_NODES.map((n) => `${root}/${n}/${uid}`);
  for (const gw of await childKeysOf(db, `${root}/PreviewPushed`, log)) {
    wholePaths.push(`${root}/PreviewPushed/${gw}/${uid}`);
  }
  snap.wholeNodes.push(...await readAll(db, wholePaths));

  const manager = `${root}/Managers/${uid}`;
  snap.scrubRows.push({ path: manager, value: await db.read(manager), kind: 'fantasy-manager' });
  const access = `${root}/Access/${uid}`;
  snap.scrubRows.push({ path: access, value: await db.read(access), kind: 'fantasy-access' });

  for (const [id, league] of childEntries(await db.read(`${root}/MiniLeagues`))) {
    if (!isPlainMap(league)) continue;
    const members = isPlainMap(league['Members']) ? league['Members'] : {};
    if (league['Owner'] === uid || members[uid] != null) {
      snap.miniLeagues.push({ path: `${root}/MiniLeagues/${id}`, value: league });
    }
  }
  for (const [name, row] of childEntries(await db.read(`${root}/Players`))) {
    if (isPlainMap(row) && row['uid'] === uid) {
      snap.uidLeafRows.push({ path: `${root}/Players/${name}`, row, alsoRemove: ['photoUrl'] });
    }
  }
}

/** Roster rows (a map of name -> row) whose UID/uid leaf is [uid]. */
function rosterRowsOf(rosterPath: string, roster: unknown, uid: string): UidLeafRow[] {
  const out: UidLeafRow[] = [];
  for (const [name, row] of childEntries(roster)) {
    if (isPlainMap(row) && ROSTER_UID_KEYS.some((k) => row[k] === uid)) {
      out.push({ path: `${rosterPath}/${name}`, row, alsoRemove: [...ROSTER_PHOTO_KEYS] });
    }
  }
  return out;
}

async function readRosters(
  db: FantasyDb, uid: string, user: unknown, log: FantasyLogger,
): Promise<UidLeafRow[]> {
  const rows: UidLeafRow[] = [];
  // League rosters: every numbered season (keys-only), one Line Ups read
  // each — the merge tool's scanRosters walk.
  for (const sport of LEAGUE_SPORTS) {
    const seasons = (await childKeysOf(db, sport, log)).filter((k) => SEASON_RE.test(k));
    for (const found of await readAll(db, seasons.map((s) => `${sport}/${s}/Line Ups`))) {
      for (const [team, players] of childEntries(found.value)) {
        rows.push(...rosterRowsOf(`${found.path}/${team}`, players, uid));
      }
    }
  }
  const afc = await childKeysOf(db, AFC_SEASONS, log);
  for (const found of await readAll(db, afc.map((s) => `${AFC_SEASONS}/${s}/Roster`))) {
    rows.push(...rosterRowsOf(found.path, found.value, uid));
  }
  // Tournament rosters: only the ones the person's own index names.
  const played = isPlainMap(user) ? childEntries(user['TournamentsPlayed']) : [];
  const tournaments = played.map(([tid]) => tid).filter((tid) => SAFE_KEY_RE.test(tid))
    .map((tid) => `Tournaments/${tid}/Rosters`);
  for (const found of await readAll(db, tournaments)) {
    for (const [team, players] of childEntries(found.value)) {
      rows.push(...rosterRowsOf(`${found.path}/${team}`, players, uid));
    }
  }
  return rows;
}

/** Reads every place [uid] lives, boundedly: seasons, gameweeks, events,
 *  forms and tickets are discovered with keys-only reads and each per-uid
 *  node is then read by its own path — never the Fantasy node, a whole
 *  season, all of Support/Tickets or all of Referrals. The small shared
 *  nodes scanned for the uid are a fantasy season's MiniLeagues and
 *  Players, a league season's Line Ups, the AFC rosters and the person's
 *  own tournaments' rosters. */
export async function readAccountDeletionSnapshot(
  db: FantasyDb, uid: string, log: FantasyLogger = silent, opts: DeletionOptions = {},
): Promise<AccountDeletionSnapshot> {
  assertUid(uid);
  const user = await db.read(`Users/${uid}`);
  const snap = emptySnapshot(uid, user, await db.read(`DeletedAccounts/${uid}`));
  if (opts.allowMerged !== true && mergedInto(user) !== null) return snap; // refused
  await readUidPlaces(db, uid, user, snap, log);

  // C1: the old accounts combined into this one. The MergedFrom index sits
  // in the person's own (user-writable) node, so an old account is followed
  // only when IT points back here: Users/<old>/MergedInto, or - once its
  // Users node is gone on a rerun - its own DeletedAccounts/<old>/MergedInto
  // (written only by this server). A link that does not check out costs
  // exactly those two reads. One level only: an old account's own
  // MergedFrom is never followed.
  for (const old of mergedFromOf(user, uid)) {
    const oldUser = await db.read(`Users/${old}`);
    const oldStamp = await db.read(`DeletedAccounts/${old}`);
    const back = oldUser != null
      ? mergedInto(oldUser)
      : (isPlainMap(oldStamp) ? oldStamp['MergedInto'] : null);
    if (back !== uid) continue;
    const sub = emptySnapshot(old, oldUser, oldStamp);
    await readUidPlaces(db, old, oldUser, sub, log);
    snap.merged.push(sub);
  }
  return snap;
}

function emptySnapshot(uid: string, user: unknown, previousStamp: unknown): AccountDeletionSnapshot {
  return {
    uid, user, uidLeafRows: [], ledgerRows: [], scrubRows: [], miniLeagues: [],
    referral: null, tickets: [], signUpComments: [], wholeNodes: [], previousStamp, merged: [],
  };
}

/** The uids listed in Users/<uid>/MergedFrom (`<old>: true`), never [uid]. */
function mergedFromOf(user: unknown, uid: string): string[] {
  const from = isPlainMap(user) ? user['MergedFrom'] : null;
  return childEntries(from).filter(([o, v]) => v === true && o !== uid && UID_RE.test(o)).map(([o]) => o);
}

/** Every per-uid place of [uid] (the body of the snapshot, for the account
 *  itself and for each old account combined into it). */
async function readUidPlaces(
  db: FantasyDb, uid: string, user: unknown, snap: AccountDeletionSnapshot, log: FantasyLogger,
): Promise<void> {
  snap.uidLeafRows.push(...await readRosters(db, uid, user, log));
  for (const ref of await listFantasySeasons(db, log)) {
    await readFantasySeason(db, uid, fantasyRoot(ref.sport, ref.season), snap, log);
  }

  for (const form of await childKeysOf(db, 'Registrations', log)) {
    const path = `Registrations/${form}/Submissions/${uid}`;
    snap.scrubRows.push({ path, value: await db.read(path), kind: 'registration' });
  }

  const eventPaths: string[] = [];
  for (const id of await childKeysOf(db, 'EventsV2', log)) {
    eventPaths.push(`EventsV2/${id}/Attendees/${uid}`, `EventsV2/${id}/Reminders/${uid}`);
  }
  for (const id of await childKeysOf(db, 'Events', log)) {
    eventPaths.push(`Events/${id}/Attendees/${uid}`);
  }
  snap.wholeNodes.push(...await readAll(db, eventPaths));

  const pointer = await db.read(`ReferredUsers/${uid}`);
  if (typeof pointer === 'string' && SAFE_KEY_RE.test(pointer)) {
    const path = `Referrals/${pointer}`;
    snap.referral = { path, value: await db.read(path) };
  }

  // The index is user-written: a ticket is the person's only when the
  // ticket's own Uid says so (read leaf by leaf, never all tickets).
  const index = await db.read(`Support/UserTickets/${uid}`);
  const nums = childEntries(index).filter(([, v]) => v !== false).map(([n]) => n)
    .filter((n) => /^\d{1,12}$/.test(n));
  snap.tickets = await Promise.all(nums.map(async (num) => ({
    num, owner: await db.read(`Support/Tickets/${num}/Uid`),
  })));

  // I3 + M11: sign-ups. Leagues and their seasons keys-only (tournament
  // sign-ups are `<TournamentName>/<id>`); per season the person's unpaid
  // record (the value is just the name - nothing was paid) and the Comments
  // node, scanned for "<uid>:" values. Paid records stay (accounting).
  for (const league of await childKeysOf(db, 'Sign Ups', log)) {
    if (!SAFE_KEY_RE.test(league)) continue;
    for (const season of await childKeysOf(db, `Sign Ups/${league}`, log)) {
      if (!SAFE_KEY_RE.test(season)) continue;
      const base = `Sign Ups/${league}/${season}`;
      const notPaid = `${base}/NotPaid/${uid}`;
      snap.wholeNodes.push({ path: notPaid, value: await db.read(notPaid) });
      snap.signUpComments.push({ path: `${base}/Comments`, value: await db.read(`${base}/Comments`) });
    }
  }

  snap.wholeNodes.push({ path: `MergeNotices/${uid}`, value: await db.read(`MergeNotices/${uid}`) });
  const insider = await db.read(`Insiders/${uid}`);
  const code = isPlainMap(insider) && typeof insider['Code'] === 'string'
    ? insider['Code'].trim().toUpperCase() : '';
  if (code.length > 0 && SAFE_KEY_RE.test(code)) {
    const path = `InsiderCodes/${code}`;
    const owner = await db.read(path);
    if (owner === uid) snap.wholeNodes.push({ path, value: owner });
  }
  snap.wholeNodes.push(
    { path: `Insiders/${uid}`, value: insider },
    { path: `Support/UserTickets/${uid}`, value: index },
    { path: `PublicProfiles/${uid}`, value: await db.read(`PublicProfiles/${uid}`) },
    { path: `Users/${uid}`, value: user },
  );
}

// ── Planner (pure) ──────────────────────────────────────────────────────────

function assertUid(uid: string): void {
  if (!UID_RE.test(uid)) throw new Error('account deletion: not a uid');
}

function mergedInto(user: unknown): string | null {
  const m = isPlainMap(user) ? user['MergedInto'] : null;
  return typeof m === 'string' && m.length > 0 ? m : null;
}

/** A ledger row with every name replaced by DELETED_MANAGER and every photo
 *  url removed; null when there is nothing to change (already anonymous, no
 *  names, or not a map — an RTDB list-coerced RankHistory row holds ranks
 *  only). Numbers and booleans are never touched. */
export function anonymiseLedgerRow(row: unknown): Record<string, unknown> | null {
  if (!isPlainMap(row)) return null;
  const out: Record<string, unknown> = {};
  let changed = false;
  for (const [k, v] of Object.entries(row)) {
    if (PHOTO_KEYS.includes(k)) { changed = true; continue; }
    if (NAME_KEYS.includes(k) && typeof v === 'string' && v !== DELETED_MANAGER) {
      out[k] = DELETED_MANAGER;
      changed = true;
      continue;
    }
    out[k] = v;
  }
  return changed ? out : null;
}

/** Managers/<uid> anonymised (see the header); null when absent or
 *  already marked Deleted. */
export function anonymiseManager(node: unknown): Record<string, unknown> | null {
  if (!isPlainMap(node) || node['Deleted'] === true) return null;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(node)) if (!MANAGER_DROP.includes(k)) out[k] = v;
  out['TeamName'] = DELETED_MANAGER;
  out['Deleted'] = true;
  return out;
}

/** The payment record that stays, plus `Deleted: true` (or the anonymised
 *  manager); null when the row is absent or already done. */
function scrubbed(row: ScrubRow): Record<string, unknown> | null {
  if (row.kind === 'fantasy-manager') return anonymiseManager(row.value);
  if (!isPlainMap(row.value)) return null;
  const keep = row.kind === 'fantasy-access'
    ? (k: string) => ACCESS_KEEP.has(k) : (k: string) => SUBMISSION_KEEP.has(k);
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row.value)) if (keep(k)) out[k] = v;
  // M11: an unpaid submission keeps its fee keys (the same allow-list) but
  // not the person's name - nothing was paid, so there is no record to keep
  // it for.
  if (row.kind === 'registration' && row.value['Paid'] !== true) out['DisplayName'] = DELETED_PLAYER;
  out['Deleted'] = true;
  return isDeepStrictEqual(out, row.value) ? null : out;
}

/** The member that inherits a league: the lowest numeric join value when
 *  members carry one, else the first uid in key order (members are stored
 *  as `true`, so there is no join time to compare). */
function nextOwner(members: Record<string, unknown>, leaving: ReadonlySet<string>): string | null {
  const rest = Object.entries(members)
    .filter(([m, v]) => !leaving.has(m) && v != null && v !== false);
  if (rest.length === 0) return null;
  const at = (v: unknown) => (typeof v === 'number' ? v : Number.POSITIVE_INFINITY);
  rest.sort(([a, va], [b, vb]) => (at(va) - at(vb)) || (a < b ? -1 : a > b ? 1 : 0));
  return rest[0][0];
}

/** [leaving] = every account this plan deletes (the person and the old
 *  accounts combined into them): none of them can inherit a league.
 *  [gone] = leagues an earlier part of the plan deletes whole (skipped). */
function miniLeagueSteps(
  league: FoundNode, uid: string, leaving: ReadonlySet<string>, gone: Set<string>,
): DeletionStep[] {
  if (!isPlainMap(league.value) || gone.has(league.path)) return [];
  const members = isPlainMap(league.value['Members']) ? league.value['Members'] : {};
  const owns = league.value['Owner'] === uid;
  const heir = nextOwner(members, leaving);
  if (owns && heir === null) {
    gone.add(league.path);
    return [{ path: league.path, action: 'delete' }];
  }
  const steps: DeletionStep[] = [];
  if (members[uid] != null) steps.push({ path: `${league.path}/Members/${uid}`, action: 'delete' });
  if (owns && heir !== null) steps.push({ path: `${league.path}/Owner`, action: 'write', after: heir, handoff: true });
  return steps;
}

/** One account's own steps (no DeletedAccounts write) and Storage objects,
 *  shared by the person and every old account combined into them. */
function planUidPart(
  snap: AccountDeletionSnapshot, uid: string, leaving: ReadonlySet<string>, gone: Set<string>,
): { steps: DeletionStep[]; storagePaths: string[] } {
  const steps: DeletionStep[] = [];
  const del = (path: string) => { steps.push({ path, action: 'delete' }); };

  for (const r of snap.uidLeafRows) {
    if (!isPlainMap(r.row)) continue;
    const row = r.row;
    if (!ROSTER_UID_KEYS.some((k) => row[k] === uid)) continue;
    for (const leaf of r.alsoRemove) if (row[leaf] != null) del(`${r.path}/${leaf}`);
    for (const k of ROSTER_UID_KEYS) if (row[k] === uid) del(`${r.path}/${k}`);
  }
  for (const r of snap.ledgerRows) {
    const after = anonymiseLedgerRow(r.value);
    if (after !== null) steps.push({ path: r.path, action: 'write', after });
  }
  for (const r of snap.scrubRows) {
    const after = scrubbed(r);
    if (after !== null) steps.push({ path: r.path, action: 'write', after });
  }
  for (const league of snap.miniLeagues) steps.push(...miniLeagueSteps(league, uid, leaving, gone));
  const ref = snap.referral;
  if (ref !== null && isPlainMap(ref.value) && ref.value['ReferredUid'] === uid &&
      ref.value['ReferredName'] != null) {
    del(`${ref.path}/ReferredName`);
  }
  // I3: a sign-up comment is `<displayName>: "<uid>:<text>"` - the person's
  // when the value starts with their uid and a colon.
  for (const node of snap.signUpComments) {
    for (const [name, v] of childEntries(node.value)) {
      if (typeof v === 'string' && v.startsWith(`${uid}:`) && SAFE_KEY_RE.test(name)) {
        del(`${node.path}/${name}`);
      }
    }
  }
  const owned = snap.tickets.filter((t) => t.owner === uid).map((t) => t.num);
  for (const num of owned) del(`Support/Tickets/${num}`);
  for (const node of snap.wholeNodes) if (node.value != null) del(node.path);

  const storagePaths = [`Users/${uid}/profileimage.jpg`];
  for (const num of owned) {
    for (let i = 0; i < MAX_SCREENSHOTS; i++) storagePaths.push(`support/${num}/img_${i}.jpg`);
  }
  return { steps, storagePaths };
}

/** The valid uids of a stamp's PendingAuth list, never [uid] itself. */
function pendingAuthOf(stamp: Record<string, unknown>, uid: string): string[] {
  return childEntries(stamp['PendingAuth']).map(([, u]) => u)
    .filter((u): u is string => typeof u === 'string' && UID_RE.test(u) && u !== uid);
}

/** The ordered plan for [uid] from [snapshot] (see the header for what each
 *  place gets). Pure and idempotent: a snapshot of a half-deleted account
 *  plans only what is left, a finished one only the DeletedAccounts write.
 *
 *  C1: the old accounts combined into [uid] (snapshot.merged) come first,
 *  each with its full per-uid plan and its own DeletedAccounts/<old> stamp
 *  {At, Provider: 'merged', MergedInto: uid} just before its Users node -
 *  all of it before Users/<uid> (which holds the MergedFrom link) goes. A
 *  first step records the old uids in DeletedAccounts/<uid>/PendingAuth, so
 *  a rerun after Users/<uid> is gone still knows which Auth users to delete;
 *  the callable settles that list (settlePendingAuth) once they are. */
export function planAccountDeletion(
  snapshot: AccountDeletionSnapshot, uid: string, stamp: DeletionStamp,
  opts: DeletionOptions = {},
): AccountDeletionPlanning {
  assertUid(uid);
  if (snapshot.uid !== uid) throw new Error('account deletion: snapshot is for another account');
  if (opts.allowMerged !== true && mergedInto(snapshot.user) !== null) {
    const hint = isPlainMap(snapshot.user) ? snapshot.user['MergedHint'] : null;
    return { refused: 'already-merged', keepHint: typeof hint === 'string' ? hint : '' };
  }
  const prev = snapshot.previousStamp;
  const prevMap = isPlainMap(prev) ? prev : {};
  const olds = snapshot.merged.map((m) => m.uid);
  const prevPending = pendingAuthOf(prevMap, uid);
  const pendingAuth = [...prevPending, ...olds.filter((o) => !prevPending.includes(o))];
  const leaving = new Set<string>([uid, ...olds]);
  const gone = new Set<string>();
  const steps: DeletionStep[] = [];
  const storagePaths: string[] = [];
  const addStorage = (paths: string[]) => {
    for (const p of paths) if (!storagePaths.includes(p)) storagePaths.push(p);
  };

  if (olds.some((o) => !prevPending.includes(o))) {
    steps.push({ path: `DeletedAccounts/${uid}/PendingAuth`, action: 'write', after: pendingAuth, stamp: true });
  }
  for (const old of snapshot.merged) {
    const part = planUidPart(old, old.uid, leaving, gone);
    const oldPrev = isPlainMap(old.previousStamp) ? old.previousStamp : {};
    const oldClosing = {
      At: typeof oldPrev['At'] === 'number' ? oldPrev['At'] : stamp.nowMs,
      Provider: 'merged',
      MergedInto: uid,
    };
    if (!isDeepStrictEqual(oldClosing, old.previousStamp)) {
      const users = part.steps.findIndex((s) => s.path === `Users/${old.uid}` && s.action === 'delete');
      const oldStamp: DeletionStep = {
        path: `DeletedAccounts/${old.uid}`, action: 'write', after: oldClosing, stamp: true,
      };
      if (users >= 0) part.steps.splice(users, 0, oldStamp); else part.steps.push(oldStamp);
    }
    steps.push(...part.steps);
    addStorage(part.storagePaths);
  }
  const own = planUidPart(snapshot, uid, leaving, gone);
  steps.push(...own.steps);

  const first = <T>(old: unknown, now: T | undefined, ok: (v: unknown) => boolean) =>
    (ok(old) ? old : now) as T | undefined;
  const isStr = (v: unknown) => typeof v === 'string' && v.length > 0;
  const closing: Record<string, unknown> = {
    At: first(prevMap['At'], stamp.nowMs, (v) => typeof v === 'number'),
    Provider: first(prevMap['Provider'], stamp.provider, isStr),
  };
  const by = first(prevMap['By'], stamp.by, isStr);
  if (by !== undefined) closing['By'] = by;
  if (pendingAuth.length > 0) closing['PendingAuth'] = pendingAuth;
  steps.push({ path: `DeletedAccounts/${uid}`, action: 'write', after: closing });

  // The person's own objects first, then the old accounts', then whatever
  // an earlier run could not delete.
  const ownStorage = own.storagePaths;
  storagePaths.splice(0, 0, ...ownStorage.filter((p) => !storagePaths.includes(p)));
  const pending = childEntries(prevMap['PendingStorage']).map(([, p]) => p);
  for (const p of pending) {
    if (typeof p === 'string' && PENDING_OBJECT_RE.test(p)) addStorage([p]);
  }
  return { uid, steps, storagePaths, authUidsToDelete: [uid, ...pendingAuth] };
}

/** C1: after the callable tried every old account's Auth user, record the
 *  ones that are still there (or clear the list). Opaque uids only. */
export async function settlePendingAuth(db: FantasyDb, uid: string, failed: string[]): Promise<void> {
  assertUid(uid);
  const keep = failed.filter((u) => UID_RE.test(u) && u !== uid);
  await db.write(`DeletedAccounts/${uid}/PendingAuth`, keep.length > 0 ? keep : null);
}

// ── Applier ─────────────────────────────────────────────────────────────────

/** Runs [plan]: the database steps in order (stopping at the first
 *  failure, with no Storage and no stamp), then every Storage object (a
 *  failure is recorded, never thrown), then the closing DeletedAccounts
 *  write — with `PendingStorage: [failed paths]` when any Storage delete
 *  failed, without the key (cleared) when none did. Errors never carry the
 *  uid; the summary is counts only. */
export async function applyAccountDeletion(
  db: FantasyDb, storage: ObjectStore, plan: DeletionPlan,
): Promise<DeletionSummary> {
  const summary: DeletionSummary = {
    deleted: 0, anonymised: 0, handoffs: 0, stamped: false, storageDeleted: 0, errors: [],
  };
  // Every uid of the plan (the person and any old account), longest first so
  // a uid that prefixes another never leaves a tail behind.
  const uids = [...new Set([plan.uid, ...(plan.authUidsToDelete ?? [])])]
    .sort((a, b) => b.length - a.length);
  const masked = (what: string, err: unknown) => uids.reduce(
    (text, u) => text.split(u).join('<uid>'),
    `${what}: ${err instanceof Error ? err.message : String(err)}`);
  const run = async (step: DeletionStep): Promise<boolean> => {
    try {
      await db.write(step.path, step.action === 'delete' ? null : step.after);
      return true;
    } catch (err) {
      summary.errors.push(masked(`${step.action} ${step.path}`, err));
      return false;
    }
  };

  const stamp = plan.steps[plan.steps.length - 1];
  for (const step of plan.steps.slice(0, -1)) {
    if (!await run(step)) return summary;
    if (step.stamp === true) continue; // bookkeeping, not a change to the person's data
    if (step.action === 'delete') summary.deleted++;
    else if (step.handoff === true) summary.handoffs++;
    else summary.anonymised++;
  }
  const failed: string[] = [];
  for (const path of plan.storagePaths) {
    try {
      await storage.deleteObject(path);
      summary.storageDeleted++;
    } catch (err) {
      failed.push(path);
      summary.errors.push(masked(`storage ${path}`, err));
    }
  }
  if (stamp !== undefined) {
    const after = isPlainMap(stamp.after) ? { ...stamp.after } : {};
    if (failed.length > 0) after['PendingStorage'] = failed;
    summary.stamped = await run({ ...stamp, after });
  }
  return summary;
}
