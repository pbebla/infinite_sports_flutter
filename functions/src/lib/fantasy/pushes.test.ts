// Phase F pure push logic: reminder config parsing (the owner-editable
// shape), the deadline formatter, the unchanged-squad audience rule and the
// spec-verbatim recap line.

import { describe, expect, it } from 'vitest';
import {
  DEFAULT_REMINDER_TEMPLATE, fantasyPushData, fillReminderTemplate,
  formatDeadline, recapBody, reminderAudience, reminderConfigFrom,
  reminderInstantMs,
} from './pushes';

describe('reminderConfigFrom', () => {
  it('defaults: enabled, 3 hours before (Sunday noon for a 3 PM lock), stock template', () => {
    expect(reminderConfigFrom(null)).toEqual({
      enabled: true, hoursBefore: 3, template: DEFAULT_REMINDER_TEMPLATE,
    });
    expect(reminderConfigFrom({})).toEqual({
      enabled: true, hoursBefore: 3, template: DEFAULT_REMINDER_TEMPLATE,
    });
  });

  it('owner-editable fields: Enabled, HoursBefore, Template', () => {
    expect(reminderConfigFrom({
      Enabled: false, HoursBefore: 27, Template: 'T-minus {deadline}!',
    })).toEqual({
      enabled: false, hoursBefore: 27, template: 'T-minus {deadline}!',
    });
    // Garbage values fall back per field.
    expect(reminderConfigFrom({ HoursBefore: -5, Template: '   ' })).toEqual({
      enabled: true, hoursBefore: 3, template: DEFAULT_REMINDER_TEMPLATE,
    });
  });

  it('reminderInstantMs = lock minus HoursBefore', () => {
    const lock = Date.UTC(2026, 5, 28, 22);
    expect(reminderInstantMs(lock, reminderConfigFrom(null)))
      .toBe(lock - 3 * 3_600_000);
  });
});

describe('formatDeadline', () => {
  it('spec §5 shape: "Sun, Jun 28 · 3:00 PM"', () => {
    expect(formatDeadline('06282026', 15)).toBe('Sun, Jun 28 · 3:00 PM');
  });

  it('12-hour edges', () => {
    expect(formatDeadline('06282026', 0)).toBe('Sun, Jun 28 · 12:00 AM');
    expect(formatDeadline('06282026', 12)).toBe('Sun, Jun 28 · 12:00 PM');
    expect(formatDeadline('12012026', 9)).toBe('Tue, Dec 1 · 9:00 AM');
  });
});

describe('fillReminderTemplate', () => {
  it('replaces every {deadline}', () => {
    expect(fillReminderTemplate('By {deadline}. Really: {deadline}.', 'X'))
      .toBe('By X. Really: X.');
    expect(fillReminderTemplate(DEFAULT_REMINDER_TEMPLATE, 'Sun, Jun 28 · 3:00 PM'))
      .toBe('Your fantasy squad is untouched this week — deadline ' +
        'Sun, Jun 28 · 3:00 PM.');
  });
});

describe('reminderAudience (the measurable unchanged-squad rule)', () => {
  const managersRaw = { a: { TeamName: 'A' }, b: { TeamName: 'B' } };
  const squadsRaw = { b: { picks: [] }, c: { picks: [] } };

  it('signed-up = Managers ∪ Squads keys; excluded only by SavedGw == gw', () => {
    const uids = reminderAudience({
      managersRaw,
      squadsRaw,
      transferStateRaw: {
        b: { Free: 2, UsedThisGw: 1, SavedGw: 2 }, // saved this week: skip
        c: { Free: 2, UsedThisGw: 0, SavedGw: 1 }, // stale save: remind
      },
      gw: 2,
    });
    expect(uids).toEqual(['a', 'c']);
  });

  it('no TransferState at all = everyone is unchanged', () => {
    expect(reminderAudience({
      managersRaw, squadsRaw, transferStateRaw: null, gw: 2,
    })).toEqual(['a', 'b', 'c']);
  });
});

describe('recapBody + push payload', () => {
  it('spec §12 verbatim', () => {
    expect(recapBody({ gw: 3, points: 41, rank: 4, topScore: 52 }))
      .toBe('GW3: you scored 41, moved to #4, top score 52.');
  });

  it('every fantasy push routes with type fantasy', () => {
    expect(fantasyPushData('Futsal', '15', 2)).toEqual({
      type: 'fantasy', sport: 'Futsal', season: '15', gw: '2',
    });
  });
});
