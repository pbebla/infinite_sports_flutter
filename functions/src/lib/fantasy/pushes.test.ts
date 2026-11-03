// Phase F pure push logic: reminder config parsing (the owner-editable
// shape), the deadline formatter, the unchanged-squad audience rule and the
// spec-verbatim recap line.

import { describe, expect, it } from 'vitest';
import {
  adminUidsOf, DEFAULT_REMINDER_TEMPLATE, fantasyPushData,
  fillReminderTemplate, formatDeadline, formatMoneyTenths, NEWS_READY_TITLE,
  newsReadyBody, OVER_BUDGET_PREVIEW_TITLE, overBudgetPreviewBody, recapBody,
  reminderAudience, reminderConfigFrom, reminderInstantMs,
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

describe('over-budget preview push (FPL selling, spec §4)', () => {
  it('formatMoneyTenths is the app\'s "$1.0M" (fantasy_format.dart twin)', () => {
    expect(formatMoneyTenths(10)).toBe('$1.0M');
    expect(formatMoneyTenths(5)).toBe('$0.5M');
    expect(formatMoneyTenths(125)).toBe('$12.5M');
    expect(formatMoneyTenths(0)).toBe('$0.0M');
    expect(formatMoneyTenths(-5)).toBe('$-0.5M');
  });

  it('the exact copy: title + body with the amount and the deadline', () => {
    expect(OVER_BUDGET_PREVIEW_TITLE).toBe('Your fantasy team is over budget');
    expect(overBudgetPreviewBody(10, formatDeadline('06282026', 15))).toBe(
      "This week's price changes put your team $1.0M over. Fix it before " +
      "Sun, Jun 28 · 3:00 PM or this week won't count.");
    expect(overBudgetPreviewBody(5, 'Sun, Oct 19 · 3:00 PM')).toBe(
      "This week's price changes put your team $0.5M over. Fix it before " +
      "Sun, Oct 19 · 3:00 PM or this week won't count.");
  });
});

describe('news autopilot admin heads-up', () => {
  it('autopilot on: N posts publish <when> (spec §4.4 copy)', () => {
    expect(NEWS_READY_TITLE).toBe('Fantasy stories ready');
    expect(newsReadyBody(3, 'Tue 10:00 AM')).toBe(
      '3 posts publish Tue 10:00 AM unless you change them in the Manager.');
    // Singular reads as English.
    expect(newsReadyBody(1, 'Tue 10:00 AM')).toBe(
      '1 post publishes Tue 10:00 AM unless you change it in the Manager.');
  });

  it('autopilot off: N stories wait for approval', () => {
    expect(newsReadyBody(4, null)).toBe(
      '4 fantasy stories are waiting for your approval in the Manager.');
    expect(newsReadyBody(1, null)).toBe(
      '1 fantasy story is waiting for your approval in the Manager.');
  });

  it('adminUidsOf: only Admins/<uid> === true, sorted', () => {
    expect(adminUidsOf({ zed: true, amy: true, off: false, str: 'true', n: 1 }))
      .toEqual(['amy', 'zed']);
    expect(adminUidsOf(null)).toEqual([]);
    expect(adminUidsOf('junk')).toEqual([]);
  });
});
