// The fan app's transfer preview (lib/fantasy/hub/transfer_preview.dart
// transferPreview, plan 2026-11-03) counts a draft against the published
// baseline (TransferState.CountFrom) with its own small rule. The server
// counts the same squad with usedAfterFreeSwaps + transferCost at every save
// and at the lock — so the line a manager sees and the points the lock
// charges must be the same number. This pins the two together over the same
// raw TransferState nodes: `dartPreview` below is a line-for-line TS mirror
// of the Dart counting rule (Dart can't run here), the right-hand side is
// the real server code. Same pattern as client_draft_money.test.ts.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from '../src/lib/fantasy/fantasy_config';
import { FantasySquad, SquadPick } from '../src/lib/fantasy/squad';
import {
  isUnlimitedChip, parseTransferState, usedAfterFreeSwaps,
} from '../src/lib/fantasy/transfer_state';
import { transferCost } from '../src/lib/fantasy/transfers';

const cfg = futsalDefault(); // 2 free per week, 4 points each extra

const BASELINE = ['B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7'];
/** The baseline with its first [n] players swapped for newcomers. */
const swapped = (n: number): string[] =>
  BASELINE.map((id, i) => (i < n ? `N${i}` : id));

/** A TransferState/<uid> node for gameweek 5's baseline. */
const node = (over: Record<string, unknown> = {}): Record<string, unknown> =>
  ({ Free: 2, UsedThisGw: 0, CountFromGw: 5, CountFrom: BASELINE, ...over });

// ── The Dart side: TransferStateView + transferPreview's counting rule ────
interface View {
  free: number | null; countFromGw: number | null; countFrom: string[] | null;
  freeSwapsGw: number | null; freeSwaps: string[];
}
const ids = (v: unknown): string[] => (Array.isArray(v) ? v : [])
  .filter((x): x is string => typeof x === 'string' && x.length > 0);
/** parseTransferState (fantasy_parsers.dart) for list-shaped nodes. */
const viewOf = (n: Record<string, unknown>): View => {
  const cgw = Number(n['CountFromGw']) > 0 ? Number(n['CountFromGw']) : null;
  const sgw = Number(n['FreeSwapsGw']) > 0 ? Number(n['FreeSwapsGw']) : null;
  const swaps = sgw === null ? [] : ids(n['FreeSwaps']);
  const from = cgw === null ? [] : ids(n['CountFrom']);
  return {
    free: typeof n['Free'] === 'number' ? Math.trunc(n['Free']) : null,
    countFromGw: cgw, countFrom: from.length > 0 ? from : null,
    freeSwapsGw: swaps.length > 0 ? sgw : null, freeSwaps: swaps,
  };
};
const dartPreview = (draft: string[], v: View, editingGw: number, chip: string | null) => {
  if (chip === 'wildcard' || chip === 'freeHit') return { used: 0, free: 0, cost: 0 };
  const before = new Set(v.countFrom), now = new Set(draft);
  let used = draft.filter((id) => !before.has(id)).length;
  if (v.freeSwapsGw === editingGw) {
    used = Math.max(0, used - v.freeSwaps.filter((p) => before.has(p) && !now.has(p)).length);
  }
  const free = v.free ?? cfg.freeTransfersPerWeek;
  return { used, free, cost: used > free ? (used - free) * cfg.extraTransferCost : 0 };
};

// ── The server side: the real functions ───────────────────────────────────
const squadOf = (playerIds: string[], chip: string | null = null): FantasySquad => ({
  picks: playerIds.map((playerId): SquadPick =>
    ({ playerId, position: 'DEF', priceTenths: 50, bench: false })),
  captainId: '', viceId: '', chip,
});
const serverCount = (draft: string[], n: Record<string, unknown>, gw: number, chip: string | null) => {
  const state = parseTransferState(n, cfg);
  const prev = squadOf(state.countFrom?.ids ?? []);
  const used = usedAfterFreeSwaps(squadOf(draft, chip), prev, state, gw);
  const unlimited = isUnlimitedChip(chip);
  return { used, free: state.free, cost: transferCost({ used, free: state.free, cfg, unlimited }), unlimited };
};

describe('the app\'s transfer preview equals the server\'s count and cost', () => {
  const fixtures: Array<{ name: string; draft: string[]; node: Record<string, unknown>; chip: string | null; cost: number }> = [
    { name: 'no changes', draft: BASELINE, node: node(), chip: null, cost: 0 },
    { name: '1 transfer within 2 free', draft: swapped(1), node: node(), chip: null, cost: 0 },
    { name: '2 transfers = 2 free', draft: swapped(2), node: node(), chip: null, cost: 0 },
    { name: '3 transfers over 2 free', draft: swapped(3), node: node(), chip: null, cost: 4 },
    { name: '4 transfers over 2 free', draft: swapped(4), node: node(), chip: null, cost: 8 },
    { name: 'a free swap sold this week is not counted',
      draft: swapped(3), node: node({ FreeSwaps: ['B1'], FreeSwapsGw: 5 }), chip: null, cost: 0 },
    { name: 'a free swap from another week is counted',
      draft: swapped(3), node: node({ FreeSwaps: ['B1'], FreeSwapsGw: 4 }), chip: null, cost: 4 },
    { name: 'Wildcard: everything free', draft: swapped(5), node: node(), chip: 'wildcard', cost: 0 },
    { name: 'Free Hit: everything free', draft: swapped(7), node: node(), chip: 'freeHit', cost: 0 },
    { name: 'a banked allowance of 4', draft: swapped(3), node: node({ Free: 4 }), chip: null, cost: 0 },
    { name: 'Free absent: the config allowance', draft: swapped(3),
      node: (() => { const n = node(); delete n['Free']; return n; })(), chip: null, cost: 4 },
  ];

  for (const f of fixtures) {
    it(f.name, () => {
      const app = dartPreview(f.draft, viewOf(f.node), 5, f.chip);
      const server = serverCount(f.draft, f.node, 5, f.chip);
      expect(app.cost).toBe(server.cost);
      expect(app.cost).toBe(f.cost);
      if (!server.unlimited) {
        expect(app.used).toBe(server.used);
        expect(app.free).toBe(server.free);
      }
    });
  }

  it('a reorder of the same players is free on both', () => {
    const draft = [...BASELINE].reverse();
    const app = dartPreview(draft, viewOf(node()), 5, null);
    expect(app.used).toBe(0);
    expect(serverCount(draft, node(), 5, null).used).toBe(0);
  });
});
