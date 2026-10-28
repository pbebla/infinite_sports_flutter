// Phase F pushes over the in-memory FantasyDb + capturing pusher: the
// scheduled deadline reminder (audience + once-only claim + template), the
// send-now callable core, and the weekly recap folded into finalize (format
// + RecapSent guard). World: test_support.ts world2 (GW1 settled, GW2 under
// test; GW2 locks Sun Jun 28 22:00Z).

import { describe, expect, it } from 'vitest';
import {
  maybeFinalizeGame, runLifecycleSweep, sendReminderNow,
} from './orchestration';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, FakePusher, GW2_DATE, world2,
} from './test_support';

// Sunday noon league time (PDT) = 19:00Z — the default reminder instant for
// the 15:00 league lock (22:00Z).
const SUNDAY_NOON = new Date(Date.UTC(2026, 5, 28, 19));
const SUNDAY_LATER = new Date(Date.UTC(2026, 5, 28, 20));

function withManagers(db: FakeDb): FakeDb {
  db.data.Fantasy.Futsal['15'].Managers = {
    alpha: { TeamName: 'Alpha FC' },
    boost: { TeamName: 'Boost FC' },
    churn: { TeamName: 'Churn FC' },
    lurker: { TeamName: 'Lurker FC' }, // signed up, never saved a squad
  };
  return db;
}

describe('scheduled deadline reminder (sweep step 4)', () => {
  it('fires once at the reminder instant, to unchanged squads only', async () => {
    const db = withManagers(new FakeDb(world2({ gw2Status: 1 })));
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 2, UsedThisGw: 1, SavedGw: 2 }, // acted this week
      alpha: { Free: 4, UsedThisGw: 0, SavedGw: 1, RolledGw: 1 }, // stale
    };
    const pusher = new FakePusher();

    // Too early: 13:00Z is before the 19:00Z instant.
    await runLifecycleSweep(
      db, new Date(Date.UTC(2026, 5, 28, 13)), undefined, { pusher });
    expect(pusher.sends).toEqual([]);
    expect(await db.read(`${F_ROOT}/ReminderSent/2`)).toBeNull();

    await runLifecycleSweep(db, SUNDAY_NOON, undefined, { pusher });
    expect(pusher.sends).toHaveLength(1);
    const msgs = pusher.sends[0];
    expect(msgs.map((m) => m.uid)).toEqual(['alpha', 'boost', 'lurker']);
    expect(msgs[0].title).toBe('Fantasy deadline');
    expect(msgs[0].body).toBe('Your fantasy squad is untouched this week — ' +
      'deadline Sun, Jun 28 · 3:00 PM.');
    expect(msgs[0].data).toEqual({
      type: 'fantasy', sport: 'Futsal', season: '15', gw: '2',
    });
    expect(await db.read(`${F_ROOT}/ReminderSent/2`))
      .toEqual({ At: SUNDAY_NOON.getTime() });

    // Once only: the next sweep sends nothing.
    await runLifecycleSweep(db, SUNDAY_LATER, undefined, { pusher });
    expect(pusher.sends).toHaveLength(1);
  });

  it('owner config: HoursBefore moves the instant, Template is honored, Enabled kills it', async () => {
    const db = withManagers(new FakeDb(world2({ gw2Status: 1 })));
    db.data.Fantasy.Futsal['15'].Config.Reminder = {
      HoursBefore: 27, Template: 'T-minus: {deadline}!',
    };
    const pusher = new FakePusher();
    // 27h before the 22:00Z Sunday lock = Saturday 19:00Z.
    await runLifecycleSweep(
      db, new Date(Date.UTC(2026, 5, 27, 20)), undefined, { pusher });
    expect(pusher.sends).toHaveLength(1);
    expect(pusher.sends[0][0].body).toBe('T-minus: Sun, Jun 28 · 3:00 PM!');

    const off = withManagers(new FakeDb(world2({ gw2Status: 1 })));
    off.data.Fantasy.Futsal['15'].Config.Reminder = { Enabled: false };
    const offPusher = new FakePusher();
    await runLifecycleSweep(off, SUNDAY_NOON, undefined, { pusher: offPusher });
    expect(offPusher.sends).toEqual([]);
    expect(await off.read(`${F_ROOT}/ReminderSent/2`)).toBeNull();
  });

  it('without a pusher the claim stays unclaimed (a later equipped sweep still delivers)', async () => {
    const db = withManagers(new FakeDb(world2({ gw2Status: 1 })));
    await runLifecycleSweep(db, SUNDAY_NOON);
    expect(await db.read(`${F_ROOT}/ReminderSent/2`)).toBeNull();
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SUNDAY_LATER, undefined, { pusher });
    expect(pusher.sends).toHaveLength(1);
  });
});

