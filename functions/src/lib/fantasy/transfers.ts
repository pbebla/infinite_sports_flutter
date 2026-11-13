// Transfer cost + rollover. Faithful port of lib/fantasy/engine/transfers.dart.

import { FantasyConfig } from './fantasy_config';

/** Dart num.clamp(lo, hi). */
function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/** Point cost of making [used] transfers with [free] available (spec §5).
 *  Wildcard / Free Hit weeks ([unlimited]) are always free. */
export function transferCost(args: {
  used: number;
  free: number;
  cfg: FantasyConfig;
  unlimited?: boolean;
}): number {
  if (args.unlimited === true) return 0;
  const extra = args.used - args.free;
  return extra > 0 ? extra * args.cfg.extraTransferCost : 0;
}

/** Free transfers available next gameweek. Unused ones bank (cap 7); a
 *  wildcard/free-hit week doesn't consume the bank.
 *
 *  [firstWeek]: the week just finished was the manager's FIRST team. Building
 *  it cost nothing, so there is no unused allowance to carry — he starts the
 *  next week on the plain weekly grant, whatever the stored Free says
 *  (without this a GW1 manager opened GW2 with 4, a bank he never earned).
 *  Not "no squad last week": a manager who deletes and rebuilds a squad
 *  inside an open week still has the week before's locked squad (callers
 *  decide firstWeek from that). */
export function rolloverFreeTransfers(args: {
  free: number;
  used: number;
  cfg: FantasyConfig;
  unlimited?: boolean;
  firstWeek?: boolean;
}): number {
  if (args.firstWeek === true) return args.cfg.freeTransfersPerWeek;
  const remaining = args.unlimited === true
    ? args.free
    : clamp(args.free - args.used, 0, args.free);
  return clamp(
    remaining + args.cfg.freeTransfersPerWeek, 0, args.cfg.maxBankedTransfers);
}
