// Phase E pure logic: TransferState parsing, used-transfer counting, chip
// sets + voiding, lock accounting (cost freeze) and the rollover. Every
// expected number is hand-computed from the futsal default config
// (2 free/week, bank cap 7, -4 per extra transfer, chipSet1EndGw 6).

import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import { FantasySquad } from './squad';
import { IntegrityInputs, integrityMarketOf } from './squad_integrity';
import {
  annotateSquadIntegrity, chipSetOf, isUnlimitedChip, LockAccounting,
  lockAccounting, parseTransferState, pickIdsOf, priorChipsOfUid,
  rolloverState, shouldVoidChip, transferStateToNode, usedTransfers,
} from './transfer_state';

const cfg = futsalDefault();

// The rollover's per-manager basis: scored in a normal week, with a squad
// held coming in (not a first week) and nothing to publish as the baseline.
const held = { firstWeek: false, countFromIds: null, scored: true };

function mkSquad(ids: string[], chip: string | null = null): FantasySquad {
  return {
    picks: ids.map((id, i) => ({
      playerId: id, position: 'ATT', priceTenths: 50, bench: i >= 5,
    })),
    captainId: ids[0],
    viceId: ids[1] ?? ids[0],
    chip,
  };
}

function mkSquadMap(ids: string[], chip?: string): Record<string, unknown> {
  return {
    picks: ids.map((id, i) => ({
      playerId: id, position: 'ATT', priceTenths: 50, bench: i >= 5,
    })),
    captainId: ids[0],
    viceId: ids[1] ?? ids[0],
    ...(chip ? { chip } : {}),
  };
}

describe('parseTransferState', () => {
  it('absent node = full weekly allowance, nothing used', () => {
    expect(parseTransferState(null, cfg)).toEqual({
      free: 2, usedThisGw: 0, chipPlayed: null, savedGw: null, rolledGw: null,
    });
  });

  it('round-trips through transferStateToNode (optional fields omitted when null)', () => {
    const full = {
      free: 4, usedThisGw: 3, chipPlayed: 'freeHit', savedGw: 5, rolledGw: 4,
    };
    expect(parseTransferState(transferStateToNode(full), cfg)).toEqual(full);
    const bare = {
      free: 2, usedThisGw: 0, chipPlayed: null, savedGw: null, rolledGw: null,
    };
    expect(transferStateToNode(bare)).toEqual({ Free: 2, UsedThisGw: 0 });
  });

  it('holder-protection free swaps round-trip; half-written or empty ones read as none', () => {
    const s = {
      free: 2, usedThisGw: 1, chipPlayed: null, savedGw: 3, rolledGw: 2,
      freeSwaps: { gw: 3, players: ['Bea', 'Ezra'] },
    };
    const node = transferStateToNode(s);
    expect(node).toMatchObject({ FreeSwaps: ['Bea', 'Ezra'], FreeSwapsGw: 3 });
    expect(parseTransferState(node, cfg)).toEqual(s);
    expect(parseTransferState({ FreeSwaps: ['Bea'] }, cfg).freeSwaps).toBeUndefined();
    expect(parseTransferState({ FreeSwaps: [], FreeSwapsGw: 3 }, cfg).freeSwaps)
      .toBeUndefined();
    // Rollover keeps swaps only when granted for a LATER gameweek.
    expect(rolloverState(s, cfg, 3, held).freeSwaps).toBeUndefined();
    expect(rolloverState(s, cfg, 2, held).freeSwaps).toEqual(s.freeSwaps);
  });

  // The transfer baseline the rollover publishes for the fan app (CountFrom /
  // CountFromGw). CountFromGw present with CountFrom absent = "no squad to
  // count from: a first team"; both absent = no basis published; a
  // CountFrom without its CountFromGw is half-written and reads as none.
  it('CountFrom / CountFromGw round-trip through the node', () => {
    const s = {
      free: 2, usedThisGw: 0, chipPlayed: null, savedGw: null, rolledGw: 2,
      countFrom: { gw: 3, ids: ['A', 'B', 'C'] },
    };
    const node = transferStateToNode(s);
    expect(node).toMatchObject({ CountFromGw: 3, CountFrom: ['A', 'B', 'C'] });
    expect(parseTransferState(node, cfg)).toEqual(s);
  });

  it('CountFromGw alone reads as a first team: {gw, ids: null}, and writes back alone', () => {
    const parsed = parseTransferState({ Free: 2, UsedThisGw: 0, CountFromGw: 3 }, cfg);
    expect(parsed.countFrom).toEqual({ gw: 3, ids: null });
    const node = transferStateToNode(parsed);
    expect(node['CountFromGw']).toBe(3);
    expect('CountFrom' in node).toBe(false); // RTDB drops empty arrays anyway
  });

  it('a half-written baseline (one field without the other) reads as none', () => {
    expect(parseTransferState({ CountFrom: ['A', 'B'] }, cfg).countFrom)
      .toBeUndefined();
    expect(parseTransferState({ CountFrom: ['A'], CountFromGw: 0 }, cfg).countFrom)
      .toBeUndefined();
    expect(parseTransferState({ CountFromGw: 'nope' }, cfg).countFrom)
      .toBeUndefined();
    // Absent baseline: nothing written for it either.
    const bare = transferStateToNode(parseTransferState({ Free: 3 }, cfg));
    expect('CountFromGw' in bare || 'CountFrom' in bare).toBe(false);
  });

  it('CountFrom keeps only usable ids (RTDB null-padded arrays, junk entries)', () => {
    const parsed = parseTransferState({
      CountFromGw: 4, CountFrom: ['A', null, '', 7, 'B'],
    }, cfg);
    expect(parsed.countFrom).toEqual({ gw: 4, ids: ['A', 'B'] });
  });
});

