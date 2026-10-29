// Message managers (spec 2026-10-28 §3) over the in-memory FantasyDb +
// capturing pusher: the shared core behind the sendFantasyMessage callable
// (sendManagerMessage — audiences all / unchanged / owners, trim + cut, the
// throws the callable maps to failed-precondition) and the sweep's
// scheduled-message step (ScheduledPushes/<id>: due rows claimed via SentAt
// and sent once, future rows untouched, a failing row records Error and is
// never retried, and it runs even while the engine is paused). World:
// test_support.ts world2 (GW1 settled, GW2 open until Sun Jun 28 22:00Z).
// Golden squads: alpha holds Alex + Will (bench), boost holds Will + Sam,
// churn holds neither; nobody holds Wes.

import { describe, expect, it } from 'vitest';
import {
  isScheduledMessageDue, managerMessageAudienceOf, sendDueScheduledMessages,
  sendManagerMessage,
} from './messages';
import { FantasyLogger, runLifecycleSweep } from './orchestration';
import { F_ROOT, FakeDb, FakePusher, world2 } from './test_support';

// Saturday before the GW2 lock (open window; the deadline reminder's
// Sunday 19:00Z instant is still ahead, so the sweep sends nothing else).
const NOW = new Date(Date.UTC(2026, 5, 27, 18));
const NOW_MS = NOW.getTime();
const HOUR_MS = 3_600_000;
const GW2_DATA = { type: 'fantasy', sport: 'Futsal', season: '15', gw: '2' };

function seeded(): FakeDb {
  const db = new FakeDb(world2());
  db.data.Fantasy.Futsal['15'].Managers = {
    alpha: { TeamName: 'Alpha FC' },
    boost: { TeamName: 'Boost FC' },
    churn: { TeamName: 'Churn FC' },
    lurker: { TeamName: 'Lurker FC' }, // signed up, never saved a squad
  };
  db.data.Fantasy.Futsal['15'].TransferState = {
    churn: { Free: 2, UsedThisGw: 1, SavedGw: 2 }, // acted this week
  };
  return db;
}

const BASE = {
  sport: 'Futsal', season: '15', title: 'Deadline moved',
  body: 'The deadline is now Sunday 5 PM.', nowUtc: NOW,
};

function capturingLog(): FantasyLogger & {
  infos: string[]; warns: Array<{ message: string; context?: Record<string, unknown> }>;
} {
  const infos: string[] = [];
  const warns: Array<{ message: string; context?: Record<string, unknown> }> = [];
  return {
    infos,
    warns,
    info: (message) => { infos.push(message); },
    warn: (message, context) => { warns.push({ message, context }); },
  };
}

