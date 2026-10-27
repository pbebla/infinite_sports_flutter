import { describe, expect, it } from 'vitest';
import {
  PUBLIC_PROFILE_KEYS, publicProfileProjection, registrationConfigProjection,
  teamMemberEntry,
} from './public_mirrors';

// Every private Users/{uid} field the sweep found — the projection tests
// prove each one NEVER appears in a mirror, whatever else the node carries.
const PII_KEYS = [
  'DOB',
  'Phone Number',
  'Token',
  'Zip',
  'City',
  'Gender',
  'ReferralSource',
  'FavoriteSports',
  'Date Joined',
  'Email',
] as const;

/** A realistic full Users/{uid} node: every whitelisted key AND every PII
 *  key populated, exactly as a long-lived account looks in RTDB. */
function fullUserNode(): Record<string, unknown> {
  return {
    'First Name': 'Zaya',
    'Last Name': 'Arami',
    ProfileUrl: 'https://example.com/p.jpg',
    Played: 42,
    TournamentsPlayed: 7,
    Awards: { 'Golden Boot': 2 },
    Information: { Age: 28, Height: `5'10"`, FutsalPositions: 'Pivot;Winger' },
    ProfileCompleted: true,
    // --- private fields that must never leak ---
    DOB: '01011998',
    'Phone Number': '4085551234',
    Token: 'fcm-token-abc123',
    Zip: '95112',
    City: 'San Jose',
    Gender: 'M',
    ReferralSource: 'friend',
    FavoriteSports: 'Futsal;Basketball',
    'Date Joined': '05202020',
    Email: 'zaya@example.com',
  };
}

describe('publicProfileProjection', () => {
  it('copies every whitelisted key of a full node verbatim', () => {
    const out = publicProfileProjection(fullUserNode())!;
    expect(out).not.toBeNull();
    expect(out['First Name']).toBe('Zaya');
    expect(out['Last Name']).toBe('Arami');
    expect(out['ProfileUrl']).toBe('https://example.com/p.jpg');
    expect(out['Played']).toBe(42);
    expect(out['TournamentsPlayed']).toBe(7);
    expect(out['Awards']).toEqual({ 'Golden Boot': 2 });
    expect(out['Information']).toEqual(
      { Age: 28, Height: `5'10"`, FutsalPositions: 'Pivot;Winger' });
    expect(out['ProfileCompleted']).toBe(true);
  });

  it('NEVER outputs any PII key, even when every one is present', () => {
    const out = publicProfileProjection(fullUserNode())!;
    for (const key of PII_KEYS) {
      expect(out, `PII key "${key}" leaked into the mirror`)
        .not.toHaveProperty([key]);
    }
  });

  it('outputs ONLY whitelisted keys — the output key set is a subset of the whitelist', () => {
    const out = publicProfileProjection(fullUserNode())!;
    for (const key of Object.keys(out)) {
      expect(PUBLIC_PROFILE_KEYS).toContain(key);
    }
  });

  it('never leaks PII through serialized output either', () => {
    const json = JSON.stringify(publicProfileProjection(fullUserNode()));
    expect(json).not.toContain('01011998'); // DOB
    expect(json).not.toContain('4085551234'); // phone
    expect(json).not.toContain('fcm-token-abc123'); // FCM token
    expect(json).not.toContain('95112'); // zip
    expect(json).not.toContain('zaya@example.com'); // email
  });

  it('a minimal node projects just the keys it has, nothing else', () => {
    const out = publicProfileProjection({ 'First Name': 'Pat' });
    expect(out).toEqual({ 'First Name': 'Pat' });
  });

  it('omits absent whitelisted keys instead of writing undefined/null', () => {
    const out = publicProfileProjection(
      { 'First Name': 'Pat', Played: 3, DOB: '02022000' })!;
    expect(Object.keys(out).sort()).toEqual(['First Name', 'Played']);
  });

  it('drops a whitelisted key whose value is null (defensive)', () => {
    const out = publicProfileProjection(
      { 'First Name': 'Pat', ProfileUrl: null });
    expect(out).toEqual({ 'First Name': 'Pat' });
  });

  it('returns null for null/undefined (mirror should be deleted)', () => {
    expect(publicProfileProjection(null)).toBeNull();
    expect(publicProfileProjection(undefined)).toBeNull();
  });

  it('returns null for scalar junk without crashing', () => {
    expect(publicProfileProjection('hello')).toBeNull();
    expect(publicProfileProjection(7)).toBeNull();
    expect(publicProfileProjection(true)).toBeNull();
  });

  it('returns null for an RTDB array-coerced node without crashing', () => {
    expect(publicProfileProjection(['a', 'b', 'c'])).toBeNull();
    expect(publicProfileProjection([{ 'First Name': 'Pat' }])).toBeNull();
    expect(publicProfileProjection([])).toBeNull();
  });

  it('returns null for an empty map', () => {
    expect(publicProfileProjection({})).toBeNull();
  });

  it('returns null for a node carrying ONLY private fields (nothing public to mirror)', () => {
    const out = publicProfileProjection({
      DOB: '01011998',
      'Phone Number': '4085551234',
      Token: 'tok',
      Email: 'x@y.z',
    });
    expect(out).toBeNull();
  });

  it('keeps an array-coerced value INSIDE a whitelisted key (value copied verbatim)', () => {
    // Awards with integer keys can coerce to a list; the projection must
    // copy it as-is, not crash or mangle it.
    const out = publicProfileProjection(
      { 'First Name': 'Pat', Awards: ['MVP', 'Golden Boot'] })!;
    expect(out['Awards']).toEqual(['MVP', 'Golden Boot']);
  });
});