describe('pickIdsOf', () => {
  it("lists a squad node's pick ids in pick order; null when there are none", () => {
    expect(pickIdsOf(mkSquadMap(['A', 'B', 'C']))).toEqual(['A', 'B', 'C']);
    expect(pickIdsOf(null)).toBeNull();
    expect(pickIdsOf({ picks: 'nope' })).toBeNull();
    expect(pickIdsOf({ picks: [] })).toBeNull();
    expect(pickIdsOf({ picks: [{ playerId: '' }, { position: 'GK' }] })).toBeNull();
  });
});

describe('usedTransfers', () => {
  const prev = mkSquad(['A', 'B', 'C', 'D', 'E', 'F', 'G']);

  it('same players = 0, however shuffled', () => {
    const shuffled = mkSquad(['G', 'F', 'E', 'D', 'C', 'B', 'A']);
    expect(usedTransfers(shuffled, prev)).toBe(0);
  });

  it('counts players not in the previous locked squad', () => {
    const twoIn = mkSquad(['A', 'B', 'C', 'D', 'E', 'X', 'Y']);
    expect(usedTransfers(twoIn, prev)).toBe(2);
    const fullChurn = mkSquad(['P', 'Q', 'R', 'S', 'T', 'U', 'V']);
    expect(usedTransfers(fullChurn, prev)).toBe(7);
  });
});

