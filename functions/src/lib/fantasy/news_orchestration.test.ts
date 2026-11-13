// Phase G news over the in-memory FantasyDb: the NewsDrafted-guarded
// post-finalize drafting step (deterministic Dream Team post + AI drafts
// through a fake fetch, including the write-NOTHING failure paths), the
// autopilot schedule (ON by default, Config/NewsAutopilot, legacy
// DreamTeamPost), the tagged-player snapshots, the once-only admin heads-up
// push, and the sweep's auto-publish of ANY due draft. World:
// test_support.ts world2.
//
// HAND MATH for the player cards (world2 = both match days replay the two
// golden games; no PlayerWeeks/1 and no PriceChanges are seeded):
// - gw = 2 (the only PlayerWeeks key after the GW2 finalize); gwPoints =
//   the golden week points (Bo 12, Bea 15, Dana 13, Alex 12, Ben 9);
//   seasonPoints = the same (GW2 is the only stored week); no
//   priceDeltaTenths (nothing repriced).
// - ownershipPct over the three GW2 squads: Bo churn = round(100/3) = 33;
//   Bea boost+churn = 67; Dana alpha+churn = 67; Alex alpha = 33; Ben
//   boost+churn = 67.
// - goals/assists = 2x one golden match day: Dana goal1 assist1 -> 2/2;
//   Alex Goal+PenGoal -> 4/0; Ben goal1 -> 2/0; Bea assist1 -> 0/2; Bo 0/0.

import { describe, expect, it } from 'vitest';
import { FetchLike } from '../support';
import { Json } from './golden_fixture';
import { FantasyLogger, maybeFinalizeGame, runLifecycleSweep } from './orchestration';
import { AFTER_LOCK2, F_ROOT, FakeDb, FakePusher, world2 } from './test_support';

const replyWith = (text: string): FetchLike => async () => ({
  ok: true,
  status: 200,
  json: async () => ({ content: [{ type: 'text', text }] }),
});

// The golden games' Dream Team (same either gameweek): Bo/Bea/Dana/Alex/Ben.
const DREAM_BODY =
  'Bo (GK) 12 · Bea (DEF) 15 · Dana (DEF) 13 · Alex (ATT) 12 · Ben (ATT) 9';

// AFTER_LOCK2 = Sun Jun 28 23:00Z (league Sun 16:00 PDT) -> the autopilot's
// stock "Tuesday 10:00" = Tue Jun 30 10:00 PDT = 17:00Z.
const TUE_10AM = Date.UTC(2026, 5, 30, 17);

const TEAMS: Record<string, string> = {
  Bo: 'Bulls', Bea: 'Bulls', Ben: 'Bulls', Dana: 'Sharks', Alex: 'Sharks',
};

const CARDS: Record<string, Json> = {
  Bo: {
    name: 'Bo', position: 'GK', team: 'Bulls', priceTenths: 75, gw: 2,
    gwPoints: 12, seasonPoints: 12, ownershipPct: 33, goals: 0, assists: 0,
  },
  Bea: {
    name: 'Bea', position: 'DEF', team: 'Bulls', priceTenths: 70, gw: 2,
    gwPoints: 15, seasonPoints: 15, ownershipPct: 67, goals: 0, assists: 2,
  },
  Dana: {
    name: 'Dana', position: 'DEF', team: 'Sharks', priceTenths: 80, gw: 2,
    gwPoints: 13, seasonPoints: 13, ownershipPct: 67, goals: 2, assists: 2,
  },
  Alex: {
    name: 'Alex', position: 'ATT', team: 'Sharks', priceTenths: 95, gw: 2,
    gwPoints: 12, seasonPoints: 12, ownershipPct: 33, goals: 4, assists: 0,
  },
  Ben: {
    name: 'Ben', position: 'ATT', team: 'Bulls', priceTenths: 85, gw: 2,
    gwPoints: 9, seasonPoints: 9, ownershipPct: 67, goals: 2, assists: 0,
  },
};

