// Transfer accounting (P4 Phase E) — the pure logic behind the
// Fantasy/<sport>/<season>/TransferState node, the lock-time chip/cost
// freeze, and the post-finalize rollover. No firebase imports; the
// db-coupled halves live in orchestration.ts behind the FantasyDb seam.
//
// NODE SHAPE — TransferState/<uid> (rules: read own + admin, NO client
// write; only functions — the Admin SDK — ever write it):
//
//   { Free:int,         // free transfers available THIS gameweek
//     UsedThisGw:int,   // players in the saved squad that were not in the
//                       //   previous locked squad; recomputed on every save
//                       //   while the gameweek is open; the lock raises
//                       //   it to its own recount when that is higher
//                       //   (lockUsedTransfers; charged and persisted)
//     ChipPlayed?:string, // frozen at lock from the locked squad's chip
//                       //   (post-void); cleared again at rollover
//     SavedGw?:int,     // gameweek of the manager's latest squad save —
//                       //   the reminder audience's "changed" marker;
//                       //   server writes to Squads (ServerWriteAt —
//                       //   orchestration_db.ts) never stamp it
//     RolledGw?:int,    // last gameweek whose post-finalize rollover ran
//                       //   (once-only guard for rollover + freeHit restore)
//     FreeSwaps?:[name], // holder protection (spec §3): players whose
//     FreeSwapsGw?:int,   //   position change broke this squad's formation
//                       //   — selling one of them in gameweek FreeSwapsGw
//                       //   costs no transfer (recordSquadSave discounts
//                       //   it); dropped at that week's rollover. Both
//                       //   present or both absent.
//     CountFromGw?:int,  // the TRANSFER BASELINE the fan app counts a
//     CountFrom?:[playerId] } //   week's transfers against: CountFrom =
//                       //   the player ids of the squad the manager
//                       //   effectively held coming in to gameweek
//                       //   CountFromGw (effectiveSquadAfterWeek(gw-1), Free
//                       //   Hit aware — the very squad recordSquadSave and
//                       //   the lock count against, so the app's live
//                       //   counter and the server's can never disagree).
//                       //   CountFromGw present with CountFrom ABSENT = "no
//                       //   squad to count from: a first team" (RTDB drops
//                       //   an empty array, so null ids are never written
//                       //   as []). Both absent = no baseline published
//                       //   (an older node); CountFrom without CountFromGw
//                       //   is half-written and reads as none. Written by
//                       //   the rollover (for gw + 1) and by every counted
//                       //   save (for the open gw); the lock freeze keeps it.
//
// SavedGw and RolledGw extend the spec'd {Free, UsedThisGw, ChipPlayed}
// shape: SavedGw is the measurable "squad save this gw" rule the deadline
// reminder needs (spec §12), RolledGw is what keeps the idempotent,
// re-runnable finalize from rolling transfers (or restoring a Free Hit
// squad) twice.

import { FantasyConfig } from './fantasy_config';
import { childEntries, isPlainMap, toIntLoose } from './orchestration_db';
import { REALIZED_KEY } from './selling';
import { FantasySquad, squadFromMap } from './squad';
import {
  baselineRealizedFor, baselineSquadOf, INVALID_KEY, integrityVerdictOf,
  IntegrityInputs, picksAtJudgedPrices, SquadIntegrityIssue,
} from './squad_integrity';
import { rolloverFreeTransfers, transferCost } from './transfers';

export interface TransferState {
  free: number;
  usedThisGw: number;
  chipPlayed: string | null;
  savedGw: number | null;
  rolledGw: number | null;
  /** Holder-protection free swaps (FreeSwaps + FreeSwapsGw); absent = none. */
  freeSwaps?: { gw: number; players: string[] };
  /** The transfer baseline (CountFromGw + CountFrom): the squad ids gameweek
   *  [gw]'s transfers count against. ids null = no squad to count from (a
   *  first team: nothing counts). Absent = no baseline published. */
  countFrom?: { gw: number; ids: string[] | null };
}

/** Tolerant node parse. An absent node is a manager who never transferred:
 *  the full weekly allowance, nothing used. */