describe('chip sets + voiding', () => {
  it('set 1 runs through chipSet1EndGw, set 2 after', () => {
    expect(chipSetOf(1, cfg)).toBe(1);
    expect(chipSetOf(6, cfg)).toBe(1);
    expect(chipSetOf(7, cfg)).toBe(2);
  });

  it('isUnlimitedChip: wildcard/freeHit only', () => {
    expect(isUnlimitedChip('wildcard')).toBe(true);
    expect(isUnlimitedChip('freeHit')).toBe(true);
    expect(isUnlimitedChip('benchBoost')).toBe(false);
    expect(isUnlimitedChip(null)).toBe(false);
  });

  it('priorChipsOfUid reads only this uid, weeks with a chip', () => {
    const history = {
      1: { me: { chip: 'wildcard' }, other: { chip: 'freeHit' } },
      2: { me: { captainId: 'A' } },
    };
    expect(priorChipsOfUid(history, 'me')).toEqual({ 1: 'wildcard' });
  });

  it('same chip earlier in the same set voids; the other set does not', () => {
    const prior = { 2: 'benchBoost' };
    expect(shouldVoidChip({ chip: 'benchBoost', gw: 5, priorChips: prior, cfg }))
      .toBe(true);
    expect(shouldVoidChip({ chip: 'benchBoost', gw: 7, priorChips: prior, cfg }))
      .toBe(false); // set 2 re-arms every chip
    expect(shouldVoidChip({ chip: 'wildcard', gw: 5, priorChips: prior, cfg }))
      .toBe(false); // a different chip
    expect(shouldVoidChip({
      chip: 'benchBoost', gw: 5, priorChips: { 5: 'benchBoost' }, cfg,
    })).toBe(false); // only EARLIER weeks void (this week's own History rerun)
  });

  it('priorChipsOfUid skips owner-voided weeks (the chip is refunded)', () => {
    const history = {
      1: { me: { chip: 'wildcard' } },
      2: { me: { chip: 'freeHit' } },
    };
    expect(priorChipsOfUid(history, 'me', [1])).toEqual({ 2: 'freeHit' });
    expect(priorChipsOfUid(history, 'me', [1, 2])).toEqual({});
  });
});

