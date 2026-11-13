// News push on publish (spec 2026-10-28 §4.5): a News/Published row with a
// Push map and no PushedAt pushes exactly once — the News/PushClaims/<id>
// claim makes a repeat (the trigger re-firing on its own PushedAt/PushSent
// writes, an edit, a whole-row republish that wiped the display stamps, a
// concurrent instance) a no-op; a post first seen over an hour after it was
// published is claimed as stale and never pushes. Audiences: managers
// (Managers ∪ Squads), owners of ANY tagged player, everyone (FCM topic
// all_users).

import { describe, expect, it } from 'vitest';
import {
  NEWS_PUSH_STALE_MS, needsNewsPush, pushPublishedPost,
} from './news_push';
import { F_ROOT, FakeDb, FakePusher } from './test_support';

const NOW = new Date(Date.UTC(2026, 9, 28, 17, 0));
const POST = `${F_ROOT}/News/Published/p1`;
const CLAIM = `${F_ROOT}/News/PushClaims/p1`;
// Published a minute before the trigger runs (a fresh publish).
const PUBLISHED_AT = NOW.getTime() - 60_000;

function pick(playerId: string, position: string, bench = false) {
  return { playerId, position, priceTenths: 50, bench };
}

function squad(starters: string[], bench: string[] = []) {
  return {
    picks: [
      ...starters.map((n, i) => pick(n, i === 0 ? 'GK' : 'ATT')),
      ...bench.map((n) => pick(n, 'DEF', true)),
    ],
    captainId: starters[1] ?? starters[0],
    viceId: starters[2] ?? starters[0],
  };
}

function card(name: string) {
  return {
    name, position: 'ATT', team: 'Sharks', priceTenths: 75, goals: 3, assists: 1,
  };
}

function world(post: Record<string, unknown> | null, extra: {
  managers?: unknown; squads?: unknown;
} = {}): FakeDb {
  return new FakeDb({
    Fantasy: {
      Futsal: {
        '15': {
          Managers: extra.managers ?? { u1: { TeamName: 'One' }, u2: true },
          Squads: extra.squads ?? {
            u2: squad(['K', 'Alex', 'B']),
            u3: squad(['K', 'C', 'D'], ['Zed']),
            u4: squad(['K', 'C', 'D']),
          },
          News: { Published: post === null ? {} : { p1: post } },
        },
      },
    },
  });
}

function post(push: unknown, extra: Record<string, unknown> = {}) {
  return {
    Title: 'Team of the Week', Body: 'Five made it.', At: PUBLISHED_AT, Gw: 3,
    ...(push === undefined ? {} : { Push: push }),
    ...extra,
  };
}

const ARGS = { sport: 'Futsal', season: '15', postId: 'p1', nowUtc: NOW };

