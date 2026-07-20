import { describe, expect, it } from 'vitest';
import {
  audienceTopic, chunk, isDue, parseCampaign,
} from '../src/lib/campaigns';

describe('parseCampaign', () => {
  it('parses an everyone campaign', () => {
    const c = parseCampaign({
      Title: 'Season starts!', Body: 'See you Sunday',
      Audience: { Type: 'all' }, SendAt: 0, Status: 'pending',
    });
    expect(c).not.toBeNull();
    expect(c!.audience.type).toBe('all');
    expect(c!.data.type).toBe('campaign');
  });

  it('requires sport for sport audience and event for event audience', () => {
    expect(parseCampaign({
      Title: 'x', Audience: { Type: 'sport' },
    })).toBeNull();
    expect(parseCampaign({
      Title: 'x', Audience: { Type: 'sport', Sport: 'Futsal' },
    })!.audience.sport).toBe('Futsal');
    expect(parseCampaign({
      Title: 'x', Audience: { Type: 'event' },
    })).toBeNull();
  });

  it('reads uids from a map or an array and rejects empty lists', () => {
    const fromMap = parseCampaign({
      Title: 'x', Audience: { Type: 'users', Uids: { a: true, b: true } },
    });
    expect(fromMap!.audience.uids!.sort()).toEqual(['a', 'b']);
    const fromArray = parseCampaign({
      Title: 'x', Audience: { Type: 'users', Uids: ['u1', 'u2'] },
    });
    expect(fromArray!.audience.uids).toEqual(['u1', 'u2']);
    expect(parseCampaign({
      Title: 'x', Audience: { Type: 'users', Uids: {} },
    })).toBeNull();
  });

  it('carries Data through for tap routing', () => {
    const c = parseCampaign({
      Title: 'x', Audience: { Type: 'all' },
      Data: { type: 'campaign', eventId: 'abc' },
    });
    expect(c!.data.eventId).toBe('abc');
  });

  it('rejects garbage', () => {
    expect(parseCampaign(null)).toBeNull();
    expect(parseCampaign('nope')).toBeNull();
    expect(parseCampaign({ Audience: { Type: 'all' } })).toBeNull(); // no title
    expect(parseCampaign({ Title: 'x', Audience: { Type: 'mystery' } })).toBeNull();
  });
});

describe('audienceTopic', () => {
  it('maps broadcast audiences to fan-app topic names', () => {
    expect(audienceTopic({ type: 'all' })).toBe('all_users');
    expect(audienceTopic({ type: 'sport', sport: 'Flag Football' }))
      .toBe('sport_Flag_Football');
    expect(audienceTopic({ type: 'event', eventId: '-OxUP A3v' }))
      .toBe('event_-OxUP_A3v');
  });

  it('hand-picked users have no topic (token sends)', () => {
    expect(audienceTopic({ type: 'users', uids: ['a'] })).toBeNull();
  });
});

describe('isDue', () => {
  const base = {
    title: 'x', body: '', data: {}, audience: { type: 'all' as const },
  };
  it('send-now is due immediately, future schedules are not', () => {
    expect(isDue({ ...base, sendAtMs: 0, status: 'pending' }, 1000)).toBe(true);
    expect(isDue({ ...base, sendAtMs: 2000, status: 'pending' }, 1000)).toBe(false);
    expect(isDue({ ...base, sendAtMs: 2000, status: 'pending' }, 2000)).toBe(true);
  });
  it('only pending campaigns are due', () => {
    expect(isDue({ ...base, sendAtMs: 0, status: 'sent' }, 1000)).toBe(false);
    expect(isDue({ ...base, sendAtMs: 0, status: 'sending' }, 1000)).toBe(false);
  });
});

describe('chunk', () => {
  it('splits into batches of at most the given size', () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunk([], 500)).toEqual([]);
  });
});
