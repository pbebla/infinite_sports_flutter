import { describe, expect, it } from 'vitest';
import { campaignClaim } from './campaigns';

describe('campaignClaim', () => {
  it('claims a pending campaign', () => {
    expect(campaignClaim('pending')).toBe('sending');
  });

  it('never aborts on null: the first RTDB run sees an empty cache', () => {
    expect(campaignClaim(null)).toBeNull();
    expect(campaignClaim(undefined)).toBeNull();
  });

  it('aborts on any other status (already claimed / sent / cancelled)', () => {
    for (const s of ['sending', 'sent', 'cancelled', 'failed', 7, {}]) {
      expect(campaignClaim(s)).toBeUndefined();
    }
  });
});