describe('pushPublishedPost', () => {
  it('managers: Managers ∪ Squads, postId + gw in data, PushedAt/PushSent written', async () => {
    const db = world(post({ Title: 'TOTW is out', Body: 'See who made it.', Audience: 'managers' }));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 4 });

    expect(pusher.sends).toHaveLength(1);
    expect(pusher.sends[0].map((m) => m.uid)).toEqual(['u1', 'u2', 'u3', 'u4']);
    const data = {
      type: 'fantasy', sport: 'Futsal', season: '15', gw: '3', postId: 'p1',
    };
    for (const m of pusher.sends[0]) {
      expect(m).toMatchObject({ title: 'TOTW is out', body: 'See who made it.' });
      expect(m.data).toEqual(data);
    }
    expect(pusher.topicSends).toEqual([]);
    expect(await db.read(`${POST}/PushedAt`)).toBe(NOW.getTime());
    expect(await db.read(`${POST}/PushSent`)).toBe(4);
    // The authoritative once-only claim lives in its own node.
    expect(await db.read(CLAIM)).toEqual({ At: NOW.getTime(), Sent: 4 });
    // The post itself is untouched.
    expect(await db.read(`${POST}/Title`)).toBe('Team of the Week');
  });

  it('owners: managers holding ANY tagged player (starter or bench)', async () => {
    const db = world(post(
      { Title: 'Spotlight', Body: 'Alex and Zed.', Audience: 'owners' },
      { Players: { 0: card('Alex'), 1: card('Zed') } },
    ));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 2 });
    expect(pusher.sends[0].map((m) => m.uid)).toEqual(['u2', 'u3']);
    expect(pusher.sends[0][0].data['postId']).toBe('p1');
    expect(await db.read(`${POST}/PushSent`)).toBe(2);
  });

  it('owners: a list-coerced Players node reads the same', async () => {
    const db = world(post(
      { Title: 'Spotlight', Body: '', Audience: 'owners' },
      { Players: [card('Zed')] },
    ));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 1 });
    expect(pusher.sends[0].map((m) => m.uid)).toEqual(['u3']);
  });

  it('owners with nobody holding the players: claimed, nothing sent, PushSent 0', async () => {
    const db = world(post(
      { Title: 'Spotlight', Body: 'x', Audience: 'owners' },
      { Players: { 0: card('Nobody') } },
    ));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 0 });
    expect(pusher.sends).toEqual([]);
    expect(await db.read(`${POST}/PushedAt`)).toBe(NOW.getTime());
    expect(await db.read(`${POST}/PushSent`)).toBe(0);
  });

  it('everyone: one topic send to all_users, no per-user sends', async () => {
    const db = world(post({ Title: 'Big news', Body: 'Read it.', Audience: 'everyone' }));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 1 });
    expect(pusher.sends).toEqual([]);
    expect(pusher.topicSends).toEqual([{
      topic: 'all_users',
      title: 'Big news',
      body: 'Read it.',
      data: { type: 'fantasy', sport: 'Futsal', season: '15', gw: '3', postId: 'p1' },
    }]);
    expect(await db.read(`${POST}/PushSent`)).toBe(1);
  });

  it('unknown or missing Audience falls back to managers', async () => {
    for (const audience of ['vip', undefined, 7]) {
      const db = world(post({ Title: 'T', Body: 'B', Audience: audience }));
      const pusher = new FakePusher();
      expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 4 });
      expect(pusher.topicSends).toEqual([]);
      expect(pusher.sends[0].map((m) => m.uid)).toEqual(['u1', 'u2', 'u3', 'u4']);
    }
  });

  it('blank push title falls back to the post title; blank body stays empty; no Gw -> gw 0', async () => {
    const db = world(post({ Title: '   ', Audience: 'everyone' }));
    delete db.data['Fantasy']['Futsal']['15']['News']['Published']['p1']['Gw'];
    const pusher = new FakePusher();

    await pushPublishedPost(db, pusher, ARGS);
    expect(pusher.topicSends[0]).toMatchObject({
      title: 'Team of the Week', body: '',
    });
    expect(pusher.topicSends[0].data['gw']).toBe('0');
  });

  it('push and post titles both blank -> the generic "Fantasy news" title', async () => {
    const db = world(post(
      { Title: '', Body: 'Body only.', Audience: 'everyone' }, { Title: ' ' },
    ));
    const pusher = new FakePusher();

    await pushPublishedPost(db, pusher, ARGS);
    expect(pusher.topicSends[0]).toMatchObject({
      title: 'Fantasy news', body: 'Body only.',
    });
  });

  it('a second call is a no-op: the PushedAt claim holds (trigger echo / edits)', async () => {
    const db = world(post({ Title: 'T', Body: 'B', Audience: 'managers' }));
    const pusher = new FakePusher();
    await pushPublishedPost(db, pusher, ARGS);
    const writesAfterFirst = db.writes.length;

    // The trigger re-fires on its own PushedAt and PushSent writes...
    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    // ...and on a later Manager edit of the published post.
    await db.write(`${POST}/Title`, 'Edited title');
    expect(await pushPublishedPost(db, pusher, {
      ...ARGS, nowUtc: new Date(NOW.getTime() + 60_000),
    })).toBeNull();

    expect(pusher.sends).toHaveLength(1);
    expect(db.writes.length).toBe(writesAfterFirst + 1); // just the edit
    expect(await db.read(`${POST}/PushedAt`)).toBe(NOW.getTime());
    expect(await db.read(`${POST}/PushSent`)).toBe(4);
  });

  it('a lost claim (another instance won between read and claim) -> null, nothing sent', async () => {
    const db = world(post({ Title: 'T', Body: 'B', Audience: 'everyone' }));
    db.writeIfAbsent = async () => false;
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    expect(pusher.sends).toEqual([]);
    expect(pusher.topicSends).toEqual([]);
    expect(await db.read(`${POST}/PushSent`)).toBeNull();
  });

  it('a row without a Push map -> null and no PushedAt written', async () => {
    for (const push of [undefined, null, 'managers', true, ['x']]) {
      const db = world(post(push));
      const pusher = new FakePusher();
      expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
      expect(db.writes).toEqual([]);
      expect(await db.read(`${POST}/PushedAt`)).toBeNull();
      expect(pusher.sends).toEqual([]);
    }
  });

  it('an absent row (deleted) -> null, nothing written', async () => {
    const db = world(null);
    const pusher = new FakePusher();
    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    expect(db.writes).toEqual([]);
  });

  it('a row already carrying PushedAt -> null, nothing written', async () => {
    const db = world(post(
      { Title: 'T', Body: 'B', Audience: 'everyone' }, { PushedAt: 5 },
    ));
    const pusher = new FakePusher();
    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    expect(db.writes).toEqual([]);
    expect(pusher.topicSends).toEqual([]);
  });
});