describe('sendReminderNow (callable core)', () => {
  it('unchanged audience by default, all on request; marks nothing', async () => {
    const db = withManagers(new FakeDb(world2({ gw2Status: 1 })));
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 2, UsedThisGw: 1, SavedGw: 2 },
    };
    const pusher = new FakePusher();
    const now = new Date(Date.UTC(2026, 5, 24, 12));

    const res = await sendReminderNow(db, pusher, {
      sport: 'Futsal', season: '15', nowUtc: now,
    });
    expect(res).toEqual({ gw: 2, audience: 3, sent: 3 });
    expect(pusher.sends[0].map((m) => m.uid))
      .toEqual(['alpha', 'boost', 'lurker']);

    const all = await sendReminderNow(db, pusher, {
      sport: 'Futsal', season: '15', audience: 'all', nowUtc: now,
    });
    expect(all).toEqual({ gw: 2, audience: 4, sent: 4 });

    // Manual sends never consume the scheduled reminder's once-only claim.
    expect(await db.read(`${F_ROOT}/ReminderSent/2`)).toBeNull();
  });

  it('throws on a season without fantasy or without a current gameweek', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 }));
    const pusher = new FakePusher();
    await expect(sendReminderNow(db, pusher, {
      sport: 'Basketball', season: '9', nowUtc: SUNDAY_NOON,
    })).rejects.toThrow('No fantasy Config');
    await expect(sendReminderNow(db, pusher, {
      sport: 'Futsal', season: '15', nowUtc: new Date(Date.UTC(2026, 7, 15)),
    })).rejects.toThrow('No current gameweek');
  });
});

describe('weekly recap (finalize epilogue)', () => {
  it('spec format per manager, once per gameweek', async () => {
    const db = new FakeDb(world2());
    const pusher = new FakePusher();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, { pusher });

    // Locked sweep: no reminder (week not open) — only the recap batch.
    expect(pusher.sends).toHaveLength(1);
    const byUid = Object.fromEntries(pusher.sends[0].map((m) => [m.uid, m]));
    // boost's benchBoost replay was voided -> 45; gross alpha 35, churn 59.
    // Overall after GW2: churn 118 #1, boost 89 #2, alpha 70 #3; top 59.
    expect(byUid['alpha'].title).toBe('Fantasy recap');
    expect(byUid['alpha'].body)
      .toBe('GW2: you scored 35, moved to #3, top score 59.');
    expect(byUid['boost'].body)
      .toBe('GW2: you scored 45, moved to #2, top score 59.');
    expect(byUid['churn'].body)
      .toBe('GW2: you scored 59, moved to #1, top score 59.');
    expect(byUid['churn'].data).toEqual({
      type: 'fantasy', sport: 'Futsal', season: '15', gw: '2',
    });
    expect(await db.read(`${F_ROOT}/RecapSent/2`))
      .toEqual({ At: AFTER_LOCK2.getTime() });

    // A score-edit rerun re-settles points but never re-pushes.
    db.data.Futsal['15'].Date[GW2_DATE][1].team1score = 1;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
      deps: { pusher },
    });
    expect(pusher.sends).toHaveLength(1);
  });
});