export function parseTransferState(
  raw: unknown, cfg: FantasyConfig,
): TransferState {
  const m = isPlainMap(raw) ? raw : {};
  const chip = m['ChipPlayed'];
  const savedGw = toIntLoose(m['SavedGw']);
  const rolledGw = toIntLoose(m['RolledGw']);
  const swapsGw = toIntLoose(m['FreeSwapsGw']);
  const swaps = childEntries(m['FreeSwaps'])
    .map(([, v]) => v)
    .filter((v): v is string => typeof v === 'string' && v.length > 0);
  const countFromGw = toIntLoose(m['CountFromGw']);
  const countFromIds = childEntries(m['CountFrom'])
    .map(([, v]) => v)
    .filter((v): v is string => typeof v === 'string' && v.length > 0);
  return {
    free: typeof m['Free'] === 'number'
      ? Math.trunc(m['Free']) : cfg.freeTransfersPerWeek,
    usedThisGw: toIntLoose(m['UsedThisGw']),
    chipPlayed: typeof chip === 'string' && chip.length > 0 ? chip : null,
    savedGw: savedGw > 0 ? savedGw : null,
    rolledGw: rolledGw > 0 ? rolledGw : null,
    ...(swapsGw > 0 && swaps.length > 0
      ? { freeSwaps: { gw: swapsGw, players: swaps } } : {}),
    // CountFromGw is the anchor: with it, no CountFrom = a first team; a
    // CountFrom without it is half-written and reads as none.
    ...(countFromGw > 0 ? {
      countFrom: {
        gw: countFromGw, ids: countFromIds.length > 0 ? countFromIds : null,
      },
    } : {}),
  };
}

export function transferStateToNode(s: TransferState): Record<string, unknown> {
  const out: Record<string, unknown> = {
    Free: s.free, UsedThisGw: s.usedThisGw,
  };
  if (s.chipPlayed !== null) out['ChipPlayed'] = s.chipPlayed;
  if (s.savedGw !== null) out['SavedGw'] = s.savedGw;
  if (s.rolledGw !== null) out['RolledGw'] = s.rolledGw;
  if (s.freeSwaps && s.freeSwaps.players.length > 0) {
    out['FreeSwaps'] = [...s.freeSwaps.players];
    out['FreeSwapsGw'] = s.freeSwaps.gw;
  }
  if (s.countFrom) {
    out['CountFromGw'] = s.countFrom.gw;
    // No ids = "a first team": only CountFromGw is written (never []).
    if (s.countFrom.ids !== null && s.countFrom.ids.length > 0) {
      out['CountFrom'] = [...s.countFrom.ids];
    }
  }
  return out;
}

/** The player ids of a squad node's picks, in pick order — what
 *  TransferState.CountFrom publishes. null when [squadRaw] is not a map or
 *  holds no usable pick id (RTDB drops an empty array, so "none" is always
 *  null, never []). Tolerant like every node reader here: no squad parse,
 *  so an unreadable-but-present squad still yields the ids it has. */
export function pickIdsOf(squadRaw: unknown): string[] | null {
  if (!isPlainMap(squadRaw)) return null;
  const ids = childEntries(squadRaw['picks'])
    .map(([, pick]) => (isPlainMap(pick) ? pick['playerId'] : null))
    .filter((id): id is string => typeof id === 'string' && id.length > 0);
  return ids.length > 0 ? ids : null;
}

/** Used transfers after holder protection: each FREE-SWAP player (spec §3 —
 *  his position change broke the squad's formation) who was in the
 *  baseline and is no longer in the saved squad pays for one incoming
 *  player, so swapping him out costs nothing. Only for the swaps' own
 *  gameweek. */
export function usedAfterFreeSwaps(
  newSquad: FantasySquad, prevSquad: FantasySquad,
  state: TransferState, gw: number,
): number {
  const used = usedTransfers(newSquad, prevSquad);
  if (!state.freeSwaps || state.freeSwaps.gw !== gw) return used;
  const before = new Set(prevSquad.picks.map((p) => p.playerId));
  const now = new Set(newSquad.picks.map((p) => p.playerId));
  const sold = state.freeSwaps.players
    .filter((p) => before.has(p) && !now.has(p)).length;
  return Math.max(0, used - sold);
}

/** Wildcard / Free Hit weeks are unlimited (the engine's `unlimited` flag). */
export function isUnlimitedChip(chip: string | null): boolean {
  return chip === 'wildcard' || chip === 'freeHit';
}

/** Used transfers = players in the new squad that were NOT in the previous
 *  locked squad (spec §5). Position/bench/captain shuffles of the same
 *  players are free. */
export function usedTransfers(
  newSquad: FantasySquad, prevSquad: FantasySquad,
): number {
  const prevIds = new Set(prevSquad.picks.map((p) => p.playerId));
  return newSquad.picks.filter((p) => !prevIds.has(p.playerId)).length;
}