describe('lockAccounting', () => {
  it('prices the week: used 3 vs free 2 at -4/extra = 4 points', () => {
    const acc = lockAccounting({
      squadsByUid: { churn: mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G']) },
      statesByUid: { churn: { Free: 2, UsedThisGw: 3 } },
      historyRaw: null,
      cfg,
      gw: 2,
    });
    expect(acc.costPointsByUid).toEqual({ churn: 4 });
    expect(acc.chipPlayedByUid).toEqual({ churn: null });
    expect(acc.voided).toEqual([]);
  });

  it('wildcard/freeHit weeks are unlimited: Used stays recorded, nothing charged', () => {
    const acc = lockAccounting({
      squadsByUid: {
        wc: mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G'], 'wildcard'),
      },
      statesByUid: { wc: { Free: 2, UsedThisGw: 7 } },
      historyRaw: null,
      cfg,
      gw: 2,
    });
    expect(acc.costPointsByUid).toEqual({});
    expect(acc.chipPlayedByUid).toEqual({ wc: 'wildcard' });
  });

  it('voids a set-repeated chip: stripped from the snapshot, transfers charged for real', () => {
    const squad = mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G'], 'wildcard');
    const acc = lockAccounting({
      squadsByUid: { me: squad },
      statesByUid: { me: { Free: 2, UsedThisGw: 3 } },
      historyRaw: { 1: { me: { chip: 'wildcard' } } },
      cfg,
      gw: 3,
    });
    expect(acc.voided).toEqual([{ uid: 'me', chip: 'wildcard' }]);
    expect(acc.chipPlayedByUid).toEqual({ me: null });
    // Stripped chip only — every other squad field is the manager's verbatim.
    expect(acc.cleanSquads['me']).toEqual(
      mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G']));
    // The voided wildcard grants nothing: the 3 transfers cost 1 extra * 4.
    expect(acc.costPointsByUid).toEqual({ me: 4 });
  });

  it('a chip first played in a VOIDED week is honored again in the same set', () => {
    // Same squad/history as the void case above, but GW1 was owner-voided:
    // the wildcard was refunded, so GW3's wildcard stands (unlimited week:
    // used 3 vs free 2 charges nothing).
    const squad = mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G'], 'wildcard');
    const acc = lockAccounting({
      squadsByUid: { me: squad },
      statesByUid: { me: { Free: 2, UsedThisGw: 3 } },
      historyRaw: { 1: { me: { chip: 'wildcard' } } },
      cfg,
      gw: 3,
      voidedWeeks: [1],
    });
    expect(acc.voided).toEqual([]);
    expect(acc.chipPlayedByUid).toEqual({ me: 'wildcard' });
    expect(acc.cleanSquads['me']).toEqual(squad); // chip kept
    expect(acc.costPointsByUid).toEqual({});
  });

  it('malformed squads pass through verbatim with no accounting', () => {
    const acc = lockAccounting({
      squadsByUid: { bad: { picks: 'nope' } },
      statesByUid: { bad: { Free: 2, UsedThisGw: 9 } },
      historyRaw: null,
      cfg,
      gw: 2,
    });
    expect(acc.cleanSquads).toEqual({ bad: { picks: 'nope' } });
    expect(acc.costPointsByUid).toEqual({});
    expect(acc.chipPlayedByUid).toEqual({});
  });
});

describe('lockAccounting: the lock recounts transfers (uncounted saves)', () => {
  // Last week's locked squad A..G. Every player costs 50 now, so every
  // squad below passes the judge (the count never depends on the verdict).
  // This week's squad sold E, F, G for X, Y, Z: 3 transfers.
  const at = (priceTenths: number) =>
    ({ position: 'ATT', priceTenths, eligible: true });
  const market = integrityMarketOf({
    A: at(50), B: at(50), C: at(50), D: at(50), E: at(50), F: at(50),
    G: at(50), X: at(50), Y: at(50), Z: at(50),
  });
  const prev = mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G']);
  const inputs = (previousByUid: Record<string, unknown>): IntegrityInputs =>
    ({ market, previousByUid, previousWeekPrices: {} });
  const threeSold = ['A', 'B', 'C', 'D', 'X', 'Y', 'Z'];

  type RecountCase = {
    squad: Record<string, unknown>;
    state: Record<string, unknown>;
    previous?: unknown; // absent = no baseline for the manager
    integrity?: boolean; // default true
    historyRaw?: unknown;
    gw?: number;
  };

  function accOf(args: RecountCase): LockAccounting {
    return lockAccounting({
      squadsByUid: { u: args.squad },
      statesByUid: { u: args.state },
      historyRaw: args.historyRaw ?? null,
      cfg,
      gw: args.gw ?? 3,
      ...(args.integrity === false ? {} : {
        integrity: inputs(args.previous === undefined ? {} : { u: args.previous }),
      }),
    });
  }
  const costOf = (args: RecountCase) => accOf(args).costPointsByUid;
  const usedOf = (args: RecountCase) => accOf(args).usedByUid;

  it('3 sales locked while UsedThisGw says 0 (Free 2): 1 extra transfer charged', () => {
    expect(costOf({
      squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 0 }, previous: prev,
    })).toEqual({ u: 1 * cfg.extraTransferCost });
    // Without the integrity inputs nothing is recounted (the old gap).
    expect(costOf({
      squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 0 }, previous: prev,
      integrity: false,
    })).toEqual({});
  });

  it('wildcard / Free Hit weeks stay free', () => {
    for (const chip of ['wildcard', 'freeHit']) {
      expect(costOf({
        squad: mkSquadMap(threeSold, chip), state: { Free: 2, UsedThisGw: 0 }, previous: prev,
      }), chip).toEqual({});
    }
  });

  it('a VOIDED wildcard is no shield: the recount is charged', () => {
    // Wildcard already played in GW1 (same set) → void at GW3 → chip null.
    expect(costOf({
      squad: mkSquadMap(threeSold, 'wildcard'), state: { Free: 2, UsedThisGw: 0 },
      previous: prev, historyRaw: { 1: { u: { chip: 'wildcard' } } },
    })).toEqual({ u: 1 * cfg.extraTransferCost });
  });

  it('free-swap players sold are not counted (their own week only)', () => {
    // E and F broke the formation (holder protection): selling them is free.
    // Free 0: the 1 transfer left (G -> Z) is the only one charged.
    expect(costOf({
      squad: mkSquadMap(threeSold),
      state: { Free: 0, UsedThisGw: 0, FreeSwaps: ['E', 'F'], FreeSwapsGw: 3 },
      previous: prev,
    })).toEqual({ u: 1 * cfg.extraTransferCost });
    // Swaps granted for another week discount nothing.
    expect(costOf({
      squad: mkSquadMap(threeSold),
      state: { Free: 0, UsedThisGw: 0, FreeSwaps: ['E', 'F'], FreeSwapsGw: 2 },
      previous: prev,
    })).toEqual({ u: 3 * cfg.extraTransferCost });
  });

  it('the stored count wins when it is higher (max of the two)', () => {
    expect(costOf({
      squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 4 }, previous: prev,
    })).toEqual({ u: 2 * cfg.extraTransferCost });
  });

  it('no usable baseline keeps the stored value', () => {
    // No previous squad (a first squad): the stored count, whatever it is.
    expect(costOf({ squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 0 } }))
      .toEqual({});
    expect(costOf({ squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 3 } }))
      .toEqual({ u: 1 * cfg.extraTransferCost });
    // An Invalid-marked or malformed baseline is no baseline either.
    expect(costOf({
      squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 0 },
      previous: { ...prev, Invalid: ['overBudget'] },
    })).toEqual({});
    expect(costOf({
      squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 0 },
      previous: { picks: 'nope' },
    })).toEqual({});
  });

  // Fix round 1: the caller persists usedByUid into TransferState.UsedThisGw
  // (max) so the rollover banks from it — only where the recount WON.
  it('usedByUid: the recounted used, only where it beat the stored count', () => {
    const base = { squad: mkSquadMap(threeSold), previous: prev };
    expect(usedOf({ ...base, state: { Free: 2, UsedThisGw: 0 } })).toEqual({ u: 3 });
    // Free swaps discount the recount here too (3 sold - 2 swaps = 1).
    expect(usedOf({
      ...base, state: { Free: 2, UsedThisGw: 0, FreeSwaps: ['E', 'F'], FreeSwapsGw: 3 },
    })).toEqual({ u: 1 });
    // An unlimited week still records Used (the bank is untouched by it).
    expect(usedOf({
      ...base, squad: mkSquadMap(threeSold, 'wildcard'), state: { Free: 2, UsedThisGw: 0 },
    })).toEqual({ u: 3 });
    // Stored equal or higher: nothing to raise.
    expect(usedOf({ ...base, state: { Free: 2, UsedThisGw: 3 } })).toEqual({});
    expect(usedOf({ ...base, state: { Free: 2, UsedThisGw: 4 } })).toEqual({});
    // No baseline, or no integrity inputs: never.
    expect(usedOf({ squad: mkSquadMap(threeSold), state: { Free: 2, UsedThisGw: 0 } }))
      .toEqual({});
    expect(usedOf({ ...base, state: { Free: 2, UsedThisGw: 0 }, integrity: false }))
      .toEqual({});
  });
});