describe('sendManagerMessage', () => {
  it("'all': every manager (Managers ∪ Squads), current gw in the payload", async () => {
    const db = seeded();
    const pusher = new FakePusher();
    const res = await sendManagerMessage(db, pusher, { ...BASE, audience: 'all' });

    expect(res).toEqual({ audience: 4, sent: 4 });
    expect(pusher.sends).toHaveLength(1);
    expect(pusher.sends[0].map((m) => m.uid))
      .toEqual(['alpha', 'boost', 'churn', 'lurker']);
    for (const m of pusher.sends[0]) {
      expect(m.title).toBe('Deadline moved');
      expect(m.body).toBe('The deadline is now Sunday 5 PM.');
      expect(m.data).toEqual(GW2_DATA);
    }
    expect(pusher.topicSends).toEqual([]);
  });

  it("'unchanged': the reminder audience — managers who did not save this gameweek", async () => {
    const db = seeded();
    const pusher = new FakePusher();
    const res = await sendManagerMessage(db, pusher, { ...BASE, audience: 'unchanged' });

    expect(res).toEqual({ audience: 3, sent: 3 });
    expect(pusher.sends[0].map((m) => m.uid)).toEqual(['alpha', 'boost', 'lurker']);
    expect(pusher.sends[0][0].data).toEqual(GW2_DATA);
  });

  it("'unchanged' throws without a fantasy Config or a current gameweek", async () => {
    const pusher = new FakePusher();
    await expect(sendManagerMessage(seeded(), pusher, {
      ...BASE, sport: 'Basketball', season: '9', audience: 'unchanged',
    })).rejects.toThrow('No fantasy Config for Basketball/9');
    await expect(sendManagerMessage(seeded(), pusher, {
      ...BASE, audience: 'unchanged', nowUtc: new Date(Date.UTC(2026, 7, 15)),
    })).rejects.toThrow('No current gameweek for Futsal/15');
    expect(pusher.sends).toEqual([]);
  });

  it("'owners': managers holding the player in ANY slot (starter or bench)", async () => {
    const db = seeded();
    const pusher = new FakePusher();
    const res = await sendManagerMessage(db, pusher, {
      ...BASE, audience: 'owners', player: '  Will ',
    });
    expect(res).toEqual({ audience: 2, sent: 2 });
    expect(pusher.sends[0].map((m) => m.uid)).toEqual(['alpha', 'boost']);
  });

  it("'owners' of a player nobody holds: audience 0, nothing sent", async () => {
    const pusher = new FakePusher();
    expect(await sendManagerMessage(seeded(), pusher, {
      ...BASE, audience: 'owners', player: 'Wes',
    })).toEqual({ audience: 0, sent: 0 });
    expect(pusher.sends).toEqual([]);
  });

  it("'owners' without a player throws", async () => {
    const pusher = new FakePusher();
    for (const player of [undefined, '', '   ']) {
      await expect(sendManagerMessage(seeded(), pusher, {
        ...BASE, audience: 'owners', player,
      })).rejects.toThrow('Pick a player');
    }
    expect(pusher.sends).toEqual([]);
  });

  it('title/body are trimmed and cut (title ≤ 40, body ≤ 140) — never a throw', async () => {
    const pusher = new FakePusher();
    await sendManagerMessage(seeded(), pusher, {
      ...BASE, audience: 'all',
      title: `  ${'T'.repeat(50)}  `,
      body: `\n${'b'.repeat(200)} `,
    });
    const m = pusher.sends[0][0];
    expect(m.title).toBe('T'.repeat(40));
    expect(m.body).toBe('b'.repeat(140));
  });

  it('the cut counts characters the way the Manager counter does (an emoji is one)', async () => {
    const pusher = new FakePusher();
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}'; // one grapheme
    await sendManagerMessage(seeded(), pusher, {
      ...BASE, audience: 'all', title: `${'x'.repeat(39)}${family}yz`,
    });
    expect(pusher.sends[0][0].title).toBe(`${'x'.repeat(39)}${family}`);
  });

  it('an empty body is allowed (title-only push)', async () => {
    const pusher = new FakePusher();
    await sendManagerMessage(seeded(), pusher, { ...BASE, audience: 'all', body: '  ' });
    expect(pusher.sends[0][0].body).toBe('');
  });

  it('an empty title throws before anything is sent', async () => {
    const pusher = new FakePusher();
    for (const title of ['', '    ']) {
      await expect(sendManagerMessage(seeded(), pusher, {
        ...BASE, audience: 'all', title,
      })).rejects.toThrow('needs a title');
    }
    expect(pusher.sends).toEqual([]);
  });

  it("'all' outside any gameweek (or without Config) still sends, with gw 0", async () => {
    const pusher = new FakePusher();
    expect(await sendManagerMessage(seeded(), pusher, {
      ...BASE, audience: 'all', nowUtc: new Date(Date.UTC(2026, 7, 15)),
    })).toEqual({ audience: 4, sent: 4 });
    expect(pusher.sends[0][0].data).toEqual({ ...GW2_DATA, gw: '0' });

    const noConfig = seeded();
    delete noConfig.data.Fantasy.Futsal['15'].Config;
    const pusher2 = new FakePusher();
    await sendManagerMessage(noConfig, pusher2, {
      ...BASE, audience: 'owners', player: 'Alex',
    });
    expect(pusher2.sends[0].map((m) => m.uid)).toEqual(['alpha']);
    expect(pusher2.sends[0][0].data['gw']).toBe('0');
  });
});

describe('managerMessageAudienceOf', () => {
  it('the three audiences; absent = all; anything else throws', () => {
    expect(managerMessageAudienceOf('all')).toBe('all');
    expect(managerMessageAudienceOf('unchanged')).toBe('unchanged');
    expect(managerMessageAudienceOf('owners')).toBe('owners');
    expect(managerMessageAudienceOf(undefined)).toBe('all');
    expect(managerMessageAudienceOf(null)).toBe('all');
    expect(() => managerMessageAudienceOf('everyone')).toThrow('Unknown audience');
    expect(() => managerMessageAudienceOf(3)).toThrow('Unknown audience');
  });
});

