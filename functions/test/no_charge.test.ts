// "No charge" auto-stamp (plan 2026-11-14-no-charge-payment-option, Task 6):
// a sign-up that owes nothing starts out Paid / 'no charge' / 0, and a legacy
// NotPaid entry that lands next to a Paid one is cleaned up after a settle
// delay. Driven over an in-memory tree; all names and ids are made up.

import { describe, expect, it, vi } from 'vitest';
import { buildNoChargeUpdate, shouldStampNoCharge } from '../src/lib/no_charge';
import { handleLegacyNotPaidCreated, handleSubmissionCreated } from '../src/no_charge_watch';
import type { RegistrationConfigLike } from '../src/lib/stripe_pay';

const logged = vi.hoisted(() => [] as unknown[]);
vi.mock('firebase-functions/logger', () => ({
  info: (...a: unknown[]) => logged.push(a),
  error: (...a: unknown[]) => logged.push(a),
  warn: (...a: unknown[]) => logged.push(a),
}));

const cfg = (over: Partial<RegistrationConfigLike> = {}): RegistrationConfigLike => ({
  targetType: 'league', sport: 'Futsal', season: '99', tournamentId: '', tournamentName: '',
  fee: 0, teamFee: 0, paymentMode: 'perPlayer', ...over,
});
const sub = (path: string, paid = false) => ({ path, paid });

describe('shouldStampNoCharge', () => {
  it('fee 0 individual -> true', () => {
    expect(shouldStampNoCharge(cfg(), sub('individual'))).toBe(true);
  });
  it("paymentMode 'teamFee' individual -> true", () => {
    expect(shouldStampNoCharge(cfg({ fee: 255, teamFee: 900, paymentMode: 'teamFee' }), sub('individual'))).toBe(true);
  });
  it("captain under 'perPlayer' -> true", () => {
    expect(shouldStampNoCharge(cfg({ fee: 255, teamFee: 900, paymentMode: 'perPlayer' }), sub('captain'))).toBe(true);
  });
  it('fee 255 individual -> false', () => {
    expect(shouldStampNoCharge(cfg({ fee: 255 }), sub('individual'))).toBe(false);
  });
  it('already paid -> false', () => {
    expect(shouldStampNoCharge(cfg(), sub('individual', true))).toBe(false);
  });
  it('joiner on a waiving team -> false', () => {
    expect(shouldStampNoCharge(cfg({ fee: 255 }), sub('joiner'), { codeWaivesPayment: true })).toBe(false);
    expect(shouldStampNoCharge(cfg(), sub('joiner'), { codeWaivesPayment: true })).toBe(false);
  });
  it('joiner with no team -> false (owedCents fails closed)', () => {
    expect(shouldStampNoCharge(cfg({ fee: 255 }), sub('joiner'))).toBe(false);
  });
});

describe('buildNoChargeUpdate', () => {
  it('is one root multi-path update with the exact stored values', () => {
    expect(buildNoChargeUpdate('reg1', 'uidA', { league: 'Futsal', season: '99' }, 'Ann Able')).toEqual({
      'Registrations/reg1/Submissions/uidA/Paid': true,
      'Registrations/reg1/Submissions/uidA/PaidVia': 'no charge',
      'Registrations/reg1/Submissions/uidA/PaidAmount': 0,
      'Sign Ups/Futsal/99/NotPaid/uidA': null,
      'Sign Ups/Futsal/99/Paid/uidA': 'Ann Able',
    });
  });
  it('falls back to the uid when the name is empty', () => {
    const u = buildNoChargeUpdate('reg1', 'uidA', { league: 'Futsal', season: '99' }, '  ');
    expect(u['Sign Ups/Futsal/99/Paid/uidA']).toBe('uidA');
  });
});

type Tree = Record<string, any>;
function fakeRef(tree: Tree, path: string, log: any[] = []): any {
  const parts = path.split('/').filter((p) => p.length > 0);
  const read = (): unknown => {
    let node: any = tree;
    for (const p of parts) {
      if (node === null || node === undefined || typeof node !== 'object') return null;
      node = node[p];
    }
    return node === undefined ? null : node;
  };
  const write = (value: unknown): void => {
    let node: any = tree;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') node[p] = {};
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) delete node[last]; else node[last] = value;
  };
  return {
    child: (name: string) => fakeRef(tree, `${path}/${name}`, log),
    get: async () => ({ val: () => read() }),
    update: async (v: Record<string, unknown>) => {
      log.push({ op: 'update', path, keys: Object.keys(v) });
      for (const [k, val] of Object.entries(v)) fakeRef(tree, `${path}/${k}`).set(val);
    },
    remove: async () => { log.push({ op: 'remove', path }); write(null); },
    set: (v: unknown) => write(v),
  };
}

const baseTree = (): Tree => ({
  Registrations: { reg1: {
    Config: { Sport: 'Futsal', Season: '99', Fee: 0, PaymentMode: 'perPlayer', Methods: { venmo: true } },
    Submissions: { uidA: { Path: 'individual', DisplayName: 'Ann Able', Paid: false } },
  } },
  'Sign Ups': { Futsal: { '99': { NotPaid: { uidA: 'Ann Able' } } } },
});