/** Chip set of a gameweek: set 1 runs GW1..chipSet1EndGw, set 2 the rest of
 *  the season including playoffs (spec §6). */
export function chipSetOf(gw: number, cfg: FantasyConfig): number {
  return gw <= cfg.chipSet1EndGw ? 1 : 2;
}

/** One manager's honored chip history ({week: chip}) out of the raw History
 *  node — set-repeated chips were stripped before the snapshot, so every
 *  chip in History was really consumed. EXCEPT in owner-voided gameweeks
 *  ([voidedWeeks], Voided/<gw> == true, spec §15): a chip played in a week
 *  that counted zero is REFUNDED, so those weeks are skipped and the chip
 *  can be played again inside the same set. (The History entry itself keeps
 *  the chip — it is what the manager locked; un-voiding re-consumes it.) */
export function priorChipsOfUid(
  historyRaw: unknown, uid: string, voidedWeeks: readonly number[] = [],
): Record<number, string> {
  const out: Record<number, string> = {};
  for (const [w, byUid] of childEntries(historyRaw)) {
    const week = Number(w);
    if (!Number.isInteger(week) || !isPlainMap(byUid)) continue;
    if (voidedWeeks.includes(week)) continue; // refunded

    const entry = byUid[uid];
    if (!isPlainMap(entry)) continue;
    const chip = entry['chip'];
    if (typeof chip === 'string' && chip.length > 0) out[week] = chip;
  }
  return out;
}

/** Server chip-set enforcement (client UX shows the counts; the server is
 *  the law at lock): a chip already consumed in an EARLIER gameweek of the
 *  same set is void this week. */
export function shouldVoidChip(args: {
  chip: string;
  gw: number;
  priorChips: Record<number, string>;
  cfg: FantasyConfig;
}): boolean {
  const set = chipSetOf(args.gw, args.cfg);
  for (const [w, c] of Object.entries(args.priorChips)) {
    const week = Number(w);
    if (week < args.gw && chipSetOf(week, args.cfg) === set && c === args.chip) {
      return true;
    }
  }
  return false;
}

export interface LockAccounting {
  /** The squads to snapshot/score: verbatim per uid, except a voided chip is
   *  stripped (every other field untouched — the snapshot stays the
   *  manager's own writing). */
  cleanSquads: Record<string, unknown>;
  /** Non-zero transfer cost points per uid (TransferCosts/<gw> rows). */
  costPointsByUid: Record<string, number>;
  /** The lock's recount of used transfers (lockUsedTransfers), ONLY for
   *  the uids where it beat the stored UsedThisGw — the caller raises
   *  TransferState.UsedThisGw to it (max, re-read) so the rollover banks
   *  from the transfers really made (orchestration.ts
   *  freezeLockTransferState). Empty without [integrity]. */
  usedByUid: Record<string, number>;
  /** Effective chip per uid (post-void; null = none) — frozen into
   *  TransferState.ChipPlayed. Only uids with a parseable squad appear. */
  chipPlayedByUid: Record<string, string | null>;
  /** Voided chips, for the caller's log. */
  voided: Array<{ uid: string; chip: string }>;
  /** Squads judged invalid (audit I2; squad_integrity.ts) — their
   *  cleanSquads entry carries `Invalid: issues`. Only when the caller
   *  passed [integrity]. */
  invalid: Array<{ uid: string; issues: SquadIntegrityIssue[] }>;
  /** Parseable squads judged clean (only with [integrity]) — the caller
   *  clears a stale integrity alert for them. */
  valid: string[];
}

/** The integrity pass on its own (audit I2): every parseable squad judged
 *  against [inputs] and turned into the node the lock snapshots
 *  (PublishedPicks/<gw>/<uid>; FPL selling, spec §4 — squad_integrity.ts
 *  TRUSTED PRICES):
 *  - VALID: its picks re-priced at the verdict's trusted prices (every
 *    other key kept), `realizedTenths` = the verdict's, and any `Invalid`
 *    key dropped (only the server ever writes the marker) — next week's
 *    held prices and realized money are the judge's own, never the
 *    client's.
 *  - INVALID: verbatim (so the manager sees exactly what was judged) plus
 *    `Invalid: [issues]` and `realizedTenths` = the total the judge started
 *    from (baselineRealizedFor — no sale credited for a week that didn't
 *    count).
 *  A `realizedTenths` the client wrote is replaced either way. Malformed
 *  squads pass through untouched. Used by lockAccounting and by a first
 *  finalize's live-Squads fallback that skips the accounting. */