describe('isScheduledMessageDue', () => {
  it('a map row with a numeric SendAt <= now and no SentAt', () => {
    expect(isScheduledMessageDue({ SendAt: NOW_MS }, NOW_MS)).toBe(true);
    expect(isScheduledMessageDue({ SendAt: NOW_MS - 1 }, NOW_MS)).toBe(true);
    expect(isScheduledMessageDue({ SendAt: NOW_MS + 1 }, NOW_MS)).toBe(false);
    expect(isScheduledMessageDue({ SendAt: NOW_MS - 1, SentAt: 5 }, NOW_MS)).toBe(false);
    expect(isScheduledMessageDue({ SendAt: String(NOW_MS - 1) }, NOW_MS)).toBe(false);
    expect(isScheduledMessageDue({}, NOW_MS)).toBe(false);
    expect(isScheduledMessageDue(null, NOW_MS)).toBe(false);
    expect(isScheduledMessageDue([{ SendAt: 1 }], NOW_MS)).toBe(false);
  });
});

const SCHED = `${F_ROOT}/ScheduledPushes`;

function withScheduled(db: FakeDb): FakeDb {
  db.data.Fantasy.Futsal['15'].ScheduledPushes = {
    due: {
      Title: 'Match day postponed', Body: "This week's games are postponed.",
      Audience: 'all', SendAt: NOW_MS - 60_000, CreatedAt: NOW_MS - HOUR_MS,
    },
    owners: {
      Title: 'Alex news', Body: 'Check your squad.', Audience: 'owners',
      Player: 'Alex', SendAt: NOW_MS, CreatedAt: NOW_MS - HOUR_MS,
    },
    future: {
      Title: 'Later', Body: 'Not yet.', Audience: 'all',
      SendAt: NOW_MS + HOUR_MS, CreatedAt: NOW_MS - HOUR_MS,
    },
    broken: { // owners without a player: fails, recorded, never retried
      Title: 'Owners', Body: 'x', Audience: 'owners',
      SendAt: NOW_MS - 5, CreatedAt: NOW_MS - HOUR_MS,
    },
    done: {
      Title: 'Old', Body: 'Already out.', Audience: 'all',
      SendAt: NOW_MS - 2 * HOUR_MS, CreatedAt: 1, SentAt: NOW_MS - HOUR_MS, Sent: 3,
    },
  };
  return db;
}

