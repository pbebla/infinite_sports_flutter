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
//                       //   while the gameweek is open
//     ChipPlayed?:string, // frozen at lock from the locked squad's chip
//                       //   (post-void); cleared again at rollover
//     SavedGw?:int,     // gameweek of the manager's latest squad save —
//                       //   the reminder audience's "changed" marker;
//                       //   server writes to Squads (ServerWriteAt —
//                       //   orchestration_db.ts) never stamp it
//     RolledGw?:int,    // last gameweek whose post-finalize rollover ran
//                       //   (once-only guard for rollover + freeHit restore)
//     FreeSwaps?:[name], // holder protection (spec §3): players whose
//     FreeSwapsGw?:int }  //   position change broke this squad's formation
//                       //   — selling one of them in gameweek FreeSwapsGw
//                       //   costs no transfer (recordSquadSave discounts
//                       //   it); dropped at that week's rollover. Both
//                       //   present or both absent.
//
// SavedGw and RolledGw extend the spec'd {Free, UsedThisGw, ChipPlayed}
// shape: SavedGw is the measurable "squad save this gw" rule the deadline
// reminder needs (spec §12), RolledGw is what keeps the idempotent,
// re-runnable finalize from rolling transfers (or restoring a Free Hit
// squad) twice.

import { FantasyConfig } from './fantasy_config';
import { childEntries, isPlainMap, toIntLoose } from './orchestration_db';
import { FantasySquad, squadFromMap } from './squad';
import { rolloverFreeTransfers, transferCost } from './transfers';

export interface TransferState {
  free: number;
  usedThisGw: number;
  chipPlayed: string | null;
  savedGw: number | null;
  rolledGw: number | null;
  /** Holder-protection free swaps (FreeSwaps + FreeSwapsGw); absent = none. */
  freeSwaps?: { gw: number; players: string[] };
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
  return {
    free: typeof m['Free'] === 'number'
      ? Math.trunc(m['Free']) : cfg.freeTransfersPerWeek,
    usedThisGw: toIntLoose(m['UsedThisGw']),
    chipPlayed: typeof chip === 'string' && chip.length > 0 ? chip : null,
    savedGw: savedGw > 0 ? savedGw : null,
    rolledGw: rolledGw > 0 ? rolledGw : null,
    ...(swapsGw > 0 && swaps.length > 0
      ? { freeSwaps: { gw: swapsGw, players: swaps } } : {}),
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
  return out;
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
  /** Effective chip per uid (post-void; null = none) — frozen into
   *  TransferState.ChipPlayed. Only uids with a parseable squad appear. */
  chipPlayedByUid: Record<string, string | null>;
  /** Voided chips, for the caller's log. */
  voided: Array<{ uid: string; chip: string }>;
}

/** The whole lock-time transfer accounting, pure: per manager, void a chip
 *  reused within its set, freeze the effective chip, and price the week's
 *  transfers (used vs Free; wildcard/freeHit = unlimited = free — Used stays
 *  recorded, nothing is charged). Malformed squads pass through verbatim
 *  with no accounting (finalize skips them the same way). Chips from
 *  owner-voided weeks ([voidedWeeks]) never count as used (refund — see
 *  priorChipsOfUid). The cost is still frozen for a voided week: finalize
 *  waives it while the week stays voided, and an un-void re-settle charges
 *  exactly what the lock froze. */
export function lockAccounting(args: {
  squadsByUid: Record<string, unknown>;
  statesByUid: Record<string, unknown>;
  historyRaw: unknown;
  cfg: FantasyConfig;
  gw: number;
  voidedWeeks?: readonly number[];
}): LockAccounting {
  const { cfg, gw } = args;
  const cleanSquads: Record<string, unknown> = {};
  const costPointsByUid: Record<string, number> = {};
  const chipPlayedByUid: Record<string, string | null> = {};
  const voided: Array<{ uid: string; chip: string }> = [];

  for (const [uid, raw] of Object.entries(args.squadsByUid)) {
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
    const cost = transferCost({
      used: state.usedThisGw,
      free: state.free,
      cfg,
      unlimited: isUnlimitedChip(chip),
    });
    if (cost > 0) costPointsByUid[uid] = cost;
  }
  return { cleanSquads, costPointsByUid, chipPlayedByUid, voided };
}

/** The post-finalize rollover of one manager's state: next week's Free per
 *  the engine (a wildcard/freeHit week doesn't consume the bank), counter
 *  reset, ChipPlayed cleared, RolledGw stamped. UsedThisGw survives only
 *  when the manager already saved for a LATER gameweek (a delayed finalize
 *  must not erase next week's running count); free swaps likewise survive
 *  only when granted for a LATER gameweek. */
export function rolloverState(
  state: TransferState, cfg: FantasyConfig, gw: number,
): TransferState {
  return {
    free: rolloverFreeTransfers({
      free: state.free,
      used: state.usedThisGw,
      cfg,
      unlimited: isUnlimitedChip(state.chipPlayed),
    }),
    usedThisGw:
      state.savedGw !== null && state.savedGw > gw ? state.usedThisGw : 0,
    chipPlayed: null,
    savedGw: state.savedGw,
    rolledGw: gw,
    ...(state.freeSwaps && state.freeSwaps.gw > gw
      ? { freeSwaps: state.freeSwaps } : {}),
  };
}