describe('annotateSquadIntegrity: the snapshot node (FPL selling, spec §4)', () => {
  // Last week's locked squad A..G (all bought at 50), carrying realized 3.
  // Since then G rose to 70 (sells for 60: +10); H costs 60.
  const at = (priceTenths: number) =>
    ({ position: 'ATT', priceTenths, eligible: true });
  const market = integrityMarketOf({
    A: at(50), B: at(50), C: at(50), D: at(50), E: at(50), F: at(50),
    G: at(70), H: at(60),
  });
  const inputs: IntegrityInputs = {
    market,
    previousByUid: {
      u: { ...mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'G']), realizedTenths: 3 },
    },
    previousWeekPrices: {},
  };

  it("a valid node carries the verdict's prices and realizedTenths, other keys kept", () => {
    // G sold for H; the client lowballs held A (10) and new H (55), and
    // writes its own realizedTenths.
    const raw: any = {
      ...mkSquadMap(['A', 'B', 'C', 'D', 'E', 'F', 'H']),
      Unrelated: 'kept', realizedTenths: 9999,
    };
    raw.picks[0].priceTenths = 10;
    raw.picks[6].priceTenths = 55;
    const out = annotateSquadIntegrity({ u: raw }, cfg, inputs);
    expect(out.valid).toEqual(['u']);
    expect(out.squads['u']).toEqual({
      ...raw,
      // Held A at the 50 paid; new H at its market floor 60.
      picks: raw.picks.map((p: any, i: number) =>
        ({ ...p, priceTenths: [50, 50, 50, 50, 50, 50, 60][i] })),
      realizedTenths: 13, // 3 + (60 - 50)
    });
    expect(raw.picks[0].priceTenths).toBe(10); // the input is never mutated
  });

  it("an invalid node keeps the client's prices and carries the baseline's realized", () => {
    // A twice (duplicatePlayer); B and G sold — no sale is credited.
    const raw: any = {
      ...mkSquadMap(['A', 'A', 'C', 'D', 'E', 'F', 'H']), realizedTenths: 9999,
    };
    raw.picks[0].priceTenths = 10;
    const out = annotateSquadIntegrity({ u: raw }, cfg, inputs);
    expect(out.invalid).toEqual([{ uid: 'u', issues: ['duplicatePlayer'] }]);
    expect(out.squads['u']).toEqual(
      { ...raw, Invalid: ['duplicatePlayer'], realizedTenths: 3 });
  });

  it('a malformed node is untouched', () => {
    const raw = { picks: 'nope', realizedTenths: 9999 };
    const out = annotateSquadIntegrity({ u: raw }, cfg, inputs);
    expect(out.squads['u']).toBe(raw);
    expect(out.valid).toEqual([]);
    expect(out.invalid).toEqual([]);
  });
});