describe('handleSubmissionCreated', () => {
  it('stamps a free sign-up in ONE root update and moves the legacy entry', async () => {
    const tree = baseTree(); const writes: any[] = [];
    expect(await handleSubmissionCreated(fakeRef(tree, '', writes), 'reg1', 'uidA')).toBe('stamped');
    expect(writes.filter((w) => w.op === 'update')).toHaveLength(1);
    expect(writes).toHaveLength(1);
    expect(writes[0].path).toBe('');
    const s = tree.Registrations.reg1.Submissions.uidA;
    expect([s.Paid, s.PaidVia, s.PaidAmount]).toEqual([true, 'no charge', 0]);
    expect(tree['Sign Ups'].Futsal['99'].NotPaid?.uidA).toBeUndefined();
    expect(tree['Sign Ups'].Futsal['99'].Paid.uidA).toBe('Ann Able');
  });
  it('does not need Stripe to be enabled to stamp', async () => {
    const tree = baseTree();
    expect(tree.Registrations.reg1.Config.Methods.stripe).toBeUndefined();
    expect(await handleSubmissionCreated(fakeRef(tree, ''), 'reg1', 'uidA')).toBe('stamped');
  });
  it('never touches a submission that is already Paid', async () => {
    const tree = baseTree(); const writes: any[] = [];
    Object.assign(tree.Registrations.reg1.Submissions.uidA, { Paid: true, PaidVia: 'card', PaidAmount: 255 });
    expect(await handleSubmissionCreated(fakeRef(tree, '', writes), 'reg1', 'uidA')).toBe('skipped');
    expect(writes).toEqual([]);
    expect(tree.Registrations.reg1.Submissions.uidA.PaidVia).toBe('card');
  });
  it('skips a sign-up that owes money', async () => {
    const tree = baseTree(); const writes: any[] = [];
    tree.Registrations.reg1.Config.Fee = 255;
    expect(await handleSubmissionCreated(fakeRef(tree, '', writes), 'reg1', 'uidA')).toBe('skipped');
    expect(writes).toEqual([]);
  });
  it('skips a joiner (waiving team: left as is; normal team: owes the fee)', async () => {
    const mk = (waives: boolean) => {
      const t = baseTree();
      t.Registrations.reg1.Config.Fee = 255;
      t.Registrations.reg1.Submissions.uidA = { Path: 'joiner', TeamId: 't1', DisplayName: 'Ann Able' };
      t.Registrations.reg1.Teams = { t1: { CodeWaivesPayment: waives } };
      return t;
    };
    const writes: any[] = [];
    expect(await handleSubmissionCreated(fakeRef(mk(true), '', writes), 'reg1', 'uidA')).toBe('skipped');
    expect(await handleSubmissionCreated(fakeRef(mk(false), '', writes), 'reg1', 'uidA')).toBe('skipped');
    expect(writes).toEqual([]);
  });
  it('skips when the config or submission is missing', async () => {
    expect(await handleSubmissionCreated(fakeRef({}, ''), 'reg1', 'uidA')).toBe('skipped');
  });
  it('logs no full uid or name', async () => {
    logged.length = 0;
    await handleSubmissionCreated(fakeRef(baseTree(), ''), 'reg1', 'uidAVeryLongUid1234567890');
    const text = JSON.stringify(logged);
    expect(text).not.toContain('uidAVeryLongUid1234567890');
    expect(text).not.toContain('Ann Able');
  });
});

describe('handleLegacyNotPaidCreated', () => {
  const both = (): Tree => ({ 'Sign Ups': { Futsal: { '99': { Paid: { uidA: 'Ann' }, NotPaid: { uidA: 'Ann' } } } } });
  const noWait = async () => {};

  it('removes NotPaid when Paid still exists after the delay', async () => {
    const tree = both(); let waited = 0;
    expect(await handleLegacyNotPaidCreated(fakeRef(tree, ''), 'Futsal', '99', 'uidA', async () => { waited++; }))
      .toBe('removed');
    expect(waited).toBe(1);
    expect(tree['Sign Ups'].Futsal['99'].NotPaid?.uidA).toBeUndefined();
    expect(tree['Sign Ups'].Futsal['99'].Paid.uidA).toBe('Ann');
  });
  it('leaves NotPaid alone when there is no Paid entry', async () => {
    const tree = both(); delete tree['Sign Ups'].Futsal['99'].Paid;
    expect(await handleLegacyNotPaidCreated(fakeRef(tree, ''), 'Futsal', '99', 'uidA', noWait)).toBe('kept');
    expect(tree['Sign Ups'].Futsal['99'].NotPaid.uidA).toBe('Ann');
  });
  it('leaves NotPaid alone when Paid is removed during the delay (old Manager second write)', async () => {
    const tree = both();
    const wait = async () => { delete tree['Sign Ups'].Futsal['99'].Paid.uidA; };
    expect(await handleLegacyNotPaidCreated(fakeRef(tree, ''), 'Futsal', '99', 'uidA', wait)).toBe('kept');
    expect(tree['Sign Ups'].Futsal['99'].NotPaid.uidA).toBe('Ann');
  });
  it('writes nothing when NotPaid is removed during the delay', async () => {
    const tree = both(); const writes: any[] = [];
    const wait = async () => { delete tree['Sign Ups'].Futsal['99'].NotPaid.uidA; };
    expect(await handleLegacyNotPaidCreated(fakeRef(tree, '', writes), 'Futsal', '99', 'uidA', wait)).toBe('gone');
    expect(writes).toEqual([]);
    expect(tree['Sign Ups'].Futsal['99'].Paid.uidA).toBe('Ann');
  });
});
