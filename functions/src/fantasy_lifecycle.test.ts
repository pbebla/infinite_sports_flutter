// The fantasy schedulers' wiring (final review I5): the reprice job tries
// every hour from 10:00 to 15:00 league time, so one failed run (a read
// that timed out) is retried the same morning instead of turning into a
// permanent Repriced {Skipped:'late'} the next day. Its claim makes every
// later attempt a no-op. The deployed name stays fantasyMondayReprice
// (renaming a deployed function deletes and recreates it).

import { describe, expect, it } from 'vitest';
import { fantasyLifecycleSweep, fantasyMondayReprice } from './fantasy_lifecycle';

const scheduleOf = (fn: unknown) =>
  (fn as { __endpoint: { scheduleTrigger: Record<string, unknown> } })
    .__endpoint.scheduleTrigger;

describe('fantasy scheduler wiring', () => {
  it('reprice: hourly attempts 10:00–15:00 league time', () => {
    expect(scheduleOf(fantasyMondayReprice)['schedule']).toBe('0 10-15 * * *');
    expect(scheduleOf(fantasyMondayReprice)['timeZone']).toBe('America/Los_Angeles');
  });

  it('the sweep still runs every 15 minutes', () => {
    expect(scheduleOf(fantasyLifecycleSweep)['schedule']).toBe('every 15 minutes');
  });
});