describe('rolloverState', () => {
  const base = {
    free: 2, usedThisGw: 0, chipPlayed: null as string | null,
    savedGw: null as number | null, rolledGw: null as number | null,
  };

  it('banks unused transfers (+2/week, cap 7), resets the counter, stamps RolledGw', () => {
    expect(rolloverState(base, cfg, 3, held)).toEqual({
      free: 4, usedThisGw: 0, chipPlayed: null, savedGw: null, rolledGw: 3,
      countFrom: { gw: 4, ids: null },
    });
    expect(rolloverState({ ...base, free: 7 }, cfg, 3, held).free).toBe(7); // cap
    expect(rolloverState({ ...base, free: 2, usedThisGw: 3 }, cfg, 3, held).free)
      .toBe(2); // overspent week: remaining clamps to 0
  });

  it('a wildcard/freeHit week never consumes the bank, and ChipPlayed clears', () => {
    const s = { ...base, free: 5, usedThisGw: 9, chipPlayed: 'freeHit' };
    expect(rolloverState(s, cfg, 4, held)).toEqual({
      free: 7, usedThisGw: 0, chipPlayed: null, savedGw: null, rolledGw: 4,
      countFrom: { gw: 5, ids: null },
    });
  });

  it('a save already made for a LATER gameweek survives a delayed finalize', () => {
    const s = { ...base, usedThisGw: 2, savedGw: 4 };
    expect(rolloverState(s, cfg, 3, held).usedThisGw).toBe(2);
    expect(rolloverState({ ...base, usedThisGw: 2, savedGw: 3 }, cfg, 3, held)
      .usedThisGw).toBe(0);
  });

  it('publishes the baseline for NEXT week: countFrom.gw = gw + 1 with the given ids', () => {
    const ids = ['A', 'B', 'C'];
    expect(rolloverState(base, cfg, 2, { ...held, countFromIds: ids }).countFrom)
      .toEqual({ gw: 3, ids });
    expect(rolloverState(base, cfg, 7, held).countFrom).toEqual({ gw: 8, ids: null });
  });

  it("a manager's first week never banks: next week is the weekly grant", () => {
    const first = { ...held, firstWeek: true };
    expect(rolloverState(base, cfg, 1, first).free).toBe(2); // not 2 + 2
    expect(rolloverState({ ...base, free: 7 }, cfg, 1, first).free).toBe(2);
    expect(rolloverState({ ...base, chipPlayed: 'wildcard' }, cfg, 1, first).free)
      .toBe(2);
  });

  it('a manager not scored this week rolls as if nothing was used', () => {
    // 3 transfers counted earlier in the open week, then the squad was
    // deleted before the lock: nothing was charged, so nothing is spent.
    const s = { ...base, free: 2, usedThisGw: 3 };
    expect(rolloverState(s, cfg, 2, { ...held, scored: false }).free).toBe(4);
    expect(rolloverState(s, cfg, 2, held).free).toBe(2); // scored: overspent
    // The counter still resets (only a later week's save survives).
    expect(rolloverState(s, cfg, 2, { ...held, scored: false }).usedThisGw).toBe(0);
  });
});