describe('registrationConfigProjection', () => {
  const config = {
    Status: 'open',
    Sport: 'Futsal',
    Season: '16',
    Fee: 150,
    TeamFee: 900,
    PaymentMode: 'both',
    Methods: { venmo: true, zelle: true, stripe: true },
    TargetType: 'league',
  };

  it('returns the Config node verbatim when it is a map', () => {
    expect(registrationConfigProjection(config)).toEqual(config);
  });

  it('returns a copy, not the same reference', () => {
    const out = registrationConfigProjection(config)!;
    expect(out).not.toBe(config);
    out['Status'] = 'closed';
    expect(config.Status).toBe('open');
  });

  it('returns null for null/undefined/scalars', () => {
    expect(registrationConfigProjection(null)).toBeNull();
    expect(registrationConfigProjection(undefined)).toBeNull();
    expect(registrationConfigProjection('open')).toBeNull();
    expect(registrationConfigProjection(5)).toBeNull();
  });

  it('returns null for an RTDB array-coerced node without crashing', () => {
    expect(registrationConfigProjection([config])).toBeNull();
    expect(registrationConfigProjection([])).toBeNull();
  });

  it('returns null for an empty map (nothing to mirror)', () => {
    expect(registrationConfigProjection({})).toBeNull();
  });
});

describe('teamMemberEntry', () => {
  const joiner = {
    Path: 'joiner',
    TeamId: '-NxTeam123',
    DisplayName: 'Sam Lee',
    Paid: true,
    Answers: { email: 'sam@example.com', phone: '408-555-9999', dob: '03031999' },
    SubmittedAt: 1730000000000,
  };

  it('projects a joiner submission to {teamId, {DisplayName, Paid}}', () => {
    expect(teamMemberEntry(joiner)).toEqual({
      teamId: '-NxTeam123',
      value: { DisplayName: 'Sam Lee', Paid: true },
    });
  });

  it('projects a captain submission too (it carries a TeamId)', () => {
    const entry = teamMemberEntry(
      { ...joiner, Path: 'captain', Paid: false });
    expect(entry).toEqual({
      teamId: '-NxTeam123',
      value: { DisplayName: 'Sam Lee', Paid: false },
    });
  });

  it('the value carries EXACTLY DisplayName and Paid — Answers never leak', () => {
    const entry = teamMemberEntry(joiner)!;
    expect(Object.keys(entry.value).sort()).toEqual(['DisplayName', 'Paid']);
    const json = JSON.stringify(entry);
    expect(json).not.toContain('sam@example.com');
    expect(json).not.toContain('408-555-9999');
    expect(json).not.toContain('03031999');
  });

  it('DisplayName falls back to empty string when missing or non-string', () => {
    expect(teamMemberEntry({ TeamId: 't1', Paid: true })!.value.DisplayName)
      .toBe('');
    expect(teamMemberEntry({ TeamId: 't1', DisplayName: 42 })!.value.DisplayName)
      .toBe('');
  });

  it('Paid is true only for a literal true', () => {
    expect(teamMemberEntry({ TeamId: 't1' })!.value.Paid).toBe(false);
    expect(teamMemberEntry({ TeamId: 't1', Paid: 'yes' })!.value.Paid).toBe(false);
    expect(teamMemberEntry({ TeamId: 't1', Paid: 1 })!.value.Paid).toBe(false);
    expect(teamMemberEntry({ TeamId: 't1', Paid: true })!.value.Paid).toBe(true);
  });

  it('returns null for an individual submission (no TeamId)', () => {
    expect(teamMemberEntry({
      Path: 'individual', DisplayName: 'Pat', Paid: false, Answers: {},
    })).toBeNull();
  });

  it('returns null for an empty or non-string TeamId', () => {
    expect(teamMemberEntry({ TeamId: '', DisplayName: 'Pat' })).toBeNull();
    expect(teamMemberEntry({ TeamId: 42, DisplayName: 'Pat' })).toBeNull();
    expect(teamMemberEntry({ TeamId: null, DisplayName: 'Pat' })).toBeNull();
  });

  it('returns null for null/undefined (deleted submission)', () => {
    expect(teamMemberEntry(null)).toBeNull();
    expect(teamMemberEntry(undefined)).toBeNull();
  });

  it('returns null for scalar junk and RTDB array coercion without crashing', () => {
    expect(teamMemberEntry('junk')).toBeNull();
    expect(teamMemberEntry(9)).toBeNull();
    expect(teamMemberEntry([joiner])).toBeNull();
    expect(teamMemberEntry([])).toBeNull();
  });
});