const DREAM_PUSH = {
  Title: 'Team of the Week is out',
  Body: "GW2's best five are in — see who made it.",
  Audience: 'managers',
};

const HEADS_UP_DATA = { type: 'fantasy', sport: 'Futsal', season: '15', gw: '2' };

/** world2 with team names on the Dream Team players (the card's `team`). */
function newsWorld(): FakeDb {
  const db = new FakeDb(world2());
  const players = db.data.Fantasy.Futsal['15'].Players;
  for (const [name, team] of Object.entries(TEAMS)) players[name].teamName = team;
  return db;
}

/** Two AI drafts: the first tags Bea (in this week's stats) and a name the
 *  model invented (dropped); the second tags nobody. */
const TWO_DRAFTS = replyWith(JSON.stringify([
  {
    title: 'Bea on fire', body: 'Fifteen points for the Bulls wall.',
    players: ['Bea', 'Nobody'],
  },
  { title: 'Captain Bo', body: 'A twelve-point week between the posts.' },
]));

describe('post-finalize news drafting (NewsDrafted-guarded)', () => {
  it('queues the Dream Team post and the AI drafts — tagged, autopilot-scheduled', async () => {
    const db = newsWorld();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, {
      news: { apiKey: 'k', fetchImpl: TWO_DRAFTS },
    });

    expect(await db.read(`${F_ROOT}/NewsDrafted/2`))
      .toEqual({ At: AFTER_LOCK2.getTime() });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2dreamteam`)).toEqual({
      Title: 'Team of the Week — GW2',
      Body: DREAM_BODY,
      Gw: 2,
      CreatedAt: AFTER_LOCK2.getTime(),
      Source: 'dreamteam',
      Template: 'dreamteam',
      Players: {
        0: CARDS.Bo, 1: CARDS.Bea, 2: CARDS.Dana, 3: CARDS.Alex, 4: CARDS.Ben,
      },
      Push: DREAM_PUSH,
      AutoPublishAt: TUE_10AM, // autopilot is ON when Config has no row
    });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toEqual({
      Title: 'Bea on fire',
      Body: 'Fifteen points for the Bulls wall.',
      Gw: 2,
      CreatedAt: AFTER_LOCK2.getTime(),
      Source: 'ai',
      Template: 'ai',
      Players: { 0: CARDS.Bea },
      AutoPublishAt: TUE_10AM,
    });
    // No tagged players -> no Players node; AI drafts never carry a Push.
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2ai2`)).toEqual({
      Title: 'Captain Bo',
      Body: 'A twelve-point week between the posts.',
      Gw: 2,
      CreatedAt: AFTER_LOCK2.getTime(),
      Source: 'ai',
      Template: 'ai',
      AutoPublishAt: TUE_10AM,
    });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2ai3`)).toBeNull();
  });

  it('Config/NewsAutopilot Enabled:false: drafts wait in the queue (no AutoPublishAt)', async () => {
    const db = newsWorld();
    db.data.Fantasy.Futsal['15'].Config.NewsAutopilot = {
      Enabled: false, Weekday: 'tuesday', Hour: 10,
    };
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, {
      news: { apiKey: 'k', fetchImpl: TWO_DRAFTS },
    });
    for (const key of ['gw2dreamteam', 'gw2ai1', 'gw2ai2']) {
      const draft = await db.read(`${F_ROOT}/News/Drafts/${key}`) as Json;
      expect(draft).not.toBeNull();
      expect('AutoPublishAt' in draft).toBe(false);
    }
    // Everything else about the drafts is unchanged.
    const dream = await db.read(`${F_ROOT}/News/Drafts/gw2dreamteam`) as Json;
    expect(dream['Template']).toBe('dreamteam');
    expect(dream['Push']).toEqual(DREAM_PUSH);
    expect(Object.keys(dream['Players'])).toHaveLength(5);
  });

  it('Config/NewsAutopilot schedule: every draft carries the next league-local instant', async () => {
    const db = newsWorld();
    db.data.Fantasy.Futsal['15'].Config.NewsAutopilot = {
      Enabled: true, Weekday: 'friday', Hour: 18,
    };
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, {
      news: { apiKey: 'k', fetchImpl: TWO_DRAFTS },
    });
    // Fri Jul 3 18:00 PDT = Sat Jul 4 01:00Z.
    const at = Date.UTC(2026, 6, 4, 1);
    for (const key of ['gw2dreamteam', 'gw2ai1', 'gw2ai2']) {
      expect(await db.read(`${F_ROOT}/News/Drafts/${key}/AutoPublishAt`)).toBe(at);
    }
  });

  it('legacy Config/DreamTeamPost still decides when NewsAutopilot is absent', async () => {
    const on = newsWorld();
    on.data.Fantasy.Futsal['15'].Config.DreamTeamPost = {
      AutoPublish: true, Weekday: 'tuesday', Hour: 10,
    };
    await runLifecycleSweep(on, AFTER_LOCK2); // no AI deps: dream post only
    const draft = await on.read(`${F_ROOT}/News/Drafts/gw2dreamteam`) as Json;
    // Sunday 23:00Z -> Tuesday Jun 30 10:00 PDT = 17:00Z.
    expect(draft['AutoPublishAt']).toBe(TUE_10AM);

    const off = newsWorld();
    off.data.Fantasy.Futsal['15'].Config.DreamTeamPost = {
      AutoPublish: false, Weekday: 'tuesday', Hour: 10,
    };
    await runLifecycleSweep(off, AFTER_LOCK2);
    expect(await off.read(`${F_ROOT}/News/Drafts/gw2dreamteam/AutoPublishAt`))
      .toBeNull();
  });

  it('AI failure or blank key writes NOTHING from the model — and the claim holds', async () => {
    const garbage = new FakeDb(world2());
    await runLifecycleSweep(garbage, AFTER_LOCK2, undefined, {
      news: { apiKey: 'k', fetchImpl: replyWith('I cannot write that.') },
    });
    expect(await garbage.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toBeNull();
    expect(await garbage.read(`${F_ROOT}/News/Drafts/gw2dreamteam`)).not.toBeNull();
    expect(await garbage.read(`${F_ROOT}/History/2`)).not.toBeNull(); // never blocks

    const blankKey = new FakeDb(world2());
    let calls = 0;
    const counting: FetchLike = async (url, init) => {
      calls++;
      return replyWith('[]')(url, init);
    };
    await runLifecycleSweep(blankKey, AFTER_LOCK2, undefined, {
      news: { apiKey: '', fetchImpl: counting },
    });
    expect(calls).toBe(0);
    expect(await blankKey.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toBeNull();

    // Drafting is once-only: a rerun with a now-working model stays silent
    // (the owner already saw this week's queue).
    await maybeFinalizeGame(garbage, {
      sport: 'Futsal', season: '15', dateKey: '06282026', nowUtc: AFTER_LOCK2,
      deps: { news: { apiKey: 'k', fetchImpl: replyWith(
        '[{"title":"Late","body":"Too late."}]') } },
    });
    expect(await garbage.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toBeNull();
  });

  it('a player-card source failure still writes every draft (no Players) and the heads-up', async () => {
    const db = newsWorld();
    db.data.Admins = { owner: true };
    const read = db.read.bind(db);
    db.read = async (path: string) => {
      if (path === `${F_ROOT}/PlayerTotals`) throw new Error('RTDB unavailable');
      return read(path);
    };
    const warns: string[] = [];
    const log: FantasyLogger = {
      info: () => undefined,
      warn: (m) => { warns.push(m); },
    };
    const pusher = new FakePusher();
    await runLifecycleSweep(db, AFTER_LOCK2, log, {
      pusher, news: { apiKey: 'k', fetchImpl: TWO_DRAFTS },
    });

    expect(await db.read(`${F_ROOT}/NewsDrafted/2`))
      .toEqual({ At: AFTER_LOCK2.getTime() });
    const dream = await db.read(`${F_ROOT}/News/Drafts/gw2dreamteam`) as Json;
    expect(dream).toMatchObject({
      Template: 'dreamteam', Body: DREAM_BODY, Push: DREAM_PUSH,
      AutoPublishAt: TUE_10AM,
    });
    expect('Players' in dream).toBe(false);
    for (const key of ['gw2ai1', 'gw2ai2']) {
      const draft = await db.read(`${F_ROOT}/News/Drafts/${key}`) as Json;
      expect(draft).toMatchObject({ Source: 'ai', AutoPublishAt: TUE_10AM });
      expect('Players' in draft).toBe(false);
    }
    expect(pusher.sends[1]).toEqual([{
      uid: 'owner', title: 'Fantasy stories ready',
      body: '3 posts publish Tue 10:00 AM unless you change them in the Manager.',
      data: HEADS_UP_DATA,
    }]);
    expect(warns).toContain(
      'fantasy news: player cards unavailable — drafts without Players');
  });
});

describe('admin heads-up push (once per gameweek, with the drafts)', () => {
  function adminWorld(): FakeDb {
    const db = newsWorld();
    db.data.Admins = { owner: true, helper: true, former: false };
    return db;
  }

  it('autopilot on: every Admins/<uid> === true hears when the posts go live', async () => {
    const db = adminWorld();
    const pusher = new FakePusher();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, {
      pusher, news: { apiKey: 'k', fetchImpl: TWO_DRAFTS },
    });

    expect(pusher.sends).toHaveLength(2); // the GW2 recap, then the heads-up
    const body =
      '3 posts publish Tue 10:00 AM unless you change them in the Manager.';
    expect(pusher.sends[1]).toEqual([
      { uid: 'helper', title: 'Fantasy stories ready', body, data: HEADS_UP_DATA },
      { uid: 'owner', title: 'Fantasy stories ready', body, data: HEADS_UP_DATA },
    ]);

    // Once only: a score-edit rerun drafts nothing and pushes nothing.
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: '06282026', nowUtc: AFTER_LOCK2,
      deps: { pusher, news: { apiKey: 'k', fetchImpl: TWO_DRAFTS } },
    });
    expect(pusher.sends).toHaveLength(2);
  });

  it('a late finalize still leaves 12 h of review: AutoPublishAt = now + 12 h, named in the heads-up', async () => {
    const db = adminWorld();
    const pusher = new FakePusher();
    // Tue Jun 30 08:00 PDT (15:00Z): the stock Tuesday 10:00 slot is 2 h
    // away -> every draft waits until Tue 20:00 PDT (Wed Jul 1 03:00Z).
    const late = new Date(Date.UTC(2026, 5, 30, 15));
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: '06282026', nowUtc: late,
      deps: { pusher, news: { apiKey: 'k', fetchImpl: TWO_DRAFTS } },
    });

    const at = Date.UTC(2026, 6, 1, 3);
    for (const key of ['gw2dreamteam', 'gw2ai1', 'gw2ai2']) {
      expect(await db.read(`${F_ROOT}/News/Drafts/${key}/AutoPublishAt`)).toBe(at);
    }
    expect(pusher.sends[1].map((m) => m.body)).toEqual([
      '3 posts publish Tue 8:00 PM unless you change them in the Manager.',
      '3 posts publish Tue 8:00 PM unless you change them in the Manager.',
    ]);
  });

  it('autopilot off: the stories wait for approval', async () => {
    const db = adminWorld();
    db.data.Fantasy.Futsal['15'].Config.NewsAutopilot = { Enabled: false };
    const pusher = new FakePusher();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, { pusher });

    // No AI deps: the Dream Team post is the only draft.
    expect(pusher.sends[1]).toEqual([
      {
        uid: 'helper', title: 'Fantasy stories ready',
        body: '1 fantasy story is waiting for your approval in the Manager.',
        data: HEADS_UP_DATA,
      },
      {
        uid: 'owner', title: 'Fantasy stories ready',
        body: '1 fantasy story is waiting for your approval in the Manager.',
        data: HEADS_UP_DATA,
      },
    ]);
  });

  it('no draft written, no Admins, or no pusher: no heads-up', async () => {
    // An admin-edited Dream Team with no players + no AI = nothing drafted.
    const empty = adminWorld();
    empty.data.Fantasy.Futsal['15'].DreamTeam = { 2: { Note: 'cleared' } };
    const p1 = new FakePusher();
    await runLifecycleSweep(empty, AFTER_LOCK2, undefined, { pusher: p1 });
    expect(await empty.read(`${F_ROOT}/News/Drafts`)).toBeNull();
    expect(p1.sends).toHaveLength(1); // the recap only

    const noAdmins = newsWorld();
    const p2 = new FakePusher();
    await runLifecycleSweep(noAdmins, AFTER_LOCK2, undefined, { pusher: p2 });
    expect(await noAdmins.read(`${F_ROOT}/News/Drafts/gw2dreamteam`)).not.toBeNull();
    expect(p2.sends).toHaveLength(1); // the recap only

    // No pusher: the drafts still land (and the claim is spent — drafting,
    // not the heads-up, is what NewsDrafted guards).
    const noPusher = adminWorld();
    await runLifecycleSweep(noPusher, AFTER_LOCK2);
    expect(await noPusher.read(`${F_ROOT}/News/Drafts/gw2dreamteam`)).not.toBeNull();
    expect(await noPusher.read(`${F_ROOT}/NewsDrafted/2`)).not.toBeNull();
  });
});

describe('draft auto-publish (sweep step)', () => {
  it('publishes ANY due draft with its post fields; unscheduled and future drafts stay queued', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 })); // games live: no finalize
    const now = new Date(Date.UTC(2026, 5, 24, 12));
    const dreamPlayers = { 0: CARDS.Bo, 1: CARDS.Bea };
    const ownerPush = { Title: 'Bea!', Body: 'Look.', Audience: 'owners' };
    db.data.Fantasy.Futsal['15'].News = {
      Drafts: {
        due: {
          Title: 'Team of the Week — GW1', Body: DREAM_BODY, Gw: 1,
          CreatedAt: 1, Source: 'dreamteam', AutoPublishAt: now.getTime() - 1,
          Template: 'dreamteam', Players: dreamPlayers, Push: DREAM_PUSH,
        },
        ai1: {
          Title: 'AI', Body: 'B', Gw: 1, CreatedAt: 1, Source: 'ai',
          Template: 'ai', Players: { 0: CARDS.Bea },
          AutoPublishAt: now.getTime() - 1,
        },
        mine: { // an owner-scheduled post: no Gw, a photo, an owners push
          Title: 'Spotlight: Bea', Body: 'Bea is great.', CreatedAt: 1,
          Source: 'owner', Template: 'spotlight', Players: { 0: CARDS.Bea },
          Push: ownerPush, PhotoUrl: 'https://img/bea.jpg', EditedAt: 5,
          AutoPublishAt: now.getTime(),
        },
        unscheduled: { // the owner switched Auto-publish off
          Title: 'Edited', Body: 'B', Gw: 1, CreatedAt: 1, Source: 'dreamteam',
        },
        future: {
          Title: 'Later', Body: 'B', Gw: 1, CreatedAt: 1,
          Source: 'ai', AutoPublishAt: now.getTime() + 3_600_000,
        },
      },
    };
    const infos: Array<[string, Record<string, unknown> | undefined]> = [];
    const log: FantasyLogger = {
      info: (m, c) => { infos.push([m, c]); },
      warn: () => undefined,
    };
    await runLifecycleSweep(db, now, log);

    expect(await db.read(`${F_ROOT}/News/Published/due`)).toEqual({
      Title: 'Team of the Week — GW1', Body: DREAM_BODY, At: now.getTime(),
      Template: 'dreamteam', Gw: 1, Players: dreamPlayers, Push: DREAM_PUSH,
    });
    expect(await db.read(`${F_ROOT}/News/Published/ai1`)).toEqual({
      Title: 'AI', Body: 'B', At: now.getTime(),
      Template: 'ai', Gw: 1, Players: { 0: CARDS.Bea },
    });
    // Source/CreatedAt/AutoPublishAt/EditedAt never reach the public feed.
    expect(await db.read(`${F_ROOT}/News/Published/mine`)).toEqual({
      Title: 'Spotlight: Bea', Body: 'Bea is great.', At: now.getTime(),
      Template: 'spotlight', Players: { 0: CARDS.Bea }, Push: ownerPush,
      PhotoUrl: 'https://img/bea.jpg',
    });
    for (const key of ['due', 'ai1', 'mine']) {
      expect(await db.read(`${F_ROOT}/News/Drafts/${key}`)).toBeNull();
    }
    expect(await db.read(`${F_ROOT}/News/Drafts/unscheduled`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/future`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Published/future`)).toBeNull();
    expect(infos.filter(([m]) => m === 'fantasy news: draft auto-published')
      .map(([, c]) => c?.['key']).sort()).toEqual(['ai1', 'due', 'mine']);

    // Idempotent: the next sweep republishes nothing.
    const before = db.snapshot();
    await runLifecycleSweep(db, now);
    expect(db.snapshot()).toBe(before);
  });

  it('a due draft whose Published row already exists never overwrites it: schedule cleared, draft kept', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 })); // games live: no finalize
    const now = new Date(Date.UTC(2026, 5, 24, 12));
    // The live post, pushed yesterday (its display stamps are what a
    // rewrite used to wipe — and the push trigger then sent again).
    const live = {
      Title: 'Team of the Week — GW1', Body: DREAM_BODY,
      At: now.getTime() - 86_400_000, Template: 'dreamteam', Gw: 1,
      Push: DREAM_PUSH, PushedAt: now.getTime() - 86_400_000, PushSent: 3,
    };
    // A duplicate draft under the same key (resurrected / failed delete).
    const duplicate = {
      Title: 'Team of the Week — GW1 (edited)', Body: DREAM_BODY, Gw: 1,
      CreatedAt: 1, Source: 'dreamteam', Template: 'dreamteam',
      Push: DREAM_PUSH, EditedAt: 2,
    };
    db.data.Fantasy.Futsal['15'].News = {
      Published: { gw1dreamteam: live },
      Drafts: {
        gw1dreamteam: { ...duplicate, AutoPublishAt: now.getTime() - 60_000 },
      },
    };
    const logged: Array<[string, Record<string, unknown> | undefined]> = [];
    const log: FantasyLogger = {
      info: (m, c) => { logged.push([m, c]); },
      warn: (m, c) => { logged.push([m, c]); },
    };
    await runLifecycleSweep(db, now, log);

    expect(await db.read(`${F_ROOT}/News/Published/gw1dreamteam`)).toEqual(live);
    // Kept in the owner's queue as a visible duplicate, no longer scheduled.
    expect(await db.read(`${F_ROOT}/News/Drafts/gw1dreamteam`)).toEqual(duplicate);
    expect(logged).toContainEqual([
      'fantasy news: draft already published — schedule cleared',
      { sport: 'Futsal', season: '15', key: 'gw1dreamteam' },
    ]);
    expect(logged.map(([m]) => m)).not.toContain('fantasy news: draft auto-published');

    // The next sweep leaves both alone (no schedule = waits for the owner).
    const before = db.snapshot();
    await runLifecycleSweep(db, now);
    expect(db.snapshot()).toBe(before);
  });
});