describe('once-only across row rewrites (review 2026-10-28)', () => {
  it('a republish that rewrites the whole row (stamps wiped) never pushes again', async () => {
    const db = world(post({ Title: 'T', Body: 'B', Audience: 'managers' }));
    const pusher = new FakePusher();
    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 4 });

    // The Manager's publish multi-path update (or an old sweep) sets the
    // whole row again: PushedAt/PushSent are gone, At is fresh.
    const later = new Date(NOW.getTime() + 5 * 60_000);
    await db.write(POST, post(
      { Title: 'T', Body: 'B', Audience: 'managers' },
      { Title: 'Edited', At: later.getTime() },
    ));
    expect(needsNewsPush(await db.read(POST))).toBe(true); // the gate passes...
    expect(await pushPublishedPost(db, pusher, { ...ARGS, nowUtc: later }))
      .toBeNull(); // ...the claim does not

    expect(pusher.sends).toHaveLength(1);
    expect(await db.read(CLAIM)).toEqual({ At: NOW.getTime(), Sent: 4 });
  });

  it('an existing PushClaims entry -> null, nothing written, nothing sent', async () => {
    const db = world(post({ Title: 'T', Body: 'B', Audience: 'everyone' }));
    db.data.Fantasy.Futsal['15'].News.PushClaims = { p1: { At: 5, Sent: 1 } };
    const pusher = new FakePusher();
    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    expect(db.writes).toEqual([]);
    expect(pusher.topicSends).toEqual([]);
  });

  it('a post deleted while its push goes out is never recreated by the stamps', async () => {
    const db = world(post({ Title: 'T', Body: 'B', Audience: 'managers' }));
    const pusher = new FakePusher();
    const send = pusher.sendToUsers.bind(pusher);
    pusher.sendToUsers = async (messages) => {
      await db.write(POST, null); // the owner deletes the post mid-send
      return send(messages);
    };

    expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 4 });
    expect(await db.read(POST)).toBeNull(); // no {PushSent} stub row
    expect(await db.read(CLAIM)).toEqual({ At: NOW.getTime(), Sent: 4 });
  });
});

describe('stale first push (review 2026-10-28)', () => {
  it('a post published over 60 minutes ago is claimed as skipped — nothing sent, ever', async () => {
    const db = world(post(
      { Title: 'T', Body: 'B', Audience: 'everyone' },
      { At: NOW.getTime() - NEWS_PUSH_STALE_MS - 1 },
    ));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, ARGS)).toBeNull();
    expect(pusher.topicSends).toEqual([]);
    expect(pusher.sends).toEqual([]);
    expect(await db.read(CLAIM)).toEqual({ At: NOW.getTime(), Skipped: 'stale' });
    // Nothing is stamped on the row: it was never pushed.
    expect(await db.read(`${POST}/PushedAt`)).toBeNull();
    expect(await db.read(`${POST}/PushSent`)).toBeNull();

    // A later edit re-fires the trigger: still nothing.
    expect(await pushPublishedPost(db, pusher, {
      ...ARGS, nowUtc: new Date(NOW.getTime() + 60_000),
    })).toBeNull();
    expect(pusher.topicSends).toEqual([]);
    expect(await db.read(CLAIM)).toEqual({ At: NOW.getTime(), Skipped: 'stale' });
  });

  it('a freshly CREATED row pushes even when its At is hours old (skewed tablet clock)', async () => {
    const db = world(post(
      { Title: 'T', Body: 'B', Audience: 'everyone' },
      { At: NOW.getTime() - 5 * NEWS_PUSH_STALE_MS },
    ));
    const pusher = new FakePusher();

    expect(await pushPublishedPost(db, pusher, { ...ARGS, isCreate: true }))
      .toEqual({ sent: 1 });
    expect(pusher.topicSends).toHaveLength(1);
    expect(await db.read(CLAIM)).toEqual({ At: NOW.getTime(), Sent: 1 });
  });

  it('exactly 60 minutes old still pushes; a row without a numeric At is never stale', async () => {
    for (const extra of [
      { At: NOW.getTime() - NEWS_PUSH_STALE_MS },
      { At: undefined },
      { At: 'yesterday' },
    ]) {
      const db = world(post({ Title: 'T', Body: 'B', Audience: 'everyone' }, extra));
      if (extra.At === undefined) {
        delete db.data.Fantasy.Futsal['15'].News.Published.p1.At;
      }
      const pusher = new FakePusher();
      expect(await pushPublishedPost(db, pusher, ARGS)).toEqual({ sent: 1 });
      expect(pusher.topicSends).toHaveLength(1);
    }
  });
});

describe('needsNewsPush (the trigger\'s read-free echo gate)', () => {
  it('true only for a map row with a Push map and no PushedAt', () => {
    expect(needsNewsPush(post({ Audience: 'managers' }))).toBe(true);
    expect(needsNewsPush(post({ Audience: 'managers' }, { PushedAt: 1 }))).toBe(false);
    expect(needsNewsPush(post(undefined))).toBe(false);
    expect(needsNewsPush(post('managers'))).toBe(false);
    expect(needsNewsPush(null)).toBe(false);
    expect(needsNewsPush('row')).toBe(false);
    expect(needsNewsPush([post({})])).toBe(false);
  });
});