export function annotateSquadIntegrity(
  squadsByUid: Record<string, unknown>, cfg: FantasyConfig,
  inputs: IntegrityInputs,
): Pick<LockAccounting, 'invalid' | 'valid'> & {
  squads: Record<string, unknown>;
} {
  const squads: Record<string, unknown> = {};
  const invalid: Array<{ uid: string; issues: SquadIntegrityIssue[] }> = [];
  const valid: string[] = [];
  for (const [uid, raw] of Object.entries(squadsByUid)) {
    squads[uid] = raw;
    const verdict = integrityVerdictOf(raw, uid, cfg, inputs);
    if (verdict === null) continue; // malformed: existing handling
    const node = { ...(raw as Record<string, unknown>) };
    if (verdict.issues.length > 0) {
      node[INVALID_KEY] = verdict.issues;
      node[REALIZED_KEY] = baselineRealizedFor(inputs, uid); // the judge's own
      invalid.push({ uid, issues: verdict.issues });
    } else {
      delete node[INVALID_KEY];
      node['picks'] = picksAtJudgedPrices(node['picks'], verdict.prices);
      node[REALIZED_KEY] = verdict.realizedTenths;
      valid.push(uid);
    }
    squads[uid] = node;
  }
  return { squads, invalid, valid };
}

/** The used transfers the lock charges for: the stored UsedThisGw (counted
 *  by the save trigger, recordSquadSave, on every save while GwState says
 *  'open'), raised to a recount of the LOCKED squad against the manager's
 *  baseline — integrity.previousByUid[uid], the same effective squad the
 *  trigger counts against — with the same free-swap discount
 *  (usedAfterFreeSwaps). Catches saves the trigger never counted: the
 *  rules' +24 h reopen gap (a save once lock + 24 h has passed while
 *  GwState still says 'locked'/'finalized'), a 'locked' override before
 *  the lock, an 'open' override after GwState left 'open', a trigger that
 *  failed. max(): the recount never lowers what the trigger recorded. No
 *  integrity inputs, or no usable baseline (absent, malformed or
 *  Invalid-marked — baselineSquadOf null, the judge's own fresh start) →
 *  the stored value unchanged. A wildcard / Free Hit week is still free:
 *  the caller passes `unlimited` for the post-void chip. */
function lockUsedTransfers(
  squad: FantasySquad, uid: string, state: TransferState, gw: number,
  integrity: IntegrityInputs | undefined,
): number {
  if (integrity === undefined) return state.usedThisGw;
  const baseline = baselineSquadOf(integrity.previousByUid[uid]);
  if (baseline === null) return state.usedThisGw;
  return Math.max(state.usedThisGw,
    usedAfterFreeSwaps(squad, baseline, state, gw));
}

/** The whole lock-time transfer accounting, pure: per manager, void a chip
 *  reused within its set, freeze the effective chip, and price the week's
 *  transfers (used vs Free; wildcard/freeHit = unlimited = free — Used stays
 *  recorded, nothing is charged). Malformed squads pass through verbatim
 *  with no accounting (finalize skips them the same way). Chips from
 *  owner-voided weeks ([voidedWeeks]) never count as used (refund — see
 *  priorChipsOfUid). The cost is still frozen for a voided week: finalize
 *  waives it while the week stays voided, and an un-void re-settle charges
 *  exactly what the lock froze.
 *
 *  INTEGRITY (audit I2, squad hardening 2026-11-01): with [integrity] (the
 *  market, each manager's previous locked squad and last week's prices —
 *  orchestration.ts loadIntegrityInputs) every squad is first judged by
 *  squad_integrity.ts; an invalid one is snapshotted verbatim plus
 *  `Invalid: [issues]` and finalize scores it zero. Its chip/cost
 *  accounting runs as for any squad (the chip it locked is consumed; the
 *  cost is moot — the week nets zero). Without [integrity] nothing is
 *  judged (a snapshot that already carries a marker keeps it verbatim).
 *
 *  RECOUNT (FPL selling plan Task 5): with [integrity] the week's used
 *  transfers are also recounted from the locked squad itself — see
 *  lockUsedTransfers. The cost is priced from it, and [usedByUid] carries
 *  every recount that beat the stored count for the caller to persist. */
