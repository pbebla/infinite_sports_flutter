import { describe, expect, it } from 'vitest';
import {
  centsToDollars, legacyTarget, owedCents, parseWebhookMetadata, RegistrationConfigLike,
  SubmissionLike, TeamLike, webhookMetadata,
} from './stripe_pay';

function config(overrides: Partial<RegistrationConfigLike> = {}): RegistrationConfigLike {
  return {
    targetType: 'league',
    sport: 'Futsal',
    season: '17',
    tournamentId: '',
    tournamentName: '',
    fee: 20,
    teamFee: 300,
    paymentMode: 'perPlayer',
    ...overrides,
  };
}

function submission(overrides: Partial<SubmissionLike> = {}): SubmissionLike {
  return { path: 'individual', paid: false, ...overrides };
}

describe('owedCents', () => {
  it('individual owes the per-player fee in cents under perPlayer/both', () => {
    expect(owedCents(config({ paymentMode: 'perPlayer' }), submission())).toBe(2000);
    expect(owedCents(config({ paymentMode: 'both' }), submission())).toBe(2000);
  });

  it('individual owes 0 under teamFee mode', () => {
    expect(owedCents(config({ paymentMode: 'teamFee' }), submission())).toBe(0);
  });

  it('captain owes the flat team fee in cents under teamFee/both', () => {
    expect(owedCents(config({ paymentMode: 'teamFee' }), submission({ path: 'captain' }))).toBe(30000);
    expect(owedCents(config({ paymentMode: 'both' }), submission({ path: 'captain' }))).toBe(30000);
  });

  it('captain owes 0 under perPlayer mode', () => {
    expect(owedCents(config({ paymentMode: 'perPlayer' }), submission({ path: 'captain' }))).toBe(0);
  });

  it('joiner owes the per-player fee unless the team code waives it', () => {
    const team: TeamLike = { codeWaivesPayment: false };
    const waived: TeamLike = { codeWaivesPayment: true };
    expect(owedCents(config(), submission({ path: 'joiner' }), team)).toBe(2000);
    expect(owedCents(config(), submission({ path: 'joiner' }), waived)).toBe(0);
  });

  it('joiner with no team info owes the per-player fee (defensive default)', () => {
    expect(owedCents(config(), submission({ path: 'joiner' }))).toBe(2000);
  });

  it('anything already paid owes 0', () => {
    expect(owedCents(config(), submission({ paid: true }))).toBe(0);
    expect(owedCents(config({ paymentMode: 'teamFee' }), submission({ path: 'captain', paid: true }))).toBe(0);
  });

  it('a free registration (fee 0) owes 0', () => {
    expect(owedCents(config({ fee: 0, paymentMode: 'perPlayer' }), submission())).toBe(0);
  });

  it('rounds fractional dollar fees to the nearest cent', () => {
    expect(owedCents(config({ fee: 19.99, paymentMode: 'perPlayer' }), submission())).toBe(1999);
    expect(owedCents(config({ fee: 12.345, paymentMode: 'perPlayer' }), submission())).toBe(1235);
  });
});

describe('centsToDollars', () => {
  it('converts integer cents back to dollars', () => {
    expect(centsToDollars(2000)).toBe(20);
    expect(centsToDollars(30000)).toBe(300);
  });

  it('round-trips toCents-rounded fractional fees', () => {
    expect(centsToDollars(1999)).toBeCloseTo(19.99);
    expect(centsToDollars(1235)).toBeCloseTo(12.35);
  });
});

describe('legacyTarget', () => {
  it('leagues target Sport/Season', () => {
    expect(legacyTarget(config())).toEqual({ league: 'Futsal', season: '17' });
  });

  it('tournaments target TournamentName/TournamentId, falling back to the id', () => {
    expect(legacyTarget(config({
      targetType: 'tournament', tournamentId: 't1', tournamentName: 'Summer Cup',
    }))).toEqual({ league: 'Summer Cup', season: 't1' });
    expect(legacyTarget(config({
      targetType: 'tournament', tournamentId: 't1', tournamentName: '',
    }))).toEqual({ league: 't1', season: 't1' });
  });
});

describe('webhookMetadata / parseWebhookMetadata', () => {
  it('round-trips regId/uid/league/season through Stripe metadata strings', () => {
    const meta = webhookMetadata({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal', season: '17' });
    expect(meta).toEqual({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal', season: '17' });
    const parsed = parseWebhookMetadata(meta);
    expect(parsed).toEqual({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal', season: '17' });
  });

  it('parseWebhookMetadata returns null when a required field is missing', () => {
    expect(parseWebhookMetadata({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal' })).toBeNull();
    expect(parseWebhookMetadata(null)).toBeNull();
    expect(parseWebhookMetadata(undefined)).toBeNull();
  });

  it('parseWebhookMetadata rejects non-string values defensively', () => {
    expect(parseWebhookMetadata({ regId: 'x', uid: 1, league: 'Futsal', season: '17' })).toBeNull();
  });
});