describe('scheduled manager messages (sweep step 0)', () => {
  it('due rows are claimed (SentAt) and sent once with Sent; future and sent rows untouched', async () => {
    const db = withScheduled(seeded());
    const pusher = new FakePusher();
    const log = capturingLog();
    await runLifecycleSweep(db, NOW, log, { pusher });

    // Two sends: 'due' to all four, 'owners' to alpha (the Alex holder).
    expect(pusher.sends).toHaveLength(2);
    const byTitle = Object.fromEntries(
      pusher.sends.map((batch) => [batch[0].title, batch]));
    expect(byTitle['Match day postponed'].map((m) => m.uid))
      .toEqual(['alpha', 'boost', 'churn', 'lurker']);
    expect(byTitle['Match day postponed'][0].body)
      .toBe("This week's games are postponed.");
    expect(byTitle['Match day postponed'][0].data).toEqual(GW2_DATA);
    expect(byTitle['Alex news'].map((m) => m.uid)).toEqual(['alpha']);

    expect(await db.read(`${SCHED}/due/SentAt`)).toBe(NOW_MS);
    expect(await db.read(`${SCHED}/due/Sent`)).toBe(4);
    expect(await db.read(`${SCHED}/owners/Sent`)).toBe(1);
    expect(await db.read(`${SCHED}/future`)).toEqual({
      Title: 'Later', Body: 'Not yet.', Audience: 'all',
      SendAt: NOW_MS + HOUR_MS, CreatedAt: NOW_MS - HOUR_MS,
    });
    expect(await db.read(`${SCHED}/done`)).toEqual({
      Title: 'Old', Body: 'Already out.', Audience: 'all',
      SendAt: NOW_MS - 2 * HOUR_MS, CreatedAt: 1, SentAt: NOW_MS - HOUR_MS, Sent: 3,
    });

    // The failing row: claimed, Error recorded, no Sent, a warning logged.
    expect(await db.read(`${SCHED}/broken/SentAt`)).toBe(NOW_MS);
    expect(String(await db.read(`${SCHED}/broken/Error`))).toContain('Pick a player');
    expect(await db.read(`${SCHED}/broken/Sent`)).toBeNull();
    expect(log.warns).toHaveLength(1);
    expect(log.warns[0].message).toBe('fantasy message: scheduled message failed');
    expect(log.warns[0].context).toMatchObject({
      sport: 'Futsal', season: '15', id: 'broken',
    });

    // The next sweep re-sends nothing and never retries the failed row.
    const writesBefore = db.writes.length;
    await runLifecycleSweep(db, new Date(NOW_MS + 15 * 60_000), log, { pusher });
    expect(pusher.sends).toHaveLength(2);
    expect(log.warns).toHaveLength(1);
    expect(db.writes.slice(writesBefore)
      .filter((p) => p.startsWith(SCHED))).toEqual([]);

    // Once the future row is due, it goes out on its own.
    await runLifecycleSweep(db, new Date(NOW_MS + HOUR_MS), log, { pusher });
    expect(pusher.sends).toHaveLength(3);
    expect(pusher.sends[2][0].title).toBe('Later');
    expect(await db.read(`${SCHED}/future/Sent`)).toBe(4);
  });

  it('runs even while the engine is paused (lockOverride locked) — the season still stands down', async () => {
    const db = withScheduled(seeded());
    db.data.Fantasy.Futsal['15'].Config.lockOverride = 'locked';
    delete db.data.Fantasy.Futsal['15'].GwState;
    const pusher = new FakePusher();
    const log = capturingLog();
    await runLifecycleSweep(db, NOW, log, { pusher });

    expect(pusher.sends.map((b) => b[0].title))
      .toEqual(['Match day postponed', 'Alex news']);
    expect(await db.read(`${SCHED}/due/Sent`)).toBe(4);
    expect(log.infos).toContain('fantasy sweep: lockOverride frozen — standing down');
    // The engine itself did nothing: no GwState written.
    expect(await db.read(`${F_ROOT}/GwState`)).toBeNull();
  });

  it('a sweep without a pusher claims nothing (a later equipped sweep delivers)', async () => {
    const db = withScheduled(seeded());
    await runLifecycleSweep(db, NOW);
    expect(await db.read(`${SCHED}/due/SentAt`)).toBeNull();

    const pusher = new FakePusher();
    await runLifecycleSweep(db, NOW, undefined, { pusher });
    expect(await db.read(`${SCHED}/due/Sent`)).toBe(4);
  });

  it('a lost SentAt claim (a concurrent sweep won) sends nothing', async () => {
    const db = withScheduled(seeded());
    db.writeIfAbsent = async () => false;
    const pusher = new FakePusher();
    expect(await sendDueScheduledMessages(db, pusher, {
      sport: 'Futsal', season: '15', nowUtc: NOW,
    })).toBe(0);
    expect(pusher.sends).toEqual([]);
    expect(await db.read(`${SCHED}/due/Sent`)).toBeNull();
  });

  it('a pusher that throws records Error (no retry); junk rows are skipped', async () => {
    const db = seeded();
    db.data.Fantasy.Futsal['15'].ScheduledPushes = {
      boom: { Title: 'T', Body: 'B', Audience: 'all', SendAt: NOW_MS - 1 },
      junk: 'not a row',
      noTime: { Title: 'T', Body: 'B', Audience: 'all' },
      badAudience: { Title: 'T', Body: 'B', Audience: 'vip', SendAt: NOW_MS - 1 },
      noTitle: { Body: 'B', Audience: 'all', SendAt: NOW_MS - 1 },
    };
    const pusher = new FakePusher();
    pusher.sendToUsers = async () => { throw new Error('FCM down'); };
    const handled = await sendDueScheduledMessages(db, pusher, {
      sport: 'Futsal', season: '15', nowUtc: NOW,
    });

    expect(handled).toBe(3);
    expect(await db.read(`${SCHED}/boom/Error`)).toBe('FCM down');
    expect(await db.read(`${SCHED}/boom/SentAt`)).toBe(NOW_MS);
    expect(String(await db.read(`${SCHED}/badAudience/Error`)))
      .toContain('Unknown audience');
    expect(String(await db.read(`${SCHED}/noTitle/Error`))).toContain('needs a title');
    expect(await db.read(`${SCHED}/junk`)).toBe('not a row');
    expect(await db.read(`${SCHED}/noTime`)).toEqual(
      { Title: 'T', Body: 'B', Audience: 'all' });
  });
});