export function lockAccounting(args: {
  squadsByUid: Record<string, unknown>;
  statesByUid: Record<string, unknown>;
  historyRaw: unknown;
  cfg: FantasyConfig;
  gw: number;
  voidedWeeks?: readonly number[];
  integrity?: IntegrityInputs;
}): LockAccounting {
  const { cfg, gw } = args;
  let squadsByUid = args.squadsByUid;
  let invalid: LockAccounting['invalid'] = [];
  let valid: string[] = [];
  if (args.integrity !== undefined) {
    const judged = annotateSquadIntegrity(squadsByUid, cfg, args.integrity);
    squadsByUid = judged.squads;
    invalid = judged.invalid;
    valid = judged.valid;
  }
  const cleanSquads: Record<string, unknown> = {};
  const costPointsByUid: Record<string, number> = {};
  const usedByUid: Record<string, number> = {};
  const chipPlayedByUid: Record<string, string | null> = {};
  const voided: Array<{ uid: string; chip: string }> = [];

  for (const [uid, raw] of Object.entries(squadsByUid)) {
    cleanSquads[uid] = raw;
    if (!isPlainMap(raw)) continue;
    let squad: FantasySquad;
    try {
      squad = squadFromMap(raw);
    } catch {
      continue; // malformed: snapshot verbatim, no accounting
    }

    let chip = squad.chip;
    if (chip !== null && shouldVoidChip({
      chip,
      gw,
      priorChips: priorChipsOfUid(args.historyRaw, uid, args.voidedWeeks),
      cfg,
    })) {
      voided.push({ uid, chip });
      chip = null;
      const stripped = { ...raw };
      delete stripped['chip'];
      cleanSquads[uid] = stripped;
    }
    chipPlayedByUid[uid] = chip;

    const state = parseTransferState(args.statesByUid[uid], cfg);
    const used = lockUsedTransfers(squad, uid, state, gw, args.integrity);
    if (used > state.usedThisGw) usedByUid[uid] = used;
    const cost = transferCost({
      used,
      free: state.free,
      cfg,
      unlimited: isUnlimitedChip(chip),
    });
    if (cost > 0) costPointsByUid[uid] = cost;
  }
  return {
    cleanSquads, costPointsByUid, usedByUid, chipPlayedByUid, voided,
    invalid, valid,
  };
}

/** What the rollover needs to know about ONE manager beyond his stored
 *  state — all read from the locked squads by the caller
 *  (orchestration.ts settleTransfersAfterFinalize). */
export interface RolloverBasis {
  /** The week just finished was his FIRST team: no locked squad the week
   *  before (effectiveSquadAfterWeek(gw-1) is null). Building a first team
   *  is free, so nothing banks — next week is the plain weekly grant. */
  firstWeek: boolean;
  /** The player ids of the squad he effectively held after this week
   *  (effectiveSquadAfterWeek(gw), Free Hit aware): next week's transfer
   *  baseline. null = he held none (squad deleted before the lock — his next
   *  squad is a first team). */
  countFromIds: string[] | null;
  /** He was scored this week. false = no locked squad (e.g. deleted before
   *  the lock): nothing was charged, so the week rolls as if he used
   *  nothing — whatever a mid-week save counted — and the bank keeps
   *  growing instead of freezing on him. */
  scored: boolean;
}

/** The post-finalize rollover of one manager's state: next week's Free per
 *  the engine (a wildcard/freeHit week doesn't consume the bank; a first
 *  team never banks — see [basis]), counter reset, ChipPlayed cleared,
 *  RolledGw stamped, and next week's transfer baseline published
 *  (countFrom = { gw + 1, ids }). UsedThisGw survives only when the manager
 *  already saved for a LATER gameweek (a delayed finalize must not erase next
 *  week's running count); free swaps likewise survive only when granted for
 *  a LATER gameweek. */
export function rolloverState(
  state: TransferState, cfg: FantasyConfig, gw: number, basis: RolloverBasis,
): TransferState {
  return {
    free: rolloverFreeTransfers({
      free: state.free,
      used: basis.scored ? state.usedThisGw : 0,
      cfg,
      unlimited: isUnlimitedChip(state.chipPlayed),
      firstWeek: basis.firstWeek,
    }),
    usedThisGw:
      state.savedGw !== null && state.savedGw > gw ? state.usedThisGw : 0,
    chipPlayed: null,
    savedGw: state.savedGw,
    rolledGw: gw,
    countFrom: { gw: gw + 1, ids: basis.countFromIds },
    ...(state.freeSwaps && state.freeSwaps.gw > gw
      ? { freeSwaps: state.freeSwaps } : {}),
  };
}
